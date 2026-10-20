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
