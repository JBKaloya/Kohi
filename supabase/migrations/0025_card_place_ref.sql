-- Optional slug of a bundled place (the Paris catalogue ships in the app).
-- Not a foreign key: a closed café has to keep resolving after it leaves the
-- picker, and the row is not in Postgres.

alter table public.coffee_cards
  add column if not exists place_ref text;
