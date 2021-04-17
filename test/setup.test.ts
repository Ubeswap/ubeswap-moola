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

export const MOCK_LPC_ADDRESS = getAddress(
  "0xff90d41fee89bcf4205fb249c2b3d1a405813601"
);
export const MOCK_GOLD_ADDRESS = "0x6E5bB2f456E6e4612B9D1D5EdD337810740162a2";

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

  await mockRegistry.contract.setAddress(
    solidityKeccak256(["string"], ["GoldToken"]),
    await lpc.contract.celo()
  );
});
