-- Migration: 20260731100000_backfill_plantilla_position_ids
-- Created: 2026-07-09
-- Purpose: Backfill position_id for 71 resolvable plantilla rows on Staging (41 exact + 30 auto-mapped).
--          Category C (263 blank/null text rows) remains untouched.
--
-- Reversal Plan:
--   UPDATE public.plantilla
--   SET position_id = NULL
--   WHERE id IN (
--     -- Part 1: Exact matches (41 rows)
--     '28320473-b3db-4654-be8c-9b16afecd030',
--     '2b02344f-c893-4607-ab9b-3b653fbf04f3',
--     '97a655d4-b3d7-4cd3-80e7-1bc372fa306a',
--     '7d1af322-fada-4538-9c79-2d2c6ed47fc5',
--     '1cbca624-8fdb-454f-8ca3-e647b72f3924',
--     '55737447-e893-499a-b5aa-9b0b9ecd7a73',
--     '4804b5ab-13bb-4f1f-a993-2b384305a8ca',
--     '1f6092e9-06dd-4c4d-94c1-5b5984055463',
--     '8355d05c-f4dc-43f9-bbb8-cb236b885125',
--     '4933c390-4cac-4e0d-92d6-d58c8a888ffb',
--     'c0c5ada9-085c-41bd-b672-ce37bf600139',
--     'a7ef11d5-a855-4ad9-b099-67404b0ba889',
--     '9e6277b1-f82c-43f7-a9e5-c2314c87acb7',
--     'e1578da0-6e04-4f67-b568-bb80f0406521',
--     'c3af6b55-8a69-498f-bb5a-15f3393e96e6',
--     '1f2fc408-3520-4ec5-8090-a045b5c50605',
--     '15163742-6005-4bb3-928e-73c05bbec38c',
--     'f152c744-b847-401e-908d-fced90fb0401',
--     '792ae58d-56ed-4125-b55b-33ab9587820a',
--     '7766ab38-511c-4014-9509-c06d6e2f4d2e',
--     'dae3de6d-3d4c-4b34-bbec-b4d989d8417e',
--     '26cccaf9-a4f7-4152-a37e-db48a9ce0faa',
--     'f8ba1905-57bd-4fb7-a83e-8a16865baaf1',
--     '1005c744-75b8-4a8a-a585-29864b68d241',
--     'bfbed107-aa78-4622-8778-e279ddb82c73',
--     '20d57aaf-daad-4c63-9ffb-c541d05fa955',
--     '2c4c1fd4-e427-45c2-ba0f-afb8684015e8',
--     'd6f9d6fc-392a-4eaf-97e3-439f17012619',
--     '0d274da7-a5b2-4c1f-9f47-aa0163fa222a',
--     'a1d67923-7c3c-4c81-a2b0-b4e43efb5fe8',
--     '40f11c41-8edf-42e0-a259-9b7a3a5c5fad',
--     '7e53d65a-98ba-48f5-8cd3-2d3fedbb3ff6',
--     '7d66a72e-5d93-442b-a28a-13eee1cd8cac',
--     'f8c87d7e-c47f-4402-b82d-44a5acf64e77',
--     '74ccf744-cee9-463a-bdb2-a5fe322eb871',
--     'b5baed12-c730-4cef-9c37-9cd7763872be',
--     'a5ae535b-c571-4376-82a8-5ccb7b49c8fb',
--     'e09f1b7d-cb6b-4a73-8a00-7be862fec512',
--     'ea8a8f65-d355-4d74-a581-199b51515571',
--     'c9c6d091-c76d-4859-bc2c-df8346ac773c',
--     -- Part 2: Closest-candidate auto-mapping (30 rows)
--     '87592cdb-5e02-4ed8-8821-40a41059506d',
--     '7488cee5-a948-4a9e-b028-f0446d6800b0',
--     'a7a658ae-1f3d-4502-96ca-76505f66ce0e',
--     '0704a699-1124-49c4-ba81-6b996e56f743',
--     '8dc0411f-0c26-4796-8d9b-c8e25a3cceff',
--     '697efc9d-143c-46ca-ae71-f269e6fb2cdf',
--     'ab4f4bb6-7c10-430a-9d38-5e17149d92b7',
--     '240d56ca-27e9-40fa-98d4-698db4d2fcde',
--     '92eb4d16-d77b-415b-94cd-768424a1f1ef',
--     '2739ef8b-9685-4c15-8659-008c66c4e6d2',
--     'af6585c6-279e-436d-8386-9c936c47d463',
--     '1c9525b4-3a98-4bfe-9df3-a43a01670146',
--     '6e817c9c-9cf4-41cc-b3da-57dc0ac2b348',
--     '0b1177a4-224e-42da-9ad5-474b3cccfba5',
--     '76bb1471-c5bf-489b-a1d6-36655de991b2',
--     'ac1c7a5b-430d-4141-867c-1b1d03440777',
--     'b99103e0-69d6-411c-924e-396f042b9db5',
--     '9a777c4d-a1dc-4dbc-a74e-eeba91a7313a',
--     'd3f0f2bf-a1aa-452b-ae6d-a7d3c04439ab',
--     '489144cd-64b2-4da3-a879-91b3df189067',
--     'f9a4eb3c-a05f-4dca-8c1e-a8d383a236f9',
--     '6e28180e-33ec-4151-906b-cd7930c0dbe9',
--     '545a200a-efa7-49e1-82ff-872eca1698e0',
--     'f29eabd4-a608-4564-9e0c-5f3048e0b248',
--     'f0d26d4b-d673-43e4-a117-317ba9371bf9',
--     '9aca8c94-3837-4b68-b02a-cbc33b4c6f3b',
--     '71277d23-6058-4d94-9c7c-9bab4fbbb8cf',
--     '06f7e200-cfd0-4554-8959-3d75f2b1897a',
--     'aea5a66e-92ae-484c-95ef-c2ca896a0150',
--     '0537b531-3c99-4eef-984b-e607e90ac449'
--   );
--
-- Smoke Tests:
-- S1: Count of NULL position_id Active/Stationary rows matches 263.
-- S2: Spot-check of updated rows confirms correct position_id mappings.

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
  RAISE NOTICE 'PART 1 update completed. Count: %', v_count;
  
  IF v_count <> 41 THEN
    RAISE EXCEPTION 'PART 1 backfill validation failed: expected 41 rows, got %', v_count;
  END IF;

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
  RAISE NOTICE 'PART 2 update completed. Count: %', v_count;
  
  IF v_count <> 30 THEN
    RAISE EXCEPTION 'PART 2 backfill validation failed: expected 30 rows, got %', v_count;
  END IF;

END;
$$;
