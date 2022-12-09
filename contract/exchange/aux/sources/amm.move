module aux::amm{
    use aptos_framework::coin;
    public fun swap_exact_coin_for_coin_mut<CoinIn, CoinOut>(
        _sender_addr: address,
        _user_in: &mut coin::Coin<CoinIn>,
        _user_out: &mut coin::Coin<CoinOut>,
        _au_in: u64,
        // may always be zero
        _min_au_out: u64,
        // false
        _use_limit_price: bool,
        // zero
        _max_out_per_in_au_numerator: u128,
        // zero
        _max_out_per_in_au_denominator: u128,
    ): (u64, u64){
        (0,0)
    }
}