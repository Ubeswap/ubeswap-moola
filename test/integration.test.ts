import { deployMockContract } from "@ethereum-waffle/mock-contract";
import UbeswapFactoryArtifact from "@ubeswap/core/build/metadata/UniswapV2Factory/artifact.json";
import UbeswapRouterArtifact from "@ubeswap/core/build/metadata/UniswapV2Router02/artifact.json";
import { doTx } from "@ubeswap/hardhat-celo";
import { getCurrentTime } from "@ubeswap/hardhat-celo/lib/testing";
import { deployContract } from "@ubeswap/solidity-create2-deployer";
import { expect } from "chai";
import { Wallet } from "ethers";
import { formatEther, parseEther, solidityKeccak256 } from "ethers/lib/utils";
import hre from "hardhat";
import IRegistryABI from "../build/abi/IRegistry.json";
import {
  UniswapV2Factory,
  UniswapV2Factory__factory,
  UniswapV2Router02,
  UniswapV2Router02__factory,
} from "../build/test-fixtures/";
import {
  IERC20,
  MockAToken,
  MockAToken__factory,
  MockERC20,
  MockERC20__factory,
  MockGold,
  MockGold__factory,
  MockLendingPool,
  MockLendingPoolCore,
  MockLendingPoolCore__factory,
  MockLendingPool__factory,
} from "../build/types";
import {
  UbeswapMoolaRouter,
  UbeswapMoolaRouter__factory,
} from "../build/types/";

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

