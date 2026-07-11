-- ============================================================
-- OHM2026_0093 — Coverage Request Architecture Foundation
-- Migration: 20261021000000_coverage_request_foundation.sql
--
-- Phase 1 scope only:
--   - Coverage Request request/history tables
--   - request_type and request_status enums
--   - approval/audit fields
--   - read-scoped RLS
--
-- Explicitly out of scope:
--   - approval RPCs
--   - execution engine
--   - coverage group mutation
--   - HC, slot, vacancy, pipeline, dashboard, or CENCOM changes
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'request_type'
  ) THEN
    CREATE TYPE public.request_type AS ENUM (
      'create_coverage_group',
      'add_store',
      'remove_store',
      'convert_stationary_to_roving',
      'convert_roving_to_stationary',
      'merge_coverage_groups',
      'dissolve_coverage_group'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'request_status'
  ) THEN
    CREATE TYPE public.request_status AS ENUM (
      'draft',
      'pending',
      'approved',
      'rejected',
      'cancelled'
    );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.coverage_requests (
  id                            uuid                  NOT NULL DEFAULT gen_random_uuid(),
  request_type                  public.request_type   NOT NULL,
  status                        public.request_status NOT NULL DEFAULT 'draft'::public.request_status,

  -- Scope and typed references. These are structure references only; they do
  -- not imply HC demand, slot creation, vacancy creation, or pipeline creation.
  account_id                    uuid                  REFERENCES public.accounts(id) ON DELETE RESTRICT,
  position_id                   uuid                  REFERENCES public.positions(id) ON DELETE RESTRICT,
  employment_type               text,
  target_coverage_group_id      uuid                  REFERENCES public.coverage_groups(id) ON DELETE RESTRICT,
  source_coverage_group_id      uuid                  REFERENCES public.coverage_groups(id) ON DELETE RESTRICT,
  destination_coverage_group_id uuid                  REFERENCES public.coverage_groups(id) ON DELETE RESTRICT,

  -- Request-specific proposed structure. Future phases may validate this via
  -- request-type-specific RPCs before any execution engine exists.
  payload                       jsonb                 NOT NULL DEFAULT '{}'::jsonb,
  reason                        text,

  -- Requester audit.
  requested_by                  uuid                  NOT NULL REFERENCES public.users_profile(id) ON DELETE RESTRICT,
  requested_by_name             text                  NOT NULL,
  requested_by_role             text,
  requested_at                  timestamptz           NOT NULL DEFAULT now(),

  -- Submission audit.
  submitted_by                  uuid                  REFERENCES public.users_profile(id) ON DELETE SET NULL,
  submitted_by_name             text,
  submitted_at                  timestamptz,

  -- Approval/review audit. Phase 1 stores the contract only; no approval logic.
  approved_by                   uuid                  REFERENCES public.users_profile(id) ON DELETE SET NULL,
  approved_by_name              text,
  approved_at                   timestamptz,
  rejected_by                   uuid                  REFERENCES public.users_profile(id) ON DELETE SET NULL,
  rejected_by_name              text,
  rejected_at                   timestamptz,
  rejection_reason              text,
  cancelled_by                  uuid                  REFERENCES public.users_profile(id) ON DELETE SET NULL,
  cancelled_by_name             text,
  cancelled_at                  timestamptz,
  cancellation_reason           text,
  reviewer_remarks              text,

  -- Execution remains intentionally absent in Phase 1. These fields are
  -- reserved for traceability once a separate execution engine is designed.
  executed_at                   timestamptz,
  execution_summary             jsonb,

  -- Generic audit/soft-archive.
  created_at                    timestamptz           NOT NULL DEFAULT now(),
  created_by                    uuid                  REFERENCES public.users_profile(id) ON DELETE SET NULL,
  updated_at                    timestamptz           NOT NULL DEFAULT now(),
  updated_by                    uuid                  REFERENCES public.users_profile(id) ON DELETE SET NULL,
  archived_at                   timestamptz,
  archived_by                   uuid                  REFERENCES public.users_profile(id) ON DELETE SET NULL,
  archive_reason                text,

  CONSTRAINT coverage_requests_pkey PRIMARY KEY (id),
  CONSTRAINT coverage_requests_payload_object_chk CHECK (jsonb_typeof(payload) = 'object'),
  CONSTRAINT coverage_requests_execution_summary_object_chk
    CHECK (execution_summary IS NULL OR jsonb_typeof(execution_summary) = 'object'),
  CONSTRAINT coverage_requests_submitted_status_chk CHECK (
    (status = 'draft'::public.request_status AND submitted_at IS NULL)
    OR status <> 'draft'::public.request_status
  ),
  CONSTRAINT coverage_requests_approved_fields_chk CHECK (
    (status = 'approved'::public.request_status AND approved_at IS NOT NULL)
    OR status <> 'approved'::public.request_status
  ),
  CONSTRAINT coverage_requests_rejected_fields_chk CHECK (
    (status = 'rejected'::public.request_status AND rejected_at IS NOT NULL)
    OR status <> 'rejected'::public.request_status
  ),
  CONSTRAINT coverage_requests_cancelled_fields_chk CHECK (
    (status = 'cancelled'::public.request_status AND cancelled_at IS NOT NULL)
    OR status <> 'cancelled'::public.request_status
  )
);

