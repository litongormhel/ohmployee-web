-- ============================================================================
-- Migration: 20261026000002_qa_reset_soft_archive_and_atomic_rollback.sql
-- Purpose: 100% Soft-Archive Sweep, 72-Hour Atomic Rollback & Safe Audit Actor
--          Zeroes out all operational metrics on QA Reset while preserving
--          User Accounts, Permissions, and Account Sign-Ups.
-- ============================================================================

BEGIN;

-- ── §1. Ensure Canonical Batch Registries Exist ─────────────────────────────

CREATE TABLE IF NOT EXISTS public.archive_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_type TEXT NOT NULL DEFAULT 'QA_RESET',
    status TEXT NOT NULL DEFAULT 'ACTIVE',
    reason TEXT NOT NULL DEFAULT 'QA Reset Archive',
    created_by UUID,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '72 hours'),
    total_records INT NOT NULL DEFAULT 0,
    rolled_back_at TIMESTAMPTZ,
    rolled_back_by UUID,
    rollback_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_archive_batches_status CHECK (status IN ('ACTIVE', 'ROLLED_BACK', 'EXPIRED'))
);

CREATE INDEX IF NOT EXISTS idx_archive_batches_status ON public.archive_batches(status);
CREATE INDEX IF NOT EXISTS idx_archive_batches_executed_at ON public.archive_batches(executed_at DESC);

ALTER TABLE public.archive_batches ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'archive_batches' AND policyname = 'archive_batches_super_admin_all'
  ) THEN
    CREATE POLICY archive_batches_super_admin_all ON public.archive_batches
      FOR ALL TO authenticated USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());
  END IF;
END $$;

GRANT ALL ON TABLE public.archive_batches TO authenticated, service_role;

-- Also ensure quick_reports table exists
CREATE TABLE IF NOT EXISTS public.quick_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT,
    category TEXT,
    is_archived BOOLEAN DEFAULT FALSE,
    archived_at TIMESTAMPTZ,
    archive_batch_id UUID,
    suppressed_by_batch_id UUID,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.quick_reports ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'quick_reports' AND policyname = 'quick_reports_read_auth'
  ) THEN
    CREATE POLICY quick_reports_read_auth ON public.quick_reports
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

GRANT SELECT ON TABLE public.quick_reports TO authenticated, service_role;


-- ── §2. Standardize Archival Columns Across All Target Tables ───────────────

DO $$
DECLARE
    t TEXT;
    target_tables TEXT[] := ARRAY[
        'plantilla', 'plantilla_slots', 'vacancies', 'hr_emploc', 'applicants',
        'workforce_pool_slots', 'workforce_pool_requests', 'workforce_pool_request_items',
        'stores', 'groups', 'accounts',
        'coverage_groups', 'coverage_group_stores', 'coverage_slots', 'coverage_applicants',
        'hr_coverage_links', 'plantilla_store_links',
        'account_group_transfers', 'account_group_transfer_requests',
        'applicant_movements', 'applicant_movement_requests',
        'coverage_requests', 'deactivation_requests', 'employee_deactivation_requests',
        'headcount_requests', 'hr_emploc_deletions', 'hr_emploc_deletion_requests',
        'new_store_requests', 'plantilla_placements', 'plantilla_approvals',
        'vacancy_closure_requests', 'workforce_assignment_requests',
        'sla_breach_logs', 'employee_movements', 'mika_ghost_employees',
        'possible_ghost_employees', 'mika_import_logs', 'quick_reports', 'notifications',
        'approval_requests'
    ];
BEGIN
    FOREACH t IN ARRAY target_tables LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t) THEN
            EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE;', t);
            EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;', t);
            EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS archive_batch_id UUID;', t);
            EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS suppressed_by_batch_id UUID;', t);
            EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I(is_archived);', 'idx_' || t || '_is_archived', t);
            EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I(archive_batch_id);', 'idx_' || t || '_archive_batch_id', t);
            EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I(suppressed_by_batch_id);', 'idx_' || t || '_suppressed_by_batch_id', t);
        END IF;
    END LOOP;
END $$;


-- ── §3. Safe Actor ID Resolver for audit_logs (Fixes audit_logs_actor_id_fkey)

