import {
  deployerAddress,
  deployFactory,
} from "@ubeswap/solidity-create2-deployer";
import { parseEther } from "ethers/lib/utils";
import hre from "hardhat";
import { makeCommon } from "../tasks/deploy";

before(async () => {
  const { signer: deployer, provider } = await makeCommon(hre);
  // deploy create2 factory
  await deployer.sendTransaction({
    to: deployerAddress,
    value: parseEther("1"),
  });
  await deployFactory(provider);
});
