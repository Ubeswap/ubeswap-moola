import {
  deployCreate2,
  deployerAddress,
  deployFactory,
} from "@ubeswap/solidity-create2-deployer";
import { parseEther } from "ethers/lib/utils";
import hre from "hardhat";
import { makeCommonEnvironment } from "@ubeswap/hardhat-celo";
import { MockGold__factory } from "../build/types";

export const MOCK_GOLD_ADDRESS = "0x3F735F0E3bdcFaA6e53FD0D9C844a3fcd3CCC81b";

before(async () => {
  const { signer: deployer, provider } = await makeCommonEnvironment(hre);
  // deploy create2 factory
  await deployer.sendTransaction({
    to: deployerAddress,
    value: parseEther("1"),
  });
  await deployFactory(provider);

  const wallets = await hre.waffle.provider.getWallets();
  await deployCreate2({
    salt: "rando",
    signer: wallets[0]!,
    factory: MockGold__factory,
    args: [],
  });
});
