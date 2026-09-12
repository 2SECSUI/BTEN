#!/usr/bin/env node
/**
 * BTEN direct-Cetus event verifier.
 *
 * A narrow public-data keeper: it examines only successful Cetus SwapEvent
 * records from frozen BTEN pools. It never quotes, swaps, transfers treasury
 * funds, or accesses an admin or upgrade capability.
 */
import fs from "node:fs";
import path from "node:path";
import { SuiGrpcClient } from "@mysten/sui/grpc";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";

const root = path.resolve(import.meta.dirname, "..");
const mainnet = JSON.parse(fs.readFileSync(path.join(root, "MAINNET_ROUTE_CONFIG.json"), "utf8"));
const policy = JSON.parse(fs.readFileSync(path.join(root, "config", "keeper_policy.json"), "utf8"));
const EXECUTE = process.argv.includes("--execute");
const GRAPHQL = "https://graphql.mainnet.sui.io/graphql";
const CLOCK = "0x6";
const CETUS_SWAP_EVENT = "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::SwapEvent";
const EXTERNAL_ATTESTATION = `${mainnet.currentPackage}::bten::ExternalCetusRouteAttested`;
const verifier = mainnet.externalCetusVerifier;

if (!verifier?.state || !verifier?.cap || !verifier?.activationAfterMs) throw new Error("External Cetus verifier configuration is incomplete");

function normal(value) { return String(value ?? "").toLowerCase(); }
function positive(value) { try { return BigInt(value ?? 0) > 0n; } catch { return false; } }

function decodeBase58(value) {
  const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  let number = 0n;
  for (const char of value) {
    const index = alphabet.indexOf(char);
    if (index < 0) throw new Error("Invalid base58 transaction digest");
    number = number * 58n + BigInt(index);
  }
  const body = [];
  while (number > 0n) { body.unshift(Number(number & 255n)); number >>= 8n; }
  for (const char of value) { if (char === "1") body.unshift(0); else break; }
  return Uint8Array.from(body);
}

async function graphql(query, variables) {
  const response = await fetch(GRAPHQL, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ query, variables }) });
  if (!response.ok) throw new Error(`GraphQL request failed: ${response.status}`);
  const body = await response.json();
  if (body.errors?.length) throw new Error(body.errors.map((item) => item.message).join("; "));
  return body.data;
}

async function moveFields(address) {
  const data = await graphql("query($address:SuiAddress!){ object(address:$address){ asMoveObject { contents { json } } } }", { address });
  const fields = data?.object?.asMoveObject?.contents?.json;
  if (!fields) throw new Error(`Object ${address} is unavailable`);
  return fields;
}

async function recentPoolTransactions(pool) {
  const data = await graphql(
    `query($pool:SuiAddress!,$limit:Int!){ transactions(last:$limit,filter:{affectedObject:$pool}) { nodes {
      digest sender { address } effects { status timestamp events(last:50) { nodes {
        sequenceNumber sender { address } contents { type { repr } json }
      } } }
    } } }`,
    { pool, limit: verifier.scanTransactionsPerPool ?? 50 },
  );
  return data.transactions.nodes;
}

async function recentAttestations() {
  const data = await graphql(
    `query($type:String!){ events(last:50,filter:{type:$type}) { nodes { contents { json } } } }`,
    { type: EXTERNAL_ATTESTATION },
  );
  return new Set((data.events.nodes ?? []).map((event) => {
    const json = event.contents?.json ?? {};
    return `${json.transaction_digest}:${json.event_sequence}`;
  }));
}

function candidateFromTransaction(transaction, pool) {
  if (transaction.effects?.status !== "SUCCESS") return null;
  const timestamp = Date.parse(transaction.effects?.timestamp ?? "");
  if (!Number.isFinite(timestamp) || timestamp <= Number(verifier.activationAfterMs)) return null;
  const sender = normal(transaction.sender?.address);
  if (!sender) return null;
  const events = transaction.effects?.events?.nodes ?? [];
  // The protected adapter has already made its own on-chain RouteRecorded receipt.
  if (events.some((event) => event.contents?.type?.repr?.endsWith("::bten::RouteRecorded"))) return null;
  const match = events.find((event) => {
    const json = event.contents?.json ?? {};
    return event.contents?.type?.repr === CETUS_SWAP_EVENT
      && normal(json.pool) === normal(pool)
      && normal(event.sender?.address) === sender
      && positive(json.amount_in) && positive(json.amount_out);
  });
  if (!match) return null;
  const digestBytes = decodeBase58(transaction.digest);
  if (digestBytes.length !== 32) return null;
  return {
    digest: transaction.digest, digestBytes, eventSequence: Number(match.sequenceNumber), pool,
    trader: transaction.sender.address, timestamp: transaction.effects.timestamp,
    // Fixed one point prevents token decimal units from inflating rewards.
    feePoints: "1",
  };
}

