-- ============================================================
-- OHM2026_0002 — Plantilla Slot Foundation (Phase 1A)
-- Migration:  20260804000000_plantilla_slot_foundation_v1.sql
-- Depends on: get_my_allowed_account_ids(), i_have_full_access()
--             (both pre-existing); stores, accounts, groups,
--             plantilla, users_profile.
-- ============================================================
-- Scope: DATABASE FOUNDATION ONLY for the locked Plantilla Slot
--   architecture (docs/architecture/plantilla_slot_architecture.md,
--   v1.0 Locked). Creates three new, self-contained tables.
--
--   This migration deliberately does NOT:
--     • migrate or backfill existing data,
--     • create lifecycle automation / triggers,
--     • alter Vacancy / Plantilla / Transfer / Import behavior,
--     • touch MFR / CENCOM.
--   No existing table is modified. No existing behavior changes.
--
-- Sections:
--   §1  slot_reason_codes  (master lookup + seed)
--   §2  plantilla_slots    (the asset / position)
--   §3  slot_history       (lifecycle audit trail)
--   §4  Indexes
--   §5  RLS
--
-- Validation Queries (run manually after applying):
--   V1 – New tables exist
--     SELECT tablename FROM pg_tables WHERE schemaname='public'
--       AND tablename IN ('plantilla_slots','slot_history','slot_reason_codes');
--   V2 – Reason codes seeded (expect 7 rows)
--     SELECT code FROM public.slot_reason_codes ORDER BY sort_order;
--   V3 – RLS enabled on all three tables
--     SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public'
--       AND tablename IN ('plantilla_slots','slot_history','slot_reason_codes');
--   V4 – Policies present
--     SELECT tablename, policyname FROM pg_policies WHERE schemaname='public'
--       AND tablename IN ('plantilla_slots','slot_history','slot_reason_codes');
--   V5 – Indexes present
--     SELECT tablename, indexname FROM pg_indexes WHERE schemaname='public'
--       AND tablename IN ('plantilla_slots','slot_history')
--       ORDER BY tablename, indexname;
-- ============================================================


-- ============================================================
-- §1  slot_reason_codes  (master lookup)
-- ============================================================
-- Reserved reason codes for slot lifecycle events, per the locked
-- architecture. Small, stable lookup table; readable by all
-- authenticated users. Writes are migration/RPC-only.

CREATE TABLE IF NOT EXISTS public.slot_reason_codes (
  code        text        NOT NULL,
  label       text        NOT NULL,
  description text,
  is_active   boolean     NOT NULL DEFAULT true,
  sort_order  integer     NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT slot_reason_codes_pkey PRIMARY KEY (code)
);

COMMENT ON TABLE public.slot_reason_codes IS
  'Master lookup of slot lifecycle reason codes (HC_ADD, REPLACEMENT, '
  'TRANSFER_OUT, RESIGNED, ENDO, HC_REDUCTION, STORE_CLOSED). '
  'Referenced by plantilla_slots.closure_reason_code and slot_history.reason_code.';

INSERT INTO public.slot_reason_codes (code, label, description, sort_order)
VALUES
  ('HC_ADD',       'Headcount Added',      'Additional headcount approved → slot created.',   10),
  ('REPLACEMENT',  'Replacement',          'Slot refilled after an occupant left.',           20),
  ('TRANSFER_OUT', 'Transfer Out',         'Occupant transferred out of a slot.',             30),
  ('RESIGNED',     'Resigned',             'Occupant resigned, slot reopened.',               40),
  ('ENDO',         'End of Deployment',    'End-of-deployment separation.',                   50),
  ('HC_REDUCTION', 'Headcount Reduction',  'Headcount reduced → slot closed.',                60),
  ('STORE_CLOSED', 'Store Closed',         'Slot closed due to store closure.',               70)
ON CONFLICT (code) DO NOTHING;


-- ============================================================
-- §2  plantilla_slots  (the asset)
-- ============================================================
-- A slot is an approved, fundable manpower position. It persists
-- across occupant changes and moves between lifecycle states.
-- Created only when additional headcount is approved (future RPC).

