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
