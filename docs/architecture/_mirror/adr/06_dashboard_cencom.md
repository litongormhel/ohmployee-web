<!--
ADR-MIRROR: DO NOT EDIT. Read-only copy of ADR-Dashboard-CENCOM. Edit in mobile repo, then run `npm run sync:adr`.
source: OHMployee/docs/architecture/adr/06_dashboard_cencom.md
source_commit: 0eb4407 2026-11-23T23:02:59+08:00
source_sha256: 30a31270a93dcd6b2a21a5330501ad8d9306d9accc3e8b5ab7ddde5e927faa1a
synced_at: 2026-11-27T08:16:11.240Z
-->
# Executive Dashboard & CENCOM Technical Architecture

- **Status:** ACCEPTED & LOCKED
- **Scope:** Executive Dashboard Command Center (/dashboard), CENCOM Central Command (/cencom), Authoritative Database Pass-Through Principle ("Database Computes, UI Renders"), MFR Health Threshold Scale, and Whole-Number Headcount KPI Rounding Contract.

---

## Dashboard & CENCOM

### Rule 4 compliance

**SHIPPED (`ohm#2q7x5m9j`, commit `c597b5c`; formula extended `ohm#w8r4n2yj`, 2026-08-04).** Shared `VacancyItem.remainingOpenCount` getter (`derivedOpenCount - displayPipelineCount - hrProcessingCount`, floored at 0) in `models.dart`. Dashboard's `openVacRowCount`/`agingList` row-count fallback and CENCOM's `_mapOperationalVacancies` aging-bucket/Target-Deployment membership filter both now gate on this formula, matching Vacancy's Rule 4 tab logic.

**Still non-compliant:** each module's *primary/headline* Open/Vacant KPI (Dashboard's `openVacCount` via `slotOpenVacCount`; CENCOM's `mfrVacant`/`_totalVacant`) is sourced from `slot_vacant_hc` (`v_account_allocation_kpi`/`v_cencom_allocation_kpi`) — a structurally different, `slot_status`-based formula (counts `slot_status IN ('open','pipeline')` as vacant) that is explicitly LOCKED (see `docs/state/cencom_state.md`, "Locked KPI Formulas OHM2026_0067/0073" — must not be changed without a new prompt decision). The `hr_processing_count` fix (`ohm#w8r4n2yj`) does NOT close this gap: `slot_vacant_hc` still counts pipeline slots as vacant capacity while Rule 4's `remainingOpenCount` subtracts pipeline, so the two formulas diverge whenever pipeline > 0 (they only coincide in the pipeline=0 case). Closing this fully still requires a backend migration and a deliberate decision to reopen that lock — a separate, dedicated prompt, not a Flutter-only change. Do not assume Dashboard/CENCOM's headline figures match the Vacancy screen's Open tab count until that follow-up ships.

### Rule 5 compliance

