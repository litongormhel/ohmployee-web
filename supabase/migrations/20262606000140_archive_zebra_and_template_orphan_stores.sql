-- ==============================================================================
-- Migration: 20262606000140_archive_zebra_and_template_orphan_stores.sql
-- Description:
--   1. Synchronize store status, is_active, and is_archived columns via triggers
--      (preventing de-synced stores where status/is_active is modified but is_archived stays false)
--   2. Explicitly archive ZEBRA template import orphan stores (b8312324... and 2c6e2cc3...)
--      whose plantilla slots were reset via QA_RESET but stores were left active
--   3. Safely archive other template test and rolled-back orphan stores across staging
--      that have 0 active allocations, 0 active slots, 0 open vacancies, and 0 pending requests
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Enhance store legacy sync triggers to keep status, is_active, and is_archived aligned
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_stores_sync_legacy_ins()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.area_province IS NULL AND NEW.province IS NOT NULL THEN 
    NEW.area_province := NEW.province; 
  END IF;
  IF NEW.province IS NULL AND NEW.area_province IS NOT NULL THEN 
    NEW.province := NEW.area_province; 
  END IF;

  -- 3-way status/active/archived sync on insert
  IF NEW.is_archived IS TRUE THEN
    NEW.is_active := false;
    NEW.status := 'archived';
    NEW.archived_at := COALESCE(NEW.archived_at, now());
  ELSIF NEW.status = 'archived' OR NEW.is_active IS FALSE THEN
    NEW.is_active := false;
    NEW.status := 'archived';
    NEW.is_archived := true;
    NEW.archived_at := COALESCE(NEW.archived_at, now());
  ELSE
    IF NEW.status IS NULL THEN NEW.status := 'active'; END IF;
    IF NEW.is_active IS NULL THEN NEW.is_active := true; END IF;
    IF NEW.is_archived IS NULL THEN NEW.is_archived := false; END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_stores_sync_legacy_upd()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  -- Province sync
  IF NEW.area_province IS DISTINCT FROM OLD.area_province THEN
    NEW.province := NEW.area_province;
  ELSIF NEW.province IS DISTINCT FROM OLD.province THEN
    NEW.area_province := NEW.province;
  END IF;

  -- 3-way status/active/archived sync on update
  IF NEW.is_archived IS DISTINCT FROM OLD.is_archived AND NEW.is_archived IS TRUE THEN
    NEW.is_active := false;
    NEW.status := 'archived';
    NEW.archived_at := COALESCE(NEW.archived_at, now());
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.is_active := (NEW.status = 'active');
    NEW.is_archived := (NEW.status = 'archived');
    IF NEW.status = 'archived' THEN
      NEW.archived_at := COALESCE(NEW.archived_at, now());
    END IF;
  ELSIF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
    NEW.status := CASE WHEN NEW.is_active THEN 'active' ELSE 'archived' END;
    NEW.is_archived := NOT NEW.is_active;
    IF NOT NEW.is_active THEN
      NEW.archived_at := COALESCE(NEW.archived_at, now());
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------------------------
-- 2. Specifically archive ZEBRA orphan stores from template import batches
-- ------------------------------------------------------------------------------
UPDATE public.stores
SET is_active = false,
    status = 'archived',
    is_archived = true,
    archived_at = now()
WHERE id IN (
  'e1932464-376f-4031-a9cd-10a6b6997046',
  'c8675271-2fc1-43fe-930e-c3946857ca82',
  'be6a5411-d5f8-4429-9dab-0c4a4deaaff0',
  'ea67e2dd-811e-41a6-8b9b-cc9f801d870b'
);

UPDATE public.plantilla_slots
SET is_archived = true,
    archived_at = now()
WHERE store_id IN (
  'e1932464-376f-4031-a9cd-10a6b6997046',
  'c8675271-2fc1-43fe-930e-c3946857ca82',
  'be6a5411-d5f8-4429-9dab-0c4a4deaaff0',
  'ea67e2dd-811e-41a6-8b9b-cc9f801d870b'
);

UPDATE public.plantilla_import_batches
SET status = 'rolled_back',
    rolled_back_at = now(),
    rollback_reason = 'Template test upload - QA reset orphan stores archived'
WHERE id IN (
  'b8312324-a939-4373-bda2-5639fdfb6469',
  '2c6e2cc3-9e21-4781-9c55-1de0a4851e15'
);

-- ------------------------------------------------------------------------------
-- 3. Safely archive other template test / rolled-back orphan stores with 0 active dependencies
-- ------------------------------------------------------------------------------
WITH orphan_candidate_stores AS (
  SELECT s.id
  FROM public.stores s
  JOIN public.plantilla_import_batches pib ON pib.id = s.source_import_id
  LEFT JOIN public.employee_store_allocations esa ON esa.store_id = s.id AND esa.is_active = true
  LEFT JOIN public.plantilla_slots ps ON ps.store_id = s.id AND ps.slot_status = 'active'
  LEFT JOIN public.vacancies v ON v.store_id = s.id AND v.status != 'Closed' AND (v.is_archived IS NULL OR v.is_archived = false)
  LEFT JOIN public.headcount_requests hr ON hr.store_id = s.id AND hr.status NOT IN ('cancelled', 'rejected')
  WHERE s.is_active = true
    AND (pib.file_name ILIKE '%template%' OR pib.status = 'rolled_back')
    AND esa.id IS NULL
    AND ps.id IS NULL
    AND v.id IS NULL
    AND hr.id IS NULL
)
UPDATE public.stores
SET is_active = false,
    status = 'archived',
    is_archived = true,
    archived_at = now()
WHERE id IN (SELECT id FROM orphan_candidate_stores);

-- ------------------------------------------------------------------------------
-- 4. Mark all closed/inactive slots on archived stores as is_archived = true
-- ------------------------------------------------------------------------------
UPDATE public.plantilla_slots
SET is_archived = true,
    archived_at = now()
WHERE store_id IN (
  SELECT id FROM public.stores WHERE is_active = false AND is_archived = true
)
AND (is_archived IS NULL OR is_archived = false);
