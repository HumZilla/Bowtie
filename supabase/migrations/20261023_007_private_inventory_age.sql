-- Private inventory aging and Gold Bowtie admin selections
create table if not exists public.bowtie_inventory_admin (
 vin text primary key check (vin ~ '^[A-HJ-NPR-Z0-9]{17}$'),
 stock text not null,
 dealership text not null,
 days_in_inventory integer check (days_in_inventory between 0 and 10000),
 gold_bowtie boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.bowtie_inventory_admin enable row level security;
revoke all on public.bowtie_inventory_admin from anon;
grant select,insert,update,delete on public.bowtie_inventory_admin to authenticated;
drop policy if exists "Admins read private inventory" on public.bowtie_inventory_admin;
create policy "Admins read private inventory" on public.bowtie_inventory_admin for select to authenticated using (exists(select 1 from public.admin_members a where a.user_id=(select auth.uid())));
drop policy if exists "Admins add private inventory" on public.bowtie_inventory_admin;
create policy "Admins add private inventory" on public.bowtie_inventory_admin for insert to authenticated with check (exists(select 1 from public.admin_members a where a.user_id=(select auth.uid())));
drop policy if exists "Admins edit private inventory" on public.bowtie_inventory_admin;
create policy "Admins edit private inventory" on public.bowtie_inventory_admin for update to authenticated using (exists(select 1 from public.admin_members a where a.user_id=(select auth.uid()))) with check (exists(select 1 from public.admin_members a where a.user_id=(select auth.uid())));
