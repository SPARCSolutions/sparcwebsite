# Donor-ops teardown + privacy lockdown

Two scripts for Supabase project `ldxpockcgcxvsrbyhcnt`. Everything in them was
verified against the live database on 2026-09-15 — object names, table-vs-view,
function signatures, cron state and RLS posture were all read from the database,
not inferred from the READMEs.

Run in order. Neither runs itself: both end in `rollback` or keep the
destructive parts commented until you flip them.

| File | What it does | Destructive? |
|---|---|---|
| `00-lockdown-privacy.sql` | Closes the ways in | No — removes unused access only |
| `01-donor-ops-teardown.sql` | Drops the donor-ops / devdash schema | Yes, from Part 2 on |

## Run the lockdown first

It is independent of the teardown and worth running today either way.

**`public.call_edge(fn text, payload jsonb)` is a service-role escalation open
to the internet right now.** It is SECURITY DEFINER with EXECUTE granted to
PUBLIC and `anon`. It reads `cron_token` (falling back to `service_role_key`)
from `system_config` and POSTs to `functions/v1/<fn>` with that token, where
`<fn>` is supplied by the caller. The anon key is published in the website's
own JavaScript, so anyone who views source can invoke **any** edge function in
the project — `donor-ops`, `bloomerang`, `letters`, `gmail-archive` — with
privileged credentials, without authenticating.

Second: 15 policies read `FOR SELECT TO authenticated USING (true)` on the
donor-ops tables. In Supabase `authenticated` is any holder of a valid project
JWT, not "SPARC staff". `crm_inbox` and `crm_inbox_attachment` also allow
UPDATE that way, so such a user can rewrite donor triage rows.

What was already fine, measured rather than assumed: RLS is enabled on all 104
public tables, and `anon` holds no policy on anything outside `access_*`. The
2026-09-13 revoke on the donor views has held.

## What the teardown keeps

- **The Google Sheets sync**, and every table it reads or writes. Confirmed by
  reading the deployed `sheets-sync` source: `grants`, `auction_pipeline`,
  `task_list`, `sponsorships`, `gala_outreach`, `donation_tracker`,
  `tuition_payments`, `system_config`, `sheet_sync_log`. None of them are
  Bloomerang tables, so the teardown and the sync do not overlap.
- **The public website** — summit, volunteer and photo gallery.
- **`/access`, `/art` and `/accesstrails`**, which read the `access_*` **tables**
  directly through the anon key. The original draft's keep-list mentioned only
  "the access_* views"; dropping the tables under them would have taken all
  three surfaces down.

One real effect on the sheet: the tracker tab's "Bloomerang Acknowledged"
column is fed by `bloomerang_acknowledgments` through `crm_account_map`. Both
go, so that column freezes. It is 1 populated row out of 70.

## Corrections to the original draft

The draft's Part B claimed its four migrations "created exactly the objects
below and nothing else", and its Part C was explicitly guesswork. Against the
live database:

- **Three active cron jobs refill the drop set.** `bloomerang-snapshot` (daily
  07:30 UTC) rebuilds all 11 `snap_*` tables, `bloomerang-ack` rebuilds
  `bloomerang_acknowledgments`, `bloomerang` rebuilds `crm_account_map`. The
  draft dropped those tables without unscheduling anything, so they would have
  come back the next morning. Stopping the writers is now Part 1.
- **`donations_canonical` is a view, not a table.** The draft's
  `drop table ... donations_canonical` would have silently done nothing.
- **`call_edge()` and `call_edge_svc()` take `(text, jsonb)`.** The draft's
  zero-argument `drop function ... call_edge()` matched no function and, with
  `if exists`, would have succeeded while changing nothing.
- **Part B was not exhaustive.** `crm_account_map` and `crm_write_ledger` are
  `crm_*` tables those migrations did not create and the draft never listed.
- **`asked_this_year` should not be dropped.** It reads `auction_pipeline`,
  `gala_outreach`, `grants` and `sponsorships` — all Sheets tables, no donor
  input. The draft dropped it.
- **The draft covered 3 of 25 edge functions.** It named `tasks`, `asks` and
  `docs`; 19 are donor-ops. Deleting the tables while leaving the functions
  deployed leaves them erroring against missing objects.
- **The keep-list understated `/access` and `/art`**, as above.

## Not covered

Deleting the now-dead repo directories (`supabase/functions/{tasks,asks,docs}`,
the four `20260806_crm_*` migrations, the two `scripts/*.ts`) is left as a
separate commit — see Part 6 of the teardown.
