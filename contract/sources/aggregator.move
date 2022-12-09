module transit_aggregator::aggregator {
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_std::event;
    use aptos_std::event::EventHandle;
    use aptos_std::type_info::{TypeInfo, type_of};
    use std::signer;
    use std::vector;
    use std::option;
    use std::option::{Option};

    const APTOSWAP_DEX: u64 = 1;
    const LIQUIDSWAP_DEX: u64 = 2;
    const ANIMESWAP_DEX: u64 = 3;
    const PANCAKE_DEX: u64 = 4;
    const AUX_DEX: u64 = 5;
    const CETUS_DEX: u64 = 6;

    const ERR_UNKNOWN_DEX: u64 = 148001;
    const ERR_OUTPUT_LESS_THAN_MINIMUM: u64 = 148002;
    const ERR_NOT_ADMIN: u64 = 148003;
    const ERR_INVALID_PARAMETER: u64 = 148004;
    const ERR_NOT_ENOUGH_BALANCE: u64 = 148005;
    const ERR_UNSUPPORTED_NUM_STEPS: u64 = 148006;
    const ERR_BATCH_SWAP_NUM: u64 = 148007;
    const ERR_UNKNOWN_POOL_TYPE: u64 = 148008;
    const ERR_UNSUPPORTED: u64 = 148009;

    const AGG_FEE_BASE:u128 = 10000;
    const AGG_FEE:u128 = 30;
    const AUX_TYPE_AMM:u64 = 0;
    const AUX_TYPE_MARKET:u64 = 1;

    struct EventStore has key {
        swap_events: EventHandle<SwapEvent>,
    }

    struct SwapEvent has drop, store {
        trader: address,
        channel: u64,
        x_type_info: TypeInfo,
        y_type_info: TypeInfo,
        input_amount: u64,
        output_amount: u64,
    }

    fun emit_swap_event<X, Y>(
        trader:address,
        channel:u64,
        input_amount:u64,
        output_amount: u64
    ) acquires EventStore {
        let event_store = borrow_global_mut<EventStore>(@transit_aggregator);
        event::emit_event<SwapEvent>(
            &mut event_store.swap_events,
            SwapEvent {
                trader,
                channel,
                x_type_info: type_of<coin::Coin<X>>(),
                y_type_info: type_of<coin::Coin<Y>>(),
                input_amount,
                output_amount,
            },
        );
    }

    public entry fun init_module_event(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @transit_aggregator, ERR_NOT_ADMIN);
        move_to(admin, EventStore {
            swap_events: account::new_event_handle<SwapEvent>(admin)
        });
    }

    fun liquid_swap<X, Y, E>(x_in: coin::Coin<X>): coin::Coin<Y> {
        use liquidswap::router_v2;
        let y_out =router_v2::swap_exact_coin_for_coin<X, Y, E>(x_in, 0);
        y_out
    }

    fun apto_swap<X, Y>(is_x_to_y: bool, x_in: coin::Coin<X>): coin::Coin<Y> {
        use Aptoswap::pool;
        if (is_x_to_y) {
            let y_out = pool::swap_x_to_y_direct<X, Y>(x_in);
            y_out
        }
        else {
            let y_out = pool::swap_y_to_x_direct<Y, X>(x_in);
            y_out
        }
    }

    fun pancake_swap<X, Y>(x_in: coin::Coin<X>): coin::Coin<Y> {
        use pancake::router;
        let y_out = router::swap_exact_x_to_y_direct_external<X, Y>(x_in);
        y_out
    }

    fun anime_swap<X, Y>(x_in: coin::Coin<X>): coin::Coin<Y> {
        use SwapDeployer::AnimeSwapPoolV1;
        let y_out =AnimeSwapPoolV1::swap_coins_for_coins<X, Y>(x_in);
        y_out
    }

    fun aux_swap<X, Y>(pool_type: u64, is_x_to_y: bool, x_in: coin::Coin<X>): (Option<coin::Coin<X>>, coin::Coin<Y>) {
        let amount_in_value = coin::value(&x_in);
        if (pool_type == AUX_TYPE_AMM){
            use aux::amm;
            let y_out = coin::zero<Y>();
            amm::swap_exact_coin_for_coin_mut(
                @transit_aggregator,
                &mut x_in,
                &mut y_out,
                amount_in_value,
                0,
                false,
                0,
                0
            );

            (option::some(x_in),y_out)
        } else if (pool_type == AUX_TYPE_MARKET){
            use aux::clob_market;
            let y_out = coin::zero<Y>();
            if (is_x_to_y){
                clob_market::place_market_order_mut<X, Y>(
                    @transit_aggregator,
                    &mut x_in,
                    &mut y_out,
                    false,
                    102,// IMMEDIATE_OR_CANCEL in aux::router,
                    0,
                    amount_in_value,
                    0
                );
            } else {
                abort ERR_UNSUPPORTED
            };
            (option::some(x_in),y_out)
        } else {
            abort ERR_UNKNOWN_POOL_TYPE
        }
    }

    fun cetus_swap<X, Y>(x_in: coin::Coin<X>): coin::Coin<Y> {
        use cetus_amm::amm_router;
        let y_out = amm_router::swap<X, Y>(@transit_aggregator, x_in);
        y_out
    }

    fun get_intermediate_out_from_dexs<X, Y, E>(
        sender: &signer,
        dex_type: u64,
        pool_type: u64,
        is_x_to_y: bool,
        x_in: coin::Coin<X>
    ): coin::Coin<Y> {
        let (x_out_opt, y_out) = if (dex_type == LIQUIDSWAP_DEX) {
            let y_out = liquid_swap<X, Y, E>(x_in);
            (option::none(), y_out)
        } else if (dex_type == APTOSWAP_DEX) {
            let y_out = apto_swap<X, Y>(is_x_to_y, x_in);
            (option::none(), y_out)
        } else if (dex_type == PANCAKE_DEX){
            let y_out = pancake_swap<X, Y>(x_in);
            (option::none(), y_out)
        } else if (dex_type == ANIMESWAP_DEX) {
            let y_out = anime_swap<X, Y>(x_in);
            (option::none(), y_out)
        } else if (dex_type == AUX_DEX) {
            aux_swap<X, Y>(pool_type, is_x_to_y, x_in)
        }  else if (dex_type == CETUS_DEX) {
            let y_out = cetus_swap<X, Y>(x_in);
            (option::none(),y_out)
        } else {
            abort ERR_UNKNOWN_DEX
        };
        check_and_deposit_opt(sender, x_out_opt);
        y_out
    }

    fun swap<
        X, Y, Z, OutCoin, E1, E2, E3
    >(
        sender: &signer,
        num_steps: u64,
        first_dex_type: u64,
        first_pool_type: u64,
        first_is_x_to_y: bool,
        second_dex_type: u64,
        second_pool_type: u64,
        second_is_x_to_y: bool,
        third_dex_type: u64,
        third_pool_type: u64,
        third_is_x_to_y: bool,
        x_in: coin::Coin<X>
    ): coin::Coin<OutCoin> {
        let coin_m = if (num_steps == 1) {
            let coin_m = get_intermediate_out_from_dexs<X, OutCoin, E1>(sender,first_dex_type, first_pool_type, first_is_x_to_y, x_in);
            coin_m
        }
        else if (num_steps == 2) {
            let coin_y = get_intermediate_out_from_dexs<X, Y, E1>(sender, first_dex_type, first_pool_type, first_is_x_to_y, x_in);
            let coin_m = get_intermediate_out_from_dexs<Y, OutCoin, E2>(sender, second_dex_type, second_pool_type, second_is_x_to_y, coin_y);
            coin_m
        }
        else if (num_steps == 3) {
            let coin_y = get_intermediate_out_from_dexs<X, Y, E1>(sender,first_dex_type, first_pool_type, first_is_x_to_y, x_in);
            let coin_z = get_intermediate_out_from_dexs<Y, Z, E2>(sender,second_dex_type, second_pool_type, second_is_x_to_y, coin_y);
            let coin_m = get_intermediate_out_from_dexs<Z, OutCoin, E3>(sender,third_dex_type, third_pool_type, third_is_x_to_y, coin_z);
            coin_m
        }else {
            abort ERR_UNSUPPORTED_NUM_STEPS
        };

        coin_m
    }

    public entry fun swap_one<
        X, Y, Z, OutCoin, E1, E2, E3
    >(
        sender: &signer,
        channel: u64,
        num_steps: u64,
        first_dex_type: u64,
        first_pool_type: u64,
        first_is_x_to_y: bool,
        second_dex_type: u64,
        second_pool_type: u64,
        second_is_x_to_y: bool,
        third_dex_type: u64,
        third_pool_type: u64,
        third_is_x_to_y: bool,
        x_in: u64,
        m_min_out: u64,
    ) acquires EventStore {
        let coin_x = coin::withdraw<X>(sender, x_in);

        let x_fee_direct = is_x_direct_fee<X>();
        if (x_fee_direct) {
            collect_fee<X>(&mut coin_x);
        };

        let coin_m = swap<X, Y, Z, OutCoin, E1, E2, E3>(
            sender,
            num_steps,
            first_dex_type,
            first_pool_type,
            first_is_x_to_y,
            second_dex_type,
            second_pool_type,
            second_is_x_to_y,
            third_dex_type,
            third_pool_type,
            third_is_x_to_y,
            coin_x
        );

        if (!x_fee_direct) {
            collect_fee<OutCoin>(&mut coin_m);
        };

        assert!(coin::value(&coin_m) >= m_min_out, ERR_OUTPUT_LESS_THAN_MINIMUM);
        emit_swap_event<X, OutCoin>(
            signer::address_of(sender),
            channel,
            x_in,
            coin::value(&coin_m)
        );
        deposit_out<OutCoin>(sender, coin_m);
    }

    public entry fun batch_swap_three<
        X, OutCoin,
        Y0, Z0, E01, E02, E03,
        Y1, Z1, E11, E12, E13,
        Y2, Z2, E21, E22, E23,
    >(
        sender: &signer,
        channel: u64,
        batch_num: u64,
        num_steps_vec: vector<u64>,
        first_dex_type_vec: vector<u64>,
        first_pool_type_vec: vector<u64>,
        first_is_x_to_y_vec: vector<bool>,
        second_dex_type_vec: vector<u64>,
        second_pool_type_vec: vector<u64>,
        second_is_x_to_y_vec: vector<bool>,
        third_dex_type_vec: vector<u64>,
        third_pool_type_vec: vector<u64>,
        third_is_x_to_y_vec: vector<bool>,
        x_in_vec: vector<u64>,
        m_min_out: u64,
    ) acquires EventStore {
        assert!(batch_num <= 3, ERR_BATCH_SWAP_NUM);
        let out: coin::Coin<OutCoin> = coin::zero<OutCoin>();
        let x_fee: coin::Coin<X> = coin::zero<X>();
        let x_fee_direct = is_x_direct_fee<X>();
        let amount_all_in: u64 = 0;
        let i: u64 = 0;
        while(i < batch_num) {
            let num_steps =  *vector::borrow(&num_steps_vec, i);
            let first_dex_type =  *vector::borrow(&first_dex_type_vec, i);
            let first_pool_type =  *vector::borrow(&first_pool_type_vec, i);
            let first_is_x_to_y =  *vector::borrow(&first_is_x_to_y_vec, i);
            let second_dex_type =  *vector::borrow(&second_dex_type_vec, i);
            let second_pool_type =  *vector::borrow(&second_pool_type_vec, i);
            let second_is_x_to_y =  *vector::borrow(&second_is_x_to_y_vec, i);
            let third_dex_type =  *vector::borrow(&third_dex_type_vec, i);
            let third_pool_type =  *vector::borrow(&third_pool_type_vec, i);
            let third_is_x_to_y =  *vector::borrow(&third_is_x_to_y_vec, i);
            let x_in =  *vector::borrow(&x_in_vec, i);
            let coin_x = coin::withdraw<X>(sender, x_in);

            if (x_fee_direct) {
                let fee = get_fee_amount(&mut coin_x);
                coin::merge(&mut x_fee, fee);
            };

            let coin_m = if (i == 0) {
                swap<X, Y0, Z0, OutCoin, E01, E02, E03>(sender, num_steps, first_dex_type, first_pool_type, first_is_x_to_y,
                    second_dex_type, second_pool_type, second_is_x_to_y, third_dex_type, third_pool_type, third_is_x_to_y, coin_x)
            } else if (i == 1) {
                swap<X, Y1, Z1, OutCoin, E11, E12, E13>(sender, num_steps, first_dex_type, first_pool_type, first_is_x_to_y,
                    second_dex_type, second_pool_type, second_is_x_to_y, third_dex_type, third_pool_type, third_is_x_to_y, coin_x)
            } else if (i == 2) {
                swap<X, Y2, Z2, OutCoin, E21, E22, E23>(sender, num_steps, first_dex_type, first_pool_type, first_is_x_to_y,
                    second_dex_type, second_pool_type, second_is_x_to_y, third_dex_type, third_pool_type, third_is_x_to_y, coin_x)
            } else {
                abort ERR_BATCH_SWAP_NUM
            };
            coin::merge(&mut out, coin_m);
            i = i + 1;
            amount_all_in = amount_all_in + x_in;
        };

        handle_batch_swap_result(sender, channel, amount_all_in, m_min_out, x_fee_direct, x_fee, out);
    }

    public entry fun batch_swap_five<
        X, OutCoin,
        Y0, Z0, E01, E02, E03,
        Y1, Z1, E11, E12, E13,
        Y2, Z2, E21, E22, E23,
        Y3, Z3, E31, E32, E33,
        Y4, Z4, E41, E42, E43,
    >(
        sender: &signer,
        channel: u64,
        batch_num: u64,
        num_steps_vec: vector<u64>,
        first_dex_type_vec: vector<u64>,
        first_pool_type_vec: vector<u64>,
        first_is_x_to_y_vec: vector<bool>,
        second_dex_type_vec: vector<u64>,
        second_pool_type_vec: vector<u64>,
        second_is_x_to_y_vec: vector<bool>,
        third_dex_type_vec: vector<u64>,
        third_pool_type_vec: vector<u64>,
        third_is_x_to_y_vec: vector<bool>,
        x_in_vec: vector<u64>,
        m_min_out: u64,
    ) acquires EventStore {
        assert!(batch_num <= 5, ERR_BATCH_SWAP_NUM);
        let out: coin::Coin<OutCoin> = coin::zero<OutCoin>();
        let x_fee: coin::Coin<X> = coin::zero<X>();
        let x_fee_direct = is_x_direct_fee<X>();
        let i: u64 = 0;
        let amount_all_in: u64 = 0;
        while(i < batch_num) {
            let num_steps =  *vector::borrow(&num_steps_vec, i);
            let first_dex_type =  *vector::borrow(&first_dex_type_vec, i);
            let first_pool_type =  *vector::borrow(&first_pool_type_vec, i);
            let first_is_x_to_y =  *vector::borrow(&first_is_x_to_y_vec, i);
            let second_dex_type =  *vector::borrow(&second_dex_type_vec, i);
            let second_pool_type =  *vector::borrow(&second_pool_type_vec, i);
            let second_is_x_to_y =  *vector::borrow(&second_is_x_to_y_vec, i);
            let third_dex_type =  *vector::borrow(&third_dex_type_vec, i);
            let third_pool_type =  *vector::borrow(&third_pool_type_vec, i);
            let third_is_x_to_y =  *vector::borrow(&third_is_x_to_y_vec, i);
            let x_in =  *vector::borrow(&x_in_vec, i);
            let coin_x = coin::withdraw<X>(sender, x_in);

            if (x_fee_direct) {
                let fee = get_fee_amount(&mut coin_x);
                coin::merge(&mut x_fee, fee);
            };

            let coin_m = if (i == 0) {
                swap<X, Y0, Z0, OutCoin, E01, E02, E03>(sender, num_steps, first_dex_type, first_pool_type, first_is_x_to_y,
                    second_dex_type, second_pool_type, second_is_x_to_y, third_dex_type, third_pool_type, third_is_x_to_y, coin_x)
            } else if (i == 1) {
                swap<X, Y1, Z1, OutCoin, E11, E12, E13>(sender, num_steps, first_dex_type, first_pool_type, first_is_x_to_y,
                    second_dex_type, second_pool_type, second_is_x_to_y, third_dex_type, third_pool_type, third_is_x_to_y, coin_x)
            } else if (i == 2) {
                swap<X, Y2, Z2, OutCoin, E21, E22, E23>(sender, num_steps, first_dex_type, first_pool_type, first_is_x_to_y,
                    second_dex_type, second_pool_type, second_is_x_to_y, third_dex_type, third_pool_type, third_is_x_to_y, coin_x)
            } else if (i == 3) {
                swap<X, Y3, Z3, OutCoin, E31, E32, E33>(sender, num_steps, first_dex_type, first_pool_type, first_is_x_to_y,
                    second_dex_type, second_pool_type, second_is_x_to_y, third_dex_type, third_pool_type, third_is_x_to_y, coin_x)
            } else if (i == 4) {
                swap<X, Y4, Z4, OutCoin, E41, E42, E43>(sender, num_steps, first_dex_type, first_pool_type, first_is_x_to_y,
                    second_dex_type, second_pool_type, second_is_x_to_y, third_dex_type, third_pool_type, third_is_x_to_y, coin_x)
            }  else {
                abort ERR_BATCH_SWAP_NUM
            };
            coin::merge(&mut out, coin_m);
            i = i + 1;
            amount_all_in = amount_all_in + x_in;
        };

        handle_batch_swap_result(sender, channel, amount_all_in, m_min_out, x_fee_direct, x_fee, out);
    }

    fun handle_batch_swap_result<X, OutCoin>(sender:  &signer, channel: u64, amount_all_in: u64,  m_min_out: u64, x_fee_direct: bool, x_fee: coin::Coin<X>, out: coin::Coin<OutCoin>) acquires EventStore {
        if(x_fee_direct) {
            deposit_fee<X>(x_fee)
        } else {
            collect_fee<OutCoin>(&mut out);
            coin::destroy_zero(x_fee);
        };

        assert!(coin::value(&out) >= m_min_out, ERR_OUTPUT_LESS_THAN_MINIMUM);
        emit_swap_event<X, OutCoin>(
            signer::address_of(sender),
            channel,
            amount_all_in,
            coin::value(&out)
        );
        deposit_out<OutCoin>(sender, out);
    }

    fun is_x_direct_fee<X>(): bool {
        let x_fee_direct = true;
        if (!coin::is_account_registered<X>(@agg_fee_address)) {
            x_fee_direct = false;
        };
        x_fee_direct
    }

    fun collect_fee<X>(amount_in: &mut  coin::Coin<X>) {
        if (coin::is_account_registered<X>(@agg_fee_address)) {
            let fee = get_fee_amount(amount_in);
            coin::deposit( @agg_fee_address, fee);
        }
    }

    fun deposit_fee<X>(fee: coin::Coin<X>) {
        coin::deposit( @agg_fee_address, fee);
    }

    fun get_fee_amount<X>(amount_in: &mut  coin::Coin<X>): coin::Coin<X> {
        let amount = (coin::value(amount_in) as u128);
        let fee_amount = (((amount * AGG_FEE) / AGG_FEE_BASE) as u64);
        let fee = coin::extract(amount_in, fee_amount);
        fee
    }

    fun deposit_out<X>(sender: &signer, coin: coin::Coin<X>) {
        let sender_addr = signer::address_of(sender);
        if (!coin::is_account_registered<X>(sender_addr)) {
            coin::register<X>(sender);
        };
        coin::deposit(sender_addr, coin);
    }

    fun check_and_deposit_opt<X>(sender: &signer, coin_opt: Option<coin::Coin<X>>) {
        if (option::is_some(&coin_opt)) {
            let coin = option::extract(&mut coin_opt);
            let sender_addr = signer::address_of(sender);
            if (!coin::is_account_registered<X>(sender_addr)) {
                coin::register<X>(sender);
            };
            coin::deposit(sender_addr, coin);
        };
        option::destroy_none(coin_opt)
    }
}
