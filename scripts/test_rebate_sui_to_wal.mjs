#!/usr/bin/env node
/**
 * Reproducible protected SUI -> BTEN -> WAL rebate route test.
 * Default mode simulates; pass --execute only for the approved tiny live test.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { CetusClmmSDK } from "@cetusprotocol/sui-clmm-sdk";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction, coinWithBalance } from "@mysten/sui/transactions";

const OWNER = "0x58189b677894e0fe7ad38e0e516408a3500da57d86fc0436373bc1d9c6334d0a";
const PACKAGE = "0xc71c7ab810ba15ea337dc7722e8eaac4e3c7e631cf3557f70167783f1f3bcc41";
const STATE = "0x22face12e4a73bc38171c5a2dd62a1cef8650bac3abc95eb5d3852ee36544253";
const TREASURY = "0xf1992cffa7d4980cd03f37a114bd49fc01a1edef09213cffaec7c0f081fa23ce";
const REBATE = "0x3ee90e618bc814feb124b4a783ff43015777945d30d98f6857953dbb3ed818c8";
const REGISTRY = "0xc78a803d7acc6e9740911802e382a45c347e0fb012613a908eb0738c4957d133";
const CONFIG = "0xdaa46292632c3c4d8f31f23ea0f9b36a28ff3677e9684980e4438403a67a3d8f";
const SUI = "0x2::sui::SUI";
const BTEN = "0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0::bten::BTEN";
const WAL = "0x356a26eb9e012a68958082340d4c4116e7f55615cf27affcff209cf0ae544f59::wal::WAL";
const SUI_BTEN_POOL = "0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950";
const WAL_BTEN_POOL = "0xa9f12a204ac1cb778c015e77a88fc8eb5926599ece17b2a8841753c7712544c7";
const MIN_SQRT = "4295048016";
const MAX_SQRT = "79226673515401279992447579055";
const amount = BigInt(process.argv.includes("--amount-raw") ? process.argv[process.argv.indexOf("--amount-raw") + 1] : "2000000");
const rebate = BigInt(process.argv.includes("--rebate-raw") ? process.argv[process.argv.indexOf("--rebate-raw") + 1] : "25000");
const execute = process.argv.includes("--execute");
if (amount <= 0n || rebate <= 0n || rebate > 1_000_000n) throw new Error("invalid test amount or rebate cap");

const client = new SuiGrpcClient({ network: "mainnet", baseUrl: "https://fullnode.mainnet.sui.io:443" });
const sdk = CetusClmmSDK.createSDK({ env: "mainnet" });
const [suiPool, walPool, walMeta] = await Promise.all([
  sdk.Pool.getPool(SUI_BTEN_POOL, true), sdk.Pool.getPool(WAL_BTEN_POOL, true), client.getCoinMetadata({ coinType: WAL }),
]);
const isA = (pool, type) => pool.coin_type_a.toLowerCase() === type.toLowerCase();
const suiIsA = isA(suiPool, SUI);
const btenIsA = isA(walPool, BTEN);
const preSwap = async (pool, a2b, raw, decimalsA, decimalsB) => {
  const q = await sdk.Swap.preSwap({ pool, current_sqrt_price: Number(pool.current_sqrt_price), decimals_a: decimalsA, decimals_b: decimalsB, a2b, by_amount_in: true, amount: raw.toString(), coin_type_a: pool.coin_type_a, coin_type_b: pool.coin_type_b });
  const out = BigInt(q.estimated_amount_out ?? 0);
  if (q.is_exceed || out <= 0n) throw new Error("no safe Cetus quote");
  return out;
};
const btenOut = await preSwap(suiPool, suiIsA, amount, suiIsA ? 9 : 8, suiIsA ? 8 : 9);
const walOut = await preSwap(walPool, btenIsA, btenOut + rebate, btenIsA ? 8 : Number(walMeta.decimals), btenIsA ? Number(walMeta.decimals) : 8);
const tx = new Transaction();
tx.setSender(OWNER);
tx.setGasBudget(30_000_000);
const input = tx.add(coinWithBalance({ balance: amount, type: SUI }));
tx.moveCall({
  target: `${PACKAGE}::bten::${btenIsA ? "cetus_sui_to_asset_via_bten_rebate_a2b" : "cetus_sui_to_asset_via_bten_rebate_b2a"}`,
  typeArguments: [WAL],
  arguments: [tx.object(STATE), tx.object(TREASURY), tx.object(REBATE), tx.object(REGISTRY), tx.object(CONFIG), tx.object(SUI_BTEN_POOL), tx.object(WAL_BTEN_POOL), input, tx.pure.u64(rebate), tx.pure.u64(walOut * 95n / 100n), tx.pure.u128(suiIsA ? MIN_SQRT : MAX_SQRT), tx.pure.u128(btenIsA ? MIN_SQRT : MAX_SQRT), tx.object("0x6")],
});
function signer() {
  const keystore = path.join(process.env.SUI_CONFIG_DIR ?? path.join(os.homedir(), ".sui", "sui_config"), "sui.keystore");
  for (const encoded of JSON.parse(fs.readFileSync(keystore, "utf8"))) try {
    const secret = encoded.startsWith("suiprivkey") ? decodeSuiPrivateKey(encoded).secretKey : Uint8Array.from(Buffer.from(encoded, "base64")).slice(1);
    const key = Ed25519Keypair.fromSecretKey(secret);
    if (key.toSuiAddress().toLowerCase() === OWNER) return key;
  } catch {}
  throw new Error("ops signer unavailable");
}
const result = execute ? await client.signAndExecuteTransaction({ signer: signer(), transaction: tx, include: { effects: true, events: true, balanceChanges: true } }) : await client.simulateTransaction({ transaction: tx, include: { effects: true, events: true, balanceChanges: true } });
const done = result.Transaction ?? result;
const events = done.events ?? [];
console.log(JSON.stringify({ mode: execute ? "executed" : "dry-run", inputSuiRaw: amount.toString(), quotedBtenRaw: btenOut.toString(), requestedRebateBtenRaw: rebate.toString(), quotedWalRaw: walOut.toString(), minWalRaw: (walOut * 95n / 100n).toString(), digest: done.digest, status: done.effects?.status ?? done.status, routeRecorded: events.some((e) => String(e.eventType ?? "").includes("RouteRecorded")), rebatePaid: events.some((e) => String(e.eventType ?? "").includes("RouteRebatePaid")) }, null, 2));
if ((done.effects?.status ?? done.status)?.status !== "success") process.exit(1);
