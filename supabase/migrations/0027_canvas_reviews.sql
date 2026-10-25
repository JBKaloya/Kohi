-- Comments on hosted canvas exports.
--
-- The share link is the access boundary: anyone who can open the page can
-- read and write remarks, with the publishable key. These policies belong
-- only on this pair of tables. Coffee data stays behind auth.uid().
--
-- author_key is generated in the browser and stored so a later pass can
-- restrict edits to the writer. It is not selectable through the API.
-- A remark can be resolved, and nothing else on the row can change.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

create table public.canvas_reviews (
  slug        text primary key,
  title       text not null,
  created_at  timestamptz not null default now(),

  constraint canvas_reviews_slug_shape check (slug ~ '^[a-z0-9-]{1,80}$'),
  constraint canvas_reviews_title_len check (char_length(title) between 1 and 120)
);

create table public.canvas_comments (
  id           uuid primary key default gen_random_uuid(),
  canvas_slug  text not null references public.canvas_reviews(slug) on delete cascade,
  parent_id    uuid references public.canvas_comments(id) on delete cascade,
  author_name  text not null,
  author_key   text not null,
  body         text not null,
  anchor       text,
  pin_x        double precision,
  pin_y        double precision,
  view_state   jsonb not null default '{}'::jsonb,
  status       text not null default 'open' check (status in ('open', 'resolved')),
  created_at   timestamptz not null default now(),

  constraint canvas_comments_author_len check (char_length(author_name) between 1 and 40),
  constraint canvas_comments_author_key_len check (char_length(author_key) between 16 and 80),
  constraint canvas_comments_body_len check (char_length(body) between 1 and 2000),
  constraint canvas_comments_anchor_len check (anchor is null or char_length(anchor) between 1 and 80),
  constraint canvas_comments_pin check (
    (pin_x is null and pin_y is null)
    or (pin_x between 0 and 100 and pin_y between 0 and 100)
  ),
  constraint canvas_comments_state_size check (octet_length(view_state::text) < 4000)
);

create index canvas_comments_canvas_created_idx
  on public.canvas_comments (canvas_slug, created_at);

create index canvas_comments_parent_idx
  on public.canvas_comments (parent_id);

alter table public.canvas_reviews enable row level security;
alter table public.canvas_comments enable row level security;

create policy "canvas reviews are readable with the link"
  on public.canvas_reviews for select
  to anon, authenticated
  using (true);

create policy "canvas reviews can be registered from the page"
  on public.canvas_reviews for insert
  to anon, authenticated
  with check (true);

create policy "canvas review titles can be refreshed from the page"
  on public.canvas_reviews for update
  to anon, authenticated
  using (true)
  with check (true);

create policy "canvas comments are readable with the link"
  on public.canvas_comments for select
  to anon, authenticated
  using (true);

create policy "canvas comments can be added from the page"
  on public.canvas_comments for insert
  to anon, authenticated
  with check (true);

-- Status only. The trigger below rejects every other change, which is what
-- makes "anyone with the link may resolve" safe.
create policy "canvas comments can be resolved from the page"
  on public.canvas_comments for update
  to anon, authenticated
  using (true)
  with check (status in ('open', 'resolved'));

revoke all on public.canvas_reviews from public, anon, authenticated;
grant select (slug, title, created_at) on public.canvas_reviews to anon, authenticated;
grant insert (slug, title) on public.canvas_reviews to anon, authenticated;
grant update (title) on public.canvas_reviews to anon, authenticated;

revoke all on public.canvas_comments from public, anon, authenticated;
grant select (
  id, canvas_slug, parent_id, author_name, body, anchor, pin_x, pin_y, view_state, status, created_at
) on public.canvas_comments to anon, authenticated;
grant insert (
  canvas_slug, parent_id, author_name, author_key, body, anchor, pin_x, pin_y, view_state
) on public.canvas_comments to anon, authenticated;
grant update (status) on public.canvas_comments to anon, authenticated;

create or replace function private.canvas_comment_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_slug text;
  parent_parent uuid;
begin
  if tg_op = 'INSERT' then
    if new.parent_id is not null then
      select canvas_slug, parent_id
        into parent_slug, parent_parent
      from public.canvas_comments
      where id = new.parent_id;

      if parent_slug is null then
        raise exception 'reply target is missing';
      end if;
      if parent_slug <> new.canvas_slug then
        raise exception 'reply stays on the same canvas';
      end if;
      if parent_parent is not null then
        raise exception 'replies are one level deep';
      end if;

      new.anchor := null;
      new.pin_x := null;
      new.pin_y := null;
      new.view_state := '{}'::jsonb;
      new.status := 'open';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.canvas_slug is distinct from old.canvas_slug
       or new.parent_id is distinct from old.parent_id
       or new.author_name is distinct from old.author_name
       or new.author_key is distinct from old.author_key
       or new.body is distinct from old.body
       or new.anchor is distinct from old.anchor
       or new.pin_x is distinct from old.pin_x
       or new.pin_y is distinct from old.pin_y
       or new.view_state is distinct from old.view_state
       or new.created_at is distinct from old.created_at
    then
      raise exception 'only the status of a comment can change';
    end if;
    return new;
  end if;

  return new;
end;
$$;

revoke all on function private.canvas_comment_guard() from public, anon, authenticated;

create trigger canvas_comments_guard
  before insert or update on public.canvas_comments
  for each row execute function private.canvas_comment_guard();

insert into public.canvas_reviews (slug, title)
values ('tastings-before-after', 'Tastings : avant / après')
on conflict (slug) do update set title = excluded.title;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'canvas_comments'
  ) then
    alter publication supabase_realtime add table public.canvas_comments;
  end if;
end $$;

notify pgrst, 'reload schema';
