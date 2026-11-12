# HR Emploc Web State & Architecture Specification

## 1. Scope & Core Purpose

This document specifies the target architecture, visual structures, data contracts, and user workflows for the **HR Emploc Web** module of the OHMployee Web dashboard. 

The **HR Emploc** module sits at a critical junction in the hiring pipeline. It bridges the gap between candidate onboarding confirmation and official deployment as an active employee. The canonical pipeline flows as follows:

```
Vacancy → Applicant → Endorsed to Ops → Confirmed Onboard → HR Emploc (Onboarding Compliance) → Plantilla Approval (Movement) → Plantilla (Official Active Employee)
```

The core responsibilities of the HR Emploc Web module are:
1. **Onboarding Compliance & Audit**: Tracking the upload and validation of compliance requirements for newly hired candidates.
2. **Deficiency & Correction Workflows**: Flagging missing or incorrect documents, managing communication between HR Personnel and assigned field coordinators (HRCOs) for corrections, and validating uploaded files.
3. **Deployment Readiness**: Finalizing records by assigning official `employee_no` values.
4. **Plantilla Transition**: Transitioning fully validated, complete records to the **Plantilla** directory as official active employees.

Like all modules in OHMployee Web, this is a thin admin-panel presentation layer. **Supabase remains the absolute authority** for data access scopes, workflow states, RLS, push notification triggers, and transactional mutations.

---

## 2. Queue & Status Architecture

The administrative dashboard organizes employee placement records into distinct queues using **Status Tabs**. These queues are driven by two database fields:
* `hr_status`: Tracks the HR compliance workflow state (`Pending`, `For Emploc`, `For Correction`, `For Review`, `Complete`, `Rejected`, `Transferred`).
* `status`: Tracks the deployment lifecycle (`Pending Emploc`, `Moved to Plantilla`, `Backout`).

To facilitate rapid filtering and administrative scanning, the UI implements 5 tab-controlled queues, each with a live badge count:

| Queue Tab | Database Conditions | Primary Purpose / Administrative Action |
| :--- | :--- | :--- |
| **Pending** | `status = 'Pending Emploc'` AND `hr_status = 'Pending'` | Operational requirements intake queue. Ops coordinators in scope (OM, TL, ATL, HRCO) + Super Admin upload compliance documents to private bucket `hr-corrections`. Advancing to `For Emploc` via `submit_hr_emploc_requirements` requires at least 1 document uploaded. Assigning Emploc ID directly from Pending is restricted to Super Admin override ONLY (`can_assign_pending_hr_emploc()`); all other roles wait for `hr_status = 'For Emploc'`. Tag Deficiency is BLOCKED on Pending (requires For Emploc). |
| **For Emploc** *(NEW)* | `status = 'Pending Emploc'` AND `hr_status = 'For Emploc'` | Deployment readiness queue (requirements uploaded and verified, waiting ONLY for Emploc ID). Actions: `+ Add Emploc` (allowed for HR Personnel, Head Admin, Encoder, Super Admin; atomically assigns Emploc ID and auto-moves to Plantilla) and `! Tag Deficiency` (allowed for HR Personnel and Super Admin ONLY; Head Admin and Encoder blocked; moves record to `For Correction`). Document upload/removal by Ops is blocked. |
| **Correction** | `hr_status = 'For Correction'` | Deficiency correction queue. Displays deficient documents returned to field coordinators. Actions: In-scope Ops upload compliance attachments (stage `correction`) and submit correction to review (`submit_hrco_correction_update`; moves to `For Review`). HR Personnel, Head Admin, and Encoder blocked. |
| **Review** | `hr_status = 'For Review'` | Review queue for corrected submissions. Actions: Approve (HR Personnel and Super Admin ONLY; Head Admin and Encoder blocked. Atomically assigns Emploc ID and auto-moves to Plantilla in same transaction) or Revert/Return to Correction. Remarks column displays Ops coordinator correction remarks (`ops_remarks`) only. |
| **Deployed** | `status = 'Moved to Plantilla'` OR `hr_status = 'Transferred'` (with `deleted_at IS NULL`) | Historical & audit queue for records assigned an Employee ID and deployed to Plantilla. Actions: `Edit Emploc` (Data Team: Encoder, Head Admin + Super Admin ONLY; HR Personnel blocked) and `Revert to Pending` (Data Team + Super Admin ONLY with required reason; soft-deletes Plantilla row, re-opens slot). **3-Day Storage Purge Queue**: Deployment automatically enqueues all uploaded requirement/correction docs for permanent storage purge in 3 days (`run_at = now() + interval '3 days'`). If reverted within the 3-day grace window before docs are purged, the queued purge is cancelled and `hr_status` is restored to `'For Emploc'`; if reverted after docs have been purged, `hr_status` is restored to `'Pending'` (Ops re-uploads). View docs is blocked for all roles once deployed. SLA timer is frozen with `Completed in X days`. |

---

## 3. KPI Metric Structure

The KPI summary bar sits above the main grid to provide immediate insight into workload and bottlenecks. These cards are strictly restricted to a height of `h-[100px]` (to prevent Layout Shifts during loading) and are mapped as follows:

1. **Total Processing (`Pending Review` Count)**
   - *Formula*: Counts records with `hr_status IN ('Pending', 'For Review')` and `deleted_at IS NULL`.
   - *Visual Badge*: `info` (Soft blue) representing active workload.
2. **Action Needed (`For Correction` Count)**
   - *Formula*: Counts records with `hr_status = 'For Correction'`.
   - *Visual Badge*: `warning` (Soft amber) indicating blockers.
