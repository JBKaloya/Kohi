-- Testers compare the narration pipelines on their own brews: every
-- pipeline hears the same note, the versions are shown blind and shuffled,
-- and the tester picks the one closest to what they said, or none, and says
-- what they would change.
--
-- candidates: one object per version shown, the iPhone's included:
--   { pipeline, ok, model, transcript, steps, latency_ms, cost_usd, failure }
-- shown_order: the pipelines in the order they were shown, "Version 1" first.
-- chosen: the pipeline picked; null when skipped or when none was right.
--
-- No foreign key on dictation_id or brew_id, for the same reasons as
-- public.dictations.

create table if not exists public.narration_trials (
  id            uuid primary key,
  user_id       uuid not null references auth.users on delete cascade,
  dictation_id  uuid,
  brew_id       uuid,
  duration_s    double precision not null default 0,
  candidates    jsonb not null default '[]'::jsonb,
  shown_order   jsonb not null default '[]'::jsonb,
  chosen        text,
  none_right    boolean not null default false,
  skipped       boolean not null default false,
  comment       text not null default '',
  app_build     text,
  created_at    timestamptz not null default now()
);

create index if not exists narration_trials_user on public.narration_trials (user_id, created_at desc);

alter table public.narration_trials enable row level security;

create policy "narration trials are private"
  on public.narration_trials for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

insert into public.ai_flags (feature, note) values
  ('narration-compare', 'Testers compare every narration pipeline on their brews.')
on conflict (feature) do nothing;
