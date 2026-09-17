#[test_only]
module bten::ops_buy_desk_tests {
    use bten::bten::{Self, BTEN};
    use bten::ops_buy_desk::{Self, OpsBuyDesk, OpsBuyDeskAdminCap};
    use sui::clock::{Self, Clock};
    use sui::coin;
    use sui::sui::SUI;
    use sui::test_scenario;

    const POOL: address = @0x7f46bdbd74d2f162617376e4cecccb2c603bb9459766226d1359b38a605a2950;
    /// Live-ish mid sample: ~0.4285 SUI per BTEN → 428465615 mist SUI per 1 BTEN.
    const SAMPLE_PRICE: u64 = 428_465_615;
    const SAMPLE_SQRT: u128 = 38_183_673_712_928_216_200;

    #[test]
    fun sqrt_mid_math_matches_posted_price() {
        let from_sqrt = ops_buy_desk::price_mist_sui_per_bten_from_sqrt(SAMPLE_SQRT);
        // Allow 1 mist rounding vs Python float reference SAMPLE_PRICE
        assert!(from_sqrt > SAMPLE_PRICE - 2 && from_sqrt < SAMPLE_PRICE + 2, 1);

        let sui_in = 2_000_000; // 0.002 SUI
        let out_sqrt = ops_buy_desk::bten_out_at_sqrt_mid(sui_in, SAMPLE_SQRT);
        let out_posted = ops_buy_desk::bten_out_at_posted_price(sui_in, from_sqrt);
        assert!(out_sqrt == out_posted, 2);
        assert!(out_sqrt > 400_000, 3); // ~0.004667 BTEN
    }

    #[test]
    fun posted_price_no_discount() {
        // 1 SUI at 0.5 SUI/BTEN → exactly 2 BTEN (no −2%)
        let price = 500_000_000; // 0.5 SUI per BTEN
        let out = ops_buy_desk::bten_out_at_posted_price(1_000_000_000, price);
        assert!(out == 200_000_000, 10);
    }

    #[test]
    fun create_deposit_buy_posted_and_withdraw() {
        let admin = @0xA;
        let ops = @0xB;
        let buyer = @0xC;
        let updater = @0xD;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();

        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            ops_buy_desk::create(
                &admin_cap,
                ops,
                ops,
                updater,
                POOL,
                SAMPLE_PRICE,
                scenario.ctx(),
            );
            scenario.return_to_sender(admin_cap);
        };

        // Mint BTEN for ops via taking from emission? Use coin::mint_for_testing
        scenario.next_tx(ops);
        {
            let mut desk = scenario.take_shared<OpsBuyDesk>();
            let desk_admin = scenario.take_from_sender<OpsBuyDeskAdminCap>();
            assert!(!ops_buy_desk::is_paused(&desk), 20);
            assert!(ops_buy_desk::pool_id(&desk) == POOL, 21);
            assert!(ops_buy_desk::price_mist_sui_per_bten(&desk) == SAMPLE_PRICE, 22);

            let deposit = coin::mint_for_testing<BTEN>(1_000_000_000, scenario.ctx()); // 10 BTEN
            ops_buy_desk::deposit_bten(&mut desk, &desk_admin, deposit);
            assert!(ops_buy_desk::inventory(&desk) == 1_000_000_000, 23);

            test_scenario::return_shared(desk);
            scenario.return_to_sender(desk_admin);
        };

        // Keeper updates price (= mid, no discount)
        scenario.next_tx(updater);
        {
            let mut desk = scenario.take_shared<OpsBuyDesk>();
            let mut clock = scenario.take_shared<Clock>();
            clock::set_for_testing(&mut clock, 1_700_000_000_000);
            let new_price = 400_000_000; // 0.4 SUI / BTEN
            ops_buy_desk::set_price_mist_sui_per_bten(&mut desk, new_price, &clock, scenario.ctx());
            assert!(ops_buy_desk::price_mist_sui_per_bten(&desk) == new_price, 30);
            assert!(ops_buy_desk::price_updated_ms(&desk) == 1_700_000_000_000, 31);
            test_scenario::return_shared(desk);
            test_scenario::return_shared(clock);
        };

