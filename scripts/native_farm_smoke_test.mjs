#!/usr/bin/env node
/**
 * Wallet-signed native BTEN farm smoke test.
 * Default mode simulates. `--execute` broadcasts exactly one selected action.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction, coinWithBalance } from "@mysten/sui/transactions";

const root = path.resolve(import.meta.dirname, "..");
const integration = JSON.parse(fs.readFileSync(path.join(root, "config", "block10_integration.json"), "utf8"));
const farm = JSON.parse(fs.readFileSync(path.join(root, "config", "bten_staking_farm.json"), "utf8"));
const owner = "0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a";
const action = process.argv.includes("--withdraw") ? "withdraw" : "stake";
const execute = process.argv.includes("--execute");
const raw = BigInt(process.argv[process.argv.indexOf("--amount-raw") + 1] ?? "1000000"); // 0.01 BTEN
if (raw <= 0n || farm.status !== "active" || !farm.farmObjectId) throw new Error("active farm and positive --amount-raw are required");

function signer() {
  const keystore = path.join(process.env.SUI_CONFIG_DIR ?? path.join(os.homedir(), ".sui", "sui_config"), "sui.keystore");
  for (const entry of JSON.parse(fs.readFileSync(keystore, "utf8"))) {
    try {
      const secret = entry.startsWith("suiprivkey") ? decodeSuiPrivateKey(entry).secretKey : Uint8Array.from(Buffer.from(entry, "base64")).slice(1);
      const key = Ed25519Keypair.fromSecretKey(secret);
      if (key.toSuiAddress().toLowerCase() === owner) return key;
    } catch { /* unrelated signer */ }
  }
  throw new Error("controlled wallet signer unavailable");
}

const tx = new Transaction();
tx.setSender(owner);
tx.setGasBudget(30_000_000);
if (action === "stake") {
  const stake = tx.add(coinWithBalance({ balance: raw, type: farm.coinType }));
  tx.moveCall({ target: `${integration.currentPackage}::bten::stake_bten`, arguments: [tx.object(integration.emissionState), tx.object(farm.farmObjectId), stake] });
} else {
  tx.moveCall({ target: `${integration.currentPackage}::bten::withdraw_bten_and_rewards`, arguments: [tx.object(integration.emissionState), tx.object(farm.farmObjectId), tx.pure.u64(raw)] });
}
const client = new SuiGrpcClient({ network: "mainnet", baseUrl: "https://fullnode.mainnet.sui.io:443" });
const result = execute
  ? await client.signAndExecuteTransaction({ signer: signer(), transaction: tx, include: { effects: true, events: true, balanceChanges: true } })
  : await client.simulateTransaction({ transaction: tx, include: { effects: true, events: true, balanceChanges: true } });
const out = result.Transaction ?? result;
const status = out.effects?.status;
console.log(JSON.stringify({ mode: execute ? "execute" : "dry-run", action, amountRaw: raw.toString(), farm: farm.farmObjectId, digest: out.digest ?? null, status, balanceChanges: out.balanceChanges ?? [] }, null, 2));
if (!(status?.success === true || status?.status === "success")) process.exitCode = 1;
