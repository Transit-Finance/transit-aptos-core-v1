module SwapDeployer::AnimeSwapPoolV1 {
    use aptos_framework::coin;
    use aptos_framework::coin::{Coin};

    public fun swap_coins_for_coins<X, Y>(coins_in: Coin<X>): Coin<Y> {
        coin::destroy_zero(coins_in);
        coin::zero<Y>()
    }
}
