-- OHMployee-v2.18.8-reapply
-- close_workforce_assignment(p_assignment_id, p_notes)
--
-- Allows Data Team (encoder), HA, and SA to close an active workforce pool
-- assignment and mark it Completed. Prevents lifecycle dead-ends for
-- deployed relievers.
--
-- Closeable statuses: Active | Approved | Pending
-- Sets:  status = 'Completed', completed_at = now()
-- Preserves: notes (appended), audit trail, no hard deletes.

CREATE OR REPLACE FUNCTION public.close_workforce_assignment(
  p_assignment_id uuid,
  p_notes         text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_assignment public.workforce_assignments%rowtype;
  v_actor      uuid := public.get_my_profile_id();
BEGIN
  -- Data Team (encoder role_level=30), HA and SA via i_have_full_access
  IF NOT (public.i_have_full_access() OR public.get_my_role_level() = 30) THEN
    RAISE EXCEPTION 'forbidden: Data Team action required'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_assignment
  FROM public.workforce_assignments
  WHERE id = p_assignment_id
  FOR UPDATE;

  IF v_assignment.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  IF v_assignment.status NOT IN ('Active', 'Approved', 'Pending') THEN
    RETURN jsonb_build_object(
      'ok',      false,
      'error',   'invalid_status',
      'current', v_assignment.status
    );
  END IF;

  UPDATE public.workforce_assignments
  SET status       = 'Completed',
      completed_at = now(),
      notes        = CONCAT_WS(
                       E'\n',
                       NULLIF(v_assignment.notes, ''),
                       NULLIF(BTRIM(COALESCE(p_notes, '')), '')
                     ),
      updated_at   = now(),
      updated_by   = v_actor::text
  WHERE id = p_assignment_id;

  PERFORM public.log_audit_event(
    'workforce_assignments',
    'UPDATE',
    p_assignment_id,
    to_jsonb(v_assignment),
    to_jsonb((SELECT a FROM public.workforce_assignments a WHERE a.id = p_assignment_id))
  );

  RETURN jsonb_build_object(
    'ok',            true,
    'assignment_id', p_assignment_id,
    'status',        'Completed'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.close_workforce_assignment(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_workforce_assignment(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_workforce_assignment(uuid, text) TO service_role;
