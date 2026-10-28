# CENCOM State & Technical Architecture Specification

**Module Route:** `/cencom`  
**Primary Schema / Sources:** `v_cencom_allocation_kpi`, `v_cencom_group_allocation_kpi`, `fn_cencom_deployment_summary`, `stores`, `accounts`  
**Last Updated:** 2026-10-25 (`ohm#l3c8m1q5`)

---

## 1. Overview & Architecture

- **`v_account_allocation_kpi` Actual Headcount Active Plantilla Guard (`ohm#4x7n2k9w` — Phase 10, `20261028033655_fix_account_allocation_kpi_actual_hc_active_plantilla_guard.sql`)**:
  - Guarded the `filled` CTE by joining active plantilla records (`JOIN plantilla p ON p.id = a.plantilla_id WHERE a.is_active AND p.status IN ('Active', 'For Deactivation', 'On Leave') AND NOT p.is_deleted AND NOT p.is_archived`).
  - Eliminates orphan/inactive plantilla parent allocations (e.g. historical MARIZ assignments) from leaking into `actual_hc` or `filled_hc`.
  - 116-account gate verified: sole diff across the entire database is ALTURAS `754 -> 752` (`filled_hc`: `754.0000 -> 752.0000`). All other 115 accounts 100% unchanged (`ACTISERVE` 1, `FOREVER OFFICE` 5). Dependent view `v_cencom_account_allocation_kpi` resolves cleanly.


The **CENCOM (Central Command)** module provides operational manpower fulfillment rate (MFR) monitoring, slot-authority allocation, vacancy aging analytics, and deployment velocity tracking.

### Tab Navigation (5 Tabs via Shared `SegmentedTabs`)
1. **Overview (`overview`)**: Executive operational command center featuring Hero Overall MFR ring gauge, neutral KPI cards (Total required, Total actual, Open vacancies, Deployed stores), monthly deployment summary, and quick tab shortcuts.
2. **Groups (`groups`)**: Granular group performance roster table (`CencomGroupTable.tsx`) with search, health filtering, sorting, store counts, shared `PercentageBar` MFR progress indicators, and account badges.
3. **Target Deployment (`target_deployment`)**: Vacancy aging brackets (1–15d, 16–30d, 31–60d, 61–120d, >121d, Advance), province aging breakdowns, and store outlet drilldowns (`CencomTargetDeploymentTab.tsx`).
4. **Deployment Activity (`deployments`)**: Chronological candidate placement records and onboarding velocity (`CencomDeploymentActivityTab.tsx`).
5. **Quick Reports (`reports`)**: 18 standard analytical workforce reports (`CencomQuickReportsTab.tsx`) using semantic card surfaces.

---

## 2. Group Scope Dropdown

### Behavior & Placement
- **Location**: Rightmost end of the tab navigation row, aligned opposite "Overview". Powered by shared `ScopeDropdown`.
- **Visibility**: Rendered strictly when `activeTab === "overview"`. Hidden on all other tabs.
- **Default Selection**: `"all"` ("All groups").
- **Options Construction**:
  - Dynamically resolved from `useCencomGroupKpi()`.
  - Scoped users (OM, TL, ATL, Encoder) have options restricted to their assigned groups via `currentUser.groupScope.ids` (from `get_web_current_user_context`).
  - Broad-access users (Super Admin, Head Admin) see all operational groups (`cencom_scope = true`).
  - Sorted canonically by `group_code` ascending (`G1` → `G2` → `G3` → `G4` → `G5`), labeled via `formatGroupName`.
  - Zero hardcoding of 5 groups.
- **Lifecycle & Persistence**:
  - Group selection persists across "Refresh Data" clicks.
  - Stale-selection fallback: If a selected group is no longer present after refetch, falls back automatically to `"all"`.
  - Resets to `"all"` upon leaving the CENCOM module.

---

## 3. Scoping & Data Mapping Matrix (Option A)

