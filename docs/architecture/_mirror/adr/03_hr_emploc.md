<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-HREmploc. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/03_hr_emploc.md
source_commit: 8df2f62 2026-11-24T23:07:07+08:00
source_sha256: 023b59f68aa11b3941b4705dbaef7a20393dd6694617227683fa4fa3b59cb14a
synced_at: 2026-11-26T02:11:10.785Z
-->
# HR Emploc Module Architecture (Onboarding Compliance & Import Lifecycle)

- **Status:** ACCEPTED & LOCKED
- **Scope:** Five Operational Queues, Emploc Number Ownership, Atomic Plantilla Deployment, 4 Canonical Statutory Requirements, 3-Day Storage Purge, Deployed Reverts, and SLA Clock.

---

## HR Emploc (Onboarding Compliance & Import Lifecycle)

### Core Pipeline & Lifecycle

The HR Emploc module bridges candidate onboarding confirmation and official deployment as an active employee:

```
Vacancy (Confirmed Onboard) → HR Emploc (Onboarding Compliance) → Plantilla (Official Active Employee)
```

For batch spreadsheet uploads, the lifecycle strictly follows:

```
HC Request approved
        ↓
Plantilla Vacancy Slot created
        ↓
Vacancy opens (Open / Pipeline)
        ↓
Employee gets hired
        ↓
HR Emploc Import (references VCode → occupies existing slot)
        ↓
Employee appears in HR Emploc
        ↓
Vacancy automatically closes
```

### Rule 1 — Slot-First Architecture

HR Emploc Import shall always require a valid Plantilla Slot identified by a VCode. No Plantilla Slot means no HR Emploc Import. HR Emploc Import may only occupy an existing Plantilla vacancy slot. It does not create workforce capacity.

### Rule 2 — HR Emploc Import Never Creates Capacity

HR Emploc Import must never: create Plantilla Slots, create Vacancy records, increase Required HC, or bypass the Plantilla lifecycle. Its sole responsibility is to occupy an existing open slot and advance the employee into the HR Emploc stage.

### Rule 3 — Slot Authority via VCode (Plantilla Slot is the Source of Truth, Referenced by VCode)

HR Emploc Import shall always require a valid Plantilla Slot identified by a VCode. Approval occupies the existing Plantilla Slot and preserves the VCode throughout the employee lifecycle. Physical rows in `public.plantilla_slots` remain the actual authoritative source of truth for workforce demand and slot capacity; the VCode serves as the canonical human-readable reference linking the store requisition to its underlying plantilla slot(s). Every HR Emploc Import row references exactly one VCode. That VCode resolves the Plantilla Slot, Group, Account, Store, and Position. All attributes must be validated against the Plantilla Slot — never derived from manually uploaded column values. Every HR Emploc record must remain linked to a valid Plantilla Slot through its assigned VCode. HR Emploc records without a corresponding Plantilla Slot are prohibited. Historical implementations may have allowed HR Emploc records without linked Plantilla Slots — this behavior is deprecated and must not be reintroduced.

### Rule 4 — Valid Slot States for Import

Import is permitted only when the Plantilla Slot is in one of these states: `open`, `pipeline` or `hr_processing`. Import must be rejected when the slot is: `occupied` (already has an active occupant), `archived`, `closed`, `hc_reduced`, or non-existent for the given VCode.

### Rule 5 — Approval Behavior

When an import batch is approved: one HR Emploc record is created per valid row; the corresponding Plantilla Slot is marked occupied; the corresponding Vacancy is closed (status → Filled); the VCode is preserved on the HR Emploc record; the full audit history is preserved. Duplicate HR Emploc records and duplicate slot occupancy are never permitted.

### Rule 6 — Validation Error Messages

Validation must never return a generic error. Every rejection must state the exact reason, including: VCode not found, Plantilla slot not found, VCode belongs to another group, Slot already occupied, Slot archived, Slot closed, Position mismatch, Store mismatch.

### Rule 7 — Single Occupancy

One Plantilla Slot may have only one active occupant at any time. Duplicate occupancy must be rejected before any record is committed.

### Rule 8 — Audit Trail

