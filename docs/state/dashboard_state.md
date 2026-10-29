# Dashboard Web State & Architecture

## 1. Scope

The Dashboard (`/dashboard`) is the cross-module operational overview for authenticated OHMployee Web users (with Vacancy `/vacancy` serving as the primary operational landing workspace). It provides an overview sourced exclusively from backend RPCs. No data is mocked or computed in the web layer.

---

## 2. Backend Contracts

| RPC | Purpose |
|-----|---------|
| `fn_dashboard_metrics()` | Operational KPIs (active plantilla, open vacancies, unassigned/assigned vacancies, understaffed stores, active SLA breaches, ghost employee anomalies, 11-queue operational pending approvals) + role-gated admin security approvals |
| `fn_dashboard_operational_analytics()` | Hiring pipeline and analytics metrics (actual deployed plantilla, HR pipeline count, open vacancies, required headcount, average fill rate %, hires/separations) |
| `fn_get_recent_activity(p_group_id, p_account_id, p_limit)` | Scoped, role-gated audit feed (Plantilla, Vacancies, HR Emploc, User Approvals) enforcing caller scope and canonical module access (`get_web_current_user_context`). Deduplicates same-transaction/same-entity events (priority: Plantilla deployment > Separation/Deactivation > Vacancy filled > HR Emploc Complete > Status change). Batches events occurring within a 5-minute window (`date_bin`) with same actor, event_type, and account into ONE row with `batch_count` and up to 3 `samples` (name + employee_no). Non-admin callers without `user_scopes` fail closed. Pre-limit 30-day index scan via `idx_audit_logs_timestamp_desc` and `idx_audit_logs_account_ts`. Approvals visible to Data Team + Encoder; role updates & archives visible to SA/HA only. |

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

`src/lib/queries/activity.ts` exports:
- `useRecentActivity({ groupId, accountId, limit })` — calls `fn_get_recent_activity` with 60-second `staleTime` and reactive scope filtering
- `RecentActivityItem` type

---

## 4. Page Structure (`/dashboard`)

`src/app/(dashboard)/dashboard/page.tsx` is an interactive `"use client"` executive command center with modern, streamlined components:

### 4.1 Top Command Header Bar
- **Left:** Breadcrumb (`ADMIN PANEL` → `Dashboard Overview`), title (`Command Center`), subtitle (`Cross-module operational overview for the OHMployee admin workspace`). Removed legacy `Live RPC Telemetry Connected` status badge.
- **Right Actions:**
  - Group Scope Selector (`ScopeDropdown`) dynamically populated across all organizational groups (`All Retail Groups`, `Group 1`, `Group 2`, `Group 3`, `Group 4`, `Group 5`, `MOSES HQ`).
  - Header triage and sync triggers removed: `CENCOM Triage` and `"Sync MIKA"` buttons removed from the header.

### 4.2 Top Executive KPI Grid (4 Responsive Module Cards)
Rendered in a 4-column responsive grid consuming shared `KpiCard` (`@/components/shared/KpiCard`) with direct routing links to primary modules:
1. **`Workforce Coverage`:** Fill rate % (`avgFillRatePct.toFixed(1)}%`), `"X of Y seats filled"` subtitle, prominent 10px (~8px inner) segmented 3-color progress bar (Active Plantilla, HR Emploc Pending, Open Vacancies) with legends, and `"Above 80% target"` / `"Below 80% target"` status pill. Clickable; routes to `/plantilla`.
2. **`Open Vacancies`:** Total open vacancy count, `"N unassigned to HRCO"` neutral badge (shown once), and footer direct link to Vacancy Hub. Clickable; routes to `/vacancy`.
3. **`Hiring Pipeline`:** Total pipeline count, `"Active Funnel"` badge, subtitle (`N HR Emploc · N applicants`), and monthly momentum footer (`This month: +hired · −separated`). Clickable; routes to `/hr-emploc`.
4. **`SLA Breaches`:** Total active breach count, `"Action required"` badge, subtitle (`Pending movements or vacancy SLA breaches`). Footer links and aging lines removed. Clickable; routes to `/cencom`.

