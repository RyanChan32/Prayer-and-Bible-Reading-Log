# Backend setup

This connects the app to [Supabase](https://supabase.com), which provides the login system and database. It takes about 15 minutes. Until you finish step 3, the app keeps using its browser-only prototype accounts.

## 1. Create the project
1. Sign up at supabase.com and create a new project on the free plan.
2. Save the database password it asks you to choose somewhere safe.

## 2. Create the database
In your project, open **SQL Editor**. Paste and run each file's full contents, in this order:
1. `database/migrations/0001_schema.sql`
2. `database/policies/0001_row_level_security.sql`

Each should report success. Run each file only once: a second run fails because the tables already exist.

## 3. Connect the app
1. In Supabase, open **Project Settings → API** (or **API Keys**) and copy the **Project URL** and the **anon** or **publishable** key.
2. Paste them into `frontend/services/supabase-config.js`.

Never use the **service_role** or **secret** key here. It bypasses all the security rules, and this file is public.

## 4. Set up the email links
Open **Authentication → URL Configuration**:
- **Site URL:** where the app is hosted, such as `https://ryanchan32.github.io/Prayer-and-Bible-Reading-Log/`
- **Redirect URLs:** add the same address

Confirmation and password reset links return people to these addresses, so they need the app published on a real web address. A file opened by double-clicking won't work for them.

## 5. Publish and test
1. Commit and push your changes, then turn on GitHub Pages if it isn't already on (see the main README).
2. On the live site, sign up with your own email, click the confirmation link and log in.
3. Log out, use **Forgot your password?** and confirm the reset works.

## Before real people use it
- **Email limits:** Supabase's built-in email service only allows a few messages per hour. Add your own email provider under **Authentication → Emails → SMTP Settings**.
- **Journal data:** prayers, readings and groups aren't connected to the database yet. See below.

## What's connected so far
| Piece | Status |
|---|---|
| Sign-up, log-in, log-out, password reset | Connected |
| Tables and security rules for all features | Written and tested, not yet used by the app |
| Prayers, readings, streaks, groups, community | Still saved only in the browser |

Accounts made in the prototype can't be moved to Supabase, because the new system has its own user IDs. People need to sign up again, and entries saved under an old prototype account won't appear under the new one.

## Testing the security rules
This runs the tables and rules in a temporary database on your computer. It doesn't touch your Supabase project.

```bash
cd database/tests
npm install
npm test
```
