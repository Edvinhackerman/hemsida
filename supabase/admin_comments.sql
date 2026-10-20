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

create or replace function public.admin_update_place(
  p_place_id bigint,
  p_name text,
  p_city text,
  p_description text,
  p_rating numeric,
  p_latitude numeric,
  p_longitude numeric
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

  update public.places
  set name = trim(p_name),
      city = nullif(trim(coalesce(p_city, '')), ''),
      description = coalesce(p_description, ''),
      rating = p_rating,
      latitude = p_latitude,
      longitude = p_longitude
  where id = p_place_id;

  get diagnostics updated_count = row_count;
  if updated_count = 0 then
    raise exception 'Place not found';
  end if;
end;
$$;

revoke all on function public.admin_update_place(bigint, text, text, text, numeric, numeric, numeric) from public, anon;
grant execute on function public.admin_update_place(bigint, text, text, text, numeric, numeric, numeric) to authenticated;
