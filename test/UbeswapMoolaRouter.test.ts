import { deployMockContract } from "@ethereum-waffle/mock-contract";
import { Wallet } from "ethers";
import hre from "hardhat";
import IUbeswapRouterABI from "../build/abi/IUbeswapRouter.json";
import ILendingPoolABI from "../build/abi/ILendingPool.json";
import ILendingPoolCoreABI from "../build/abi/ILendingPoolCore.json";
import IATokenABI from "../build/abi/IAToken.json";
import IERC20ABI from "../build/abi/IERC20.json";
import IRegistryABI from "../build/abi/IRegistry.json";
import { UbeswapMoolaRouter__factory } from "../build/types/factories/UbeswapMoolaRouter__factory";
import { expect } from "chai";

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

describe("UbeswapMoolaRouter", () => {
  let wallet: Wallet;
  let other0: Wallet;
  let other1: Wallet;
  let chainId: number;

  before(async () => {
    const wallets = await hre.waffle.provider.getWallets();
    chainId = await (await hre.waffle.provider.getNetwork()).chainId;

    wallet = wallets[0]!;
    other0 = wallets[1]!;
    other1 = wallets[2]!;
  });

  describe("#computeSwap", () => {
    it("works", async () => {
      const router = await deployMockContract(wallet, IUbeswapRouterABI);
      const pool = await deployMockContract(wallet, ILendingPoolABI);
      const core = await deployMockContract(wallet, ILendingPoolCoreABI);
      const cUSD = await deployMockContract(wallet, IERC20ABI);
      const CELO = await deployMockContract(wallet, IERC20ABI);
      const mcUSD = await deployMockContract(wallet, IATokenABI);
      const mCELO = await deployMockContract(wallet, IATokenABI);

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

      const registry = await deployMockContract(wallet, IRegistryABI);
      const moolaRouter = await new UbeswapMoolaRouter__factory(wallet).deploy(
        router.address,
        pool.address,
        core.address,
        registry.address
      );

      await registry.mock.getAddressForOrDie
        ?.withArgs(await moolaRouter.GOLD_TOKEN_REGISTRY_ID())
        .returns(CELO.address);

      const {
        _reserveIn,
        _depositIn,
        _reserveOut,
        _depositOut,
        _nextPath,
      } = await moolaRouter.computeSwap([
        mcUSD.address,
        cUSD.address,
        CELO.address,
        mCELO.address,
      ]);

      expect(_reserveIn).to.equal(cUSD.address);
      expect(_depositIn).to.equal(false);
      expect(_reserveOut).to.equal(CELO.address);
      expect(_depositOut).to.equal(true);
      expect(_nextPath).to.eql([cUSD.address, CELO.address]);
    });
  });
});
