# CENCOM State & Technical Architecture Specification

**Module Route:** `/cencom`  
**Primary Schema / Sources:** `v_cencom_allocation_kpi`, `v_cencom_group_allocation_kpi`, `fn_cencom_deployment_summary`, `stores`, `accounts`  
**Last Updated:** 2026-10-24 (`ohm#6c3q8wzn`)

---

## 1. Overview & Architecture

The **CENCOM (Central Command)** module provides operational manpower fulfillment rate (MFR) monitoring, slot-authority allocation, vacancy aging analytics, and deployment velocity tracking.

### Tab Navigation (5 Tabs)
1. **Overview (`overview`)**: Executive operational command center featuring Hero Overall MFR ring gauge, neutral KPI cards (Total required, Total actual, Open vacancies, Deployed stores), monthly deployment summary, and quick tab shortcuts.
2. **Groups (`groups`)**: Granular group performance roster table (`CencomGroupTable.tsx`) with search, health filtering, sorting, store counts, MFR progress bars, and account badges.
3. **Target Deployment (`target_deployment`)**: Vacancy aging brackets (&lt;30d, 30–60d, &gt;60d), province aging breakdowns, and store outlet drilldowns (`CencomTargetDeploymentTab.tsx`).
4. **Deployment Activity (`deployments`)**: Chronological candidate placement records and onboarding velocity (`CencomDeploymentActivityTab.tsx`).
5. **Quick Reports (`reports`)**: 18 standard analytical workforce reports (`CencomQuickReportsTab.tsx`).

---

## 2. Group Scope Dropdown (OHM#6c3q8wzn)

### Behavior & Placement
- **Location**: Rightmost end of the tab navigation row, aligned opposite "Overview". On narrow viewports, the tab row scrolls horizontally while the dropdown wraps cleanly below without layout overflow.
- **Visibility**: Rendered strictly when `activeTab === "overview"`. Hidden on all other tabs (Groups, Target Deployment, Deployment Activity, Quick Reports).
- **Default Selection**: `"all"` ("All groups").
- **Options Construction**:
  - Dynamically resolved from `useCencomGroupKpi()`.
  - Scoped users (OM, TL, ATL, Encoder) have options restricted to their assigned groups via `currentUser.groupScope.ids` (from `get_web_current_user_context`).
  - Broad-access users (Super Admin, Head Admin) see all operational groups (`cencom_scope = true`).
  - Sorted canonically by `group_code` ascending (`G1` &rarr; `G2` &rarr; `G3` &rarr; `G4` &rarr; `G5`), labeled via `formatGroupName`.
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

## 4. Design Tokens & Typography

### Typography Standards
- Page Title: `40px` (`text-[40px]`), font weight `w600` (`font-semibold`), tracking `-0.035em` (`tracking-[-0.035em]`).
- Card Title: `16px` (`text-base`), font weight `w600` (`font-semibold`).
- Meta / Subtitles: `12px` minimum (`text-xs`), sentence case (no all-caps).
- KPI Numbers: `44px` (`text-[44px]`), font weight `w600` (`font-semibold`), tracking `-0.04em` (`tracking-[-0.04em]`).
- Hero Gauge Value: `52px` (`text-[52px]`), font weight `w600` (`font-semibold`), tracking `-0.04em`.
- Tabular Figures: `tabular-nums` applied to all numerical counters. Monospace strictly reserved for VCODE.
- Contrast: All text &ge; 4.5:1 against surfaces in both light and dark themes.

### Semantic Hero Tokens (`src/app/globals.css`)
CENCOM Overview Hero card consumes dedicated semantic tokens that adapt automatically across themes without hardcoded hex literals in components:

| CSS Variable | Tailwind Utility | Light Theme (`:root`) | Dark Theme (`.dark`, `[data-theme="dark"]`) | Purpose |
|---|---|---|---|---|
| `--hero-surface` | `bg-hero-surface` | `#fbe9ec` (soft red tint) | `#2a1417` (dark red-black) | Hero card background |
| `--hero-border` | `border-hero-border` | `#f8c9d0` | `#442226` | Hero card perimeter border |
| `--hero-text` | `text-hero-text` | `#16161a` (dark text) | `#ececf0` (light text) | Hero primary text & numbers |
| `--hero-muted` | `text-hero-muted` | `#73595c` | `#ad9497` | Hero meta text & unit labels |
| `--hero-accent` | `text-hero-accent` | `#c4372b` | `#ff7d70` | Gauge active arc & accent highlights |
| `--hero-track` | `text-hero-track` | `rgba(196, 55, 43, 0.12)` | `rgba(255, 125, 112, 0.18)` | Gauge background ring track |

### Motion & Transitions
- Numbers: count up 900ms (`easeOutCubic`).
- Progress bars: grow 1100ms (`easeOutCubic`).
- Ring gauge: sweeps 1300ms (`stroke-dashoffset` ease-out).
- Tab navigation pill: slides 350ms (`transition-all duration-[350ms]`).
- Overview panel: fades in 280ms (`animate-in fade-in duration-[280ms]`).
- `prefers-reduced-motion`: When active, animations are bypassed and final values are rendered immediately.
