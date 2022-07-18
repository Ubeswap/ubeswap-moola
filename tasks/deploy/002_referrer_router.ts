import { DeployerFn } from "@ubeswap/hardhat-celo";
import { ChainId } from "@ubeswap/sdk";
import { UbeswapReferrerRouter__factory } from "../../build/types/factories/UbeswapReferrerRouter__factory";

const moolaRouters = {
  [ChainId.ALFAJORES]: "0x56d0Ae52f33f7C2e38E92F6D20b8ccfD7Dc318Ce",
  [ChainId.MAINNET]: "0x7D28570135A2B1930F331c507F65039D4937f66c",
};

export const OPERATOR = "0x489AAc7Cb9A3B233e4a289Ec92284C8d83d49c6f";

export const deployReferrerRouter: DeployerFn<{
  UbeswapReferrerRouter: string;
}> = async ({ deployer, deployCreate2 }) => {
  const chainId = (await deployer.getChainId()) as ChainId;
  const moolaRouter =
    chainId in moolaRouters
      ? moolaRouters[chainId as keyof typeof moolaRouters]
      : null;
  if (!moolaRouter) {
    throw new Error(`unknown chain id ${chainId}`);
  }

  const referrerRouter = await deployCreate2("UbeswapReferrerRouter", {
    factory: UbeswapReferrerRouter__factory,
    args: [moolaRouter],
    signer: deployer,
  });

  return {
    UbeswapReferrerRouter: referrerRouter.address,
  };
};
