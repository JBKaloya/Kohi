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
