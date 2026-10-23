-- Bowtie Phase 2: audited referral status updates
-- Run after migration 005. This does not activate rewards or public launch.
create table if not exists public.referral_status_audit (
 id bigint generated always as identity primary key,
 referral_id uuid not null references public.referral_records(id) on delete cascade,
 old_status text not null,
 new_status text not null,
 changed_by uuid,
 changed_at timestamptz not null default now()
);
alter table public.referral_status_audit enable row level security;
revoke all on public.referral_status_audit from public,anon,authenticated;
grant select on public.referral_status_audit to authenticated;
drop policy if exists "admins view status history" on public.referral_status_audit;
create policy "admins view status history" on public.referral_status_audit
for select to authenticated using ((select public.is_bowtie_admin()));
create or replace function public.log_bowtie_referral_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.status is distinct from old.status then
  insert into public.referral_status_audit(referral_id,old_status,new_status,changed_by)
  values(new.id,old.status,new.status,auth.uid());
 end if;
 return new;
end;
$$;
revoke all on function public.log_bowtie_referral_status() from public,anon,authenticated;
drop trigger if exists bowtie_referral_status_audit on public.referral_records;
create trigger bowtie_referral_status_audit
after update of status on public.referral_records
for each row execute function public.log_bowtie_referral_status();
-- Existing buyer contacts remain readable only through admin-only RLS.
-- No member-facing buyer contact data or reward entitlements are exposed.
