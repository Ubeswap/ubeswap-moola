import { Wallet } from "ethers";
import hre from "hardhat";

describe("UbeswapMoolaRouter", () => {
  let wallet: Wallet;
  let other0: Wallet;
  let other1: Wallet;
  let chainId: number;

  before(async () => {
    const wallets = await hre.waffle.provider.getWallets();
    chainId = await (await hre.waffle.provider.getNetwork()).chainId;

    wallet = wallets[0]!;
    other0 = wallets[1]!;
    other1 = wallets[2]!;
  });
});
