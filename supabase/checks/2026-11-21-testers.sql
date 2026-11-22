-- Read-only. Who has tastings, to find the account whose tastings feed
-- scripts/compare-real.ts. One line per account with at least one tasting.
-- Sign in with Apple may show a private relay address: the counts and dates
-- tell the accounts apart.

select u.id,
       u.email,
       u.created_at::date as signed_up,
       count(t.id) as tastings,
       count(t.id) filter (where t.taste <> '{}'::jsonb) as with_taste,
       max(t.tasted_at)::date as last_tasting
from auth.users u
join public.tastings t on t.user_id = u.id and t.deleted_at is null
group by u.id, u.email, u.created_at
order by tastings desc;
