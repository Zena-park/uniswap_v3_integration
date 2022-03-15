const chai = require("chai");
const { solidity } = require("ethereum-waffle");
const { expect, assert } = chai;

const JSBI = require('jsbi');

//chai.use(require("chai-bn")(BN));
chai.use(solidity);
require("chai").should();
const univ3prices = require('@thanpolas/univ3prices');
const utils = require("./utils");

// const { expect } = require("chai");
const { ethers } = require("hardhat");
const Web3EthAbi = require('web3-eth-abi');
const {
  keccak256,
} = require("web3-utils");
const bn = require('bignumber.js');

const {
  deployedUniswapV3Contracts,
  FeeAmount,
  TICK_SPACINGS,
  getMinTick,
  getMaxTick,
  getNegativeOneTick,
  getPositiveOneMaxTick,
  encodePriceSqrt,
  getUniswapV3Pool,
  getBlock,
  mintPosition2,
  getTick,
  // getMaxLiquidityPerTick,
} = require("./uniswap-v3/uniswap-v3-contracts");

// let TOSToken = require('../abis/TOS.json');
// let ERC20TokenA = require('../abis/ERC20A.json');
// let UniswapV3Factory = require('../abis/UniswapV3Factory.json');
let NonfungiblePositionManager = require('../abis/NonfungiblePositionManager.json');
let UniswapV3Pool = require('../abis/UniswapV3Pool.json');
let UniswapV3LiquidityChanger= require('../abis/UniswapV3LiquidityChanger.json');


let UniswapV3LiquidityChangerAddress = "0xa839a0e64b27a34ed293d3d81e1f2f8b463c3514";
/**
DOC/TOS (0.3 %)  0x831a1f01ce17b6123a7d1ea65c26783539747d6d
TOS/WTON (0.3 %) 0x516e1af7303a94f81e91e4ac29e20f4319d4ecaf
 */
let poolAddress = "0x516e1af7303a94f81e91e4ac29e20f4319d4ecaf";
let tokenId = ethers.BigNumber.from("7534");
// let poolAddress = "0x831a1f01ce17b6123a7d1ea65c26783539747d6d";
// let tokenId = ethers.BigNumber.from("13076");



describe("LiquidityChanger", function () {

    let provider;
    let nonfungiblePositionManager, uniswapV3Pool, uniswapV3LiquidityChanger ;

    // rinkeby
    let uniswapInfo={
            poolfactory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            npm: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            swapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
            wethUsdcPool: "0xfbDc20aEFB98a2dD3842023f21D17004eAefbe68",
            wtonWethPool: "0xE032a3aEc591fF1Ca88122928161eA1053a098AC",
            wtonTosPool: "0x516e1af7303a94f81e91e4ac29e20f4319d4ecaf",
            wton: "0x709bef48982Bbfd6F2D4Be24660832665F53406C",
            tos: "0x73a54e5C054aA64C1AE7373C2B5474d8AFEa08bd",
            weth: "0xc778417e063141139fce010982780140aa0cd5ab",
            usdc: "0x4dbcdf9b62e891a7cec5a2568c3f4faf9e8abe2b",
            _fee: ethers.BigNumber.from("3000"),
            NonfungibleTokenPositionDescriptor: "0x91ae842A5Ffd8d12023116943e72A606179294f3"
    }

    before(async function () {
        accounts = await ethers.getSigners();
        [admin1, admin2, user1, user2, minter1, minter2, proxyAdmin, proxyAdmin2 ] = accounts;
        //console.log('admin1',admin1.address);

        provider = ethers.provider;
        // poolInfo.admin = admin1;
        // tokenInfo.admin = admin1;
    });

    it("set UniswapV3Pool", async function () {

        uniswapV3Pool = new ethers.Contract(poolAddress, UniswapV3Pool.abi, provider);

        const code = await ethers.provider.getCode(poolAddress);
        expect(code).to.not.eq('0x');
    });

    it("set UniswapV3LiquidityChanger", async function () {

        // uniswapV3LiquidityChanger = new ethers.Contract(UniswapV3LiquidityChangerAddress, UniswapV3LiquidityChanger.abi, provider);
        let LiquidityChanger = await ethers.getContractFactory("UniswapV3LiquidityChanger");
        let LiquidityChangerDeployed = await LiquidityChanger.deploy();

        let tx = await LiquidityChangerDeployed.deployed();

        uniswapV3LiquidityChanger = new ethers.Contract(LiquidityChangerDeployed.address, UniswapV3LiquidityChanger.abi, provider);
        console.log('uniswapV3LiquidityChanger deployed at ' , uniswapV3LiquidityChanger.address);

        const code = await ethers.provider.getCode(uniswapV3LiquidityChanger.address);
        expect(code).to.not.eq('0x');


    });

    it("set NonfungiblePositionManager", async function () {

        nonfungiblePositionManager = new ethers.Contract(uniswapInfo.npm, NonfungiblePositionManager.abi, provider);

        const code = await ethers.provider.getCode(uniswapInfo.npm);
        expect(code).to.not.eq('0x');
    });

    it("univ3prices", async function () {
        let positions = await nonfungiblePositionManager.positions(tokenId);
        //console.log('positions.liquidity.toString()',positions.liquidity.toString());

        let slot0 = await uniswapV3Pool.slot0();

        //console.log('slot0.sqrtPriceX96.toString()',slot0.sqrtPriceX96.toString());

        let tickSpacing = TICK_SPACINGS[FeeAmount.MEDIUM];

        //console.log('tickSpacing',tickSpacing);

        let tokenDecimals = [27, 18];
        let amount = univ3prices.getAmountsForCurrentLiquidity(
            tokenDecimals,
            positions.liquidity.toString(),
            slot0.sqrtPriceX96.toString(),
            tickSpacing,
            optOpts = {},
        )
        // console.log('amount',amount);
                //console.log('univ3prices',univ3prices.getAmountsForCurrentLiquidity();)
        //const price = univ3prices(tokenDecimals, slot0.sqrtPriceX96.toString()).toAuto();
        const price = univ3prices(tokenDecimals, slot0.sqrtPriceX96.toString()).toSignificant({
            // reverse: true,
            decimalPlaces: 6,
        });
        console.log(price);

        let sqrtRatioAX96 = univ3prices.tickMath.getSqrtRatioAtTick(positions.tickLower);
        let sqrtRatioBX96 = univ3prices.tickMath.getSqrtRatioAtTick(positions.tickUpper);

        const reserves = univ3prices.getAmountsForLiquidityRange(
                slot0.sqrtPriceX96.toString(),
                sqrtRatioAX96,
                sqrtRatioBX96,
                positions.liquidity.toString(),
            );
        console.log('reserves',reserves[0].toString(),reserves[1].toString());

    });

    it("getAmount0", async function () {

        let positions = await nonfungiblePositionManager.positions(tokenId);
        //console.log('positions',positions);

        let amount = await uniswapV3LiquidityChanger.getAmounts(uniswapInfo.npm, poolAddress, tokenId);
        console.log('getAmounts',amount);

    });

    it("getPriceToken0ByOracle", async function () {

        let price = await uniswapV3LiquidityChanger.getPriceToken0(poolAddress);
        console.log('price based token0',price);

    });

    it("getPriceToken1ByOracle", async function () {

        let price = await uniswapV3LiquidityChanger.getPriceToken1(poolAddress);
        console.log('price based token1',price);

    });
});
