# One Day Closer — Prayer & Bible Reading Journal (Prototype v1)

A mobile-friendly web app for logging prayers and daily Bible reading, with reading streaks and prayer groups.

## Features in this prototype
- **Accounts** — sign up / log in with email + password (salted SHA-256 hash).
- **Prayer log** — write prayers, add tags (people, events, topics), pick a date, view by date, search, filter by tag, mark answered, make public/private, share to a group.
- **Bible reading log** — pick book (all 66), chapter range, verse range, notes and tags. Live reference preview (e.g. `John 3:16–18`) and a "Read ↗" link to the passage.
- **Streaks** — current streak, longest streak, total days, 12-week heatmap, confetti at milestones (3, 7, 14, 30… days).
- **Groups** — create groups, add members by email, chat, share prayer requests with a "🙏 Praying" reaction.
  - **Owner**: all settings, promote/demote admins, transfer ownership, delete group
  - **Admin**: edit name/description, add & remove members
  - **Member**: chat; can add people / share prayers only if the owner allows it
- **Community** — feed of anything users chose to make public. Everything else is private by default.
- **Export** — download your own data as JSON.

## Libraries (all free, loaded from CDN — no build step)
- [Alpine.js](https://alpinejs.dev) — reactivity
- [Tailwind CSS](https://tailwindcss.com) (Play CDN) — styling
- [canvas-confetti](https://github.com/catdad/canvas-confetti) — streak celebrations
- Google Fonts: Inter + Lora

## Project structure
The working app is still the single `index.html` in the repo root. The folders below are where its code will move and where the backend will go. Each one has a short README explaining its purpose.

```
├── index.html            the live app
├── frontend/             runs in the browser
│   ├── assets/           images, icons, fonts, styles
│   ├── components/       UI shared between features
│   ├── services/         storage and backend access
│   └── features/
│       ├── accounts/     sign-up, log-in, sessions
│       ├── prayers/      prayer log
│       ├── bible-reading/ reading log
│       ├── streaks/      streaks and heatmap
│       ├── groups/       groups, chat, roles
│       └── community/    public feed
├── backend/              notes on the Supabase backend
│   ├── auth/             real accounts and verification
│   └── functions/        trusted server actions
├── database/             shared database
│   ├── migrations/       table definitions
│   ├── policies/         who can see what
│   ├── seeds/            test data
│   └── tests/            security rule tests
└── docs/                 notes and decisions
```

## Run it
Open `index.html` in a browser. That's it.

**Testing groups:** on the login screen click *"Create two demo accounts"* (password `demo123`), then open a second browser tab and log in as a different user — the tabs sync live.

## Deploy to GitHub Pages
1. Create a repo and push `index.html` + `README.md` to the `main` branch.
2. Repo → **Settings → Pages** → Source: *Deploy from a branch* → `main` / `(root)` → Save.
3. Your app will be live at `https://<username>.github.io/<repo>/`.

## Backend
The login system uses [Supabase](https://supabase.com), and it switches on once `frontend/services/supabase-config.js` is filled in. Follow [docs/backend-setup.md](docs/backend-setup.md). Until then, the app uses browser-only prototype accounts.

The database tables and security rules cover every feature, but only accounts are connected so far.

## Current limits (important)
Prayers, readings, groups and community posts are still stored in the browser's `localStorage`, so they live **only on that device/browser**. Groups only work between accounts on the same browser. This is not real privacy or security: anyone with access to the browser can read the data.

## Next step
Connect each feature to the database by replacing the `store` and `persist()` calls in `index.html` with Supabase queries. The tables are `profiles, prayers, readings, groups, group_members, messages, message_praying`, and group membership and role changes go through the functions in `database/policies`.