Every import event must preserve the identity of who uploaded, who approved, when the import occurred, which employee was imported, which VCode was used, and what the previous vacancy status was. Audit records must never be overwritten or deleted.

### Forbidden Patterns

- Accepting an import row without a resolvable VCode and Plantilla Slot
- Creating a new Plantilla Slot from import approval
- Creating a new Vacancy from import approval
- Bypassing slot state validation
- Importing into an occupied, archived, closed, or non-existent slot
- Returning generic validation errors in place of field-specific messages

### Vacancy Closure on HR Emploc Import

Vacancy represents the open demand surface for a Plantilla Slot. When HR Emploc Import occupies the slot, the corresponding vacancy must close automatically.

| Event | Vacancy State Change |
|-------|----------------------|
| HC Request approved | Vacancy created (`Open`) |
| Applicant enters pipeline | Vacancy → `Pipeline` |
| HR Emploc Import approved (slot occupied) | Vacancy → `Filled` |
| Import rolled back | Vacancy re-opened if slot is unoccupied |

### Five Operational Queues (Status Tabs Architecture)

**Status: ACCEPTED.** Codifies the standard onboarding queues in HR Emploc across Web and Mobile:

1. **Tab 1: Pending** (`status = 'Pending Emploc'` AND `hr_status = 'Pending'`): Operational requirements intake. Field Ops coordinators in scope (OM, TL, ATL, HRCO) and Super Admin upload candidate compliance documents to private storage bucket `hr-corrections`. Advancing to `For Emploc` via `submit_hr_emploc_requirements` strictly requires at least 1 uploaded document.
2. **Tab 2: For Emploc** (`status = 'Pending Emploc'` AND `hr_status = 'For Emploc'`): Deployment readiness queue. Requirements are verified and the record is ready for Emploc ID assignment.
   - Primary Actions: `+ Add Emploc` (assigns employee number and auto-deploys to Plantilla) and `! Tag Deficiency` (returns record to `For Correction`).
   - Document upload/removal is strictly disabled on this tab.
3. **Tab 3: Correction** (`hr_status = 'For Correction'`): Deficiency queue. Displays deficient documents returned to field coordinators. In-scope Ops coordinators re-upload corrected compliance files and resubmit to review (`submit_hrco_correction_update`), transitioning the record to `For Review`.
4. **Tab 4: Review** (`hr_status = 'For Review'`): Review queue for corrected resubmissions. Authorized reviewers evaluate the resubmission to either `Approve` (assigns Emploc ID and auto-deploys to Plantilla in same transaction) or `Return to Correction`.
5. **Tab 5: Deployed** (`status = 'Moved to Plantilla'` OR `hr_status = 'Transferred'` with `deleted_at IS NULL`): Historical and audit queue for records assigned an Employee ID and deployed to Plantilla.
   - Actions: `Edit Emploc` and `Revert to Pending` (Data Team & Super Admin only).
   - SLA timer freezes displaying `Completed in X days`.

### Emploc Number Assignment Ownership (HR Personnel Primary, Data Team Backup)

**Status: ACCEPTED.** Governs operational roles and responsibilities for assigning Employee Numbers (`employee_no` / `emploc_no`):

1. **Primary Operational Owner — HR Personnel**:
   - **HR Personnel** is the primary, dedicated authority responsible for verifying candidate compliance documents and assigning Employee Numbers in the `For Emploc` and `Review` queues.
2. **Operational Backup — Data Team (Head Admin & Encoder)**:
   - **Data Team** (Encoder and Head Admin) serves as operational backup. They are fully authorized to step in and assign Employee Numbers (`+ Add Emploc`) when candidate volume is high or when HR Personnel is heavily loaded, ensuring onboarding throughput is never throttled.
   - Head Admin and Encoder remain strictly BLOCKED from tagging deficiencies (`Tag Deficiency`) or reviewing corrected documents (`Review Return`), preserving HR compliance integrity.
3. **Super Admin**: Retains full administrative override capability across all queues and workflows.

### Atomic Deployment to Plantilla & Permanent Employee Number Registry (Rules a–d)

**Status: ACCEPTED.** Enforces transaction safety and 1:1 lifetime identity governance:

