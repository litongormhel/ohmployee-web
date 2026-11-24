<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-Core. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/00_core_invariants.md
source_commit: 0eb4407 2026-11-23T23:02:59+08:00
source_sha256: 3f4f940153e53ea4cac1eabb5c5280329db34718b923f1fdf59dd680cc8e66f4
synced_at: 2026-11-24T09:04:13.191Z
-->
# ADR Architecture — Core Cross-Module Invariants

- **Status:** ACCEPTED & BINDING (Single Source of Truth)
- **Scope:** Cross-Module Invariants binding every module in OHMployee and OHMployee Web.

This document contains the core, non-negotiable cross-module invariants that govern slot state, hired-headcount derivation, user management, and denormalized counters across all modules.

> [!IMPORTANT]
> **Hub-and-Spoke Context Loading Rule:**
> When executing a prompt, an AI agent loads:
> 1. `00_core_invariants.md` (this file)
> 2. The specific module file in `docs/architecture/adr/` corresponding to the active task (e.g., `02_vacancy.md` for Vacancy work).
> Do NOT load unrelated module files.

---

## Core Cross-Module Invariants

These four rules are binding across every module that touches slot state, hired-headcount derivation, or denormalized counters. Documented once here — not duplicated per module. Do not revert any rule without equally explicit re-verification and an update to this document.

### Rule 1 — Slot Authority

**Module scope:** Plantilla & Vacancy primarily; HR Emploc and Onboarding write paths also participate.

`fn_set_slot_status` is the ONLY path that may change `plantilla_slots.slot_status`. All lifecycle writers are rewired through it: `move_to_plantilla` (reserve/finalize), `_execute_approved_coverage_request` (all 5 slot writes), `tag_backout` (slot release), and HR Emploc Import's submit/approve/reject/rollback flow (open→hr_processing→pipeline transitions). Callers RAISE on a `blocked` result — never silently ignore it. `anon`/`authenticated` hold zero table- or column-level UPDATE privilege on `plantilla_slots` (guard-asserted live).

The 5 SA-gated admin/QA bulk archive functions (`fn_archive_*`, `fn_qa_*`, `fn_rollback_archive_batch`) remain justified direct writers — bulk archival is not a lifecycle transition. (This is the basis for the More Module compliance note below.)

**Backout releases the slot in the same transaction:** `tag_backout` resolves the linked plantilla slot (`hr_emploc.slot_id`, else unambiguous single-`hr_processing`-slot fallback on the vcode) and releases it → open via `fn_set_slot_status(reason 'BACKOUT')`; blocked release is FATAL (22023). Slots occupied by a different employee are never released. Reason codes `BACKOUT`/`HC_READD` are seeded into `slot_reason_codes`; `slot_history.reason_code` is FK-checked. Matrix extension: `closed`/`hc_reduced`→`open` only with reason `HC_READD`/`COVERAGE_STORE_REMOVED`/`COVERAGE_GROUP_DISSOLVED`.

### Rule 2 — Hired HC Source

**Module scope:** Cross-module derived read. Source of truth lives in Plantilla; consumed by Vacancy, Dashboard, CENCOM, HR Emploc, and Onboarding.

`hired_count` derives STRICTLY from `plantilla.status = 'Active'` per VCode, filtered to active occupants only. No other source (applicant status, `hc_filled`, view fallbacks) may contribute to a Hired count. A Confirmed-Onboard applicant not yet in Plantilla counts nowhere — its slot sits `hr_processing`, not hired. When an employee is tagged Inactive (Resigned, AWOL, Terminated, Endo, Backout, etc.), `hired_count` drops immediately and the slot/vacancy reopens.

### Rule 3 — Lifecycle Sync

**Module scope:** Cross-module (Applicant / Vacancy / Plantilla / HR Emploc / Onboarding).

An applicant/vacancy status change (hire, backout, separation) must never leave its corresponding `plantilla_slots` row dangling. This is enforced as a backstop, not just a convention: a deferred CONSTRAINT TRIGGER (`trg_applicant_terminal_slot_sync`) on `applicants` fails the transaction at COMMIT if a move into Backout/Withdrawn/Separated leaves its slot unclaimed (`hr_processing`) or still occupied/filled by that applicant's plantilla row.

### Rule 6 — Denormalized Writes

**Module scope:** Cross-module.

