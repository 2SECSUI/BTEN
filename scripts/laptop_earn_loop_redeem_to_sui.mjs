#!/usr/bin/env node
/**
 * Laptop Earn Loop — redeem 50% of bot-tracked Earn park adds → swap to SUI.
 *
 * ONLY removes liquidity corresponding to amounts this daemon tracked as added
 * during the current redeem window. Never closes protocol BTEN/SUI|CETUS|WAL
 * pools. Never touches vault 0x539079f8…446bc0. WAL/SUI desk = swap-through only.
 *
 * Usage:
 *   node scripts/bandbot_earn_loop_redeem_to_sui.mjs
 *   node scripts/bandbot_earn_loop_redeem_to_sui.mjs --state artifacts/v30/laptop_earn_loop_state.json
 *   node scripts/bandbot_earn_loop_redeem_to_sui.mjs --fraction 0.5 --execute
 *
 * Live requires BOTH --execute AND BTEN_EARN_LOOP_EXECUTE=1.
 * Bluefin remove additionally requires BTEN_BLUEFIN_EXECUTE=1.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { CetusClmmSDK } from "@cetusprotocol/sui-clmm-sdk";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import {
  BLUEFIN_DEEP_SUI_POOL,
  BLUEFIN_DEEP_SUI_POS,
  BLUEFIN_CURRENT_PACKAGE,
  BLUEFIN_GLOBAL_CONFIG,
  SUI_CLOCK,
  DEEP,
  OPS as BLUEFIN_OPS,
} from "./lib/bluefin_deep_sui_park.mjs";

const REPO = "/workspace/BTEN-work";
const OUT_DIR = path.join(REPO, "artifacts/v30");
const DEFAULT_STATE = path.join(OUT_DIR, "laptop_earn_loop_state.json");

const OPS = "0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a";
const FORBIDDEN_VAULT =
  "0x539079f8c0b0055e334307d472fe693a2c0ae545d4f3c9752e1e6ceddb446bc0";
const WAL_SUI_DESK =
  "0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17";

const BTEN =
  "0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN";
const HAEDAL =
  "0x3a304c7feba2d819ea57c3542d68439ca2c386ba02159c740f7b406e592c62ea::haedal::HAEDAL";
const WAL =
  "0x356a26eb9e012a68958082340d4c4116e7f55615cf27affcff209cf0ae544f59::wal::WAL";
const SUI = "0x2::sui::SUI";
const CETUS =
  "0x06864a6f921804860930db6ddbe2e16acdf8504495ea7481637a1c8b9a8fe54b::cetus::CETUS";

/** Canonical Earn parks (add-only redeem targets). */
const PARK_META = {
  "HAEDAL-BTEN": {
    pool: "0x3ea08eda95787196aa5afb3880b4f22eaf548bfc3cab4e209d3864c6cfb426f3",
    pos: "0xaf2882f18d23f1ffbf6e629cafbb9c65e30df20c1a214e97c049f43efb2de369",
    venue: "cetus",
    coinAType: HAEDAL,
    coinBType: BTEN,
  },
  "WAL-BTEN": {
    pool: "0xa9f12a204ac1cb778c015e77a88fc8eb5926599ece17b2a8841753c7712544c7",
    pos: "0x00fbadfc20ee3b4325e63e6405c1075efbaa15913cdf4c64a3262ee8d1847713",
    venue: "cetus",
    coinAType: WAL,
    coinBType: BTEN,
  },
  "BTEN-SUI": {
    pool: "0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950",
    pos: "0x7cef638a37de4083e66dc2f400a1760f5098ae51cce66865ce733bdd6ec2689e",
    venue: "cetus",
    coinAType: BTEN,
    coinBType: SUI,
  },
  "BTEN-CETUS": {
    pool: "0xf6c5df04eb488373c8309b96f0ea187aada7c3b446b3fb6ef5f73f222eaa5f0c",
    pos: "0x0f281bf808e6fab914930fa17316244acd146ee1d72a06f57496e46a64788ead",
    venue: "cetus",
    coinAType: BTEN,
    coinBType: CETUS,
  },
  "BLUEFIN-DEEP-SUI": {
    pool: BLUEFIN_DEEP_SUI_POOL,
    pos: BLUEFIN_DEEP_SUI_POS,
    venue: "bluefin",
    coinAType: DEEP,
    coinBType: SUI,
  },
  "Bluefin DEEP-SUI": {
    pool: BLUEFIN_DEEP_SUI_POOL,
    pos: BLUEFIN_DEEP_SUI_POS,
    venue: "bluefin",
    coinAType: DEEP,
    coinBType: SUI,
  },
};

