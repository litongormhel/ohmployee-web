# OHMployee Web: UI Standard & Motion System (Loop Briefing)

**Status:** Draft v2 (adds responsive, dark mode standard, no-approval loop, ADR updates), ready for Loop 0
**Owner:** Ohm (product owner)
**Runs in:** Claude Code (loop engineering), on `main` only
**Suggested location:** `docs/architecture/ui-standard-briefing.md` (Loop 1 produces the enforceable `docs/architecture/ui-standard.md`)

---

## 1. Goal

Make OHMployee Web feel like one smooth, calm, consistent product. Every module, every second-level page, every modal and drawer follows the same UI and transition standard. The brand stays **blue and white**. The result must look designed, not generated.

This is a **standard**, not a one-off refresh. After this work, new screens are built from the standard by default.

## 2. Scope

**In:** all OHMployee Web modules (Vacancy, HR Emploc, Plantilla, Dashboard, CENCOM, Approvals, User management, Team directory, Notifications, Reports, Settings, More), their detail/second-level pages, modals, drawers, dropdowns, empty/loading/error states.

**Out:**
- Flutter mobile app (this briefing covers the web app on desktop, tablet, and phone screens).
- Data, hooks, queries, RPCs, RLS, RBAC, schema, business formulas.
- Copy/labels changes beyond sentence-case cleanup.
- New features (no realtime sources, no new metrics).

## 3. Non-negotiables

1. **No regression.** Same data, same numbers, same permissions. Animation changes display only.
2. **Brand colors:** white, neutral grays, brand blue. Nothing else is decorative.
3. **Color is reserved for percentages.** Green / yellow / red appear only on percentage values, bars, and rings (fill rate, MFR, compliance, etc.). Counts (SLA breaches, vacancies, headcount) are neutral. Status chips are neutral; the percentage next to them carries the color. Use the thresholds that already exist in code; do not invent new ones.
4. **Light and dark both work, and both are on-brand (blue and white).** Follow the user's theme setting. Nothing forced dark or light. In dark mode everything must be visible, readable, and functional (section 5.4).
5. **Font is user-changeable.** Settings already has a font switch; the standard only sets the default.
6. **Works on low-end PCs.** Most users are on low-end machines. Motion has a strict budget (section 8).
7. **Readable for users in their 30s-40s.** Larger text, strong contrast, big click targets.
8. **Preserve existing architecture** unless a loop explicitly says otherwise.
9. **Responsive everywhere.** The web app adapts automatically to any screen size (desktop, laptop, tablet, phone). No fixed widths, no sideways page scroll (section 5.5).
10. **Loops run without approval gates.** They pause only on a stop condition or a failed verification (section 10).
11. **ADR-001 stays true.** If a loop changes anything the ADR describes, update the ADR in the same loop (section 11).

## 4. Design principles (the "not vibe-coded" test)

- One grid, one spacing scale, one radius scale, one type scale. No one-off values.
- Hierarchy by size, weight, and whitespace, not by color or boxes inside boxes.
- One hero element per page at most. Everything else is quiet.
- Few chips. A chip appears only when it changes what the user does next.
- Sentence case labels. No all-caps tracking labels, no emoji-style icons, no gradients, no glow.
- Same component = same look everywhere. If two screens differ, one of them is wrong.
- Empty, loading, and error states are designed, not left blank.
- Review checklist at the end of every loop (section 10, step 6).

## 5. Visual foundation

### 5.1 Color
- Tokens live in `src/app/globals.css` (additive only, never rename or edit existing variables).
- **Brand blue:** read the existing `brand-*` tokens in code. Do not pick a new blue. If only a partial scale exists, extend it from the existing primary.
- Surfaces: page background, card, muted, hover, border. Reuse existing `--surface-*`, `--text-*`, `--border-*` where they exist.
- **Hero card:** brand-blue tinted surface (light) and deep blue surface (dark), with brand-blue accents. No red or pink tint. Any percentage inside it still uses green/yellow/red.
- **Percentage scale:** `--pct-good`, `--pct-warn`, `--pct-bad` (+ bg/text pairs) for both themes. These are the only non-brand colors in the system.

### 5.2 Typography
- Default font: a clean Google font (proposed: **Hanken Grotesk**). Exposed as one `--font-sans` variable so the Settings font switch overrides it everywhere.
- **Tabular numerals** on every number. Monospace only for VCODE-style identifiers.
- Scale (users are 30s-40s, so floors are higher than the mockups):

