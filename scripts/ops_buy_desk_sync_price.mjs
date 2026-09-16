#!/usr/bin/env node
/**
 * OpsBuyDesk price keeper — posts mist SUI per BTEN implied by the WAL home book.
 *
 * Source (no discount):
 *   1) Cetus Pool<WAL,BTEN>  (home book)
 *   2) Cetus Pool<WAL,SUI>   (WAL leg → SUI)
 *
 * mist_sui_per_full_bten = UNIT * sqrt_wal_sui^2 / sqrt_wal_bten^2
 * (Cetus Q64.64: coin_b/coin_a = sqrt^2/2^128; 2^128 cancels across the two pools.)
 *
 * Calls `ops_buy_desk::set_price_mist_sui_per_bten` as `price_updater`.
 * Dapp should prefer `buy_with_sui_posted_price` (no on-chain BTEN/SUI pool read).
 * Cetus BTEN/SUI pool is left OPEN — optional/legacy display only; do not unregister.
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
const UNIT = 100_000_000n; // 1 full BTEN in mist (8 decimals)

const WAL_BTEN_POOL =
  cfg.cetusBtenWalPool ||
  "0xa9f12a204ac1cb778c015e77a88fc8eb5926599ece17b2a8841753c7712544c7";
const WAL_SUI_POOL =
  cfg.cetusWalSuiPool ||
  "0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17";
const LEGACY_BTEN_SUI_POOL =
  cfg.cetusBtenSuiPool ||
  "0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950";

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

async function readPool(poolId, { expectA, expectB, label }) {
  const data = await gql(
    `query($address: SuiAddress!) {
      object(address: $address) {
        asMoveObject { contents { type { repr } json } }
      }
    }`,
    { address: poolId },
  );
  const contents = data?.object?.asMoveObject?.contents;
  if (!contents?.json) throw new Error(`Pool ${poolId} (${label}) unavailable`);
  const typeRepr = contents.type?.repr ?? "";
  if (!typeRepr.includes("::pool::Pool")) {
    throw new Error(`Unexpected pool type for ${label}: ${typeRepr}`);
  }
  const lower = typeRepr.toLowerCase();
  for (const needle of [expectA, expectB]) {
    if (!lower.includes(needle.toLowerCase())) {
      throw new Error(`${label} type missing ${needle}: ${typeRepr}`);
    }
  }
  // Enforce coin order: Pool<A,B>
  const m = typeRepr.match(/Pool<([^,]+),\s*([^>]+)>/);
  if (!m) throw new Error(`${label}: cannot parse Pool type params: ${typeRepr}`);
  const coinA = m[1].trim();
  const coinB = m[2].trim();
  if (!coinA.toLowerCase().includes(expectA.toLowerCase()) || !coinB.toLowerCase().includes(expectB.toLowerCase())) {
    throw new Error(
      `${label}: expected Pool<…${expectA}…, …${expectB}…> got Pool<${coinA}, ${coinB}>`,
    );
  }
  const sqrt = BigInt(contents.json.current_sqrt_price);
  if (sqrt <= 0n) throw new Error(`${label}: current_sqrt_price is zero`);
  return { sqrt, typeRepr, coinA, coinB };
}

/** mist SUI per 1 full BTEN from Pool<WAL,BTEN> + Pool<WAL,SUI> */
function priceMistSuiPerBtenFromWal(sqrtWalBten, sqrtWalSui) {
  // UNIT * sqrt_ws^2 / sqrt_wb^2
  const num = UNIT * sqrtWalSui * sqrtWalSui;
  const den = sqrtWalBten * sqrtWalBten;
  const price = num / den;
  if (price <= 0n) throw new Error("computed WAL-implied mid price is zero");
  if (price > 0xffffffffffffffffn) throw new Error("computed WAL-implied mid price overflows u64");
  return price;
}

/** Legacy comparator: mist SUI per 1 full BTEN from Pool<BTEN,SUI> mid */
function priceMistSuiPerBtenFromSqrtBtenSui(sqrt) {
  const sq = sqrt * sqrt;
  const price = (sq * UNIT) >> 128n;
  if (price <= 0n) return null;
  if (price > 0xffffffffffffffffn) return null;
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

const walBten = await readPool(WAL_BTEN_POOL, {
  expectA: "::wal::WAL",
  expectB: "::bten::BTEN",
  label: "WAL/BTEN",
});
const walSui = await readPool(WAL_SUI_POOL, {
  expectA: "::wal::WAL",
  expectB: "::sui::SUI",
  label: "WAL/SUI",
});

const mid = priceMistSuiPerBtenFromWal(walBten.sqrt, walSui.sqrt);
const humanSuiPerBten = Number(mid) / 1e9;

let legacyMid = null;
let legacyHuman = null;
try {
  const legacy = await readPool(LEGACY_BTEN_SUI_POOL, {
    expectA: "::bten::BTEN",
    expectB: "::sui::SUI",
    label: "BTEN/SUI-legacy",
  });
  legacyMid = priceMistSuiPerBtenFromSqrtBtenSui(legacy.sqrt);
  if (legacyMid != null) legacyHuman = Number(legacyMid) / 1e9;
} catch (err) {
  // Pool stays open; comparator is best-effort only.
  legacyMid = null;
  legacyHuman = null;
}

const report = {
  network: cfg.network,
  pricingMode: "wal-implied-bten",
  homeBook: {
    pool: WAL_BTEN_POOL,
    type: walBten.typeRepr,
    currentSqrtPrice: walBten.sqrt.toString(),
  },
  walSuiLeg: {
    pool: WAL_SUI_POOL,
    type: walSui.typeRepr,
    currentSqrtPrice: walSui.sqrt.toString(),
  },
  priceMistSuiPerBten: mid.toString(),
  humanSuiPerBten,
  legacyBtenSuiPool: {
    pool: LEGACY_BTEN_SUI_POOL,
    note: "Optional/legacy display only — pool left OPEN; not used for desk pricing",
    priceMistSuiPerBten: legacyMid != null ? legacyMid.toString() : null,
    humanSuiPerBten: legacyHuman,
  },
  discountBps: 0,
  note: "Posted price = WAL-implied mid (BTEN/WAL home book × WAL/SUI). No discount. Prefer buy_with_sui_posted_price.",
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
  throw new Error("packageId not set — update config/ops_buy_desk.json");
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
