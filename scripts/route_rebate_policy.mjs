/** Public, deterministic policy for a final-output route rebate.
 * The caller must quote the rebate conversion into the same output token as
 * the direct route. This code does not sign, transfer, or create a subsidy.
 */
const raw = (name, value) => {
  if (!/^\d+$/.test(String(value ?? ""))) throw new Error(`${name} must be a non-negative raw integer`);
  return BigInt(value);
};

export function evaluateRouteRebate({ directOutRaw, btenOutRaw, btenIntermediateRaw, rebateBtenRaw, rebateFinalOutRaw, maxRebateBps, perSwapCapBtenRaw, minImprovementBps = 1 }) {
  const direct = raw("directOutRaw", directOutRaw);
  const btenOut = raw("btenOutRaw", btenOutRaw);
  const intermediate = raw("btenIntermediateRaw", btenIntermediateRaw);
  const rebateBten = raw("rebateBtenRaw", rebateBtenRaw);
  const rebateFinal = raw("rebateFinalOutRaw", rebateFinalOutRaw);
  const perSwapCap = raw("perSwapCapBtenRaw", perSwapCapBtenRaw);
  if (!Number.isInteger(maxRebateBps) || maxRebateBps < 0 || maxRebateBps > 10_000) throw new Error("maxRebateBps must be 0..10000");
  if (!Number.isInteger(minImprovementBps) || minImprovementBps < 0 || minImprovementBps > 10_000) throw new Error("minImprovementBps must be 0..10000");
  const proportionalCap = intermediate * BigInt(maxRebateBps) / 10_000n;
  const allowedBten = proportionalCap < perSwapCap ? proportionalCap : perSwapCap;
  if (rebateBten > allowedBten) throw new Error("rebate exceeds the route's proportional or per-swap BTEN cap");
  const netOut = btenOut + rebateFinal;
  const required = (direct * BigInt(10_000 + minImprovementBps) + 9_999n) / 10_000n;
  return {
    eligible: netOut >= required,
    directOutRaw: direct.toString(),
    btenOutRaw: btenOut.toString(),
    rebateBtenRaw: rebateBten.toString(),
    rebateFinalOutRaw: rebateFinal.toString(),
    netOutRaw: netOut.toString(),
    requiredNetOutRaw: required.toString(),
    allowedRebateBtenRaw: allowedBten.toString(),
    reason: netOut >= required ? "Quoted final-token rebate makes the BTEN route net-better" : "Direct route remains better; do not offer a rebate",
  };
}
