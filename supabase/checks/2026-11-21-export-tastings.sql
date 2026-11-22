-- Read-only. One tester's tastings, as the JSON scripts/compare-real.ts reads.
--
-- 1. Put the account id from 2026-11-21-testers.sql in place of the zeros.
-- 2. Run it in the dashboard SQL editor; it returns one row.
-- 3. Copy the `export` cell into .private/tastings.json (.private/ is
--    ignored by git; the file never leaves this Mac).
--
-- Only what a comparison needs: the coffee's name, roaster, origin and
-- process, the place's name, the date, the seven axes, the flavours and the
-- rating. No address, coordinates, price, note or photo.

with tester as (
  select '00000000-0000-0000-0000-000000000000'::uuid as id
)
select count(*) as tastings,
       json_agg(json_build_object(
         'id', t.id,
         'tasted_at', t.tasted_at,
         'coffee', json_build_object(
           'name', t.coffee ->> 'name',
           'roaster', t.coffee ->> 'roaster',
           'country', t.coffee ->> 'country',
           'process', t.coffee ->> 'process'
         ),
         'place', t.place ->> 'name',
         'taste', t.taste,
         'flavors', t.flavors,
         'rating', t.rating,
         'rating_halves', t.rating_halves
       ) order by t.tasted_at) as export
from public.tastings t
join tester on t.user_id = tester.id
where t.deleted_at is null;
