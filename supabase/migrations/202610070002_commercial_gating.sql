-- Apply after profile_completion. Existing duplicate phone rows must be resolved
-- before creating this index; this migration deliberately does not delete data.
create unique index if not exists drivers_phone_unique on public.drivers(phone);
alter table public.user_profiles add column if not exists village_id text;
grant insert(village_id) on public.user_profiles to authenticated;

revoke all on public.drivers, public.load_requests from anon;
revoke all on public.call_telemetry from anon;
grant select, insert, update on public.drivers, public.load_requests to authenticated;
alter table public.drivers enable row level security;
alter table public.load_requests enable row level security;

create or replace function public.kolleru_role()
returns text language sql stable security definer set search_path = '' as $$
  select role from public.user_profiles where user_id = auth.uid();
$$;
revoke all on function public.kolleru_role() from public;
grant execute on function public.kolleru_role() to authenticated;

create policy commercial_drivers_read on public.drivers for select to authenticated
using (public.kolleru_role() = 'admin'
  or (public.kolleru_role() = 'shipper' and is_available)
  or (public.kolleru_role() = 'driver' and phone = '+' || ltrim(auth.jwt()->>'phone', '+')));
create policy commercial_drivers_read_boundary on public.drivers as restrictive for select to authenticated
using (public.kolleru_role() = 'admin'
  or (public.kolleru_role() = 'shipper' and is_available)
  or (public.kolleru_role() = 'driver' and phone = '+' || ltrim(auth.jwt()->>'phone', '+')));
create policy commercial_drivers_insert on public.drivers for insert to authenticated
with check (public.kolleru_role() = 'driver' and phone = '+' || ltrim(auth.jwt()->>'phone', '+'));
create policy commercial_drivers_update on public.drivers for update to authenticated
using (public.kolleru_role() = 'driver' and phone = '+' || ltrim(auth.jwt()->>'phone', '+'))
with check (public.kolleru_role() = 'driver' and phone = '+' || ltrim(auth.jwt()->>'phone', '+'));
create policy commercial_drivers_insert_boundary on public.drivers as restrictive for insert to authenticated
with check (public.kolleru_role() = 'driver' and phone = '+' || ltrim(auth.jwt()->>'phone', '+'));
create policy commercial_drivers_update_boundary on public.drivers as restrictive for update to authenticated
using (public.kolleru_role() = 'driver' and phone = '+' || ltrim(auth.jwt()->>'phone', '+'))
with check (public.kolleru_role() = 'driver' and phone = '+' || ltrim(auth.jwt()->>'phone', '+'));

create policy commercial_loads_read on public.load_requests for select to authenticated
using (public.kolleru_role() = 'admin'
  or (public.kolleru_role() = 'driver' and not is_closed and created_at > now() - interval '30 minutes')
  or (public.kolleru_role() = 'shipper' and poster_phone = '+' || ltrim(auth.jwt()->>'phone', '+')));
create policy commercial_loads_read_boundary on public.load_requests as restrictive for select to authenticated
using (public.kolleru_role() = 'admin'
  or (public.kolleru_role() = 'driver' and not is_closed and created_at > now() - interval '30 minutes')
  or (public.kolleru_role() = 'shipper' and poster_phone = '+' || ltrim(auth.jwt()->>'phone', '+')));
create policy commercial_loads_insert on public.load_requests for insert to authenticated
with check (public.kolleru_role() = 'shipper' and poster_phone = '+' || ltrim(auth.jwt()->>'phone', '+'));
create policy commercial_loads_update on public.load_requests for update to authenticated
using (public.kolleru_role() = 'shipper' and poster_phone = '+' || ltrim(auth.jwt()->>'phone', '+'))
with check (public.kolleru_role() = 'shipper' and poster_phone = '+' || ltrim(auth.jwt()->>'phone', '+'));
create policy commercial_loads_insert_boundary on public.load_requests as restrictive for insert to authenticated
with check (public.kolleru_role() = 'shipper' and poster_phone = '+' || ltrim(auth.jwt()->>'phone', '+'));
create policy commercial_loads_update_boundary on public.load_requests as restrictive for update to authenticated
using (public.kolleru_role() = 'shipper' and poster_phone = '+' || ltrim(auth.jwt()->>'phone', '+'))
with check (public.kolleru_role() = 'shipper' and poster_phone = '+' || ltrim(auth.jwt()->>'phone', '+'));
