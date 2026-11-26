-- Migration: 20262606000204_auto_data_cleanup_and_alignment_adr_all_modules.sql
-- Description: Automatic Data Clean Up and Alignment Migration across All Modules (ADR-001, ADR-002, ADR-003, ADR-004)
-- Enforces 100% data integrity on Plantilla, Vacancy, HR Emploc, and Store Governance.

-- ==================================================================
-- 1. APPROVALS & STORES: Deduplicate & Reactivate Canonical Stores with Active Personnel (ADR-001/004)
-- ==================================================================
-- Stores may have duplicate archived historical rows sharing the same vcode.
-- Only exactly ONE canonical store per vcode may be status = 'active' (enforced by stores_vcode_active_uidx).

-- Step 1A: Select exactly ONE canonical store per vcode to reactivate
WITH candidates AS (
  SELECT st.id, st.vcode,
         ROW_NUMBER() OVER (
           PARTITION BY st.vcode
           ORDER BY
             (SELECT count(*) FROM public.plantilla p WHERE p.store_id = st.id AND p.status = 'Active') DESC,
             (SELECT count(*) FROM public.plantilla_slots s WHERE s.store_id = st.id AND s.slot_status = 'occupied') DESC,
             st.created_at ASC,
             st.id ASC
         ) as rn
  FROM public.stores st
  WHERE (st.status = 'archived' OR st.is_archived = true)
    AND st.vcode IS NOT NULL
    AND trim(st.vcode) != ''
    AND (
      EXISTS (
        SELECT 1 FROM public.plantilla p
        WHERE p.store_id = st.id AND p.status = 'Active'
      )
      OR EXISTS (
        SELECT 1 FROM public.employee_store_allocations esa
        JOIN public.plantilla p ON p.id = esa.plantilla_id
        WHERE esa.store_id = st.id AND esa.is_active = true AND p.status = 'Active'
      )
      OR EXISTS (
        SELECT 1 FROM public.plantilla_slots s
        WHERE s.store_id = st.id AND s.slot_status = 'occupied'
      )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.stores existing
      WHERE existing.vcode = st.vcode AND existing.status = 'active'
    )
)
UPDATE public.stores s
SET is_active = true,
    is_archived = false,
    status = 'active',
    updated_at = NOW()
FROM candidates c
WHERE s.id = c.id AND c.rn = 1;

-- Step 1B: Re-point any plantilla records, slots, and allocations pointing to non-canonical duplicate stores
-- to the canonical active store for that vcode
UPDATE public.plantilla p
SET store_id = active_st.id
FROM public.stores old_st
JOIN public.stores active_st ON active_st.vcode = old_st.vcode AND active_st.status = 'active'
WHERE p.store_id = old_st.id AND old_st.id != active_st.id;

UPDATE public.plantilla_slots s
SET store_id = active_st.id
FROM public.stores old_st
JOIN public.stores active_st ON active_st.vcode = old_st.vcode AND active_st.status = 'active'
WHERE s.store_id = old_st.id AND old_st.id != active_st.id;

UPDATE public.employee_store_allocations esa
SET store_id = active_st.id
FROM public.stores old_st
JOIN public.stores active_st ON active_st.vcode = old_st.vcode AND active_st.status = 'active'
WHERE esa.store_id = old_st.id AND old_st.id != active_st.id;

-- Step 1C: For genuinely archived stores that still have 'open' slots, close those open slots.
UPDATE public.plantilla_slots
SET slot_status = 'closed',
    closed_at = NOW(),
    closure_reason_code = 'STORE_CLOSED',
    updated_at = NOW()
WHERE store_id IN (
  SELECT id FROM public.stores
  WHERE status = 'archived' OR is_archived = true
)
AND slot_status = 'open';

