# Baseline Architecture, Theme, and Core Modules Audit
**Audit ID:** ohm#w10a482b  
**Date:** 2026-10-09  
**Auditor:** Antigravity (Pair Programming Agent)  
**Target Application:** `ohmployee_web` (Web Companion to OHMployee Mobile)  
**Status:** COMPLETE (Baseline Architecture Audit & Parity Roadmap)

---

## Executive Summary

This baseline audit evaluates the `ohmployee_web` architecture, styling infrastructure, Supabase integration, routing, and core module state to establish the technical blueprint for replicating recent mobile enhancements across:
1. **Global Light Mode Default Enactment**
2. **Headcount Quota Revision (`Adjust Quota` & `Request HC Adjustment`)**
3. **Request Center Menu Label Streamlining & Pending Badges**
4. **CENCOM Slot-Authority Metric Alignment & Group Performance Views**

The web codebase is built on **Next.js 16.2.4 (App Router)** with **React 19.2.4**, **Tailwind CSS v4**, and **TanStack React Query v5**. It consumes Supabase via browser client calls and database RPCs/views. While the Plantilla, Vacancy, and HR Emploc modules have high-fidelity read shells and select mutation capabilities, the CENCOM and Approvals modules are currently scaffold stubs (`ModuleEmptyState`). This audit details the exact code touchpoints and outlines an actionable, low-risk implementation roadmap.

---

## 1. Framework & Architecture Discovery

### 1.1 Framework & Runtime
- **Framework:** Next.js `16.2.4` using the App Router (`src/app`).
- **React Engine:** React `19.2.4` and React DOM `19.2.4`.
- **TypeScript:** TypeScript `5.x` with `@/*` mapped to `./src/*`.
- **Routing Organization:**
  - Route Groups:
    - `(auth)`: Contains `/login` for Supabase authentication.
    - `(dashboard)`: Contains core administrative command views (`/dashboard`, `/cencom`, `/vacancy`, `/hr-emploc`, `/plantilla`, `/approvals`, `/users`, `/team-directory`, `/notifications`, `/reports`, `/settings`, `/more`).
  - Layout Wrapper: `src/app/(dashboard)/layout.tsx` wraps all protected views inside `DashboardAuthShell`.

### 1.2 UI Library & Styling Setup
- **CSS Engine:** Tailwind CSS v4 (`@tailwindcss/postcss` v4 + `tailwindcss` v4) configured via `postcss.config.mjs` and `src/app/globals.css`.
- **UI Architecture:** Zero third-party component libraries (no Radix UI, Shadcn UI CLI, or Chakra). The project uses a custom, lightweight Shared Web UI System (`docs/state/web_ui_system_state.md`):
  - **Shared Layout Primitives (`src/components/shared/`):**
    - `AdminPageHeader.tsx`: Uniform title, subtitle, badges, and primary action bar.
    - `MetricCard.tsx`: Standardized 100px KPI cards with CLS-preventing pulse skeletons.
    - `AdminFilterBar.tsx`: Modular search and filter bar container with view toggles.
    - `DataState.tsx`: Explicit boundary container for loading, empty, access-denied, and retryable error states.
    - `DetailDrawer.tsx`: Standard right-sliding drawers (`drawer-width-md`: 460px, `drawer-width-lg`: 640px, `drawer-width-xl`: 800px).
    - `CapabilityActionBar.tsx`: Permission-aware sticky action footer.
  - **UI Primitives (`src/components/ui/`):**
    - `StatusBadge.tsx`: Semantic badge system (`success`, `warning`, `danger`, `info`, `neutral`, `accent`).
  - **Icons:** `lucide-react` (`^1.16.0`).

### 1.3 State Management & Data Fetching
- **Client State:** `@tanstack/react-query` v5 (`^5.100.13`) initialized in `src/app/providers.tsx` via `QueryClientProvider`.
- **Query Organization:** Centralized under `src/lib/queries/`:
  - `plantilla.ts`: Store staffing and employee roster queries.
  - `vacancy.ts`: Requisition and vacancy applicant queries.
  - `hr_emploc.ts`: HR Emploc compliance queue and mutation RPCs.
  - `dashboard.ts`: High-level command center KPIs.
  - `freeze.ts`: Emergency read-only freeze state checks.
- **Session & Inactivity Management:**
  - `useIdleTimer.ts` (`src/hooks/useIdleTimer.ts`): Tracks user interaction (mouse/keyboard) without triggering on background API refetches.
  - `IdleWarningModal.tsx` (`src/components/IdleWarningModal.tsx`): Displays a warning dialog before signing out inactive sessions.

