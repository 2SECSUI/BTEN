module turbos_clmm::pool {
    use std::string::String;
    use sui::object::{UID, ID};
    use sui::balance::Balance;
    use sui::table::Table;
    use sui::coin::Coin;
    use sui::clock::Clock;
    use sui::tx_context::TxContext;
    use turbos_clmm::i32::I32;

    public struct Versioned has key, store {
        id: UID,
        version: u64,
    }

    public struct PoolRewardInfo has key, store {
        id: UID,
        vault: address,
        vault_coin_type: String,
        emissions_per_second: u128,
        growth_global: u128,
        manager: address,
    }

    public struct Pool<phantom CoinTypeA, phantom CoinTypeB, phantom FeeType> has key, store {
        id: UID,
        coin_a: Balance<CoinTypeA>,
        coin_b: Balance<CoinTypeB>,
        protocol_fees_a: u64,
        protocol_fees_b: u64,
        sqrt_price: u128,
        tick_current_index: I32,
        tick_spacing: u32,
        max_liquidity_per_tick: u128,
        fee: u32,
        fee_protocol: u32,
        unlocked: bool,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        liquidity: u128,
        tick_map: Table<I32, u256>,
        deploy_time_ms: u64,
        reward_infos: vector<PoolRewardInfo>,
        reward_last_updated_time_ms: u64,
    }

    public struct FlashSwapReceipt<phantom CoinTypeA, phantom CoinTypeB> {
        pool_id: ID,
        a_to_b: bool,
        pay_amount: u64,
    }

    public fun flash_swap<CoinTypeA, CoinTypeB, FeeType>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB, FeeType>,
        _recipient: address,
        _a_to_b: bool,
        _amount_specified: u128,
        _amount_specified_is_input: bool,
        _sqrt_price_limit: u128,
        _clock: &Clock,
        _versioned: &Versioned,
        _ctx: &mut TxContext,
    ): (Coin<CoinTypeA>, Coin<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        abort 0
    }

    public fun repay_flash_swap<CoinTypeA, CoinTypeB, FeeType>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB, FeeType>,
        _coin_a: Coin<CoinTypeA>,
        _coin_b: Coin<CoinTypeB>,
        _receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>,
        _versioned: &Versioned,
    ) {
        abort 0
    }
}
