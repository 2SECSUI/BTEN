#!/usr/bin/env node
/**
 * Builds a guarded replacement-farm reward schedule transaction. It is a
 * simulation by default; `--execute` is required to broadcast. Operators
 * must first confirm that no active reward schedule already exists.
 */
import fs from "node:fs";
import { execFileSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { Aftermath } from "aftermath-ts-sdk";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

const OWNER = "0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a";
const FARM = "0x462c6ea2b16c1ab8d5afac0af198f52aede5f0dbdfd45009b77d4007161fed7f";
const CAP = "0xfc4e31b0d5979e27151d38f549192817af6a9ddd9f64bb2a02d2b4c6e7b88e3d";
const BTEN = "0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN";
const amountIndex = process.argv.indexOf("--amount-raw");
const REWARD_AMOUNT = amountIndex >= 0 ? BigInt(process.argv[amountIndex + 1]) : 500_000_000n; // 5 BTEN, 8 decimals
const SCHEDULE_MS = 500_000_000; // 1 raw unit/ms = 5.79 days
const EXECUTE = process.argv.includes("--execute");
if (REWARD_AMOUNT <= 0n) throw new Error("--amount-raw must be a positive integer");

const farmObject = JSON.parse(execFileSync("sui", ["client", "object", FARM, "--json"], { encoding: "utf8" }));
const rewardsRemaining = BigInt(farmObject?.content?.total_rewards_remaining?.[0] ?? 0);
if (rewardsRemaining > 0n) {
  console.log(JSON.stringify({
    mode: EXECUTE ? "execute" : "dry-run",
    submitted: false,
    reason: "replacement farm already has an active reward schedule",
    farm: FARM,
    rewardsRemainingRaw: rewardsRemaining.toString(),
  }, null, 2));
  process.exit(0);
}

function signer() {
  const file = path.join(process.env.SUI_CONFIG_DIR || path.join(os.homedir(), ".sui", "sui_config"), "sui.keystore");
  const entries = JSON.parse(fs.readFileSync(file, "utf8"));
  for (const entry of Array.isArray(entries) ? entries : entries.keys ?? []) {
    try {
      const decoded = entry.startsWith("suiprivkey") ? decodeSuiPrivateKey(entry) : null;
      const encoded = decoded ? null : Uint8Array.from(Buffer.from(entry, "base64"));
      const key = decoded?.schema === "ED25519"
        ? Ed25519Keypair.fromSecretKey(decoded.secretKey)
        : (encoded?.length === 33 && encoded[0] === 0 ? Ed25519Keypair.fromSecretKey(encoded.slice(1)) : null);
      if (key?.toSuiAddress().toLowerCase() === OWNER) return key;
    } catch { /* ignore unrelated entries */ }
  }
  throw new Error("controlled BTEN signer unavailable");
}

const aftermath = await Aftermath.create({ network: "MAINNET" });
const farm = await aftermath.Farms().getStakingPool({ objectId: FARM });
const tx = await farm.getInitializeRewardTransaction({
  ownerCapId: CAP,
  rewardAmount: REWARD_AMOUNT,
  emissionScheduleMs: SCHEDULE_MS,
  emissionRate: 1n,
  emissionDelayTimestampMs: 0,
  rewardCoinType: BTEN,
  walletAddress: OWNER,
});
tx.setSender(OWNER);
const client = new SuiGrpcClient({ network: "mainnet", baseUrl: "https://fullnode.mainnet.sui.io:443" });
const result = EXECUTE
  ? await client.signAndExecuteTransaction({ signer: signer(), transaction: tx, include: { effects: true, events: true } })
  : await client.simulateTransaction({ transaction: tx, include: { effects: true, events: true } });
const executed = result.Transaction ?? result;
console.log(JSON.stringify({
  mode: EXECUTE ? "execute" : "dry-run",
  farm: FARM,
  rewardAmountRaw: REWARD_AMOUNT.toString(),
  scheduleMs: SCHEDULE_MS,
  startsImmediately: true,
  digest: executed.digest,
  status: executed.effects?.status,
  events: executed.events,
}, null, 2));
if (executed.effects?.status?.status !== "success") process.exitCode = 1;