### 1.4 Supabase Client & Auth Architecture
- **Client Configuration:** Single browser client instantiated in `src/lib/supabase/client.ts` via `@supabase/supabase-js` (`^2.106.1`).
- **Environment Management:** Multi-environment support switched via `node scripts/switch-env.js [staging|prod]`:
  - **Staging Project Ref:** `qqiiznmqxfoamqytjica` (`.env.staging`)
  - **Production Project Ref:** `rwxelulyapjgaarlwkus` (`.env.prod`)
- **Web Auth Bootstrap (`src/lib/auth.ts`):**
  - Canonical RPC: `public.get_web_current_user_context()`.
  - Validates `access_status === "allowed"`.
  - Resolves `allowed_module_keys` to drive visible navigation items in `Sidebar.tsx` and `AdminTopbar.tsx`.
  - Normalizes JSONB structures for `group_scope` and `account_scope` (supporting `all`, `scoped`, and `none` modes).
  - Normalizes `module_capabilities` for UI display gating (backend RLS/RPC remains final authority).

---

## 2. Theme Configuration Audit

### 2.1 Current Theme Implementation
- **Theme Variables:** Declared on `:root` in `src/app/globals.css` and bound to Tailwind via `@theme inline`:
  - Surfaces: `--background` (`#f8fafc`), `--surface-base` (`#ffffff`), `--surface-header` (`#fafafa`), `--surface-hover` (`#f8fafc`), `--surface-selected` (`#f0f9ff`).
  - Text: `--text-primary` (`#0f172a`), `--text-secondary` (`#475569`), `--text-muted` (`#94a3b8`).
  - Tables: Dedicated table tokens (`--table-header`, `--table-row`, `--table-row-hover`, `--table-row-selected`, `--table-rule`, `--table-text`).
  - Status: Runtime badge tokens (`--status-success-*`, `--status-warning-*`, `--status-danger-*`, etc.).
- **Dark Mode Status:**
  - In task `ohm#9m2v5jqk`, the `@media (prefers-color-scheme: dark)` override block was removed from `globals.css` to prevent browser dark-mode detection from inverting colors.
  - The root `<html>` element in `src/app/layout.tsx` does not currently specify `data-theme="light"` or `style={{ colorScheme: "light" }}`.
- **Intentional High-Contrast Dark Elements:**
  - `Sidebar.tsx`: Uses `bg-slate-950 text-white` as a high-contrast desktop command sidebar.
  - `dashboard/page.tsx`: Uses `bg-slate-950` for security command telemetry containers.

### 2.2 Recommendations for Global Light Mode Hardening
1. **Root HTML Enforcement:**
   In `src/app/layout.tsx`:
   ```tsx
   <html
     lang="en"
     data-theme="light"
     style={{ colorScheme: "light" }}
     className={`h-full antialiased ${dmSans.variable} ${dmMono.variable}`}
   >
   ```
2. **Sanitize Residual Dark Mode Comments and Classes:**
   - Update CSS documentation headers in `src/app/globals.css` to declare light mode as strictly authoritative.
   - Ensure all dialog overlays and drawer backdrops use `var(--surface-overlay)` (`rgba(15, 23, 42, 0.4)`).
   - Ensure form controls, native select elements, and inputs consistently render light surfaces with `bg-white text-slate-900 border-slate-200`.

---

## 3. Module Inventory & Mapping (Mobile vs. Web Parity)

### 3.1 Plantilla & Vacancies: Headcount Quota Revision

#### Mobile Implementation Baseline
- **Capabilities & Roles:**
  - `canReviseHeadcountQuota` (`Super Admin`, `Head Admin`, `Encoder`): Permitted to execute direct quota changes in-place.
  - `canRequestHeadcountAdjustment` (`Ops Team`, `Data Team`, `Admins`): Permitted to submit quota amendment requests requiring approval.
- **Database Contracts:**
  - Direct Revision: `public.revise_vcode_headcount_quota(p_vcode, p_new_target, p_justification, p_source_request_id)`.
  - Amendment Request: `public.submit_headcount_amendment_request(p_account_id, p_store_id, p_position_id, p_proposed_target, p_target_vcode, p_reason)`.
