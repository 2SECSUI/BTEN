/// BlockTen (BTEN) is a fixed-cap, trade-gated emission token.
///
/// This package intentionally separates three concerns:
/// - `EmissionState` schedules the 50-BTEN, ten-minute block emissions.
/// - A route executor records only completed, qualifying routes.
/// - `PoolRegistry` lists the LP positions eligible for incentives.
///
/// Qualifying routes are recorded only by adapters that complete their swap in
/// the same transaction. The retained `RouterCap` entry is deliberately
/// disabled for upgrade compatibility with the development deployment.
module bten::bten {
    use std::ascii;
    use std::string;
    use std::option;
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::event;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url;
    use cetusclmm::config::GlobalConfig;
    use cetusclmm::pool::{Self, Pool};

    const DECIMALS: u8 = 8;
    const UNIT: u64 = 100_000_000;
    const MAX_SUPPLY: u64 = 2_100_000_000_000_000;
    const INITIAL_SUBSIDY: u64 = 50 * UNIT;
    const BLOCK_TIME_SECS: u64 = 600;
    const HALVING_INTERVAL: u64 = 210_000;
    const MIN_TRADES_PER_BLOCK: u64 = 10;
    const MAX_SETTLE_BLOCKS: u64 = 100;
    const BPS: u64 = 10_000;

    const ROUTE_VAULT_BPS: u64 = 5_000;
    const TRADER_BPS: u64 = 1_000;
    const BTEN_LP_BPS: u64 = 2_500;
    const STAKING_BPS: u64 = 1_000;
    const CETUS_BPS: u64 = 100;
    const HAEDAL_BPS: u64 = 100;
    const BLUE_BPS: u64 = 100;
    const TURBOS_BPS: u64 = 100;
    const SUI_GAS_BPS: u64 = 100;
    const BUCKET_BTEN_LP: u8 = 0;
    const BUCKET_CETUS: u8 = 1;
    const BUCKET_BLUE: u8 = 2;
    const BUCKET_TURBOS: u8 = 3;
    const BUCKET_SUI_GAS: u8 = 4;
    const BUCKET_HAEDAL: u8 = 5;
    const MAX_BUCKET: u8 = BUCKET_HAEDAL;

    const E_BAD_AMOUNT: u64 = 0;
    const E_NO_ELIGIBLE_BLOCKS: u64 = 1;
    const E_CAP_EXCEEDED: u64 = 2;
    const E_BAD_BUCKET: u64 = 3;
    const E_DUPLICATE_POOL: u64 = 4;
    const E_REGISTRY_FINAL: u64 = 5;
    const E_UNKNOWN_ROUND: u64 = 6;
    const E_NOTHING_TO_PAY: u64 = 7;
    const E_UNREGISTERED_POOL: u64 = 8;
    const E_POOL_FUNDING_BUCKET: u64 = 9;
    const E_GENESIS_ALREADY_RELEASED: u64 = 10;
    const E_LEGACY_ROUTE_DISABLED: u64 = 11;
    const E_POOL_NOT_REGISTERED: u64 = 12;
    const E_MIN_OUTPUT: u64 = 13;
    const E_ZERO_INPUT: u64 = 14;

    public struct BTEN has drop {}

    /// Held during the development/test phase only. The final router replaces
    /// this capability with an internal call made after the atomic swap.
    public struct RouterCap has key, store { id: UID }

    /// Held during setup so exact live pool IDs can be registered. Destroy it
    /// after the initial pool set is tested and the registry is finalized.
    public struct RegistryAdminCap has key, store { id: UID }

    public struct PoolRegistry has key {
        id: UID,
        pools: Table<address, u8>,
        finalized: bool,
    }

    /// A receipt key is immutable once the qualifying atomic route succeeds.
    /// It lets a keeper pay the trader later without making the trader submit
    /// a redemption transaction.
    public struct PointKey has copy, drop, store {
        round: u64,
        trader: address,
    }

    public struct TraderRound has copy, drop, store {
        total_points: u64,
        reward_total: u64,
        reward_paid: u64,
    }

