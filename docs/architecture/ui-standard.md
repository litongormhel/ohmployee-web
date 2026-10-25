# OHMployee Web: UI Standard & Motion System

**Status:** Authoritative Standard (Enforceable from Loop 1 onwards)  
**Owner:** Product Architecture / Engineering  
**Applies to:** All modules across OHMployee Web on desktop, tablet, and mobile viewports.

---

## 1. Design Principles & Anti-Vibe Rules

1. **One System, Zero Ad-Hoc Styling:** One unified spacing scale, radius scale, typography scale, and color system. No arbitrary hex codes, no unmapped Tailwind utility colors.
2. **Hierarchy by Structure, Not Color:** Information hierarchy is established through font weight, typography size, and white space—never by stacking colored boxes or nested borders.
3. **One Hero Per Page:** At most one prominent hero card per module (e.g. Overall MFR in CENCOM). All remaining cards are neutral, calm, and quiet.
4. **Color is Strictly Reserved for Percentages:**
   - Green, amber, and red appear **only** on percentage metrics, gauge rings, progress bars, and percentage change indicators.
   - Headcount numbers, vacancy counts, applicant totals, and status labels are **neutral**.
   - Status badges use neutral surface and border tokens; only the associated percentage carries semantic color.
5. **No Per-Row Table Animations:**
   - In dense tables (Plantilla, HR Emploc, Vacancy), individual rows **must never** animate or tween on filter/sort.
   - Only the table container may execute a subtle fade-in ($\le 150\text{ms}$).
6. **Sentence Case Exclusively:**
   - All labels, headers, chips, and button text follow sentence case (e.g., "Total required", "Open vacancies", "Review queue").
   - No uppercase tracking labels, no emojis as UI icons, no glow effects, and no backdrop blurs.

---

## 2. Visual Foundation & Design Tokens

### 2.1 Brand Palette
The OHMployee Web brand identity is **blue and white** in light mode and **blue and navy** in dark mode. Tokens are declared on `:root` and exposed via `@theme inline` in `src/app/globals.css`.

- **Brand Primary Scale:**
  - `brand-50`: `#eef2ff`
  - `brand-100`: `#e0e7ff`
  - `brand-500`: `#2b4fd6` (Primary action blue)
  - `brand-600`: `#2240b0`
  - `brand-700`: `#1a318a`

### 2.2 Surface & Border Tokens
| Surface Token | Light Value | Dark Value (Approved 7a Navy) | Description |
|---|---|---|---|
| `--bg` | `#ffffff` | `#0c1017` | Canvas / Page background |
| `--side` | `#fafafb` | `#0c1017` | Sidebar / Navigation panel |
| `--soft` | `#f4f4f6` | `#131924` | Muted card backgrounds, hover fills |
| `--line` | `#ececef` | `#1e2638` | Default component borders & rules |
| `--border-strong` | `#d4d4d8` | `#2e3b56` | Emphasized card boundaries |
| `--surface-card` | `#ffffff` | `#131924` | Metric cards and panel bodies |
| `--surface-overlay`| `rgba(16, 17, 20, 0.45)` | `rgba(12, 16, 23, 0.70)` | Drawer and modal backdrops (flat, no blur) |

### 2.3 Hero Card Tokens (Brand Blue)
Hero cards use a dedicated brand blue tint (light) and deep midnight navy (dark):
| Token | Light Value | Dark Value | Purpose |
|---|---|---|---|
| `--hero-surface` | `#f0f4ff` | `#111a33` | Hero card background |
| `--hero-border` | `#dbeafe` | `#1e2f5d` | Hero card outline |
| `--hero-text` | `#16161a` | `#ececf0` | Hero card primary headings |
| `--hero-muted` | `#4b5563` | `#93a4c8` | Hero card secondary labels |
| `--hero-accent` | `#2b4fd6` | `#8aa4ff` | Primary hero indicator accent |
| `--hero-track` | `rgba(43, 79, 214, 0.12)` | `rgba(138, 164, 255, 0.18)` | Gauge background ring track |

### 2.4 Percentage Scale Tokens & Contrast Ratios
The only non-brand semantic colors in the system. Every text/bg pair satisfies WCAG AA contrast (&ge; 4.5:1):

