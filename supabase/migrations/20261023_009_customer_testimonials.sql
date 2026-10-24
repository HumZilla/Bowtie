-- Customer-authored Sold by Bowtie stories: private until administrator approval.
create table if not exists public.bowtie_testimonials (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references auth.users(id),
 display_name text not null check (char_length(display_name) between 2 and 60),
 vehicle text not null check (char_length(vehicle) between 3 and 120),
 story text not null check (char_length(story) between 20 and 1500),
 consent boolean not null check (consent = true),
 submitted_at timestamptz not null default now(),
 approved_at timestamptz,
 approved_by uuid references auth.users(id),
 rejected_at timestamptz,
 constraint testimonial_moderation_exclusive check (approved_at is null or rejected_at is null)
);
alter table public.bowtie_testimonials enable row level security;
revoke all on public.bowtie_testimonials from public,anon,authenticated;
grant select,insert,update on public.bowtie_testimonials to authenticated;
grant select on public.bowtie_testimonials to anon;
drop policy if exists "authors can submit own testimonials" on public.bowtie_testimonials;
create policy "authors can submit own testimonials" on public.bowtie_testimonials for insert to authenticated
with check (author_id=(select auth.uid()) and approved_at is null and approved_by is null and rejected_at is null and consent=true);
drop policy if exists "approved stories visible publicly" on public.bowtie_testimonials;
create policy "approved stories visible publicly" on public.bowtie_testimonials for select to anon,authenticated
using (approved_at is not null and rejected_at is null);
drop policy if exists "admins can review all testimonials" on public.bowtie_testimonials;
create policy "admins can review all testimonials" on public.bowtie_testimonials for select to authenticated
using ((select public.is_bowtie_admin()));
drop policy if exists "admins can moderate testimonials" on public.bowtie_testimonials;
create policy "admins can moderate testimonials" on public.bowtie_testimonials for update to authenticated
using ((select public.is_bowtie_admin()))
with check ((select public.is_bowtie_admin()));
-- Restrict columns authors may set; admins moderate via security-definer RPC instead of unrestricted UPDATE.
revoke update on public.bowtie_testimonials from authenticated;
create or replace function public.moderate_bowtie_testimonial(p_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 update public.bowtie_testimonials
 set approved_at=case when p_approve then now() else null end,
     approved_by=case when p_approve then auth.uid() else null end,
     rejected_at=case when p_approve then null else now() end
 where id=p_id;
 if not found then raise exception 'Submission not found'; end if;
end; $$;
revoke all on function public.moderate_bowtie_testimonial(uuid,boolean) from public,anon;
grant execute on function public.moderate_bowtie_testimonial(uuid,boolean) to authenticated;