    /// Shared state holding the only TreasuryCap. There is no public mint.
    /// Every newly issued BTEN must pass through `settle` and its fixed split.
    public struct EmissionState has key {
        id: UID,
        cap: TreasuryCap<BTEN>,
        total_minted: u64,
        block_height: u64,
        last_slot_ts: u64,
        pending_blocks: u64,
        batch_trades: u64,
        batch_fee_points: u64,
        current_round: u64,
        trader_points: Table<PointKey, u64>,
        trader_rounds: Table<u64, TraderRound>,
        route_fee_vault: Balance<BTEN>,
        trader_vault: Balance<BTEN>,
        bten_lp_vault: Balance<BTEN>,
        staking_vault: Balance<BTEN>,
        cetus_vault: Balance<BTEN>,
        haedal_vault: Balance<BTEN>,
        blue_vault: Balance<BTEN>,
        // Field name is retained for testnet upgrade compatibility with v1;
        // its allocation is now the Turbos LP bucket.
        magma_vault: Balance<BTEN>,
        sui_gas_vault: Balance<BTEN>,
    }

    public struct RouteRecorded has copy, drop {
        trader: address,
        fee_points: u64,
        batch_trades: u64,
    }

    public struct BlocksReleased has copy, drop {
        blocks: u64,
        emission: u64,
        remaining_pending: u64,
    }

    public struct TraderPaid has copy, drop {
        round: u64,
        trader: address,
        amount: u64,
    }

    #[test_only]
    public fun initialize_for_testing(ctx: &mut TxContext) { init(BTEN {}, ctx) }

    fun init(witness: BTEN, ctx: &mut TxContext) {
        let publisher = tx_context::sender(ctx);
        let (cap, metadata) = coin::create_currency<BTEN>(
            witness,
            DECIMALS,
            b"BTEN",
            b"BlockTen",
            b"Trade-gated, fixed-cap routing token",
            option::none(),
            ctx,
        );
        transfer::public_transfer(metadata, publisher);
        transfer::public_transfer(RouterCap { id: object::new(ctx) }, publisher);
        transfer::public_transfer(RegistryAdminCap { id: object::new(ctx) }, publisher);
        transfer::share_object(PoolRegistry {
            id: object::new(ctx),
            pools: table::new(ctx),
            finalized: false,
        });
        transfer::share_object(EmissionState {
            id: object::new(ctx),
            cap,
            total_minted: 0,
            block_height: 0,
            last_slot_ts: 0,
            pending_blocks: 0,
            batch_trades: 0,
            batch_fee_points: 0,
            current_round: 0,
            trader_points: table::new(ctx),
            trader_rounds: table::new(ctx),
            route_fee_vault: balance::zero<BTEN>(),
            trader_vault: balance::zero<BTEN>(),
            bten_lp_vault: balance::zero<BTEN>(),
            staking_vault: balance::zero<BTEN>(),
            cetus_vault: balance::zero<BTEN>(),
            haedal_vault: balance::zero<BTEN>(),
            blue_vault: balance::zero<BTEN>(),
            magma_vault: balance::zero<BTEN>(),
            sui_gas_vault: balance::zero<BTEN>(),
        });
    }

    /// Retained solely for ABI compatibility with the development deployment.
    /// It is permanently disabled: a RouterCap can no longer create rewards.
    public fun record_qualified_route(
        state: &mut EmissionState,
        _router_cap: &RouterCap,
        fee_points: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        abort E_LEGACY_ROUTE_DISABLED
    }

