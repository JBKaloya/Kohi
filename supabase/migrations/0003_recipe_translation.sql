-- Recipe suggestions read off the card, and original text kept when fields
-- were translated to English.

alter table public.coffee_cards
  add column recipe_suggestion jsonb,
  add column source_language   text,
  add column original_fields   jsonb not null default '{}'::jsonb;