-- ==================================================================
-- 2. PLANTILLA: Resolve store_id and Provision Slots for Remaining Active Personnel (ADR-001 Invariant 1)
-- ==================================================================
-- Backfill store_id on plantilla from allocations or matching vcode
UPDATE public.plantilla p
SET store_id = COALESCE(
  p.store_id,
  (SELECT esa.store_id FROM public.employee_store_allocations esa WHERE esa.plantilla_id = p.id AND esa.is_active = true AND esa.store_id IS NOT NULL LIMIT 1),
  (SELECT st.id FROM public.stores st WHERE st.vcode = p.vcode AND st.status = 'active' LIMIT 1),
  (SELECT st.id FROM public.stores st WHERE st.vcode = p.vcode AND (st.account_id = p.account_id OR p.account_id IS NULL) LIMIT 1),
  (SELECT st.id FROM public.stores st WHERE st.account_id = p.account_id AND st.status = 'active' ORDER BY st.created_at ASC LIMIT 1)
),
updated_at = NOW()
WHERE p.status = 'Active'
  AND p.store_id IS NULL
  AND (p.is_pool_employee = false OR p.is_pool_employee IS NULL);

-- Sync vcode on plantilla if store_id exists but vcode is blank
UPDATE public.plantilla p
SET vcode = st.vcode,
    updated_at = NOW()
FROM public.stores st
WHERE p.store_id = st.id
  AND p.status = 'Active'
  AND (p.vcode IS NULL OR trim(p.vcode) = '');

-- Provision or reopen occupied slots for all active non-pool employees without an occupied slot
DO $$
DECLARE
  v_emp RECORD;
  v_slot_id uuid;
  v_max_ordinal integer;
BEGIN
  FOR v_emp IN
    SELECT p.id, p.employee_no, p.employee_name, p.store_id, p.account_id, p.chain_id,
           p.position, p.deployment_type, p.vcode
    FROM public.plantilla p
    LEFT JOIN public.plantilla_slots s ON s.current_occupant_plantilla_id = p.id AND s.slot_status = 'occupied'
    WHERE p.status = 'Active'
      AND s.id IS NULL
      AND (p.is_pool_employee = false OR p.is_pool_employee IS NULL)
      AND p.store_id IS NOT NULL
  LOOP
    -- Step A: Check if a closed slot belonging to this employee exists
    SELECT s.id INTO v_slot_id
    FROM public.plantilla_slots s
    WHERE s.store_id = v_emp.store_id
      AND s.slot_status = 'closed'
      AND (s.current_occupant_plantilla_id = v_emp.id OR s.current_occupant_plantilla_id IS NULL)
    ORDER BY CASE WHEN s.current_occupant_plantilla_id = v_emp.id THEN 0 ELSE 1 END, s.slot_ordinal ASC
    LIMIT 1;

    IF v_slot_id IS NOT NULL THEN
      UPDATE public.plantilla_slots
      SET slot_status = 'occupied',
          current_occupant_plantilla_id = v_emp.id,
          closed_at = NULL,
          closed_by = NULL,
          closure_reason_code = NULL,
          position = COALESCE(v_emp.position, position),
          updated_at = NOW()
      WHERE id = v_slot_id;
    ELSE
      -- Step B: Check for an open slot
      SELECT s.id INTO v_slot_id
      FROM public.plantilla_slots s
      WHERE s.store_id = v_emp.store_id
        AND s.slot_status = 'open'
      ORDER BY s.slot_ordinal ASC
      LIMIT 1;

      IF v_slot_id IS NOT NULL THEN
        UPDATE public.plantilla_slots
        SET slot_status = 'occupied',
            current_occupant_plantilla_id = v_emp.id,
            position = COALESCE(v_emp.position, position),
            updated_at = NOW()
        WHERE id = v_slot_id;
      ELSE
        -- Step C: Provision brand new occupied physical slot
        SELECT COALESCE(MAX(slot_ordinal), 0) INTO v_max_ordinal
        FROM public.plantilla_slots
        WHERE store_id = v_emp.store_id;

        INSERT INTO public.plantilla_slots (
          store_id, account_id, group_id, position, employment_type, is_roving,
          slot_status, current_occupant_plantilla_id, slot_ordinal, created_at, updated_at
        ) VALUES (
          v_emp.store_id,
          v_emp.account_id,
          COALESCE(v_emp.chain_id, (SELECT group_id FROM public.stores WHERE id = v_emp.store_id)),
          COALESCE(v_emp.position, 'Merchandiser'),
          CASE WHEN v_emp.deployment_type ILIKE 'roving' THEN 'roving' ELSE 'stationary' END,
          CASE WHEN v_emp.deployment_type ILIKE 'roving' THEN true ELSE false END,
          'occupied',
          v_emp.id,
          v_max_ordinal + 1,
          NOW(),
          NOW()
        );
      END IF;
    END IF;
  END LOOP;
