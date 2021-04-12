import { DeployerFn } from "@ubeswap/hardhat-celo";
import { ChainId } from "@ubeswap/sdk";
import { UbeswapMoolaRouter__factory } from "../../build/types/factories/UbeswapMoolaRouter__factory";

const ROUTER_ADDRESS = "0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121";

const moolaLendingPools = {
  // Addresses from: https://github.com/moolamarket/moola
  [ChainId.ALFAJORES]: {
    lendingPool: "0x0886f74eEEc443fBb6907fB5528B57C28E813129",
    lendingPoolCore: "0x090D652d1Bb0FEFbEe2531e9BBbb3604bE71f5de",
  },
  [ChainId.MAINNET]: {
    lendingPool: "0xc1548F5AA1D76CDcAB7385FA6B5cEA70f941e535",
    lendingPoolCore: "0xAF106F8D4756490E7069027315F4886cc94A8F73",
  },
};

export const deployRouter: DeployerFn<{
  UbeswapMoolaRouter: string;
}> = async ({ deployer, deployCreate2 }) => {
  const chainId = (await deployer.getChainId()) as ChainId;
  const pools =
    chainId in moolaLendingPools
      ? moolaLendingPools[chainId as keyof typeof moolaLendingPools]
      : null;
  if (!pools) {
    throw new Error(`unknown chain id ${chainId}`);
  }

  const ubeswapMoolaRouter = await deployCreate2("UbeswapMoolaRouter", {
    factory: UbeswapMoolaRouter__factory,
    args: [
      ROUTER_ADDRESS,
      pools.lendingPool,
      pools.lendingPoolCore,
      "0x000000000000000000000000000000000000ce10",
    ],
    signer: deployer,
  });

  return {
    UbeswapMoolaRouter: ubeswapMoolaRouter.address,
  };
};