### 4.3 Main 2-Column Asymmetric Command Workspace (12-Column Desktop Grid)
- **Left Column (8 Cols) — "Where is the gap?" Operational Card:**
  - Navigated via shared `SegmentedTabs` (`@/components/shared/SegmentedTabs`) with 3 tabs:
    - **Tab 1: `Group matrix` (Group Workforce Matrix):** Always displays **Group 1 to Group 5 by default, with MOSES HQ pinned below Group 5**. Groups with no active data display `—` (never hidden). MOSES HQ displays real values (2 active plantilla, 2 HR Emploc pending) derived from the global-to-CENCOM delta without modifying views or `cencom_scope`. Fill rate is `—` and SLA status is `Standby` (never "Critical"). Rows in `Critical` status receive a red row highlight (`bg-red-500/10 border-l-4 border-l-red-500`).
    - **Tab 2: `SLA breaches` (Active SLA Breaches):** Sourced live via `useDashboardSlaBreaches()`, showing Store/Unit, Category (`NeutralChip`), Scope owner, Aging, and Action link.
    - **Tab 3: `Under-staffed stores` (Under-Staffed Stores):** Sourced live via `useDashboardUnderstaffedStores()`, aggregating store vacancies with assigned HRCO and neutral vacancy counts.
- **Right Column (4 Cols) — "Needs your attention" Alert List:**
  - Compact card replacing legacy Card C and Card D. Displays 4 compact operational rows with direct actions:
    1. Critical group(s) alert (view matrix).
    2. Reconciled Pending approvals count with explicit spacing (`Includes N coverage & reliever count`), synced with the sidebar Approvals badge from `useRequestCategoryCounts()`.
    3. Under-staffed stores alert (inspect stores).
    4. Ghost employee records alert with `"Resolve Anomalies →"` linking to `/plantilla` (MIKA/Plantilla reconciliation; no sync trigger on Dashboard).

### 4.4 Full-Width Recent Activity Feed (`src/components/dashboard/RecentActivityFeed.tsx`)
- Full-width operational audit section mounted directly below the 12-column command workspace and above the telemetry footer.
- Max 8 entries (`limit: 8`), one compact line per entry with right-aligned relative timestamps (`timeAgo`).
- Collapse bulk multi-item events using fixed 5-minute clock-aligned `date_bin` buckets (`date_bin(interval '5 minutes', timestamp, timestamptz '2000-01-01 00:00:00Z')`, not a sliding window) by the same actor, event_type, and account into a single row (`batchCount`). Events crossing a 5-minute clock boundary (e.g. 12:04:59 and 12:05:01) fall into distinct buckets and produce separate batches rather than merging.
- Subject-first formatting (`src/lib/utils/activity_formatter.tsx`):
  - Single: `"<Actor>: <Subject> [<no>] transferred to Plantilla [<account>]"`
  - Batched: `"<Actor>: transferred N employees to Plantilla [<account>]"` with an expandable sample list disclosure button.
- Reactively scoped to `selectedGroupScope` (`p_group_id` for retail groups, `p_account_id` for Moses HQ).
- Footer `"View all →"` link to the Audit Logs modal gated strictly to Super Admin.

### 4.5 Security & Audit Telemetry Footer
- Replaced standalone Card E with a single high-contrast footer line:
  `"System healthy · N access events today · Audit logs →"` linking to `/more?tab=audit_logs` and consuming `metrics?.securityEventCount`.

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

- The dashboard page calls only the two approved RPCs plus live SLA breach / understaffed stores queries. All telemetry adheres to `COALESCE(is_archived, FALSE) = FALSE AND suppressed_by_batch_id IS NULL`.
- All filter parameters (if any) are blank on this page — the RPCs use `auth.uid()` scoping server-side.
- React Query keys: `["dashboard", "metrics"]` and `["dashboard", "operational-analytics"]`.
- Cache invalidation is wired from `useExecuteBulkArchive` and `useRollbackArchiveBatch` to immediately reflect zeroed state on QA Reset and full restoration on Rollback.

---

## 7. Archival & QA Reset Governance
- `fn_dashboard_metrics` filters `sla_breach_logs`, `possible_ghost_employees`, `hr_emploc`, `vacancies`, and all 11 request queues by `COALESCE(is_archived, FALSE) = FALSE AND suppressed_by_batch_id IS NULL` (preserving Account Sign-Ups).
- `fn_dashboard_operational_analytics` filters applicants, hr_emploc, and separation logs by `COALESCE(is_archived, FALSE) = FALSE AND suppressed_by_batch_id IS NULL`.
- All metrics correctly drop to 0 post QA Reset and restore atomically upon 72-hour batch rollback.
