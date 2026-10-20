-- Run supabase/admin_comments.sql first to create public.profiles.

alter table public.profiles
  add column if not exists is_public boolean not null default true;

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

drop function if exists public.get_public_profile(uuid);
drop function if exists public.get_public_profile_details(uuid);
drop function if exists public.search_public_profiles(text);
drop function if exists public.get_my_following();
drop function if exists public.set_profile_follow(uuid, boolean);

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

alter table public.profiles
  alter column is_public set default true,
  add column if not exists public_age smallint;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_public_age_range_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_public_age_range_check
      check (public_age is null or public_age between 13 and 120);
  end if;
end;
$$;

create table if not exists public.profile_friendships (
  user_low uuid not null references auth.users(id) on delete cascade,
  user_high uuid not null references auth.users(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_low, user_high),
  constraint profile_friendships_ordered_pair check (user_low < user_high),
  constraint profile_friendships_requester_in_pair check (requested_by in (user_low, user_high)),
  constraint profile_friendships_status_check check (status in ('pending', 'accepted', 'rejected'))
);

create index if not exists profile_friendships_recipient_pending_idx
  on public.profile_friendships (user_low, user_high)
  where status = 'pending';

alter table public.profile_friendships enable row level security;
revoke all on table public.profile_friendships from public, anon, authenticated;

