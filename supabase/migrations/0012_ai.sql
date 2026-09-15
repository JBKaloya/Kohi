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
