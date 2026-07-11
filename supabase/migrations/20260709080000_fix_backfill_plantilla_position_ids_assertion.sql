-- Migration: 20260709080000_fix_backfill_plantilla_position_ids_assertion
-- Created: 2026-07-09
-- Purpose: Re-run the position_id backfill from 20260731100000_backfill_plantilla_position_ids.sql
--          without its environment-specific hardcoded row-count assertions. On PROD, Part 1's
--          exact-match set is 40 rows (not 41 as on Staging) because 2 of the 41 IDs baked into
--          the original migration's audit comment do not exist in PROD's plantilla table, while
--          2 other real PROD rows match instead. All UPDATEs remain scoped to position_id IS NULL,
--          so this is a safe no-op on Staging (already fully backfilled by the original migration)
--          and completes the backfill correctly on PROD.
--
-- Reversal Plan:
--   Not applicable in isolation — this migration only backfills position_id where currently NULL.
--   To reverse, see the reversal plan in 20260731100000_backfill_plantilla_position_ids.sql, or
--   set position_id = NULL for any plantilla row whose position_id was newly set by this migration.
--
-- Smoke Tests:
-- S1: No exception raised; NOTICE output shows actual Part 1 / Part 2 update counts (may be < 41 / < 30 on some environments).
-- S2: SELECT count(*) FROM public.plantilla WHERE status='Active' AND COALESCE(deployment_type,'')<>'Roving' AND position_id IS NULL AND position IN ('Merchandiser','Promodiser','Cashier','MERCHANDISER','CASHIER','CHECKER','PICKER','WAREHOUSEMAN') returns 0 after apply.

DO $$
DECLARE
  v_rec RECORD;
  v_new_pos_id uuid;
  v_count integer := 0;
