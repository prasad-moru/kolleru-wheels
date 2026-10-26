-- Preserve the typed village/cluster while village_id remains a stable mandal routing locality.
alter table public.user_profiles add column if not exists base_location text
  check (base_location is null or char_length(btrim(base_location)) between 2 and 80);
alter table public.drivers add column if not exists base_location text
  check (base_location is null or char_length(btrim(base_location)) between 2 and 80);
-- Existing RLS ownership policies apply to the new column.
grant insert(base_location) on public.user_profiles to authenticated;
grant select(base_location) on public.drivers to anon;
