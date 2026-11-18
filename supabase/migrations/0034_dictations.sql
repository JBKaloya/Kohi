-- Every brew dictation, kept to learn from: the audio in a private bucket,
-- and a row with what Speech heard (timestamped words), what the parser
-- read, and the steps the brewer kept once the brew was saved.
--
-- Sent only while "Share dictations to improve Kohi" is on (on by default).
-- Each user reads and writes their own; analysis runs with the service key.
-- No foreign key on brew_id or recipe_id: a dictation can land before its
-- brew, and must outlive a deleted one.

insert into storage.buckets (id, name, public)
values ('dictations', 'dictations', false)
on conflict (id) do nothing;

create policy dictations_storage_select on storage.objects
  for select using (
    bucket_id = 'dictations'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy dictations_storage_insert on storage.objects
  for insert with check (
    bucket_id = 'dictations'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy dictations_storage_update on storage.objects
  for update using (
    bucket_id = 'dictations'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy dictations_storage_delete on storage.objects
  for delete using (
    bucket_id = 'dictations'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create table if not exists public.dictations (
  id            uuid primary key,
  user_id       uuid not null references auth.users on delete cascade,
  brew_id       uuid,
  recipe_id     uuid,
  context       text not null check (context in ('live', 'after_brew')),
  audio_path    text not null,
  duration_s    double precision not null default 0,
  locale        text,
  transcript    text not null default '',
  phrases       jsonb not null default '[]'::jsonb,
  parsed        jsonb not null default '{}'::jsonb,
  steps_heard   integer not null default 0,
  edited_steps  jsonb,
  app_build     text,
  created_at    timestamptz not null default now()
);

create index if not exists dictations_user on public.dictations (user_id, created_at desc);
create index if not exists dictations_context on public.dictations (context, created_at desc);

alter table public.dictations enable row level security;

create policy "dictations are private"
  on public.dictations for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
