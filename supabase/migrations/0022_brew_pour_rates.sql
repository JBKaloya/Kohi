-- Snapshot of the recipe name at brew time, and per-pour rates from actuals.

alter table public.brews
  add column if not exists recipe_name text,
  add column if not exists pour_rates jsonb not null default '[]'::jsonb;
