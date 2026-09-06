# Supabase

This folder records the security hardening applied to the deployed Groomd Supabase project.

## What this is

`security-hardening.sql` is a record of the privilege, policy, constraint, and function changes
that were applied to the live project. It is checked in so those changes are reviewable — so a
reader can see exactly which grants were revoked, which policies were replaced, and how the
database functions were pinned down, rather than having to take the README's word for it.

## What this is not

**This is not a complete database bootstrap or full schema export.** Running it against an empty
project will fail.

The base tables (`businesses`, `business_services`, `business_staff`, `business_amenities`,
`business_owners`, `bookings`, `profiles`), the original business-owner policies, the new-user
trigger, and the `get_booked_slots` RPC already existed in the deployed project before this
script was applied. The script assumes all of them are present and modifies them in place. There
is no `CREATE TABLE` here, and no seed data.

## Applying it

**Do not run this blindly against another project.** It revokes privileges wholesale before
re-granting a narrower set, drops and recreates policies by name, and replaces function bodies.
On a project whose schema differs — different column names, different policy names, a
`get_booked_slots` with a different signature — the result would range from an error to a
silently different authorization model.

Read it, map each statement to the target schema, and apply the parts that genuinely fit.