BEGIN
  -- ==========================================
  -- PART 1: EXACT MATCH BACKFILL
  -- ==========================================
  RAISE NOTICE '=== AUDIT TRAIL: PART 1 EXACT MATCH ===';
  FOR v_rec IN (
    SELECT p.id, p.position, pos.id as new_position_id
    FROM public.plantilla p
    JOIN public.positions pos ON pos.position_name = p.position
    WHERE p.status='Active'
      AND COALESCE(p.deployment_type,'')<>'Roving'
      AND p.position_id IS NULL
      AND p.position IN ('Merchandiser','Promodiser','Cashier','MERCHANDISER','CASHIER','CHECKER','PICKER','WAREHOUSEMAN')
      AND pos.is_active = true
  ) LOOP
    RAISE NOTICE 'PART 1: id=%, position=%, old_position_id=NULL, new_position_id=%',
                 v_rec.id, v_rec.position, v_rec.new_position_id;
  END LOOP;

  UPDATE public.plantilla p
  SET position_id = pos.id
  FROM public.positions pos
  WHERE pos.position_name = p.position
    AND p.status='Active'
    AND COALESCE(p.deployment_type,'')<>'Roving'
    AND p.position_id IS NULL
    AND p.position IN ('Merchandiser','Promodiser','Cashier','MERCHANDISER','CASHIER','CHECKER','PICKER','WAREHOUSEMAN')
    AND pos.is_active = true;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'PART 1 update completed. Count: % (environment-specific; not asserted against a fixed expected value)', v_count;

  -- ==========================================
  -- PART 2: CLOSEST CANDIDATE AUTO-MAPPING
  -- ==========================================
  RAISE NOTICE '=== AUDIT TRAIL: PART 2 CLOSEST-CANDIDATE AUTO-MAPPING ===';
  FOR v_rec IN (
    SELECT p.id, p.position,
           CASE
             WHEN p.position IN ('WAREHOUSE SUPPORT CREW 1', 'WAREHOUSE SUPPORT CREW 2', 'WAREHOUSE SUPPORT CREW 3', 'GENERAL SUPPORT CREW 1', 'DELIVERY SUPPORT CREW 5') THEN 'SUPPORT CREW'
             WHEN p.position IN ('COOP ASSISTANT SUPERVISOR', 'ASSISTANT SELLING SUPERVISOR', 'CHECK OUT ASSISTANT SUPERVISOR', 'CHECK OUT ASSISTANT SUPERVISOR TRAINEE', 'TREASURY ASSISTANT SUPERVISOR') THEN 'SUPERVISOR ASSISTANT'
             WHEN p.position = 'STORE MAINTENANCE PERSONNEL' THEN 'MAINTENANCE'
             WHEN p.position = 'UTILITY MESSENGER' THEN 'UTILITY'
             WHEN p.position IN ('RELIEVER CASHIER', 'STORE CASHIER') THEN 'CASHIER'
             WHEN p.position IN ('RECEIVING CHECKER', 'RECIEVING CHECKER') THEN 'CHECKER (RECEIVING)'
             WHEN p.position IN ('SELLING SUPERVISOR', 'COOP CHECK OUT SUPERVISOR', 'TREASURY SUPERVISOR 1') THEN 'SUPERVISOR'
             WHEN p.position = 'CUSTOMER SERVICE REPRESENTATIVE' THEN 'CUSTOMER ASSISTANT'
             WHEN p.position = 'Promoter' THEN 'Sales Promoter'
             WHEN p.position = 'FIELD SALES REPRESENTATIVE' THEN 'SALES REPRESENTATIVE'
           END as target_position_name
    FROM public.plantilla p
    WHERE p.status='Active'
      AND COALESCE(p.deployment_type,'')<>'Roving'
      AND p.position_id IS NULL
      AND p.position IN (
        'WAREHOUSE SUPPORT CREW 1', 'WAREHOUSE SUPPORT CREW 2', 'WAREHOUSE SUPPORT CREW 3', 'GENERAL SUPPORT CREW 1', 'DELIVERY SUPPORT CREW 5',
        'COOP ASSISTANT SUPERVISOR', 'ASSISTANT SELLING SUPERVISOR', 'CHECK OUT ASSISTANT SUPERVISOR', 'CHECK OUT ASSISTANT SUPERVISOR TRAINEE', 'TREASURY ASSISTANT SUPERVISOR',
        'STORE MAINTENANCE PERSONNEL', 'UTILITY MESSENGER', 'RELIEVER CASHIER', 'STORE CASHIER', 'RECEIVING CHECKER', 'RECIEVING CHECKER',
        'SELLING SUPERVISOR', 'COOP CHECK OUT SUPERVISOR', 'TREASURY SUPERVISOR 1', 'CUSTOMER SERVICE REPRESENTATIVE', 'Promoter', 'FIELD SALES REPRESENTATIVE'
      )
  ) LOOP
    -- resolve target position ID
    SELECT id INTO v_new_pos_id
    FROM public.positions
    WHERE position_name = v_rec.target_position_name AND is_active = true;

    IF v_new_pos_id IS NULL THEN
      RAISE EXCEPTION 'Target position name % resolved to NULL', v_rec.target_position_name;
    END IF;

    RAISE NOTICE 'PART 2: id=%, position=%, old_position_id=NULL, new_position_id=%',
                 v_rec.id, v_rec.position, v_new_pos_id;
  END LOOP;

  -- Perform Part 2 Updates
  WITH mappings(src_name, tgt_name) AS (
    VALUES
      ('WAREHOUSE SUPPORT CREW 1', 'SUPPORT CREW'),
      ('WAREHOUSE SUPPORT CREW 2', 'SUPPORT CREW'),
      ('WAREHOUSE SUPPORT CREW 3', 'SUPPORT CREW'),
      ('GENERAL SUPPORT CREW 1', 'SUPPORT CREW'),
      ('DELIVERY SUPPORT CREW 5', 'SUPPORT CREW'),
      ('COOP ASSISTANT SUPERVISOR', 'SUPERVISOR ASSISTANT'),
      ('ASSISTANT SELLING SUPERVISOR', 'SUPERVISOR ASSISTANT'),
      ('CHECK OUT ASSISTANT SUPERVISOR', 'SUPERVISOR ASSISTANT'),
      ('CHECK OUT ASSISTANT SUPERVISOR TRAINEE', 'SUPERVISOR ASSISTANT'),
      ('TREASURY ASSISTANT SUPERVISOR', 'SUPERVISOR ASSISTANT'),
      ('STORE MAINTENANCE PERSONNEL', 'MAINTENANCE'),
      ('UTILITY MESSENGER', 'UTILITY'),
      ('RELIEVER CASHIER', 'CASHIER'),
      ('STORE CASHIER', 'CASHIER'),
      ('RECEIVING CHECKER', 'CHECKER (RECEIVING)'),
      ('RECIEVING CHECKER', 'CHECKER (RECEIVING)'),
      ('SELLING SUPERVISOR', 'SUPERVISOR'),
      ('COOP CHECK OUT SUPERVISOR', 'SUPERVISOR'),
      ('TREASURY SUPERVISOR 1', 'SUPERVISOR'),
      ('CUSTOMER SERVICE REPRESENTATIVE', 'CUSTOMER ASSISTANT'),
      ('Promoter', 'Sales Promoter'),
      ('FIELD SALES REPRESENTATIVE', 'SALES REPRESENTATIVE')
  )
  UPDATE public.plantilla p
  SET position_id = pos.id
  FROM mappings m
  JOIN public.positions pos ON pos.position_name = m.tgt_name
  WHERE p.position = m.src_name
    AND p.status='Active'
    AND COALESCE(p.deployment_type,'')<>'Roving'
    AND p.position_id IS NULL
    AND pos.is_active = true;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'PART 2 update completed. Count: % (environment-specific; not asserted against a fixed expected value)', v_count;

END;
$$;
