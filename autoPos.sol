import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CFollowAutoPos {

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;

    address internal immutable owner;

    mapping(uint160=>int24) internal positions;

    mapping(address => bool) internal whitelist;

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

    function checkDataa(address pool,int24 posSpacing,bool isToken0) external pure returns(bytes memory data){
        return abi.encode(pool,posSpacing,isToken0);
    }

    function checkUpkeep(bytes calldata checkData)external view returns (bool upkeepNeeded, bytes memory performData){
        (address pool,int24 posSpacing,bool isToken0)=abi.decode(checkData,(address,int24,bool));
        int24 tickLower=positions[uint160(pool)+uint24(posSpacing)];
        (uint128 liquidity,,,,)=IUniswapV3Pool(pool).positions(keccak256(abi.encodePacked(address(this), tickLower, tickLower+posSpacing)));
        require(liquidity>0);
        (,int24 tick , , , , , )=IUniswapV3Pool(pool).slot0();
        int24 spacing=IUniswapV3Pool(pool).tickSpacing();
        int24 newTickLower;address token;
        if(isToken0){
            newTickLower=tickLowerBound(tick,spacing)+spacing;
            require(newTickLower+posSpacing<MAX_TICK);
            token=IUniswapV3Pool(msg.sender).token0();
        }else{
            newTickLower=tickLowerBound(tick,spacing)-posSpacing;
            require(newTickLower>MIN_TICK);
            token=IUniswapV3Pool(msg.sender).token1();
        }
        require(newTickLower!=tickLower);
        upkeepNeeded=true;
        performData=abi.encode(pool,posSpacing,newTickLower,isToken0,token);
    }

    function performUpkeep(bytes calldata performData) external payable checkWhitelist{
        (address pool,int24 posSpacing,int24 newTickLower,bool isToken0,address token)=abi.decode(performData,(address,int24,int24,bool,address));
        uint160 posKey=uint160(pool)+uint24(posSpacing);
        int24 tickLower=positions[posKey];
        (uint amount0,uint amount1)=_burnPosition(address(this),pool,tickLower,tickLower+posSpacing);
        uint amount;
        if(isToken0){
            amount=amount0;
            require(amount1==0);
        }else{
            amount=amount1;
            require(amount0==0);
        }
        _mintPosition(pool,newTickLower,newTickLower+posSpacing,amount,isToken0,abi.encode(token));
        positions[posKey]=newTickLower;
    }

    function createNewPosition(address pool,int24 posSpacing,uint amount,bool isToken0)external payable checkOwner{
        (, int24 tick, , , , , )=IUniswapV3Pool(pool).slot0();
        int24 spacing=IUniswapV3Pool(pool).tickSpacing();
        int24 posTickLower;int24 posTickUpper;address token;
        if(isToken0){
            posTickLower=tickLowerBound(tick,spacing)+spacing;
            posTickUpper=posTickLower+posSpacing;
            require(posTickUpper<MAX_TICK);
            token=IUniswapV3Pool(pool).token0();
        }else{
            posTickUpper=tickLowerBound(tick,spacing);
            posTickLower=posTickUpper-posSpacing;
            require(posTickLower>MIN_TICK);
            token=IUniswapV3Pool(pool).token1();
        }
        IERC20(token).transferFrom(owner,address(this),amount);
        _mintPosition(pool,posTickLower,posTickUpper,amount,isToken0,abi.encode(token));
        positions[uint160(pool)+uint24(posSpacing)]=posTickLower;
    }

    function deletePosition(address pool,int24 posSpacing) external payable checkOwner{
        uint160 posKey=uint160(pool)+uint24(posSpacing);
        int24 posTickLower=positions[posKey];
        _burnPosition(owner,pool,posTickLower,posTickLower+posSpacing);
        delete positions[posKey];
    }

    function _mintPosition(address pool,int24 tickLower,int24 tickUpper,uint amount,bool isToken0,bytes memory data)internal {
        uint _amount;
        if(isToken0){
            uint liquidity = getLiquidityForAmount0(getSqrtPriceAtTick(tickLower), getSqrtPriceAtTick(tickUpper), amount);
            (_amount,)=IUniswapV3Pool(pool).mint(address(this),tickLower,tickUpper,uint128(liquidity),data);
        }else{
            uint liquidity = getLiquidityForAmount1(getSqrtPriceAtTick(tickLower), getSqrtPriceAtTick(tickUpper), amount);
            (,_amount)=IUniswapV3Pool(pool).mint(address(this),tickLower,tickUpper,uint128(liquidity),data);
        }
        require(_amount==amount);
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
        return uint128((amount0 * (sqrtPLX96>>48) * (sqrtPUX96>>48)) / (sqrtPUX96 - sqrtPLX96));
    }

    function getLiquidityForAmount1(uint160 sqrtPLX96,uint160 sqrtPUX96,uint256 amount1) internal pure returns (uint128 liquidity) {
        return uint128((amount1 << 96) / (sqrtPUX96 - sqrtPLX96));
    }

    function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160 sqrtPX96) {
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

}
