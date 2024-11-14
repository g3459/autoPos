import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract CFollowAutoPos {

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;

    address immutable liquidityManager;

    mapping(uint160=>int24) internal positions;

    constructor(address _liquidityManager) payable{
        liquidityManager = _liquidityManager;
    }

    function checkUpkeep(bytes calldata checkData)external view returns (bool upkeepNeeded, bytes memory performData){
        (address pool,uint posSpacing,int mode)=abi.decode(checkData,(address,uint,int));
        int24 tickLower=positions[uint160(pool)+uint160(posSpacing)];
        (,int24 tick , , , , , )=IUniswapV3Pool(pool).slot0();
        if(mode>=0 && tick>=tickLower+int(posSpacing)){
            upkeepNeeded=true;
            int spacing=IUniswapV3Pool(pool).tickSpacing();
            int newTickLower=tickLowerBound(tick,uint(spacing))-int(posSpacing);
            require(newTickLower>MIN_TICK);
            // uint liquidity = getLiquidityForAmount1(sqrtPX96,getSqrtPriceAtTick(newTickLower),getSqrtPriceAtTick(newTickUpper),amount);
            performData=abi.encode(pool,posSpacing,newTickLower);
        }else if(mode<=0 && tick<tickLower){
            upkeepNeeded=true;
            int spacing=IUniswapV3Pool(pool).tickSpacing();
            int newTickLower=tickLowerBound(tick,uint(spacing))+spacing;
            require(newTickLower+int(posSpacing)<MAX_TICK);
            // uint liquidity = getLiquidityForAmount0(sqrtPX96,getSqrtPriceAtTick(newTickLower),getSqrtPriceAtTick(newTickUpper),amount);
            performData=abi.encode(pool,posSpacing,newTickLower);
        }
    }

    function performUpkeep(bytes calldata performData) external {
        (address pool,uint posSpacing,int newTickLower)=abi.decode(performData,(address,uint,int));

        
    }

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

    function tickLowerBound(int t,uint s)internal pure returns(int tl){
        assembly {tl := mul(sub(sdiv(t, s), and(slt(t, 0), smod(t, s))), s)}
    }

}