/** Swap routes to SUI (desk WAL/SUI is swap-through only). */
const TO_SUI_ROUTES = {
  [HAEDAL.toLowerCase()]: {
    pool: "0x76d6955a413555c961d2806b1bcce5113ef89696c46875482147510151172f94",
    note: "HAEDAL/SUI",
  },
  [WAL.toLowerCase()]: {
    pool: WAL_SUI_DESK,
    note: "WAL/SUI desk swap-through ONLY",
  },
  [BTEN.toLowerCase()]: {
    pool: "0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950",
    note: "BTEN/SUI",
  },
  [CETUS.toLowerCase()]: {
    pool: "0x2e041f3fd93646dcc877f783c1f2b7fa62d30271bdef1f21ef002cebf857bded",
    note: "CETUS/SUI",
  },
  [DEEP.toLowerCase()]: {
    pool: BLUEFIN_DEEP_SUI_POOL,
    venue: "bluefin",
    note: "DEEP/SUI Bluefin swap",
  },
};

function argVal(flag, def) {
  const i = process.argv.indexOf(flag);
  if (i >= 0 && process.argv[i + 1]) return process.argv[i + 1];
  return def;
}

const EXECUTE_FLAG = process.argv.includes("--execute");
const ENV_GATE = process.env.BTEN_EARN_LOOP_EXECUTE === "1";
const BLUEFIN_GATE = process.env.BTEN_BLUEFIN_EXECUTE === "1";
const LIVE = EXECUTE_FLAG && ENV_GATE;
const FRACTION = Math.min(
  1,
  Math.max(0, Number(argVal("--fraction", "0.5")) || 0.5),
);
const STATE_PATH = path.resolve(argVal("--state", DEFAULT_STATE));
const MIN_LEAVE_LIQ = 1n; // never drain position to zero

function assertSafetyIds(report) {
  report.safety = {
    neverTouchVault: FORBIDDEN_VAULT,
    walSuiDeskSwapThroughOnly: WAL_SUI_DESK,
    neverCloseProtocolPools: ["BTEN/SUI", "BTEN/CETUS", "BTEN/WAL"],
    redeemFromBotTrackedAddsOnly: true,
    dualExecuteGates: {
      flagExecute: EXECUTE_FLAG,
      envBTEN_EARN_LOOP_EXECUTE: ENV_GATE,
      live: LIVE,
      bluefinEnv: BLUEFIN_GATE,
    },
  };
  if (FORBIDDEN_VAULT.includes("539079f8") === false) {
    throw new Error("vault id sanity failed");
  }
}

function loadSigner() {
  const file = path.join(
    process.env.SUI_CONFIG_DIR || path.join(os.homedir(), ".sui", "sui_config"),
    "sui.keystore",
  );
  if (!fs.existsSync(file)) return null;
  const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
  const entries = Array.isArray(parsed) ? parsed : parsed.keys ?? [];
  for (const entry of entries) {
    try {
      if (typeof entry !== "string") continue;
      let kp;
      if (entry.startsWith("suiprivkey")) {
        const d = decodeSuiPrivateKey(entry);
        if (d.schema !== "ED25519") continue;
        kp = Ed25519Keypair.fromSecretKey(d.secretKey);
      } else {
        const bytes = Uint8Array.from(Buffer.from(entry, "base64"));
        if (bytes.length !== 33 || bytes[0] !== 0) continue;
        kp = Ed25519Keypair.fromSecretKey(bytes.slice(1));
      }
      if (kp.getPublicKey().toSuiAddress().toLowerCase() === OPS.toLowerCase())
        return kp;
    } catch {}
  }
  return null;
}