CREATE TABLE IF NOT EXISTS public.plantilla_slots (
  -- Identity
  id                            uuid        NOT NULL DEFAULT gen_random_uuid(),

  -- Linkage
  store_id                      uuid,        -- home store; NULL allowed for roving slots
  account_id                    uuid,        -- denormalized for scope filtering
  group_id                      uuid,        -- denormalized for scope filtering

  -- Position definition
  position                      text        NOT NULL,
  employment_type               text        NOT NULL,
  is_roving                     boolean     NOT NULL DEFAULT false,

  -- Lifecycle state
  slot_status                   text        NOT NULL DEFAULT 'open',

  -- Current occupant (where safely available). Occupants come and go;
  -- this points at the active plantilla row currently filling the slot.
  current_occupant_plantilla_id uuid,

  -- Created / updated metadata
  created_at                    timestamptz NOT NULL DEFAULT now(),
  created_by                    uuid,
  updated_at                    timestamptz NOT NULL DEFAULT now(),
  updated_by                    uuid,

  -- Closed metadata (slots are closed, never deleted)
  closed_at                     timestamptz,
  closed_by                     uuid,
  closure_reason_code           text,

  -- Constraints
  CONSTRAINT plantilla_slots_pkey
    PRIMARY KEY (id),

  CONSTRAINT plantilla_slots_status_check
    CHECK (slot_status IN ('open', 'pipeline', 'hr_processing', 'occupied', 'closed')),

  CONSTRAINT plantilla_slots_store_fkey
    FOREIGN KEY (store_id)      REFERENCES public.stores(id),
  CONSTRAINT plantilla_slots_account_fkey
    FOREIGN KEY (account_id)    REFERENCES public.accounts(id),
  CONSTRAINT plantilla_slots_group_fkey
    FOREIGN KEY (group_id)      REFERENCES public.groups(id),
  CONSTRAINT plantilla_slots_created_by_fkey
    FOREIGN KEY (created_by)    REFERENCES public.users_profile(id),
  CONSTRAINT plantilla_slots_updated_by_fkey
    FOREIGN KEY (updated_by)    REFERENCES public.users_profile(id),
  CONSTRAINT plantilla_slots_closed_by_fkey
    FOREIGN KEY (closed_by)     REFERENCES public.users_profile(id),
  CONSTRAINT plantilla_slots_closure_reason_fkey
    FOREIGN KEY (closure_reason_code) REFERENCES public.slot_reason_codes(code),

  -- The occupant reference points at plantilla(id). Declared NOT VALID:
  -- plantilla is a large, actively-mutated table — skip the validation
  -- scan. New rows are still checked because the table starts empty.
  CONSTRAINT plantilla_slots_occupant_fkey
    FOREIGN KEY (current_occupant_plantilla_id)
    REFERENCES public.plantilla(id) NOT VALID
);

COMMENT ON TABLE public.plantilla_slots IS
  'Workforce slot — an approved, fundable manpower position. The asset that '
  'persists while employees flow through it. Required HC = count of slots. '
  'Foundation table only (Phase 1A); lifecycle automation is deferred.';
COMMENT ON COLUMN public.plantilla_slots.store_id IS
  'Home store. NULL permitted for roving slots whose coverage is not bound to a '
  'single store; multi-store coverage is a future-phase attribute.';
COMMENT ON COLUMN public.plantilla_slots.account_id IS
  'Denormalized account for scope filtering. Scoped users see a slot only when '
  'this matches one of their allowed accounts; NULL is visible to full-access only.';
COMMENT ON COLUMN public.plantilla_slots.slot_status IS
  'open | pipeline | hr_processing | occupied | closed. A slot is always in '
  'exactly one state. "closed" is the archive-first retirement state.';
COMMENT ON COLUMN public.plantilla_slots.current_occupant_plantilla_id IS
  'Active plantilla row filling this slot, where safely available. NULL when the '
  'slot is empty (open/pipeline/hr_processing) or closed.';
COMMENT ON COLUMN public.plantilla_slots.is_roving IS
  'TRUE when this slot is a roving position. Roving = one slot, many covered '
  'stores; coverage and MFR are slot-based.';


-- ============================================================
-- §3  slot_history  (lifecycle audit trail)
-- ============================================================
-- Append-only record of each slot lifecycle event. Writes are
-- RPC-only (future phase). Example actions: created, occupied,
-- transfer_in, transfer_out, resigned, closed.

