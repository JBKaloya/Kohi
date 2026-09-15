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
