-- Whether the bloom is the first of the parts a recipe's water splits into.
-- Null reads as counted, which is how every recipe before build 17 read.

alter table public.recipes
  add column if not exists split_counts_bloom boolean;
