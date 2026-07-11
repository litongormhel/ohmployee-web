-- ============================================================
-- ohm#6v9q2m8x — Fix Plantilla Import for 1000+ Rows
-- Migration: 20261215000011_fix_plantilla_import_large_batch_support.sql
-- ============================================================
-- Root causes
-- -----------
--   1. submit_plantilla_baseline_import and approve_plantilla_import_batch
--      use per-row PL/pgSQL loops with individual INSERTs and EXISTS queries.
--      For 1000+ rows these exceed Supabase's default 30-second statement
--      timeout, causing the import to fail with a cancellation error.
--
--   2. get_plantilla_import_rows returns SETOF with no LIMIT clause.
--      PostgREST enforces max_rows = 1000 on all SETOF API calls, silently
--      truncating batches with >1000 rows. The review screen then shows fewer
--      rows than were uploaded, and any subsequent Flutter pagination loop
--      (which terminates when the page is smaller than the page size) halts
--      early.
--
-- Fixes
-- -----
--   §1  ALTER submit_plantilla_baseline_import — raise statement_timeout to
--       5 minutes so row loops can complete for up to 5000-row batches.
--
--   §2  ALTER approve_plantilla_import_batch — same timeout increase for the
--       store+employee+allocation upsert loops at commit time.
--
--   §3  DROP + recreate get_plantilla_import_rows — add optional p_offset /
--       p_limit parameters so the Flutter client can page through large result
--       sets in chunks of 500, staying under the PostgREST max_rows cap.
--       The old 1-arg overload is dropped to avoid overload ambiguity.
--
-- No table schema changes. No data changes.
-- ============================================================


-- ── §1  Raise timeout for submit ────────────────────────────────────────────

ALTER FUNCTION public.submit_plantilla_baseline_import(text, uuid, uuid, jsonb)
  SET statement_timeout TO '300000';


-- ── §2  Raise timeout for approve ───────────────────────────────────────────

ALTER FUNCTION public.approve_plantilla_import_batch(uuid)
  SET statement_timeout TO '300000';


-- ── §3  Paginated get_plantilla_import_rows ──────────────────────────────────
-- Drop the old 1-arg signature to avoid overload ambiguity in PostgREST, then
-- recreate with optional offset/limit params.  Callers that pass only p_batch_id
-- get the default first 500 rows; callers that pass p_offset/p_limit get the
-- requested page.  Flutter must call in a loop until a page < p_limit is returned.

DROP FUNCTION IF EXISTS public.get_plantilla_import_rows(uuid);

CREATE OR REPLACE FUNCTION public.get_plantilla_import_rows(
  p_batch_id uuid,
  p_offset   integer DEFAULT 0,
  p_limit    integer DEFAULT 500
)
RETURNS SETOF public.plantilla_import_rows
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
  SELECT r.*
    FROM public.plantilla_import_rows r
   WHERE r.batch_id = p_batch_id
     AND (
       public.i_have_full_access()
       OR EXISTS (
         SELECT 1
           FROM public.plantilla_import_batches b
          WHERE b.id = r.batch_id
            AND b.uploaded_by = auth.uid()
       )
     )
   ORDER BY r.row_number
   LIMIT  GREATEST(1, LEAST(p_limit, 1000))
   OFFSET GREATEST(0, p_offset);
$func$;

REVOKE ALL ON FUNCTION public.get_plantilla_import_rows(uuid, integer, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_plantilla_import_rows(uuid, integer, integer) TO authenticated;

COMMENT ON FUNCTION public.get_plantilla_import_rows(uuid, integer, integer) IS
  'ohm#6v9q2m8x: paginated row fetch for import review. '
  'p_limit is clamped to 1–1000 so callers cannot exceed PostgREST max_rows. '
  'Loop until returned row count < p_limit to collect all rows.';
