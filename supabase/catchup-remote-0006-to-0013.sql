-- Catch-up for the Kohi remote: migrations 0006 → 0013.
-- Paste once in the SQL editor. Safe to re-run (IF NOT EXISTS / DROP IF EXISTS).
-- Do not add this file to the numbered migration history.


-- ============================================================================ 
-- supabase/migrations/0006_on_the_bag.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- supabase/migrations/0007_roasters.sql
-- ============================================================================ 

-- The roaster index: shared reference data, not private archive.
--
-- Readable by every signed-in user, writable by anyone (that is the point —
-- one person adding Belleville spares everybody else the typing), and never
-- deleted from a client, because another archive may point at the row.

create table if not exists public.roasters (
  id          uuid primary key,
  name        text not null,
  country     text not null default '',
  city        text not null default '',
  website     text,
  instagram   text,
  created_by  uuid references auth.users on delete set null,
  updated_at  timestamptz not null default now(),

  -- Computed by the client (`Roaster.dedupeKey`) and stored so the unique
  -- index below can reject a duplicate the client did not catch — two devices
  -- adding the same roastery offline, most likely.
  dedupe_key  text not null
);

create unique index if not exists roasters_dedupe_key on public.roasters (dedupe_key);
create index if not exists roasters_updated_at on public.roasters (updated_at);

alter table public.roasters enable row level security;

drop policy if exists "roasters are readable by everyone" on public.roasters;
create policy "roasters are readable by everyone"
  on public.roasters for select
  to authenticated
  using (true);

drop policy if exists "signed-in users can add roasters" on public.roasters;
create policy "signed-in users can add roasters"
  on public.roasters for insert
  to authenticated
  with check (auth.uid() = created_by);

-- Anyone can correct an entry: a shared index that only its author can fix
-- goes stale. `created_by` is not reassignable, so authorship survives.
drop policy if exists "signed-in users can correct roasters" on public.roasters;
create policy "signed-in users can correct roasters"
  on public.roasters for update
  to authenticated
  using (true)
  with check (true);

-- Now that the table exists, point the card's column at it. Set null on delete
-- so losing a roaster entry never takes a card with it.
alter table public.coffee_cards
  drop constraint if exists coffee_cards_roaster_id_fkey;
alter table public.coffee_cards
  add constraint coffee_cards_roaster_id_fkey
  foreign key (roaster_id) references public.roasters(id) on delete set null;


-- ============================================================================ 
-- supabase/migrations/0008_setup.sql
-- ============================================================================ 

-- Setup: the cupboard and the tap. Private per account, like the archive.

