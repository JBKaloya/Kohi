-- Chemex (and similar) can override the indicative rinse mass.
-- The 1…7 grind notch survives a brew logged without a grinder range.

alter table public.recipes
  add column if not exists rinse_mass_override double precision;

alter table public.brews
  add column if not exists grind_position integer;
