-- Owned paper filters, private per account. Mirrors 0008_setup.sql.

create table if not exists public.filter_stock (
  id              uuid primary key,
  user_id         uuid not null references auth.users on delete cascade,

  model_id        text,
  custom_name     text,
  size            text not null default '',
  origin          text,
  shape           text,
  is_default_for  uuid[] not null default '{}',

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists filter_stock_user_updated
  on public.filter_stock (user_id, updated_at);

alter table public.filter_stock enable row level security;

drop policy if exists "filter stock is private" on public.filter_stock;
create policy "filter stock is private"
  on public.filter_stock for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.equipment
  add column if not exists size text,
  add column if not exists accepts_filter_shapes text[] not null default '{}';
