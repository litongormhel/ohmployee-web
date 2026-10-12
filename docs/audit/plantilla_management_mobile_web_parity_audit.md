# Plantilla Management: Mobile-to-Web Technical Parity Audit
**ADR-001 (Slot-First Architecture) Comprehensive Analysis**

**Audit ID:** `ohm#w45p336a`  
**Date:** 2026-10-12  
**Auditor:** Antigravity (Deep Architecture & Parity Audit Pass)  
**Target Codebases:**
- **Mobile Codebase (Flutter):** `D:\Projects\OHMployee`
  - Screens: `lib/features/plantilla/` (`plantilla_folder_screen.dart`, `plantilla_screen.dart`, `moses_hq_pool_screen.dart`, `workforce_analytics_dashboard_screen.dart`, `widgets/`)
  - Services: `lib/data/services/plantilla_scope_service.dart`, `plantilla_service.dart`, `workforce_pool_service.dart`
  - Database Migrations & Schemas: `supabase/migrations/` (Slot foundation, lifecycle automation, and quota controls)
- **Web Implementation Target (Next.js / TypeScript):** `D:\Projects\ohmployee-web`
  - Routes & Pages: `src/app/(dashboard)/plantilla/page.tsx`
  - Components: `src/components/plantilla/` (`PlantillaDetailDrawer.tsx`, `StoreStaffingDrawer.tsx`)
  - Queries & Mutations: `src/lib/queries/plantilla.ts`, `src/lib/queries/quota.ts`
  - Architecture Specifications: `docs/state/plantilla_web_state.md`, `docs/audit/adr001_plantilla_account_gate_2026-07-11.md`

---

## 1. Executive Summary & ADR-001 Architectural Alignment

The **Plantilla Management** module is the central authority for personnel placement, headcount budget governance, and operational staffing across OHMployee. 

Under **ADR-001 (Slot-First Architecture)**, a fundamental paradigm shift was codified:
1. **The Slot is the Asset**: A workforce slot (`plantilla_slots`) is an approved, fundable manpower position. Employees flow through slots; when an employee separates, the slot persists and moves back into recruitment.
2. **Headcount Single Source of Truth**: Contracted / Required Headcount is strictly equal to the count of approved slots. 
3. **Canonical MFR Computation**: Store and Account Manpower Fill Rate (MFR) is strictly defined as:
   $$\text{MFR \%} = \frac{\text{Actual (Onboard)}}{\text{Actual} + \text{HR Pipeline} + \text{Vacancy}}$$
   *(Any web-side calculation omitting HR Pipeline from the denominator or deriving $\frac{\text{Actual}}{\text{Required}}$ violates architectural contracts).*
4. **Account-First Access Gate**: In compliance with audit `ohm#4t8w2xhp`, all Plantilla listings and store views are strictly gated behind an authorized billing account selection, with immediate auto-fire reserved only for single-scoped role holders.

```
                    [Canonical Operational Pipeline]
                                  │
                                  ▼
                            [ Vacancy ]
                                  │
                                  ▼
                           [ Applicant ]
                                  │
                                  ▼
                         [ Confirmed Onboard ]
                                  │
                                  ▼
                       [ HR Emploc Compliance ]
                                  │
                                  ▼
                        [ Move to Plantilla ]
                                  │
                                  ▼
                      [ Active Plantilla Slot ]
                          (Occupied/Filled)
```

### High-Level Parity Verdict: ADVANCED DIRECTORY MATURITY / MUTATION & SLOT-INSPECTOR GAPS

