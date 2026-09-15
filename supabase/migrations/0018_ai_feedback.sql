-- AI feedback (four-level usefulness) and water recipe fields.

create table if not exists public.ai_feedback (
  id           uuid primary key,
  user_id      uuid not null references auth.users on delete cascade,
  ai_event_id  uuid,
  feature      text not null,
  score        integer not null check (score between 1 and 4),
  comment      text,
  created_at   timestamptz not null default now()
);

create index if not exists ai_feedback_user on public.ai_feedback (user_id, created_at desc);

alter table public.ai_feedback enable row level security;

create policy "ai_feedback is private"
  on public.ai_feedback for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

insert into public.ai_flags (feature, note) values
  ('suggested-correction', 'Ranks three moves from the admissible set.'),
  ('ai-feedback', 'Four-level usefulness under every model output.')
on conflict (feature) do nothing;

alter table public.water_profiles
  add column if not exists mineral_product_id text,
  add column if not exists filtration_system text,
  add column if not exists water_base text;
