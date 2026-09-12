/**
 * Read-only Aftermath Smart Order Router quote.
 *
 * This script never constructs, signs, or submits a transaction.  Block10
 * uses its result only as the independent direct-route comparator before it
 * offers a protected BTEN path.
 *
 * Example:
 *   node scripts/aftermath_router_quote.mjs --in 0x2::sui::SUI --out <TYPE> --amount-raw 2000000
 */
import { Aftermath } from "aftermath-ts-sdk";

function option(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const coinInType = option("--in");
const coinOutType = option("--out");
const amountRaw = option("--amount-raw");
if (!coinInType || !coinOutType || !/^\d+$/.test(amountRaw ?? "") || BigInt(amountRaw) === 0n) {
  console.error("Usage: node scripts/aftermath_router_quote.mjs --in <coin-type> --out <coin-type> --amount-raw <positive-integer>");
  process.exit(2);
}

const sdk = await Aftermath.create({ network: "MAINNET" });
const route = await sdk.Router().getCompleteTradeRouteGivenAmountIn({
  coinInType,
  coinOutType,
  coinInAmount: BigInt(amountRaw),
});

const safe = (value) => typeof value === "bigint" ? value.toString() : value;
console.log(JSON.stringify({
  provider: "Aftermath Smart Order Router",
  mode: "quote-only",
  executable: false,
  coinIn: route.coinIn,
  coinOut: route.coinOut,
  netTradeFeePercentage: route.netTradeFeePercentage,
  routeCount: route.routes.length,
  routes: route.routes,
  note: "Compare this direct-route output with the protected BTEN-path quote. Do not execute an Aftermath-built transaction for a BTEN-gated route.",
}, (_key, value) => safe(value), 2));
