it-- OHMployee-v2.18.8-reapply
-- reopen_pool_slot_review — vacancy cascade
--
-- Extends reopen_pool_slot_review so that when a pool slot is reopened,
-- the directly linked pool vacancy (via workforce_pool_slots.vacancy_id)
-- is also restored to Open sourcing state when it is currently Filled.
--
-- Preserves VCODE lineage. Prevents duplicate active/open slot conflicts.
-- No hard deletes.

CREATE OR REPLACE FUNCTION public.reopen_pool_slot_review(
  p_review_id uuid,
  p_notes     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_review              public.workforce_slot_reviews%rowtype;
  v_slot                public.workforce_pool_slots%rowtype;
  v_actor               uuid    := public.get_my_profile_id();
  v_actor_name          text    := public.get_my_full_name();
  v_duplicate_open_count integer := 0;
  v_vacancy_reopened    boolean := false;
  v_row_count           integer := 0;
BEGIN
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team action required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_review
  FROM public.workforce_slot_reviews
  WHERE id = p_review_id
  FOR UPDATE;

  IF v_review.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  IF v_review.status <> 'Pending' THEN
    RETURN jsonb_build_object(
      'ok',     false,
      'error',  'invalid_status',
      'current', v_review.status
    );
  END IF;

  SELECT * INTO v_slot
  FROM public.workforce_pool_slots
  WHERE vcode = v_review.vcode
    AND deleted_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_slot.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_duplicate_open_count
    FROM public.workforce_pool_slots s
    WHERE s.vcode = v_review.vcode
      AND s.deleted_at IS NULL
      AND s.id <> v_slot.id
      AND (
        s.is_active IS TRUE
        OR LOWER(COALESCE(s.status, '')) IN ('active', 'open', 'available')
      );

    IF v_duplicate_open_count > 0 THEN
      RETURN jsonb_build_object(
        'ok',    false,
        'error', 'duplicate_open_slot',
        'vcode', v_review.vcode
      );
    END IF;

    UPDATE public.workforce_pool_slots
    SET status     = 'active',
        is_active  = true,
        updated_at = now(),
        updated_by = v_actor
    WHERE id = v_slot.id;

    -- Cascade: restore the directly-linked pool vacancy to Open if Filled.
    -- Uses vacancy_id FK for precision; preserves VCODE lineage.
    IF v_slot.vacancy_id IS NOT NULL THEN
      UPDATE public.vacancies
      SET status      = 'Open',
          is_archived = false,
          updated_at  = now(),
          updated_by  = v_actor
      WHERE id         = v_slot.vacancy_id
        AND status     = 'Filled'
        AND deleted_at IS NULL;

      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_vacancy_reopened := v_row_count > 0;
    END IF;
  ELSE
    RETURN jsonb_build_object(
      'ok',    false,
      'error', 'missing_slot',
      'vcode', v_review.vcode
    );
  END IF;

  UPDATE public.workforce_slot_reviews
  SET status      = 'Resolved',
      action      = 'reopen',
      decided_at  = now(),
      decided_by  = v_actor,
      review_notes = CONCAT_WS(
        E'\n',
        NULLIF(review_notes, ''),
        NULLIF(BTRIM(COALESCE(p_notes, '')), '')
      ),
      updated_at  = now()
  WHERE id = v_review.id;

  PERFORM public.log_audit_event(
    'workforce_slot_reviews',
    'UPDATE',
    v_review.id,
    to_jsonb(v_review),
    to_jsonb((SELECT r FROM public.workforce_slot_reviews r WHERE r.id = v_review.id))
  );

  RETURN jsonb_build_object(
    'ok',               true,
    'review_id',        v_review.id,
    'vcode',            v_review.vcode,
    'action',           'reopen',
    'slot_id',          v_slot.id,
    'vacancy_reopened', v_vacancy_reopened
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reopen_pool_slot_review(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reopen_pool_slot_review(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reopen_pool_slot_review(uuid, text) TO service_role;
