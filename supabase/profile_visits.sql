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
