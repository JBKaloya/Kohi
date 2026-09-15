-- What the packaging says beyond the origin story.
--
-- Every column is nullable: a card that prints none of this is still a card.
-- `roaster_id` has no foreign key yet — the roasters table arrives in the next
-- migration, and the app can already match a card to one by then.

alter table public.coffee_cards
  add column if not exists roaster_id    uuid,
  add column if not exists place_type    text,
  add column if not exists roast_level   text,
  add column if not exists agtron        integer,
  add column if not exists roasted_on    timestamptz,
  add column if not exists harvest        text,
  add column if not exists cupping_score double precision,
  add column if not exists price         double precision,
  add column if not exists currency      text,
  add column if not exists bag_weight_g  double precision,
  add column if not exists lot           text;

-- Closed vocabularies are checked, so a typo from a future client is rejected
-- at the door rather than becoming a silent third value.
alter table public.coffee_cards
  drop constraint if exists coffee_cards_roast_level_check;
alter table public.coffee_cards
  add constraint coffee_cards_roast_level_check
  check (roast_level is null or roast_level in
    ('light','mediumLight','medium','mediumDark','dark'));

alter table public.coffee_cards
  drop constraint if exists coffee_cards_place_type_check;
alter table public.coffee_cards
  add constraint coffee_cards_place_type_check
  check (place_type is null or place_type in ('roastery','cafe','shop','online'));

alter table public.coffee_cards
  drop constraint if exists coffee_cards_agtron_check;
alter table public.coffee_cards
  add constraint coffee_cards_agtron_check
  check (agtron is null or agtron between 0 and 120);

alter table public.coffee_cards
  drop constraint if exists coffee_cards_cupping_score_check;
alter table public.coffee_cards
  add constraint coffee_cards_cupping_score_check
  check (cupping_score is null or cupping_score between 0 and 100);

create index if not exists coffee_cards_roaster_id on public.coffee_cards (roaster_id);
