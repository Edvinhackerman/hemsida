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

## Import more bathing places

To add the supplied locations with IDs 75–145, run `supabase/add_places_75_145.sql` in the Supabase SQL Editor. Existing IDs are left unchanged. The script reports how many rows it inserted or skipped. IDs 50–74 are not included in this batch.

## Admin comment moderation

To enable comment deletion, run `supabase/admin_comments.sql` in the Supabase SQL Editor. Create an email/password user under Authentication → Users, then grant that user admin access in the SQL Editor:

```sql
insert into public.site_admins (user_id)
select id from auth.users where email = 'admin@example.com'
on conflict do nothing;
```

Replace the example email with the admin account's email. The hidden admin panel still requires this authenticated account, and deletion is checked again by the database.

The admin migration also contains the place-editing function and the structured amenities field (parking, toilet, pier, child-friendly, grill, changing room, and kiosk). Run the updated `supabase/admin_comments.sql` again after updating the project files to enable these fields; running the script again is safe.

## Profiles and place suggestions

Run `supabase/place_favorites.sql` first, then run the latest `supabase/admin_comments.sql` in the Supabase SQL Editor. Both scripts are safe to rerun. The admin script adds account profiles, account-owned comments, place verification dates, and a moderated place-suggestion queue.

Enable email sign-ups in Supabase Authentication settings. Set the Site URL to the published site and add the local Vite URL to the allowed redirect URLs when testing locally. If email confirmation is enabled, new users must confirm their address before signing in.

Visitors can submit place suggestions from a place's detail view. Suggestions do not change published data; an admin reviews them in the Admin → Förslag tab. Admins can edit place information and mark its last-verified date in Admin → Platser.

## Visited places and achievements

After running `supabase/admin_comments.sql`, run `supabase/profile_visits.sql` in the Supabase SQL Editor. Signed-in users can mark bathing places as visited and earn achievements. Profiles are private by default; users can opt in to sharing their display name, visited places, and achievements through a public profile link. The migration is safe to rerun.

## Feature ideas and municipal contacts

After `supabase/admin_comments.sql` and `supabase/profile_visits.sql`, run `supabase/feature_ideas_and_contacts.sql` in the Supabase SQL Editor. Anyone can read the ideas board; signed-in users can submit ideas, vote, and discuss them. Admins can change idea statuses and moderate comments in the hidden Admin → Idéforum panel.

Municipal error-report links are deliberately shown only for contacts with a verification date. In Admin → Platser, add the municipality's official report link, an official source confirming the bathing place, and the date you verified the links. Do this only for confirmed municipal bathing places; incomplete or unverified contacts are not shown publicly.

## GitHub Pages

Settings → Pages → Source: GitHub Actions

After pushing to `main`, the workflow builds the Vite app and publishes `dist/`.