    /// Swap a non-BTEN pool asset into BTEN through an approved Cetus pool.
    /// The received BTEN and any unused input are returned atomically to the
    /// caller only after the Cetus flash-swap repayment succeeds. Route points
    /// use the actual input paid by Cetus, never a caller-supplied value.
    public entry fun cetus_swap_to_bten<A>(
        state: &mut EmissionState,
        registry: &PoolRegistry,
        config: &GlobalConfig,
        pool: &mut Pool<A, BTEN>,
        mut input: Coin<A>,
        min_bten_out: u64,
        sqrt_price_limit: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let pool_id = object::id(pool);
        let pool_address = object::id_to_address(&pool_id);
        assert!(table::contains(&registry.pools, pool_address), E_POOL_NOT_REGISTERED);
        assert!(*table::borrow(&registry.pools, pool_address) == BUCKET_CETUS, E_POOL_NOT_REGISTERED);
        let requested = coin::value(&input);
        assert!(requested > 0, E_ZERO_INPUT);
        let (receive_a, receive_b, receipt) = pool::flash_swap<A, BTEN>(
            config, pool, true, true, requested, sqrt_price_limit, clock
        );
        let paid = pool::swap_pay_amount(&receipt);
        let out = balance::value(&receive_b);
        assert!(out >= min_bten_out, E_MIN_OUTPUT);
        let pay_a = coin::into_balance(coin::split(&mut input, paid, ctx));
        pool::repay_flash_swap(config, pool, pay_a, balance::zero<BTEN>(), receipt);
        coin::join(&mut input, coin::from_balance(receive_a, ctx));
        record_atomic_route(state, paid, clock, tx_context::sender(ctx));
        transfer::public_transfer(input, tx_context::sender(ctx));
        transfer::public_transfer(coin::from_balance(receive_b, ctx), tx_context::sender(ctx));
    }

    /// Swap BTEN into a non-BTEN asset through an approved Cetus pool. This is
    /// the reverse leg of `cetus_swap_to_bten` and has the same output guard.
    public entry fun cetus_swap_from_bten<A>(
        state: &mut EmissionState,
        registry: &PoolRegistry,
        config: &GlobalConfig,
        pool: &mut Pool<A, BTEN>,
        mut input: Coin<BTEN>,
        min_asset_out: u64,
        sqrt_price_limit: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let pool_id = object::id(pool);
        let pool_address = object::id_to_address(&pool_id);
        assert!(table::contains(&registry.pools, pool_address), E_POOL_NOT_REGISTERED);
        assert!(*table::borrow(&registry.pools, pool_address) == BUCKET_CETUS, E_POOL_NOT_REGISTERED);
        let requested = coin::value(&input);
        assert!(requested > 0, E_ZERO_INPUT);
        let (receive_a, receive_b, receipt) = pool::flash_swap<A, BTEN>(
            config, pool, false, true, requested, sqrt_price_limit, clock
        );
        let paid = pool::swap_pay_amount(&receipt);
        let out = balance::value(&receive_a);
        assert!(out >= min_asset_out, E_MIN_OUTPUT);
        let pay_b = coin::into_balance(coin::split(&mut input, paid, ctx));
        pool::repay_flash_swap(config, pool, balance::zero<A>(), pay_b, receipt);
        coin::join(&mut input, coin::from_balance(receive_b, ctx));
        record_atomic_route(state, paid, clock, tx_context::sender(ctx));
        transfer::public_transfer(input, tx_context::sender(ctx));
        transfer::public_transfer(coin::from_balance(receive_a, ctx), tx_context::sender(ctx));
    }

    /// BTEN-first-pool variant: swap a non-BTEN asset into BTEN. Cetus orders
    /// the live BTEN/SUI pool as `Pool<BTEN, SUI>`, so this mirrors the
    /// BTEN-second implementation above without accepting arbitrary ordering.
    public entry fun cetus_swap_to_bten_b2a<A>(
        state: &mut EmissionState,
        registry: &PoolRegistry,
        config: &GlobalConfig,
        pool: &mut Pool<BTEN, A>,
        mut input: Coin<A>,
        min_bten_out: u64,
        sqrt_price_limit: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let pool_id = object::id(pool);
        let pool_address = object::id_to_address(&pool_id);
        assert!(table::contains(&registry.pools, pool_address), E_POOL_NOT_REGISTERED);
        assert!(*table::borrow(&registry.pools, pool_address) == BUCKET_CETUS, E_POOL_NOT_REGISTERED);
        let requested = coin::value(&input);
        assert!(requested > 0, E_ZERO_INPUT);
        let (receive_bten, receive_asset, receipt) = pool::flash_swap<BTEN, A>(
            config, pool, false, true, requested, sqrt_price_limit, clock
        );
        let paid = pool::swap_pay_amount(&receipt);
        let out = balance::value(&receive_bten);
        assert!(out >= min_bten_out, E_MIN_OUTPUT);
        let pay_asset = coin::into_balance(coin::split(&mut input, paid, ctx));
        pool::repay_flash_swap(config, pool, balance::zero<BTEN>(), pay_asset, receipt);
        coin::join(&mut input, coin::from_balance(receive_asset, ctx));
        record_atomic_route(state, paid, clock, tx_context::sender(ctx));
        transfer::public_transfer(input, tx_context::sender(ctx));
        transfer::public_transfer(coin::from_balance(receive_bten, ctx), tx_context::sender(ctx));
    }

