# Security Model

This document describes how Groomd protects booking data, who is allowed to see and change what,
and which protections this MVP does not yet have. Groomd is a portfolio prototype, not a launched
product, and this document is written to be accurate about that.

## Security model

The guiding rule is that **the browser is not trusted to enforce anything**.

The frontend is a single static `index.html` file. Anyone can read it, edit it, and issue their
own requests with the same credentials the page uses. So every rule that actually matters lives
in PostgreSQL: Row Level Security policies decide which rows a caller can read or write, and
table grants decide which operations are available at all. The client sends a request; the
database decides the answer.

The browser holds a Supabase **publishable (anon) key**. That key is public by design: it
identifies the anonymous client and provides exactly the access allowed by the project's
database grants and Row Level Security policies — no more, and no less. It is not a secret, but
it is also not inert, which is why the database grants and RLS policies behind it matter. No
service-role key exists anywhere in client code, and adding one would defeat the entire model.
When a user is signed in, requests carry that user's access token instead, and the database
evaluates policies against their identity.

The applied privilege, policy, constraint, and function changes described below are recorded in
[`supabase/security-hardening.sql`](../supabase/security-hardening.sql), so the claims in this
document can be checked against the SQL that produced them.

## Customer booking ownership

Bookings are owned by the customer who made them, through a `customer_id` column tied to the
Supabase Auth user id. Customer permissions are deliberately narrow:

- **Insert.** Authenticated customers insert bookings for their own user id with status
  `upcoming`. The insert policy checks both conditions (`customer_id = auth.uid()` and
  `status = 'upcoming'`), so a customer cannot create a booking attributed to someone else, nor
  self-issue one that is already `confirmed`. The insert grant is column-scoped rather than
  table-wide.
- **Select.** They select only their own bookings. The client queries
  `bookings?customer_id=eq.<their id>`, and RLS independently enforces the same restriction, so
  a modified client cannot widen the query to read other people's rows.
- **Update.** Their update permission is limited to the `status` column — the grant itself is
  `UPDATE (status)`, so no other column is writable — and the cancellation policy requires the
  new value to be `cancelled`. A customer can cancel; a customer cannot silently change a
  booking's price, date, staff member, or owner-set status.

On sign-out, backend-loaded bookings are dropped from client state, so the next person to use
the browser does not see the previous user's appointments.

## Business-owner authorization

Owner access is derived from a `business_owners` table that maps an authenticated account to the
business ids it owns.

When a user opens the dashboard, the client asks `business_owners` for its rows **without
supplying a user filter**. Row Level Security returns only the businesses that caller actually
owns. If the result is empty, the dashboard does not open.

This matters: the client never decides who is an owner. It asks, and the database answers.
Owners are restricted to bookings associated with businesses they own — for reads and for status
changes alike — so manipulating `dashboardBusinessId` in the browser does not grant access to
another business's bookings.

## Least-privilege database grants

The hardening revoked all privileges on the application tables from both `anon` and
`authenticated`, then re-granted only what each flow actually needs.

The anonymous role can read public catalog content — businesses, services, staff, amenities —
because that is what an unauthenticated visitor must see to browse. It has **no** access to
`bookings`, `business_owners`, or `profiles`.

The authenticated role gets `SELECT` on catalog tables, `business_owners`, and `bookings`
(narrowed further by RLS); a **column-scoped** `INSERT` on `bookings` listing exactly the
bookable fields; `UPDATE (status)` on `bookings`; and `SELECT` plus `UPDATE (full_name, phone)`
on `profiles`. Column-level grants matter here: even if a policy were mistakenly written too
loosely, the grant still prevents writes to columns outside that list.

Execute privileges were narrowed too. `get_booked_slots` is executable by `anon` and
`authenticated`, while the internal `handle_new_user` and `rls_auto_enable` functions are not
executable by either. `handle_new_user` runs `SECURITY DEFINER` with an empty `search_path`, so
it cannot be redirected through an attacker-controlled schema. No client role holds service-role
capability.

## Row Level Security

Row Level Security is enabled across the public application tables. Public `SELECT` policies
exist only for catalog data — businesses, services, staff, and amenities — which is content
intended to be browsable by anyone. Every other table's policies are scoped to an identity:

- A customer may act on rows where they are the customer, within the column limits above.
- An owner may act on rows belonging to a business they own.
- Anonymous callers have no persistent booking-table access at all after the hardening.

Because RLS is evaluated per row inside PostgreSQL, these rules hold regardless of what query
the client constructs. The `bookings` table additionally constrains `status` to the known set
(`pending`, `upcoming`, `confirmed`, `completed`, `cancelled`) via a check constraint, and
`business_id` and `status` are both `NOT NULL`.

## Slot-availability RPC behavior

Availability is served by a database function, `get_booked_slots`, called over
`/rest/v1/rpc/get_booked_slots` with a business id, staff name, and date.

