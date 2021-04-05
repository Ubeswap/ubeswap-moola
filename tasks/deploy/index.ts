import { networkNames } from "@ubeswap/hardhat-celo";
import { ChainId } from "@ubeswap/sdk";
import { deployCreate2 } from "@ubeswap/solidity-create2-deployer";
import { ethers, Signer } from "ethers";
import * as fs from "fs/promises";
import { ActionType, HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployCreate2 } from "../lib/deployCreate2";
import { log } from "../lib/logger";
import { deployRouter } from "./001_router";

const SALT = process.env.SALT ?? "no salt";
if (!process.env.SALT) {
  console.warn("SALT not specified.");
}

export type DeployFunction<R> = (args: {
  provider: ethers.providers.BaseProvider;
  deployer: Signer;
  getAddresses: <D extends keyof typeof deployers>(
    keys: readonly D[]
  ) => IAllResults<D>;
  salt: string;
  deployCreate2: DeployCreate2;
}) => Promise<R>;

export const deployers = {
  router: deployRouter,
};

type AsyncReturnType<T extends (...args: any) => any> = T extends (
  ...args: any
) => Promise<infer U>
  ? U
  : T extends (...args: any) => infer U
  ? U
  : any;

// https://fettblog.eu/typescript-union-to-intersection/
type UnionToIntersection<T> = (T extends any ? (x: T) => any : never) extends (
  x: infer R
) => any
  ? R
  : never;

/**
 * Gets the type of the results of the given steps.
 */
export type IAllResults<D extends keyof typeof deployers> = UnionToIntersection<
  AsyncReturnType<typeof deployers[D]>
>;

const makeConfigPath = (step: string, chainId: ChainId): string =>
  __dirname +
  `/../../deployments/${step}.${networkNames[chainId]}.addresses.json`;

const writeDeployment = async (
  step: string,
  chainId: ChainId,
  addresses: Record<string, unknown>
): Promise<void> => {
  const configPath = makeConfigPath(step, chainId);
  Object.entries(addresses).forEach(([name, addr]) =>
    console.log(
      `${name}: ${
        typeof addr === "string" ? addr : JSON.stringify(addr, null, 2)
      }`
    )
  );
  await fs.writeFile(configPath, JSON.stringify(addresses, null, 2));
};

export const makeCommon = async (
  env: HardhatRuntimeEnvironment
): Promise<{
  signer: Signer;
  provider: ethers.providers.BaseProvider;
}> => {
  if (env.network.config.chainId === 31337) {
    const [deployerSigner] = await env.ethers.getSigners();
    if (!deployerSigner) {
      throw new Error("No deployer.");
    }
    return { signer: deployerSigner, provider: env.ethers.provider };
  } else {
    const [deployerSigner] = env.celo.getSigners();
    if (!deployerSigner) {
      throw new Error("No deployer.");
    }
    return { signer: deployerSigner, provider: env.celo.ethersProvider };
  }
};

export const deploy: ActionType<{ step: string }> = async ({ step }, env) => {
  const chainId = (await env.celo.kit.connection.chainId()) as ChainId;
  const deployer = (deployers as { [step: string]: DeployFunction<unknown> })[
    step
  ];
  if (!deployer) {
    throw new Error(`Unknown step: ${step}`);
  }

  const { signer, provider } = await makeCommon(env);

  const theDeployCreate2 = (async (
    name,
    { signer, factory, args, saltExtra }
  ) => {
    log(`Deploying ${name}...`);
    const result = await deployCreate2({
      signer,
      factory,
      args,
      salt: `${SALT}-${name}${saltExtra ?? ""}`,
    });
    log(`Deployed at ${result.address} (tx: ${result.txHash})`);
    return result;
  }) as DeployCreate2;

  const result = await deployer({
    deployer: signer,
    provider,
    getAddresses: <D extends keyof typeof deployers>(keys: readonly D[]) =>
      ({
        ...keys.reduce(
          (acc, k) => ({
            ...acc,
            ...require(`../../deployments/${k}.${networkNames[chainId]}.addresses.json`),
          }),
          {}
        ),
      } as IAllResults<D>),
    salt: SALT,
    deployCreate2: theDeployCreate2,
  });
  await writeDeployment(step, chainId, result as Record<string, unknown>);
};

const tryRequire = (path: string): Record<string, unknown> => {
  try {
    return require(path);
  } catch (e) {
    return {};
  }
};
