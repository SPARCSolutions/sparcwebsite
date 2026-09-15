-- ============================================================================
-- SPARC — donor-ops / Development Dashboard teardown
-- Target: Supabase project ldxpockcgcxvsrbyhcnt
-- Verified against the live database on 2026-09-15.
--
-- SCOPE
--   GO   — the sparc-donor-ops backend and the tables behind /devdash.
--   STAY — the Google Sheets sync and every table it touches.
--   STAY — the public website, /access, /art and /accesstrails.
--
-- Run 00-lockdown-privacy.sql first. It is independent of this file and closes
-- a service-role escalation that is open right now.
--
-- ORDER MATTERS. Part 1 stops the jobs that REFILL these tables. Skip it and
-- three active cron jobs put the data back — snap_* returns at 07:30 UTC the
-- next morning.
--
-- Irreversible from Part 2 on. Back up first:
--   Supabase Dashboard -> Database -> Backups, or `supabase db dump`.
-- ============================================================================


-- ============================================================================
-- PART 0 — SURVEY (read-only)
-- ============================================================================

select c.relname,
       case c.relkind when 'r' then 'table' when 'v' then 'view' end as kind,
       pg_size_pretty(pg_total_relation_size(c.oid)) as size,
       c.reltuples::bigint as est_rows
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relkind in ('r','v')
order by pg_total_relation_size(c.oid) desc;

select jobid, schedule, active, command from cron.job order by jobid;


-- ============================================================================
-- PART 1 — STOP THE WRITERS FIRST
--
-- All 14 cron jobs in this project belong to donor-ops. Three are ACTIVE and
-- each refills part of the drop set:
--
--   jobid  4  20 11 * * 1-5  bloomerang-ack      -> bloomerang_acknowledgments
--   jobid  5  0  7  * * 0    bloomerang sync     -> crm_account_map
--   jobid 12  30 7  * * *    bloomerang-snapshot -> snap_* (all 11 tables)
--
-- The other eleven (2, 7, 8, 9, 13-19: daily-sweep, tasks, gift-scan,
-- donation-sync, asks-autodraft) are already inactive but still scheduled.
--
-- The Sheets sync has NO cron job — it is invoked through
-- invoke_sheets_sync(), which this does not touch. Nothing below affects it.
--
-- Re-check the ids against Part 0 before running; ids change if a job is
-- ever dropped and recreated.
-- ============================================================================

select cron.unschedule(jobid) from cron.job;

select count(*) as jobs_remaining from cron.job;   -- expect 0


-- ============================================================================
-- PART 2 — VIEWS OVER DONOR DATA
--
-- Dropped first and explicitly, so the cascades in Part 3 are deliberate
-- rather than silent. Verified dependencies:
--   constituent_richness <- snap_addresses, snap_constituents, snap_emails,
--                           snap_phones, snap_transactions, crm_account_map
--   constituent_clusters <- constituent_richness
--   donation_ack_status  <- donations_canonical, thank_you_letters,
--                           bloomerang_acknowledgments, crm_account_map
--   donations_canonical  <- donations_staging, gift_types   (a VIEW, not a table)
--
-- NOT dropped: asked_this_year. It reads auction_pipeline, gala_outreach,
-- grants and sponsorships — all Sheets tables. It survives this teardown.
-- ============================================================================

begin;

drop view if exists public.constituent_clusters cascade;
drop view if exists public.constituent_richness cascade;
drop view if exists public.donation_ack_status  cascade;
drop view if exists public.donations_canonical  cascade;

commit;


-- ============================================================================
-- PART 3 — TABLES
--
-- Run as one transaction. Read Part 0's output, then flip the final
-- `rollback` to `commit`.
-- ============================================================================

begin;

-- 3a. Bloomerang mirror.
drop table if exists public.snap_addresses     cascade;
drop table if exists public.snap_attachments   cascade;
drop table if exists public.snap_constituents  cascade;
drop table if exists public.snap_emails        cascade;
drop table if exists public.snap_households    cascade;
drop table if exists public.snap_interactions  cascade;
drop table if exists public.snap_notes         cascade;
drop table if exists public.snap_phones        cascade;
drop table if exists public.snap_relationships cascade;
drop table if exists public.snap_transactions  cascade;
drop table if exists public.snap_tributes      cascade;
drop table if exists public.bloomerang_acknowledgments cascade;
drop table if exists public.crm_account_map            cascade;
drop table if exists public.constituent_notes_sent     cascade;

-- 3b. CRM triage + push pipeline (children before parents).
drop table if exists public.crm_inbox_attachment    cascade;
drop table if exists public.crm_push_log            cascade;
drop table if exists public.crm_trust_rule          cascade;
drop table if exists public.crm_write_ledger        cascade;
drop table if exists public.crm_inbox               cascade;
drop table if exists public.crm_lookup              cascade;
drop table if exists public.crm_duplicate_candidate cascade;
drop table if exists public.crm_sender_collision    cascade;
drop table if exists public.crm_sender_map          cascade;
drop type  if exists public.crm_inbox_status        cascade;

