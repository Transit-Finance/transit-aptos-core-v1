module aux::clob_market {
    use aptos_framework::coin;

    /// Place a market order (IOC or FOK) on behalf of the router.
    /// Returns (total_base_quantity_owed_au, quote_quantity_owed_au), the amounts that must be credited/debited to the sender.
    /// Emits events on order placement and fills.
    public fun place_market_order_mut<B, Q>(
        _sender_addr: address,
        _base_coin: &mut coin::Coin<B>,
        _quote_coin: &mut coin::Coin<Q>,
        _is_bid: bool,
        _order_type: u64,
        _limit_price: u64,
        _quantity: u64,
        _client_order_id: u128,
    ): (u64, u64) {
        (0, 0)
    }
}
