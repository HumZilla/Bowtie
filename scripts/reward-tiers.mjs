// Pure reward-tier calculation; server-side enforcement is still required.
export function rewardTier(ageDays, gold = false) {
  if (gold === true) return {tier: 'gold', points: 500};
  if (!Number.isInteger(ageDays) || ageDays < 0) return null;
  if (ageDays <= 44) return {tier: 'white', points: 100};
  if (ageDays <= 74) return {tier: 'black', points: 250};
  return {tier: 'purple', points: 375};
}
