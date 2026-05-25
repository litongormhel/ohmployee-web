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
* `hr_status`: Tracks the HR compliance workflow state (`Pending`, `For Correction`, `For Review`, `Complete`, `Rejected`, `Transferred`).
* `status`: Tracks the deployment lifecycle (`Pending Emploc`, `Moved to Plantilla`, `Backout`).

To facilitate rapid filtering and administrative scanning, the UI will implement the following tab-controlled queues:

| Queue Tab | Database Conditions | Primary Purpose / Administrative Action |
| :--- | :--- | :--- |
| **Pending Review** | `hr_status = 'Pending'` or `hr_status = 'For Review'` | Default operational queue. Lists newly confirmed onboard hires whose documentation needs initial audit or re-validation after correction. |
| **For Correction** | `hr_status = 'For Correction'` | Lists records currently sent back to field coordinators with deficiency lists. Awaiting upload of correct files. |
| **Compliance Complete** | `hr_status = 'Complete'` and `status = 'Pending Emploc'` | Actionable queue listing records that have met all compliance checks. Encoders/Super Admins focus here to assign employee numbers and trigger plantilla movement. |
| **Pending Deletion** | `hr_status = 'Pending Deletion'` | Risk management queue tracking active separation/deletion requests (Backout or Duplicate Record requests) awaiting admin review. |
| **All / History** | *Unfiltered on status* | Read-only archive and audit history. |

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
   - `For Correction` → `warning` (amber)
   - `Complete` → `success` (green)
   - `Pending Deletion` → `danger` (rose)
   - `Transferred` / `Rejected` → `neutral` (gray)
6. **Deficiency Summary**: High-level text listing deficient items extracted from `correction_reason` JSONB.
7. **SLA Counter**: Calculated days active since `coalesce(date_requested, created_at)`. If exceeding 3 days, it prints a rose alert badge (`text-red-700 bg-red-50 border-red-200`).
8. **Actions Area**: Desktop "Eye" icon to open the selected record in the Detail Drawer. Row clicking is also fully supported with an active overlay highlight (`bg-blue-50`).

---

## 5. Detail Drawer UX & Content Structure

When a row is selected, the desktop Detail Drawer slides overlaying the grid from the right. It consumes the `DetailDrawer` shared container, locked to the `drawer-width-lg` (`640px`) layout to fit side-by-side forms and checklists.

### Drawer Sections:

```
+-----------------------------------------------------------------------+
|  Account / Location Hierarchy Breadcrumbs                        [X]  |
|                                                                       |
|  [H1] CANDIDATE FULL NAME                                             |
|  VCode: VAC-2026-0042 (Monospace Badge)                               |
|  Status: [Ready for Deployment (Complete)]                            |
+-----------------------------------------------------------------------+
|  Placement Details (Grid)                                             |
|  - Date Hired: 2026-05-20       - Assignment Type: Roving             |
|  - Position: Field Merchandiser - Coordinator: HRCO Name              |
+-----------------------------------------------------------------------+
|  Onboarding Requirements & Deficiencies                               |
|  [Requirement Checklist]                                              |
|  [x] SSS Card                    [ ] NBI Clearance (Deficient)        |
|  [x] PagIBIG ID                  [ ] Birth Certificate (Deficient)    |
|                                                                       |
|  HR remarks: "NBI Clearance is blurry. Birth Certificate is missing   |
|  the seal."                                                           |
+-----------------------------------------------------------------------+
|  Corrections & Deficient File Uploads                                 |
|  - NBI_clearance_corrected.jpg  (Uploaded 10h ago by HRCO_Name)       |
|  - Birth_cert_official.pdf      (Uploaded 10h ago by HRCO_Name)       |
+-----------------------------------------------------------------------+
|  SLA & Processing Performance                                         |
|  - Elapsed Processing Time: 4 Days                                    |
|  - [!] SLA Breach Notice: Record has exceeded the 3-day SLA threshold.|
+-----------------------------------------------------------------------+
|  Activity Timeline & Audit Trail                                      |
|  o [Correction Submitted] - 10 hours ago by Santos, Maria (HRCO)       |
|  o [Correction Tagged]    - 2 days ago by Dela Cruz, Ana (HR Dept)      |
|  o [Confirmed Onboard]    - 4 days ago by System Automatic Trigger    |
+-----------------------------------------------------------------------+
|  Capability-Aware Actions (Sticky Bottom)                             |
|  [ Tag Deficiency ]  [ Assign Employee No ]  [ Move to Plantilla ]    |
+-----------------------------------------------------------------------+
```