3. **Ready to Deploy (`Complete` Count)**
   - *Formula*: Counts records with `hr_status = 'Complete'` and `employee_no IS NULL`.
   - *Visual Badge*: `success` (Soft green) representing backlog ready for number assignment.
4. **SLA Breach Watch**
   - *Formula*: Counts records where `sla_breached = true` as defined by the canonical SLA view:
     ```sql
     (deleted_at IS NULL) AND (employee_no IS NULL) AND (status IN ('Pending Emploc', 'Pending Requirements', 'For Compliance', 'In Review')) AND (coalesce(date_requested, created_at) < (now() - '3 days'::interval))
     ```
   - *Visual Badge*: `danger` (Soft rose) highlighting critical compliance breaches (records lagging past the 3-day window).

---

## 4. Dense Table Layout & Column Structure

Admin users must scan hundreds of incoming recruits. We enforce the **Compact Grid** layout standard (`py-2 px-3`, cells `text-sm`, headers `text-xs uppercase font-semibold text-gray-500`) to maximize information density:

```
[Main Grid Viewport (Scrollable horizontally if needed, min-width: 1120px)]
-----------------------------------------------------------------------------------------------------------------------------
Candidate Name  | VCode   | Account / Location         | Assignment | HR Status    | Deficiency Summary | SLA Age | Actions
-----------------------------------------------------------------------------------------------------------------------------
Santos, Maria   | VAC-042 | Cebu Regional / Cebu Mall  | Stationary | For Review   | (None)             | 1 Day   | [Eye]
Cruz, Juan      | VAC-099 | Manila Region / Hub 1      | Roving (3) | Deficiency   | NBI, Birth Cert    | 4 Days  | [Eye] [SLA Warn]
Del Rosario, A. | VAC-101 | Davao South / Davao Hub    | Stationary | Pending Del  | backout request    | 2 Days  | [Eye] [Lock]
```

### Table Columns Mapping:
1. **Candidate Name**: Combined `applicant_name_snapshot` (or `applicant_name`).
2. **Vacancy Code**: `vcode` (Rendered in monospaced style: `font-mono text-xs text-gray-700 bg-gray-50 border border-gray-100 rounded px-1.5 py-0.5`).
3. **Account & Location**: Displayed hierarchically as `account` / `store_name`.
4. **Assignment Type**: 
   - `assignment_type` ('Stationary' or 'Roving'). 
   - If 'Roving', include a hoverable tooltip badge showing the count of stores listed in `covered_stores` (e.g., `Roving (3)`).
5. **HR Status Badge**: Maps `hr_status` to a unified semantic color scheme using `StatusBadge`:
   - `Pending` / `For Review` → `info` (blue)
   - `For Emploc` → `brand` / `info` (blue)
   - `For Correction` → `warning` (amber)
   - `Complete` → `success` (green)
   - `Pending Deletion` → `danger` (rose)
   - `Transferred` / `Rejected` → `neutral` (gray)
6. **Deficiency Summary**: High-level text listing deficient items extracted from `correction_reason` JSONB.
7. **SLA Counter**: Calculated days active since `coalesce(date_requested, created_at)`. If exceeding 3 days, it prints a rose alert badge (`text-red-700 bg-red-50 border-red-200`).
8. **Actions Area**: Desktop actions per queue tab, 100% driven by `row_capabilities`. Actions column uses `sticky right-0` to eliminate horizontal clipping on wide viewports:
   - **Pending Tab**: `Upload Docs` (driven by `can_upload_docs`). `+ Add Emploc` / `! For Correction` are removed here; SA override `+ Add Emploc` resides in row overflow menu via `can_assign_employee_no`.
   - **For Emploc Tab**: `+ Add Emploc` (driven by `can_assign_employee_no`) and `! For Correction` (driven by `can_tag_deficiency`).
   - **Correction & Review Tabs**: Position and HRCO columns removed to allocate space for Reasons (rendered in flex-wrap gap-1.5 badges without truncation) and Remarks (rendered with Ops remark precedence). Attachment column provides `View` button with document count.
   - **Deployed Tab**: Actions menu provides `Edit Emploc #` (driven by `can_edit_emploc_number`) and `Revert to Pending` (driven by `can_revert_to_pending`). Document viewing is hidden once deployed.
   - Row clicking opens the Detail Drawer with active overlay highlight (`bg-blue-50`).

### 4.1 Stage 2b-Web Implementation Details (ohm#q3v8n2kd)
1. **Capability-Driven Architecture**:
   - Zero hardcoded role name checks in frontend components; every action button and menu item strictly inspects `row.capabilities` (`can_upload_docs`, `can_assign_employee_no`, `can_tag_deficiency`, `can_edit_emploc_number`, `can_revert_to_pending`, `can_view_docs`).
   - Missing capabilities default to `false`.
2. **Sequential Multi-File Upload & Compression**:
   - Implemented `UploadDocsModal.tsx` supporting PDF, JPEG, PNG, WEBP files up to 10MB each.
   - Client-side Canvas image compression for JPEG/PNG/WEBP downscaling to max 1600px width/height at 0.75 quality without upscaling (PDFs bypass compression untouched).
   - Sequential pipeline: `authorize_hr_emploc_doc_upload` -> Supabase Storage upload -> `register_hr_emploc_document` with server-derived stage (`initial_requirements` or `correction`).
   - Idempotent upload tracking: duplicate registration returns existing row without error.
   - Unverified document deletion: uploader can remove unverified uploads via `can_remove` flag.
   - Advancing Pending to For Emploc via `submit_hr_emploc_requirements` requiring >= 1 uploaded document.
3. **Multi-File Document Preview**:
   - Implemented `DocumentPreviewModal.tsx` featuring multi-file thumbnail switcher, zoom (0.5x to 3.0x), 90-degree rotation, PDF iframe viewer, and short-TTL (5-10m) signed URL generation with direct download.