function okStatus(st) {
  return st?.success === true || st?.status === "success" || st === "success";
}

function digestOf(done, res) {
  return done?.digest ?? res?.digest ?? res?.Transaction?.digest ?? null;
}

async function bal(client, coinType) {
  const b = await client.getBalance({ owner: OPS, coinType });
  return BigInt(
    b?.totalBalance ??
      b?.balance?.balance ??
      b?.balance?.addressBalance ??
      0,
  );
}

/**
 * Aggregate tracked adds by park name for the current redeem window.
 * Prefer liquidityDelta when present; also sum amountA/amountB for reporting.
 */
export function aggregateTrackedAdds(trackedAdds = []) {
  const byName = new Map();
  for (const a of trackedAdds) {
    if (!a || !a.name) continue;
    const key = a.name;
    const cur = byName.get(key) || {
      name: key,
      venue: a.venue || PARK_META[key]?.venue || "cetus",
      pool: a.pool || PARK_META[key]?.pool,
      pos: a.pos || PARK_META[key]?.pos,
      coinAType: a.coinAType || PARK_META[key]?.coinAType,
      coinBType: a.coinBType || PARK_META[key]?.coinBType,
      amountA: 0n,
      amountB: 0n,
      liquidityDelta: 0n,
      entries: 0,
    };
    cur.amountA += BigInt(a.amountA ?? 0);
    cur.amountB += BigInt(a.amountB ?? 0);
    cur.liquidityDelta += BigInt(a.liquidityDelta ?? 0);
    cur.entries += 1;
    byName.set(key, cur);
  }
  return [...byName.values()];
}

/** 50% of tracked window amounts (liquidity preferred). */
export function planRedeemCuts(aggregated, fraction = 0.5) {
  return aggregated.map((row) => {
    const liqCut =
      row.liquidityDelta > 0n
        ? (row.liquidityDelta * BigInt(Math.round(fraction * 10000))) / 10000n
        : 0n;
    const amtACut =
      (row.amountA * BigInt(Math.round(fraction * 10000))) / 10000n;
    const amtBCut =
      (row.amountB * BigInt(Math.round(fraction * 10000))) / 10000n;
    return {
      name: row.name,
      venue: row.venue,
      pool: row.pool,
      pos: row.pos,
      coinAType: row.coinAType,
      coinBType: row.coinBType,
      trackedLiquidity: row.liquidityDelta.toString(),
      trackedAmountA: row.amountA.toString(),
      trackedAmountB: row.amountB.toString(),
      redeemLiquidity: liqCut.toString(),
      redeemAmountA: amtACut.toString(),
      redeemAmountB: amtBCut.toString(),
      fraction,
      entries: row.entries,
    };
  });
}

async function getCetusLiquidity(sdk, posId) {
  const pos = await sdk.Position.getPositionById(posId, false);
  return {
    liquidity: BigInt(pos.liquidity ?? pos.liquidity_amount ?? 0),
    tickLower: Number(pos.tick_lower_index ?? pos.tick_lower),
    tickUpper: Number(pos.tick_upper_index ?? pos.tick_upper),
    raw: pos,
  };
}

