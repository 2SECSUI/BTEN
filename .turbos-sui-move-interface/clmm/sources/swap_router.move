module turbos_clmm::swap_router {
    use sui::tx_context::TxContext;
    use turbos_clmm::pool::{Pool, Versioned};
    use sui::coin::Coin;
    use sui::clock::Clock;

    public fun swap_a_b_with_return_<CoinTypeA, CoinTypeB, FeeType>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB, FeeType>,
        _coins_a: vector<Coin<CoinTypeA>>,
        _amount: u64,
        _amount_threshold: u64,
        _sqrt_price_limit: u128,
        _is_exact_in: bool,
        _recipient: address,
        _deadline: u64,
        _clock: &Clock,
        _versioned: &Versioned,
        _ctx: &mut TxContext,
    ): (Coin<CoinTypeB>, Coin<CoinTypeA>) {
        abort 0
    }

    public fun swap_b_a_with_return_<CoinTypeA, CoinTypeB, FeeType>(
        _pool: &mut Pool<CoinTypeA, CoinTypeB, FeeType>,
        _coins_b: vector<Coin<CoinTypeB>>,
        _amount: u64,
        _amount_threshold: u64,
        _sqrt_price_limit: u128,
        _is_exact_in: bool,
        _recipient: address,
        _deadline: u64,
        _clock: &Clock,
        _versioned: &Versioned,
        _ctx: &mut TxContext,
    ): (Coin<CoinTypeA>, Coin<CoinTypeB>) {
        abort 0
    }
}
