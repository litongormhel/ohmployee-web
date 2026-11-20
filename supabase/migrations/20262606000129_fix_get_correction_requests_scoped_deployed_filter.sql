-- ==============================================================================
-- Migration: 20262606000129_fix_get_correction_requests_scoped_deployed_filter.sql
-- Module   : HR Emploc / Corrections & Review Parity
-- Author   : Antigravity (ohm#emplocreviewparity01)
-- Date     : 2026-11-20
-- Purpose  : Fix silent bug where already deployed / transferred HR Emploc records
--            retaining historical correction_reason JSON were mapped as 'for_review'
--            via an unsafe catch-all ELSE 'for_review' fallback in get_correction_requests_scoped.
-- Invariants:
--   1. Deployed records (status = 'Moved to Plantilla' or hr_status = 'Transferred')
--      must NEVER appear in active correction or review queues.
--   2. Preserves exact table return signature and scoping logic across all roles.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.get_correction_requests_scoped(
  p_hr_emploc_id uuid DEFAULT NULL::uuid,
  p_status text DEFAULT NULL::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  hr_emploc_id uuid,
  applicant_id uuid,
  applicant_name text,
  group_id uuid,
  account_id uuid,
  assigned_hrco_id uuid,
  assigned_hrco_name text,
  requested_by uuid,
  requested_by_name text,
  requested_at timestamp with time zone,
  issue_type text,
  hr_remarks text,
  additional_remarks text,
  hrco_notes text,
  ops_update_message text,
  status text,
  sla_status text,
  allows_attachment boolean,
  last_updated_at timestamp with time zone,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  reopened_at timestamp with time zone,
  for_review_at timestamp with time zone,
  ready_at timestamp with time zone,
  attachment_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_my_id   uuid := public.get_my_profile_id();
  v_my_role text := public.get_my_role();
BEGIN
  IF v_my_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped AS (
    SELECT
      he.*,
      CASE
        WHEN he.hr_status = 'For Correction' THEN 'for_correction'
        WHEN he.hr_status = 'For Review' THEN 'for_review'
        WHEN he.hr_status = 'Complete'
             AND (NULLIF(BTRIM(COALESCE(he.employee_no, '')), '') IS NOT NULL
                  OR NULLIF(BTRIM(COALESCE(he.emploc_no, '')), '') IS NOT NULL)
          THEN 'ready'
        WHEN he.hr_status = 'Complete' THEN 'for_review'
        ELSE NULL
      END AS mapped_status
    FROM public.hr_emploc he
    WHERE he.deleted_at IS NULL
      AND he.correction_reason IS NOT NULL
      AND COALESCE(he.status, '') <> 'Moved to Plantilla'
      AND COALESCE(he.hr_status, '') NOT IN ('Transferred', 'Rejected')
  )
  SELECT
    he.id                                                              AS id,
    he.id                                                              AS hr_emploc_id,
    he.applicant_id                                                    AS applicant_id,
    COALESCE(he.applicant_name_snapshot, he.applicant_name)            AS applicant_name,
    a.group_id                                                         AS group_id,
    he.account_id                                                      AS account_id,
    he.hrco_user_id_snapshot                                           AS assigned_hrco_id,
    hrco.full_name                                                     AS assigned_hrco_name,
    he.updated_by                                                      AS requested_by,
    he.hr_reviewed_by                                                  AS requested_by_name,
    COALESCE(he.hr_reviewed_at, he.updated_at)                         AS requested_at,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN COALESCE(he.correction_reason->0->>'code', 'OTHER')
      ELSE COALESCE(he.correction_reason->>'type', 'OTHER')
    END                                                                AS issue_type,

    COALESCE(he.hr_remarks, '')                                        AS hr_remarks,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN he.correction_reason->0->>'comment'
      ELSE he.correction_reason->>'comment'
    END                                                                AS additional_remarks,

    he.ops_remarks                                                     AS hrco_notes,
    he.ops_remarks                                                     AS ops_update_message,
    he.mapped_status                                                   AS status,
    'normal'::text                                                     AS sla_status,

    CASE
      WHEN jsonb_typeof(he.correction_reason) = 'array'
      THEN EXISTS (
        SELECT 1
          FROM jsonb_array_elements(he.correction_reason) el
          JOIN public.hr_emploc_issue_types it ON it.code = el->>'code'
         WHERE it.allows_attachment = true
      )
      ELSE COALESCE(he.correction_reason->>'type', '') <> 'INVALID_BENEFITS'
    END                                                                AS allows_attachment,

    he.updated_at                                                      AS last_updated_at,
    NULL::uuid                                                         AS reviewed_by,
    NULL::timestamptz                                                  AS reviewed_at,
    NULL::timestamptz                                                  AS reopened_at,
    CASE WHEN he.mapped_status = 'for_review' THEN he.updated_at ELSE NULL::timestamptz END AS for_review_at,
    CASE WHEN he.mapped_status = 'ready' THEN he.updated_at ELSE NULL::timestamptz END      AS ready_at,

    COALESCE((
      SELECT COUNT(*)
        FROM public.hr_emploc_correction_attachments atch
       WHERE atch.hr_emploc_id = he.id AND atch.is_deleted = false
    ), 0)::bigint                                                      AS attachment_count

  FROM scoped he
  LEFT JOIN public.accounts a ON a.id = he.account_id
  LEFT JOIN public.users_profile hrco ON hrco.id = he.hrco_user_id_snapshot
  WHERE
    he.mapped_status IS NOT NULL
    AND (
      v_my_role NOT IN ('hrco')
      OR public.i_have_full_access()
      OR public.get_my_scope_type() = 'global'
      OR public.i_have_hrco_global_visibility()
      OR he.hrco_user_id_snapshot = v_my_id
      OR he.account = ANY (public.get_my_allowed_accounts())
      OR (he.account_id IS NOT NULL AND he.account_id IN (
        SELECT acc.id FROM public.accounts acc WHERE acc.account_name = ANY (public.get_my_allowed_accounts())
      ))
    )
    AND (p_hr_emploc_id IS NULL OR he.id = p_hr_emploc_id)
    AND (p_status IS NULL OR he.mapped_status = p_status)
  ORDER BY he.updated_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION public.get_correction_requests_scoped(uuid, text, integer, integer) IS
  'Scoped list of HR Emploc records with active correction requests. Excludes soft-deleted, deployed (Moved to Plantilla), and transferred/rejected records to eliminate silent queue leakage.';

REVOKE ALL ON FUNCTION public.get_correction_requests_scoped(uuid, text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_correction_requests_scoped(uuid, text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_correction_requests_scoped(uuid, text, integer, integer) TO authenticated;
