-- Recipe profile chips, the author's grinder, auto-advance, and a brewer
-- reference into the dripper seed.

alter table public.recipes
  add column if not exists profile_tags text[] not null default '{}',
  add column if not exists author_grinder text,
  add column if not exists auto_advance boolean not null default false;

alter table public.equipment
  add column if not exists brewer_ref text;
