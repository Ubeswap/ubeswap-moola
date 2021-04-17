import { deployMockContract } from "@ethereum-waffle/mock-contract";
import UbeswapFactoryArtifact from "@ubeswap/core/build/metadata/UniswapV2Factory/artifact.json";
import UbeswapRouterArtifact from "@ubeswap/core/build/metadata/UniswapV2Router02/artifact.json";
import { doTx } from "@ubeswap/hardhat-celo";
import { getCurrentTime } from "@ubeswap/hardhat-celo/lib/testing";
import { deployContract } from "@ubeswap/solidity-create2-deployer";
import { expect } from "chai";
import { Wallet } from "ethers";
import { formatEther, parseEther, solidityKeccak256 } from "ethers/lib/utils";
import hre from "hardhat";
import IRegistryABI from "../build/abi/IRegistry.json";
import {
  UniswapV2Factory,
  UniswapV2Factory__factory,
  UniswapV2Router02,
  UniswapV2Router02__factory,
} from "../build/test-fixtures/";
import {
  IERC20,
  MockAToken,
  MockAToken__factory,
  MockERC20,
  MockERC20__factory,
  MockGold,
  MockGold__factory,
  MockLendingPool,
  MockLendingPoolCore,
  MockLendingPoolCore__factory,
  MockLendingPool__factory,
} from "../build/types";
import {
  UbeswapMoolaRouter,
  UbeswapMoolaRouter__factory,
} from "../build/types/";
import { countBy, uniq, uniqBy, zip } from "lodash";

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

