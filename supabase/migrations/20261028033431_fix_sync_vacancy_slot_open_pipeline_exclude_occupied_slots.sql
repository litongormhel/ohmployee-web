-- Migration: 20261028033431_fix_sync_vacancy_slot_open_pipeline_exclude_occupied_slots.sql
-- Description: Exclude hr_processing, occupied, and filled slots from both claim and release loops in fn_sync_vacancy_slot_open_pipeline

CREATE OR REPLACE FUNCTION public.fn_sync_vacancy_slot_open_pipeline(
  p_vcode text,
  p_performed_by uuid DEFAULT NULL::uuid,
  p_source_fn text DEFAULT 'unknown'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_active_cnt  bigint;
  v_target      text;
  v_result      jsonb;
  r_slot        record;
BEGIN
  IF p_vcode IS NULL OR btrim(p_vcode) = '' THEN
    RAISE NOTICE
      'fn_sync_vacancy_slot_open_pipeline: skipped — p_vcode is null/empty (source=%)',
      COALESCE(p_source_fn, 'unknown');
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_active_cnt
  FROM public.applicants
  WHERE vacancy_vcode = p_vcode
    AND COALESCE(is_archived, false) = false
    AND replace(replace(lower(btrim(COALESCE(status, ''))), ' ', '_'), '-', '_') NOT IN (
      'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew', 'confirmed_onboard'
    );

  v_target := CASE WHEN v_active_cnt > 0 THEN 'pipeline' ELSE 'open' END;

  IF v_target = 'open' THEN
    -- Transition all unassigned non-closed pipeline slots for this vcode back to 'open'
    FOR r_slot IN
      SELECT id, slot_status
      FROM public.plantilla_slots
      WHERE legacy_vcode = p_vcode
        AND is_roving = false
        AND slot_status = 'pipeline'
        AND slot_status NOT IN ('hr_processing', 'occupied', 'filled')
        AND current_occupant_plantilla_id IS NULL
        AND closed_at IS NULL
    LOOP
      PERFORM public.fn_set_slot_status(
        p_slot_id               => r_slot.id,
        p_new_status            => 'open',
        p_reason_code           => NULL,
        p_performed_by          => p_performed_by,
        p_remarks               => format('Phase 6.1 / %s / VCODE=%s / active_applicants=0 / release to open', COALESCE(p_source_fn, 'unknown'), p_vcode),
        p_occupant_plantilla_id => NULL
      );
    END LOOP;

    RETURN jsonb_build_object(
      'status', 'ok',
      'vcode', p_vcode,
      'target', 'open',
      'active_applicants', 0
    );
  ELSE
    FOR r_slot IN
      SELECT id, slot_status
      FROM public.plantilla_slots
      WHERE legacy_vcode = p_vcode
        AND is_roving = false
        AND slot_status = 'open'
        AND slot_status NOT IN ('hr_processing', 'occupied', 'filled')
        AND closed_at IS NULL
      ORDER BY slot_ordinal ASC, created_at ASC, id ASC
      LIMIT 1
    LOOP
      SELECT public.fn_set_slot_status(
        p_slot_id               => r_slot.id,
        p_new_status            => 'pipeline',
        p_reason_code           => NULL,
        p_performed_by          => p_performed_by,
        p_remarks               => format('Phase 6.1 / %s / VCODE=%s / active_applicants=%s', COALESCE(p_source_fn, 'unknown'), p_vcode, v_active_cnt),
        p_occupant_plantilla_id => NULL
      ) INTO v_result;
      RETURN v_result;
    END LOOP;

    RETURN jsonb_build_object(
      'status', 'no_op',
      'vcode', p_vcode,
      'target', 'pipeline',
      'active_applicants', v_active_cnt
    );
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'fn_sync_vacancy_slot_open_pipeline: error for VCODE=% source=% — % (sqlstate=%)',
    p_vcode, COALESCE(p_source_fn, 'unknown'), SQLERRM, SQLSTATE;
  RETURN NULL;
END;
$function$;
