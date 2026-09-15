-- A brew may follow a bundled reference recipe that does not live in
-- public.recipes. recipe_id stays a FK to the user's own recipes; recipe_ref
-- names a bundled one (`ref:a1-v60-ultimate`); recipe_snapshot keeps the numbers
-- as they were when the cup was made.

alter table public.brews
  add column if not exists recipe_ref text,
  add column if not exists recipe_snapshot jsonb;

comment on column public.brews.recipe_ref is
  'Bundled reference recipe key, e.g. ref:a1-v60-ultimate. Distinct from recipe_id.';
comment on column public.brews.recipe_snapshot is
  'Parameters and steps at brew time, durable if the recipe later changes.';
