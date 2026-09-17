#!/usr/bin/env node
/**
 * Laptop Earn Loop daemon
 *
 * Cadence:
 *   - Flash earn every 1 minute (minProfitMist=0 / ignoreMinProfit)
 *   - Track Earn park adds this redeem window
 *   - Redeem timer starts at 5 min, then +1 min each redeem cycle (5→6→7…)
 *   - On fire: redeem 50% of tracked-window adds → swap to SUI → keep flashing
 *
 * Safety:
 *   - Never touch vault 0x539079f8…446bc0
 *   - WAL/SUI desk swap-through only
 *   - Never close protocol BTEN/SUI|CETUS|WAL pools — only redeem bot-tracked adds
 *   - Dual execute gates: BTEN_EARN_LOOP_EXECUTE=1 AND --execute
 *   - Skip overlapping ticks; persist state to artifacts/v30/laptop_earn_loop_state.json
 *
 * Usage (default dry):
 *   node scripts/laptop_earn_loop_daemon.mjs
 *   node scripts/laptop_earn_loop_daemon.mjs
 *   node scripts/laptop_earn_loop_daemon.mjs --once
 *   BTEN_EARN_LOOP_EXECUTE=1 node scripts/laptop_earn_loop_daemon.mjs --execute
 */
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { CetusClmmSDK } from "@cetusprotocol/sui-clmm-sdk";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import {
  redeemTrackedAddsToSui,
  aggregateTrackedAdds,
  planRedeemCuts,
} from "./laptop_earn_loop_redeem_to_sui.mjs";
import {
  BLUEFIN_DEEP_SUI_POOL,
  BLUEFIN_DEEP_SUI_POS,
  DEEP,
} from "./lib/bluefin_deep_sui_park.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(__dirname, "..");
const CONFIG_PATH = path.join(REPO, "config/laptop_earn_loop.json");
const STATE_PATH = path.join(REPO, "artifacts/v30/laptop_earn_loop_state.json");
const OUT_DIR = path.join(REPO, "artifacts/v30");

const FORBIDDEN_VAULT =
  "0x539079f8c0b0055e334307d472fe693a2c0ae545d4f3c9752e1e6ceddb446bc0";
const WAL_SUI_DESK =
  "0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17";
const OPS = "0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a";

const PARK_POSITIONS = [
  {
    name: "HAEDAL-BTEN",
    pool: "0x3ea08eda95787196aa5afb3880b4f22eaf548bfc3cab4e209d3864c6cfb426f3",
    pos: "0xaf2882f18d23f1ffbf6e629cafbb9c65e30df20c1a214e97c049f43efb2de369",
    venue: "cetus",
  },
  {
    name: "WAL-BTEN",
    pool: "0xa9f12a204ac1cb778c015e77a88fc8eb5926599ece17b2a8841753c7712544c7",
    pos: "0x00fbadfc20ee3b4325e63e6405c1075efbaa15913cdf4c64a3262ee8d1847713",
    venue: "cetus",
  },
  {
    name: "BTEN-SUI",
    pool: "0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950",
    pos: "0x7cef638a37de4083e66dc2f400a1760f5098ae51cce66865ce733bdd6ec2689e",
    venue: "cetus",
  },
  {
    name: "BTEN-CETUS",
    pool: "0xf6c5df04eb488373c8309b96f0ea187aada7c3b446b3fb6ef5f73f222eaa5f0c",
    pos: "0x0f281bf808e6fab914930fa17316244acd146ee1d72a06f57496e46a64788ead",
    venue: "cetus",
  },
  {
    name: "BLUEFIN-DEEP-SUI",
    pool: BLUEFIN_DEEP_SUI_POOL,
    pos: BLUEFIN_DEEP_SUI_POS,
    venue: "bluefin",
  },
];

function argVal(flag, def) {
  const i = process.argv.indexOf(flag);
  if (i >= 0 && process.argv[i + 1]) return process.argv[i + 1];
  return def;
}

const EXECUTE_FLAG = process.argv.includes("--execute");
const ONCE = process.argv.includes("--once");
const ENV_GATE = process.env.BTEN_EARN_LOOP_EXECUTE === "1";
const LIVE = EXECUTE_FLAG && ENV_GATE;

