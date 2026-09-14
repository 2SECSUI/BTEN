#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const lp = read('config/lp_program_policy.json');
const dapp = read('config/block10_integration.json');
const keeper = read('config/keeper_policy.json');
const farm = read('config/bten_staking_farm.json');
const address = /^0x[0-9a-f]+$/i;
const fail = (message) => { throw new Error(message); };

if (lp.network !== 'mainnet' || dapp.network !== 'mainnet') fail('all launch configuration must target mainnet');
if (lp.allocation.redirectedEmissionBps !== 3000 || lp.allocation.protocolOwnedLiquidityBps !== 10_000) fail('all redirected LP allocation must become protocol-owned liquidity');
if (lp.pools.reduce((total, pool) => total + pool.weightBps, 0) !== 10_000) fail('LP pool weights must sum to 10,000 bps');
if (new Set(lp.pools.map((pool) => pool.poolId.toLowerCase())).size !== lp.pools.length) fail('LP pool IDs must be unique');
for (const pool of lp.pools) if (!address.test(pool.poolId) || pool.weightBps <= 0) fail(`invalid pool configuration: ${pool.pair}`);
for (const [field, value] of Object.entries(dapp)) if (/key|secret|mnemonic|private/i.test(field) || (typeof value === 'string' && /suiprivkey|mnemonic/i.test(value))) fail(`sensitive value prohibited in public dapp config: ${field}`);

const wallet = dapp.walletPolicy ?? {};
if (wallet.userPaysGas !== true) fail('userPaysGas must remain true so sponsorship can fall back to wallet-paid gas');
if (wallet.neverEmbedPrivateKeys !== true) fail('neverEmbedPrivateKeys must remain true');

const sponsorship = dapp.sponsorship ?? {};
const policyFile = wallet.sponsorshipPolicyFile || sponsorship.policyFile;
if (wallet.sponsorshipEnabled === true) {
  if (sponsorship.enabled !== true) fail('sponsorshipEnabled requires dapp.sponsorship.enabled === true');
  if (!policyFile || typeof policyFile !== 'string') fail('sponsorshipEnabled requires walletPolicy.sponsorshipPolicyFile or sponsorship.policyFile');
  const policyPath = path.join(root, policyFile);
  if (!fs.existsSync(policyPath)) fail(`sponsorship policy file missing: ${policyFile}`);
} else if (wallet.sponsorshipEnabled !== false && wallet.sponsorshipEnabled != null) {
  fail('walletPolicy.sponsorshipEnabled must be a boolean');
}

if (keeper.lpProgrammeAccrual?.enabled && !keeper.lpProgrammeAccrual?.state) fail('LP accrual cannot be enabled without its deployed shared-state ID');
if (keeper.nativeFarmSync?.enabled && !address.test(keeper.nativeFarmSync?.state ?? '')) fail('native farm sync cannot be enabled without its deployed shared-state ID');
if (farm.network !== 'mainnet' || farm.coinType !== dapp.coinType) fail('farm must use the configured mainnet BTEN coin');
if (farm.farmObjectId !== null && !address.test(farm.farmObjectId)) fail('farm object ID must be null before deployment or a valid Sui address after deployment');
if (farm.status === 'active' && !address.test(farm.farmObjectId ?? '')) fail('an active farm requires its on-chain object ID');
console.log(JSON.stringify({
  ok: true,
  pools: lp.pools.length,
  dapp: dapp.dapp,
  sponsorshipEnabled: wallet.sponsorshipEnabled === true,
  sponsorshipPolicyFile: policyFile ?? null,
  publishedVersion: dapp.publishedVersion ?? null,
  currentPackage: dapp.currentPackage ?? null,
}, null, 2));