create table if not exists public.equipment (
  id                      uuid primary key,
  user_id                 uuid not null references auth.users on delete cascade,

  kind                    text not null check (kind in
                            ('grinder','brewer','espressoMachine','kettle','scale','accessory')),
  brand                   text not null default '',
  model                   text not null default '',
  notes                   text not null default '',
  is_default_for          text[] not null default '{}',

  -- Grinder
  grinder_ref             text,
  burr_type               text check (burr_type is null or burr_type in ('conical','flat')),
  burr_mm                 double precision,
  adjustment              text check (adjustment is null or adjustment in
                            ('clicks','stepless','dial')),
  steps_per_rotation      integer,
  maker_microns_per_step  double precision,
  -- [{ "method": "v60", "low": 20, "high": 26 }]. A list read as a whole.
  ranges                  jsonb not null default '[]'::jsonb,

  -- Brewer
  brewer_type             text,
  filter_brand            text,
  filter_shape            text,

  -- Espresso machine
  basket_g                double precision,
  pressure_bar            double precision,

  -- Kettle
  is_gooseneck            boolean,
  has_temperature_control boolean,

  -- Scale
  resolution_g            double precision,
  has_timer               boolean,

  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create index if not exists equipment_user_updated on public.equipment (user_id, updated_at);

alter table public.equipment enable row level security;

drop policy if exists "equipment is private" on public.equipment;
create policy "equipment is private"
  on public.equipment for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Hardness and alkalinity are deliberately absent: they are computed from the
-- ions (annexe C1), and a stored copy is a second truth waiting to drift.
create table if not exists public.water_profiles (
  id             uuid primary key,
  user_id        uuid not null references auth.users on delete cascade,

  name           text not null default '',
  source         text not null check (source in ('tap','filtered','bottled','recipe')),
  tds            double precision,
  calcium        double precision,
  magnesium      double precision,
  sodium         double precision,
  bicarbonate    double precision,
  additive_name  text,
  additive_dose  text,
  notes          text not null default '',
  is_default     boolean not null default false,
  water_ref      text,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists water_profiles_user_updated
  on public.water_profiles (user_id, updated_at);

alter table public.water_profiles enable row level security;

drop policy if exists "water profiles are private" on public.water_profiles;
create policy "water profiles are private"
  on public.water_profiles for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ============================================================================ 
-- supabase/migrations/0009_recipes.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- supabase/migrations/0010_grind_calibrations.sql
-- ============================================================================ 

-- "My 22 clicks is your 700 µm": one observed pair, per grinder and method.
-- The collective version of this table — pairs from many users, weighted by
-- rating — is v2. This one is yours alone.

create table if not exists public.grind_calibrations (
  id             uuid primary key,
  user_id        uuid not null references auth.users on delete cascade,

  grinder_id     uuid not null references public.equipment on delete cascade,
  method         text not null,
  setting        double precision not null,
  microns_proxy  double precision,
  note           text not null default '',

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- One answer per question. The app enforces this too; the constraint is what
  -- makes it true after a two-device race.
  unique (user_id, grinder_id, method)
);

create index if not exists grind_calibrations_user_updated
  on public.grind_calibrations (user_id, updated_at);

alter table public.grind_calibrations enable row level security;

drop policy if exists "calibrations are private" on public.grind_calibrations;
create policy "calibrations are private"
  on public.grind_calibrations for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ============================================================================ 
-- supabase/migrations/0011_brew_enriched.sql
-- ============================================================================ 

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


-- ============================================================================ 
-- supabase/migrations/0012_ai.sql
-- ============================================================================ 

-- The experimental layer: what the models are allowed to do, what they were
-- asked, and whether the answer was kept.

-- One row per feature. Absent means enabled: a flags table that fails to load
-- must not silently kill the app, and a feature nobody has thought about yet
-- should not be off by accident.
create table if not exists public.ai_flags (
  feature     text primary key,
  enabled     boolean not null default true,
  note        text not null default '',
  updated_at  timestamptz not null default now()
);

insert into public.ai_flags (feature, note) values
  ('card-vision',   'Reads a label the on-device parse could not.'),
  ('field-extract', 'Turns a dictated phrase into fields.'),
  ('recipe-adapt',  'Offers a variant under the rules-based recipe.'),
  ('ask',           'Answers from the curated base, with citations.'),
  ('card-poster',   'Generates the flyer.')
on conflict (feature) do nothing;

alter table public.ai_flags enable row level security;

-- Readable by anyone signed in, writable only from the dashboard or a service
-- role: a kill switch the client can flip is not a kill switch.
create policy "ai_flags are readable by everyone"
  on public.ai_flags for select
  to authenticated
  using (true);

-- One row per call to a model.
create table if not exists public.ai_events (
  id             uuid primary key,
  user_id        uuid not null references auth.users on delete cascade,

  feature        text not null,
  model          text not null,
  input_tokens   integer,
  output_tokens  integer,
  latency_ms     integer not null,
  -- Null until answered. This is the column the experiment is actually about:
  -- cost is easy to measure and easy to ignore, kept-or-not is not.
  accepted       boolean,
  failure        text,

  created_at     timestamptz not null default now()
);

create index if not exists ai_events_feature on public.ai_events (feature, created_at desc);
create index if not exists ai_events_user on public.ai_events (user_id, created_at desc);

alter table public.ai_events enable row level security;

create policy "ai_events are private"
  on public.ai_events for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- The curated base behind `ask`. Entries are written by hand from the PRD
-- annexes; nothing scraped, nothing generated, every row with a source.
create table if not exists public.knowledge (
  id          text primary key,
  topic       text not null,
  title       text not null,
  body        text not null,
  -- Where it comes from, named well enough to be checked: "Hoffmann, The
  -- Ultimate V60 Technique (2019)".
  source      text not null,
  source_url  text,
  -- 'verified' entries are the only ones served. The gate is editorial, and
  -- it lives in the data rather than in a prompt.
  evidence    text not null default 'verified',
  updated_at  timestamptz not null default now()
);

alter table public.knowledge
  add column if not exists search tsvector
  generated always as (
    to_tsvector('english', title || ' ' || body)
  ) stored;

create index if not exists knowledge_search on public.knowledge using gin (search);
create index if not exists knowledge_topic on public.knowledge (topic);

alter table public.knowledge enable row level security;

create policy "knowledge is readable by everyone"
  on public.knowledge for select
  to authenticated
  using (evidence = 'verified');


-- ============================================================================ 
-- supabase/migrations/0013_lot2.sql
-- ============================================================================ 

-- Lot 2: grind as a setting, agitation, filter, flavour tags, card product URL.

alter table public.brews
  add column if not exists grind_grinder_id uuid,
  add column if not exists grind_value       double precision,
  add column if not exists grind_raw         text,
  add column if not exists agitation          text,
  add column if not exists filter_id         uuid,
  add column if not exists legacy_taste     jsonb,
  add column if not exists flavor_tags      jsonb not null default '[]'::jsonb;

alter table public.brews
  drop constraint if exists brews_agitation_check;

alter table public.brews
  add constraint brews_agitation_check
  check (agitation is null or agitation in
    ('none','swirl','stir','wdt','pulse'));

alter table public.equipment
  add column if not exists filters           jsonb not null default '[]'::jsonb,
  add column if not exists default_filter_id uuid;

alter table public.coffee_cards
  add column if not exists product_url   text,
  add column if not exists decaf_method  text,
  add column if not exists farm            text,
  add column if not exists wash_station   text;

alter table public.coffee_cards
  drop constraint if exists coffee_cards_decaf_method_check;

alter table public.coffee_cards
  add constraint coffee_cards_decaf_method_check
  check (decaf_method is null or decaf_method in
    ('swissWater','co2','sugarcaneEA','mountainWater','other'));