CREATE TABLE IF NOT EXISTS public.slot_history (
  id           uuid        NOT NULL DEFAULT gen_random_uuid(),
  slot_id      uuid        NOT NULL,

  -- Denormalized account for scope-safe RLS and indexing
  account_id   uuid,

  action_type  text        NOT NULL,
  old_value    text,
  new_value    text,
  reason_code  text,
  performed_by uuid,
  remarks      text,
  created_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT slot_history_pkey
    PRIMARY KEY (id),

  CONSTRAINT slot_history_slot_fkey
    FOREIGN KEY (slot_id)      REFERENCES public.plantilla_slots(id),
  CONSTRAINT slot_history_account_fkey
    FOREIGN KEY (account_id)   REFERENCES public.accounts(id),
  CONSTRAINT slot_history_reason_fkey
    FOREIGN KEY (reason_code)  REFERENCES public.slot_reason_codes(code),
  CONSTRAINT slot_history_performer_fkey
    FOREIGN KEY (performed_by) REFERENCES public.users_profile(id)
);

COMMENT ON TABLE public.slot_history IS
  'Append-only audit trail of slot lifecycle events. One row per event. '
  'Client mutations are blocked; all writes go through future SECURITY DEFINER RPCs.';
COMMENT ON COLUMN public.slot_history.account_id IS
  'Denormalized from the parent slot for scope-safe RLS and efficient filtering.';
COMMENT ON COLUMN public.slot_history.action_type IS
  'Lifecycle event, e.g. created | occupied | transfer_in | transfer_out | '
  'resigned | closed. Free text in Phase 1A; canonicalized when RPCs land.';


-- ============================================================
-- §4  Indexes
-- ============================================================

-- plantilla_slots
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_store_id
  ON public.plantilla_slots(store_id);
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_position
  ON public.plantilla_slots(position);
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_employment_type
  ON public.plantilla_slots(employment_type);
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_status
  ON public.plantilla_slots(slot_status);
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_occupant
  ON public.plantilla_slots(current_occupant_plantilla_id)
  WHERE current_occupant_plantilla_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_closure_reason
  ON public.plantilla_slots(closure_reason_code)
  WHERE closure_reason_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_created_at
  ON public.plantilla_slots(created_at);
-- Account scope path (RLS predicate support)
CREATE INDEX IF NOT EXISTS idx_plantilla_slots_account_id
  ON public.plantilla_slots(account_id);

-- slot_history
CREATE INDEX IF NOT EXISTS idx_slot_history_slot_id
  ON public.slot_history(slot_id);
CREATE INDEX IF NOT EXISTS idx_slot_history_reason_code
  ON public.slot_history(reason_code)
  WHERE reason_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_slot_history_created_at
  ON public.slot_history(created_at);
CREATE INDEX IF NOT EXISTS idx_slot_history_account_id
  ON public.slot_history(account_id);


-- ============================================================
-- §5  RLS
-- ============================================================
-- Consistent with existing project patterns:
--   • Mutations are blocked for authenticated/anon — all writes go
--     through future SECURITY DEFINER RPCs (RPC-first, backend-enforced).
--   • SELECT is scoped: full-access (Super/Head Admin) see all; scoped
--     users see only their allowed accounts via get_my_allowed_account_ids().
--   • slot_reason_codes is a master lookup — readable by all authenticated.

-- ── slot_reason_codes ────────────────────────────────────────
ALTER TABLE public.slot_reason_codes ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.slot_reason_codes FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.slot_reason_codes FROM anon;

CREATE POLICY slot_reason_codes_read_all
  ON public.slot_reason_codes
  FOR SELECT
  TO authenticated
  USING (true);

-- ── plantilla_slots ──────────────────────────────────────────
ALTER TABLE public.plantilla_slots ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.plantilla_slots FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.plantilla_slots FROM anon;

CREATE POLICY plantilla_slots_read_scoped
  ON public.plantilla_slots
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR account_id = ANY (public.get_my_allowed_account_ids())
  );

-- ── slot_history ─────────────────────────────────────────────
ALTER TABLE public.slot_history ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.slot_history FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.slot_history FROM anon;

CREATE POLICY slot_history_read_scoped
  ON public.slot_history
  FOR SELECT
  TO authenticated
  USING (
    public.i_have_full_access()
    OR account_id = ANY (public.get_my_allowed_account_ids())
  );