When `"All groups"` is selected, metrics match global baseline views 1:1. When a specific group is selected, metrics scope to that group without fabricating missing backend data:

| Metric Tile | Global Source | Scoped Group Source | Scoped Group Behavior |
|---|---|---|---|
| **Overall MFR** | `kpi.mfrPercent` | `selectedGroup.mfrPercent` | Scoped MFR gauge & fulfillment percentage |
| **Total required** | `kpi.required` | `selectedGroup.required` | Slot-authority capacity for selected group |
| **Total actual** | `kpi.actual` | `selectedGroup.actual` | Active employee headcount under selected group |
| **Open vacancies** | `kpi.vacant` | `selectedGroup.vacant` | Reconciled open vacancy count for selected group |
| **Deployed stores** | `storeStats.activeStores / storeStats.totalStores` | `selectedGroup.activeStores / selectedGroup.totalStores` | Active vs total stores assigned to selected group with progress bar |
| **New deployments** | `deploymentSummary.deployment` | Backend RPC is global only | Displays `"—"` with caption `"All groups only"` |
| **Additional HC** | `deploymentSummary.additionalHc` | Backend RPC is global only | Displays `"—"` with caption `"All groups only"` |
| **Total departures**| `deploymentSummary.totalDepartures` | Backend RPC is global only | Displays `"—"` with caption `"All groups only"` |
| **Deleted VCodes** | `deploymentSummary.deletedVcode` | Backend RPC is global only | Displays `"—"` with caption `"All groups only"` |

---

## 4. Design Tokens & Shared UI System Alignment (ohm#l3c8m1q5)

### Component Alignment
- **Hero Card**: `CencomOverviewHeroCard.tsx` consumes shared `HeroCard` (`@/components/shared/HeroCard`) with Brand Blue semantic tokens (`--hero-*`) and animated sweep ring gauge.
- **KPI Cards**: `CencomKpiCard.tsx` wraps shared `KpiCard` (`@/components/shared/KpiCard`) with `NeutralChip` and `PercentageBar`.
- **Navigation**: Tab bar consumes shared `SegmentedTabs` (`@/components/shared/SegmentedTabs`) with sliding pill indicator.
- **Scope Dropdown**: `CencomGroupScopeDropdown.tsx` wraps shared `ScopeDropdown` (`@/components/shared/ScopeDropdown`).
- **Group Performance**: `CencomGroupTable.tsx` consumes shared `PercentageBar` for MFR ratios with zero color literals. Tracks use recessed `bg-surface-muted border border-border-subtle/50` to eliminate blending into card backgrounds across themes.
- **MFR Thresholds**: Aligned to authoritative scale (100% Green `good`, 95% to 99.99% Yellow `warn`, <95% Red `bad`). CENCOM health status mapping (`healthStatus`) enforces `mfr >= 1.0` -> `healthy`, `mfr >= 0.95` -> `at_risk`, and `< 0.95` -> `critical`.
- **Aging & Reports**: `CencomTargetDeploymentTab.tsx` and `CencomQuickReportsTab.tsx` fully tokenized with zero raw color literals.

### Color Literal Audit
- Module Total: **0 color literals** across all CENCOM files (dropped from 237).
- Gate Verification: `TOUCHED_MODULES=cencom python3 .agents/scripts/gate.py` passed with 0 violations.

---

## 5. Archival, QA Reset & Rollback Behavior
- **Stores & Groups**: Queries filter `stores` and `accounts` by `COALESCE(is_archived, FALSE) = FALSE AND suppressed_by_batch_id IS NULL`.
- **Deployment Summary**: `fn_cencom_deployment_summary` filters `deleted_vcode` by `v.suppressed_by_batch_id IS NULL AND v.archive_batch_id IS NULL`, ensuring pre-existing deleted VCodes drop to 0 during QA Reset and restore on rollback without reopening into active operational views.
- **Quick Reports Tab Badge**: Displays 0 when groups = 0 post QA Reset.
