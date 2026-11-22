-- Read-only. Second pass after 2026-11-21-state.sql, which found 0019–0038
-- missing from the history and 14 timestamp versions recorded on the server
-- that no file in supabase/migrations carries.
--
-- This shows:
--   extra    each timestamp version with the name it was recorded under and
--            the start of its SQL, to match it to a repo migration;
--   format   how 0017 and 0018 are recorded, so the repair writes the same shape;
--   effect   whether what 0019–0035 create is in the database.
--
-- Run it in the dashboard SQL editor and paste the whole result back.

with extras as (
  select version, coalesce(name, '') as name,
         left(regexp_replace(coalesce(array_to_string(statements, ' '), ''), '\s+', ' ', 'g'), 140) as head
  from supabase_migrations.schema_migrations
  where version !~ '^\d{4}$'
),
format as (
  select version, coalesce(name, '') as name,
         coalesce(array_length(statements, 1), 0) as statement_count
  from supabase_migrations.schema_migrations
  where version in ('0017', '0018')
),
col as (
  select table_name || '.' || column_name as id, is_nullable, column_default
  from information_schema.columns
  where table_schema = 'public'
),
constraint_def as (
  select conname, pg_get_constraintdef(oid) as def
  from pg_constraint
  where connamespace = 'public'::regnamespace
),
effects(version, item, present) as (
  values
    ('0019', 'table public.filter_stock', to_regclass('public.filter_stock') is not null),
    ('0019', 'column equipment.accepts_filter_shapes', exists (select 1 from col where id = 'equipment.accepts_filter_shapes')),
    ('0020', 'column recipes.rinse_mass_override', exists (select 1 from col where id = 'recipes.rinse_mass_override')),
    ('0020', 'column brews.grind_position', exists (select 1 from col where id = 'brews.grind_position')),
    ('0021', 'recipes_source_check allows express', exists (select 1 from constraint_def where conname = 'recipes_source_check' and def like '%express%')),
    ('0022', 'column brews.pour_rates', exists (select 1 from col where id = 'brews.pour_rates')),
    ('0023', 'column brews.planned_steps', exists (select 1 from col where id = 'brews.planned_steps')),
    ('0023', 'column brews.actual_source', exists (select 1 from col where id = 'brews.actual_source')),
    ('0024', 'recipes_advance_mode_check allows cues', exists (select 1 from constraint_def where conname = 'recipes_advance_mode_check' and def like '%cues%')),
    ('0025', 'column coffee_cards.place_ref', exists (select 1 from col where id = 'coffee_cards.place_ref')),
    ('0026', 'column coffee_cards.tastings', exists (select 1 from col where id = 'coffee_cards.tastings')),
    ('0027', 'table public.canvas_reviews', to_regclass('public.canvas_reviews') is not null),
    ('0027', 'table public.canvas_comments', to_regclass('public.canvas_comments') is not null),
    ('0027', 'function private.canvas_comment_guard', to_regprocedure('private.canvas_comment_guard()') is not null),
    ('0028', 'table public.tastings', to_regclass('public.tastings') is not null),
    ('0028', 'ai_flags menu-extract', exists (select 1 from public.ai_flags where feature = 'menu-extract')),
    ('0029', 'column brews.complexity', exists (select 1 from col where id = 'brews.complexity')),
    ('0030', 'column tastings.rating_halves', exists (select 1 from col where id = 'tastings.rating_halves')),
    ('0030', 'column brews.rating_halves', exists (select 1 from col where id = 'brews.rating_halves')),
    ('0031', 'brews.card_id nullable', exists (select 1 from col where id = 'brews.card_id' and is_nullable = 'YES')),
    ('0031', 'column brews.coffee', exists (select 1 from col where id = 'brews.coffee')),
    ('0032', 'column recipes.advance_mode_chosen', exists (select 1 from col where id = 'recipes.advance_mode_chosen')),
    ('0033', 'recipes.advance_mode defaults to auto', exists (select 1 from col where id = 'recipes.advance_mode' and column_default like '%auto%')),
    ('0034', 'table public.dictations', to_regclass('public.dictations') is not null),
    ('0034', 'storage bucket dictations', exists (select 1 from storage.buckets where id = 'dictations')),
    ('0035', 'column recipes.split_counts_bloom', exists (select 1 from col where id = 'recipes.split_counts_bloom'))
)
select 'extra' as kind, version as item, name || ' · ' || head as status from extras
union all
select 'format', version, 'name "' || name || '", ' || statement_count || ' statements' from format
union all
select 'effect', version || ' ' || item, case when present then 'present' else 'ABSENT' end from effects
order by kind, item;
