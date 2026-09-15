-- Add poster state to coffee_cards.
-- Values: 'none', 'pending', 'ready', 'failed'.
alter table public.coffee_cards
  add column poster text not null default 'none';
