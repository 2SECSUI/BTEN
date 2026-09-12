#!/usr/bin/env node
/**
 * BTEN -> Aftermath rolling staking keeper.
 *
 * Read-only by default. It never tops up a live reward schedule. When a
 * schedule is exhausted, `--execute` performs two deliberate operations:
 * withdraw one bounded tranche from BTEN's staking vault, then initialise the
 * next Aftermath reward schedule. The operations are intentionally separate:
 * Aftermath's SDK selects a wallet Coin for its funding call, while BTEN's
 * staking allocation is held inside EmissionState.
 */
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Aftermath } from "aftermath-ts-sdk";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";

const root = path.resolve(import.meta.dirname, "..");
const mainnet = JSON.parse(fs.readFileSync(path.join(root, "MAINNET_ROUTE_CONFIG.json"), "utf8"));
const OWNER = "0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a";
// Always target the currently published BTEN package; the state object types
// remain stable across upgrades, while hard-coding a prior package breaks the
// rolling-farm path after a release.
const PACKAGE = mainnet.currentPackage;
const STATE = "0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253";
const ADMIN = "0x950ef4d2afc672d684e54e39204b6d7f328d76f47590da73463f525e531973e9";
const FARM = "0x462c6ea2b16c1ab8d5afac0af198f52aede5f0dbdfd45009b77d4007161fed7f";
const FARM_CAP = "0xfc4e31b0d5979e27151d38f549192817af6a9ddd9f64bb2a02d2b4c6e7b88e3d";
const BTEN = "0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN";
const TRANCHE = 500_000_000n; // 5 BTEN at 8 decimals
const SCHEDULE_MS = 500_000_000;
const EXECUTE = process.argv.includes("--execute");

const readObject = (id) => JSON.parse(execFileSync("sui", ["client", "object", id, "--json"], { encoding: "utf8" })).content;
const state = readObject(STATE);
const farm = readObject(FARM);
const available = BigInt(state.staking_vault ?? 0);
const remaining = BigInt(farm.total_rewards_remaining?.[0] ?? 0);
const report = {
  mode: EXECUTE ? "execute" : "read-only",
  farm: FARM,
  activeScheduleRemainingRaw: remaining.toString(),
  stakingVaultRaw: available.toString(),
  trancheRaw: TRANCHE.toString(),
};

if (remaining > 0n) {
  console.log(JSON.stringify({ ...report, submitted: false, reason: "active Aftermath schedule still has rewards" }, null, 2));
  process.exit(0);
}
if (available < TRANCHE) {
  console.log(JSON.stringify({ ...report, submitted: false, reason: "staking vault has less than one rolling tranche" }, null, 2));
  process.exit(0);
}
if (!EXECUTE) {
  console.log(JSON.stringify({ ...report, submitted: false, eligible: true, reason: "farm exhausted; rerun with --execute to create exactly one replacement schedule" }, null, 2));
  process.exit(0);
}

function signer() {
  const file = path.join(process.env.SUI_CONFIG_DIR || path.join(os.homedir(), ".sui", "sui_config"), "sui.keystore");
  for (const entry of JSON.parse(fs.readFileSync(file, "utf8"))) {
    try {
      const decoded = entry.startsWith("suiprivkey") ? decodeSuiPrivateKey(entry) : null;
      const raw = decoded ? decoded.secretKey : Uint8Array.from(Buffer.from(entry, "base64")).slice(1);
      const key = Ed25519Keypair.fromSecretKey(raw);
      if (key.toSuiAddress().toLowerCase() === OWNER) return key;
    } catch { /* ignore unrelated keystore entries */ }
  }
  throw new Error("ops signer unavailable");
}

const client = new SuiGrpcClient({ network: "mainnet", baseUrl: "https://fullnode.mainnet.sui.io:443" });
const withdrawTx = new Transaction();
withdrawTx.setSender(OWNER);
withdrawTx.setGasBudget(30_000_000);
withdrawTx.moveCall({ target: `${PACKAGE}::bten::withdraw_staking_rewards_to_sender`, arguments: [withdrawTx.object(STATE), withdrawTx.object(ADMIN), withdrawTx.pure.u64(TRANCHE)] });
const withdrawal = await client.signAndExecuteTransaction({ signer: signer(), transaction: withdrawTx, include: { effects: true, events: true, balanceChanges: true } });
const withdrawn = withdrawal.Transaction ?? withdrawal;
if (withdrawn.effects?.status?.status !== "success") throw new Error("staking-vault withdrawal failed; farm was not funded");

const aftermath = await Aftermath.create({ network: "MAINNET" });
const stakingPool = await aftermath.Farms().getStakingPool({ objectId: FARM });
const fundingTx = await stakingPool.getInitializeRewardTransaction({
  ownerCapId: FARM_CAP,
  rewardAmount: TRANCHE,
  emissionScheduleMs: SCHEDULE_MS,
  emissionRate: 1n,
  emissionDelayTimestampMs: 0,
  rewardCoinType: BTEN,
  walletAddress: OWNER,
});
fundingTx.setSender(OWNER);
const funding = await client.signAndExecuteTransaction({ signer: signer(), transaction: fundingTx, include: { effects: true, events: true, balanceChanges: true } });
const funded = funding.Transaction ?? funding;
console.log(JSON.stringify({ ...report, submitted: true, withdrawalDigest: withdrawn.digest, fundingDigest: funded.digest, fundingStatus: funded.effects?.status, balanceChanges: funded.balanceChanges ?? [] }, null, 2));
if (funded.effects?.status?.status !== "success") process.exitCode = 1;
