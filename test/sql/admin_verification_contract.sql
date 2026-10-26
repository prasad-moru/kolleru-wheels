-- Run only in an isolated pg_virtualenv database.
\set ON_ERROR_STOP on
begin;
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create table auth.users(id uuid primary key);
create table public.user_profiles(phone text primary key, user_id uuid, role text);
create table public.drivers(id uuid primary key, phone text unique, user_id uuid, is_available boolean,
  updated_at timestamptz default now());
create table public.call_telemetry(id uuid primary key);
create function public.kolleru_role() returns text language sql security definer set search_path = '' as
  $$ select role from public.user_profiles where user_id = auth.uid() $$;
create function public.is_kolleru_admin() returns boolean language sql security definer set search_path = '' as
  $$ select exists(select 1 from public.user_profiles where user_id = auth.uid() and role = 'admin') $$;
create function public.kolleru_normalized_phone(value text) returns text language sql immutable as
  $$ select '+' || regexp_replace(value, '[^0-9]', '', 'g') $$;
insert into auth.users values
('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'), ('00000000-0000-0000-0000-000000000003');
insert into public.user_profiles values
('+919876543210', '00000000-0000-0000-0000-000000000001', 'driver'),
('+919111111111', '00000000-0000-0000-0000-000000000002', 'admin'),
('+918523123498', '00000000-0000-0000-0000-000000000003', 'shipper');
insert into public.drivers(id,phone,user_id,is_available) values
('00000000-0000-0000-0000-000000000011', '+919876543210', '00000000-0000-0000-0000-000000000001', true);
\ir ../../supabase/migrations/202610260003_admin_driver_verification.sql
create trigger stamp_driver_owner before insert or update on public.drivers
  for each row execute function public.stamp_kolleru_driver_owner();
alter table public.drivers enable row level security;
grant usage on schema auth to authenticated;
grant select, insert, update on public.drivers to authenticated;
grant select(id,phone,is_available) on public.drivers to anon;
-- Reproduce the existing permissive policies; the migration adds the boundary.
create policy guest_directory_read on public.drivers for select to anon using (is_available);
create policy driver_owner_all on public.drivers for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy admin_hub_drivers_read on public.drivers for select to authenticated using (public.is_kolleru_admin());
create policy shipper_directory on public.drivers for select to authenticated using (public.kolleru_role() = 'shipper' and is_available);
insert into public.drivers(id,phone,user_id,is_available) values
('00000000-0000-0000-0000-000000000012', '+919222222222', null, true),
('00000000-0000-0000-0000-000000000013', '+919333333333', null, true);
do $$ begin
  assert (select verification_status from public.drivers where id = '00000000-0000-0000-0000-000000000011') = 'approved', 'Legacy fleet lost approval';
  assert (select verification_status from public.drivers where id = '00000000-0000-0000-0000-000000000012') = 'pending';
  assert not has_function_privilege('anon', 'public.review_kolleru_driver(uuid,text)', 'EXECUTE');
end $$;
set local role anon;
do $$ begin assert (select count(id) from public.drivers) = 1, 'Pending drivers leaked to guests'; end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"phone":"919876543210"}', true);
do $$ begin
  begin perform public.review_kolleru_driver('00000000-0000-0000-0000-000000000012', 'approved');
    raise exception 'Driver granted approval'; exception when insufficient_privilege then null; end;
end $$;
-- A fresh owner cannot spoof approval, reviewer, or owner id in an upsert.
insert into public.drivers(id,phone,user_id,is_available,verification_status,reviewed_by) values
('00000000-0000-0000-0000-000000000014', '+919876543210', '00000000-0000-0000-0000-000000000002', true, 'approved', '00000000-0000-0000-0000-000000000002')
on conflict(phone) do update set verification_status = excluded.verification_status;
do $$ begin
  assert (select verification_status from public.drivers where phone = '+919876543210') = 'approved', 'Owner upsert reset legacy approval';
end $$;
reset role;
-- Re-use the owner's identity for a truly new pending registration.
delete from public.drivers where phone = '+919876543210';
set local role authenticated;
insert into public.drivers(id,phone,user_id,is_available,verification_status,reviewed_by) values
('00000000-0000-0000-0000-000000000014', '+919876543210', null, true, 'approved', '00000000-0000-0000-0000-000000000002');
update public.drivers set verification_status = 'approved', reviewed_at = now();
do $$ begin
  assert (select verification_status from public.drivers where phone = '+919876543210') = 'pending', 'Owner self-approved';
  assert (select reviewed_at is null and reviewed_by is null from public.drivers where phone = '+919876543210');
end $$;
-- Trusted admin approves one pending row, rejects another, preserves ownership.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"phone":"919111111111"}', true);
select public.review_kolleru_driver('00000000-0000-0000-0000-000000000014', 'approved');
select public.review_kolleru_driver('00000000-0000-0000-0000-000000000013', 'rejected');
do $$ begin
  assert (select verification_status = 'approved' and reviewed_by = auth.uid() and reviewed_at is not null and user_id = '00000000-0000-0000-0000-000000000001' and phone = '+919876543210'
    from public.drivers where id = '00000000-0000-0000-0000-000000000014');
  assert (select verification_status from public.drivers where id = '00000000-0000-0000-0000-000000000013') = 'rejected';
  begin perform public.review_kolleru_driver('00000000-0000-0000-0000-000000000014', 'rejected');
    raise exception 'Stale decision overwrote approval'; exception when serialization_failure then null; end;
  begin perform public.review_kolleru_driver('00000000-0000-0000-0000-000000000012', 'pending');
    raise exception 'Invalid decision accepted'; exception when invalid_parameter_value then null; end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
do $$ begin
  assert (select count(*) from public.drivers) = 1, 'Shipper saw pending or rejected vehicles';
  begin perform public.review_kolleru_driver('00000000-0000-0000-0000-000000000012', 'approved');
    raise exception 'Shipper granted approval'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin assert (select count(id) from public.drivers) = 1, 'Rejected drivers leaked to guests'; end $$;
reset role;
rollback;
