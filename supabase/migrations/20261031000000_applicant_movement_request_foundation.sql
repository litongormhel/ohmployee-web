-- ============================================================
-- OHM2026_0088A — Applicant Movement Requests (AMR)
-- Migration: 20261026000000_applicant_movement_request_foundation.sql
--
-- Creates:
--   • applicant_movement_requests         — core request table
--   • applicant_movement_request_history  — per-transition audit trail
--   • applicant_movement_reservations     — vacancy hold during pending review
--   • vw_amr_list                         — Flutter list view (joined)
--   • vw_amr_vacancy_reservation_status  — per-VCODE reservation indicator
--   • create_applicant_movement_request   — submit Transfer or Swap
--   • approve_applicant_movement_request  — advance approval stage
--   • reject_applicant_movement_request   — reject + release reservation
--   • withdraw_applicant_movement_request — requester withdrawal
--   • fn_amr_execute_transfer             — internal: move applicant
--   • fn_amr_execute_swap                 — internal: swap applicants
--   • get_applicant_movement_requests     — scoped list for Flutter
--   • get_amr_vacancy_reservation         — reservation check for Flutter
--   • fn_amr_sla_escalation               — Day 3 HA / Day 5 SA escalation
-- ============================================================

-- ─── Sequence for human-readable request numbers ─────────────
CREATE SEQUENCE IF NOT EXISTS public.amr_request_number_seq
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  CACHE 1;

