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

### 4.1.5 Dashboard Announcements Banner Strip & Urgent Acknowledgements
- **Placement:** Dedicated prominent card strip placed directly below the header bar and above the 4 KPI cards.
- **Components:**
  - `AnnouncementBannerStrip` (`src/components/dashboard/AnnouncementBannerStrip.tsx`): Displays active, non-expired announcements sorted with pinned items first. Features color-coded priority styling (`urgent`: red border/badge with AlertOctagon icon, `important`: amber border/badge with AlertTriangle icon, `info`: blue border/badge with Megaphone icon).
  - `CreateAnnouncementModal` (`src/components/dashboard/CreateAnnouncementModal.tsx`): Restricted to Super Admin & Head Admin via "+ New Announcement" button. Allows setting title, body, priority, pinned status, role targeting, and optional expiry date.
  - `UrgentAnnouncementModal` (`src/components/dashboard/UrgentAnnouncementModal.tsx`): Mandatory one-time acknowledgement modal for any active `urgent` announcements not yet acknowledged by the user (tracked in `public.announcement_acknowledgements`).
- **Database & Permissions Architecture (`20262606000180_fix_announcements_grants_and_creator_resolution.sql`)**:
  - **Explicit PostgREST Table Grants**: Explicitly granted `ALL` on `public.announcements` and `public.announcement_acknowledgements` to `authenticated` and `service_role`, plus `SELECT` on `announcements` to `anon`, resolving PostgREST error `42501: permission denied for table announcements`.
  - **Auto-Resolve Creator Trigger (`fn_announcements_resolve_creator`)**: Automatically resolves `created_by` from `public.users_profile` via `auth.uid()` (with fallback to Super Admin) if omitted or null, preventing FK / NOT NULL exceptions on client payload variations.
  - **Dedicated RPC & Direct Mutation Parity (`public.create_announcement`)**: High-reliability `SECURITY DEFINER` RPC validating `i_have_full_access()`, resolving caller profile ID, and creating the announcement row with atomic return. `createAnnouncement` client query executes RPC first with graceful fallback to direct PostgREST insert.
  - **Physical Column Contract (`users_profile.role`)**: Fixed PostgREST schema mismatch in `fetchActiveAnnouncements` (`author:users_profile!created_by(full_name, role)`), replacing nonexistent `role_name` with physical table column `role`.
- **Live Realtime:** Subscribes to Supabase Realtime channel `realtime:announcements` to reactively update the feed upon new posts or updates without full page reloads.
- **Push Notification Fanout:** Backed by database trigger `public.trg_announcement_notify()` which safely fans out notification items to `public.notifications` for all targeted roles, automatically dispatching In-App and Mobile Push Notifications. Notification dispatch is isolated inside exception-safe blocks so background fan-out warnings never abort announcement creation.

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
- **Individual 1-by-1 Event Stream**: Operations affecting multiple employees or vacancies (e.g. bulk transfer to Plantilla or batch status updates) render as individual 1-by-1 operational activities per employee/record. Grouping into aggregated batches and expandable "sample subjects" disclosures are removed per operational specification.
- User Management approvals (Option A integration): `fn_get_recent_activity` unifies approved `public.account_requests` into the feed for Data Team roles (Encoder, Head Admin, Super Admin), exposing only `full_name` and the assigned `role_name` within a 30-day window. Null approvers render as `System:`. These events originate directly from `public.account_requests` and do NOT appear in the Audit Logs viewer (`/more?tab=audit_logs`). Non-Data Team roles (OM, HRCO, Recruitment, HR Personnel, Back Office) receive 0 User Management rows.
- Over-capacity vacancies: 12 vacancies in Groups 1 and 2 (created Oct 23 to 27) are classified as over-capacity vacancies because existing actual headcount already equals or exceeds required capacity (`actual >= required`), causing `normalizeSlotAuthorityMetrics` to clamp vacant slots to 0.
- Subject-first formatting (`src/lib/utils/activity_formatter.tsx`):
  - Every event is rendered as an individual, subject-first sentence: `"<Actor>: <Subject> [<no>] transferred to Plantilla [<account>]"`, `"<Actor>: updated status for <Subject> to <Status> [<account>]"`, `"<Actor>: marked separation for <Subject> [<account>]"`, `"<Actor>: opened vacancy for <Position> at <Store> [<account>]"`.
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

---

## 8. Plantilla Source of Truth & Percentage Alignment (`ohm#d2c8m9p4` — 2026-11-14)
- **Dashboard Fill Rate Percentage Normalized**:
  - Eliminated the double `* 100` multiplication on `avgFillRate` (where backend RPC already returns percentage e.g. `93.5`).
  - Derived Card 1 (`Workforce Coverage`) fill rate directly from `(totalActivePlantilla / totalScopedDemand) * 100`, guaranteeing 100% mathematical cohesion with the subtitle `${totalActivePlantilla} of ${totalScopedDemand} seats filled` and the segmented progress bar.
- **Plantilla as Authoritative Source of Truth**:
  - In `src/lib/queries/cencom.ts`, `fetchCencomGroupAllocationKpi` and `fetchCencomAllocationKpi` query `plantilla` (active headcount) and `plantilla_slots` (non-closed slots), mapped by account to CENCOM group.
  - The Dashboard Group Matrix (`displayedGroupRows`), which derives from `useCencomGroupKpi()`, automatically reflects these authoritative Plantilla-derived figures.

---

## 9. Ecosystem Dashboard View Parity & Cascade Recovery (`ohm#fix-migration-127-dashboard-views` — 2026-11-20)
- **Context**: When migration `20262606000096` executed `DROP VIEW IF EXISTS public.v_plantilla_safe CASCADE;`, PostgreSQL automatically cascaded the drop to all dependent views (`v_dashboard_account_breakdown`, `v_dashboard_account_mfr_breakdown`, and `v_dashboard_hrco_breakdown`).
- **Remediation**: In `supabase/migrations/20262606000127_security_hardening_rls_rpcs_views.sql`, Section 4 now explicitly recreates all 3 dashboard views `WITH (security_invoker = true)` before altering view parameters. This permanently prevents relation missing errors (`SQLSTATE 42P01`) on remote production deployments and guarantees full mobile/web operational telemetry continuity.