    /// BTEN-first-pool variant: swap BTEN into the paired non-BTEN asset.
    public entry fun cetus_swap_from_bten_a2b<A>(
        state: &mut EmissionState,
        registry: &PoolRegistry,
        config: &GlobalConfig,
        pool: &mut Pool<BTEN, A>,
        mut input: Coin<BTEN>,
        min_asset_out: u64,
        sqrt_price_limit: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let pool_id = object::id(pool);
        let pool_address = object::id_to_address(&pool_id);
        assert!(table::contains(&registry.pools, pool_address), E_POOL_NOT_REGISTERED);
        assert!(*table::borrow(&registry.pools, pool_address) == BUCKET_CETUS, E_POOL_NOT_REGISTERED);
        let requested = coin::value(&input);
        assert!(requested > 0, E_ZERO_INPUT);
        let (receive_bten, receive_asset, receipt) = pool::flash_swap<BTEN, A>(
            config, pool, true, true, requested, sqrt_price_limit, clock
        );
        let paid = pool::swap_pay_amount(&receipt);
        let out = balance::value(&receive_asset);
        assert!(out >= min_asset_out, E_MIN_OUTPUT);
        let pay_bten = coin::into_balance(coin::split(&mut input, paid, ctx));
        pool::repay_flash_swap(config, pool, pay_bten, balance::zero<A>(), receipt);
        coin::join(&mut input, coin::from_balance(receive_bten, ctx));
        record_atomic_route(state, paid, clock, tx_context::sender(ctx));
        transfer::public_transfer(input, tx_context::sender(ctx));
        transfer::public_transfer(coin::from_balance(receive_asset, ctx), tx_context::sender(ctx));
    }

    /// Shared private receipt path. It cannot be reached without completing a
    /// Cetus flash-swap in one transaction, because the receipt has no drop.
    fun record_atomic_route(
        state: &mut EmissionState,
        fee_points: u64,
        clock: &Clock,
        trader: address,
    ) {
        assert!(fee_points > 0, E_BAD_AMOUNT);
        advance_slots(state, clock::timestamp_ms(clock) / 1000);
        state.batch_trades = state.batch_trades + 1;
        state.batch_fee_points = state.batch_fee_points + fee_points;
        let key = PointKey { round: state.current_round, trader };
        if (table::contains(&state.trader_points, key)) {
            *table::borrow_mut(&mut state.trader_points, key) = *table::borrow(&state.trader_points, key) + fee_points;
        } else {
            table::add(&mut state.trader_points, key, fee_points);
        };
        event::emit(RouteRecorded {
            trader,
            fee_points,
            batch_trades: state.batch_trades,
        });
    }

    #[test_only]
    public fun record_qualified_route_for_testing(
        state: &mut EmissionState,
        fee_points: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        record_atomic_route(state, fee_points, clock, tx_context::sender(ctx));
    }

    /// The Bitcoin-style genesis block: 50 BTEN is available to bootstrap
    /// routing and liquidity before any trade-gated ten-minute block is due.
    /// It occupies height zero, so it is included in the fixed emission cap.
    public fun release_genesis(state: &mut EmissionState, ctx: &mut TxContext) {
        assert!(state.total_minted == 0 && state.block_height == 0, E_GENESIS_ALREADY_RELEASED);
        let emission = subsidy_at_height(0);
        state.total_minted = emission;
        let minted = coin::into_balance(coin::mint(&mut state.cap, emission, ctx));
        allocate(state, minted, emission);
        state.block_height = 1;
        event::emit(BlocksReleased { blocks: 1, emission, remaining_pending: state.pending_blocks });
    }

