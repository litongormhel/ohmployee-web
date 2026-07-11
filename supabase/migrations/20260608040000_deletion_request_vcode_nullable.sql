-- OHM2026_0090 BUG 1 — Coverage HR Emploc deletion request vcode constraint
-- fn_request_emploc_deletion inserts v_emp.vcode which is NULL for Coverage
-- records (no linked vacancy). The NOT NULL constraint causes a hard failure.
-- Fix: drop NOT NULL. The approve RPC uses applicant_id FK as primary lookup;
-- vcode fallback only fires when applicant_id IS NULL (legacy stationary path).

ALTER TABLE public.hr_emploc_deletion_requests
  ALTER COLUMN vcode DROP NOT NULL;

-- Prevent NULL notification body when vcode is NULL (Coverage records).
-- Original: '(' || NEW.vcode || ')' → NULL if vcode IS NULL.
CREATE OR REPLACE FUNCTION public.handle_emploc_deletion_requested()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_account RECORD;
  v_encoder RECORD;
BEGIN
  SELECT a.id, a.account_name, a.group_id
  INTO v_account
  FROM public.hr_emploc he
  LEFT JOIN public.accounts a ON a.id = he.account_id OR a.account_name = he.account
  WHERE he.id = NEW.hr_emploc_id
  LIMIT 1;

  IF v_account.group_id IS NULL THEN
    SELECT a.id, a.account_name, a.group_id
    INTO v_account
    FROM public.accounts a
    WHERE a.account_name = NEW.account
    LIMIT 1;
  END IF;

  SELECT up.auth_user_id, up.role
  INTO v_encoder
  FROM public.users_profile up
  WHERE up.role = 'Encoder'
    AND up.is_active = true
    AND up.auth_user_id IS NOT NULL
    AND up.group_id = v_account.group_id
  LIMIT 1;

  IF v_encoder.auth_user_id IS NOT NULL THEN
    PERFORM public.notify_user(
      v_encoder.auth_user_id,
      'Encoder',
      'Deletion Request — ' || COALESCE(v_account.account_name, NEW.account),
      NEW.requested_by || ' has requested to delete HR Emploc record for ' || NEW.applicant_name || ' (' || COALESCE(NEW.vcode, 'Coverage') || '). Please review.',
      'submission',
      'hr_emploc_deletion',
      'hr_emploc_deletion',
      NEW.id::TEXT,
      FORMAT('/hr-emploc/deletion-requests/%s', NEW.id),
      NULL
    );
  END IF;

  RETURN NEW;
END;
$function$;
