#[test_only]
module bten::bten_tests {
    use bten::bten;
    use sui::coin;
    use sui::clock::{Self, Clock};
    use sui::test_scenario;
    use sui::transfer;

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
    fun keeper_config_starts_paused_and_is_bounded() {
        let admin = @0xA;
        let keeper = @0xB;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();

        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            let clock = scenario.take_shared<Clock>();
            bten::create_keeper_config(&admin_cap, keeper, 500_000_000, &clock, scenario.ctx());
            test_scenario::return_shared(clock);
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let config = scenario.take_shared<bten::KeeperConfig>();
            assert!(bten::keeper_address(&config) == keeper, 40);
            assert!(bten::keeper_is_paused(&config), 41);
            assert!(bten::keeper_daily_staking_cap(&config) == 500_000_000, 42);
            assert!(bten::keeper_staking_spent_today(&config) == 0, 43);
            test_scenario::return_shared(config);
        };
        scenario.next_tx(keeper);
        {
            let cap = scenario.take_from_sender<bten::KeeperCap>();
            scenario.return_to_sender(cap);
        };
        scenario.end();
    }

    #[test]
    fun keeper_can_only_withdraw_the_unpaused_staking_tranche() {
        let admin = @0xA;
        let keeper = @0xB;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();

        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            let clock = scenario.take_shared<Clock>();
            bten::create_keeper_config(&admin_cap, keeper, 500_000_000, &clock, scenario.ctx());
            test_scenario::return_shared(clock);
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let mut config = scenario.take_shared<bten::KeeperConfig>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::set_keeper_paused(&mut config, &admin_cap, false);
            test_scenario::return_shared(config);
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            clock::set_for_testing(&mut clock, 1_000);
            let mut i: u64 = 0;
            while (i < 10) {
                bten::record_qualified_route_for_testing(&mut state, 1, &clock, scenario.ctx());
                i = i + 1;
            };
            clock::set_for_testing(&mut clock, 601_000);
            bten::settle(&mut state, &clock, scenario.ctx());
            assert!(bten::staking_balance(&state) == 500_000_000, 44);
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.next_tx(keeper);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut config = scenario.take_shared<bten::KeeperConfig>();
            let clock = scenario.take_shared<Clock>();
            let cap = scenario.take_from_sender<bten::KeeperCap>();
            bten::withdraw_staking_tranche_to_keeper(&mut state, &mut config, &cap, 500_000_000, &clock, scenario.ctx());
            assert!(bten::staking_balance(&state) == 0, 45);
            assert!(bten::keeper_staking_spent_today(&config) == 500_000_000, 46);
            test_scenario::return_shared(state);
            test_scenario::return_shared(config);
            test_scenario::return_shared(clock);
            scenario.return_to_sender(cap);
        };
        scenario.next_tx(keeper);
        {
            let reward = scenario.take_from_sender<coin::Coin<bten::BTEN>>();
            assert!(coin::value(&reward) == 500_000_000, 47);
            scenario.return_to_sender(reward);
        };
        scenario.end();
    }

    #[test]
    fun lp_program_migrates_paused_backlog_and_enforces_allowlist() {
        let admin = @0xA;
        let pool = @0xB;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();

        scenario.next_tx(admin);
        {
            let mut registry = scenario.take_shared<bten::PoolRegistry>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::register_pool(&mut registry, &admin_cap, pool, 1);
            bten::create_lp_program(&admin_cap, admin, scenario.ctx());
            test_scenario::return_shared(registry);
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let mut programme = scenario.take_shared<bten::LpProgramState>();
            let registry = scenario.take_shared<bten::PoolRegistry>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::register_lp_program_pool(&mut programme, &registry, &admin_cap, pool, 10_000);
            bten::finalize_lp_program(&mut programme, &admin_cap);
            bten::set_lp_program_paused(&mut programme, &admin_cap, false);
            test_scenario::return_shared(programme);
            test_scenario::return_shared(registry);
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            clock::set_for_testing(&mut clock, 1_000);
            let mut i: u64 = 0;
            while (i < 10) {
                bten::record_qualified_route_for_testing(&mut state, 1, &clock, scenario.ctx());
                i = i + 1;
            };
            clock::set_for_testing(&mut clock, 601_000);
            bten::settle(&mut state, &clock, scenario.ctx());
            let mut programme = scenario.take_shared<bten::LpProgramState>();
            bten::accrue_lp_program(&mut state, &mut programme);
            assert!(bten::bten_lp_balance(&state) == 0, 50);
            assert!(bten::cetus_balance(&state) == 0, 51);
            assert!(bten::haedal_balance(&state) == 0, 52);
            assert!(bten::blue_balance(&state) == 0, 53);
            assert!(bten::turbos_balance(&state) == 0, 54);
            assert!(bten::sui_gas_balance(&state) == 0, 55);
            assert!(bten::lp_program_protocol_balance(&programme) == 1_050_000_000, 56);
            assert!(bten::lp_program_cetus_reward_balance(&programme) == 450_000_000, 57);
            let cap = scenario.take_from_sender<bten::LpProgramCap>();
            let funding = bten::take_protocol_liquidity(&mut programme, &cap, pool, 100_000_000, scenario.ctx());
            transfer::public_transfer(funding, admin);
            scenario.return_to_sender(cap);
            test_scenario::return_shared(programme);
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
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
