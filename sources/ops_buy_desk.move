/// OpsBuyDesk: public sale of ops-held BTEN inventory at WAL-implied BTEN mid
/// (no discount). Pricing source of truth is keeper-posted mist SUI/BTEN from
/// Cetus `Pool<WAL,BTEN>` × `Pool<WAL,SUI>` (see scripts/ops_buy_desk_sync_price.mjs).
///
/// Prefer `buy_with_sui_posted_price` for settlement. Legacy `buy_with_sui` still
/// reads `current_sqrt_price` on a configured `Pool<BTEN, SUI>` in-transaction;
/// that path is optional — the Cetus BTEN/SUI pool is left OPEN and must not be
/// unregistered for this desk rewire. Keeper must stay running for fair posted pricing.
module bten::ops_buy_desk {
    use bten::bten::{BTEN, RegistryAdminCap};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use cetusclmm::pool::{Self, Pool};

    /// Mist per 1 full BTEN (8 decimals).
    const UNIT: u64 = 100_000_000;

    const E_BAD_AMOUNT: u64 = 1;
    const E_PAUSED: u64 = 2;
    const E_ZERO_INPUT: u64 = 3;
    const E_MIN_OUT: u64 = 4;
    const E_INVENTORY: u64 = 5;
    const E_BAD_PRICE: u64 = 6;
    const E_BAD_RECIPIENT: u64 = 7;
    const E_BAD_POOL: u64 = 8;
    const E_NOT_UPDATER: u64 = 9;
    const E_OVERFLOW: u64 = 10;

    /// Capability for ops inventory / config of the buy desk.
    public struct OpsBuyDeskAdminCap has key, store { id: UID }

    /// Shared desk holding BTEN inventory sold for SUI at keeper-posted WAL-implied mid.
    public struct OpsBuyDesk has key {
        id: UID,
        /// Ops BTEN inventory available for public purchase.
        inventory: Balance<BTEN>,
        /// Where buyer SUI is sent (typically ops).
        sui_recipient: address,
        /// Address allowed to push keeper mid price updates without AdminCap.
        price_updater: address,
        /// Expected Cetus `Pool<BTEN, SUI>` object id.
        pool_id: address,
        /// Mist SUI required to buy 1 full BTEN (UNIT mist). Equal to WAL-implied mid — **no discount**.
        price_mist_sui_per_bten: u64,
        /// Last keeper / admin price update (ms), 0 if never set by clock.
        price_updated_ms: u64,
        paused: bool,
        total_sold_bten: u64,
        total_received_sui: u64,
    }

    public struct OpsBuyDeskCreated has copy, drop {
        desk_id: address,
        sui_recipient: address,
        price_updater: address,
        pool_id: address,
        initial_price_mist_sui_per_bten: u64,
    }

    public struct OpsBuyDeskDeposit has copy, drop {
        desk_id: address,
        amount: u64,
        inventory_after: u64,
    }

    public struct OpsBuyDeskWithdraw has copy, drop {
        desk_id: address,
        amount: u64,
        inventory_after: u64,
    }

    public struct OpsBuyDeskPriceUpdated has copy, drop {
        desk_id: address,
        price_mist_sui_per_bten: u64,
        updated_ms: u64,
        updater: address,
    }

    public struct OpsBuyDeskPurchase has copy, drop {
        desk_id: address,
        buyer: address,
        sui_in: u64,
        bten_out: u64,
        price_mist_sui_per_bten: u64,
        pricing: u8, // 0 = pool mid in-tx, 1 = posted keeper price
        inventory_after: u64,
    }

    public struct OpsBuyDeskPaused has copy, drop {
        desk_id: address,
        paused: bool,
    }

    /// Create the shared desk. Transfers `OpsBuyDeskAdminCap` to `operator`.
    public entry fun create(
        _admin: &RegistryAdminCap,
        operator: address,
        sui_recipient: address,
        price_updater: address,
        pool_id: address,
        initial_price_mist_sui_per_bten: u64,
        ctx: &mut TxContext,
    ) {
        assert!(operator != @0x0, E_BAD_RECIPIENT);
        assert!(sui_recipient != @0x0, E_BAD_RECIPIENT);
        assert!(price_updater != @0x0, E_BAD_RECIPIENT);
        assert!(pool_id != @0x0, E_BAD_POOL);
        assert!(initial_price_mist_sui_per_bten > 0, E_BAD_PRICE);

        let desk = OpsBuyDesk {
            id: object::new(ctx),
            inventory: balance::zero<BTEN>(),
            sui_recipient,
            price_updater,
            pool_id,
            price_mist_sui_per_bten: initial_price_mist_sui_per_bten,
            price_updated_ms: 0,
            paused: false,
            total_sold_bten: 0,
            total_received_sui: 0,
        };
        let desk_id = object::id_to_address(&object::id(&desk));
        event::emit(OpsBuyDeskCreated {
            desk_id,
            sui_recipient,
            price_updater,
            pool_id,
            initial_price_mist_sui_per_bten,
        });
        transfer::share_object(desk);
        transfer::public_transfer(OpsBuyDeskAdminCap { id: object::new(ctx) }, operator);
    }

