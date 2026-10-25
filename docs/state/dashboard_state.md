# Dashboard Web State & Architecture

## 1. Scope

The Dashboard (`/dashboard`) is the cross-module operational overview for authenticated OHMployee Web users (with Vacancy `/vacancy` serving as the primary operational landing workspace). It provides an overview sourced exclusively from backend RPCs. No data is mocked or computed in the web layer.

---

## 2. Backend Contracts

| RPC | Purpose |
|-----|---------|
| `fn_dashboard_metrics()` | Operational KPIs (active plantilla, open vacancies, unassigned/assigned vacancies, understaffed stores, active SLA breaches, ghost employee anomalies, 11-queue operational pending approvals) + role-gated admin security approvals |
| `fn_dashboard_operational_analytics()` | Hiring pipeline and analytics metrics (actual deployed plantilla, HR pipeline count, open vacancies, required headcount, average fill rate %, hires/separations) |

Both RPCs are `SECURITY DEFINER` and derive caller identity from `auth.uid()` only. No caller-controlled role or scope parameters are accepted.

---

## 3. Frontend Query Wrappers

`src/lib/queries/dashboard.ts` exports:

- `getDashboardMetrics()` — calls `fn_dashboard_metrics()` (normalizes operational metrics + security escalations + ghost employee count)
- `getDashboardOperationalAnalytics()` — calls `fn_dashboard_operational_analytics()`
- `useDashboardSlaBreaches()` — queries live vacancies with SLA breach markers
- `useDashboardUnderstaffedStores()` — aggregates live open vacancies per store to identify stores with headcount shortages
- `DashboardDataError` — error class with `access_denied` / `retryable` kind discriminator
- `DashboardMetrics` type
- `DashboardOperationalAnalytics` type

---

## 4. Page Structure (`/dashboard`)

`src/app/(dashboard)/dashboard/page.tsx` is an interactive `"use client"` executive command center with four unified components:

### 4.1 Top Command Header Bar
- **Left:** Breadcrumb (`ADMIN PANEL` → `Dashboard Overview`), title (`Web Admin Command Center`), subtitle, and subtle `Live RPC Telemetry Connected` status badge.
- **Right Actions:**
  - Group Scope Selector dynamically populated across all organizational groups (`All Retail Groups`, `Group 1`, `Group 2`, `Group 3`, `Group 4`, `Group 5`, `Moses HQ`).
  - Quick link button to `CENCOM Triage` when `activeSlaBreaches > 0`.
  - **`"Sync MIKA"`** primary action button (role-gated: visible to `Super Admin` only; hidden for `Head Admin`).

### 4.2 Top 5 Executive KPI Ribbon (Interactive 5-Column Grid)
Rendered in a responsive 5-column row consuming shared `KpiCard` (`@/components/shared/KpiCard`) with `AnimatedNumber` and `NeutralChip`. Counts are strictly neutral (`text-text-primary`); clicking any card activates the corresponding operational matrix drilldown tab below:
1. **`ACTIVE SLA BREACHES`:** Neutral count (`text-text-primary`), `"Action Required"` neutral badge, sub-label (`Pending movements or vacancy SLA breaches`). Clicking activates the *Active SLA Breaches* tab.
2. **`UNDER-STAFFED STORES`:** Neutral count, `"At Risk"` neutral badge, sub-label (`Stores below budgeted plantilla target`). Clicking activates the *Under-Staffed Stores* tab.
3. **`OPEN VACANCIES`:** Neutral count with `Briefcase` icon, `"X Unassigned"` neutral badge, sub-label (`Active open vacancy slots`). Clicking focuses the workforce matrix.
4. **`HR EMPLOC PENDING`:** Neutral count with `FileCheck2` icon, `"In Motion"` neutral badge, sub-label (`Onboarding compliance items pending`).
5. **`ACTIVE PLANTILLA`:** Neutral count with `Users` icon, `"of X Target"` neutral badge, sub-label (`Total active deployed employees`).

