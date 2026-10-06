-- Apply in Supabase SQL editor/migration tooling before enabling phone sign-in.
-- Roles are authoritative server records; clients cannot promote themselves.
create table if not exists public.user_profiles (
  phone text primary key,
  user_id uuid unique not null references auth.users(id) on delete cascade,
  role text not null check (role in ('driver', 'shipper', 'admin')),
  name text not null default ''
);
alter table public.user_profiles enable row level security;

create or replace function public.is_kolleru_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.user_profiles
    where user_id = auth.uid() and role = 'admin');
$$;
revoke all on function public.is_kolleru_admin() from public;
grant execute on function public.is_kolleru_admin() to authenticated;

create policy profiles_read_self_or_admin on public.user_profiles for select to authenticated
  using (user_id = auth.uid() or public.is_kolleru_admin());
revoke all on public.user_profiles from anon, authenticated;
grant select on public.user_profiles to authenticated;
grant all on public.user_profiles to service_role;

create or replace function public.create_kolleru_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.phone is not null then
    insert into public.user_profiles(phone,user_id,role)
      values ('+' || ltrim(new.phone, '+'), new.id,
        case when new.raw_user_meta_data->>'role' = 'driver' then 'driver' else 'shipper' end)
      on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.create_kolleru_profile() from public;
create trigger on_kolleru_phone_user after insert on auth.users
  for each row execute function public.create_kolleru_profile();
-- Backfill existing phone accounts without trusting any client-supplied admin role.
insert into public.user_profiles(phone,user_id,role)
select '+' || ltrim(phone, '+'), id,
  case when raw_user_meta_data->>'role' = 'driver' then 'driver' else 'shipper' end
from auth.users where phone is not null
on conflict (user_id) do nothing;

create table if not exists public.call_telemetry (
  id uuid primary key default gen_random_uuid(),
  caller_phone text,
  receiver_phone text not null check (length(receiver_phone) <= 24),
  caller_role text not null default 'guest' check (caller_role in ('guest','driver','shipper','admin')),
  context_note text not null default 'directory' check (length(context_note) <= 250),
  created_at timestamptz not null default now()
);
create index if not exists call_telemetry_recent on public.call_telemetry(created_at desc);
alter table public.call_telemetry enable row level security;

create or replace function public.stamp_kolleru_call()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.created_at := now();
  new.caller_phone := null;
  new.caller_role := 'guest';
  if auth.uid() is not null then
    select phone, role into new.caller_phone, new.caller_role
      from public.user_profiles where user_id = auth.uid();
    new.caller_role := coalesce(new.caller_role, 'guest');
  end if;
  return new;
end;
$$;
revoke all on function public.stamp_kolleru_call() from public;
create trigger stamp_call_intent before insert on public.call_telemetry
  for each row execute function public.stamp_kolleru_call();
create policy calls_insert on public.call_telemetry for insert to anon, authenticated with check (true);
create policy calls_admin_read on public.call_telemetry for select to authenticated
  using (public.is_kolleru_admin());
revoke all on public.call_telemetry from anon, authenticated;
grant insert (caller_phone, receiver_phone, caller_role, context_note) on public.call_telemetry to anon, authenticated;
grant select on public.call_telemetry to authenticated;
grant all on public.call_telemetry to service_role;

-- Supplement existing directory policies to allow admins to count busy/closed rows.
create policy drivers_admin_read on public.drivers for select to authenticated
  using (public.is_kolleru_admin());
create policy loads_admin_read on public.load_requests for select to authenticated
  using (public.is_kolleru_admin());
-- Provision admin roles only via trusted SQL/service-role tooling after OTP signup.
-- No client role-update grant, admin role chip, or secret tap bypass is provided.
