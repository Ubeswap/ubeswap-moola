import { deployMockContract } from "@ethereum-waffle/mock-contract";
import UbeswapFactoryArtifact from "@ubeswap/core/build/metadata/UniswapV2Factory/artifact.json";
import UbeswapRouterArtifact from "@ubeswap/core/build/metadata/UniswapV2Router02/artifact.json";
import { doTx } from "@ubeswap/hardhat-celo";
import { getCurrentTime } from "@ubeswap/hardhat-celo/lib/testing";
import { deployContract } from "@ubeswap/solidity-create2-deployer";
import { expect } from "chai";
import { BigNumber, ContractTransaction, Wallet } from "ethers";
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

interface ISwapArgs {
  readonly swapperRouter: UbeswapMoolaRouter;
  readonly swapper: Wallet;
  readonly path: readonly IERC20[];
  readonly inputToken: IERC20;
  readonly outputToken: IERC20;
  readonly innerPath: readonly IERC20[];
  readonly inAmountDesired: BigNumber;
  readonly outAmountDesired: BigNumber;
}

interface ISwapTester {
  methodName: string;
  swap: (args: ISwapArgs) => Promise<ContractTransaction>;
  checks: (args: ISwapArgs) => Promise<void>[];
  processSwapResult?: (
    args: ISwapArgs,
    result: Promise<ContractTransaction>
  ) => Promise<void>;
}

const swapExactTokensForTokensTester: ISwapTester = {
  methodName: "swapExactTokensForTokens",
  swap: async ({
    swapperRouter,
    swapper,
    path,
    inAmountDesired,
    outAmountDesired,
  }) =>
    swapperRouter.swapExactTokensForTokens(
      inAmountDesired,
      outAmountDesired,
      path.map((p) => p.address),
      swapper.address,
      Math.floor(new Date().getTime() / 1000) + 999999
    ),
  checks: ({ swapper, inputToken, outputToken }) => [
    (async () => {
      if (inputToken.address !== outputToken.address) {
        expect(
          await inputToken.balanceOf(swapper.address),
          `post-swap: swapper should have no input ${await inputToken.name()}`
        ).to.equal(0);
      }
    })(),
    (async () => {
      expect(
        await outputToken.balanceOf(swapper.address),
        `post-swap: swapper more than zero output ${await outputToken.name()}`
      ).to.not.equal(0);
    })(),
  ],
};

const swapTokensForExactTokensTester: ISwapTester = {
  methodName: "swapTokensForExactTokens",
  swap: async ({
    swapperRouter,
    swapper,
    path,
    inAmountDesired,
    outAmountDesired,
  }) =>
    swapperRouter.swapTokensForExactTokens(
      outAmountDesired,
      inAmountDesired,
      path.map((p) => p.address),
      swapper.address,
      Math.floor(new Date().getTime() / 1000) + 999999
    ),
  checks: ({
    swapper,
    inputToken,
    outputToken,
    inAmountDesired,
    outAmountDesired,
  }) => [
    // end balance: 0 inputToken, some outputToken UNLESS input == output
    (async () => {
      const newBalance = await inputToken.balanceOf(swapper.address);
      expect(
        newBalance,
        `post-swap: swapper should have more than zero input ${await inputToken.name()}`
      ).to.not.equal(0);
      expect(
        newBalance,
        `post-swap: swapper should have spent ${await inputToken.name()}`
      ).to.not.equal(inAmountDesired);
    })(),
    (async () => {
      if (inputToken.address === outputToken.address) {
        const newBalance = await outputToken.balanceOf(swapper.address);
        expect(
          newBalance,
          `post-swap: if input is output, swapper should not output the out ${await outputToken.name()}`
        ).to.not.equal(outAmountDesired);
        expect(
          newBalance,
          `post-swap: if input is output, swapper should modify balances ${await outputToken.name()}`
        ).to.not.equal(inAmountDesired);
      } else {
        expect(
          await outputToken.balanceOf(swapper.address),
          `post-swap: swapper should have preserved output ${await outputToken.name()}`
        ).to.equal(outAmountDesired);
      }
    })(),
  ],
  processSwapResult: async ({ swapperRouter }, result) => {
    await expect(result).to.emit(swapperRouter, "TokensSwapped");
  },
};

