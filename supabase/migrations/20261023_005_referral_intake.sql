-- Bowtie Phase 2: authenticated, consent-based referral intake
-- Buyer must sign in with a verified email. Never put buyer PII in member-visible records.
create table if not exists public.referral_buyers (
 referral_id uuid primary key references public.referral_records(id) on delete cascade,
 buyer_user_id uuid not null references auth.users(id),
 buyer_email text not null,
 buyer_name text not null,
 consent_at timestamptz not null default now()
);
create unique index if not exists referral_buyer_dedupe on public.referral_buyers(buyer_user_id,referral_id);
alter table public.referral_buyers enable row level security;
revoke all on public.referral_buyers from public,anon,authenticated;
grant select on public.referral_buyers to authenticated;
drop policy if exists "admin reads buyer contacts" on public.referral_buyers;
create policy "admin reads buyer contacts" on public.referral_buyers for select to authenticated
using ((select public.is_bowtie_admin()));

create or replace function public.submit_bowtie_inquiry(
 p_member_code text, p_vehicle_stock text, p_buyer_name text, p_consent boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
 v_buyer uuid := auth.uid();
 v_member uuid;
 v_email text;
 v_id uuid;
begin
 if v_buyer is null then raise exception 'Please sign in first'; end if;
 select email into v_email from auth.users where id=v_buyer and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verify your email before submitting'; end if;
 if p_consent is distinct from true then raise exception 'Consent is required'; end if;
 if length(trim(coalesce(p_buyer_name,''))) not between 2 and 80 then raise exception 'Enter your name'; end if;
 if length(trim(coalesce(p_vehicle_stock,''))) not between 1 and 60 then raise exception 'Enter a vehicle stock number'; end if;
 select user_id into v_member from public.member_profiles where member_code=trim(p_member_code);
 if v_member is null then raise exception 'Unknown referral code'; end if;
 if v_member=v_buyer then raise exception 'You cannot submit your own referral'; end if;
 if exists (select 1 from public.referral_buyers b
   join public.referral_records r on r.id=b.referral_id
   where b.buyer_user_id=v_buyer and r.member_id=v_member and r.vehicle_stock=trim(p_vehicle_stock))
 then raise exception 'This inquiry has already been submitted'; end if;
 insert into public.referral_records(member_id,vehicle_stock,status)
 values(v_member,trim(p_vehicle_stock),'received') returning id into v_id;
 insert into public.referral_buyers(referral_id,buyer_user_id,buyer_email,buyer_name)
 values(v_id,v_buyer,v_email,trim(p_buyer_name));
 return v_id;
end;
$$;
revoke all on function public.submit_bowtie_inquiry(text,text,text,boolean) from public,anon;
grant execute on function public.submit_bowtie_inquiry(text,text,text,boolean) to authenticated;
-- Authenticated accounts can still submit spam. Add CAPTCHA, throttling,
-- audit trail, verified dealership inventory, and abuse monitoring before public launch.
