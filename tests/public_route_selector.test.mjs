import assert from "node:assert/strict";
import { selectPublicRoute } from "../scripts/public_route_selector.mjs";

assert.equal(selectPublicRoute({ directOutRaw: "1000000", btenLeg1OutRaw: "500000", btenLeg2OutRaw: "1000200", minImprovementBps: 1 }).selected, "bten-two-hop");
assert.equal(selectPublicRoute({ directOutRaw: "1000000", btenLeg1OutRaw: "500000", btenLeg2OutRaw: "1000099", minImprovementBps: 1 }).selected, "direct");
assert.equal(selectPublicRoute({ directOutRaw: "1000000", directCostOutRaw: "100", btenLeg1OutRaw: "500000", btenLeg2OutRaw: "1000200", btenCostOutRaw: "200", minImprovementBps: 0 }).selected, "bten-two-hop");
console.log("public route selector tests passed");
