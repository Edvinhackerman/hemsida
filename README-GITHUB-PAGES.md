# EDVINS BADVLOGG – GitHub Pages

This project uses Vite and GitHub Actions to deploy to:
https://edvinhackerman.github.io/hemsida/

## GitHub repository

Repository name: `hemsida`

## Required GitHub Actions secrets

In GitHub: Settings → Secrets and variables → Actions → New repository secret

Create:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Use the same values as your local `.env` file. Do not upload `.env` to GitHub.

## Shared favorites

Before deploying the shared favorites leaderboard, open the Supabase SQL Editor and run `supabase/place_favorites.sql`.

The migration stores one favorite per browser and bathing spot. The public site can read aggregate counts but cannot read visitor IDs directly. Existing browser favorites are synced the next time that browser visits after the migration is installed.

## Admin comment moderation

To enable comment deletion, run `supabase/admin_comments.sql` in the Supabase SQL Editor. Create an email/password user under Authentication → Users, then grant that user admin access in the SQL Editor:

```sql
insert into public.site_admins (user_id)
select id from auth.users where email = 'admin@example.com'
on conflict do nothing;
```

Replace the example email with the admin account's email. The hidden admin panel still requires this authenticated account, and deletion is checked again by the database.

The admin migration also contains the place-editing function. Run the updated `supabase/admin_comments.sql` again after updating the project files to enable it; running the script again is safe.

## GitHub Pages

Settings → Pages → Source: GitHub Actions

After pushing to `main`, the workflow builds the Vite app and publishes `dist/`.
