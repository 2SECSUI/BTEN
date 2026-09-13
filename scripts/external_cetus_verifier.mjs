#!/usr/bin/env node
/**
 * BTEN direct-Cetus event verifier.
 *
 * Narrow public-data keeper: examines successful Cetus SwapEvent records from
 * registered BTEN pools and attests them so they count as gated for emission
 * block release (`attest_external_cetus_route` -> `record_atomic_route` ->
 * `batch_trades` / settle unlock). Live-tape labeling is not the gate.
 * One emission-gate receipt per transaction digest, including multi-pool
 * aggregator PTBs. It never quotes, swaps, transfers treasury funds, or
 * prints private keys.
 *
 * Usage:
 *   node scripts/external_cetus_verifier.mjs              # dry-run scan
 *   node scripts/external_cetus_verifier.mjs --digest <tx> # dry-run one digest
 *   node scripts/external_cetus_verifier.mjs --execute    # submit attestations
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
const digestFlagIndex = process.argv.indexOf("--digest");
const TARGET_DIGEST = digestFlagIndex >= 0 ? String(process.argv[digestFlagIndex + 1] ?? "").trim() : "";
const GRAPHQL = "https://graphql.mainnet.sui.io/graphql";
const CLOCK = "0x6";
const CETUS_SWAP_EVENT = "0x1eabed72c53feb3805120a081dc15963c204dc8d091542592abaf7a35689b2fb::pool::SwapEvent";
const verifier = mainnet.externalCetusVerifier;

if (!verifier?.state || !verifier?.cap || !verifier?.activationAfterMs) {
  throw new Error("External Cetus verifier configuration is incomplete");
}

function readPublishedTomlPackageIds() {
  const publishedPath = path.join(root, "Published.toml");
  if (!fs.existsSync(publishedPath)) return {};
  const text = fs.readFileSync(publishedPath, "utf8");
  const mainnetSection = text.split("[published.mainnet]")[1]?.split("[")[0] ?? "";
  const publishedAt = /published-at\s*=\s*"([^"]+)"/.exec(mainnetSection)?.[1];
  const originalId = /original-id\s*=\s*"([^"]+)"/.exec(mainnetSection)?.[1];
  return { publishedAt, originalId };
}

function resolvePackageIds() {
  const published = readPublishedTomlPackageIds();
  const livePackageId = normalHex(
    mainnet.livePackageId
      || verifier.livePackageId
      || mainnet.currentPackage
      || published.publishedAt,
  );
  const originalPackageId = normalHex(
    mainnet.originalPackageId
      || verifier.originalPackageId
      || published.originalId
      || "0x31c6c71184b08a574bd62fa8edd9a75aab9a986427484cf765a1890ce00aece0",
  );
  if (!livePackageId) throw new Error("Unable to resolve livePackageId from MAINNET_ROUTE_CONFIG / Published.toml");
  return { livePackageId, originalPackageId };
}

function normal(value) { return String(value ?? "").toLowerCase(); }
function normalHex(value) {
  const text = String(value ?? "").trim().toLowerCase();
  return text || null;
}
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

/** Normalize GraphQL/Move JSON vector<u8> forms to raw 32 bytes. */
function digestBytesFromJson(value) {
  if (value == null) return null;
  if (Array.isArray(value)) {
    const bytes = Uint8Array.from(value.map((item) => Number(item)));
    return bytes.length === 32 ? bytes : null;
  }
  if (typeof value === "object") {
    if (Array.isArray(value.bytes)) return digestBytesFromJson(value.bytes);
    if (typeof value.bytes === "string") return digestBytesFromJson(value.bytes);
    if (typeof value.data === "string" || Array.isArray(value.data)) return digestBytesFromJson(value.data);
  }
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (/^[1-9A-HJ-NP-Za-km-z]+$/.test(trimmed) && trimmed.length >= 40) {
      try {
        const decoded = decodeBase58(trimmed);
        if (decoded.length === 32) return decoded;
      } catch { /* fall through */ }
    }
    if (/^(0x)?[0-9a-fA-F]{64}$/.test(trimmed)) {
      const hex = trimmed.replace(/^0x/i, "");
      return Uint8Array.from(Buffer.from(hex, "hex"));
    }
    try {
      const b64 = Buffer.from(trimmed, "base64");
      if (b64.length === 32) return new Uint8Array(b64);
    } catch { /* ignore */ }
  }
  return null;
}