create or replace function public.get_public_profile_details(p_user_id uuid)
returns table (
  display_name text,
  public_age smallint,
  friendship_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.display_name,
    profile.public_age,
    case
      when profile.user_id = (select auth.uid()) then 'self'
      when exists (
        select 1 from public.profile_friendships as friendship
        where friendship.user_low = least(profile.user_id, (select auth.uid()))
          and friendship.user_high = greatest(profile.user_id, (select auth.uid()))
          and friendship.status = 'accepted'
      ) then 'friends'
      when exists (
        select 1 from public.profile_friendships as friendship
        where friendship.user_low = least(profile.user_id, (select auth.uid()))
          and friendship.user_high = greatest(profile.user_id, (select auth.uid()))
          and friendship.status = 'pending'
          and friendship.requested_by = (select auth.uid())
      ) then 'request_sent'
      when exists (
        select 1 from public.profile_friendships as friendship
        where friendship.user_low = least(profile.user_id, (select auth.uid()))
          and friendship.user_high = greatest(profile.user_id, (select auth.uid()))
          and friendship.status = 'pending'
          and friendship.requested_by = profile.user_id
      ) then 'request_received'
      else 'none'
    end
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
  public_age smallint,
  friendship_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.user_id,
    profile.display_name,
    profile.public_age,
    case
      when exists (
        select 1 from public.profile_friendships as friendship
        where friendship.user_low = least(profile.user_id, (select auth.uid()))
          and friendship.user_high = greatest(profile.user_id, (select auth.uid()))
          and friendship.status = 'accepted'
      ) then 'friends'
      when exists (
        select 1 from public.profile_friendships as friendship
        where friendship.user_low = least(profile.user_id, (select auth.uid()))
          and friendship.user_high = greatest(profile.user_id, (select auth.uid()))
          and friendship.status = 'pending'
          and friendship.requested_by = (select auth.uid())
      ) then 'request_sent'
      when exists (
        select 1 from public.profile_friendships as friendship
        where friendship.user_low = least(profile.user_id, (select auth.uid()))
          and friendship.user_high = greatest(profile.user_id, (select auth.uid()))
          and friendship.status = 'pending'
          and friendship.requested_by = profile.user_id
      ) then 'request_received'
      else 'none'
    end
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

create or replace function public.get_my_friends()
returns table (
  user_id uuid,
  display_name text,
  public_age smallint,
  friends_since timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.user_id,
    profile.display_name,
    profile.public_age,
    friendship.updated_at
  from public.profile_friendships as friendship
  join public.profiles as profile
    on profile.user_id = case
      when friendship.user_low = (select auth.uid()) then friendship.user_high
      else friendship.user_low
    end
  where (friendship.user_low = (select auth.uid()) or friendship.user_high = (select auth.uid()))
    and friendship.status = 'accepted'
    and profile.is_public
  order by profile.display_name;
$$;

revoke all on function public.get_my_friends() from public;
grant execute on function public.get_my_friends() to authenticated;

create or replace function public.get_my_friend_requests()
returns table (
  user_id uuid,
  display_name text,
  public_age smallint,
  direction text,
  requested_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.user_id,
    profile.display_name,
    profile.public_age,
    case when friendship.requested_by = (select auth.uid()) then 'outgoing' else 'incoming' end,
    friendship.created_at
  from public.profile_friendships as friendship
  join public.profiles as profile
    on profile.user_id = case
      when friendship.user_low = (select auth.uid()) then friendship.user_high
      else friendship.user_low
    end
  where (friendship.user_low = (select auth.uid()) or friendship.user_high = (select auth.uid()))
    and friendship.status = 'pending'
    and profile.is_public
  order by friendship.created_at desc;
$$;

revoke all on function public.get_my_friend_requests() from public;
grant execute on function public.get_my_friend_requests() to authenticated;

create or replace function public.send_friend_request(p_recipient_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_low uuid;
  v_high uuid;
  v_status text;
  v_requested_by uuid;
begin
  if v_user_id is null then
    raise exception 'Sign in to add friends.';
  end if;
  if p_recipient_id is null or p_recipient_id = v_user_id then
    raise exception 'You cannot add yourself as a friend.';
  end if;
  if not exists (
    select 1 from public.profiles as profile
    where profile.user_id = v_user_id and profile.is_public
  ) or not exists (
    select 1 from public.profiles as profile
    where profile.user_id = p_recipient_id and profile.is_public
  ) then
    raise exception 'Friend requests are only available between public profiles.';
  end if;

  v_low := least(v_user_id, p_recipient_id);
  v_high := greatest(v_user_id, p_recipient_id);

  insert into public.profile_friendships (user_low, user_high, requested_by, status)
  values (v_low, v_high, v_user_id, 'pending')
  on conflict (user_low, user_high) do update
    set requested_by = excluded.requested_by,
        status = 'pending',
        created_at = now(),
        updated_at = now()
    where public.profile_friendships.status = 'rejected';

  select status, requested_by
    into v_status, v_requested_by
  from public.profile_friendships
  where user_low = v_low and user_high = v_high;

  if v_status = 'accepted' then
    raise exception 'You are already friends.';
  elsif v_status = 'pending' and v_requested_by = v_user_id then
    raise exception 'A friend request is already pending.';
  elsif v_status = 'pending' then
    raise exception 'This person has already sent you a request. Accept it from your profile.';
  end if;
end;
$$;

revoke all on function public.send_friend_request(uuid) from public;
grant execute on function public.send_friend_request(uuid) to authenticated;

create or replace function public.respond_friend_request(p_requester_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_low uuid;
  v_high uuid;
begin
  if v_user_id is null then
    raise exception 'Sign in to respond to friend requests.';
  end if;
  if p_requester_id is null or p_requester_id = v_user_id or p_accept is null then
    raise exception 'Invalid friend request.';
  end if;
  v_low := least(v_user_id, p_requester_id);
  v_high := greatest(v_user_id, p_requester_id);

  update public.profile_friendships
  set status = case when p_accept then 'accepted' else 'rejected' end,
      updated_at = now()
  where user_low = v_low
    and user_high = v_high
    and requested_by = p_requester_id
    and status = 'pending';

  if not found then
    raise exception 'No pending friend request was found.';
  end if;
end;
$$;

revoke all on function public.respond_friend_request(uuid, boolean) from public;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;

create or replace function public.cancel_friend_request(p_recipient_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null or p_recipient_id is null then
    raise exception 'Sign in to cancel a friend request.';
  end if;

  delete from public.profile_friendships
  where user_low = least(v_user_id, p_recipient_id)
    and user_high = greatest(v_user_id, p_recipient_id)
    and requested_by = v_user_id
    and status = 'pending';

  if not found then
    raise exception 'No pending friend request was found.';
  end if;
end;
$$;

revoke all on function public.cancel_friend_request(uuid) from public;
grant execute on function public.cancel_friend_request(uuid) to authenticated;

create or replace function public.remove_friend(p_friend_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null or p_friend_user_id is null or p_friend_user_id = v_user_id then
    raise exception 'Invalid friend.';
  end if;

  delete from public.profile_friendships
  where user_low = least(v_user_id, p_friend_user_id)
    and user_high = greatest(v_user_id, p_friend_user_id)
    and status = 'accepted';

  if not found then
    raise exception 'Friendship was not found.';
  end if;
end;
$$;

revoke all on function public.remove_friend(uuid) from public;
grant execute on function public.remove_friend(uuid) to authenticated;

create or replace function public.admin_list_recent_accounts()
returns table (
  display_name text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not public.is_site_admin() then
    raise exception 'Admin access required.';
  end if;

  return query
  select
    coalesce(
      nullif(profile.display_name, ''),
      nullif(account.raw_user_meta_data ->> 'display_name', ''),
      'Namn saknas'
    ),
    account.created_at
  from auth.users as account
  left join public.profiles as profile on profile.user_id = account.id
  order by account.created_at desc
  limit 100;
end;
$$;

revoke all on function public.admin_list_recent_accounts() from public, anon;
grant execute on function public.admin_list_recent_accounts() to authenticated;
