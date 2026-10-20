create table if not exists public.site_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.site_admins enable row level security;
revoke all on table public.site_admins from public, anon, authenticated;
grant usage on schema public to authenticated;

create or replace function public.is_site_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.site_admins
    where user_id = auth.uid()
  );
$$;

create or replace function public.admin_delete_comment(p_comment_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count integer;
begin
  if auth.uid() is null or not public.is_site_admin() then
    raise exception 'Admin access required';
  end if;

  delete from public.comments
  where id::text = p_comment_id;

  get diagnostics deleted_count = row_count;
  if deleted_count = 0 then
    raise exception 'Comment not found';
  end if;
end;
$$;

revoke all on function public.is_site_admin() from public, anon;
revoke all on function public.admin_delete_comment(text) from public, anon;
grant execute on function public.is_site_admin() to authenticated;
grant execute on function public.admin_delete_comment(text) to authenticated;
grant select on table public.comments to authenticated;

drop policy if exists "site admins can read comments" on public.comments;
create policy "site admins can read comments"
  on public.comments
  for select
  to authenticated
  using (public.is_site_admin());

alter table public.site_visitors enable row level security;
grant select on table public.site_visitors to authenticated;

drop policy if exists "site admins can read site visits" on public.site_visitors;
create policy "site admins can read site visits"
  on public.site_visitors
  for select
  to authenticated
  using (public.is_site_admin());

alter table public.places
  add column if not exists amenities jsonb not null default '{}'::jsonb;
alter table public.places
  add column if not exists last_verified_at date;

drop function if exists public.admin_update_place(bigint, text, text, text, numeric, numeric, numeric);
drop function if exists public.admin_update_place(bigint, text, text, text, numeric, numeric, numeric, jsonb);

create or replace function public.admin_update_place(
  p_place_id bigint,
  p_name text,
  p_city text,
  p_description text,
  p_rating numeric,
  p_latitude numeric,
  p_longitude numeric,
  p_amenities jsonb,
  p_last_verified_at date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_count integer;
begin
  if auth.uid() is null or not public.is_site_admin() then
    raise exception 'Admin access required';
  end if;

  if p_name is null or length(trim(p_name)) = 0 or length(p_name) > 120 then
    raise exception 'Name must be between 1 and 120 characters';
  end if;
  if p_city is not null and length(p_city) > 120 then
    raise exception 'City must be at most 120 characters';
  end if;
  if p_description is not null and length(p_description) > 3000 then
    raise exception 'Description must be at most 3000 characters';
  end if;
  if p_rating is null or p_rating < 0 or p_rating > 10 then
    raise exception 'Rating must be between 0 and 10';
  end if;
  if p_latitude is null or p_longitude is null
    or p_latitude < -90 or p_latitude > 90
    or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Valid latitude and longitude are required';
  end if;
  if p_amenities is null or pg_catalog.jsonb_typeof(p_amenities) <> 'object'
    or exists (
      select 1
      from pg_catalog.jsonb_each(p_amenities) as amenity(key, value)
      where key not in ('parking', 'toilet', 'pier', 'child_friendly', 'grill', 'changing_room', 'kiosk')
        or pg_catalog.jsonb_typeof(value) <> 'boolean'
    ) then
    raise exception 'Amenities must contain supported boolean values';
  end if;

  update public.places
  set name = trim(p_name),
      city = nullif(trim(coalesce(p_city, '')), ''),
      description = coalesce(p_description, ''),
      rating = p_rating,
      latitude = p_latitude,
      longitude = p_longitude,
      amenities = p_amenities,
      last_verified_at = p_last_verified_at
  where id = p_place_id;

  get diagnostics updated_count = row_count;
  if updated_count = 0 then
    raise exception 'Place not found';
  end if;
end;
$$;

revoke all on function public.admin_update_place(bigint, text, text, text, numeric, numeric, numeric, jsonb, date) from public, anon;
grant execute on function public.admin_update_place(bigint, text, text, text, numeric, numeric, numeric, jsonb, date) to authenticated;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (length(display_name) <= 60)
);

alter table public.profiles enable row level security;
revoke all on table public.profiles from public, anon, authenticated;
grant select, insert, update on table public.profiles to authenticated;

drop policy if exists "users read own profile" on public.profiles;
create policy "users read own profile" on public.profiles
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "users create own profile" on public.profiles;
create policy "users create own profile" on public.profiles
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.comments
  add column if not exists user_id uuid references auth.users(id) on delete set null;
alter table public.comments enable row level security;
revoke select, insert, update on table public.comments from anon, authenticated;
grant select (id, place_id, name, text, created_at, likes) on public.comments to anon, authenticated;
grant insert (place_id, name, text) on public.comments to anon;
grant insert (place_id, name, text, user_id) on public.comments to authenticated;
grant update (likes) on public.comments to anon, authenticated;

drop policy if exists "authenticated read comments" on public.comments;
create policy "authenticated read comments" on public.comments
  for select to authenticated using (true);
drop policy if exists "users insert own comments" on public.comments;
create policy "users insert own comments" on public.comments
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "authenticated users update comment likes" on public.comments;
create policy "authenticated users update comment likes" on public.comments
  for update to authenticated using (true) with check (true);

create or replace function public.get_my_comments()
returns table (comment_id text, place_id bigint, text text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select comment_row.id::text, comment_row.place_id, comment_row.text, comment_row.created_at
  from public.comments as comment_row
  where auth.uid() is not null and comment_row.user_id = auth.uid()
  order by comment_row.created_at desc;
$$;

revoke all on function public.get_my_comments() from public, anon;
grant execute on function public.get_my_comments() to authenticated;

create table if not exists public.place_change_suggestions (
  id uuid primary key default gen_random_uuid(),
  place_id bigint not null references public.places(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  author_name text not null default 'Anonym',
  message text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  constraint place_suggestion_message_length check (length(trim(message)) between 10 and 2000),
  constraint place_suggestion_status check (status in ('pending', 'reviewed', 'rejected'))
);

alter table public.place_change_suggestions enable row level security;
revoke all on table public.place_change_suggestions from public, anon, authenticated;
grant insert on table public.place_change_suggestions to anon, authenticated;
grant select, update on table public.place_change_suggestions to authenticated;

drop policy if exists "visitors submit place suggestions" on public.place_change_suggestions;
create policy "visitors submit place suggestions" on public.place_change_suggestions
  for insert to anon with check (user_id is null);
drop policy if exists "users submit place suggestions" on public.place_change_suggestions;
create policy "users submit place suggestions" on public.place_change_suggestions
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "admins read place suggestions" on public.place_change_suggestions;
create policy "admins read place suggestions" on public.place_change_suggestions
  for select to authenticated using (public.is_site_admin());
drop policy if exists "admins review place suggestions" on public.place_change_suggestions;
create policy "admins review place suggestions" on public.place_change_suggestions
  for update to authenticated using (public.is_site_admin()) with check (public.is_site_admin());