1. **Header Breadcrumbs & Identification**:
   - Primary `H1` displaying `applicant_name_snapshot`.
   - VCode as a prominent monospaced badge.
   - Status badge and Location breadcrumbs (`Account / Store / Chain`).
2. **Placement Details**:
   - Key attributes: `hired_date`, `position`, `assignment_type`, `hrco_name`, and assigned deployer.
3. **Deficiencies & Compliance Checklist**:
   - Interactive representation of the `correction_reason` JSONB object showing tagged deficiency codes (from `hr_emploc_issue_types`) and comments.
   - Standard checkboxes indicating missing requirements.
4. **Correction Uploads Component**:
   - Listing uploaded compliance files linked to `hr_emploc_correction_attachments` with file type icons, name links, size, and uploader identities.
5. **SLA & Escalation Segment**:
   - Precise processing duration readout.
   - Escalation level tracker.
6. **Immutable Audit Activity Timeline**:
   - Tracks movements, re-submissions, and remarks dynamically from the audit log and deletion request log.
7. **Capability-Controlled Action Bar**:
   - Rendered using the shared `CapabilityActionBar`. Buttons are dynamically enabled/disabled and marked with "available" / "unexposed" visual indicators based on resolved backend `row_capabilities`.

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
4. **Finalization (Correction Review — second web mutation, architected OHM2026_1110)**: HR Personnel reviews the `For Review` resubmission via `review_web_hr_emploc_correction(...)`. Under the **strict all-deficiencies-resolved model**, the reviewer affirms each tagged deficiency:
   - **Approve** (every deficiency resolved) → `hr_status = 'Complete'`, `correction_reason` cleared, record becomes eligible for employee-number assignment. `employee_no` is *not* touched here. This is a forward gate with no web-side re-open path, so approval requires a fully clean record.
   - **Return** (residual deficiencies remain) → `hr_status = 'For Correction'`, `correction_reason` rewritten to the residual keys, HRCO re-notified. The loop repeats until clean.
   See `docs/state/web_mutation_workflow_state.md` Part II (§10–§18) for the full backend-authoritative contract, approval-model comparison, and the exact implementation prompt.

---

## 7. Approval, Correction, and Deletion Flows

Mutations inside the HR Emploc module are strictly transaction-safe. The web interface relies on safe RPC handlers for the following critical workflows:

### A. Assigning Employee Number (The Compliance Complete gate)
* **Pre-conditions**: `hr_status = 'Complete'`, `status = 'Pending Emploc'`, and no pending deletion requests.
* **Role Check (CRITICAL FIX)**: This action is **strictly restricted to Encoder and Super Admin roles**. 
  > [!IMPORTANT]
  > **Head Admin is blocked** from executing this action per migration `fix_assign_hr_emploc_number_block_head_admin`.
* **Execution**: Caller enters the official employee ID. The RPC updates `employee_no` and runs unique validations.

### B. Moving to Plantilla (Final Deployment)
* **Pre-conditions**: `employee_no` must be assigned (non-null), `hr_status` must be `Complete`, and no pending deletion requests.
* **Role Check**: Authorized Data Team roles (`Encoder`, `headAdmin`, `superAdmin`) only.
* **Execution**: Moves candidate data to `plantilla` table, logs onboarding timestamp, creates audit trail, and marks `status = 'Moved to Plantilla'`.

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
                         [Role Access Matrix]
