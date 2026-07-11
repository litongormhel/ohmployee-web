-- ============================================================
-- OHM2026_2058 — Deactivation Request v2 Foundation
-- Migration:  20260524100000_deactivation_v2_foundation.sql
-- Depends on: none (self-contained)
-- ============================================================
-- Sections:
--   §1  i_am_backoffice() helper
--   §2  plantilla.inactive_visible_until column
--   §3  employee_deactivation_requests table + RLS
--   §4  employee_deactivation_audit_log table + RLS
--   §5  Indexes
--
-- Preservation:  Legacy tables (deactivation_requests,
--   deactivation_batches, deactivation_items,
--   deactivation_audit_log) are NOT touched.
--
-- Validation Queries (run manually after applying):
--   V1 – Helper returns correct result for backoffice caller
--     SELECT public.i_am_backoffice();
--   V2 – New column exists on plantilla
--     SELECT column_name, data_type FROM information_schema.columns
--     WHERE table_name='plantilla' AND column_name='inactive_visible_until';
--   V3 – New tables exist
--     SELECT tablename FROM pg_tables
--     WHERE schemaname='public'
--       AND tablename IN (
--         'employee_deactivation_requests',
--         'employee_deactivation_audit_log'
--       );
--   V4 – RLS enabled on both new tables
--     SELECT tablename, rowsecurity FROM pg_tables
--     WHERE schemaname='public'
--       AND tablename IN (
--         'employee_deactivation_requests',
--         'employee_deactivation_audit_log'
--       );
--   V5 – RLS policies created
--     SELECT policyname, tablename FROM pg_policies
--     WHERE schemaname='public'
--       AND tablename IN (
--         'employee_deactivation_requests',
--         'employee_deactivation_audit_log'
--       );
--   V6 – Unique partial index exists
--     SELECT indexname FROM pg_indexes
--     WHERE tablename='employee_deactivation_requests'
--       AND indexname='uq_deact_req_pending_per_employee';
--   V7 – All supporting indexes exist
--     SELECT indexname FROM pg_indexes
--     WHERE tablename IN (
--       'employee_deactivation_requests',
--       'employee_deactivation_audit_log'
--     ) ORDER BY tablename, indexname;
-- ============================================================


-- ============================================================
-- §1  i_am_backoffice() helper
-- ============================================================
-- Role-name based check to avoid relying on a numeric level that
-- may drift across migrations. Matches 'Back Office', 'Backoffice',
-- and 'Backoffice Personnel' for forward compatibility.

CREATE OR REPLACE FUNCTION public.i_am_backoffice()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.get_my_role() IN (
    'Back Office',
    'Backoffice',
    'Backoffice Personnel'
  );
$$;

REVOKE ALL ON FUNCTION public.i_am_backoffice() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.i_am_backoffice() FROM anon;
GRANT EXECUTE ON FUNCTION public.i_am_backoffice() TO authenticated;

COMMENT ON FUNCTION public.i_am_backoffice() IS
  'Returns true when the authenticated caller is a Backoffice Personnel role. '
  'Used as RBAC guard in deactivation RPCs and RLS policies.';


-- ============================================================
-- §2  plantilla.inactive_visible_until column
-- ============================================================
-- 30-day Inactive tab visibility window. Controls when a Pending
-- Deactivation / Rejected Deactivation employee ages out of the
-- Inactive tab. NULL = no expiry window enforced for legacy rows.

ALTER TABLE public.plantilla
  ADD COLUMN IF NOT EXISTS inactive_visible_until timestamptz;

COMMENT ON COLUMN public.plantilla.inactive_visible_until IS
  'Timestamp after which the row is hidden from the Inactive tab. '
  'Set to NOW()+30d on Pending Deactivation and reset on rejection. '
  'Cleared (set to NULL) when the row transitions to Deactivated.';


-- ============================================================
-- §3  employee_deactivation_requests table
-- ============================================================
-- Individual-employee request tracking for the v2 workflow.
-- One row per request event (resubmits create new rows).
-- Legacy deactivation_requests table is preserved — do not join.

