-- 21 Nov 2026: what the comparison summary and Ask did on the server.
-- Run in the dashboard's SQL editor after trying them in the app, and paste
-- the result back. Read only. The last 20 calls, newest first, each with the
-- usefulness score given under it, if any.

select e.created_at,
       e.feature,
       e.model,
       e.latency_ms,
       e.input_tokens,
       e.output_tokens,
       e.failure,
       f.score as usefulness
from public.ai_events e
left join public.ai_feedback f on f.ai_event_id = e.id
where e.feature in ('compare-summary', 'ask')
order by e.created_at desc
limit 20;