/** Canonical attestation map key: base64(32-byte digest):event_sequence */
function attestationKey(digestBytes, eventSequence) {
  return `${Buffer.from(digestBytes).toString("base64")}:${Number(eventSequence)}`;
}

function attestationKeyFromEventJson(json) {
  const digestBytes = digestBytesFromJson(json?.transaction_digest);
  if (!digestBytes) return null;
  return attestationKey(digestBytes, json.event_sequence);
}

async function graphql(query, variables) {
  const response = await fetch(GRAPHQL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ query, variables }),
  });
  if (!response.ok) throw new Error(`GraphQL request failed: ${response.status}`);
  const body = await response.json();
  if (body.errors?.length) throw new Error(body.errors.map((item) => item.message).join("; "));
  return body.data;
}

async function moveFields(address) {
  const data = await graphql(
    "query($address:SuiAddress!){ object(address:$address){ asMoveObject { contents { json } } } }",
    { address },
  );
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

async function fetchTransactionByDigest(digest) {
  const data = await graphql(
    `query($digest:String!){ transaction(digest:$digest) {
      digest sender { address } effects { status timestamp events(last:50) { nodes {
        sequenceNumber sender { address } contents { type { repr } json }
      } } }
    } }`,
    { digest },
  );
  return data?.transaction ?? null;
}

async function recentAttestations(eventTypes) {
  const keys = new Set();
  for (const type of eventTypes) {
    const data = await graphql(
      `query($type:String!){ events(last:50,filter:{type:$type}) { nodes { contents { json } } } }`,
      { type },
    );
    for (const event of data.events.nodes ?? []) {
      const key = attestationKeyFromEventJson(event.contents?.json ?? {});
      if (key) keys.add(key);
    }
  }
  return keys;
}

function candidateFromTransaction(transaction, pool) {
  if (!transaction || transaction.effects?.status !== "SUCCESS") return null;
  const timestamp = Date.parse(transaction.effects?.timestamp ?? "");
  if (!Number.isFinite(timestamp) || timestamp <= Number(verifier.activationAfterMs)) return null;
  const sender = normal(transaction.sender?.address);
  if (!sender) return null;
  const events = transaction.effects?.events?.nodes ?? [];
  // Protected adapter already emitted RouteRecorded — already emission-gated.
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
    digest: transaction.digest,
    digestBytes,
    eventSequence: Number(match.sequenceNumber),
    pool,
    trader: transaction.sender.address,
    timestamp: transaction.effects.timestamp,
    // Fixed one point prevents token decimal units from inflating rewards.
    feePoints: "1",
  };
}

function keeperSigner() {
  const encoded = process.env.BTEN_KEEPER_PRIVATE_KEY;
  if (!encoded) throw new Error("BTEN_KEEPER_PRIVATE_KEY is required only for --execute");
  const secret = encoded.startsWith("suiprivkey")
    ? decodeSuiPrivateKey(encoded).secretKey
    : Uint8Array.from(Buffer.from(encoded, "base64")).slice(1);
  const signer = Ed25519Keypair.fromSecretKey(secret);
  if (normal(signer.toSuiAddress()) !== normal(policy.keeperAddress)) {
    throw new Error("GitHub secret does not match the dedicated keeper address");
  }
  if (normal(signer.toSuiAddress()) === normal(policy.opsAddress)) {
    throw new Error("Ops wallet is forbidden as a GitHub keeper");
  }
  return signer;
}