-- ─── Core request table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.applicant_movement_requests (
  id                     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  request_number         text        NOT NULL UNIQUE,

  -- Workflow identifiers
  movement_type          text        NOT NULL
                           CHECK (movement_type IN ('TRANSFER', 'SWAP')),
  status                 text        NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
  approval_stage         text        -- 'encoder' | 'ha' | 'sa' | null (direct)
                           CHECK (approval_stage IN ('encoder', 'ha', 'sa')),

  -- Source applicant (always required)
  source_applicant_id    uuid        NOT NULL REFERENCES public.applicants(id),
  source_vacancy_vcode   text        NOT NULL,  -- snapshot at submission
  source_account_id      uuid,                  -- snapshot
  source_account_name    text,                  -- snapshot
  source_group_id        uuid,                  -- snapshot for approval matrix

  -- Target vacancy (always required)
  target_vacancy_vcode   text        NOT NULL,
  target_account_id      uuid,                  -- snapshot
  target_account_name    text,                  -- snapshot
  target_group_id        uuid,                  -- snapshot for approval matrix

  -- SWAP: second applicant (NULL for TRANSFER)
  target_applicant_id    uuid        REFERENCES public.applicants(id),

  -- Reason
  reason                 text        NOT NULL,
  remarks                text,                  -- required when reason = 'Other'

  -- Requester
  requested_by           uuid        NOT NULL REFERENCES public.users_profile(id),
  requested_by_name      text        NOT NULL,
  requested_by_role      text        NOT NULL,
  requested_by_role_level int        NOT NULL,
  requested_at           timestamptz NOT NULL DEFAULT now(),

  -- Approval tracking
  encoder_approved_by    uuid        REFERENCES public.users_profile(id),
  encoder_approved_at    timestamptz,
  ha_approved_by         uuid        REFERENCES public.users_profile(id),
  ha_approved_at         timestamptz,
  sa_approved_by         uuid        REFERENCES public.users_profile(id),
  sa_approved_at         timestamptz,

  -- Rejection
  rejected_by            uuid        REFERENCES public.users_profile(id),
  rejected_at            timestamptz,
  rejection_reason       text,

  -- Withdrawal
  withdrawn_by           uuid        REFERENCES public.users_profile(id),
  withdrawn_at           timestamptz,

  -- Execution
  executed_at            timestamptz,
  execution_error        text,

  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.applicant_movement_requests IS
  'OHM2026_0088A: Transfer and Swap applicant movement requests with multi-stage approval workflow.';

-- ─── History / audit trail ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.applicant_movement_request_history (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id    uuid        NOT NULL
                  REFERENCES public.applicant_movement_requests(id) ON DELETE CASCADE,
  from_status   text,
  to_status     text        NOT NULL,
  from_stage    text,
  to_stage      text,
  action        text        NOT NULL
                  CHECK (action IN ('submitted', 'approved_stage', 'approved_final', 'rejected', 'withdrawn', 'escalated', 'execution_failed')),
  actor_id      uuid,
  actor_name    text,
  actor_role    text,
  actor_role_level int,
  note          text,
  event_payload jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_amr_history_request_id
  ON public.applicant_movement_request_history(request_id);

-- ─── Target vacancy reservation ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.applicant_movement_reservations (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id     uuid        NOT NULL UNIQUE
                   REFERENCES public.applicant_movement_requests(id) ON DELETE CASCADE,
  reserved_vcode text        NOT NULL,
  reserved_at    timestamptz NOT NULL DEFAULT now(),
  released_at    timestamptz,          -- NULL = active
  release_reason text                  -- 'approved' | 'rejected' | 'withdrawn'
);

CREATE INDEX IF NOT EXISTS idx_amr_reservations_vcode
  ON public.applicant_movement_reservations(reserved_vcode)
  WHERE released_at IS NULL;

-- ─── Indexes on core table ─────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_amr_status
  ON public.applicant_movement_requests(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_amr_requested_by
  ON public.applicant_movement_requests(requested_by);
CREATE INDEX IF NOT EXISTS idx_amr_source_applicant
  ON public.applicant_movement_requests(source_applicant_id);
CREATE INDEX IF NOT EXISTS idx_amr_target_vcode
  ON public.applicant_movement_requests(target_vacancy_vcode);
CREATE INDEX IF NOT EXISTS idx_amr_source_vcode
  ON public.applicant_movement_requests(source_vacancy_vcode);

-- ─── Auto-update updated_at ────────────────────────────────────
CREATE TRIGGER trg_amr_set_updated_at
  BEFORE UPDATE ON public.applicant_movement_requests
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.applicant_movement_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.applicant_movement_request_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.applicant_movement_reservations ENABLE ROW LEVEL SECURITY;

-- Requests: SELECT — own requests or approver roles
CREATE POLICY amr_select_own ON public.applicant_movement_requests
  FOR SELECT USING (
    requested_by = (SELECT id FROM public.users_profile WHERE auth_user_id = auth.uid())
    OR public.i_have_full_access()
    OR public.get_my_role_level() >= 30   -- Encoder+
  );

-- Requests: no direct write — all writes through SECURITY DEFINER RPCs
CREATE POLICY amr_no_direct_insert ON public.applicant_movement_requests
  FOR INSERT WITH CHECK (false);
CREATE POLICY amr_no_direct_update ON public.applicant_movement_requests
  FOR UPDATE USING (false);
CREATE POLICY amr_no_direct_delete ON public.applicant_movement_requests
  FOR DELETE USING (false);

-- History: read-only via parent request access
CREATE POLICY amr_history_select ON public.applicant_movement_request_history
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.applicant_movement_requests r
      WHERE r.id = request_id
        AND (
          r.requested_by = (SELECT id FROM public.users_profile WHERE auth_user_id = auth.uid())
          OR public.i_have_full_access()
          OR public.get_my_role_level() >= 30
        )
    )
  );
CREATE POLICY amr_history_no_write ON public.applicant_movement_request_history
  FOR ALL USING (false);

-- Reservations: SELECT open to all authenticated (needed for vacancy UI badge)
CREATE POLICY amr_reservation_select ON public.applicant_movement_reservations
  FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY amr_reservation_no_write ON public.applicant_movement_reservations
  FOR ALL USING (false);

-- ─── Views ────────────────────────────────────────────────────

-- Full list view for Flutter with joined names and reservation status
CREATE OR REPLACE VIEW public.vw_amr_list AS
SELECT
  r.id,
  r.request_number,
  r.movement_type,
  r.status,
  r.approval_stage,

  r.source_applicant_id,
  COALESCE(
    a_src.last_name || ', ' || a_src.first_name ||
    CASE WHEN a_src.middle_name IS NOT NULL AND a_src.middle_name <> '' THEN ' ' || a_src.middle_name ELSE '' END,
    '—'
  ) AS source_applicant_name,
  a_src.status          AS source_applicant_status,
  r.source_vacancy_vcode,
  r.source_account_name,

  r.target_applicant_id,
  COALESCE(
    a_tgt.last_name || ', ' || a_tgt.first_name ||
    CASE WHEN a_tgt.middle_name IS NOT NULL AND a_tgt.middle_name <> '' THEN ' ' || a_tgt.middle_name ELSE '' END,
    NULL
  ) AS target_applicant_name,
  a_tgt.status          AS target_applicant_status,
  r.target_vacancy_vcode,
  r.target_account_name,

  r.reason,
  r.remarks,

  r.requested_by,
  r.requested_by_name,
  r.requested_by_role,
  r.requested_at,

  r.encoder_approved_by,
  r.encoder_approved_at,
  r.ha_approved_by,
  r.ha_approved_at,
  r.sa_approved_by,
  r.sa_approved_at,

  r.rejected_by,
  r.rejected_at,
  r.rejection_reason,

  r.withdrawn_by,
  r.withdrawn_at,

  r.executed_at,
  r.execution_error,

  r.created_at,
  r.updated_at,

  -- Active reservation info
  res.id              AS reservation_id,
  res.reserved_at     AS reservation_reserved_at,
  (res.id IS NOT NULL AND res.released_at IS NULL) AS has_active_reservation

FROM public.applicant_movement_requests r
LEFT JOIN public.applicants a_src ON a_src.id = r.source_applicant_id
LEFT JOIN public.applicants a_tgt ON a_tgt.id = r.target_applicant_id
LEFT JOIN public.applicant_movement_reservations res ON res.request_id = r.id;

-- Per-VCODE reservation status for vacancy card UI
CREATE OR REPLACE VIEW public.vw_amr_vacancy_reservation_status AS
SELECT
  res.reserved_vcode          AS vcode,
  res.id                      AS reservation_id,
  r.id                        AS request_id,
  r.request_number,
  r.movement_type,
  r.status                    AS request_status,
  r.approval_stage,
  r.requested_by_name,
  res.reserved_at
FROM public.applicant_movement_reservations res
JOIN public.applicant_movement_requests r ON r.id = res.request_id
WHERE res.released_at IS NULL
  AND r.status = 'pending';

-- ─── HELPER: determine approval stages ────────────────────────
-- Returns ordered stage list ('encoder', 'ha', 'sa') based on
-- requester role level and source/target group relationship.
-- Called inside create_applicant_movement_request.
CREATE OR REPLACE FUNCTION public.fn_amr_determine_stages(
  p_requester_role_level  int,
  p_source_group_id       uuid,
  p_target_group_id       uuid,
  p_source_account_id     uuid,
  p_target_account_id     uuid
)
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_same_account  bool;
  v_same_group    bool;
  v_stages        text[];
BEGIN
  v_same_account := (p_source_account_id IS NOT NULL
                     AND p_source_account_id = p_target_account_id);
  v_same_group   := (p_source_group_id IS NOT NULL
                     AND p_source_group_id = p_target_group_id);

  -- SA: direct approval in every matrix path.
  IF p_requester_role_level >= 100 THEN
    RETURN ARRAY[]::text[];
  END IF;

  -- Same account
  IF v_same_account THEN
    IF p_requester_role_level >= 30 THEN  -- Encoder
      RETURN ARRAY[]::text[];             -- Direct
    ELSE
      RETURN ARRAY['encoder']::text[];    -- Ops → Encoder
    END IF;
  END IF;

  -- Cross-account, same group
  IF v_same_group THEN
    IF p_requester_role_level >= 90 THEN  -- HA
      RETURN ARRAY[]::text[];
    ELSIF p_requester_role_level >= 30 THEN  -- Encoder
      RETURN ARRAY['ha']::text[];
    ELSE
      RETURN ARRAY['encoder', 'ha']::text[];
    END IF;
  END IF;

  -- Cross-group
  IF p_requester_role_level >= 90 THEN    -- HA
    RETURN ARRAY['sa']::text[];
  ELSIF p_requester_role_level >= 30 THEN  -- Encoder
    RETURN ARRAY['ha', 'sa']::text[];
  ELSE
    RETURN ARRAY['encoder', 'ha', 'sa']::text[];
  END IF;
END;
$$;

-- ─── HELPER: release reservation ──────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_amr_release_reservation(
  p_request_id    uuid,
  p_release_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.applicant_movement_reservations
  SET released_at    = now(),
      release_reason = p_release_reason
  WHERE request_id = p_request_id
    AND released_at IS NULL;
END;
$$;

-- ─── HELPER: execute transfer ──────────────────────────────────
-- Moves source applicant to target vacancy.
-- Full revalidation at execution time to prevent stale-state approvals.
CREATE OR REPLACE FUNCTION public.fn_amr_execute_transfer(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_req     public.applicant_movement_requests%ROWTYPE;
  v_src_status text;
  v_tgt_status text;
  v_tgt_open_count int;
  v_blocked_statuses text[] := ARRAY['Confirmed Onboard', 'Hired'];
  v_actor_name text;
  v_src_slot_id uuid;
  v_tgt_slot_id uuid;
BEGIN
  SELECT * INTO v_req
  FROM public.applicant_movement_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_NOT_FOUND: Request % not found', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Revalidate source applicant
  SELECT status, slot_id INTO v_src_status, v_src_slot_id
  FROM public.applicants
  WHERE id = v_req.source_applicant_id;

  IF v_src_status = ANY(v_blocked_statuses) THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Source applicant is in a terminal status (%)', v_src_status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Revalidate target vacancy is still open and not reserved by another request
  SELECT
    COALESCE(open_count, 0)
  INTO v_tgt_open_count
  FROM public.vw_slot_derived_vacancy_shadow
  WHERE legacy_vcode = v_req.target_vacancy_vcode;

  -- Fallback to vacancies table if shadow view not available
  IF NOT FOUND THEN
    SELECT CASE WHEN status = 'Open' THEN 1 ELSE 0 END
    INTO v_tgt_open_count
    FROM public.vacancies
    WHERE vcode = v_req.target_vacancy_vcode
      AND deleted_at IS NULL;
  END IF;

  IF COALESCE(v_tgt_open_count, 0) < 1 THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Target vacancy % has no open slots at time of execution', v_req.target_vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT id INTO v_tgt_slot_id
  FROM public.plantilla_slots
  WHERE legacy_vcode = v_req.target_vacancy_vcode
    AND slot_status = 'open'
    AND COALESCE(is_roving, false) = false
  ORDER BY slot_ordinal NULLS LAST, created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  -- Check for competing reservation from another request
  IF EXISTS (
    SELECT 1
    FROM public.applicant_movement_reservations res
    JOIN public.applicant_movement_requests r2 ON r2.id = res.request_id
    WHERE res.reserved_vcode = v_req.target_vacancy_vcode
      AND res.released_at IS NULL
      AND res.request_id <> p_request_id
      AND r2.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Target vacancy % is reserved by another pending request', v_req.target_vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Execute: move applicant to target vacancy
  UPDATE public.applicants
  SET
    vacancy_vcode   = v_req.target_vacancy_vcode,
    slot_id         = COALESCE(v_tgt_slot_id, slot_id),
    updated_at      = now()
  WHERE id = v_req.source_applicant_id;

  IF v_src_slot_id IS NOT NULL THEN
    PERFORM public.fn_release_applicant_slot(v_src_slot_id, COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by));
  ELSE
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v_req.source_vacancy_vcode,
      p_performed_by => COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
      p_source_fn    => 'fn_amr_execute_transfer.source'
    );
  END IF;

  IF v_tgt_slot_id IS NOT NULL THEN
    PERFORM public.fn_set_slot_status(
      p_slot_id      => v_tgt_slot_id,
      p_new_status   => 'pipeline',
      p_reason_code  => NULL,
      p_performed_by => COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
      p_remarks      => 'Applicant Movement Request ' || v_req.request_number || ': target vacancy claimed'
    );
  ELSE
    PERFORM public.fn_sync_vacancy_slot_open_pipeline(
      p_vcode        => v_req.target_vacancy_vcode,
      p_performed_by => COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
      p_source_fn    => 'fn_amr_execute_transfer.target'
    );
  END IF;

  SELECT full_name INTO v_actor_name
  FROM public.users_profile
  WHERE id = COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by);

  INSERT INTO public.applicant_status_history (
    applicant_id, from_status, to_status, remarks, changed_by, changed_at,
    source_module, update_type, changed_field, old_value, new_value,
    changed_by_name
  ) VALUES (
    v_req.source_applicant_id,
    v_src_status,
    v_src_status,
    'Applicant Movement Request ' || v_req.request_number || ': Transfer ' ||
      v_req.source_vacancy_vcode || ' → ' || v_req.target_vacancy_vcode ||
      '. Reason: ' || v_req.reason,
    COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
    now(),
    'vacancy',
    'status_change',
    'vacancy_vcode',
    v_req.source_vacancy_vcode,
    v_req.target_vacancy_vcode,
    v_actor_name
  );

  INSERT INTO public.audit_logs (
    actor_id, module, action, record_id, old_data, new_data, role
  ) VALUES (
    COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by),
    'Applicant Movement',
    'UPDATE',
    p_request_id,
    jsonb_build_object(
      'applicant_id', v_req.source_applicant_id,
      'source_vcode', v_req.source_vacancy_vcode
    ),
    jsonb_build_object(
      'request_number', v_req.request_number,
      'movement_type', 'TRANSFER',
      'applicant_id', v_req.source_applicant_id,
      'target_vcode', v_req.target_vacancy_vcode,
      'requested_by', v_req.requested_by_name,
      'reason', v_req.reason
    ),
    COALESCE(v_req.requested_by_role, 'Applicant Movement')
  );

  -- Stamp execution time
  UPDATE public.applicant_movement_requests
  SET executed_at = now(),
      updated_at  = now()
  WHERE id = p_request_id;