END $$;

-- Clean up dangling slots with missing store_id (ADR-001 Invariant 1)
-- First resolve store_id from occupant if occupant is present
UPDATE public.plantilla_slots ps
SET store_id = p.store_id,
    account_id = COALESCE(ps.account_id, p.account_id),
    group_id = COALESCE(ps.group_id, p.chain_id),
    updated_at = NOW()
FROM public.plantilla p
WHERE ps.current_occupant_plantilla_id = p.id
  AND ps.store_id IS NULL
  AND p.store_id IS NOT NULL;

-- Then from legacy_vcode if matching a store
UPDATE public.plantilla_slots ps
SET store_id = st.id,
    account_id = COALESCE(ps.account_id, st.account_id),
    group_id = COALESCE(ps.group_id, st.group_id),
    updated_at = NOW()
FROM public.stores st
WHERE ps.store_id IS NULL
  AND ps.legacy_vcode IS NOT NULL
  AND ps.legacy_vcode = st.vcode;

-- For any remaining closed slots with no store_id, attach to the account's active store (or any active store)
UPDATE public.plantilla_slots ps
SET store_id = COALESCE(
  (SELECT id FROM public.stores WHERE account_id = ps.account_id AND status = 'active' LIMIT 1),
  (SELECT id FROM public.stores WHERE account_id = ps.account_id LIMIT 1),
  (SELECT id FROM public.stores WHERE status = 'active' LIMIT 1)
),
updated_at = NOW()
WHERE ps.store_id IS NULL;

-- Correct Roving Allocations with high store counts to 4-decimal precision (ADR-001 Invariant 4)
WITH active_counts AS (
  SELECT plantilla_id, count(*) as store_cnt
  FROM public.employee_store_allocations
  WHERE is_active = true
  GROUP BY plantilla_id
)
UPDATE public.employee_store_allocations esa
SET filled_hc = ROUND(1.0 / ac.store_cnt, 4),
    active_store_count = ac.store_cnt
FROM active_counts ac
WHERE esa.plantilla_id = ac.plantilla_id
  AND esa.is_active = true
  AND ac.store_cnt >= 2
  AND abs(esa.filled_hc - ROUND(1.0 / ac.store_cnt, 4)) > 0.0001;

-- ==================================================================
-- 3. VACANCY: Align Vacancy States, Capacities, and Terminal Applicants (ADR-002)
-- ==================================================================
-- A. Release slot_id from terminal applicants (ADR-002 Invariant 3)
UPDATE public.applicants
SET slot_id = NULL,
    updated_at = NOW()
WHERE status IN ('Backout', 'Rejected', 'Failed', 'Withdrawn')
  AND slot_id IS NOT NULL;

-- B. Archive applicant on VCAG5_0056 with is_archived = true to Withdrawn (fixing negative capacity)
UPDATE public.applicants
SET status = 'Withdrawn',
    updated_at = NOW()
WHERE vacancy_vcode = 'VCAG5_0056'
  AND is_archived = true
  AND status = 'Confirmed Onboard';

-- C. Fulfilled vacancies lingering in status 'Open' transition to 'Filled' (ADR-002)
UPDATE public.vacancies v
SET status = 'Filled',
    updated_at = NOW()
WHERE v.status = 'Open'
  AND (
    SELECT count(*)
    FROM public.applicants a
    WHERE a.vacancy_vcode = v.vcode
      AND a.is_archived = false
      AND a.status IN ('Hired', 'Confirmed Onboard')
  ) >= v.required_headcount;

