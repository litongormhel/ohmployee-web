-- ============================================================================
-- OHM2026_0073 — Fix Roving Employee Vacancy Reopen Failure After Inactive Approval
-- Migration: 20260914000000_fix_roving_employee_vacancy_reopen.sql
-- ============================================================================
-- PROBLEM:
--   When a roving employee goes Inactive (AWOL/Resigned/Endo/Terminated),
--   the separation trigger `fn_plantilla_separation_to_vacancy` fires.
--   For roving employees, it loops over `plantilla_store_links` to update link
--   statuses and reopen vacancies.
--   However, baseline imported roving employees (such as 2023-09515) do not have
--   `plantilla_store_links` because they don't have roving assignments.
--   Additionally, they don't have vacancies in the database.
--   As a result, their separation does not reopen or create any vacancies.
--
-- FIX:
--   1. Drop the NOT NULL constraint on `plantilla_store_links.roving_assignment_id`.
--   2. Harden trigger function `fn_plantilla_separation_to_vacancy` to:
--      - First check `plantilla_store_links`.
--      - If no active store links exist, fall back to `employee_store_allocations`.
--      - Reopen existing vacancies by vcode. If missing entirely, create as Open.
--        Note: For roving vacancies, we set source_plantilla_id to NULL to avoid
--        violating the unique constraint uq_vacancy_source_plantilla. The 1-to-many
--        link is preserved in plantilla_store_links.
--      - Write historical links into `plantilla_store_links` with status Resigned / Backed Out.
--   3. One-time backfill: retroactively create active `plantilla_store_links`
--      from active `employee_store_allocations` for active roving employees.
-- ============================================================================

BEGIN;

-- 1. Drop NOT NULL constraint on roving_assignment_id to allow NULL roving assignments
ALTER TABLE public.plantilla_store_links ALTER COLUMN roving_assignment_id DROP NOT NULL;

-- 2. Harden trigger function fn_plantilla_separation_to_vacancy
CREATE OR REPLACE FUNCTION public.fn_plantilla_separation_to_vacancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_link          record;
  v_link_status   text;
  v_has_links     boolean := false;
  v_store         record;
  v_rows_updated  int;
  v_new_vacancy_id uuid;
  v_new_link_id   uuid;
