// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.4;

import "../libraries/FullMath.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityAmounts.sol";
import "../libraries/OracleLibrary.sol";
import "../libraries/FixedPoint128.sol";
import "../libraries/FixedPoint96.sol";
import "../libraries/PositionKey.sol";
import "../libraries/SafeMath512.sol";

import "hardhat/console.sol";

interface IIUniswapV3Pool {

    function token0() external view returns(address);
    function token1() external view returns(address);

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function positions(bytes32 key)
        external
        view
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);


}

interface IINonfungiblePositionManager {

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

interface IIUniswapV3Factory {

     function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}

contract UniswapV3LiquidityChanger {

    function getAmounts(address npm, address poolAddress, uint256 tokenId)
        public view returns (uint256 amount0, uint256 amount1) {

        (
            uint160 sqrtPriceX96, , , , , ,
        ) = IIUniswapV3Pool(poolAddress).slot0();

        ( , , , , ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity, , , ,
        ) = IINonfungiblePositionManager(npm).positions(tokenId);

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
        console.log('amount0 %s ', amount0);
        console.log('amount1 %s ', amount1);
    }

    function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) public view returns(uint256 priceX96) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function getSqrtTwapX96(address poolAddress, uint32 twapInterval) public view returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = IIUniswapV3Pool(poolAddress).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) = IIUniswapV3Pool(poolAddress).observe(secondsAgos);

            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / int56( int32(twapInterval)))
            );
        }
    }

    function getTotalAmountBasedToken0(address npm, address poolAddress, uint256 tokenId) public view returns (uint256 totalAmount0) {

        (uint160 sqrtPriceX96, int24 tick, , , , ,) = IIUniswapV3Pool(poolAddress).slot0();

        ( , ,address token0, address token1, ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity, , , ,
        ) = IINonfungiblePositionManager(npm).positions(tokenId);

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);

        // amount1 -> amount0
        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(tick, uint128(amount1), token1, token0);

        totalAmount0 = amount0 + quoteAmount;
    }

    function getTotalAmountBasedToken1(address npm, address poolAddress, uint256 tokenId) public view returns (uint256 totalAmount1) {

        (uint160 sqrtPriceX96, int24 tick, , , , ,) = IIUniswapV3Pool(poolAddress).slot0();

        ( , ,address token0, address token1, ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity, , , ,
        ) = IINonfungiblePositionManager(npm).positions(tokenId);

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);

        // amount1 -> amount0
        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(tick, uint128(amount0), token0, token1);

        totalAmount1 = amount1 + quoteAmount;
    }

    function getCollectableAmount(address npm, address poolAddress, uint256 tokenId) public view
        returns (uint128 token0CollectableAmount, uint128 token1CollectableAmount) {

        ( , , ,  , ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 tokenIdFeeGrowthInside0LastX128,
            uint256 tokenIdFeeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = IINonfungiblePositionManager(npm).positions(tokenId);

        bytes32 positionKey = PositionKey.compute(npm, tickLower, tickUpper);

        // this is now updated to the current transaction
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = IIUniswapV3Pool(poolAddress).positions(positionKey);

        token0CollectableAmount = tokensOwed0 + uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - tokenIdFeeGrowthInside0LastX128,
                    liquidity,
                    FixedPoint128.Q128
                )
            );

        token1CollectableAmount = tokensOwed1 + uint128(
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - tokenIdFeeGrowthInside1LastX128,
                liquidity,
                FixedPoint128.Q128
            )
        );
    }

    function getCollectableTotalAmountBasedToken0(address npm, address poolAddress, uint256 tokenId) public view returns(uint256 amount0)
    {
        (, int24 tick, , , , ,) = IIUniswapV3Pool(poolAddress).slot0();
        ( , ,address token0, address token1, , , , , , , , ) = IINonfungiblePositionManager(npm).positions(tokenId);

        (uint128 token0CollectableAmount, uint128 token1CollectableAmount) = getCollectableAmount(npm, poolAddress, tokenId);
         uint256 quoteAmount = OracleLibrary.getQuoteAtTick(tick, uint128(token1CollectableAmount), token1, token0);

        amount0 = uint256(token0CollectableAmount) + quoteAmount;
    }

    function getCollectableTotalAmountBasedToken1(address npm, address poolAddress, uint256 tokenId) public view returns(uint256 amount1)
    {
        (, int24 tick, , , , ,) = IIUniswapV3Pool(poolAddress).slot0();
        ( , ,address token0, address token1, , , , , , , , ) = IINonfungiblePositionManager(npm).positions(tokenId);

        (uint128 token0CollectableAmount, uint128 token1CollectableAmount) = getCollectableAmount(npm, poolAddress, tokenId);
         uint256 quoteAmount = OracleLibrary.getQuoteAtTick(tick, uint128(token0CollectableAmount), token0, token1);

        amount1 = uint256(token1CollectableAmount) + quoteAmount;
    }

    function estimateAmountOut(
        address factoryAddress,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint128 amountIn,
        uint32 secondsAgos
    ) external view returns (uint256 amountOut) {

        address pool = IIUniswapV3Factory(factoryAddress).getPool(
            tokenIn, tokenOut, fee
        );
        require(pool != address(0), "pool doesn't exist") ;

        address token0 = IIUniswapV3Pool(pool).token0();
        address token1 = IIUniswapV3Pool(pool).token1();

        require(token0 == tokenIn || token0 == tokenOut, "there is no matching token0");
        require(token1 == tokenIn || token1 == tokenOut, "there is no matching token1");

        int24 tick = OracleLibrary.consult(pool, secondsAgos);
        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }
}