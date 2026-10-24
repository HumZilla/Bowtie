-- Bowtie phase 3: invite-only Hicks Family Subaru sales referral intake.
-- Run after 002, 005, 006, 009, 010. No payouts or automatic delivered statuses.
create table if not exists public.bowtie_sales_reps(
 email text primary key,
 display_name text not null,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 constraint sales_rep_email_normalized check(email=lower(email))
);
alter table public.bowtie_sales_reps enable row level security;
revoke all on public.bowtie_sales_reps from public,anon,authenticated;
insert into public.bowtie_sales_reps(email,display_name) values
('smartinez@hicksautogroup.com','Bass'),
('lfoster@hicksautogroup.com','Lulu'),
('kconsoli@hicksautogroup.com','KC'),
('jleal@hicksautogroup.com','Jose'),
('mcarrales@hicksautogroup.com','Marcos')
on conflict(email) do nothing;

create table if not exists public.bowtie_sales_intake(
 id uuid primary key default gen_random_uuid(),
 created_by uuid not null references auth.users(id),
 referral_id uuid references public.referral_records(id),
 intake_type text not null check(intake_type in ('walkin','delivery')),
 buyer_name text,
 referrer_name text,
 vehicle_stock text not null,
 delivery_date date,
 consent_confirmed boolean not null default false,
 review_status text not null default 'pending' check(review_status in ('pending','approved','rejected')),
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 constraint intake_fields_check check(
 (intake_type='walkin' and referral_id is null and buyer_name is not null and referrer_name is not null and consent_confirmed=true and delivery_date is null)
 or (intake_type='delivery' and referral_id is not null and buyer_name is null and referrer_name is null and delivery_date is not null)
 )
);
create unique index if not exists bowtie_pending_delivery_unique on public.bowtie_sales_intake(referral_id) where intake_type='delivery' and review_status='pending';
create index if not exists bowtie_sales_intake_owner on public.bowtie_sales_intake(created_by,created_at desc);
alter table public.bowtie_sales_intake enable row level security;
revoke all on public.bowtie_sales_intake from public,anon,authenticated;

create table if not exists public.bowtie_referral_assignments(
 referral_id uuid primary key references public.referral_records(id) on delete cascade,
 rep_email text not null references public.bowtie_sales_reps(email),
 assigned_by uuid not null references auth.users(id),
 assigned_at timestamptz not null default now()
);
alter table public.bowtie_referral_assignments enable row level security;
revoke all on public.bowtie_referral_assignments from public,anon,authenticated;

-- The login identity must have a verified email and be on the active allowlist.
create or replace function public.bowtie_sales_identity()
returns text language sql stable security definer set search_path='' as $$
 select lower(u.email) from auth.users u
 join public.bowtie_sales_reps r on r.email=lower(u.email) and r.active
 where u.id=auth.uid() and u.email_confirmed_at is not null
 limit 1;
$$;
revoke all on function public.bowtie_sales_identity() from public,anon;
grant execute on function public.bowtie_sales_identity() to authenticated;