| Role | Size | Weight | Notes |
|---|---|---|---|
| Page title | 32-40px | 600 | tracking -0.03em, same on every page |
| Section/card title | 16-18px | 600 | |
| Body / table | 14-15px | 400-500 | never below 14 |
| Meta / helper | 12-13px | 400 | minimum 12, contrast >= 4.5:1 |
| KPI value | 36-44px | 600 | tracking -0.04em |
| Hero value | 56-64px | 600 | |

- Contrast >= 4.5:1 for all text in both themes. Interactive targets >= 40px.

### 5.3 Shape and space
- Radius: card 16-20, control 10-12, pill 999. Spacing on a 4px base. One card padding (20-24).
- Borders over shadows. No blur, no backdrop-filter, no large shadows (also a performance rule).

### 5.4 Dark mode (blue and white, fully legible)
- Dark mode is part of the brand, not a color inversion. Surfaces are deep blue-tinted neutrals derived from the brand blue scale; text is near-white; accents are a lighter brand blue. No pure `#000` page with pure `#fff` text, no gray-on-gray.
- Contrast floors: body text >= 4.5:1; large text and UI parts (borders, icons, focus rings, input outlines) >= 3:1; placeholders and disabled states stay readable.
- **Nothing may disappear or look blurry:** card edges, dividers, table row separators, progress/ring tracks, chart gridlines, skeletons, and hover/selected/focus states must be clearly visible in dark.
- Percentage colors (green/yellow/red) get dark-tuned variants with legible text on their backgrounds.
- No text dimmed by opacity below the contrast floor. No text over images or gradients without a solid scrim.
- **Everything works in dark:** modals, drawers, dropdowns, tooltips, toasts, date pickers, inputs, tables, charts, scrollbars. Native controls use `color-scheme`. Any third-party widget is re-themed or replaced.
- No flash of the wrong theme on load.
- Verified per screen: screenshots in both themes plus a contrast check (axe/Lighthouse if the repo already has it; otherwise manual DevTools contrast inspection). No new tooling is required.

### 5.5 Responsive (desktop, laptop, tablet, phone)
- One responsive web app. Mobile-first, fluid CSS, container-aware layouts. No fixed pixel widths and no sideways page scroll.
- Breakpoints (proposed; Loop 0 aligns them to the existing Tailwind config): phone < 640, tablet 640-1023, desktop >= 1024, large >= 1536 (content gets a max-width).
- Navigation: sidebar on desktop; on phone it collapses (drawer or bottom bar, decided in Loop 0/1 from the existing nav).
- Grids reflow (for example KPI cards 4 -> 2 -> 1). The hero spans full width on phone.
- Tables scroll inside their own container, or become stacked rows for key lists on phone. Sticky first column where useful. Never page-level horizontal scroll.
- Modals become full-width bottom sheets (or full screen) on phone; drawers become full width. Respect safe-area insets.
- Type scales fluidly (`clamp`) but never below the floors in 5.2. Touch targets >= 44px on touch screens. Anything hover-only has a tap equivalent.
- Verify at 360x800, 390x844, 768x1024, 1280x720, 1366x768 (common low-end laptop), and 1920x1080, plus orientation change.
- Phones follow the same Lite motion rules (section 8).

## 6. Component catalog (built in Loop 1, reused everywhere)

Page header (breadcrumb, title, subtitle, actions) · Segmented tabs with sliding pill (count badge inside) · Scope dropdown · KPI card · Hero card · Percentage bar · Percentage ring · Neutral chip · Data table (density options, sticky header, right-aligned numeric columns) · Modal · Drawer · Dropdown/select · Toast · Empty state · Skeleton · Inline error.

Rules: every component takes theme tokens only (no literals like `#FBE9EC`, `bg-emerald-50`, `text-slate-900`), supports keyboard and visible focus, and has light/dark/reduced-motion behavior defined.

## 7. Behavior patterns

### 7.1 Scope / tab change
Segmented pill slides. Numbers tween from their **current** value to the new one (never from 0). Rapid changes retarget from the current displayed value, no jump.

### 7.2 Page enter (per page)
Sequence: title reveal, KPI cards stagger in, tabs/filters fade in, then content. Content is usable immediately; motion never gates data or clicks.

### 7.3 Modal and drawer
- Modal: fade + small scale/translate in, faster out. Focus trap, Esc closes, backdrop is a flat translucent color (no blur).
- Drawer: slides from the right with the same easing. Same header, footer, and spacing in every module.
- On phone: modal becomes a bottom sheet / full screen, drawer becomes full width.
- Loop 0 decides, from the existing code, whether to unify onto one shared Modal/Drawer or wrap the current ones.

### 7.4 Tables
Large tables (Plantilla, HR Emploc, Vacancy lists) get **no per-row animation**. Only the container fades in. Sorting/filtering updates do not animate rows.

