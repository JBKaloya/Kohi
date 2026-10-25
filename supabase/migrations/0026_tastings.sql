-- Times a coffee was drunk. A brew stays a brew; a tasting only points at
-- one, or records a cup had out, with the score, the seven axes, the flavours
-- and the correction. Same shape as attachments: one jsonb array on the card,
-- not a table of its own.

alter table public.coffee_cards
  add column if not exists tastings jsonb not null default '[]'::jsonb;
