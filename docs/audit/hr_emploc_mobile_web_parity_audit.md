# HR Emploc (Employee Locator) & Import Reconciliation: Mobile-to-Web Parity Audit

**Prompt ID:** `ohm#w30e821a`  
**Date:** 2026-10-10  
**Auditor:** Antigravity (Deep Technical Audit Pass)  
**Target Codebases:**
- Mobile Source of Truth: `D:\Projects\OHMployee` (`lib/features/hr_emploc/`, `lib/data/services/hr_emploc_service.dart`, `lib/data/services/hr_emploc_import_service.dart`, `lib/utils/hr_emploc_import_xlsx.dart`, `docs/state/hr_emploc_state.md`)
- Web Implementation Target: `D:\Projects\ohmployee-web` (`src/app/(dashboard)/hr-emploc/`, `src/components/hr-emploc/`, `src/lib/queries/hr_emploc.ts`, `docs/state/hr_emploc_web_state.md`)

---

## 1. Executive Summary

The **HR Emploc** (Employee Locator / Onboarding Masterlist) module represents the bridge between **Vacancy Pipeline Candidate Confirmation** and **Official Plantilla Deployment**. In the OHMployee lifecycle:

$$\text{Pipeline Applicant Confirmed Onboard} \longrightarrow \text{HR Emploc Compliance Audit} \longrightarrow \text{Employee No Assignment} \longrightarrow \text{Move to Plantilla (Active Staff)}$$

In addition, an operational pathway exists to ingest bulk recruits directly into HR Emploc via the **HR Emploc XLSX Import & Reconciliation Wizard** (with slot-first reservation, approval gate, and rollback safety).

