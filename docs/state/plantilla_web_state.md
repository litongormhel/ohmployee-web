# Plantilla Web State & Architecture Specification

> [!NOTE]
> **Governing Architecture:** Governed by [ADR-002: Plantilla Import, Store Identity, Headcount Governance & Rollback Architecture](../architecture/adr002_plantilla_import_store_identity_and_governance.md).
> Key rules: 1 Store Name = 1 Permanent VCODE; Vacant baseline imports allowed; Auto-computed roving headcount fractions ($1/N$); Strict middle name rules; Per-Account HRCO auto-population and reactive backfill; 72-hour rollback window with strict Zero-Edit Lock.

## 1. Scope & Core Purpose

This document specifies the target architecture, visual structures, data contracts, and user workflows for the **Plantilla Web** module of the OHMployee Web dashboard. 

The **Plantilla** module is the final authority and active directory for all deployed personnel across the organization. In the operational hiring and deployment pipeline, a record progresses through the following canonical stages:

```
Vacancy → Applicant → Endorsed to Ops → Confirmed Onboard → HR Emploc (Onboarding Compliance) → Plantilla Approval (Movement) → Plantilla (Official Active Employee)
```

The core responsibilities of the Plantilla Web module are:
1. **Roster & Directory Authority**: Maintaining the single source of truth for active employee allocations, personal records, and employment statuses.
2. **Budgetary & Capacity Control**: Auditing active store placements against contracted store plantilla capacities to prevent over-allocation.
3. **Headcount Extensions**: Governing requests, reviews, and allocations for temporary or seasonal **Additional Headcount (AH)**.
4. **Personnel Movements**: Tracking active transfers, roving assignments, and multi-store scheduling splits.
5. **Clearance & Offboarding**: Executing clean **Separation Workflows** (Resignations, Terminations, Backouts) backed by interactive clearance tracking and row edit overlays.

Like other modules in OHMployee Web, this is designed as a thin admin presentation layer. **Supabase is the absolute authority** for data access scopes, Row-Level Security (RLS) enforcement, notification dispatch, and transactional mutations.

---

## 2. Dual Views Architecture (Employee vs. Store)

Admin users need to switch between reviewing individual active personnel and auditing store capacity compliance. The Plantilla module solves this by implementing **Dual Views** driven by a segmented tab controller (`src/components/plantilla/ViewToggle.tsx`) situated in the primary filter toolbar:

```
[ Plantilla Directory ]
=======================================================================================
[ Metric Card: Active Roster ] [ Metric Card: Budget Slots ] [ Metric Card: AH Slots ] [ Metric Card: Under-Staffed ]
---------------------------------------------------------------------------------------
Search: "Search by employee, store, or VCode..."      [ View: Employee Centric ] [ View: Store Centric ]
=======================================================================================
```

### A. Employee-Centric View
This is the default view. Each row represents an active employee currently deployed to a store plantilla slot.

```
[Employee Roster Grid Viewport (Scrollable horizontally, min-width: 1120px)]
-----------------------------------------------------------------------------------------------------------------------------
Emp ID     | Name              | Account / Location         | Position     | Assignment | Type     | Status     | Actions
-----------------------------------------------------------------------------------------------------------------------------
EMP-001042 | Santos, Maria     | Cebu Regional / Cebu Mall  | Merchandiser | Stationary | Budgeted | Active     | [Eye]
EMP-001099 | Cruz, Juan        | Manila Region / Hub 1      | Promodiser   | Roving (3) | Budgeted | Transfer   | [Eye] [SLA Warn]
EMP-001101 | Del Rosario, A.   | Davao South / Davao Hub    | Coordinator  | Stationary | AH (Temp)| Sep Pending| [Eye] [Lock]
```

#### Column Structure (Employee View):
1. **Employee ID**: `employee_no` (Rendered in monospaced style: `font-mono text-xs text-gray-700 bg-gray-50 border border-gray-100 rounded px-1.5 py-0.5`).
2. **Employee Name**: Combined `last_name, first_name` from profile metadata.
3. **Account & Store (Primary)**: The primary deployment location (`account` / `store_name`).
4. **Position Title**: Deployed role designation (e.g., 'Merchandiser', 'Promodiser').
5. **Assignment Type**: 
   - `assignment_type` ('Stationary' or 'Roving').
   - If 'Roving', a hoverable badge showing covered store counts (e.g. `Roving (3)`) with a tooltip listing the other covered stores.
6. **Plantilla Type**:
   - `Budgeted`: Deployed against standard store capacity contracts.
   - `AH (Temp)`: Deployed to a temporary, seasonal Additional Headcount slot.
7. **Status Badge**: Maps `plantilla_status` via `StatusBadge`:
   - `Active` → `success` (green)
   - `Pending Transfer` → `info` (blue)
   - `Pending Separation` → `danger` (rose)
   - `Suspended` → `warning` (amber)
   - `Inactive` → `neutral` (gray)
8. **Actions**: Desktop "Eye" icon to open the selected record in the Plantilla Detail Drawer. Row clicking is also fully supported with an active overlay highlight (`bg-blue-50`).

---

### B. Store-Centric View
This view switches focus to store capacity metrics. Each row represents a specific store's staffing capacity and MFR breakdown (OHM2026_1132 contract).

```
[Store Plantilla Grid Viewport (Scrollable horizontally, min-width: 1400px)]
-----------------------------------------------------------------------------------------------------------------------------------
Store Code | Store Name        | Account / Region           | Actual | HR Pipeline | Vacancy | Required | MFR %  | Risk      | SLA
-----------------------------------------------------------------------------------------------------------------------------------
STR-C042   | Cebu Mall         | Cebu Regional / Visayas    | 4      | 1           | 1       | 5        | 66.7%  | Medium    | Fully-Staffed
STR-M099   | Manila Hub 1      | Manila Region / NCR        | 1      | 1           | 2       | 3        | 25.0%  | High      | Under-Staffed
STR-D101   | Davao Hub         | Davao South / Mindanao     | 4      | 0           | 0       | 4        | 100.0% | Low       | Fully-Staffed
```

#### MFR Breakdown Column Structure (Store View — OHM2026_1132):

The store staffing table renders the MFR breakdown sourced from `list_web_plantilla_store_staffing()`. The formula is displayed as a column tooltip:

**MFR % = Actual / (Actual + HR Pipeline + Vacancy)**

| Column | Backend Field | Description |
|--------|--------------|-------------|
| Store Code | `store_code` | Monospaced store identifier |
| Store Name | `store_name` | Display name |
| Account / Region | `account_name`, `region` | Billing account and region |
| **Actual** | `onboard_count` | Confirmed onboarded headcount |
| **HR Pipeline** | `hr_pipeline_count` | In-progress hires/deployments |
| **Vacancy** | `open_headcount` | Open unfilled slots (SLA warning if ≥ 7 days) |
| **Required** | `required_headcount` | Contracted staffing target |
| **MFR %** | `fill_rate` | Backend-computed; formula: Actual / (Actual + HR Pipeline + Vacancy) |
| Staffing Risk | `staffing_risk` | Backend-returned risk level badge |
| SLA Badge | `sla_badge` | Under/Fully/Over-staffed badge |

**Guardrail**: The `fill_rate` is sourced from the backend only. The web layer does NOT compute MFR. Any future web-side MFR derivation must include HR Pipeline in the denominator — computing `Actual / Required` is incorrect and excluded by design.

---

## 3. Scoped RBAC Visibility & RLS Boundaries

Web presentations are governed strictly by the capabilities returned from `get_web_current_user_context()`. The Supabase backend enforces access boundaries at the table level using PostgreSQL Row-Level Security (RLS) policies.