| Architectural Domain | Mobile Flutter (`OHMployee`) | Web Target (`ohmployee-web`) | Parity Status |
| :--- | :--- | :--- | :--- |
| **Account Selection Gate** | `PlantillaFolderScreen`: 4 KPI metrics, Group dropdown, Moses HQ pool card, MFR badges, sorting by urgency. | `PlantillaPage` Account Selector: 4 KPI metrics, Group dropdown, Moses HQ pool card, MFR progress bar, auto-fire single account. | **100% PARITY** |
| **Directory Roster Views** | Dual view toggle (`By Employee` vs `By Store`), 3-4 Tabs (`Active`, `Vacancy`, `Inactive`, `Needs HRCO`). | Segmented View Switch (`Employee View`, `Inactive`, `Store Staffing`). | **90% PARITY** |
| **Store Staffing Quotas** | MFR formula breakdown (Actual, Pipeline, Vacancy, Required). Urgency badges. | MFR formula breakdown (Actual, HR Pipeline, Vacancy, Required). SLA Badges, Staffing Risk. | **95% PARITY** |
| **Slot-Level Inspector** | Direct query on `plantilla_slots` and `workforce_pool_slots`; slot status tracking across 4 canonical states. | Indirect: Displays vacancy vcodes and employee placement rows. No dedicated slot drawer or slot table. | **STRUCTURAL GAP** |
| **Quota Revision Workflows** | Direct Quota Revision (`revise_vcode_headcount_quota`) & Ops Amendment (`submit_headcount_amendment_request`). | Fully implemented modals in `StoreStaffingDrawer`: `ReviseHeadcountQuotaModal` & `RequestHeadcountAdjustmentModal`. | **100% PARITY** |
| **Personnel Movement Mutations** | Active transfer (`plantilla_transfer`), schedule edit, HRCO reassignment (`assign_hrco_to_plantilla`). | Read-only capability hints (`canTransferEmployee`). Mutations not wired to web UI triggers. | **MUTATION GAP** |
| **Separations & Deactivations** | Multi-type separation (Resigned, Endo, Terminated, AWOL, On Leave, Floating) + Deactivation request/approval. | Read-only clearance checklist and separation banners in drawer. No separation/deactivation trigger modals. | **MUTATION GAP** |
| **Moses HQ Workforce Pool** | Dedicated pool screens (`MosesHqPoolListScreen`), Reliever/Commando deployments, open slots view. | Pool account card detected; routes into standard store staffing table. No pool dashboard. | **FEATURE GAP** |

---

## 2. Feature & View Parity Matrix

### 2.1 Store List / Card Overview vs Detailed Store Plantilla Roster

```
+---------------------------------------------------------------------------------------------------------+
|                                    ACCOUNT OVERVIEW SCREEN                                             |
|                                                                                                         |
|  [ Required: 450 ]        [ Actual: 412 ]        [ HR Process: 18 ]        [ Vacant: 20 ]               |
|  Search: [ Search account...     ]       Group Filter: [ All Groups | Group 1 | Group 2 ... ]           |
|                                                                                                         |
|  +---------------------------------------------------------------------------------------------------+  |
|  | [Pool Icon] MOSES HQ (Workforce Pool Inside Plantilla)                  [POOL] [>]                |  |
|  | HC: 42/45 • Vacant: 3                                                                            |  |
|  +---------------------------------------------------------------------------------------------------+  |
|  | [Store Icon] CEBU REGIONAL ACCOUNT (Group 1)                          [WARNING] [>]                |  |
|  | HC: 140/150 • Vacant: 8 • Pipeline: 2                                                             |  |
|  | MFR [=============================       ] 88.5%                                                  |  |
|  +---------------------------------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------------------------------+
```

| Feature / UI Component | Mobile Implementation | Web Current State | Parity Status & Analysis |
| :--- | :--- | :--- | :--- |
| **Account Selector Metrics** | Top 4-card metric strip: Required, Actual, HR Process, Vacant. | 4-card `MetricCard` strip: Required, Actual, HR Process, Vacant. | **Parity Achieved**: Both derive identical aggregates. |
| **Moses HQ Pool Card** | Prominently pinned at top with purple theme, "POOL" badge, "WORKFORCE POOL INSIDE PLANTILLA" subtitle. | Pinned at top with purple styling, `Share2` pool icon, "POOL" badge, and subtitle. | **Parity Achieved**. |
| **Account Urgency Ordering** | 1. Moses HQ pinned;<br>2. Fill rate 0% at bottom;<br>3. Fill rate ascending (problematic accounts first);<br>4. Alphabetical. | 1. Moses HQ pinned;<br>2. Fill rate 0% at bottom;<br>3. Fill rate ascending;<br>4. Alphabetical. | **Parity Achieved**: Exact algorithmic matching in client sorting. |
| **MFR Color Coding** | Green ($\ge 100\%$), Amber ($95\% - 99.9\%$), Red ($< 95\%$). "WARNING" badge if MFR $< 80\%$. | Emerald ($\ge 100\%$), Amber ($95\% - 99.9\%$), Red ($< 95\%$). "Warning" badge if MFR $< 80\%$. | **Parity Achieved**. |
| **Scoped Role Auto-Fire** | Scoped users with 1 account bypass folder screen into roster automatically. | Auto-selects account and executes queries immediately if `ids.length === 1`. | **Parity Achieved** (ADR-001 Compliant). |
| **Group Scoping** | Group filter dropdown ("All Groups", "Group 1".."Group 5"). | Group dropdown filter (`selectorGroupId`) and cleared filter reset button. | **Parity Achieved**. |
| **Detailed Store Roster** | Tabbed screen (`Active`, `Vacancy`, `Inactive`, `Needs HRCO`) with By Employee / By Store switch. | Segmented button (`Employee View`, `Inactive`, `Store Staffing`). | **Partial Gap**: Mobile separates Active/Vacancy/Inactive into top tabs; Web splits them between two views + an Inactive tab. Vacancies are inspected via Store Staffing Drawer on Web. |

