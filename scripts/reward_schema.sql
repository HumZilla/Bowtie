create table public.bowtie_rewards (
 referral_id uuid primary key references public.referral_records(id) on delete restrict,
 member_id uuid not null references public.member_profiles(user_id),
 stock text not null,
 age_days integer check(age_days is null or age_days >= 0),
 tier text not null check(tier in ('white','black','purple','gold')),
 amount integer not null check ((tier='white' and amount=100) or (tier='black' and amount=250) or (tier='purple' and amount=375) or (tier='gold' and amount=500)),
 status text not null default 'pending' check(status in ('pending','earned','paid','cancelled')),
 created_at timestamptz not null default now(),
 earned_at timestamptz, earned_by uuid references auth.users(id),
 paid_at timestamptz, paid_by uuid references auth.users(id)
);
alter table public.bowtie_rewards enable row level security;
revoke all on public.bowtie_rewards from public, anon, authenticated;
create index bowtie_rewards_member_idx on public.bowtie_rewards(member_id,created_at desc);
create function public.bowtie_snapshot_reward() returns trigger language plpgsql security definer set search_path='' as $$
declare v_age integer; v_gold boolean; v_tier text; v_amount integer; v_matches integer;
begin
 select count(*), max(days_in_inventory), bool_or(gold_bowtie)
 into v_matches,v_age,v_gold from public.bowtie_inventory_admin
 where upper(trim(stock))=upper(trim(coalesce(new.vehicle_stock,''))) and dealership='Hicks Family Subaru';
 if v_matches<>1 then v_age:=null; v_gold:=false;
 elsif v_age is not null then v_age:=v_age+greatest(0,(new.created_at at time zone 'America/Chicago')::date-date '2026-10-23'); end if;
 v_tier:=case when v_gold then 'gold' when v_age is null or v_age<=44 then 'white' when v_age<=74 then 'black' else 'purple' end;
 v_amount:=case v_tier when 'gold' then 500 when 'purple' then 375 when 'black' then 250 else 100 end;
 insert into public.bowtie_rewards(referral_id,member_id,stock,age_days,tier,amount) values(new.id,new.member_id,coalesce(new.vehicle_stock,''),v_age,v_tier,v_amount);
 return new;
end $$;
revoke all on function public.bowtie_snapshot_reward() from public,anon,authenticated;
create trigger bowtie_referral_reward_snapshot after insert on public.referral_records for each row execute function public.bowtie_snapshot_reward();
create function public.bowtie_my_rewards() returns table(referral_id uuid,stock text,tier text,amount integer,status text,created_at timestamptz,earned_at timestamptz,paid_at timestamptz)
language sql stable security definer set search_path='' as $$
 select r.referral_id,r.stock,r.tier,r.amount,r.status,r.created_at,r.earned_at,r.paid_at from public.bowtie_rewards r where r.member_id=auth.uid() order by r.created_at desc
$$;
revoke all on function public.bowtie_my_rewards() from public,anon;
grant execute on function public.bowtie_my_rewards() to authenticated;
create function public.bowtie_admin_rewards() returns table(referral_id uuid,member_id uuid,member_name text,stock text,tier text,amount integer,status text,created_at timestamptz,earned_at timestamptz,paid_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 return query select r.referral_id,r.member_id,m.display_name,r.stock,r.tier,r.amount,r.status,r.created_at,r.earned_at,r.paid_at from public.bowtie_rewards r join public.member_profiles m on m.user_id=r.member_id order by r.created_at desc;
end $$;
revoke all on function public.bowtie_admin_rewards() from public,anon;
grant execute on function public.bowtie_admin_rewards() to authenticated;
create function public.bowtie_admin_reward_transition(p_referral_id uuid,p_status text,p_hfs_verified boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare v_status text; v_ref_status text;
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 select r.status,f.status into v_status,v_ref_status from public.bowtie_rewards r join public.referral_records f on f.id=r.referral_id where r.referral_id=p_referral_id for update of r;
 if not found then raise exception 'Reward not found'; end if;
 if p_status='earned' then
  if v_status<>'pending' then raise exception 'Reward is not pending'; end if;
  if v_ref_status<>'delivered' or p_hfs_verified is distinct from true then raise exception 'Verify Hicks Family Subaru delivery first'; end if;
  update public.bowtie_rewards set status='earned',earned_at=now(),earned_by=auth.uid() where referral_id=p_referral_id;
 elsif p_status='paid' then
  if v_status<>'earned' then raise exception 'Reward must be earned and not already paid'; end if;
  update public.bowtie_rewards set status='paid',paid_at=now(),paid_by=auth.uid() where referral_id=p_referral_id;
 else raise exception 'Invalid transition'; end if;
end $$;
revoke all on function public.bowtie_admin_reward_transition(uuid,text,boolean) from public,anon;
grant execute on function public.bowtie_admin_reward_transition(uuid,text,boolean) to authenticated;