create or replace function public.bowtie_sales_my_queue()
returns table(referral_id uuid,vehicle_stock text,referral_status text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select r.id,r.vehicle_stock,r.status,r.created_at from public.referral_records r
 join public.bowtie_referral_assignments a on a.referral_id=r.id
 where a.rep_email=public.bowtie_sales_identity()
 order by r.created_at desc limit 100;
$$;
revoke all on function public.bowtie_sales_my_queue() from public,anon;
grant execute on function public.bowtie_sales_my_queue() to authenticated;

create or replace function public.bowtie_sales_my_submissions()
returns table(id uuid,intake_type text,vehicle_stock text,review_status text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select s.id,s.intake_type,s.vehicle_stock,s.review_status,s.created_at
 from public.bowtie_sales_intake s where s.created_by=auth.uid()
 and public.bowtie_sales_identity() is not null order by s.created_at desc limit 100;
$$;
revoke all on function public.bowtie_sales_my_submissions() from public,anon;
grant execute on function public.bowtie_sales_my_submissions() to authenticated;

create or replace function public.bowtie_sales_create_walkin(p_buyer_name text,p_referrer_name text,p_vehicle_stock text,p_consent_confirmed boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if public.bowtie_sales_identity() is null then raise exception 'Authorized sales account required'; end if;
 if p_consent_confirmed is distinct from true then raise exception 'Confirm customer consent before submission'; end if;
 if length(trim(coalesce(p_buyer_name,''))) not between 2 and 80 or length(trim(coalesce(p_referrer_name,''))) not between 2 and 80 then raise exception 'Enter customer and referrer names'; end if;
 if length(trim(coalesce(p_vehicle_stock,''))) not between 1 and 60 then raise exception 'Enter a valid stock number'; end if;
 insert into public.bowtie_sales_intake(created_by,intake_type,buyer_name,referrer_name,vehicle_stock,consent_confirmed)
 values(auth.uid(),'walkin',trim(p_buyer_name),trim(p_referrer_name),trim(p_vehicle_stock),true) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.bowtie_sales_create_walkin(text,text,text,boolean) from public,anon;
grant execute on function public.bowtie_sales_create_walkin(text,text,text,boolean) to authenticated;

create or replace function public.bowtie_sales_submit_delivery(p_referral_id uuid,p_vehicle_stock text,p_delivery_date date)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_email text:=public.bowtie_sales_identity();
begin
 if v_email is null then raise exception 'Authorized sales account required'; end if;
 if not exists(select 1 from public.bowtie_referral_assignments a where a.referral_id=p_referral_id and a.rep_email=v_email) then raise exception 'Referral not assigned to your account'; end if;
 if p_delivery_date is null or p_delivery_date>current_date or p_delivery_date<current_date-interval '365 days' then raise exception 'Enter a valid delivery date'; end if;
 if length(trim(coalesce(p_vehicle_stock,''))) not between 1 and 60 then raise exception 'Enter purchased stock number'; end if;
 if exists(select 1 from public.bowtie_sales_intake where referral_id=p_referral_id and intake_type='delivery' and review_status='approved') then raise exception 'Delivery already approved'; end if;
 insert into public.bowtie_sales_intake(created_by,referral_id,intake_type,vehicle_stock,delivery_date)
 values(auth.uid(),p_referral_id,'delivery',trim(p_vehicle_stock),p_delivery_date) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.bowtie_sales_submit_delivery(uuid,text,date) from public,anon;
grant execute on function public.bowtie_sales_submit_delivery(uuid,text,date) to authenticated;

create or replace function public.bowtie_admin_sales_queue()
returns table(id uuid,rep_email text,intake_type text,referral_id uuid,buyer_name text,referrer_name text,vehicle_stock text,delivery_date date,review_status text,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 return query select s.id,lower(u.email),s.intake_type,s.referral_id,s.buyer_name,s.referrer_name,s.vehicle_stock,s.delivery_date,s.review_status,s.created_at
 from public.bowtie_sales_intake s join auth.users u on u.id=s.created_by
 order by s.created_at desc limit 150;
end; $$;
revoke all on function public.bowtie_admin_sales_queue() from public,anon;
grant execute on function public.bowtie_admin_sales_queue() to authenticated;

create or replace function public.bowtie_admin_assign_referral(p_referral_id uuid,p_rep_email text)
returns void language plpgsql security definer set search_path='' as $$
declare v_email text:=lower(trim(p_rep_email));
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 if not exists(select 1 from public.bowtie_sales_reps where email=v_email and active) then raise exception 'Sales rep is not active'; end if;
 if not exists(select 1 from public.referral_records where id=p_referral_id) then raise exception 'Referral not found'; end if;
 insert into public.bowtie_referral_assignments(referral_id,rep_email,assigned_by)
 values(p_referral_id,v_email,auth.uid())
 on conflict(referral_id) do update set rep_email=excluded.rep_email,assigned_by=excluded.assigned_by,assigned_at=now();
end; $$;
revoke all on function public.bowtie_admin_assign_referral(uuid,text) from public,anon;
grant execute on function public.bowtie_admin_assign_referral(uuid,text) to authenticated;

create or replace function public.bowtie_admin_review_sales_intake(p_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_record public.bowtie_sales_intake%rowtype;
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 select * into v_record from public.bowtie_sales_intake where id=p_id for update;
 if not found then raise exception 'Submission not found'; end if;
 if v_record.review_status<>'pending' then raise exception 'Already reviewed'; end if;
 update public.bowtie_sales_intake set review_status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
 -- Approved delivery evidence is intentionally NOT a verified delivery or payout.
 -- Manager must separately verify sale in DMS/CRM before changing referral_records.status.
end; $$;
revoke all on function public.bowtie_admin_review_sales_intake(uuid,boolean) from public,anon;
grant execute on function public.bowtie_admin_review_sales_intake(uuid,boolean) to authenticated;
