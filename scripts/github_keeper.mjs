#!/usr/bin/env node
/**
 * GitHub Actions keeper for permissionless BTEN maintenance.
 *
 * `--execute` is deliberately limited to settlement, accounting, LP accrual,
 * and permissionless native-farm reward syncing. It never swaps, controls an
 * upgrade, withdraws user stake, or holds a farm/sponsor administrator cap.
 *
 * Bitcoin-style ~10-minute cadence: advance_slots creates pending every 600s;
 * each settle releases at most one block (MAX_SETTLE_BLOCKS=1). On-chain still
 * settles one block per call; execute mode loops settle_and_distribute (re-reading
 * emission state) until pending work is cleared or maximumSettleCallsPerRun is hit,
 * so Actions cron lag can catch up without a Move change. Trades still accrue
 * trader rewards when present; they do not gate unlock.
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
const EXECUTE = process.argv.includes("--execute");
const GRAPHQL = "https://graphql.mainnet.sui.io/graphql";
const PACKAGE = mainnet.currentPackage;
const CLOCK = "0x6";
const SLOT_SECONDS = 600;
const MAX_SETTLE_BLOCKS = 1; // matches on-chain MAX_SETTLE_BLOCKS — Bitcoin-style one block per settle
const LP_VAULT_FIELDS = ["bten_lp_vault", "cetus_vault", "haedal_vault", "blue_vault", "magma_vault", "sui_gas_vault"];
const MAX_SETTLE_CALLS = Math.max(1, Number(policy.settlement?.maximumSettleCallsPerRun ?? 30));

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

function pendingWork(state, now = Math.floor(Date.now() / 1000)) {
  const elapsedSlots = Math.max(0, Math.floor((now - Number(state.last_slot_ts)) / SLOT_SECONDS));
  const pendingBlocks = Number(state.pending_blocks);
  return {
    pendingBlocks,
    elapsedSlots,
    pendingEffective: pendingBlocks + elapsedSlots,
  };
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

function balanceValue(value) {
  if (typeof value === "bigint" || typeof value === "number" || typeof value === "string") return BigInt(value);
  return BigInt(value?.value ?? 0);
}

async function execute(client, signer, transaction) {
  const result = await client.signAndExecuteTransaction({ signer, transaction, include: { effects: true, events: true } });
  if (!succeeded(result)) throw new Error("Keeper transaction did not report success");
  return { digest: result.digest ?? result.transaction?.digest ?? result.Transaction?.digest ?? null, effects: result.effects ?? result.transaction?.effects ?? result.Transaction?.effects };
}

const [state, treasuryState, farmState] = await Promise.all([
  moveFields(mainnet.emissionState),
  moveFields(policy.routeTreasuryState),
  policy.nativeFarmSync?.enabled && policy.nativeFarmSync?.state ? moveFields(policy.nativeFarmSync.state) : Promise.resolve(null),
]);
const initialPending = pendingWork(state);
const eligibleBlocks = Math.min(initialPending.pendingEffective, MAX_SETTLE_BLOCKS, policy.settlement.maximumBlocksPerRun);
const syncNeeded = Number(treasuryState.next_height) < Number(state.block_height);
const report = {
  mode: EXECUTE ? "execute" : "dry-run",
  keeper: policy.keeperAddress,
  livePackageId: policy.livePackageId ?? PACKAGE,
  livePackageVersion: policy.livePackageVersion ?? null,
  settlement: {
    enabled: Boolean(policy.settlement?.enabled),
    eligibleBlocks,
    maximumBlocksPerRun: policy.settlement.maximumBlocksPerRun,
    maximumSettleCallsPerRun: MAX_SETTLE_CALLS,
    routeReceipts: Number(state.batch_trades),
    pendingBlocks: initialPending.pendingBlocks,
    elapsedSlots: initialPending.elapsedSlots,
    pendingBlocksAfterTimeAdvance: initialPending.pendingEffective,
  },
  treasurySync: { needed: syncNeeded, nextHeight: String(treasuryState.next_height), blockHeight: String(state.block_height) },
  lpProgrammeAccrual: {
    enabled: Boolean(policy.lpProgrammeAccrual?.enabled),
    configured: Boolean(policy.lpProgrammeAccrual?.state),
    availableRaw: LP_VAULT_FIELDS.reduce((total, field) => total + balanceValue(state[field]), 0n).toString(),
  },
  nativeFarmSync: {
    enabled: Boolean(policy.nativeFarmSync?.enabled),
    configured: Boolean(policy.nativeFarmSync?.state),
    needed: Boolean(farmState?.started) && Number(farmState.next_height) < Number(state.block_height),
    started: Boolean(farmState?.started),
    nextHeight: farmState ? String(farmState.next_height) : null,
    blockHeight: String(state.block_height),
  },
  privilegedExecutors: policy.privilegedExecutors,
  submitted: [],
};

if (!EXECUTE) {
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

const signer = keeperSigner();
const client = new SuiGrpcClient({ network: "mainnet", baseUrl: "https://fullnode.mainnet.sui.io:443" });
if (policy.settlement.enabled) {
  let settleCalls = 0;
  let lastState = state;
  while (settleCalls < MAX_SETTLE_CALLS) {
    const current = settleCalls === 0 ? lastState : await moveFields(mainnet.emissionState);
    lastState = current;
    const work = pendingWork(current);
    // Catch up while time/pending work remains. On-chain still MAX_SETTLE_BLOCKS=1 per call.
    if (work.pendingEffective <= 0) break;
    const tx = new Transaction();
    tx.setSender(policy.keeperAddress);
    tx.setGasBudget(BigInt(policy.settlement.gasBudgetMist));
    tx.moveCall({ target: `${PACKAGE}::bten::settle_and_distribute`, arguments: [tx.object(mainnet.emissionState), tx.object(policy.distributionState), tx.object(CLOCK)] });
    const submitted = await execute(client, signer, tx);
    settleCalls += 1;
    report.submitted.push({
      action: "settle_and_distribute",
      call: settleCalls,
      pendingBlocksBefore: work.pendingBlocks,
      elapsedSlotsBefore: work.elapsedSlots,
      ...submitted,
    });
  }
  report.settlement.settleCallsSubmitted = settleCalls;
  report.settlement.stoppedReason = settleCalls >= MAX_SETTLE_CALLS
    ? "maximumSettleCallsPerRun"
    : "pending_blocks==0";
  const finalState = await moveFields(mainnet.emissionState);
  const finalWork = pendingWork(finalState);
  report.settlement.pendingBlocksAfter = finalWork.pendingBlocks;
  report.settlement.elapsedSlotsAfter = finalWork.elapsedSlots;
  report.settlement.blockHeightAfter = String(finalState.block_height);
}
if (policy.treasurySync.enabled) {
  const refreshed = await moveFields(mainnet.emissionState);
  const refreshedTreasury = await moveFields(policy.routeTreasuryState);
  if (Number(refreshedTreasury.next_height) < Number(refreshed.block_height)) {
    const tx = new Transaction();
    tx.setSender(policy.keeperAddress);
    tx.setGasBudget(BigInt(policy.settlement.gasBudgetMist));
    tx.moveCall({ target: `${PACKAGE}::bten::sync_route_treasury`, arguments: [tx.object(mainnet.emissionState), tx.object(policy.routeTreasuryState)] });
    report.submitted.push({ action: "sync_route_treasury", ...(await execute(client, signer, tx)) });
  }
}
if (policy.lpProgrammeAccrual?.enabled && policy.lpProgrammeAccrual?.state) {
  const refreshed = await moveFields(mainnet.emissionState);
  const available = LP_VAULT_FIELDS.reduce((total, field) => total + balanceValue(refreshed[field]), 0n);
  if (available > 0n) {
    const tx = new Transaction();
    tx.setSender(policy.keeperAddress);
    tx.setGasBudget(BigInt(policy.settlement.gasBudgetMist));
    tx.moveCall({ target: `${PACKAGE}::bten::accrue_lp_program`, arguments: [tx.object(mainnet.emissionState), tx.object(policy.lpProgrammeAccrual.state)] });
    report.submitted.push({ action: "accrue_lp_program", ...(await execute(client, signer, tx)) });
  }
}
if (policy.nativeFarmSync?.enabled && policy.nativeFarmSync?.state) {
  const refreshedState = await moveFields(mainnet.emissionState);
  const refreshedFarm = await moveFields(policy.nativeFarmSync.state);
  if (Boolean(refreshedFarm.started) && Number(refreshedFarm.next_height) < Number(refreshedState.block_height)) {
    const tx = new Transaction();
    tx.setSender(policy.keeperAddress);
    tx.setGasBudget(BigInt(policy.settlement.gasBudgetMist));
    tx.moveCall({ target: `${PACKAGE}::bten::sync_bten_staking_farm_rewards`, arguments: [tx.object(mainnet.emissionState), tx.object(policy.nativeFarmSync.state)] });
    report.submitted.push({ action: "sync_bten_staking_farm_rewards", ...(await execute(client, signer, tx)) });
  }
}
console.log(JSON.stringify(report, null, 2));
