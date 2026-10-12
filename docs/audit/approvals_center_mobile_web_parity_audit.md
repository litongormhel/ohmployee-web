# Request Center & Mobile Approvals: Mobile-to-Web Parity Audit

**Prompt ID:** `ohm#w34a225e`  
**Date:** 2026-10-12  
**Auditor:** Antigravity (Deep Technical Architecture Audit Pass)  
**Target Codebases:**
- Mobile Source of Truth: `D:\Projects\OHMployee` (`lib/features/requests/`, `lib/features/approval/`, `lib/features/headcount_requests/`, `lib/features/vacancy/`, `lib/features/hr_emploc/`, `lib/features/deactivation/`, `lib/features/coverage/`, `lib/features/user_management/`, `lib/features/plantilla/`, `lib/data/services/`)
- Web Target: `D:\Projects\ohmployee-web` (`src/app/(dashboard)/approvals/`, `src/components/approvals/`, `src/lib/queries/requests.ts`, `src/lib/queries/hr_emploc.ts`)

---

## 1. Executive Summary

The **Request Center & Approvals Module** serves as the central administrative clearinghouse for all operational mutations that require human review, two-step authoring, or organizational approval before updating the database core.

In the mobile client (`OHMployee`), approval and review operations are split between:
1. **Request Center Hub** (`lib/features/requests/request_center_screen.dart`): Aggregated unified feed covering **New Stores**, **Headcount Requests**, **Vacancy Closures**, and **HR Emploc Deletions**.
2. **Dedicated Specialized Review Queues** in domain feature folders:
   - **Applicant Movement Requests (AMR)** (`lib/features/requests/applicant_movement_request_screen.dart`)
   - **Separation & Deactivations** (`lib/features/more/deactivation_requests_screen.dart` & `lib/features/deactivation/`)
   - **Coverage Requests** (`lib/features/coverage/coverage_request_screen.dart`)
   - **Account Group Transfers** (`lib/features/account_group_transfer/account_group_transfer_screens.dart`)
   - **Global Store Transfers** (`lib/features/user_management/global_store_transfer_screen.dart`)
   - **Temporary Permission Overrides** (`lib/features/user_management/temp_permission_screen.dart`)
   - **Workforce Pool Reliever Endorsements / Coverage Requests** (`lib/features/plantilla/moses_hq_pool_screen.dart`)
   - **Plantilla Onboarding Approvals** (`lib/features/approval/approval_screen.dart`)
   - **Vacancy Closure Review** (`lib/features/vacancy/vacancy_closure_review_screen.dart`)
   - **HR Emploc Deletions Review** (`lib/features/hr_emploc/hr_emploc_deletion_review_screen.dart`)
3. **Cross-Module Notification & Badge System**: `RequestCenterBadgeService` (`lib/data/services/request_center_badge_service.dart`) aggregates live pending count badges across all queues for top-level navigation.

