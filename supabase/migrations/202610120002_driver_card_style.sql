alter table public.drivers
  add column if not exists card_style text not null default 'classic_delta'
  check (card_style in ('classic_delta', 'aqua_marine', 'gold_elite'));
