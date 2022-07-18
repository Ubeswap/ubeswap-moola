import { makeDeployTask } from "@ubeswap/hardhat-celo";
import * as path from "path";
import { deployRouter } from "./001_router";
import { deployReferrerRouter } from "./002_referrer_router";

const deployers = {
  router: deployRouter,
  referrerRouter: deployReferrerRouter,
};

export const { deploy } = makeDeployTask({
  deployers,
  rootDir: path.resolve(__dirname + "/../../"),
});
