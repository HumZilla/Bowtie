-- Apply after migration 012. Adds concurrency-safe 24-hour duplicate handoff prevention.
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

