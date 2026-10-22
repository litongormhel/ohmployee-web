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
Rendered in a responsive 5-column row where clicking any card activates the corresponding operational matrix drilldown tab below:
1. **`ACTIVE SLA BREACHES` (`37`):** Red top accent bar, `#DC2626` numeral, `"Action Required"` badge, sub-breakdown (`26 Vacancy SLA • 11 Movement SLA`). Clicking activates the *Active SLA Breaches* tab.
2. **`UNDER-STAFFED STORES` (`8`):** Amber top accent bar, `#D97706` numeral, `"At Risk"` badge, sub-label (`Stores below budgeted plantilla target`). Clicking activates the *Under-Staffed Stores* tab.
3. **`OPEN VACANCIES` (`13`):** Blue top accent bar, tabular numeral, sub-label (`Active open vacancy slots`). Clicking focuses the workforce matrix.
4. **`HR EMPLOC PENDING` (`4`):** Indigo top accent bar, tabular numeral, sub-label (`Onboarding compliance items pending`).
5. **`ACTIVE PLANTILLA` (`13`):** Emerald top accent bar, tabular numeral, sub-label (`Total active deployed employees`).

### 4.3 Main 2-Column Asymmetric Command Workspace (12-Column Desktop Grid)
- **Left Column (8 Cols):**
  - **Card A: Operational Analytics & Fill Rate Breakdown (`fn_dashboard_operational_analytics`):**
    - Top visual segmented coverage bar for **`AVG FILL RATE (43.3%)`** with formula breakdown: `Actual [13] / (Actual [13] + HR Pipeline [4] + Vacancy [13] = 30 Required)`.
    - Proportional 3-segment progress bar: `Active Plantilla` (Emerald), `HR Emploc Pending` (Blue), `Open Vacancies` (Rose/Amber).
    - 4-column metric strip: `Pipeline Total` (14), `Hires This Month` (8), `Separations This Month` (0 with green "0% Attrition" pill), and `Avg Fill Rate` (43.3%).
  - **Card B: Cross-Module Operational Matrix (Tabbed Bottom Viewport):**
    - **Tab 1: `Group Workforce Matrix`** — Sourced live from `v_cencom_group_allocation_kpi` via `useCencomGroupKpi()`, displaying actual plantilla, open vacancies, pipeline, and fill rate % across database groups (`Group 1`–`Group 5`, `Moses HQ`) with an active groups filter toggle. Zero mock fallbacks.
    - **Tab 2: `Active SLA Breaches`** — Sourced live via `useDashboardSlaBreaches()`, showing Store/Unit, Breach Category, Aging, Assigned Owner, and Inspect action. Renders loading skeletons and clean empty state when zero breaches exist.
    - **Tab 3: `Under-Staffed Stores`** — Sourced live via `useDashboardUnderstaffedStores()`, aggregating store vacancies with assigned HRCO and vacancy counts. Renders loading skeletons and clean empty states.
- **Right Column (4 Cols — Tightened 12px Vertical Rhythm for 1080p Viewport Clearance):**
  - **Card C: Reconciled Pending Approvals Queue:**
    - Binds dynamically to `useRequestCategoryCounts()`, showing live non-zero pending categories (`Plantilla Deployments & Movements`, `HR Emploc Compliance & Deletions`, `Store Headcount & Requisitions`, `Coverage & Reliever Approvals`, `Vacancy Closures`) with direct links to `/approvals?tab=<category>`. Displays green "All approvals cleared" badge when zero.
  - **Card D: Super Admin Governance & MIKA Sync Card (Strictly `Super Admin` Only):**
    - Hidden completely for `Head Admin`.
    - Displays MIKA sync health, dynamic anomaly alerts derived from live `metrics.ghostEmployeeCount`, and an inline **`"Sync MIKA"`** button and anomaly resolution link.
  - **Card E: Compact Security & Audit Telemetry (`fn_dashboard_metrics`):**
    - High-density compact card showing `Admin Security Approvals` (sourced from `admin_security_approvals`), `Security Events Today` (0), caller role scope badge, and audit log link. Fits 100% above the fold without clipping on 1080p and 900p displays with `pb-8` bottom container clearance.

### 4.4 MIKA Sync Modal (`src/components/dashboard/MikaSyncModal.tsx`)
- Drag-and-drop file target (`.xlsx`, `.csv`) for MIKA masterfile upload.
- Strictly labeled **`"Sync MIKA"`** action button (never `"Refresh"`).
- Automatically triggers React Query refetch for operational metrics and analytics upon completion.

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
