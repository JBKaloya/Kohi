-- Read-only. How each provider behaved on our own calls so far, before the
-- assistants compare Gemini and OpenAI (docs/assistants-gemini-vs-openai.md,
-- step 0).
--
-- Two sources, one result:
--   events   ai_events: every model call the app logged, by model. Gemini for
--            every feature, OpenAI only behind narration so far.
--   trials   narration_trials: each pipeline run side by side on the same
--            note, the closest thing to a fair test we have. The *+luna
--            pipelines are the only OpenAI text calls on record.
--
-- Columns: calls, failure share, median and p90 latency in seconds, and the
-- most frequent failure. Run it in the dashboard SQL editor and paste the
-- result back.

with events as (
  select 'events' as source,
         feature || ' · ' || model as item,
         latency_ms,
         failure
  from public.ai_events
  where created_at > now() - interval '30 days'
),
trials as (
  select 'trials' as source,
         (c ->> 'pipeline') || ' · ' || coalesce(c ->> 'model', '?') as item,
         (c ->> 'latency_ms')::int as latency_ms,
         case when (c ->> 'ok')::boolean then null else coalesce(c ->> 'failure', 'failed') end as failure
  from public.narration_trials t,
       jsonb_array_elements(t.candidates) as c
  where c ->> 'pipeline' <> 'device'
),
everything as (
  select * from events
  union all
  select * from trials
)
select source,
       item,
       count(*) as calls,
       round(100.0 * count(failure) / count(*), 1) as failure_pct,
       round((percentile_cont(0.5) within group (order by latency_ms) / 1000.0)::numeric, 1) as p50_s,
       round((percentile_cont(0.9) within group (order by latency_ms) / 1000.0)::numeric, 1) as p90_s,
       mode() within group (order by left(failure, 60)) as usual_failure
from everything
group by source, item
order by source, item;