function keeperSigner() {
  const encoded = process.env.BTEN_KEEPER_PRIVATE_KEY;
  if (!encoded) throw new Error("BTEN_KEEPER_PRIVATE_KEY is required only for --execute");
  const secret = encoded.startsWith("suiprivkey") ? decodeSuiPrivateKey(encoded).secretKey : Uint8Array.from(Buffer.from(encoded, "base64")).slice(1);
  const signer = Ed25519Keypair.fromSecretKey(secret);
  if (normal(signer.toSuiAddress()) !== normal(policy.keeperAddress)) throw new Error("GitHub secret does not match the dedicated keeper address");
  if (normal(signer.toSuiAddress()) === normal(policy.opsAddress)) throw new Error("Ops wallet is forbidden as a GitHub keeper");
  return signer;
}

async function submit(client, signer, candidate) {
  const tx = new Transaction();
  tx.setSender(policy.keeperAddress);
  tx.setGasBudget(BigInt(policy.settlement.gasBudgetMist));
  tx.moveCall({ target: `${mainnet.currentPackage}::bten::attest_external_cetus_route`, arguments: [
    tx.object(mainnet.emissionState), tx.object(mainnet.poolRegistry), tx.object(verifier.state), tx.object(verifier.cap),
    tx.pure.address(candidate.pool), tx.pure.vector("u8", candidate.digestBytes), tx.pure.u64(candidate.eventSequence),
    tx.pure.address(candidate.trader), tx.pure.u64(candidate.feePoints), tx.object(CLOCK),
  ] });
  const result = await client.signAndExecuteTransaction({ signer, transaction: tx, include: { effects: true, events: true } });
  const submittedDigest = result.digest ?? result.transaction?.digest ?? result.Transaction?.digest ?? null;
  const eventKey = `${Buffer.from(candidate.digestBytes).toString("base64")}:${candidate.eventSequence}`;
  // The public BTEN event is the canonical success proof. This avoids coupling
  // keeper correctness to differing Sui gRPC response-shapes across runners.
  for (let attempt = 0; attempt < 4; attempt += 1) {
    if ((await recentAttestations()).has(eventKey)) return submittedDigest;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(`No on-chain attestation event was found for ${candidate.digest}`);
}

const pools = mainnet.venues.flatMap((venue) => venue.name === "cetus" && venue.enabled ? venue.pools : []);
const [state, attestations, batches] = await Promise.all([
  moveFields(verifier.state),
  recentAttestations(),
  Promise.all(pools.map(async (pool) => (await recentPoolTransactions(pool))
    .map((tx) => candidateFromTransaction(tx, pool))
    .filter(Boolean))),
]);
const byDigest = new Map();
for (const candidate of batches.flat()) {
  // A routed transaction can touch multiple BTEN pools; it earns one gate only.
  const current = byDigest.get(candidate.digest);
  if (!current || candidate.eventSequence < current.eventSequence) byDigest.set(candidate.digest, candidate);
}
const remainingDaily = Math.max(0, Number(state.daily_event_cap) - Number(state.events_today));
const candidates = [...byDigest.values()]
  .filter((candidate) => !attestations.has(`${Buffer.from(candidate.digestBytes).toString("base64")}:${candidate.eventSequence}`))
  .sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp))
  .slice(0, Math.min(remainingDaily, verifier.maxEventsPerRun ?? 10));
const report = {
  mode: EXECUTE ? "execute" : "dry-run",
  verifier: { state: verifier.state, paused: Boolean(state.paused), eventsToday: String(state.events_today), dailyEventCap: String(state.daily_event_cap) },
  policy: { activationAfterMs: String(verifier.activationAfterMs), fixedFeePoints: "1", oneReceiptPerTransaction: true, scannedPools: pools.length, alreadyAttestedInPublicLog: attestations.size },
  candidates: candidates.map(({ digest, eventSequence, pool, trader, timestamp, feePoints }) => ({ digest, eventSequence, pool, trader, timestamp, feePoints })),
  submitted: [],
};

if (!EXECUTE || state.paused || candidates.length === 0) {
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

const client = new SuiGrpcClient({ network: "mainnet", baseUrl: "https://fullnode.mainnet.sui.io:443" });
const signer = keeperSigner();
for (const candidate of candidates) report.submitted.push({ digest: candidate.digest, attestation: await submit(client, signer, candidate) });
console.log(JSON.stringify(report, null, 2));
