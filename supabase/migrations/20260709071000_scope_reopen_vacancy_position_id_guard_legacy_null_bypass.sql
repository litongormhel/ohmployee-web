-- ============================================================================
-- Scope position_id Guard in reopen_or_create_vacancy_for_plantilla(): hard-
-- block only post-import-fix records, bypass legacy null rows.
-- Migration: 20260709071000_scope_reopen_vacancy_position_id_guard_legacy_null_bypass.sql
-- Task: ohm#5qwm9btr (follow-up, discovered during required verification)
-- ============================================================================
-- DISCOVERED DURING VERIFICATION: the stationary path of
-- fn_plantilla_separation_to_vacancy() (fixed to bypass legacy-null rows in
-- 20260709070000, same task) does not itself perform the vacancy reopen --
-- it PERFORMs public.reopen_or_create_vacancy_for_plantilla(NEW.id, ...),
-- which re-fetches the plantilla row and runs its OWN, separate, identical
-- "Invalid position_id: <NULL>" hard guard. Live test on a known legacy
-- null-position_id row (69d5368a-8238-4179-b28d-766115cd0345, created
-- 2026-05-26, well before the import-path fix) confirmed
-- fn_plantilla_separation_to_vacancy()'s own guard correctly let the row
-- through post-20260709070000, but the separation still failed P0001 --
-- raised instead by this function, one call frame deeper. Scoping only the
-- caller's guard therefore did not fix the reported blocking behavior; this
-- callee guard must be scoped identically, using the same verified cutoff
-- and the same reasoning (see 20260709070000 for full detail):
--   - non-null position_id that doesn't resolve to a real positions row:
--     always blocks (real corruption, not part of the legacy exception).
--   - null position_id, plantilla.created_at >= 2026-07-09 06:03:55 UTC
--     (the exact wall-clock version of the approve_plantilla_import_batch
--     position_id-resolution fix, ohm#4dh6y1sc): still blocks -- a genuine
--     new regression.
--   - null position_id, plantilla.created_at < cutoff (or created_at IS
--     NULL, treated as "now" defensively): known legacy dirty data pending
--     future archive/cleanup -- skip the check, let the reopen/create
--     proceed. In this branch p.id will be NULL (positions has no NULL-id
--     row), so the subsequent SELECT position_name ... WHERE p.id =
--     v_plantilla.position_id / vacancies INSERT ... SELECT FROM positions p
--     naturally yields no position row on the create-path -- vacancy.position
--     and vacancy.position_id are simply left NULL/absent for a legacy row
--     with no resolvable position, matching the existing "POSITION is
--     optional" convention used elsewhere in this codebase. The reopen-
--     existing-vacancy path (the far more common case -- this fn's first
--     branch) is unaffected either way, since it writes position/position_id
--     straight from v_plantilla, not from a re-joined positions row.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reopen_or_create_vacancy_for_plantilla(p_plantilla_id uuid, p_effective_date date, p_vacancy_type text DEFAULT 'Backfill'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_plantilla public.plantilla;
  v_vacancy_id uuid;
BEGIN
  SELECT *
    INTO v_plantilla
  FROM public.plantilla
  WHERE id = p_plantilla_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plantilla not found: %', p_plantilla_id;
  END IF;

  -- ohm#5qwm9btr: position_id guard, now time-scoped (mirrors
  -- fn_plantilla_separation_to_vacancy() stationary-path guard, 20260709070000).
  IF v_plantilla.position_id IS NULL THEN
    IF COALESCE(v_plantilla.created_at, NOW()) >= TIMESTAMPTZ '2026-07-09 06:03:55+00' THEN
      RAISE EXCEPTION 'Invalid position_id: %', v_plantilla.position_id;
    END IF;
  ELSIF NOT EXISTS (
    SELECT 1 FROM public.positions WHERE id = v_plantilla.position_id
  ) THEN
    RAISE EXCEPTION 'Invalid position_id: %', v_plantilla.position_id;
  END IF;

  -- VCODE is the manpower slot identity.
  -- Reopen/reactivate existing slot first.
  SELECT id
    INTO v_vacancy_id
  FROM public.vacancies
  WHERE vcode = v_plantilla.vcode
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_vacancy_id IS NOT NULL THEN

    UPDATE public.vacancies
    SET
      status = 'Open',
      vacancy_type = COALESCE(p_vacancy_type, vacancy_type, 'Backfill'),
      vacant_date = p_effective_date,
      source_plantilla_id = v_plantilla.id,
      account = v_plantilla.account,
      account_id = v_plantilla.account_id,
      chain_id = v_plantilla.chain_id,
      store_id = v_plantilla.store_id,
      province_id = v_plantilla.province_id,
      position = v_plantilla.position,
      position_id = v_plantilla.position_id,
      area_name = COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      store_name = v_plantilla.store_name,
      is_archived = FALSE,
      archived_at = NULL,
      deleted_at = NULL,
      has_pending_closure = FALSE,
      updated_at = NOW(),
      updated_by = auth.uid()
    WHERE id = v_vacancy_id;

    RETURN v_vacancy_id;
  END IF;

  INSERT INTO public.vacancies (
    vcode,
    account,
    position,
    account_id,
    chain_id,
    store_id,
    province_id,
    area_name,
    position_id,
    vacant_date,
    vacancy_type,
    status,
    source_plantilla_id,
    store_name,
    created_at,
    updated_at,
    created_by,
    updated_by,
    required_headcount
  )
  SELECT
    v_plantilla.vcode,
    v_plantilla.account,
    p.position_name,
    v_plantilla.account_id,
    v_plantilla.chain_id,
    v_plantilla.store_id,
    v_plantilla.province_id,
    COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
    p.id,
    p_effective_date,
    COALESCE(p_vacancy_type, 'Backfill'),
    'Open',
    v_plantilla.id,
    v_plantilla.store_name,
    NOW(),
    NOW(),
    auth.uid(),
    auth.uid(),
    1
  FROM public.positions p
  WHERE p.id = v_plantilla.position_id
  RETURNING id INTO v_vacancy_id;

  IF v_vacancy_id IS NULL THEN
    -- ohm#5qwm9btr: legacy null-position_id row -- no positions row to join,
    -- so the SELECT ... FROM positions p above returned zero rows and the
    -- INSERT never ran. Insert the vacancy with position_id left NULL.
    -- vacancies.position is NOT NULL (20260708220000), so it cannot be left
    -- NULL like position_id -- fall back to the plantilla row's free-text
    -- position (may itself be blank for legacy rows with no position text
    -- at all) or an explicit placeholder, never a raw NULL.
    INSERT INTO public.vacancies (
      vcode,
      account,
      position,
      account_id,
      chain_id,
      store_id,
      province_id,
      area_name,
      position_id,
      vacant_date,
      vacancy_type,
      status,
      source_plantilla_id,
      store_name,
      created_at,
      updated_at,
      created_by,
      updated_by,
      required_headcount
    ) VALUES (
      v_plantilla.vcode,
      v_plantilla.account,
      COALESCE(NULLIF(TRIM(v_plantilla.position), ''), 'UNSPECIFIED'),
      v_plantilla.account_id,
      v_plantilla.chain_id,
      v_plantilla.store_id,
      v_plantilla.province_id,
      COALESCE(v_plantilla.area_name_snapshot, v_plantilla.area),
      NULL,
      p_effective_date,
      COALESCE(p_vacancy_type, 'Backfill'),
      'Open',
      v_plantilla.id,
      v_plantilla.store_name,
      NOW(),
      NOW(),
      auth.uid(),
      auth.uid(),
      1
    ) RETURNING id INTO v_vacancy_id;
  END IF;

  RETURN v_vacancy_id;
END;
$function$
;