| Status | Light Text | Light BG | Light Ratio | Dark Text | Dark BG (Composite) | Dark Ratio |
|---|---|---|---|---|---|---|
| **Good** | `#047857` | `#ecfdf5` | **5.21:1** | `#34d399` | `rgba(52, 211, 153, 0.15)` (`#122d2a`) | **7.61:1** |
| **Warn** | `#b45309` | `#fffbeb` | **4.84:1** | `#fbbf24` | `rgba(251, 191, 36, 0.15)` (`#302a19`) | **8.55:1** |
| **Bad** | `#b91c1c` | `#fef2f2` | **5.91:1** | `#f87171` | `rgba(248, 113, 113, 0.15)` (`#2f1f24`) | **5.66:1** |

Borders: Light `--pct-good-border: #a7f3d0`, `--pct-warn-border: #fde68a`, `--pct-bad-border: #fecaca`. Dark uses 35% alpha overlays.

---

## 3. Authoritative Percentage Scales & Thresholds

Centralized in [`src/lib/utils/thresholds.ts`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/lib/utils/thresholds.ts). Components invoke `evaluatePercentage(scale, percent)`.

### 3.1 Cutoffs as Defined in Code
1. **`"mfr"` (Manpower Fulfillment Rate)**:
   - Cutoffs in `src/lib/queries/cencom.ts`:
     - $\ge 100\%$ ($\ge 1.0$) &rarr; Good (Healthy)
     - $90.0\% \le \text{value} < 100\%$ ($0.90 \le \text{value} < 1.0$) &rarr; Warn (At risk)
     - $< 90.0\%$ ($< 0.90$) &rarr; Bad (Critical)
   - Screens using `"mfr"`:
     - `src/app/(dashboard)/cencom/page.tsx`
     - `src/components/cencom/CencomOverviewHeroCard.tsx`
     - `src/components/cencom/CencomGroupTable.tsx`
     - `src/components/cencom/CencomTargetDeploymentTab.tsx`
     - `src/components/cencom/CencomDeploymentCard.tsx`

2. **`"fill_rate"` (Store & Position Fill Rate)**:
   - Cutoffs in `src/app/(dashboard)/dashboard/page.tsx`:
     - $> 70\%$ &rarr; Good (Optimal)
     - $40\% \le \text{value} \le 70\%$ &rarr; Warn (Watch)
     - $< 40\%$ &rarr; Bad (Low)
   - Screens using `"fill_rate"`:
     - `src/app/(dashboard)/dashboard/page.tsx`
     - `src/components/plantilla/StoreStaffingOverviewDrawer.tsx`
     - `src/components/plantilla/WorkforceAnalyticsView.tsx`

> [!NOTE]
> 41.5% MFR (red) and 48.8% fill rate (amber) can appear on different pages. Each page strictly specifies its scale name (`"mfr"` or `"fill_rate"`).

---

## 4. Typography Standard

- **Default Font:** **DM Sans** (`var(--font-dm-sans)`), loaded via Next.js Google font loader in `src/app/layout.tsx`.
- **Monospace Font:** **DM Mono** (`var(--font-dm-mono)`), used strictly for technical codes (VCODE, Employee No, RPC identifiers).
- **Tabular Numerals:** **Mandatory** across all numerical displays (`tabular-nums` / `font-variant-numeric: tabular-nums`). DM Sans fully supports OpenType tabular numbers.
- **Scale & Floors:**

| Role | Size | Weight | Tracking | Minimum Floor |
|---|---|---|---|---|
| **Page title** | 32–40px (`text-3xl sm:text-4xl`) | 600 (`font-semibold`) | `-0.03em` | 28px on mobile |
| **Section title** | 16–18px (`text-base sm:text-lg`) | 600 (`font-semibold`) | Normal | 16px |
| **Table text** | **14–15px (`text-sm`)** | 400–500 | Normal | **Never below 14px** |
| **Meta / Helper** | 12–13px (`text-xs`) | 400 | Normal | Minimum 12px (contrast $\ge 4.5:1$) |
| **KPI value** | 36–44px (`text-3xl sm:text-4xl`) | 600 (`font-semibold`) | `-0.04em` | 32px |
| **Hero value** | 52–64px (`text-[52px] sm:text-6xl`)| 600 (`font-semibold`) | `-0.04em` | 44px on mobile |

