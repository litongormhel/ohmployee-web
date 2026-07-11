-- ============================================================
-- ohm#rci006: Auto-Close Reliever/Commando Coverage When Covered Vacancy Slot Is Filled
-- Migration: 20261224000000_auto_close_coverage_on_slot_occupied.sql
-- ============================================================
-- Sections:
--   §1  Add covered_vacancy_id and end_reason to workforce_assignments
--   §2  Define tg_auto_close_coverage_on_slot_occupied trigger function
--   §3  Attach trigger to plantilla_slots table
-- ============================================================

-- ============================================================
-- §1  Add covered_vacancy_id and end_reason to workforce_assignments
-- ============================================================

ALTER TABLE public.workforce_assignments
  ADD COLUMN IF NOT EXISTS end_reason text,
  ADD COLUMN IF NOT EXISTS covered_vacancy_id uuid
    REFERENCES public.vacancies(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.workforce_assignments.end_reason IS
  'Reason why the workforce pool deployment ended (e.g. Position Filled / Applicant Onboarded).';

COMMENT ON COLUMN public.workforce_assignments.covered_vacancy_id IS
  'Reference to the vacancy this deployment covered when it is closed automatically due to slot occupancy.';

CREATE INDEX IF NOT EXISTS idx_wa_covered_vacancy_id
  ON public.workforce_assignments (covered_vacancy_id)
  WHERE covered_vacancy_id IS NOT NULL;


-- ============================================================
-- §2  Define tg_auto_close_coverage_on_slot_occupied trigger function
-- ============================================================

CREATE OR REPLACE FUNCTION public.tg_auto_close_coverage_on_slot_occupied()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cov_row            record;
  v_wa_row             record;
  v_vac_row            record;
BEGIN
  -- Trigger executes only when slot transitions to 'occupied'
  IF NEW.slot_status = 'occupied' AND OLD.slot_status IS DISTINCT FROM 'occupied' THEN
    
    -- If store_id is null, there is nothing to stop
    IF NEW.store_id IS NOT NULL THEN
      
      -- A. Close ALL active vacancy coverages for this store
      FOR v_cov_row IN
        SELECT vc.*, v.vcode AS vac_vcode
        FROM public.vacancy_coverage vc
        JOIN public.vacancies v ON (vc.vacancy_id = v.id OR vc.vcode = v.vcode)
        WHERE v.store_id = NEW.store_id
          AND vc.status = 'Active'::public.vacancy_coverage_status
          AND vc.archived_at IS NULL
      LOOP
        UPDATE public.vacancy_coverage
        SET status = 'Ended'::public.vacancy_coverage_status,
            covered_until = CURRENT_DATE,
            updated_at = NOW(),
            updated_by = auth.uid()
        WHERE id = v_cov_row.id;

        -- Write audit log for coverage closure
        PERFORM public.log_audit_event(
          'vacancy_coverage',
          'UPDATE',
          v_cov_row.id,
          to_jsonb(v_cov_row),
          jsonb_build_object(
            'status', 'Ended',
            'covered_until', CURRENT_DATE,
            'notes', 'Coverage Auto Closed. Reason: Position Filled / Applicant Onboarded. Triggered By: System. Affected Vacancy: ' || v_cov_row.vac_vcode
          )
        );
      END LOOP;

      -- B. Close ALL active workforce assignments for this store
      -- Resolve the primary vacancy matching the slot's position first
      SELECT id, vcode INTO v_vac_row
      FROM public.vacancies
      WHERE store_id = NEW.store_id
        AND lower(trim(position)) = lower(trim(NEW.position))
        AND deleted_at IS NULL
        AND is_archived = false
      LIMIT 1;

      -- Fallback: match by store only
      IF v_vac_row.id IS NULL THEN
        SELECT id, vcode INTO v_vac_row
        FROM public.vacancies
        WHERE store_id = NEW.store_id
          AND deleted_at IS NULL
          AND is_archived = false
        LIMIT 1;
      END IF;

      FOR v_wa_row IN
        SELECT 
          wa.id, 
          wa.employee_id, 
          wa.deployment_type, 
          wa.start_date, 
          wa.end_date, 
          wa.assigned_store_id, 
          wa.assigned_account_id, 
          pt.employee_no,
          pt.employee_name
        FROM public.workforce_assignments wa
        JOIN public.plantilla pt ON pt.id = wa.employee_id
        WHERE wa.assigned_store_id = NEW.store_id
          AND wa.status = ANY (ARRAY['Approved', 'Deployed', 'Active', 'In Progress'])
      LOOP
        UPDATE public.workforce_assignments
        SET status = 'Completed',
            completed_at = NOW(),
            end_reason = 'Position Filled / Applicant Onboarded',
            covered_vacancy_id = v_vac_row.id,
            notes = CONCAT_WS(E'\n', NULLIF(notes, ''), 'Auto-closed: covered vacancy store was filled')
        WHERE id = v_wa_row.id;

        -- Write audit log for assignment update
        PERFORM public.log_audit_event(
          'workforce_assignments',
          'UPDATE',
          v_wa_row.id,
          jsonb_build_object('status', 'Active'),
          jsonb_build_object(
            'status', 'Completed',
            'end_reason', 'Position Filled / Applicant Onboarded',
            'covered_vacancy_id', v_vac_row.id,
            'notes', 'Auto-closed: covered vacancy store was filled'
          )
        );

        -- Write employee activity log
        INSERT INTO public.employee_activity_log (
          emploc_no,
          vcode,
          activity_type,
          description,
          performed_by,
          metadata
        ) VALUES (
          v_wa_row.employee_no,
          COALESCE(v_vac_row.vcode, '—'),
          'Coverage Auto Closed',
          format(
            E'Coverage Auto Closed\nReason:\nPosition Filled / Applicant Onboarded\n\nTriggered By:\nSystem\n\nAffected Vacancy:\n%s\n\nAffected Workforce Assignment:\n%s',
            COALESCE(v_vac_row.vcode, '—'),
            v_wa_row.id::text
          ),
          'System',
          jsonb_build_object(
            'affected_vacancy_vcode', COALESCE(v_vac_row.vcode, '—'),
            'affected_workforce_assignment_id', v_wa_row.id,
            'employee_name', v_wa_row.employee_name,
            'deployment_type', v_wa_row.deployment_type,
            'store_id', v_wa_row.assigned_store_id,
            'account_id', v_wa_row.assigned_account_id,
            'position_covered', NEW.position,
            'start_date', v_wa_row.start_date,
            'end_date', v_wa_row.end_date
          )
        );
      END LOOP;

    END IF;
  END IF;

  RETURN NEW;
END;
$$;


-- ============================================================
-- §3  Attach trigger to plantilla_slots table
-- ============================================================

DROP TRIGGER IF EXISTS trg_auto_close_coverage_on_slot_occupied ON public.plantilla_slots;

CREATE TRIGGER trg_auto_close_coverage_on_slot_occupied
  AFTER UPDATE OF slot_status ON public.plantilla_slots
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_auto_close_coverage_on_slot_occupied();
