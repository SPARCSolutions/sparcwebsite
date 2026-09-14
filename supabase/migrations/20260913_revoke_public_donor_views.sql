-- 2026-09-13 — close public read access to donor data via SECURITY DEFINER views.
--
-- Found during a privacy audit of project ldxpockcgcxvsrbyhcnt.
--
-- Every table in `public` has RLS enabled (80 of them with no policies at all,
-- i.e. service-role only), so direct reads as `anon` correctly returned nothing.
-- These five VIEWS, however, are SECURITY DEFINER: they run as their owner and
-- therefore bypass the RLS on the snap_* / donations_* tables underneath. SELECT
-- was granted to `anon`, so all five were readable over the public REST API using
-- the publishable key that is embedded in every page of the website:
--
--   constituent_richness   2078 rows  full_name, primary_email, lifetime_giving,
--                                     is_deceased
--   donations_canonical      97 rows  donor_name, donor_email, amount,
--                                     stripe_subscription_id
--   donation_ack_status      99 rows  donor_name, amount, donation_date
--   constituent_clusters    288 rows  norm_name, emails, account_numbers
--   asked_this_year         254 rows  grant/ask pipeline
--
-- Verified reachable pre-fix with a plain curl + anon key; verified 401
-- "permission denied for view" after.
--
-- Safe to revoke: no page in this repo references any of these five views, and
-- the Development Dashboard reads them via service_role, which grants do not
-- gate. The curated public access_* views are deliberately readable and are
-- left alone.
--
-- The underlying leak is the SECURITY DEFINER property; revoking the grants
-- closes the exposure. Converting these to SECURITY INVOKER (Postgres 15+
-- `WITH (security_invoker = on)`) would remove the RLS bypass at the source and
-- is the better long-term fix.

revoke all on public.constituent_richness  from anon, authenticated, public;
revoke all on public.donations_canonical   from anon, authenticated, public;
revoke all on public.donation_ack_status   from anon, authenticated, public;
revoke all on public.constituent_clusters  from anon, authenticated, public;
revoke all on public.asked_this_year       from anon, authenticated, public;