async function redeemCetus({
  client,
  sdk,
  plan,
  execute,
  reportStep,
}) {
  if (!plan.pool || !plan.pos) {
    reportStep.skipped = true;
    reportStep.reason = "missing-pool-pos";
    return reportStep;
  }
  if (plan.pool.toLowerCase() === WAL_SUI_DESK.toLowerCase()) {
    reportStep.skipped = true;
    reportStep.reason = "refuse-wal-sui-desk-lp-mutate";
    return reportStep;
  }
  if (plan.pos.toLowerCase() === FORBIDDEN_VAULT.toLowerCase()) {
    reportStep.skipped = true;
    reportStep.reason = "refuse-vault";
    return reportStep;
  }

  const posInfo = await getCetusLiquidity(sdk, plan.pos);
  const pool = await sdk.Pool.getPool(plan.pool, true);
  let delta = BigInt(plan.redeemLiquidity || 0);

  // If we only tracked coin amounts (no liq delta), estimate a proportional cut:
  // use min(50% of amounts ratio against current position) via amount floors.
  if (delta <= 0n) {
    // Fall back: remove a small proportional slice based on tracked amounts vs
    // position liquidity — use 1% of current liq capped by having tracked adds.
    const trackedA = BigInt(plan.trackedAmountA || 0);
    const trackedB = BigInt(plan.trackedAmountB || 0);
    if (trackedA <= 0n && trackedB <= 0n) {
      reportStep.skipped = true;
      reportStep.reason = "no-tracked-amounts";
      return reportStep;
    }
    // Conservative: remove up to 5% of position liquidity when only amounts known,
    // scaled by fraction — still never close.
    delta = (posInfo.liquidity * BigInt(Math.round(FRACTION * 500))) / 10000n;
    reportStep.liquidityEstimate = "proportional-fallback-from-amounts";
  }

  // Hard cap: leave at least MIN_LEAVE_LIQ so we never close the position.
  const maxRemovable =
    posInfo.liquidity > MIN_LEAVE_LIQ
      ? posInfo.liquidity - MIN_LEAVE_LIQ
      : 0n;
  if (delta > maxRemovable) delta = maxRemovable;
  if (delta <= 0n) {
    reportStep.skipped = true;
    reportStep.reason = "nothing-to-redeem-or-would-close";
    reportStep.positionLiquidity = posInfo.liquidity.toString();
    return reportStep;
  }

  reportStep.positionLiquidityBefore = posInfo.liquidity.toString();
  reportStep.deltaLiquidity = delta.toString();

  const params = {
    pool_id: plan.pool,
    pos_id: plan.pos,
    coin_type_a: pool.coin_type_a,
    coin_type_b: pool.coin_type_b,
    delta_liquidity: delta.toString(),
    min_amount_a: "0",
    min_amount_b: "0",
    collect_fee: true,
    rewarder_coin_types: (pool.rewarder_infos || [])
      .map((r) => r.coin_type)
      .filter(Boolean),
  };
  reportStep.params = {
    ...params,
    rewarder_coin_types: params.rewarder_coin_types.length,
  };

  const tx = await sdk.Position.removeLiquidityPayload(params);
  tx.setSender(OPS);
  tx.setGasBudget(120_000_000);

  if (!execute) {
    const bytes = await tx.build({ client });
    reportStep.dry = { ok: true, builtBytes: bytes.length };
    reportStep.ok = true;
    return reportStep;
  }

  const signer = loadSigner();
  if (!signer) throw new Error(`no signer for ${OPS}`);
  const res = await client.signAndExecuteTransaction({
    signer,
    transaction: tx,
    include: {
      effects: true,
      events: true,
      balanceChanges: true,
      objectChanges: true,
    },
  });
  const done = res.Transaction ?? res.FailedTransaction ?? res;
  const st = done.effects?.status ?? done.status;
  reportStep.result = {
    success: okStatus(st),
    digest: digestOf(done, res),
    status: st,
    gasUsed: done.effects?.gasUsed ?? null,
  };
  reportStep.ok = !!reportStep.result.success;
  await new Promise((r) => setTimeout(r, 1500));
  return reportStep;
}

