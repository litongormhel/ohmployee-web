# Dashboard Web State & Architecture

## 1. Scope

The Dashboard (`/dashboard`) is the landing module for all authenticated OHMployee Web users. It provides a cross-module operational overview sourced exclusively from backend RPCs. No data is mocked or computed in the web layer.

---

## 2. Backend Contracts

| RPC | Purpose |
|-----|---------|
| `fn_dashboard_metrics()` | Operational KPIs + security KPIs (role-gated) |
| `fn_dashboard_operational_analytics()` | Hiring pipeline and analytics metrics |

Both RPCs are `SECURITY DEFINER` and derive caller identity from `auth.uid()` only. No caller-controlled role or scope parameters are accepted.

---

## 3. Frontend Query Wrappers

`src/lib/queries/dashboard.ts` exports:

- `getDashboardMetrics()` — calls `fn_dashboard_metrics()`
- `getDashboardOperationalAnalytics()` — calls `fn_dashboard_operational_analytics()`
- `DashboardDataError` — error class with `access_denied` / `retryable` kind discriminator
- `DashboardMetrics` type
- `DashboardOperationalAnalytics` type

---

## 4. Page Structure (`/dashboard`)

`src/app/(dashboard)/dashboard/page.tsx` is a `"use client"` page with three sections:

### 4.1 Operational KPI Row (5 cards)

Sourced from `fn_dashboard_metrics()`:

| Card Label | Backend Field |
|-----------|--------------|
| Open Vacancies | `total_open_vacancies` |
| HR Emploc Pending | `total_hr_emploc_pending` |
| Active Plantilla | `total_active_plantilla` |
| Under-Staffed Stores | `understaffed_stores` |
| Active SLA Breaches | `active_sla_breaches` |

Uses `MetricCard` with `isLoading`, `isBlocked`, `isError` states from `DashboardDataError`.

### 4.2 Operational Analytics

Sourced from `fn_dashboard_operational_analytics()`:

| Stat Label | Backend Field | Notes |
|-----------|--------------|-------|
| Pipeline Total | `pipeline_total` | Active hiring pipeline |
| Hires This Month | `hires_this_month` | |
| Separations This Month | `separations_this_month` | |
| Avg Fill Rate | `avg_fill_rate` | Displayed as %; formula: Actual / (Actual + HR Pipeline + Vacancy) |

Renders as a horizontal stat row. `DataState kind="access_denied"` shown if blocked. `DataState kind="error"` with retry if retryable.

### 4.3 Security Dashboard KPIs (RBAC-gated)

Also sourced from `fn_dashboard_metrics()`. The backend gates these fields by caller role — non-admin roles receive `null` for:
- `pending_approvals`
- `security_event_count`

**Gating logic (frontend-side):**
- If both fields are `null` after a successful RPC call → `DataState kind="access_denied"` shown with a message that this section is admin-only.
- If at least one field is non-null → `MetricCard` rendered with the available values; individual null values use `isBlocked` on the card.
- No frontend role-key check is performed — the backend is the sole authority.

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
