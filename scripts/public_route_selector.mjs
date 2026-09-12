/**
 * Pure, public best-execution selection for Block10.
 * Quoters must supply final output amounts in the same token's raw units.
 * This module does not build a transaction, sign, or use a wallet key.
 */
const raw = (name, value) => {
  if (!/^\d+$/.test(String(value ?? ""))) throw new Error(`${name} must be a non-negative raw integer`);
  return BigInt(value);
};

export function selectPublicRoute({ directOutRaw, directCostOutRaw = "0", btenLeg1OutRaw, btenLeg2OutRaw, btenCostOutRaw = "0", minImprovementBps = 1 }) {
  if (!Number.isInteger(minImprovementBps) || minImprovementBps < 0 || minImprovementBps > 10_000) throw new Error("minImprovementBps must be 0..10000");
  const directNet = raw("directOutRaw", directOutRaw) - raw("directCostOutRaw", directCostOutRaw);
  const btenNet = raw("btenLeg2OutRaw", btenLeg2OutRaw) - raw("btenCostOutRaw", btenCostOutRaw);
  if (directNet <= 0n || btenNet <= 0n) throw new Error("net output must remain positive");
  const requiredBtenNet = (directNet * BigInt(10_000 + minImprovementBps) + 9_999n) / 10_000n;
  const useBten = btenNet >= requiredBtenNet;
  return {
    selected: useBten ? "bten-two-hop" : "direct",
    directNetOutRaw: directNet.toString(),
    btenNetOutRaw: btenNet.toString(),
    btenIntermediateOutRaw: raw("btenLeg1OutRaw", btenLeg1OutRaw).toString(),
    improvementBps: Number((btenNet - directNet) * 10_000n / directNet),
    minImprovementBps,
    reason: useBten ? "BTEN net output meets the transparent best-execution threshold" : "Direct route is equal or better after stated costs",
  };
}
