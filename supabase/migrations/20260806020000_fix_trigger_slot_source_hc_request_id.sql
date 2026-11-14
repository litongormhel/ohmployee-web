-- Migration: fix_trigger_slot_source_hc_request_id
-- Prompt: ohm#7v3k9m5r (2026-08-06)
--
-- Problem: fn_trg_auto_create_vacancy_slot() hardcoded source_hc_request_id = NULL
-- on every plantilla_slots row it INSERTs. create_plantilla_slot_from_request()'s
-- follow-up "adoption" UPDATE (WHERE source_hc_request_id IS NULL) only stamps the
-- real value when that RPC is the caller. Direct admin writes to
-- vacancies.required_headcount/status (RLS-restricted to SA/Head Admin) skip
-- adoption entirely, leaving permanently orphaned (untraceable) slots.
--
-- Fix: stamp new slot INSERTs with NEW.source_headcount_request_id (already
-- populated on vacancies at creation time), falling back to NULL only when that
-- column is itself NULL on the vacancy row. create_plantilla_slot_from_request's
-- own adoption UPDATE is left untouched — it becomes a no-op in the normal path
-- (the slot already carries the same id the adoption step would set) and remains
-- a harmless defensive no-op for any vacancy row where source_headcount_request_id
-- is NULL at INSERT time.

CREATE OR REPLACE FUNCTION public.fn_trg_auto_create_vacancy_slot()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_required_hc  int;
  v_max_ordinal  int;
  v_slot_id      uuid;
  v_store_id     uuid;
  v_ordinal      int;
  v_slot_status  text;
  v_aging_ts     timestamptz;
  v_emp_type     text;
BEGIN
  -- Only fire for non-pool, non-deleted, non-roving, VCODE-bearing vacancies
  -- that have affects_required_hc = true (or NULL, which defaults to true).
  IF COALESCE(NEW.is_pool_vacancy, false)       = true  THEN RETURN NEW; END IF;
  IF NEW.deleted_at IS NOT NULL                          THEN RETURN NEW; END IF;
  IF NEW.vcode IS NULL                                   THEN RETURN NEW; END IF;
  IF COALESCE(NEW.affects_required_hc, true)    = false THEN RETURN NEW; END IF;

  -- Only fire when the vacancy is entering or staying at Open/Pipeline
  IF lower(NEW.status) NOT IN ('open', 'pipeline') THEN RETURN NEW; END IF;

  -- On UPDATE: skip if status did not change to/from an open state
  -- (avoids re-firing on unrelated column updates when status is already Open)
  IF TG_OP = 'UPDATE' THEN
    IF lower(OLD.status) = lower(NEW.status) THEN
      -- Status unchanged — only re-evaluate if required_headcount increased
      IF COALESCE(NEW.required_headcount, 1) <= COALESCE(OLD.required_headcount, 1) THEN
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  v_required_hc := GREATEST(COALESCE(NEW.required_headcount, 1), 1);
  v_slot_status  := CASE
                      WHEN lower(NEW.status) = 'pipeline' THEN 'pipeline'
                      ELSE 'open'
                    END;
  v_aging_ts     := COALESCE(NEW.vacant_date::timestamptz, now());
  v_emp_type     := COALESCE(NEW.employment_type, 'stationary');

  -- Resolve store_id, prioritizing NEW.store_id (fix: ohm#9x4p2k7q)
  -- Previously only did VCode lookup, causing NULL store_id for new stores
  -- where stores.vcode had not yet been set.
  IF NEW.store_id IS NOT NULL THEN
    v_store_id := NEW.store_id;
  ELSE
    SELECT s.id INTO v_store_id
    FROM public.stores s
    WHERE upper(s.vcode) = upper(NEW.vcode)
      AND s.status = 'active'
    ORDER BY s.created_at
    LIMIT 1;
  END IF;

  -- Determine how many slots already exist for this VCODE
  SELECT COALESCE(MAX(ps.slot_ordinal), 0) INTO v_max_ordinal
  FROM public.plantilla_slots ps
  WHERE ps.legacy_vcode = NEW.vcode;

  -- Create only the missing ordinals (v_max_ordinal+1 .. required_hc)
  FOR v_ordinal IN (v_max_ordinal + 1) .. v_required_hc LOOP
    -- Idempotency guard
    IF EXISTS (
      SELECT 1 FROM public.plantilla_slots ps2
      WHERE ps2.legacy_vcode = NEW.vcode
        AND ps2.slot_ordinal = v_ordinal
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO public.plantilla_slots (
      store_id,
      account_id,
      group_id,
      position,
      employment_type,
      is_roving,
      slot_status,
      slot_ordinal,
      legacy_vcode,
      source_hc_request_id,
      created_at,
      updated_at
    ) VALUES (
      v_store_id,
      NEW.account_id,
      NEW.group_id,
      COALESCE(NEW.position, ''),
      v_emp_type,
      false,
      v_slot_status,
      v_ordinal::smallint,
      NEW.vcode,
      NEW.source_headcount_request_id,
      now(),
      now()
    )
    RETURNING id INTO v_slot_id;

    INSERT INTO public.slot_history (
      slot_id,
      account_id,
      action_type,
      old_value,
      new_value,
      reason_code,
      performed_by,
      remarks,
      created_at
    ) VALUES (
      v_slot_id,
      NEW.account_id,
      'status_change',
      NULL,
      v_slot_status,
      NULL,
      public.get_current_profile_id(),
      'Auto-created by fn_trg_auto_create_vacancy_slot on vacancy ' || NEW.vcode,
      v_aging_ts
    );
  END LOOP;

  RETURN NEW;
END$function$;