### 7.5 Reference timings (from the Corbel recording; approximate, +/-100ms)
| Pattern | Reference | OHMployee budget (low-end) |
|---|---|---|
| Pill slide | ~300ms | 200-250ms |
| Value tween | ~1200ms, strong ease-out | 600-800ms |
| Page enter total | ~1.2s | <= 700ms |
| Card stagger | 60-80ms step | 40-50ms step, max 5-6 items |
| Fade out old content | 150-200ms | 100-150ms |
| Modal in / out | n/a | 180ms / 120ms |

Easing: one curve everywhere, `cubic-bezier(0.16, 1, 0.3, 1)` (or easeOutQuart). Defined once as a token.

## 8. Performance and accessibility budget

- Animate only `transform`, `opacity`, `stroke-dashoffset`, and `clip-path`. No layout properties.
- Prefer CSS animations. If JS is needed (value tween), use one shared `requestAnimationFrame` loop, update a DOM node's text directly, and avoid per-frame React state.
- **Motion levels:** Full / Lite / Off. Default is automatic: `prefers-reduced-motion` -> Off; weak device (`navigator.hardwareConcurrency <= 4` or `deviceMemory <= 4`) -> Lite. Lite = opacity fades <= 150ms only (no stagger, no count-up, no ring sweep). The user can override in Settings (proposed; Loop 1 confirms where it lives).
- Static content first, motion layered on top. No effect on LCP. The page must be fully correct if animations never run.
- No new animation library unless Loop 0 shows one is already in use. Default is CSS plus a tiny shared hook.
- Test protocol for every loop: production build (`npm run build` + start), Chrome DevTools **CPU 4x slowdown**, light, dark, reduced-motion, keyboard-only pass, and the viewport list in 5.5.

## 9. Known facts (from the CENCOM pass, ohm#6c3q8wzn). Verify in code, do not trust blindly.

- Repo: `ohmployee-web` (Next.js app router, Tailwind v4, tokens in `src/app/globals.css`, dark via `.dark` / `[data-theme="dark"]`).
- CENCOM Overview was refreshed first: group scope dropdown, hero card, KPI cards, deployment summary tiles, tab pill, count-up. These pieces were built inside `src/components/cencom/`. **Loop 1 promotes the reusable ones to shared components** and CENCOM then consumes them.
- Before that pass, `CencomDeploymentCard` and the CENCOM shortcut cards used hardcoded Tailwind colors (`bg-emerald-50/50`, `bg-blue-50`, ...) with poor dark-mode contrast. Expect the same pattern in other modules.
- The CENCOM hero was prototyped with a red tint (it showed "Critical"). That is superseded: hero is brand blue (section 5.1).
- Existing helpers to reuse: `formatGroupName`, group ordering by `group_code`, existing role/scope hooks.

## 10. The loop

### Loop 0: Discovery (read-only, no code)
Write a short audit (as the opening entry in `.ai/handoff.md`), then continue straight into Loop 1:
1. Brand token inventory (brand scale, surfaces, current dark mode support).
2. `package.json`: animation/UI libraries, test setup.
3. `(dashboard)` layout, sidebar, header: what is shared by all modules.
4. Modal/drawer/dropdown inventory: shared components or per-module copies; counts; a recommendation (unify vs wrap).
5. Settings font mechanism (how the user changes font; what variable it sets).
6. Module and route list, including second-level pages and modals per module. Proposed rollout order with reasoning.
7. Hardcoded color count per module (grep for Tailwind color literals and hex).
8. Largest tables per module (row counts, virtualization yes/no).
9. Percentage thresholds already used in code (green/yellow/red cutoffs). List where defined.
10. What from the CENCOM pass is reusable as shared.
Deliver: findings, answers to the "decided by Claude" items (section 12), the Loop 1 plan, regression risk assessment. No approval wait; proceed unless a stop condition applies.