END;
$$;

-- ─── HELPER: execute swap ──────────────────────────────────────
-- Swaps two applicants between their respective vacancies.
CREATE OR REPLACE FUNCTION public.fn_amr_execute_swap(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_req          public.applicant_movement_requests%ROWTYPE;
  v_src_status   text;
  v_tgt_status   text;
  v_blocked_statuses text[] := ARRAY['Confirmed Onboard', 'Hired'];
  v_actor_id     uuid;
  v_actor_name   text;
  v_src_slot_id  uuid;
  v_tgt_slot_id  uuid;
BEGIN
  SELECT * INTO v_req
  FROM public.applicant_movement_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_NOT_FOUND: Request % not found', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_req.target_applicant_id IS NULL THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: SWAP request % has no target applicant', p_request_id
      USING ERRCODE = 'check_violation';
  END IF;

  -- Revalidate both applicants
  SELECT status, slot_id INTO v_src_status, v_src_slot_id
  FROM public.applicants WHERE id = v_req.source_applicant_id;

  SELECT status, slot_id INTO v_tgt_status, v_tgt_slot_id
  FROM public.applicants WHERE id = v_req.target_applicant_id;

  IF v_src_status = ANY(v_blocked_statuses) THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Source applicant is in a terminal status (%)', v_src_status
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_tgt_status = ANY(v_blocked_statuses) THEN
    RAISE EXCEPTION 'AMR_EXECUTION_BLOCKED: Target applicant is in a terminal status (%)', v_tgt_status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Execute: atomic swap (temp VCODE to avoid constraint conflicts)
  UPDATE public.applicants
  SET vacancy_vcode = '_amr_swap_temp_' || p_request_id::text,
      slot_id       = NULL,
      updated_at    = now()
  WHERE id = v_req.source_applicant_id;

  UPDATE public.applicants
  SET vacancy_vcode = v_req.source_vacancy_vcode,
      slot_id       = v_src_slot_id,
      updated_at    = now()
  WHERE id = v_req.target_applicant_id;

  UPDATE public.applicants
  SET vacancy_vcode = v_req.target_vacancy_vcode,
      slot_id       = v_tgt_slot_id,
      updated_at    = now()
  WHERE id = v_req.source_applicant_id;

  v_actor_id := COALESCE(v_req.sa_approved_by, v_req.ha_approved_by, v_req.encoder_approved_by, v_req.requested_by);
  SELECT full_name INTO v_actor_name FROM public.users_profile WHERE id = v_actor_id;

  INSERT INTO public.applicant_status_history (
    applicant_id, from_status, to_status, remarks, changed_by, changed_at,
    source_module, update_type, changed_field, old_value, new_value,
    changed_by_name
  ) VALUES
  (
    v_req.source_applicant_id,
    v_src_status,
    v_src_status,
    'Applicant Movement Request ' || v_req.request_number || ': Swap ' ||
      v_req.source_vacancy_vcode || ' ↔ ' || v_req.target_vacancy_vcode ||
      '. Reason: ' || v_req.reason,
    v_actor_id,
    now(),
    'vacancy',
    'status_change',
    'vacancy_vcode',
    v_req.source_vacancy_vcode,
    v_req.target_vacancy_vcode,
    v_actor_name
  ),
  (
    v_req.target_applicant_id,
    v_tgt_status,
    v_tgt_status,
    'Applicant Movement Request ' || v_req.request_number || ': Swap ' ||
      v_req.target_vacancy_vcode || ' ↔ ' || v_req.source_vacancy_vcode ||
      '. Reason: ' || v_req.reason,
    v_actor_id,
    now(),
    'vacancy',
    'status_change',
    'vacancy_vcode',
    v_req.target_vacancy_vcode,
    v_req.source_vacancy_vcode,
    v_actor_name
  );

  INSERT INTO public.audit_logs (
    actor_id, module, action, record_id, old_data, new_data, role
  ) VALUES (
    v_actor_id,
    'Applicant Movement',
    'UPDATE',
    p_request_id,
    jsonb_build_object(
      'source_applicant_id', v_req.source_applicant_id,
      'source_vcode', v_req.source_vacancy_vcode,
      'target_applicant_id', v_req.target_applicant_id,
      'target_vcode', v_req.target_vacancy_vcode
    ),
    jsonb_build_object(
      'request_number', v_req.request_number,
      'movement_type', 'SWAP',
      'source_applicant_id', v_req.source_applicant_id,
      'source_new_vcode', v_req.target_vacancy_vcode,
      'target_applicant_id', v_req.target_applicant_id,
      'target_new_vcode', v_req.source_vacancy_vcode,
      'requested_by', v_req.requested_by_name,
      'reason', v_req.reason
    ),
    COALESCE(v_req.requested_by_role, 'Applicant Movement')
  );

  -- Stamp execution time
  UPDATE public.applicant_movement_requests
  SET executed_at = now(),
      updated_at  = now()
  WHERE id = p_request_id;
END;
$$;

-- ─── RPC: create_applicant_movement_request ───────────────────
CREATE OR REPLACE FUNCTION public.create_applicant_movement_request(
  p_movement_type          text,     -- 'TRANSFER' | 'SWAP'
  p_source_applicant_id    uuid,
  p_target_vacancy_vcode   text,
  p_target_applicant_id    uuid DEFAULT NULL,   -- SWAP only
  p_reason                 text DEFAULT NULL,
  p_remarks                text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me              public.users_profile%ROWTYPE;
  v_me_role_level   int;
  v_src_app         public.applicants%ROWTYPE;
  v_tgt_app         public.applicants%ROWTYPE;
  v_src_vac         RECORD;
  v_tgt_vac         RECORD;
  v_src_acct        RECORD;
  v_tgt_acct        RECORD;
  v_stages          text[];
  v_first_stage     text;
  v_request_id      uuid;
  v_request_number  text;
  v_year            text;
  v_seq             bigint;
  v_blocked_statuses text[] := ARRAY['Confirmed Onboard', 'Hired'];
  v_first_approver  public.users_profile%ROWTYPE;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────
  SELECT * INTO v_me
  FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_FORBIDDEN: Authenticated user not found in users_profile'
      USING ERRCODE = '42501';
  END IF;

  SELECT r.role_level INTO v_me_role_level
  FROM public.roles r WHERE r.id = v_me.role_id;

  -- Must be at least Ops level (40) to submit
  IF COALESCE(v_me_role_level, 0) < 40 THEN
    RAISE EXCEPTION 'AMR_FORBIDDEN: Your role does not permit submitting movement requests (minimum: Ops/ATL/TL level 40)'
      USING ERRCODE = '42501';
  END IF;

  -- ── Validate movement type ────────────────────────────────
  IF p_movement_type NOT IN ('TRANSFER', 'SWAP') THEN
    RAISE EXCEPTION 'AMR_INVALID: movement_type must be TRANSFER or SWAP'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- ── Validate reason ───────────────────────────────────────
  IF nullif(trim(coalesce(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'AMR_INVALID: reason is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF p_reason = 'Other' AND (nullif(trim(coalesce(p_remarks, '')), '') IS NULL OR length(trim(p_remarks)) < 20) THEN
    RAISE EXCEPTION 'AMR_INVALID: remarks are required (min 20 chars) when reason is Other'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- ── Validate source applicant ─────────────────────────────
  SELECT * INTO v_src_app
  FROM public.applicants
  WHERE id = p_source_applicant_id
    AND (is_archived IS NULL OR is_archived = false);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_INVALID: Source applicant % not found or archived', p_source_applicant_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_src_app.status = ANY(v_blocked_statuses) THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Source applicant is in a blocked status (%)', v_src_app.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block if applicant already linked to plantilla
  IF v_src_app.applicant_source = 'plantilla' OR v_src_app.linked_plantilla_id IS NOT NULL THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Source applicant is linked to Plantilla and cannot be moved'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_src_app.coverage_group_id IS NOT NULL OR v_src_app.coverage_slot_id IS NOT NULL THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Source applicant is linked to Coverage Group and cannot be moved through Applicant Movement Requests'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block if source applicant already has an active AMR
  IF EXISTS (
    SELECT 1 FROM public.applicant_movement_requests
    WHERE source_applicant_id = p_source_applicant_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Source applicant already has a pending movement request'
      USING ERRCODE = 'check_violation';
  END IF;

  -- ── Fetch source vacancy ──────────────────────────────────
  SELECT
    v.id              AS vacancy_id,
    v.vcode,
    v.account,
    a_src.id          AS account_id,
    a_src.group_id    AS group_id,
    v.status          AS vacancy_status,
    v.is_archived,
    COALESCE(v.has_reliever, false) AS has_reliever,
    v.vacancy_type,
    v.employment_type
  INTO v_src_vac
  FROM public.vacancies v
  LEFT JOIN public.accounts a_src ON a_src.account_name = v.account
  WHERE v.vcode = v_src_app.vacancy_vcode
    AND v.deleted_at IS NULL
  LIMIT 1;

  -- ── Fetch target vacancy ──────────────────────────────────
  IF nullif(trim(coalesce(p_target_vacancy_vcode, '')), '') IS NULL THEN
    RAISE EXCEPTION 'AMR_INVALID: target_vacancy_vcode is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_target_vacancy_vcode = v_src_app.vacancy_vcode THEN
    RAISE EXCEPTION 'AMR_INVALID: Target vacancy must be different from source vacancy'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT
    v.id              AS vacancy_id,
    v.vcode,
    v.account,
    a_tgt.id          AS account_id,
    a_tgt.group_id    AS group_id,
    v.status          AS vacancy_status,
    v.is_archived,
    v.has_pending_closure,
    COALESCE(v.has_reliever, false) AS has_reliever,
    v.vacancy_type,
    v.employment_type
  INTO v_tgt_vac
  FROM public.vacancies v
  LEFT JOIN public.accounts a_tgt ON a_tgt.account_name = v.account
  WHERE v.vcode = p_target_vacancy_vcode
    AND v.deleted_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_INVALID: Target vacancy % not found', p_target_vacancy_vcode
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_tgt_vac.is_archived THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Target vacancy % is archived', p_target_vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_tgt_vac.has_pending_closure THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Target vacancy % has a pending closure request', p_target_vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  IF COALESCE(v_src_vac.has_reliever, false)
     OR lower(coalesce(v_src_vac.vacancy_type, '')) IN ('reliever', 'commando')
     OR lower(coalesce(v_src_vac.employment_type, '')) IN ('reliever', 'commando') THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Source vacancy % is a Reliever/Commando coverage vacancy and cannot be moved through Applicant Movement Requests', v_src_app.vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  IF COALESCE(v_tgt_vac.has_reliever, false)
     OR lower(coalesce(v_tgt_vac.vacancy_type, '')) IN ('reliever', 'commando')
     OR lower(coalesce(v_tgt_vac.employment_type, '')) IN ('reliever', 'commando') THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Target vacancy % is a Reliever/Commando coverage vacancy and cannot be used for Applicant Movement Requests', p_target_vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block: target already reserved by another active request
  IF EXISTS (
    SELECT 1
    FROM public.applicant_movement_reservations res
    JOIN public.applicant_movement_requests r2 ON r2.id = res.request_id
    WHERE res.reserved_vcode = p_target_vacancy_vcode
      AND res.released_at IS NULL
      AND r2.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Target vacancy % is already reserved by a pending movement request', p_target_vacancy_vcode
      USING ERRCODE = 'check_violation';
  END IF;

  -- ── SWAP-specific validation ──────────────────────────────
  IF p_movement_type = 'SWAP' THEN
    IF p_target_applicant_id IS NULL THEN
      RAISE EXCEPTION 'AMR_INVALID: SWAP requires target_applicant_id'
        USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT * INTO v_tgt_app
    FROM public.applicants
    WHERE id = p_target_applicant_id
      AND (is_archived IS NULL OR is_archived = false);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'AMR_INVALID: Target applicant % not found or archived', p_target_applicant_id
        USING ERRCODE = 'no_data_found';
    END IF;

    IF v_tgt_app.status = ANY(v_blocked_statuses) THEN
      RAISE EXCEPTION 'AMR_BLOCKED: Target applicant is in a blocked status (%)', v_tgt_app.status
        USING ERRCODE = 'check_violation';
    END IF;

    -- Target applicant must be in the target vacancy
    IF v_tgt_app.vacancy_vcode <> p_target_vacancy_vcode THEN
      RAISE EXCEPTION 'AMR_INVALID: Target applicant % is not assigned to target vacancy %',
        p_target_applicant_id, p_target_vacancy_vcode
        USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Block if target applicant already linked to plantilla
    IF v_tgt_app.applicant_source = 'plantilla' OR v_tgt_app.linked_plantilla_id IS NOT NULL THEN
      RAISE EXCEPTION 'AMR_BLOCKED: Target applicant is linked to Plantilla and cannot be moved'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_tgt_app.coverage_group_id IS NOT NULL OR v_tgt_app.coverage_slot_id IS NOT NULL THEN
      RAISE EXCEPTION 'AMR_BLOCKED: Target applicant is linked to Coverage Group and cannot be moved through Applicant Movement Requests'
        USING ERRCODE = 'check_violation';
    END IF;

    -- Block if target applicant already has an active AMR
    IF EXISTS (
      SELECT 1 FROM public.applicant_movement_requests
      WHERE (source_applicant_id = p_target_applicant_id OR target_applicant_id = p_target_applicant_id)
        AND status = 'pending'
    ) THEN
      RAISE EXCEPTION 'AMR_BLOCKED: Target applicant already has a pending movement request'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- TRANSFER-specific: target vacancy must have an open slot
  IF p_movement_type = 'TRANSFER' THEN
    -- Check via shadow view first, fallback to vacancies
    DECLARE
      v_open_count int := 0;
    BEGIN
      SELECT COALESCE(open_count, 0)
      INTO v_open_count
      FROM public.vw_slot_derived_vacancy_shadow
      WHERE legacy_vcode = p_target_vacancy_vcode;

      IF NOT FOUND THEN
        SELECT CASE WHEN v_tgt_vac.vacancy_status = 'Open' THEN 1 ELSE 0 END
        INTO v_open_count;
      END IF;

      IF v_open_count < 1 THEN
        RAISE EXCEPTION 'AMR_BLOCKED: Target vacancy % has no open slots', p_target_vacancy_vcode
          USING ERRCODE = 'check_violation';
      END IF;
    END;
  END IF;

  -- ── Determine approval stages ─────────────────────────────
  v_stages := public.fn_amr_determine_stages(
    v_me_role_level,
    v_src_vac.group_id,
    v_tgt_vac.group_id,
    v_src_vac.account_id,
    v_tgt_vac.account_id
  );

  v_first_stage := CASE WHEN array_length(v_stages, 1) > 0 THEN v_stages[1] ELSE NULL END;

  -- ── Generate request number ───────────────────────────────
  v_year   := extract(year FROM now())::text;
  v_seq    := nextval('public.amr_request_number_seq');
  v_request_number := 'AMR-' || v_year || '-' || lpad(v_seq::text, 4, '0');

  -- ── Create request ────────────────────────────────────────
  INSERT INTO public.applicant_movement_requests (
    request_number, movement_type, status, approval_stage,
    source_applicant_id, source_vacancy_vcode, source_account_id, source_account_name, source_group_id,
    target_vacancy_vcode, target_account_id, target_account_name, target_group_id,
    target_applicant_id,
    reason, remarks,
    requested_by, requested_by_name, requested_by_role, requested_by_role_level
  ) VALUES (
    v_request_number,
    p_movement_type,
    CASE WHEN v_first_stage IS NULL THEN 'pending' ELSE 'pending' END,
    v_first_stage,
    p_source_applicant_id,
    v_src_app.vacancy_vcode,
    v_src_vac.account_id,
    v_src_vac.account,
    v_src_vac.group_id,
    p_target_vacancy_vcode,
    v_tgt_vac.account_id,
    v_tgt_vac.account,
    v_tgt_vac.group_id,
    CASE p_movement_type WHEN 'SWAP' THEN p_target_applicant_id ELSE NULL END,
    p_reason,
    p_remarks,
    v_me.id,
    v_me.full_name,
    (SELECT role_name FROM public.roles WHERE id = v_me.role_id),
    v_me_role_level
  )
  RETURNING id INTO v_request_id;

  -- ── Create reservation ────────────────────────────────────
  INSERT INTO public.applicant_movement_reservations (request_id, reserved_vcode)
  VALUES (v_request_id, p_target_vacancy_vcode);

  -- ── Write history ─────────────────────────────────────────
  INSERT INTO public.applicant_movement_request_history (
    request_id, from_status, to_status, from_stage, to_stage,
    action, actor_id, actor_name, actor_role, actor_role_level, note
  ) VALUES (
    v_request_id, NULL, 'pending', NULL, v_first_stage,
    'submitted', v_me.id, v_me.full_name,
    (SELECT role_name FROM public.roles WHERE id = v_me.role_id),
    v_me_role_level,
    'Request submitted. Movement type: ' || p_movement_type || '. Reason: ' || p_reason
  );

  -- Direct matrix paths execute immediately: SA direct, HA same-account/same-group
  -- direct, and Encoder same-account direct.
  IF v_first_stage IS NULL THEN
    UPDATE public.applicant_movement_requests
    SET
      status = 'approved',
      encoder_approved_by = CASE WHEN v_me_role_level >= 30 AND v_me_role_level < 90 THEN v_me.id ELSE encoder_approved_by END,
      encoder_approved_at = CASE WHEN v_me_role_level >= 30 AND v_me_role_level < 90 THEN now() ELSE encoder_approved_at END,
      ha_approved_by      = CASE WHEN v_me_role_level >= 90 AND v_me_role_level < 100 THEN v_me.id ELSE ha_approved_by END,
      ha_approved_at      = CASE WHEN v_me_role_level >= 90 AND v_me_role_level < 100 THEN now() ELSE ha_approved_at END,
      sa_approved_by      = CASE WHEN v_me_role_level >= 100 THEN v_me.id ELSE sa_approved_by END,
      sa_approved_at      = CASE WHEN v_me_role_level >= 100 THEN now() ELSE sa_approved_at END,
      updated_at          = now()
    WHERE id = v_request_id;

    INSERT INTO public.applicant_movement_request_history (
      request_id, from_status, to_status, from_stage, to_stage,
      action, actor_id, actor_name, actor_role, actor_role_level, note
    ) VALUES (
      v_request_id, 'pending', 'approved', NULL, NULL,
      'approved_final', v_me.id, v_me.full_name,
      (SELECT role_name FROM public.roles WHERE id = v_me.role_id),
      v_me_role_level,
      'Direct approval path executed by ' || v_me.full_name
    );

    BEGIN
      IF p_movement_type = 'TRANSFER' THEN
        PERFORM public.fn_amr_execute_transfer(v_request_id);
      ELSE
        PERFORM public.fn_amr_execute_swap(v_request_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.applicant_movement_requests
      SET execution_error = SQLERRM, updated_at = now()
      WHERE id = v_request_id;

      INSERT INTO public.applicant_movement_request_history (
        request_id, from_status, to_status, action,
        actor_id, actor_name, note
      ) VALUES (
        v_request_id, 'approved', 'approved', 'execution_failed',
        v_me.id, v_me.full_name,
        'Execution failed: ' || SQLERRM
      );
    END;

    PERFORM public.fn_amr_release_reservation(v_request_id, 'approved');

    PERFORM public.notify_user(
      v_me.auth_user_id,
      (SELECT role_name FROM public.roles WHERE id = v_me.role_id),
      'Applicant Movement Request Approved — ' || v_request_number,
      'Your ' || p_movement_type || ' request for vacancy ' || p_target_vacancy_vcode || ' has been approved and executed.',
      'approved',
      'applicant_movement',
      'applicant_movement',
      v_request_id::text,
      '/requests/applicant-movement/' || v_request_id::text,
      NULL
    );

    RETURN jsonb_build_object(
      'request_id',     v_request_id,
      'request_number', v_request_number,
      'status',         'approved',
      'approval_stage', NULL,
      'stages_required', v_stages
    );
  END IF;

  -- ── Send notifications ────────────────────────────────────
  -- Notify requester
  PERFORM public.notify_user(
    v_me.auth_user_id,
    (SELECT role_name FROM public.roles WHERE id = v_me.role_id),
    'Applicant Movement Request Submitted — ' || v_request_number,
    'Your ' || p_movement_type || ' request for vacancy ' || p_target_vacancy_vcode || ' has been submitted and is pending review.',
    'confirmation',
    'applicant_movement',
    'applicant_movement',
    v_request_id::text,
    '/requests/applicant-movement/' || v_request_id::text,
    NULL
  );

  -- Notify first approver role if stage required
  IF v_first_stage = 'encoder' THEN
    -- Notify Encoders in the relevant group
    FOR v_first_approver IN
      SELECT up.* FROM public.users_profile up
      JOIN public.roles r ON r.id = up.role_id
      WHERE r.role_name = 'Encoder'
        AND up.is_active = true
        AND up.auth_user_id IS NOT NULL
        AND (
          up.group_id = v_src_vac.group_id
          OR up.group_id = v_tgt_vac.group_id
        )
    LOOP
      PERFORM public.notify_user(
        v_first_approver.auth_user_id,
        'Encoder',
        'Action Required: Applicant Movement Request — ' || v_request_number,
        v_me.full_name || ' has submitted a ' || p_movement_type || ' request. Please review.',
        'approval_required',
        'applicant_movement',
        'applicant_movement',
        v_request_id::text,
        '/requests/applicant-movement/' || v_request_id::text,
        NULL
      );
    END LOOP;

  ELSIF v_first_stage = 'ha' THEN
    FOR v_first_approver IN
      SELECT up.* FROM public.users_profile up
      JOIN public.roles r ON r.id = up.role_id
      WHERE r.role_name = 'Head Admin'
        AND up.is_active = true
        AND up.auth_user_id IS NOT NULL
    LOOP
      PERFORM public.notify_user(
        v_first_approver.auth_user_id,
        'Head Admin',
        'Action Required: Applicant Movement Request — ' || v_request_number,
        v_me.full_name || ' has submitted a ' || p_movement_type || ' request. Please review.',
        'approval_required',
        'applicant_movement',
        'applicant_movement',
        v_request_id::text,
        '/requests/applicant-movement/' || v_request_id::text,
        NULL
      );
    END LOOP;

  ELSIF v_first_stage = 'sa' OR v_first_stage IS NULL THEN
    -- Direct (SA, HA as requester, or same-account Encoder) — no additional notify needed
    -- unless direct approval is needed from SA
    IF v_first_stage = 'sa' THEN
      FOR v_first_approver IN
        SELECT up.* FROM public.users_profile up
        JOIN public.roles r ON r.id = up.role_id
        WHERE r.role_name = 'Super Admin'
          AND up.is_active = true
          AND up.auth_user_id IS NOT NULL
      LOOP
        PERFORM public.notify_user(
          v_first_approver.auth_user_id,
          'Super Admin',
          'Action Required: Applicant Movement Request — ' || v_request_number,
          v_me.full_name || ' has submitted a ' || p_movement_type || ' request requiring SA approval.',
          'approval_required',
          'applicant_movement',
          'applicant_movement',
          v_request_id::text,
          '/requests/applicant-movement/' || v_request_id::text,
          NULL
        );
      END LOOP;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'request_id',     v_request_id,
    'request_number', v_request_number,
    'status',         'pending',
    'approval_stage', v_first_stage,
    'stages_required', v_stages
  );
END;
$$;

-- ─── RPC: approve_applicant_movement_request ──────────────────
CREATE OR REPLACE FUNCTION public.approve_applicant_movement_request(
  p_request_id uuid,
  p_note       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me              public.users_profile%ROWTYPE;
  v_me_role_level   int;
  v_req             public.applicant_movement_requests%ROWTYPE;
  v_stages          text[];
  v_current_idx     int;
  v_next_stage      text;
  v_is_final        bool;
  v_next_approver   public.users_profile%ROWTYPE;
BEGIN
  -- ── Auth ──────────────────────────────────────────────────
  SELECT * INTO v_me FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_FORBIDDEN: User not found' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_level INTO v_me_role_level
  FROM public.roles r WHERE r.id = v_me.role_id;

  -- ── Fetch request ─────────────────────────────────────────
  SELECT * INTO v_req FROM public.applicant_movement_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_NOT_FOUND: Request % not found', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'AMR_INVALID: Request is not in pending status (current: %)', v_req.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- ── Authorize current approver ────────────────────────────
  CASE v_req.approval_stage
    WHEN 'encoder' THEN
      IF v_me_role_level <> 30 THEN
        IF NOT i_have_full_access() THEN
          RAISE EXCEPTION 'AMR_FORBIDDEN: Encoder stage requires Encoder role (or SA/HA override)'
            USING ERRCODE = '42501';
        END IF;
      END IF;
    WHEN 'ha' THEN
      IF NOT i_have_full_access() THEN
        RAISE EXCEPTION 'AMR_FORBIDDEN: HA stage requires Head Admin or Super Admin'
          USING ERRCODE = '42501';
      END IF;
    WHEN 'sa' THEN
      IF NOT (v_me_role_level >= 100) THEN
        RAISE EXCEPTION 'AMR_FORBIDDEN: SA stage requires Super Admin'
          USING ERRCODE = '42501';
      END IF;
    ELSE
      -- NULL (direct) — requester was SA/HA/same-account Encoder
      -- Only SA/HA can approve a "direct" request (it auto-approves on creation for SA/HA requesters,
      -- so if we reach here it means another SA/HA is approving for completeness)
      IF NOT i_have_full_access() THEN
        RAISE EXCEPTION 'AMR_FORBIDDEN: This request was submitted as direct approval — only SA/HA can confirm'
          USING ERRCODE = '42501';
      END IF;
  END CASE;

  -- ── Recalculate stages to find next ───────────────────────
  v_stages := public.fn_amr_determine_stages(
    v_req.requested_by_role_level,
    v_req.source_group_id,
    v_req.target_group_id,
    v_req.source_account_id,
    v_req.target_account_id
  );

  -- Find current index
  v_current_idx := array_position(v_stages, v_req.approval_stage);

  -- Next stage (if any)
  IF v_current_idx IS NULL OR v_current_idx >= array_length(v_stages, 1) THEN
    v_next_stage := NULL;
    v_is_final   := true;
  ELSE
    v_next_stage := v_stages[v_current_idx + 1];
    v_is_final   := false;
  END IF;

  -- If no stages array at all (direct), treat as final
  IF array_length(v_stages, 1) IS NULL THEN
    v_next_stage := NULL;
    v_is_final   := true;
  END IF;

  -- ── Stamp current stage approval ──────────────────────────
  UPDATE public.applicant_movement_requests
  SET
    approval_stage           = v_next_stage,
    status                   = CASE WHEN v_is_final THEN 'approved' ELSE 'pending' END,
    encoder_approved_by      = CASE WHEN v_req.approval_stage = 'encoder' THEN v_me.id ELSE encoder_approved_by END,
    encoder_approved_at      = CASE WHEN v_req.approval_stage = 'encoder' THEN now() ELSE encoder_approved_at END,
    ha_approved_by           = CASE WHEN v_req.approval_stage = 'ha' OR (v_req.approval_stage IS NULL AND i_have_full_access() AND NOT (v_me_role_level >= 100)) THEN v_me.id ELSE ha_approved_by END,
    ha_approved_at           = CASE WHEN v_req.approval_stage = 'ha' OR (v_req.approval_stage IS NULL AND i_have_full_access() AND NOT (v_me_role_level >= 100)) THEN now() ELSE ha_approved_at END,
    sa_approved_by           = CASE WHEN v_req.approval_stage = 'sa' OR (v_req.approval_stage IS NULL AND v_me_role_level >= 100) THEN v_me.id ELSE sa_approved_by END,
    sa_approved_at           = CASE WHEN v_req.approval_stage = 'sa' OR (v_req.approval_stage IS NULL AND v_me_role_level >= 100) THEN now() ELSE sa_approved_at END,
    updated_at               = now()
  WHERE id = p_request_id;

  -- ── Write history ─────────────────────────────────────────
  INSERT INTO public.applicant_movement_request_history (
    request_id, from_status, to_status, from_stage, to_stage,
    action, actor_id, actor_name, actor_role, actor_role_level, note
  ) VALUES (
    p_request_id,
    'pending',
    CASE WHEN v_is_final THEN 'approved' ELSE 'pending' END,
    v_req.approval_stage,
    v_next_stage,
    CASE WHEN v_is_final THEN 'approved_final' ELSE 'approved_stage' END,
    v_me.id,
    v_me.full_name,
    (SELECT role_name FROM public.roles WHERE id = v_me.role_id),
    v_me_role_level,
    COALESCE(p_note, 'Stage approved by ' || v_me.full_name)
  );

  -- ── Execute movement if final approval ────────────────────
  IF v_is_final THEN
    BEGIN
      IF v_req.movement_type = 'TRANSFER' THEN
        PERFORM public.fn_amr_execute_transfer(p_request_id);
      ELSE
        PERFORM public.fn_amr_execute_swap(p_request_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Log execution failure but don't roll back approval
      UPDATE public.applicant_movement_requests
      SET execution_error = SQLERRM, updated_at = now()
      WHERE id = p_request_id;

      INSERT INTO public.applicant_movement_request_history (
        request_id, from_status, to_status, action,
        actor_id, actor_name, note
      ) VALUES (
        p_request_id, 'approved', 'approved', 'execution_failed',
        v_me.id, v_me.full_name,
        'Execution failed: ' || SQLERRM
      );
    END;

    -- Release reservation
    PERFORM public.fn_amr_release_reservation(p_request_id, 'approved');

    -- Notify requester of approval
    PERFORM public.notify_user(
      (SELECT auth_user_id FROM public.users_profile WHERE id = v_req.requested_by),
      v_req.requested_by_role,
      'Applicant Movement Request Approved — ' || v_req.request_number,
      'Your ' || v_req.movement_type || ' request for vacancy ' || v_req.target_vacancy_vcode || ' has been approved and executed.',
      'approved',
      'applicant_movement',
      'applicant_movement',
      p_request_id::text,
      '/requests/applicant-movement/' || p_request_id::text,
      NULL
    );

  ELSE
    -- Notify next stage approver
    DECLARE
      v_next_role text := CASE v_next_stage
        WHEN 'encoder' THEN 'Encoder'
        WHEN 'ha'      THEN 'Head Admin'
        WHEN 'sa'      THEN 'Super Admin'
      END;
    BEGIN
      FOR v_next_approver IN
        SELECT up.* FROM public.users_profile up
        JOIN public.roles r ON r.id = up.role_id
        WHERE r.role_name = v_next_role
          AND up.is_active = true
          AND up.auth_user_id IS NOT NULL
          AND (v_next_role NOT IN ('Encoder') OR (
            up.group_id = v_req.source_group_id
            OR up.group_id = v_req.target_group_id
          ))
      LOOP
        PERFORM public.notify_user(
          v_next_approver.auth_user_id,
          v_next_role,
          'Action Required: Applicant Movement Request — ' || v_req.request_number,
          'Encoder has approved stage. Your review is now required for ' || v_req.movement_type || ' request.',
          'approval_required',
          'applicant_movement',
          'applicant_movement',
          p_request_id::text,
          '/requests/applicant-movement/' || p_request_id::text,
          NULL
        );
      END LOOP;
    END;
  END IF;

  RETURN jsonb_build_object(
    'request_id',   p_request_id,
    'status',       CASE WHEN v_is_final THEN 'approved' ELSE 'pending' END,
    'next_stage',   v_next_stage,
    'is_final',     v_is_final
  );
END;
$$;

-- ─── RPC: reject_applicant_movement_request ───────────────────
CREATE OR REPLACE FUNCTION public.reject_applicant_movement_request(
  p_request_id uuid,
  p_reason     text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me            public.users_profile%ROWTYPE;
  v_me_role_level int;
  v_req           public.applicant_movement_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_me FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_FORBIDDEN: User not found' USING ERRCODE = '42501';
  END IF;

  SELECT r.role_level INTO v_me_role_level
  FROM public.roles r WHERE r.id = v_me.role_id;

  SELECT * INTO v_req FROM public.applicant_movement_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_NOT_FOUND: Request % not found', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'AMR_INVALID: Only pending requests can be rejected (current: %)', v_req.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Must be the current stage approver or SA/HA
  IF NOT (
    i_have_full_access()
    OR (v_req.approval_stage = 'encoder' AND v_me_role_level = 30)
    OR (v_req.approval_stage = 'ha' AND i_have_full_access())
    OR (v_req.approval_stage = 'sa' AND v_me_role_level >= 100)
    OR (v_req.approval_stage IS NULL AND i_have_full_access())
  ) THEN
    RAISE EXCEPTION 'AMR_FORBIDDEN: You do not have permission to reject this request at stage %', v_req.approval_stage
      USING ERRCODE = '42501';
  END IF;

  IF nullif(trim(coalesce(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'AMR_INVALID: Rejection reason is required'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE public.applicant_movement_requests
  SET status           = 'rejected',
      rejected_by      = v_me.id,
      rejected_at      = now(),
      rejection_reason = p_reason,
      updated_at       = now()
  WHERE id = p_request_id;

  PERFORM public.fn_amr_release_reservation(p_request_id, 'rejected');

  INSERT INTO public.applicant_movement_request_history (
    request_id, from_status, to_status, from_stage, to_stage,
    action, actor_id, actor_name, actor_role, actor_role_level, note
  ) VALUES (
    p_request_id, 'pending', 'rejected', v_req.approval_stage, NULL,
    'rejected', v_me.id, v_me.full_name,
    (SELECT role_name FROM public.roles WHERE id = v_me.role_id),
    v_me_role_level,
    'Rejected: ' || p_reason
  );

  -- Notify requester
  PERFORM public.notify_user(
    (SELECT auth_user_id FROM public.users_profile WHERE id = v_req.requested_by),
    v_req.requested_by_role,
    'Applicant Movement Request Rejected — ' || v_req.request_number,
    'Your ' || v_req.movement_type || ' request for vacancy ' || v_req.target_vacancy_vcode || ' was rejected. Reason: ' || p_reason,
    'rejected',
    'applicant_movement',
    'applicant_movement',
    p_request_id::text,
    '/requests/applicant-movement/' || p_request_id::text,
    NULL
  );
END;
$$;

-- ─── RPC: withdraw_applicant_movement_request ─────────────────
CREATE OR REPLACE FUNCTION public.withdraw_applicant_movement_request(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me        public.users_profile%ROWTYPE;
  v_req       public.applicant_movement_requests%ROWTYPE;
  v_had_first_action bool;
BEGIN
  SELECT * INTO v_me FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_FORBIDDEN: User not found' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req FROM public.applicant_movement_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'AMR_NOT_FOUND: Request % not found', p_request_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Only the original requester (or SA/HA) can withdraw
  IF v_req.requested_by <> v_me.id AND NOT i_have_full_access() THEN
    RAISE EXCEPTION 'AMR_FORBIDDEN: Only the requester or SA/HA can withdraw a request'
      USING ERRCODE = '42501';
  END IF;

  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'AMR_INVALID: Only pending requests can be withdrawn (current: %)', v_req.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Block withdrawal if any approval action has been taken
  v_had_first_action := (
    v_req.encoder_approved_at IS NOT NULL
    OR v_req.ha_approved_at IS NOT NULL
    OR v_req.sa_approved_at IS NOT NULL
  );

  IF v_had_first_action AND NOT i_have_full_access() THEN
    RAISE EXCEPTION 'AMR_BLOCKED: Cannot withdraw a request after approval action has been taken. Contact SA/HA to reject instead.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.applicant_movement_requests
  SET status       = 'withdrawn',
      withdrawn_by = v_me.id,
      withdrawn_at = now(),
      updated_at   = now()
  WHERE id = p_request_id;

  PERFORM public.fn_amr_release_reservation(p_request_id, 'withdrawn');

  INSERT INTO public.applicant_movement_request_history (
    request_id, from_status, to_status, action,
    actor_id, actor_name, note
  ) VALUES (
    p_request_id, 'pending', 'withdrawn', 'withdrawn',
    v_me.id, v_me.full_name,
    'Withdrawn by ' || v_me.full_name
  );
END;
$$;

-- ─── RPC: get_applicant_movement_requests ─────────────────────
-- Flutter calls this for both requester view and approver queue.
CREATE OR REPLACE FUNCTION public.get_applicant_movement_requests(
  p_filter jsonb DEFAULT '{}'::jsonb
)
RETURNS SETOF public.vw_amr_list
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me            public.users_profile%ROWTYPE;
  v_me_role_level int;
  v_mine_only     bool;
  v_status_filter text;
  v_type_filter   text;
BEGIN
  SELECT * INTO v_me FROM public.users_profile
  WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT r.role_level INTO v_me_role_level
  FROM public.roles r WHERE r.id = v_me.role_id;

  v_mine_only     := COALESCE((p_filter->>'mine_only')::bool, false);
  v_status_filter := p_filter->>'status';
  v_type_filter   := p_filter->>'movement_type';

  RETURN QUERY
  SELECT *
  FROM public.vw_amr_list r
  WHERE
    (
      -- Requester sees own requests
      r.requested_by = v_me.id
      -- Approvers see all (with RLS on base table already filtering)
      OR (NOT v_mine_only AND (i_have_full_access() OR v_me_role_level >= 30))
    )
    AND (v_status_filter IS NULL OR r.status = v_status_filter)
    AND (v_type_filter IS NULL OR r.movement_type = v_type_filter)
  ORDER BY r.created_at DESC;
END;
$$;

-- ─── RPC: get_amr_vacancy_reservation ─────────────────────────
CREATE OR REPLACE FUNCTION public.get_amr_vacancy_reservation(p_vcode text)
RETURNS TABLE (
  request_id       uuid,
  request_number   text,
  movement_type    text,
  request_status   text,
  approval_stage   text,
  requested_by_name text,
  reserved_at      timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    r.request_id,
    r.request_number,
    r.movement_type,
    r.request_status,
    r.approval_stage,
    r.requested_by_name,
    r.reserved_at
  FROM public.vw_amr_vacancy_reservation_status r
  WHERE r.vcode = p_vcode;
END;
$$;

-- ─── RPC: fn_amr_sla_escalation ───────────────────────────────
-- Day 3: escalate to Head Admin. Day 5: escalate to Super Admin.
-- Designed to be called by pg_cron once per day.
CREATE OR REPLACE FUNCTION public.fn_amr_sla_escalation()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r           RECORD;
  v_ha        RECORD;
  v_sa        RECORD;
  v_day3_count int := 0;
  v_day5_count int := 0;
BEGIN
  -- Day 5: escalate to SA
  FOR r IN
    SELECT amr.*
    FROM public.applicant_movement_requests amr
    WHERE amr.status = 'pending'
      AND amr.requested_at < now() - INTERVAL '5 days'
      AND NOT EXISTS (
        SELECT 1 FROM public.applicant_movement_request_history h
        WHERE h.request_id = amr.id
          AND h.action = 'escalated'
          AND h.note LIKE '%Day 5%'
          AND h.created_at > now() - INTERVAL '1 day'
      )
  LOOP
    FOR v_sa IN
      SELECT up.* FROM public.users_profile up
      JOIN public.roles r ON r.id = up.role_id
      WHERE r.role_name = 'Super Admin'
        AND up.is_active = true AND up.auth_user_id IS NOT NULL
    LOOP
      PERFORM public.notify_user(
        v_sa.auth_user_id, 'Super Admin',
        'Escalated AMR — ' || r.request_number,
        'Applicant movement request ' || r.request_number || ' has been pending for over 5 days with no action.',
        'escalation', 'applicant_movement', 'applicant_movement',
        r.id::text, '/requests/applicant-movement/' || r.id::text, 2
      );
    END LOOP;
    -- Notify requester
    PERFORM public.notify_user(
      (SELECT auth_user_id FROM public.users_profile WHERE id = r.requested_by),
      r.requested_by_role,
      'Your AMR Escalated to Super Admin — ' || r.request_number,
      'Your ' || r.movement_type || ' request has been escalated to Super Admin after 5 days of no action.',
      'escalation', 'applicant_movement', 'applicant_movement',
      r.id::text, '/requests/applicant-movement/' || r.id::text, 2
    );
    INSERT INTO public.applicant_movement_request_history (
      request_id, from_status, to_status, action, note
    ) VALUES (r.id, 'pending', 'pending', 'escalated', 'Day 5: Escalated to Super Admin');
    v_day5_count := v_day5_count + 1;
  END LOOP;

  -- Day 3: escalate to HA
  FOR r IN
    SELECT amr.*
    FROM public.applicant_movement_requests amr
    WHERE amr.status = 'pending'
      AND amr.requested_at < now() - INTERVAL '3 days'
      AND amr.requested_at >= now() - INTERVAL '5 days'
      AND NOT EXISTS (
        SELECT 1 FROM public.applicant_movement_request_history h
        WHERE h.request_id = amr.id
          AND h.action = 'escalated'
          AND h.note LIKE '%Day 3%'
          AND h.created_at > now() - INTERVAL '1 day'
      )
  LOOP
    FOR v_ha IN
      SELECT up.* FROM public.users_profile up
      JOIN public.roles r ON r.id = up.role_id
      WHERE r.role_name = 'Head Admin'
        AND up.is_active = true AND up.auth_user_id IS NOT NULL
    LOOP
      PERFORM public.notify_user(
        v_ha.auth_user_id, 'Head Admin',
        'Unactioned AMR — ' || r.request_number,
        'Applicant movement request ' || r.request_number || ' has been pending for 3 days with no action.',
        'escalation', 'applicant_movement', 'applicant_movement',
        r.id::text, '/requests/applicant-movement/' || r.id::text, 1
      );
    END LOOP;
    PERFORM public.notify_user(
      (SELECT auth_user_id FROM public.users_profile WHERE id = r.requested_by),
      r.requested_by_role,
      'Your AMR Escalated to Head Admin — ' || r.request_number,
      'Your ' || r.movement_type || ' request has been escalated to Head Admin after 3 days.',
      'escalation', 'applicant_movement', 'applicant_movement',
      r.id::text, '/requests/applicant-movement/' || r.id::text, 1
    );
    INSERT INTO public.applicant_movement_request_history (
      request_id, from_status, to_status, action, note
    ) VALUES (r.id, 'pending', 'pending', 'escalated', 'Day 3: Escalated to Head Admin');
    v_day3_count := v_day3_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'day3_escalated', v_day3_count,
    'day5_escalated', v_day5_count,
    'run_at',         now()
  );
END;
$$;

-- ─── Grant execute to authenticated ───────────────────────────
GRANT EXECUTE ON FUNCTION public.create_applicant_movement_request(text, uuid, text, uuid, text, text)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_applicant_movement_request(uuid, text)                              TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_applicant_movement_request(uuid, text)                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_applicant_movement_request(uuid)                                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_applicant_movement_requests(jsonb)                                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_amr_vacancy_reservation(text)                                          TO authenticated;
-- fn_amr_sla_escalation is called by service role / pg_cron only
GRANT EXECUTE ON FUNCTION public.fn_amr_sla_escalation()                                                     TO service_role;

-- Grant SELECT on views
GRANT SELECT ON public.vw_amr_list TO authenticated;
GRANT SELECT ON public.vw_amr_vacancy_reservation_status TO authenticated;
