-- Preserve the existing listed fleet; every new registration needs review.
alter table public.drivers add column verification_status text;
update public.drivers set verification_status = 'approved';
alter table public.drivers alter column verification_status set default 'pending';
alter table public.drivers alter column verification_status set not null;
alter table public.drivers add constraint driver_verification_status_check
  check (verification_status in ('pending', 'approved', 'rejected'));
alter table public.drivers add column reviewed_by uuid references auth.users(id) on delete set null;
alter table public.drivers add column reviewed_at timestamptz;
create index drivers_pending_review on public.drivers (updated_at) where verification_status = 'pending';

-- Admin review must preserve ownership. Owner upserts may never grant approval,
-- including the INSERT trigger that runs before ON CONFLICT DO UPDATE.
create or replace function public.stamp_kolleru_driver_owner()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.uid() is not null then
    if public.is_kolleru_admin() then
      if tg_op = 'UPDATE' then
        new.user_id := old.user_id;
        new.phone := old.phone;
      end if;
    else
      if public.kolleru_normalized_phone(new.phone) is distinct from
          public.kolleru_normalized_phone(auth.jwt()->>'phone') then
        raise exception 'Driver phone must match the verified session';
      end if;
      new.user_id := auth.uid();
      if tg_op = 'INSERT' then
        new.verification_status := 'pending';
        new.reviewed_by := null;
        new.reviewed_at := null;
      else
        new.verification_status := old.verification_status;
        new.reviewed_by := old.reviewed_by;
        new.reviewed_at := old.reviewed_at;
      end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.review_kolleru_driver(driver_id uuid, decision text)
returns void language plpgsql security definer set search_path = '' as $$
declare current_status text;
begin
  if auth.uid() is null or not public.is_kolleru_admin() then
    raise exception 'Admin authorization required' using errcode = '42501';
  end if;
  if decision is null or decision not in ('approved', 'rejected') then
    raise exception 'Invalid verification decision' using errcode = '22023';
  end if;
  select d.verification_status into current_status from public.drivers d
    where d.id = driver_id for update;
  if not found then raise exception 'Driver not found' using errcode = 'P0002'; end if;
  if current_status <> 'pending' then
    raise exception 'Driver has already been reviewed' using errcode = '40001';
  end if;
  update public.drivers d set verification_status = decision,
    reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
    where d.id = driver_id;
end;
$$;
revoke all on function public.review_kolleru_driver(uuid, text) from public, anon;
grant execute on function public.review_kolleru_driver(uuid, text) to authenticated;

-- Approval controls public discovery; owner recovery and admin access remain.
grant select (verification_status) on public.drivers to anon;
drop policy if exists guest_directory_boundary on public.drivers;
create policy guest_directory_boundary on public.drivers as restrictive
  for select to anon using (is_available and verification_status = 'approved');
drop policy if exists commercial_drivers_read_boundary on public.drivers;
create policy commercial_drivers_read_boundary on public.drivers as restrictive
for select to authenticated using (
  public.kolleru_role() = 'admin'
  or (public.kolleru_role() = 'shipper' and is_available and verification_status = 'approved')
  or ((public.kolleru_role() = 'driver' or public.kolleru_role() is null) and
    (user_id = auth.uid() or public.kolleru_normalized_phone(phone) =
      public.kolleru_normalized_phone(auth.jwt()->>'phone')))
);
-- Subscribe to both tables for admin updates. The 30-second poll remains a
-- fallback. RLS still determines which records a subscriber may receive.
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'drivers') then
      alter publication supabase_realtime add table public.drivers;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_telemetry') then
      alter publication supabase_realtime add table public.call_telemetry;
    end if;
  end if;
end $$;