- **Validation & Safety Floor Formula:**
  $$\text{Commitments} = \text{Occupied} + \text{HR Processing} + \text{Pipeline}$$
  $$\text{Safety Floor} = \max(1, \text{Commitments})$$
  $$\text{New Target} \ge \text{Safety Floor}$$
  - Justification/Reason: Mandatory string, minimum 5 characters.
- **Mobile Entry Point:** Mounted on `_VacancyCard` in the Plantilla Vacancy tab as two action buttons: `Adjust Quota` and `Request HC Adjustment`.

#### Web Module Mapping
1. **Vacancy Web (`src/app/(dashboard)/vacancy/page.tsx` & `VacancyDetailDrawer.tsx`):**
   - **Current State:** `VacancyTable` renders dense list of vacancies; selecting a row opens `VacancyDetailDrawer`. Inside `VacancyDetailDrawer`, `CapabilityActionBar` currently provides: `Approve Vacancy`, `Add Applicant`, `Update Applicant Status`, `Request Closure`.
   - **Target Integration:**
     - Add `Adjust Quota` and `Request HC Adjustment` action buttons into `CapabilityActionBar` in `VacancyDetailDrawer.tsx`.
     - Mount lightweight modal dialogs: `ReviseHeadcountQuotaModal.tsx` and `RequestHeadcountAdjustmentModal.tsx`.
2. **Plantilla Web (`src/app/(dashboard)/plantilla/page.tsx`):**
   - **Current State:** Store-centric view renders `StoreTable` (Store Code, Store Name, Account/Region, Actual, HR Pipeline, Vacancy, Required, MFR %, Staffing Risk, SLA Badge). Store rows are currently read-only with no drawer.
   - **Target Integration:**
     - Enable store row click or add an action dropdown column in `StoreTable` to open a Store Staffing drawer or trigger the quota modals.

---

### 3.2 Request Center & Approvals: Menu Streamlining & Pending Badges

#### Mobile Implementation Baseline
- **Streamlined Labels:** Removed redundant "Request" / "Requests" suffixes across the 8 request modules:
  - `New Store Request` $\rightarrow$ **`New Stores`**
  - `Headcount Requests` $\rightarrow$ **`Headcount`**
  - `Coverage Requests` $\rightarrow$ **`Coverage`**
  - `Vacancy Closure Requests` $\rightarrow$ **`Vacancy Closures`**
  - `HR Emploc Deletions` $\rightarrow$ **`HR Emploc Deletions`**
  - `Deactivation Requests` $\rightarrow$ **`Deactivations`**
  - `Applicant Movement Requests` $\rightarrow$ **`Applicant Movements`**
  - `Account Group Transfer Requests` $\rightarrow$ **`Account Group Transfers`**
  - Preserved: **`My Requests`**
- **Pending Badges Service (`RequestCenterBadgeService`):** Queries live pending counts across all 8 request tables (`new_store_requests`, `headcount_requests`, `coverage_requests`, `vacancy_closure_requests`, `hr_emploc_deletion_requests`, `v_deactivation_requests`, `applicant_movement_requests`, `account_group_transfer_requests`) and renders pill badges when `count > 0`.
- **Headcount Request Approval Pipeline:** Supports `request_type = 'Quota Amendment'` items, displaying previous target vs. proposed target, justification, and approval invoking `public.approve_headcount_amendment_request`.

#### Web Module Mapping
1. **Approvals Web (`src/app/(dashboard)/approvals/page.tsx`):**
   - **Current State:** Scaffold stub rendering `<ModuleEmptyState href="/approvals" />`.
   - **Target Integration:**
     - Replace stub with a multi-tab or card-based **Request Center Command Hub**.
     - Display the 8 streamlined categories + My Requests with live count badges.
     - Implement the **Headcount Requests** approval queue with full Quota Amendment card/table support (Target VCode, Delta, Previous Target $\rightarrow$ Proposed Target, Reason, Approve/Reject actions).
2. **Navigation Sidebar (`src/components/Sidebar.tsx`):**
   - Currently displays plain module links.
   - Can optionally display an aggregate pending badge on the `Approvals` sidebar link when unreviewed requests exist.

---

### 3.3 CENCOM: Slot-Authority Metric Alignment & Performance Views

#### Mobile Implementation Baseline
- **Data Contract:**
  - Aggregates: `v_cencom_allocation_kpi`
  - Group Breakdown: `v_cencom_group_allocation_kpi`
  - Account Breakdown: `v_cencom_account_allocation_kpi`
  - Scope RPC: `fn_cencom_snapshot_scope`
  - Weekly Delta: `fn_cencom_weekly_delta`
  - Deployment Summary: `fn_cencom_deployment_summary`
