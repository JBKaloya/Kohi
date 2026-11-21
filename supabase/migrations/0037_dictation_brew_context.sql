-- The coffee and the water the brewer set before recording, kept next to
-- the audio. A later batch gives the models the same facts. Absent on a
-- dictation made before this column: an empty object.

alter table public.dictations
  add column if not exists brew_context jsonb not null default '{}'::jsonb;

update public.dictations as dictation
set brew_context = jsonb_strip_nulls(jsonb_build_object(
  'dose', brew.dose,
  'water', brew.water,
  'method', brew.method,
  'coffee', card.name
))
from public.brews as brew
left join public.coffee_cards as card on card.id = brew.card_id
where dictation.brew_id = brew.id
  and dictation.brew_context = '{}'::jsonb;
