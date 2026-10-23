-- Bowtie Network: Phase 2 secure account foundation
-- Review before running in Supabase SQL Editor.
create table if not exists public.member_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  member_code text not null unique default ('BT-' || upper(encode(gen_random_bytes(8),'hex'))),
  created_at timestamptz not null default now()
);
alter table public.member_profiles enable row level security;
revoke all on public.member_profiles from anon;
revoke all on public.member_profiles from authenticated;
grant select on public.member_profiles to authenticated;
create policy "members read own profile" on public.member_profiles
  for select to authenticated using ((select auth.uid()) = user_id);
-- No client-side INSERT/UPDATE/DELETE grants or policies.
-- Profiles are created by the auth trigger only.
create or replace function public.create_bowtie_member()
returns trigger language plpgsql security definer
set search_path = '' as $$
begin
  insert into public.member_profiles(user_id, display_name)
  values(new.id, left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'),''),'Member'),80))
  on conflict (user_id) do nothing;
  return new;
end;
$$;
revoke all on function public.create_bowtie_member() from public, anon, authenticated;
drop trigger if exists bowtie_new_member on auth.users;
create trigger bowtie_new_member after insert on auth.users
for each row execute function public.create_bowtie_member();
-- Rewards/checks intentionally absent: no monetary functionality is enabled.
-- Referral submission requires a separate verified buyer-consent workflow.