---

### 2.2 Slot-Level Inspector Drawer & Capacity Quota Indicators

Under ADR-001, each vacancy or position consists of discrete **Slots**.

```
+---------------------------------------------------------------------------------------------------------+
|                                    SLOT-FIRST LIFECYCLE AUDIT                                           |
|                                                                                                         |
|       +----------+      First Applicant       +--------------+     Confirm Onboard     +---------------+ |
|       |   OPEN   | ─────────────────────────> |   PIPELINE   | ──────────────────────> | HR_PROCESSING | |
|       +----------+                            +--------------+                         +---------------+ |
|            ▲   ▲                                     │                                         │         |
|            │   │              Terminal Drop          │                     Backout             │         |
|            │   └─────────────────────────────────────┘                        │                │         |
|            │                                                                  ▼                ▼         |
|            │                          Resign / Endo / Deactivation                   +-----------------+ |
|            └──────────────────────────────────────────────────────────────────────── |    OCCUPIED     | |
|                                                                                      |    (FILLED)     | |
|                                                                                      +-----------------+ |
+---------------------------------------------------------------------------------------------------------+
```

| Slot State & Attributes | Mobile Implementation | Web Implementation | Parity Assessment |
| :--- | :--- | :--- | :--- |
| **State 1: `open`** | Slot exists, unoccupied, zero applicants. Tracked in `plantilla_slots(slot_status='open')` and `vw_slot_derived_vacancy_shadow`. | Displayed as `open_headcount` in Store Staffing table; listed as open quota slots in `useStoreVacancies`. | **Functionally Parity, UI Gap**: Web lacks slot ID level row drill-down. |
| **State 2: `pipeline`** | Slot linked to 1+ active applicants in recruitment pipeline. | Displayed as part of `hr_pipeline_count` / `pipelineCount`. | **Aggregated Only**: No applicant card link on Web. |
| **State 3: `hr_processing`** | Candidate confirmed onboard, undergoing HR Emploc onboarding compliance. | Displayed as `hr_pipeline_count` and in `MetricCard("HR Process")`. | **Aggregated Only**. |
| **State 4: `occupied` / `filled`** | Bound to active employee row (`current_occupant_plantilla_id = plantilla.id`). | Displayed in `EmployeeTable` as Active Roster row, and `onboard_count` in Store table. | **Parity Achieved**. |
| **State 5: `closed`** | Headcount reduced via HC Reduction workflow. Slot archived with `closure_reason_code`. | Filtered out of active counts. Not inspectable on Web. | **Missing View**: Closed slots cannot be audited on Web. |
| **Commitments & Safety Floor** | Calculated as $\max(1, \text{Occupied} + \text{HR Processing} + \text{Pipeline})$. Guards quota reduction. | Computed in `getVcodeQuotaDetails()` in `src/lib/queries/quota.ts`. Safety floor enforced in `ReviseHeadcountQuotaModal`. | **100% PARITY**. |
| **Slot Inspector Drawer** | Slot cards list VCode, Position, Urgency, Aging days, Source (HC Request vs Import vs Backfill). | Store Staffing Drawer lists VCodes and Position Quotas with "Manage Quota" actions. | **Parity Achieved for Quotas, Gap for Slot Identity**. |

---

### 2.3 Personnel Actions & Lifecycle Triggers

