-- Size a brew was shown at when it was created from a recipe.
alter table public.brews
  add column if not exists scale text;

alter table public.brews
  drop constraint if exists brews_scale_check;

alter table public.brews
  add constraint brews_scale_check
  check (scale is null or scale in ('cup', 'twoCups', 'batch'));