    public entry fun deposit_bten(
        desk: &mut OpsBuyDesk,
        _admin: &OpsBuyDeskAdminCap,
        coin: Coin<BTEN>,
    ) {
        let amount = coin::value(&coin);
        assert!(amount > 0, E_BAD_AMOUNT);
        balance::join(&mut desk.inventory, coin::into_balance(coin));
        event::emit(OpsBuyDeskDeposit {
            desk_id: object::id_to_address(&object::id(desk)),
            amount,
            inventory_after: balance::value(&desk.inventory),
        });
    }

    public entry fun withdraw_bten(
        desk: &mut OpsBuyDesk,
        _admin: &OpsBuyDeskAdminCap,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(amount > 0, E_BAD_AMOUNT);
        assert!(amount <= balance::value(&desk.inventory), E_INVENTORY);
        let out = coin::from_balance(balance::split(&mut desk.inventory, amount), ctx);
        event::emit(OpsBuyDeskWithdraw {
            desk_id: object::id_to_address(&object::id(desk)),
            amount,
            inventory_after: balance::value(&desk.inventory),
        });
        transfer::public_transfer(out, tx_context::sender(ctx));
    }

    public entry fun set_paused(
        desk: &mut OpsBuyDesk,
        _admin: &OpsBuyDeskAdminCap,
        paused: bool,
    ) {
        desk.paused = paused;
        event::emit(OpsBuyDeskPaused {
            desk_id: object::id_to_address(&object::id(desk)),
            paused,
        });
    }

    public entry fun set_sui_recipient(
        desk: &mut OpsBuyDesk,
        _admin: &OpsBuyDeskAdminCap,
        sui_recipient: address,
    ) {
        assert!(sui_recipient != @0x0, E_BAD_RECIPIENT);
        desk.sui_recipient = sui_recipient;
    }

    public entry fun set_pool_id(
        desk: &mut OpsBuyDesk,
        _admin: &OpsBuyDeskAdminCap,
        pool_id: address,
    ) {
        assert!(pool_id != @0x0, E_BAD_POOL);
        desk.pool_id = pool_id;
    }

    public entry fun set_price_updater(
        desk: &mut OpsBuyDesk,
        _admin: &OpsBuyDeskAdminCap,
        price_updater: address,
    ) {
        assert!(price_updater != @0x0, E_BAD_RECIPIENT);
        desk.price_updater = price_updater;
    }

    /// Admin sets posted mid price (mist SUI per 1 BTEN). Must equal Cetus mid — no discount.
    public entry fun set_price_mist_sui_per_bten_admin(
        desk: &mut OpsBuyDesk,
        _admin: &OpsBuyDeskAdminCap,
        price_mist_sui_per_bten: u64,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        apply_price(desk, price_mist_sui_per_bten, clock::timestamp_ms(clock), tx_context::sender(ctx));
    }

    /// Keeper / price_updater sets posted mid = Cetus mid (no −2% or other discount).
    public entry fun set_price_mist_sui_per_bten(
        desk: &mut OpsBuyDesk,
        price_mist_sui_per_bten: u64,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let updater = tx_context::sender(ctx);
        assert!(updater == desk.price_updater, E_NOT_UPDATER);
        apply_price(desk, price_mist_sui_per_bten, clock::timestamp_ms(clock), updater);
    }

    fun apply_price(desk: &mut OpsBuyDesk, price: u64, updated_ms: u64, updater: address) {
        assert!(price > 0, E_BAD_PRICE);
        desk.price_mist_sui_per_bten = price;
        desk.price_updated_ms = updated_ms;
        event::emit(OpsBuyDeskPriceUpdated {
            desk_id: object::id_to_address(&object::id(desk)),
            price_mist_sui_per_bten: price,
            updated_ms,
            updater,
        });
    }

    /// Public buy: pay `Coin<SUI>`, receive BTEN at **on-chain Cetus pool mid**.
    /// No discount. `min_bten_out` is the buyer slippage floor.
    public entry fun buy_with_sui(
        desk: &mut OpsBuyDesk,
        pool: &Pool<BTEN, SUI>,
        payment: Coin<SUI>,
        min_bten_out: u64,
        ctx: &mut TxContext,
    ) {
        assert!(!desk.paused, E_PAUSED);
        let pool_addr = object::id_to_address(&object::id(pool));
        assert!(pool_addr == desk.pool_id, E_BAD_POOL);

        let sui_in = coin::value(&payment);
        assert!(sui_in > 0, E_ZERO_INPUT);

        let sqrt_price = pool::current_sqrt_price(pool);
        let bten_out = bten_out_at_sqrt_mid(sui_in, sqrt_price);
        // Effective posted-equivalent price for the event (mist SUI per 1 BTEN).
        let effective_price = price_mist_sui_per_bten_from_sqrt(sqrt_price);
        settle_buy(desk, payment, sui_in, bten_out, min_bten_out, effective_price, /*pricing=*/0, ctx);
    }

