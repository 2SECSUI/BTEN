/** Read-only Hop Aggregator quote for Block10 route comparison. */
import { HopApi } from "@hop.ag/sdk";

function option(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const coinInType = option("--in");
const coinOutType = option("--out");
const amountRaw = option("--amount-raw");
if (!coinInType || !coinOutType || !/^\d+$/.test(amountRaw ?? "") || BigInt(amountRaw) === 0n) {
  console.error("Usage: node scripts/hop_router_quote.mjs --in <coin-type> --out <coin-type> --amount-raw <positive-integer>");
  process.exit(2);
}

const quote = await new HopApi().quote({
  coin_in: coinInType,
  coin_out: coinOutType,
  amount_in: BigInt(amountRaw),
});

console.log(JSON.stringify({
  provider: "Hop Aggregator",
  mode: "quote-only",
  executable: false,
  quote,
  note: "Compare this output with the protected BTEN path. Do not build or submit a Hop transaction for a BTEN-gated route.",
}, (_key, value) => typeof value === "bigint" ? value.toString() : value, 2));