### Loop 1: Foundation
- Additive tokens in `globals.css` (colors, `--pct-*`, radius, spacing, motion durations/easing/stagger, `--font-sans`).
- Motion-level detection hook + Settings hook-up (if approved in Loop 0).
- Shared components from section 6, built once.
- Move reusable CENCOM pieces to shared and re-point CENCOM at them (visual parity check, numbers identical).
- Write `docs/architecture/ui-standard.md` (tokens, components, patterns, do/don't, test protocol). This becomes the source of truth.
- Exit: lint + build clean, CENCOM unchanged in behavior, standard doc complete.

### Loop 2..N: Module rollout (one module per loop)
Suggested order (Loop 0 confirms): Dashboard -> CENCOM (align) -> Vacancy -> HR Emploc -> Plantilla -> Approvals -> User management / Team directory -> Notifications / Reports / Settings / More.
Each loop covers the module's list page, detail pages, modals, drawers, and empty/loading/error states.

### Final loop: App-wide route transition and polish
Only after all modules. Touches the shared `(dashboard)` layout, so it runs last with extra verification: a full-app smoke pass in both themes and at every viewport in 5.5. Also: consistency sweep across modules, remove dead one-off styles, update the standard doc.

### Per-loop procedure
1. **Load context:** `.ai/briefing.md`, `.ai/current_state.md`, `docs/state/<module>_state.md`, ADR-001 relevant sections only (mandatory for Vacancy, HR Emploc, Plantilla, More, Dashboard, CENCOM), `docs/architecture/ui-standard.md`. No full-repo scans.
2. **Inventory** the module's screens, modals, drawers (targeted grep).
3. **Plan + regression assessment** (one screen), written to `.ai/handoff.md` as the loop's opening entry. **No approval wait: the loop proceeds automatically** unless a stop condition triggers. (This overrides the standing "stop and wait" rule for this project only.)
4. **Implement** with parallel sub-agents where heavy: (A) token/color cleanup, (B) component adoption, (C) motion and states.
5. **Verify:** `npm run lint`, `npm run build`, existing tests pass, numbers identical to before, manual matrix: light, dark (legibility and contrast check), reduced-motion, CPU 4x, keyboard, and every viewport in 5.5. A failed check is fixed inside the loop; the loop does not close with known failures.
6. **Design review checklist & Color-Use Audit:**
   - **Per-loop color-use audit table:** For every use of `--pct-good/warn/bad` (or equivalent classes) in the module, list file, element, and the exact percentage it represents. Verify anything not a percentage (aging brackets in days, counts, status words, report cards, modal completion states) is neutral. Record the audit table in handoff.
   - No color literals (0 hex/rgb/raw Tailwind color classes).
   - Color strictly on percentages only.
   - One hero max.
   - Type scale respected.
   - Numbers tabular.
   - All states designed.
   - No per-row animation.
   - Every interactive control focusable.
   - Dark mode fully readable.
   - Layout correct from phone to large desktop.
7. **Docs:** `.ai/briefing.md` (prepend task, keep 5), `.ai/handoff.md` (prepend entry), `docs/state/<module>_state.md` (surgical), `ui-standard.md` changelog, and **ADR-001 if affected** (section 11).
8. **Report:** files touched, any shared-module touch, decisions made, deviations, remaining items.

### Stop conditions (the loop pauses only here, or when verification fails)
- Any change to hooks, queries, RPCs, RLS, RBAC, schema, or formulas.
- Any edit to an existing shared component with consumers outside the current module (list consumers first).
- Any edit or rename of an existing `globals.css` variable.
- Any layout-level or route-level change outside the Final loop.
- Percentage thresholds that are missing or conflicting in code.
- A screen that cannot meet the standard without changing behavior.
- A conflict between the standard and an ADR-001 invariant.

## 11. Repo rules (unchanged)

- Work on `main` only. Do not create a branch unless Ohm writes "create a branch". If the session ends up on its own branch (cloud isolation), report it. Do not merge, push, or delete; Ohm verifies and merges.
- No full-repo scans; read only what the loop needs.
- Smoke test block applies to any DB-touching work. None is expected here.
- **ADR-001 (`.ai/architecture_locks/ADR-001-ohmployee-system-architecture.md`):** load only the relevant module section(s). If a loop changes something the ADR describes (shared layout, shared components other modules depend on, cross-module invariants, module behavior), update only the affected section(s) and add a Changelog entry in the same loop. Do not copy `ui-standard.md` content into the ADR; add a short pointer to it under Core Cross-Module Invariants in Loop 1. If the standard conflicts with an ADR invariant, stop (section 10).
- Documentation: state files hold current stable behavior only; no duplicated architecture text; archive obsolete logs.

## 12. Decided by Claude Code in Loop 0 (log each in the audit)

- Modal/drawer: unify vs wrap existing components.
- Final module rollout order.
- Where the motion-level setting lives, and its default.
- Exact brand-blue mapping for hero (light/dark).
- Table density approach for the largest tables.
- Whether any existing library should be kept or removed.
- Final breakpoints and the phone navigation pattern (drawer vs bottom bar).
- Dark-mode surface and accent values (derived from the existing brand scale).

## 13. Reference material

- Static mockups (blue/neutral version to be attached): Dashboard and CENCOM Overview.
- Corbel screen recording observations (timings above) for tween, stagger, and page-enter feel.
- CENCOM pass: ohm#6c3q8wzn (Phase 1 report and approved plan).
- Superseded: ohm#9k2d4vxe (motion prompt) is **not** used; this briefing replaces it.