    /// Permissionless settlement. A routed transaction can invoke this after
    /// recording its receipt; an ops keeper covers quiet periods.
    public fun settle(state: &mut EmissionState, clock: &Clock, ctx: &mut TxContext) {
        advance_slots(state, clock::timestamp_ms(clock) / 1000);
        let trade_supported = state.batch_trades / MIN_TRADES_PER_BLOCK;
        let mut blocks = if (state.pending_blocks < trade_supported) { state.pending_blocks } else { trade_supported };
        if (blocks > MAX_SETTLE_BLOCKS) { blocks = MAX_SETTLE_BLOCKS };
        assert!(blocks > 0, E_NO_ELIGIBLE_BLOCKS);

        let emission = emission_between(state.block_height, state.block_height + blocks);
        if (emission > 0) {
            assert!(state.total_minted + emission <= MAX_SUPPLY, E_CAP_EXCEEDED);
            state.total_minted = state.total_minted + emission;
            let minted = coin::into_balance(coin::mint(&mut state.cap, emission, ctx));
            allocate(state, minted, emission);
            let trader_reward = emission * TRADER_BPS / BPS;
            table::add(&mut state.trader_rounds, state.current_round, TraderRound {
                total_points: state.batch_fee_points,
                reward_total: trader_reward,
                reward_paid: 0,
            });
        };
        state.block_height = state.block_height + blocks;
        state.pending_blocks = state.pending_blocks - blocks;
        // The complete batch shares this settlement's trader allocation. This
        // intentionally prevents surplus trades from pre-unlocking new slots.
        state.batch_trades = 0;
        state.batch_fee_points = 0;
        state.current_round = state.current_round + 1;
        event::emit(BlocksReleased { blocks, emission, remaining_pending: state.pending_blocks });
    }

    public fun register_pool(
        registry: &mut PoolRegistry,
        _admin: &RegistryAdminCap,
        pool_id: address,
        bucket: u8,
    ) {
        assert!(!registry.finalized, E_REGISTRY_FINAL);
        assert!(bucket <= MAX_BUCKET, E_BAD_BUCKET);
        assert!(!table::contains(&registry.pools, pool_id), E_DUPLICATE_POOL);
        table::add(&mut registry.pools, pool_id, bucket);
    }

    /// Irreversibly blocks new pool registrations. The caller must delete or
    /// permanently custody RegistryAdminCap after this call.
    public fun finalize_pool_registry(registry: &mut PoolRegistry, _admin: &RegistryAdminCap) {
        registry.finalized = true;
    }

    /// Update public coin metadata while setup remains upgradeable. Holding the
    /// RegistryAdminCap is required, and no supply is minted by this function.
    public fun update_coin_metadata(
        state: &EmissionState,
        _admin: &RegistryAdminCap,
        metadata: &mut coin::CoinMetadata<BTEN>,
        icon_url: ascii::String,
        description: string::String,
    ) {
        coin::update_icon_url(&state.cap, metadata, icon_url);
        coin::update_description(&state.cap, metadata, description);
    }

