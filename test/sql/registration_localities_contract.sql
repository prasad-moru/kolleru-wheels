-- Run with pg_virtualenv -t psql -X -q -f test/sql/registration_localities_contract.sql
\set ON_ERROR_STOP on
begin;
create role anon nologin;
create role authenticated nologin;
create table public.user_profiles(phone text primary key);
create table public.drivers(id text primary key, is_available boolean not null);
alter table public.drivers enable row level security;
create policy guest_available on public.drivers for select to anon using (is_available);
\ir ../../supabase/migrations/202610260002_registration_localities.sql
-- Existing and new rows remain compatible, and names are stored verbatim.
insert into public.user_profiles(phone) values ('legacy');
insert into public.user_profiles(phone, base_location) values ('shipper', 'సిద్ధాపురం');
insert into public.drivers values ('online', true, 'Siddhapuram Pond'), ('offline', false, 'Private base');
do $$ begin
  assert (select base_location is null from public.user_profiles where phone = 'legacy');
  assert (select base_location = 'సిద్ధాపురం' from public.user_profiles where phone = 'shipper');
  begin insert into public.user_profiles values ('bad', ' '); raise exception 'Blank base accepted';
  exception when check_violation then null; end;
  begin insert into public.drivers values ('long', true, repeat('a', 81)); raise exception 'Oversized base accepted';
  exception when check_violation then null; end;
  assert has_column_privilege('anon', 'public.drivers', 'base_location', 'SELECT');
  assert not has_column_privilege('anon', 'public.drivers', 'base_location', 'UPDATE');
  assert not has_column_privilege('anon', 'public.user_profiles', 'base_location', 'SELECT');
end $$;
set local role anon;
do $$ begin
  assert (select count(base_location) from public.drivers) = 1, 'Offline locality leaked';
  assert (select base_location from public.drivers) = 'Siddhapuram Pond';
end $$;
reset role;
rollback;
