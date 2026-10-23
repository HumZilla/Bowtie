-- Bowtie Network Phase 2: server-enforced admin review access
-- Run AFTER 001 member profiles, 002 referrals, and 003 admin roles.
-- Authorized admins may review/update referral status; ordinary members remain read-only.
create or replace function public.is_bowtie_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.admin_members a
    where a.user_id = (select auth.uid())
  );
$$;
revoke all on function public.is_bowtie_admin() from public, anon;
grant execute on function public.is_bowtie_admin() to authenticated;

drop policy if exists "admins review referral records" on public.referral_records;
create policy "admins review referral records" on public.referral_records
for select to authenticated using ((select public.is_bowtie_admin()));

drop policy if exists "admins update referral status" on public.referral_records;
create policy "admins update referral status" on public.referral_records
for update to authenticated using ((select public.is_bowtie_admin()))
with check ((select public.is_bowtie_admin()));

-- Column-specific update permissions prevent edits to ownership or vehicle attribution.
revoke update on public.referral_records from authenticated;
grant update (status, updated_at) on public.referral_records to authenticated;
-- The status column is limited to predefined values by the existing check constraint.
-- No INSERT or DELETE permissions are granted to browser clients.
-- Admin access to member profiles and buyer contact details is NOT granted here.
