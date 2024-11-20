import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/Uniswap/v4-core/src/libraries/FullMath.sol";

contract CFollowAutoPos {

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;

    address internal immutable owner;

    mapping(uint160=>uint24) internal positions;

    mapping(address => bool) public whitelist;

    constructor() payable{
        owner=msg.sender;
        whitelist[msg.sender]=true;
    }

    modifier checkOwner{
        require(owner==msg.sender,"OW");
        _;
    }

    modifier checkWhitelist{
        require(whitelist[msg.sender],"WL");
        _;
    }

    function setWhitelist(address a, bool b)external payable checkOwner{
        require(a!=owner);
        whitelist[a]=b;
    }

    // function checkDataGen(address pool,int24 posSpacing,bool isToken0) external pure returns(bytes memory data){
    //     return abi.encode(pool,posSpacing,isToken0);
    // }

    function checkUpkeep(bytes calldata checkData)external view returns (bool upkeepNeeded, bytes memory performData){
        (address pool,int24 posSpacing,bool isToken0)=abi.decode(checkData,(address,int24,bool));
        uint160 posKey=getPosKey(pool,posSpacing);
        int24 tickLower=getPos(posKey);
        (,int24 tick , , , , , )=IUniswapV3Pool(pool).slot0();
        int24 spacing=IUniswapV3Pool(pool).tickSpacing();
        int24 newTickLower;address token;
        if(isToken0){
            newTickLower=tickLowerBound(tick,spacing)+spacing;
            int24 newTickUpper=newTickLower+posSpacing;
            require(newTickUpper<MAX_TICK,"TU");
            require(newTickLower<tickLower,"NU");
            token=IUniswapV3Pool(pool).token0();
        }else{
            int24 newTickUpper=tickLowerBound(tick,spacing);
            newTickLower=newTickUpper-posSpacing;
            require(newTickLower>MIN_TICK,"TL");
            require(newTickLower>tickLower,"NU");
            token=IUniswapV3Pool(pool).token1();
        }
        upkeepNeeded=true;
        performData=abi.encode(pool,posSpacing,newTickLower,isToken0,token);
    }

    function performUpkeep(bytes calldata performData) external payable checkWhitelist{
        (address pool,int24 posSpacing,int24 newTickLower,bool isToken0,address token)=abi.decode(performData,(address,int24,int24,bool,address));
        int24 newTickUpper=newTickLower+posSpacing;
        uint160 posKey=getPosKey(pool,posSpacing);
        int24 tickLower=getPos(posKey);
        (uint amount0,uint amount1)=_burnPosition(address(this),pool,tickLower,tickLower+posSpacing);
        uint128 liquidity;
        if(isToken0){
            require(amount1==0,"A1");
            liquidity=getLiquidityForAmount0(tickSqrtP(newTickLower), tickSqrtP(newTickUpper), amount0);
        }else{
            require(amount0==0,"A0");
            liquidity=getLiquidityForAmount1(tickSqrtP(newTickLower), tickSqrtP(newTickUpper), amount1);
        }
        (uint _amount0,uint _amount1)=_mintPosition(pool,newTickLower,newTickUpper,liquidity,abi.encode(token));
        require(amount0==_amount0 && amount1==_amount1);
        setPos(posKey,newTickLower);
    }

    function createNewPosition(address pool,int24 posSpacing,uint amount,bool isToken0)external payable checkOwner{
        uint160 posKey=getPosKey(pool,posSpacing);
        require(positions[posKey]==0,"AP");
        (, int24 tick, , , , , )=IUniswapV3Pool(pool).slot0();
        int24 spacing=IUniswapV3Pool(pool).tickSpacing();
        address token;int24 posTickLower;int24 posTickUpper;uint128 liquidity;
        if(isToken0){
            posTickLower=tickLowerBound(tick,spacing)+spacing;
            posTickUpper=posTickLower+posSpacing;
            require(posTickUpper<MAX_TICK,"TU");
            token=IUniswapV3Pool(pool).token0();
            liquidity=getLiquidityForAmount0(tickSqrtP(posTickLower), tickSqrtP(posTickUpper), amount);
        }else{
            posTickUpper=tickLowerBound(tick,spacing);
            posTickLower=posTickUpper-posSpacing;
            require(posTickLower>MIN_TICK,"TL");
            token=IUniswapV3Pool(pool).token1();
            liquidity=getLiquidityForAmount1(tickSqrtP(posTickLower), tickSqrtP(posTickUpper), amount);
        }
        IERC20(token).transferFrom(owner,address(this),amount);
        (uint amount0,uint amount1)=_mintPosition(pool,posTickLower,posTickUpper,liquidity,abi.encode(token));
        require(isToken0?amount0==amount:amount1==amount,"MA");
        setPos(posKey,posTickLower);
    }

    function deletePosition(address pool,int24 posSpacing) external payable checkOwner{
        uint160 posKey=getPosKey(pool,posSpacing);
        int24 posTickLower=getPos(posKey);
        _burnPosition(owner,pool,posTickLower,posTickLower+posSpacing);
        delete positions[posKey];
    }

    function execute(address target, bytes calldata call) external payable checkOwner returns (bool s){
        unchecked{(s,)=target.call(call);}
    }

    function _mintPosition(address pool,int24 tickLower,int24 tickUpper,uint128 liquidity,bytes memory data)internal returns (uint amount0,uint amount1){
        (amount0,amount1)=IUniswapV3Pool(pool).mint(address(this),tickLower,tickUpper,liquidity,data);
    }

    function _burnPosition(address recipient,address pool,int24 tickLower,int24 tickUpper)internal returns (uint amount0,uint amount1){
        (uint128 liquidity,,,,)=IUniswapV3Pool(pool).positions(keccak256(abi.encodePacked(address(this), tickLower, tickUpper)));
        IUniswapV3Pool(pool).burn(tickLower,tickUpper,liquidity);
        (amount0,amount1)=IUniswapV3Pool(pool).collect(recipient,tickLower,tickUpper,type(uint128).max,type(uint128).max);
    }

    function uniswapV3MintCallback(uint amount0,uint amount1, bytes calldata data)external payable{
        address token=abi.decode(data,(address));
        IERC20(token).transfer(msg.sender,amount0>0?amount0:amount1);
    }

    


    //utils

    function getLiquidityForAmount0(uint160 sqrtPLX96,uint160 sqrtPUX96,uint256 amount0) internal pure returns (uint128 liquidity) {
        return uint128(FullMath.mulDiv(amount0 , FullMath.mulDiv(sqrtPLX96, sqrtPUX96, 1<<96) , (sqrtPUX96 - sqrtPLX96)));
    }

    function getLiquidityForAmount1(uint160 sqrtPLX96,uint160 sqrtPUX96,uint256 amount1) internal pure returns (uint128 liquidity) {
        return uint128((amount1 << 96) / (sqrtPUX96 - sqrtPLX96));
    }

    function tickSqrtP(int24 tick) internal pure returns (uint160 sqrtPX96) {
        unchecked {
            uint256 absTick;
            assembly {
                tick := signextend(2, tick)
                let mask := sar(255, tick)
                absTick := xor(mask, add(mask, tick))
            }
            uint256 price;
            assembly {
                price := xor(shl(128, 1), mul(xor(shl(128, 1), 0xfffcb933bd6fad37aa2d162d1a594001), and(absTick, 0x1)))
            }
            if (absTick & 0x2 != 0) price = (price * 0xfff97272373d413259a46990580e213a) >> 128;
            if (absTick & 0x4 != 0) price = (price * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x8 != 0) price = (price * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x10 != 0) price = (price * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x20 != 0) price = (price * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x40 != 0) price = (price * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x80 != 0) price = (price * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x100 != 0) price = (price * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x200 != 0) price = (price * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x400 != 0) price = (price * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x800 != 0) price = (price * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x1000 != 0) price = (price * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x2000 != 0) price = (price * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x4000 != 0) price = (price * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x8000 != 0) price = (price * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x10000 != 0) price = (price * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
            if (absTick & 0x20000 != 0) price = (price * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x40000 != 0) price = (price * 0x2216e584f5fa1ea926041bedfe98) >> 128;
            if (absTick & 0x80000 != 0) price = (price * 0x48a170391f7dc42444e8fa2) >> 128;
            assembly {
                if sgt(tick, 0) { price := div(not(0), price) }
                sqrtPX96 := shr(32, add(price, sub(shl(32, 1), 1)))
            }
        }
    }

    function tickLowerBound(int24 t,int24 s)internal pure returns(int24 tl){
        assembly {tl := mul(sub(sdiv(t, s), and(slt(t, 0), smod(t, s))), s)}
    }

    function getPosKey(address pool,int24 posSpacing)internal pure returns(uint160){
        return uint160(pool)^uint24(posSpacing);
    }

    function getPos(uint160 posKey)internal view returns(int24){
        uint24 temp = positions[posKey];
        require(temp!=0,"NP");
        return int24(temp&0x7fffff);
    }

    function setPos(uint160 posKey,int24 tick)internal{
        positions[posKey]=uint24(tick)|0x800000;
    }
}