-- 3c. Dashboard sign-in.
drop table if exists public.app_sessions    cascade;
drop table if exists public.password_resets cascade;
drop table if exists public.app_users       cascade;

-- 3d. Task / ask / doc extraction (the tasks, asks and docs edge functions).
drop table if exists public.ask_answers        cascade;
drop table if exists public.follow_ups         cascade;
drop table if exists public.tasks_completed    cascade;
drop table if exists public.tasks              cascade;
drop table if exists public.task_scan_messages cascade;
drop table if exists public.task_scan_runs     cascade;
drop table if exists public.doc_revisions      cascade;
drop table if exists public.question_dismissals cascade;

-- 3e. Email ingest and Gmail OAuth.
drop table if exists public.email_attachments  cascade;
drop table if exists public.email_connections  cascade;
drop table if exists public.email_sent_log     cascade;
drop table if exists public.emails_raw         cascade;   -- 17 MB, the largest table here
drop table if exists public.gmail_tokens       cascade;
drop table if exists public.attach_sweep_state cascade;
drop table if exists public.sweep_notes        cascade;

-- 3f. Donation processing.
drop table if exists public.duplicates           cascade;
drop table if exists public.donations_quarantine cascade;
drop table if exists public.donations_approved   cascade;
drop table if exists public.donations_staging    cascade;
drop table if exists public.donations_form       cascade;
drop table if exists public.donations_stripe     cascade;
drop table if exists public.donor_categories     cascade;

-- 3g. Gala / event operations.
--     The website's gala pages (/gala, /galaguest, /gala-register,
--     /auctiondonation, /donate, /events) were checked: none of them reference
--     Supabase at all. They are static and unaffected by everything here.
drop table if exists public.auction_bids           cascade;
drop table if exists public.auction_item_donations cascade;
drop table if exists public.auction_items          cascade;
drop table if exists public.raffle_tickets         cascade;
drop table if exists public.event_checkin_log      cascade;
drop table if exists public.event_checkins         cascade;
drop table if exists public.rsvps                  cascade;
drop table if exists public.rsvp_candidates        cascade;
drop table if exists public.pledges                cascade;
drop table if exists public.events                 cascade;

-- 3h. Outreach, letters and reporting.
drop table if exists public.outreach_attempts        cascade;
drop table if exists public.outreach_messages        cascade;
drop table if exists public.outreach_campaigns       cascade;
drop table if exists public.letter_drafts            cascade;
drop table if exists public.letter_rules             cascade;
drop table if exists public.high_value_donors_monthly cascade;
drop table if exists public.monthly_donors           cascade;
drop table if exists public.sponsor_exclusions       cascade;
drop table if exists public.sponsorship_candidates   cascade;
drop table if exists public.source_tombstones        cascade;
drop table if exists public.ops_memory               cascade;

-- 3i. Functions. Signatures verified against pg_proc — the zero-argument
--     spellings used in the earlier draft would have matched nothing and
--     silently succeeded.
drop function if exists public.snap_reset()                     cascade;
drop function if exists public.crm_seed_sender_map()            cascade;
drop function if exists public.crm_build_duplicate_candidates() cascade;
drop function if exists public.crm_inbox_touch_updated_at()     cascade;
drop function if exists public.crm_email_base(text)             cascade;
drop function if exists public.crm_is_office_email(text)        cascade;
drop function if exists public.crm_norm_email(text)             cascade;
drop function if exists public.crm_norm_name(text)              cascade;
drop function if exists public.claim_crm_write(text, text, bigint, uuid) cascade;
drop function if exists public.complete_crm_write(text, bigint) cascade;
drop function if exists public.release_crm_write(text)          cascade;
drop function if exists public.archive_checked_tasks()          cascade;
drop function if exists public.match_open_task(text)            cascade;
drop function if exists public.record_outreach(text, jsonb, text, text, text, text, text) cascade;
drop function if exists public.donation_fingerprint(text, numeric, timestamp without time zone) cascade;
drop function if exists public.auction_email_guard()            cascade;

rollback;  -- <-- change to commit when you are satisfied


-- ============================================================================
-- PART 4 — DECIDE THESE YOURSELF. Not dropped above.
--
-- Each one is arguably donor-ops, but destroys something with no other copy.
-- Uncomment only what you have actually decided on.
--
--   thank_you_letters (9 rows)
--     The archive of acknowledgement letters — drive links, what went to Debi,
--     when. The Sheets tracker tab keeps its own letter_status / letter_drive_url
--     / letter_sent_at columns on donation_tracker, so the SHEET loses nothing.
--     What you lose is the history behind those columns.
--
--   audit_log (452 rows)
--     Who did what in the dashboard. Worth keeping as a record even after the
--     thing it audited is gone.
--
--   gift_types
--     Lookup table; its only reader was the donations_canonical view, dropped
--     in Part 2. Safe, but it is a reference list you may want to keep.
--
--   call_edge(text, jsonb) / call_edge_svc(text, jsonb)
--     Generic "invoke an edge function from SQL" plumbing. Once Part 1 has
--     unscheduled every job, nothing calls either one. call_edge is the
--     escalation described in the lockdown script; 00-lockdown-privacy.sql
--     revokes public EXECUTE, and dropping it closes the matter for good.
--     Do NOT drop invoke_sheets_sync() or sheets_sync_result() — those are
--     the Sheets path.
-- ============================================================================

