#!/usr/bin/env node
/**
 * GitHub Actions keeper for permissionless BTEN maintenance.
 *
 * `--execute` is deliberately limited to settlement and treasury accounting.
 * It never swaps, transfers treasury assets, funds a farm, controls upgrades,
 * or starts a sponsor.  Those paths require the future delegated KeeperCap
 * release described in config/keeper_policy.json.
 */
import fs from "node:fs";
import path from "node:path";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";

const root = path.resolve(import.meta.dirname, "..");
const mainnet = JSON.parse(fs.readFileSync(path.join(root, "MAINNET_ROUTE_CONFIG.json"), "utf8"));
const policy = JSON.parse(fs.readFileSync(path.join(root, "config", "keeper_policy.json"), "utf8"));
const distribution = JSON.parse(fs.readFileSync(path.join(root, "config", "distribution_destinations.json"), "utf8"));
const treasury = JSON.parse(fs.readFileSync(path.join(root, "config", "route_treasury_policy.json"), "utf8"));
const EXECUTE = process.argv.includes("--execute");
const GRAPHQL = "https://graphql.mainnet.sui.io/graphql";
const PACKAGE = "0xfb4a37274bc784bc31cd03bbb6ab3e176d077ce22722ca2d7a9ba7f08f814042";
const CLOCK = "0x6";
const SLOT_SECONDS = 600;
const ROUTES_PER_BLOCK = 10;

async function moveFields(address) {
  const query = `query($address: SuiAddress!) { object(address: $address) { asMoveObject { contents { json } } } }`;
  const response = await fetch(GRAPHQL, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, variables: { address } }),
  });
  if (!response.ok) throw new Error(`GraphQL object read failed: ${response.status}`);
  const body = await response.json();
  if (body.errors?.length || !body.data?.object?.asMoveObject?.contents?.json) throw new Error(`Object ${address} is unavailable`);
  return body.data.object.asMoveObject.contents.json;
}

function keeperSigner() {
  const encoded = process.env.BTEN_KEEPER_PRIVATE_KEY;
  if (!encoded) throw new Error("BTEN_KEEPER_PRIVATE_KEY is required only for --execute");
  const secret = encoded.startsWith("suiprivkey")
    ? decodeSuiPrivateKey(encoded).secretKey
    : Uint8Array.from(Buffer.from(encoded, "base64")).slice(1);
  const signer = Ed25519Keypair.fromSecretKey(secret);
  if (signer.toSuiAddress().toLowerCase() !== policy.keeperAddress.toLowerCase()) throw new Error("GitHub secret does not match the configured dedicated keeper address");
  if (signer.toSuiAddress().toLowerCase() === policy.opsAddress.toLowerCase()) throw new Error("Ops wallet is forbidden as a GitHub keeper");
  return signer;
}

function succeeded(result) {
  const effects = result.effects ?? result.transaction?.effects ?? result.Transaction?.effects;
  return effects?.status?.status === "success" || effects?.status?.success === true;
}

async function execute(client, signer, transaction) {
  const result = await client.signAndExecuteTransaction({ signer, transaction, include: { effects: true, events: true } });
  if (!succeeded(result)) throw new Error("Keeper transaction did not report success");
  return { digest: result.digest ?? result.transaction?.digest ?? result.Transaction?.digest ?? null, effects: result.effects ?? result.transaction?.effects ?? result.Transaction?.effects };
}

const [state, treasuryState] = await Promise.all([moveFields(mainnet.emissionState), moveFields(treasury.routeTreasuryState)]);
const now = Math.floor(Date.now() / 1000);
const elapsedSlots = Math.max(0, Math.floor((now - Number(state.last_slot_ts)) / SLOT_SECONDS));
const pending = Number(state.pending_blocks) + elapsedSlots;
const eligibleBlocks = Math.min(pending, Math.floor(Number(state.batch_trades) / ROUTES_PER_BLOCK), policy.settlement.maximumBlocksPerRun);
const syncNeeded = Number(treasuryState.next_height) < Number(state.block_height);
const report = {
  mode: EXECUTE ? "execute" : "dry-run",
  keeper: policy.keeperAddress,
  settlement: { eligibleBlocks, routeReceipts: Number(state.batch_trades), pendingBlocksAfterTimeAdvance: pending },
  treasurySync: { needed: syncNeeded, nextHeight: String(treasuryState.next_height), blockHeight: String(state.block_height) },
  privilegedExecutors: policy.privilegedExecutors,
  submitted: [],
};

if (!EXECUTE) {
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

const signer = keeperSigner();
const client = new SuiGrpcClient({ network: "mainnet", baseUrl: "https://fullnode.mainnet.sui.io:443" });
if (eligibleBlocks > 0 && policy.settlement.enabled) {
  const tx = new Transaction();
  tx.setSender(policy.keeperAddress);
  tx.setGasBudget(BigInt(policy.settlement.gasBudgetMist));
  tx.moveCall({ target: `${PACKAGE}::bten::settle_and_distribute`, arguments: [tx.object(mainnet.emissionState), tx.object(distribution.distributionState), tx.object(CLOCK)] });
  report.submitted.push({ action: "settle_and_distribute", ...(await execute(client, signer, tx)) });
}
if (policy.treasurySync.enabled) {
  const refreshed = await moveFields(mainnet.emissionState);
  const refreshedTreasury = await moveFields(treasury.routeTreasuryState);
  if (Number(refreshedTreasury.next_height) < Number(refreshed.block_height)) {
    const tx = new Transaction();
    tx.setSender(policy.keeperAddress);
    tx.setGasBudget(BigInt(policy.settlement.gasBudgetMist));
    tx.moveCall({ target: `${PACKAGE}::bten::sync_route_treasury`, arguments: [tx.object(mainnet.emissionState), tx.object(treasury.routeTreasuryState)] });
    report.submitted.push({ action: "sync_route_treasury", ...(await execute(client, signer, tx)) });
  }
}
console.log(JSON.stringify(report, null, 2));
