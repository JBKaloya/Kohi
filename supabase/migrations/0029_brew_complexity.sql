-- Aromatic complexity on a home brew, stored as the wish for next time:
-- +1 more, -1 less, null when left as is and on every earlier brew.
-- Nothing else changes: acidity, bitterness and body keep their meaning.

alter table public.brews
  add column if not exists complexity integer
  check (complexity is null or complexity between -1 and 1);
