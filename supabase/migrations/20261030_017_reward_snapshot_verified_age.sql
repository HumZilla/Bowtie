-- Applied to production Supabase on 2026-10-30.
-- Authoritative age baseline for 274 VINs is stored in bowtie_inventory_age_snapshots.
-- Records were imported from the six dealership CSV exports, with age_as_of 2026-10-30.
-- Existing bowtie_inventory_admin.gold_bowtie flags are preserved.
create table if not exists public.bowtie_inventory_age_snapshots (
 vin text primary key, stock text not null, dealership text not null,
 age_days integer not null, age_as_of date not null
);
alter table public.bowtie_inventory_age_snapshots enable row level security;
revoke all on public.bowtie_inventory_age_snapshots from anon, authenticated;
create or replace function public.bowtie_snapshot_reward()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_age integer; v_gold boolean; v_matches integer; v_tier text; v_amount integer;
begin
 select count(*), max(s.age_days + greatest(0,(new.created_at at time zone 'America/Chicago')::date-s.age_as_of)), bool_or(coalesce(a.gold_bowtie,false))
 into v_matches,v_age,v_gold
 from public.bowtie_inventory_age_snapshots s
 left join public.bowtie_inventory_admin a on a.vin=s.vin
 where upper(trim(s.stock))=upper(trim(coalesce(new.vehicle_stock,'')));
 if v_matches<>1 or v_age is null then
   raise exception 'Reward vehicle stock cannot be verified; contact Hicks Family Subaru';
 end if;
 v_tier:=case when v_gold then 'gold' when v_age<=44 then 'white' when v_age<=74 then 'black' else 'purple' end;
 v_amount:=case v_tier when 'gold' then 500 when 'purple' then 375 when 'black' then 250 else 100 end;
 insert into public.bowtie_rewards(referral_id,member_id,stock,age_days,tier,amount)
 values(new.id,new.member_id,new.vehicle_stock,v_age,v_tier,v_amount);
 return new;
end $$;
revoke all on function public.bowtie_snapshot_reward() from public, anon, authenticated;
