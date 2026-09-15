-- Add attachments column to coffee_cards
-- Stores CardAttachment objects as JSONB array

alter table public.coffee_cards
  add column attachments jsonb not null default '[]'::jsonb;
