import { makeDeployTask } from "@ubeswap/hardhat-celo";
import * as path from "path";
import { deployRouter } from "./001_router";

const deployers = {
  router: deployRouter,
};

export const { deploy } = makeDeployTask({
  deployers,
  rootDir: path.resolve(__dirname + "/../../"),
});
