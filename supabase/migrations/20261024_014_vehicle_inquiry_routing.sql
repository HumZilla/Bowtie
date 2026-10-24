-- Bowtie production intake: referred and direct vehicle inquiries.
-- Apply after migrations 005 and 013. No rewards or automatic CRM delivery.
create table if not exists public.bowtie_vehicle_inquiries (
 id uuid primary key default gen_random_uuid(),
 buyer_id uuid not null references auth.users(id),
 buyer_email text not null,
 buyer_name text not null check (length(buyer_name) between 2 and 80),
 vehicle_stock text not null check (length(vehicle_stock) between 1 and 60),
 member_id uuid references public.member_profiles(user_id),
 referral_record_id uuid unique references public.referral_records(id),
 consent_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 routing_status text not null default 'needs_hicks_followup' check(routing_status in ('needs_hicks_followup','hicks_contacted','closed')),
 routed_at timestamptz,
 routed_by uuid references auth.users(id)
);
create index if not exists bowtie_vehicle_inquiries_created on public.bowtie_vehicle_inquiries(created_at desc);
create index if not exists bowtie_vehicle_inquiries_buyer on public.bowtie_vehicle_inquiries(buyer_id,created_at desc);
alter table public.bowtie_vehicle_inquiries enable row level security;
revoke all on public.bowtie_vehicle_inquiries from public,anon,authenticated;
grant select on public.bowtie_vehicle_inquiries to authenticated;
drop policy if exists "admins read vehicle inquiries" on public.bowtie_vehicle_inquiries;
create policy "admins read vehicle inquiries" on public.bowtie_vehicle_inquiries for select to authenticated using ((select public.is_bowtie_admin()));
-- Do not expose buyer PII to referring members or sales reps.

create or replace function public.bowtie_submit_vehicle_inquiry(
 p_member_code text,p_vehicle_stock text,p_buyer_name text,p_consent boolean
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_buyer uuid:=auth.uid();
 v_email text;
 v_member uuid;
 v_referral uuid;
 v_id uuid;
 v_stock text:=upper(trim(coalesce(p_vehicle_stock,'')));
 v_name text:=trim(coalesce(p_buyer_name,''));
 v_code text:=trim(coalesce(p_member_code,''));
begin
 if v_buyer is null then raise exception 'Please sign in first'; end if;
 select email into v_email from auth.users where id=v_buyer and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verify your email before submitting'; end if;
 if p_consent is distinct from true then raise exception 'Customer consent is required'; end if;
 if length(v_name) not between 2 and 80 then raise exception 'Enter your name'; end if;
 if length(v_stock) not between 1 and 60 then raise exception 'Enter vehicle stock number'; end if;
 if v_code<>'' then
   select user_id into v_member from public.member_profiles where member_code=v_code;
   if v_member is null then raise exception 'Referral code not recognized'; end if;
   if v_member=v_buyer then raise exception 'Self-referrals are not allowed'; end if;
 end if;
 -- Serialize per buyer/stock to prevent concurrent double submissions.
 perform pg_advisory_xact_lock(hashtextextended(v_buyer::text||':'||v_stock,0));
 if exists(select 1 from public.bowtie_vehicle_inquiries where buyer_id=v_buyer and vehicle_stock=v_stock and created_at>now()-interval '24 hours')
 then raise exception 'You already submitted an inquiry for this vehicle in the last 24 hours'; end if;
 if (select count(*) from public.bowtie_vehicle_inquiries where buyer_id=v_buyer and created_at>now()-interval '1 hour')>=5
 then raise exception 'Inquiry limit reached. Please try again later'; end if;
 if v_member is not null then
  insert into public.referral_records(member_id,vehicle_stock,status)
  values(v_member,v_stock,'received') returning id into v_referral;
  insert into public.referral_buyers(referral_id,buyer_user_id,buyer_email,buyer_name)
  values(v_referral,v_buyer,v_email,v_name);
 end if;
 insert into public.bowtie_vehicle_inquiries(buyer_id,buyer_email,buyer_name,vehicle_stock,member_id,referral_record_id)
 values(v_buyer,v_email,v_name,v_stock,v_member,v_referral) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.bowtie_submit_vehicle_inquiry(text,text,text,boolean) from public,anon;
grant execute on function public.bowtie_submit_vehicle_inquiry(text,text,text,boolean) to authenticated;

create or replace function public.bowtie_admin_mark_inquiry(p_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 if p_status not in ('hicks_contacted','closed') then raise exception 'Invalid routing status'; end if;
 update public.bowtie_vehicle_inquiries
 set routing_status=p_status,routed_at=now(),routed_by=auth.uid()
 where id=p_id and routing_status='needs_hicks_followup';
 if not found then raise exception 'Inquiry not found or already processed'; end if;
 -- This action is a human acknowledgment, NOT an automated CRM transmission.
end; $$;
revoke all on function public.bowtie_admin_mark_inquiry(uuid,text) from public,anon;
grant execute on function public.bowtie_admin_mark_inquiry(uuid,text) to authenticated;