CREATE OR REPLACE FUNCTION public.resolve_audit_actor_id(p_input_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_valid_actor_id UUID := NULL;
    v_input UUID := COALESCE(p_input_user_id, auth.uid());
    v_fk_target TEXT := NULL;
BEGIN
    IF v_input IS NULL THEN
        RETURN NULL;
    END IF;

    -- 1. Inspect direct foreign key referenced table on audit_logs.actor_id using pg_constraint
    SELECT c.confrelid::regclass::TEXT INTO v_fk_target
    FROM pg_constraint c
    WHERE c.conrelid = 'public.audit_logs'::regclass
      AND c.conname = 'audit_logs_actor_id_fkey'
    LIMIT 1;

    -- 2. Resolve actor according to the exact foreign table
    IF v_fk_target = 'public.users_profile' OR v_fk_target = 'users_profile' THEN
        -- If FK references users_profile directly:
        SELECT id INTO v_valid_actor_id
        FROM public.users_profile
        WHERE id = v_input OR auth_user_id = v_input
        LIMIT 1;
    ELSE
        -- Default (and live Supabase target): references auth.users(id)
        -- Step 2a: Check if input UUID is directly a valid auth.users id
        SELECT id INTO v_valid_actor_id
        FROM auth.users
        WHERE id = v_input
        LIMIT 1;

        -- Step 2b: If not direct auth user, resolve via users_profile with strict INNER JOIN against auth.users
        -- (Ensures orphaned profiles whose auth_user_id does not exist in auth.users are NEVER returned)
        IF v_valid_actor_id IS NULL THEN
            SELECT au.id INTO v_valid_actor_id
            FROM public.users_profile up
            JOIN auth.users au ON au.id = up.auth_user_id
            WHERE up.id = v_input
            LIMIT 1;
        END IF;

        -- Step 2c: Fallback to auth.uid() if valid in auth.users
        IF v_valid_actor_id IS NULL AND auth.uid() IS NOT NULL THEN
            SELECT id INTO v_valid_actor_id
            FROM auth.users
            WHERE id = auth.uid()
            LIMIT 1;
        END IF;
    END IF;

    -- If unresolvable (e.g. orphaned profile or non-existent user), return NULL.
    -- Because public.audit_logs.actor_id is NULLABLE, returning NULL guarantees zero foreign key violation!
    RETURN v_valid_actor_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_audit_actor_id(UUID) TO authenticated, service_role;


-- ── §4. Execute QA Reset Archive RPC ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.execute_qa_reset_archive(
    p_actor_id UUID DEFAULT NULL,
    p_reason TEXT DEFAULT 'QA Reset Archive'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_batch_id UUID := gen_random_uuid();
    v_resolved_actor UUID;
    v_caller_profile_id UUID;
    v_now TIMESTAMPTZ := now();
    v_total_affected INT := 0;
    v_row_count INT := 0;
    v_plantilla_count INT := 0;
    v_vacancy_count INT := 0;
    v_hr_emploc_count INT := 0;
    t TEXT;
    target_tables TEXT[] := ARRAY[
        'plantilla', 'plantilla_slots', 'vacancies', 'hr_emploc', 'applicants',
        'workforce_pool_slots', 'workforce_pool_requests', 'workforce_pool_request_items',
        'stores', 'groups', 'accounts',
        'coverage_groups', 'coverage_group_stores', 'coverage_slots', 'coverage_applicants',
        'hr_coverage_links', 'plantilla_store_links',
        'account_group_transfers', 'account_group_transfer_requests',
        'applicant_movements', 'applicant_movement_requests',
        'coverage_requests', 'deactivation_requests', 'employee_deactivation_requests',
        'headcount_requests', 'hr_emploc_deletions', 'hr_emploc_deletion_requests',
        'new_store_requests', 'plantilla_placements', 'plantilla_approvals',
        'vacancy_closure_requests', 'workforce_assignment_requests',
        'sla_breach_logs', 'employee_movements', 'mika_ghost_employees',
        'possible_ghost_employees', 'mika_import_logs', 'quick_reports', 'notifications'
    ];
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
    END IF;

    v_resolved_actor := public.resolve_audit_actor_id(COALESCE(p_actor_id, auth.uid()));
    v_caller_profile_id := public.get_current_profile_id();

    -- 1. Insert into canonical archive_batches
    INSERT INTO public.archive_batches (
        id, batch_type, status, reason, created_by, executed_at, expires_at
    ) VALUES (
        v_batch_id, 'QA_RESET', 'ACTIVE', p_reason, v_resolved_actor, v_now, v_now + INTERVAL '72 hours'
    );

    -- 2. Sweep target operational tables
    FOREACH t IN ARRAY target_tables LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t) THEN
            -- Archive active records
            EXECUTE format(
                'UPDATE public.%I
                 SET is_archived = TRUE,
                     archived_at = $1,
                     archive_batch_id = $2
                 WHERE COALESCE(is_archived, FALSE) = FALSE;', t
            ) USING v_now, v_batch_id;
            GET DIAGNOSTICS v_row_count = ROW_COUNT;
            v_total_affected := v_total_affected + v_row_count;

            IF t = 'plantilla' THEN v_plantilla_count := v_row_count; END IF;
            IF t = 'vacancies' THEN v_vacancy_count := v_row_count; END IF;
            IF t = 'hr_emploc' THEN v_hr_emploc_count := v_row_count; END IF;

            -- Suppress already-archived records (e.g. Deleted VCodes, historical closures)
            EXECUTE format(
                'UPDATE public.%I
                 SET suppressed_by_batch_id = $1
                 WHERE is_archived = TRUE
                   AND archive_batch_id IS DISTINCT FROM $1
                   AND suppressed_by_batch_id IS NULL;', t
            ) USING v_batch_id;
        END IF;
    END LOOP;

    -- 3. Handle unified approval_requests / account_requests while PRESERVING Account Sign-Ups
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'approval_requests') THEN
        UPDATE public.approval_requests
        SET is_archived = TRUE,
            archived_at = v_now,
            archive_batch_id = v_batch_id
        WHERE COALESCE(is_archived, FALSE) = FALSE
          AND request_type NOT IN ('ACCOUNT_SIGNUP', 'account_sign_up', 'Account Sign-Ups');
        GET DIAGNOSTICS v_row_count = ROW_COUNT;
        v_total_affected := v_total_affected + v_row_count;

        UPDATE public.approval_requests
        SET suppressed_by_batch_id = v_batch_id
        WHERE is_archived = TRUE
          AND archive_batch_id IS DISTINCT FROM v_batch_id
          AND suppressed_by_batch_id IS NULL
          AND request_type NOT IN ('ACCOUNT_SIGNUP', 'account_sign_up', 'Account Sign-Ups');
    END IF;

    -- 4. Update archive_batches with total count
    UPDATE public.archive_batches
    SET total_records = v_total_affected
    WHERE id = v_batch_id;

    -- 5. Mirror into system_archive_batches if table exists (for existing UI modal history)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'system_archive_batches') THEN
        INSERT INTO public.system_archive_batches (
            archive_batch_id, action_type, reason, executed_by, executed_at,
            rollback_deadline, plantilla_count, vacancy_count, hr_emploc_count, status
        ) VALUES (
            v_batch_id, 'qa_reset', p_reason, v_caller_profile_id, v_now,
            v_now + INTERVAL '72 hours', v_plantilla_count, v_vacancy_count, v_hr_emploc_count, 'ACTIVE'
        );
    END IF;

    -- 6. Insert audit log entries safely
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
        INSERT INTO public.audit_logs (
            actor_id, module, action, record_id, new_data, timestamp
        ) VALUES (
            v_resolved_actor,
            'DATA_ARCHIVAL',
            'SOFT_DELETE'::public.audit_action,
            v_batch_id,
            jsonb_build_object('reason', p_reason, 'total_records', v_total_affected, 'plantilla', v_plantilla_count, 'vacancies', v_vacancy_count, 'hr_emploc', v_hr_emploc_count),
            v_now
        );
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'archival_audit_logs') THEN
        INSERT INTO public.archival_audit_logs (
            module, record_id, action_type, archived_by, reason, archive_batch_id, payload_snapshot
        ) VALUES (
            'qa_reset_sweep', v_batch_id, 'qa_archive', v_caller_profile_id, p_reason, v_batch_id,
            jsonb_build_object('batch_id', v_batch_id, 'total_records', v_total_affected, 'reason', p_reason)
        );
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'batch_id', v_batch_id,
        'total_records_archived', v_total_affected
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.execute_qa_reset_archive(UUID, TEXT) TO authenticated, service_role;

