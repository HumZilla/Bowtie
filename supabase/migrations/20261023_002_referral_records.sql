-- Bowtie Phase 2: private referral tracking foundation
-- No client write grants: only a future validated backend may record buyer referrals.
create table if not exists public.referral_records (
 id uuid primary key default gen_random_uuid(),
 member_id uuid not null references public.member_profiles(user_id) on delete restrict,
 vehicle_vin text,
 vehicle_stock text,
 dealership_name text,
 status text not null default 'received' check (status in ('received','reviewing','contacted','appointment','delivered','closed')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists referral_records_member_idx on public.referral_records(member_id,created_at desc);
alter table public.referral_records enable row level security;
revoke all on public.referral_records from anon,authenticated;
grant select on public.referral_records to authenticated;
drop policy if exists "members view own referrals" on public.referral_records;
create policy "members view own referrals" on public.referral_records
for select to authenticated using (member_id=(select auth.uid()));
-- Do not store buyer names, phone numbers, emails or other PII in member-visible records.
-- Referral creation and attribution will require consent, rate limiting, duplicate checks, and a trusted backend.
-- No points, check register, or monetary awards are enabled.
