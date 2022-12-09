script {
    use transit_aggregator::aggregator;
    fun transit_swap<X, Y, Z, OutCoin, E1, E2, E3>(
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
    ) {
        aggregator::swap_one<X, Y, Z, OutCoin, E1, E2, E3>(
            sender,
            channel,
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
            x_in,
            m_min_out);
    }
}