```
                             [Role Access Matrix]
========================================================================================================================
Role             | Read Scope       | Personal PII Masking | Mutations (RPCs Allowed)
========================================================================================================================
superAdmin       | Global           | Unmasked             | Full transfers, separations, AH approvals, salary overrides
------------------------------------------------------------------------------------------------------------------------
headAdmin        | Global           | Unmasked             | Approve transfers, approve separations, review AH, adjust rates
------------------------------------------------------------------------------------------------------------------------
Encoder          | Scoped           | Unmasked             | Edit employee profiles, upload clearances, initiate transfers
                 | (Allowed Accts)  |                      | (BLOCKED: Final separation & rate approval)
------------------------------------------------------------------------------------------------------------------------
hrPersonnel      | Global           | Unmasked             | Verify clearances, initiate separations, audit roving coverages
------------------------------------------------------------------------------------------------------------------------
om               | Scoped           | Masked               | Request personnel transfers, request Additional Headcount (AH),
                 | (Allowed Accts)  |                      | initiate separation workflows for account staff
------------------------------------------------------------------------------------------------------------------------
hrco             | Scoped           | Masked               | Upload clearance files, submit transfer recommendations,
                 | (Allowed Accts)  |                      | report resignations/backouts
------------------------------------------------------------------------------------------------------------------------
atl / tl         | Scoped           | Masked               | Read-only scoped directory view. Roving check-ins audit.
------------------------------------------------------------------------------------------------------------------------
viewer           | Scoped           | Masked               | Read-only. (Mutation RPCs strictly blocked)
========================================================================================================================
```

* **Caller Validation**: All queries and RPCs fetch caller metadata directly from `auth.uid()`. The frontend never passes `profile_id` or `role_key` as arguments.
* **Scope Isolation**: In scoped roles (e.g. `om`, `hrco`), the backend filters all records to match the caller's authorized account and group list. If a scoped caller requests details for a personnel outside their hierarchy, the RPC raises an access-denied error.

---

## 4. Masking Rules (PII Shielding)

To satisfy strict data privacy mandates, sensitive candidate details must be hidden or partially masked when displayed to non-authorized roles.

### A. Masked Fields & Formats:
1. **Personal Contact Number**:
   - *Format*: Mask all but country prefix and last 2 digits.
   - *Example*: `+63 917 *** **42`
2. **Personal Email Address**:
   - *Format*: Mask characters in the username, leaving only first character and domain.
   - *Example*: `s****s@domain.com`
3. **Residential Address**:
   - *Format*: Mask precise house numbers and streets, leaving only Barangay and City.
   - *Example*: `Unit ***, ******* Blvd, Cebu City`
4. **Base Salary & Day Rate**:
   - *Format*: Replace numerical characters with asterisks or replace the string entirely.
   - *Example*: `₱**,***.**` (or fully display `[RESTRICTED]`).
5. **Government IDs (SSS, PhilHealth, PagIBIG, TIN)**:
   - *Format*: Mask all but the last 2 digits.
   - *Example*: `03-****42-9`

### B. Security Enforcement Boundary (Backend Masking):
PII masking is **enforced at the database query layer (within SQL functions)** rather than on the client. 

The backend RPC checks the caller's role context via `get_web_current_user_context()`. If the user is a restricted role (`om`, `hrco`, `atl`, `tl`, `viewer`), the RPC returns already-masked strings. This guarantees that raw, unmasked PII is **never sent over the network**, preventing local memory audits or client console inspections from capturing sensitive information.

---

## 5. Deactivation Overlays & Status Styling

Personnel in deactivated, suspended, or pending separation states require immediate, prominent visual identifiers in the administrative grid. This prevents operational errors such as scheduling or deploying workers who are no longer active.

```
+-----------------------------------------------------------------------+
| Row: Active Employee (Normal display)                                 |
| EMP-001042  Santos, Maria      Cebu Regional     Active               |
+-----------------------------------------------------------------------+
| Row: Pending Separation (Dashed borders, 65% opacity overlay)         |
| ░░░ EMP-001101  Del Rosario, A.   Davao South    [Sep Pending]  ░░░░░  |
+-----------------------------------------------------------------------+
| Row: Inactive / Terminated (Dimmed grey background, crossed-out style)|
| [<s>EMP-001202  Abad, Clara       Manila Region  Terminated</s>]       |
+-----------------------------------------------------------------------+
```

### A. CSS / Tailwind Class Rules:
1. **Pending Separation**:
   - Row wrapper gains a dashed border: `border-dashed border-status-danger-border`.
   - Slight dimmed overlay: `opacity-80`.
   - Subtle alert highlight: `bg-red-50/30`.
2. **Inactive / Terminated / Suspended**:
   - Row opacity is dimmed: `opacity-65`.
   - Hover highlights are disabled: `hover:bg-transparent pointer-events-none`.
   - Font colors are grayed out: `text-gray-400`.
   - monospaced IDs and Names get strikethrough styling: `line-through decoration-gray-300`.

### B. Drawer Warnings:
When a deactivated or separation-pending record is viewed, the detail drawer renders an immediate top-anchored banner:
* **Pending Separation Banner**: `bg-status-danger-bg border border-status-danger-border text-status-danger-text p-3 rounded-md flex items-center gap-2 mb-4` showing: *"This employee has an active separation request pending clearance approval. Roster details are currently locked."*
* **Deactivated Banner**: `bg-status-neutral-bg border border-status-neutral-border text-status-neutral-text p-3 rounded-md flex items-center gap-2 mb-4` showing: *"This profile is INACTIVE. This record is locked and archived."*

---

## 6. Separation Workflows & Clearance Auditing

Transitioning a personnel out of the active Plantilla roster is a multi-step operation to ensure organizational clearances are satisfied before archiving the profile.

```
                   [Separation Workflow State Machine]
                                 
      +--------+     (Initiate Separation)     +--------------------+
      | ACTIVE | ────────────────────────────> | PENDING SEPARATION |
      +--------+                               +--------------------+
                                                         │
                                               (Complete Checklist)
                                               (Approve Clearance)
                                                         │
                                                         ▼
                                               +--------------------+
                                               | INACTIVE / ARCHIVED|
                                               +--------------------+
```

### A. Separation Types & Visual Triggers:
1. **Resignation (Voluntary)**:
   - *Requires*: Upload of signed resignation letter, 30-day notice period tracking, asset return checklist.
2. **Termination (Involuntary)**:
   - *Requires*: Upload of memo/disciplinary filings, immediate scheduling block, asset return checklist.
3. **Backout (Day 1 No-Show)**:
   - *Requires*: Coordinator confirmation. 
   - *System Action*: Deactivates the plantilla record and **automatically reopens** the corresponding original Vacancy slot (changes `vacancies.status` back to `Open` and increments open targets) so the recruiter can immediately fill it.
4. **Administrative Archive**:
   - *Use Case*: Fixing duplicate placements or data-entry errors. Archives the record without modifying vacancy metrics.

### B. Clearance Auditing Checklist (Detail Drawer View):
The detail drawer renders an interactive clearance board for records in `Pending Separation` status:
* **Asset Returns Checklist**:
  - `[ ]` Company Uniform Returned
  - `[ ]` Company ID Card Surrendered
  - `[ ]` Mobile SIM/Device Returned
* **Compliance Checks**:
  - `[ ]` Government ID Verification (SSS, PagIBIG, PhilHealth matches verified)
  - `[ ]` Handover Documentation Completed
* **Clearance File Attachment**: File uploader for signed clearance forms.
* **Separation Action Lock**: While `Pending Separation` is active, all other mutations (such as processing store transfers, editing base rates, or adding roving locations) are **strictly blocked and disabled**.

---

## 7. Additional Headcount (AH) Integration

Retailers often require temporary, seasonal, or campaign-based personnel who sit outside standard budgeted allocations. The Plantilla module integrates budgeted and temporary staffing into a single schema while preserving separate compliance rails.

