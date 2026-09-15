-- Kohi schema v1: coffee_cards + brews + Storage bucket
-- Applied to project zeplgxxxbqiehwidrvmm

-- coffee_cards -----------------------------------------------------------

create table public.coffee_cards (
  id              uuid primary key,
  user_id         uuid not null references auth.users on delete cascade,

  name            text not null default '',
  roaster         text not null default '',
  country         text not null default '',
  region          text not null default '',
  producer        text not null default '',
  altitude        text not null default '',
  variety         text not null default '',
  process         text not null default '',
  tasting_notes   text[] not null default '{}',
  brew_method     text check (brew_method in ('espresso','v60','filter','aeropress','moka','frenchPress','coldBrew')),
  personal_notes  text not null default '',

  species         text not null default 'arabica' check (species in ('arabica','robusta')),
  is_decaf        boolean not null default false,
  label_code      text,

  date            timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  aspect_ratio    double precision not null default 0.75,
  has_mask        boolean not null default false,
  enhanced        boolean not null default false,

  -- Place (embedded, not normalized)
  place_name      text,
  place_address   text,
  place_latitude  double precision,
  place_longitude double precision
);

alter table public.coffee_cards enable row level security;

create policy cards_owner on public.coffee_cards
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index coffee_cards_user_updated on public.coffee_cards (user_id, updated_at);

-- brews ------------------------------------------------------------------

create table public.brews (
  id                    uuid primary key,
  card_id               uuid not null references public.coffee_cards(id) on delete cascade,
  user_id               uuid not null references auth.users on delete cascade,

  date                  timestamptz not null default now(),
  method                text check (method in ('espresso','v60','filter','aeropress','moka','frenchPress','coldBrew')),

  dose                  double precision,
  water                 double precision,
  beverage              double precision,
  seconds               integer,
  grind                 text not null default '',
  temperature           double precision,

  tds                   double precision,
  rating                integer check (rating between 1 and 5),

  acidity               integer not null default 0 check (acidity between -1 and 1),
  bitterness            integer not null default 0 check (bitterness between -1 and 1),
  body                  integer not null default 0 check (body between -1 and 1),

  caffeine_override_mg  double precision,
  notes                 text not null default ''
);

alter table public.brews enable row level security;

create policy brews_owner on public.brews
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index brews_card on public.brews (card_id);

-- Storage bucket ---------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('cards', 'cards', false);

create policy cards_storage_select on storage.objects
  for select using (
    bucket_id = 'cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy cards_storage_insert on storage.objects
  for insert with check (
    bucket_id = 'cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy cards_storage_update on storage.objects
  for update using (
    bucket_id = 'cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy cards_storage_delete on storage.objects
  for delete using (
    bucket_id = 'cards'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
