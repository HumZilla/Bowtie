-- Bowtie reward review register. Apply after 014 and 011.
-- COMPLIANCE LOCK: no point issuance, gift-card redemption, check or payment functions.
-- Records verification and a proposed amount only; a proposal is NOT a member balance.
create table if not exists public.bowtie_reward_reviews (
 referral_id uuid primary key references public.referral_records(id) on delete restrict,
 member_id uuid not null references public.member_profiles(user_id),
 buyer_inquiry_id uuid unique references public.bowtie_vehicle_inquiries(id),
 purchased_stock text not null check (length(trim(purchased_stock)) between 1 and 60),
 purchase_date date not null,
 crm_lead_verified boolean not null default false,
 delivery_verified boolean not null default false,
 manager_verified boolean not null default false,
 proposed_points integer not null default 0 check(proposed_points between 0 and 100000),
 review_state text not null default 'evidence_pending' check(review_state in ('evidence_pending','verified_for_compliance','rejected')),
 review_note text not null default '' check(length(review_note)<=1000),
 reviewed_by uuid not null references auth.users(id),
 reviewed_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint reward_review_verified_check check (
   review_state <> 'verified_for_compliance'
   or (crm_lead_verified and delivery_verified and manager_verified and buyer_inquiry_id is not null and proposed_points>0)
 )
);
create index if not exists bowtie_reward_reviews_member on public.bowtie_reward_reviews(member_id,created_at desc);
alter table public.bowtie_reward_reviews enable row level security;
revoke all on public.bowtie_reward_reviews from public,anon,authenticated;
-- Only a narrowly scoped member RPC exposes a safe subset. No direct table access.

create table if not exists public.bowtie_reward_review_audit (
 id bigint generated always as identity primary key,
 referral_id uuid not null references public.referral_records(id),
 actor_id uuid not null references auth.users(id),
 old_state text,
 new_state text not null,
 old_proposed_points integer,
 new_proposed_points integer not null,
 changed_at timestamptz not null default now()
);
alter table public.bowtie_reward_review_audit enable row level security;
revoke all on public.bowtie_reward_review_audit from public,anon,authenticated;

create or replace function public.bowtie_admin_reward_queue()
returns table(referral_id uuid,member_id uuid,vehicle_stock text,referral_status text,buyer_inquiry_id uuid,purchased_stock text,purchase_date date,crm_lead_verified boolean,delivery_verified boolean,manager_verified boolean,proposed_points integer,review_state text,review_note text,reviewed_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 return query
 select r.id,r.member_id,r.vehicle_stock,r.status,i.id,coalesce(w.purchased_stock,''),w.purchase_date,
 coalesce(w.crm_lead_verified,false),coalesce(w.delivery_verified,false),coalesce(w.manager_verified,false),
 coalesce(w.proposed_points,0),coalesce(w.review_state,'not_started'),coalesce(w.review_note,''),w.reviewed_at
 from public.referral_records r
 left join public.bowtie_vehicle_inquiries i on i.referral_record_id=r.id
 left join public.bowtie_reward_reviews w on w.referral_id=r.id
 order by r.created_at desc limit 150;
end; $$;
revoke all on function public.bowtie_admin_reward_queue() from public,anon;
grant execute on function public.bowtie_admin_reward_queue() to authenticated;

create or replace function public.bowtie_admin_review_reward(
 p_referral_id uuid,p_purchased_stock text,p_purchase_date date,
 p_crm_lead_verified boolean,p_delivery_verified boolean,p_manager_verified boolean,
 p_proposed_points integer,p_review_state text,p_review_note text
) returns void language plpgsql security definer set search_path='' as $$
declare v_ref public.referral_records%rowtype; v_inquiry uuid; v_old_state text; v_old_points integer;
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 select * into v_ref from public.referral_records where id=p_referral_id for update;
 if not found then raise exception 'Referral not found'; end if;
 select id into v_inquiry from public.bowtie_vehicle_inquiries where referral_record_id=p_referral_id;
 if length(trim(coalesce(p_purchased_stock,''))) not between 1 and 60 then raise exception 'Purchased stock required'; end if;
 if p_purchase_date is null or p_purchase_date>current_date or p_purchase_date<current_date-interval '365 days' then raise exception 'Valid purchase date required'; end if;
 if p_proposed_points is null or p_proposed_points<0 or p_proposed_points>100000 then raise exception 'Invalid proposed points'; end if;
 if p_review_state not in ('evidence_pending','verified_for_compliance','rejected') then raise exception 'Invalid review state'; end if;
 if length(coalesce(p_review_note,''))>1000 then raise exception 'Review note too long'; end if;
 if p_review_state='verified_for_compliance' then
  if v_ref.status<>'delivered' then raise exception 'Referral must be marked delivered after DMS verification'; end if;
  if v_inquiry is null then raise exception 'A tracked Bowtie customer inquiry is required'; end if;
  if p_crm_lead_verified is distinct from true or p_delivery_verified is distinct from true or p_manager_verified is distinct from true
  then raise exception 'All three evidence checks are required'; end if;
  if p_proposed_points=0 then raise exception 'Enter a proposed point value'; end if;
 end if;
 select review_state,proposed_points into v_old_state,v_old_points from public.bowtie_reward_reviews where referral_id=p_referral_id for update;
 insert into public.bowtie_reward_reviews(referral_id,member_id,buyer_inquiry_id,purchased_stock,purchase_date,crm_lead_verified,delivery_verified,manager_verified,proposed_points,review_state,review_note,reviewed_by)
 values(p_referral_id,v_ref.member_id,v_inquiry,trim(p_purchased_stock),p_purchase_date,coalesce(p_crm_lead_verified,false),coalesce(p_delivery_verified,false),coalesce(p_manager_verified,false),p_proposed_points,p_review_state,coalesce(p_review_note,''),auth.uid())
 on conflict(referral_id) do update set
 buyer_inquiry_id=excluded.buyer_inquiry_id,purchased_stock=excluded.purchased_stock,purchase_date=excluded.purchase_date,
 crm_lead_verified=excluded.crm_lead_verified,delivery_verified=excluded.delivery_verified,manager_verified=excluded.manager_verified,
 proposed_points=excluded.proposed_points,review_state=excluded.review_state,review_note=excluded.review_note,
 reviewed_by=excluded.reviewed_by,reviewed_at=now(),updated_at=now();
 insert into public.bowtie_reward_review_audit(referral_id,actor_id,old_state,new_state,old_proposed_points,new_proposed_points)
 values(p_referral_id,auth.uid(),v_old_state,p_review_state,v_old_points,p_proposed_points);
 -- No credits, balances, rewards, redemptions or payments are created.
end; $$;
revoke all on function public.bowtie_admin_review_reward(uuid,text,date,boolean,boolean,boolean,integer,text,text) from public,anon;
grant execute on function public.bowtie_admin_review_reward(uuid,text,date,boolean,boolean,boolean,integer,text,text) to authenticated;

create or replace function public.bowtie_member_reward_status()
returns table(referral_id uuid,vehicle_stock text,referral_status text,review_state text,proposed_points integer,reviewed_at timestamptz)
language sql stable security definer set search_path='' as $$
 select r.id,r.vehicle_stock,r.status,coalesce(w.review_state,'not_started'),coalesce(w.proposed_points,0),w.reviewed_at
 from public.referral_records r left join public.bowtie_reward_reviews w on w.referral_id=r.id
 where r.member_id=auth.uid()
 order by r.created_at desc limit 100;
$$;
revoke all on function public.bowtie_member_reward_status() from public,anon;
grant execute on function public.bowtie_member_reward_status() to authenticated;
