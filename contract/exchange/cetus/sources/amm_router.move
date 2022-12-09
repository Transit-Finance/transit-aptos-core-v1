module cetus_amm::amm_router {
    use aptos_framework::coin::Coin;
    use aptos_framework::coin;

    public fun swap<CoinTypeA, CoinTypeB>(_account: address, coin_in: Coin<CoinTypeA>):Coin<CoinTypeB>{
        coin::destroy_zero(coin_in);
        coin::zero<CoinTypeB>()
    }
}