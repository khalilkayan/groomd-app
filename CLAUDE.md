# CLAUDE.md

Working notes for AI-assisted development on this repository.

## Project overview

Groomd is a beauty and wellness booking MVP for the Lebanese market. Customers browse
businesses, pick a service, staff member, date, and time, and book. Business owners sign in to a
dashboard scoped to the businesses they own, where they review bookings, change booking
statuses, add manual bookings, and block slots.

It is a portfolio prototype: a functional MVP, not a launched or production-ready product.

## Architecture summary

- **Frontend:** one file, `index.html`. Vanilla HTML, CSS, and JavaScript. No framework, no
  build step, no bundler. State lives in module-level variables; `render()` redraws from state.
- **Backend:** Supabase — PostgreSQL, Auth, PostgREST, and database functions.
- **Data access:** direct `fetch` calls to `/rest/v1/<table>`, sending the publishable key plus
  the signed-in user's access token when a session exists. Tables in use: `businesses`,
  `business_services`, `business_staff`, `business_amenities`, `business_owners`, `bookings`,
  and `profiles`.
- **Availability:** the `get_booked_slots` RPC (`/rest/v1/rpc/get_booked_slots`) takes a
  business id, staff name, and date, and returns taken times only. It is queried on demand —
  there is no Realtime subscription.
- **Authorization:** enforced in PostgreSQL via Row Level Security and table grants — never in
  the browser. Client code sends requests; the database decides what comes back.
- **Fallback:** if Supabase is unreachable, bundled demo data keeps the UI rendering.
- **Schema:** the base schema lives in the Supabase project, not this repo. The applied
  privilege, policy, constraint, and function hardening is recorded in
  `supabase/security-hardening.sql` for review; it is not a bootstrap script.

## Local run command

```bash
python3 -m http.server 5500
```

Then open http://localhost:5500. Serve over HTTP rather than opening the file directly, so
Supabase Auth session handling behaves normally.

## Important security boundaries

- **Never expose a Supabase service-role key in browser code.** No exceptions, not even
  temporarily while debugging.
- **The browser publishable/anon key is public by design.** It identifies the anonymous client
  and provides only the access allowed by the project's database grants and Row Level Security
  policies. It is not a secret and does not need to be hidden — but it is also not inert, so
  authorization must be enforced with grants and RLS, never by concealing the key or hiding UI
  in the client.
- **Treat authentication, database, and live-input values as untrusted at rendering boundaries.**
  A value coming back from Supabase or from the auth session is still attacker-influenceable
  content.
- **Customer- and user-writable values require escaping.** That means booking fields, profile
  fields, notes, and anything derived from the auth session. Operator-managed catalog content
  (businesses, services, staff, amenities) is currently treated as trusted only because ordinary
  app users cannot edit it — if self-service catalog editing is ever added, that content becomes
  user-writable and must be escaped at every rendering boundary too.
- **Preserve the `esc` and `escJs` protections.** `esc` escapes text for HTML text nodes and
  quoted attributes; `escJs` escapes values that land inside a single-quoted JS string within a
  double-quoted HTML attribute (e.g. `onclick="fn('HERE')"`). Do not remove these calls, and add
  them when introducing new interpolation of user-controlled data.
- **Do not log customer names, emails, phone numbers, booking payloads, access tokens, or raw
  database responses.** Log counts, statuses, and non-identifying markers instead. This is a
  forward-looking guardrail for new code, not a claim that every existing diagnostic message has
  already been cleaned up — some generic error strings remain and should be reviewed before any
  production use.
- **Do not modify RLS policies or booking permissions without separately verifying customer,
  owner, and anonymous access.** All three paths must be re-checked; a change that fixes one can
  silently open or break another.
- **Keep anonymous guest bookings local-only** unless a new abuse-resistant backend design is
  deliberately introduced. Guests must not be able to read back other people's rows.
- **Do not commit or push unless explicitly asked.**

## Verification checklist

Before considering a change to booking, auth, or dashboard behavior done, manually check in the
browser:

- [ ] Sign up and log in as a customer; the profile shows the right account.
- [ ] Book a service: service, staff, date, and time selection all work, and the booking appears
      in My Bookings.
- [ ] Already-taken times are shown as unavailable for the selected business, staff, and date.
- [ ] Booking an already-taken active slot is rejected rather than silently duplicated.
- [ ] Cancel, reschedule, and rebook each produce the expected booking state.
- [ ] Log out: the signed-in user's backend bookings disappear from the UI.
- [ ] As a guest (not signed in), My Bookings shows only this session's local bookings — never
      anyone else's rows.
- [ ] Sign in as a business owner: the dashboard opens and shows only that owner's business.
- [ ] Owner actions work — status updates, manual booking, and blocking a slot.
- [ ] A non-owner account cannot open the dashboard or read another business's bookings.
- [ ] The browser console contains no customer names, emails, phone numbers, tokens, or raw row
      dumps.