function loadConfig() {
  const raw = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
  const flashMs =
    Number(raw.schedule?.flashIntervalMs) ||
    Number(raw.cadence?.flashIntervalSec || 60) * 1000;
  const redeemStartMin = Number(
    raw.cadence?.redeemStartMin ?? raw.schedule?.redeemStartMin ?? 5,
  );
  const redeemIncrementMin = Number(
    raw.cadence?.redeemIncrementMin ?? raw.schedule?.redeemIncrementMin ?? 1,
  );
  const redeemFraction = Number(
    raw.cadence?.redeemFraction ?? raw.limits?.redeemFraction ?? 0.5,
  );
  return {
    ...raw,
    flashIntervalMs: flashMs,
    redeemStartMin,
    redeemIncrementMin,
    redeemFraction,
    borrowSui: Number(raw.limits?.borrowSuiDefault ?? 1),
    ignoreMinProfit: raw.limits?.ignoreMinProfit !== false,
    minProfitMist: String(raw.limits?.minProfitMist ?? "0"),
    enabled: raw.enabled === true,
  };
}

function defaultState(cfg) {
  const now = Date.now();
  const redeemMs = cfg.redeemStartMin * 60_000;
  return {
    version: 1,
    updatedAt: new Date(now).toISOString(),
    enabled: cfg.enabled,
    killSwitch: false,
    mode: LIVE ? "live" : "dry",
    flashIntervalMs: cfg.flashIntervalMs,
    redeemCycleIndex: 0,
    redeemIntervalMin: cfg.redeemStartMin,
    redeemIntervalMs: redeemMs,
    redeemFraction: cfg.redeemFraction,
    nextFlashAt: now,
    nextRedeemAt: now + redeemMs,
    lastFlashAt: null,
    lastRedeemAt: null,
    tickInFlight: false,
    flashCount: 0,
    redeemCount: 0,
    trackedAdds: [],
    history: [],
    safety: {
      neverTouchVault: FORBIDDEN_VAULT,
      walSuiDeskSwapThroughOnly: WAL_SUI_DESK,
      dualGates: {
        flagExecute: EXECUTE_FLAG,
        envBTEN_EARN_LOOP_EXECUTE: ENV_GATE,
        live: LIVE,
      },
    },
    lastError: null,
  };
}

function loadState(cfg) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  if (!fs.existsSync(STATE_PATH)) {
    const s = defaultState(cfg);
    saveState(s);
    return s;
  }
  try {
    const s = JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
    s.mode = LIVE ? "live" : "dry";
    s.safety = {
      neverTouchVault: FORBIDDEN_VAULT,
      walSuiDeskSwapThroughOnly: WAL_SUI_DESK,
      dualGates: {
        flagExecute: EXECUTE_FLAG,
        envBTEN_EARN_LOOP_EXECUTE: ENV_GATE,
        live: LIVE,
      },
    };
    if (!Array.isArray(s.trackedAdds)) s.trackedAdds = [];
    if (!Array.isArray(s.history)) s.history = [];
    if (s.killSwitch == null) s.killSwitch = false;
    return s;
  } catch {
    return defaultState(cfg);
  }
}

function saveState(state) {
  state.updatedAt = new Date().toISOString();
  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2) + "\n");
  // UI-friendly mirror
  const uiPath = path.join(REPO, "artifacts/v30/laptop_earn_loop_state.mirror.json");
  try {
    fs.mkdirSync(path.dirname(uiPath), { recursive: true });
    fs.writeFileSync(uiPath, JSON.stringify(state, null, 2) + "\n");
  } catch {}
}

