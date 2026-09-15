-- Recipes you saved. The bundled reference recipes ship with the app and are
-- deliberately absent: they are the same on every device and have no owner.

create table if not exists public.recipes (
  id                  uuid primary key,
  user_id             uuid not null references auth.users on delete cascade,

  name                text not null default '',
  method              text not null,
  dose                double precision,
  water               double precision,
  beverage            double precision,
  temperature         double precision,
  temperature_max     double precision,
  seconds             integer,
  grind_label         text not null default '',
  grind_microns_low   double precision,
  grind_microns_high  double precision,
  -- [{ "at": 45, "action": "pour", "targetMass": 300 }]
  steps               jsonb not null default '[]'::jsonb,
  source              text not null default 'mine'
                        check (source in ('card','reference','mine','adapted')),
  evidence            text not null default 'practice'
                        check (evidence in ('verified','partial','practice')),
  attribution         text not null default '',
  source_url          text,
  notes               text not null default '',
  -- The coffee and the brew this was saved from, kept for provenance. Nulled
  -- rather than cascaded: deleting a card should not delete a recipe that has
  -- since been used on five others.
  card_id             uuid references public.coffee_cards on delete set null,
  brew_id             uuid,
  reference_id        text,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists recipes_user_updated on public.recipes (user_id, updated_at);

alter table public.recipes enable row level security;

drop policy if exists "recipes are private" on public.recipes;
create policy "recipes are private"
  on public.recipes for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
