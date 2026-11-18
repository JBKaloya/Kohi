-- The guided timer only advances by time. Tap and Cues are gone from the app;
-- the columns stay so builds 15 and earlier keep reading a valid row, and
-- they read Auto everywhere.

update public.recipes
  set advance_mode = 'auto', auto_advance = true, advance_mode_chosen = null
  where advance_mode is distinct from 'auto'
     or auto_advance is distinct from true
     or advance_mode_chosen is not null;

alter table public.recipes
  alter column advance_mode set default 'auto';

alter table public.recipes
  alter column auto_advance set default true;
