#!/usr/bin/env node
/**
 * OpsBuyDesk price keeper — sets posted mid equal to the Cetus BTEN/SUI pool mid.
 *
 * NO discount (−0%). Reads current_sqrt_price from the configured pool and calls
 * `ops_buy_desk::set_price_mist_sui_per_bten` as `price_updater`.
 *
 * Usage:
 *   node scripts/ops_buy_desk_sync_price.mjs            # dry-run (print mid)
 *   node scripts/ops_buy_desk_sync_price.mjs --execute  # submit set_price tx
 *
 * Requires BTEN_OPS_BUY_DESK_UPDATER_KEY (suiprivkey / base64) matching
 * config/ops_buy_desk.json#priceUpdater when --execute is set.
 * neverEmbedPrivateKeys — key from env only.
 */
import fs from "node:fs";
import path from "node:path";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";

const root = path.resolve(import.meta.dirname, "..");
const cfg = JSON.parse(fs.readFileSync(path.join(root, "config", "ops_buy_desk.json"), "utf8"));
const EXECUTE = process.argv.includes("--execute");
const GRAPHQL = "https://graphql.mainnet.sui.io/graphql";
const CLOCK = "0x6";
const UNIT = 100_000_000n;

async function gql(query, variables = {}) {
  const response = await fetch(GRAPHQL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });
  if (!response.ok) throw new Error(`GraphQL HTTP ${response.status}`);
  const body = await response.json();
  if (body.errors?.length) throw new Error(JSON.stringify(body.errors));
  return body.data;
}

async function readPoolSqrtPrice(poolId) {
  const data = await gql(
    `query($address: SuiAddress!) {
      object(address: $address) {
        asMoveObject { contents { type { repr } json } }
      }
    }`,
    { address: poolId },
  );
  const contents = data?.object?.asMoveObject?.contents;
  if (!contents?.json) throw new Error(`Pool ${poolId} unavailable`);
  const typeRepr = contents.type?.repr ?? "";
  if (!typeRepr.includes("::pool::Pool") || !typeRepr.includes("::bten::BTEN") || !typeRepr.includes("::sui::SUI")) {
    throw new Error(`Unexpected pool type: ${typeRepr}`);
  }
  const sqrt = BigInt(contents.json.current_sqrt_price);
  if (sqrt <= 0n) throw new Error("current_sqrt_price is zero");
  return sqrt;
}

/** mist SUI per 1 full BTEN = sqrt^2 * UNIT / 2^128 */
function priceMistSuiPerBtenFromSqrt(sqrt) {
  const sq = sqrt * sqrt;
  const price = (sq * UNIT) >> 128n;
  if (price <= 0n) throw new Error("computed mid price is zero");
  if (price > 0xffffffffffffffffn) throw new Error("computed mid price overflows u64");
  return price;
}

function updaterSigner() {
  const encoded = process.env.BTEN_OPS_BUY_DESK_UPDATER_KEY;
  if (!encoded) throw new Error("BTEN_OPS_BUY_DESK_UPDATER_KEY required for --execute");
  const secret = encoded.startsWith("suiprivkey")
    ? decodeSuiPrivateKey(encoded).secretKey
    : Uint8Array.from(Buffer.from(encoded, "base64")).slice(1);
  const signer = Ed25519Keypair.fromSecretKey(secret);
  if (signer.toSuiAddress().toLowerCase() !== String(cfg.priceUpdater).toLowerCase()) {
    throw new Error("Updater key address does not match config/ops_buy_desk.json#priceUpdater");
  }
  return signer;
}

function resolvePackage() {
  return cfg.packageId || cfg.livePackageId || null;
}

const sqrt = await readPoolSqrtPrice(cfg.cetusBtenSuiPool);
const mid = priceMistSuiPerBtenFromSqrt(sqrt);
const humanSuiPerBten = Number(mid) / 1e9;

const report = {
  network: cfg.network,
  pool: cfg.cetusBtenSuiPool,
  currentSqrtPrice: sqrt.toString(),
  priceMistSuiPerBten: mid.toString(),
  humanSuiPerBten,
  discountBps: 0,
  note: "Posted price MUST equal Cetus mid — no −2% or other discount",
  deskObjectId: cfg.deskObjectId ?? null,
  packageId: resolvePackage(),
  execute: EXECUTE,
};

if (!EXECUTE) {
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

if (!cfg.deskObjectId) throw new Error("config/ops_buy_desk.json#deskObjectId missing — create desk first");
const packageId = resolvePackage();
if (!packageId || packageId.includes("PENDING")) {
  throw new Error("packageId not set — upgrade to v23 and update config/ops_buy_desk.json");
}

const signer = updaterSigner();
const client = await SuiGrpcClient.mainnet();
const tx = new Transaction();
tx.moveCall({
  target: `${packageId}::ops_buy_desk::set_price_mist_sui_per_bten`,
  arguments: [
    tx.object(cfg.deskObjectId),
    tx.pure.u64(mid.toString()),
    tx.object(CLOCK),
  ],
});
tx.setGasBudget(cfg.keeper?.gasBudgetMist ? Number(cfg.keeper.gasBudgetMist) : 20_000_000);

const result = await client.signAndExecuteTransaction({
  signer,
  transaction: tx,
  include: { effects: true, events: true },
});
const effects = result.effects ?? result.transaction?.effects;
const ok = effects?.status?.status === "success" || effects?.status?.success === true;
if (!ok) throw new Error(`set_price failed: ${JSON.stringify(effects?.status)}`);

report.digest = result.digest ?? result.transaction?.digest ?? null;
console.log(JSON.stringify(report, null, 2));
