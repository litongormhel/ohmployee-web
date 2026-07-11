-- Migration: 20260526114430_stub_employee_import_batches
-- Purpose: Ensures employee_import_batches exists before remote_schema.sql
--          (20260526114431) applies REVOKE statements on it.
--          Safe no-op on prod (CREATE TABLE IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS public.employee_import_batches (
  id                       uuid        NOT NULL DEFAULT gen_random_uuid(),
  file_name                text        NOT NULL,
  uploaded_by              uuid        NOT NULL,
  uploaded_role            text,
  selected_group_id        uuid        NOT NULL,
  selected_account_id      uuid        NOT NULL,
  status                   text        NOT NULL DEFAULT 'draft_uploaded',
  total_rows               integer     NOT NULL DEFAULT 0,
  valid_rows               integer     NOT NULL DEFAULT 0,
  skipped_duplicate_rows   integer     NOT NULL DEFAULT 0,
  blocked_rows             integer     NOT NULL DEFAULT 0,
  flagged_rows             integer     NOT NULL DEFAULT 0,
  roving_detected          integer     NOT NULL DEFAULT 0,
  cross_account_conflicts  integer     NOT NULL DEFAULT 0,
  cross_group_conflicts    integer     NOT NULL DEFAULT 0,
  over_20_store_warnings   integer     NOT NULL DEFAULT 0,
  error_summary            jsonb       NOT NULL DEFAULT '{}'::jsonb,
  approved_by              uuid,
  approved_at              timestamptz,
  committed_rows           integer,
  rejected_by              uuid,
  rejected_at              timestamptz,
  rejection_reason         text,
  created_at               timestamptz NOT NULL DEFAULT NOW(),
  updated_at               timestamptz NOT NULL DEFAULT NOW(),

  CONSTRAINT employee_import_batches_pkey PRIMARY KEY (id),
  CONSTRAINT employee_import_batches_status_check
    CHECK (status IN ('draft_uploaded','validation_failed','pending_approval','approved','rejected')),
  CONSTRAINT employee_import_batches_group_fkey
    FOREIGN KEY (selected_group_id) REFERENCES public.groups(id) NOT VALID,
  CONSTRAINT employee_import_batches_account_fkey
    FOREIGN KEY (selected_account_id) REFERENCES public.accounts(id) NOT VALID
);

ALTER TABLE public.employee_import_batches ENABLE ROW LEVEL SECURITY;