-- E. Closed/Archived vacancies with remaining 'open' slots in plantilla_slots: close them (ADR-002)
UPDATE public.plantilla_slots s
SET slot_status = 'closed',
    closed_at = NOW(),
    closure_reason_code = 'HC_REDUCTION',
    updated_at = NOW()
FROM public.vacancies v
WHERE s.store_id = v.store_id
  AND v.status IN ('Closed', 'Archived', 'Cancelled')
  AND s.slot_status = 'open';

-- F. Vacancies on active physical stores missing physical slots: provision open physical slots (ADR-002 Invariant 1)
DO $$
DECLARE
  v_rec RECORD;
  v_active_slots integer;
  v_needed integer;
  v_max_ordinal integer;
  i integer;
BEGIN
  FOR v_rec IN
    SELECT v.id, v.vcode, v.store_id, v.account_id, v.position, v.required_headcount::integer as req_hc
    FROM public.vacancies v
    JOIN public.stores st ON st.id = v.store_id
    WHERE v.status IN ('Open', 'Pipeline')
      AND v.store_id IS NOT NULL
      AND (v.is_pool_vacancy = false OR v.is_pool_vacancy IS NULL)
  LOOP
    SELECT count(*) INTO v_active_slots
    FROM public.plantilla_slots s
    WHERE s.store_id = v_rec.store_id AND s.slot_status != 'closed';

    v_needed := v_rec.req_hc - v_active_slots;
    IF v_needed > 0 THEN
      SELECT COALESCE(MAX(slot_ordinal), 0) INTO v_max_ordinal
      FROM public.plantilla_slots
      WHERE store_id = v_rec.store_id;

      FOR i IN 1..v_needed LOOP
        INSERT INTO public.plantilla_slots (
          store_id, account_id, group_id, position, employment_type, is_roving,
          slot_status, slot_ordinal, created_at, updated_at
        ) VALUES (
          v_rec.store_id,
          v_rec.account_id,
          (SELECT group_id FROM public.stores WHERE id = v_rec.store_id),
          COALESCE(v_rec.position, 'Merchandiser'),
          'stationary',
          false,
          'open',
          v_max_ordinal + i,
          NOW(),
          NOW()
        );
      END LOOP;
    END IF;
  END LOOP;
END $$;

-- ==================================================================
-- 4. HR EMPLOC: Link Slots and Ensure Occupancy Parity (ADR-003)
-- ==================================================================
-- A. Link slot_id for stationary HR Emploc records where employee is Active in Plantilla
UPDATE public.hr_emploc e
SET slot_id = s.id,
    updated_at = NOW()
FROM public.plantilla p
JOIN public.plantilla_slots s ON s.current_occupant_plantilla_id = p.id AND s.slot_status = 'occupied'
WHERE e.employee_no = p.employee_no
  AND p.status = 'Active'
  AND e.coverage_slot_id IS NULL
  AND e.coverage_group_id IS NULL
  AND (e.slot_id IS NULL OR e.slot_id != s.id);

-- B. For active deployed personnel whose HR Emploc slot was marked 'closed', reopen to 'occupied'
UPDATE public.plantilla_slots s
SET slot_status = 'occupied',
    current_occupant_plantilla_id = p.id,
    closed_at = NULL,
    closed_by = NULL,
    closure_reason_code = NULL,
    updated_at = NOW()
FROM public.hr_emploc e
JOIN public.plantilla p ON p.employee_no = e.employee_no
WHERE e.slot_id = s.id
  AND p.status = 'Active'
  AND s.slot_status = 'closed';

-- C. For Pending Emploc records with store_id but missing slot_id, link to an open slot on that store (stationary only)
UPDATE public.hr_emploc e
SET slot_id = (
  SELECT s.id
  FROM public.plantilla_slots s
  WHERE s.store_id = e.store_id AND s.slot_status = 'open'
  ORDER BY s.slot_ordinal ASC
  LIMIT 1
),
updated_at = NOW()
WHERE e.status = 'Pending Emploc'
  AND e.coverage_slot_id IS NULL
  AND e.coverage_group_id IS NULL
  AND e.slot_id IS NULL
  AND e.store_id IS NOT NULL;