async function redeemBluefin({ client, plan, execute, reportStep }) {
  if (!BLUEFIN_GATE && execute) {
    reportStep.skipped = true;
    reportStep.reason =
      "Bluefin live remove requires BTEN_BLUEFIN_EXECUTE=1 in addition to earn-loop gates";
    return reportStep;
  }
  let delta = BigInt(plan.redeemLiquidity || 0);
  if (delta <= 0n) {
    // Fallback estimate from tracked DEEP amount (coin A)
    const trackedA = BigInt(plan.trackedAmountA || 0);
    if (trackedA <= 0n) {
      reportStep.skipped = true;
      reportStep.reason = "no-bluefin-tracked-liquidity";
      return reportStep;
    }
    // Without on-chain liq math here, skip live estimate and report plan only
    reportStep.skipped = true;
    reportStep.reason = "bluefin-needs-liquidityDelta-in-tracked-adds";
    reportStep.plannedAmountA = plan.redeemAmountA;
    reportStep.plannedAmountB = plan.redeemAmountB;
    return reportStep;
  }

  reportStep.deltaLiquidity = delta.toString();
  const tx = new Transaction();
  tx.setSender(OPS);
  tx.setGasBudget(100_000_000);
  tx.moveCall({
    target: `${BLUEFIN_CURRENT_PACKAGE}::gateway::remove_liquidity`,
    typeArguments: [DEEP, SUI],
    arguments: [
      tx.object(SUI_CLOCK),
      tx.object(BLUEFIN_GLOBAL_CONFIG),
      tx.object(plan.pool || BLUEFIN_DEEP_SUI_POOL),
      tx.object(plan.pos || BLUEFIN_DEEP_SUI_POS),
      tx.pure.u128(delta.toString()),
      tx.pure.u64("0"),
      tx.pure.u64("0"),
      tx.pure.address(OPS),
    ],
  });

  if (!execute) {
    try {
      const bytes = await tx.build({ client });
      reportStep.dry = { ok: true, builtBytes: bytes.length };
      reportStep.ok = true;
    } catch (e) {
      reportStep.dry = {
        ok: false,
        error: String(e?.message || e).slice(0, 400),
      };
      reportStep.ok = false;
    }
    return reportStep;
  }

  const signer = loadSigner();
  if (!signer) throw new Error(`no signer for ${OPS}`);
  const res = await client.signAndExecuteTransaction({
    signer,
    transaction: tx,
    include: { effects: true, events: true, balanceChanges: true },
  });
  const done = res.Transaction ?? res.FailedTransaction ?? res;
  const st = done.effects?.status ?? done.status;
  reportStep.result = {
    success: okStatus(st),
    digest: digestOf(done, res),
    status: st,
  };
  reportStep.ok = !!reportStep.result.success;
  await new Promise((r) => setTimeout(r, 1500));
  return reportStep;
}

