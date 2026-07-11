-- ============================================================
-- OHMployee - Cross-Account Active Applicant Duplicate Guard
-- Prompt ID : OHM2026_1149
-- Date      : 2026-05-29
-- Scope     : Applicant data-integrity enforcement ONLY
-- ============================================================
-- Adds the missing data-integrity rule:
--
--   The SAME applicant (LAST_NAME + FIRST_NAME + CONTACT_NUMBER,
--   middle name ignored) may NOT hold an active recruitment record
--   under more than one account at the same time.
--
-- Preserved unchanged:
--   * uq_applicants_one_active_per_vcode (1 active VCODE = 1 active
--     applicant) is NOT touched.
--   * Active-status logic stays centralized in the existing function
--     public.fn_is_active_vacancy_applicant_status(text). It is NOT
--     redefined here.
--   * Vacancy lifecycle / approval / rollback / Import workflow,
--     VCODE generation, applicant status transitions, HR Emploc and
--     Plantilla flows are NOT touched.
--
-- Allowed (NOT blocked):
--   * Same Last+First+Contact in the SAME account across different
--     VCODEs.
--   * Same Last+First+Contact in a different account when the other
--     record is terminal / archived / non-active.
--
-- Blocked:
--   * Same Last+First+Contact active under a DIFFERENT account.
--
-- Account resolution path (per spec):
--   applicants.vacancy_vcode -> vacancies.vcode -> vacancies.account_id
--
-- Identity completeness:
--   Identity requires LAST_NAME, FIRST_NAME and CONTACT_NUMBER.
--   When the contact number is NULL/blank an identity cannot be
--   formed, so the guard is skipped (consistent with the existing
--   nullable contact_number column — no new NOT NULL behavior is
--   introduced). The account_id resolution being NULL also skips the
--   guard (cannot attribute the record to an account).
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_assert_applicant_no_cross_account_active()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id   uuid;
  v_last         text;
  v_first        text;
  v_contact      text;
  v_conflict_acc text;
BEGIN
  -- Only enforce when the resulting row is an ACTIVE, non-archived applicant.
  IF COALESCE(NEW.is_archived, false) = true
     OR NOT public.fn_is_active_vacancy_applicant_status(NEW.status) THEN
    RETURN NEW;
  END IF;

  -- Normalise identity components.
  v_last    := lower(btrim(COALESCE(NEW.last_name, '')));
  v_first   := lower(btrim(COALESCE(NEW.first_name, '')));
  v_contact := btrim(COALESCE(NEW.contact_number, ''));

  -- Incomplete identity -> cannot reliably match a person -> skip.
  IF v_last = '' OR v_first = '' OR v_contact = '' THEN
    RETURN NEW;
  END IF;

  -- Resolve this applicant's account via the vacancy.
  SELECT v.account_id
    INTO v_account_id
  FROM public.vacancies v
  WHERE v.vcode = NEW.vacancy_vcode
    AND v.deleted_at IS NULL
  LIMIT 1;

  -- No resolvable account -> cannot compare across accounts -> skip.
  IF v_account_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Look for an active applicant with the same identity bound to a
  -- DIFFERENT account.
  SELECT v2.account
    INTO v_conflict_acc
  FROM public.applicants a2
  JOIN public.vacancies v2 ON v2.vcode = a2.vacancy_vcode
  WHERE a2.id <> NEW.id
    AND v2.deleted_at IS NULL
    AND v2.account_id IS NOT NULL
    AND v2.account_id IS DISTINCT FROM v_account_id
    AND COALESCE(a2.is_archived, false) = false
    AND public.fn_is_active_vacancy_applicant_status(a2.status)
    AND lower(btrim(COALESCE(a2.last_name, '')))  = v_last
    AND lower(btrim(COALESCE(a2.first_name, ''))) = v_first
    AND btrim(COALESCE(a2.contact_number, ''))    = v_contact
  ORDER BY a2.created_at
  LIMIT 1;

  IF v_conflict_acc IS NOT NULL THEN
    RAISE EXCEPTION
      'Applicant already has an active application under another account.'
      USING
        DETAIL  = format('Conflicting account: %s', v_conflict_acc),
        ERRCODE = '23505';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_assert_applicant_no_cross_account_active() IS
  'OHM2026_1149 - Blocks the same applicant (last+first+contact, middle ignored) '
  'from holding active recruitment records under more than one account. '
  'Active status logic delegated to fn_is_active_vacancy_applicant_status. '
  'Does not affect uq_applicants_one_active_per_vcode or any Vacancy workflow.';

-- Apply to inserts and to updates that can flip identity / account / active state.
DROP TRIGGER IF EXISTS trg_assert_applicant_no_cross_account_active ON public.applicants;

CREATE TRIGGER trg_assert_applicant_no_cross_account_active
  BEFORE INSERT OR UPDATE OF
    status, is_archived, last_name, first_name, contact_number, vacancy_vcode
  ON public.applicants
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_assert_applicant_no_cross_account_active();

-- ============================================================
-- Validation SQL (run manually after apply)
-- ============================================================
-- Existing cross-account active duplicates report (resolve before
-- relying on the guard for new writes — the guard does NOT retro-clean):
--
-- SELECT lower(btrim(a.last_name))  AS last_name,
--        lower(btrim(a.first_name)) AS first_name,
--        btrim(a.contact_number)    AS contact_number,
--        array_agg(DISTINCT v.account) AS accounts,
--        count(DISTINCT v.account_id)  AS distinct_accounts
-- FROM public.applicants a
-- JOIN public.vacancies v ON v.vcode = a.vacancy_vcode
-- WHERE COALESCE(a.is_archived,false) = false
--   AND public.fn_is_active_vacancy_applicant_status(a.status)
--   AND v.deleted_at IS NULL
--   AND v.account_id IS NOT NULL
--   AND btrim(COALESCE(a.contact_number,'')) <> ''
-- GROUP BY 1,2,3
-- HAVING count(DISTINCT v.account_id) > 1;
--
-- Expected behavior:
--   * Active applicant in SAME account + new VCODE  -> allowed.
--   * Active applicant in a DIFFERENT account       -> blocked (23505).
--   * Rejected/archived applicant in another account-> allowed.
--   * Second active applicant on SAME VCODE          -> still blocked by
--     uq_applicants_one_active_per_vcode (unchanged).
-- ============================================================
