/**
 * Shared Cetus LP / swap gate matching for registered BTEN pools.
 * Used by external_cetus_verifier.mjs and unit tests.
 *
 * Gated kinds (one receipt per digest):
 *   swap | liquidity_add | liquidity_remove
 * WAL/SUI event_kind mapping: 1=swap, 2=add, 3=remove.
 */

export const CETUS_SWAP_EVENT =
  "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::SwapEvent";
export const CETUS_ADD_LIQUIDITY_EVENT =
  "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::AddLiquidityEvent";
export const CETUS_ADD_LIQUIDITY_V2_EVENT =
  "0xdb5cd62a06c79695bfc9982eb08534706d3752fe123b48e0144f480209b3117f::pool::AddLiquidityV2Event";
export const CETUS_OPEN_POSITION_EVENT =
  "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::OpenPositionEvent";
export const CETUS_REMOVE_LIQUIDITY_EVENT =
  "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::RemoveLiquidityEvent";
export const CETUS_REMOVE_LIQUIDITY_V2_EVENT =
  "0xdb5cd62a06c79695bfc9982eb08534706d3752fe123b48e0144f480209b3117f::pool::RemoveLiquidityV2Event";

export const GATED_KINDS = Object.freeze(["swap", "liquidity_add", "liquidity_remove"]);
export const KIND_RANK = Object.freeze({ liquidity_add: 0, liquidity_remove: 1, swap: 2 });

export const WAL_SUI_EVENT_KIND = Object.freeze({
  swap: 1,
  liquidity_add: 2,
  liquidity_remove: 3,
});

export function normal(value) {
  return String(value ?? "").toLowerCase();
}

export function positive(value) {
  try {
    return BigInt(value ?? 0) > 0n;
  } catch {
    return false;
  }
}

/**
 * Match a Cetus pool event for a registered pool + tx sender.
 * Returns { kind, event } or null.
 */
export function matchPoolEvent(event, pool, sender) {
  const type = event.contents?.type?.repr;
  const json = event.contents?.json ?? {};
  if (normal(json.pool) !== normal(pool)) return null;
  if (normal(event.sender?.address) !== sender) return null;
  if (type === CETUS_SWAP_EVENT && positive(json.amount_in) && positive(json.amount_out)) {
    return { kind: "swap", event };
  }
  if (type === CETUS_ADD_LIQUIDITY_V2_EVENT && (positive(json.amount_a) || positive(json.amount_b))) {
    return { kind: "liquidity_add", event };
  }
  if (
    type === CETUS_ADD_LIQUIDITY_EVENT
    && (positive(json.amount_a) || positive(json.amount_b) || positive(json.liquidity))
  ) {
    return { kind: "liquidity_add", event };
  }
  if (
    type === CETUS_REMOVE_LIQUIDITY_V2_EVENT
    && (positive(json.amount_a) || positive(json.amount_b) || positive(json.liquidity))
  ) {
    return { kind: "liquidity_remove", event };
  }
  if (
    type === CETUS_REMOVE_LIQUIDITY_EVENT
    && (positive(json.amount_a) || positive(json.amount_b) || positive(json.liquidity))
  ) {
    return { kind: "liquidity_remove", event };
  }
  if (type === CETUS_OPEN_POSITION_EVENT) {
    return { kind: "open_position", event };
  }
  return null;
}

/**
 * Prefer add > remove > swap on a pool; ignore bare OpenPosition.
 * `matched` is an array of { kind, event } from matchPoolEvent.
 */
export function preferGatedMatch(matched) {
  const hasAdd = matched.some((item) => item.kind === "liquidity_add");
  const preferred =
    matched.find((item) => item.kind === "liquidity_add")
    || matched.find((item) => item.kind === "liquidity_remove")
    || matched.find((item) => item.kind === "swap")
    || (hasAdd ? matched.find((item) => item.kind === "open_position") : null);
  if (!preferred || preferred.kind === "open_position") return null;
  return preferred;
}

/** Map verifier kind → on-chain WAL/SUI event_kind u8. */
export function walSuiEventKind(kind) {
  if (kind === "liquidity_add") return WAL_SUI_EVENT_KIND.liquidity_add;
  if (kind === "liquidity_remove") return WAL_SUI_EVENT_KIND.liquidity_remove;
  return WAL_SUI_EVENT_KIND.swap;
}

/** Collapse multi-pool candidates to one receipt per digest (best kind rank). */
export function pickBestPerDigest(candidates) {
  const byDigest = new Map();
  for (const candidate of candidates) {
    const current = byDigest.get(candidate.digest);
    const nextRank = KIND_RANK[candidate.kind] ?? 9;
    const curRank = current ? (KIND_RANK[current.kind] ?? 9) : 99;
    if (
      !current
      || nextRank < curRank
      || (nextRank === curRank && candidate.eventSequence < current.eventSequence)
    ) {
      byDigest.set(candidate.digest, candidate);
    }
  }
  return [...byDigest.values()];
}
