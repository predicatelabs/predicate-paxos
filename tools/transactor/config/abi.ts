export const ROUTER_ABI = [
    "function swap(tuple(address currency0, address currency1, uint24 fee, " +
    "int24 tickSpacing, address hooks) key, tuple(bool zeroForOne, " +
    "int256 amountSpecified, uint160 sqrtPriceLimitX96) params, " +
    "bytes calldata data) external returns (tuple(int128 amount0, int128 amount1))"
];