import { DeployerFn, doTx } from "@ubeswap/hardhat-celo";
import { ChainId } from "@ubeswap/sdk";
import { UbeswapMoolaRouter__factory } from "../../build/types/factories/UbeswapMoolaRouter__factory";

const ROUTER_ADDRESS = "0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121";

const moolaLendingPools = {
  // Addresses from: https://github.com/moolamarket/moola
  [ChainId.ALFAJORES]: {
    lendingPool: "0x58ad305f1eCe49ca55ADE0D5cCC90114C3902E88",
    dataProvider: "0x31ccB9dC068058672D96E92BAf96B1607855822E",
  },
  [ChainId.MAINNET]: {
    lendingPool: "0x970b12522CA9b4054807a2c5B736149a5BE6f670",
    dataProvider: "0x43d067ed784D9DD2ffEda73775e2CC4c560103A1",
  },
};

export const OPERATOR = "0x489AAc7Cb9A3B233e4a289Ec92284C8d83d49c6f";

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
    args: [ROUTER_ADDRESS, OPERATOR],
    signer: deployer,
  });

  await doTx(
    "Initialize router",
    UbeswapMoolaRouter__factory.connect(
      ubeswapMoolaRouter.address,
      deployer
    ).initialize(pools.lendingPool, pools.dataProvider)
  );

  return {
    UbeswapMoolaRouter: ubeswapMoolaRouter.address,
  };
};