| Action Trigger | Mobile Implementation | Web Current State | Parity Status & Action Plan |
| :--- | :--- | :--- | :--- |
| **Direct Headcount Quota Revision** | Dialog executes `revise_vcode_headcount_quota` RPC with safety floor validation. | `ReviseHeadcountQuotaModal` wired to `useReviseHeadcountQuota` mutation. | **PARITY COMPLETE** |
| **Request Headcount Adjustment** | Dialog executes `submit_headcount_amendment_request` RPC with justification. | `RequestHeadcountAdjustmentModal` wired to `useSubmitHeadcountAmendment` mutation. | **PARITY COMPLETE** |
| **Initiate Separation (Resign / Endo / Terminate)** | Bottom sheet with effective date, type, remarks. Calls `resignEmployee`, `endoEmployee`, or `separateEmployee`. Automatically reopens slot with same VCode. | Capability pill `can_request_deactivation` in drawer is read-only. No modal or mutation wired. | **P1 MUTATION GAP**: Implement `InitiateSeparationModal`. |
| **Set On Leave / Floating / Return Active** | Status modal triggers `set_plantilla_on_leave`, `set_plantilla_floating`, `set_plantilla_active`. | No status change dialog on Web. | **P1 MUTATION GAP**: Implement `UpdateEmploymentStatusModal`. |
| **Request Deactivation** | Submits deactivation request via `create_deactivation_request` with idempotency and resubmit checks. | Read-only drawer banner for pending separation. Capability hint displayed. | **P1 MUTATION GAP**: Implement `RequestDeactivationModal`. |
| **Complete Deactivation** | Reviewer calls `complete_employee_deactivation`, archiving employee and locking record. | Displayed only as capability hint `canReviewDeactivation`. | **P1 MUTATION GAP**: Wire `CompleteDeactivationModal`. |
| **Store Transfer (Reassignment)** | Searchable store picker; validates island group, creates movement request via `plantilla_transfer`. | Displays active transfer overlay banner if transfer in progress (`deriveTransferOverlay`). Transfer initiate button disabled. | **P1 MUTATION GAP**: Implement `TransferEmployeeModal`. |
| **Edit Work Schedule & Daily Rate** | Edits schedule, day-off dropdown, daily rate, and coordinator (via `search_deployers` RPC). | Displays schedule and rate in drawer. No edit modal. | **P2 MUTATION GAP**: Implement `EditWorkScheduleModal`. |
| **HRCO Assignment & Transfer** | Single and bulk HRCO reassignment via `assign_hrco_to_plantilla` and `fn_transfer_employee_hrco`. "Needs HRCO" tab. | Displays HRCO name if present. No HRCO assignment tool or "Needs HRCO" queue on Web. | **P2 GAP**: Add HRCO assignment action. |
| **Benefits PII Reveal & MIKA Sync** | 30s reveal timer logging audit event via `log_employee_benefit_reveal`. Syncs from `plantilla_sync_mika`. | Masked PII returned by backend SQL. No client reveal timer or MIKA refresh button. | **P2 GAP**: Add Reveal PII action with audit logging. |

---

## 3. Schema & RPC Mapping

### 3.1 Database Tables & Views Comparison

```
+---------------------------------------------------------------------------------------------------+
|                                    CORE DATABASE ENTITIES                                         |
|                                                                                                   |
|  [ plantilla ] ──────────── Linked to ───────────> [ plantilla_slots ] ──> [ slot_history ]       |
|       │                                                     │                                     |
|       │ (Occupant)                                          │ (Quota & Lifecycle)                 |
|       ▼                                                     ▼                                     |
|  [ v_plantilla_safe ]                                [ vw_slot_derived_vacancy_shadow ]            |
|       │                                                     │                                     |
|       └───────────────────────┬─────────────────────────────┘                                     |
|                               ▼                                                                   |
|             [ v_web_plantilla_store_staffing ] (MFR: Actual / Actual+Pipeline+Vacancy)             |
+---------------------------------------------------------------------------------------------------+
```