### A. Budgeted vs. Additional Headcount (AH):
* **Budgeted Slots**: Contractual, long-term headcount targets approved at the Account/Store level (e.g. Cebu Mall is contracted for exactly 5 long-term Merchandisers). Deploys to these slots require matching available budget vacancy slots.
* **Additional Headcount (AH)**: Temporary slots created for specific durations (e.g., "Holiday Campaign 2026", "Store Launch Promo"). They require an approved business justification, target headcount size, and strict expiry dates.

### B. Additional Headcount Roster Workflow:
1. **Initiate Request**: Ops Managers (`om`) or Field Coordinators (`hrco`) submit an Additional Headcount Request through the dashboard, indicating target Store, Position, Count needed, Start Date, Expiry Date, and Business Justification.
2. **Approval Gateway**: The request is routed to the Approvals queue. `headAdmin` or `superAdmin` reviews and approves/rejects the request.
3. **Plantilla Adjustment**: Upon approval, the target store's available plantilla capacity is dynamically incremented by the approved amount under the `Additional` category.
4. **Personnel Assignment**: HRCOs can deploy incoming hires directly into these approved temporary slots. These employees are explicitly marked in the roster with `Plantilla Type = Additional Headcount`.

### C. Visual Indicators & Expiry Countdown Tickers:
* **Roster Badge**: Displays an orange-bordered semantic badge next to the employee name or type column: `bg-amber-50 border border-status-warning-border text-status-warning-text rounded px-1.5 py-0.5 text-xs font-semibold tracking-wide`.
* **Expiry countdown ticker**: If an AH personnel's slot is within 15 days of expiration, the detail drawer displays a countdown badge:
  - *Within 15 days*: `[Expires in 12 days]` in amber warning styling.
  - *Lapsed/Expired*: `[EXPIRED]` in rose danger styling with a recommendation to initiate a transfer or separation workflow.

---

## 8. Plantilla Detail Drawer UX & Content Structure

When a row is clicked in the main grid, the Plantilla Detail Drawer slides overlaying the list from the right. It utilizes the `DetailDrawer` shared container, locked to `drawer-width-lg` (`640px`) to handle dense layouts.

```
+-----------------------------------------------------------------------+
|  Account / Location Hierarchy Breadcrumbs                        [X]  |
|                                                                       |
|  [H1] SANTOS, MARIA                                                   |
|  Employee ID: EMP-001042 (Monospace Badge)                            |
|  Type: [Budgeted]        Status: [Active (success)]                    |
+-----------------------------------------------------------------------+
|  Employment & Allocation (Grid)                                       |
|  - Date Deployed: 2025-01-15     - Position: Field Merchandiser       |
|  - Account: Cebu Regional Account- Primary Store: Cebu Mall           |
|  - Base Rate: ₱560.00 / day      - Tenure: 1 Year, 4 Months           |
+-----------------------------------------------------------------------+
|  Roving Coverage Assignments                                          |
|  [Assignment: Roving]                                                 |
|  - Cebu Mall (Primary - 60% Allocation)                               |
|  - Cebu Plaza Store (Roving - 20% Allocation)                         |
|  - Mandaue Hub (Roving - 20% Allocation)                              |
+-----------------------------------------------------------------------+
|  Clearance & Offboarding Audits                                       |
|  [Status: Pending Separation (resignation)]                            |
|  [ ] Uniform Returned            [x] Company ID Card Surrendered      |
|  [ ] SIM/Device Returned         [x] Handover Document Uploaded       |
|  HR Remarks: "Awaiting uniform return from HRCO before final archive" |
+-----------------------------------------------------------------------+
|  SLA & Transition Performance                                         |
|  - Pending Separation Age: 4 Days                                     |
|  - [!] SLA Breach: Clearance approval has exceeded the 48h SLA window.|
+-----------------------------------------------------------------------+
|  Roster Audit History                                                 |
|  o [Separation Requested] - 4 days ago by Santos, Maria (HRCO)        |
|  o [Transfer Approved]    - 6 months ago by Dela Cruz, Ana (HeadAdmin)|
|  o [Deployed to Plantilla]- 1.3 years ago by System Automatic Trigger |
+-----------------------------------------------------------------------+
|  Capability-Aware Actions (Sticky Bottom)                             |
|  [ Transfer Personnel ]  [ Initiate Separation ]  [ Complete Clearance]|
+-----------------------------------------------------------------------+
```

### Drawer Layout Components:
1. **Header Identification Area**:
   - Employee primary display name (`last_name, first_name`).
   - `employee_no` rendered as a prominent monospace badge.
   - Status Badge and Plantilla Type pill (`Budgeted` vs. `AH`).
   - Location breadcrumbs (`Account / Primary Store / Regional Group`).
2. **Employment Details Grid**:
   - Dynamic data fields: `date_deployed`, `position_title`, `tenure` (calculated dynamically as `now() - date_deployed`), and `base_rate` (rendered as `₱***.**` or fully visible depending on role capability).
3. **Roving Coverage Component**:
   - Displayed only if `assignment_type == 'Roving'`.
   - Renders a micro-grid of covered stores extracted from the `roving_stores` array.
   - Lists the allocation weight (e.g., `60% primary`, `20% secondary`) or active weekly roster coverage.
4. **Clearance Panel**:
   - Active only when `plantilla_status == 'Pending Separation'`.
   - Renders checklist checkboxes, file attachments for signed clearances, and HR coordinator notes.
5. **SLA Warning Block**:
   - Highlighted in soft red if active transitions (like transfers or separations) breach standard operational SLAs.
6. **Roster Audit History Timeline**:
   - Collapsible micro-list of chronological movements, promotions, and changes captured from the database audit log table (`plantilla_audit_logs`).
7. **Capability-Controlled Action Bar**:
   - Uses the shared `CapabilityActionBar` to display context actions dynamically based on resolved `row_capabilities`.
   - Displays actions such as: `Initiate Transfer`, `Initiate Separation`, `Edit Roving Stores`, `Approve Clearance`, and `Toggle Suspend`.

---

## 9. SLA & Status Transition Rules

Operational bottlenecks in personnel movement directly impact retail performance. The system enforces strict timers and escalates breaches:

```
[Transfer Requested] ──(48 Hours SLA Clock)──> [SLA Breached Alert] ──(72 Hours)──> [SuperAdmin Escalated Alert]
```

### A. Personnel Movement Approval SLA:
* **Calculation Baseline**: `movement_requested_at` timestamp.
* **Response Window**: **48 Hours** (2 days).
* **Behavior**: If a transfer or promotion remains in `Pending Approval` beyond 48 hours without action:
  - **SLA Tier 1 Breach**: The status text shifts to red inside the table queue. A warning alert icon displays inside the detail drawer. The dashboard's "SLA Breaches" metric card increments by 1.
  - **SLA Tier 2 Breach (72 Hours)**: An automated notification is sent directly to the `Super Admin` to override or expedite approval.

### B. Store Staffing Vacancy SLA:
* **Calculation Baseline**: The date a store's active budgeted staff falls below the budgeted plantilla target (`STR-V-01` date of vacancy opening).
* **Response Window**: **7 Days** (168 hours).
* **Behavior**: In **Store-Centric View**, if a contracted budgeted slot remains vacant for more than 7 days, the store row displays a red vacancy alarm badge: `[Under-staffed SLA Breach]`. This flags the account to recruiters to prioritize filling the vacancy.

---

## 10. Proposed Database RPC Contracts

To integrate seamlessly with the Supabase thin-client presentation model, we recommend the following backend RPC signatures:

