-- Bowtie Phase 4: service-to-sales direct handoffs.
-- Requires migration 011 (bowtie_sales_reps). Run only after 011.
-- Service referrals are operational leads, NOT member referrals or payout claims.
create table if not exists public.bowtie_service_advisors(
 email text primary key check(email=lower(email)),
 display_name text not null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
alter table public.bowtie_service_advisors enable row level security;
revoke all on public.bowtie_service_advisors from public,anon,authenticated;

create table if not exists public.bowtie_service_handoffs(
 id uuid primary key default gen_random_uuid(),
 advisor_id uuid not null references auth.users(id),
 advisor_email text not null references public.bowtie_service_advisors(email),
 rep_email text not null references public.bowtie_sales_reps(email),
 customer_name text not null check(char_length(customer_name) between 2 and 80),
 customer_phone text not null check(char_length(customer_phone) between 7 and 25),
 ro_number text check(ro_number is null or char_length(ro_number) between 1 and 40),
 opportunity text not null check(opportunity in ('trade','upgrade','equity','repair','other')),
 note text check(note is null or char_length(note)<=400),
 customer_consent boolean not null check(customer_consent=true),
 status text not null default 'sent' check(status in ('sent','accepted','contacted','appointment','working','sold','closed')),
 created_at timestamptz not null default now(),
 acknowledged_at timestamptz,
 updated_at timestamptz not null default now(),
 constraint service_ack_check check(status='sent' or acknowledged_at is not null)
);
create index if not exists service_handoffs_rep_idx on public.bowtie_service_handoffs(rep_email,created_at desc);
create index if not exists service_handoffs_advisor_idx on public.bowtie_service_handoffs(advisor_email,created_at desc);
alter table public.bowtie_service_handoffs enable row level security;
revoke all on public.bowtie_service_handoffs from public,anon,authenticated;

create table if not exists public.bowtie_service_handoff_events(
 id bigint generated always as identity primary key,
 handoff_id uuid not null references public.bowtie_service_handoffs(id),
 actor_id uuid not null references auth.users(id),
 old_status text,
 new_status text not null,
 occurred_at timestamptz not null default now()
);
alter table public.bowtie_service_handoff_events enable row level security;
revoke all on public.bowtie_service_handoff_events from public,anon,authenticated;

create or replace function public.bowtie_service_identity()
returns text language sql stable security definer set search_path='' as $$
 select lower(u.email) from auth.users u
 join public.bowtie_service_advisors a on a.email=lower(u.email) and a.active
 where u.id=auth.uid() and u.email_confirmed_at is not null limit 1;
$$;
revoke all on function public.bowtie_service_identity() from public,anon;
grant execute on function public.bowtie_service_identity() to authenticated;

create or replace function public.bowtie_service_rep_options()
returns table(email text,display_name text) language plpgsql stable security definer set search_path='' as $$
begin
 if public.bowtie_service_identity() is null and not public.is_bowtie_admin() then raise exception 'Service advisor or administrator access required'; end if;
 return query select r.email,r.display_name from public.bowtie_sales_reps r where r.active order by r.display_name;
end; $$;
revoke all on function public.bowtie_service_rep_options() from public,anon;
grant execute on function public.bowtie_service_rep_options() to authenticated;

create or replace function public.bowtie_service_send(
 p_rep_email text,p_customer_name text,p_customer_phone text,p_ro_number text,p_opportunity text,p_note text,p_consent boolean
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_email text:=public.bowtie_service_identity();v_rep text:=lower(trim(p_rep_email));v_id uuid;
begin
 if v_email is null then raise exception 'Authorized service advisor account required'; end if;
 if p_consent is distinct from true then raise exception 'Confirm customer consent to sales follow-up'; end if;
 if not exists(select 1 from public.bowtie_sales_reps where email=v_rep and active) then raise exception 'Choose an active sales rep'; end if;
 if length(trim(coalesce(p_customer_name,''))) not between 2 and 80 then raise exception 'Enter customer name'; end if;
 if length(trim(coalesce(p_customer_phone,''))) not between 7 and 25 then raise exception 'Enter customer phone'; end if;
 if p_opportunity not in ('trade','upgrade','equity','repair','other') then raise exception 'Select opportunity type'; end if;
 if length(trim(coalesce(p_ro_number,'')))>40 or length(trim(coalesce(p_note,'')))>400 then raise exception 'Input too long'; end if;
 -- Serialize submissions for this advisor/customer pair to avoid concurrent duplicates.
 perform pg_advisory_xact_lock(hashtextextended(v_email||':'||trim(p_customer_phone),0));
 if exists(
  select 1 from public.bowtie_service_handoffs h
  where h.advisor_email=v_email and h.rep_email=v_rep
    and h.customer_phone=trim(p_customer_phone)
    and coalesce(h.ro_number,'')=coalesce(nullif(trim(p_ro_number),''),'')
    and h.created_at>now()-interval '24 hours'
 ) then raise exception 'A matching handoff was already submitted within 24 hours'; end if;
 insert into public.bowtie_service_handoffs(advisor_id,advisor_email,rep_email,customer_name,customer_phone,ro_number,opportunity,note,customer_consent)
 values(auth.uid(),v_email,v_rep,trim(p_customer_name),trim(p_customer_phone),nullif(trim(p_ro_number),''),p_opportunity,nullif(trim(p_note),''),true)
 returning id into v_id;
 insert into public.bowtie_service_handoff_events(handoff_id,actor_id,old_status,new_status) values(v_id,auth.uid(),null,'sent');
 return v_id;
end; $$;
revoke all on function public.bowtie_service_send(text,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.bowtie_service_send(text,text,text,text,text,text,boolean) to authenticated;

create or replace function public.bowtie_service_my_handoffs()
returns table(id uuid,advisor_email text,rep_email text,customer_name text,customer_phone text,ro_number text,opportunity text,note text,status text,created_at timestamptz,acknowledged_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_service text:=public.bowtie_service_identity();v_rep text:=public.bowtie_sales_identity();
begin
 if v_service is null and v_rep is null and not public.is_bowtie_admin() then raise exception 'Authorized staff access required'; end if;
 return query select h.id,h.advisor_email,h.rep_email,h.customer_name,h.customer_phone,h.ro_number,h.opportunity,h.note,h.status,h.created_at,h.acknowledged_at
 from public.bowtie_service_handoffs h
 where public.is_bowtie_admin() or h.advisor_email=v_service or h.rep_email=v_rep
 order by h.created_at desc limit 200;
end; $$;
revoke all on function public.bowtie_service_my_handoffs() from public,anon;
grant execute on function public.bowtie_service_my_handoffs() to authenticated;

create or replace function public.bowtie_service_update_status(p_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare v_email text:=public.bowtie_sales_identity();v_old text;v_assigned text;v_ack timestamptz;
begin
 if v_email is null then raise exception 'Authorized salesperson account required'; end if;
 if p_status not in ('accepted','contacted','appointment','working','sold','closed') then raise exception 'Invalid status'; end if;
 select h.status,h.rep_email,h.acknowledged_at into v_old,v_assigned,v_ack from public.bowtie_service_handoffs h where h.id=p_id for update;
 if not found or v_assigned<>v_email then raise exception 'Handoff not assigned to you'; end if;
 if v_old in ('sold','closed') then raise exception 'Finalized handoff: ask management to review'; end if;
 if v_old='sent' and p_status<>'accepted' then raise exception 'Acknowledge the handoff first'; end if;
 if v_old=p_status then return; end if;
 update public.bowtie_service_handoffs set status=p_status,acknowledged_at=coalesce(v_ack,now()),updated_at=now() where id=p_id;
 insert into public.bowtie_service_handoff_events(handoff_id,actor_id,old_status,new_status) values(p_id,auth.uid(),v_old,p_status);
 -- Sold is a salesperson-reported outcome, not a DMS-verified delivery.
end; $$;
revoke all on function public.bowtie_service_update_status(uuid,text) from public,anon;
grant execute on function public.bowtie_service_update_status(uuid,text) to authenticated;

create or replace function public.bowtie_admin_add_service_advisor(p_email text,p_name text)
returns void language plpgsql security definer set search_path='' as $$
declare v_email text:=lower(trim(p_email));
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 if v_email not like '%@%' or length(v_email)>254 or length(trim(coalesce(p_name,''))) not between 2 and 80 then raise exception 'Enter valid work email and name'; end if;
 insert into public.bowtie_service_advisors(email,display_name,active) values(v_email,trim(p_name),true)
 on conflict(email) do update set display_name=excluded.display_name,active=true;
end; $$;
revoke all on function public.bowtie_admin_add_service_advisor(text,text) from public,anon;
grant execute on function public.bowtie_admin_add_service_advisor(text,text) to authenticated;

create or replace function public.bowtie_admin_set_service_advisor_active(p_email text,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 update public.bowtie_service_advisors set active=p_active where email=lower(trim(p_email));
 if not found then raise exception 'Advisor not found'; end if;
end; $$;
revoke all on function public.bowtie_admin_set_service_advisor_active(text,boolean) from public,anon;
grant execute on function public.bowtie_admin_set_service_advisor_active(text,boolean) to authenticated;

create or replace function public.bowtie_admin_service_advisors()
returns table(email text,display_name text,active boolean) language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_bowtie_admin() then raise exception 'Administrator access required'; end if;
 return query select a.email,a.display_name,a.active from public.bowtie_service_advisors a order by a.display_name;
end; $$;
revoke all on function public.bowtie_admin_service_advisors() from public,anon;
grant execute on function public.bowtie_admin_service_advisors() to authenticated;
