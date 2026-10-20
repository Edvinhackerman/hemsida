create table if not exists public.place_favorites (
  place_id bigint not null,
  visitor_id text not null,
  created_at timestamptz not null default now(),
  primary key (place_id, visitor_id)
);

alter table public.place_favorites enable row level security;
revoke all on table public.place_favorites from public, anon, authenticated;

grant usage on schema public to anon, authenticated;

create or replace function public.set_place_favorite(
  p_place_id bigint,
  p_visitor_id text,
  p_is_favorite boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  favorite_key text;
begin
  if auth.uid() is null and (p_visitor_id is null or length(trim(p_visitor_id)) < 8 or length(p_visitor_id) > 128) then
    raise exception 'Invalid visitor id';
  end if;

  favorite_key := case
    when auth.uid() is not null then 'user:' || auth.uid()::text
    else p_visitor_id
  end;

  if not exists (select 1 from public.places where id = p_place_id) then
    raise exception 'Unknown place id';
  end if;

  if p_is_favorite then
    insert into public.place_favorites (place_id, visitor_id)
    values (p_place_id, favorite_key)
    on conflict (place_id, visitor_id) do nothing;
  else
    delete from public.place_favorites
    where place_id = p_place_id and visitor_id = favorite_key;
  end if;
end;
$$;

create or replace function public.get_place_favorite_counts()
returns table (place_id bigint, favorite_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select favorites.place_id, count(*)::bigint
  from public.place_favorites as favorites
  group by favorites.place_id;
$$;

revoke all on function public.set_place_favorite(bigint, text, boolean) from public;
revoke all on function public.get_place_favorite_counts() from public;
grant execute on function public.set_place_favorite(bigint, text, boolean) to anon, authenticated;
grant execute on function public.get_place_favorite_counts() to anon, authenticated;

create or replace function public.get_my_place_favorites()
returns table (place_id bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select favorites.place_id
  from public.place_favorites as favorites
  where auth.uid() is not null
    and favorites.visitor_id = 'user:' || auth.uid()::text;
$$;

revoke all on function public.get_my_place_favorites() from public, anon;
grant execute on function public.get_my_place_favorites() to authenticated;
