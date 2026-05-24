# OHMployee Web Design Token System Specification

This document serves as the authoritative visual design and layout blueprint for the OHMployee Web dashboard. To ensure a cohesive, desktop-first admin experience across all shared modules (including **Vacancy**, **HR Emploc**, and **Plantilla**), these tokens must be strictly referenced in all current and future front-end components.

By centralizing these visual parameters, we eliminate styling divergence, enforce a premium aesthetic rhythm, and protect the codebase's structural integrity.

---

## 0. Activation Status (OHM2026_1097)

The token system is **live** in `src/app/globals.css`. Implementation notes:

- **Semantic colors are dark-mode aware.** Surface, text, and border tokens are declared as runtime CSS variables on `:root` and remapped under `@media (prefers-color-scheme: dark)`. They are exposed to Tailwind via `@theme inline` (e.g. `bg-surface-base`, `text-text-primary`, `text-text-secondary`, `text-text-muted`, `border-border-default`, `border-border-subtle`, `bg-surface-hover`, `bg-surface-selected`, `bg-[var(--surface-overlay)]`). Because they resolve at runtime, a single dark block re-themes all chrome.
- **Static scales use plain `@theme`.** Brand ramp (`brand-50…700`), status colors (`status-{success,warning,danger,info,neutral}-{bg,border,text}`), radii (`radius-*`), and animations (`animate-drawer-in`, `animate-drawer-out`, `animate-fade-in`) generate utilities directly.
- **Layout/motion constants are plain `:root` custom properties** consumed through arbitrary values, since they have no Tailwind utility namespace: `--sidebar-width` (240px), `--topbar-height`, `--drawer-width-md|lg|xl`, `--z-base…toast`, `--space-*`, `--duration-*`. Example usage: `w-[var(--sidebar-width)]`, `w-[var(--drawer-width-lg)]`.
- **Status tokens are wired through `StatusBadge`**, so every semantic badge now reads from `status-*` variables rather than ad-hoc green/amber/red strings.
- **Shared primitives** (`AdminPageHeader`, `MetricCard`, `DataState`, `DetailDrawer`, `AdminFilterBar`, `StatusBadge`) consume the semantic surface/text/border tokens and therefore respond to dark mode automatically.

Dense feature tables (Vacancy, HR Emploc) intentionally keep their literal Tailwind row classes for now; only the shared chrome and the cross-module inconsistencies listed in OHM2026_1097 were tokenized to avoid risky module-wide churn.

---

## 1. Tailwind CSS v4 Theme Token Blueprint

This project leverages **Tailwind CSS v4** where the `@theme` directive inside the main stylesheet (`src/app/globals.css`) handles theme custom properties natively. Below is the official CSS configuration block to bind these design tokens as Tailwind utility classes:

```css
@import "tailwindcss";

:root {
  /* Core Brand Base Variables */
  --background: #f8fafc; /* Slate 50 (Page background surface) */
  --foreground: #0f172a; /* Slate 900 (Primary text) */

  /* Neutral Surface Shades */
  --surface-base: #ffffff;
  --surface-header: #fafafa;
  --surface-muted: #f1f5f9;
}

@theme {
  /* 1. Page Surfaces & Custom Brand Colors */
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  
  --color-surface-base: var(--surface-base);
  --color-surface-header: var(--surface-header);
  --color-surface-muted: var(--surface-muted);

  --color-brand-50: #f0f9ff;   /* Sky 50 */
  --color-brand-100: #e0f2fe;  /* Sky 100 */
  --color-brand-500: #0ea5e9;  /* Sky 500 */
  --color-brand-600: #0284c7;  /* Sky 600 */
  --color-brand-700: #0369a1;  /* Sky 700 */

  /* 2. Semantic Status Variants (HSL Tailored Colors) */
  --color-status-success-bg: #ecfdf5;     /* Emerald 50 */
  --color-status-success-border: #a7f3d0; /* Emerald 200 */
  --color-status-success-text: #047857;   /* Emerald 700 */

  --color-status-warning-bg: #fef3c7;     /* Amber 50 */
  --color-status-warning-border: #fde68a; /* Amber 200 */
  --color-status-warning-text: #b45309;   /* Amber 700 */

  --color-status-danger-bg: #fff1f2;      /* Rose 50 */
  --color-status-danger-border: #fecdd3;  /* Rose 200 */
  --color-status-danger-text: #be123c;    /* Rose 700 */

  --color-status-info-bg: #f0f9ff;        /* Sky 50 */
  --color-status-info-border: #bae6fd;    /* Sky 200 */
  --color-status-info-text: #0369a1;      /* Sky 700 */

  --color-status-neutral-bg: #f8fafc;     /* Slate 50 */
  --color-status-neutral-border: #e2e8f0; /* Slate 200 */
  --color-status-neutral-text: #475569;   /* Slate 600 */

  /* 3. Border Radii Tiers */
  --radius-xs: 2px;
  --radius-sm: 6px;
  --radius-md: 8px;   /* Standard card & container rounded-md */
  --radius-lg: 12px;  /* Sliding drawer & modal rounded-lg */
  --radius-full: 9999px;

  /* 4. Animation Timing & Easing Curves */
  --animate-drawer-in: slideIn 300ms cubic-bezier(0, 0, 0.2, 1) forwards;
  --animate-drawer-out: slideOut 250ms cubic-bezier(0.4, 0, 1, 1) forwards;
  --animate-fade-in: fadeIn 200ms cubic-bezier(0.4, 0, 0.2, 1) forwards;

  /* 5. Centralized Dimensions */
  --sidebar-width: 240px;
  --topbar-height: 56px;
}

@keyframes slideIn {
  from { transform: translateX(100%); }
  to { transform: translateX(0); }
}

@keyframes slideOut {
  from { transform: translateX(0); }
  to { transform: translateX(100%); }
}

@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}
```