=============================================================================
Role             | Read Scope       | Mutations (RPCs Allowed)
=============================================================================
superAdmin       | Global           | Full approvals, assignments, deletion overrides
-----------------------------------------------------------------------------
headAdmin        | Global           | Move to Plantilla, Review Deletion
                 |                  | (BLOCKED: Assign Employee Number!)
-----------------------------------------------------------------------------
Encoder          | Scoped           | Assign Employee Number, Move to Plantilla,
                 | (Allowed Accts)  | Review Deletion (Approved/Rejected)
-----------------------------------------------------------------------------
hrPersonnel      | Global           | Deficiency tagging, correction approvals,
                 |                  | complete documentation review
-----------------------------------------------------------------------------
om / hrco        | Scoped           | Upload corrections, submit compliance files,
                 | (Allowed Accts)  | request Deletions (Backout/Duplicate)
-----------------------------------------------------------------------------
atl / tl         | Scoped           | Read-only scoped queue view, details inspector
-----------------------------------------------------------------------------
viewer           | Scoped           | Read-only (Read RPCs only, mutations blocked)
=============================================================================
```

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
- Verified security policies: checked RLS, restricted anonymous callers, and enforced role constraints (`Head Admin` block on employee number assignment).

### Phase 3: Read-Only Client Integration [COMPLETED]
- Created typed client integration helpers in `src/lib/queries/hr_emploc.ts`.
- Hooked React Query loaders (`useQuery`) into the main page and drawer components.
- Established robust error boundaries: display network warnings, empty tables, and lock shields for RLS scope violations.

### Phase 4: Action Integrations (Mutations) [PARTIAL — Deficiency Tagging Wired]

**Completed (OHM2026_1109):**
- `tagWebHrEmplocDeficiency` RPC wrapper added to `src/lib/queries/hr_emploc.ts` calling `public.tag_web_hr_emploc_deficiency(p_hr_emploc_id, p_deficiencies, p_remarks)`.
- "Tag Deficiency (HR Compliance)" action in `HrEmplocDetailDrawer.tsx` is now enabled when `canTagDeficiency === true && !isPendingDeletion`.
- Confirmation modal with issue checkboxes, per-issue notes, optional remarks textarea, submitting state, inline error display, and Cancel/Confirm actions.
- On success: invalidates `["hr-emploc-detail", id]`, `["hr-emploc-list"]`, and `["hr-emploc-summary"]`; modal closes.
- Error handling: `42501` → access/session error message; `P0001` → backend validation message; generic → network fallback.
- `HrEmplocDataErrorKind` extended with `invalid_state` for `P0001` backend precondition rejections.
- Backend deployed: migration `20260607000004` applies `public.tag_web_hr_emploc_deficiency(...)` remotely. Mutation executes end-to-end.

**Frontend wired, backend deployed (OHM2026_1110 / OHM2026_1112 / OHM2026_1127):**
- Correction review (`For Review` → `Complete` on approve / `For Review` → `For Correction` on return). Backend-authoritative contract `review_web_hr_emploc_correction(p_hr_emploc_id, p_decision, p_resolved_keys, p_remarks)` applied remotely via migration `20260609000000`. `canReviewCorrection` row capability normalized from live `can_review_correction` only (canonical key; stale `can_approve_correction` alias removed in OHM2026_1127). `ReviewCorrectionModal` wired in `HrEmplocDetailDrawer.tsx` with per-deficiency toggles, auto-derived approve/return decision, decision-preview block, remarks textarea, inline error display, and invalidation of `["hr-emploc-detail", id]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. As of OHM2026_1129, the drawer action visibility depends only on this backend-authored capability; unauthorized users, wrong statuses, pending deletion requests, missing keys, and malformed capability payloads fail closed by rendering no Review Correction action.

**Remaining:**
- Assign Employee Number (Encoder/SuperAdmin).
- Move to Plantilla.
- Request Deletion (Backout/Duplicate).
- Review Deletion Request.
