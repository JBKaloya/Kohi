-- A brew can be logged before its coffee is chosen, and linked to a card
-- later. Such a brew has no card_id and carries what was told about the
-- coffee in `coffee`, the same shape as tastings.coffee:
--   { name, roaster, roasterId, country, region, farm, variety, process,
--     tastingNotes, referenceID }
--
-- Additive for older builds: they only read brews through the card join,
-- which never returns a row without a card. Linking a brew sets card_id and
-- the app drops `coffee` from then on. A card's brews still go with the card.

alter table public.brews
  alter column card_id drop not null;

alter table public.brews
  add column if not exists coffee jsonb;

create index if not exists brews_loose
  on public.brews (user_id, updated_at)
  where card_id is null;