    /// Primary buy at the keeper-posted mid (`price_mist_sui_per_bten`).
    /// Keeper must keep this equal to WAL-implied mid (BTEN/WAL × WAL/SUI; no discount).
    public entry fun buy_with_sui_posted_price(
        desk: &mut OpsBuyDesk,
        payment: Coin<SUI>,
        min_bten_out: u64,
        ctx: &mut TxContext,
    ) {
        assert!(!desk.paused, E_PAUSED);
        let sui_in = coin::value(&payment);
        assert!(sui_in > 0, E_ZERO_INPUT);
        let price = desk.price_mist_sui_per_bten;
        let bten_out = bten_out_at_posted_price(sui_in, price);
        settle_buy(desk, payment, sui_in, bten_out, min_bten_out, price, /*pricing=*/1, ctx);
    }

    fun settle_buy(
        desk: &mut OpsBuyDesk,
        payment: Coin<SUI>,
        sui_in: u64,
        bten_out: u64,
        min_bten_out: u64,
        price_mist_sui_per_bten: u64,
        pricing: u8,
        ctx: &mut TxContext,
    ) {
        assert!(bten_out > 0, E_BAD_AMOUNT);
        assert!(bten_out >= min_bten_out, E_MIN_OUT);
        assert!(bten_out <= balance::value(&desk.inventory), E_INVENTORY);

        transfer::public_transfer(payment, desk.sui_recipient);
        let out = coin::from_balance(balance::split(&mut desk.inventory, bten_out), ctx);
        let buyer = tx_context::sender(ctx);
        desk.total_sold_bten = desk.total_sold_bten + bten_out;
        desk.total_received_sui = desk.total_received_sui + sui_in;
        event::emit(OpsBuyDeskPurchase {
            desk_id: object::id_to_address(&object::id(desk)),
            buyer,
            sui_in,
            bten_out,
            price_mist_sui_per_bten,
            pricing,
            inventory_after: balance::value(&desk.inventory),
        });
        transfer::public_transfer(out, buyer);
    }

    /// BTEN mist out for SUI mist in at Cetus mid for `Pool<BTEN, SUI>`.
    /// `raw = sui_mist/bten_mist = sqrt_price^2 / 2^128` → `bten_out = sui_in * 2^128 / sqrt^2`.
    public fun bten_out_at_sqrt_mid(sui_in: u64, sqrt_price: u128): u64 {
        assert!(sui_in > 0, E_ZERO_INPUT);
        assert!(sqrt_price > 0, E_BAD_PRICE);
        let sq = (sqrt_price as u256) * (sqrt_price as u256);
        let out = ((sui_in as u256) << 128) / sq;
        assert!(out > 0, E_BAD_AMOUNT);
        assert!(out <= 18446744073709551615u256, E_OVERFLOW);
        (out as u64)
    }

    /// Mist SUI required to buy 1 full BTEN (UNIT mist) from sqrt mid.
    /// `price = sqrt^2 * UNIT / 2^128`.
    public fun price_mist_sui_per_bten_from_sqrt(sqrt_price: u128): u64 {
        assert!(sqrt_price > 0, E_BAD_PRICE);
        let sq = (sqrt_price as u256) * (sqrt_price as u256);
        let p = (sq * (UNIT as u256)) >> 128;
        assert!(p > 0, E_BAD_PRICE);
        assert!(p <= 18446744073709551615u256, E_OVERFLOW);
        (p as u64)
    }

    /// Posted-price path: `bten_out = sui_in * UNIT / price_mist_sui_per_bten`.
    public fun bten_out_at_posted_price(sui_in: u64, price_mist_sui_per_bten: u64): u64 {
        assert!(sui_in > 0, E_ZERO_INPUT);
        assert!(price_mist_sui_per_bten > 0, E_BAD_PRICE);
        let out = ((sui_in as u128) * (UNIT as u128)) / (price_mist_sui_per_bten as u128);
        assert!(out > 0, E_BAD_AMOUNT);
        assert!(out <= 18446744073709551615u128, E_OVERFLOW);
        (out as u64)
    }

    public fun unit(): u64 { UNIT }
    public fun inventory(desk: &OpsBuyDesk): u64 { balance::value(&desk.inventory) }
    public fun is_paused(desk: &OpsBuyDesk): bool { desk.paused }
    public fun sui_recipient(desk: &OpsBuyDesk): address { desk.sui_recipient }
    public fun price_updater(desk: &OpsBuyDesk): address { desk.price_updater }
    public fun pool_id(desk: &OpsBuyDesk): address { desk.pool_id }
    public fun price_mist_sui_per_bten(desk: &OpsBuyDesk): u64 { desk.price_mist_sui_per_bten }
    public fun price_updated_ms(desk: &OpsBuyDesk): u64 { desk.price_updated_ms }
    public fun total_sold_bten(desk: &OpsBuyDesk): u64 { desk.total_sold_bten }
    public fun total_received_sui(desk: &OpsBuyDesk): u64 { desk.total_received_sui }

}
