import { makeCommonEnvironment } from "@ubeswap/hardhat-celo";
import {
  deployCreate2,
  deployerAddress,
  deployFactory,
} from "@ubeswap/solidity-create2-deployer";
import { getAddress, parseEther, solidityKeccak256 } from "ethers/lib/utils";
import hre from "hardhat";
import {
  MockLendingPoolCore__factory,
  MockRegistry__factory,
} from "../build/types";

export const MOCK_LPC_KEY = solidityKeccak256(["string"], ["LendingPoolCore"]);

export const MOCK_GOLD_KEY = solidityKeccak256(["string"], ["GoldToken"]);

export const MOCK_REGISTRY_ADDRESS =
  "0xd5Fd7f35752300C24cb6C2D4c954A34463070432";

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

  const lpc = await deployCreate2({
    salt: "rando",
    signer: wallets[0]!,
    factory: MockLendingPoolCore__factory,
    args: [],
  });

  await lpc.contract.initialize();

  console.log("Mock lookup: " + mockRegistry.address);
  console.log("Mock lending pool core: " + lpc.address);
  console.log("Mock Gold: " + (await lpc.contract.celo()));

  await mockRegistry.contract.setAddress(MOCK_LPC_KEY, lpc.address);

  await mockRegistry.contract.setAddress(
    MOCK_GOLD_KEY,
    await lpc.contract.celo()
  );
});
