module Aptoswap::pool {
    use aptos_framework::coin;

    public fun swap_x_to_y_direct<X, Y>(in_coin: coin::Coin<X>): coin::Coin<Y> {
        coin::destroy_zero(in_coin);
        coin::zero<Y>()
    }

    public fun swap_y_to_x_direct<X, Y>(in_coin: coin::Coin<Y>): coin::Coin<X> {
        coin::destroy_zero(in_coin);
        coin::zero<X>()
    }
}