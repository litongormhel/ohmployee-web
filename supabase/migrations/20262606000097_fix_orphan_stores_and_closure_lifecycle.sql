-- Migration: 20262606000097_fix_orphan_stores_and_closure_lifecycle.sql
-- Description: 
-- 1. Clean up orphan stores whose vacancies have been closed due to outlet cessation or all records archived
-- 2. Close dangling open slots in public.plantilla_slots for closed stores
-- 3. Correct Kimi Antonelli's vcode to TEST009 matching assigned store SUPER 9
-- 4. Update handle_closure_approval trigger to automatically deactivate stores and close slots upon closure approval

BEGIN;

-- 1. Deactivate & archive stores whose vacancies were approved for closure or are already archived/closed
UPDATE public.stores
SET is_active = false,
    is_archived = true,
    status = 'archived',
    updated_at = NOW()
WHERE vcode IN ('TEST007', 'TEST010', 'BK-G1-0053', 'ACT-G5-001', 'ACT-G5-003', 'ACT-G5-005', 'ACT-G5-007', 'ACT-G5-009', 'VCSSG2_1600')
   OR id IN (
     'e4d0507f-03ee-43b8-9144-9ea62e95ae1e', -- SUPER 7
     '521227be-f60e-4705-bf7a-24d66b026de1', -- SUPER 10
     '23c0122e-99f5-461d-b28b-1015fe24158c'  -- S8 BANGAE
   );

-- 2. Close dangling open slots in public.plantilla_slots for closed/archived vcodes
UPDATE public.plantilla_slots
SET slot_status = 'closed',
    closure_reason_code = 'STORE_CLOSED',
    updated_at = NOW()
WHERE legacy_vcode IN ('TEST007', 'TEST010', 'BK-G1-0053', 'ACT-G5-001', 'ACT-G5-003', 'ACT-G5-005', 'ACT-G5-007', 'ACT-G5-009', 'VCSSG2_1600')
  AND slot_status IN ('open', 'pipeline');

-- 3. Correct Kimi Antonelli's vcode to match SUPER 9 (TEST009)
UPDATE public.plantilla
SET vcode = 'TEST009',
    updated_at = NOW()
WHERE employee_no = '2026-136256'
  AND store_id = '1307caef-2f7b-4734-ac44-4032b853864a';

-- 4. Enhance handle_closure_approval trigger function to prevent future orphan stores & dangling slots
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

    -- 3. Automatically close any remaining open/pipeline slots in plantilla_slots
    UPDATE public.plantilla_slots
    SET slot_status = 'closed',
        closure_reason_code = CASE
          WHEN LOWER(COALESCE(NEW.reason, '')) LIKE '%store closed%' 
            OR LOWER(COALESCE(NEW.reason, '')) LIKE '%outlet ceased%' 
            OR LOWER(COALESCE(NEW.reason, '')) LIKE '%ceased operations%' THEN 'STORE_CLOSED'
          ELSE 'VACANCY_CLOSED'
        END,
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

COMMIT;
