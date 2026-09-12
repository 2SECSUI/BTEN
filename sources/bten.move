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
    use sui::sui::SUI;
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
    const DAY_MS: u64 = 86_400_000;
    // The route reserve may only refill the SUI sponsor gradually. These are
    // hard maximums; the shared FeeSubsidyState can choose lower values.
    const MAX_REFILL_MIST: u64 = 5_000_000;
    const MAX_DAILY_REFILL_MIST: u64 = 250_000_000;
    const ROUTE_SPONSOR_BPS: u64 = 3_000;
    const ROUTE_POL_BPS: u64 = 3_000;
    const ROUTE_REBATE_BPS: u64 = 2_000;
    const ROUTE_LP_SUPPORT_BPS: u64 = 1_000;
    const ROUTE_SAFETY_BPS: u64 = 1_000;
    const LP_PROTOCOL_LIQUIDITY_BPS: u64 = 10_000;
    const MAX_LP_RELEASE_PER_CALL: u64 = 50 * UNIT;

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
    const BUCKET_STAKING: u8 = 6;
    const MAX_BUCKET: u8 = BUCKET_STAKING;

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
    const E_FEE_STATE_CONFIG: u64 = 15;
    const E_FEE_CAP: u64 = 16;
    const E_FEE_POOL: u64 = 17;
    const E_DISTRIBUTION_CONFIG: u64 = 18;
    const E_TREASURY_PAUSED: u64 = 19;
    const E_KEEPER_PAUSED: u64 = 20;
    const E_KEEPER_SENDER: u64 = 21;
    const E_KEEPER_CAP: u64 = 22;
    const E_LP_PROGRAM_PAUSED: u64 = 23;
    const E_LP_PROGRAM_POOL: u64 = 24;
    const E_LP_PROGRAM_FINAL: u64 = 25;
    const E_LP_PROGRAM_WEIGHTS: u64 = 26;
    const E_REDIRECTED_BUCKET: u64 = 27;

    public struct BTEN has drop {}

    /// Held during the development/test phase only. The final router replaces
    /// this capability with an internal call made after the atomic swap.
    public struct RouterCap has key, store { id: UID }

    /// Held during setup so exact live pool IDs can be registered. Destroy it
    /// after the initial pool set is tested and the registry is finalized.
    public struct RegistryAdminCap has key, store { id: UID }

    /// A deliberately narrow capability held by the remote keeper. It grants
    /// no upgrade, registry, LP, or treasury authority.
    public struct KeeperCap has key, store { id: UID }

    /// Staking-only automation configuration. It begins paused and applies a
    /// rolling 24-hour ceiling, so activation is an explicit admin action.
    public struct KeeperConfig has key {
        id: UID,
        keeper: address,
        paused: bool,
        daily_staking_cap: u64,
        accounting_day: u64,
        spent_today: u64,
    }

    /// Narrow capability for the treasury-owned LP execution wallet. It has
    /// no mint, upgrade, registry, staking, or sponsor authority.
    public struct LpProgramCap has key, store { id: UID }

    /// Accounting and allowlist for the BTEN LP programme. The actual Cetus
    /// add-liquidity calls consume coins from this object in a
    /// single operator-signed transaction after their quote is simulated.
    public struct LpProgramState has key {
        id: UID,
        pools: Table<address, u64>,
        weight_total: u64,
        finalized: bool,
        paused: bool,
        protocol_liquidity: Balance<BTEN>,
    }

    public struct PoolRegistry has key {
        id: UID,
        pools: Table<address, u8>,
        finalized: bool,
    }

    /// Shared, capped configuration for converting a small portion of the
    /// route reserve into SUI gas. It has no withdrawal function: the only
    /// destination is the fixed sponsor address and the only source is the
    /// route_fee_vault through this exact registered BTEN/SUI pool.
    public struct FeeSubsidyState has key {
        id: UID,
        sponsor: address,
        sui_pool: address,
        per_refill_cap_mist: u64,
        daily_cap_mist: u64,
        accounting_day: u64,
        spent_today_mist: u64,
    }

    /// Shared delivery configuration for allocations that have a fixed
    /// destination.  It deliberately starts at the current height: reserves
    /// accumulated before a venue is configured stay in their vault, while
    /// every subsequently released block can be delivered atomically.
    /// Route-reserve and trader allocations are excluded: those have their
    /// own capped sponsor and point-based payout paths.
    public struct DistributionState has key {
        id: UID,
        next_height: u64,
        enabled: Table<u8, bool>,
        destinations: Table<u8, address>,
    }

    /// Per-height accounting for the fixed route-reserve split. The BTEN stays
    /// in EmissionState's route vault until a separately protected adapter
    /// consumes an accrued budget; this state prevents the keeper from
    /// treating the whole 50% reserve as freely spendable.
    public struct RouteTreasuryState has key {
        id: UID,
        next_height: u64,
        sponsor_accrued: u64,
        pol_accrued: u64,
        rebate_accrued: u64,
        lp_support_accrued: u64,
        safety_accrued: u64,
        paused: bool,
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

    public struct SponsorRefilled has copy, drop {
        sponsor: address,
        bten_in: u64,
        sui_out_mist: u64,
        spent_today_mist: u64,
    }

    public struct AllocationDelivered has copy, drop {
        height: u64,
        bucket: u8,
        recipient: address,
        amount: u64,
    }

    public struct DistributionDestinationConfigured has copy, drop {
        bucket: u8,
        recipient: address,
        enabled: bool,
    }

    public struct RouteTreasuryAccrued has copy, drop {
        height: u64,
        sponsor: u64,
        protocol_liquidity: u64,
        rebates: u64,
        lp_support: u64,
        safety: u64,
    }

    public struct LpProgrammeAccrued has copy, drop {
        total: u64,
        protocol_liquidity: u64,
        /// Retained in the public event schema for indexers; v9 always emits 0.
        cetus_rewards: u64,
    }

    public struct LpProgrammeReleased has copy, drop {
        pool_id: address,
        category: u8,
        amount: u64,
    }

    /// Evidence for a protected protocol-owned Cetus liquidity deployment.
    public struct ProtocolLiquidityDeployed has copy, drop {
        pool_id: address,
        bten_in: u64,
        sui_in_mist: u64,
        recipient: address,
    }

    /// Evidence for a one-sided, out-of-range protocol-owned LP deployment.
    /// The range is checked by the Cetus receipt: a non-BTEN payment aborts
    /// the whole transaction before any balance is repaid.
    public struct ProtocolLiquidityOutOfRangeDeployed has copy, drop {
        pool_id: address,
        bten_in: u64,
        recipient: address,
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

    /// One-time setup for the gas-subsidy route. The owner of RegistryAdminCap
    /// sets the immutable sponsor wallet and the exact registered BTEN/SUI
    /// pool. Caps cannot exceed the protocol seed policy.
    public entry fun create_fee_subsidy_state(
        registry: &PoolRegistry,
        _admin: &RegistryAdminCap,
        sponsor: address,
        sui_pool: address,
        per_refill_cap_mist: u64,
        daily_cap_mist: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&registry.pools, sui_pool), E_FEE_POOL);
        assert!(*table::borrow(&registry.pools, sui_pool) == BUCKET_CETUS, E_FEE_POOL);
        assert!(per_refill_cap_mist > 0 && per_refill_cap_mist <= MAX_REFILL_MIST, E_FEE_STATE_CONFIG);
        assert!(daily_cap_mist >= per_refill_cap_mist && daily_cap_mist <= MAX_DAILY_REFILL_MIST, E_FEE_STATE_CONFIG);
        transfer::share_object(FeeSubsidyState {
            id: object::new(ctx),
            sponsor,
            sui_pool,
            per_refill_cap_mist,
            daily_cap_mist,
            accounting_day: clock::timestamp_ms(clock) / DAY_MS,
            spent_today_mist: 0,
        });
    }

    /// Permissionless but fully constrained route-reserve refill. It can only
    /// exchange BTEN from the route vault for SUI via the configured
    /// BTEN/SUI Cetus pool, honours a caller-provided minimum output, and sends
    /// the SUI only to the fixed sponsor wallet. No caller receives reserve
    /// funds. A keeper invokes it when the sponsor balance is low.
    public fun refill_sponsor_from_route_reserve(
        state: &mut EmissionState,
        fee: &mut FeeSubsidyState,
        config: &GlobalConfig,
        pool: &mut Pool<BTEN, SUI>,
        requested_bten: u64,
        min_sui_out: u64,
        sqrt_price_limit: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(requested_bten > 0, E_BAD_AMOUNT);
        let pool_id = object::id(pool);
        assert!(object::id_to_address(&pool_id) == fee.sui_pool, E_FEE_POOL);
        let day = clock::timestamp_ms(clock) / DAY_MS;
        if (day > fee.accounting_day) {
            fee.accounting_day = day;
            fee.spent_today_mist = 0;
        };
        let (unused_bten, receive_sui, receipt) = pool::flash_swap<BTEN, SUI>(
            config, pool, true, true, requested_bten, sqrt_price_limit, clock
        );
        let paid_bten = pool::swap_pay_amount(&receipt);
        let sui_out = balance::value(&receive_sui);
        assert!(sui_out >= min_sui_out, E_MIN_OUTPUT);
        assert!(sui_out <= fee.per_refill_cap_mist, E_FEE_CAP);
        assert!(fee.spent_today_mist + sui_out <= fee.daily_cap_mist, E_FEE_CAP);
        let payment = balance::split(&mut state.route_fee_vault, paid_bten);
        pool::repay_flash_swap(config, pool, payment, balance::zero<SUI>(), receipt);
        balance::join(&mut state.route_fee_vault, unused_bten);
        fee.spent_today_mist = fee.spent_today_mist + sui_out;
        transfer::public_transfer(coin::from_balance(receive_sui, ctx), fee.sponsor);
        event::emit(SponsorRefilled { sponsor: fee.sponsor, bten_in: paid_bten, sui_out_mist: sui_out, spent_today_mist: fee.spent_today_mist });
    }

    /// Creates the delivery state at the current emission height. This makes
    /// the first configured payout occur at the next gate release, rather
    /// than retrospectively sending any bootstrap or unconfigured reserves.
    public entry fun create_distribution_state(
        state: &EmissionState,
        _admin: &RegistryAdminCap,
        ctx: &mut TxContext,
    ) {
        transfer::share_object(DistributionState {
            id: object::new(ctx),
            next_height: state.block_height,
            enabled: table::new<u8, bool>(ctx),
            destinations: table::new<u8, address>(ctx),
        });
    }

    /// Begins route-reserve accounting at the current height. Existing route
    /// reserve is deliberately not retroactively reclassified.
    public entry fun create_route_treasury_state(
        state: &EmissionState,
        _admin: &RegistryAdminCap,
        ctx: &mut TxContext,
    ) {
        transfer::share_object(RouteTreasuryState {
            id: object::new(ctx), next_height: state.block_height,
            sponsor_accrued: 0, pol_accrued: 0, rebate_accrued: 0,
            lp_support_accrued: 0, safety_accrued: 0, paused: false,
        });
    }

    /// One-time setup for the remote keeper. The config is shared so a
    /// keeper transaction can be audited on-chain; the narrow cap is sent to
    /// the configured address. This function never transfers BTEN.
    public entry fun create_keeper_config(
        _admin: &RegistryAdminCap,
        keeper: address,
        daily_staking_cap: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(keeper != @0x0, E_KEEPER_SENDER);
        assert!(daily_staking_cap > 0 && daily_staking_cap <= 5 * UNIT, E_KEEPER_CAP);
        transfer::public_transfer(KeeperCap { id: object::new(ctx) }, keeper);
        transfer::share_object(KeeperConfig {
            id: object::new(ctx), keeper, paused: true, daily_staking_cap,
            accounting_day: clock::timestamp_ms(clock) / 86_400_000,
            spent_today: 0,
        });
    }

    public fun set_keeper_paused(config: &mut KeeperConfig, _admin: &RegistryAdminCap, paused: bool) {
        config.paused = paused;
    }

    public fun rotate_keeper(
        config: &mut KeeperConfig,
        _admin: &RegistryAdminCap,
        keeper: address,
        ctx: &mut TxContext,
    ) {
        assert!(keeper != @0x0, E_KEEPER_SENDER);
        config.keeper = keeper;
        config.paused = true;
        // Any cap retained by the former keeper becomes unusable because the
        // sender check above now points at the replacement address.
        transfer::public_transfer(KeeperCap { id: object::new(ctx) }, keeper);
    }

    public fun set_route_treasury_paused(
        treasury: &mut RouteTreasuryState,
        _admin: &RegistryAdminCap,
        paused: bool,
    ) { treasury.paused = paused; }

    /// Creates the LP programme in a paused state and assigns its narrowly
    /// scoped execution cap to the declared treasury operator.
    public entry fun create_lp_program(
        _admin: &RegistryAdminCap,
        treasury_operator: address,
        ctx: &mut TxContext,
    ) {
        assert!(treasury_operator != @0x0, E_KEEPER_SENDER);
        transfer::public_transfer(LpProgramCap { id: object::new(ctx) }, treasury_operator);
        transfer::share_object(LpProgramState {
            id: object::new(ctx), pools: table::new(ctx), weight_total: 0,
            finalized: false, paused: false,
            protocol_liquidity: balance::zero<BTEN>(),
        });
    }

    /// Records a fixed registered Cetus BTEN-pair pool and its allocation
    /// weight. No new pool can be added once the programme is finalized.
    public fun register_lp_program_pool(
        programme: &mut LpProgramState,
        registry: &PoolRegistry,
        _admin: &RegistryAdminCap,
        pool_id: address,
        weight_bps: u64,
    ) {
        assert!(!programme.finalized, E_LP_PROGRAM_FINAL);
        assert!(weight_bps > 0 && programme.weight_total + weight_bps <= BPS, E_LP_PROGRAM_WEIGHTS);
        assert!(table::contains(&registry.pools, pool_id), E_LP_PROGRAM_POOL);
        assert!(!table::contains(&programme.pools, pool_id), E_DUPLICATE_POOL);
        table::add(&mut programme.pools, pool_id, weight_bps);
        programme.weight_total = programme.weight_total + weight_bps;
    }

    public fun finalize_lp_program(programme: &mut LpProgramState, _admin: &RegistryAdminCap) {
        assert!(programme.weight_total == BPS, E_LP_PROGRAM_WEIGHTS);
        programme.finalized = true;
    }

    public fun set_lp_program_paused(
        programme: &mut LpProgramState,
        _admin: &RegistryAdminCap,
        paused: bool,
    ) { programme.paused = paused; }

    /// Collects the 25% BTEN LP vault plus every redirected 1% venue vault,
    /// including any backlog accumulated while those venue buckets were
    /// paused. Every BTEN is routed to protocol-owned liquidity across the
    /// fixed registered-pool set; no allocation is held for a separate farm.
    public entry fun accrue_lp_program(
        state: &mut EmissionState,
        programme: &mut LpProgramState,
    ) {
        assert!(programme.finalized, E_LP_PROGRAM_FINAL);
        let mut total = drain_bten(&mut state.bten_lp_vault);
        balance::join(&mut total, drain_bten(&mut state.cetus_vault));
        balance::join(&mut total, drain_bten(&mut state.haedal_vault));
        balance::join(&mut total, drain_bten(&mut state.blue_vault));
        balance::join(&mut total, drain_bten(&mut state.magma_vault));
        balance::join(&mut total, drain_bten(&mut state.sui_gas_vault));
        let amount = balance::value(&total);
        assert!(LP_PROTOCOL_LIQUIDITY_BPS == BPS, E_LP_PROGRAM_WEIGHTS);
        let protocol_amount = amount * LP_PROTOCOL_LIQUIDITY_BPS / BPS;
        balance::join(&mut programme.protocol_liquidity, total);
        event::emit(LpProgrammeAccrued { total: amount, protocol_liquidity: protocol_amount, cetus_rewards: 0 });
    }

    /// Moves only the already-accounted route-reserve LP-support allocation
    /// into protocol-owned liquidity. Sponsor, rebate, and safety balances are
    /// deliberately excluded from this path.
    public fun accrue_route_lp_support_to_program(
        state: &mut EmissionState,
        treasury: &mut RouteTreasuryState,
        programme: &mut LpProgramState,
        _cap: &LpProgramCap,
        amount: u64,
    ) {
        assert!(!programme.paused && programme.finalized, E_LP_PROGRAM_PAUSED);
        assert!(amount > 0 && amount <= treasury.lp_support_accrued, E_BAD_AMOUNT);
        treasury.lp_support_accrued = treasury.lp_support_accrued - amount;
        balance::join(&mut programme.protocol_liquidity, balance::split(&mut state.route_fee_vault, amount));
        event::emit(LpProgrammeAccrued { total: amount, protocol_liquidity: amount, cetus_rewards: 0 });
    }

    /// Takes a bounded, allowlisted protocol-liquidity allocation. The caller
    /// must use the returned coin in the same transaction's verified Cetus
    /// add-liquidity path; users and the GitHub keeper never receive this cap.
    public fun take_protocol_liquidity(
        programme: &mut LpProgramState,
        _cap: &LpProgramCap,
        pool_id: address,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<BTEN> {
        assert!(!programme.paused, E_LP_PROGRAM_PAUSED);
        assert!(programme.finalized && table::contains(&programme.pools, pool_id), E_LP_PROGRAM_POOL);
        assert!(amount > 0 && amount <= MAX_LP_RELEASE_PER_CALL, E_BAD_AMOUNT);
        let funding = coin::from_balance(balance::split(&mut programme.protocol_liquidity, amount), ctx);
        event::emit(LpProgrammeReleased { pool_id, category: 0, amount });
        funding
    }

    /// Atomically deploys an allowlisted BTEN allocation to the BTEN/SUI
    /// Cetus pool. The owner of the narrow LP cap supplies SUI, the quote's
    /// maximum SUI is enforced before repayment, and the resulting position
    /// plus every unused coin returns to the transaction sender.
    public entry fun deploy_protocol_liquidity_to_sui_cetus(
        programme: &mut LpProgramState,
        cap: &LpProgramCap,
        config: &GlobalConfig,
        pool: &mut Pool<BTEN, SUI>,
        mut sui: Coin<SUI>,
        pool_id: address,
        bten_amount: u64,
        max_sui_mist: u64,
        tick_lower: u32,
        tick_upper: u32,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let recipient = tx_context::sender(ctx);
        assert!(tick_lower < tick_upper, E_BAD_AMOUNT);
        assert!(max_sui_mist > 0 && coin::value(&sui) >= max_sui_mist, E_BAD_AMOUNT);
        let mut bten = take_protocol_liquidity(programme, cap, pool_id, bten_amount, ctx);
        let mut position = pool::open_position(config, pool, tick_lower, tick_upper, ctx);
        // Cetus uses `true` to fix CoinTypeA. BTEN is CoinTypeA in the
        // registered BTEN/SUI pool, so this keeps `bten_amount` meaningful.
        let receipt = pool::add_liquidity_fix_coin(config, pool, &mut position, bten_amount, true, clock);
        let (bten_due, sui_due) = pool::add_liquidity_pay_amount(&receipt);
        assert!(bten_due <= bten_amount && sui_due <= max_sui_mist, E_BAD_AMOUNT);
        let bten_payment = coin::into_balance(coin::split(&mut bten, bten_due, ctx));
        let sui_payment = coin::into_balance(coin::split(&mut sui, sui_due, ctx));
        pool::repay_add_liquidity(config, pool, bten_payment, sui_payment, receipt);
        transfer::public_transfer(bten, recipient);
        transfer::public_transfer(sui, recipient);
        transfer::public_transfer(position, recipient);
        event::emit(ProtocolLiquidityDeployed { pool_id, bten_in: bten_due, sui_in_mist: sui_due, recipient });
    }

    /// Adds one-sided BTEN liquidity where BTEN is Cetus CoinTypeA.  The
    /// caller supplies an out-of-range tick interval; a range that requires
    /// any paired asset is rejected atomically.
    public entry fun deploy_protocol_liquidity_out_of_range_a<A>(
        programme: &mut LpProgramState,
        cap: &LpProgramCap,
        config: &GlobalConfig,
        pool: &mut Pool<BTEN, A>,
        pool_id: address,
        bten_amount: u64,
        tick_lower: u32,
        tick_upper: u32,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let recipient = tx_context::sender(ctx);
        assert!(tick_lower < tick_upper, E_BAD_AMOUNT);
        let mut bten = take_protocol_liquidity(programme, cap, pool_id, bten_amount, ctx);
        let mut position = pool::open_position(config, pool, tick_lower, tick_upper, ctx);
        let receipt = pool::add_liquidity_fix_coin(config, pool, &mut position, bten_amount, true, clock);
        let (bten_due, paired_due) = pool::add_liquidity_pay_amount(&receipt);
        assert!(bten_due <= bten_amount && paired_due == 0, E_BAD_AMOUNT);
        let bten_payment = coin::into_balance(coin::split(&mut bten, bten_due, ctx));
        pool::repay_add_liquidity(config, pool, bten_payment, balance::zero<A>(), receipt);
        transfer::public_transfer(bten, recipient);
        transfer::public_transfer(position, recipient);
        event::emit(ProtocolLiquidityOutOfRangeDeployed { pool_id, bten_in: bten_due, recipient });
    }

    /// Adds one-sided BTEN liquidity where BTEN is Cetus CoinTypeB.  As with
    /// the CoinTypeA variant, the paired side must quote to exactly zero.
    public entry fun deploy_protocol_liquidity_out_of_range_b<A>(
        programme: &mut LpProgramState,
        cap: &LpProgramCap,
        config: &GlobalConfig,
        pool: &mut Pool<A, BTEN>,
        pool_id: address,
        bten_amount: u64,
        tick_lower: u32,
        tick_upper: u32,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let recipient = tx_context::sender(ctx);
        assert!(tick_lower < tick_upper, E_BAD_AMOUNT);
        let mut bten = take_protocol_liquidity(programme, cap, pool_id, bten_amount, ctx);
        let mut position = pool::open_position(config, pool, tick_lower, tick_upper, ctx);
        let receipt = pool::add_liquidity_fix_coin(config, pool, &mut position, bten_amount, false, clock);
        let (paired_due, bten_due) = pool::add_liquidity_pay_amount(&receipt);
        assert!(paired_due == 0 && bten_due <= bten_amount, E_BAD_AMOUNT);
        let bten_payment = coin::into_balance(coin::split(&mut bten, bten_due, ctx));
        pool::repay_add_liquidity(config, pool, balance::zero<A>(), bten_payment, receipt);
        transfer::public_transfer(bten, recipient);
        transfer::public_transfer(position, recipient);
        event::emit(ProtocolLiquidityOutOfRangeDeployed { pool_id, bten_in: bten_due, recipient });
    }

    /// Permissionless accounting sync after a settlement. Each released
    /// height is split 30/30/20/10/10 inside the fixed 50% route reserve.
    public entry fun sync_route_treasury(
        state: &EmissionState,
        treasury: &mut RouteTreasuryState,
    ) {
        assert!(!treasury.paused, E_TREASURY_PAUSED);
        while (treasury.next_height < state.block_height) {
            let height = treasury.next_height;
            let route = subsidy_at_height(height) * ROUTE_VAULT_BPS / BPS;
            let sponsor = route * ROUTE_SPONSOR_BPS / BPS;
            let pol = route * ROUTE_POL_BPS / BPS;
            let rebates = route * ROUTE_REBATE_BPS / BPS;
            let lp = route * ROUTE_LP_SUPPORT_BPS / BPS;
            let mut safety = route * ROUTE_SAFETY_BPS / BPS;
            // Preserve exact accounting at future halvings by retaining any
            // integer-division dust in the non-spendable safety budget.
            safety = safety + (route - sponsor - pol - rebates - lp - safety);
            treasury.sponsor_accrued = treasury.sponsor_accrued + sponsor;
            treasury.pol_accrued = treasury.pol_accrued + pol;
            treasury.rebate_accrued = treasury.rebate_accrued + rebates;
            treasury.lp_support_accrued = treasury.lp_support_accrued + lp;
            treasury.safety_accrued = treasury.safety_accrued + safety;
            treasury.next_height = height + 1;
            event::emit(RouteTreasuryAccrued { height, sponsor, protocol_liquidity: pol, rebates, lp_support: lp, safety });
        };
    }

    /// Configure or pause one allocation destination while setup is still
    /// controlled. A disabled bucket advances with each release but its BTEN
    /// remains safely accumulated in the corresponding emission vault.
    public fun configure_distribution_destination(
        distribution: &mut DistributionState,
        _admin: &RegistryAdminCap,
        bucket: u8,
        destination: address,
        enabled: bool,
    ) {
        assert!(bucket <= MAX_BUCKET, E_BAD_BUCKET);
        // v9 redirects all LP and venue shares through LpProgramState. Direct
        // recipient transfers would bypass its fixed weights and safeguards.
        assert!(bucket == BUCKET_STAKING, E_REDIRECTED_BUCKET);
        assert!(bucket != BUCKET_BTEN_LP || destination != @0x0, E_DISTRIBUTION_CONFIG);
        assert!(bucket != BUCKET_CETUS || destination != @0x0, E_DISTRIBUTION_CONFIG);
        assert!(bucket != BUCKET_BLUE || destination != @0x0, E_DISTRIBUTION_CONFIG);
        assert!(bucket != BUCKET_TURBOS || destination != @0x0, E_DISTRIBUTION_CONFIG);
        assert!(bucket != BUCKET_SUI_GAS || destination != @0x0, E_DISTRIBUTION_CONFIG);
        assert!(bucket != BUCKET_HAEDAL || destination != @0x0, E_DISTRIBUTION_CONFIG);
        assert!(bucket != BUCKET_STAKING || destination != @0x0, E_DISTRIBUTION_CONFIG);
        if (table::contains(&distribution.destinations, bucket)) {
            *table::borrow_mut(&mut distribution.destinations, bucket) = destination;
            *table::borrow_mut(&mut distribution.enabled, bucket) = enabled;
        } else {
            table::add(&mut distribution.destinations, bucket, destination);
            table::add(&mut distribution.enabled, bucket, enabled);
        };
        event::emit(DistributionDestinationConfigured { bucket, recipient: destination, enabled });
    }

    /// Settle a gate and immediately deliver the allocations from every block
    /// released by that gate. This is permissionless: destinations are fixed
    /// in DistributionState and callers can never redirect a payout.
    public entry fun settle_and_distribute(
        state: &mut EmissionState,
        distribution: &mut DistributionState,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        settle(state, clock, ctx);
        distribute_released_blocks(state, distribution, ctx);
    }

    /// Completes delivery for blocks already settled in an earlier transaction
    /// (for example, a legacy route which called `settle` directly). It only
    /// processes heights already released by EmissionState.
    public entry fun distribute_released_blocks(
        state: &mut EmissionState,
        distribution: &mut DistributionState,
        ctx: &mut TxContext,
    ) {
        while (distribution.next_height < state.block_height) {
            let height = distribution.next_height;
            let emission = subsidy_at_height(height);
            distribute_fixed_allocations(state, distribution, height, emission, ctx);
            distribution.next_height = height + 1;
        };
    }

    fun distribute_fixed_allocations(
        state: &mut EmissionState,
        distribution: &DistributionState,
        height: u64,
        emission: u64,
        ctx: &mut TxContext,
    ) {
        deliver_if_enabled(&mut state.bten_lp_vault, distribution, BUCKET_BTEN_LP, emission * BTEN_LP_BPS / BPS, height, ctx);
        deliver_if_enabled(&mut state.staking_vault, distribution, BUCKET_STAKING, emission * STAKING_BPS / BPS, height, ctx);
        deliver_if_enabled(&mut state.cetus_vault, distribution, BUCKET_CETUS, emission * CETUS_BPS / BPS, height, ctx);
        deliver_if_enabled(&mut state.haedal_vault, distribution, BUCKET_HAEDAL, emission * HAEDAL_BPS / BPS, height, ctx);
        deliver_if_enabled(&mut state.blue_vault, distribution, BUCKET_BLUE, emission * BLUE_BPS / BPS, height, ctx);
        deliver_if_enabled(&mut state.magma_vault, distribution, BUCKET_TURBOS, emission * TURBOS_BPS / BPS, height, ctx);
        deliver_if_enabled(&mut state.sui_gas_vault, distribution, BUCKET_SUI_GAS, emission * SUI_GAS_BPS / BPS, height, ctx);
    }

    fun deliver_if_enabled(
        vault: &mut Balance<BTEN>,
        distribution: &DistributionState,
        bucket: u8,
        amount: u64,
        height: u64,
        ctx: &mut TxContext,
    ) {
        if (amount == 0 || !table::contains(&distribution.enabled, bucket) || !*table::borrow(&distribution.enabled, bucket)) {
            return
        };
        let recipient = *table::borrow(&distribution.destinations, bucket);
        transfer::public_transfer(coin::from_balance(balance::split(vault, amount), ctx), recipient);
        event::emit(AllocationDelivered { height, bucket, recipient, amount });
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

    /// Remote keeper path for only the released staking allocation. It cannot
    /// access route, LP, trader, or venue vaults and is bounded per day.
    public entry fun withdraw_staking_tranche_to_keeper(
        state: &mut EmissionState,
        config: &mut KeeperConfig,
        _keeper_cap: &KeeperCap,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!config.paused, E_KEEPER_PAUSED);
        assert!(tx_context::sender(ctx) == config.keeper, E_KEEPER_SENDER);
        assert!(amount > 0 && amount <= config.daily_staking_cap, E_KEEPER_CAP);
        let day = clock::timestamp_ms(clock) / 86_400_000;
        if (day > config.accounting_day) {
            config.accounting_day = day;
            config.spent_today = 0;
        };
        assert!(config.spent_today + amount <= config.daily_staking_cap, E_KEEPER_CAP);
        config.spent_today = config.spent_today + amount;
        let funding = coin::from_balance(balance::split(&mut state.staking_vault, amount), ctx);
        transfer::public_transfer(funding, config.keeper);
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

    /// Transaction-friendly keeper entrypoint. Payout amounts and recipients
    /// remain derived from sealed on-chain route points.
    public entry fun auto_pay_trader_entry(
        state: &mut EmissionState,
        round: u64,
        trader: address,
        ctx: &mut TxContext,
    ) {
        auto_pay_trader(state, round, trader, ctx);
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

    fun drain_bten(vault: &mut Balance<BTEN>): Balance<BTEN> {
        let amount = balance::value(vault);
        balance::split(vault, amount)
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
    public fun distribution_next_height(distribution: &DistributionState): u64 { distribution.next_height }
    public fun distribution_is_enabled(distribution: &DistributionState, bucket: u8): bool {
        if (!table::contains(&distribution.enabled, bucket)) { return false };
        *table::borrow(&distribution.enabled, bucket)
    }
    public fun distribution_destination(distribution: &DistributionState, bucket: u8): option::Option<address> {
        if (!table::contains(&distribution.destinations, bucket)) { return option::none<address>() };
        option::some(*table::borrow(&distribution.destinations, bucket))
    }
    public fun route_treasury_next_height(treasury: &RouteTreasuryState): u64 { treasury.next_height }
    public fun route_treasury_sponsor(treasury: &RouteTreasuryState): u64 { treasury.sponsor_accrued }
    public fun route_treasury_pol(treasury: &RouteTreasuryState): u64 { treasury.pol_accrued }
    public fun route_treasury_rebates(treasury: &RouteTreasuryState): u64 { treasury.rebate_accrued }
    public fun route_treasury_lp_support(treasury: &RouteTreasuryState): u64 { treasury.lp_support_accrued }
    public fun route_treasury_safety(treasury: &RouteTreasuryState): u64 { treasury.safety_accrued }
    public fun route_treasury_is_paused(treasury: &RouteTreasuryState): bool { treasury.paused }
    public fun keeper_address(config: &KeeperConfig): address { config.keeper }
    public fun keeper_is_paused(config: &KeeperConfig): bool { config.paused }
    public fun keeper_daily_staking_cap(config: &KeeperConfig): u64 { config.daily_staking_cap }
    public fun keeper_staking_spent_today(config: &KeeperConfig): u64 { config.spent_today }
    public fun lp_program_is_paused(programme: &LpProgramState): bool { programme.paused }
    public fun lp_program_is_finalized(programme: &LpProgramState): bool { programme.finalized }
    public fun lp_program_weight(programme: &LpProgramState, pool_id: address): u64 {
        if (!table::contains(&programme.pools, pool_id)) { return 0 };
        *table::borrow(&programme.pools, pool_id)
    }
    public fun lp_program_protocol_balance(programme: &LpProgramState): u64 { balance::value(&programme.protocol_liquidity) }
    public fun pool_bucket(registry: &PoolRegistry, pool_id: address): u8 {
        if (!table::contains(&registry.pools, pool_id)) { return 255 };
        *table::borrow(&registry.pools, pool_id)
    }
    public fun registry_is_finalized(registry: &PoolRegistry): bool { registry.finalized }
}