### A. List Employees Contract
```sql
CREATE OR REPLACE FUNCTION public.list_web_plantilla_employees(
  p_search          text    DEFAULT NULL, -- searches employee number or name
  p_account_id      uuid    DEFAULT NULL,
  p_group_id        uuid    DEFAULT NULL,
  p_store_id        uuid    DEFAULT NULL,
  p_employment_status text DEFAULT NULL, -- 'active', 'suspended', 'pending_separation', 'inactive'
  p_deployment      text    DEFAULT NULL, -- 'budgeted', 'additional'
  p_active_state    text    DEFAULT NULL,
  p_limit           integer DEFAULT 50,
  p_offset          integer DEFAULT 0,
  p_sort_by         text    DEFAULT 'employee_name',
  p_sort_dir        text    DEFAULT 'asc'
)
RETURNS TABLE (
  id                    uuid,
  employee_no           text,
  first_name            text,
  last_name             text,
  position_title        text,
  account_name          text,
  primary_store_name    text,
  assignment_type       text, -- 'Stationary', 'Roving'
  covered_stores_count  integer,
  plantilla_type        text, -- 'Budgeted', 'AH'
  plantilla_status      text,
  date_deployed         date,
  tenure_days           integer,
  base_rate_masked      text,
  sla_breached          boolean,
  row_capabilities      jsonb, -- dynamic actions authorized for caller
  total_count           bigint
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

Supported employee sort fields are `employee_name`, `employee_no`, `account_name`, `primary_store_name`, `position_title`, `plantilla_type`, `plantilla_status`, `date_deployed`, and `created_at`.

### B. List Stores Contract
```sql
CREATE OR REPLACE FUNCTION public.list_web_plantilla_store_staffing(
  p_search        text    DEFAULT NULL, -- searches store code or name
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_risk_filter   text    DEFAULT NULL, -- 'under-staffed', 'fully-staffed', 'over-staffed'
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'store_name',
  p_sort_dir      text    DEFAULT 'asc'
)
RETURNS TABLE (
  store_id                uuid,
  store_code              text,
  store_name              text,
  account_name            text,
  region                  text,
  required_headcount      integer,
  active_headcount        integer,
  vacancy_count           integer,
  pipeline_count          integer,
  staffing_gap            integer,
  staffing_risk           text,
  sla_badge               text,
  vacancy_sla_breached    boolean,
  row_capabilities        jsonb,
  total_count             bigint
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

Supported store staffing sort fields are `store_name`, `store_code`, `account_name`, `region`, `required_headcount`, `active_headcount`, `vacancy_count`, `pipeline_count`, `staffing_gap`, `staffing_risk`, and `sla_badge`.

### C. Summary Count Metrics Contract
```sql
CREATE OR REPLACE FUNCTION public.get_web_plantilla_summary(
  p_search        text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL
)
RETURNS TABLE (
  total_active_roster     bigint, -- count of active employees
  total_budgeted_slots    bigint, -- count of budgeted employees
  total_additional_slots  bigint, -- count of active AH employees
  understaffed_stores     bigint, -- count of stores where active < budgeted target
  sla_breaches_count      bigint  -- count of active movement or vacancy SLA breaches
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

### D. Detail Drawer Contract
```sql
CREATE OR REPLACE FUNCTION public.get_web_plantilla_detail(
  p_employee_id uuid
)
RETURNS TABLE (
  id                    uuid,
  employee_no           text,
  first_name            text,
  last_name             text,
  position_title        text,
  account_name          text,
  primary_store_name    text,
  assignment_type       text,
  covered_stores        jsonb, -- array of covered stores with allocation %
  plantilla_type        text,
  plantilla_status      text,
  date_deployed         date,
  tenure_description    text, -- formatted text "1 Year, 4 Months"
  base_rate_masked      text, -- dynamic masking based on caller role
  contact_number        text, -- masked/unmasked contact number
  email_address         text, -- masked/unmasked email address
  residential_address   text, -- masked/unmasked address
  government_ids        jsonb, -- SSS, PagIBIG, PhilHealth, TIN (masked/unmasked)
  clearance_status      text, -- 'Complete', 'Pending', 'Incomplete'
  clearance_checklist   jsonb, -- interactive checklist states
  clearance_documents   jsonb, -- array of uploaded clearance files
  sla_elapsed_hours     integer,
  sla_breached          boolean,
  active_movement_req   jsonb, -- active transfer/movement metadata if any
  audit_timeline        jsonb, -- historical logs array
  row_capabilities      jsonb  -- capability keys
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

---

## 11. Shared Component Reuse Mapping

To achieve perfect visual alignment with the design systems defined in `web_ui_system_state.md`, the Plantilla Web module consumes the core shared component library:

```
[Plantilla Main Dashboard]
 ├── AdminPageHeader ───────────────── Title: "Plantilla Directory"
 │                                     Subtitle: "Manage active personnel, audit store capacities, and govern movements."
 │                                     Primary Action: Scoped "Request Additional Headcount" (OM / Admin only)
 ├── MetricCard (Grid) ─────────────── Renders: 1. Active Roster | 2. Budgeted Slots
 │                                              3. AH (Temp) Slots | 4. Under-Staffed Stores
 ├── AdminFilterBar ────────────────── Search: "Search by employee, store, or VCode..."
 │                                     Segmented Switch: [ Employee View ] vs. [ Store View ]
 │                                     Select Dropdowns: Account, Position, Plantilla Type, SLA Status
 ├── Compact Table ─────────────────── Rendered grid of personnel or store records.
 │    └── DataState ────────────────── Handles Loading skeletons, Empty records, Access Denied shields,
 │                                     and Connection alerts with retry callbacks
 └─ Detail Drawer
      ├── DetailDrawer ────────────── Width token: drawer-width-lg (640px)
      │                                Handles Escape keypresses, backdrop dismissals, and background scroll locking
      ├── StatusBadge ──────────────── Maps statuses ('Active' -> success, 'Pending Separation' -> danger)
      └── CapabilityActionBar ──────── Renders context action options:
                                                - [ Transfer Personnel ] (Encoder / HeadAdmin / SuperAdmin)
                                                - [ Initiate Separation ] (OM / HRCO / HR / Admin)
                                                - [ Approve Clearance ] (HR Personnel / Admin)
                                                - [ Adjust Roving Schedule ] (HRCO / OM / Admin)
```

---

## 12. Proposed Implementation Plan

### Phase 1: Route & Shared Shell Scaffolding ✅ COMPLETE
- `src/app/(dashboard)/plantilla/page.tsx` is fully implemented as a read-only admin page.
- `AdminPageHeader` (title, subtitle, readOnly badge), 4x `MetricCard` KPI row, `AdminFilterBar` with Employee/Store segmented view toggle, and `DataState` (loading, empty, access_denied, error) are all wired.
- Employee View and Store Staffing View share a single page with filtered, paginated dense tables.
- No mock data; all queries go through Supabase RPCs only.
- Employee table columns: Emp ID, Name (AH badge), Account/Store, Position, Assignment (Roving count), Type, Status (StatusBadge + SLA breach ⚠).
- Store table columns (OHM2026_1132): Store Code, Store Name, Account/Region, Actual (`onboard_count`), HR Pipeline (`hr_pipeline_count`), Vacancy (`open_headcount`, SLA breach ⚠), Required (`required_headcount`), MFR % (`fill_rate` from backend; formula tooltip: Actual / (Actual + HR Pipeline + Vacancy)), Staffing Risk, SLA Badge. Legacy "Gap" column removed; no web-side MFR computation.
- Deactivation overlays applied via `deriveDeactivationOverlay`: pending-separation rows get dashed border + `bg-red-50/30 opacity-80`; inactive/terminated/suspended rows get `opacity-65 pointer-events-none` + strikethrough on ID and name.
- Staffing risk derived via `deriveStaffingRisk` to drive backend-returned staffing risk, SLA badge, vacancy count, and vacancy SLA breach indicators.
- Filters: search (apply-on-click), account ID, group ID, store ID (employee view), employment status (employee view), deployment type (employee view), staffing risk/SLA status (store view).
- Validated: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

### Phase 2: Database RPC & Security Migrations ✅ APPLIED REMOTELY
- Migrations `20260607000002` and `20260607000003` exist and are applied remotely.
- Backend contracts implemented: `list_web_plantilla_employees`, `list_web_plantilla_store_staffing`, `get_web_plantilla_summary`, and `get_web_plantilla_detail`.
- User-role caller context resolution via `get_web_current_user_context` is implemented.
- Strict SQL-level data masking for personal numbers, emails, addresses, salary rates, and Gov IDs is enforced for restricted roles.
- RLS security policies gating queries against user accounts and group scopes are set up.
- Group ID filtering is wired through deployed `p_group_id` parameters on summary, employee list, and store staffing RPCs.

### Phase 3: Client Integration & State Management ✅ COMPLETE
- `src/lib/queries/plantilla.ts` is implemented with full TypeScript types, RPC wrappers, and normalizers. Added `getPlantillaAccountStatusCounts` to fetch active status counts for authorized accounts.
- Exported RPC wrappers: `getPlantillaSummary`, `listWebPlantillaEmployees`, `listWebPlantillaStoreStaffing`, `getWebPlantillaDetail`, `getPlantillaAccountStatusCounts`.
- Employee list sorting defaults to backend-supported `employee_name`; stale `last_name` is not sent to the deployed RPC allowlist. Store staffing sorting defaults to backend-supported `store_name`.
- Typed JSONB sub-types: `PlantillaCoveredStore`, `PlantillaGovernmentIds`, `PlantillaClearanceChecklistItem`, `PlantillaClearanceDocument`, `PlantillaMovementRequest`, `PlantillaAuditTimelineItem`.
- Presentation-layer derivation helpers: `deriveDeactivationOverlay`, `deriveTransferOverlay`, `deriveStaffingRisk`.
- Error class `PlantillaDataError` with `access_denied` / `retryable` kind discriminator.
- React Query `useQuery` hooks are wired in `page.tsx` for summary, employee list, and store staffing list.
- **Account-First Selection Gate (ADR-001 Compliance):**
  - **Query Gating:** All three listing/summary queries (`summaryQuery`, `employeeQuery`, `storeQuery`) are gated using `enabled: !!accountId`.
  - **Auto-Fire/Auto-Select:** Users with scoped roles (e.g. HRCO, OM, Encoder) having exactly one authorized account automatically bypass the selection screen. The single account is resolved and selected on mount.
  - **URL Deep-linking:** If the page is entered with an `accountId` URL query parameter, the state is hydrated and queries execute immediately.
  - **Fail Closed:** If the account scope is empty or unresolved, the queries remain disabled.
  - **Account Selector UI:** Multi-account or broad-access users are presented with a selection dashboard displaying a grid of account cards showing placement status counts (Active, Transfer, Separation, Suspended) aggregated via `get_plantilla_account_status_counts` RPC.
  - **Back Navigation:** Multi-account users can reset selection via a "← Back to Account Selection" button which clears the URL query parameter and filters.
- All four `DataState` boundaries (loading, empty, access_denied, retryable error with retry callback) are active.
- **Next.js `<Suspense>` & Canonical Auth Parity (ohm#p7f2a1b9):**
  - Wrapped page export in `<Suspense fallback={<PlantillaSkeleton />}>` to avoid CSR bail-out freezes when reading `useSearchParams()`.
  - Replaced ad-hoc `userContextQuery` with canonical `useCurrentUser()` from `@/lib/auth`, matching `/vacancy`, `/hr-emploc`, and `/approvals`.
  - Removed fragile `isHydrated` latch and derived `viewMode` and `accountId` directly from `searchParams` / single-scoped context, eliminating cascading re-render loops and URL navigation race conditions.

### Phase 4: Detail Drawer ✅ COMPLETE
- `src/components/plantilla/PlantillaDetailDrawer.tsx` is fully implemented.
- Employment/allocation grid, roving coverage (when `assignmentType === 'Roving'`), clearance panel (when `plantilla_status === 'Pending Separation'`), SLA warning block, masked PII fields, and audit timeline are all rendered.
- `getWebPlantillaDetail` is called via `useQuery` (queryKey: `["plantilla", "detail", plantillaId]`), enabled only when a `plantillaId` is non-null.
- All four DataState boundaries are active: loading, access_denied, not found (empty), and retryable error with retry callback.
- Deactivation banners (separation-pending, deactivated) and transfer overlay banner are rendered at the top of the drawer body.
- `CapabilityActionBar` maps backend `row_capabilities` only to read-only visibility hints for `can_request_deactivation`, `can_review_deactivation`, `can_request_deletion`, `can_review_deletion`, and `can_transfer_employee`. Stale frontend-only action assumptions such as generic separation approval, roving edit, suspend toggle, and AH request are not rendered in the employee detail drawer.
- Detail JSONB arrays (`covered_stores`, `clearance_checklist`, `clearance_documents`, `audit_timeline`) tolerate null/partial payloads and use normalized stable keys so duplicate or partially missing items do not collide in React rendering.
- Assignment coverage renders for both stationary and roving employees: stationary records show the primary store, while roving records show covered stores or an explicit empty roving payload state.
- Clearance/offboarding audit rendering is restricted to pending-separation records with checklist rows.
- Audit timeline rendering is null-safe; missing event timestamps render as unavailable instead of inventing client-side dates.
- Row click wiring: employee table rows emit `onRowClick(row.id)`. Dimmed rows (inactive/terminated/suspended) keep `pointer-events-none` and cannot be clicked. Active and pending-separation rows are keyboard- and mouse-accessible (`role="button"`, `tabIndex=0`, Enter/Space support).
- Drawer close clears `selectedPlantillaId` state in the page, closing the drawer.
- Store view drawer: not yet implemented (Phase 4 partial — employee only).
- Validated: `pnpm lint` clean, `pnpm build` clean (zero errors, zero warnings).

### Phase 5: Action Mutations Integration
- Hook up React Query mutations (`useMutation`) to backend action RPCs:

### Phase 6: UI Standard & Motion System Alignment (Loop 6A & 6B) ✅ COMPLETE
- **Loop 6A (Drawers & Tables)**: Wrapped `PlantillaDetailDrawer` and all 8 pool/store drawers with canonical `@/components/shared/DetailDrawer` (`drawer-width-lg`). Tokenized directory page, account gate selection, MFR / fill rate bars, tab pills, and member/vacancy tables (0 literals, $\ge 14\text{px}$ floor). MFR progress bars in Account cards and `StoreStaffingOverviewDrawer` strictly enforce thresholds (100% Green, 95% to 99.99% Yellow, <95% Red) with recessed `bg-surface-muted border border-border-subtle/50` tracks to maintain visibility across light and dark themes without fading out into card backgrounds. Top tab switcher removed in favor of direct Store Plantilla default view with pinned Moses HQ entry routing to Moses HQ Pool; Workforce Analytics integrated as top-toolbar modal trigger in `MosesHqPoolView`.
- **Loop 6B (Modals & Forms)**: Standardized all 8 Plantilla lifecycle modals (`InitiateSeparationModal`, `RequestDeactivationModal`, `RequestPoolConversionModal`, `RequestPoolHeadcountModal`, `RequestRelieverCoverageModal`, `TransferPersonnelModal`, `UpdateEmploymentStatusModal`, `UpdateScheduleModal`) with canonical `Modal` at `z-[60]` (stacks above `DetailDrawer` at `z-50`). Hardened `isSubmitting`, `isDirty`, and backdrop guards. Preserved `--danger` strictly for validation errors and destructive actions. Exactly 0 literals across all 8 modals.
  - Submit personnel store transfer.
  - Request Additional Headcount (AH).
  - Initiate separation workflow (Resignation / Termination / Backout).
  - Update separation clearance checkboxes and upload clearance forms.
- Configure cache invalidation policies to automatically reload active roster tables and metrics summary bars after every mutation.

### Phase 6: Plantilla Bulk Baseline Import & Mobile Governance Parity (`PlantillaImportModal.tsx`, ADR-002) ✅ COMPLETE
- **ADR-002 Architectural Invariants & Template Standardization (`data_control_xlsx.ts`)**:
  - 8 Always-Required Store Columns: `GROUP_NAME`, `ACCOUNT_NAME`, `MOTHER_ACCOUNT`, `VCODE`, `STORE_NAME`, `AREA_PROVINCE`, `AREA_CITY`, `POSITION`.
  - 5 Conditionally-Required Employee Columns: `EMPLOYEE_NO`, `LAST_NAME`, `FIRST_NAME`, `MIDDLE_NAME`, `DATE_HIRED` (blank employee fields create valid vacant store baseline slots; partial employee fields without `EMPLOYEE_NO` hard-blocked).
  - Derived fields: `EMPLOYMENT_TYPE` (auto-computed stationary vs roving $1/N$ headcount) and `WITH_PENALTY` (auto-derived from `mother_account_configs`) removed from required input; backward-compatible if present in legacy files.
  - Configuration Table & Production Parity (`mother_account_configs`, Migration `20262606000064`):
    - Created `public.mother_account_configs` table with RLS, authenticated select policy, admin full access policy, and seeded 17 active accounts from stores/accounts.
    - Synchronized 21 companion columns across `plantilla_import_rows`, `stores`, `accounts`, `plantilla`, `employee_store_allocations`, `plantilla_import_batches`, and `employees` on production.
    - Full parity achieved across Staging and Production for `trg_account_hrco_backfill`, Zero-Edit lock helpers (`_import_records_modified_after_approval`, `get_plantilla_import_first_modified_record`), `fn_assert_vcode_exists_in_plantilla`, and 6 batch review/approve/rollback RPCs.
  - Bulk Import Performance & Timeout Optimization (Migration `20262606000065`):
    - Added functional index `idx_stores_vcode_upper_active` on `stores(upper(vcode))` and active employee index `idx_plantilla_emp_no_acct_active` on `plantilla(employee_no, account_id)`.
    - Expanded `pib_status_check` constraint on `plantilla_import_batches` to include `'blocked'`, `'partially_blocked'`, and `'pending_review'`.
    - Refactored `submit_plantilla_baseline_import` from $O(N^2)$ row-by-row nested JSON lookups to $O(N)$ set-based CTE aggregation with single bulk insert, reducing 1,326-row ingestion time from >25s to <1s.
    - Attached `SET statement_timeout = '60s'` to `submit_plantilla_baseline_import`, `approve_plantilla_import_batch`, and all 4 rollback RPCs, permanently preventing role-level 8s timeout aborts on large files.
  - **Store Name Multi-VCODE Governance & Review Queue Scaling (Migration `20262606000072_relax_store_name_multivcode_rule.sql`, formerly `...066`)**:
    - Relaxed `STORE_NAME is mapped to multiple different VCODEs in upload` from a hard block (`validation_errors`) to an advisory warning (`validation_flags` with flag `multiple_vcodes_per_store`), permitting motorized collection accounts (e.g., Alturas/BPI) with multiple collector VCODEs in a single municipality to be imported and approved.
    - Retained strict hard-block corruption guard on the inverse check (`VCODE is mapped to multiple different STORE_NAMEs in upload`).
    - Client Row Fetching Pagination (`dataControl.ts`): Implemented async while-loop in `fetchPlantillaImportRows` querying `get_plantilla_import_rows` in chunks of 1,000, removing the former 500-row cap and ensuring all 1,326+ rows are displayed in the Review Queue row inspector with 100% filter pill alignment.
    - Filtered Batch Card Errors (`PlantillaImportModal.tsx`): Filtered `errorSummary` to exclude metric counters (`total_rows`, `valid_rows`, `flagged_rows`, etc.), displaying red error badges only for active conflict fields with count $> 0$.
  - Strict Middle Name Validation: single-character initials (`"S"`, `"S."`) hard-blocked; full middle names ($\ge 2$ alpha chars) or explicit case-insensitive `"NA"`/`"N/A"` accepted.
  - ExcelJS Download Template Generator (`downloadPlantillaImportTemplate`):
    - Styled 8 Always Required Store Headers and 5 Conditionally Required Employee Headers in soft red fill (`#FFC7CE`), dark red bold font (`#9C0006`), centered, thin border.
    - Free-form text input on all schedule columns (`SCHEDULE_DAYS`, `SCHEDULE_TIME`, and `DAYOFF`) without dropdown list restrictions or validation prompts.
    - Secondary `VALIDATION_GUIDE` sheet detailing all 15 ADR-002 operational invariants.
  - Comprehensive 19-rule guide sheet included in downloadable Excel template (`downloadPlantillaImportTemplate`).
- **Client-Side Pre-Validation (`data_control_xlsx.ts`)**:
  - Validates `GROUP_NAME` and `ACCOUNT_NAME` against the user's active UI scope dropdown selection before triggering backend RPC calls. If values mismatch, returns row-level guidance (`Row #X: GROUP_NAME does not match selected group`).
- **Review Queue State Machine & Row Inspector (`PlantillaImportModal.tsx`)**:
  - `pendingBatches` includes reviewable non-terminal statuses: `draft_uploaded`, `pending_approval`, `validation_failed`, `blocked`, and `partially_blocked`.
  - On upload, if `status === 'validation_failed'` or `blockedRows > 0`, the UI avoids premature green success toasts, switches to the Review Queue, auto-expands the newly created batch, and defaults the row filter to `blocked`.
  - Added `Skipped` filter pill: vacant rows with existing VCODEs are non-blocking (`validation_status = 'skipped'`) and rendered with distinct slate badges.
  - Rows display `Vacant Baseline Slot` badge, `Mother Account`, `Position / HC`, and schedule metadata.
  - **Typography & Compact Hierarchy Polish (`PlantillaImportModal.tsx`)**:
    - Primary identifiers (`VCODE`, `Store Name`, `Position`, `Employee Name`) standardized at clean `text-xs font-medium leading-tight` (max 12px, no bulky bolding).
    - Secondary metadata (`Employee ID`, `Mother Account`, `schedule/shift`, `employmentType`, `requiredHc`) standardized at compact `text-[11px] text-slate-500 leading-tight` with minimized cell padding (`px-2.5 py-1.5 align-middle`) cutting vertical row bloat in half.
    - Status and badge pills (`FLAGGED`, `ROVING`, `NEEDS HRCO`, `VALID`, `BLOCKED`, `SKIPPED`, `Vacant Baseline Slot`) compacted (`text-[10px] px-1.5 py-0.5 rounded font-medium leading-none whitespace-nowrap`).
    - Validation error and guidance messages styled in compact `text-[11px] leading-snug break-words space-y-0.5` with compact conflict badges (`text-[10px] px-1.5 py-0.5 font-mono font-medium`) ensuring roving messages fit cleanly on 1–2 tight lines.
    - **Dedicated Rejection Reason Modal**: Clicking "Reject" or "Dismiss / Reject" on batch cards or within the row inspection drawer opens a dedicated rejection modal (`isRejectModalOpen`, `z-60`) replacing previous inline inputs. Requires non-empty audit remarks (`rejectionNote.trim()`), validates inline if empty, executes `rejectPlantillaImportBatch`, and provides instant feedback via auto-dismissing floating confirmation toast (`toastMessage`) and review notice banner.
    - **Import History Clean Actors & Compact Spacing**: Column headers use `text-[10px] font-semibold uppercase tracking-wider px-2.5 py-1.5`, cells use `px-2.5 py-1.5 align-middle text-xs leading-tight`. Uses `useUsersList()` to resolve auth and profile UUIDs to human full names (e.g., `"Litong, Ohm"`) instead of raw wrapped UUID snippets.
  - "Approve & Apply" claims existing open vacant slots before incrementing slot ordinals, creates/updates linked `public.vacancies` (guaranteeing required not-null `account` and `position` fields), and records `approved_at` after all DML completes.
  - **Pre-Commit Guard & Robust Commit Exception Propagation (`approve_plantilla_import_batch`, Migrations `20262606000055`, `20262606000056`, `20262606000057`)**:
    - Pre-commit guard strictly blocks approval only if hard-error rows exist (`validation_status = 'blocked'`), raising `Cannot approve batch: X blocked rows must be resolved or removed first` (retaining `pending_approval` state).
    - Rows marked as `flagged` (advisory warnings such as `NEEDS HRCO` or roving employee allocations) are permitted to commit alongside `valid` rows.
    - Store-Scoped Occupant Uniqueness (`uq_plantilla_slots_active_occupant`): Replaced table-wide index with a store-scoped unique index on `(COALESCE(store_id, '00000000-0000-0000-0000-000000000000'::uuid), current_occupant_plantilla_id)` where `slot_status IN ('occupied', 'filled')`. This enforces that an employee can occupy at most one active slot per store while allowing roving personnel to occupy slots across multiple stores per ADR-002 without `SQLSTATE 23505` conflicts.
    - Phase B2 Idempotent Slot Assignment: Implements a 3-step cascade:
      1. *Reuse*: Checks if the employee already occupies an active slot in this store; if so, updates its position, roving status, and metadata in-place.
      2. *Claim Vacant*: Else, searches for the lowest ordinal open slot in this store, transitions it to occupied, closes linked vacancies, and logs `IMPORT_CLAIM_VACANT`.
      3. *New Slot*: Else, provisions a new occupied slot with ordinal `MAX + 1` and logs `IMPORT_OCCUPIED`.
    - Master Lookup Reason Codes (`public.slot_reason_codes`): Seeded `IMPORT_VACANT_SLOT` and `IMPORT_CLAIM_VACANT`.
    - Defensive `slot_history` Lookup Checks: `approve_plantilla_import_batch` verifies that `reason_code` exists in `public.slot_reason_codes` before insertion, preventing foreign key reference conflicts (`SQLSTATE 23503`).
    - Uncommitted Batch Rejection (`reject_plantilla_import_batch`): Expanded allowed batch states to `('pending_approval', 'pending_review', 'validation_failed', 'draft_uploaded', 'commit_failed', 'blocked', 'partially_blocked')`. `rejectPlantillaImportBatch` formats complete Supabase error diagnostics (`[message, details, hint]`) to surface detailed reasons directly in the rejection modal.
    - Review Queue vs Import History Scope: `reviewableStatuses` in `PlantillaImportModal.tsx` strictly scopes to active pending batches (`draft_uploaded`, `pending_approval`, `pending_review`, `validation_failed`, `blocked`, `partially_blocked`). Failed batches (`commit_failed`) remain exclusively in the Import History tab, preventing historical failed test batches from flooding the Review Queue.
    - HRCO Auto-Tagging & Default Fallback: Looks up selected account's assigned HRCO. If an employee row lacks HRCO, it safely defaults to the account HRCO and resolves `hrco_name`, setting `needs_hrco = false`. If neither has an HRCO assigned, sets `hrco_user_id_snapshot = NULL` and marks `needs_hrco = true` without raising constraint errors.
    - Vacant slot creation in Phase B1 syncs shadow `public.vacancies` records with non-null `account` (`COALESCE(v_acct_name, 'Unknown Account')`) and `position` (`COALESCE(v_vrow.position, 'Merchandiser')`), handling conflicts with `ON CONFLICT (vcode) DO UPDATE`.
    - Pl/pgSQL exception handler translates Postgres constraint errors (e.g. `23502` missing required field, `23505` unique conflict, `23503` foreign key) into human-readable descriptions, writing them into both `commit_error_detail` and `error_message` on `plantilla_import_batches`.
    - Client-side `approvePlantillaImportBatch` formats complete Supabase error messages (`[message, details, hint].filter(Boolean).join(" - ")`) and detects `status === 'commit_failed'` in return payloads, propagating the detailed explanation directly into user-facing UI error banners.
- **Rollback Governance & History Audit (`PlantillaImportModal.tsx`)**:
  - History table rendered inside a dedicated horizontal scroll container (`overflow-x-auto`) with fixed column layout (`table-fixed min-w-[920px]`).
  - Columns optimized with compact padding (`px-2.5 py-2.5`), text truncation (`truncate`), and native `title` hover tooltips on `File Name`, `Scope`, `Uploaded By`, and `Approved / Rejected By` (displaying shortened UUIDs or formatted actor names).
  - Single-line status and rollback badges protected with `whitespace-nowrap` to prevent vertical row stretching.
  - 72-hour countdown window tracked accurately with `formatRollbackRemaining`.
  - Head Admin and Super Admin can approve or reject rollback requests (`rejectPlantillaImportRollback`).
  - Super Admin Emergency Rollback Override enabled for expired windows when zero records were touched.
  - **Strict Zero-Edit Immutability Lock**: If any record in the batch was modified post-approval (with 2-second approval grace guard), rollback is hard-blocked and displays humanized error message identifying modified records.
- **Needs HRCO Visibility Guard & Unassigned Employees Resolution (`ohm#n2k7w9m4`)**:
  - **Account HRCO Conditional Tab Visibility**: The "Needs HRCO" directory tab only renders when the selected account has no assigned HRCO (`!accountHasAssignedHrco`). When an HRCO is assigned to the account (`accounts.hrco_user_id IS NOT NULL` or leadership team HRCO present), the tab is hidden and views default cleanly to `active`.
  - **RPC Access & Unassigned Population (Migration `20262606000060`)**: Removed the restrictive `i_am_data_team() OR i_have_full_access()` check from `get_plantilla_unassigned_hrco_count` and `get_plantilla_needs_hrco_employees`. If an account has no assigned HRCO, all active employees under that account are returned as needing an HRCO.
- **Web-Optimized Desktop Drawer Layout & 4-Tab System (`PlantillaDetailDrawer.tsx`)**:
  - Right-side desktop drawer (`max-w-2xl bg-slate-50`) with deep blue banner (`bg-[#1e3a8a]`), circular initials avatar, employee ID (`IdCard`), deployed date (`Calendar`), and active status badge.
  - **4-Tab Navigation**:
    - **Profile**: 2-column Employment & Allocation grid (VCODE, Position, Store, Employment Type, Date Hired, Tenure computed via `computeTenure`), Work Schedule & Rate card (`Schedule Days`, `Schedule Time`, `Day Off`, `Daily Rate`, `Coordinator`) with modal launcher `UpdateScheduleModal`, System Information collapsible accordion, and Capability-Aware Personnel Actions toolbar (Transfer, Reassign HRCO, Request Deactivation, Request Deletion, Update Employment Status).
    - **Benefits**: SSS, PhilHealth, Pag-IBIG, and ATM Number with an interactive Eye toggle for masking (`••••-••••-1234` vs unmasked), plus MIKA sync card with timestamp and dedicated `syncPlantillaMika` RPC mutation with 5-minute cooldown handling.
    - **Stores**: Current Stores vs Past Stores count summary cards and active store allocation details with live status indicator, VCODE, Area, and HC Share.
    - **Activity**: Audit trail logs and deployment history with timestamps, profile actors, and snapshot details.
- **Ops Schedule & Store Visit Audit (`PlantillaDetailDrawer.tsx` & `UpdateScheduleModal.tsx`)**:
  - Displays `Schedule & Store Visit Audit` section card in employee detail drawer (`Schedule Days`, `Schedule Time`, `Dayoff`).
  - Interactive `UpdateScheduleModal` enables Ops/lifecycle roles to update schedule days (multi-select MON-SUN with presets), schedule time (shift windows & flexi visit hours), and dayoff (multi-select MON-SUN).
  - Updates `plantilla` and `employee_store_allocations` and advances `updated_at`, actively enforcing the Zero-Edit Lock against uncoordinated rollbacks.
- **Strict Vacancy Occupancy Filter for Missing Store Detection & Direct Import Guard (`ohm#s8k2w7m3`)**:
  - **Strict Occupancy Filtering**: Store slots occupied by active personnel in `public.plantilla_slots` (`slot_status IN ('occupied', 'filled')` or `current_occupant_plantilla_id IS NOT NULL`), `public.plantilla` (active employees), or `public.employee_store_allocations` (`is_active = true`) are strictly excluded from the Vacancy tab's "Stores without Active Vacancies" / "Missing from Vacancies" quick-import section.
  - **Authoritative Backend Guard**: `directImportVacancy` verifies store occupancy via `fetchOccupiedStoreIdentifiers(accountId)` and rejects attempts to create vacancies for occupied stores.

- **Plantilla Import Completeness, Vacancy Tab Enhancements & Detail Drawer Cleanup (`ohm#v2k8w4m9`)**:
  - **Import Completeness Fix (Migration `20262606000058`)**:
    - Fixed `submit_plantilla_baseline_import` to prevent skipping vacant rows for existing stores (`IF v_emp IS NULL` now processed as valid vacant slots).
    - Resolved loop state bleed bug by re-initializing `v_status := 'valid'` on every row iteration.
    - Updated `approve_plantilla_import_batch` Phase B1 to provision all valid vacant rows with dynamic `slot_ordinal = COALESCE(MAX(slot_ordinal), 0) + 1` and synchronize `public.vacancies` (`status = 'Open'`, `vacant_date = CURRENT_DATE`).
    - Guarded Phase B2 against claiming newly created batch vacant slots via `v_batch_created_slot_ids`.
  - **Vacancy Tab Decoupling & Direct Import (`src/app/(dashboard)/plantilla/page.tsx`)**:
    - Decoupled vacancy table rows and cards from `RequestHeadcountModal`; clicking now inspects via `VacancyDetailDrawer`.
    - Added `Aging` column with color badges: emerald ($\le 15$d), amber ($16\text{--}30$d), rose ($> 30$d).
    - Added `Action` column with `Inspect` button for active vacancies and `+ Direct Import` quick-action button for unlisted stores under the active account without forcing the import wizard.
  - **Conditional `NEEDS HRCO` Badge**:
    - Warning badge hidden across `PlantillaImportModal.tsx`, `EmployeeTable`, and `EmployeeCard` whenever the account has an assigned HRCO (`accounts.hrco_user_id IS NOT NULL`) or the row/employee has an assigned HRCO.
  - **Inspect & Detail Drawers Cleanup**:
    - `PlantillaDetailDrawer.tsx`: Compacted to `p-4 space-y-3`, suppressed redundant stationary coverage card (already in EmploymentGrid), and formatted Schedule Audit into a compact 3-column inline strip.
    - `VacancyDetailDrawer.tsx`: Spacing tightened to `p-3.5 space-y-2`, removed duplicate quota label from Requisition & Quota controls header.

- **Plantilla Baseline Import Batch Summary Column Fix & Error Surfacing Hardening (`ohm#b7k2w9m5`)**:
  - **Database Migration (`20262606000061`)**:
    - Replaced `submit_plantilla_baseline_import` to update `error_summary = v_summary` instead of non-existent column `summary_json` in `plantilla_import_batches`.
    - Preserved batch conflict counters (`roving_detected`, `new_stores_count`, `existing_stores_count`, `cross_account_conflicts`, `cross_group_conflicts`) and `updated_at`.
    - Applied to both live Staging (`qqiiznmqxfoamqytjica`) and Production (`rwxelulyapjgaarlwkus`).
  - **Client Error Hardening**:
    - `dataControl.ts`: `submitPlantillaBaselineImport` now wraps Postgrest error messages into `new Error(...)`.
    - `PlantillaImportModal.tsx`: catch block safely extracts `(err as { message?: string })?.message` fallback, preventing real database error messages from being swallowed by generic banner text.

- **Vacancy Account & Group Linkage Propagation, Import RPC Hardening & Orphan Backfill (`ohm#v2k9w4r8`)**:
  - **Database Migration (`20262606000062`) Applied to Live Staging**:
    - Hardened `approve_plantilla_import_batch` Phase A to update `stores.account_id` and `stores.group_id` from batch when missing.
    - Updated Phase B1 to strictly inherit store/batch `account_id` and `group_id` for vacant slots and shadow vacancies, preventing fallback or overwrite with `"Unknown Account"`.
    - Phase B2 slot creation now inherits store account/group fallbacks.
    - Repaired orphaned vacancies (including `CPRVJV13`), slots, and stores via SQL backfill.

- **Plantilla Import Role Check Regression Fix & Helper Function Parity (`ohm#p9r2k5w8`)**:
  - **Database Migration (`20262606000073_fix_plantilla_import_role_check_parity.sql`, formerly `...067`)**:
    - Added helper function wrappers `public.get_current_role()` and `public.fn_is_admin()` aliased to `public.get_my_role()` and `public.i_have_full_access()`.
    - Added missing batch tracking columns `commit_error`, `stores_created`, `employees_created`, and `allocations_created` on `public.plantilla_import_batches`.
    - Restored canonical `v_role text := public.get_my_role();` and robust RBAC + operational governance assertions (`fn_can_upload_plantilla_import()`, `fn_assert_governance_enabled('import_plantilla')`, `fn_assert_freeze_inactive('audit_freeze')`) inside `submit_plantilla_baseline_import`.
    - Preserved 100% of migration 65 performance optimizations (set-based CTEs, single bulk insert, `statement_timeout = '60s'`) and migration 66 multi-VCODE store name governance (`multiple_vcodes_per_store` as `flagged` advisory warning).
    - Applied and verified on both Production (`rwxelulyapjgaarlwkus`, tracking version `20262606000073`) and Staging (`qqiiznmqxfoamqytjica`, tracking version `20262606000073`).

- **UI Standard & Motion System Alignment (Loop 6A, 6B, 6C: `ohm#l6a1m4w9`, `ohm#l6b2n7k4`, `ohm#l6c3w8m2`)**:
  - **Zero Color Literals**: Eliminated 100% of raw color literals (all 1,031 baseline occurrences across 19 files) down to 0, replacing them with standard design tokens (`bg-surface`, `bg-surface-muted`, `border-border-default`, `text-text-primary`, `text-text-secondary`, `text-accent`, `--pct-*`, and `--danger-*`).
  - **Drawer & Table Standardization (Loop 6A)**: Standardized `PlantillaDetailDrawer` (`drawer-width-lg`) and all 8 pool/store drawers with canonical `DetailDrawer`; strictly preserved table text floor $\ge 14\text{px}$ (`text-sm`) across members, vacancies, and store tables; preserved single-account auto-fire and ADR-001 account gate query rules.
  - **Modal Hardening & Canonical Stacking (Loop 6B)**: Aligned all 8 Plantilla lifecycle modals (`InitiateSeparationModal`, `RequestDeactivationModal`, `RequestPoolConversionModal`, `RequestPoolHeadcountModal`, `RequestRelieverCoverageModal`, `TransferPersonnelModal`, `UpdateEmploymentStatusModal`, `UpdateScheduleModal`) with canonical `Modal` at `z-[60]` over `DetailDrawer` at `z-50`; hardened against backdrop clicks during dirty states; disabled Esc/close buttons during `isSubmitting`.
  - **Specialized Views & Analytics Parity (Loop 6C)**: Standardized `MosesHqPoolView.tsx` and `WorkforceAnalyticsView.tsx` across all 7 analytics tabs (Overview, Deployment, Coverage, Conversion, Slots, Health, Executive); converted SVG progress donuts and horizontal bar indicators to standard tokens (`var(--accent)`, `var(--pct-good-text)`, `var(--pct-warn-text)`, `var(--danger-text)`); preserved 100% RPC integration contracts and XLSX export capabilities.