CREATE TABLE IF NOT EXISTS public.employee_deactivation_requests (
  -- Identity
  id                        uuid        NOT NULL DEFAULT gen_random_uuid(),
  plantilla_id              uuid        NOT NULL,
  requestor_profile_id      uuid        NOT NULL,

  -- Denormalized scope columns for efficient filtering
  group_id                  uuid,
  account_id                uuid        NOT NULL,

  -- Snapshot data (captured at request time — survives future edits)
  employee_name             text        NOT NULL,
  employee_no               text,
  account_name              text,

  -- Workflow
  status                    text        NOT NULL DEFAULT 'Pending',
  batch_id                  uuid,           -- batch context for approve/reject operations
  resubmit_count            integer     NOT NULL DEFAULT 0,

  -- Processing
  processed_by_profile_id   uuid,
  processed_at              timestamptz,

  -- Timestamps
  created_at                timestamptz NOT NULL DEFAULT NOW(),
  updated_at                timestamptz NOT NULL DEFAULT NOW(),

  -- Archive
  archived_at               timestamptz,
  archived_by_system        boolean     NOT NULL DEFAULT false,
  is_archived               boolean     NOT NULL DEFAULT false,

  -- Constraints
  CONSTRAINT employee_deactivation_requests_pkey
    PRIMARY KEY (id),

  CONSTRAINT employee_deactivation_requests_status_check
    CHECK (status IN ('Pending', 'Approved', 'Rejected', 'Archived')),

  CONSTRAINT employee_deactivation_requests_plantilla_fkey
    FOREIGN KEY (plantilla_id)
    REFERENCES public.plantilla(id)
    NOT VALID,

  CONSTRAINT employee_deactivation_requests_requestor_fkey
    FOREIGN KEY (requestor_profile_id)
    REFERENCES public.users_profile(id)
    NOT VALID,

  CONSTRAINT employee_deactivation_requests_processor_fkey
    FOREIGN KEY (processed_by_profile_id)
    REFERENCES public.users_profile(id)
    NOT VALID,

  CONSTRAINT employee_deactivation_requests_group_fkey
    FOREIGN KEY (group_id)
    REFERENCES public.groups(id)
    NOT VALID
);

-- Validate FK constraints without full table scan
ALTER TABLE public.employee_deactivation_requests
  VALIDATE CONSTRAINT employee_deactivation_requests_plantilla_fkey;
ALTER TABLE public.employee_deactivation_requests
  VALIDATE CONSTRAINT employee_deactivation_requests_requestor_fkey;

COMMENT ON TABLE public.employee_deactivation_requests IS
  'v2 deactivation request tracking. One row per request event per employee. '
  'Resubmits create a new row; prior rejected rows remain for audit history. '
  'Legacy deactivation_requests table is preserved and must not be mixed with this table.';

COMMENT ON COLUMN public.employee_deactivation_requests.batch_id IS
  'UUID grouping context for batch approve/reject operations. '
  'Set by approve/reject RPCs so all rows in one RPC call share the same batch_id.';

COMMENT ON COLUMN public.employee_deactivation_requests.resubmit_count IS
  'Incremented each time a new request is created for the same plantilla_id '
  'after a prior rejection. 0 = first-time request.';

COMMENT ON COLUMN public.employee_deactivation_requests.archived_by_system IS
  'TRUE when archived automatically by archive_processed_deactivations() cron. '
  'FALSE for any future manual archive path.';

-- RLS
ALTER TABLE public.employee_deactivation_requests ENABLE ROW LEVEL SECURITY;

-- INSERT/UPDATE/DELETE blocked — RPC-only mutations
REVOKE INSERT, UPDATE, DELETE ON public.employee_deactivation_requests FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.employee_deactivation_requests FROM anon;

-- SELECT: full-access users see all; Backoffice sees all; Ops sees own requests only
CREATE POLICY deact_req_v2_read_scoped
  ON public.employee_deactivation_requests
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR public.i_am_backoffice()
    OR (
      public.i_am_ops()
      AND requestor_profile_id = public.get_current_profile_id()
    )
  );


-- ============================================================
-- §4  employee_deactivation_audit_log table
-- ============================================================
-- Immutable audit trail for v2 workflow events.
-- Legacy deactivation_audit_log is preserved — do not join.

