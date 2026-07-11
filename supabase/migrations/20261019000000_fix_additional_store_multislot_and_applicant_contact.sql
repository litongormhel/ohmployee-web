-- OHM2026_0090
-- Fix Plantilla additional-store multi-slot vacancy closure and applicant
-- contact normalization.
--
-- Vacancy invariant:
-- A VCODE may become Filled only when no active non-roving slot remains in
-- open, pipeline, or hr_processing.
--
-- Contact invariant:
-- Applicant contacts are stored as canonical 09XXXXXXXXX when present.
-- Blank contact values become NULL. 10-digit 9XXXXXXXXX input is accepted and
-- normalized; invalid non-empty values still fail before the table CHECK.

-- --------------------------------------------------------------------------
-- Applicant contact normalization
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_normalize_applicant_contact_number(
  p_contact  text,
  p_required boolean DEFAULT false
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_raw    text := btrim(COALESCE(p_contact, ''));
  v_digits text;
BEGIN
  IF v_raw = '' THEN
    IF p_required THEN
      RAISE EXCEPTION 'contact_number is required'
        USING ERRCODE = '22023';
    END IF;
    RETURN NULL;
  END IF;

  v_digits := regexp_replace(v_raw, '[^0-9]', '', 'g');

  IF v_digits ~ '^9[0-9]{9}$' THEN
    RETURN '0' || v_digits;
  END IF;

  IF v_digits ~ '^09[0-9]{9}$' THEN
    RETURN v_digits;
  END IF;

  RAISE EXCEPTION
    'contact_number must be 10 digits starting with 9 or 11 digits starting with 09 (received: %)',
    p_contact
    USING ERRCODE = '22023';
END;
$$;

COMMENT ON FUNCTION public.fn_normalize_applicant_contact_number(text, boolean) IS
  'Normalizes applicant PH mobile contacts to 09XXXXXXXXX; blank optional values return NULL.';

CREATE OR REPLACE FUNCTION public.fn_validate_ph_contact_number(p_contact text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM public.fn_normalize_applicant_contact_number(p_contact, true);
END;
$$;

COMMENT ON FUNCTION public.fn_validate_ph_contact_number(text) IS
  'Validates applicant PH mobile contacts. Accepts 9XXXXXXXXX and 09XXXXXXXXX.';

CREATE OR REPLACE FUNCTION public.trg_normalize_applicant_contact_number()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.contact_number := public.fn_normalize_applicant_contact_number(
    NEW.contact_number,
    false
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_applicant_contact_number
  ON public.applicants;

CREATE TRIGGER trg_normalize_applicant_contact_number
BEFORE INSERT OR UPDATE OF contact_number
ON public.applicants
FOR EACH ROW
EXECUTE FUNCTION public.trg_normalize_applicant_contact_number();

UPDATE public.applicants
   SET contact_number = CASE
                          WHEN btrim(COALESCE(contact_number, '')) = '' THEN NULL
                          WHEN regexp_replace(btrim(contact_number), '[^0-9]', '', 'g') ~ '^9[0-9]{9}$'
                            THEN '0' || regexp_replace(btrim(contact_number), '[^0-9]', '', 'g')
                          WHEN regexp_replace(btrim(contact_number), '[^0-9]', '', 'g') ~ '^09[0-9]{9}$'
                            THEN regexp_replace(btrim(contact_number), '[^0-9]', '', 'g')
                          ELSE contact_number
                        END
 WHERE contact_number IS NOT NULL
   AND (
     btrim(contact_number) = ''
     OR regexp_replace(btrim(contact_number), '[^0-9]', '', 'g') ~ '^9[0-9]{9}$'
     OR regexp_replace(btrim(contact_number), '[^0-9]', '', 'g') ~ '^09[0-9]{9}$'
   );

-- Keep the existing CHECK as the final canonical-storage guard. It still
-- allows NULL and only allows stored non-null values in 09XXXXXXXXX format.
ALTER TABLE public.applicants
  DROP CONSTRAINT IF EXISTS chk_applicants_contact_number_format;

ALTER TABLE public.applicants
  ADD CONSTRAINT chk_applicants_contact_number_format
  CHECK (contact_number IS NULL OR contact_number ~ '^09[0-9]{9}$');

-- --------------------------------------------------------------------------
-- Slot sync helper: target an active slot, not an arbitrary VCODE row.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_sync_slot_to_occupied(
  p_vcode        text,
  p_hr_emploc_id uuid DEFAULT NULL,
  p_plantilla_id uuid DEFAULT NULL,
  p_performed_by uuid DEFAULT NULL,
  p_source_fn    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slot_id uuid;
  v_result  jsonb;
BEGIN
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: skipped - p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  IF p_plantilla_id IS NULL THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: skipped - p_plantilla_id is null, cannot set occupant link (VCODE=%, source=%)',
      p_vcode, COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  SELECT id INTO v_slot_id
    FROM public.plantilla_slots
   WHERE legacy_vcode = p_vcode
     AND COALESCE(is_roving, false) = false
     AND slot_status IN ('hr_processing', 'pipeline', 'open')
   ORDER BY CASE slot_status
              WHEN 'hr_processing' THEN 1
              WHEN 'pipeline' THEN 2
              WHEN 'open' THEN 3
              ELSE 4
            END,
            created_at,
            id
   LIMIT 1;

  IF v_slot_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT public.fn_set_slot_status(
    p_slot_id               => v_slot_id,
    p_new_status            => 'occupied',
    p_reason_code           => 'REPLACEMENT',
    p_performed_by          => p_performed_by,
    p_remarks               => format(
                                 'OHM2026_0090 / %s / VCODE=%s / hr_emploc_id=%s / plantilla_id=%s',
                                 COALESCE(p_source_fn, 'unknown'),
                                 p_vcode,
                                 COALESCE(p_hr_emploc_id::text, 'null'),
                                 p_plantilla_id::text
                               ),
    p_occupant_plantilla_id => p_plantilla_id
  ) INTO v_result;

  IF (v_result->>'status') IN ('blocked', 'no_op') THEN
    RAISE NOTICE
      'fn_sync_slot_to_occupied: % for slot_id=% VCODE=% plantilla_id=% source=% - %',
      v_result->>'status',
      v_slot_id,
      p_vcode,
      p_plantilla_id,
      COALESCE(p_source_fn, 'unknown'),
      COALESCE(v_result->>'blocked_reason', 'same-state no_op');
  END IF;

  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_slot_to_occupied: error for VCODE=% plantilla_id=% source=% - % (sqlstate=%)',
    p_vcode, p_plantilla_id, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.fn_sync_slot_to_occupied(text, uuid, uuid, uuid, text) IS
  'Slot sync helper. OHM2026_0090 targets active non-roving slots before occupied/no-op rows.';

-- --------------------------------------------------------------------------
-- Plantilla additional-store approval: Filled only when all slots are filled.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_approve_plantilla_additional_store(
  p_applicant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role         text  := public.get_my_role();
  v_role_level   int   := COALESCE(public.get_my_role_level(), 0);
  v_profile_id   uuid  := public.get_my_profile_id();
  v_app          public.applicants%ROWTYPE;
  v_linked_plt   public.plantilla%ROWTYPE;
  v_vac          public.vacancies%ROWTYPE;
  v_new_esa_id   uuid;
  v_target_vcode text;
BEGIN
  IF NOT (
    public.i_have_full_access()
    OR v_role_level IN (30, 90, 100)
    OR public.i_am_ops()
    OR v_role IN ('OM', 'HRCO', 'ATL', 'TL', 'Operations Manager')
  ) THEN
    RAISE EXCEPTION 'forbidden: Ops Team or Data Team required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_app
    FROM public.applicants
   WHERE id = p_applicant_id
  FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_app.is_archived, false) THEN
    RAISE EXCEPTION 'applicant % not found or archived', p_applicant_id
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_app.applicant_source, 'manual') <> 'plantilla' THEN
    RAISE EXCEPTION
      'applicant % is not a plantilla-sourced applicant (source=%)',
      p_applicant_id, COALESCE(v_app.applicant_source, 'manual')
      USING ERRCODE = '22023';
  END IF;

  IF v_app.linked_plantilla_id IS NULL THEN
    RAISE EXCEPTION
      'applicant % has applicant_source=plantilla but no linked_plantilla_id',
      p_applicant_id
      USING ERRCODE = '22023';
  END IF;

  IF v_app.status = 'Confirmed Onboard' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'applicant_id', v_app.id,
      'applicant_status', v_app.status,
      'vcode', v_app.vacancy_vcode,
      'idempotent', true
    );
  END IF;

  SELECT * INTO v_linked_plt
    FROM public.plantilla
   WHERE id = v_app.linked_plantilla_id
     AND COALESCE(is_deleted, false) = false
     AND COALESCE(is_archived, false) = false
     AND status IN ('Active', 'For Deactivation', 'On Leave')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'linked plantilla employee % not found or not active',
      v_app.linked_plantilla_id USING ERRCODE = 'P0002';
  END IF;

  IF v_linked_plt.employee_no IS NULL OR btrim(v_linked_plt.employee_no) = '' THEN
    RAISE EXCEPTION 'linked plantilla employee has no employee_no'
      USING ERRCODE = '22023';
  END IF;

  v_target_vcode := v_app.vacancy_vcode;

  SELECT * INTO v_vac
    FROM public.vacancies
   WHERE vcode = v_target_vcode
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'active vacancy not found for vcode %', v_target_vcode
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_vac.has_pending_closure, false) = true THEN
    RAISE EXCEPTION
      'onboarding blocked: vacancy % has a pending closure request',
      v_target_vcode USING ERRCODE = '55000';
  END IF;

  IF NOT public.i_have_full_access()
     AND NOT (v_vac.account = ANY(public.get_my_allowed_accounts())) THEN
    RAISE EXCEPTION 'forbidden: vacancy is outside caller scope'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.employee_store_allocations
     WHERE plantilla_id = v_linked_plt.id
       AND vcode = v_target_vcode
       AND is_active = true
       AND effective_end IS NULL
  ) THEN
    RAISE EXCEPTION
      'employee % already has an active store allocation for VCODE %',
      v_linked_plt.employee_no, v_target_vcode
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.employee_store_allocations (
    plantilla_id,
    employee_no,
    store_id,
    store_name,
    vcode,
    account_id,
    group_id,
    filled_hc,
    active_store_count,
    effective_start,
    effective_end,
    is_active,
    created_by,
    created_at
  )
  VALUES (
    v_linked_plt.id,
    v_linked_plt.employee_no,
    v_vac.store_id,
    v_vac.store_name,
    v_target_vcode,
    v_vac.account_id,
    v_vac.chain_id,
    1.0,
    1,
    CURRENT_DATE,
    NULL,
    true,
    v_profile_id,
    NOW()
  )
  RETURNING id INTO v_new_esa_id;

  PERFORM public.fn_sync_slot_to_occupied(
    p_vcode        => v_target_vcode,
    p_hr_emploc_id => NULL,
    p_plantilla_id => v_linked_plt.id,
    p_performed_by => v_profile_id,
    p_source_fn    => 'fn_approve_plantilla_additional_store'
  );

  IF v_vac.id IS NOT NULL THEN
    UPDATE public.vacancies
       SET status     = 'Filled',
           updated_at = NOW(),
           updated_by = v_profile_id
     WHERE id = v_vac.id
       AND NOT EXISTS (
         SELECT 1
           FROM public.plantilla_slots ps
          WHERE ps.legacy_vcode = v_target_vcode
            AND COALESCE(ps.is_roving, false) = false
            AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
       );
  END IF;

  UPDATE public.vacancies
     SET status     = 'Filled',
         updated_at = NOW(),
         updated_by = v_profile_id
   WHERE vcode = v_target_vcode
     AND status IN ('Open', 'For Sourcing')
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
     AND NOT EXISTS (
       SELECT 1
         FROM public.plantilla_slots ps
        WHERE ps.legacy_vcode = v_target_vcode
          AND COALESCE(ps.is_roving, false) = false
          AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
     );

  UPDATE public.applicants
     SET status     = 'Confirmed Onboard',
         hired_date = COALESCE(hired_date, CURRENT_DATE),
         updated_at = NOW(),
         updated_by = v_profile_id
   WHERE id = p_applicant_id;

  INSERT INTO public.audit_logs (
    actor_id, module, action, record_id, new_data, role
  ) VALUES (
    v_profile_id,
    'Plantilla',
    'INSERT',
    v_new_esa_id,
    jsonb_build_object(
      'business_action', 'PLANTILLA_ADDITIONAL_STORE_ESA',
      'employee_no', v_linked_plt.employee_no,
      'target_vcode', v_target_vcode,
      'source_plantilla_id', v_app.linked_plantilla_id,
      'applicant_id', p_applicant_id,
      'new_esa_id', v_new_esa_id,
      'target_store_id', v_vac.store_id,
      'target_store_name', v_vac.store_name,
      'label', 'Additional store assignment created'
    ),
    v_role
  );

  RETURN jsonb_build_object(
    'ok', true,
    'applicant_id', p_applicant_id,
    'applicant_status', 'Confirmed Onboard',
    'new_esa_id', v_new_esa_id,
    'source_plantilla_id', v_linked_plt.id,
    'vcode', v_target_vcode,
    'employee_no', v_linked_plt.employee_no,
    'idempotent', false
  );
