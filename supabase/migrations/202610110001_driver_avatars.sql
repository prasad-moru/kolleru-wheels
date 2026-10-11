alter table public.drivers
  add column if not exists avatar_url text;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'driver-avatars',
  'driver-avatars',
  true,
  5242880,
  array['image/jpeg']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Drivers upload their own avatar"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'driver-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Drivers replace their own avatar"
on storage.objects for update to authenticated
using (
  bucket_id = 'driver-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'driver-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);