It returns **taken times only**. It does not return customer names, phone numbers, emails,
prices, notes, or booking ids. This is a deliberate boundary: showing which slots are unavailable
is necessary to book, but revealing who booked them is not. A visitor can learn that 3:00 PM is
taken; they cannot learn whose appointment it is.

The RPC is used in two places — to grey out unavailable times in the picker, and to re-check the
chosen time immediately before submitting a booking.

## Double-booking protection

Two layers guard against two customers claiming the same slot:

1. **A pre-submit check.** Before inserting, the client re-queries `get_booked_slots` for the
   selected business, staff, and date, and refuses if the chosen time is already taken.
2. **A partial unique index** on active bookings (`bookings_no_double_active_slot`) covering
   business, staff, date, and time. It is partial because it applies only to rows in an active
   state — `pending`, `upcoming`, or `confirmed` — which is what allows a cancelled booking to
   free its slot without colliding with the replacement.

The second layer is the one that actually guarantees correctness. The client check is a UX
courtesy and is inherently racy: two people can pass it simultaneously. The partial unique index
resolves that race, and the client detects the resulting conflict (a `23505` unique violation
surfacing as HTTP 409) and tells the user the slot was just taken rather than showing a generic
failure.

Cancelled bookings fall outside the index predicate, so a freed time becomes bookable again.

## Client-side output escaping

Because the UI renders dynamic values through HTML string interpolation, customer-writable,
authentication-derived, and booking values must be escaped at the relevant rendering boundaries.
Two helpers support this:

- **`esc(value)`** — escapes `&`, `<`, `>`, `"`, and `'` for HTML text nodes and quoted attribute
  values. `null` and `undefined` become empty strings, while `0`, `false`, and `''` are
  preserved, so escaping never silently changes what a legitimate value displays as.
- **`escJs(value)`** — for values that land inside a single-quoted JavaScript string that is
  itself inside a double-quoted HTML attribute, such as `onclick="fn('HERE')"`. It
  JavaScript-escapes backslashes, single quotes, and newlines *first*, then HTML-escapes the
  result, so the browser's attribute-decoding step cannot re-introduce a quote that breaks out
  of the JS string.

**What is escaped, precisely:** customer-writable values, authentication-derived values, and
booking values are escaped at the relevant rendering boundaries — customer names, phone numbers,
emails, notes, profile fields, and values read back from the auth session.

Operator-managed catalog fields — business names, service names, staff names, descriptions —
are currently treated as trusted, because ordinary app users cannot edit them; they are
maintained directly in the Supabase project by the operator. This is a defensible position for
the current data model, not a general-purpose one. The moment self-service catalog editing is
introduced, those fields become user-writable and every one of their rendering boundaries needs
the same escaping treatment. That is the single change most likely to turn a currently-safe
render into an injection point.

## Privacy-conscious logging

The application logs to the browser console for debugging. Direct customer identifiers and
booking write payloads were removed or reduced during hardening: logging now favours row counts,
statuses, and short markers such as `MY_BOOKINGS_ROWS: rows=3`, `BOOKING_SLOT_TAKEN`, or
`AUTH_STATE_CHANGED: signed-in` over names, emails, phone numbers, tokens, and full payloads.
This keeps personal data out of a place that is easy to screenshot, screen-share, or leave open
on a shared machine.

**This work is not finished.** Some generic diagnostic error messages remain, and error paths in
particular are where response text can still leak into the console. The logging surface should
be reviewed end-to-end before any production use rather than assumed clean.

## Guest-mode behavior

Visitors can browse and try the booking flow without an account, and the UI retains those guest
bookings in session state so the flow feels complete.

The database, however, does not persist them: after the hardening, the anonymous role has no
insert or select privilege on `bookings`, and the guest insert policy was dropped. An
unauthenticated booking attempt is refused by the database, and the app does not fetch booking
rows back for an anonymous caller — which also means a guest cannot read anyone else's rows.

Retrievable booking history therefore requires an authenticated account. A guest who signs up
gets a real, database-backed history; a guest who does not keeps a local view that disappears
with the session.

## Remaining MVP limitations

Known gaps, stated plainly:

- **Single-file frontend prototype.** One `index.html` file, no build step or module boundaries.
  A deliberate MVP choice, not a production structure.
- **Manual browser verification rather than a full automated browser suite.** Customer and owner
  flows were tested by hand, so regression protection depends on repeating those checks.
- **No production payment integration.** Payment method is a label only; no processor is
  connected, so no payment data is handled and none of the associated compliance work applies.
- **No production-grade CAPTCHA or rate-limiting layer.** Beyond Supabase defaults, there is no
  application-level defense against automated signup, booking spam, or enumeration.
- **Business catalog content is operator-managed** rather than editable by ordinary app users.
  This keeps the catalog write surface small today, and is the assumption the escaping section
  above depends on.
- **Diagnostic logging needs a final pass** before production, as noted above.
