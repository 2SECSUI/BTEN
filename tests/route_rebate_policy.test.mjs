import assert from "node:assert/strict";
import { evaluateRouteRebate } from "../scripts/route_rebate_policy.mjs";

const eligible = evaluateRouteRebate({ directOutRaw: "56019084", btenOutRaw: "52395749", btenIntermediateRaw: "362394", rebateBtenRaw: "25000", rebateFinalOutRaw: "3700000", maxRebateBps: 750, perSwapCapBtenRaw: "1000000" });
assert.equal(eligible.eligible, true);
assert.equal(eligible.allowedRebateBtenRaw, "27179");
const notEligible = evaluateRouteRebate({ directOutRaw: "56019084", btenOutRaw: "52395749", btenIntermediateRaw: "362394", rebateBtenRaw: "25000", rebateFinalOutRaw: "1000000", maxRebateBps: 750, perSwapCapBtenRaw: "1000000" });
assert.equal(notEligible.eligible, false);
assert.throws(() => evaluateRouteRebate({ directOutRaw: "10", btenOutRaw: "9", btenIntermediateRaw: "100", rebateBtenRaw: "8", rebateFinalOutRaw: "2", maxRebateBps: 750, perSwapCapBtenRaw: "100" }));
console.log("route rebate policy tests passed");
