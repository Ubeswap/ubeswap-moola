import { makeDeployTask } from "@ubeswap/hardhat-celo";
import { deployRouter } from "./001_router";

const deployers = {
  router: deployRouter,
};

export const { deploy } = makeDeployTask({ deployers });