### Current Web State (`ohmployee-web`)
The web implementation currently adopts an asymmetric two-pane layout in [`src/app/(dashboard)/approvals/page.tsx`](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/approvals/page.tsx):
- **Left Navigation**: Lists 8 categories with live badge counters via `useRequestCategoryCounts()`.
- **Right Review Pane**:
  - **Category 1: Headcount Amendments & Standard HC**: Fully implemented with in-place review cards ([`HeadcountAmendmentApprovalCard.tsx`](file:///d:/Projects/ohmployee-web/src/components/approvals/HeadcountAmendmentApprovalCard.tsx) and [`HeadcountStandardApprovalCard.tsx`](file:///d:/Projects/ohmployee-web/src/components/approvals/HeadcountStandardApprovalCard.tsx)).
  - **Category 5: HR Emploc Deletions**: Fully integrated in-place review card ([`HrEmplocDeletionReviewCard.tsx`](file:///d:/Projects/ohmployee-web/src/components/approvals/HrEmplocDeletionReviewCard.tsx)) with backout vs duplicate handling and vacancy reopening toggle.
  - **Other 7 Categories**: Show fallback placeholder cards with external module redirection buttons (e.g. `/cencom`, `/vacancy`, `/plantilla`) or unlinked queues.

---

## 2. Request Category & Action Inventory (All 9 Target Categories)

Below is the definitive review card layout, required metadata fields, actions, and modal requirements across all 9 request categories comparing Mobile vs Web.

| # | Request Category | Mobile UI Location & Review Capability | Web Current State | Review Card Layout & Metadata Fields | Actions (Approve / Reject / Clarify) | Confirmation Modals & Required Form Fields |
| :- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **Headcount Amendments & Standard HC** | `lib/features/headcount_requests/` & `RequestCenterScreen` (Approve, Reject, Generate VCODE, Execute HC Reduction). | **Full Operational Parity** (`HeadcountAmendmentApprovalCard`, `HeadcountStandardApprovalCard`). | Store, Position, Account, Group, Request Type, Target VCode, Proposed vs Previous Target, Delta pill, Urgency badge, Requester info, SLA aging. | **Approve**, **Reject**. (VCode creation handled post-approval). | • **Approve Amendment**: Optional approval remarks.<br>• **Approve Standard**: Confirmation modal.<br>• **Reject**: Required rejection remarks. |
| **2** | **New Store Requests** | In-place in `RequestCenterScreen` (`_CenterRequestCard`). Direct Approve & Reject. Also has "Request HC" bridge on approved items. | **Fallback Pane Only** (Redirects nowhere or shows empty placeholder). | Store Name, Account Name, Province / City, Requester profile name, Date requested, Age label (`d ago`), Status badge. On Approved: Status badge + "Store is active" note. | **Approve**, **Reject**, **Request HC** (post-approval shortcut). | • **Approve**: Inline spinner / direct action.<br>• **Reject**: Dialog with required `Reason *` (multiline).<br>• **Request HC**: Opens HC Request Dialog prepopulated with new store context. |
| **3** | **Store Transfers** *(Global Store Transfer & Account Group Transfer)* | Dedicated screens: `GlobalStoreTransferScreen` (3-tab: New, Pending, History) and `AccountGroupTransferScreens`. | **Fallback Pane Only** (Account Group Transfers redirects nowhere; Global Store Transfer not in Approvals). | **Store Transfer:** Source Scope (Group/Account/Store), Target Scope (Group/Account/Store), Employee cards with Source VCode/Position & Target Vacant Slot VCode/Position.<br>**Account Group Transfer:** Account Name, From Group -> To Group, Request number, Requester, Reason, Simulation snapshot. | **Store Transfer:** Segmented button per employee (`Approve` / `Reject`), `Approve Valid`, `Reject Selected`.<br>**Account Group:** `Approve`, `Reject`. | • **Store Transfer**: Partial approval sheet. Blocked rows locked to Reject; valid rows toggleable.<br>• **Account Group Reject**: Dialog with required `Rejection Reason *`. |
| **4** | **Vacancy Closures** | Dedicated `VacancyClosureReviewScreen` (Pending / History tabs) + in `RequestCenterScreen`. | **Fallback Pane Only** (Link button to `/vacancy`). | Vacancy VCode, Store Name, Account Name, Position, Requested By, Requested Date, Reason for closure. Single items + "Approve All" action bar. | **Approve**, **Reject**, **Approve All** (Bulk action for pending). | • **Approve**: Dialog confirmation.<br>• **Reject**: Dialog with required `Remarks *` (multiline).<br>• **Approve All**: Dialog confirmation with count of impacted vacancies. |
| **5** | **HR Emploc Deletions** | `HrEmplocDeletionReviewScreen` (Pending / History tabs) + in `RequestCenterScreen`. | **Full Operational Parity** (`HrEmplocDeletionReviewCard`). | Applicant Name, VCode, Store Name, Position, Employee No, Deletion Type (`Backout` vs `Duplicate Record`), Notes / Justification, Requester, Requested Date. | **Approve & Delete**, **Reject**. | • **Approve**: Step 1 asks "Reopen Vacancy? (Yes/No)" with explainer cards. Step 2 confirms deletion.<br>• **Reject**: Dialog with optional remarks. |
| **6** | **Account Deactivations** | `lib/features/more/deactivation_requests_screen.dart` (HRCO vs Backoffice view). Filter by Account, Batch, Status, Date. | **Fallback Pane Only** (Link button to `/plantilla`). | Employee Name, Employee No, Account, Store, Position, Group, Separation Status (`Resigned`), Batch ID, Request Date, Requester. | **Mark Deactivated** (`Complete`), **Reject**. | • **Mark Deactivated**: Dialog with optional remarks.<br>• **Reject**: Dialog with required `Rejection Reason *` and remarks. Atomically reopens vacancy or reverts separation status. |
| **7** | **Applicant Movements (AMR)** | `ApplicantMovementRequestScreen` (Tabs: `For Approval`, `Approved`, `Rejected`, `Withdrawn`). | **Fallback Pane Only** (Shows pending count, no review cards). | Request Number, Movement Type (`TRANSFER` vs `SWAP`), Source Applicant Name & Current Vacancy, Target Vacancy VCode & Store, Target Applicant (for SWAP), Stated Reason, Approval Stage indicator (`HA` / `Encoder` / `SA`), Retry Execution banner if execution error. | **Approve**, **Reject**, **Retry Execution**, **Withdraw** (for requester). | • **Approve**: Dialog with optional note. Stage advances or final execution occurs.<br>• **Reject**: Dialog with required `Reason *`.<br>• **Retry**: Dialog confirming re-execution of failed server mutation. |
| **8** | **Reliever Endorsements / Coverage Requests** | `MosesHqPoolScreen` (`MosesHqReviewQueueScreen` & `_approveRelieverRequest`) for pool deployments, and `CoverageRequestScreen` for roving groups. | **Fallback Pane Only** (Coverage category links to `/cencom`; Reliever Endorsements unmapped). | **Reliever Request:** Candidate Name, Pool Type (`Reliever`, `Commando`), Requested Store, Requested Account, Start Date, End Date, Reason, Priority.<br>**Coverage Group Request:** Group Name, Account, Position, Target Stores, Request Type (`create`, `add_store`, `remove_store`, `merge`, `dissolve`). | **Approve**, **Reject**, **Withdraw**. | • **Approve Reliever**: Confirmation dialog (creates active workforce assignment).<br>• **Reject Reliever**: Dialog with required `Reason *`.<br>• **Review Coverage Group**: Review modal with decision (`approved` / `rejected`), reviewer remarks, and rejection reason. |
| **9** | **Temporary Access Requests (Temp Permission Overrides)** | `TempPermissionScreen` (`Active` / `History` tabs) with `GrantTempPermissionScreen` modal. | **Missing from Approvals** (Currently only exists as a sub-route under Settings/Security on web). | User Full Name, Base Role, Current Scope, Additional Groups granted, Granted By, Expiry Date countdown pill (`Expires in Xd`), Reason, Notification flag. | **Revoke Access**, **Grant Access** (Admin creation action). | • **Grant Access**: User dropdown, Additional Group checkboxes, Expiry Date picker, Reason, Notify User switch.<br>• **Revoke**: Confirmation dialog detailing immediate permission strip. |

---

## 3. Schema & RPC Mapping

All request approval and rejection actions across mobile and web are backed by PostgreSQL RPCs or authoritative views. Direct table updates without atomic triggers are strictly forbidden.

### 3.1 Category 1: Headcount Amendments & Standard HC
- **Primary Tables/Views:** `public.headcount_requests`, `public.vacancies`, `public.v_store_quota_headcount`
- **Listing Query:**
  ```sql
  SELECT * FROM public.headcount_requests 
  WHERE status ILIKE 'pending' OR status ILIKE 'under_review' 
  ORDER BY created_at DESC;
  ```
- **RPC Signatures:**
  ```sql
  -- Standard Headcount Approval:
  public.approve_headcount_request(p_request_id uuid, p_remarks text DEFAULT '') RETURNS jsonb;

  -- Quota Amendment Approval (Authoritative Delta Revision):
  public.approve_headcount_amendment_request(p_request_id uuid, p_remarks text DEFAULT '') RETURNS jsonb;

  -- Rejection (Both Standard and Amendment):
  public.reject_headcount_request(p_request_id uuid, p_remarks text DEFAULT '') RETURNS jsonb;

  -- Downstream VCODE Generation (Post-approval):
  public.generate_vcode_from_headcount_request(p_request_id uuid) RETURNS jsonb;

  -- Downstream HC Reduction Execution (Post-approval):
  public.execute_hc_reduction(p_request_id uuid) RETURNS jsonb;
  ```

### 3.2 Category 2: New Store Requests
- **Primary Tables/Views:** `public.new_store_requests`, `public.stores`
- **Listing Query:**
  ```sql
  -- Mobile uses RPC get_new_store_requests() or direct filtered view:
  SELECT * FROM public.new_store_requests 
  WHERE status = 'pending' 
  ORDER BY requested_at DESC;
  ```
- **RPC Signatures:**
  ```sql
  -- Approval: Activates store or creates verified store record
  public.approve_new_store_request(p_request_id uuid) RETURNS jsonb;

  -- Rejection:
  public.reject_new_store_request(p_request_id uuid, p_reason text) RETURNS jsonb;

  -- Submission:
  public.submit_new_store_request(
    p_store_name text, 
    p_province text, 
    p_city text, 
    p_account_id uuid, 
    p_reason text
  ) RETURNS jsonb;
  ```

### 3.3 Category 3: Store Transfers (Global Store Transfer & Account Group Transfer)
- **Primary Tables/Views:** `public.account_group_transfer_requests`, `public.v_plantilla_safe`, `public.stores`
- **Listing Queries:**
  ```sql
  SELECT * FROM public.account_group_transfer_requests 
  WHERE status = 'pending' 
  ORDER BY created_at DESC;
  ```
- **RPC Signatures:**
  ```sql
  -- Account Group Transfer:
  public.simulate_account_group_transfer(p_account_id uuid, p_to_group_id uuid) RETURNS jsonb;
  public.submit_account_group_transfer_request(p_account_id uuid, p_to_group_id uuid, p_reason text) RETURNS text;
  public.approve_account_group_transfer_request(p_request_id uuid) RETURNS void;
  public.reject_account_group_transfer_request(p_request_id uuid, p_reason text) RETURNS void;

  -- Global Store Transfer (Batch employee store reassignment):
  public.get_plantilla_scope_menu() RETURNS TABLE(...);
  public.get_accounts_by_group(p_group_id uuid) RETURNS TABLE(...);
  ```

### 3.4 Category 4: Vacancy Closures
- **Primary Tables/Views:** `public.vacancy_closure_requests`, `public.vacancies`
- **Listing Query:**
  ```sql
  SELECT * FROM public.vacancy_closure_requests 
  ORDER BY created_at DESC;
  ```
- **RPC / Mutation Signatures:**
  ```sql
  -- Single Closure Review (triggers automatic vacancy archival):
  public.review_vacancy_closure_request(
    p_request_id uuid, 
    p_status text, -- 'Approved' | 'Rejected'
    p_reviewed_by text, 
    p_remarks text DEFAULT NULL
  ) RETURNS void;

  -- Bulk Closure Approval (Admin / Super Admin):
  public.approve_all_vacancy_closure_requests() RETURNS jsonb; -- returns {approved_count, skipped_count}
  ```

### 3.5 Category 5: HR Emploc Deletions
- **Primary Tables/Views:** `public.hr_emploc_deletion_requests`, `public.hr_emploc`, `public.vacancies`
- **Listing Query:**
  ```sql
  SELECT * FROM public.hr_emploc_deletion_requests 
  ORDER BY created_at DESC;
  ```
- **RPC Signatures:**
  ```sql
  -- Submission:
  public.fn_request_emploc_deletion(
    p_hr_emploc_id uuid, 
    p_deletion_type text, -- 'Backout' | 'Duplicate Record'
    p_reason text, 
    p_duplicate_of_id uuid DEFAULT NULL
  ) RETURNS jsonb;

  -- Approval (handles optional slot reopening and expungement):
  public.fn_approve_emploc_deletion_request(
    p_request_id uuid, 
    p_reopen_vacancy boolean DEFAULT false, 
    p_notes text DEFAULT NULL
  ) RETURNS jsonb;

  -- Rejection:
  public.fn_reject_emploc_deletion_request(
    p_request_id uuid, 
    p_rejection_reason text
  ) RETURNS jsonb;

  -- Withdrawal (Requester):
  public.fn_withdraw_emploc_deletion_request(p_request_id uuid) RETURNS jsonb;
  ```

### 3.6 Category 6: Account Deactivations
- **Primary Tables/Views:** `public.deactivation_requests`, `public.v_deactivation_requests`, `public.deactivation_batches`, `public.plantilla`
- **Listing Query:**
  ```sql
  SELECT * FROM public.v_deactivation_requests 
  WHERE status ILIKE 'pending' 
  ORDER BY created_at DESC;
  ```
- **RPC Signatures:**
  ```sql
  -- Request Submission:
  public.plantilla_request_deactivation(p_plantilla_id uuid, p_reason text) RETURNS void;

  -- Completion (Backoffice / Super Admin):
  public.complete_employee_deactivation(p_plantilla_id uuid, p_remarks text DEFAULT NULL) RETURNS void;

  -- Rejection (Reverts separation status and reopens vacancy if applicable):
  public.plantilla_update_separation(
    p_plantilla_id uuid, 
    p_separation_status text, 
    p_effective_date date, 
    p_remarks text, 
    p_open_vacancy boolean
  ) RETURNS void;
  ```

### 3.7 Category 7: Applicant Movements (AMR)
- **Primary Tables/Views:** `public.applicant_movement_requests`, `public.applicant_movement_request_history`, `public.applicants`, `public.vacancies`
- **Listing RPC:**
  ```sql
  public.get_applicant_movement_requests(p_filter jsonb) RETURNS TABLE(...);
  -- Filter accepts: { "mine_only": boolean, "status": text, "movement_type": text }
  ```
- **RPC Signatures:**
  ```sql
  -- Submission (TRANSFER or SWAP):
  public.create_applicant_movement_request(
    p_movement_type text, -- 'TRANSFER' | 'SWAP'
    p_source_applicant_id uuid, 
    p_target_vacancy_vcode text, 
    p_target_applicant_id uuid DEFAULT NULL, 
    p_reason text, 
    p_remarks text DEFAULT NULL
  ) RETURNS jsonb;

  -- Approval (Stage advancement or final server-side execution):
  public.approve_applicant_movement_request(
    p_request_id uuid, 
    p_note text DEFAULT NULL
  ) RETURNS jsonb;

  -- Rejection:
  public.reject_applicant_movement_request(
    p_request_id uuid, 
    p_reason text
  ) RETURNS void;

  -- Withdrawal (Requester):
  public.withdraw_applicant_movement_request(p_request_id uuid) RETURNS void;
  ```

### 3.8 Category 8: Reliever Endorsements & Coverage Requests
- **Primary Tables/Views:** `public.workforce_assignment_requests`, `public.coverage_requests`, `public.coverage_request_history`, `public.workforce_pool_slots`
- **Listing Queries:**
  ```sql
  -- Reliever Pool Assignment Requests:
  SELECT * FROM public.workforce_assignment_requests 
  WHERE status = 'Pending' 
  ORDER BY created_at DESC;

  -- Coverage Group Mutation Requests:
  SELECT * FROM public.coverage_requests 
  WHERE archived_at IS NULL AND status = 'pending' 
  ORDER BY created_at DESC;
  ```
- **RPC Signatures:**
  ```sql
  -- Reliever Coverage Submission:
  public.request_reliever_coverage(
    p_employee_id uuid, 
    p_pool_type_id uuid, 
    p_requested_group_id uuid DEFAULT NULL, 
    p_requested_account_id uuid DEFAULT NULL, 
    p_requested_store_id uuid DEFAULT NULL, 
    p_requested_position text DEFAULT NULL, 
    p_priority text DEFAULT 'normal', 
    p_start_date date DEFAULT NULL, 
    p_end_date date DEFAULT NULL, 
    p_reason text DEFAULT NULL
  ) RETURNS TABLE(request_id uuid, employee_id uuid, status text, message text);

  -- Reliever Approval:
  public.approve_reliever_coverage_request(
    p_request_id uuid, 
    p_assigned_employee_id uuid DEFAULT NULL, 
    p_notes text DEFAULT NULL
  ) RETURNS TABLE(request_id uuid, assignment_id uuid, status text, message text);

  -- Reliever Rejection:
  public.reject_reliever_coverage_request(p_request_id uuid, p_rejection_reason text) RETURNS void;

  -- Reliever Withdrawal:
  public.withdraw_reliever_coverage_request(p_request_id uuid, p_reason text DEFAULT NULL) RETURNS void;

  -- Coverage Group Request Workflow:
  public.review_coverage_request(
    p_coverage_request_id uuid, 
    p_decision text, -- 'approved' | 'rejected'
    p_reviewer_remarks text DEFAULT NULL, 
    p_rejection_reason text DEFAULT NULL
  ) RETURNS jsonb;
  public.approve_coverage_request(
    p_coverage_request_id uuid, 
    p_reviewer_remarks text DEFAULT NULL, 
    p_employee_home_stores jsonb DEFAULT NULL
  ) RETURNS jsonb;
  public.reject_coverage_request(
    p_coverage_request_id uuid, 
    p_rejection_reason text, 
    p_reviewer_remarks text DEFAULT NULL
  ) RETURNS jsonb;
  ```

### 3.9 Category 9: Temporary Access Requests (Permission Overrides)
- **Primary Tables/Views:** `public.temp_permission_overrides`, `public.users_profile`, `public.roles`, `public.groups`
- **Listing Query:**
  ```sql
  SELECT o.*, u.full_name, r.role_name 
  FROM public.temp_permission_overrides o
  JOIN public.users_profile u ON u.id = o.user_id
  LEFT JOIN public.roles r ON r.id = u.role_id
  ORDER BY o.created_at DESC;
  ```
- **RPC Signatures:**
  ```sql
  -- Grant Temporary Permission Override:
  public.grant_temp_permission_override(
    p_user_id uuid, 
    p_additional_groups text[], 
    p_expires_at timestamptz, 
    p_reason text DEFAULT NULL, 
    p_notify_user boolean DEFAULT true, 
    p_granted_by text DEFAULT NULL
  ) RETURNS void;

  -- Revoke Temporary Permission Override:
  public.revoke_temp_permission_override(
    p_override_id uuid, 
    p_revoked_by text
  ) RETURNS void;
  ```

---

## 4. Parity Gap Analysis

### 4.1 Summary Status by Category

| Category Key | Category Name | Web Current State | Operational Parity Status | Primary Gap & Work Needed |
| :--- | :--- | :--- | :--- | :--- |
| `headcount` | Headcount Amendments & Standard HC | **In-Place Cards** (`HeadcountAmendmentApprovalCard`, `HeadcountStandardApprovalCard`) | **100% Operational Parity** | Production-ready with live safety floor queries and delta badges. |
| `hr_emploc_deletions` | HR Emploc Deletions | **In-Place Card** (`HrEmplocDeletionReviewCard`) | **100% Operational Parity** | Production-ready with Step 1/2 vacancy reopening toggle. |
| `new_stores` | New Store Requests | **Fallback Pane** | **0% Review Parity** (Missing card) | Needs `NewStoreApprovalCard.tsx` + `approve_new_store_request` / `reject_new_store_request` mutations. Add "Request HC" bridge for approved stores. |
| `vacancy_closures` | Vacancy Closures | **Fallback Link** (Points to `/vacancy`) | **0% Review Parity** (External Link) | Needs in-place `VacancyClosureReviewCard.tsx` + "Approve All" batch action button via `approve_all_vacancy_closure_requests`. |
| `applicant_movements` | Applicant Movements (AMR) | **Fallback Pane** | **0% Review Parity** (No review view) | Needs `ApplicantMovementReviewCard.tsx` supporting TRANSFER / SWAP, stage awareness (`For Approval` vs status tabs), and `approve_applicant_movement_request`. |
| `deactivations` | Deactivations | **Fallback Link** (Points to `/plantilla`) | **0% Review Parity** (External Link) | Needs `DeactivationReviewCard.tsx` with employee profile context, separation reason, and `complete_employee_deactivation` / `plantilla_update_separation` RPC wiring. |
| `coverage` | Coverage (CENCOM) | **Fallback Link** (Points to `/cencom`) | **0% Review Parity** (External Link) | Needs `CoverageRequestReviewCard.tsx` with request payload inspector (`add_store`, `create`, `merge`) and `review_coverage_request` RPC wiring. |
| `account_group_transfers` | Account Group Transfers | **Fallback Pane** | **0% Review Parity** (No review view) | Needs `AccountGroupTransferReviewCard.tsx` displaying simulation impacts (affected stores/employees) and `approve_account_group_transfer_request` / `reject_account_group_transfer_request` RPC wiring. |
| `relievers` & `temp_access` | Reliever Endorsements & Temp Overrides | **Excluded from Approvals Navigation** (Only 8 categories currently in web) | **0% Integration** | Web navigation combines or omits Relievers and Temp Overrides from Request Center navigation. Need to either introduce dedicated categories or embed them as dedicated sub-views. |

### 4.2 Structural Architectural Deficits in Web
1. **Fallback Pane Dominance:** 6 out of the 8 categories in `RequestCategoryNavigation` currently render static `Building2` info cards that route the user away from Approvals to disparate modules (`/cencom`, `/vacancy`, `/plantilla`), breaking the single-pane-of-glass administrative review promise.
2. **Missing Category Representation:** Mobile actively tracks **9 categories** (including Reliever Endorsements from workforce pool and Temporary Permission Overrides), while the web [`REQUEST_CATEGORIES`](file:///d:/Projects/ohmployee-web/src/lib/queries/requests.ts#L21) array only defines 8 items (omitting Reliever Endorsements and Temp Overrides).
3. **Filter Tab Inconsistency:** While mobile provides quick state filtering (`Pending`, `Approved`, `Rejected`) or sub-queue toggles for each category, the web right pane only provides sub-filtering for Headcount (`All`, `Quota Amendments`, `Standard Headcount`).
4. **Bulk Actions Absent:** Mobile supports high-efficiency batch processing (e.g. `Approve All` for Vacancy Closures and `Approve Valid` for Global Store Transfers), whereas web lacks bulk resolution toolbars.

---

## 5. Prioritized Parity Roadmap & Step-by-Step Implementation Plan

To achieve 1-to-1 operational parity between Web and Mobile without regression, implementation should follow a prioritized 4-phase roadmap.

```mermaid
flowchart TD
    subgraph Phase 1: High-Frequency Operational Approvals
        P1A["New Store Request In-Place Card & Review"]
        P1B["Vacancy Closure In-Place Card & Bulk Approve"]
    end

    subgraph Phase 2: Personnel & Separation Workflows
        P2A["Applicant Movement Review Card (TRANSFER / SWAP)"]
        P2B["Deactivation Review Card (Separation Clearance)"]
    end

    subgraph Phase 3: Structural & Group Governance
        P3A["Account Group Transfer Review Card & Simulation"]
        P3B["Coverage Group Request Review Card (CENCOM)"]
    end

    subgraph Phase 4: Workforce Pool & Access Controls
        P4A["Reliever Coverage Request Approval Card"]
        P4B["Temporary Permission Overrides Audit & Revocation"]
        P4C["Request Center Navigation Expansion (Full 9 Categories)"]
    end

    Phase 1 --> Phase 2
    Phase 2 --> Phase 3
    Phase 3 --> Phase 4
```

### Phase 1: High-Frequency Operational Approvals (Immediate Parity)
1. **New Store Requests (`new_stores`):**
   - Create `src/components/approvals/NewStoreApprovalCard.tsx`.
   - Wire `approve_new_store_request` and `reject_new_store_request` RPC hooks in `src/lib/queries/requests.ts`.
   - Add rejection dialog requiring a non-empty `reason`.
   - Add post-approval action: "Submit Headcount Request for this Store" (prepopulating store, province, city, and account).
2. **Vacancy Closures (`vacancy_closures`):**
   - Create `src/components/approvals/VacancyClosureApprovalCard.tsx`.
   - Wire `review_vacancy_closure_request` for individual Approve and Reject (with required remarks).
   - Add an "Approve All Pending" toolbar button triggering `approve_all_vacancy_closure_requests` with confirmation modal showing item count.

### Phase 2: Personnel & Separation Workflows
1. **Applicant Movements (`applicant_movements`):**
   - Create `src/components/approvals/ApplicantMovementReviewCard.tsx`.
   - Display movement type badges (`TRANSFER` vs `SWAP`), source applicant, source vacancy, target vacancy, and target applicant.
   - Display approval stage badge (`HA`, `Encoder`, `SA`) and execution status.
   - Wire `approve_applicant_movement_request`, `reject_applicant_movement_request`, and retry execution logic.
2. **Deactivations (`deactivations`):**
   - Create `src/components/approvals/DeactivationReviewCard.tsx`.
   - Display employee name, employee number, separation type, and batch number.
   - Wire `complete_employee_deactivation` (Mark Deactivated) and `plantilla_update_separation` (Reject and revert).

### Phase 3: Structural & Group Governance
1. **Account Group Transfers (`account_group_transfers`):**
   - Create `src/components/approvals/AccountGroupTransferReviewCard.tsx`.
   - Display source group, target group, reason, and simulation payload summary.
   - Wire `approve_account_group_transfer_request` and `reject_account_group_transfer_request`.
2. **Coverage Requests (`coverage`):**
   - Create `src/components/approvals/CoverageRequestReviewCard.tsx`.
   - Render request type badges (`create_coverage_group`, `add_store`, `remove_store`, `merge`, `dissolve`).
   - Display impacted stores and target roles.
   - Wire `review_coverage_request`, `approve_coverage_request`, and `reject_coverage_request`.

### Phase 4: Workforce Pool & Access Controls
1. **Reliever Endorsements / Coverage Requests (`relievers`):**
   - Add `relievers` to `REQUEST_CATEGORIES` in `src/lib/queries/requests.ts`.
   - Query `workforce_assignment_requests` for pending reliever coverage.
   - Create `src/components/approvals/RelieverCoverageApprovalCard.tsx`.
   - Wire `approve_reliever_coverage_request` and `reject_reliever_coverage_request`.
2. **Temporary Access Requests (`temp_access`):**
   - Add `temp_access` to `REQUEST_CATEGORIES` or create an Admin Overrides tab in Approvals.
   - Create `src/components/approvals/TempPermissionReviewCard.tsx`.
   - Wire `revoke_temp_permission_override` and embed access granting trigger.
3. **Unified Navigation & Badge Polish:**
   - Update `fetchRequestCategoryCounts()` to query pending counts for all 9 categories with resilient error handling.
   - Ensure clear-on-click badge acknowledgment persists per session.
   - Add status sub-filters (`Pending`, `Approved`, `Rejected`) to all categories in `ActiveQueueReviewPane.tsx`.

---

## 6. Verification & Validation Rules
- **Security Check:** All write actions must verify caller permissions against user role level (`Super Admin`, `Head Admin`, `Data Team`, or `Encoder`) matching backend `SECURITY DEFINER` RPC rules.
- **Audit Logging:** Every approval and rejection mutation must emit a corresponding record in the audit timeline (`audit_logs` or domain-specific history table).
- **Zero Fallback Target:** When Phase 4 completes, all 9 request categories must provide immediate, in-place review cards inside `ActiveQueueReviewPane.tsx` without routing users away to external modules.