---

## 2. Token Focus Area Breakdown

### 1. Spacing Scale
A consistent spatial rhythm prevents visual clutter. Below is the standard padding/gap scale:

| Token Name | Rem Value | Equivalent Pixel | Tailwind Utility | Primary Design Application |
| :--- | :--- | :--- | :--- | :--- |
| `space-xxs` | `0.125rem` | 2px | `p-0.5` / `gap-0.5` | Inline monospace codes, badge borders |
| `space-xs` | `0.25rem` | 4px | `p-1` / `gap-1` | Badge margin, Lucide icon spacing |
| `space-sm` | `0.5rem` | 8px | `p-2` / `gap-2` | Filter inputs, mini buttons, small headers |
| `space-md` | `0.75rem` | 12px | `p-3` / `gap-3` | Table column spacing, filter bar padding |
| `space-lg` | `1rem` | 16px | `p-4` / `gap-4` | Standard margins, KPI grid gap, cards |
| `space-xl` | `1.25rem` | 20px | `p-5` / `gap-5` | Main content padding, Drawer inner panel |
| `space-2xl` | `1.5rem` | 24px | `p-6` / `gap-6` | Primary dashboard outer grids, major boundaries |
| `space-3xl` | `2rem` | 32px | `p-8` / `gap-8` | Login screens, specialized visual elements |

### 2. Drawer Widths
Detail drawers slide in overlaying the dashboard content from the right side. Standardizing widths prevents arbitrary panel sizing:

- **Standard Inspect Drawer (`drawer-width-md`)**: `460px`
  - *Tailwind class*: `w-[460px] max-w-full`
  - *Use Case*: Vacancy details, simple approvals history, log verification panels.
- **Form/Data Drawer (`drawer-width-lg`)**: `640px`
  - *Tailwind class*: `w-[640px] max-w-full`
  - *Use Case*: Employee profile forms (HR Emploc), Plantilla allocations, multi-step actions.
- **Command-Center Drawer (`drawer-width-xl`)**: `800px`
  - *Tailwind class*: `w-[800px] max-w-full`
  - *Use Case*: Complex candidate pipeline sub-grids, large action audit boards.
- **Responsiveness Override**: Drawers must transition to `w-full` on screens smaller than their target width (mobile/tablet fallback).

### 3. Table Density
Administrative users scan hundreds of records per day. We enforce high structural density to prevent grid scanning fatigue:

- **Compact Grid (Standard)**
  - *Padding*: Vertical: `8px` (`py-2`), Horizontal: `12px` (`px-3`)
  - *Typography*: Column headers: `12px` (`text-xs uppercase font-semibold text-gray-500`), Cells: `13px`/`14px` (`text-sm`)
  - *Interactive States*: Hover: `transition-colors hover:bg-gray-50`, Selected active row: `bg-blue-50`
  - *Application*: Vacancy main table, HR Emploc roster list, Plantilla registry columns.
- **Micro Grid (Secondary Sub-tables & Audit Panels)**
  - *Padding*: Vertical: `6px` (`py-1.5`), Horizontal: `8px` (`px-2`)
  - *Typography*: Cell Content: `11px` (`text-[11px]`) or `12px` monospaced (`font-mono text-xs text-gray-700`)
  - *Application*: Inside-drawer grids (active applicants sub-list, audit events timeline).

### 4. KPI Card Sizing & Loading Boundaries
To avoid cumulative layout shifts (CLS) as metrics query dynamically:

- **Dimensions**: Card height is restricted to exactly `100px` (`h-[100px]`) or `6.25rem`.
- **Card Padding**: Inner padding is `p-4` (`16px`).
- **Internal Spacing**: Text/numerical alignment uses `flex flex-col gap-1.5`.
- **Pulsing skeletons**: Loading placeholder skeletons must match the card dimensions (`h-[100px] rounded-lg`) with exact internal alignment boxes to maintain grid layout.

### 5. Status Color Variants (Semantic Mappings)
Badges convey instant semantic meaning. Standardizing their background, border, and text pairings eliminates inconsistent color strings:

- **Success (`success`)** - *Approved, Active, Available, Open*
  - Background: `bg-status-success-bg` (`#ecfdf5`)
  - Border: `border-status-success-border` (`#a7f3d0`)
  - Text: `text-status-success-text` (`#047857`)
