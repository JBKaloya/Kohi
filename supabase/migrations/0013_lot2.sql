-- Lot 2: grind as a setting, agitation, filter, flavour tags, card product URL.

alter table public.brews
  add column if not exists grind_grinder_id uuid,
  add column if not exists grind_value       double precision,
  add column if not exists grind_raw         text,
  add column if not exists agitation          text,
  add column if not exists filter_id         uuid,
  add column if not exists legacy_taste     jsonb,
  add column if not exists flavor_tags      jsonb not null default '[]'::jsonb;

alter table public.brews
  drop constraint if exists brews_agitation_check;

alter table public.brews
  add constraint brews_agitation_check
  check (agitation is null or agitation in
    ('none','swirl','stir','wdt','pulse'));

alter table public.equipment
  add column if not exists filters           jsonb not null default '[]'::jsonb,
  add column if not exists default_filter_id uuid;

alter table public.coffee_cards
  add column if not exists product_url   text,
  add column if not exists decaf_method  text,
  add column if not exists farm            text,
  add column if not exists wash_station   text;

alter table public.coffee_cards
  drop constraint if exists coffee_cards_decaf_method_check;

alter table public.coffee_cards
  add constraint coffee_cards_decaf_method_check
  check (decaf_method is null or decaf_method in
    ('swissWater','co2','sugarcaneEA','mountainWater','other'));