        // Create ops interaction fee config (default recipient = OPS_FEE_RECIPIENT)
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::create_ops_interaction_fee_config(&admin_cap, scenario.ctx());
            scenario.return_to_sender(admin_cap);
        };

        // Buyer pays 0.4 SUI purchase + 0.5 SUI ops fee → 1 BTEN at posted mid
        scenario.next_tx(buyer);
        {
            let mut desk = scenario.take_shared<OpsBuyDesk>();
            let fee_cfg = scenario.take_shared<bten::OpsInteractionFeeConfig>();
            assert!(bten::ops_interaction_fee_mist(&fee_cfg) == 500_000_000, 39);
            let payment = coin::mint_for_testing<SUI>(400_000_000, scenario.ctx());
            let ops_fee = coin::mint_for_testing<SUI>(500_000_000, scenario.ctx());
            ops_buy_desk::buy_with_sui_posted_price_ops_fee(
                &mut desk, &fee_cfg, ops_fee, payment, 100_000_000, scenario.ctx(),
            );
            assert!(ops_buy_desk::inventory(&desk) == 900_000_000, 40);
            assert!(ops_buy_desk::total_sold_bten(&desk) == 100_000_000, 41);
            assert!(ops_buy_desk::total_received_sui(&desk) == 400_000_000, 42);
            test_scenario::return_shared(desk);
            test_scenario::return_shared(fee_cfg);
        };

        scenario.next_tx(buyer);
        {
            let got = scenario.take_from_sender<coin::Coin<BTEN>>();
            assert!(coin::value(&got) == 100_000_000, 50);
            scenario.return_to_sender(got);
        };

        // Desk sui_recipient (ops) receives purchase SUI
        scenario.next_tx(ops);
        {
            let sui = scenario.take_from_sender<coin::Coin<SUI>>();
            assert!(coin::value(&sui) == 400_000_000, 55);
            scenario.return_to_sender(sui);
        };

        // Default OPS_FEE_RECIPIENT receives the 0.5 SUI interaction fee
        let fee_ops = bten::default_ops_fee_recipient();
        scenario.next_tx(fee_ops);
        {
            let fee = scenario.take_from_sender<coin::Coin<SUI>>();
            assert!(coin::value(&fee) == 500_000_000, 56);
            scenario.return_to_sender(fee);
        };

        // Withdraw remaining inventory
        scenario.next_tx(ops);
        {
            let mut desk = scenario.take_shared<OpsBuyDesk>();
            let desk_admin = scenario.take_from_sender<OpsBuyDeskAdminCap>();
            ops_buy_desk::withdraw_bten(&mut desk, &desk_admin, 900_000_000, scenario.ctx());
            assert!(ops_buy_desk::inventory(&desk) == 0, 60);
            test_scenario::return_shared(desk);
            scenario.return_to_sender(desk_admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun buy_aborts_when_paused() {
        let admin = @0xA;
        let ops = @0xB;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            ops_buy_desk::create(&admin_cap, ops, ops, ops, POOL, SAMPLE_PRICE, scenario.ctx());
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::create_ops_interaction_fee_config(&admin_cap, scenario.ctx());
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(ops);
        {
            let mut desk = scenario.take_shared<OpsBuyDesk>();
            let desk_admin = scenario.take_from_sender<OpsBuyDeskAdminCap>();
            let fee_cfg = scenario.take_shared<bten::OpsInteractionFeeConfig>();
            ops_buy_desk::deposit_bten(
                &mut desk,
                &desk_admin,
                coin::mint_for_testing<BTEN>(100_000_000, scenario.ctx()),
            );
            ops_buy_desk::set_paused(&mut desk, &desk_admin, true);
            let payment = coin::mint_for_testing<SUI>(500_000_000, scenario.ctx());
            let ops_fee = coin::mint_for_testing<SUI>(500_000_000, scenario.ctx());
            ops_buy_desk::buy_with_sui_posted_price_ops_fee(
                &mut desk, &fee_cfg, ops_fee, payment, 1, scenario.ctx(),
            );
            test_scenario::return_shared(desk);
            test_scenario::return_shared(fee_cfg);
            scenario.return_to_sender(desk_admin);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 4)]
    fun buy_aborts_on_slippage() {
        let admin = @0xA;
        let ops = @0xB;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            ops_buy_desk::create(&admin_cap, ops, ops, ops, POOL, SAMPLE_PRICE, scenario.ctx());
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::create_ops_interaction_fee_config(&admin_cap, scenario.ctx());
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(ops);
        {
            let mut desk = scenario.take_shared<OpsBuyDesk>();
            let desk_admin = scenario.take_from_sender<OpsBuyDeskAdminCap>();
            let fee_cfg = scenario.take_shared<bten::OpsInteractionFeeConfig>();
            ops_buy_desk::deposit_bten(
                &mut desk,
                &desk_admin,
                coin::mint_for_testing<BTEN>(1_000_000_000, scenario.ctx()),
            );
            // 0.002 SUI → ~466781 mist; demand impossible min_out
            let payment = coin::mint_for_testing<SUI>(2_000_000, scenario.ctx());
            let ops_fee = coin::mint_for_testing<SUI>(500_000_000, scenario.ctx());
            ops_buy_desk::buy_with_sui_posted_price_ops_fee(
                &mut desk, &fee_cfg, ops_fee, payment, 1_000_000_000, scenario.ctx(),
            );
            test_scenario::return_shared(desk);
            test_scenario::return_shared(fee_cfg);
            scenario.return_to_sender(desk_admin);
        };
        scenario.end();
    }

    /// Legacy free buy path must abort (v30).
    #[test]
    #[expected_failure(abort_code = 11)]
    fun legacy_buy_requires_ops_fee() {
        let admin = @0xA;
        let ops = @0xB;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            ops_buy_desk::create(&admin_cap, ops, ops, ops, POOL, SAMPLE_PRICE, scenario.ctx());
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(ops);
        {
            let mut desk = scenario.take_shared<OpsBuyDesk>();
            let desk_admin = scenario.take_from_sender<OpsBuyDeskAdminCap>();
            ops_buy_desk::deposit_bten(
                &mut desk,
                &desk_admin,
                coin::mint_for_testing<BTEN>(100_000_000, scenario.ctx()),
            );
            let payment = coin::mint_for_testing<SUI>(400_000_000, scenario.ctx());
            ops_buy_desk::buy_with_sui_posted_price(&mut desk, payment, 1, scenario.ctx());
            test_scenario::return_shared(desk);
            scenario.return_to_sender(desk_admin);
        };
        scenario.end();
    }
}
