#[test_only]
module bten::bten_tests {
    use bten::bten;
    use sui::coin;
    use sui::clock::{Self, Clock};
    use sui::test_scenario;

    #[test]
    fun policy_and_one_block_allocation() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            clock::set_for_testing(&mut clock, 1_000);
            bten::record_qualified_route_for_testing(&mut state, 1, &clock, scenario.ctx());
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        let mut i: u64 = 0;
        while (i < 9) {
            scenario.next_tx(admin);
            let mut state = scenario.take_shared<bten::EmissionState>();
            let clock = scenario.take_shared<Clock>();
            bten::record_qualified_route_for_testing(&mut state, 1, &clock, scenario.ctx());
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
            i = i + 1;
        };
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            clock::set_for_testing(&mut clock, 601_000);
            bten::settle(&mut state, &clock, scenario.ctx());
            assert!(bten::block_height(&state) == 1, 0);
            assert!(bten::total_minted(&state) == 5_000_000_000, 1);
            assert!(bten::route_fee_balance(&state) == 2_500_000_000, 2);
            assert!(bten::trader_balance(&state) == 500_000_000, 3);
            assert!(bten::bten_lp_balance(&state) == 1_250_000_000, 4);
            assert!(bten::staking_balance(&state) == 500_000_000, 5);
            assert!(bten::cetus_balance(&state) == 50_000_000, 6);
            assert!(bten::haedal_balance(&state) == 50_000_000, 7);
            assert!(bten::blue_balance(&state) == 50_000_000, 8);
            assert!(bten::turbos_balance(&state) == 50_000_000, 9);
            assert!(bten::sui_gas_balance(&state) == 50_000_000, 10);
            assert!(bten::haedal_balance(&state) == 50_000_000, 11);
            bten::auto_pay_trader(&mut state, 0, admin, scenario.ctx());
            assert!(bten::trader_balance(&state) == 0, 12);
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.next_tx(admin);
        {
            let reward = scenario.take_from_sender<coin::Coin<bten::BTEN>>();
            assert!(coin::value(&reward) == 500_000_000, 13);
            coin::destroy_zero(coin::zero<bten::BTEN>(scenario.ctx()));
            scenario.return_to_sender(reward);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 11)]
    fun legacy_router_cap_cannot_record_routes() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        let mut state = scenario.take_shared<bten::EmissionState>();
        let clock = scenario.take_shared<Clock>();
        let router_cap = scenario.take_from_sender<bten::RouterCap>();
        bten::record_qualified_route(&mut state, &router_cap, 1, &clock, scenario.ctx());
        // Unreachable: expected_failure confirms legacy calls now abort.
        test_scenario::return_shared(state);
        test_scenario::return_shared(clock);
        scenario.return_to_sender(router_cap);
        scenario.end();
    }
}