describe("UbeswapMoolaRouter swapping", () => {
  let wallet: Wallet;
  let other0: Wallet;

  let factory: UniswapV2Factory;
  let router: UniswapV2Router02;
  let moolaRouter: UbeswapMoolaRouter;

  // All possible token in/out paths for those ATokens
  let ALL_PATHS: readonly (readonly IERC20[])[];

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
    wallet = wallets[0]!;
    other0 = wallets[1]!;

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
    const cUSD = await new MockERC20__factory(wallet).deploy(
      "Celo Dollar",
      "cUSD"
    );
    const CELO = await new MockGold__factory(wallet).deploy();

    // send gold
    await CELO.connect(other0).wrap({ value: parseEther("100") });
    await CELO.connect(other0).transfer(wallet.address, parseEther("100"));

    const mcUSD = await new MockAToken__factory(wallet).deploy(
      cUSD.address,
      "Moola Dollar",
      "mcUSD"
    );
    const mCELO = await new MockAToken__factory(wallet).deploy(
      CELO.address,
      "Moola Celo",
      "mCELO"
    );

    const core = await new MockLendingPoolCore__factory(wallet).deploy(
      CELO.address,
      cUSD.address,
      mCELO.address,
      mcUSD.address
    );
    const pool = await new MockLendingPool__factory(wallet).deploy(
      core.address
    );

    const rand1 = await new MockERC20__factory(wallet).deploy(
      "Randy One",
      "RAN1"
    );
    const rand2 = await new MockERC20__factory(wallet).deploy(
      "Randy Deuce",
      "RAN2"
    );
    const rand3 = await new MockERC20__factory(wallet).deploy(
      "Randy Tre",
      "RAN3"
    );

    const registry = await deployMockContract(wallet, IRegistryABI);
    await registry.mock.getAddressForOrDie
      ?.withArgs(solidityKeccak256(["string"], ["GoldToken"]))
      .returns(CELO.address);

    moolaRouter = await new UbeswapMoolaRouter__factory(wallet).deploy(
      router.address,
      registry.address
    );
    await moolaRouter.initialize(pool.address, core.address);

    // setup swap tester
    const allAtokens = [
      [cUSD, mcUSD],
      [CELO, mCELO],
    ] as const;
    const commonPath = [rand1, rand2, rand3];
    ALL_PATHS = [
      commonPath,
      ...allAtokens.flatMap(([token, aToken]) => {
        const paths = allAtokens.flatMap(([outToken, outAToken]) => {
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

    // setup path liquidity
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

  const testTradePath = (index: number, tester: ISwapTester) => {
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

      const inAmountDesired = parseEther("1");
      const outAmountDesired = parseEther("0.001");

      try {
        // prepare swapper
        await Promise.all([
          // send eth
          other0.sendTransaction({
            to: swapper.address,
            value: parseEther("1"),
          }),
          // send in amount
          inputToken.transfer(swapper.address, inAmountDesired),
          inputToken
            .connect(swapper)
            .approve(moolaRouter.address, inAmountDesired),
        ]);
      } catch (e) {
        throw new Error("error preparing swapper: " + e.message);
      }

      await Promise.all([
        (async () => {
          expect(
            await inputToken.balanceOf(swapper.address),
            `pre-swap: swapper has desired ${formatEther(
              inAmountDesired
            )} ${await inputToken.name()}`
          ).to.equal(inAmountDesired);
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

      const args: ISwapArgs = {
        swapperRouter: moolaRouter.connect(swapper),
        swapper,
        path,
        inputToken,
        outputToken,
        innerPath,
        inAmountDesired,
        outAmountDesired,
      };
      try {
        const swapResult = tester.swap(args);
        if (tester.processSwapResult) {
          await tester.processSwapResult(args, swapResult);
        } else {
          await swapResult;
        }
      } catch (e) {
        throw new Error("error swapping: " + e.message);
      }
      await Promise.all([
        ...tester.checks(args),
        // router is empty afterwards for all path tokens
        ...path.map(async (token) => {
          expect(
            await token.balanceOf(moolaRouter.address),
            `post-swap: router should have no ${await token.name()}`
          ).to.equal(0);
        }),
        ...innerPath.map(async (token) => {
          if (
            token.address !== outputToken.address &&
            token.address !== inputToken.address
          ) {
            expect(
              await token.balanceOf(swapper.address),
              `post-swap: swapper should have no ${await token.name()}`
            ).to.equal(0);
          }
        }),
      ]);
    });
  };

  const testMethod = (tester: ISwapTester) => {
    describe(`#${tester.methodName}`, () => {
      ALL_PATHS_NAMES
        //
        // .slice(0, 15)
        .forEach((_, i) => {
          testTradePath(i, tester);
        });
    });
  };

  [
    //
    swapTokensForExactTokensTester,
    //
    swapExactTokensForTokensTester,
    //
  ].map(testMethod);
});
