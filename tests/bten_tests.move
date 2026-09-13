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
            assert!(bten::lp_program_protocol_balance(&programme) == 1_500_000_000, 56);
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
    fun external_cetus_verifier_is_capped_and_records_one_gate() {
        let admin = @0xA;
        let keeper = @0xB;
        let pool = @0xC;
        let trader = @0xD;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();

        scenario.next_tx(admin);
        {
            let mut registry = scenario.take_shared<bten::PoolRegistry>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            let clock = scenario.take_shared<Clock>();
            bten::register_pool(&mut registry, &admin_cap, pool, 1);
            bten::finalize_pool_registry(&mut registry, &admin_cap);
            bten::create_external_route_verifier(&registry, &admin_cap, keeper, 2, &clock, scenario.ctx());
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
            scenario.return_to_sender(admin_cap);
        };

        scenario.next_tx(admin);
        {
            let mut verifier = scenario.take_shared<bten::ExternalRouteVerifierState>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::set_external_route_verifier_paused(&mut verifier, &admin_cap, false);
            test_scenario::return_shared(verifier);
            scenario.return_to_sender(admin_cap);
        };

        scenario.next_tx(keeper);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let registry = scenario.take_shared<bten::PoolRegistry>();
            let mut verifier = scenario.take_shared<bten::ExternalRouteVerifierState>();
            let cap = scenario.take_from_sender<bten::ExternalRouteVerifierCap>();
            let clock = scenario.take_shared<Clock>();
            let digest = vector[
                1u8, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
                1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            ];
            bten::attest_external_cetus_route(
                &mut state, &registry, &mut verifier, &cap, pool, digest, 0,
                trader, 99, &clock, scenario.ctx(),
            );
            assert!(bten::batch_trades(&state) == 1, 60);
            assert!(bten::external_verifier_events_today(&verifier) == 1, 61);
            assert!(bten::external_verifier_daily_cap(&verifier) == 2, 62);
            test_scenario::return_shared(state);
            test_scenario::return_shared(registry);
            test_scenario::return_shared(verifier);
            test_scenario::return_shared(clock);
            scenario.return_to_sender(cap);
        };
        scenario.end();
    }

    #[test]
    fun pending_slots_release_without_trades() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            assert!(bten::batch_trades(&state) == 0, 84);
            assert!(bten::max_settle_blocks() == 1, 88);
            clock::set_for_testing(&mut clock, 1_000);
            bten::prime_slots_for_testing(&mut state, &clock);
            // Two elapsed slots create pending=2, but settle releases only 1.
            clock::set_for_testing(&mut clock, 1_201_000);
            bten::settle(&mut state, &clock, scenario.ctx());
            assert!(bten::block_height(&state) == 1, 85);
            assert!(bten::pending_blocks(&state) == 1, 89);
            assert!(bten::batch_trades(&state) == 0, 86);
            assert!(bten::total_minted(&state) == 5_000_000_000, 87);
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.end();
    }

    /// Bitcoin-style cadence: even with a large pending backlog, one settle
    /// call unlocks at most one block (MAX_SETTLE_BLOCKS = 1).
    #[test]
    fun settle_releases_at_most_one_when_pending_large() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            clock::set_for_testing(&mut clock, 1_000);
            bten::prime_slots_for_testing(&mut state, &clock);
            // 100 * 600s = 60_000s → 100 pending slots after advance_slots.
            clock::set_for_testing(&mut clock, 60_001_000);
            assert!(bten::batch_trades(&state) == 0, 90);
            bten::settle(&mut state, &clock, scenario.ctx());
            assert!(bten::block_height(&state) == 1, 91);
            assert!(bten::pending_blocks(&state) == 99, 92);
            assert!(bten::total_minted(&state) == 5_000_000_000, 93);
            assert!(bten::max_settle_blocks() == 1, 94);
            // Second settle still only releases one more.
            bten::settle(&mut state, &clock, scenario.ctx());
            assert!(bten::block_height(&state) == 2, 95);
            assert!(bten::pending_blocks(&state) == 98, 96);
            assert!(bten::total_minted(&state) == 10_000_000_000, 97);
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.end();
    }

    #[test]
    fun one_gated_receipt_unlocks_one_pending_block() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            assert!(bten::min_trades_per_block() == 1, 80);
            clock::set_for_testing(&mut clock, 1_000);
            bten::record_qualified_route_for_testing(&mut state, 1, &clock, scenario.ctx());
            assert!(bten::batch_trades(&state) == 1, 81);
            clock::set_for_testing(&mut clock, 601_000);
            bten::settle(&mut state, &clock, scenario.ctx());
            assert!(bten::block_height(&state) == 1, 82);
            assert!(bten::batch_trades(&state) == 0, 83);
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.end();
    }

    #[test]
    fun batch_attest_records_one_receipt_per_digest() {
        let admin = @0xA;
        let keeper = @0xB;
        let pool = @0xC;
        let trader = @0xD;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();

        scenario.next_tx(admin);
        {
            let mut registry = scenario.take_shared<bten::PoolRegistry>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            let clock = scenario.take_shared<Clock>();
            bten::register_pool(&mut registry, &admin_cap, pool, 1);
            bten::finalize_pool_registry(&mut registry, &admin_cap);
            bten::create_external_route_verifier(&registry, &admin_cap, keeper, 3, &clock, scenario.ctx());
            test_scenario::return_shared(registry);
            test_scenario::return_shared(clock);
            scenario.return_to_sender(admin_cap);
        };

        scenario.next_tx(admin);
        {
            let mut verifier = scenario.take_shared<bten::ExternalRouteVerifierState>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::set_external_route_verifier_paused(&mut verifier, &admin_cap, false);
            test_scenario::return_shared(verifier);
            scenario.return_to_sender(admin_cap);
        };

        scenario.next_tx(keeper);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let registry = scenario.take_shared<bten::PoolRegistry>();
            let mut verifier = scenario.take_shared<bten::ExternalRouteVerifierState>();
            let cap = scenario.take_from_sender<bten::ExternalRouteVerifierCap>();
            let clock = scenario.take_shared<Clock>();
            let digest_a = vector[
                2u8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
                2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
            ];
            let digest_b = vector[
                3u8, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
                3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
            ];
            bten::attest_external_cetus_routes(
                &mut state, &registry, &mut verifier, &cap,
                vector[pool, pool],
                vector[digest_a, digest_b],
                vector[0, 0],
                vector[trader, trader],
                vector[1, 1],
                &clock, scenario.ctx(),
            );
            assert!(bten::batch_trades(&state) == 2, 90);
            assert!(bten::external_verifier_events_today(&verifier) == 2, 91);
            test_scenario::return_shared(state);
            test_scenario::return_shared(registry);
            test_scenario::return_shared(verifier);
            test_scenario::return_shared(clock);
            scenario.return_to_sender(cap);
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

    #[test]
    fun native_bten_farm_returns_principal_and_new_block_reward() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();

        // Create an unpaused native farm, then release the first block. The
        // farm has no staker yet, so that historical staking allocation stays
        // in EmissionState rather than becoming a late-depositor windfall.
        scenario.next_tx(admin);
        {
            let state = scenario.take_shared<bten::EmissionState>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::create_bten_staking_farm(&state, &admin_cap, admin, scenario.ctx());
            test_scenario::return_shared(state);
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            clock::set_for_testing(&mut clock, 1_000);
            let mut i = 0;
            while (i < 10) { bten::record_qualified_route_for_testing(&mut state, 1, &clock, scenario.ctx()); i = i + 1; };
            clock::set_for_testing(&mut clock, 601_000);
            bten::settle(&mut state, &clock, scenario.ctx());
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        // Use 1 BTEN as stake principal from the already-released staking
        // allocation; the remaining first-block allocation remains untouched.
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::withdraw_staking_rewards_to_sender(&mut state, &admin_cap, 100_000_000, scenario.ctx());
            test_scenario::return_shared(state);
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let stake = scenario.take_from_sender<coin::Coin<bten::BTEN>>();
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut farm = scenario.take_shared<bten::BtenStakingFarm>();
            bten::stake_bten(&mut state, &mut farm, stake, scenario.ctx());
            assert!(bten::bten_farm_total_staked(&farm) == 100_000_000, 70);
            test_scenario::return_shared(state);
            test_scenario::return_shared(farm);
        };
        // The next released block contributes its 10% (5 BTEN) allocation.
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            let mut i = 0;
            while (i < 10) { bten::record_qualified_route_for_testing(&mut state, 1, &clock, scenario.ctx()); i = i + 1; };
            clock::set_for_testing(&mut clock, 1_201_000);
            bten::settle(&mut state, &clock, scenario.ctx());
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut farm = scenario.take_shared<bten::BtenStakingFarm>();
            bten::withdraw_bten_and_rewards(&mut state, &mut farm, 100_000_000, scenario.ctx());
            assert!(bten::bten_farm_total_staked(&farm) == 0, 71);
            assert!(bten::bten_farm_reward_balance(&farm) == 0, 72);
            test_scenario::return_shared(state);
            test_scenario::return_shared(farm);
        };
        scenario.next_tx(admin);
        {
            let payout = scenario.take_from_sender<coin::Coin<bten::BTEN>>();
            assert!(coin::value(&payout) == 600_000_000, 73);
            scenario.return_to_sender(payout);
        };
        scenario.end();
    }

    #[test]
    fun composable_route_seals_once_for_accrued_hops() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();

        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let clock = scenario.take_shared<Clock>();
            let mut ticket = bten::open_composable_route(scenario.ctx());
            assert!(bten::composable_route_paid_points(&ticket) == 0, 100);
            // Two hops accrue points; sealing must mint exactly one gate receipt.
            bten::accrue_composable_route_for_testing(&mut ticket, 10, scenario.ctx());
            bten::accrue_composable_route_for_testing(&mut ticket, 25, scenario.ctx());
            assert!(bten::composable_route_paid_points(&ticket) == 35, 101);
            assert!(bten::batch_trades(&state) == 0, 102);
            bten::seal_composable_route(&mut state, ticket, &clock, scenario.ctx());
            assert!(bten::batch_trades(&state) == 1, 103);
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 14)]
    fun composable_route_seal_rejects_zero_accrual() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let clock = scenario.take_shared<Clock>();
            let ticket = bten::open_composable_route(scenario.ctx());
            bten::seal_composable_route(&mut state, ticket, &clock, scenario.ctx());
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 37)]
    fun composable_route_seal_rejects_foreign_trader() {
        let admin = @0xA;
        let other = @0xB;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let clock = scenario.take_shared<Clock>();
            // Pre-accrued ticket owned by other; admin cannot seal it.
            let mut ticket = bten::open_composable_route_as_for_testing(other);
            bten::force_accrue_composable_route_for_testing(&mut ticket, 7);
            bten::seal_composable_route(&mut state, ticket, &clock, scenario.ctx());
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.end();
    }

    #[test]
    fun managed_profit_fee_is_two_percent_of_profit_only() {
        // basis 100 / 50, returned 150 / 40 -> profit only on A (50), fee 1; B no profit
        let (fee_a, fee_b) = bten::managed_profit_fees(100, 50, 150, 40, 200);
        assert!(fee_a == 1, 300);
        assert!(fee_b == 0, 301);
        let (fee_a2, fee_b2) = bten::managed_profit_fees(100, 50, 100, 50, 200);
        assert!(fee_a2 == 0 && fee_b2 == 0, 302);
    }

    #[test]
    fun managed_vault_creates_and_pauses() {
        let admin = @0xA;
        let ops = @0xB;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            bten::create_managed_vault(&admin_cap, ops, scenario.ctx());
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<bten::ManagedVaultState>();
            let admin_cap = scenario.take_from_sender<bten::RegistryAdminCap>();
            assert!(bten::managed_vault_ops_wallet(&vault) == ops, 310);
            assert!(bten::managed_vault_fee_bps(&vault) == 200, 311);
            assert!(!bten::managed_vault_is_paused(&vault), 312);
            bten::set_managed_vault_paused(&mut vault, &admin_cap, true);
            assert!(bten::managed_vault_is_paused(&vault), 313);
            test_scenario::return_shared(vault);
            scenario.return_to_sender(admin_cap);
        };
        scenario.next_tx(admin);
        {
            let cap = scenario.take_from_sender<bten::ManagedVaultOperatorCap>();
            scenario.return_to_sender(cap);
        };
        scenario.end();
    }


    /// Reproduces the live Block10 overflow: points * reward_total exceeds u64
    /// before dividing by total_points. u128 intermediate must succeed.
    #[test]
    fun auto_pay_trader_u128_avoids_u64_overflow() {
        let admin = @0xA;
        let mut scenario = test_scenario::begin(admin);
        bten::initialize_for_testing(scenario.ctx());
        scenario.create_system_objects();
        scenario.next_tx(admin);
        {
            let mut state = scenario.take_shared<bten::EmissionState>();
            let mut clock = scenario.take_shared<Clock>();
            clock::set_for_testing(&mut clock, 1_000);
            // 50e9 * 500e6 = 2.5e19 > u64::MAX (~1.84e19) — overflows in u64 math
            bten::record_qualified_route_for_testing(&mut state, 50_000_000_000, &clock, scenario.ctx());
            clock::set_for_testing(&mut clock, 601_000);
            bten::settle(&mut state, &clock, scenario.ctx());
            assert!(bten::block_height(&state) == 1, 0);
            assert!(bten::trader_balance(&state) == 500_000_000, 1);
            bten::auto_pay_trader(&mut state, 0, admin, scenario.ctx());
            assert!(bten::trader_balance(&state) == 0, 2);
            test_scenario::return_shared(state);
            test_scenario::return_shared(clock);
        };
        scenario.next_tx(admin);
        {
            let reward = scenario.take_from_sender<coin::Coin<bten::BTEN>>();
            assert!(coin::value(&reward) == 500_000_000, 3);
            scenario.return_to_sender(reward);
        };
        scenario.end();
    }
}
