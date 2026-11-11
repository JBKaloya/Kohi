-- Auto is the default way the guided timer leaves a step. A mode picked on
-- How much? is a choice, and the one-time move to Auto leaves it alone.
-- Null means never chosen; the app only sends the column when it is true,
-- so older rows and older builds are unaffected.

alter table public.recipes
  add column if not exists advance_mode_chosen boolean;