4. **Single-RPC Deployment & Interactive Confirmation**:
   - Replaced multi-step deployment with atomic single-RPC assignment (`assign_hr_emploc_number`).
   - Interactive confirmation dialog for `REHIRE_CONFIRM_REQUIRED`, `POSSIBLE_DUPLICATE_PERSON`, and `MIDDLE_NAME_CONFIRM_REQUIRED` prompting user for reuse justification and retrying with `confirmReuse: true`.
5. **Standardized Error Mapper (`hr_emploc_errors.ts`)**:
   - Unified parser prioritizing Postgres `DETAIL` code first (`json.code`), message token prefix second (`TOKEN:`), and SQLSTATE fallback third.
   - Unit-tested with 100% pass rate.

### Onboarding Compliance Requirements
Only canonical statutory and documentation requirements are tracked for deficiency:
1. `INVALID_SSS`: SSS Card / ID Document (Remarks Optional)
2. `INVALID_PAGIBIG`: PagIBIG Member ID (Remarks Optional)
3. `INVALID_PHILHEALTH`: PhilHealth ID / MDF (Remarks Optional)
4. `INCOMPLETE_REQUIREMENT`: Incomplete Docs (Remarks Strictly Required)
*(NBI Clearance Certificate and PSA Birth Certificate have been removed).*

Validation Rule:
- Multiple selections are supported across all four requirements.
- When only benefits (`SSS`, `PagIBIG`, `PhilHealth`) are selected, remarks are optional.
- When `Incomplete Docs` is selected, overall HR Compliance Remarks is strictly required before submission.
- In `HrEmplocTable`, the Deployed tab displays a dual stacked column under header `Emploc ID | Applicant (separate columns)` (monospace bold employee ID on top, applicant name underneath).
- In the Review queue, the column is named `Remarks` (displaying latest Ops correction remarks from `ops_remarks` projected via `row_capabilities`, rendering standard muted `--` placeholder when empty), and `Attachment` renders an icon-only download button (`Download` icon with tooltip/aria-label, excluding filename text) for uploaded compliance documents.

---

## 5. Detail Drawer UX & Content Structure (Exact 8-Section Order)

When a row is selected, the desktop Detail Drawer slides overlaying the grid from the right (`DetailDrawer`, `w-[var(--drawer-width-lg)]`). It enforces the following exact top-to-bottom section order:

1. **Drawer Header**:
   - `VCode` badge (e.g., `VAC-2026-0042`).
   - `Applicant Full Name` (strikethrough when locked for deletion).
   - `📍 Account / Store` breadcrumb.
2. **Status Summary Cards (2-Column Grid)**:
   - `Deployment status`: `Pending Emploc`, `Deployed to Plantilla`, or `Deletion Requested`.
   - `HR status`: `Pending`, `For Correction`, `Deployed`.
3. **Placement Parameters Card**:
   - `Vacancy Code (VCode)`, `Account`, `Store / Location`, `Assignment Type`, `Position Title`, `HRCO Coordinator` (inherited from User Management Group/Account matrix via `<InheritedHrcoBadge />`), `Hired Date`, and `Employee ID` (rendered with prominent badge when assigned).
   - Covered stores list if `Assignment Type = 'Roving'`.
4. **SLA & Aging Performance Card**:
   - `Elapsed Compliance Time`: Freezes once deployed and displays `Completed in X days`. Active records display `X Days`.
   - `Baseline Request Date`: Formatted baseline date.
   - SLA breach alert badge & Tier 1/2 escalation notifications (active only while in progress).
5. *(Completely Removed: "Onboarding Requirements Compliance" checklist)*:
   - The document checklist (SSS, Pag-IBIG, PhilHealth, NBI, PSA) has been completely removed from the drawer.
6. **Requirements & Correction Documents Card**:
   - Placed directly below SLA & Aging Performance.
   - Shows uploaded requirement and correction files with one-click signed URL download links, uploader metadata, stage (`requirement` or `correction`), and file sizes.
   - Storage architecture:
     - Private Supabase bucket `hr-corrections`.
     - Standardized path: `emploc-docs/{record_id}/{timestamp}_{sanitized_filename}`.
     - Document metadata tracked in `public.hr_emploc_correction_attachments` (extended with `stage`, `deleted_at`, `deleted_reason`).
     - Upload permitted strictly for Ops coordinators within account/store scope (OM, TL, ATL, HRCO) + Super Admin while the record is in `Pending` or `For Correction`.
     - Ops uploaders may remove only their own uploaded files (Super Admin override) while the record is in `Pending` or `For Correction`.
     - Viewing documents permitted for HR Personnel, Head Admin, Encoder, in-scope Ops (OM, TL, ATL, HRCO), and Super Admin, but strictly BLOCKED for everyone once the record is Deployed.
     - 3-day document purge queue: upon deployment, documents are enqueued into `storage_cleanup_queue` with a 3-day TTL. When the queue runs via pg_net and cron, the physical storage objects are deleted via Storage API and metadata rows marked `is_deleted = true, deleted_reason = 'deployed_3day_ttl'`. Reverting to Pending within the 3-day window cancels the queued purge.
