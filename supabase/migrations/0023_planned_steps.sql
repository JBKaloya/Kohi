-- What was shown vs what happened. `steps` stays the actuals column.

alter table public.brews
  add column if not exists planned_steps jsonb not null default '[]'::jsonb,
  add column if not exists actual_source text not null default 'none'
    check (actual_source in ('timer','narration','edited','none'));
