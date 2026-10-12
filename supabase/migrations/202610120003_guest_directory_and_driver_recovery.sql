-- Restore existing drivers by auth UID or verified phone. Preserve phone conflict writes.
create or replace function public.kolleru_normalized_phone(value text)
returns text language sql immutable set search_path = '' as $$
  select case
    when digits ~ '^[6-9][0-9]{9}$' then '+91' || digits
    when digits ~ '^91[6-9][0-9]{9}$' then '+' || digits
    else null end
  from (select regexp_replace(value, '[^0-9]', '', 'g') as digits) p;
$$;
revoke all on function public.kolleru_normalized_phone(text) from public;
grant execute on function public.kolleru_normalized_phone(text) to authenticated;

-- Canonicalize unambiguous legacy rows without merging or deleting duplicates.
update public.drivers d set phone = public.kolleru_normalized_phone(d.phone)
where public.kolleru_normalized_phone(d.phone) is not null
  and d.phone <> public.kolleru_normalized_phone(d.phone)
  and not exists (select 1 from public.drivers other
    where other.id <> d.id and public.kolleru_normalized_phone(other.phone) =
      public.kolleru_normalized_phone(d.phone));

alter table public.drivers
  add column if not exists user_id uuid references auth.users(id) on delete set null;
alter table public.drivers alter column user_id set default auth.uid();
create index if not exists drivers_user_id_lookup on public.drivers(user_id);
update public.drivers d set user_id = p.user_id
from public.user_profiles p
where d.user_id is null and p.role = 'driver'
  and public.kolleru_normalized_phone(d.phone) = p.phone;

-- Auth UIDs are stamped by the server, never trusted from a client payload.
create or replace function public.stamp_kolleru_driver_owner()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.uid() is not null then
    if public.kolleru_normalized_phone(new.phone) is distinct from
        public.kolleru_normalized_phone(auth.jwt()->>'phone') then
      raise exception 'Driver phone must match the verified session';
    end if;
    new.user_id := auth.uid();
  end if;
  return new;
end;
$$;
revoke all on function public.stamp_kolleru_driver_owner() from public;
create trigger stamp_driver_owner before insert or update on public.drivers
for each row execute function public.stamp_kolleru_driver_owner();

create policy driver_identity_read on public.drivers for select to authenticated
using ((public.kolleru_role() = 'driver' or public.kolleru_role() is null)
  and (user_id = auth.uid() or public.kolleru_normalized_phone(phone) =
    public.kolleru_normalized_phone(auth.jwt()->>'phone')));
-- Replace the restrictive read boundary so UID ownership can recover legacy rows.
drop policy if exists commercial_drivers_read_boundary on public.drivers;
create policy commercial_drivers_read_boundary on public.drivers as restrictive
for select to authenticated using (
  public.kolleru_role() = 'admin'
  or (public.kolleru_role() = 'shipper' and is_available)
  or ((public.kolleru_role() = 'driver' or public.kolleru_role() is null) and
    (user_id = auth.uid() or public.kolleru_normalized_phone(phone) =
      public.kolleru_normalized_phone(auth.jwt()->>'phone')))
);

-- Public discovery exposes only available directory fields, never auth UIDs.
grant select (id, phone, name, base_village_id, current_spot_village_id,
  vehicle_type, capacity_tons, vehicle_number, specializations, is_available,
  avatar_url, card_style, updated_at) on public.drivers to anon;
create policy guest_directory_read on public.drivers for select to anon
using (is_available);
create policy guest_directory_boundary on public.drivers as restrictive
for select to anon using (is_available);

-- Existing stamp_kolleru_call trigger supplies null caller phone and guest role.
grant insert (caller_phone, receiver_phone, caller_role, context_note)
  on public.call_telemetry to anon;
create policy guest_calls_boundary on public.call_telemetry as restrictive
for insert to anon with check (caller_phone is null and caller_role = 'guest');
-- Load posting, private user profiles, and account mutations stay authenticated.
