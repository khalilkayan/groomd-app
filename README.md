# Groomd

Groomd is a functional full-stack beauty and wellness booking MVP designed for the Lebanese market. It was built with Claude Code in VS Code, using vanilla HTML, CSS, JavaScript, and Supabase.

## Overview

Groomd connects customers with barbershops, salons, nail studios, and spas. Customers browse
businesses, pick a service, staff member, date, and available time, and confirm a booking.
Business owners sign in to a dashboard scoped to their own business, where they review bookings,
update their status, create manual bookings, and block slots they are unavailable for. It is a
portfolio prototype centered on an end-to-end booking workflow backed by Supabase and
database-enforced authorization, rather than a static UI mockup.

## Key Features

**Customer experience**

- Browse and search businesses, and view their services and staff
- Select a service, staff member, date, and available time
- Customer authentication and profiles (Supabase Auth)
- Create and view bookings, cancel them, and reschedule or rebook appointments
- Session-based saved businesses, and booking history for signed-in customers

**Business-owner experience**

- Business-specific owner dashboard, scoped to the businesses the signed-in account owns
- View that business's bookings and update their statuses (`pending`, `upcoming`, `confirmed`,
  `completed`, `cancelled`)
- Add manual bookings taken by phone or walk-in, and block unavailable appointment slots

**Backend**

- Supabase Authentication and PostgreSQL, with Row Level Security across the public application
  tables and role- and ownership-based authorization
- On-demand availability lookup through the `get_booked_slots` RPC, and active-slot
  double-booking protection via a partial unique index
- Guest mode is session-local; retrievable booking history requires authentication

## Technology

Vanilla HTML, CSS, and JavaScript with no build step or framework; Supabase (PostgreSQL, Auth,
PostgREST, RPC) reached through REST endpoints called with `fetch` plus the
`@supabase/supabase-js` auth client; built in VS Code with Claude Code.

## Architecture

The frontend is a single `index.html` file containing markup, styles, and application logic.
State lives in module-level JavaScript variables, and a `render()` function redraws the UI from
that state. Data reaches Supabase two ways:

1. **Catalog and bookings** over the PostgREST API (`/rest/v1/<table>`), carrying the browser's
   publishable key plus the signed-in user's access token when a session exists. Tables in use:
   `businesses`, `business_services`, `business_staff`, `business_amenities`, `business_owners`,
   `bookings`, and `profiles`.
2. **Availability** through the `get_booked_slots` function (`/rest/v1/rpc/get_booked_slots`),
   queried on demand for a business, staff member, and date, returning taken times only — an RPC
   query, not a Supabase Realtime subscription.

Authorization is not enforced in the browser. The client sends a request; PostgreSQL decides
what it may see or change, through RLS policies and least-privilege table and column grants. The
owner dashboard, for instance, asks `business_owners` for its businesses without a user filter,
and RLS returns only the caller's rows. If Supabase is unreachable, bundled demo data keeps the
UI rendering.

## Running Locally

The frontend is static, so any local HTTP server works. From the repository root:

```bash
python3 -m http.server 5500
```

Then open http://localhost:5500. Serve over HTTP rather than opening the file directly, so
Supabase Auth session handling behaves normally.

The Supabase URL and publishable key are embedded in `index.html`. That key identifies the
anonymous client and provides only the access allowed by the project's database grants and RLS
policies — not a secret, and not a substitute for authorization. No service-role key is present
in client code, and none should ever be added.

## AI-Assisted Development

Kayan led product requirements, feature decisions, acceptance criteria, and browser verification.
Claude Code accelerated iterative implementation, debugging, code review, and security hardening.
The workflow remained human-directed and evidence-based: changes were inspected and important
customer and owner flows were verified before acceptance.

## Security

The full model is documented in [docs/security.md](docs/security.md). The rules that matter:

- Authenticated customers create bookings under their own user id, select only their own rows,
  and cancel through a status-only update — not arbitrary row modification.
- Owners are restricted to bookings for businesses they own, and anonymous users have no
  persistent booking-table access after the security hardening.
- Availability is exposed as times only, never customer details, and two active bookings cannot
  occupy the same slot — enforced by a partial unique index, not client-side checks alone.
- Customer-writable, authentication-derived, and booking values are escaped at the relevant
  rendering boundaries; logging reduces exposure of direct customer identifiers and booking
  write payloads.

## Current Status

Groomd is a functional MVP and portfolio prototype. It has not been commercially launched and is
not presented as production-ready. Its shape reflects deliberate scoping, with known next steps:

- The frontend intentionally remains one `index.html` file; modularizing it behind a build
  pipeline is the natural next step.
- No real-payment processor is integrated; payment method is a label on a booking, so no money
  moves and no payment data is handled.
- Core authentication, booking, rescheduling, and owner-dashboard flows were verified manually
  in the browser; an automated suite is the main testing gap.
- Catalog content is operator-managed and not writable by ordinary app users, keeping the write
  surface small; self-service onboarding would be a feature addition.

## Project Structure

```
.
├── index.html                  # Entire frontend: markup, styles, state, rendering, data access
├── docs/security.md            # Security model, authorization rules, MVP limitations
├── supabase/
│   ├── README.md               # Scope and caveats for the SQL below
│   └── security-hardening.sql  # Applied privilege, policy, constraint, function changes
├── CLAUDE.md                   # Working notes and guardrails for AI-assisted development
└── README.md
```

The base schema — table definitions, original owner policies, the new-user trigger, and the
`get_booked_slots` function — remains managed in the Supabase project itself.
`supabase/security-hardening.sql` records the hardening applied on top of it so those changes are
reviewable here; it is not a bootstrap schema and will not recreate the database.