END;
$$;

COMMENT ON FUNCTION public.fn_approve_plantilla_additional_store(uuid) IS
  'Approves plantilla-sourced applicants for additional-store ESA assignment. OHM2026_0090 keeps multi-slot VCODEs Open until all active non-roving slots are occupied.';

GRANT EXECUTE ON FUNCTION public.fn_approve_plantilla_additional_store(uuid)
TO authenticated;

REVOKE EXECUTE ON FUNCTION public.fn_approve_plantilla_additional_store(uuid)
FROM anon;

-- --------------------------------------------------------------------------
-- Backstop Plantilla active-insert trigger with the same slot-aware guard.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tg_close_vacancy_on_plantilla_active_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status <> 'Active' OR NEW.vcode IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.vacancies
     SET status     = 'Filled',
         updated_at = NOW()
   WHERE vcode = NEW.vcode
     AND status IN ('Open', 'For Sourcing')
     AND COALESCE(is_archived, false) = false
     AND deleted_at IS NULL
     AND NOT EXISTS (
       SELECT 1
         FROM public.plantilla_slots ps
        WHERE ps.legacy_vcode = NEW.vcode
          AND COALESCE(ps.is_roving, false) = false
          AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
     );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tg_close_vacancy_on_plantilla_active_insert() IS
  'VCODE close backstop. OHM2026_0090 only closes when no active non-roving slots remain open/pipeline/hr_processing.';