describe("UbeswapMoolaRouter", () => {
  let wallet: Wallet;
  let other0: Wallet;
  let other1: Wallet;
  let chainId: number;

  let factory: UniswapV2Factory;
  let router: UniswapV2Router02;
  let pool: MockLendingPool;
  let core: MockLendingPoolCore;

  let cUSD: MockERC20;
  let CELO: MockGold;
  let mcUSD: MockAToken;
  let mCELO: MockAToken;

  let rand1: MockERC20;
  let rand2: MockERC20;
  let rand3: MockERC20;

  let moolaRouter: UbeswapMoolaRouter;

  let CUSD_CELO_PATH_TOKENS: readonly IERC20[];
  let CUSD_CELO_PATH: readonly string[];

  before(async () => {
    const wallets = await hre.waffle.provider.getWallets();
    chainId = await (await hre.waffle.provider.getNetwork()).chainId;

    wallet = wallets[0]!;
    other0 = wallets[1]!;
    other1 = wallets[2]!;

    factory = UniswapV2Factory__factory.connect(
      (
        await deployContract({
          salt: "Tayo'y magsayawan",
          signer: wallet,
          contractBytecode: "0x" + UbeswapFactoryArtifact.bin,
          constructorTypes: ["address"],
          constructorArgs: ["0xDF5B9dE8Ba90223e47c56Fb58Cfb80f79B95c967"],
        })
      ).address,
      wallet
    );
    router = UniswapV2Router02__factory.connect(
      (
        await deployContract({
          salt: "Tayo'y magsayawan",
          signer: wallet,
          contractBytecode: "0x" + UbeswapRouterArtifact.bin,
          constructorTypes: ["address"],
          constructorArgs: [factory.address],
        })
      ).address,
      wallet
    );
  });

  beforeEach("init moola router", async () => {
    cUSD = await new MockERC20__factory(wallet).deploy("Celo Dollar", "cUSD");
    CELO = await new MockGold__factory(wallet).deploy();

    // send gold
    await CELO.connect(other0).wrap({ value: parseEther("100") });
    await CELO.connect(other0).transfer(wallet.address, parseEther("100"));

    mcUSD = await new MockAToken__factory(wallet).deploy(
      cUSD.address,
      "Moola Dollar",
      "mcUSD"
    );
    mCELO = await new MockAToken__factory(wallet).deploy(
      CELO.address,
      "Moola Celo",
      "mCELO"
    );

    core = await new MockLendingPoolCore__factory(wallet).deploy(
      CELO.address,
      cUSD.address,
      mCELO.address,
      mcUSD.address
    );
    pool = await new MockLendingPool__factory(wallet).deploy(core.address);

    rand1 = await new MockERC20__factory(wallet).deploy("Randy One", "RAN1");
    rand2 = await new MockERC20__factory(wallet).deploy("Randy Deuce", "RAN2");
    rand3 = await new MockERC20__factory(wallet).deploy("Randy Tre", "RAN3");

    const registry = await deployMockContract(wallet, IRegistryABI);
    await registry.mock.getAddressForOrDie
      ?.withArgs(solidityKeccak256(["string"], ["GoldToken"]))
      .returns(CELO.address);

    moolaRouter = await new UbeswapMoolaRouter__factory(wallet).deploy(
      router.address,
      registry.address
    );
    await moolaRouter.initialize(pool.address, core.address);

    CUSD_CELO_PATH_TOKENS = [cUSD, rand1, rand2, rand3, CELO];
    CUSD_CELO_PATH = CUSD_CELO_PATH_TOKENS.map((tok) => tok.address);
    for (let i = 0; i < CUSD_CELO_PATH.length; i++) {
      await CUSD_CELO_PATH_TOKENS[i]?.approve(
        router.address,
        parseEther("100000000")
      );
    }

    const now = await getCurrentTime();

    for (let i = 0; i < CUSD_CELO_PATH.length - 1; i++) {
      await router.addLiquidity(
        CUSD_CELO_PATH[i]!,
        CUSD_CELO_PATH[i + 1]!,
        parseEther("100"),
        parseEther("100"),
        parseEther("100"),
        parseEther("100"),
        wallet.address,
        now + 1800000,
        { gasLimit: 7000000 }
      );
    }

    await cUSD.approve(moolaRouter.address, parseEther("10000"));
    await moolaRouter.deposit(cUSD.address, parseEther("10000"));
    await CELO.wrap({ value: parseEther("1000") });
    await CELO.approve(moolaRouter.address, parseEther("1000"));
    await moolaRouter.deposit(CELO.address, parseEther("1000"));
    for (const [tokenA, tokenB] of [
      [mcUSD, CUSD_CELO_PATH_TOKENS[1]],
      [mCELO, CUSD_CELO_PATH_TOKENS.slice().reverse()[1]],
    ]) {
      await tokenA?.approve(router.address, parseEther("100"));
      await tokenB?.approve(router.address, parseEther("100"));
      await router.addLiquidity(
        tokenA?.address!,
        tokenB?.address!,
        parseEther("100"),
        parseEther("100"),
        parseEther("100"),
        parseEther("100"),
        wallet.address,
        now + 1800000,
        { gasLimit: 7000000 }
      );
    }
  });

  describe("#swap", () => {
    it("works deposit in, withdraw out", async () => {
      await cUSD.approve(core.address, parseEther("1"));
      await pool.deposit(cUSD.address, parseEther("1"), 0);
      await mcUSD.transfer(other1.address, parseEther("1"));

      // initial balance: 1 mcUSD, 0 mCELO
      expect(await mcUSD.balanceOf(other1.address)).to.equal(parseEther("1"));
      await mcUSD.connect(other1).approve(moolaRouter.address, parseEther("1"));
      expect(await mCELO.balanceOf(other1.address)).to.equal(0);

      // path is empty before
      for (const token of CUSD_CELO_PATH_TOKENS) {
        expect(await token.balanceOf(moolaRouter.address)).to.equal(0);
        expect(await token.balanceOf(other1.address)).to.equal(0);
      }

      const estimate = await router.getAmountsOut(
        parseEther("1"),
        CUSD_CELO_PATH.slice()
      );

      // router should be empty
      expect(await mcUSD.balanceOf(router.address)).to.equal(0);
      expect(await mCELO.balanceOf(router.address)).to.equal(0);

      await moolaRouter
        .connect(other1)
        .swapExactTokensForTokens(
          parseEther("1"),
          parseEther("0.1"),
          [mcUSD.address, ...CUSD_CELO_PATH, mCELO.address],
          other1.address,
          Math.floor(new Date().getTime() / 1000 + 1800)
        );

      // path is empty afterwards
      for (const token of CUSD_CELO_PATH_TOKENS) {
        expect(await token.balanceOf(moolaRouter.address)).to.equal(0);
        expect(await token.balanceOf(other1.address)).to.equal(0);
      }

      // end balance: 0 mcUSD, 0.?? mCELO
      expect(await mcUSD.balanceOf(other1.address)).to.equal(0);
      expect(await mCELO.balanceOf(other1.address)).to.equal(
        estimate[estimate.length - 1]
      );

      // router should still be empty
      expect(await mcUSD.balanceOf(router.address)).to.equal(0);
      expect(await mCELO.balanceOf(router.address)).to.equal(0);
    });

    it("works deposit in, normal out", async () => {
      await cUSD.approve(core.address, parseEther("1"));
      await pool.deposit(cUSD.address, parseEther("1"), 0);
      await mcUSD.transfer(other1.address, parseEther("1"));

      // initial balance: 1 mcUSD, 0 CELO
      expect(await mcUSD.balanceOf(other1.address)).to.equal(parseEther("1"));
      await mcUSD.connect(other1).approve(moolaRouter.address, parseEther("1"));
      expect(await CELO.balanceOf(router.address)).to.equal(0);

      // path is empty before
      for (const token of CUSD_CELO_PATH_TOKENS) {
        expect(await token.balanceOf(moolaRouter.address)).to.equal(0);
        expect(await token.balanceOf(other1.address)).to.equal(0);
      }

      const estimate = await router.getAmountsOut(
        parseEther("1"),
        CUSD_CELO_PATH.slice()
      );

      // router should be empty
      expect(await mcUSD.balanceOf(router.address)).to.equal(0);
      expect(await CELO.balanceOf(router.address)).to.equal(0);

      await moolaRouter
        .connect(other1)
        .swapExactTokensForTokens(
          parseEther("1"),
          parseEther("0.1"),
          [mcUSD.address, ...CUSD_CELO_PATH],
          other1.address,
          Math.floor(new Date().getTime() / 1000 + 1800)
        );

      // path is empty afterwards
      for (const token of CUSD_CELO_PATH_TOKENS.slice(
        0,
        CUSD_CELO_PATH_TOKENS.length - 1
      )) {
        expect(await token.balanceOf(moolaRouter.address)).to.equal(0);
        expect(await token.balanceOf(other1.address)).to.equal(0);
      }

      // end balance: 0 mcUSD, 0.?? mCELO
      expect(await mcUSD.balanceOf(other1.address)).to.equal(0);
      expect(await CELO.balanceOf(other1.address)).to.equal(
        estimate[estimate.length - 1]
      );

      // router should still be empty
      expect(await mcUSD.balanceOf(router.address)).to.equal(0);
      expect(await CELO.balanceOf(router.address)).to.equal(0);
    });
  });
});