-- Backward compatibility wrapper for existing UI
CREATE OR REPLACE FUNCTION public.fn_archive_all_operational_data(p_reason TEXT DEFAULT 'QA Reset Archive')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.execute_qa_reset_archive(auth.uid(), p_reason);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_archive_all_operational_data(TEXT) TO authenticated, service_role;


-- ── §5. Atomic Rollback Archive Batch RPC ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.rollback_archive_batch(
    p_batch_id UUID,
    p_actor_id UUID DEFAULT NULL,
    p_rollback_reason TEXT DEFAULT 'Rollback QA Archive Batch'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resolved_actor UUID;
    v_caller_profile_id UUID;
    v_now TIMESTAMPTZ := now();
    v_total_restored INT := 0;
    v_row_count INT := 0;
    v_batch_found BOOLEAN := FALSE;
    t TEXT;
    target_tables TEXT[] := ARRAY[
        'plantilla', 'plantilla_slots', 'vacancies', 'hr_emploc', 'applicants',
        'workforce_pool_slots', 'workforce_pool_requests', 'workforce_pool_request_items',
        'stores', 'groups', 'accounts',
        'coverage_groups', 'coverage_group_stores', 'coverage_slots', 'coverage_applicants',
        'hr_coverage_links', 'plantilla_store_links',
        'account_group_transfers', 'account_group_transfer_requests',
        'applicant_movements', 'applicant_movement_requests',
        'coverage_requests', 'deactivation_requests', 'employee_deactivation_requests',
        'headcount_requests', 'hr_emploc_deletions', 'hr_emploc_deletion_requests',
        'new_store_requests', 'plantilla_placements', 'plantilla_approvals',
        'vacancy_closure_requests', 'workforce_assignment_requests',
        'sla_breach_logs', 'employee_movements', 'mika_ghost_employees',
        'possible_ghost_employees', 'mika_import_logs', 'quick_reports', 'notifications',
        'approval_requests'
    ];
BEGIN
    IF NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Access Denied: Super Admin only' USING ERRCODE = '42501';
    END IF;

    IF p_rollback_reason IS NULL OR TRIM(p_rollback_reason) = '' THEN
        RAISE EXCEPTION 'rollback_reason is required and must not be empty' USING ERRCODE = '22000';
    END IF;

    v_resolved_actor := public.resolve_audit_actor_id(COALESCE(p_actor_id, auth.uid()));
    v_caller_profile_id := public.get_current_profile_id();

    -- Check status in archive_batches
    IF EXISTS (
        SELECT 1 FROM public.archive_batches
        WHERE id = p_batch_id AND status = 'ACTIVE'
    ) THEN
        v_batch_found := TRUE;
    END IF;

    -- Also check status in system_archive_batches
    IF NOT v_batch_found AND EXISTS (
        SELECT 1 FROM public.system_archive_batches
        WHERE (archive_batch_id = p_batch_id OR id = p_batch_id) AND status = 'ACTIVE'
    ) THEN
        v_batch_found := TRUE;
    END IF;

    IF NOT v_batch_found THEN
        RAISE EXCEPTION 'Archive batch % is not active or has already been rolled back.', p_batch_id;
    END IF;

    -- 1. Restore rows across all target operational tables
    FOREACH t IN ARRAY target_tables LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t) THEN
            -- Restore active rows
            EXECUTE format(
                'UPDATE public.%I
                 SET is_archived = FALSE,
                     archived_at = NULL,
                     archive_batch_id = NULL
                 WHERE archive_batch_id = $1;', t
            ) USING p_batch_id;
            GET DIAGNOSTICS v_row_count = ROW_COUNT;
            v_total_restored := v_total_restored + v_row_count;

            -- Restore previously closed/archived rows (e.g. Deleted VCodes) without making them active
            EXECUTE format(
                'UPDATE public.%I
                 SET suppressed_by_batch_id = NULL
                 WHERE suppressed_by_batch_id = $1;', t
            ) USING p_batch_id;
        END IF;
    END LOOP;

    -- 2. Mark batch as ROLLED_BACK in archive_batches
    UPDATE public.archive_batches
    SET status = 'ROLLED_BACK',
        rolled_back_at = v_now,
        rolled_back_by = v_resolved_actor,
        rollback_reason = p_rollback_reason
    WHERE id = p_batch_id;

    -- 3. Mark batch as ROLLED_BACK in system_archive_batches
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'system_archive_batches') THEN
        UPDATE public.system_archive_batches
        SET status = 'ROLLED_BACK',
            rolled_back_at = v_now,
            rolled_back_by = v_caller_profile_id
        WHERE archive_batch_id = p_batch_id OR id = p_batch_id;
    END IF;

    -- 4. Audit logging
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
        INSERT INTO public.audit_logs (
            actor_id, module, action, record_id, new_data, timestamp
        ) VALUES (
            v_resolved_actor,
            'DATA_ARCHIVAL',
            'UPDATE'::public.audit_action,
            p_batch_id,
            jsonb_build_object('rollback_reason', p_rollback_reason, 'restored_records', v_total_restored),
            v_now
        );
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'archival_audit_logs') THEN
        INSERT INTO public.archival_audit_logs (
            module, record_id, action_type, restored_by, reason, archive_batch_id, payload_snapshot
        ) VALUES (
            'enterprise_archive_rollback', p_batch_id, 'qa_rollback', v_caller_profile_id, p_rollback_reason, p_batch_id,
            jsonb_build_object('batch_id', p_batch_id, 'restored_records', v_total_restored, 'reason', p_rollback_reason)
        );
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'batch_id', p_batch_id,
        'restored_records', v_total_restored
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rollback_archive_batch(UUID, UUID, TEXT) TO authenticated, service_role;

