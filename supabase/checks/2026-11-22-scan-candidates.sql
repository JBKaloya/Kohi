-- Read-only. Coffees whose photos can serve the scan benchmark
-- (scripts/scan-bench.ts, KohiTests/ScanBenchmarkTests): every card with its
-- photo in the `cards` bucket, the ones with other sides first, and what the
-- card holds today, to draft each truth.json from.
--
-- Photos live at cards/<user>/<card>/flat.heic, and each page at
-- cards/<user>/<card>/attach-<ATTACHMENT ID>.heic (SyncCoordinator.uploadImages).
-- Only photos actually uploaded count: `photos` is what storage holds.
--
-- Run it in the dashboard SQL editor and paste the result back, or export it
-- as CSV into .private/scan-candidates.csv.

with stored as (
  select (storage.foldername(name))[2] as card_id,
         count(*) filter (where name like '%/flat.heic') as flat,
         count(*) filter (where name like '%/attach-%') as pages,
         sum((metadata ->> 'size')::bigint) as bytes
  from storage.objects
  where bucket_id = 'cards'
  group by 1
)
select c.id,
       c.user_id,
       c.name,
       c.roaster,
       c.country,
       c.region,
       c.producer,
       c.altitude,
       c.variety,
       c.process,
       c.tasting_notes,
       coalesce(s.pages, 0) as pages,
       round(coalesce(s.bytes, 0) / 1048576.0, 1) as mb,
       c.created_at::date as added
from public.coffee_cards c
join stored s on s.card_id = c.id::text and s.flat > 0
order by coalesce(s.pages, 0) desc, c.created_at desc
limit 40;
