-- ==============================================================================
-- Migration: 20262606000179_seed_vacancy_closed_slot_reason_and_fix_closure_approval.sql
-- Description:
--   1. Seed missing reason code 'VACANCY_CLOSED' into public.slot_reason_codes.
--      Root cause of IMG_4427.jpg: Approving vacancy closure executes
--      handle_closure_approval(), which updates plantilla_slots.closure_reason_code
--      to 'VACANCY_CLOSED' for non-store-closure reasons (e.g. 'Operational Restructuring').
--      Because 'VACANCY_CLOSED' was not in public.slot_reason_codes, it violated
--      foreign key constraint plantilla_slots_closure_reason_fkey (SQLSTATE 23503).
--   2. Enhance public.handle_closure_approval():
--      - Explicitly set closed_at = NOW() and closed_by in plantilla_slots on closure.
--      - Support 'HC_REDUCTION' when closure reason mentions headcount reduction.
-- ==============================================================================

-- 1. Seed missing reason code into master lookup table
INSERT INTO public.slot_reason_codes (code, label, description, is_active, sort_order)
VALUES
  (
    'VACANCY_CLOSED',
    'Vacancy Closed',
    'Slot closed and decommissioned due to approved vacancy closure request.',
    true,
    92
  )
ON CONFLICT (code) DO UPDATE
SET label = EXCLUDED.label,
    description = EXCLUDED.description,
    is_active = true;

-- 2. Surgical update of handle_closure_approval trigger function
CREATE OR REPLACE FUNCTION public.handle_closure_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_vacancy RECORD;
  v_requestor RECORD;
  v_type TEXT;
  v_closed_by uuid;
  v_closure_code text;
BEGIN
  IF NEW.status = 'Approved' AND OLD.status = 'Pending' THEN
    PERFORM public.fn_assert_vacancy_closeable(NEW.vacancy_vcode);

    -- 1. Close and archive the vacancy
    UPDATE public.vacancies
    SET status = 'Closed',
        is_archived = true,
        archived_at = NOW(),
        archived_by = NEW.reviewed_by,
        has_pending_closure = false,
        closure_request_status = 'Approved',
        updated_at = NOW()
    WHERE vcode = NEW.vacancy_vcode;

    -- 2. Deactivate & archive store if closure reason indicates store/outlet closure
    IF LOWER(COALESCE(NEW.reason, '')) LIKE '%store closed%' 
       OR LOWER(COALESCE(NEW.reason, '')) LIKE '%outlet ceased%' 
       OR LOWER(COALESCE(NEW.reason, '')) LIKE '%ceased operations%' THEN
      UPDATE public.stores
      SET is_active = false,
          is_archived = true,
          status = 'archived',
          updated_at = NOW()
      WHERE id = (SELECT store_id FROM public.vacancies WHERE vcode = NEW.vacancy_vcode LIMIT 1)
         OR vcode = NEW.vacancy_vcode;
    END IF;

    -- Resolve closed_by profile id if possible
    SELECT id INTO v_closed_by
    FROM public.users_profile
    WHERE auth_user_id = auth.uid()
       OR full_name = NEW.reviewed_by
    LIMIT 1;

    -- Determine closure reason code
    v_closure_code := CASE
      WHEN LOWER(COALESCE(NEW.reason, '')) LIKE '%store closed%' 
        OR LOWER(COALESCE(NEW.reason, '')) LIKE '%outlet ceased%' 
        OR LOWER(COALESCE(NEW.reason, '')) LIKE '%ceased operations%' THEN 'STORE_CLOSED'
      WHEN LOWER(COALESCE(NEW.reason, '')) LIKE '%headcount%'
        OR LOWER(COALESCE(NEW.reason, '')) LIKE '%reduction%' THEN 'HC_REDUCTION'
      ELSE 'VACANCY_CLOSED'
    END;

    -- 3. Automatically close any remaining open/pipeline slots in plantilla_slots
    UPDATE public.plantilla_slots
    SET slot_status = 'closed',
        closed_at = NOW(),
        closed_by = COALESCE(v_closed_by, closed_by),
        closure_reason_code = v_closure_code,
        updated_at = NOW()
    WHERE legacy_vcode = NEW.vacancy_vcode
      AND slot_status IN ('open', 'pipeline');
  END IF;

  IF NEW.status = 'Rejected' AND OLD.status = 'Pending' THEN
    UPDATE public.vacancies
    SET has_pending_closure = false,
        closure_request_status = 'Rejected',
        updated_at = NOW()
    WHERE vcode = NEW.vacancy_vcode;
  END IF;

  IF NEW.status IN ('Approved', 'Rejected') AND OLD.status IS DISTINCT FROM NEW.status THEN
    SELECT v.id AS vacancy_id,
           COALESCE(a.account_name, v.account) AS account_name
    INTO v_vacancy
    FROM public.vacancies v
    LEFT JOIN public.accounts a ON a.id = v.account_id
    WHERE v.vcode = NEW.vacancy_vcode
    LIMIT 1;

    SELECT up.auth_user_id, up.role
    INTO v_requestor
    FROM public.users_profile up
    WHERE up.auth_user_id = NEW.requested_by_user_id
       OR up.id = NEW.requested_by_user_id
    LIMIT 1;

    v_type := CASE WHEN NEW.status = 'Approved' THEN 'approval' ELSE 'rejection' END;

    IF COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id) IS NOT NULL THEN
      PERFORM public.notify_user(
        COALESCE(v_requestor.auth_user_id, NEW.requested_by_user_id),
        COALESCE(v_requestor.role, 'Ops'),
        CASE WHEN NEW.status = 'Approved' THEN 'Vacancy Closure Approved' ELSE 'Vacancy Closure Rejected' END,
        CASE WHEN NEW.status = 'Approved'
          THEN 'Your closure request for ' || NEW.vacancy_vcode || ' (' || COALESCE(v_vacancy.account_name, 'Account') || ') has been approved by ' || COALESCE(NEW.reviewed_by, NEW.encoder_by, 'Encoder') || '.'
          ELSE 'Your closure request for ' || NEW.vacancy_vcode || ' (' || COALESCE(v_vacancy.account_name, 'Account') || ') was rejected by ' || COALESCE(NEW.reviewed_by, NEW.encoder_by, 'Encoder') || '. Reason: ' || COALESCE(NEW.reviewer_remarks, NEW.details, NEW.reason, 'No reason provided') || '.'
        END,
        v_type,
        'vacancy_closure',
        'vacancy_closure',
        NEW.id::TEXT,
        FORMAT('/vacancies/%s/closure-request/%s', COALESCE(v_vacancy.vacancy_id::TEXT, NEW.vacancy_vcode), NEW.id),
        NULL
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
