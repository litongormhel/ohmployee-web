-- ============================================================
-- OHMployee — Migration: Fix Overloaded fn_get_applicant_status_options
-- Prompt ID : OHM2026_2027
-- Date      : 2026-05-21
-- ============================================================
-- ROOT CAUSE:
--   Migration 20260520700000 created:
--     fn_get_applicant_status_options(p_include_inactive boolean DEFAULT false)
--     → 1-parameter signature
--
--   Migration 20260521900000 used CREATE OR REPLACE with a different
--   parameter list:
--     fn_get_applicant_status_options(p_include_inactive boolean DEFAULT false,
--                                     p_exclude_system_only boolean DEFAULT false)
--     → CREATE OR REPLACE does NOT replace across different signatures.
--       PostgreSQL registers it as a NEW overload.
--
--   Result: two functions exist under the same name with different arities.
--   PostgREST cannot choose between them → runtime error:
--     "Could not choose the best candidate function between:
--      public.fn_get_applicant_status_options(p_include_inactive => boolean),
--      public.fn_get_applicant_status_options(p_include_inactive => boolean,
--                                              p_exclude_system_only => boolean)"
--
-- FIX (this migration):
--   §1  Drop the 1-parameter overload. One signature remains.
--   §2  CREATE OR REPLACE the canonical 2-parameter function (idempotent).
--       Default values preserve all old callers — no Flutter changes required.
--   §3  Idempotent system-only guard for `hired` and `confirmed_onboard`.
--       `hired` is not in the current seed but may exist in live DB as a
--       legacy value. `confirmed_onboard` was seeded as system-only but an
--       accidental UPDATE could have cleared it; this re-asserts the flag.
--   §4  Re-assert GRANT on canonical signature.
--
-- CALLER COMPATIBILITY AFTER THIS MIGRATION:
--   fn_get_applicant_status_options()           → both defaults false → all active
--   fn_get_applicant_status_options(false)      → same as above
--   fn_get_applicant_status_options(false,true) → exclude system-only (7 manual)
--   fn_get_applicant_status_options(false,false)→ all active (12 rows)
--   fn_get_applicant_status_options(true,false) → include inactive rows too
--
-- DEPENDENCIES:
--   20260520700000_applicant_backend_infra.sql must be applied first.
--   20260521900000_fix_applicant_status_transition_rules.sql must be applied first.
--
-- NO CHANGES TO:
--   - Any table schema or seeds
--   - Any other RPC
--   - RLS policies
--   - Flutter/Dart code
-- ============================================================

-- ============================================================
-- §1  DROP THE 1-PARAMETER OVERLOAD
--     This is the root of the PostgREST ambiguity.
--     IF NOT EXISTS guard: safe to run on a DB where the overload
--     was never created or was already cleaned up manually.
-- ============================================================
DROP FUNCTION IF EXISTS public.fn_get_applicant_status_options(boolean);

-- ============================================================
-- §2  CANONICAL 2-PARAMETER FUNCTION (idempotent CREATE OR REPLACE)
--     Identical body to the one in 20260521900000 §2.
--     Included here so this patch is self-contained and re-asserting
--     the correct definition is safe even if 20260521900000 was
--     rolled back or partially applied.
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_get_applicant_status_options(
  p_include_inactive    boolean DEFAULT false,
  p_exclude_system_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'status_code',     s.status_code,
        'label',           s.label,
        'is_terminal',     s.is_terminal,
        'allow_on_create', s.allow_on_create,
        'is_system_only',  s.is_system_only,
        'color_key',       s.color_key,
        'sort_order',      s.sort_order,
        'is_active',       s.is_active
      ) ORDER BY s.sort_order
    ), '[]'::jsonb)
    FROM public.applicant_status_options s
    WHERE (p_include_inactive OR s.is_active = true)
      AND (NOT p_exclude_system_only OR s.is_system_only = false)
  );
END;
$$;

-- ============================================================
-- §3  DEFENSIVE SYSTEM-ONLY FLAG ASSERTIONS (idempotent)
--     These statuses must never appear in a manual dropdown.
--     confirmed_onboard and transferred are seeded correctly in
--     20260520700000; did_not_report and rejected_by_ops are
--     corrected in 20260521900000. This block is a safety net
--     in case any of those rows were accidentally modified.
--
--     `hired` is NOT in the current seed but may exist in a live
--     DB as a legacy label. If found, it is system-only — it is
--     set by backend onboarding RPCs, not manual selection.
-- ============================================================
UPDATE public.applicant_status_options
SET    is_system_only = true,
       updated_at     = now()
WHERE  status_code IN (
         'confirmed_onboard',
         'transferred',
         'endorsed',
         'did_not_report',
         'rejected_by_ops',
         'hired'           -- defensive: not in current seed; no-op if absent
       )
  AND  is_system_only = false;  -- idempotent: only touches rows that need fixing

-- ============================================================
-- §4  GRANT ON CANONICAL SIGNATURE
--     Drop of the 1-param function also removed its ACLs.
--     Re-assert the grant on the canonical 2-param function.
--     (20260521900000 already granted this; included here for
--     self-contained safety.)
-- ============================================================
GRANT EXECUTE ON FUNCTION public.fn_get_applicant_status_options(boolean, boolean)
  TO authenticated, service_role;

-- ============================================================
-- §5  VALIDATION QUERIES
--     Run these in Supabase SQL Editor after applying this migration.
-- ============================================================

-- V1: Confirm exactly ONE function signature exists
-- SELECT proname,
--        pronargs,
--        proargnames::text,
--        pg_get_function_arguments(oid) AS signature
-- FROM   pg_proc
-- WHERE  proname         = 'fn_get_applicant_status_options'
--   AND  pronamespace    = 'public'::regnamespace;
--
-- Expected: exactly 1 row
--   pronargs  = 2
--   signature = "p_include_inactive boolean DEFAULT false,
--                p_exclude_system_only boolean DEFAULT false"

-- V2: Call with (false, true) — Add Applicant / Status Update dialog
--     Returns only non-system-only, active statuses (7 rows expected)
-- SELECT jsonb_array_elements(
--   public.fn_get_applicant_status_options(false, true)
-- ) ->> 'status_code' AS status_code;
--
-- Expected codes (7):
--   new, for_interview, for_requirements, for_onboard,
--   backout, rejected, failed
--
-- Must NOT appear:
--   transferred, endorsed, confirmed_onboard, did_not_report, rejected_by_ops, hired

-- V3: Call with (false, false) — All active statuses (including system-only)
-- SELECT jsonb_array_elements(
--   public.fn_get_applicant_status_options(false, false)
-- ) ->> 'status_code' AS status_code;
--
-- Expected: all is_active=true rows (12 rows from standard seed)

-- V4: No-arg backward-compat call — must resolve without ambiguity
-- SELECT public.fn_get_applicant_status_options();
-- Expected: same as V3 result (both defaults = false)

-- V5: Confirm system-only flags are correct
-- SELECT status_code, label, is_terminal, is_system_only
-- FROM   public.applicant_status_options
-- ORDER  BY sort_order;
--
-- Expected is_system_only = true:
--   transferred, endorsed, confirmed_onboard, did_not_report, rejected_by_ops
--   (+ hired if that row exists in live DB)
--
-- Expected is_system_only = false AND is_terminal = true (manual terminal):
--   backout, rejected, failed
--
-- Expected is_system_only = false AND is_terminal = false (active/manual):
--   new, for_interview, for_requirements, for_onboard
-- ============================================================
