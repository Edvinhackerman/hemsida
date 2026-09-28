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

## GitHub Pages

Settings → Pages → Source: GitHub Actions

After pushing to `main`, the workflow builds the Vite app and publishes `dist/`.