-- Backward compatibility wrapper for existing UI
CREATE OR REPLACE FUNCTION public.fn_rollback_archive_batch(p_batch_id UUID, p_reason TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.rollback_archive_batch(p_batch_id, auth.uid(), p_reason);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_rollback_archive_batch(UUID, TEXT) TO authenticated, service_role;


-- ── §6. Update Dashboard Telemetry RPCs ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_dashboard_metrics(
  p_account_id uuid DEFAULT NULL,
  p_group_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_uid            uuid := auth.uid();
  v_role_level          integer;
  v_is_admin            boolean;
  v_allowed_acc_ids     uuid[];

  v_open_vacancies      bigint := 0;
  v_emploc_pending      bigint := 0;
  v_active_plantilla    bigint := 0;
  v_understaffed_stores bigint := 0;
  v_active_sla_breaches bigint := 0;
  v_pending_approvals   bigint := NULL;
  v_admin_approvals     bigint := NULL;
  v_security_event_count bigint := NULL;
  v_ghost_employee_count bigint := 0;
  v_unassigned_vacancies bigint := 0;
  v_assigned_vacancies   bigint := 0;
BEGIN
  IF v_auth_uid IS NULL THEN
    IF (auth.jwt() ->> 'role') = 'service_role' OR session_user = 'postgres' THEN
      v_is_admin := true;
    ELSE
      RAISE EXCEPTION 'unauthenticated: dashboard metrics requires a valid session'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    v_role_level := COALESCE(public.get_my_role_level(), 0);
    v_is_admin := (v_role_level >= 90);

    IF NOT EXISTS (
      SELECT 1 FROM public.users_profile
      WHERE auth_user_id = v_auth_uid
        AND is_active = true
        AND archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: dashboard caller is not authorized'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Determine account filtering scope
  IF v_is_admin THEN
    IF p_account_id IS NOT NULL THEN
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(id) INTO v_allowed_acc_ids
      FROM public.accounts
      WHERE group_id = p_group_id AND is_active = true AND COALESCE(is_archived, false) = false;
    ELSE
      v_allowed_acc_ids := NULL; -- All accounts
    END IF;
  ELSE
    v_allowed_acc_ids := public.get_my_allowed_account_ids();
    IF p_account_id IS NOT NULL THEN
      IF NOT (p_account_id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]))) THEN
        RAISE EXCEPTION 'forbidden: account is out of scope' USING ERRCODE = '42501';
      END IF;
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(a.id) INTO v_allowed_acc_ids
      FROM public.accounts a
      WHERE a.group_id = p_group_id
        AND a.is_active = true
        AND COALESCE(a.is_archived, false) = false
        AND a.id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]));
    END IF;
  END IF;

  -- 1. Open Vacancies
  SELECT count(*)::bigint INTO v_open_vacancies
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  -- 1b. Unassigned vs Assigned Vacancies
  SELECT count(*)::bigint INTO v_unassigned_vacancies
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v.hrco_name IS NULL OR TRIM(v.hrco_name) = '')
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  v_assigned_vacancies := GREATEST(0, v_open_vacancies - v_unassigned_vacancies);

  -- 2. HR Emploc Pending
  SELECT count(*)::bigint INTO v_emploc_pending
  FROM public.hr_emploc h
  WHERE h.deleted_at IS NULL
    AND COALESCE(h.is_archived, false) = false
    AND h.hr_status IN ('Pending', 'For Correction', 'For Review')
    AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids));

  -- 3. Active Plantilla
  SELECT count(*)::bigint INTO v_active_plantilla
  FROM public.plantilla p
  WHERE p.status = 'Active'
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  -- 4. Under-Staffed Stores
  SELECT count(DISTINCT v.store_id)::bigint INTO v_understaffed_stores
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND v.store_id IS NOT NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  -- 5. Active SLA Breaches
  IF v_allowed_acc_ids IS NULL THEN
    SELECT count(*)::bigint INTO v_active_sla_breaches
    FROM public.sla_breach_logs
    WHERE COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL;
  ELSE
    SELECT count(*)::bigint INTO v_active_sla_breaches
    FROM public.sla_breach_logs s
    WHERE COALESCE(s.is_archived, false) = false
      AND s.suppressed_by_batch_id IS NULL
      AND s.account = ANY(public.get_my_allowed_accounts());
  END IF;

  -- 6. Approvals & Security KPIs
  IF v_is_admin THEN
    SELECT (
      COALESCE((SELECT count(*) FROM public.new_store_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.headcount_requests WHERE COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL AND (status::text ILIKE 'pending' OR status::text ILIKE 'under_review')), 0) +
      COALESCE((SELECT count(*) FROM public.plantilla_approvals WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.account_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.coverage_requests WHERE COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL AND status::text IN ('pending', 'draft')), 0) +
      COALESCE((SELECT count(*) FROM public.v_workforce_assignment_request_queue WHERE status::text ILIKE 'pending' OR status::text ILIKE 'for review'), 0) +
      COALESCE((SELECT count(*) FROM public.vacancy_closure_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.hr_emploc_deletion_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.employee_deactivation_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.applicant_movement_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.account_group_transfer_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0)
    )::bigint INTO v_pending_approvals;

    SELECT (
      COALESCE((SELECT count(*) FROM public.account_requests WHERE status::text ILIKE 'pending'), 0) +
      COALESCE((SELECT count(*) FROM public.applicant_movement_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.coverage_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.employee_deactivation_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0) +
      COALESCE((SELECT count(*) FROM public.hr_emploc_deletion_requests WHERE status::text ILIKE 'pending' AND COALESCE(is_archived, false) = false AND suppressed_by_batch_id IS NULL), 0)
    )::bigint INTO v_admin_approvals;

    SELECT (
      COALESCE((SELECT count(*) FROM public.security_audit_logs WHERE created_at >= CURRENT_DATE), 0) +
      COALESCE((SELECT count(*) FROM public.security_events WHERE happened_at >= CURRENT_DATE), 0)
    )::bigint INTO v_security_event_count;

    SELECT count(*)::bigint INTO v_ghost_employee_count
    FROM public.possible_ghost_employees
    WHERE status NOT IN ('Cleared', 'For Termination')
      AND COALESCE(is_archived, false) = false
      AND suppressed_by_batch_id IS NULL;
  ELSE
    v_pending_approvals := NULL;
    v_admin_approvals := NULL;
    v_security_event_count := NULL;
    v_ghost_employee_count := 0;
  END IF;

  RETURN jsonb_build_object(
    'total_open_vacancies', v_open_vacancies,
    'unassigned_vacancies', v_unassigned_vacancies,
    'assigned_vacancies', v_assigned_vacancies,
    'total_hr_emploc_pending', v_emploc_pending,
    'total_active_plantilla', v_active_plantilla,
    'understaffed_stores', v_understaffed_stores,
    'active_sla_breaches', v_active_sla_breaches,
    'pending_approvals', v_pending_approvals,
    'admin_security_approvals', v_admin_approvals,
    'security_event_count', v_security_event_count,
    'ghost_employee_count', v_ghost_employee_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_dashboard_metrics(uuid, uuid) TO authenticated, service_role;


-- ── §7. Update Dashboard Operational Analytics RPC ─────────────────────────

CREATE OR REPLACE FUNCTION public.fn_dashboard_operational_analytics(
  p_account_id uuid DEFAULT NULL,
  p_group_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_uid            uuid := auth.uid();
  v_role_level          integer;
  v_is_admin            boolean;
  v_allowed_acc_ids     uuid[];

  v_pipeline_total      bigint := 0;
  v_hires_this_month    bigint := 0;
  v_separations_month   bigint := 0;
  v_actual_hc           numeric := 0;
  v_hr_pipeline         numeric := 0;
  v_vacant_hc           numeric := 0;
  v_denominator         numeric := 0;
  v_avg_fill_rate       numeric := NULL;
BEGIN
  IF v_auth_uid IS NULL THEN
    IF (auth.jwt() ->> 'role') = 'service_role' OR session_user = 'postgres' THEN
      v_is_admin := true;
    ELSE
      RAISE EXCEPTION 'unauthenticated: dashboard operational analytics requires a valid session'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    v_role_level := COALESCE(public.get_my_role_level(), 0);
    v_is_admin := (v_role_level >= 90);

    IF NOT EXISTS (
      SELECT 1 FROM public.users_profile
      WHERE auth_user_id = v_auth_uid
        AND is_active = true
        AND archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'forbidden: dashboard caller is not authorized'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Determine account filtering scope
  IF v_is_admin THEN
    IF p_account_id IS NOT NULL THEN
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(id) INTO v_allowed_acc_ids
      FROM public.accounts
      WHERE group_id = p_group_id AND is_active = true AND COALESCE(is_archived, false) = false;
    ELSE
      v_allowed_acc_ids := NULL; -- All accounts
    END IF;
  ELSE
    v_allowed_acc_ids := public.get_my_allowed_account_ids();
    IF p_account_id IS NOT NULL THEN
      IF NOT (p_account_id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]))) THEN
        RAISE EXCEPTION 'forbidden: account is out of scope' USING ERRCODE = '42501';
      END IF;
      v_allowed_acc_ids := ARRAY[p_account_id];
    ELSIF p_group_id IS NOT NULL THEN
      SELECT array_agg(a.id) INTO v_allowed_acc_ids
      FROM public.accounts a
      WHERE a.group_id = p_group_id
        AND a.is_active = true
        AND COALESCE(a.is_archived, false) = false
        AND a.id = ANY(COALESCE(v_allowed_acc_ids, ARRAY[]::uuid[]));
    END IF;
  END IF;

  -- 1. Pipeline Total (Active applicants + pending HR Emploc)
  SELECT (
    COALESCE((
      SELECT count(*)
      FROM public.applicants ap
      WHERE COALESCE(ap.is_archived, false) = false
        AND ap.suppressed_by_batch_id IS NULL
        AND public.fn_is_active_vacancy_applicant_status(ap.status)
        AND (
          v_allowed_acc_ids IS NULL
          OR EXISTS (
            SELECT 1 FROM public.vacancies v
            WHERE v.vcode = ap.vacancy_vcode
              AND v.account_id = ANY(v_allowed_acc_ids)
          )
        )
    ), 0) +
    COALESCE((
      SELECT count(*)
      FROM public.hr_emploc h
      WHERE h.deleted_at IS NULL
        AND COALESCE(h.is_archived, false) = false
        AND h.suppressed_by_batch_id IS NULL
        AND h.hr_status IN ('Pending', 'For Correction', 'For Review')
        AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids))
    ), 0)
  )::bigint INTO v_pipeline_total;

  -- 2. Hires This Month
  SELECT (
    COALESCE((
      SELECT count(*)
      FROM public.applicants ap
      WHERE ap.hired_date IS NOT NULL
        AND COALESCE(ap.is_archived, false) = false
        AND ap.suppressed_by_batch_id IS NULL
        AND date_trunc('month', ap.hired_date::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
        AND (
          v_allowed_acc_ids IS NULL
          OR EXISTS (
            SELECT 1 FROM public.vacancies v
            WHERE v.vcode = ap.vacancy_vcode
              AND v.account_id = ANY(v_allowed_acc_ids)
          )
        )
    ), 0) +
    COALESCE((
      SELECT count(*)
      FROM public.hr_emploc h
      WHERE h.hired_date IS NOT NULL
        AND COALESCE(h.is_archived, false) = false
        AND h.suppressed_by_batch_id IS NULL
        AND date_trunc('month', h.hired_date::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
        AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids))
    ), 0)
  )::bigint INTO v_hires_this_month;

  -- 3. Separations This Month
  SELECT count(*)::bigint INTO v_separations_month
  FROM public.plantilla p
  WHERE p.date_of_separation IS NOT NULL
    AND COALESCE(p.is_archived, false) = false
    AND p.suppressed_by_batch_id IS NULL
    AND date_trunc('month', p.date_of_separation::timestamp) = date_trunc('month', CURRENT_DATE::timestamp)
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  -- 4. Avg Fill Rate
  SELECT count(*)::numeric INTO v_actual_hc
  FROM public.plantilla p
  WHERE p.status = 'Active'
    AND COALESCE(p.is_deleted, false) = false
    AND COALESCE(p.is_archived, false) = false
    AND (v_allowed_acc_ids IS NULL OR p.account_id = ANY(v_allowed_acc_ids));

  SELECT count(*)::numeric INTO v_hr_pipeline
  FROM public.hr_emploc h
  WHERE h.deleted_at IS NULL
    AND COALESCE(h.is_archived, false) = false
    AND h.hr_status = ANY(ARRAY['Pending'::text, 'Complete'::text])
    AND (v_allowed_acc_ids IS NULL OR h.account_id = ANY(v_allowed_acc_ids));

  SELECT count(*)::numeric INTO v_vacant_hc
  FROM public.vacancies v
  WHERE v.status = 'Open'
    AND COALESCE(v.is_archived, false) = false
    AND v.deleted_at IS NULL
    AND (v_allowed_acc_ids IS NULL OR v.account_id = ANY(v_allowed_acc_ids));

  v_denominator := v_actual_hc + v_hr_pipeline + v_vacant_hc;
  IF v_denominator > 0 THEN
    v_avg_fill_rate := round((v_actual_hc / v_denominator) * 100.0, 1);
  ELSE
    v_avg_fill_rate := NULL;
  END IF;

  RETURN jsonb_build_object(
    'pipeline_total', v_pipeline_total,
    'hires_this_month', v_hires_this_month,
    'separations_this_month', v_separations_month,
    'avg_fill_rate', v_avg_fill_rate
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_dashboard_operational_analytics(uuid, uuid) TO authenticated, service_role;


-- ── §8. Update CENCOM Deployment Summary RPC ───────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_cencom_deployment_summary()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH
  period AS (
    SELECT
      date_trunc('month', now())::date                         AS month_start,
      (date_trunc('month', now()) + interval '1 month')::date AS month_end
  ),
  allowed AS (
    SELECT CASE
      WHEN public.i_have_full_access() THEN NULL::uuid[]
      ELSE public.get_my_allowed_account_ids()
    END AS ids
  ),
  departures AS (
    SELECT count(*) AS cnt
    FROM public.employee_deactivation_requests d
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE d.status = 'Approved'
      AND d.processed_at::date >= p.month_start
      AND d.processed_at::date <  p.month_end
      AND COALESCE(d.is_archived, false) = false
      AND d.suppressed_by_batch_id IS NULL
      AND (sc.ids IS NULL OR d.account_id = ANY(sc.ids))
  ),
  additional_hc AS (
    SELECT count(*) AS cnt
    FROM public.headcount_requests h
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE h.status IN ('approved_pending_vcode', 'completed')
      AND COALESCE(h.head_admin_approved_at, h.reviewed_at)::date >= p.month_start
      AND COALESCE(h.head_admin_approved_at, h.reviewed_at)::date <  p.month_end
      AND COALESCE(h.is_archived, false) = false
      AND h.suppressed_by_batch_id IS NULL
      AND (sc.ids IS NULL OR h.account_id = ANY(sc.ids))
  ),
  deleted_vcode AS (
    SELECT count(*) AS cnt
    FROM public.vacancies v
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE COALESCE(v.archived_at, v.deleted_at)::date >= p.month_start
      AND COALESCE(v.archived_at, v.deleted_at)::date <  p.month_end
      AND v.suppressed_by_batch_id IS NULL
      AND v.archive_batch_id IS NULL
      AND (sc.ids IS NULL OR v.account_id = ANY(sc.ids))
  ),
  deployment AS (
    SELECT count(*) AS cnt
    FROM public.hr_emploc he
    CROSS JOIN period p
    CROSS JOIN allowed sc
    WHERE he.hired_date >= p.month_start
      AND he.hired_date <  p.month_end
      AND he.deleted_at IS NULL
      AND COALESCE(he.is_archived, false) = false
      AND he.suppressed_by_batch_id IS NULL
      AND (sc.ids IS NULL OR he.account_id = ANY(sc.ids))
  )
SELECT jsonb_build_object(
  'total_departures', COALESCE((SELECT cnt FROM departures),   0),
  'additional_hc',    COALESCE((SELECT cnt FROM additional_hc), 0),
  'deleted_vcode',    COALESCE((SELECT cnt FROM deleted_vcode), 0),
  'deployment',       COALESCE((SELECT cnt FROM deployment),    0)
);
$$;

GRANT EXECUTE ON FUNCTION public.fn_cencom_deployment_summary() TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
