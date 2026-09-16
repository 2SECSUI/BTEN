#!/usr/bin/env node
/**
 * DRY-RUN ONLY — Bandbot harvest → WAL→BTEN sink → settle-when-ready planner.
 *
 * - Read-only eligibility checks (GraphQL)
 * - Prints recommended PTB steps + object IDs
 * - Optional Cetus quote for WAL→BTEN (no sign / no broadcast)
 * - NEVER executes, NEVER reads keystore, NEVER embeds keys
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");

if (process.argv.includes("--execute") || process.argv.includes("--sign")) {
  console.error("REFUSED: this script is dry-run only (no execute / no spend)");
  process.exit(2);
}

const cfg = JSON.parse(
  fs.readFileSync(path.join(root, "config", "bandbot_bten_integration.json"), "utf8"),
);
const mainnet = JSON.parse(fs.readFileSync(path.join(root, "MAINNET_ROUTE_CONFIG.json"), "utf8"));

const GRAPHQL = "https://graphql.mainnet.sui.io/graphql";
const PACKAGE = cfg.livePackageId || mainnet.currentPackage;
const EMISSION = cfg.objects.emissionState;
const DISTRIBUTION = cfg.objects.distributionState;
const REGISTRY = cfg.objects.poolRegistry;
const CETUS_CFG = cfg.objects.cetusGlobalConfig;
const CLOCK = cfg.objects.clock;
const BTEN_WAL = cfg.objects.btenWalPool;
const WAL_SUI = cfg.objects.walSuiPool;
const WAL = cfg.coinTypes.WAL;
const BTEN = cfg.coinTypes.BTEN;
const SUI = cfg.coinTypes.SUI;
const MIN_TRADES = Number(cfg.settleEligibility?.minTradesPerBlock ?? 10);
const MAX_SETTLE = Number(cfg.settleEligibility?.maxSettleBlocks ?? 100);
const MIN_SQRT = "4295048016";
const MAX_SQRT = "79226673515401279992447579055";

const walRaw = BigInt(
  process.argv.includes("--wal-raw")
    ? process.argv[process.argv.indexOf("--wal-raw") + 1]
    : "1000000",
);
const suiRaw = BigInt(
  process.argv.includes("--sui-raw")
    ? process.argv[process.argv.indexOf("--sui-raw") + 1]
    : "0",
);

async function moveFields(address) {
  const query = `query($address: SuiAddress!) { object(address: $address) { asMoveObject { contents { json } } version } }`;
  const response = await fetch(GRAPHQL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, variables: { address } }),
  });
  if (!response.ok) throw new Error(`GraphQL object read failed: ${response.status}`);
  const body = await response.json();
  if (body.errors?.length || !body.data?.object?.asMoveObject?.contents?.json) {
    throw new Error(`Object ${address} unavailable: ${JSON.stringify(body.errors || body)}`);
  }
  return {
    ...body.data.object.asMoveObject.contents.json,
    _version: body.data.object.version,
  };
}

function eligibility(state) {
  const pending = Number(state.pending_blocks ?? 0);
  const batch = Number(state.batch_trades ?? 0);
  const afterOne = batch + 1;
  const tradeSupportedNow = Math.floor(batch / MIN_TRADES);
  const tradeSupportedAfter = Math.floor(afterOne / MIN_TRADES);
  const eligibleNow = Math.min(pending, tradeSupportedNow, MAX_SETTLE);
  const eligibleAfterOneReceipt = Math.min(pending, tradeSupportedAfter, MAX_SETTLE);
  const settleWhenReady =
    pending >= 1 && afterOne >= MIN_TRADES;
  return {
    pending_blocks: pending,
    batch_trades: batch,
    batch_trades_after_this_route: afterOne,
    minTradesPerBlock: MIN_TRADES,
    maxSettleBlocks: MAX_SETTLE,
    eligible_blocks_now: eligibleNow,
    eligible_blocks_after_one_receipt: eligibleAfterOneReceipt,
    settleWhenReadyRule: "pending_blocks>=1 && (batch_trades+1)>=10",
    recommendSettleInSamePtb: settleWhenReady,
    doNotSettleIfNotEligible: true,
  };
}

function recommendedPtb({ includeSuiToWal, includeSettle, walToBtenFn, minBtenOut, sqrtLimit }) {
  const steps = [];
  if (includeSuiToWal) {
    steps.push({
      step: 1,
      target: `${PACKAGE}::bten::cetus_swap_registered_b2a`,
      altRebate: `${PACKAGE}::bten::cetus_swap_registered_b2a_rebate`,
      typeArguments: [WAL, SUI],
      arguments: [
        "EmissionState",
        "PoolRegistry",
        "Cetus GlobalConfig",
        "WAL/SUI Pool",
        "Coin<SUI>",
        "min_wal_out",
        "sqrt_price_limit (MAX for b2a)",
        "Clock 0x6",
      ],
      objects: {
        emissionState: EMISSION,
        poolRegistry: REGISTRY,
        cetusGlobalConfig: CETUS_CFG,
        pool: WAL_SUI,
        clock: CLOCK,
      },
      note: "Optional: SUI→WAL on Pool<WAL,SUI> (SUI is B).",
    });
  }
  steps.push({
    step: includeSuiToWal ? 2 : 1,
    target: `${PACKAGE}::bten::${walToBtenFn}`,
    typeArguments: [WAL],
    arguments: [
      "EmissionState",
      "PoolRegistry",
      "Cetus GlobalConfig",
      "BTEN/WAL Pool",
      "Coin<WAL>",
      `min_bten_out=${minBtenOut ?? "<quote>"}`,
      `sqrt_price_limit=${sqrtLimit ?? MIN_SQRT}`,
      "Clock 0x6",
    ],
    objects: {
      emissionState: EMISSION,
      poolRegistry: REGISTRY,
      cetusGlobalConfig: CETUS_CFG,
      pool: BTEN_WAL,
      clock: CLOCK,
    },
    note: "Required: WAL→BTEN on Pool<WAL,BTEN> only — never BTEN/SUI as purchase leg.",
  });
  steps.push({
    step: includeSuiToWal ? 3 : 2,
    action: "Cetus addLiquidity",
    pool: BTEN_WAL,
    coinTypes: { a: WAL, b: BTEN },
    note: "Sink remaining WAL + BTEN into BTEN/WAL. Do not open side BTEN LPs.",
  });
  if (includeSettle) {
    steps.push({
      step: includeSuiToWal ? 4 : 3,
      target: `${PACKAGE}::bten::settle_and_distribute`,
      arguments: ["EmissionState", "DistributionState", "Clock 0x6"],
      objects: {
        emissionState: EMISSION,
        distributionState: DISTRIBUTION,
        clock: CLOCK,
      },
      note: "Only because eligibility says settleWhenReady. Skip if not eligible.",
    });
  } else {
    steps.push({
      step: includeSuiToWal ? 4 : 3,
      target: `${PACKAGE}::bten::settle_and_distribute`,
      skipped: true,
      reason: "Not eligible (need pending_blocks>=1 && batch_trades+1>=10). Do not call.",
    });
  }
  return steps;
}

async function maybeQuoteWalToBten(amount) {
  if (amount <= 0n) {
    return { skipped: true, reason: "wal-raw <= 0" };
  }
  try {
    const { CetusClmmSDK } = await import("@cetusprotocol/sui-clmm-sdk");
    const { SuiGrpcClient } = await import("@mysten/sui/grpc");
    const client = new SuiGrpcClient({
      network: "mainnet",
      baseUrl: "https://fullnode.mainnet.sui.io:443",
    });
    const sdk = CetusClmmSDK.createSDK({ env: "mainnet" });
    const [pool, meta] = await Promise.all([
      sdk.Pool.getPool(BTEN_WAL, true),
      client.getCoinMetadata({ coinType: WAL }),
    ]);
    const partnerIsA = pool.coin_type_a.toLowerCase() === WAL.toLowerCase();
    const decimalsPartner = Number(meta.decimals);
    const quote = await sdk.Swap.preSwap({
      pool,
      current_sqrt_price: Number(pool.current_sqrt_price),
      decimals_a: partnerIsA ? decimalsPartner : 8,
      decimals_b: partnerIsA ? 8 : decimalsPartner,
      a2b: partnerIsA,
      by_amount_in: true,
      amount: amount.toString(),
      coin_type_a: pool.coin_type_a,
      coin_type_b: pool.coin_type_b,
    });
    const out = BigInt(quote.estimated_amount_out ?? 0);
    if (out <= 0n || quote.is_exceed) {
      return {
        ok: false,
        poolCoinOrder: { a: pool.coin_type_a, b: pool.coin_type_b, partnerIsA },
        quote,
      };
    }
    const min = (out * 99n) / 100n;
    const fn = partnerIsA ? "cetus_swap_to_bten" : "cetus_swap_to_bten_b2a";
    const sqrt = partnerIsA ? MIN_SQRT : MAX_SQRT;
    return {
      ok: true,
      poolCoinOrder: { a: pool.coin_type_a, b: pool.coin_type_b, partnerIsA },
      walDecimals: decimalsPartner,
      inputWalRaw: amount.toString(),
      estimatedBtenRaw: out.toString(),
      minBtenOut: min.toString(),
      function: fn,
      sqrtPriceLimit: sqrt,
      note: "Quote only — not simulated, not executed",
    };
  } catch (err) {
    return {
      ok: false,
      error: String(err?.message ?? err),
      fallbackFunction: "cetus_swap_to_bten",
      note: "Quote failed; PTB still printed with default adapter name",
    };
  }
}

const emission = await moveFields(EMISSION);
const elig = eligibility(emission);
const quote = await maybeQuoteWalToBten(walRaw);
const walFn = quote.function || "cetus_swap_to_bten";
const includeSui = suiRaw > 0n;
const steps = recommendedPtb({
  includeSuiToWal: includeSui,
  includeSettle: elig.recommendSettleInSamePtb,
  walToBtenFn: walFn,
  minBtenOut: quote.minBtenOut,
  sqrtLimit: quote.sqrtPriceLimit,
});

const report = {
  mode: "dry-run-only",
  spent: false,
  signed: false,
  executed: false,
  package: PACKAGE,
  packageVersion: cfg.livePackageVersion ?? 28,
  inputs: {
    walRaw: walRaw.toString(),
    suiRaw: suiRaw.toString(),
    includeOptionalSuiToWal: includeSui,
  },
  objects: cfg.objects,
  coinTypes: cfg.coinTypes,
  emissionSnapshot: {
    block_height: emission.block_height,
    pending_blocks: emission.pending_blocks,
    batch_trades: emission.batch_trades,
    last_slot_ts: emission.last_slot_ts,
    _version: emission._version,
  },
  eligibility: elig,
  walToBtenQuote: quote,
  recommendedPtb: steps,
  gasBudgetMistSuggested: cfg.safety?.gasBudgetMistSuggested ?? "80000000",
  safety: {
    nonCustodial: true,
    neverEmbedPrivateKeys: true,
    neverUnregisterBtenSui: true,
    neverOpenSideBtenLps: true,
    doNotSettleIfNotEligible: true,
    note: "This script only reads chain state and prints a plan. No keystore, no PTB broadcast.",
  },
  docs: {
    bandbot: "docs/BANDBOT_BTEN_INTEGRATION.md",
    buyViaWal: "docs/BUY_VIA_WAL.md",
    config: "config/bandbot_bten_integration.json",
  },
  at: new Date().toISOString(),
};

console.log(JSON.stringify(report, null, 2));