| Object Name | Type | Purpose & Lifecycle Role | Mobile Usage | Web Usage | Parity Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `public.plantilla` | Table | Master physical employee deployment roster. | Polled / filtered directly or via safe views. | Queried via `get_web_plantilla_detail` and list RPCs. | **Aligned** |
| `public.plantilla_slots` | Table | Foundation asset table: defines manpower slots, slot status (`open`, `pipeline`, `hr_processing`, `occupied`, `closed`), home store, and current occupant. | Directly queried for HC reduction data, live commitments, and vacancy counts. | Queried in `getVcodeQuotaDetails` to count commitments by status. | **Aligned** |
| `public.slot_history` | Table | Append-only audit trail for slot lifecycle transitions (`fn_set_slot_status`). | Written via central slot helper. | Read-only audit log. | **Aligned** |
| `public.slot_reason_codes` | Table | Master lookup for slot transitions (`HC_ADD`, `REPLACEMENT`, `TRANSFER_OUT`, `RESIGNED`, `ENDO`, `HC_REDUCTION`, `STORE_CLOSED`). | Referenced in lifecycle mutations. | Not directly queried by Web client. | **Aligned** |
| `public.v_plantilla_safe` | View | Security-invoker view shielding inactive/deleted rows and masking PII. | Queried for account-level employee rosters and roving links. | Backend RPCs build on top of this view. | **Aligned** |
| `public.v_account_allocation_kpi` | View | Aggregates store/account staffing KPIs for card presentation. | Queried in `fetchAccountCardsForScope`. | Replaced on web by `get_web_plantilla_summary`. | **Alternative Pattern (RPC-first on web)** |
| `public.vw_slot_derived_vacancy_shadow` | View | Projects live open slots into vacancy records under ADR-001. | Queried in `fetchVacanciesForAccount`. | Vacancies read via `vacancies` table. | **Aligned** |
| `public.vacancies` | Table | Requisition entities holding VCodes, position titles, and required headcount quota. | Read and mutated in vacancy tab. | Queried via `useStoreVacancies` and `getVcodeQuotaDetails`. | **Aligned** |
| `public.workforce_pool_slots` | Table | Moses HQ workforce pool slots for Relievers, Commandos, and Seasonal staff. | Queried in `WorkforcePoolService.fetchOpenPoolSlots`. | Not queried on Web. | **Web Gap** |
| `public.v_workforce_pool_employees` | View | Active workforce pool personnel with availability and deployment load indicators. | Sourced for Moses HQ pool screens. | Not queried on Web. | **Web Gap** |
| `public.coverage_groups` | Table | Manages multi-store coverage groupings and roving assignments. | Queried via `list_coverage_groups`. | Not queried on Plantilla Web. | **Web Gap** |

---

### 3.2 Backend RPC Signatures & Integration Contracts

#### A. Web Thin-Client RPC Contracts (Deployed & Active)

```sql
-- 1. Scoped Employee List (Dense Grid)
public.list_web_plantilla_employees(
  p_search            text    DEFAULT NULL,
  p_account_id        uuid    DEFAULT NULL,
  p_group_id          uuid    DEFAULT NULL,
  p_store_id          uuid    DEFAULT NULL,
  p_employment_status text    DEFAULT NULL,
  p_deployment        text    DEFAULT NULL,
  p_active_state      text    DEFAULT NULL, -- 'active', 'inactive'
  p_limit             integer DEFAULT 50,
  p_offset            integer DEFAULT 0,
  p_sort_by           text    DEFAULT 'employee_name',
  p_sort_dir          text    DEFAULT 'asc'
) RETURNS TABLE (...);

-- 2. Scoped Store Staffing List (MFR OHM2026_1132 Contract)
public.list_web_plantilla_store_staffing(
  p_search        text    DEFAULT NULL,
  p_account_id    uuid    DEFAULT NULL,
  p_group_id      uuid    DEFAULT NULL,
  p_risk_filter   text    DEFAULT NULL, -- 'under-staffed', 'fully-staffed', 'over-staffed'
  p_limit         integer DEFAULT 50,
  p_offset        integer DEFAULT 0,
  p_sort_by       text    DEFAULT 'store_name',
  p_sort_dir      text    DEFAULT 'asc'
) RETURNS TABLE (...);

-- 3. Top KPI Summary Counters
public.get_web_plantilla_summary(
  p_search        text DEFAULT NULL,
  p_account_id    uuid DEFAULT NULL,
  p_group_id      uuid DEFAULT NULL
) RETURNS TABLE (
  total_active_roster     bigint,
  total_budgeted_slots    bigint,
  total_additional_slots  bigint,
  understaffed_stores     bigint,
  sla_breaches_count      bigint
);

-- 4. Deep Record Inspector
public.get_web_plantilla_detail(
  p_employee_id uuid
) RETURNS TABLE (...);

-- 5. Account Selection Dashboard Status Counts
public.get_plantilla_account_status_counts(
  p_account_ids uuid[]
) RETURNS TABLE (
  account_id uuid,
  status     text,
  row_count  bigint
);
```

