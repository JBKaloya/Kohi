-- compare-summary: a sentence or two under the comparison radar, testers
-- first. Its server switch, so it can be paused without a build.

insert into public.ai_flags (feature, note) values
  ('compare-summary', 'Testers read a plain summary of what sets compared coffees apart.')
on conflict (feature) do nothing;