- **Slot-Authority & Mathematical Coherence Formula:**
  - Raw Vacant count: `rawVacant = slot_vacant_hc ?? open_hc ?? vacant_count`
  - Mathematical Coherence Guard:
    $$\text{if } (\text{rawVacant} > 0 \land \text{actual} > 0 \land \text{rawRequired} > 0 \land \text{actual} \ge \text{rawRequired}) \implies \text{vacant} = 0, \text{required} = \text{actual}$$
  - MFR Calculation:
    $$\text{if } (\text{required} == 0) \implies \text{mfr} = 0.0$$
    $$\text{else if } (\text{vacant} == 0 \land \text{actual} \ge \text{required}) \implies \text{mfr} = 1.0 \ (100\%)$$
    $$\text{else} \implies \text{mfr} = \text{kpiRow.mfr}$$

#### Web Module Mapping
1. **CENCOM Web (`src/app/(dashboard)/cencom/page.tsx`):**
   - **Current State:** Scaffold stub rendering `<ModuleEmptyState href="/cencom" />`.
   - **Target Integration:**
     - Build `src/lib/queries/cencom.ts` fetching `v_cencom_allocation_kpi`, `v_cencom_group_allocation_kpi`, `v_cencom_account_allocation_kpi`, and `fn_cencom_deployment_summary`.
     - Implement top KPI metric cards (Active Plantilla, MFR %, Required HC, Vacant Slots, HR Pipeline, Projected MFR) applying the Slot-Authority alignment formula.
     - Implement Group Performance table with MFR progress bars, weekly delta trends, and store coverage metrics.

---

## 4. Step-by-Step Implementation Roadmap

```mermaid
flowchart TD
    subgraph Phase 1: Theme Hardening
        T1[Enforce colorScheme: light in layout.tsx] --> T2[Sanitize dark-mode references in globals.css]
    end

    subgraph Phase 2: Quota Revision
        Q1[Create quota RPC wrapper queries] --> Q2[Build ReviseQuotaModal & RequestHcModal]
        Q2 --> Q3[Wire into VacancyDetailDrawer ActionBar]
        Q2 --> Q4[Wire into Plantilla Store Staffing View]
    end

    subgraph Phase 3: Request Center Hub
        R1[Build RequestCenterBadgeService in web] --> R2[Build Approvals Hub layout with streamlined labels]
        R2 --> R3[Implement Headcount Amendment Approval Queue]
    end

    subgraph Phase 4: CENCOM Module
        C1[Implement cencom query contracts with Slot-Authority math] --> C2[Build CENCOM Page with KPI cards & Group Breakdown]
    end

    Phase 1 --> Phase 2
    Phase 2 --> Phase 3
    Phase 3 --> Phase 4
```

| Phase | Module | Target File(s) | Description |
|---|---|---|---|
| **Phase 1** | Global Theme | `src/app/layout.tsx`<br>`src/app/globals.css` | Enforce explicit `data-theme="light"` and `colorScheme="light"` on `<html>`. Clean up dark mode remnants. |
| **Phase 2** | Plantilla & Vacancy | `src/lib/queries/quota.ts`<br>`src/components/vacancy/VacancyDetailDrawer.tsx`<br>`src/components/plantilla/StoreStaffingDrawer.tsx` | Create RPC wrappers for `revise_vcode_headcount_quota` and `submit_headcount_amendment_request`. Add modals and wire into action bars. |
| **Phase 3** | Approvals & Requests | `src/app/(dashboard)/approvals/page.tsx`<br>`src/lib/queries/requests.ts`<br>`src/components/Sidebar.tsx` | Implement Request Center Hub with 8 streamlined labels, pending badges, and the Headcount Amendment approval queue. |
| **Phase 4** | CENCOM | `src/app/(dashboard)/cencom/page.tsx`<br>`src/lib/queries/cencom.ts` | Implement CENCOM overview, applying slot-authority mathematical coherence formula across KPI cards and group performance tables. |

---

## 5. Verification & Test Gate Plan

1. **Lint & Typecheck:**
   - Execute `npm run lint` and verify zero errors/warnings.
2. **Build Validation:**
   - Execute `npm run build` to confirm static export and App Router compile cleanliness.
3. **Task Completion Gate:**
   - Execute `powershell -ExecutionPolicy Bypass -File scripts/ai-finish.ps1` to run automated verification and staging gate checks.
