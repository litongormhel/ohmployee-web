-- ============================================================
-- ohm#r8v2k7m4 — Store Master Island Group Authority
-- Migration: 20261237000000_store_master_island_group.sql
-- ============================================================
-- §1  Add island_group to stores
-- §2  fn_derive_island_group() — province → island group mapping
-- §3  Trigger: auto-set island_group on stores insert/update
-- §4  Backfill existing stores
-- §5  Update approve_new_store_request to carry island_group
-- ============================================================
-- INVARIANT: island_group is ALWAYS derived from province.
--            Never accept island_group as a direct user input.
--            Never infer province/city from store name.
-- ============================================================


-- ============================================================
-- §1  Add island_group to stores
-- ============================================================

ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS island_group text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'stores_island_group_chk'
  ) THEN
    ALTER TABLE public.stores
      ADD CONSTRAINT stores_island_group_chk
      CHECK (island_group IN ('Luzon', 'Visayas', 'Mindanao') OR island_group IS NULL);
  END IF;
END $$;

COMMENT ON COLUMN public.stores.island_group IS
  'Derived automatically from province via fn_derive_island_group(). '
  'Never set directly by users. Authority for Coverage Group island validation.';


-- ============================================================
-- §2  fn_derive_island_group() — province → island group
-- ============================================================
-- Maps any Philippine province/region name to its island group.
-- Returns NULL for unknown/unresolvable provinces.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_derive_island_group(p_province text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
SELECT CASE
  -- ── Luzon ─────────────────────────────────────────────────────────────────
  WHEN lower(trim(p_province)) IN (
    -- NCR / Metro Manila
    'metro manila', 'ncr', 'national capital region', 'manila', 'quezon city',
    'caloocan', 'las piñas', 'las pinas', 'makati', 'malabon', 'mandaluyong',
    'marikina', 'muntinlupa', 'navotas', 'parañaque', 'paranaque',
    'pasay', 'pasig', 'pateros', 'san juan', 'taguig', 'valenzuela',
    -- CAR
    'car', 'cordillera', 'cordillera administrative region',
    'abra', 'apayao', 'benguet', 'ifugao', 'kalinga', 'mountain province',
    'baguio', 'baguio city',
    -- Region I — Ilocos
    'region i', 'ilocos region',
    'ilocos norte', 'ilocos sur', 'la union', 'pangasinan',
    -- Region II — Cagayan Valley
    'region ii', 'cagayan valley',
    'batanes', 'cagayan', 'isabela', 'nueva vizcaya', 'quirino',
    -- Region III — Central Luzon
    'region iii', 'central luzon',
    'aurora', 'bataan', 'bulacan', 'nueva ecija', 'pampanga', 'tarlac', 'zambales',
    -- Region IV-A — CALABARZON
    'region iv-a', 'calabarzon',
    'batangas', 'cavite', 'laguna', 'quezon', 'rizal',
    -- Region IV-B — MIMAROPA
    'region iv-b', 'mimaropa',
    'marinduque', 'occidental mindoro', 'oriental mindoro', 'palawan', 'romblon',
    -- Region V — Bicol
    'region v', 'bicol region',
    'albay', 'camarines norte', 'camarines sur', 'catanduanes', 'masbate', 'sorsogon'
  ) THEN 'Luzon'

  -- ── Visayas ──────────────────────────────────────────────────────────────
  WHEN lower(trim(p_province)) IN (
    -- Region VI — Western Visayas
    'region vi', 'western visayas',
    'aklan', 'antique', 'capiz', 'guimaras', 'iloilo', 'negros occidental',
    -- Region VII — Central Visayas
    'region vii', 'central visayas',
    'bohol', 'cebu', 'negros oriental', 'siquijor',
    -- Region VIII — Eastern Visayas
    'region viii', 'eastern visayas',
    'biliran', 'eastern samar', 'leyte', 'northern samar', 'samar', 'southern leyte'
  ) THEN 'Visayas'

  -- ── Mindanao ─────────────────────────────────────────────────────────────
  WHEN lower(trim(p_province)) IN (
    -- Region IX — Zamboanga Peninsula
    'region ix', 'zamboanga peninsula',
    'zamboanga del norte', 'zamboanga del sur', 'zamboanga sibugay',
    -- Region X — Northern Mindanao
    'region x', 'northern mindanao',
    'bukidnon', 'camiguin', 'lanao del norte', 'misamis occidental', 'misamis oriental',
    -- Region XI — Davao
    'region xi', 'davao region',
    'compostela valley', 'davao de oro', 'davao del norte', 'davao del sur',
    'davao occidental', 'davao oriental',
    -- Region XII — SOCCSKSARGEN
    'region xii', 'soccsksargen',
    'cotabato', 'north cotabato', 'sarangani', 'south cotabato', 'sultan kudarat',
    -- Region XIII — Caraga
    'region xiii', 'caraga',
    'agusan del norte', 'agusan del sur', 'dinagat islands',
    'surigao del norte', 'surigao del sur',
    -- BARMM
    'barmm', 'bangsamoro',
    'basilan', 'lanao del sur', 'maguindanao', 'sulu', 'tawi-tawi',
    'maguindanao del norte', 'maguindanao del sur'
  ) THEN 'Mindanao'

  ELSE NULL
END;
$$;

COMMENT ON FUNCTION public.fn_derive_island_group(text) IS
  'Maps a Philippine province/region name to Luzon, Visayas, or Mindanao. '
  'Returns NULL for unknown inputs. Used to enforce island group validation on Coverage Groups.';

GRANT EXECUTE ON FUNCTION public.fn_derive_island_group(text) TO authenticated;


-- ============================================================
-- §3  Trigger: auto-set island_group on stores insert/update
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_trg_stores_set_island_group()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.province IS NOT NULL AND NEW.province <> '' THEN
    NEW.island_group := public.fn_derive_island_group(NEW.province);
  ELSIF NEW.area_province IS NOT NULL AND NEW.area_province <> '' THEN
    NEW.island_group := public.fn_derive_island_group(NEW.area_province);
  ELSE
    NEW.island_group := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stores_set_island_group ON public.stores;
CREATE TRIGGER trg_stores_set_island_group
  BEFORE INSERT OR UPDATE OF province, area_province ON public.stores
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_stores_set_island_group();


-- ============================================================
-- §4  Backfill existing stores
-- ============================================================

UPDATE public.stores
SET island_group = public.fn_derive_island_group(
  COALESCE(NULLIF(TRIM(province), ''), NULLIF(TRIM(area_province), ''))
)
WHERE island_group IS NULL
  AND COALESCE(NULLIF(TRIM(province), ''), NULLIF(TRIM(area_province), '')) IS NOT NULL;


-- ============================================================
-- §5  Update approve_new_store_request to carry island_group
-- ============================================================
-- The trigger on stores will fire automatically on INSERT,
-- so no explicit island_group column is needed in the INSERT.
-- This section adds an index for efficient island-group lookups.
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_stores_island_group
  ON public.stores (island_group)
  WHERE island_group IS NOT NULL AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_stores_account_island_group
  ON public.stores (account_id, island_group)
  WHERE island_group IS NOT NULL AND is_active = true AND status = 'active';
