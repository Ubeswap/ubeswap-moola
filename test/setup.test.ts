import { makeCommonEnvironment } from "@ubeswap/hardhat-celo";
import {
  deployCreate2,
  deployerAddress,
  deployFactory,
} from "@ubeswap/solidity-create2-deployer";
import { parseEther, solidityKeccak256 } from "ethers/lib/utils";
import hre from "hardhat";
import {
  MockLendingPool__factory,
  MockRegistry__factory,
} from "../build/types";

export const MOCK_LP_KEY = solidityKeccak256(["string"], ["LendingPool"]);

export const MOCK_GOLD_KEY = solidityKeccak256(["string"], ["GoldToken"]);

export const MOCK_REGISTRY_ADDRESS =
  "0xCde5a0dC96d0ecEaee6fFfA84a6d9a6343f2c8E2";

before(async () => {
  const { signer: deployer, provider } = await makeCommonEnvironment(hre);
  // deploy create2 factory
  await deployer.sendTransaction({
    to: deployerAddress,
    value: parseEther("1"),
  });
  await deployFactory(provider);

  const wallets = await hre.waffle.provider.getWallets();

  const mockRegistry = await deployCreate2({
    salt: "rando",
    signer: wallets[0]!,
    factory: MockRegistry__factory,
    args: [],
  });

  const lp = await deployCreate2({
    salt: "rando",
    signer: wallets[0]!,
    factory: MockLendingPool__factory,
    args: [],
  });

  await lp.contract.initialize();

  console.log("Mock lookup: " + mockRegistry.address);
  console.log("Mock lending pool core: " + lp.address);
  console.log("Mock Gold: " + (await lp.contract.celo()));

  await mockRegistry.contract.setAddress(MOCK_LP_KEY, lp.address);

  await mockRegistry.contract.setAddress(
    MOCK_GOLD_KEY,
    await lp.contract.celo()
  );
});
