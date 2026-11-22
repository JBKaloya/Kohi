-- Writes to the migration history only (supabase_migrations.schema_migrations).
-- No table, column or row of the app is touched.
--
-- Why. On 21 Nov 2026, 2026-11-21-state.sql and 2026-11-21-extras.sql found:
--   * 0019–0038 missing from the history, though every one of their effects is
--     in the database (tables, columns, constraints, bucket, flags: all present);
--   * 14 versions numbered by date, recorded when migrations were applied from
--     the dashboard or the API instead of `supabase db push`. 13 are repo
--     migrations under another number; the 14th is an earlier cleanup of the
--     same kind of rows, itself recorded under a date.
--
--   20260915064855  0020_drop_timestamped_history_rows   earlier cleanup, no file
--   20260919154024  filter_stock                         = 0019
--   20260919154026  recipe_rinse                         = 0020
--   20260919154030  roast_level_includes_super_light     = first part of 0021
--   20260919154251  recipe_source_express                = 0021
--   20260919154252  brew_pour_rates                      = 0022
--   20260919154256  brew_planned_steps                   = 0023
--   20260926191644  recipe_advance_mode                  = 0024
--   20261002084115  card_place_ref                       = 0025
--   20261025185900  canvas_reviews                       = 0027
--   20261025190000  tastings                             = 0026
--   20261025190100  tastings_table                       = 0028
--   20261025190200  brew_complexity                      = 0029
--   20261109115553  rating_halves                        = 0030
--   (0031–0038 were applied without any record.)
--
-- What. One transaction: record 0019–0038 the way 0001–0018 are recorded
-- (version, name, no statements, like `supabase migration repair --status
-- applied`), then drop the 14 dated rows (like `--status reverted`). The last
-- block checks the result and rolls everything back if it is not 0001–0038
-- with nothing else.
--
-- Run it once in the dashboard SQL editor, then run 2026-11-21-state.sql
-- again: every history line should read ok and there should be no extra.

begin;

insert into supabase_migrations.schema_migrations (version, name, statements) values
  ('0019', 'filter_stock', '{}'),
  ('0020', 'recipe_rinse', '{}'),
  ('0021', 'recipe_source_express', '{}'),
  ('0022', 'brew_pour_rates', '{}'),
  ('0023', 'planned_steps', '{}'),
  ('0024', 'recipe_advance_mode', '{}'),
  ('0025', 'card_place_ref', '{}'),
  ('0026', 'tastings', '{}'),
  ('0027', 'canvas_reviews', '{}'),
  ('0028', 'tastings_table', '{}'),
  ('0029', 'brew_complexity', '{}'),
  ('0030', 'rating_halves', '{}'),
  ('0031', 'loose_brews', '{}'),
  ('0032', 'recipe_advance_choice', '{}'),
  ('0033', 'recipe_advance_auto_only', '{}'),
  ('0034', 'dictations', '{}'),
  ('0035', 'recipe_split_counts_bloom', '{}'),
  ('0036', 'narration_trials', '{}'),
  ('0037', 'dictation_brew_context', '{}'),
  ('0038', 'compare_summary_flag', '{}')
on conflict (version) do nothing;

delete from supabase_migrations.schema_migrations
where version in (
  '20260915064855',
  '20260919154024',
  '20260919154026',
  '20260919154030',
  '20260919154251',
  '20260919154252',
  '20260919154256',
  '20260926191644',
  '20261002084115',
  '20261025185900',
  '20261025190000',
  '20261025190100',
  '20261025190200',
  '20261109115553'
);

do $$
declare
  numbered int;
  others int;
begin
  select count(*) into numbered
  from supabase_migrations.schema_migrations
  where version ~ '^\d{4}$' and version::int between 1 and 38;
  select count(*) into others
  from supabase_migrations.schema_migrations
  where not (version ~ '^\d{4}$' and version::int between 1 and 38);
  if numbered <> 38 or others <> 0 then
    raise exception 'history is not 0001–0038 alone (% numbered, % other): nothing written', numbered, others;
  end if;
end $$;

commit;
