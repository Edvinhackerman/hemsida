-- Run supabase/admin_comments.sql first to create public.profiles.

alter table public.profiles
  add column if not exists is_public boolean not null default false;

create table if not exists public.profile_visits (
  user_id uuid not null references auth.users(id) on delete cascade,
  place_id bigint not null references public.places(id) on delete cascade,
  visited_at timestamptz not null default now(),
  primary key (user_id, place_id)
);

create index if not exists profile_visits_place_id_idx
  on public.profile_visits (place_id);

alter table public.profile_visits enable row level security;
revoke all on table public.profile_visits from public, anon, authenticated;
grant select, insert, delete on table public.profile_visits to authenticated;

drop policy if exists "users read own place visits" on public.profile_visits;
create policy "users read own place visits" on public.profile_visits
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "users add own place visits" on public.profile_visits;
create policy "users add own place visits" on public.profile_visits
  for insert to authenticated with check (user_id = (select auth.uid()));

drop policy if exists "users remove own place visits" on public.profile_visits;
create policy "users remove own place visits" on public.profile_visits
  for delete to authenticated using (user_id = (select auth.uid()));

create or replace function public.get_public_profile(p_user_id uuid)
returns table (
  display_name text,
  visited_place_ids bigint[],
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.display_name,
    coalesce(
      array_agg(visit.place_id order by visit.visited_at desc)
        filter (where visit.place_id is not null),
      array[]::bigint[]
    ),
    profile.created_at
  from public.profiles as profile
  left join public.profile_visits as visit
    on visit.user_id = profile.user_id
  where profile.user_id = p_user_id
    and profile.is_public
  group by profile.user_id, profile.display_name, profile.created_at;
$$;

revoke all on function public.get_public_profile(uuid) from public;
grant execute on function public.get_public_profile(uuid) to anon, authenticated;

alter table public.profile_visits
  add column if not exists note text not null default '';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profile_visits_note_length_check'
      and conrelid = 'public.profile_visits'::regclass
  ) then
    alter table public.profile_visits
      add constraint profile_visits_note_length_check
      check (char_length(note) <= 500);
  end if;
end;
$$;

drop policy if exists "users update own place visits" on public.profile_visits;
create policy "users update own place visits" on public.profile_visits
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant update (visited_at, note) on table public.profile_visits to authenticated;

create table if not exists public.profile_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_user_id uuid not null references auth.users(id) on delete cascade,
  followed_at timestamptz not null default now(),
  primary key (follower_id, followed_user_id),
  constraint profile_follows_no_self_follow check (follower_id <> followed_user_id)
);

create index if not exists profile_follows_followed_user_id_idx
  on public.profile_follows (followed_user_id);

alter table public.profile_follows enable row level security;
revoke all on table public.profile_follows from public, anon, authenticated;

create or replace function public.get_public_profile_details(p_user_id uuid)
returns table (
  display_name text,
  visits jsonb,
  visited_count bigint,
  city_count bigint,
  follower_count bigint,
  following_count bigint,
  is_following boolean,
  public_following jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.display_name,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'place_id', visit.place_id,
          'visited_at', visit.visited_at,
          'note', visit.note
        ) order by visit.visited_at desc
      )
      from public.profile_visits as visit
      where visit.user_id = profile.user_id
    ), '[]'::jsonb),
    (
      select count(*)
      from public.profile_visits as visit
      where visit.user_id = profile.user_id
    ),
    (
      select count(distinct nullif(btrim(place.city), ''))
      from public.profile_visits as visit
      join public.places as place on place.id = visit.place_id
      where visit.user_id = profile.user_id
    ),
    (
      select count(*)
      from public.profile_follows as follow
      where follow.followed_user_id = profile.user_id
    ),
    (
      select count(*)
      from public.profile_follows as follow
      join public.profiles as followed_profile on followed_profile.user_id = follow.followed_user_id
      where follow.follower_id = profile.user_id
        and followed_profile.is_public
    ),
    exists (
      select 1
      from public.profile_follows as follow
      where follow.follower_id = (select auth.uid())
        and follow.followed_user_id = profile.user_id
    ),
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'user_id', followed_profile.user_id,
          'display_name', followed_profile.display_name,
          'visited_place_count', (
            select count(*)
            from public.profile_visits as visit
            where visit.user_id = followed_profile.user_id
          )
        ) order by followed_profile.display_name
      )
      from public.profile_follows as follow
      join public.profiles as followed_profile on followed_profile.user_id = follow.followed_user_id
      where follow.follower_id = profile.user_id
        and followed_profile.is_public
    ), '[]'::jsonb)
  from public.profiles as profile
  where profile.user_id = p_user_id
    and profile.is_public;