---

## 5. Table Standard

All dense tables adhere to strict legibility constraints:
1. **Font Size Floor:** Minimum table font size is **14px (`text-sm`)**.
2. **Compact Density:** Compact density reduces **padding only** (`px-2.5 py-1.5`). Text size remains 14px.
3. **Comfortable Density:** `px-4 py-2.5` with 14px text.
4. **Alignment:** Numeric columns are right-aligned with `tabular-nums`. Text columns are left-aligned. Status pills and action icons are center-aligned.
5. **Sticky Header:** Sticky `top-0 z-10` with opaque token background `bg-table-header`.
6. **No Row Animations:** Sorting, pagination, or filtering updates apply instantly without row-level transition lag.

---

## 6. Shared Components Catalog (`src/components/shared/`)

| Component | File | Key Props & Capabilities |
|---|---|---|
| **`AnimatedNumber`** | [`AnimatedNumber.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/AnimatedNumber.tsx) | Direct DOM `requestAnimationFrame` tween (600ms ease-out). No React cascading re-renders. Tabular numerals. Automatically respects motion level. |
| **`PercentageRing`** | [`PercentageRing.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/PercentageRing.tsx) | SVG circular sweep gauge (800ms ease-out quart). Uses token colors from `evaluatePercentage`. Bypasses sweep in Lite/Off mode. |
| **`PercentageBar`** | [`PercentageBar.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/PercentageBar.tsx) | Horizontal progress bar using token colors from `evaluatePercentage`. Accessible `progressbar` attributes. |
| **`KpiCard`** | [`KpiCard.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/KpiCard.tsx) | Standard 44px KPI card with sentence-case title, `AnimatedNumber` counter, and neutral metadata slots. |
| **`HeroCard`** | [`HeroCard.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/HeroCard.tsx) | Brand-blue hero card featuring ring gauge, actual/required counts, and benchmark footer. Stacks cleanly on mobile. |
| **`SegmentedTabs`** | [`SegmentedTabs.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/SegmentedTabs.tsx) | Sliding pill segmented tab bar (200ms ease-out). Tabular count badges. Full arrow key navigation (`ArrowLeft`, `ArrowRight`, `Home`, `End`). |
| **`Modal`** | [`Modal.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/Modal.tsx) | Accessible dialog shell with ESC capture, body scroll lock, focus trap, and flat translucent backdrop (no blur). Converts to bottom sheet on mobile screens. |
| **`DetailDrawer`** | [`DetailDrawer.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/DetailDrawer.tsx) | Sliding drawer with flat translucent backdrop. Converts to full width on phone screens (`< 640px`). |
| **`DataTable`** | [`DataTable.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/DataTable.tsx) | Token-compliant data table supporting compact and comfortable padding with a strict 14px font size floor. |
| **`ScopeDropdown`** | [`ScopeDropdown.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/ScopeDropdown.tsx) | Accessible dropdown selector with chevron indicator and focus ring. |
| **`NeutralChip`** | [`NeutralChip.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/NeutralChip.tsx) | Neutral pill chip for metadata and counts. Avoids decorative colors. |
| **`EmptyState`** | [`EmptyState.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/EmptyState.tsx) | Token-compliant empty container with icon, message, and action slot. |
| **`Skeleton`** | [`Skeleton.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/Skeleton.tsx) | Subtle pulse loader matching container dimensions. |
| **`InlineError`** | [`InlineError.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/InlineError.tsx) | Tokenized error box with retry trigger. |
| **`Toast`** | [`Toast.tsx`](file:///Users/armanjr/Projects/OHMployee/OHMployee_web/src/components/shared/Toast.tsx) | Floating bottom-right alert message using semantic token colors. |

---

## 7. Motion Budget & Performance Standard

- **Budget:**
  - Pill slide: 200–250ms
  - Value tween: 600–800ms
  - Modal in / out: 180ms / 120ms
  - Card stagger: 45ms step (maximum 6 items)
  - Fade out / in: $\le 150\text{ms}$
- **Easing Curve:** One curve across the system: `cubic-bezier(0.16, 1, 0.3, 1)`.
- **Properties Allowed to Animate:** `transform`, `opacity`, `stroke-dashoffset`. Layout properties (`width`, `height`, `margin`, `padding`, `top`, `left`) are **forbidden** to animate.
- **Motion Levels (`useMotionLevel.ts`):**
  - **Full:** Standard smooth transitions and tweens.
  - **Lite:** Opacity fades only ($\le 150\text{ms}$). No stagger, no count-up, no SVG sweep. Auto-selected when `hardwareConcurrency <= 4` or `deviceMemory <= 4`.
  - **Off:** Zero motion. Immediate value rendering. Selected when `prefers-reduced-motion` is active or user toggles `reduceMotionEnabled` in Settings.

---

## 8. Responsive Specifications

- **Breakpoints:**
  - Phone: `< 640px` (sm)
  - Tablet: `640px - 1023px` (sm to lg)
  - Desktop: $\ge 1024\text{px}$ (lg)
  - Large: $\ge 1536\text{px}$ (2xl)
- **Rules:**
  - No fixed pixel widths on page layouts. No sideways page scroll.
  - On phone: Modals become bottom sheets (`rounded-t-2xl sm:rounded-2xl`). Drawers become full width (`w-full sm:w-[var(--drawer-width-md)]`).
  - Tables scroll within their own container (`overflow-x-auto`).
  - Touch targets $\ge 44\text{px}$ on touch devices.

---

## 9. Gate & Verification Protocol for Loops

Every module loop must satisfy:
1. **ESLint Clean:** `npm run lint` with 0 errors.
2. **Next.js Build Clean:** `npm run build` with zero regressions beyond documented baseline.
3. **Zero Color Literals:** 0 unmapped color literals (`bg-emerald-*`, `text-slate-*`, raw hex codes) in touched modules, mechanically enforced by `.agents/scripts/gate.py`.
4. **Dark Mode & Contrast Verification:** Body text contrast $\ge 4.5:1$, large text and borders $\ge 3:1$. Card edges and progress tracks clearly visible in both themes.
5. **No Business Formula Changes:** Same RPCs, same formulas, same permission gates.

---

## 10. Changelog & Implementation History

- **Loop 4 (Vacancy) & Color-Use Audit (`ohm#l4v9k2x1`)**:
  - Conducted full Color-Use Audit across Dashboard, CENCOM, and Vacancy enforcing Blueprint Section 3, Rule 3 & 4 (color strictly reserved for percentage metrics).
  - Neutralized aging brackets in days, vacancy counts, operational totals, deployment statuses, and modal completion states in Dashboard and CENCOM.
  - Aligned Vacancy module (`src/app/(dashboard)/vacancy/page.tsx`, `VacancyTable.tsx`, `VacancyDetailDrawer.tsx`, `VacancyFilterToolbar.tsx`, and all 9 modals) dropping color literals from 450+ to 0.
  - Wrapped all 9 Vacancy modals in shared `Modal` (`@/components/shared/Modal.tsx`) and verified `DetailDrawer` in `VacancyDetailDrawer.tsx` with 100% preservation of form logic, mutations, and hooks.
- **Loop 3 (CENCOM) & Gate Hardening (`ohm#l3c8m1q5`)**:
  - Hardened mechanical gate (`.agents/scripts/gate.py`), removing baseline-red allowance and auto-deriving touched modules.
  - Fixed shared `Toast` contract and conditional usage in Dashboard; verified `npm run build` green across 19 static routes on `main`.
  - Aligned CENCOM module dropping 237 color literals to 0 and adopting shared `HeroCard`, `KpiCard`, `ScopeDropdown`, `SegmentedTabs`, `PercentageBar`, and `NeutralChip`.
- **Loop 2 (Dashboard) (`ohm#l2d7k8w1`)**:
  - Full tokenization and shared component adoption for Dashboard module (`dashboard/page.tsx`, `MikaSyncModal.tsx`).
- **Loop 1 (Foundation) (`ohm#l1f9w2s4`)**:
  - Delivered authoritative `ui-standard.md`, centralized percentage thresholds in `src/lib/utils/thresholds.ts`, implemented 7a dark navy token values, delivered 15-component shared UI catalog.
- **Loop 0 (Discovery & Gate Setup) (`ohm#l0u8s2d9`)**:
  - Comprehensive codebase audit, gate script configuration in `.agents/scripts/gate.py` and `.agents/hooks.json`.
