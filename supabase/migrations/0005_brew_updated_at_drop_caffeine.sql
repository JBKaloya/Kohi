-- Brews get their own audit timestamp, and the caffeine estimate leaves the app.
--
-- The app never sends `brews.updated_at`: the trigger owns it. Cards are the
-- opposite — `coffee_cards.updated_at` comes from the client, because the pull
-- compares it against the local clock to resolve conflicts. Do not add a
-- trigger there.

alter table public.brews
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists brews_touch_updated_at on public.brews;

create trigger brews_touch_updated_at
  before insert or update on public.brews
  for each row execute function public.touch_updated_at();

create index if not exists brews_user_updated on public.brews (user_id, updated_at);

-- Caffeine estimation is gone from the product. The column stays nullable and
-- unread so existing rows still decode; nothing writes it any more.
comment on column public.brews.caffeine_override_mg is
  'Deprecated 2026-09 (caffeine estimate removed from the app). Unused.';