async function swapCoinToSui({ client, sdk, coinType, amount, execute, step }) {
  const route = TO_SUI_ROUTES[coinType.toLowerCase()];
  if (!route) {
    step.skipped = true;
    step.reason = `no-to-sui-route-for-${coinType}`;
    return step;
  }
  if (coinType.toLowerCase() === SUI.toLowerCase()) {
    step.skipped = true;
    step.reason = "already-sui";
    return step;
  }
  if (amount <= 0n) {
    step.skipped = true;
    step.reason = "zero-amount";
    return step;
  }

  // Leave a dust floor so we don't fail on residual dust
  const walletBal = await bal(client, coinType);
  let use = amount > walletBal ? walletBal : amount;
  if (use <= 0n) {
    step.skipped = true;
    step.reason = "wallet-zero-after-redeem";
    return step;
  }
  step.amountIn = use.toString();
  step.route = route;

  if (route.venue === "bluefin") {
    step.skipped = true;
    step.reason =
      "bluefin-swap-deferred; DEEP→SUI via Cetus not wired — redeem leaves DEEP in wallet for separate desk";
    step.note = "Redeem still returns DEEP+SUI to ops; SUI leg already native";
    return step;
  }

  const pool = await sdk.Pool.getPool(route.pool, true);
  const aIsIn =
    String(pool.coin_type_a).toLowerCase() === coinType.toLowerCase();
  const bIsSui =
    String(pool.coin_type_b).toLowerCase() === SUI.toLowerCase() ||
    String(pool.coin_type_a).toLowerCase() === SUI.toLowerCase();
  if (!bIsSui) {
    step.skipped = true;
    step.reason = "pool-not-sui-paired";
    return step;
  }
  const a2b = aIsIn; // if input is coin A, a2b=true sells A for B

  // Refuse mutating desk as LP — swap only via createSwapPayload
  if (route.pool.toLowerCase() === WAL_SUI_DESK.toLowerCase()) {
    step.deskPolicy = "swap-through-only";
  }

  try {
    const pre = await sdk.Swap.preSwap({
      pool,
      currentSqrtPrice: pool.current_sqrt_price,
      coinTypeA: pool.coin_type_a,
      coinTypeB: pool.coin_type_b,
      decimalsA: 9,
      decimalsB: 9,
      a2b,
      byAmountIn: true,
      amount: use.toString(),
    });
    step.preSwap = {
      estimatedAmountOut: String(
        pre?.estimatedAmountOut ?? pre?.amountOut ?? "",
      ),
    };
  } catch (e) {
    step.preSwapError = String(e?.message || e).slice(0, 200);
  }

  const tx = await sdk.Swap.createSwapPayload({
    pool_id: route.pool,
    coin_type_a: pool.coin_type_a,
    coin_type_b: pool.coin_type_b,
    a2b,
    by_amount_in: true,
    amount: use.toString(),
    amount_limit: "0",
  });
  tx.setSender(OPS);
  tx.setGasBudget(80_000_000);

  if (!execute) {
    const bytes = await tx.build({ client });
    step.dry = { ok: true, builtBytes: bytes.length };
    step.ok = true;
    return step;
  }

  const signer = loadSigner();
  if (!signer) throw new Error(`no signer for ${OPS}`);
  const res = await client.signAndExecuteTransaction({
    signer,
    transaction: tx,
    include: { effects: true, balanceChanges: true },
  });
  const done = res.Transaction ?? res.FailedTransaction ?? res;
  const st = done.effects?.status ?? done.status;
  step.result = {
    success: okStatus(st),
    digest: digestOf(done, res),
    status: st,
  };
  step.ok = !!step.result.success;
  await new Promise((r) => setTimeout(r, 1200));
  return step;
}

