-- The overall score in half points, on tastings and on brews: 1 is half a
-- dot, 10 is five. Additive. `rating` stays and is still written, rounded down
-- and never below 1, because builds before half points read only that column
-- and their decoders fail on a fractional value.
--
-- The app reads rating_halves only when it agrees with rating; when it does
-- not, an older build changed the score and rating wins. Existing rows keep
-- rating_halves null and read as rating * 2, so nothing is backfilled.

alter table public.tastings
  add column if not exists rating_halves smallint
  check (rating_halves is null or rating_halves between 1 and 10);

alter table public.brews
  add column if not exists rating_halves smallint
  check (rating_halves is null or rating_halves between 1 and 10);
