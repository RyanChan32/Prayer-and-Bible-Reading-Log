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

## Run it
Open `index.html` in a browser. That's it.

**Testing groups:** on the login screen click *"Create two demo accounts"* (password `demo123`), then open a second browser tab and log in as a different user — the tabs sync live.

## Deploy to GitHub Pages
1. Create a repo and push `index.html` + `README.md` to the `main` branch.
2. Repo → **Settings → Pages** → Source: *Deploy from a branch* → `main` / `(root)` → Save.
3. Your app will be live at `https://<username>.github.io/<repo>/`.

## Prototype limits (important)
Data is stored in the browser's `localStorage`, so it lives **only on that device/browser**. Groups only work between accounts on the same browser. This is not real privacy or security — anyone with access to the browser can read the data.

## Next step: real backend
GitHub Pages only hosts static files, so pair it with a free hosted backend. Recommended: **Supabase** (free tier):
- Supabase Auth → real email sign-up and verification
- Postgres tables: `profiles, prayers, readings, groups, group_members, messages`
- **Row Level Security** → enforces "only you can see your posts unless public" at the database level
- Realtime → live group chat

All data access in `index.html` already goes through the user-filtered getters and the `store` object, so swapping in Supabase means replacing those calls rather than rewriting the UI.