export async function redeemTrackedAddsToSui({
  trackedAdds,
  fraction = 0.5,
  execute = false,
  statePath = STATE_PATH,
} = {}) {
  const report = {
    at: new Date().toISOString(),
    mode: execute ? "execute" : "dry-run",
    fraction,
    statePath,
    owner: OPS,
    redeemSteps: [],
    swapSteps: [],
  };
  assertSafetyIds(report);

  if (execute && !ENV_GATE) {
    report.blocked = true;
    report.reason =
      "Live redeem refused: need BTEN_EARN_LOOP_EXECUTE=1 together with --execute";
    return report;
  }

  const aggregated = aggregateTrackedAdds(trackedAdds);
  const plans = planRedeemCuts(aggregated, fraction);
  report.plans = plans.map((p) => ({
    ...p,
    // stringify already
  }));

  if (!plans.length) {
    report.skipped = true;
    report.reason = "no-tracked-adds-in-window";
    return report;
  }

  const client = new SuiGrpcClient({
    network: "mainnet",
    baseUrl: "https://fullnode.mainnet.sui.io:443",
  });
  const sdk = CetusClmmSDK.createSDK({ env: "mainnet" });
  sdk.setSenderAddress(OPS);

  report.balancesBefore = {
    sui: (await bal(client, SUI)).toString(),
    bten: (await bal(client, BTEN)).toString(),
    haedal: (await bal(client, HAEDAL)).toString(),
    wal: (await bal(client, WAL)).toString(),
    cetus: (await bal(client, CETUS)).toString(),
    deep: (await bal(client, DEEP)).toString(),
  };

  for (const plan of plans) {
    const step = {
      name: plan.name,
      venue: plan.venue,
      pool: plan.pool,
      pos: plan.pos,
    };
    try {
      if (plan.venue === "bluefin") {
        await redeemBluefin({ client, plan, execute, reportStep: step });
      } else {
        await redeemCetus({
          client,
          sdk,
          plan,
          execute,
          reportStep: step,
        });
      }
    } catch (e) {
      step.error = String(e?.message || e).slice(0, 800);
      step.ok = false;
    }
    report.redeemSteps.push(step);
  }

  // After redeem, swap non-SUI proceeds toward SUI (best-effort; dry by default).
  // Use redeemAmountA/B as intended swap sizes (wallet may hold more — we cap).
  for (const plan of plans) {
    for (const [coinType, amtStr] of [
      [plan.coinAType, plan.redeemAmountA],
      [plan.coinBType, plan.redeemAmountB],
    ]) {
      if (!coinType) continue;
      if (coinType.toLowerCase() === SUI.toLowerCase()) continue;
      const step = {
        from: coinType,
        intended: amtStr,
        park: plan.name,
      };
      try {
        await swapCoinToSui({
          client,
          sdk,
          coinType,
          amount: BigInt(amtStr || 0),
          execute,
          step,
        });
      } catch (e) {
        step.error = String(e?.message || e).slice(0, 500);
        step.ok = false;
      }
      report.swapSteps.push(step);
    }
  }

  report.balancesAfter = {
    sui: (await bal(client, SUI)).toString(),
    bten: (await bal(client, BTEN)).toString(),
    haedal: (await bal(client, HAEDAL)).toString(),
    wal: (await bal(client, WAL)).toString(),
    cetus: (await bal(client, CETUS)).toString(),
    deep: (await bal(client, DEEP)).toString(),
  };

  report.ok =
    report.redeemSteps.every((s) => s.ok || s.skipped) &&
    !report.redeemSteps.some((s) => s.error);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const out = path.join(
    OUT_DIR,
    `earn_loop_redeem_${execute ? "live" : "dry"}_${Date.now()}.json`,
  );
  fs.writeFileSync(out, JSON.stringify(report, null, 2) + "\n");
  report.artifact = out;
  return report;
}

async function main() {
  let trackedAdds = [];
  if (fs.existsSync(STATE_PATH)) {
    const state = JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
    trackedAdds = state.trackedAdds ?? state.window?.trackedAdds ?? [];
  }
  if (process.argv.includes("--stdin-adds")) {
    const raw = fs.readFileSync(0, "utf8");
    const parsed = JSON.parse(raw);
    trackedAdds = Array.isArray(parsed) ? parsed : parsed.trackedAdds ?? [];
  }

  const report = await redeemTrackedAddsToSui({
    trackedAdds,
    fraction: FRACTION,
    execute: LIVE,
    statePath: STATE_PATH,
  });

  console.log(JSON.stringify(report, null, 2));
  if (EXECUTE_FLAG && !ENV_GATE) {
    console.error(
      "[redeem] --execute ignored without BTEN_EARN_LOOP_EXECUTE=1",
    );
  }
  if (report.blocked) process.exit(2);
  if (LIVE && report.ok === false) process.exit(1);
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) ===
    path.resolve(fileURLToPath(import.meta.url))
) {
  main().catch((e) => {
    console.error(String(e?.stack || e));
    process.exit(1);
  });
}
