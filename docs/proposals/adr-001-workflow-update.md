# ADR-001 Proposal: HR Emploc Atomic Auto-Move to Plantilla & Permanent Employee Number Registry

## Metadata
- **Proposal ID**: `ohm#7k4w9xqn`
- **Date**: 2026-11-04
- **Status**: Proposed (Implemented on STAGING `qqiiznmqxfoamqytjica`; PROD `rwxelulyapjgaarlwkus` deferred)
- **Canonical Target File**: `.ai/architecture_locks/adr_001_coverage_architecture_v2.md` (currently located in mobile repo `/Users/armanjr/Projects/OHMployee/OHMployee/.ai/architecture_locks/adr_001_coverage_architecture_v2.md`; mobile repo is mid-rebase and untouched)

---

## 1. Context & Contradictions in Current ADR-001 / State Docs

1. **Elimination of `Ready for Plantilla` and `hr_status = 'Complete'` as a Ready Queue**:
   - Previously, assigning an `employee_no` on Pending (`assign_hr_emploc_number`) or approving a correction on Review (`review_web_hr_emploc_correction` / `approve_correction_request`) placed the record into an intermediate state (`status = 'Ready for Plantilla'`, `hr_status = 'Complete'`) awaiting a separate manual `move_to_plantilla` / `bulk_move_ready_to_plantilla` call.
   - Under Ohm's authoritative workflow, there is **NO** "Ready" tab and **NO** `Ready for Plantilla` or `Complete` holding state. Assigning an Employee Number by any path (`assign_hr_emploc_number`, `review_web_hr_emploc_correction(approve)`, `approve_correction_request`) **atomically** moves the record to `plantilla` (`status = 'Active'`), occupies the `plantilla_slots` row (`slot_status = 'occupied'`), sets `hr_emploc.status = 'Moved to Plantilla'` and `hr_emploc.hr_status = 'Transferred'`, sets `moved_to_plantilla_at = now()`, and writes a single deployment audit log entry in the same transaction. Any failure in the Plantilla or slot step rolls back the Employee Number assignment as well.

2. **Authoritative Role Matrix & Removal of `i_have_full_access()` from HR Personnel-Only Gates**:
   - Previously, `tag_web_hr_emploc_deficiency`, `mark_for_correction`, `review_web_hr_emploc_correction`, `approve_correction_request`, `reject_correction_request`, and `reopen_correction_request` allowed `Head Admin` (via `i_have_full_access()` or `i_am_hr_dept()`), and `update_deployed_employee_id` allowed `HR Personnel` (via `i_am_hr_dept()`).
   - Authoritative Role Matrix:
     - **Pending — Assign Emploc# (auto-moves to Plantilla)**: `HR Personnel`, `Head Admin`, `Encoder`, `Super Admin` (`public.can_assign_pending_hr_emploc()`).
     - **Pending — Tag Deficiency**: `HR Personnel`, `Super Admin` ONLY (`public.can_tag_or_review_hr_emploc()`). `Head Admin` and `Encoder` are blocked.
     - **Correction — Submit Correction**: `Operations Manager` (`OM`), `TL`, `ATL`, `HRCO`, `Super Admin` (`public.can_submit_hr_emploc_correction()`).
     - **Review — Approve (assigns Emploc# + auto-moves to Plantilla) & Return to Correction**: `HR Personnel`, `Super Admin` ONLY (`public.can_tag_or_review_hr_emploc()`). `Head Admin` and `Encoder` are blocked.
     - **Deployed — Edit Emploc# & Revert to Pending**: `Encoder`, `Head Admin`, `Super Admin` ONLY (`public.can_edit_deployed_hr_emploc()`). `HR Personnel` is blocked.
   - `i_have_full_access()` must **never** be used in any gate that excludes `Head Admin`.

3. **Permanent 1:1 Employee Number Registry (`public.employee_number_registry`)**:
   - An Employee Number (`employee_no` / `emploc_no`) belongs permanently to one person across the entire ecosystem (`hr_emploc`, `plantilla`, active, inactive, resigned, or soft-deleted).
   - Person identity is matched via `public.fn_normalize_person_name` and `public.fn_match_person_name` (supporting compound first names, `MA.`/`MARIA`, multi-word surnames `DE LA`/`DELA`/`DE LOS`/`DELOS`/`DE`/`SAN`/`STO`/`STA`, stripped generational suffixes `JR`/`SR`/`II`/`III`/`IV`/`V`, middle initial matching, missing-middle-name warning `MIDDLE_NAME_CONFIRM_REQUIRED`, and registered surname aliases in `public.registry_name_aliases`).
   - Enforced under `SELECT ... FOR UPDATE` row locking:
     - **Rule a (Hard Block)**: Number registered to a different person → `EMPLOYEE_NO_ALREADY_ASSIGNED` (`23505`).
     - **Rule b (Hard Block)**: Same person already has an active `hr_emploc` (`status NOT IN ('Backout', 'Moved to Plantilla') AND deleted_at IS NULL`) or active `plantilla` (`status IN ('Active', 'On Leave', 'For Deactivation', 'Pending Deactivation', 'Rejected Deactivation') AND NOT is_deleted`) → `EMPLOYEE_ALREADY_ACTIVE` (`23505`).
     - **Rule c & Decision 1 (Rehire Confirmation)**: Same person previously owned the number and all prior records are inactive/deactivated:
       - If the **same `hr_emploc` record** and **same person** re-assigns the **same number** (e.g., after `revert_hr_emploc_to_pending`), **no rehire confirmation is required**.
       - If a **new `hr_emploc` record** of that person reuses the number, raises `REHIRE_CONFIRM_REQUIRED` (`23505`) unless `p_confirm_reuse = true` and a non-empty `p_reuse_reason` are supplied; upon confirmation, registry status becomes `'rehire_reused'`.
     - **Rule d (Duplicate Person Warning)**: Same person already owns a different number in `employee_number_registry` → raises `POSSIBLE_DUPLICATE_PERSON` (`23505`) unless `p_confirm_reuse = true` and `p_reuse_reason` are supplied.
   - **Decision 2 (Typo Release)**: When `employee_no` is edited on a Deployed record (in either table update order: `hr_emploc` → `plantilla` or `plantilla` → `hr_emploc`), `trg_sync_deployed_employee_no_fn()` releases the old number (`status = 'released'`) **only if** it was first assigned to this same record (`status = 'assigned'`), no other `hr_emploc` or `plantilla` row ever referenced it, and the actor is `Encoder`, `Head Admin`, or `Super Admin`. Otherwise, the old number stays reserved.

4. **Strict Required Plantilla Fields & `ops_remarks` Isolation**:
   - `_assign_and_deploy_emploc_core` validates all required Plantilla fields (`hired_date`, `position`, `account`/`account_id`, `store_id`/`store_name` for stationary, and applicant `first_name`/`last_name`) before writing. Missing fields raise `FIELD_REQUIRED_MISSING: <field>` (`22023`) and roll back the entire transaction. Silent defaults (`CURRENT_DATE`, `'Unspecified'`, name splitting) are forbidden.
   - `hr_emploc.ops_remarks` comes **exclusively** from Ops correction submissions (`submit_correction` / `submit_hrco_correction_update`) and is never inherited from `vacancies.remarks`.
