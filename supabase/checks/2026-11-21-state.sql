-- 21 Nov 2026: is the server where the repo says it is?
-- Run in the dashboard's SQL editor and paste the whole result back.
-- Read only. One result table: every row is one check.
--
--   history  a migration file of the repo, recorded or MISSING in the
--            server's migration history (what `supabase db push` reads)
--   effect   what the three hand-applied migrations should have left behind
--   extra    a version the server records that the repo does not have

with history as (
  select version from supabase_migrations.schema_migrations
),
expected(version, name) as (
  values
    ('0001', 'init'),
    ('0002', 'add_attachments'),
    ('0003', 'recipe_translation'),
    ('0004', 'poster'),
    ('0005', 'brew_updated_at_drop_caffeine'),
    ('0006', 'on_the_bag'),
    ('0007', 'roasters'),
    ('0008', 'setup'),
    ('0009', 'recipes'),
    ('0010', 'grind_calibrations'),
    ('0011', 'brew_enriched'),
    ('0012', 'ai'),
    ('0013', 'lot2'),
    ('0014', 'brew_scale'),
    ('0015', 'brew_recipe_ref'),
    ('0016', 'knowledge_seed'),
    ('0017', 'recipe_profile'),
    ('0018', 'ai_feedback'),
    ('0019', 'filter_stock'),
    ('0020', 'recipe_rinse'),
    ('0021', 'recipe_source_express'),
    ('0022', 'brew_pour_rates'),
    ('0023', 'planned_steps'),
    ('0024', 'recipe_advance_mode'),
    ('0025', 'card_place_ref'),
    ('0026', 'tastings'),
    ('0027', 'canvas_reviews'),
    ('0028', 'tastings_table'),
    ('0029', 'brew_complexity'),
    ('0030', 'rating_halves'),
    ('0031', 'loose_brews'),
    ('0032', 'recipe_advance_choice'),
    ('0033', 'recipe_advance_auto_only'),
    ('0034', 'dictations'),
    ('0035', 'recipe_split_counts_bloom'),
    ('0036', 'narration_trials'),
    ('0037', 'dictation_brew_context'),
    ('0038', 'compare_summary_flag')
)
select 'history' as kind,
       e.version || '_' || e.name as item,
       case when h.version is null then 'MISSING' else 'ok' end as status
from expected e
left join history h on h.version = e.version

union all
select 'extra', h.version, 'recorded on the server, not in the repo'
from history h
where h.version not in (select version from expected)

union all
select 'effect', '0036 table public.narration_trials',
       case when to_regclass('public.narration_trials') is null then 'ABSENT' else 'present' end

union all
select 'effect', '0036 ai_flags narration-compare',
       coalesce((select case when enabled then 'present, on' else 'present, OFF' end
                 from public.ai_flags where feature = 'narration-compare'), 'ABSENT')

union all
select 'effect', '0037 column public.dictations.brew_context',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'dictations' and column_name = 'brew_context'
       ) then 'present' else 'ABSENT' end

union all
select 'effect', '0038 ai_flags compare-summary',
       coalesce((select case when enabled then 'present, on' else 'present, OFF' end
                 from public.ai_flags where feature = 'compare-summary'), 'ABSENT')

order by 1, 2;