CREATE TABLE IF NOT EXISTS public.employee_deactivation_audit_log (
  id                        uuid        NOT NULL DEFAULT gen_random_uuid(),
  request_id                uuid        NOT NULL,
  plantilla_id              uuid        NOT NULL,   -- denormalized for direct lookup
  action                    text        NOT NULL,
  performed_by_profile_id   uuid        NOT NULL,
  performed_at              timestamptz NOT NULL DEFAULT NOW(),
  metadata                  jsonb,

  CONSTRAINT employee_deactivation_audit_log_pkey
    PRIMARY KEY (id),

  CONSTRAINT employee_deactivation_audit_log_action_check
    CHECK (action IN (
      'REQUEST_CREATED',
      'APPROVED',
      'REJECTED',
      'RESUBMITTED',
      'ARCHIVED'
    )),

  CONSTRAINT employee_deactivation_audit_log_request_fkey
    FOREIGN KEY (request_id)
    REFERENCES public.employee_deactivation_requests(id)
    NOT VALID,

  CONSTRAINT employee_deactivation_audit_log_plantilla_fkey
    FOREIGN KEY (plantilla_id)
    REFERENCES public.plantilla(id)
    NOT VALID,

  CONSTRAINT employee_deactivation_audit_log_performer_fkey
    FOREIGN KEY (performed_by_profile_id)
    REFERENCES public.users_profile(id)
    NOT VALID
);

ALTER TABLE public.employee_deactivation_audit_log
  VALIDATE CONSTRAINT employee_deactivation_audit_log_request_fkey;

COMMENT ON TABLE public.employee_deactivation_audit_log IS
  'Immutable audit log for v2 deactivation request lifecycle events. '
  'Client INSERT/UPDATE/DELETE is blocked. All writes go through SECURITY DEFINER RPCs.';

COMMENT ON COLUMN public.employee_deactivation_audit_log.metadata IS
  'Arbitrary context: {batch_size: N, notes: "...", archived_count: N}';

-- RLS
ALTER TABLE public.employee_deactivation_audit_log ENABLE ROW LEVEL SECURITY;

-- All mutations blocked — RPC-only
REVOKE INSERT, UPDATE, DELETE ON public.employee_deactivation_audit_log FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.employee_deactivation_audit_log FROM anon;

-- SELECT: full-access and backoffice only (Ops do not see raw audit log)
CREATE POLICY deact_audit_v2_read
  ON public.employee_deactivation_audit_log
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR public.i_am_backoffice()
  );


-- ============================================================
-- §5  Indexes
-- ============================================================

-- Duplicate prevention: at most one active Pending request per employee
-- This enforces idempotency for create_deactivation_request and resubmit.
CREATE UNIQUE INDEX IF NOT EXISTS uq_deact_req_pending_per_employee
  ON public.employee_deactivation_requests(plantilla_id)
  WHERE status = 'Pending' AND is_archived = false;

-- Efficient status-based queue queries (Backoffice module)
CREATE INDEX IF NOT EXISTS idx_deact_req_status_active
  ON public.employee_deactivation_requests(status)
  WHERE is_archived = false;

-- Per-requestor read path (Ops My Requests)
CREATE INDEX IF NOT EXISTS idx_deact_req_requestor
  ON public.employee_deactivation_requests(requestor_profile_id)
  WHERE is_archived = false;

-- Group-based queue filtering (Backoffice groups 1–5)
CREATE INDEX IF NOT EXISTS idx_deact_req_group
  ON public.employee_deactivation_requests(group_id)
  WHERE is_archived = false;

-- Archive sweep efficiency: find approved rows older than 15 days
CREATE INDEX IF NOT EXISTS idx_deact_req_archive_sweep
  ON public.employee_deactivation_requests(processed_at)
  WHERE status = 'Approved' AND is_archived = false;

-- Audit log lookup by request
CREATE INDEX IF NOT EXISTS idx_deact_audit_request_id
  ON public.employee_deactivation_audit_log(request_id);

-- Audit log lookup by plantilla (direct employee history)
CREATE INDEX IF NOT EXISTS idx_deact_audit_plantilla_id
  ON public.employee_deactivation_audit_log(plantilla_id);

-- Batch context lookup
CREATE INDEX IF NOT EXISTS idx_deact_req_batch_id
  ON public.employee_deactivation_requests(batch_id)
  WHERE batch_id IS NOT NULL;