### Audit Verdict & Web Maturity State
1. **Directory / Roster Table & Inspection**:
   - **Status**: **Advanced Partial Parity**.
   - The web app already has a high-density table ([`HrEmplocTable.tsx`](file:///d:/Projects/ohmployee-web/src/components/hr-emploc/HrEmplocTable.tsx)), summary metric cards, local/server filtering, and a slide-over detail drawer ([`HrEmplocDetailDrawer.tsx`](file:///d:/Projects/ohmployee-web/src/components/hr-emploc/HrEmplocDetailDrawer.tsx)).
   - **Gap**: Queue tab names diverge between mobile (`Pending`, `Correction`, `Review`, `Ready`) and web (`pending`, `deficiency`, `complete`, `deletion_pending`, `all`). Mobile tab counters and SLA breach styling have evolved into streamlined 3-row/4-row layouts.
2. **Deficiency & Correction Workflows**:
   - **Status**: **Backend Deployed & Frontend Wired (Deficiency Tagging & Review)**.
   - Tagging deficiencies via `tag_web_hr_emploc_deficiency` and reviewing resubmissions via `review_web_hr_emploc_correction` are implemented in web.
   - **Gap**: Web lacks ops-side correction submission / attachment upload interfaces (which are typically HRCO / mobile actions, but encoders/admins require view & management parity) and private Supabase storage bucket (`hr-corrections`) signed URL viewers for all attachment formats.
3. **Core Lifecycle Mutations**:
   - **Status**: **Missing on Web**.
   - **Assign Employee Number** (`assign_hr_emploc_number`), **Move to Plantilla** (`move_to_plantilla`), **Bulk Move All** (`bulk_move_ready_to_plantilla`), and **Roving Merge** (`merge_as_roving_emploc`) have backend RPCs but are not yet wired into the web Action Bar or UI triggers.
4. **Separation & Deletion Request Workflows**:
   - **Status**: **Missing on Web**.
   - Requesting deletions (Backout / Duplicate Record via `fn_request_emploc_deletion`), withdrawing requests (`fn_withdraw_emploc_deletion_request`), and reviewing/approving them (`fn_approve_emploc_deletion_request`, `fn_reject_emploc_deletion_request`) are currently only on mobile and in approvals routing.
5. **HR Emploc XLSX Import & Reconciliation Wizard**:
   - **Status**: **0% Implemented on Web**.
   - The mobile client has an end-to-end 3-tab wizard (`Upload File`, `Review Import`, `History`) with template generation, client-side pre-validation (`buildParsePreview`), slot-first ADR-001 backend validation, HA/SA approval (`approve_hr_emploc_import`), rejection, and full atomic rollback (`rollback_hr_emploc_import`). On web, this feature exists only as an unmapped navigation link in [`/more`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/more/page.tsx).

---

## 2. Feature & Workflow Inventory Comparison

| Feature / Capability | Mobile Implementation (`OHMployee`) | Web Current State (`ohmployee-web`) | Parity Status | Parity Gap & Target Action |
| :--- | :--- | :--- | :--- | :--- |
| **Directory Views / Tabs** | 4 Tabs: `Pending`, `Correction`, `Review`, `Ready` (SLA tab removed, SLA integrated as chip). Dynamic tab badges. | 5 Tabs: `Pending Review`, `For Correction`, `Compliance Complete`, `Pending Deletion`, `All / History`. | **Partial Divergence** | Align tab taxonomy. Map web tabs to match backend queues (`pending`, `correction`, `review`, `ready`, `deletion_pending`). Synchronize counter deduplication rules. |
| **Search & Filtering** | Local search over scoped records; matches name tokens, EMPLoc #, VCode, account, group, store. Filters: Group dropdown, SLA flags. | Scoped server-side RPC `list_web_hr_emplocs` with text search, account/group UUID inputs. Position/assignment dropdowns disabled. | **Partial** | Enable Account, Group, Position, and Assignment dropdown pickers with real datasets. Retain server-side search. |
| **Candidate Identity & PII** | Displays `Last, First Middle Name` (reverses stored `FIRST MIDDLE LAST`). Hides PII for unprivileged roles. | Formats applicant name; masks contact phone/email at RPC level. | **Parity Achieved** | Both adhere to PII protection contracts and canonical name formatting. |
| **SLA Tracking & Chips** | Tier 1 (3 days -> warning/amber), Tier 2 (5 days -> danger/red). Shared `SlaChip`. | Metric card "SLA Breach Watch" + SLA age cell in table + Detail drawer SLA alerts. | **Parity Achieved** | Logic matches `v_hr_emploc_sla_flags`. |
| **Tag Deficiency** | Full multi-issue selector modal with issue types from `hr_emploc_issue_types` + notes + remarks. | `TagDeficiencyModal` wired in drawer to `tag_web_hr_emploc_deficiency`. | **Parity Achieved** | End-to-end functional on web. |
| **Review Correction** | Review tab with HRCO resolution card, approve/reopen/reject. | `ReviewCorrectionModal` wired in drawer to `review_web_hr_emploc_correction`. | **Parity Achieved** | End-to-end functional on web. |
| **Attachment Handling** | Private `hr-corrections` bucket, signed 1-hour URLs, thumbnail/icon previews, size/uploader tags. | Read-only listing of attachments from JSONB; download links. | **Partial** | Wire secure signed URL retrieval (`createCorrectionAttachmentSignedUrl`) and inline modal file preview. |
| **Assign Employee No** | Modal dialog; role-checked (Encoder & Super Admin only; Head Admin hard-blocked). RPC: `assign_hr_emploc_number`. | Drawer button disabled with "Data Encoder Only". No dialog or RPC wiring. | **Missing Mutation** | Implement `AssignEmployeeNoModal` wired to `assign_hr_emploc_number`. |
| **Move to Plantilla** | Individual card CTA + "Move All" bulk action. ADR-001 slot availability check (`fetchAvailableSlotsForVcode`). RPC: `move_to_plantilla` / `bulk_move_ready_to_plantilla`. | Drawer button disabled with placeholder. No batch move action. | **Missing Mutation** | Implement individual "Deploy to Plantilla" action & bulk "Move All Ready" button with slot capacity validation pre-check. |
| **Request Deletion (Backout / Duplicate)** | Danger zone sheet; Backout (reopens vacancy) or Duplicate Record (links to original record). RPC: `fn_request_emploc_deletion`. | Drawer action disabled. No request modal. | **Missing Mutation** | Implement `RequestDeletionModal` (Backout vs Duplicate) wired to `fn_request_emploc_deletion`. |
| **Review Deletion Requests** | Dedicated screen (`HrEmplocDeletionReviewScreen`) with approve (reopen slot choice) & reject. | Category tile under `/approvals?tab=hr_emploc_deletions` redirects to `/hr-emploc`. | **Missing View** | Build dedicated Deletion Review modal or sub-view in Approvals/HR Emploc. |
| **Withdraw Deletion Request** | Inline "Withdraw Request" button on cards/detail. RPC: `fn_withdraw_emploc_deletion_request`. | Not wired. | **Missing Mutation** | Implement withdrawal trigger for requestor/admin. |
| **Roving Multi-Store Merging** | `merge_as_roving_emploc` RPC merges duplicate recruits into single roving employee with multiple store links. | Displays roving store count and tooltip in table/drawer. No merge tool. | **Missing Tool** | Build Roving Merge utility modal for Encoders/Admins. |
| **Bulk XLSX Import Wizard** | 3-tab wizard: Upload (template generator + client parse + slot pre-check), Review (batch cards), History (rollback). | No route, no component. Link in `/more` points to base `/hr-emploc`. | **Missing Module** | Build full 3-tab Import Wizard at `/hr-emploc/import` or modal view. |

---

## 3. Schema & Database Inventory

### 3.1 Primary Tables & Views

| Object Name | Type | Purpose & Mobile/Web Relevance |
| :--- | :--- | :--- |
| `public.hr_emploc` | Table | Core employee locator table. Key columns: `id`, `applicant_name`, `vcode`, `slot_id`, `pool_slot_id`, `account_id`, `store_id`, `hr_status`, `status`, `employee_no`, `emploc_no`, `assignment_type`, `correction_reason`, `import_batch_id`, `deleted_at`. |
| `public.v_hr_emploc_sla_flags` | View | Canonical operational view calculating `sla_breached`, `aging_days`, and standard join fields. Used by mobile `HrEmplocService.fetchAll`. |
| `public.hr_emploc_issue_types` | Table | Active catalog of deficiency issue codes (`INVALID_SSS`, `INCOMPLETE_REQUIREMENT`, etc.), labels, and requirement flags. |
| `public.hr_emploc_correction_attachments` | Table | Metadata for uploaded correction files. FK to `hr_emploc(id)`. Files stored in private Supabase bucket `hr-corrections`. |
| `public.hr_emploc_deletion_requests` | Table | Tracks separation/duplicate deletion requests. Statuses: `Pending`, `Approved`, `Rejected`, `Withdrawn`. |
| `public.hr_emploc_import_batches` | Table | Stores bulk import batch headers (`file_name`, `group_id`, `status`, `total_rows`, `valid_rows`, `blocked_rows`, `uploaded_by`, `approved_by`, `rollback_reason`). |
| `public.hr_emploc_import_rows` | Table | Individual parsed and staged rows for an import batch (`validation_status`, `validation_errors` JSONB, `vcode`, `plantilla_slot_id`). |
| `public.hr_emploc_store_links` | Table | Multi-store associations for Roving and Coverage employees. |
| `public.v_employee_activity_log` | View | Resolved timeline events for employee lifecycle activity logs. |

### 3.2 Authoritative RPC Signatures

#### A. Presentation & Web Listing RPCs
```sql
-- 1. Scoped listing for web dense table
public.list_web_hr_emplocs(
  p_queue         text    DEFAULT NULL, -- 'pending', 'correction', 'review', 'ready', 'transferred', 'rejected'
  p_status        text    DEFAULT NULL,
  p_deficiency    text    DEFAULT NULL,
  p_sla_filter    text    DEFAULT NULL,
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_search        text    DEFAULT NULL,
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'date_requested',
  p_sort_dir      text    DEFAULT 'desc'
) RETURNS TABLE (...)

-- 2. Scoped summary counts for KPI cards & tab badges
public.get_web_hr_emploc_summary(
  p_queue         text DEFAULT NULL,
  p_status        text DEFAULT NULL,
  p_deficiency    text DEFAULT NULL,
  p_sla_filter    text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL,
  p_search        text DEFAULT NULL
) RETURNS TABLE (...)

-- 3. Detailed record inspector
public.get_web_hr_emploc_detail(
  p_hr_emploc_id uuid
) RETURNS TABLE (...)
```

#### B. Compliance & Deficiency RPCs
```sql
-- Tag deficiency (Web & Mobile)
public.tag_web_hr_emploc_deficiency(
  p_hr_emploc_id uuid,
  p_deficiencies jsonb,
  p_remarks text DEFAULT NULL
) RETURNS jsonb

-- Review resubmitted correction (Web)
public.review_web_hr_emploc_correction(
  p_hr_emploc_id uuid,
  p_decision text,          -- 'approve' | 'return'
  p_resolved_keys text[],
  p_remarks text DEFAULT NULL
) RETURNS jsonb

-- Mobile correction lifecycle RPCs
public.mark_for_correction(p_id uuid, p_issues jsonb, p_hr_remarks text)
public.submit_hrco_correction_update(p_correction_request_id uuid, p_hrco_notes text)
public.approve_correction_request(p_correction_request_id uuid, p_approved_by text)
public.reject_correction_request(p_correction_request_id uuid, p_hr_remarks text)
public.reopen_correction_request(p_correction_request_id uuid, p_hr_remarks text)
public.get_correction_timeline(p_correction_request_id uuid)
```

#### C. Lifecycle & Finalization Mutations
```sql
-- 1. Assign Employee Number (Encoder & Super Admin ONLY; Head Admin BLOCKED)
public.assign_hr_emploc_number(
  p_id          uuid,
  p_employee_no text
) RETURNS void

-- 2. Move single record to Plantilla (Occupies slot, closes vacancy)
public.move_to_plantilla(
  p_id uuid
) RETURNS void

-- 3. Bulk move all 'Ready' records to Plantilla
public.bulk_move_ready_to_plantilla() RETURNS jsonb

-- 4. Merge duplicate records into roving allocation
public.merge_as_roving_emploc(
  p_master_hr_emploc_id    uuid,
  p_duplicate_hr_emploc_id uuid
) RETURNS jsonb
```

#### D. Deletion Request RPCs
```sql
-- Request separation / duplicate deletion
public.fn_request_emploc_deletion(
  p_hr_emploc_id       uuid,
  p_reason             text,
  p_deletion_type      text, -- 'backout' | 'duplicate'
  p_original_emploc_id uuid DEFAULT NULL
) RETURNS jsonb

-- Withdraw pending request
public.fn_withdraw_emploc_deletion_request(
  p_request_id uuid,
  p_reason     text DEFAULT NULL
) RETURNS jsonb

-- Approve deletion request (Encoder / Super Admin)
public.fn_approve_emploc_deletion_request(
  p_request_id         uuid,
  p_reviewer_remarks   text DEFAULT NULL
) RETURNS jsonb

-- Reject deletion request
public.fn_reject_emploc_deletion_request(
  p_request_id         uuid,
  p_reviewer_remarks   text DEFAULT NULL
) RETURNS jsonb
```

#### E. Bulk XLSX Import & Reconciliation Wizard RPCs
```sql
-- 1. Get operational cencom groups
public.get_hr_emploc_import_groups()
RETURNS TABLE (group_id uuid, group_name text, sort_order integer)

-- 2. Submit XLSX rows (Validates slot-first, creates batch in pending_approval)
public.submit_hr_emploc_import(
  p_file_name text,
  p_group_id  uuid,
  p_rows      jsonb
) RETURNS json

-- 3. Fetch import batches
public.get_hr_emploc_import_batches()
RETURNS TABLE (...)

-- 4. Fetch row-level staged items for review
public.get_hr_emploc_import_rows(
  p_batch_id uuid
) RETURNS TABLE (...)

-- 5. HA/SA Approval (Atomic slot claim, vacancy closure, hr_emploc insertion)
public.approve_hr_emploc_import(
  p_batch_id uuid
) RETURNS json

-- 6. Reject batch
public.reject_hr_emploc_import(
  p_batch_id     uuid,
  p_reason_code  text,
  p_reason_note  text DEFAULT NULL
) RETURNS void

-- 7. Rollback batch (Soft-deletes batch records, reopens slots & vacancies)
public.rollback_hr_emploc_import(
  p_batch_id uuid,
  p_reason   text
) RETURNS json
```

---

## 4. Deep Dive: HR Emploc Import & Reconciliation Architecture

The bulk import system is strictly governed by **ADR-001 (Slot-First Architecture)**:

```
+-----------------------------------------------------------------------------------------+
|                                    ADR-001 LIFECYCLE                                    |
|                                                                                         |
|  1. Headcount Approval -> Plantilla Slot Created (open) -> Vacancy Created (Open)       |
|                                    |                                                    |
|  2. XLSX Import Row Upload (GROUP, ACCOUNT, VCODE, LAST, FIRST, MIDDLE, DATE_HIRED)     |
|                                    |                                                    |
|  3. Pass 1: Slot-First Validation against plantilla_slots (legacy_vcode)               |
|             - Reject if slot missing, closed, occupied, or archived                    |
|             - Store, Position, Employment Type derived directly from Slot (Template v3) |
|                                    |                                                    |
|  4. Pass 2: Slot Reservation                                                            |
|             - Slot status transition: open -> hr_processing                             |
|             - Batch state: pending_approval                                             |
|                                    |                                                    |
|  5. HA / SA Review (Role Level >= 90)                                                   |
|             /                                           \                               |
|        [APPROVE]                                     [REJECT]                           |
|            |                                             |                              |
|   Atomic Transaction:                           Slot restored to prior state            |
|   - hr_emploc rows inserted                     (open / pipeline)                       |
|   - slot_id FK locked                           Batch state: rejected (terminal)        |
|   - vacancy status -> Filled                                                            |
|   - slot remains hr_processing                                                          |
|            |                                                                            |
|     [ROLLBACK (Emergency)]                                                              |
|   - Soft-delete hr_emploc rows                                                          |
|   - Slot restored to open                                                               |
|   - Vacancy reopened (Filled -> Open)                                                   |
|   - Blocked if any row moved to Plantilla                                               |
+-----------------------------------------------------------------------------------------+
```

### Import Template Specification (v3 Contract)
The XLSX template requires exactly **7 columns** in order:
1. `GROUP` (must match selected operational group)
2. `ACCOUNT`
3. `VCODE` (authoritative slot reference)
4. `LAST_NAME` (allowed chars: `A-Za-z0-9 '.-Ññ`)
5. `FIRST_NAME`
6. `MIDDLE_NAME` (required; use `'NA'` for none; `'N/A'` or single letter blocked)
7. `DATE_HIRED` (`YYYY-MM-DD`)

*Note: `STORE`, `POSITION`, and `EMPLOYMENT_TYPE` were removed in v3 to enforce ADR-001 single-source-of-truth slot resolution.*

---

## 5. Parity Gap Analysis

### Gap 1: Tab Queues & Metric Badge Alignment
- **Current Mobile**: Tabs are `Pending`, `Correction`, `Review`, `Ready`.
- **Current Web**: Tabs are `Pending Review` (`pending`), `For Correction` (`deficiency`), `Compliance Complete` (`complete`), `Pending Deletion` (`deletion_pending`), `All / History` (`all`).
- **Remediation**: Align web queue keys and tab labels. Add dedicated `Review` tab for resubmissions, or clearly separate `Pending Review` from `For Review` to mirror the operational lifecycle. Align tab counts with mobile badge deduplication (`_tabCount('Ready')` deduplication against active corrections).

### Gap 2: Core Action Bar Mutations in Detail Drawer
- In [`HrEmplocDetailDrawer.tsx`](file:///d:/Projects/ohmployee-web/src/components/hr-emploc/HrEmplocDetailDrawer.tsx), four critical actions are currently non-functional:
  1. `Assign Employee ID`: Disabled placeholder. Must open modal with employee ID input, client-side formatting, role check (Super Admin & Encoder; Head Admin blocked), calling `assign_hr_emploc_number`.
  2. `Deploy to Plantilla Directory`: Disabled placeholder. Must check capacity (`fetchAvailableSlotsForVcode`), execute `move_to_plantilla`, and invalidate queries.
  3. `Request Placement Separation / Deletion`: Disabled placeholder. Must open modal with Backout vs Duplicate selector, reason field, and calling `fn_request_emploc_deletion`.
  4. `Review Deletion Request`: Disabled placeholder. Must open modal with approve (reopen vacancy option) or reject, calling `fn_approve_emploc_deletion_request` or `fn_reject_emploc_deletion_request`.

### Gap 3: Bulk Actions & Capacity-Aware Operations
- Mobile includes **"Move All Ready"** (`bulk_move_ready_to_plantilla`) on the Ready tab with capacity-aware skip logging.
- Web currently has no bulk action button on the `Compliance Complete` / `Ready` view.

### Gap 4: HR Emploc Import & Reconciliation Module
- Mobile has a rich 3-tab import flow under **More → Data Control → Import HR Emploc**.
- Web has no import interface at all. The link in [`/more`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/more/page.tsx) points to `/hr-emploc`.
- Needs a dedicated sub-route `src/app/(dashboard)/hr-emploc/import/page.tsx` or an Import Drawer with:
  1. Tab 1: Upload (Template generation via `xlsx` library, client-side parse & preview matching `buildParsePreview`, group selector from `get_hr_emploc_import_groups`, submit to `submit_hr_emploc_import`).
  2. Tab 2: Review (Batches awaiting HA/SA approval, row-level validation inspection, approve / reject dialogs).
  3. Tab 3: History & Rollback (Auditable history with rollback trigger and reason modal).

### Gap 5: Approvals Queue Integration
- The web Request Center ([`/approvals`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/approvals/page.tsx)) lists `hr_emploc_deletions` in `RequestCategoryNavigation`, but [`ActiveQueueReviewPane.tsx`](file:///d:/Projects/ohmployee-web/src/components/approvals/ActiveQueueReviewPane.tsx) only provides a link button back to `/hr-emploc`.
- It lacks an inline review card to inspect and approve/reject deletion requests directly within the Request Center.

---

## 6. Implementation Roadmap

### Phase 1: Core Action Bar Mutations (Immediate Web Parity)
1. **Assign Employee Number Modal**:
   - Create `src/components/hr-emploc/AssignEmployeeNoModal.tsx`.
   - Wire to `assign_hr_emploc_number` RPC.
   - Enforce role check: Encoder (`role_level = 30`) and Super Admin (`role_level = 100`) only. Block Head Admin (`role_level = 90`).
2. **Move to Plantilla & Capacity Guard**:
   - Add service query `checkVcodeAvailability(vcode)` querying `plantilla_slots` and `workforce_pool_slots`.
   - Wire single "Deploy to Plantilla" action to `move_to_plantilla`.
   - Add "Bulk Move Ready" button in header when on Ready queue, calling `bulk_move_ready_to_plantilla`.
3. **Deletion Request Workflows**:
   - Create `src/components/hr-emploc/RequestDeletionModal.tsx` supporting `backout` and `duplicate` deletion types.
   - Wire to `fn_request_emploc_deletion`.
   - Add inline "Withdraw Request" action for pending deletion records calling `fn_withdraw_emploc_deletion_request`.
   - Create `src/components/hr-emploc/ReviewDeletionModal.tsx` for Encoders/Admins with "Reopen Vacancy" option calling `fn_approve_emploc_deletion_request` and `fn_reject_emploc_deletion_request`.

### Phase 2: Approvals Hub Integration
1. **Request Center Review Card**:
   - In `src/components/approvals/`, build `HrEmplocDeletionApprovalCard.tsx`.
   - Integrate into `ActiveQueueReviewPane.tsx` under the `hr_emploc_deletions` category to allow direct approval/rejection without navigating to `/hr-emploc`.

### Phase 3: HR Emploc XLSX Import & Reconciliation Wizard
1. **Route & Layout Scaffolding**:
   - Create `src/app/(dashboard)/hr-emploc/import/page.tsx`.
   - Implement 3-tab layout: `Upload File`, `Review Import`, `Import History`.
2. **Client-Side Parser & Template Generator**:
   - Implement `src/lib/utils/hr_emploc_import_xlsx.ts` using `xlsx` (SheetJS).
   - Generate official v3 XLSX template (`GROUP, ACCOUNT, VCODE, LAST_NAME, FIRST_NAME, MIDDLE_NAME, DATE_HIRED`).
   - Implement client validation preview (`buildParsePreview`) with name character validation (`_hasValidNameChars`) and the 6-rule `MIDDLE_NAME` parser.
3. **Backend RPC Client Wrappers**:
   - In `src/lib/queries/hr_emploc_import.ts`, implement wrappers for:
     - `getHrEmplocImportGroups`
     - `submitHrEmplocImport`
     - `getHrEmplocImportBatches`
     - `getHrEmplocImportRows`
     - `approveHrEmplocImport`
     - `rejectHrEmplocImport`
     - `rollbackHrEmplocImport`
4. **UI Components**:
   - `UploadTab`: Group selector, template download button, drag-and-drop file uploader, parse preview card with valid/blocked chip counts.
   - `ReviewTab`: Batch cards with total/valid/blocked rows, row details table drawer, HA/SA approve/reject modals.
   - `HistoryTab`: Historical batches, status badges, rollback button with confirmation and reason dialog.
5. **Navigation Wiring**:
   - Update [`src/app/(dashboard)/more/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/more/page.tsx) tile `import_hr_emploc` to link directly to `/hr-emploc/import`.
   - Add "Import XLSX" action button in [`AdminPageHeader`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/hr-emploc/page.tsx) on `/hr-emploc`.

### Phase 4: UI Refinement & Polish
1. **Filter Controls**:
   - Connect Account, Group, Position, and Assignment dropdowns in `AdminFilterBar` to live metadata tables (`accounts`, `groups`, `positions`).
2. **Secure Attachments Viewer**:
   - Wire signed URL helper for `hr-corrections` storage objects to enable safe previewing of PDFs, PNGs, and JPEGs.
3. **Roving Merge Tool**:
   - Build lightweight utility modal to merge duplicate applicant records into a single roving assignment.

---

## 7. Verification Checklist

- [x] Deep audit of Mobile codebase (`D:\Projects\OHMployee`) for `emploc`, `hr_emploc`, models, screens, and services.
- [x] Deep audit of Web codebase (`D:\Projects\ohmployee-web`) for existing `/hr-emploc` routes, components, and queries.
- [x] Complete mapping of database tables, views, constraints, and RPC signatures.
- [x] Inventory of all core actions (Assign Employee No, Move to Plantilla, Request Deletion, Review Deletion, Roving Merge).
- [x] Complete mapping of the HR Emploc Import & Reconciliation Wizard (slot-first ADR-001 rules, template v3 contract, validation pipeline, approval/rollback lifecycle).
- [x] Actionable implementation roadmap documented in `docs/audit/hr_emploc_mobile_web_parity_audit.md`.
