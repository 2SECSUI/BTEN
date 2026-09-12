#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => JSON.parse(fs.readFileSync(path.join(root, file), 'utf8'));
const lp = read('config/lp_program_policy.json');
const dapp = read('config/block10_integration.json');
const keeper = read('config/keeper_policy.json');
const address = /^0x[0-9a-f]+$/i;
const fail = (message) => { throw new Error(message); };

if (lp.network !== 'mainnet' || dapp.network !== 'mainnet') fail('all launch configuration must target mainnet');
if (lp.allocation.redirectedEmissionBps !== 3000 || lp.allocation.protocolOwnedLiquidityBps !== 10_000) fail('all redirected LP allocation must become protocol-owned liquidity');
if (lp.pools.reduce((total, pool) => total + pool.weightBps, 0) !== 10_000) fail('LP pool weights must sum to 10,000 bps');
if (new Set(lp.pools.map((pool) => pool.poolId.toLowerCase())).size !== lp.pools.length) fail('LP pool IDs must be unique');
for (const pool of lp.pools) if (!address.test(pool.poolId) || pool.weightBps <= 0) fail(`invalid pool configuration: ${pool.pair}`);
for (const [field, value] of Object.entries(dapp)) if (/key|secret|mnemonic|private/i.test(field) || (typeof value === 'string' && /suiprivkey|mnemonic/i.test(value))) fail(`sensitive value prohibited in public dapp config: ${field}`);
if (!dapp.walletPolicy.userPaysGas || dapp.walletPolicy.sponsorshipEnabled) fail('initial launch must remain wallet-paid with sponsorship disabled');
if (keeper.lpProgrammeAccrual?.enabled && !keeper.lpProgrammeAccrual?.state) fail('LP accrual cannot be enabled without its deployed shared-state ID');
console.log(JSON.stringify({ ok: true, pools: lp.pools.length, dapp: dapp.dapp, sponsorshipEnabled: dapp.walletPolicy.sponsorshipEnabled }, null, 2));
