import { deployMockContract } from "@ethereum-waffle/mock-contract";
import { expect } from "chai";
import { MockContract } from "ethereum-waffle";
import { BigNumber, Wallet } from "ethers";
import { getAddress } from "ethers/lib/utils";
import hre from "hardhat";
import IATokenABI from "../build/abi/IAToken.json";
import IERC20ABI from "../build/abi/IERC20.json";
import ILendingPoolABI from "../build/abi/ILendingPool.json";
import ILendingPoolCoreABI from "../build/abi/ILendingPoolCore.json";
import IUbeswapRouterABI from "../build/abi/IUbeswapRouter.json";
import {
  MockGold,
  MockGold__factory,
  UbeswapMoolaRouter,
  UbeswapMoolaRouter__factory,
} from "../build/types/";
import { MOCK_GOLD_ADDRESS } from "./setup.test";

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

describe("UbeswapMoolaRouter", () => {
  const RANDO_PATH = [
    "0xc0ffee254729296a45a3885639AC7E10F9d54979",
    "0xc0ffee254729296a45a3885639AC7E10F9d5a979",
    "0xc0ffee254729296a45a3885a39AC7E10F9d5b979",
    "0xc0ffeea54729296a45a3885639AC7E10F9d5c979",
    "0xc0ffee25472929aa45a3885639AC7E10F9d5c979",
  ].map((a) => getAddress(a.toLowerCase()));

  const RANDO_AMOUNTS = Array(RANDO_PATH.length - 1).fill(999999);

  let wallet: Wallet;
  let other0: Wallet;
  let other1: Wallet;
  let chainId: number;

  let router: MockContract;
  let pool: MockContract;
  let core: MockContract;
  let cUSD: MockContract;
  let CELO: MockGold;
  let mcUSD: MockContract;
  let mCELO: MockContract;

  let moolaRouter: UbeswapMoolaRouter;

  let CUSD_CELO_PATH: readonly string[];
  let CUSD_CELO_AMOUNTS: readonly number[];

  before(async () => {
    const wallets = await hre.waffle.provider.getWallets();
    chainId = await (await hre.waffle.provider.getNetwork()).chainId;

    wallet = wallets[0]!;
    other0 = wallets[1]!;
    other1 = wallets[2]!;
  });

  before("init moola router", async () => {
    router = await deployMockContract(wallet, IUbeswapRouterABI);
    pool = await deployMockContract(wallet, ILendingPoolABI);
    core = await deployMockContract(wallet, ILendingPoolCoreABI);
    CELO = MockGold__factory.connect(MOCK_GOLD_ADDRESS, wallet);
    cUSD = await deployMockContract(wallet, IERC20ABI);
    mcUSD = await deployMockContract(wallet, IATokenABI);
    mCELO = await deployMockContract(wallet, IATokenABI);

    await core.mock.getReserveATokenAddress
      ?.withArgs(cUSD.address)
      .returns(mcUSD.address);
    await core.mock.getReserveATokenAddress
      ?.withArgs(mcUSD.address)
      .returns(ZERO_ADDR);
    await core.mock.getReserveATokenAddress
      ?.withArgs("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE")
      .returns(mCELO.address);
    await core.mock.getReserveATokenAddress
      ?.withArgs(mCELO.address)
      .returns(ZERO_ADDR);
    await core.mock.getReserveATokenAddress?.returns(ZERO_ADDR);

    moolaRouter = await new UbeswapMoolaRouter__factory(wallet).deploy(
      router.address,
      router.address // this doesn't matter for our testing
    );
    await moolaRouter.initialize(pool.address, core.address);

    CUSD_CELO_PATH = [cUSD.address, ...RANDO_PATH, getAddress(CELO.address)];
    CUSD_CELO_AMOUNTS = [1000000, ...RANDO_AMOUNTS, 900000];
    await router.mock.getAmountsIn
      ?.withArgs(1000000, CUSD_CELO_PATH)
      .returns(CUSD_CELO_AMOUNTS);
  });

  describe("#computeSwap", () => {
    it("works with both in and out", async () => {
      const {
        reserveIn,
        depositIn,
        reserveOut,
        depositOut,
        nextPath,
      } = await moolaRouter.computeSwap([
        mcUSD.address,
        ...CUSD_CELO_PATH,
        mCELO.address,
      ]);

      expect(reserveIn).to.equal(cUSD.address);
      expect(depositIn).to.equal(false);
      expect(reserveOut).to.equal(getAddress(CELO.address));
      expect(depositOut).to.equal(true);
      expect(nextPath).to.eql(CUSD_CELO_PATH);
    });

    it("works with neither in nor out", async () => {
      const {
        reserveIn,
        depositIn,
        reserveOut,
        depositOut,
        nextPath,
      } = await moolaRouter.computeSwap(RANDO_PATH);

      expect(reserveIn).to.equal(ZERO_ADDR);
      expect(depositIn).to.equal(false);
      expect(reserveOut).to.equal(ZERO_ADDR);
      expect(depositOut).to.equal(false);
      expect(nextPath).to.eql(RANDO_PATH);
    });

    it("works with in no out", async () => {
      const {
        reserveIn,
        depositIn,
        reserveOut,
        depositOut,
        nextPath,
      } = await moolaRouter.computeSwap([mcUSD.address, ...CUSD_CELO_PATH]);
      expect(reserveIn).to.equal(cUSD.address);
      expect(depositIn).to.equal(false);
      expect(reserveOut).to.equal(ZERO_ADDR);
      expect(depositOut).to.equal(false);
      expect(nextPath).to.eql(CUSD_CELO_PATH);
    });

    it("works with no in, but out", async () => {
      const {
        reserveIn,
        depositIn,
        reserveOut,
        depositOut,
        nextPath,
      } = await moolaRouter.computeSwap([...CUSD_CELO_PATH, mCELO.address]);
      expect(reserveIn).to.equal(ZERO_ADDR);
      expect(depositIn).to.equal(false);
      expect(reserveOut).to.equal(getAddress(CELO.address));
      expect(depositOut).to.equal(true);
      expect(nextPath).to.eql(CUSD_CELO_PATH);
    });
  });

  describe("#getAmountsOut", () => {
    it("works in and out", async () => {
      await router.mock.getAmountsOut
        ?.withArgs(1000000, [cUSD.address, ...RANDO_PATH, CELO.address])
        .returns([1000000, ...RANDO_AMOUNTS, 900000]);

      const path = [
        mcUSD.address,
        cUSD.address,
        ...RANDO_PATH,
        CELO.address,
        mCELO.address,
      ];
      const amounts = await moolaRouter.getAmountsOut(1000000, path);

      expect(amounts.length).to.equal(path.length - 1);

      [1000000, ...[1000000, ...RANDO_AMOUNTS, 900000], 900000]
        .map((v) => BigNumber.from(v))
        .forEach((num, i) => {
          expect(amounts[i]).to.equal(num);
        });
    });

    it("works no out", async () => {
      await router.mock.getAmountsOut
        ?.withArgs(1000000, [cUSD.address, ...RANDO_PATH, CELO.address])
        .returns([1000000, ...RANDO_AMOUNTS, 900000]);

      const path = [mcUSD.address, cUSD.address, ...RANDO_PATH, CELO.address];
      const amounts = await moolaRouter.getAmountsOut(1000000, path);

      expect(amounts.length).to.equal(path.length - 1);

      [1000000, ...[1000000, ...RANDO_AMOUNTS, 900000]]
        .map((v) => BigNumber.from(v))
        .forEach((num, i) => {
          expect(amounts[i]).to.equal(num);
        });
    });

    it("works no in", async () => {
      await router.mock.getAmountsOut
        ?.withArgs(1000000, [cUSD.address, ...RANDO_PATH, CELO.address])
        .returns([1000000, ...RANDO_AMOUNTS, 900000]);

      const path = [cUSD.address, ...RANDO_PATH, CELO.address, mCELO.address];
      const amounts = await moolaRouter.getAmountsOut(1000000, path);

      expect(amounts.length).to.equal(path.length - 1);

      [...[1000000, ...RANDO_AMOUNTS, 900000], 900000]
        .map((v) => BigNumber.from(v))
        .forEach((num, i) => {
          expect(amounts[i]).to.equal(num);
        });
    });

    it("works no in no out", async () => {
      await router.mock.getAmountsOut
        ?.withArgs(1000000, [cUSD.address, ...RANDO_PATH, CELO.address])
        .returns([1000000, ...RANDO_AMOUNTS, 900000]);

      const path = [cUSD.address, ...RANDO_PATH, CELO.address];
      const amounts = await moolaRouter.getAmountsOut(1000000, path);

      expect(amounts.length).to.equal(path.length - 1);

      [1000000, ...RANDO_AMOUNTS, 900000]
        .map((v) => BigNumber.from(v))
        .forEach((num, i) => {
          expect(amounts[i]).to.equal(num);
        });
    });
  });

  describe("#getAmountsIn", () => {
    it("works in and out", async () => {
      await router.mock.getAmountsIn
        ?.withArgs(1000000, [cUSD.address, ...RANDO_PATH, CELO.address])
        .returns([1000000, ...RANDO_AMOUNTS, 900000]);

      const path = [
        mcUSD.address,
        cUSD.address,
        ...RANDO_PATH,
        CELO.address,
        mCELO.address,
      ];
      const amounts = await moolaRouter.getAmountsIn(1000000, path);

      expect(amounts.length).to.equal(path.length - 1);

      [1000000, ...[1000000, ...RANDO_AMOUNTS, 900000], 900000]
        .map((v) => BigNumber.from(v))
        .forEach((num, i) => {
          expect(amounts[i]).to.equal(num);
        });
    });

    it("works no out", async () => {
      const path = [mcUSD.address, cUSD.address, ...RANDO_PATH, CELO.address];
      const amounts = await moolaRouter.getAmountsIn(1000000, path);

      expect(amounts.length).to.equal(path.length - 1);

      [1000000, ...[1000000, ...RANDO_AMOUNTS, 900000]]
        .map((v) => BigNumber.from(v))
        .forEach((num, i) => {
          expect(amounts[i]).to.equal(num);
        });
    });

    it("works no in", async () => {
      await router.mock.getAmountsIn
        ?.withArgs(1000000, [cUSD.address, ...RANDO_PATH, CELO.address])
        .returns([1000000, ...RANDO_AMOUNTS, 900000]);

      const path = [cUSD.address, ...RANDO_PATH, CELO.address, mCELO.address];
      const amounts = await moolaRouter.getAmountsIn(1000000, path);

      expect(amounts.length).to.equal(path.length - 1);

      [...[1000000, ...RANDO_AMOUNTS, 900000], 900000]
        .map((v) => BigNumber.from(v))
        .forEach((num, i) => {
          expect(amounts[i]).to.equal(num);
        });
    });

    it("works no in no out", async () => {
      await router.mock.getAmountsIn
        ?.withArgs(1000000, [cUSD.address, ...RANDO_PATH, CELO.address])
        .returns([1000000, ...RANDO_AMOUNTS, 900000]);

      const path = [cUSD.address, ...RANDO_PATH, CELO.address];
      const amounts = await moolaRouter.getAmountsIn(1000000, path);

      expect(amounts.length).to.equal(path.length - 1);

      [1000000, ...RANDO_AMOUNTS, 900000]
        .map((v) => BigNumber.from(v))
        .forEach((num, i) => {
          expect(amounts[i]).to.equal(num);
        });
    });
  });
});
