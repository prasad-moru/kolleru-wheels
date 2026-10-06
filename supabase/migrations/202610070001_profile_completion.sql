-- Follow the auth/telemetry migration. New phone accounts complete their own profile.
drop trigger if exists on_kolleru_phone_user on auth.users;
create policy profiles_create_self on public.user_profiles for insert to authenticated
with check (
  user_id = auth.uid()
  and phone = '+' || ltrim(auth.jwt()->>'phone', '+')
  and role in ('driver', 'shipper')
  and length(trim(name)) between 2 and 80
);
grant insert (phone, user_id, role, name) on public.user_profiles to authenticated;
-- Keep existing SELECT policies. No client UPDATE grant or admin signup is added.