function runNode(scriptRel, args, envExtra = {}) {
  return new Promise((resolve) => {
    const script = path.join(REPO, scriptRel);
    const child = spawn(process.execPath, [script, ...args], {
      cwd: REPO,
      env: { ...process.env, ...envExtra },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const max = 8_000_000;
    child.stdout.on("data", (d) => {
      if (stdout.length < max) stdout += d.toString();
    });
    child.stderr.on("data", (d) => {
      if (stderr.length < max) stderr += d.toString();
    });
    child.on("close", (code) => {
      let json = null;
      const trimmed = stdout.trim();
      if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
        try {
          json = JSON.parse(trimmed);
        } catch {
          const lastBrace = trimmed.lastIndexOf("\n{");
          if (lastBrace >= 0) {
            try {
              json = JSON.parse(trimmed.slice(lastBrace + 1));
            } catch {}
          }
        }
      }
      resolve({ code, stdout, stderr, json });
    });
  });
}

async function snapshotLiquidities() {
  const out = {};
  try {
    const client = new SuiGrpcClient({
      network: "mainnet",
      baseUrl: "https://fullnode.mainnet.sui.io:443",
    });
    const sdk = CetusClmmSDK.createSDK({ env: "mainnet" });
    sdk.setSenderAddress(OPS);
    for (const p of PARK_POSITIONS) {
      try {
        if (p.venue === "cetus") {
          const pos = await sdk.Position.getPositionById(p.pos, false);
          out[p.name] = {
            liquidity: String(pos.liquidity ?? 0),
            venue: "cetus",
            pool: p.pool,
            pos: p.pos,
          };
        } else {
          // Bluefin: read object content liquidity field if present
          const o = await client.core.getObject({ objectId: p.pos });
          const obj = o.object ?? o;
          const content = obj.content ?? obj;
          const fields = content?.fields ?? content?.value?.fields ?? {};
          const liq =
            fields.liquidity ??
            fields.liquidity_amount ??
            fields.coin_amounts?.liquidity ??
            "0";
          out[p.name] = {
            liquidity: String(liq),
            venue: "bluefin",
            pool: p.pool,
            pos: p.pos,
          };
        }
      } catch (e) {
        out[p.name] = {
          liquidity: "0",
          error: String(e?.message || e).slice(0, 120),
          venue: p.venue,
          pool: p.pool,
          pos: p.pos,
        };
      }
    }
  } catch (e) {
    return { _error: String(e?.message || e).slice(0, 200) };
  }
  return out;
}

function extractParkAdds(parkJson, liqBefore, liqAfter, tickId) {
  const adds = [];
  const results = parkJson?.results ?? parkJson?.followUpPark?.results ?? [];
  const list = Array.isArray(results) ? results : [];

  // From park script results
  for (const r of list) {
    if (!r?.name) continue;
    if (r.skipped) continue;
    const ok = r.result?.success === true || r.dry?.ok === true || r.ok === true;
    if (!ok && !r.params && !r.amounts) continue;
    const amountA = String(
      r.params?.amount_a ??
        r.params?.amountA ??
        r.amountA ??
        r.amounts?.amountA ??
        r.amounts?.deep ??
        "0",
    );
    const amountB = String(
      r.params?.amount_b ??
        r.params?.amountB ??
        r.amountB ??
        r.amounts?.amountB ??
        r.amounts?.sui ??
        "0",
    );
    const before = BigInt(liqBefore?.[r.name]?.liquidity ?? 0);
    const after = BigInt(liqAfter?.[r.name]?.liquidity ?? 0);
    let liquidityDelta = after > before ? after - before : 0n;
    if (
      liquidityDelta === 0n &&
      r.amounts?.liquidityAmount != null
    ) {
      liquidityDelta = BigInt(r.amounts.liquidityAmount);
    }
    const meta = PARK_POSITIONS.find((p) => p.name === r.name) || {};
    adds.push({
      name: r.name,
      pool: r.pool || meta.pool,
      pos: r.pos || meta.pos,
      venue: meta.venue || (r.name.includes("BLUEFIN") ? "bluefin" : "cetus"),
      amountA,
      amountB,
      liquidityDelta: liquidityDelta.toString(),
      digest: r.result?.digest ?? null,
      tickId,
      at: new Date().toISOString(),
      dry: !LIVE,
    });
  }

  // Also catch flash follow-up parks shaped as digests[]
  const digests = parkJson?.followUpPark?.digests ?? parkJson?.digests ?? [];
  if (Array.isArray(digests)) {
    for (const d of digests) {
      if (!d?.name || !d.ok) continue;
      if (adds.some((a) => a.name === d.name && a.digest === d.digest)) continue;
      const before = BigInt(liqBefore?.[d.name]?.liquidity ?? 0);
      const after = BigInt(liqAfter?.[d.name]?.liquidity ?? 0);
      const liquidityDelta = after > before ? after - before : 0n;
      const meta = PARK_POSITIONS.find((p) => p.name === d.name) || {};
      adds.push({
        name: d.name,
        pool: meta.pool,
        pos: meta.pos,
        venue: meta.venue || "cetus",
        amountA: "0",
        amountB: "0",
        liquidityDelta: liquidityDelta.toString(),
        digest: d.digest ?? null,
        tickId,
        at: new Date().toISOString(),
        dry: !LIVE,
      });
    }
  }

  // Liquidity-only deltas when park JSON sparse (still track)
  for (const p of PARK_POSITIONS) {
    if (adds.some((a) => a.name === p.name)) continue;
    const before = BigInt(liqBefore?.[p.name]?.liquidity ?? 0);
    const after = BigInt(liqAfter?.[p.name]?.liquidity ?? 0);
    if (after > before) {
      adds.push({
        name: p.name,
        pool: p.pool,
        pos: p.pos,
        venue: p.venue,
        amountA: "0",
        amountB: "0",
        liquidityDelta: (after - before).toString(),
        digest: null,
        tickId,
        at: new Date().toISOString(),
        dry: !LIVE,
        source: "liquidity-snapshot",
      });
    }
  }
  return adds;
}

/**
 * Growing redeem cadence: start at redeemStartMin, then +redeemIncrementMin
 * after each redeem fire (5 → 6 → 7 → …).
 */
export function nextRedeemIntervalMin(cfg, redeemCycleIndex) {
  return cfg.redeemStartMin + redeemCycleIndex * cfg.redeemIncrementMin;
}

async function runFlashAndPark(cfg, state, tickId) {
  const borrow = cfg.borrowSui;
  const minProfit = cfg.ignoreMinProfit ? "0" : cfg.minProfitMist;
  const flashArgs = ["--borrow", String(borrow), "--min-profit", minProfit];
  const parkArgs = [];
  if (LIVE) {
    flashArgs.push("--execute");
    parkArgs.push("--execute");
  }

  const liqBefore = await snapshotLiquidities();
  console.error(
    `[daemon] flash tick=${tickId} live=${LIVE} borrow=${borrow} minProfit=${minProfit}`,
  );

  const flash = await runNode(
    "scripts/template_a_flash_earn_loop.mjs",
    flashArgs,
  );
  const parkEnv = LIVE ? { BTEN_BLUEFIN_EXECUTE: process.env.BTEN_BLUEFIN_EXECUTE || "" } : {};
  const park = await runNode(
    "scripts/earn_loop_park_residuals.mjs",
    parkArgs,
    parkEnv,
  );

  // Brief settle for object versions
  await new Promise((r) => setTimeout(r, LIVE ? 2000 : 200));
  const liqAfter = await snapshotLiquidities();

  const addsFromFlash = extractParkAdds(
    flash.json,
    liqBefore,
    liqAfter,
    tickId,
  );
  const addsFromPark = extractParkAdds(park.json, liqBefore, liqAfter, tickId);
  // Prefer park script rows; merge unique
  const merged = [...addsFromPark];
  for (const a of addsFromFlash) {
    if (!merged.some((m) => m.name === a.name && m.tickId === a.tickId)) {
      merged.push(a);
    }
  }

  return {
    flash: {
      code: flash.code,
      ok: flash.code === 0,
      digest: flash.json?.live?.digest ?? flash.json?.summary?.liveDigest ?? null,
      artifact: flash.json?.artifact ?? null,
    },
    park: {
      code: park.code,
      ok: park.code === 0 || park.json?.okCount >= 0,
      digests: park.json?.digests ?? [],
      artifact: park.json?.artifact ?? null,
    },
    adds: merged,
    liqBefore,
    liqAfter,
    stderrTail: (flash.stderr + "\n" + park.stderr).slice(-2000),
  };
}

async function runRedeem(cfg, state) {
  console.error(
    `[daemon] REDEEM fire cycle=${state.redeemCycleIndex} intervalMin=${state.redeemIntervalMin} tracked=${state.trackedAdds.length} fraction=${cfg.redeemFraction}`,
  );
  const report = await redeemTrackedAddsToSui({
    trackedAdds: state.trackedAdds,
    fraction: cfg.redeemFraction,
    execute: LIVE,
    statePath: STATE_PATH,
  });
  return report;
}

async function tick(cfg, state) {
  if (state.killSwitch) {
    console.error("[daemon] killSwitch ON — skipping");
    return state;
  }
  if (cfg.enabled === false && LIVE) {
    console.error("[daemon] config.enabled=false — refusing live; dry only");
  }
  if (state.tickInFlight) {
    console.error("[daemon] skip overlapping tick");
    return state;
  }

  state.tickInFlight = true;
  saveState(state);
  const now = Date.now();
  const tickId = `t${now}`;

  try {
    // Redeem takes priority when due
    if (now >= state.nextRedeemAt) {
      const redeemReport = await runRedeem(cfg, state);
      state.lastRedeemAt = new Date().toISOString();
      state.redeemCount = (state.redeemCount || 0) + 1;
      state.history.push({
        type: "redeem",
        at: state.lastRedeemAt,
        ok: !!redeemReport.ok,
        artifact: redeemReport.artifact ?? null,
        trackedCount: state.trackedAdds.length,
        intervalMin: state.redeemIntervalMin,
      });
      if (state.history.length > 100) state.history = state.history.slice(-100);

      // Clear window after redeem attempt
      state.trackedAdds = [];

      // Growing cadence: 5 → 6 → 7 …
      state.redeemCycleIndex = (state.redeemCycleIndex || 0) + 1;
      state.redeemIntervalMin = nextRedeemIntervalMin(
        cfg,
        state.redeemCycleIndex,
      );
      state.redeemIntervalMs = state.redeemIntervalMin * 60_000;
      state.nextRedeemAt = Date.now() + state.redeemIntervalMs;
      state.lastError = redeemReport.blocked
        ? redeemReport.reason
        : redeemReport.ok === false
          ? "redeem-failed"
          : null;
      saveState(state);
    }

    // Flash on 1-minute cadence
    if (Date.now() >= state.nextFlashAt) {
      const result = await runFlashAndPark(cfg, state, tickId);
      state.lastFlashAt = new Date().toISOString();
      state.flashCount = (state.flashCount || 0) + 1;
      state.nextFlashAt = Date.now() + cfg.flashIntervalMs;

      for (const a of result.adds) state.trackedAdds.push(a);

      state.history.push({
        type: "flash",
        at: state.lastFlashAt,
        ok: result.flash.ok,
        digest: result.flash.digest,
        adds: result.adds.map((a) => ({
          name: a.name,
          liquidityDelta: a.liquidityDelta,
          amountA: a.amountA,
          amountB: a.amountB,
        })),
      });
      if (state.history.length > 100) state.history = state.history.slice(-100);
      if (!result.flash.ok) {
        state.lastError = `flash exit ${result.flash.code}`;
      } else {
        state.lastError = null;
      }
      saveState(state);
    }
  } catch (e) {
    state.lastError = String(e?.message || e).slice(0, 500);
    console.error("[daemon] tick error", state.lastError);
    saveState(state);
  } finally {
    state.tickInFlight = false;
    saveState(state);
  }
  return state;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function main() {
  const cfg = loadConfig();
  let state = loadState(cfg);

  // Align cadence fields from config on start
  state.flashIntervalMs = cfg.flashIntervalMs;
  state.redeemFraction = cfg.redeemFraction;
  if (state.redeemIntervalMin == null) {
    state.redeemIntervalMin = cfg.redeemStartMin;
    state.redeemIntervalMs = cfg.redeemStartMin * 60_000;
  }
  if (!state.nextRedeemAt) {
    state.nextRedeemAt = Date.now() + state.redeemIntervalMs;
  }
  if (!state.nextFlashAt) state.nextFlashAt = Date.now();
  state.enabled = cfg.enabled;
  state.mode = LIVE ? "live" : "dry";
  saveState(state);

  console.error(
    JSON.stringify(
      {
        daemon: "laptop_earn_loop",
        mode: state.mode,
        live: LIVE,
        enabled: cfg.enabled,
        flashIntervalMs: cfg.flashIntervalMs,
        redeemStartMin: cfg.redeemStartMin,
        redeemIncrementMin: cfg.redeemIncrementMin,
        redeemFraction: cfg.redeemFraction,
        ignoreMinProfit: cfg.ignoreMinProfit,
        statePath: STATE_PATH,
        nextFlashAt: new Date(state.nextFlashAt).toISOString(),
        nextRedeemAt: new Date(state.nextRedeemAt).toISOString(),
        redeemIntervalMin: state.redeemIntervalMin,
        dualGates: state.safety.dualGates,
        note:
          EXECUTE_FLAG && !ENV_GATE
            ? "--execute ignored without BTEN_EARN_LOOP_EXECUTE=1"
            : LIVE
              ? "LIVE gated ON"
              : "DRY default",
      },
      null,
      2,
    ),
  );

  if (ONCE) {
    // Force due times for a single combined tick
    state.nextFlashAt = 0;
    // Do not force redeem on --once unless window already due
    await tick(cfg, state);
    console.log(JSON.stringify({ ok: true, once: true, statePath: STATE_PATH }, null, 2));
    return;
  }

  // Main loop: poll every 2s; skip if previous still running
  for (;;) {
    // Hot-reload kill switch / enabled from state file (UI may flip)
    try {
      const disk = JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
      if (disk.killSwitch === true) state.killSwitch = true;
      if (disk.killSwitch === false) state.killSwitch = false;
    } catch {}

    const cfgNow = loadConfig();
    await tick(cfgNow, state);
    await sleep(2000);
  }
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