$$;

revoke all on function public.get_public_profile_details(uuid) from public;
grant execute on function public.get_public_profile_details(uuid) to anon, authenticated;

create or replace function public.search_public_profiles(p_query text default '')
returns table (
  user_id uuid,
  display_name text,
  visited_place_count bigint,
  follower_count bigint,
  is_following boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.user_id,
    profile.display_name,
    (
      select count(*)
      from public.profile_visits as visit
      where visit.user_id = profile.user_id
    ),
    (
      select count(*)
      from public.profile_follows as follow
      where follow.followed_user_id = profile.user_id
    ),
    exists (
      select 1
      from public.profile_follows as follow
      where follow.follower_id = (select auth.uid())
        and follow.followed_user_id = profile.user_id
    )
  from public.profiles as profile
  where profile.is_public
    and (
      (select auth.uid()) is null
      or profile.user_id <> (select auth.uid())
    )
    and (
      coalesce(btrim(p_query), '') = ''
      or position(lower(btrim(p_query)) in lower(coalesce(profile.display_name, ''))) > 0
    )
  order by profile.display_name
  limit 50;
$$;

revoke all on function public.search_public_profiles(text) from public;
grant execute on function public.search_public_profiles(text) to anon, authenticated;

create or replace function public.get_my_following()
returns table (
  user_id uuid,
  display_name text,
  visited_place_count bigint,
  followed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    followed_profile.user_id,
    followed_profile.display_name,
    (
      select count(*)
      from public.profile_visits as visit
      where visit.user_id = followed_profile.user_id
    ),
    follow.followed_at
  from public.profile_follows as follow
  join public.profiles as followed_profile on followed_profile.user_id = follow.followed_user_id
  where follow.follower_id = (select auth.uid())
    and followed_profile.is_public
  order by follow.followed_at desc;
$$;

revoke all on function public.get_my_following() from public;
grant execute on function public.get_my_following() to authenticated;

create or replace function public.set_profile_follow(
  p_followed_user_id uuid,
  p_should_follow boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_follower_id uuid := (select auth.uid());
begin
  if v_follower_id is null then
    raise exception 'Sign in is required to follow profiles.';
  end if;

  if p_followed_user_id is null or p_followed_user_id = v_follower_id then
    raise exception 'You cannot follow this profile.';
  end if;

  if p_should_follow is null then
    raise exception 'Choose whether to follow or unfollow this profile.';
  end if;

  if p_should_follow then
    if not exists (
      select 1
      from public.profiles as profile
      where profile.user_id = p_followed_user_id
        and profile.is_public
    ) then
      raise exception 'Only public profiles can be followed.';
    end if;

    insert into public.profile_follows (follower_id, followed_user_id)
    values (v_follower_id, p_followed_user_id)
    on conflict (follower_id, followed_user_id) do nothing;
  else
    delete from public.profile_follows
    where follower_id = v_follower_id
      and followed_user_id = p_followed_user_id;
  end if;
end;
$$;

revoke all on function public.set_profile_follow(uuid, boolean) from public;
grant execute on function public.set_profile_follow(uuid, boolean) to authenticated;