    /// Setup-only funding leg for a registered Cetus, Turbos, or BTEN LP pool.
    /// The returned coin is intended to be passed directly into that venue's
    /// pool-create/add-liquidity call in the same programmable transaction.
    /// Finalize the registry and retire RegistryAdminCap before launch.
    public fun withdraw_registered_pool_funding(
        state: &mut EmissionState,
        registry: &PoolRegistry,
        _admin: &RegistryAdminCap,
        pool_id: address,
        bucket: u8,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<BTEN> {
        assert!(amount > 0, E_BAD_AMOUNT);
        assert!(table::contains(&registry.pools, pool_id), E_UNREGISTERED_POOL);
        assert!(*table::borrow(&registry.pools, pool_id) == bucket, E_BAD_BUCKET);
        assert!(bucket == BUCKET_BTEN_LP || bucket == BUCKET_CETUS || bucket == BUCKET_TURBOS, E_POOL_FUNDING_BUCKET);
        let source = if (bucket == BUCKET_BTEN_LP) {
            &mut state.bten_lp_vault
        } else if (bucket == BUCKET_CETUS) {
            &mut state.cetus_vault
        } else {
            &mut state.magma_vault
        };
        coin::from_balance(balance::split(source, amount), ctx)
    }

    /// Temporary setup path for the genesis BTEN LP allocation. It is guarded
    /// by RegistryAdminCap and is intended only to create the initial approved
    /// pools before the registry is finalized.
    public fun withdraw_bootstrap_bten_lp(
        state: &mut EmissionState,
        _admin: &RegistryAdminCap,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<BTEN> {
        assert!(amount > 0, E_BAD_AMOUNT);
        coin::from_balance(balance::split(&mut state.bten_lp_vault, amount), ctx)
    }

    /// CLI-safe setup entrypoint. It transfers the bootstrap allocation to the
    /// transaction sender, preventing a returned Coin from being left unused.
    /// This remains setup-only: it is guarded by RegistryAdminCap and should
    /// no longer be usable after that capability is retired at final launch.
    public entry fun withdraw_bootstrap_bten_lp_to_sender(
        state: &mut EmissionState,
        admin: &RegistryAdminCap,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        let funding = withdraw_bootstrap_bten_lp(state, admin, amount, ctx);
        transfer::public_transfer(funding, tx_context::sender(ctx));
    }

    /// Setup-only funding path for the approved external staking farm. Rewards
    /// are taken only from the fixed 10% staking allocation; this does not mint
    /// BTEN. Keep RegistryAdminCap in controlled custody until the farm and its
    /// rolling-emission keeper have been verified.
    public entry fun withdraw_staking_rewards_to_sender(
        state: &mut EmissionState,
        _admin: &RegistryAdminCap,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(amount > 0, E_BAD_AMOUNT);
        let funding = coin::from_balance(balance::split(&mut state.staking_vault, amount), ctx);
        transfer::public_transfer(funding, tx_context::sender(ctx));
    }

    /// A keeper calls this after observing RouteRecorded events. The amount is
    /// calculated on-chain from the sealed round's points; it cannot be chosen
    /// by the keeper. This is the normal no-redemption path for traders.
    public fun auto_pay_trader(
        state: &mut EmissionState,
        round: u64,
        trader: address,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&state.trader_rounds, round), E_UNKNOWN_ROUND);
        let key = PointKey { round, trader };
        assert!(table::contains(&state.trader_points, key), E_NOTHING_TO_PAY);
        let points = table::remove(&mut state.trader_points, key);
        let trader_round = table::borrow_mut(&mut state.trader_rounds, round);
        let amount = points * trader_round.reward_total / trader_round.total_points;
        assert!(amount > 0, E_NOTHING_TO_PAY);
        trader_round.reward_paid = trader_round.reward_paid + amount;
        transfer::public_transfer(coin::from_balance(balance::split(&mut state.trader_vault, amount), ctx), trader);
        event::emit(TraderPaid { round, trader, amount });
    }

    fun advance_slots(state: &mut EmissionState, now: u64) {
        if (state.last_slot_ts == 0) {
            state.last_slot_ts = now;
            return
        };
        if (now <= state.last_slot_ts) { return };
        let slots = (now - state.last_slot_ts) / BLOCK_TIME_SECS;
        if (slots > 0) {
            state.pending_blocks = state.pending_blocks + slots;
            state.last_slot_ts = state.last_slot_ts + slots * BLOCK_TIME_SECS;
        };
    }

