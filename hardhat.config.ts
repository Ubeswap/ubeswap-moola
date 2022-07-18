import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-solhint";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-deploy";
// import "@ubeswap/hardhat-celo";
import { fornoURLs, ICeloNetwork } from "@ubeswap/hardhat-celo";
import "dotenv/config";
import { parseEther } from "ethers/lib/utils";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import { removeConsoleLog } from "hardhat-preprocessor";
import "hardhat-spdx-license-identifier";
import { HardhatUserConfig, task } from "hardhat/config";
import { ActionType, HDAccountsUserConfig } from "hardhat/types";
import "solidity-coverage";

// task("deploy", "Deploys a step", (async (...args) =>
//   (await import("./tasks/deploy")).deploy(...args)) as ActionType<{
//   step: string;
// }>).addParam("step", "The step to deploy");

const accounts: HDAccountsUserConfig = {
  mnemonic:
    process.env.MNEMONIC ||
    "test test test test test test test test test test test junk",
  path: "m/44'/52752'/0'/0/",
};

export default {
  abiExporter: {
    path: "./build/abi",
    //clear: true,
    flat: true,
    // only: [],
    // except: []
  },
  waffle: {
    default_balance_ether: 1000000,
  },
  defaultNetwork: "hardhat",
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: "USD",
  },
  networks: {
    mainnet: {
      url: fornoURLs[ICeloNetwork.MAINNET],
      accounts,
      chainId: ICeloNetwork.MAINNET,
      live: true,
      gasPrice: 2 * 10 ** 8,
      gas: 8000000,
    },
    alfajores: {
      url: fornoURLs[ICeloNetwork.ALFAJORES],
      accounts,
      chainId: ICeloNetwork.ALFAJORES,
      live: true,
      gasPrice: 2 * 10 ** 8,
      gas: 8000000,
    },
    hardhat: {
      chainId: 31337,
      accounts: {
        ...accounts,
        accountsBalance: parseEther("1000000").toString(),
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./build/cache",
    artifacts: "./build/artifacts",
  },
  preprocess: {
    eachLine: removeConsoleLog(
      (bre) =>
        bre.network.name !== "hardhat" && bre.network.name !== "localhost"
    ),
  },
  solidity: {
    version: "0.8.3",
    settings: {
      optimizer: {
        enabled: true,
        runs: 999999,
      },
      metadata: {
        useLiteralContent: true,
      },
      outputSelection: {
        "*": {
          "*": [
            "abi",
            "evm.bytecode",
            "evm.deployedBytecode",
            "evm.methodIdentifiers",
            "metadata",
          ],
          "": ["ast"],
        },
      },
    },
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  namedAccounts: {
    deployer: 0,
  },
  typechain: {
    target: "ethers-v5",
    outDir: "build/types",
  },
} as HardhatUserConfig;