7. **Specific Activity History Trail Card**:
   - Replaces generic "Status Updated" placeholders with human-readable, event-specific logs:
     - Creation/Endorsement: `"Added to HR Emploc Queue ([Position] – [Store]) from Vacancy [VCode] by [Actor Name]"`
     - HRCO Assignment: `"Assigned HRCO [HRCO Name(s)] via [Group] ([Account]) matrix"`
     - Flagged for Correction: `"Flagged for Correction ([Deficiency/Remarks]) — Moved to Correction by [Actor Name]"`
     - Emploc & Deployment: `"Assigned Employee ID [ID] and deployed to Plantilla ([Store]) by [Actor Name]"`
     - Edit / Revert: `"Updated Employee ID from [Old ID] to [New ID] (Reason: [Reason]) by [Actor Name]"` / `"Reverted from Deployed to Pending and removed from Plantilla by [Actor Name]"`
     - Deletion Request / Withdrawal: `"Requested Deletion (Reason: [Reason]) by [Actor Name]"` / `"Withdrew Deletion Request and restored to Pending Emploc by [Actor Name]"`
8. **Available Actions Card (Scoped to Deletion Flow)**:
   - Section header: `Available Actions` (removed all internal debug capability rows).
   - Role restriction: Restricted to Ops (`OM` - `HRCO`) and `Super Admin`. Data Team and other roles view locked banner (`"Restricted to Ops (OM - HRCO) personnel"`).
   - Guardrail: Locked if record is `Deployed` (`"Record is deployed. To request deletion, first revert the record to Pending using Edit Emploc > Revert to Pending"`).
   - State A (No active request): `Request Deletion` button opening inline dropdown with:
     - Reason: `Applicant Backed Out`, `Duplicate / Wrong Endorsement`, `Failed Store Deployment`
     - Required specific remarks/justification textarea
     - Submit button `Confirm & Submit Request`
   - State B (Active deletion request exists):
     - Amber summary banner: `"Active Deletion Request: [Reason] — Submitted by [Requester] on [Date]"`
     - Action button: `Withdraw Request` (with confirmation dialog).

---

## 6. Status Workflows & SLA Breach Rules

The backend enforces strict transition pathways and timings. The frontend visualizes these states explicitly:

### SLA Breach Clock
- **Calculation**: Baseline is `coalesce(date_requested, created_at)`.
- **Threshold**: **3 Days** (72 hours).
- **Behavior**: If the record has no `employee_no` assigned and status is pending compliance after 3 days, `sla_breached` transitions to `true`.
- **System Escalation Levels**:
  - **SLA Tier 1 (3 Days)**: Marked in red in the web table. Highlighted in the detail drawer. Trigger alert sent to `Head Admin`.
  - **SLA Tier 2 (5 Days)**: Critical flag. Trigger alert escalated to `Super Admin`.