BEGIN
  IF NEW.separation_status IN ('AWOL','Resigned','Endo','Others','Terminated','End of Contract')
     AND NEW.date_of_separation IS NOT NULL
     AND (
          OLD.separation_status IS DISTINCT FROM NEW.separation_status
          OR OLD.date_of_separation IS DISTINCT FROM NEW.date_of_separation
         )
  THEN

    IF COALESCE(NEW.deployment_type, '') = 'Roving' THEN

      v_link_status := CASE
        WHEN NEW.separation_status IN ('Resigned','AWOL','Terminated','End of Contract','Endo','Others')
          THEN 'Resigned'
        ELSE 'Backed Out'
      END;

      -- Check if any active plantilla_store_links exist for this plantilla row
      SELECT EXISTS (
        SELECT 1
        FROM public.plantilla_store_links psl
        WHERE psl.plantilla_id = NEW.id
          AND psl.deleted_at IS NULL
          AND psl.status = 'Active'
      ) INTO v_has_links;

      IF v_has_links THEN
        -- Path A: Loop through existing active links
        FOR v_link IN
          SELECT psl.id, psl.vacancy_id, psl.vcode, psl.store_name, psl.account
            FROM public.plantilla_store_links psl
           WHERE psl.plantilla_id = NEW.id
             AND psl.deleted_at IS NULL
             AND psl.status = 'Active'
        LOOP
          UPDATE public.plantilla_store_links
             SET status      = v_link_status,
                 unlinked_at = now(),
                 updated_at  = now()
           WHERE id = v_link.id;

          -- Reopen or create vacancy
          IF v_link.vacancy_id IS NOT NULL THEN
            UPDATE public.vacancies
               SET status              = 'Open',
                   is_archived         = false,
                   archived_at         = NULL,
                   has_pending_closure = false,
                   vacant_date         = COALESCE(NEW.date_of_separation, CURRENT_DATE),
                   updated_at          = now()
             WHERE id = v_link.vacancy_id;
          ELSE
            UPDATE public.vacancies
               SET status              = 'Open',
                   is_archived         = false,
                   archived_at         = NULL,
                   has_pending_closure = false,
                   vacant_date         = COALESCE(NEW.date_of_separation, CURRENT_DATE),
                   updated_at          = now()
             WHERE vcode      = v_link.vcode
               AND deleted_at IS NULL;

            GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

            IF v_rows_updated = 0 THEN
              -- Fetch store details for vacancy creation
              SELECT s.id AS store_id, s.store_name, s.account_id, a.account_name, s.group_id
              INTO v_store
              FROM public.stores s
              LEFT JOIN public.accounts a ON a.id = s.account_id
              WHERE upper(s.vcode) = upper(v_link.vcode) AND s.status = 'active'
              ORDER BY s.created_at ASC
              LIMIT 1;

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
                required_headcount
              )
              VALUES (
                v_link.vcode,
                COALESCE(v_store.account_name, v_link.account, NEW.account, 'UNKNOWN'),
                NEW.position,
                COALESCE(v_store.account_id, NEW.account_id),
                NEW.chain_id,
                v_store.store_id,
                NEW.province_id,
                COALESCE(NEW.area_name_snapshot, NEW.area),
                NEW.position_id,
                COALESCE(NEW.date_of_separation, CURRENT_DATE),
                'Backfill',
                'Open',
                NULL, -- Set to NULL to respect the uq_vacancy_source_plantilla unique constraint
                COALESCE(v_store.store_name, v_link.store_name),
                now(),
                now(),
                1
              )
              RETURNING id INTO v_new_vacancy_id;

              -- Link the newly created vacancy to the store link
              UPDATE public.plantilla_store_links
                 SET vacancy_id = v_new_vacancy_id
               WHERE id = v_link.id;
            END IF;
          END IF;
        END LOOP;
      ELSE
        -- Path B: Fallback path - query active allocations from employee_store_allocations
        FOR v_link IN
          SELECT esa.vcode, esa.store_name, esa.store_id, esa.account_id
            FROM public.employee_store_allocations esa
           WHERE esa.plantilla_id = NEW.id
             AND esa.is_active = true
             AND esa.deleted_at IS NULL
        LOOP
          -- Fetch store details
          SELECT s.id AS store_id, s.store_name, s.account_id, a.account_name, s.group_id
          INTO v_store
          FROM public.stores s
          LEFT JOIN public.accounts a ON a.id = s.account_id
          WHERE upper(s.vcode) = upper(v_link.vcode) AND s.status = 'active'
          ORDER BY s.created_at ASC
          LIMIT 1;

          -- 1. Insert history record in plantilla_store_links marked as resigned/backed out
          INSERT INTO public.plantilla_store_links (
            plantilla_id,
            roving_assignment_id,
            vcode,
            store_name,
            account,
            status,
            linked_at,
            unlinked_at,
            created_at,
            updated_at
          )
          VALUES (
            NEW.id,
            NULL,
            v_link.vcode,
            COALESCE(v_store.store_name, v_link.store_name),
            COALESCE(v_store.account_name, NEW.account, 'UNKNOWN'),
            v_link_status,
            now(),
            now(),
            now(),
            now()
          )
          RETURNING id INTO v_new_link_id;

          -- 2. Try to reopen vacancy by vcode
          UPDATE public.vacancies
             SET status              = 'Open',
                 is_archived         = false,
                 archived_at         = NULL,
                 has_pending_closure = false,
                 vacant_date         = COALESCE(NEW.date_of_separation, CURRENT_DATE),
                 updated_at          = now()
           WHERE vcode      = v_link.vcode
             AND deleted_at IS NULL;

          GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

          -- 3. If vacancy is missing entirely, create it as Open
          IF v_rows_updated = 0 THEN
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
              required_headcount
            )
            VALUES (
              v_link.vcode,
              COALESCE(v_store.account_name, NEW.account, 'UNKNOWN'),
              NEW.position,
              COALESCE(v_store.account_id, NEW.account_id),
              NEW.chain_id,
              v_store.store_id,
              NEW.province_id,
              COALESCE(NEW.area_name_snapshot, NEW.area),
              NEW.position_id,
              COALESCE(NEW.date_of_separation, CURRENT_DATE),
              'Backfill',
              'Open',
              NULL, -- Set to NULL to respect the uq_vacancy_source_plantilla unique constraint
              COALESCE(v_store.store_name, v_link.store_name),
              now(),
              now(),
              1
            )
            RETURNING id INTO v_new_vacancy_id;

            -- Link newly created vacancy to newly created store link
            UPDATE public.plantilla_store_links
               SET vacancy_id = v_new_vacancy_id
             WHERE id = v_new_link_id;
          ELSE
            -- Link existing vacancy to newly created store link
            UPDATE public.plantilla_store_links
               SET vacancy_id = (SELECT id FROM public.vacancies WHERE vcode = v_link.vcode AND deleted_at IS NULL ORDER BY created_at ASC LIMIT 1)
             WHERE id = v_new_link_id;
          END IF;
        END LOOP;
      END IF;

      RETURN NEW;
    END IF;

    -- Stationary employee: reopen or create the single linked vacancy.
    PERFORM public.reopen_or_create_vacancy_for_plantilla(
      NEW.id,
      NEW.date_of_separation,
      'Backfill'
    );
  END IF;

  RETURN NEW;
END;
$function$;

-- 3. One-Time Backfill: retroactively create plantilla_store_links from active employee_store_allocations
INSERT INTO public.plantilla_store_links (
  plantilla_id,
  roving_assignment_id,
  hr_emploc_store_link_id,
  vacancy_id,
  vcode,
  store_name,
  account,
  status,
  linked_at,
  created_at,
  updated_at
)
SELECT
  p.id AS plantilla_id,
  NULL AS roving_assignment_id,
  NULL AS hr_emploc_store_link_id,
  NULL AS vacancy_id,
  esa.vcode,
  esa.store_name,
  COALESCE(
    (SELECT COALESCE(account_code, account_name) FROM public.accounts WHERE id = esa.account_id),
    p.account,
    'UNKNOWN'
  ) AS account,
  'Active' AS status,
  NOW() AS linked_at,
  NOW() AS created_at,
  NOW() AS updated_at
FROM public.plantilla p
JOIN public.employee_store_allocations esa ON esa.plantilla_id = p.id
WHERE p.deployment_type = 'Roving'
  AND p.status = 'Active'
  AND p.is_deleted = false
  AND esa.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM public.plantilla_store_links psl WHERE psl.plantilla_id = p.id
  );

COMMIT;
