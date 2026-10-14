# Headcount (HC) Request Flow: Mobile-to-Web Parity Audit

**Prompt ID:** `ohm#w52h043a`  
**Date:** 2026-10-14  
**Auditor:** Antigravity (Deep Technical Architecture & Parity Audit)  
**Target Codebases:**
- Mobile Source of Truth: `d:\Projects\OHMployee` (`lib/features/plantilla/`, `lib/features/headcount_requests/`, `lib/features/vacancy/`, `lib/data/services/plantilla_scope_service.dart`, `lib/core/auth/`, `supabase/migrations/`)
- Web Target: `d:\Projects\ohmployee-web` (`src/app/(dashboard)/plantilla/page.tsx`, `src/components/plantilla/StoreStaffingDrawer.tsx`, `src/components/modals/`, `src/lib/queries/quota.ts`, `src/lib/queries/requests.ts`)

---

## 1. Executive Summary

This deep technical audit reviews the **Headcount Request (HC Request / Quota Requisition)** workflows in the mobile Flutter codebase (`OHMployee`) and performs an end-to-end comparative analysis against the Plantilla directory view in `ohmployee-web`.

### Architectural Clarification: Dual Headcount Paradigms
The mobile codebase implements **two distinct headcount requisition patterns** that must not be conflated:

1. **Paradigm A: New Headcount Demand Requisition (`submit_headcount_request`)**
   - **Purpose**: Creates an operational workforce demand requisition for **new slot capacity** (Additional Headcount, Replacement, Reliever, Commando) or a general **HC Reduction** across stationary stores or multi-store roving groups.
   - **Mobile UI**: Full multi-step form screen `AccountHeadcountRequestScreen` (`lib/features/plantilla/plantilla_screen.dart`, lines 4620–6505).
   - **Primary Trigger**: Bottom-right floating action button (`FloatingActionButton` with `+` icon) on the account employee and store list, gated by `_canRequestHeadcount`.
   - **Database Target**: Inserts into `public.headcount_requests` (and `public.hc_request_stores` for multi-store roving requests).
   - **Status on Web (`ohmployee-web`)**: **CRITICAL PARITY GAP**. There is currently **no web equivalent** (`RequestHeadcountModal.tsx` does not exist), and no entry point exists in `src/app/(dashboard)/plantilla/page.tsx` or `src/components/plantilla/StoreStaffingDrawer.tsx`.