1. **Atomic Deployment (`_assign_and_deploy_emploc_core`)**:
   Assigning an Employee Number (via `assign_hr_emploc_number` on Pending/For Emploc or via `review_web_hr_emploc_correction` on Review) executes atomically in the **exact same database transaction**:
   - Validates `/^[A-Za-z0-9._-]+$/` employee number format.
   - Asserts permanent 1:1 ownership in `public.employee_number_registry` under the four registry lock rules below.
   - Transitions the linked `plantilla_slots` row to `slot_status = 'occupied'` (`current_occupant_plantilla_id = plantilla.id`).
   - Inserts the new active `public.plantilla` employee record (`status = 'Active'`).
   - Updates `public.hr_emploc` to `status = 'Moved to Plantilla'` and `hr_status = 'Transferred'`, recording `moved_to_plantilla_at = now()`.
   - Closes the corresponding vacancy slot and generates a unified audit trail entry.
2. **Permanent Employee Number Registry Lock Rules (under `SELECT FOR UPDATE`)**:
   - **Rule a (Hard Block)**: If the number is already assigned to a different person (evaluated via normalized full name) $\rightarrow$ raises `EMPLOYEE_NO_ALREADY_ASSIGNED` (`23505`).
   - **Rule b (Hard Block)**: If the same person already has an active placement or active Plantilla record with that number $\rightarrow$ raises `EMPLOYEE_ALREADY_ACTIVE` (`23505`).
   - **Rule c (Rehire Confirmation)**: If the same person was previously assigned that number but all prior records are inactive/resigned $\rightarrow$ raises `REHIRE_CONFIRM_REQUIRED` (`23505`) until `p_confirm_reuse = true` with a mandatory rehire justification is supplied.
   - **Rule d (Duplicate Warning)**: If the same person already owns a different number in the registry $\rightarrow$ raises `POSSIBLE_DUPLICATE_PERSON` (`23505`) until confirmed with reason.
3. **Strict Missing Required Fields Assertions (No Silent Defaults)**:
   - Moving to Plantilla strictly requires non-null `hired_date`, `position`, `account`/`account_id`, `store_name`/`store_id`, and applicant structured name. Silent fallbacks (`CURRENT_DATE` defaults, synthetic name splitting) are prohibited and raise `FIELD_REQUIRED_MISSING` (`23502`).

### Canonical Onboarding Compliance Requirements & 3-Day Storage Purge Queue

**Status: ACCEPTED.** Establishes required compliance artifacts and storage lifecycle:

1. **Canonical Statutory Requirements (4 items)**:
   Only four standard statutory and documentation items are recognized for onboarding compliance:
   - `INVALID_SSS`: SSS Card / ID Document (Remarks optional).
   - `INVALID_PAGIBIG`: Pag-IBIG Member ID (Remarks optional).
   - `INVALID_PHILHEALTH`: PhilHealth ID / MDF (Remarks optional).
   - `INCOMPLETE_REQUIREMENT`: Incomplete Documentation (Remarks strictly mandatory).
   *(Legacy NBI Clearance and PSA Birth Certificate are deprecated and removed from required onboarding checklists).*
2. **Three-Day Storage Purge Queue (`run_at = now() + interval '3 days'`)**:
   - Upon deployment to Plantilla, all uploaded compliance and correction documents in bucket `hr-corrections` are automatically enqueued into `storage_cleanup_queue` with a **3-day TTL**.
   - When the cleanup queue executes, physical storage objects are permanently deleted via Storage API and metadata records tagged `is_deleted = true, deleted_reason = 'deployed_3day_ttl'` for storage hygiene and PII protection.
3. **Three-Day Revert Grace Window**:
   - Data Team or Super Admin may execute `Revert to Pending` (`revert_hr_emploc_to_pending`) within the **3-day window**:
     - *Within 3 Days (Before Purge)*: The pending purge is cancelled, uploaded documents are preserved, and status is restored to `'For Emploc'`.
     - *After 3 Days (Post-Purge)*: Documents have been purged; status is restored to `'Pending'` requiring Ops to re-upload compliance documents.
   - Reverting to Pending soft-deletes the `plantilla` row, reopens the `plantilla_slots` row to `open`, and clears `employee_no = NULL`.

### Deployed Tab Revert Governance (Data Team Authority & Plantilla Cancellation)