#### B. Slot Lifecycle & Quota Mutation RPCs

| RPC Name | Parameters | Purpose | Mobile Integration | Web Integration |
| :--- | :--- | :--- | :--- | :--- |
| `fn_set_slot_status` | `(p_slot_id, p_new_status, p_reason_code, p_performed_by, p_remarks, p_occupant_plantilla_id)` | Authoritative slot status transition engine. Enforces transition matrix; appends to `slot_history`. | Underlying engine for workflow triggers. | Backend only. |
| `revise_vcode_headcount_quota` | `(p_vcode, p_new_target, p_justification, p_source_request_id)` | Direct quota revision by Data Team / Admins. | Wired in `ReviseHeadcountQuotaDialog`. | Wired in `ReviseHeadcountQuotaModal`. |
| `submit_headcount_amendment_request` | `(p_target_vcode, p_current_target, p_proposed_target, p_reason, p_account_id, p_store_id, p_position_id)` | Submits amendment request to Ops / Head Admin approval queue. | Wired in `RequestHeadcountAdjustmentDialog`. | Wired in `RequestHeadcountAdjustmentModal`. |
| `execute_hc_reduction` | `(p_store_id, p_position, p_slots_to_remove, p_reason)` | Closes excess open slots, decrementing quota cleanly under ADR-001. | Wired in mobile HC reduction form. | **Missing on Web**. |
| `create_deactivation_request` | `(p_plantilla_id, p_reason, p_remarks)` | Submits formal deactivation request into Approvals Center. | Wired in `EmployeeProfileScreen`. | **Missing on Web**. |
| `complete_employee_deactivation` | `(p_plantilla_id, p_remarks)` | Approves deactivation and moves personnel to archived inactive state. | Wired in `EmployeeProfileScreen`. | **Missing on Web**. |
| `plantilla_transfer` | `(p_plantilla_id, p_new_store_id, p_reason, p_remarks)` | Initiates employee store transfer movement. | Wired in `_showReassignStoreForm`. | **Missing on Web**. |
| `set_plantilla_on_leave` | `(p_plantilla_id)` | Sets employee status to On Leave; flags position for reliever coverage. | Wired in `_showOnLeaveForm`. | **Missing on Web**. |
| `set_plantilla_active` | `(p_plantilla_id)` | Restores On Leave employee to Active status; releases temporary reliever. | Wired in `_showActivateForm`. | **Missing on Web**. |
| `set_plantilla_floating` | `(p_plantilla_id, p_remarks)` | Sets employee status to Floating Inactive. | Wired in `_showFloatingForm`. | **Missing on Web**. |
| `assign_hrco_to_plantilla` | `(p_plantilla_id, p_hrco_user_id)` | Assigns field HR Coordinator to plantilla employee. | Wired in single and bulk assign sheets. | **Missing on Web**. |
| `plantilla_sync_mika` | `(p_employee_no)` | Triggers sync of personal benefit numbers from MIKA. | Wired in `_refreshMikaBenefits`. | **Missing on Web**. |
| `log_employee_benefit_reveal` | `(p_employee_id, p_benefit_type)` | Emits security audit event when masked Gov IDs/salaries are revealed. | Wired to 30s countdown button. | **Missing on Web**. |

---

## 4. Parity Gap Analysis & Actionable Roadmap

### 4.1 Identified Parity Gaps

