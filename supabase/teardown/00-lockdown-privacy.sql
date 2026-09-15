-- ============================================================================
-- SPARC — lock the database down to private
-- Target: Supabase project ldxpockcgcxvsrbyhcnt
-- Verified against the live database on 2026-09-15.
--
-- Run this FIRST. It is independent of the teardown and safe to run on its own:
-- it removes access nobody is using, and changes nothing the public website,
-- /access, /art or the Google Sheets sync depend on.
--
-- WHERE THE DATABASE ALREADY STANDS (measured, not assumed):
--   * RLS is enabled on all 104 public tables.
--   * `anon` has NO policy on anything except the access_* tables, which are
--     deliberately public. So unauthenticated read of donor data is already
--     closed, and the 2026-09-13 revoke on the donor views has held.
--
-- WHAT IS ACTUALLY OPEN — three real problems, in severity order.
-- ============================================================================


-- ============================================================================
-- 1. CRITICAL — public.call_edge() is a service-role escalation open to anyone
--
-- call_edge(fn text, payload jsonb) is SECURITY DEFINER, and its EXECUTE is
-- granted to PUBLIC and to `anon`. Its body reads `cron_token` (falling back to
-- `service_role_key`) out of system_config and POSTs to
--   https://ldxpockcgcxvsrbyhcnt.supabase.co/functions/v1/<fn>
-- with that token as the Authorization header, where <fn> is caller-supplied.
--
-- The anon key is published in the website's own JavaScript. So anyone who
-- views source can call this RPC and invoke ANY edge function in the project
-- with privileged credentials — donor-ops, bloomerang, letters, gmail-archive —
-- without ever authenticating. The caller never sees the token, but they do get
-- to act with it.
--
-- Revoking from PUBLIC/anon/authenticated does not affect the cron jobs: they
-- run as `postgres`, which keeps EXECUTE.
-- ============================================================================

revoke execute on function public.call_edge(text, jsonb) from public, anon, authenticated;

-- Same treatment for the other SECURITY DEFINER functions that are needlessly
-- world-executable. record_outreach writes donor outreach rows; rls_auto_enable
-- is internal plumbing. Neither is called from any public page.
revoke execute on function public.record_outreach(text, jsonb, text, text, text, text, text)
  from public, anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- KEEP as-is: access_role() must stay executable by anon — /access and /art
-- call it to decide what a visitor may see.


-- ============================================================================
-- 2. HIGH — 15 policies hand every signed-in user the donor-ops tables
--
-- Each of these is `FOR SELECT TO authenticated USING (true)` — no ownership
-- test, no tenant test. In Supabase `authenticated` means any holder of a valid
-- JWT for this project, not "SPARC staff". crm_inbox and crm_inbox_attachment
-- go further and allow UPDATE with USING(true) WITH CHECK(true), so such a user
-- can rewrite donor triage rows.
--
-- The tables themselves hold donor names, emails, gift detail and email bodies.
--
-- Every one of these tables is in the teardown, so dropping them closes this
-- too. These statements are here so the hole is shut immediately, whether or
-- not you run the teardown today, and so that re-creating any of these tables
-- later does not quietly restore the policy.
-- ============================================================================

drop policy if exists ask_answers_auth_select              on public.ask_answers;
drop policy if exists crm_duplicate_candidate_auth_select  on public.crm_duplicate_candidate;
drop policy if exists crm_inbox_auth_select                on public.crm_inbox;
drop policy if exists crm_inbox_auth_update                on public.crm_inbox;
drop policy if exists crm_inbox_attachment_auth_select     on public.crm_inbox_attachment;
drop policy if exists crm_inbox_attachment_auth_update     on public.crm_inbox_attachment;
drop policy if exists crm_lookup_auth_select               on public.crm_lookup;
drop policy if exists crm_push_log_auth_select             on public.crm_push_log;
drop policy if exists crm_trust_rule_auth_select           on public.crm_trust_rule;
drop policy if exists doc_revisions_auth_select            on public.doc_revisions;
drop policy if exists follow_ups_auth_select               on public.follow_ups;
drop policy if exists task_scan_messages_auth_select       on public.task_scan_messages;
drop policy if exists task_scan_runs_auth_select           on public.task_scan_runs;
drop policy if exists tasks_auth_select                    on public.tasks;
drop policy if exists tasks_completed_auth_select          on public.tasks_completed;


-- ============================================================================
-- 3. MEDIUM — blanket table GRANTs to anon/authenticated, across the board
--
-- Every table carries GRANTs to anon and authenticated. Today they are inert,
-- because RLS is on and most tables have no policy. But the grant is the part
-- that survives a mistake: the day someone adds a policy for convenience, or
-- runs `alter table ... disable row level security` to debug, the data is live
-- to the internet. Defence in depth — take the grant away too.
--
-- Deliberately skipped, because the public site depends on them:
--   access_*           the /access, /art and /accesstrails surfaces
-- The website's own forms and gallery are NOT skipped: summit, volunteer and
-- photo-gallery all reach the database through edge functions running as
-- service_role, which RLS and these grants do not constrain.
-- ============================================================================

do $$
declare r record;
begin
  for r in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r','v')
      and c.relname not like 'access\_%'
  loop
    execute format('revoke all on public.%I from anon, authenticated', r.relname);
  end loop;
end $$;


-- ============================================================================
-- 4. VERIFY — all three should come back empty.
-- ============================================================================

-- 4a. No SECURITY DEFINER function still executable by anon, except access_role.
select p.proname, array_to_string(p.proacl,' | ') as acl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and p.proname <> 'access_role'
  and (array_to_string(p.proacl,',') like '%anon=X%'
       or p.proacl is null);   -- null ACL = default PUBLIC EXECUTE

-- 4b. No policy outside access_* grants blanket access.
select tablename, policyname, roles::text, cmd, qual
from pg_policies
where schemaname='public' and tablename not like 'access\_%'
  and coalesce(qual,'true') = 'true';

-- 4c. No table outside access_* is still granted to anon or authenticated.
select table_name, grantee, string_agg(privilege_type, ',') as privs
from information_schema.role_table_grants
where table_schema='public' and grantee in ('anon','authenticated')
  and table_name not like 'access\_%'
group by table_name, grantee
order by table_name;


-- ============================================================================
-- 5. ONE THING TO REVIEW BY EYE — the four deliberately public views
--
-- access_community_board, access_public_stats, access_trails_community and
-- access_trails_public are all SECURITY DEFINER (security_invoker is off), and
-- readable by anon. That is intended — they are what /access and /art render —
-- but it means each one bypasses RLS on its base tables and shows exactly the
-- columns it selects, to the whole internet.
--
-- They read access_barrier_checks, access_locations, access_public_reports and
-- access_trails_submissions, which also carry submitter detail. Worth one pass
-- confirming no email, phone or exact home address reaches these four views:
--
--   select pg_get_viewdef('public.access_community_board'::regclass, true);
--   select pg_get_viewdef('public.access_public_stats'::regclass, true);
--   select pg_get_viewdef('public.access_trails_community'::regclass, true);
--   select pg_get_viewdef('public.access_trails_public'::regclass, true);
--
-- Left alone here on purpose: changing them without looking would take /access
-- and /art down, and you asked to keep both.
-- ============================================================================