### Correction & Review Cycle
```
[Pending] ──(Deficiency Found)──> [For Correction]
   ▲                                     │
   │                              (HRCO Uploads Docs)
   │                                     ▼
[For Review] <───────────────────────────┘
```
1. **Tagging Deficiency**: HR Personnel identifies blurry/missing files. They check deficiency tags (from `hr_emploc_issue_types`), add remarks, and set state to `For Correction` (this writes the `correction_reason` JSONB block).
2. **Correction Notification**: A push trigger notifies the coordinator (`trg_notify_hr_emploc_correction_tagged`).
3. **Resolution**: Coordinator uploads valid attachments to `hr_emploc_correction_attachments` and triggers an update RPC. The state moves to `For Review` and triggers `trg_notify_hr_emploc_correction_submitted` to alert the HR Personnel. *(This upload step is an ops/Mobile RPC and is out of scope for the web mutation layer.)*
4. **Finalization (Correction Review — second web mutation, architected OHM2026_1110, updated ohm#7k4w9xqn)**: HR Personnel (or Super Admin) reviews the `For Review` resubmission via `review_web_hr_emploc_correction(...)` (or `approve_correction_request(...)` on mobile). Head Admin and Encoder are strictly blocked (`42501`). Under the **strict all-deficiencies-resolved model**, the reviewer affirms each tagged deficiency:
   - **Approve** (every deficiency resolved + mandatory Emploc ID) → `employee_no` / `emploc_no` is assigned and the record is **atomically deployed to Plantilla in the same transaction** via `_assign_and_deploy_emploc_core` (validates `/^[A-Za-z0-9._-]+$/` format, permanent 1:1 ownership in `employee_number_registry` under Rules a/b/c/d + Decision 1, required Plantilla fields without silent defaults, slot reservation and `occupied` transition), setting `status = 'Moved to Plantilla'`, `hr_status = 'Transferred'`, `moved_to_plantilla_at = now()`, clearing `correction_reason`, saving `hr_remarks` while preserving `ops_remarks`, and writing a single `assign_and_deploy_to_plantilla` audit entry. Record transitions directly from Review tab to Deployed tab (there is no `Ready for Plantilla` or `Complete` ready state).
   - **Return** (residual deficiencies remain) → `hr_status = 'For Correction'`, `correction_reason` rewritten to the residual keys, HRCO re-notified. The loop repeats until clean.
   See `docs/state/web_mutation_workflow_state.md` Part II (§10–§18) and `docs/proposals/adr-001-workflow-update.md` for the full backend-authoritative contract.

---

## 7. Approval, Correction, and Deletion Flows

Mutations inside the HR Emploc module are strictly transaction-safe. The web interface relies on safe RPC handlers for the following critical workflows:

### A. Assigning Employee Number & Atomic Deployment to Plantilla
* **Pre-conditions**: `status = 'Pending Emploc'` (on Pending tab via `assign_hr_emploc_number`) or `hr_status = 'For Review'` (on Review tab via `review_web_hr_emploc_correction` / `approve_correction_request`), all required Plantilla fields present (`hired_date`, `position`, `account`, `store` for stationary, applicant `first_name` & `last_name`), and no pending deletion requests.
* **Role Check**:
  - **Pending (`assign_hr_emploc_number`)**: Restricted to `HR Personnel`, `Head Admin`, `Encoder`, and `Super Admin` (`public.can_assign_pending_hr_emploc()`).
  - **Review (`review_web_hr_emploc_correction`, `approve_correction_request`)**: Restricted to `HR Personnel` and `Super Admin` ONLY (`public.can_tag_or_review_hr_emploc()`). `Head Admin` and `Encoder` are blocked (`42501`).
* **Execution**: Both paths call `public._assign_and_deploy_emploc_core(...)`, which locks and validates `public.employee_number_registry` (Rules a, b, c, d + Decision 1), occupies the linked `plantilla_slots` row (`slot_status = 'occupied'`), inserts the active `public.plantilla` record (`status = 'Active'`), updates `hr_emploc` to `status = 'Moved to Plantilla'` and `hr_status = 'Transferred'`, and logs a single unified audit trail entry.

### B. Legacy `move_to_plantilla` Wrapper & Deployed Revert/Edit
* **`move_to_plantilla(uuid)`**: Retained as an idempotent wrapper for backwards compatibility. If the record is already `Moved to Plantilla`, it returns the existing `plantilla` row as a no-op; otherwise it delegates to `_assign_and_deploy_emploc_core` gated by `can_assign_pending_hr_emploc()`.
* **Deployed Edit (`update_deployed_employee_id`) & Revert (`revert_hr_emploc_to_pending`)**: Restricted to Data Team (`Encoder`, `Head Admin`) and `Super Admin` ONLY (`public.can_edit_deployed_hr_emploc()`). `HR Personnel` is blocked (`42501`). `revert_hr_emploc_to_pending` soft-deletes the `plantilla` row, reopens the `plantilla_slots` row, resets `hr_emploc` to `Pending Emploc` / `Pending` (`employee_no = NULL`), and keeps the employee number reserved to that person in `employee_number_registry` (so re-assigning the same number on the same `hr_emploc` record requires no rehire confirmation per Decision 1).

### C. Requesting Deletion (The Operational Separation Gate)
If a candidate backs out or is found to be a duplicate prior to final Plantilla deployment, Ops roles (`om`, `hrco`, `atl`, `tl`) must trigger a deletion request.
* **Pre-conditions**: Record must not be in Plantilla already. No pending deletion requests must exist.
* **Flow**:
  1. User selects `deletion_type`:
     - **Backout**: Applicant backed out. Approving this **archives the applicant** and **reopens the Vacancy slot** (resets `vacancies.status = 'Open'`).
     - **Duplicate Record**: Administrative fix. Requires inputting the valid `original_emploc_id` of the actual employee record. Approving this archives the duplicate record but does **NOT** reopen the vacancy slot.
  2. The RPC `fn_request_emploc_deletion` is triggered, setting `hr_status = 'Pending Deletion'` (acting as an edit-lock overlay) and saving the candidate snapshot.
  3. Action is locked: All edits, corrections, number assignments, and plantilla movements are **strictly locked** while status is `Pending Deletion`.
  4. Approvals/Rejections are routed to Encoders/Admins. Rejections restore the original `hr_status` overlay. Approvals archive the Emploc record.

---

## 8. Scoped RBAC Visibility

Web presentation utilizes capability keys returned by `get_web_current_user_context()`. The Supabase backend enforces these boundaries on all queries:

```
                         [Role Access Matrix - Authoritative]
=============================================================================
Role             | Read Scope       | Mutations (RPCs Allowed)
=============================================================================
superAdmin       | Global           | Full approvals, assignments, deletion overrides (All)
-----------------------------------------------------------------------------
headAdmin        | Global           | Pending Assign (+auto-move), Deployed Edit Emploc,
                 |                  | Deployed Revert to Pending
                 |                  | (BLOCKED: Tag Deficiency, Review Approve/Return!)
-----------------------------------------------------------------------------
Encoder          | Scoped           | Pending Assign (+auto-move), Deployed Edit Emploc,
                 | (Allowed Accts)  | Deployed Revert to Pending
                 |                  | (BLOCKED: Tag Deficiency, Review Approve/Return!)
-----------------------------------------------------------------------------
hrPersonnel      | Global           | Pending Assign (+auto-move), Tag Deficiency,
                 |                  | Review Approve (+auto-move) & Return
                 |                  | (BLOCKED: Deployed Edit Emploc, Deployed Revert)
-----------------------------------------------------------------------------
om / hrco        | Scoped / Global  | Correction Submit (`submit_hrco_correction_update`,
                 | (Allowed Accts / | `submit_correction`), request Deletions
                 |  All Scope)      | (BLOCKED: Assign, Tag, Approve, Edit Deployed)
-----------------------------------------------------------------------------
atl / tl         | Scoped           | Correction Submit (`submit_correction`), scoped read
                 |                  | (BLOCKED: Assign, Tag, Approve, Edit Deployed)
-----------------------------------------------------------------------------
viewer           | Scoped           | Read-only (Read RPCs only, all mutations blocked)
=============================================================================
```

### Permanent Emploc# Ecosystem Registry & Rules
1. **1:1 Lifetime Ownership**: An Employee Number belongs to one person permanently. Person identity is determined by normalized full name (Last, First, Middle) via `fn_normalize_person_name`.
2. **Atomic Move to Plantilla**: Whenever an Emploc# is assigned (from Pending via `assign_hr_emploc_number` or from Review via `review_web_hr_emploc_correction`), the record is deployed immediately to `plantilla` in status `Active`, the slot transitions to `occupied`, and `hr_emploc` status is set to `status = 'Moved to Plantilla'` and `hr_status = 'Transferred'`.
3. **Four Registry Lock Rules (under `SELECT FOR UPDATE`)**:
   - **Rule a (Hard Block)**: If number is already assigned to a different person → raises `EMPLOYEE_NO_ALREADY_ASSIGNED` (`23505`).
   - **Rule b (Hard Block)**: If same person already has an active placement or active Plantilla record with that number → raises `EMPLOYEE_ALREADY_ACTIVE` (`23505`).
   - **Rule c (Rehire Confirmation)**: If same person was previously assigned that number but all prior records are inactive/resigned → raises `REHIRE_CONFIRM_REQUIRED` (`23505`) with JSON detail until `p_confirm_reuse = true` with non-empty reason is supplied. Stamped `rehire_reused`.
   - **Rule d (Duplicate Warning)**: If same person already owns a different number in the registry → raises `POSSIBLE_DUPLICATE_PERSON` (`23505`) with JSON detail until `p_confirm_reuse = true` with reason is supplied.
4. **Decision 2 Typo Release (Option A)**:
   - On Deployed tab `update_deployed_employee_id`, if the old number was first assigned to this same record, no other row references it, actor is Data Team or SA, and reason is provided, trigger releases the old number in the registry (`status = 'released'`).
5. **Missing Required Fields (No Silent Defaults)**:
   - If `hired_date`, `position`, `account`/`account_id`, `store_name`/`store_id`, or applicant structured name is missing when moving to Plantilla, raises specific `FIELD_REQUIRED_MISSING: <field> is required` (`23502`). Silent defaults (`CURRENT_DATE` fallback, name splitting) are prohibited.

* **HRCO All Scope / Global Visibility**: HRCO users with `scope_type = 'global'` or `hrco_global_visibility = true` bypass per-coordinator snapshot and account restrictions across `get_correction_requests_scoped`, `list_web_hr_emplocs`, `get_web_hr_emploc_summary`, and `get_web_hr_emploc_detail`, loading all records across Pending, Correction, Review, and Ready queues. Restricted HRCOs remain strictly bound to their allowed accounts or assigned records.
* **Caller Validation**: All queries and RPCs fetch caller metadata directly from `auth.uid()`. The frontend never passes `profile_id` or `role_key` as arguments.
* **PII Guard Rails**: To ensure privacy, the dense table and detail drawer candidate checklists will **never expose contact phone numbers or email addresses** to non-authorized roles.

---

## 9. Proposed RPC Contracts

To align with the Vacancy reference architecture, we propose the following backend RPC signatures:

### A. List Contract Recommendation
```sql
CREATE OR REPLACE FUNCTION public.list_web_hr_emplocs(
  p_queue         text    DEFAULT NULL, -- 'pending', 'deficiency', 'complete', 'deletion_pending', 'all'
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_position      text    DEFAULT NULL,
  p_assignment    text    DEFAULT NULL, -- 'Stationary', 'Roving'
  p_search        text    DEFAULT NULL,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'created_at',
  p_sort_dir      text    DEFAULT 'desc'
)
RETURNS TABLE (
  id                          uuid,
  applicant_name              text,
  vcode                       text,
  account_id                  uuid,
  account_name                text,
  store_name                  text,
  position_title              text,
  hr_status                   text,
  deployment_status           text, -- hr_emploc.status ('Pending Emploc', etc.)
  employee_no                 text,
  assignment_type             text,
  covered_stores_count        integer,
  deficiency_summary          text,
  hired_date                  date,
  date_requested              timestamptz,
  sla_breached                boolean,
  sla_elapsed_days            integer,
  row_capabilities            jsonb,
  total_count                 bigint
) ...
```

### B. Summary Count Recommendation
```sql
CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_summary(
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL,
  p_position      text DEFAULT NULL,
  p_search        text DEFAULT NULL
)
RETURNS TABLE (
  total_pending       bigint, -- hr_status IN ('Pending', 'For Review')
  action_needed       bigint, -- hr_status = 'For Correction'
  ready_to_deploy     bigint, -- hr_status = 'Complete' AND employee_no IS NULL
  pending_deletion    bigint, -- hr_status = 'Pending Deletion'
  sla_breaches        bigint  -- sla_breached = true
) ...
```

### C. Detail Drawer Contract Recommendation
```sql
CREATE OR REPLACE FUNCTION public.get_web_hr_emploc_detail(
  p_hr_emploc_id uuid
)
RETURNS TABLE (
  id                          uuid,
  applicant_name              text,
  vcode                       text,
  account_name                text,
  store_name                  text,
  position_title              text,
  hr_status                   text,
  deployment_status           text,
  employee_no                 text,
  assignment_type             text,
  covered_stores              jsonb, -- covered stores for roving assignments
  hired_date                  date,
  date_requested              timestamptz,
  hrco_name                   text,
  ops_remarks                 text,
  hr_remarks                  text,
  requirement_overall_status  text,
  correction_reason           jsonb, -- detailed deficiencies list
  uploaded_attachments        jsonb, -- JSONB array of hr_emploc_correction_attachments
  sla_breached                boolean,
  sla_elapsed_days            integer,
  audit_logs_timeline         jsonb, -- JSONB array of audit events
  active_deletion_request     jsonb, -- details of any active deletion request
  row_capabilities            jsonb
) ...
```

---

## 10. Shared Component Reuse Mapping

The HR Emploc Web module will achieve aesthetic coherence and zero code duplication by mapping directly to the **Shared Web UI System** primitives:

```
[HR Emploc Main View]
 ├── AdminPageHeader ───────────────── Title: "HR Emploc Compliance"
 │                                     Subtitle: "Audit requirements, manage corrections, and deploy personnel."
 │                                     Primary Action: Scoped Bulk Upload trigger (Encoder/Admin only)
 ├── MetricCard (Grid) ─────────────── Renders: 1. Total Processing | 2. Action Needed
 │                                              3. Ready to Deploy | 4. SLA Breach Watch
 ├── AdminFilterBar ────────────────── Search: "Search by candidate, store, or VCode..."
 │                                     Select Dropdowns: Account, Group, Position, Assignment Type
 ├── Status Tabs ───────────────────── Swaps queues (Pending, Deficiencies, Completed, Deletion Pending)
 ├── Compact Table ─────────────────── Rendered grid of placement records. Soft-blue overlay on click.
 │    └── DataState ────────────────── Handles Loading Spinner, Empty Records, Lock-Shield Access Block,
 │                                     and Warning Alert Cards with retry triggers
 └─ Detail Drawer
      ├── DetailDrawer ────────────── Width token: drawer-width-lg (640px)
      │                                Handles Escape key captures, backdrop click dismiss, scroll locking
      ├── StatusBadge ──────────────── Maps hr_status ('Pending Deletion' -> danger, 'Complete' -> success)
      └── CapabilityActionBar ──────── Renders: [ Tag Correction ] (HR Personnel)
                                                [ Assign Employee No ] (Encoder/SuperAdmin)
                                                [ Move to Plantilla ] (Encoder/Admin)
                                                [ Request Deletion ] (Ops Team / om / hrco)
```

---

## 11. Proposed Implementation Plan & Progress

### Phase 1: Route & Shared Shell Scaffolding [COMPLETED]
- Replaced the basic `ModuleEmptyState` scaffold in `src/app/(dashboard)/hr-emploc/page.tsx` with a high-fidelity layout shell.
- Implemented the page structure using `AdminPageHeader`, `MetricCard` grids, `AdminFilterBar`, and custom status tabs.
- Hooked up local mock variables to visually check the compact table density and detail drawer columns.

### Phase 2: Supabase Backend Migration & RPCs [COMPLETED]
- Established backend functions: `list_web_hr_emplocs`, `get_web_hr_emploc_summary`, and `get_web_hr_emploc_detail`.
- Synchronized `get_web_hr_emploc_detail` with canonical 48-column `RETURNS TABLE` signature and body (including `deployed_by_user_id`, `employee_lookup_*`, and correction timeline) and prepended `DROP FUNCTION IF EXISTS` statements in `20261027120000_fix_hrco_all_scope_hr_emploc_correction_rpc.sql` to prevent SQLSTATE 42P13 return type collisions.
- Enforced ADR-001 Golden Rule soft-delete filtering (`h.deleted_at IS NULL`) unconditionally outside the `COALESCE(v_role_level, 0) >= 90 OR (...)` scope branch in `get_web_hr_emploc_summary` and `list_web_hr_emplocs` via migration `20261027091040_fix_plantilla_summary_slot_counts_and_emploc_deleted_filter.sql`, preventing soft-deleted records from leaking into Super Admin queue summaries and lists.
- Verified security policies: checked RLS, restricted anonymous callers, and enforced role constraints (`Head Admin` block on employee number assignment).

### Phase 3: Read-Only Client Integration [COMPLETED]
- Created typed client integration helpers in `src/lib/queries/hr_emploc.ts`.
- Hooked React Query loaders (`useQuery`) into the main page and drawer components.
- Established robust error boundaries: display network warnings, empty tables, and lock shields for RLS scope violations.

### Phase 4: Action Integrations (Mutations) [PARTIAL — Deficiency Tagging Wired]

### Phase 5: Bulk XLSX Import & Ingestion Refactor [COMPLETED — ohm#p8m2w6k9]
- Refactored HR Emploc Import from full-page dedicated route (`/hr-emploc/import`) into centered purple modal shell (`HrEmplocImportModal`) matching Plantilla, Vacancy, MIKA, and Payroll in Data Control & Batch Ingestion dashboard.
- Maintained 3-tab architecture with purple-accented (`#7C3AED`) underlined tab layout: `Upload & Preview`, `Review Queue` (with pending count), `Import History` (with processed count).
- Maintained ADR-001 slot-first capacity reservation callout banner, target operational CENCOM group dropdown selector, official template downloads (`v3 ADR-001` and `Standard 7-Col`), and client-side dropzone validation gate.
- Applied purple theming (`bg-purple-50 text-purple-600` dropzone icon, purple dragover border, purple submit CTA button, purple badges).
- Added standard mobile parity footer bar: `Full Mobile HR Emploc Parity with ADR-001 Slot Validation and Rollback Governance.` with right-aligned `Close` button.
- Updated sub-modals (`BatchDetailsModal`, `RejectBatchModal`, `RollbackBatchModal`) to `z-[60]` / `z-[70]` for clean stacking over parent modal.
- Configured legacy route `/hr-emploc/import` to automatically redirect to `/more?tab=data_control&subtab=batch_imports&open=import_hr_emploc`.

### Phase 6: UI Standard & Motion System Alignment (Loop 5A & 5B) [COMPLETED — ohm#l5b9k4x2]
- Aligned HR Emploc list page, table, drawer, and all 9 modals to the authoritative UI standard (`docs/architecture/ui-standard.md`).
- Aligned HR Emploc Import flow (`UploadTab`, `ReviewBatchesTab`, `HistoryTab`, `BatchDetailsModal`, `RejectBatchModal`, `RollbackBatchModal`).
- Parsing (`exceljs`/`xlsx`), validation, batch RPCs, and 72h rollback logic completely preserved (read-only logic, display/token changes only).
- Upload progress, row validity counts, batch counts, and countdowns strictly neutralized.
- Modal guards enforced: `z-[70]` stacking on reject/rollback submodals, `disableBackdropClick={true}` on form modals, `isSubmitting` mutation lock, `isDirty` Esc-guard.
- Reduced color literals across all HR Emploc files from 1,045 to exactly 0.
- Standardized table typography with a strict 14px (`text-sm`) minimum text floor and compact padding. Neutralized aging day counts (`SLA_BADGE_CLASS`).
- Applied `--danger` tokens (`text-[var(--danger-text)]`, `bg-[var(--danger-bg)]`, `border-[var(--danger-border)]`) strictly to destructive actions (reject batch, rollback batch, revert review, separation/deletion), validation errors, and failed-state messages.
- Mechanical verification gate passed with real module name `hr-emploc` and `"decision": "allow"`.

**Completed (OHM2026_1109):**
- `tagWebHrEmplocDeficiency` RPC wrapper added to `src/lib/queries/hr_emploc.ts` calling `public.tag_web_hr_emploc_deficiency(p_hr_emploc_id, p_deficiencies, p_remarks)`.
- "Tag Deficiency (HR Compliance)" action in `HrEmplocDetailDrawer.tsx` is now enabled when `canTagDeficiency === true && !isPendingDeletion`.
- Confirmation modal with issue checkboxes, per-issue notes, optional remarks textarea, submitting state, inline error display, and Cancel/Confirm actions.
- On success: invalidates `["hr-emploc-detail", id]`, `["hr-emploc-list"]`, and `["hr-emploc-summary"]`; modal closes.
- Error handling: `42501` → access/session error message; `P0001` → backend validation message; generic → network fallback.
- `HrEmplocDataErrorKind` extended with `invalid_state` for `P0001` backend precondition rejections.
- Backend deployed: migration `20260607000004` applies `public.tag_web_hr_emploc_deficiency(...)` remotely. Mutation executes end-to-end.

**Frontend wired, backend deployed (OHM2026_1110 / OHM2026_1112 / OHM2026_1127):**
- Correction review (`For Review` → `Complete` on approve / `For Review` → `For Correction` on return). Backend-authoritative contract `review_web_hr_emploc_correction` originally applied in migration `20260609000000` (4 params). Extended on Staging via migrations `20262606000080` and `20262606000081` to accept `p_employee_no` (and rehire confirmation flags) to support atomic Emploc ID assignment upon correction approval (pending Production promotion). `canReviewCorrection` row capability normalized from live `can_review_correction` only (canonical key; stale `can_approve_correction` alias removed in OHM2026_1127). `ReviewCorrectionModal` wired in `HrEmplocDetailDrawer.tsx` with per-deficiency toggles, auto-derived approve/return decision, decision-preview block, remarks textarea, inline error display, and invalidation of `["hr-emploc-detail", id]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. As of OHM2026_1129, the drawer action visibility depends only on this backend-authored capability; unauthorized users, wrong statuses, pending deletion requests, missing keys, and malformed capability payloads fail closed by rendering no Review Correction action.

**Remaining:**
- Assign Employee Number (Encoder/SuperAdmin).
- Move to Plantilla.
- Request Deletion (Backout/Duplicate).
- Review Deletion Request.

## Pending Deletion Lock & Activity History
- Pending tab: while an active deletion request exists (`is_pending_deletion`), `+ Add Emploc` and `! For Correction` are disabled until the request is withdrawn.
- Activity History Trail (`get_correction_timeline`) returns human-readable sentences with the actor first (e.g. "Litong, Ohm requested deletion of Santos, Jayson Mendez due to <reason>."), and includes deletion request requested/withdrawn/approved/rejected events. The drawer shows the trail latest-first.
- The drawer treats a deletion request as active only while its status is `Pending`; withdrawn/approved/rejected requests restore the normal Pending Emploc view and the Request Deletion action.

## Schema Fix — Migration 20262606000082 (ohm#9x4v2m8p)
- Fixed PostgreSQL error `42703 (undefined_column)` in `list_web_hr_emplocs`: migration `20262606000081` contained broken column reference `COALESCE(h.position_snapshot, h.position) AS position_title` (table `hr_emploc` lacks `position_snapshot`).
- Re-asserted `list_web_hr_emplocs` projecting `h.position AS position_title` in migration `20262606000082_fix_list_web_hr_emplocs_position_column.sql`, reloaded PostgREST schema cache (`NOTIFY pgrst, 'reload schema';`), and patched line 1957 of `20262606000081` for future clean Production promotion.
- Confirmed live HTTP 200 row listings across all 4 queue tabs (`pending`, `correction`, `review`, `deployed`) matching tab badge counters on Staging (`qqiiznmqxfoamqytjica`).

## RPC Restoration — Migration 20262606000104 (ohm#x7k4v9q2)
- Restored canonical Stage 2b RPC definitions on Staging (`qqiiznmqxfoamqytjica`) via `20262606000104_restore_hr_emploc_for_emploc_and_upload_docs_rpcs.sql`.
- Resolved blank Actions column on the Pending queue tab where `can_upload_docs` was not being projected by `list_web_hr_emplocs`.
- Ensured `public.list_web_hr_emplocs` projects `row_capabilities.can_upload_docs` evaluated via `public.can_upload_hr_emploc_docs(h.id)` and correctly filters `p_queue = 'for_emploc'`.
- Restored `for_emploc_count bigint` in `public.get_web_hr_emploc_summary()` to power the 5-tab badge counters (`Pending`, `For Emploc`, `Correction`, `Review`, `Deployed`).
- Restored `get_web_hr_emploc_detail` capabilities projection including `can_upload_docs`, `can_submit_requirements`, and multi-document attachment metadata (`stage`, `object_path`, `storage_path`).