    fun allocate(state: &mut EmissionState, mut minted: Balance<BTEN>, emission: u64) {
        let route = emission * ROUTE_VAULT_BPS / BPS;
        let traders = emission * TRADER_BPS / BPS;
        let bten_lp = emission * BTEN_LP_BPS / BPS;
        let staking = emission * STAKING_BPS / BPS;
        let cetus = emission * CETUS_BPS / BPS;
        let haedal = emission * HAEDAL_BPS / BPS;
        let blue = emission * BLUE_BPS / BPS;
        let turbos = emission * TURBOS_BPS / BPS;
        let sui_gas = emission * SUI_GAS_BPS / BPS;
        balance::join(&mut state.route_fee_vault, balance::split(&mut minted, route));
        balance::join(&mut state.trader_vault, balance::split(&mut minted, traders));
        balance::join(&mut state.bten_lp_vault, balance::split(&mut minted, bten_lp));
        balance::join(&mut state.staking_vault, balance::split(&mut minted, staking));
        balance::join(&mut state.cetus_vault, balance::split(&mut minted, cetus));
        balance::join(&mut state.haedal_vault, balance::split(&mut minted, haedal));
        balance::join(&mut state.blue_vault, balance::split(&mut minted, blue));
        balance::join(&mut state.magma_vault, balance::split(&mut minted, turbos));
        balance::join(&mut state.sui_gas_vault, balance::split(&mut minted, sui_gas));
        // Keep any integer-division dust in the Haedal bucket so no BTEN is
        // stranded and total supply accounting remains exact.
        balance::join(&mut state.haedal_vault, minted);
    }

    public fun subsidy_at_height(height: u64): u64 {
        let era = height / HALVING_INTERVAL;
        if (era >= 64) { return 0 };
        let mut divisor = 1;
        let mut i = 0;
        while (i < era) { divisor = divisor * 2; i = i + 1 };
        INITIAL_SUBSIDY / divisor
    }

    fun emission_between(start_height: u64, end_height: u64): u64 {
        let mut cursor = start_height;
        let mut total = 0;
        while (cursor < end_height) {
            let era = cursor / HALVING_INTERVAL;
            let boundary = (era + 1) * HALVING_INTERVAL;
            let stop = if (end_height < boundary) { end_height } else { boundary };
            total = total + (stop - cursor) * subsidy_at_height(cursor);
            cursor = stop;
        };
        total
    }

    public fun decimals(): u8 { DECIMALS }
    public fun unit(): u64 { UNIT }
    public fun max_supply(): u64 { MAX_SUPPLY }
    public fun initial_subsidy(): u64 { INITIAL_SUBSIDY }
    public fun block_time_secs(): u64 { BLOCK_TIME_SECS }
    public fun min_trades_per_block(): u64 { MIN_TRADES_PER_BLOCK }
    public fun pending_blocks(state: &EmissionState): u64 { state.pending_blocks }
    public fun batch_trades(state: &EmissionState): u64 { state.batch_trades }
    public fun current_round(state: &EmissionState): u64 { state.current_round }
    public fun block_height(state: &EmissionState): u64 { state.block_height }
    public fun total_minted(state: &EmissionState): u64 { state.total_minted }
    public fun route_fee_balance(state: &EmissionState): u64 { balance::value(&state.route_fee_vault) }
    public fun trader_balance(state: &EmissionState): u64 { balance::value(&state.trader_vault) }
    public fun bten_lp_balance(state: &EmissionState): u64 { balance::value(&state.bten_lp_vault) }
    public fun staking_balance(state: &EmissionState): u64 { balance::value(&state.staking_vault) }
    public fun cetus_balance(state: &EmissionState): u64 { balance::value(&state.cetus_vault) }
    public fun haedal_balance(state: &EmissionState): u64 { balance::value(&state.haedal_vault) }
    public fun blue_balance(state: &EmissionState): u64 { balance::value(&state.blue_vault) }
    public fun turbos_balance(state: &EmissionState): u64 { balance::value(&state.magma_vault) }
    /// Compatibility alias for the first testnet development revision. The
    /// underlying bucket is now assigned to Turbos and new callers should use
    /// `turbos_balance`.
    public fun magma_balance(state: &EmissionState): u64 { turbos_balance(state) }
    public fun sui_gas_balance(state: &EmissionState): u64 { balance::value(&state.sui_gas_vault) }
    public fun pool_bucket(registry: &PoolRegistry, pool_id: address): u8 {
        if (!table::contains(&registry.pools, pool_id)) { return 255 };
        *table::borrow(&registry.pools, pool_id)
    }
    public fun registry_is_finalized(registry: &PoolRegistry): bool { registry.finalized }
}