#### Category A: Missing Slot-Level Inspection & Roster Features (P0)
1. **Direct Slot Inspector (ADR-001 Native View)**:
   - On Web, users inspect either employees (`EmployeeTable`) or store aggregates (`StoreTable`). There is no view to inspect individual `plantilla_slots` rows (e.g. inspecting an open slot's slot ID, creation date, source HC request, or reservation history).
2. **Detailed Store Staffing Roster Tab**:
   - In Mobile, selecting an account opens the account screen where users can switch between `Active`, `Vacancy`, and `Inactive` tabs. On Web, vacancies are only viewed through a modal inside the Store Staffing drawer. A unified store staffing drill-down view showing both assigned personnel and open vacancy slots side-by-side is missing.

#### Category B: Personnel Lifecycle & Operational Mutations (P1)
3. **Initiate Separation Workflows**:
   - Web has no trigger to mark an employee as `Resigned`, `Endo`, `Terminated`, or `AWOL`.
4. **Update Employment Status (On Leave / Floating / Active)**:
   - Web cannot mark employees `On Leave` or `Floating`, blocking Reliever Coverage workflows.
5. **Store Transfer Mutation**:
   - Web can view active transfers (`deriveTransferOverlay`), but cannot initiate transfers (`plantilla_transfer`).
6. **Deactivation Request & Approval**:
   - Web cannot submit deactivation requests (`create_deactivation_request`) or complete deactivations (`complete_employee_deactivation`).

#### Category C: Workforce Pool & Reliever Coverage Integration (P2)
7. **Moses HQ Workforce Pool Integration**:
   - Mobile features a comprehensive workforce pool management sub-module (`MosesHqPoolListScreen`) for managing Relievers, Commandos, and Seasonal pools. Web currently routes the Moses HQ pool account into standard store staffing tables without specialized pool views.
8. **Reliever & Temporary Coverage Linkage**:
   - In Mobile, an On-Leave employee card highlights "Covered By [Reliever Name]", and Relievers show "Covering For [Employee Name]". This coverage visibility is absent from the Web detail drawer.
9. **Coverage Group Badging**:
   - Mobile shows coverage group codes (`coverage_code`) on multi-store assignments. Web shows store names and roving count without coverage group associations.

#### Category D: Administrative & Security Enhancements (P3)
10. **HRCO Assignment & "Needs HRCO" Queue**:
    - Mobile provides an administrative "Needs HRCO" tab with single and bulk assignment to link employees to coordinators. Missing on Web.
11. **PII Reveal Timer with Audit Trail**:
    - Mobile includes an explicit 30-second reveal toggle with audit logging (`log_employee_benefit_reveal`). Web relies solely on backend role masking.
12. **Work Schedule & Rate Overrides**:
    - Modal to update schedule, day-off, and base rate with coordinator search (`search_deployers`) is missing on Web.

---

### 4.2 Implementation Roadmap

```
+───────────────────────────────────────────────────────────────────────────────────────────+
|                               PARITY IMPLEMENTATION ROADMAP                               |
|                                                                                           |
|  [PHASE 1: Core Lifecycle Mutations] ─────────────────────────────────────────── [P1]     |
|  • Initiate Separation Modal (Resigned, Endo, Terminated, AWOL)                           |
|  • Update Status Modal (On Leave, Floating, Active)                                       |
|  • Deactivation Request & Approval Modals                                                 |
|                                                                                           |
|  [PHASE 2: Store Transfer & Headcount Movement] ──────────────────────────────── [P1]     |
|  • Transfer Personnel Modal (Island group validation, target store picker)                |
|  • Wire plantilla_transfer RPC to CapabilityActionBar                                    |
|                                                                                           |
|  [PHASE 3: Slot Inspector & Detailed Store Roster] ───────────────────────────── [P0]     |
|  • Store Roster View (side-by-side Active Personnel + Vacant Slots)                       |
|  • Slot Inspector Drawer (Slot ID, Status, Lifecycle History, Reservation)                |
|                                                                                           |
|  [PHASE 4: Workforce Pool & Coverage Integration] ────────────────────────────── [P2]     |
|  • Moses HQ Pool sub-dashboard for Relievers/Commandos                                    |
|  • Covered-by / Covering-for cross-linkage in PlantillaDetailDrawer                       |
|                                                                                           |
|  [PHASE 5: Administrative Tools & Security Controls] ──────────────────────────── [P3]     |
|  • HRCO Assignment & "Needs HRCO" filtering                                               |
|  • Work Schedule & Rate editing modal                                                     |
|  • Masked PII Reveal Timer with security audit logging                                    |
+───────────────────────────────────────────────────────────────────────────────────────────+
```

#### Phase 1: Core Lifecycle Mutations (Separation & Deactivation)
- **Goal**: Enable HR Personnel and Admins to transition employees out of the active roster and trigger slot reopening.
- **Tasks**:
  1. Create `src/components/modals/InitiateSeparationModal.tsx`:
     - Dropdown for separation type (`Resigned`, `Endo`, `Terminated`, `AWOL`).
     - Effective date picker + Remarks textarea.
     - Call Supabase mutation executing `_apply_separation` / `plantilla_update_separation`.
     - Invalidate query cache `["plantilla"]`, `["plantilla", "detail"]`, `["plantilla", "summary"]`.
  2. Create `src/components/modals/UpdateEmploymentStatusModal.tsx`:
     - Radio selection for `Active`, `On Leave`, `Floating`.
     - Call `set_plantilla_on_leave`, `set_plantilla_active`, `set_plantilla_floating`.
  3. Create `src/components/modals/RequestDeactivationModal.tsx`:
     - Justification + reason selector.
     - Call `create_deactivation_request`.
  4. Wire modals to `PlantillaDetailDrawer.tsx` `CapabilityActionBar`.

#### Phase 2: Personnel Transfers & Movement
- **Goal**: Allow Ops Managers and Admins to transfer active personnel between authorized stores.
- **Tasks**:
  1. Create `src/components/modals/TransferPersonnelModal.tsx`:
     - Fetch authorized target stores for the account.
     - Filter out current store.
     - Reason dropdown ("Store Initiated", "Employee Requested", "Operational Need").
     - Call `plantilla_transfer` RPC.
  2. Wire `onTransferClick` in `CapabilityActionBar` within `PlantillaDetailDrawer.tsx`.

#### Phase 3: Slot-First Inspector Drawer & Store Roster Drilldown
- **Goal**: Provide complete visibility into the underlying `plantilla_slots` table under ADR-001.
- **Tasks**:
  1. Implement Slot-Level View in `StoreStaffingDrawer.tsx`:
     - Render slot-by-slot roster for the selected store.
     - Visual badge per canonical status: `open` (orange), `pipeline` (purple), `hr_processing` (blue), `occupied` (green).
  2. Implement `SlotDetailDrawer.tsx`:
     - Display `slot_id`, `legacy_vcode`, `position`, `employment_type`.
     - Show current occupant (if occupied) or candidate pipeline link (if pipeline).
     - Render append-only `slot_history` timeline showing lifecycle events.

#### Phase 4: Moses HQ Workforce Pool & Coverage Group Linkage
- **Goal**: Align workforce pool and reliever coverage tracking with mobile capabilities.
- **Tasks**:
  1. Enhance Moses HQ account view in `page.tsx`:
     - When `account.isPoolAccount === true`, provide a dedicated "Workforce Pool Overview" toggle displaying pool types (Reliever, Commando, Seasonal).
  2. Add Reliever Coverage section to `PlantillaDetailDrawer.tsx`:
     - When employee is `On Leave`, display active reliever covering the slot.
     - When employee is a deployed reliever, display the target on-leave employee and store.

#### Phase 5: Administrative Tools (HRCO Assignment, Schedule & Rate Overrides)
- **Goal**: Provide encoders and administrators with full directory governance tooling.
- **Tasks**:
  1. Add HRCO Assignment Modal:
     - Searchable HRCO picker via `search_account_hrcos`.
     - Call `assign_hrco_to_plantilla`.
  2. Add `EditWorkScheduleModal.tsx`:
     - Schedule string input, rest day dropdown, numeric daily rate, coordinator picker via `search_deployers`.
  3. Add PII Reveal Timer to `PlantillaDetailDrawer.tsx`:
     - 30-second countdown button calling `log_employee_benefit_reveal` on unmask.

---

## 5. Verification Checklist & Compliance Summary

- [x] **ADR-001 (Slot-First Architecture)** reviewed and verified across database triggers and schemas.
- [x] **Account Gate Compliance (`ohm#4t8w2xhp`)** confirmed on both mobile and web implementations.
- [x] **MFR Calculation Formula** verified: strictly $\text{Actual} / (\text{Actual} + \text{Pipeline} + \text{Vacancy})$.
- [x] **Store Staffing Quota Controls** verified: `ReviseHeadcountQuotaModal` and `RequestHeadcountAdjustmentModal` are in full parity.
- [x] **Database Schemas & RPC Contracts** comprehensively mapped.
- [x] **Parity Gap Analysis & Actionable Roadmap** documented with clear implementation phases.
