import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  matchPoolEvent,
  preferGatedMatch,
  walSuiEventKind,
  pickBestPerDigest,
  GATED_KINDS,
  CETUS_SWAP_EVENT,
  CETUS_ADD_LIQUIDITY_EVENT,
  CETUS_ADD_LIQUIDITY_V2_EVENT,
  CETUS_REMOVE_LIQUIDITY_EVENT,
  CETUS_REMOVE_LIQUIDITY_V2_EVENT,
  CETUS_OPEN_POSITION_EVENT,
} from "../scripts/lib/cetus_lp_gate.mjs";

const root = path.resolve(import.meta.dirname, "..");
const mainnet = JSON.parse(fs.readFileSync(path.join(root, "MAINNET_ROUTE_CONFIG.json"), "utf8"));
const keeper = JSON.parse(fs.readFileSync(path.join(root, "config", "keeper_policy.json"), "utf8"));
const bandbot = JSON.parse(fs.readFileSync(path.join(root, "config", "bandbot_wal_sui_keeper.json"), "utf8"));

const POOL = "0x72f5c6eef73d77de271886219a2543e7c29a33de19a6c69c5cf1899f729c3f17";
const SENDER = "0xabc";

function evt(type, json, sequenceNumber = 0) {
  return {
    sequenceNumber,
    sender: { address: SENDER },
    contents: { type: { repr: type }, json: { pool: POOL, ...json } },
  };
}

test("gated kinds include swap, add, and remove", () => {
  assert.deepEqual([...GATED_KINDS], ["swap", "liquidity_add", "liquidity_remove"]);
});

test("matchPoolEvent recognizes AddLiquidity and AddLiquidityV2", () => {
  const add = matchPoolEvent(evt(CETUS_ADD_LIQUIDITY_EVENT, { amount_a: "1", amount_b: "0" }), POOL, SENDER);
  assert.equal(add.kind, "liquidity_add");
  const addV2 = matchPoolEvent(evt(CETUS_ADD_LIQUIDITY_V2_EVENT, { amount_a: "0", amount_b: "2" }), POOL, SENDER);
  assert.equal(addV2.kind, "liquidity_add");
});

test("matchPoolEvent recognizes RemoveLiquidity and RemoveLiquidityV2", () => {
  const rem = matchPoolEvent(evt(CETUS_REMOVE_LIQUIDITY_EVENT, { liquidity: "9" }), POOL, SENDER);
  assert.equal(rem.kind, "liquidity_remove");
  const remV2 = matchPoolEvent(
    evt(CETUS_REMOVE_LIQUIDITY_V2_EVENT, { amount_a: "3", amount_b: "4" }),
    POOL,
    SENDER,
  );
  assert.equal(remV2.kind, "liquidity_remove");
});

test("matchPoolEvent recognizes swaps and ignores bare OpenPosition preference", () => {
  const swap = matchPoolEvent(
    evt(CETUS_SWAP_EVENT, { amount_in: "1", amount_out: "2" }),
    POOL,
    SENDER,
  );
  assert.equal(swap.kind, "swap");
  const openOnly = preferGatedMatch([
    matchPoolEvent(evt(CETUS_OPEN_POSITION_EVENT, {}), POOL, SENDER),
  ]);
  assert.equal(openOnly, null);
});

test("preferGatedMatch ranks add over remove over swap", () => {
  const matched = [
    matchPoolEvent(evt(CETUS_SWAP_EVENT, { amount_in: "1", amount_out: "2" }, 0), POOL, SENDER),
    matchPoolEvent(evt(CETUS_REMOVE_LIQUIDITY_EVENT, { liquidity: "1" }, 1), POOL, SENDER),
    matchPoolEvent(evt(CETUS_ADD_LIQUIDITY_V2_EVENT, { amount_a: "1" }, 2), POOL, SENDER),
  ];
  assert.equal(preferGatedMatch(matched).kind, "liquidity_add");
  assert.equal(
    preferGatedMatch(matched.filter((m) => m.kind !== "liquidity_add")).kind,
    "liquidity_remove",
  );
});

test("walSuiEventKind maps add=2 remove=3 swap=1", () => {
  assert.equal(walSuiEventKind("liquidity_add"), 2);
  assert.equal(walSuiEventKind("liquidity_remove"), 3);
  assert.equal(walSuiEventKind("swap"), 1);
});

test("pickBestPerDigest keeps one receipt and prefers add", () => {
  const picked = pickBestPerDigest([
    { digest: "d1", kind: "swap", eventSequence: 0 },
    { digest: "d1", kind: "liquidity_remove", eventSequence: 1 },
    { digest: "d1", kind: "liquidity_add", eventSequence: 2 },
    { digest: "d2", kind: "liquidity_remove", eventSequence: 0 },
  ]);
  const by = Object.fromEntries(picked.map((c) => [c.digest, c.kind]));
  assert.equal(by.d1, "liquidity_add");
  assert.equal(by.d2, "liquidity_remove");
});

test("MAINNET_ROUTE_CONFIG lists RemoveLiquidity event types and gated kinds", () => {
  const v = mainnet.externalCetusVerifier;
  assert.deepEqual(v.gatedEventKinds, ["swap", "liquidity_add", "liquidity_remove"]);
  assert.ok(v.cetusEventTypes.some((t) => t.endsWith("::RemoveLiquidityEvent")));
  assert.ok(v.cetusEventTypes.some((t) => t.endsWith("::RemoveLiquidityV2Event")));
  assert.ok(v.cetusEventTypes.some((t) => t.endsWith("::AddLiquidityEvent")));
  assert.ok(v.cetusEventTypes.some((t) => t.endsWith("::AddLiquidityV2Event")));
  assert.equal(v.walSuiEntrypoints.eventKinds.add, 2);
  assert.equal(v.walSuiEntrypoints.eventKinds.remove, 3);
});

test("keeper and bandbot configs gate LP remove and point at live package", () => {
  assert.equal(keeper.attest.includeRemoveLiquidity, true);
  assert.match(keeper.livePackageId, /^0x[0-9a-f]{64}$/i);
  assert.equal(bandbot.eventKinds["2"], "add");
  assert.equal(bandbot.eventKinds["3"], "remove");
  assert.ok(bandbot.cetusEventTypes.remove.includes("RemoveLiquidityEvent"));
  assert.ok(bandbot.cetusEventTypes.removeV2.includes("RemoveLiquidityV2Event"));
});
