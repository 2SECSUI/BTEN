import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const policy = JSON.parse(fs.readFileSync(path.join(root, "config", "keeper_policy.json"), "utf8"));

test("keeper policy is a separate, bounded wallet", () => {
  assert.match(policy.keeperAddress, /^0x[0-9a-f]{64}$/i);
  assert.notEqual(policy.keeperAddress.toLowerCase(), policy.opsAddress.toLowerCase());
  assert.equal(policy.maxSuiBalanceMist, "4000000000");
  assert.match(policy.distributionState, /^0x[0-9a-f]{64}$/i);
  assert.match(policy.routeTreasuryState, /^0x[0-9a-f]{64}$/i);
  // GH settle/attest stay off while Bandbot owns WAL/SUI permissionless attest.
  assert.equal(policy.settlement.enabled, false);
  assert.equal(policy.attest.enabled, false);
  assert.equal(policy.attest.includeRemoveLiquidity, true);
  assert.equal(policy.attest.includeAddLiquidity, true);
  assert.equal(policy.minTradesPerBlock, 10);
  assert.equal(policy.settlement.routesPerBlock, 10);
  assert.equal(policy.settlement.tradeBar, true);
  assert.equal(policy.settlement.maximumBlocksPerRun, 100);
  assert.equal(policy.privilegedExecutors.enabled, false);
  assert.equal(policy.livePackageVersion, 30);
});
