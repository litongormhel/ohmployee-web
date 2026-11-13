# BRIEFING — 2026-11-13T01:17:00Z

## Mission
Investigate and specify the exact surgical SQL diff for `public.qa_run_scenario` in Milestone 1 (Database Engine & Multi-Role Sandbox Migration).

## 🔒 My Identity
- Archetype: explorer
- Roles: Migration Base & GUC Diff Specification Specialist
- Working directory: d:\Projects\ohmployee-web
- State folder: d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1
- Original parent: 6863d778-d94c-4bc3-b617-a727a50f6360
- Milestone: Milestone 1 - Database Engine & Multi-Role Sandbox Migration

## 🔒 Key Constraints
- Read-only investigation — do NOT implement in source/migrations directly
- Base migration is `supabase/migrations/20262606000045_qa_role_relay_engine.sql`
- SQL Function Surgical-Diff & Contract Gate (Anti-Overwrite Lock)
- Dual GUC requirement: set and defensively restore both `request.jwt.claim.sub` and `request.jwt.claims`
- Enforce check constraints: `hr_emploc.status` must use valid allowed statuses ('Pending Emploc', 'Active', 'Separated'), `plantilla.status` must use allowed transitions ('Resigned', etc.)
- Enforce collision-proof synthetic `users_profile` identifiers

## Current Parent
- Conversation ID: 6863d778-d94c-4bc3-b617-a727a50f6360
- Updated: not yet

## Investigation State
- **Explored paths**: `supabase/migrations/20262606000045_qa_role_relay_engine.sql`, `20260520012857_remote_schema.sql`, `20260527000000_unify_role_level_source.sql`, `20261228000000_fix_permission_drift_f01_f02.sql`, `scripts/check-sql-contracts.mjs`, `scripts/adr-mirror.mjs`.
- **Key findings**:
  1. Base migration confirmed as `20262606000045_qa_role_relay_engine.sql` (lines 7–520).
  2. `auth.uid()` reads `request.jwt.claim.sub`, causing role switching to fail without setting both `request.jwt.claim.sub` and `request.jwt.claims`.
  3. Defensive restoration of `request.jwt.claim.sub` with fallback to `v_ha_uid` prevents unhandled exception in `qa_complete_detection_run`.
  4. Physical check constraint on `hr_emploc.status` forbids `'Active'`; must be `'Pending Emploc'`.
  5. Physical check constraint on `plantilla.status` forbids `'Vacant'`; must be `'Resigned'`.
  6. Unique constraints on `users_profile` (email, full_name, auth_user_id) require random hex appending for test actors.
  7. Step telemetry can be persisted to `qa_agent_runs.metadata` right before run completion.
- **Unexplored areas**: None. Milestone 1 SQL specification complete.

## Key Decisions Made
- Formulated verbatim proposed migration `proposed_migration.sql` in `.agents/teamwork/teamwork_explorer_m1_1/`.
- Authored 5-component handoff report `handoff.md` with complete diffs and instructions for Milestone 1 Worker.

## Artifact Index
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1\proposed_migration.sql` — Verbatim proposed migration
- `d:\Projects\ohmployee-web\.agents\teamwork\teamwork_explorer_m1_1\handoff.md` — Final Milestone 1 specification report