**Status: ACCEPTED.** Codifies operational authority and atomic lifecycle mechanics when reverting records from the Deployed Tab:

1. **Role Authority (`public.can_edit_deployed_hr_emploc()`)**:
   - Only the **Data Team** (`Encoder`, `Head Admin`) and `Super Admin` are authorized to execute `Revert to Pending` (`revert_hr_emploc_to_pending`) on records in the **Deployed Tab**.
   - Field Operations coordinators (OM, TL, ATL, HRCO) and HR Personnel are strictly blocked from reverting deployed records, safeguarding active workforce rosters against unauthorized modification.
2. **Atomic Plantilla Cancellation & Disappearance**:
   - The deployed employee record in `public.plantilla` is soft-deleted and deactivated (`is_deleted = true`, `status = 'Deactivated'`). The employee **immediately disappears** from active Plantilla rosters and views (`v_plantilla_safe`).
   - Store links in `public.plantilla_store_links` are marked `status = 'Backed Out', unlinked_at = now()`.
3. **Plantilla Slot & Vacancy Reopening (Rule 1 & Rule 2)**:
   - The occupied slot in `public.plantilla_slots` is released via `public.fn_set_slot_status` back to `slot_status = 'open'` with `reason_code = 'BACKOUT'` and occupant cleared (`current_occupant_plantilla_id = NULL`).
   - The associated vacancy is reconciled and reopened (`status = 'Open'`).
4. **Restoration into HR Emploc Queues**:
   - The record returns to HR Emploc in status `status = 'Pending Emploc'` with `employee_no = NULL` and `moved_to_plantilla_at = NULL`.
   - **Queue Placement**:
     - *Within 3-Day Purge Window*: Queued storage purge is cancelled, uploaded documents are preserved, and the record is placed in **Tab 2: For Emploc** (`hr_status = 'For Emploc'`).
     - *Post 3-Day Purge Window*: If documents were already purged, the record is placed in **Tab 1: Pending** (`hr_status = 'Pending'`), requiring Operations to re-upload compliance documents.
   - The Employee Number Registry records the action in `history` (`action: 'revert_to_pending'`), releasing the number assignment while retaining full audit traceability.

### Three-Day Operational Compliance SLA Clock

**Status: ACCEPTED.** Enforces onboarding velocity and managerial escalation:

1. **SLA Calculation**: Baseline is `coalesce(date_requested, created_at)`. Threshold is **3 calendar days** (72 hours).
2. **Escalation Ladder**:
   - **SLA Tier 1 (3 Days)**: If a record has no `employee_no` assigned after 3 days, `sla_breached` evaluates to `true`. Renders prominent red alert badge in UI and dispatches notification to `Head Admin`.
   - **SLA Tier 2 (5 Days)**: Critical escalation. High-priority notification dispatched directly to `Super Admin`.

### Applicant Backout in HR Emploc & Vacancy Aging Continuity Invariant

**Status: ACCEPTED.** Governs operational backouts during HR Emploc onboarding (pre-deployment):

1. **Backout Execution (`tag_backout` / `reject_hr_emploc`)**:
   - When an applicant awaiting documentation or number assignment in HR Emploc backs out:
     - The applicant record is tagged `backout` and routes to the **Failed / Backout Tab** in Vacancy.
     - The linked slot in `public.plantilla_slots` transitions from `hr_processing` $\rightarrow$ `open` via `fn_set_slot_status(slot_id, 'open', 'BACKOUT')`.
     - The corresponding requisition immediately reappears in the **Vacancy Open Tab** (`remaining_open` increments).
2. **Original Vacancy Aging Continuity (Anti-Reset Lock)**:
   - When a slot returns to Open following an HR Emploc backout, its vacancy aging (`aging_days`, `aging_start_at`) **MUST NOT RESET** to the backout timestamp or `CURRENT_DATE`.
   - The aging clock preserves unbroken continuity from the **original date the position became vacant** (`vacant_date` / start of the vacancy episode when the prior employee separated or when the requisition was first created).
   - This ensures operational KPIs, aging alert badges (30d/60d), and executive dashboards truthfully report cumulative store vacancy duration without masking delays caused by applicant dropouts during onboarding.

---