2. **Paradigm B: Existing VCode Headcount Quota Revision & Amendment (`revise_vcode_headcount_quota` / `submit_headcount_amendment_request`)**
   - **Purpose**: Mutates or amends the target quota integer for an **already established vacancy / VCode** at a specific store.
   - **Mobile UI**: 
     - Data Team / Admin direct override: `ReviseHeadcountQuotaDialog` (`lib/features/plantilla/widgets/revise_headcount_quota_dialog.dart`).
     - Operations amendment request: `RequestHeadcountAdjustmentDialog` (`lib/features/plantilla/widgets/request_headcount_adjustment_dialog.dart`).
   - **Primary Trigger**: In-row action buttons ("Adjust Quota" / "Request HC Adjustment") inside vacancy cards and store quota tabs.
   - **Status on Web (`ohmployee-web`)**: **FULL OPERATIONAL PARITY**. Already implemented via [`ReviseHeadcountQuotaModal.tsx`](file:///d:/Projects/ohmployee-web/src/components/modals/ReviseHeadcountQuotaModal.tsx) and [`RequestHeadcountAdjustmentModal.tsx`](file:///d:/Projects/ohmployee-web/src/components/modals/RequestHeadcountAdjustmentModal.tsx) embedded in [`StoreStaffingDrawer.tsx`](file:///d:/Projects/ohmployee-web/src/components/plantilla/StoreStaffingDrawer.tsx).

---

## 2. Mobile Step-by-Step Flow Breakdown: New Headcount Request

In `OHMployee`, when an Operations Lead or Administrator initiates a new Headcount Request, the execution flow follows a disciplined 5-step validation and submission pipeline.

```
+----------------------------------------------------------------------------------------------------+
|                                    MOBILE USER INTERACTION FLOW                                    |
+----------------------------------------------------------------------------------------------------+
  1. USER ENTRY
     [Plantilla Account View] ──> Tap FloatingActionButton (+) [Gated by _canRequestHeadcount]
     or [Moses HQ Pool]       ──> Tap FloatingActionButton (+)
     or [Approved NSR Bridge] ──> "Request Headcount" button
            │
            ▼
  2. FORM INITIALIZATION (AccountHeadcountRequestScreen)
     • Loads Positions for Account (account_positions)
     • Loads Stores for Account (stores)
     • Loads Ref Locations (ref_locations -> provinces & cascading cities)
     • Loads Recent HC Requests (headcount_requests for duplicate checks)
     • Checks System Governance Freeze (recruitment_freeze)
            │
            ▼
  3. STEP 1: WORKFORCE TYPE & LOCATION
     • Workforce Type: Stationary | Roving | Floating (Floating is blocked: "Not enabled yet")
     • Province & City Dropdowns (cascading from master data)
     • If Stationary: Store Autocomplete + Verification Card (verified / available / notFound)
     • If Roving: Multi-store picker (2 to 20 stores; enforces Island Group consistency)
            │
            ▼
  4. STEP 2: DUPLICATE & PENDING CHECKS
     • Existing Store Requests Panel displays pending requests count
     • If pending requests exist: Warning Banner ("Pending HC request already exists for this store")
     • Exact Duplicate Candidate check: store + position + headcount + employment + vacant_date
            │
            ▼
  5. STEP 3: POSITION & DEMAND
     • Position Dropdown
     • Request Type: Additional Headcount | Replacement | Reliever | Commando | HC Reduction
     • Headcount Needed: Stepper [-] [N] [+] (Min: 1; if HC Reduction: capped to reducible slots)
            │
            ▼
  6. STEP 4: TIMELINE & URGENCY (Bypassed if HC Reduction)
     • Vacant Date Picker
     • Urgency Tier Dropdown: Low | Medium | High | Critical
     • Target Fill Date (Auto-calculated: Critical=+3d, High=+7d, Medium=+14d, Low=+30d)
     • Target Date Validation: Cannot precede Vacant Date
            │
            ▼
  7. STEP 5: BUSINESS JUSTIFICATION
     • Multiline text input (Max: 500 chars)
     • Mandatory if HC Reduction (Min: 20 characters); Recommended for expansions
            │
            ▼
  8. REVIEW & SUBMISSION
     • Review Modal (_showReviewModal): Full summary confirmation
     • Supabase RPC Call: submit_headcount_request(p_input)
     • Success Action Sheet (showRequestSubmittedSheet): "View in My Requests" or "Dismiss"
```

### Detailed Form Field Breakdown

| Section | Field Label | Data Type / Control | Source / Options | Validation & Business Rules |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | Operational Account | Snapshot / Display | Inherited from active Plantilla account (or Moses HQ) | Must be within user's allowed account scope. |
| **Step 1** | Workforce Type | Dropdown | `Stationary`, `Roving`, `Floating` | • `Stationary`: Single store required.<br>• `Roving`: 2–20 stores required.<br>• `Floating`: Hard blocked with warning. |
| **Step 1** | Area Province | Dropdown | `ref_locations.province` | Required for Stationary; optional for Roving. |
| **Step 1** | Area City | Cascading Dropdown | `ref_locations.city` (filtered by province) | Filter store dropdown options. |
| **Step 1** | Target Store (Stationary) | Autocomplete + Verification Card | `stores` table for account | Verified store required. If not found, offers "Request New Store" bridge. |
| **Step 1** | Target Stores (Roving) | Multi-select Chip Picker | `stores` table for account | **Island Group Guard**: All stores must share the same `island_group` (Luzon, Visayas, Mindanao). |
| **Step 2** | Existing Requests | Read-only Amber Panel | Live query on `headcount_requests` | Displays count of existing requests. Warns if pending approval exists. |
| **Step 3** | Position | Dropdown | `account_positions` (or pool positions) | Required. If HC Reduction, only positions with reducible slots (`open` slots >= 1) are selectable. |
| **Step 3** | Request Type | Dropdown | `Additional Headcount`, `Replacement`, `Reliever`, `Commando`, `HC Reduction` | Defaults to `Additional Headcount`. `HC Reduction` is restricted to Ops Team. |
| **Step 3** | Headcount Needed | Stepper `[-] [N] [+]` | Integer >= 1 | Minimum 1. If `HC Reduction`, cannot exceed reducible slots count. |
| **Step 4** | Vacant Date | Date Picker | Calendar selection | Required (unless HC Reduction). Defaults to current date. |
| **Step 4** | Urgency Tier | Dropdown | `Low`, `Medium`, `High`, `Critical` | Drives initial Target Fill Date recommendation (+30d, +14d, +7d, +3d). |
| **Step 4** | Target Fill Date | Date Picker | Calendar selection | Must not precede `Vacant Date` (`target.isBefore(vacant)` triggers error). |
| **Step 5** | Justification | Text Area (up to 500 chars) | Freeform text | Mandatory for `HC Reduction` (min 20 chars); recommended for expansions. |

---

## 3. RBAC & Role-Gating Analysis

### Who Can Submit a Headcount Request?

In `lib/features/plantilla/plantilla_screen.dart`, line 275:
```dart
bool get _canRequestHeadcount {
  return widget.loggedInUser.hasFullAccess || widget.loggedInUser.isOpsTeam;
}
```

Combined with `lib/core/auth/auth_service.dart` and `lib/core/constants/role_constants.dart`:

```dart
bool get hasFullAccess => roleLevel >= 90; // Super Admin (100), Head Admin (90)

bool get isOpsTeam =>
    this == AppRole.om ||
    this == AppRole.hrco ||
    this == AppRole.atl ||
    this == AppRole.tl;
```

#### Complete Role Access Matrix

| Role | Role Level | Can Submit New HC Request (`submit_headcount_request`) | Can Submit Quota Amendment (`submit_headcount_amendment_request`) | Can Direct Override Quota (`revise_vcode_headcount_quota`) | Scope Boundary |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Super Admin** | 100 | **YES** | **YES** | **YES** | Global (All accounts) |
| **Head Admin** | 90 | **YES** | **YES** | **YES** | Global (All accounts) |
| **Operations Manager (OM)** | 80 | **YES** | **YES** | NO (Submits amendment) | Account Scoped |
| **Team Leader (TL)** | 70 | **YES** | **YES** | NO (Submits amendment) | Account Scoped |
| **Assistant TL (ATL)** | 60 | **YES** | **YES** | NO (Submits amendment) | Account Scoped |
| **HR Coordinator (HRCO)** | 50 | **YES** | **YES** | NO (Submits amendment) | Account Scoped |
| **Encoder** | 40 | NO | NO | **YES** (Direct revision only) | Scoped / Data Team bypass |
| **Recruitment Team** | 30 | NO | NO | NO | Account Scoped |
| **HR Personnel** | 30 | NO | NO | NO | Account Scoped |
| **Backoffice Personnel** | 20 | NO | NO | NO | Account Scoped |
| **Viewer** | 10 | NO | NO | NO | Read-only |

### Backend Database RPC Guard
In `public.submit_headcount_request`:
```sql
IF NOT (public.i_have_full_access() OR public.i_am_ops()) THEN
  RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
END IF;

IF NOT public.i_have_full_access()
   AND NOT (v_account.account_name = ANY(public.get_my_allowed_accounts())) THEN
  RETURN jsonb_build_object('ok', false, 'error', 'out_of_scope');
END IF;
```

### Pending Request Cooldown & Duplicate Guarding
1. **Cooldown Period**: Mobile does **not** employ an arbitrary blocking cooldown timer (e.g., 24 hours lock).
2. **Pending Request Warning**: If any request for the target store has a status of `pending`, `pending_approval`, `pending_om_approval`, `under_review`, or `pending_head_admin_approval`, a persistent amber warning card is surfaced to alert the user.
3. **Exact Duplicate Candidate Warning**: If a recent request in the account matches the exact combination of `Store + Position + Headcount Needed + Employment Type + Vacant Date`, a distinct warning box informs the user:
   > *"A similar recent request exists for this store, position, HC, employment type, and vacant date."*
4. **Recruitment Freeze Enforcement**: If `recruitment_freeze` is active via `SystemGovernanceService`, the submit button is permanently disabled with the label: *"Recruitment freeze is active"*.

---

## 4. Underlying Supabase RPC Signatures & Target Tables

### 4.1 New Headcount Request: `public.submit_headcount_request`

- **Database Function**: `public.submit_headcount_request(p_input jsonb)`
- **Security**: `SECURITY DEFINER`, `SET search_path TO 'public'`
- **Target Tables**:
  - `public.headcount_requests` (Primary request entity)
  - `public.hc_request_stores` (Child entity for multi-store roving requests)
- **Parameter Payload Schema (`p_input jsonb`)**:

```typescript
export interface SubmitHeadcountRequestInput {
  // Required Core Identifiers
  account_id: string; // UUID
  account_name: string; // Snapshot text
  position_id: string; // UUID
  position_name: string; // Snapshot text
  workforce_type: "stationary" | "roving" | "floating";
  employment_type: "Stationary" | "Roving" | "Floating";
  request_type: "Additional Headcount" | "Replacement" | "Reliever" | "Commando" | "HC Reduction";
  headcount_needed: number; // Positive integer >= 1
  reason: string; // Justification text (min 20 chars if HC Reduction)

  // Timeline (Omitted if HC Reduction)
  vacant_date?: string | null; // "YYYY-MM-DD"
  target_fill_date?: string | null; // "YYYY-MM-DD"
  urgency?: "Low" | "Medium" | "High" | "Critical"; // Defaults to "Medium"

  // Stationary Deployment Path
  store_id?: string | null; // UUID
  store_name?: string | null; // Snapshot text
  area_province?: string | null; // Province snapshot
  area_city?: string | null; // City snapshot

  // Roving Deployment Path (Store-Array Mode)
  store_ids?: string[]; // Array of UUIDs (min: 2, max: 20)

  // Linkage to New Store Request (Optional)
  source_new_store_request_id?: string | null; // UUID
}
```

- **Return Payload Schema**:
```json
{
  "ok": true,
  "request_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "status": "pending",
  "workforce_type": "stationary",
  "store_count": 0,
  "island_group": null
}
```

---

### 4.2 Existing VCode Quota Amendment: `public.submit_headcount_amendment_request`

- **Database Function**:
  ```sql
  public.submit_headcount_amendment_request(
    p_target_vcode    text,
    p_current_target  integer,
    p_proposed_target integer,
    p_reason          text,
    p_account_id      uuid,
    p_store_id        uuid DEFAULT NULL,
    p_position_id     uuid DEFAULT NULL
  ) RETURNS jsonb;
  ```
- **Target Table**: Inserts into `public.headcount_requests` with `request_type = 'Quota Amendment'` and `status = 'pending'`.
- **Pre-validation**: Enforces Safety Floor = `GREATEST(1, occupied + hr_processing + pipeline)`. If `p_proposed_target < safety_floor`, aborts with error `QUOTA_REDUCTION_BLOCKED`.

---

### 4.3 Data Team Direct Quota Override: `public.revise_vcode_headcount_quota`

- **Database Function**:
  ```sql
  public.revise_vcode_headcount_quota(
    p_vcode             text,
    p_new_target        integer,
    p_justification     text,
    p_source_request_id uuid DEFAULT NULL
  ) RETURNS jsonb;
  ```
- **Target Tables**:
  - Updates `public.vacancies.required_headcount`
  - Updates `public.vacancy_requirements.hc_needed`
  - Inserts/updates `public.plantilla_slots` (allocates new `open` slots on expansion, or marks `open` slots as `hc_reduced` on reduction)
  - Inserts into audit log `public.headcount_quota_revisions`

---

## 5. Web Parity Audit & Gap Analysis (`ohmployee-web`)

### Existing Web Assets Comparison

```
+------------------------------------------+-----------------------+-----------------------+
| FEATURE / CAPABILITY                     | MOBILE (OHMployee)    | WEB (ohmployee-web)   |
+------------------------------------------+-----------------------+-----------------------+
| Direct VCode Quota Override              | ReviseHeadcountQuota  | ReviseHeadcountQuota  |
|                                          | Dialog (Supported)    | Modal (Supported)     |
+------------------------------------------+-----------------------+-----------------------+
| Existing VCode Quota Amendment Request   | RequestHeadcount      | RequestHeadcount      |
|                                          | AdjustmentDialog      | AdjustmentModal       |
+------------------------------------------+-----------------------+-----------------------+
| Approval of Headcount Requisitions       | RequestCenterScreen   | approvals/page.tsx    |
|                                          | (Supported)           | (Supported)           |
+------------------------------------------+-----------------------+-----------------------+
| New Headcount Demand Requisition Modal   | AccountHeadcount      | MISSING               |
|                                          | RequestScreen (Full)  | (GAP IDENTIFIED)      |
+------------------------------------------+-----------------------+-----------------------+
| Primary Entry Point in Plantilla Roster  | FAB (+) button        | MISSING               |
|                                          | (Supported)           | (GAP IDENTIFIED)      |
+------------------------------------------+-----------------------+-----------------------+
| Entry Point inside Store Staffing Drawer | Quota Tab actions     | Only existing VCodes  |
|                                          | (Supported)           | (New HC missing)      |
+------------------------------------------+-----------------------+-----------------------+
| Roving Multi-Store Array (Island Group)  | Supported (2-20 st.)  | Missing in Requisition|
+------------------------------------------+-----------------------+-----------------------+
```

### Identified Gaps on Web

1. **Missing Requisition Modal (`RequestHeadcountModal.tsx`)**:
   While `RequestHeadcountAdjustmentModal.tsx` exists, it only works when an existing `vcode` is provided. If an account needs to open a new position at a store, or initiate a roving headcount request, there is no modal to construct and submit the payload to `submit_headcount_request`.

2. **Missing Main Plantilla Directory Action**:
   In `src/app/(dashboard)/plantilla/page.tsx`, once an account is loaded, the page offers view switching (Employee, Inactive, Store Staffing), but there is no primary button to **"Request Headcount"**.

3. **Missing "Add Position / Request HC" Action in `StoreStaffingDrawer`**:
   In `src/components/plantilla/StoreStaffingDrawer.tsx`, the "Position Quotas & VCodes" tab displays existing VCodes. However, if a store needs a position that is not yet listed, there is no button to initiate a new headcount request for that store.

4. **Missing TanStack Query Hook**:
   `src/lib/queries/requests.ts` lacks a dedicated mutation hook for `submit_headcount_request`.

---

## 6. Implementation Roadmap & UI Spec for Web Parity

To achieve 100% parity with the mobile application, the following components and integration points should be implemented.

### 6.1 TanStack Query Hook: `useSubmitHeadcountRequest`

Add to `src/lib/queries/requests.ts`:

```typescript
export async function submitHeadcountRequest(
  input: SubmitHeadcountRequestInput
): Promise<{ ok: boolean; request_id: string; status: string }> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("submit_headcount_request", {
    p_input: input,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError("unauthorized", "Unauthorized: Only Operations roles and Admins may submit headcount requests.");
    }
    throw new RequestDataError("generic", error.message);
  }

  if (!data?.ok) {
    throw new RequestDataError("validation", data?.message || data?.error || "Submission rejected.");
  }

  return data;
}

export function useSubmitHeadcountRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: SubmitHeadcountRequestInput) => submitHeadcountRequest(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["pending-headcount-requests"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
    },
  });
}
```

---

### 6.2 New Component: `RequestHeadcountModal.tsx`

**File Location:** `src/components/modals/RequestHeadcountModal.tsx`

#### UI Design Specification

```
+----------------------------------------------------------------------------------------------------+
| Request Headcount                                                                              [X] |
| Operational requisition for new store headcount, replacements, or roving coverage                |
+----------------------------------------------------------------------------------------------------+
| Target Account: Suyen Corporation (Bench)                             [Stationary | Roving] Tabs   |
+----------------------------------------------------------------------------------------------------+
| STEP 1: STORE & WORKFORCE TARGET                                                                   |
| [ Province: Metro Manila            v ]  [ City: Taguig City                  v ]                  |
| Target Store:                                                                                      |
| [ Search or select active store...                                            v ]                  |
| (•) Active Store Verified: Bench BGC High Street (ST-0192)                                         |
+----------------------------------------------------------------------------------------------------+
| STEP 2: POSITION & REQUISITION DETAILS                                                             |
| Position:                                          Request Type:                                   |
| [ Sales Associate                   v ]            [ Additional Headcount             v ]          |
|                                                                                                    |
| Headcount Needed:                                                                                  |
| [ - ]  [  2  ]  [ + ]    (Requesting +2 slots expansion)                                           |
+----------------------------------------------------------------------------------------------------+
| [!] Existing Requests Notice: 1 pending request already submitted for this store.                  |
+----------------------------------------------------------------------------------------------------+
| STEP 3: TIMELINE & URGENCY                                                                         |
| Vacant Date:                      Target Fill Date:                 Urgency:                       |
| [ 2026-10-14     v ]              [ 2026-10-28     v ]              [ Medium (14d)     v ]         |
+----------------------------------------------------------------------------------------------------+
| STEP 4: OPERATIONAL JUSTIFICATION                                                                  |
| [ Detail the operational rationale for this headcount requisition...                             ] |
+----------------------------------------------------------------------------------------------------+
|                                                                    [ Cancel ]  [ Submit Request ]  |
+----------------------------------------------------------------------------------------------------+
```

#### Key Functional Features of `RequestHeadcountModal.tsx`:
1. **Pre-fill Intelligence**:
   - If opened from `StoreStaffingDrawer`, `storeId`, `storeName`, and `accountId` are pre-locked.
   - If opened from the main Plantilla toolbar, account is pre-selected and store is chosen via an autocomplete selector.
2. **Workforce Type Toggle**:
   - `Stationary`: Single store selection.
   - `Roving`: Multi-store chip selector (validates 2–20 stores and checks island group matching).
3. **Smart Fill Date Calculation**:
   - Selecting `Urgency` tier automatically suggests `target_fill_date` based on the mobile formula:
     - Critical: +3 days
     - High: +7 days
     - Medium: +14 days
     - Low: +30 days
4. **Duplicate Warning Alerts**:
   - Queries `headcount_requests` for the selected store.
   - Surfaces non-blocking amber badge if pending requests exist.
   - Surfaces warning if identical candidate already exists.
5. **Confirmation Step**:
   - Modal confirmation before final submission.

---

### 6.3 Entry Point Integrations

#### 1. Main Plantilla Directory (`src/app/(dashboard)/plantilla/page.tsx`)
Add a primary action button in the page toolbar when an account is selected:

```tsx
{/* Primary Action Button inside Plantilla Toolbar */}
{canRequestAdjustment && accountId && (
  <button
    type="button"
    onClick={() => setIsRequestHeadcountOpen(true)}
    className="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-3.5 py-2 text-sm font-semibold text-white shadow-xs hover:bg-brand-700 transition-colors"
  >
    <UserPlus className="h-4 w-4" />
    <span>Request Headcount</span>
  </button>
)}
```

#### 2. Store Staffing Drawer (`src/components/plantilla/StoreStaffingDrawer.tsx`)
In the "Position Quotas & VCodes" tab header:

```tsx
<div className="flex items-center justify-between">
  <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-text-secondary">
    <Sliders className="h-4 w-4 text-text-muted" />
    <span>Position Quotas & VCodes</span>
  </div>
  <div className="flex items-center gap-2">
    {canRequestAdjustment && (
      <button
        type="button"
        onClick={() => setIsNewHeadcountModalOpen(true)}
        className="inline-flex items-center gap-1 text-xs font-semibold text-brand-600 hover:text-brand-700 transition-colors"
      >
        <Plus className="h-3.5 w-3.5" />
        <span>New Position HC</span>
      </button>
    )}
    <button
      type="button"
      onClick={() => refetchVacancies()}
      className="text-[11px] text-text-muted hover:text-text-primary inline-flex items-center gap-1 transition-colors"
    >
      <RefreshCw className="h-3 w-3" />
      Refresh
    </button>
  </div>
</div>
```

---

## 7. Audit Conclusion & Deliverable Summary

| Item | Status | Finding / Action Required |
| :--- | :---: | :--- |
| **Existing VCode Quota Amendment Flow** | **100% PARITY** | Fully implemented in web (`StoreStaffingDrawer` + `ReviseHeadcountQuotaModal` + `RequestHeadcountAdjustmentModal`). |
| **New Headcount Demand Requisition Flow** | **0% PARITY (GAP)** | Mobile has full 5-step form in `AccountHeadcountRequestScreen`; Web has no equivalent modal. |
| **Target Database RPC** | **VERIFIED** | `public.submit_headcount_request(p_input jsonb)` is deployed and authoritative in Supabase. |
| **RBAC Rules** | **DOCUMENTED** | Super Admin, Head Admin, OM, HRCO, TL, ATL can submit; Encoder, Recruitment, Viewer denied. |
| **Duplicate / Cooldown Rules** | **DOCUMENTED** | Real-time pending requests warning + exact duplicate warning + recruitment freeze check. |
| **Web Roadmap** | **SPECIFIED** | Create `RequestHeadcountModal.tsx`, add mutation hook in `requests.ts`, and wire entry points in `page.tsx` and `StoreStaffingDrawer.tsx`. |

---
*End of Audit Report. Generated for prompt ID `ohm#w52h043a`.*