async function submit(client, signer, candidate, livePackageId, eventTypes) {
  const tx = new Transaction();
  tx.setSender(policy.keeperAddress);
  tx.setGasBudget(BigInt(policy.settlement.gasBudgetMist));
  tx.moveCall({
    target: `${livePackageId}::bten::attest_external_cetus_route`,
    arguments: [
      tx.object(mainnet.emissionState),
      tx.object(mainnet.poolRegistry),
      tx.object(verifier.state),
      tx.object(verifier.cap),
      tx.pure.address(candidate.pool),
      tx.pure.vector("u8", candidate.digestBytes),
      tx.pure.u64(candidate.eventSequence),
      tx.pure.address(candidate.trader),
      tx.pure.u64(candidate.feePoints),
      tx.object(CLOCK),
    ],
  });
  let result;
  try {
    result = await client.signAndExecuteTransaction({
      signer,
      transaction: tx,
      include: { effects: true, events: true },
    });
  } catch (error) {
    // On-chain processed table is the authoritative replay guard.
    if (String(error?.message ?? error).includes("abort code: 30")) return null;
    throw error;
  }
  const submittedDigest = result.digest ?? result.transaction?.digest ?? result.Transaction?.digest ?? null;
  const eventKey = attestationKey(candidate.digestBytes, candidate.eventSequence);
  for (let attempt = 0; attempt < 4; attempt += 1) {
    if ((await recentAttestations(eventTypes)).has(eventKey)) return submittedDigest;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(`No on-chain attestation event was found for ${candidate.digest}`);
}

const { livePackageId, originalPackageId } = resolvePackageIds();
const eventTypes = [...new Set([
  ...(verifier.eventTypes ?? []),
  `${livePackageId}::bten::ExternalCetusRouteAttested`,
  `${originalPackageId}::bten::ExternalCetusRouteAttested`,
].filter(Boolean))];

const pools = mainnet.venues.flatMap((venue) => (
  venue.name === "cetus" && venue.enabled ? venue.pools : []
));

const [state, attestations] = await Promise.all([
  moveFields(verifier.state),
  recentAttestations(eventTypes),
]);

let batches;
if (TARGET_DIGEST) {
  const transaction = await fetchTransactionByDigest(TARGET_DIGEST);
  if (!transaction) {
    console.log(JSON.stringify({
      mode: "dry-run",
      error: `Transaction ${TARGET_DIGEST} not found`,
      livePackageId,
      eventTypes,
    }, null, 2));
    process.exit(1);
  }
  batches = [pools
    .map((pool) => candidateFromTransaction(transaction, pool))
    .filter(Boolean)];
} else {
  batches = await Promise.all(pools.map(async (pool) => (await recentPoolTransactions(pool))
    .map((tx) => candidateFromTransaction(tx, pool))
    .filter(Boolean)));
}

const byDigest = new Map();
for (const candidate of batches.flat()) {
  // Multi-pool aggregator PTBs (e.g. 7K through BTEN/SUI + BTEN/MAGMA) earn ONE gate receipt.
  const current = byDigest.get(candidate.digest);
  if (!current || candidate.eventSequence < current.eventSequence) {
    byDigest.set(candidate.digest, candidate);
  }
}

const remainingDaily = Math.max(0, Number(state.daily_event_cap) - Number(state.events_today));
const candidates = [...byDigest.values()]
  .filter((candidate) => !attestations.has(attestationKey(candidate.digestBytes, candidate.eventSequence)))
  .sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp))
  .slice(0, TARGET_DIGEST ? 1 : Math.min(remainingDaily, verifier.maxEventsPerRun ?? 10));

const report = {
  mode: EXECUTE ? "execute" : "dry-run",
  targetDigest: TARGET_DIGEST || null,
  packages: { livePackageId, originalPackageId, eventTypes },
  verifier: {
    state: verifier.state,
    paused: Boolean(state.paused),
    eventsToday: String(state.events_today),
    dailyEventCap: String(state.daily_event_cap),
  },
  policy: {
    activationAfterMs: String(verifier.activationAfterMs),
    fixedFeePoints: "1",
    oneReceiptPerTransaction: true,
    treatAllLiveTapeAsGated: true,
    blockTransactions: false,
    scannedPools: pools.length,
    alreadyAttestedInPublicLog: attestations.size,
    attestationKeyFormat: "base64(digest):event_sequence",
  },
  candidates: candidates.map(({ digest, eventSequence, pool, trader, timestamp, feePoints }) => ({
    digest, eventSequence, pool, trader, timestamp, feePoints,
  })),
  submitted: [],
};

if (!EXECUTE || state.paused || candidates.length === 0) {
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

const client = new SuiGrpcClient({ network: "mainnet", baseUrl: "https://fullnode.mainnet.sui.io:443" });
const signer = keeperSigner();
for (const candidate of candidates) {
  report.submitted.push({
    digest: candidate.digest,
    attestation: await submit(client, signer, candidate, livePackageId, eventTypes),
  });
}
console.log(JSON.stringify(report, null, 2));
