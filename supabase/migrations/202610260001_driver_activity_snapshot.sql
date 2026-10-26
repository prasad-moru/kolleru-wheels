-- Driver cockpit: scoped inquiry metrics. No raw telemetry read policy is broadened.
create index if not exists call_telemetry_receiver_recent_idx
  on public.call_telemetry(receiver_phone, created_at desc);

create or replace function public.driver_activity_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  driver_phone text;
  day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  result jsonb;
begin
  select p.phone into driver_phone
    from public.user_profiles p
    where p.user_id = auth.uid() and p.role = 'driver'
      and p.phone = '+' || ltrim(auth.jwt()->>'phone', '+');
  if driver_phone is null then
    raise exception 'Driver identity required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'calls_today', (
      select count(*) from public.call_telemetry c
      where c.receiver_phone = driver_phone and c.caller_role = 'shipper'
        and c.created_at >= day_start and c.created_at < day_start + interval '1 day'
        and c.created_at <= now()
    ),
    'recent_calls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', recent.id,
        'created_at', recent.created_at,
        'caller_village_id', recent.village_id,
        'location', null,
        'load_detail', null
      ) order by recent.created_at desc, recent.id desc)
      from (
        select c.id, c.created_at, p.village_id
        from public.call_telemetry c
        left join public.user_profiles p on p.phone = c.caller_phone
        where c.receiver_phone = driver_phone and c.caller_role = 'shipper'
          and c.created_at >= now() - interval '30 days' and c.created_at <= now()
        order by c.created_at desc, c.id desc limit 50
      ) recent
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;
revoke all on function public.driver_activity_snapshot() from public, anon;
grant execute on function public.driver_activity_snapshot() to authenticated;
