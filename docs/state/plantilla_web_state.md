# Plantilla Web State & Architecture Specification

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
This view switches focus to store capacity metrics. Each row represents a specific store's staffing capacity and targets.

```
[Store Plantilla Grid Viewport (Scrollable horizontally, min-width: 1120px)]
-----------------------------------------------------------------------------------------------------------------------------
Store Code | Store Name        | Account / Region           | Budgeted   | Active (B) | Active (AH) | Vacancies  | SLA Status
-----------------------------------------------------------------------------------------------------------------------------
STR-C042   | Cebu Mall         | Cebu Regional / Visayas    | 5 Slots    | 4 Filled   | 1 Active    | 1 Vacant   | Fully-Staffed
STR-M099   | Manila Hub 1      | Manila Region / NCR        | 3 Slots    | 1 Filled   | 0 Active    | 2 Vacant   | Under-Staffed
STR-D101   | Davao Hub         | Davao South / Mindanao     | 4 Slots    | 4 Filled   | 2 Active    | 0 Vacant   | Over-Staffed
```

#### Column Structure (Store View):
1. **Store Code**: `store_code` (Rendered in monospace: `font-mono text-xs text-gray-700 bg-gray-50 border border-gray-100 rounded px-1.5 py-0.5`).
2. **Store Name**: Display name of the store.
3. **Account & Region**: The billing account and geographical region.
4. **Budgeted Plantilla Target**: Total standard contracted slots allocated for this store.
5. **Active Budgeted Staff**: Count of active employees deployed to budgeted slots.
6. **Active Additional Headcount (AH)**: Count of active employees currently occupying temporary additional slots.
7. **Vacancies**: `Budgeted Target - Active Budgeted Staff` (If negative, displays `0`).
8. **Staffing SLA Status**: Displays staffing health badges:
   - `Under-Staffed`: Active Budgeted < Budgeted Target (Flags `danger` if vacant for > 7 days).
   - `Fully-Staffed`: Active Budgeted == Budgeted Target (Flags `success`).
   - `Over-Staffed`: Active Budgeted > Budgeted Target (Flags `warning` indicating temporary overflow or unapproved placements).
9. **Actions**: Desktop "Eye" icon to open the selected Store's detailed plantilla and list of assigned personnel in a Command-Center drawer.

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
  p_account_id      uuid    DEFAULT NULL,
  p_store_id        uuid    DEFAULT NULL,
  p_position        text    DEFAULT NULL,
  p_plantilla_type  text    DEFAULT NULL, -- 'budgeted', 'additional'
  p_status          text    DEFAULT NULL, -- 'active', 'suspended', 'pending_separation', 'inactive'
  p_search          text    DEFAULT NULL, -- searches employee number or name
  p_limit           integer DEFAULT 50,
  p_offset          integer DEFAULT 0,
  p_sort_by         text    DEFAULT 'last_name',
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

### B. List Stores Contract
```sql
CREATE OR REPLACE FUNCTION public.list_web_plantilla_stores(
  p_account_id    uuid    DEFAULT NULL,
  p_region        text    DEFAULT NULL,
  p_sla_status    text    DEFAULT NULL, -- 'under-staffed', 'fully-staffed', 'over-staffed'
  p_search        text    DEFAULT NULL, -- searches store code or name
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0
)
RETURNS TABLE (
  store_id                uuid,
  store_code              text,
  store_name              text,
  account_name            text,
  region                  text,
  budgeted_target         integer,
  active_budgeted_count   integer,
  active_additional_count integer,
  vacancies_count         integer,
  staffing_sla_status     text, -- 'Under-staffed', 'Fully-staffed', 'Over-staffed'
  vacancy_sla_breached    boolean,
  row_capabilities        jsonb,
  total_count             bigint
)
SECURITY DEFINER
AS $$
...
$$ LANGUAGE plpgsql;
```

### C. Summary Count Metrics Contract
```sql
CREATE OR REPLACE FUNCTION public.get_web_plantilla_summary(
  p_account_id    uuid DEFAULT NULL,
  p_store_id      uuid DEFAULT NULL
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
  p_plantilla_id uuid
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

### Phase 1: Route & Shared Shell Scaffolding
- Replace the basic `ModuleEmptyState` scaffold in `src/app/(dashboard)/plantilla/page.tsx` with a high-fidelity layout.
- Bind `AdminPageHeader`, `MetricCard` grids, and `AdminFilterBar` with the Employee/Store Segmented View Toggle.
- Wire local mock datasets to verify column alignments and grid rendering in both Employee and Store modes.

### Phase 2: Database RPC & Security Migrations
- Write migrations for backend contracts: `list_web_plantilla_employees`, `list_web_plantilla_stores`, `get_web_plantilla_summary`, and `get_web_plantilla_detail`.
- Implement user-role caller context resolution via `get_web_current_user_context`.
- Enforce strict SQL-level data masking for personal numbers, emails, addresses, salary rates, and Gov IDs for restricted roles.
- Set up RLS security policies gating queries against user accounts and group scopes.

### Phase 3: Client Integration & State Management
- Add typed query helper helpers inside `src/lib/queries/plantilla.ts`.
- Integrate React Query hooks (`useQuery`) into the main page directory and Detail Drawer.
- Standardize full state boundary cards using `DataState` (Access Denied shields, Spinner loads, empty clipboards).

### Phase 4: Action Mutations Integration
- Hook up React Query mutations (`useMutation`) to backend action RPCs:
  - Submit personnel store transfer.
  - Request Additional Headcount (AH).
  - Initiate separation workflow (Resignation / Termination / Backout).
  - Update separation clearance checkboxes and upload clearance forms.
- Configure cache invalidation policies to automatically reload active roster tables and metrics summary bars after every mutation.