COMMENT ON TABLE public.coverage_requests IS
  'ADR-001 Coverage Request foundation. Stores proposed changes to coverage '
  'structure only. A Coverage Request never creates HC, slots, vacancies, or '
  'pipeline rows.';
COMMENT ON COLUMN public.coverage_requests.payload IS
  'Request-specific proposed structure. Must stay structure-only; never encode '
  'workforce demand or downstream slot/vacancy execution.';
COMMENT ON COLUMN public.coverage_requests.executed_at IS
  'Reserved for a later execution engine. Phase 1 does not write this field.';

CREATE TABLE IF NOT EXISTS public.coverage_request_history (
  id                  uuid                  NOT NULL DEFAULT gen_random_uuid(),
  coverage_request_id uuid                  NOT NULL REFERENCES public.coverage_requests(id) ON DELETE RESTRICT,
  from_status         public.request_status,
  to_status           public.request_status,
  event_type          text                  NOT NULL,
  event_payload       jsonb                 NOT NULL DEFAULT '{}'::jsonb,
  actor_id            uuid                  REFERENCES public.users_profile(id) ON DELETE SET NULL,
  actor_name          text,
  actor_role          text,
  note                text,
  created_at          timestamptz           NOT NULL DEFAULT now(),

  CONSTRAINT coverage_request_history_pkey PRIMARY KEY (id),
  CONSTRAINT coverage_request_history_payload_object_chk CHECK (jsonb_typeof(event_payload) = 'object')
);

COMMENT ON TABLE public.coverage_request_history IS
  'Append-only audit trail for Coverage Request lifecycle changes. Phase 1 '
  'creates the table only; future RPCs will own writes.';

CREATE INDEX IF NOT EXISTS idx_coverage_requests_account_status
  ON public.coverage_requests (account_id, status, created_at DESC)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_coverage_requests_requested_by
  ON public.coverage_requests (requested_by, created_at DESC)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_coverage_requests_target_group
  ON public.coverage_requests (target_coverage_group_id)
  WHERE archived_at IS NULL AND target_coverage_group_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_coverage_requests_type_status
  ON public.coverage_requests (request_type, status, created_at DESC)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_coverage_request_history_request
  ON public.coverage_request_history (coverage_request_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_coverage_requests_updated_at ON public.coverage_requests;
CREATE TRIGGER trg_coverage_requests_updated_at
  BEFORE UPDATE ON public.coverage_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_set_updated_at();

ALTER TABLE public.coverage_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coverage_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE public.coverage_request_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coverage_request_history FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.coverage_requests FROM anon, authenticated;
REVOKE ALL ON public.coverage_request_history FROM anon, authenticated;
GRANT SELECT ON public.coverage_requests TO authenticated;
GRANT SELECT ON public.coverage_request_history TO authenticated;

DROP POLICY IF EXISTS coverage_requests_read_scoped ON public.coverage_requests;
CREATE POLICY coverage_requests_read_scoped
  ON public.coverage_requests
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR requested_by = public.get_current_profile_id()
    OR account_id = ANY (public.get_my_allowed_account_ids())
    OR EXISTS (
      SELECT 1
      FROM public.coverage_groups cg
      WHERE cg.id IN (
        coverage_requests.target_coverage_group_id,
        coverage_requests.source_coverage_group_id,
        coverage_requests.destination_coverage_group_id
      )
        AND cg.account_id = ANY (public.get_my_allowed_account_ids())
    )
  );

DROP POLICY IF EXISTS coverage_request_history_read_scoped ON public.coverage_request_history;
CREATE POLICY coverage_request_history_read_scoped
  ON public.coverage_request_history
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.coverage_requests cr
      WHERE cr.id = coverage_request_history.coverage_request_id
    )
  );

-- Phase 1 intentionally creates no INSERT/UPDATE/DELETE policies and no
-- mutation RPCs. Future request creation/review/execution must be introduced
-- through SECURITY DEFINER RPCs that preserve ADR-001.