Denormalized count columns (e.g. `hc_filled`) must never be written directly — they must be derived. `vacancy_requirements.hc_filled` is FROZEN and DEPRECATED: `trg_freeze_vr_hc_filled` forces INSERT to 0 and raises on any UPDATE attempting to change it. The derived read path is `vw_vacancy_requirements` (security_invoker), which computes `hc_filled` as a live count of Active non-deleted Plantilla rows linked via `plantilla.vacancy_requirement_id`. Physical column removal is deferred (migration lint forbids the DDL token; requires an explicit override in a future prompt).

### Rule 7 — User Management as HRCO Single Source of Truth

**Module scope:** Cross-module (Vacancy, Plantilla, HR Emploc, Dashboard, Accounts).

User Management (`public.user_scopes` joined to `public.users_profile` with `roles.role_name = 'HRCO'`) is the exclusive authoritative Single Source of Truth for HR Coordinator (HRCO) assignments across all modules:

1. **Vacancy Resolution**: `public.vw_vacancy_list` and `public.list_web_vacancies` resolve `hrco_name` and `hrco_user_id` dynamically from active user scopes (account-level scope first, cascaded group-level scope second).
2. **Plantilla Resolution**: `public.v_plantilla_safe` and `public.list_web_plantilla_employees` resolve `hrco_name` and `coordinator` dynamically from active user scopes.
3. **Accounts Synchronization**: `public.accounts.hrco_user_id` is maintained in strict synchronization with User Management via `public.fn_reevaluate_hrco_auto_tags`.
4. **HR Emploc Inheritance**: New candidate deployments inherit their `hrco_name` and `hrco_user_id_snapshot` directly from the account/vacancy HRCO.
5. **Active Filter Contract**: Only active, non-archived user profiles (`users_profile.is_active = TRUE AND users_profile.archived_at IS NULL`) are recognized and projected as HRCOs. Soft-archived or suspended profiles are strictly suppressed and will render as `Unassigned` on requisitions until an active HRCO is assigned or the profile is reactivated.
6. **Self-Healing Reactivation Contract**: When an Administrator modifies a user's role/scopes (`public.upsert_user_profile_and_scopes`) or activates a user (`public.set_user_active`), the database automatically restores `is_active = TRUE`, clears `archived_at = NULL` and `archived_by = NULL`, and dispatches `public.fn_reevaluate_hrco_auto_tags` across all affected account scopes.

### Validation

`SELECT * FROM fn_adr001_smoke();` — 6 assertions (A1 slot/occupant coherence, A2 derived hired, A3 single-tab priority, A4 ordering, A5 privilege lockdown, A6 rolled-back lifecycle probes), zero persistent changes. Run it after any change touching slots, hired-HC derivation, or vacancy tab classification.

### Slot-Creation Traceability (`ohm#7v3k9m5r` — 2026-08-06)

`fn_trg_auto_create_vacancy_slot()` — the `AFTER INSERT OR UPDATE OF status, required_headcount ON vacancies` trigger that auto-creates `plantilla_slots` rows — stamps `source_hc_request_id = NEW.source_headcount_request_id` at INSERT time (falling back to `NULL` only when that column is itself `NULL` on the vacancy row). Previously hardcoded `NULL`, relying entirely on `create_plantilla_slot_from_request`'s follow-up "adoption" `UPDATE ... WHERE source_hc_request_id IS NULL` to backfill the real value — a step that only ran when that RPC was the caller. Direct admin writes to `vacancies.required_headcount`/`status` (RLS-restricted to Super Admin/Head Admin) bypassed adoption entirely, leaving permanently untraceable slots — confirmed live on staging across multiple pre-existing rows, not just the two `ohm#8t4w6r9p`/`ohm#3k7m9x2v` incident rows.

**Binding rule:** direct admin writes to `required_headcount`/`status` remain fully permitted (unchanged, RLS-gated) — they no longer produce untraceable orphans as a side effect. `create_plantilla_slot_from_request`'s adoption `UPDATE` is left in place as a defensive no-op (it fires only when the trigger's stamped value was itself `NULL`); do not remove it.

**Known consequence, not a defect:** when an HC request increases `required_headcount` on a VCode reused from a *different, earlier* HC request (no fresh `vacancies` INSERT), the new slot inherits the vacancy row's original `source_headcount_request_id`, not the expanding request's id — traces to demand origin rather than to whichever request most recently touched the row. Accepted as more architecturally correct than the prior mis-attribution behavior.

**Not covered by this fix:** pre-existing orphaned slots created before `20260806020000` are not backfilled. Migration `20260806020000_fix_trigger_slot_source_hc_request_id.sql`.

---
