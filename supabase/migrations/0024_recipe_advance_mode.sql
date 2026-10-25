-- How a recipe moves through its steps. Local recipes.json already stores this;
-- the column keeps Cues from disappearing on a sync round trip.
-- auto_advance stays, and means the same thing as advance_mode = 'auto'.

alter table public.recipes
  add column if not exists advance_mode text;

update public.recipes
  set advance_mode = case when auto_advance is true then 'auto' else 'manual' end
  where advance_mode is null;

alter table public.recipes
  alter column advance_mode set default 'manual';

alter table public.recipes
  drop constraint if exists recipes_advance_mode_check;

alter table public.recipes
  add constraint recipes_advance_mode_check
  check (advance_mode in ('auto', 'manual', 'cues'));