-- drop table    if exists public.thank_you_letters cascade;
-- drop table    if exists public.audit_log         cascade;
-- drop table    if exists public.gift_types        cascade;
-- drop function if exists public.call_edge(text, jsonb)     cascade;
-- drop function if exists public.call_edge_svc(text, jsonb) cascade;


-- ============================================================================
-- PART 5 — KEEP-LIST. Verified. Nothing here may be dropped.
-- ============================================================================
--
-- GOOGLE SHEETS SYNC — confirmed by reading the deployed sheets-sync source,
-- not by matching names:
--   grants               Grants spreadsheet (3 tabs)
--   auction_pipeline     Auction Items spreadsheet (3 tabs)
--   task_list            Task List spreadsheet (open + Completed)
--   sponsorships         Sponsor Outreach -> Confirmed Sponsorship
--   gala_outreach        Sponsor Outreach -> 2026 Outreach, Sponsor Prospects
--   donation_tracker     Sponsor Outreach -> Donation Received & Thank You Letters
--   tuition_payments     Sponsor Outreach -> Tuition Checks
--   system_config        holds sponsor_outreach_sheet_id, cron_token
--   sheet_sync_log       per-tab sync history
--   asked_this_year      view, built only from Sheets tables
--   functions: invoke_sheets_sync(jsonb), sheets_sync_result(bigint),
--              task_list_biu(), sponsorships_null_guard(), set_updated_at(),
--              touch_updated_at(), update_updated_at_column()
--   edge functions: sheets-sync, sheets-write-tab
--
--   ONE KNOWN EFFECT ON THE SHEET: the tracker tab's "Bloomerang Acknowledged"
--   column is fed by bloomerang_acknowledgments through crm_account_map, both
--   dropped in 3a. The column stops refreshing and freezes at today's values.
--   It is 1 true out of 70 rows, so the practical loss is small — but it does
--   become a column that no longer means anything. Every other column on every
--   tab is unaffected.
--
-- PUBLIC WEBSITE
--   summit_virtual_registrations, summit_email_relay_config
--   volunteer_applications, volunteer_email_relay_config
--   gallery_photos, gallery_people, gallery_faces, gallery_face_rejections,
--   gallery_photo_people, gallery_categories, photo_gallery_config
--   every gallery_* RPC and the `gallery` storage bucket
--   edge functions: virtual-summit-register, volunteer-register, photo-gallery
--
-- /access, /art AND /accesstrails — these read the access_* TABLES directly
-- through the anon key, not only the views. The original draft's keep-list said
-- "the access_* views", which understated it badly:
--   access_audit_log, access_barrier_checks, access_events, access_locations,
--   access_parties, access_photos, access_public_reports, access_staff,
--   access_staff_emails, access_submission_photos, access_submissions,
--   access_trails_submissions
--   views: access_community_board, access_public_stats,
--          access_trails_community, access_trails_public
--   functions: access_role(), access_guard_publish(),
--              access_check_target_visible(uuid, uuid)


-- ============================================================================
-- PART 6 — COMPANION STEPS (not runnable from SQL)
--
-- 19 of the project's 25 edge functions are donor-ops. Delete in the Dashboard
-- (Edge Functions), or:
--   supabase functions delete <slug> --project-ref ldxpockcgcxvsrbyhcnt
--
--   donor-ops            bloomerang           bloomerang-ack
--   bloomerang-snapshot  bloomerang-attach    daily-sweep
--   gift-scan            donation-sync        donations-view
--   constituent-notes    letters              letter-gen
--   gala-outreach        asks                 asks-autodraft
--   tasks                docs                 gmail-auth
--   gmail-archive        mail-archive
--
-- KEEP these six: sheets-sync, sheets-write-tab, virtual-summit-register,
--                 volunteer-register, photo-gallery.
--
-- SECRETS — revoke in Project Settings once the functions above are gone:
--   ANTHROPIC_API_KEY, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, the Bloomerang
--   API key. KEEP GOOGLE_SA_JSON — sheets-sync authenticates to Google with it.
--
-- REPO — these directories become dead once the functions are deleted:
--   supabase/functions/tasks/, supabase/functions/asks/, supabase/functions/docs/
--   supabase/migrations/20260806_crm_*.sql  (4 files, now describing nothing)
--   scripts/find-duplicate-constituents.ts, scripts/load-bloomerang-snapshot.ts
-- Left in place here — deleting repo files is a separate commit, and the
-- migrations are a record of what the database used to be.
-- ============================================================================