### 4.3 Main 2-Column Asymmetric Command Workspace (12-Column Desktop Grid)
- **Left Column (8 Cols):**
  - **Card A: Operational Analytics & Fill Rate Breakdown (`fn_dashboard_operational_analytics`):**
    - Formula breakdown badge evaluated via `evaluatePercentage("fill_rate", avgFillRatePct)` with `--pct-good-*`, `--pct-warn-*`, or `--pct-bad-*` semantic tokens.
    - Proportional 3-segment progress bar with brand-aligned tokens: `Active Plantilla` (`bg-brand-500`), `HR Emploc Pending` (`bg-brand-600`), `Open Vacancies` (`bg-border-strong`).
    - 4-column metric strip: `Pipeline Total` (`AnimatedNumber`), `Hires This Month` (`NeutralChip`), `Separations This Month` (`NeutralChip`), and `Avg Fill Rate` carrying semantic percentage color.
  - **Card B: Cross-Module Operational Matrix (Tabbed Bottom Viewport):**
    - Navigated via shared `SegmentedTabs` (`@/components/shared/SegmentedTabs`) with sliding pill indicator.
    - **Tab 1: `Group Workforce Matrix`** — Sourced live from `v_cencom_group_allocation_kpi` via `useCencomGroupKpi()`, displaying actual plantilla, open vacancies, pipeline, and fill rate % using shared `PercentageBar` (`scale="fill_rate"`). Strict $\ge 14\text{px}$ text floor (`text-sm`) with compact density padding (`py-2.5 px-3` / `px-4`). SLA status rendered via `NeutralChip`.
    - **Tab 2: `Active SLA Breaches`** — Sourced live via `useDashboardSlaBreaches()`, showing Store/Unit, Category (`NeutralChip`), Aging, Assigned Owner, and Inspect action. Renders loading skeletons and clean empty state when zero breaches exist.
    - **Tab 3: `Under-Staffed Stores`** — Sourced live via `useDashboardUnderstaffedStores()`, aggregating store vacancies with assigned HRCO and neutral vacancy counts. Renders loading skeletons and clean empty states.
- **Right Column (4 Cols):**
  - **Card C: Reconciled Pending Approvals Queue:**
    - Binds dynamically to `useRequestCategoryCounts()`, showing live non-zero pending categories with direct links to `/approvals?tab=<category>`. Standardized to semantic tokens with neutral counts.
  - **Card D: Super Admin Governance & MIKA Sync Card (Strictly `Super Admin` Only):**
    - Hidden completely for `Head Admin`.
    - Displays MIKA sync health, dynamic anomaly alerts derived from live `metrics.ghostEmployeeCount`, and an inline **`"Sync MIKA"`** button and anomaly resolution link.
  - **Card E: Compact Security & Audit Telemetry (`fn_dashboard_metrics`):**
    - High-density compact card showing `Admin Security Approvals` (`AnimatedNumber`), `Security Events Today` (`AnimatedNumber`), caller role scope badge, and audit log link.

### 4.4 MIKA Sync Modal (`src/components/dashboard/MikaSyncModal.tsx`)
- Sourced from shared `Modal` (`@/components/shared/Modal`).
- Drag-and-drop file target (`.xlsx`, `.csv`) for MIKA masterfile upload with full keyboard and backdrop support.
- Strictly labeled **`"Sync MIKA"`** action button (never `"Refresh"`).
- Automatically triggers React Query refetch for operational metrics and analytics upon completion.
- Zero color literals.

### 4.5 MIKA Attendance & Biometric Import Modal (`src/components/more/MikaImportModal.tsx`)
- Accessible via More Dashboard -> Data Control & Batch Ingestion (`import_mika`).
- **Template Schema (14 Columns, "Store Name" Dropped)**:
  1. `Employee No.` (Required)
  2. `Fullname` (Required)
  3. `Account` (Required)
  4. `Position`
  5. `Birth Date`
  6. `Civil Status`
  7. `Address`
  8. `Contact No.`
  9. `Date Hired`
  10. `SSS`
  11. `PhilHealth`
  12. `Pag-IBIG`
  13. `TIN`
  14. `ATM No.`
- **Ingestion & Validation**:
  - Automatically maps 14 headers and ignores/skips `Store Name` without throwing errors on legacy files.
  - Cross-checks employee numbers against active Plantilla slots to isolate potential ghost employees and account mismatches.
- **Review Queue**:
  - Displays pending batches for Super Admin / Head Admin review.
  - Provides **Approve** and **Reject** action buttons calling `approveMikaImport` and `rejectMikaImport` respectively.
- **Import History**:
  - Displays actioned logs with status-aware color coding: `"Rejected"` status rendered in red (`bg-rose-100 text-rose-800 border border-rose-200`), `"Approved"` status rendered in green (`bg-emerald-100 text-emerald-800`).

---

## 5. Error Handling

`DashboardDataError` maps:
- PostgreSQL `42501` / "permission denied" / "not authorized" / "rls" → `access_denied`
- All other errors → `retryable`

`access_denied` renders a lock shield via `DataState kind="access_denied"`. `retryable` renders a warning card with a retry callback via `DataState kind="error"`.

---

## 6. Guardrails

- The dashboard page calls only the two approved RPCs. No raw table queries, no fallback values, no CRUD mutations.
- All filter parameters (if any) are blank on this page — the RPCs use `auth.uid()` scoping server-side.
- React Query keys: `["dashboard", "metrics"]` and `["dashboard", "operational-analytics"]`.
- No cache invalidation is wired from mutations (dashboard is read-only).

---

## 7. Remaining Gaps

- `fn_dashboard_metrics()` and `fn_dashboard_operational_analytics()` backend implementations must be deployed remotely.
- Exact return field names may differ from normalizer assumptions once backend migration is applied; normalizer falls back gracefully (returns `0` for missing counts, `null` for missing nullable fields).
- Dashboard mutations (if any future requirement) are out of scope until backend action RPCs are defined.
