# Bowtie Network 💜🎀

Rob Polanco's personal automotive showroom and referral network.

## Inventory
- New: Hicks Family Subaru new Subaru vehicles only.
- Pre-owned: participating Hicks / Ed Hicks Coastal Bend dealerships.
- Gold Bowtie: featured vehicles marked across all inventory views.

## Status
Development foundation. Customer accounts, referrals, reward issuance and check processing are **not live**.

## Supabase
Project URL: `https://uwwzrfijxbvxqvivbudh.supabase.co`.
Use only a publishable key in frontend code. Never commit passwords, service-role or secret keys.

## Next steps
1. Upload the purple/black/gold website `index.html` to the repository root.
2. Enable GitHub Pages from `main` / root.
3. Review/apply SQL schema in Supabase SQL Editor with Row Level Security and least-privilege grants.
4. Connect Supabase Auth, secure referral submission, admin authorization, and approved inventory feed.
5. Launch public lead collection only after privacy and security testing.

## Rewards
Proposed 1 point = $1; issuance, gift cards, and checks disabled pending dealership/legal approval.

## Inventory integration plan (October 2026)
- Inventory systems: vAuto / ACV MAX; dealership sites: Team Velocity.
- Request an **authorized**, scheduled inventory export/API from the inventory provider or website provider; no website scraping as the primary source.
- Scope: new Subaru from Hicks Family Subaru only; used vehicles from participating Hicks/Ed Hicks stores only.
- Minimum fields: VIN, stock, store ID, new/used, year, make, model, trim, price, mileage, availability, photos, vehicle URL, last-updated timestamp.
- Ingestion must run on a trusted backend with feed credentials stored as secrets; never put feed credentials in GitHub Pages or browser JS.
- Validate VIN/stock uniqueness, dealer allowlist, stale/missing records, photo permissions, and price/availability timestamps. Automatically suppress sold/removed vehicles after feed reconciliation.
- Gold Bowtie curation belongs in a separate admin-controlled table keyed by VIN/store and must survive inventory refreshes.
- All vehicle-specific referral links should carry a stable vehicle ID/stock and member code; server must validate both at submission.
- Do not display demonstration inventory as real listings; only publish after feed validation and dealership authorization.
