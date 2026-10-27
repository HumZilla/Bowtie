// The reward is locked at referral submission. Server-side enforcement is required.
export function rewardTier(ageDays, gold = false) {
  if (gold === true) return {tier: 'gold', points: 500};
  if (ageDays == null) return {tier: 'white', points: 100};
  if (!Number.isInteger(ageDays) || ageDays < 0) throw new RangeError('Invalid inventory age');
  if (ageDays <= 44) return {tier: 'white', points: 100};
  if (ageDays <= 74) return {tier: 'black', points: 250};
  return {tier: 'purple', points: 375};
}
