-- Apply after 202610070002_commercial_gating.sql. Admin assignment remains
-- trusted SQL/service-role work; authenticated clients cannot change role.

alter table public.user_profiles
  drop constraint if exists user_profiles_role_check;
alter table public.user_profiles
  add constraint user_profiles_role_check
  check (role in ('driver', 'shipper', 'admin'));

create index if not exists user_profiles_role_village_idx
  on public.user_profiles(role, village_id);
create index if not exists drivers_base_village_idx
  on public.drivers(base_village_id);
create index if not exists load_requests_live_feed_idx
  on public.load_requests(created_at desc)
  where is_closed = false;
create index if not exists call_telemetry_admin_recent_idx
  on public.call_telemetry(created_at desc);

create or replace function public.is_kolleru_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles
    where user_id = auth.uid()
      and role = 'admin'
  );
$$;
revoke all on function public.is_kolleru_admin() from public;
grant execute on function public.is_kolleru_admin() to authenticated;

alter table public.user_profiles enable row level security;
alter table public.drivers enable row level security;
alter table public.load_requests enable row level security;
alter table public.call_telemetry enable row level security;

drop policy if exists admin_hub_profiles_read on public.user_profiles;
create policy admin_hub_profiles_read
  on public.user_profiles for select to authenticated
  using (user_id = auth.uid() or public.is_kolleru_admin());

drop policy if exists admin_hub_drivers_read on public.drivers;
create policy admin_hub_drivers_read
  on public.drivers for select to authenticated
  using (public.is_kolleru_admin());

drop policy if exists admin_hub_loads_read on public.load_requests;
create policy admin_hub_loads_read
  on public.load_requests for select to authenticated
  using (public.is_kolleru_admin());

drop policy if exists admin_hub_telemetry_read on public.call_telemetry;
create policy admin_hub_telemetry_read
  on public.call_telemetry for select to authenticated
  using (public.is_kolleru_admin());

grant select on public.user_profiles to authenticated;
grant select on public.drivers to authenticated;
grant select on public.load_requests to authenticated;
grant select on public.call_telemetry to authenticated;
revoke update, delete on public.user_profiles from anon, authenticated;

-- Provision a verified account only from trusted tooling, for example:
-- update public.user_profiles set role = 'admin'
-- where phone = '+91YOUR_ADMIN_NUMBER';
