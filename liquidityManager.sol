import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CUniswapV3LiquidityManager {

    address internal immutable owner;

    mapping(address => bool) internal whitelist;

    bool internal lock;
    
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

    modifier unlock{
        lock=true;
        _;
        lock=false;
    }

    modifier checkLock{
        require(lock,"LO");
        _;
    }

    function setWhitelist(address a, bool b)external payable checkOwner{
        require(a!=owner);
        whitelist[a]=b;
    }

    function mintPosition(address pool,int24 tickLower,int24 tickUpper,uint liquidity)external payable checkWhitelist unlock{
        IUniswapV3Pool(pool).mint(address(this),tickLower,tickUpper,uint128(liquidity),"");
    }

    function burnPosition(address pool,int24 tickLower,int24 tickUpper)external payable checkWhitelist{
        (uint128 liquidity,,,,)=IUniswapV3Pool(pool).positions(keccak256(abi.encodePacked(address(this), tickLower, tickUpper)));
        IUniswapV3Pool(pool).burn(tickLower,tickUpper,liquidity);
        (uint amount0,uint amount1)=IUniswapV3Pool(pool).collect(address(this),tickLower,tickUpper,type(uint128).max,type(uint128).max);
        if(amount0>0){
            address token0=IUniswapV3Pool(pool).token0();
            IERC20(token0).transfer(owner,amount0);
        }
        if(amount1>0){
            address token1=IUniswapV3Pool(pool).token1();
            IERC20(token1).transfer(owner,amount1);
        }
    }

    function uniswapV3MintCallback(uint amount0,uint amount1, bytes calldata)external payable checkLock{
        if(amount0>0){
            address token0=IUniswapV3Pool(msg.sender).token0();
            IERC20(token0).transferFrom(owner,msg.sender,amount0);
        }
        if(amount1>0){
            address token1=IUniswapV3Pool(msg.sender).token1();
            IERC20(token1).transferFrom(owner,msg.sender,amount1);
        }
    }

    // function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160 sqrtPX96) {
    //     unchecked {
    //         uint256 absTick;
    //         assembly {
    //             tick := signextend(2, tick)
    //             let mask := sar(255, tick)
    //             absTick := xor(mask, add(mask, tick))
    //         }
    //         uint256 price;
    //         assembly {
    //             price := xor(shl(128, 1), mul(xor(shl(128, 1), 0xfffcb933bd6fad37aa2d162d1a594001), and(absTick, 0x1)))
    //         }
    //         if (absTick & 0x2 != 0) price = (price * 0xfff97272373d413259a46990580e213a) >> 128;
    //         if (absTick & 0x4 != 0) price = (price * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
    //         if (absTick & 0x8 != 0) price = (price * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
    //         if (absTick & 0x10 != 0) price = (price * 0xffcb9843d60f6159c9db58835c926644) >> 128;
    //         if (absTick & 0x20 != 0) price = (price * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
    //         if (absTick & 0x40 != 0) price = (price * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
    //         if (absTick & 0x80 != 0) price = (price * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
    //         if (absTick & 0x100 != 0) price = (price * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
    //         if (absTick & 0x200 != 0) price = (price * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
    //         if (absTick & 0x400 != 0) price = (price * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
    //         if (absTick & 0x800 != 0) price = (price * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
    //         if (absTick & 0x1000 != 0) price = (price * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
    //         if (absTick & 0x2000 != 0) price = (price * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
    //         if (absTick & 0x4000 != 0) price = (price * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
    //         if (absTick & 0x8000 != 0) price = (price * 0x31be135f97d08fd981231505542fcfa6) >> 128;
    //         if (absTick & 0x10000 != 0) price = (price * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
    //         if (absTick & 0x20000 != 0) price = (price * 0x5d6af8dedb81196699c329225ee604) >> 128;
    //         if (absTick & 0x40000 != 0) price = (price * 0x2216e584f5fa1ea926041bedfe98) >> 128;
    //         if (absTick & 0x80000 != 0) price = (price * 0x48a170391f7dc42444e8fa2) >> 128;
    //         assembly {
    //             if sgt(tick, 0) { price := div(not(0), price) }
    //             sqrtPX96 := shr(32, add(price, sub(shl(32, 1), 1)))
    //         }
    //     }
    // }

    // function getLiquidityForAmounts(uint160 sqrtPX96,uint160 sqrtPLX96,uint160 sqrtPUX96,uint256 amount0,uint256 amount1) internal pure returns (uint128 liquidity) {
    //     if (sqrtPX96 <= sqrtPLX96) {
    //         liquidity = getLiquidityForAmount0(sqrtPLX96, sqrtPUX96, amount0);
    //     } else if (sqrtPX96 < sqrtPUX96) {
    //         uint128 liquidity0 = getLiquidityForAmount0(sqrtPX96, sqrtPUX96, amount0);
    //         uint128 liquidity1 = getLiquidityForAmount1(sqrtPLX96, sqrtPX96, amount1);
    //         liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
    //     } else {
    //         liquidity = getLiquidityForAmount1(sqrtPLX96, sqrtPUX96, amount1);
    //     }
    // }

    // function getLiquidityForAmount0(uint160 sqrtPLX96,uint160 sqrtPUX96,uint256 amount0) internal pure returns (uint128 liquidity) {
    //     return uint128((amount0 * (sqrtPLX96>>48) * (sqrtPUX96>>48)) / (sqrtPUX96 - sqrtPLX96));
    // }

    // function getLiquidityForAmount1(uint160 sqrtPLX96,uint160 sqrtPUX96,uint256 amount1) internal pure returns (uint128 liquidity) {
    //     return uint128((amount1 << 96) / (sqrtPUX96 - sqrtPLX96));
    // }
}