- **Warning (`warning`)** - *Pending Review, Processing, Medium Urgency*
  - Background: `bg-status-warning-bg` (`#fef3c7`)
  - Border: `border-status-warning-border` (`#fde68a`)
  - Text: `text-status-warning-text` (`#b45309`)
- **Danger (`danger`)** - *SLA Breach, Blocked, High Urgency, Error*
  - Background: `bg-status-danger-bg` (`#fff1f2`)
  - Border: `border-status-danger-border` (`#fecdd3`)
  - Text: `text-status-danger-text` (`#be123c`)
- **Info (`info`)** - *Current state, Primary Operational Context, Active Queue*
  - Background: `bg-status-info-bg` (`#f0f9ff`)
  - Border: `border-status-info-border` (`#bae6fd`)
  - Text: `text-status-info-text` (`#0369a1`)
- **Neutral (`neutral`)** - *Normal Urgency, Closed, System Constant, Draft*
  - Background: `bg-status-neutral-bg` (`#f8fafc`)
  - Border: `border-status-neutral-border` (`#e2e8f0`)
  - Text: `text-status-neutral-text` (`#475569`)

### 6. Surface Colors
Defining exact depth and surfaces ensures components layer beautifully:

- **Surface Page Background**: `#f8fafc` (Slate 50) - Soft grey background to make white content cards stand out.
- **Surface Component Base**: `#ffffff` - Applied to tables, cards, content blocks, and the primary body of detail drawers.
- **Surface Sticky Header**: `#fafafa` or `#f8fafc` - High-contrast backplate for scrolling lists.
- **Surface Interactive Hover**: `#f8fafc` (Slate 50) - Fine transition shade on row or button hover.
- **Surface Active Selection**: `#f0f9ff` (Sky 50) - Clean blue highlight indicating selection.
- **Surface Translucent Backdrop Overlay**: `rgba(15, 23, 42, 0.4)` (Slate 900 with 40% opacity) combined with `backdrop-filter: blur(4px)`.

### 7. Z-Index Layering
An explicit z-index scale prevents navigation bars, tables, popovers, and drawers from rendering under overlay components:

| Layer Constant | Z-Index Value | Primary Use Case |
| :--- | :--- | :--- |
| `z-base` | `0` | Base content layers, tables, page fields |
| `z-sticky` | `10` | Sticky table headers (`thead`), timeline category labels |
| `z-header` | `20` | Topbar actions and user profiles |
| `z-sidebar` | `30` | Persistent left-hand global navigation menu |
| `z-backdrop` | `40` | Translucent screen overlays for modals and drawers |
| `z-drawer` | `50` | Slide-over aside detail panels (from right overlay) |
| `z-modal` | `60` | Heavy operational modal alerts and forms |
| `z-toast` | `100` | Temporary system alert bars and toast notifications |

### 8. Border Radii
Rounded corners give components a modern, premium feel. We use four main tiers:

- `radius-xs` (`2px`): Microscopic elements (e.g. standard thin inline color status indicators)
- `radius-sm` (`6px`): Controls (native dropdown selectors, button icons, form search boxes)
- `radius-md` (`8px`): Content containers (KPI cards, filters header wraps, tables, active charts)
- `radius-lg` (`12px`): Floating structures (Detail drawers aside layer, dialog containers)
- `radius-full` (`9999px`): Status pills, badges, circle icons, user profile images

### 9. Animation Timing & Easing Curves
Transitions must feel instantaneous yet smooth to emulate native desktop speeds:

- **Speed Constants**:
  - `duration-fast` (`150ms`): Button hover transformations, icon swaps, status hover fades.
  - `duration-normal` (`250ms`): Dropdown menu collapses, select menus opening.
  - `duration-slow` (`300ms`): Aside drawer sliding animation, full page content shifts.
- **Easing Curves**:
  - `ease-standard` (`cubic-bezier(0.4, 0, 0.2, 1)`): Standard system easing.
  - `ease-decelerate` (`cubic-bezier(0, 0, 0.2, 1)`): Entrance animations (drawer sliding into viewport).
  - `ease-accelerate` (`cubic-bezier(0.4, 0, 1, 1)`): Exit animations (drawer sliding out).

### 10. Responsive Breakpoints
To support hybrid operational environments (laptops, desk screens, floor tablets):

- **Mobile Viewport** (`< 640px`)
  - Global navigation collapses to a hamburger button.
  - Side drawers fill the screen (`w-full`).
  - Secondary table columns hide automatically.
- **Tablet/Floor Viewport** (`640px` to `1024px`)
  - Global sidebar displays icon-only mode.
  - Tables enable overflow horizontal scrolling with a minimum width bound of `1060px`.
  - Drawers use standard `w-[460px]`.
- **Desktop Viewport** (`>= 1280px`)
  - Global sidebar expands fully (`w-[240px]`).
  - Active tables span full horizontal width.
  - Drawers slide overlaying the right list.
- **Ultra-Wide Desktop** (`>= 1536px`)
  - Ample spacing allows the table grid, expanded sidebar, and details drawer to remain open simultaneously without visual overlapping.