describe("UbeswapMoolaRouter", () => {
  let wallet: Wallet;
  let other0: Wallet;
  let other1: Wallet;
  let chainId: number;

  let factory: UniswapV2Factory;
  let router: UniswapV2Router02;
  let pool: MockLendingPool;
  let core: MockLendingPoolCore;

  let cUSD: MockERC20;
  let CELO: MockGold;
  let mcUSD: MockAToken;
  let mCELO: MockAToken;

  let rand1: MockERC20;
  let rand2: MockERC20;
  let rand3: MockERC20;

  let moolaRouter: UbeswapMoolaRouter;

  let CUSD_CELO_PATH_TOKENS: readonly IERC20[];
  let CUSD_CELO_PATH: readonly string[];

  const ALL_ATOKENS_SYMBOLS = [
    ["cUSD", "mcUSD"],
    ["CELO", "mCELO"],
  ];
  const ALL_PATHS_NAMES = [
    "path",
    ...ALL_ATOKENS_SYMBOLS.flatMap(([token, aToken]) => {
      const paths = ALL_ATOKENS_SYMBOLS.flatMap(([outToken, outAToken]) => {
        return [
          `path -> out ${outToken}`,
          `path -> out ${outAToken}`,
          `path -> out ${outToken} -> ${outAToken}`,
          `path -> out ${outAToken} -> ${outToken}`,
        ];
      });
      return [
        ...paths.flatMap((path) => [
          path,
          `in ${aToken} -> ${path}`,
          `in ${token} -> ${path}`,
          `in ${token} -> ${aToken} -> ${path}`,
          `in ${aToken} -> ${token} -> ${path}`,
        ]),
      ];
    }),
  ];

  before(async () => {
    const wallets = await hre.waffle.provider.getWallets();
    chainId = await (await hre.waffle.provider.getNetwork()).chainId;

    wallet = wallets[0]!;
    other0 = wallets[1]!;
    other1 = wallets[2]!;

    factory = UniswapV2Factory__factory.connect(
      (
        await deployContract({
          salt: "Tayo'y magsayawan",
          signer: wallet,
          contractBytecode: "0x" + UbeswapFactoryArtifact.bin,
          constructorTypes: ["address"],
          constructorArgs: ["0xDF5B9dE8Ba90223e47c56Fb58Cfb80f79B95c967"],
        })
      ).address,
      wallet
    );
    router = UniswapV2Router02__factory.connect(
      (
        await deployContract({
          salt: "Tayo'y magsayawan",
          signer: wallet,
          contractBytecode: "0x" + UbeswapRouterArtifact.bin,
          constructorTypes: ["address"],
          constructorArgs: [factory.address],
        })
      ).address,
      wallet
    );
  });

  before("init moola router", async () => {
    cUSD = await new MockERC20__factory(wallet).deploy("Celo Dollar", "cUSD");
    CELO = await new MockGold__factory(wallet).deploy();

    // send gold
    await CELO.connect(other0).wrap({ value: parseEther("100") });
    await CELO.connect(other0).transfer(wallet.address, parseEther("100"));

    mcUSD = await new MockAToken__factory(wallet).deploy(
      cUSD.address,
      "Moola Dollar",
      "mcUSD"
    );
    mCELO = await new MockAToken__factory(wallet).deploy(
      CELO.address,
      "Moola Celo",
      "mCELO"
    );

    core = await new MockLendingPoolCore__factory(wallet).deploy(
      CELO.address,
      cUSD.address,
      mCELO.address,
      mcUSD.address
    );
    pool = await new MockLendingPool__factory(wallet).deploy(core.address);

    rand1 = await new MockERC20__factory(wallet).deploy("Randy One", "RAN1");
    rand2 = await new MockERC20__factory(wallet).deploy("Randy Deuce", "RAN2");
    rand3 = await new MockERC20__factory(wallet).deploy("Randy Tre", "RAN3");

    const registry = await deployMockContract(wallet, IRegistryABI);
    await registry.mock.getAddressForOrDie
      ?.withArgs(solidityKeccak256(["string"], ["GoldToken"]))
      .returns(CELO.address);

    moolaRouter = await new UbeswapMoolaRouter__factory(wallet).deploy(
      router.address,
      registry.address
    );
    await moolaRouter.initialize(pool.address, core.address);

    CUSD_CELO_PATH_TOKENS = [cUSD, rand1, rand2, rand3, CELO];
    CUSD_CELO_PATH = CUSD_CELO_PATH_TOKENS.map((tok) => tok.address);
    for (let i = 0; i < CUSD_CELO_PATH.length; i++) {
      await CUSD_CELO_PATH_TOKENS[i]?.approve(
        router.address,
        parseEther("100000000")
      );
    }
  });

  let ALL_ATOKENS: readonly [IERC20, MockAToken][];
  // All possible token in/out paths for those ATokens
  let ALL_PATHS: readonly (readonly IERC20[])[];

  before("setup swap tester", async () => {
    ALL_ATOKENS = [
      [cUSD, mcUSD],
      [CELO, mCELO],
    ];
    const commonPath = CUSD_CELO_PATH_TOKENS.slice(
      1,
      CUSD_CELO_PATH_TOKENS.length - 1
    );
    ALL_PATHS = [
      commonPath,
      ...ALL_ATOKENS.flatMap(([token, aToken]) => {
        const paths = ALL_ATOKENS.flatMap(([outToken, outAToken]) => {
          return [
            [...commonPath, outToken],
            [...commonPath, outAToken],
            [...commonPath, outToken, outAToken],
            [...commonPath, outAToken, outToken],
          ];
        });
        return [
          ...paths.flatMap((path) => [
            [...path],
            [aToken, ...path],
            [token, ...path],
            [token, aToken, ...path],
            [aToken, token, ...path],
          ]),
        ];
      }),
    ];
  });

  before("setup path liquidty", async () => {
    const allPairsWithDuplicates = ALL_PATHS.flatMap((path): [
      IERC20,
      IERC20
    ][] => {
      const pathPairs = zip(path, path.slice(1));
      pathPairs.pop();
      return pathPairs as [IERC20, IERC20][];
    });

    const allPairs = uniqBy(
      allPairsWithDuplicates,
      ([tokenA, tokenB]) => `${tokenA.address}-${tokenB.address}`
    );

    await cUSD.approve(moolaRouter.address, parseEther("1000"));
    await moolaRouter.deposit(cUSD.address, parseEther("1000"));
    await CELO.wrap({ value: parseEther("1000").mul(2) });
    await CELO.approve(moolaRouter.address, parseEther("1000"));
    await moolaRouter.deposit(CELO.address, parseEther("1000"));

    const counts = countBy(
      allPairs.flatMap((tok) => tok),
      (tok) => tok.address
    );

    // approve router for all deposits
    for (const token of uniqBy(
      allPairs.flatMap((tok) => tok),
      (tok) => tok.address
    )) {
      await token.approve(
        router.address,
        parseEther("100").mul(counts[token.address] ?? 1)
      );
    }

    // setup path liquidity
    for (const [tokenA, tokenB] of allPairs) {
      try {
        await router.addLiquidity(
          tokenA?.address!,
          tokenB?.address!,
          parseEther("100"),
          parseEther("100"),
          parseEther("100"),
          parseEther("100"),
          wallet.address,
          Math.floor(new Date().getTime() / 1000) + 1800000,
          { gasLimit: 7000000 }
        );
      } catch (e) {
        throw new Error(
          `Error providing liquidity to ${await tokenA.name()}-${await tokenB.name()}`
        );
      }
    }
  });

  describe("#swap", () => {
    const testTradePath = (index: number) => {
      if (!ALL_PATHS_NAMES[index]) {
        throw new Error(`unknown path ${index}`);
      }
      it(`trade ${ALL_PATHS_NAMES[index]}`, async () => {
        const path = ALL_PATHS[index];
        if (!path) {
          throw new Error(`no path at index ${index}`);
        }

        const [inputToken, ...innerPathWithLast] = path;
        const innerPath = innerPathWithLast.slice(
          0,
          innerPathWithLast.length - 1
        );
        const outputToken = innerPathWithLast[innerPathWithLast.length - 1];

        const swapper = hre.waffle.provider.createEmptyWallet();

        if (!inputToken || !outputToken) {
          throw new Error("path is empty");
        }

        // prepare swapper
        await Promise.all([
          other1.sendTransaction({
            to: swapper.address,
            value: parseEther("1"),
          }),
          await inputToken
            .transfer(swapper.address, parseEther("1"))
            .then(async () => {
              await inputToken
                .connect(swapper)
                .approve(moolaRouter.address, parseEther("1"));
            }),
        ]);

        await Promise.all([
          (async () => {
            expect(
              await inputToken.balanceOf(swapper.address),
              `pre-swap: swapper has one input ${await inputToken.name()}`
            ).to.equal(parseEther("1"));
          })(),
          // initial balance: 1 in, 0 all other path tokens
          ...[...innerPath, outputToken].map(async (token) => {
            if (token.address !== inputToken.address) {
              expect(
                await token.balanceOf(swapper.address),
                `pre-swap: swapper should have no ${await token.name()}`
              ).to.equal(0);
            }
          }),
          // router is empty for all path tokens
          ...path.map(async (token) => {
            expect(
              await token.balanceOf(moolaRouter.address),
              `pre-swap: router should have no ${await token.name()}`
            ).to.equal(0);
          }),
        ]);

        await moolaRouter.connect(swapper).swapExactTokensForTokens(
          parseEther("1"),
          parseEther("0.001"),
          path.map((p) => p.address),
          swapper.address,
          Math.floor(new Date().getTime() / 1000) + 999999
        );

        await Promise.all([
          // router is empty afterwards for all path tokens
          ...path.map(async (token) => {
            expect(
              await token.balanceOf(moolaRouter.address),
              `post-swap: router should have no ${await token.name()}`
            ).to.equal(0);
          }),
          // end balance: 0 inputToken, some outputToken UNLESS input == output
          ...[inputToken, ...innerPath].map(async (token) => {
            if (token.address !== outputToken.address) {
              expect(
                await token.balanceOf(swapper.address),
                `post-swap: swapper should have no ${await token.name()}`
              ).to.equal(0);
            }
          }),
          (async () => {
            expect(
              await outputToken.balanceOf(swapper.address),
              `post-swap: swapper more than zero output ${await outputToken.name()}`
            ).to.not.equal(0);
          })(),
        ]);
      });
    };

    ALL_PATHS_NAMES.forEach((_, i) => {
      testTradePath(i);
    });
  });
});
