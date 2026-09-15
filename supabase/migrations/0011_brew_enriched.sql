-- The brew stops being a bare recipe: what it was made with, what happened
-- during it, and what it tasted like.

alter table public.brews
  add column if not exists recipe_id            uuid references public.recipes on delete set null,
  -- Ids rather than names: renaming a grinder should not rewrite history, and
  -- an array beats a join table for a list that is read whole and never
  -- queried by member.
  add column if not exists equipment_ids        uuid[] not null default '{}',
  add column if not exists water_profile_id     uuid references public.water_profiles
                                                  on delete set null,
  -- [{ "index": 0, "action": "bloom", "at": 3, "mass": 60, "targetAt": 0 }]
  add column if not exists steps                jsonb not null default '[]'::jsonb,
  add column if not exists flow_gs              double precision,
  -- { "aroma": 4, "acidity": 3, "sweetness": 4, ... } — six axes, 1 to 5.
  -- A jsonb object rather than six columns: they are always read together and
  -- always written together, and a seventh axis should not cost a migration.
  add column if not exists taste                jsonb not null default '{}'::jsonb,
  add column if not exists flavors              text[] not null default '{}',
  add column if not exists next_time_suggestion text,
  add column if not exists capture_source       text;

alter table public.brews
  drop constraint if exists brews_capture_source_check;

alter table public.brews
  add constraint brews_capture_source_check
  check (capture_source is null or capture_source in
    ('typed','dictated','scanned','prefilled'));

-- What O4 is measured from: the share of brews that never touched a keyboard.
create index if not exists brews_capture_source on public.brews (user_id, capture_source);
