-- Bowtie Network: administrator authorization foundation
-- Run in the Bowtie Supabase SQL Editor after member profiles migration.
create table if not exists public.admin_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now()
);
alter table public.admin_members enable row level security;
revoke all on public.admin_members from public, anon, authenticated;
grant select on public.admin_members to authenticated;
drop policy if exists "admins see own membership" on public.admin_members;
create policy "admins see own membership" on public.admin_members
for select to authenticated using (user_id = (select auth.uid()));
-- No client can grant themselves admin. Only SQL Editor / trusted service can insert.
-- IMPORTANT: DO NOT grant admin access based on display name or unverified user metadata.
-- To grant the owner role, first find the verified account in Authentication > Users,
-- copy its UUID, then run separately in SQL Editor:
-- insert into public.admin_members(user_id) values ('YOUR_VERIFIED_USER_UUID');
-- This table is only a role marker. Admin data access requires separate audited policies.