**Dashboard: COMPLETE, 6 of 6 sites (`ohm#d4w7k2ml`, 2026-08-05, extends `ohm#c8x1r6np`, 2026-08-04, extends `ohm#b6k9m4hp`, 2026-08-04, extends `ohm#a5t3g8ny`, 2026-08-04, extends `ohm#d7m2q8vx`, 2026-08-04).** All 6 confirmed client-side sort sites in `dashboard_screen.dart` are now fixed: the group-ops-summary site (`_buildOperationsGroups`) — new wrapper view `v_dashboard_group_allocation_kpi` (migration `20262606000027`, security_invoker over the unmodified `v_cencom_group_allocation_kpi`) enforces `ORDER BY mfr ASC, slot_vacant_hc DESC, group_name ASC` in-DB; `accountBreakdown` — new view `v_dashboard_account_breakdown` (migration `20262606000028`, security_invoker `GROUP BY account` aggregate over `v_plantilla_safe`) enforces `ORDER BY active DESC` in-DB; `agingList` — new view `v_dashboard_aging_vacancies` (migration `20262606000029`, security_invoker over `vw_slot_derived_vacancy_shadow`, gated on the full Rule 4 formula, reusing the base view's `aging_days` column) enforces `ORDER BY days_open DESC` in-DB; and `omStoreAging` — new view `v_dashboard_store_aging` (migration `20262606000030`, security_invoker `GROUP BY account_name` aggregate over `vw_slot_derived_vacancy_shadow`, `MAX(aging_days)` per store, same Rule-4-consistent open formula as `agingList` but without its `>= 30`-day floor) enforces `ORDER BY days_open DESC` in-DB — also a correctness fix, since the prior client-side loop read fields (`status`, `account`, `vacant_date`) absent from its source query's select and always returned empty. **Final 2 sites closed `ohm#d4w7k2ml`, 2026-08-05:** `accountMfrBreakdown` — new view `v_dashboard_account_mfr_breakdown` (migration `20262606000032`, security_invoker 3-way aggregate of `v_plantilla_safe`/`hr_emploc`/`vw_slot_derived_vacancy_shadow` grouped by `account`, vacancy component gated on the same Rule 4 formula) enforces `ORDER BY mfr ASC` in-DB; `omHrcoBreakdown` — new view `v_dashboard_hrco_breakdown` (migration `20262606000033`, same 3-way aggregate shape grouped by `hrco_name`, blank/null vacancy-source `hrco_name` bucketed to `'Unassigned'`) enforces `ORDER BY name ASC` with `'Unassigned'` pinned last in-DB — also a correctness fix, confirmed independently: both sites' vacancy component read `v['status']`/`v['account']`, neither of which exist in `vacQ`'s select, so it was always 0. Full detail: `docs/state/dashboard_state.md`.

**CENCOM: DRIFTED, not yet fixed.** CENCOM has 8+ client-side sort call sites, still sorting in Dart rather than relying on an in-DB `ORDER BY` view.

**Shared-view note:** `v_cencom_group_allocation_kpi` is now consumed by both modules with two different DB-enforced orders (CENCOM: `group_code ASC`; Dashboard via `v_dashboard_group_allocation_kpi`: `mfr ASC, slot_vacant_hc DESC, group_name ASC`). Any future change to the base view must be regression-checked against both.

### Known gap

`slotOpenVacCount`/`mfrVacant` headline KPIs still read the separately-locked `slot_vacant_hc` view, NOT the Rule 4 formula — requires a deliberate backend decision, out of scope until explicitly reopened.

### Executive Dashboard Command Center Architecture (/dashboard)

**Status: ACCEPTED.** Codifies the primary operational overview surface for executive leadership and managers:

1. **Top Four Executive KPI Cards**:
   - **Workforce Coverage**: Displays organizational average fill rate % (`avgFillRatePct`), seats filled subtitle (`X of Y seats filled`), and a prominent 3-color segmented progress bar (Active Plantilla, HR Emploc Pending, Open Vacancies) with target indicators (`Above 80% target` / `Below 80% target`). Routes to `/plantilla`.
   - **Open Vacancies**: Total active open vacancy slots, neutral unassigned count (`N unassigned to HRCO`), and direct navigation link. Routes to `/vacancy`.
   - **Hiring Pipeline**: Total pipeline candidate volume, active funnel badge, and monthly momentum indicator (`This month: +hired · −separated`). Routes to `/hr-emploc`.
   - **SLA Breaches**: Total active SLA breach count across vacancies and operational requests with action required pill. Routes to `/cencom`.
2. **Dashboard Announcement Banner Strip & Mandatory Urgent Acknowledgements**:
   - Displays active, non-expired announcements sorted with pinned items first, styled by priority (`urgent`: red alert, `important`: amber warning, `info`: blue notice).
   - **Mandatory Urgent Acknowledgement (`UrgentAnnouncementModal`)**: Blocks normal dashboard interaction until unacknowledged `urgent` items are formally acknowledged by the user (`public.announcement_acknowledgements`).
   - Subscribes to Supabase Realtime channel `realtime:announcements` and fans out in-app and mobile push notifications via database trigger `trg_announcement_notify()`.
3. **Asymmetric 2-Column Command Workspace**:
   - **Left Column (8 cols) — "Where is the gap?"**:
     - *Tab 1: Group Matrix*: Displays Group 1 to Group 5 by default with **MOSES HQ pinned below Group 5** (displaying real active headcount from global-to-CENCOM delta with `Standby` status). Rows in critical health receive high-visibility red highlights.
     - *Tab 2: SLA Breaches*: Live breach items with store branch, category, scope owner, aging, and action link.
     - *Tab 3: Under-staffed Stores*: Stores with urgent headcount deficits requiring immediate recruiter allocation.
   - **Right Column (4 cols) — "Needs your attention"**: Compact operational alert cards prioritizing critical groups, reconciled pending approvals count, under-staffed stores, and ghost employee anomalies linking to resolution centers.
4. **Recent Activity Feed (`public.fn_get_recent_activity`)**:
   - Chronological audit stream rendered as individual 1-by-1 subject-first sentences (`"<Actor>: <Subject> [<no>] transferred to Plantilla [<account>]"`).
   - Automatically deduplicates same-transaction mutations and scopes events to the caller's assigned organization or account.

### CENCOM Central Command Technical Architecture (/cencom)

**Status: ACCEPTED.** Codifies workforce fulfillment tracking, vacancy aging, and placement velocity:

1. **Five Standard Operational Tabs**:
   - **Tab 1: Overview** (`overview`): Hero Overall MFR sweep ring gauge, neutral KPI metrics (Total required, Total actual, Open vacancies, Deployed stores), and monthly deployment summaries.
   - **Tab 2: Groups** (`groups`): Granular group performance table with search, health filtering, store counts, and `PercentageBar` MFR progress indicators.
   - **Tab 3: Target Deployment** (`target_deployment`): Six standardized vacancy aging brackets (**1–15d, 16–30d, 31–60d, 61–120d, >121d, Advance**), province aging breakdowns, and store outlet drilldowns.
   - **Tab 4: Deployments** (`deployments`): Chronological candidate placement records and onboarding velocity.
   - **Tab 5: Quick Reports** (`reports`): 18 standard analytical workforce reports using semantic card surfaces.
2. **Standardized MFR Health Scale & Thresholds**:
   - **Healthy ($\ge 100\%$)**: Green status pill. Full capacity achieved.
   - **At Risk ($95\% - 99.99\%$)**: Amber status pill. Mild operational deficit requiring recruiter attention.
   - **Critical ($< 95\%$)**: Red alert pill. Urgent operational staffing deficit triggering managerial escalation.
3. **Dynamic Group Scope Selector**:
   - Dynamic organizational dropdown filtering metrics across `All groups` or individual assigned groups, strictly obeying caller scope boundaries (`cencom_scope = true` for broad access; scoped to assigned groups for OM, TL, ATL).

### Authoritative Database Pass-Through Principle ("Database Computes, UI Renders")

**Status: ACCEPTED.** Enforces architectural simplicity (KISS) and bandwidth optimization:

1. **Zero Client-Side Headcount Calculation**:
   - Client applications on Web and Mobile are strictly prohibited from downloading entire raw tables (`plantilla`, `plantilla_slots`) over the network to calculate headcount sums, fill rates, or vacancy totals in memory.
2. **Authoritative View Sourcing**:
   - All group metrics, account breakdowns, and KPI aggregates are computed natively by database views (`v_cencom_group_allocation_kpi`, `v_cencom_account_allocation_kpi`, `v_account_allocation_kpi`, `v_plantilla_safe`).
   - The UI layer functions purely as a presentation renderer of verified database-computed columns.

### Whole-Number Headcount & KPI Rounding Contract (Migration 20262606000147)

**Status: ACCEPTED.** Enforces clean executive reporting across organizational views:

1. **Whole-Number Corporate Presentation**:
   - Account-level and group-level headcount allocations and KPI metrics in views (`v_account_allocation_kpi`, `v_cencom_account_allocation_kpi`, `v_cencom_group_allocation_kpi`) display rounded whole numbers (`ROUND(actual_hc)`, `ROUND(slot_vacant_hc)`, `ROUND(required_hc)`).
   - Eliminates awkward fractional headcount decimals (e.g., `12.33` or `45.67`) on high-level executive cards, while underlying store-level allocations maintain mathematically accurate fractional capacity ($1/N$).

---
