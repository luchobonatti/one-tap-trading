export function calculatePnL(
  entryPrice: bigint,
  currentPrice: bigint,
  collateral: bigint,
  leverage: bigint,
  isLong: boolean,
): bigint {
  if (collateral === 0n || entryPrice === 0n) return 0n;
  const notional = collateral * leverage;
  const delta = currentPrice - entryPrice;
  const raw = (notional * delta) / entryPrice;
  return isLong ? raw : -raw;
}
