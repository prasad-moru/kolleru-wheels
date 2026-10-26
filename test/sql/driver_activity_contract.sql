-- Run in an isolated PostgreSQL database with pg_virtualenv; contains no production data.
\set ON_ERROR_STOP on
begin;
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create table public.user_profiles(phone text primary key, user_id uuid unique, role text, village_id text);
create table public.call_telemetry(id uuid primary key, caller_phone text, receiver_phone text, caller_role text, created_at timestamptz);
\ir ../../supabase/migrations/202610260001_driver_activity_snapshot.sql

insert into public.user_profiles values
('+919876543210', '00000000-0000-0000-0000-000000000001', 'driver', 'pulaparru'),
('+919111111111', '00000000-0000-0000-0000-000000000002', 'driver', 'akividu-town'),
('+918523123498', '00000000-0000-0000-0000-000000000003', 'shipper', 'kovvadalanka');
insert into public.call_telemetry values
('00000000-0000-0000-0000-000000000011', '+918523123498', '+919876543210', 'shipper', now()),
('00000000-0000-0000-0000-000000000012', '+918523123498', '+919876543210', 'shipper',
  (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') - interval '1 second'),
('00000000-0000-0000-0000-000000000013', '+918523123498', '+919111111111', 'shipper', now()),
('00000000-0000-0000-0000-000000000014', '+919111111111', '+919876543210', 'driver', now()),
('00000000-0000-0000-0000-000000000015', '+918523123498', '+919876543210', 'shipper', now() + interval '1 minute');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"phone":"919876543210"}', true);
do $$ declare result jsonb; begin
  result := public.driver_activity_snapshot();
  assert (result->>'calls_today')::int = 1, 'IST cutoff or receiver filter failed';
  assert jsonb_array_length(result->'recent_calls') = 2, 'Recent inquiry scope failed';
  assert result#>>'{recent_calls,0,caller_village_id}' = 'kovvadalanka', 'Caller location missing';
  assert not (result#>'{recent_calls,0}') ? 'caller_phone', 'Raw caller phone exposed';
end $$;
-- A second driver receives only their own records.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"phone":"919111111111"}', true);
do $$ declare result jsonb; begin
  result := public.driver_activity_snapshot();
  assert (result->>'calls_today')::int = 1;
  assert jsonb_array_length(result->'recent_calls') = 1;
  assert result#>>'{recent_calls,0,id}' = '00000000-0000-0000-0000-000000000013';
end $$;
-- An authenticated shipper and a mismatched phone claim cannot read driver metrics.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claims', '{"phone":"918523123498"}', true);
do $$ begin
  begin perform public.driver_activity_snapshot(); raise exception 'Shipper access was allowed';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"phone":"919111111111"}', true);
do $$ begin
  begin perform public.driver_activity_snapshot(); raise exception 'Mismatched phone was allowed';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  assert not has_function_privilege('anon', 'public.driver_activity_snapshot()', 'EXECUTE'), 'Guest execution allowed';
end $$;
rollback;
