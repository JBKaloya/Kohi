-- Catch up values the app already writes, plus the express recipe source.
-- `superLight` was added to RoastLevel after 0006 sealed the check.
-- `ai` / `unverified` drifted in the model; `express` is new.

alter table public.coffee_cards
  drop constraint if exists coffee_cards_roast_level_check;
alter table public.coffee_cards
  add constraint coffee_cards_roast_level_check
  check (roast_level is null or roast_level in
    ('superLight','light','mediumLight','medium','mediumDark','dark'));

alter table public.recipes
  drop constraint if exists recipes_source_check;
alter table public.recipes
  add constraint recipes_source_check
  check (source in ('card','reference','mine','adapted','ai','express'));

alter table public.recipes
  drop constraint if exists recipes_evidence_check;
alter table public.recipes
  add constraint recipes_evidence_check
  check (evidence in ('verified','partial','practice','unverified'));