-- --------------------------------------------------------------------------
-- Repair existing Filled vacancies that still have active open demand.
-- --------------------------------------------------------------------------
UPDATE public.vacancies v
   SET status      = 'Open',
       is_archived = false,
       updated_at  = NOW()
 WHERE v.status = 'Filled'
   AND v.deleted_at IS NULL
   AND EXISTS (
     SELECT 1
       FROM public.plantilla_slots ps
      WHERE ps.legacy_vcode = v.vcode
        AND COALESCE(ps.is_roving, false) = false
        AND ps.slot_status IN ('open', 'pipeline', 'hr_processing')
   );

-- Validation:
--   SELECT legacy_vcode, slot_status
--   FROM public.plantilla_slots
--   WHERE legacy_vcode = 'VCOG2_0007';
--
--   SELECT vcode, status
--   FROM public.vacancies
--   WHERE vcode = 'VCOG2_0007';
--
-- Expected for VCOG2_0007 after apply:
--   occupied/open/open slots are preserved, and vacancy status is Open.
--
-- Contact checks:
--   INSERT/UPDATE applicant contact '09171234567' stores '09171234567'.
--   INSERT/UPDATE applicant contact '9171234567' stores '09171234567'.
--   Blank contact stores NULL.
--   Invalid non-empty values raise 22023.
