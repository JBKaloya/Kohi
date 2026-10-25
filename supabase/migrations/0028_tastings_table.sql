-- Coffee-shop tastings, as their own records.
--
-- They used to live in coffee_cards.tastings (0026). That column stays as it
-- is: older builds still read it, and the app lifts its entries into this
-- table with the same ids. Deletes are soft (deleted_at) so a legacy copy that
-- is still on a card is never imported a second time on another device.

create table if not exists public.tastings (
  id             uuid primary key,
  user_id        uuid not null references auth.users on delete cascade,
  -- Navigational only: the tasting carries its own coffee snapshot. Deleting
  -- the card keeps the tasting.
  card_id        uuid references public.coffee_cards on delete set null,
  tasted_at      timestamptz not null,

  -- { name, roaster, roasterId, country, region, farm, variety, process,
  --   tastingNotes, referenceID }
  coffee         jsonb not null default '{}'::jsonb,
  -- { name, address, latitude, longitude, mapItemID, city, country }
  place          jsonb,
  -- Seed slug of a bundled place.
  place_ref      text,
  place_map_id   text,

  -- No check: the app validates through BrewMethod, so a new method never
  -- needs a constraint migration.
  method         text,
  brewer         text,
  is_batch       boolean not null default false,
  method_note    text,
  price_amount   numeric(10,2),
  price_currency char(3),

  rating         smallint check (rating between 1 and 5),
  taste          jsonb not null default '{}'::jsonb,
  flavors        jsonb not null default '[]'::jsonb,
  -- The card-era context and correction axes, kept verbatim.
  legacy         jsonb,
  note           text,
  photos         jsonb not null default '[]'::jsonb,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,

  check (price_amount is null or price_currency is not null)
);

create index if not exists tastings_user_updated on public.tastings (user_id, updated_at);
create index if not exists tastings_user_card on public.tastings (user_id, card_id);
create index if not exists tastings_user_place on public.tastings (user_id, place_ref);

alter table public.tastings enable row level security;

drop policy if exists "tastings are private" on public.tastings;
create policy "tastings are private"
  on public.tastings for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Reading a café menu from its OCR text, behind its own switch.
insert into public.ai_flags (feature, note) values
  ('menu-extract', 'Reads a café menu into coffees, from its OCR text only.')
on conflict (feature) do nothing;
