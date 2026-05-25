# AI Handoff

## Current Workflow

- Keep Next.js App Router route files in `src/app/**`.
- Keep reusable presentation components in `src/components/**`.
- Keep shared clients, providers, query contracts, and future server/client utilities in `src/lib/**`.
- Keep thin-client behavior: UI may call lightweight client helpers, but business rules, RBAC, RLS, and data integrity belong in Supabase.
- Keep the admin shell scaffold in the dashboard route group and source navigation from `src/lib/modules.ts`.
- Use `src/components/ModuleEmptyState.tsx` for scaffold-only module pages until real contracts are approved.

## Foundation Notes

- Supabase browser client setup exists at `src/lib/supabase/client.ts`.
- React Query is mounted through `src/app/providers.tsx` from the root layout.
- The dashboard shell provides a persistent desktop sidebar, topbar, responsive mobile module strip, active-route styling, and constrained main content container.
- `src/components/DashboardAuthShell.tsx` now owns the lightweight client-side dashboard guard and current-user context load from `get_web_current_user_context`.
- `src/lib/auth.ts` defines the RPC-backed current-user context, blocked-access states, and fail-closed module visibility helper.
- `src/lib/modules.ts` includes stable module keys for future backend capability mapping.
- Most module routes are placeholders only; do not add business logic until Supabase contracts and RLS are defined. Vacancy is the first read-only RPC-backed module surface.
- Root `/` redirects to `/dashboard` as the web app foundation entry point.

## Auth/RBAC Handoff

- Auth/RBAC architecture is documented in `docs/state/web_auth_rbac_state.md`.
- Dashboard route-group auth guarding is implemented through the client auth shell because the project currently has `@supabase/supabase-js` only; no SSR cookie adapter is installed.
- The temporary Supabase Auth-only context has been replaced with a call to `supabase.rpc("get_web_current_user_context")`.
- The shell renders only when `access_status === "allowed"`; missing sessions still redirect to `/login`.
- Missing profile, inactive/disabled account, unauthorized web role, RPC failure, missing module arrays, and malformed capabilities block the shell.
- Module visibility uses `src/lib/modules.ts` plus backend `allowed_module_keys`; `module_capabilities` is presentation-only metadata for sidebar/topbar display.
- Frontend role checks are display/navigation only. Backend RLS/RPC policies remain the authority for all data access, mutations, scopes, and workflow rules.
- Do not invent web-only roles; mirror Mobile role, group scope, and account scope semantics from Supabase.

## Backend Contract Handoff

- This repo currently has no local `supabase/migrations` directory.
- Backend implementation should happen in the authoritative Supabase migration workflow, or after adding an approved migration directory to this repo.
- Required canonical contract for the current frontend: `public.get_web_current_user_context()` RPC.
- Optional read contract: `public.web_current_user_context` as a `security_invoker = true` view once the RPC is safe.
- The context must include current Auth user id, safe full name/email, existing Mobile role key/name, `access_status`, group scope, account scope, `allowed_module_keys`, and `module_capabilities`.
- The contract must derive identity from `auth.uid()`, not caller arguments, and must not expose service-role data.
- Fail closed for unauthenticated, missing-profile, inactive, disabled, and unauthorized-web cases.
- See the `OHM2026_1072-IMPL-1` prompt in `docs/state/web_auth_rbac_state.md` for the exact migration/RPC/view implementation brief.

## Vacancy Web Handoff

- Vacancy Web architecture is documented in `docs/state/vacancy_web_state.md`.
- Current Vacancy implementation is a client desktop admin command center with a compact header, RPC-backed KPI cards, status tabs, submitted search, pipeline/aging/urgency/vacant-date filters, dense read-only table rows spanning full-screen width, pagination, loading/empty/error/blocked states, and a right-side sliding overlay drawer that renders complete vacancy detail contexts.
- The Vacancy page integrates `get_web_vacancy_summary(...)`, `list_web_vacancies(...)`, and `get_web_vacancy_detail(p_vacancy_id uuid)` queries through `src/lib/queries/vacancy.ts`.
- Vacancy list/summary payloads use the backend-authoritative `p_queue`, `p_search`, `p_filters`, `p_sort`, `p_sort_dir`, `p_limit`, and `p_offset` contract. The frontend allowlists queue values, aging buckets, pipeline statuses, urgency levels, vacant-date filters, and supported sort fields before sending RPC arguments; unsupported filters are dropped instead of leaking into `p_filters`.
- Vacancy list/detail rows use the RPC field name `position_title` end-to-end in the frontend item contract, table, and detail drawer.
- Do not add raw table queries, caller-controlled role/scope parameters, fake data, CRUD, or mutations.
- Target UX is a desktop admin command center: KPI summary row, status tabs, filter/search toolbar, dense full-width table, sliding right-side detail drawer, candidate summary listing (shielded PII), audit timeline, and capability-controlled action area.
- Web must mirror Mobile vacancy business rules and status transitions, but present them in a dense admin-panel workflow rather than Mobile cards.
- `OHM2026_1077` and `OHM2026_1082` define the backend read-contract architecture for Vacancy Web. The recommended Supabase migration creates `public.list_web_vacancies(...)` for dense list rows, `public.get_web_vacancy_summary(...)` for KPI counts, and `public.get_web_vacancy_detail(p_vacancy_id uuid)` for the selected vacancy's detail drawer context.
- The Vacancy Detail contract must reuse existing Mobile semantics from `vw_vacancy_detail`, `fn_is_active_vacancy_applicant_status`, and existing RBAC/scope helpers. It enforces strict access controls using the caller's `auth.uid()`, segregates list-only vs. detail-only fields, exposes capability hints (`can_approve`, `can_update_applicant_status`, `can_request_closure`), and provides candidate sub-lists and timelines without exposing candidate contact PII (emails/phone numbers).
- Scoped reads must be enforced in Supabase from `auth.uid()` and existing RBAC/scope helpers (Super Admin/Head Admin broad access; OM/ATL/TL/HRCO/Recruitment scoped access; Viewer scoped read-only access).
- Current Vacancy UI uses backend `row_capabilities` only for presentation hints inside the drawer. Actual mutations are disabled because no action RPC contract is implemented.
- See the `OHM2026_1077-IMPL-1` and `OHM2026_1082-IMPL-1` prompts in `docs/state/vacancy_web_state.md` for the exact Supabase migration implementation briefs.

## Shared Web UI System Handoff

- **Design System Blueprint**: Documented completely in `docs/state/web_ui_system_state.md`. Defines the core architecture for extracting consistent, reusable, desktop-first administrative layout structures.
- **Audited Visual Patterns**: Audited KPI metric cards, dense scrolling grids, search-and-filter bars, status badges, details drawers, access-denied RLS boundaries, network retry elements, loading skeletons, and capability action lists.
- **Shared Primitives & Layouts**: Implementation is complete for Phase 2 low-risk primitives:
  - `AdminPageHeader` (`src/components/shared/AdminPageHeader.tsx`): Reusable header with read-only badge indicator and custom administrative button actions.
  - `MetricCard` (`src/components/shared/MetricCard.tsx`): Centralized KPI item supporting blank state indicators, loading behaviors, error/retry states, and blocked-access overrides.
  - `DataState` (`src/components/shared/DataState.tsx`): Single-point presenter for data states (loading spinner, custom empty records, lock-shield access denied block, warning alert card with retry triggers).
  - `StatusBadge` (`src/components/ui/StatusBadge.tsx`): Consistent mapping of raw backend strings to tailored HSL variant color schemes, safely wrapping/extending basic badges.
- **Shared Primitives & Layouts**: Implementation is complete for both Phase 2 primitives and Phase 3 structural containers:
  - `AdminPageHeader` (`src/components/shared/AdminPageHeader.tsx`): Reusable header with read-only badge indicator and custom administrative button actions.
  - `MetricCard` (`src/components/shared/MetricCard.tsx`): Centralized KPI item supporting blank state indicators, loading behaviors, error/retry states, and blocked-access overrides.
  - `DataState` (`src/components/shared/DataState.tsx`): Single-point presenter for data states (loading spinner, custom empty records, lock-shield access denied block, warning alert card with retry triggers).
  - `StatusBadge` (`src/components/ui/StatusBadge.tsx`): Consistent mapping of raw backend strings to HSL variant styles, safely wrapping/extending basic badges.
  - `DetailDrawer` (`src/components/shared/DetailDrawer.tsx`): Reusable slide-over aside drawer that locks body scroll, listens to ESC keys, dim overlay, and accepts dynamic header badge/slots.
  - `AdminFilterBar` (`src/components/shared/AdminFilterBar.tsx`): Modular form panel container featuring standard search bars and supporting modular selects or action buttons via children slots.
  - `CapabilityActionBar` (`src/components/shared/CapabilityActionBar.tsx`): Locked administrative capability bars displaying indicator badges showing available or unexposed states.
- **Domain Boundaries**: Column definitions, raw database statuses, query RPC bindings, candidate detail PII blocks, and custom log events must remain module-specific to avoid layout dilution or scope leaks.
- **Extraction Roadmap**: Structured in 5 clear phases (Docs [Done] -> Low-risk primitives [Done] -> Structural layouts [Done] -> Vacancy refactoring [Done] -> HR Emploc/Plantilla deployment [Active]) to ensure safe execution.
- **Next Phase Actions**: Refer to Phase 5 in `docs/state/web_ui_system_state.md` to deploy shared structures across `HR Emploc` and `Plantilla` routes, replacing basic empty states with high-fidelity, shared UI shells.

- **Implementation Status**: The frontend read-only queue page, summary KPI metrics, compact dense grid table, and 640px sliding details drawer are fully implemented and validated (compiled cleanly in both linting and production bundling tests).
- **Security & RLS boundaries**: PII shielding is active (contact numbers/email are never rendered), and data queries strictly consume server-derived RLS scopes.
- **Workflow Action Area**: CapabilityActionBar buttons are fully mapped to dynamic permission flags returned on `rowCapabilities` (`canTagDeficiency`, `canAssignEmployeeNo`, `canMoveToPlantilla`, `canRequestDeletion`).
- **Next Phase Steps**:
  1. Approve the backend transactional mutation RPC signatures on Supabase (tagging deficiencies, entering employee IDs, transitioning plantilla directories, separator approvals).
  2. Implement React Query mutations (`useMutation`) and cache invalidation triggers on the client.

## Design Token System Handoff (OHM2026_1097)

- **Source of truth**: tokens are defined in `src/app/globals.css`; the blueprint is `docs/state/web_design_tokens.md` (§0 documents the activation/implementation details).
- **How tokens are exposed**:
  - Semantic colors (`--surface-*`, `--text-*`, `--border-*`, `--background`, `--foreground`) live as runtime `:root` variables and are bridged to Tailwind via `@theme inline`, producing utilities like `bg-surface-base`, `text-text-primary`, `text-text-secondary`, `text-text-muted`, `border-border-default`, `border-border-subtle`, `bg-surface-hover`, `bg-surface-selected`.
  - Static scales use plain `@theme`: `brand-50…700`, `status-{success,warning,danger,info,neutral}-{bg,border,text}`, `radius-*`, and `animate-drawer-in|drawer-out|fade-in`.
  - Layout/motion constants are plain `:root` custom properties used through arbitrary values: `--sidebar-width` (240px), `--topbar-height`, `--drawer-width-md|lg|xl`, `--z-base…toast`, `--space-*`, `--duration-*`.
- **Dark mode**: native via `@media (prefers-color-scheme: dark)` overriding the `:root` semantic variables. No theme toggle / class strategy is wired; add a `data-theme`/class override block in `globals.css` later if a manual switch is required.
- **What was refactored**: shared primitives only (`AdminPageHeader`, `MetricCard`, `DataState`, `DetailDrawer`, `AdminFilterBar`, `StatusBadge`). Dense module tables keep literal classes except for the targeted consistency fixes.
- **Fixes landed**: sidebar 288px→240px (`--sidebar-width`); `DetailDrawer` now slides in via `animate-drawer-in` (previously mounted at `translate-x-0` so the slide never played) and uses `--surface-overlay` + `animate-fade-in` backdrop; HR Emploc row selection/hover aligned to `bg-blue-50` / `hover:bg-gray-50`; invalid `gray-150`/`gray-850` classes replaced.
- **Guardrails honored**: no module redesign, no Plantilla implementation, no new libraries, no mutations, no unrelated module refactors. Validated with `pnpm lint` and `pnpm build`.
- **Table interior tokenization (OHM2026_1098)**: All hardcoded `bg-white`, `bg-gray-*`, `border-gray-*`, `text-gray-*`, and selected/hover row classes in `VacancyTable.tsx` and `HrEmplocTable.tsx` have been replaced with dedicated table tokens (`table-header`, `table-row`, `table-row-hover`, `table-row-selected`, `table-rule`, `table-rule-section`, `table-text`, `table-text-sub`, `table-text-muted`, `mono-pill-surface`, `mono-pill-ink`, `mono-pill-ring`). Both tables are now dark-mode readable. Pending deletion row (`bg-red-50 hover:bg-red-100`) and status badge colors (emerald, blue, red) remain as literal classes since they are intentional semantic indicators. Validated via `pnpm lint` and `pnpm build` (clean).

## Read Workflow Consistency Handoff (OHM2026_1105)

- **Audit scope**: Vacancy, HR Emploc, and Plantilla read-only modules — loading states, empty states, access denied, retryable errors, row click, drawer close, keyboard accessibility, token usage, spacing, badge consistency, KPI consistency, filter bar consistency.
- **Fixes applied**: 11 low-risk changes across 5 files. See `docs/state/web_ui_system_state.md §7` for the full table.
- **Remaining intentional inconsistencies**:
  - Drawer loading pattern: Vacancy/HR Emploc use custom pulse skeletons; Plantilla uses `DataState kind="loading"`. Skeletons are better for CLS; migrate Plantilla in a future pass.
  - Inline drawer error states in Vacancy/HR Emploc vs shared `DataState` in Plantilla. `DataState` is the preferred forward direction.
  - Tab active color `bg-blue-600` in Vacancy/HR Emploc vs `bg-brand-600` in Plantilla. Pending dedicated token migration pass for those two modules.
  - `CapabilityActionBar` hardcoded gray classes — pending dedicated token migration pass.
  - Plantilla missing footer boundary notice present in Vacancy/HR Emploc.
  - `formatDate` locale `en-PH` in Plantilla vs `en` in Vacancy/HR Emploc (intentional).
- **Validated**: `pnpm lint` clean, `pnpm build` clean.

## Web Mutation Workflow Handoff (OHM2026_1107 → OHM2026_1109 → OHM2026_1127)

- **Architecture doc**: `docs/state/web_mutation_workflow_state.md` — full spec and phase order for HR Emploc deficiency tagging as the first mutation.
- **Selected first mutation**: **HR Emploc deficiency tagging** (`Pending`/`For Review` → `For Correction`). Most reversible, lowest blast radius, zero cross-module coupling, least-privileged actor (`hrPersonnel`).
- **Deferred order**: correction review (natural second — closes the loop but is a forward gate); Vacancy closure (cross-pipeline); Plantilla deactivation (highest blast radius — archives an employee, reopens vacancy on Backout).
- **Backend contract (deployed — migration `20260607000004`)**: `public.tag_web_hr_emploc_deficiency(p_hr_emploc_id uuid, p_deficiencies jsonb, p_remarks text default null)` — `SECURITY DEFINER`, locked `search_path`, identity from `auth.uid()` only, granted to `authenticated`. One transaction: capability + scope + record-state checks → write `correction_reason` + set `hr_status='For Correction'` → insert immutable audit event → existing `trg_notify_hr_emploc_correction_tagged` fires. Returns JSONB envelope `{ ok, hr_emploc_id, new_hr_status, correction_reason, tagged_at }`.
- **Frontend wiring status (OHM2026_1109 — COMPLETE):**
  - `src/lib/queries/hr_emploc.ts`: `tagWebHrEmplocDeficiency()` wrapper calls `supabase.rpc("tag_web_hr_emploc_deficiency", ...)`. `HrEmplocDataErrorKind` extended with `"invalid_state"`. `getErrorKind` maps `P0001` → `invalid_state`, `42501` → `access_denied`. `TagDeficiencyParams` and `TagDeficiencyResult` types exported.
  - `src/components/shared/CapabilityActionBar.tsx`: button enabled when `isAvailable && !!action.onClick`; disabled otherwise (backward-compatible).
  - `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`: `isTagModalOpen` state; "Tag Deficiency" action has `onClick: () => setIsTagModalOpen(true)` gated on `canTagDeficiency && !isPendingDeletion`; `TagDeficiencyModal` sub-component with checkboxes, per-issue note inputs, remarks textarea, submitting state, inline error display. On success: invalidates `["hr-emploc-detail", hrEmplocId]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No optimistic UI.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).
- **Backend deployed:** mutation executes end-to-end.

## Second Mutation — Correction Review Handoff (OHM2026_1110 → OHM2026_1112)

- **Architecture doc**: `docs/state/web_mutation_workflow_state.md` **Part II (§10–§18)** — full backend-authoritative spec, approval-model comparison, state map, and the exact implementation prompt (OHM2026_1110-IMPL-1).
- **What it is**: the inverse of the first mutation — it *closes* the correction loop. Reviewable state is `For Review` (the state a record reaches after the HRCO resubmits corrected docs). The intermediate HRCO upload step (`For Correction`→`For Review`) is an ops/Mobile RPC and is **out of scope** for the web layer.
- **State transitions** (one RPC, `p_decision` discriminator):
  - `approve`: `For Review` → `Complete` — only when **all** `correction_reason` deficiencies are affirmed resolved; clears `correction_reason`; does **not** touch `employee_no`; audit `Correction Approved`.
  - `return`: `For Review` → `For Correction` — residual deficiencies kept as the new `correction_reason`; re-fires the HRCO correction notification; audit `Correction Returned`.
- **Backend contract (deployed — migration `20260609000000`)**: `public.review_web_hr_emploc_correction(p_hr_emploc_id uuid, p_decision text, p_resolved_keys text[] default null, p_remarks text default null)` — `SECURITY DEFINER`, locked `search_path`, identity from `auth.uid()` only, granted to `authenticated`. Returns `{ ok, hr_emploc_id, decision, new_hr_status, correction_reason, reviewed_at }`.
- **Allowed roles**: `hrPersonnel` (and `superAdmin` global override). Re-checked server-side; frontend gating is ergonomics only.
- **Capability flag**: `can_review_correction` must be present in `get_web_hr_emploc_detail` row capability payload (true only for authorized reviewers on `For Review`, non-`Pending Deletion` records). Keep distinct from `can_review_deletion` (deletion approvals) and `can_tag_deficiency` (Part I). Until this flag is in the payload, the Review Correction button will correctly remain hidden.
- **Recommended model**: **strict all-deficiencies-resolved** (partial-compliance approval rejected). Rationale: `Complete` is an irreversible forward gate to employee-number assignment / Plantilla movement, and there is no web-side path to re-open a `Complete` record (the Part I tagging RPC rejects `Complete`). The `return` path is the in-loop safety valve for partial fixes.
- **Blocked states**: non-`For Review` `hr_status`, `Pending Deletion`, `status != 'Pending Emploc'`, out-of-scope. No optimistic UI.
- **Invalidation**: `["hr-emploc-detail", id]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No Vacancy/Plantilla cache touch.
- **Error mapping**: reuses existing `getErrorKind` (`42501`→`access_denied`, `P0001`→`invalid_state`); no new error kinds needed.
- **Frontend wiring status (OHM2026_1112 — COMPLETE):**
  - `src/lib/queries/hr_emploc.ts`: `reviewWebHrEmplocCorrection()` wrapper calls `supabase.rpc("review_web_hr_emploc_correction", ...)`. `canReviewCorrection` normalized from `can_review_correction` only (canonical key; stale `can_approve_correction` alias removed). `ReviewCorrectionParams` and `ReviewCorrectionResult` types exported.
  - `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`: `isReviewModalOpen` state; "Review Correction Resubmission (HR Compliance)" action enabled when `canReviewCorrection && isForReview && !isPendingDeletion`; `ReviewCorrectionModal` sub-component with per-deficiency Resolved/Still-Deficient checkboxes, auto-derived decision, decision-preview block, optional remarks textarea, submitting state, inline error display. On success: invalidates `["hr-emploc-detail", hrEmplocId]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No optimistic UI.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

## HR Emploc Mutation Stability Audit (OHM2026_1127)

- **Scope**: audit and stabilize all existing HR Emploc mutation workflows, capability payload enforcement, invalidation consistency, audit/timeline integrity, and notification-safe frontend handling.
- **Capability enforcement fixes (OHM2026_1127)**:
  - Removed stale `can_tag_correction` alias from `canTagDeficiency` normalization — canonical key is `can_tag_deficiency`.
  - Removed stale `can_approve_correction` alias from `canReviewCorrection` normalization — canonical key is `can_review_correction`.
  - If the review correction button does not appear, confirm that `get_web_hr_emploc_detail` returns `can_review_correction: true` in the row capability payload.
- **Audit/timeline fixes (OHM2026_1127)**:
  - `HrEmplocAuditLogItem.createdAt` changed to `string | null`; normalizer no longer invents `new Date().toISOString()` for null timestamps — `formatDateTime(null)` renders `"--"`.
  - `CorrectionAttachmentItem.uploadedAt` changed to `string | null`; same fix applied.
  - `DeletionRequestItem.requestedAt` changed to `string | null`; same fix applied.
- **Render key stability (OHM2026_1127)**:
  - `auditLogsTimeline.map`: key is now `item.eventId || \`timeline-${index}\`` — prevents duplicate key crash on null/empty `event_id` payloads.
  - `uploadedAttachments.map`: key is now `file.attachmentId || \`attachment-${index}\``.
  - `coveredStores.map` in drawer: key is now `store.storeId || \`store-${index}\``.
- **Type cleanup (OHM2026_1127)**:
  - `HrEmplocDetailItem.correctionReason` changed from `Record<string, unknown> | null` to `Record<string, unknown>` — matches the normalizer, which always returns `{}` for null payloads via `asObject()`. The redundant `?? {}` in the drawer's `ReviewCorrectionModal` prop was removed.
- **Mutation safety (OHM2026_1127)**:
  - Both `TagDeficiencyModal` and `ReviewCorrectionModal`: `isPending` disables all form inputs, cancel button, submit button, and backdrop click. No optimistic UI. `setSubmitError(null)` on each retry. Modal unmounts on close so error state is discarded. No duplicate-submit paths exist.
- **Stale footer copy (OHM2026_1127)**: `page.tsx` footer disclaimer updated — no longer claims all mutations are read-only; correctly reflects deployed (tag deficiency, review correction) vs. pending (employee ID assignment, Plantilla deployment, separation requests).
- **Files changed**: `src/lib/queries/hr_emploc.ts`, `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`, `src/app/(dashboard)/hr-emploc/page.tsx`.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

## Plantilla Web Handoff

- **Target Architecture & Specification**: Fully documented in `docs/state/plantilla_web_state.md`.
- **Core Focus Areas**:
  1. **Dual Views**: Segmented View Toggle (`/plantilla`) switching between Employee-Centric (active roster listing with monospaced employee IDs, positions, primary store, status badges) and Store-Centric (staffing capacities listing targets, active budgeted/AH, vacancies, and staffing SLA health statuses).
  2. **Scoped RBAC**: RLS-enforced read restrictions based on authenticated profiles. Scoped roles (`om`, `hrco`, `atl`, `tl`) see only their allowed accounts.
  3. **PII Masking**: Strict database-level masking of sensitive contact details (phone, email, address, salary rates, government IDs) for restricted roles, returning pre-masked strings over the network.
  4. **Deactivation Overlays**: 65% opacity, dashed borders, and warning banner overlays for suspended, inactive, or separation-pending rows/profiles.
  5. **Separation Workflows**: Resignations, involuntary Terminations, Day 1 Backouts (which automatically reopen original Vacancies), and Administrative Archives backed by asset return checklists and interactive clearances.
  6. **Additional Headcount (AH)**: Tracking of seasonal, temporary headcount slots with expiration calendars and visual warning countdown indicators.
  7. **Detail Drawer**: High-density 640px overlay featuring employment/allocation details, roving coverages, separation checklists, SLA breachers, and timelines.
  8. **SLA Breach Clocks**: 48h movement SLAs and 7-day store vacancy vacancy alarm clocks.
- **Backend RPC Status**: Migrations `20260607000002` and `20260607000003` exist and are applied remotely. Implemented contracts: `list_web_plantilla_employees`, `list_web_plantilla_store_staffing`, `get_web_plantilla_summary`, and `get_web_plantilla_detail`.
- **Query Contract Status**: `src/lib/queries/plantilla.ts` is fully implemented. Exports: `getPlantillaSummary`, `listWebPlantillaEmployees`, `listWebPlantillaStoreStaffing`, `getWebPlantillaDetail`, `PlantillaDataError`, and all typed structs. Presentation helpers `deriveDeactivationOverlay`, `deriveTransferOverlay`, `deriveStaffingRisk` are pure functions that accept normalized data and return overlay hint objects — no backend calls.
- **RPC names wired**: `get_web_plantilla_summary`, `list_web_plantilla_employees`, `list_web_plantilla_store_staffing`, `get_web_plantilla_detail`. All use `auth.uid()`-derived scopes server-side; no caller-controlled role/scope params are passed from the frontend.
- **Masking contract**: backend returns pre-masked strings for `contact_number`, `email_address`, `residential_address`, `base_rate_masked`, and `government_ids` JSONB for restricted roles. The frontend never strips or applies masking itself.
- **Page Shell Status (OHM2026_1103 / OHM2026_1125)**: `src/app/(dashboard)/plantilla/page.tsx` is fully implemented as a read-only dual-view shell. `AdminPageHeader`, 4x `MetricCard` (wired to `getPlantillaSummary`), `AdminFilterBar` (segmented Employee/Store toggle + per-view filter selects), and two inline dense tables (employee roster, store staffing) are all live. DataState handles all four boundary states. `deriveDeactivationOverlay` and `deriveStaffingRisk` are applied inline. Store Staffing renders the backend-returned grouped metrics `required_headcount`, `active_headcount`, `vacancy_count`, `pipeline_count`, `staffing_gap`, `staffing_risk`, and `sla_badge`; the frontend does not recompute staffing metrics. Pagination is wired and resets on apply/reset/view switch. `pnpm lint` and `pnpm build` are clean.
- **Detail Drawer Status (OHM2026_1104)**: Fully implemented and wired in `src/components/plantilla/PlantillaDetailDrawer.tsx`. Employee rows in `page.tsx` emit `onRowClick(row.id)` to set `selectedPlantillaId` state; the drawer opens and fetches `getWebPlantillaDetail` via React Query. Dimmed rows (inactive/terminated/suspended) are non-clickable via `pointer-events-none`. Active and pending-separation rows are keyboard-accessible (`role="button"`, `tabIndex=0`, Enter/Space). Drawer close clears state. All DataState boundaries active. `deriveTransferOverlay` and `deriveDeactivationOverlay` applied to drawer body banners.
- **Plantilla Detail Validation (OHM2026_1126)**: Detail hydration now accepts `id`, `employee_id`, or `plantilla_id` from `get_web_plantilla_detail`; JSONB detail arrays (`covered_stores`, `clearance_checklist`, `clearance_documents`, `audit_timeline`) are null-safe and normalized with stable keys for duplicate/partial items. Employee detail actions now render only backend capability payload flags: `can_request_deactivation`, `can_review_deactivation`, `can_request_deletion`, `can_review_deletion`, and `can_transfer_employee`. The drawer no longer renders stale generic separation approval, roving edit, suspend toggle, or AH-request actions for employee details. Assignment coverage renders stationary primary-store rows and roving covered-store rows separately; clearance audit renders only for pending-separation rows; audit timeline dates tolerate nulls without client-invented timestamps.
- **Known gaps**:
  - `groupId` filter is present in the UI and is passed as `p_group_id` to summary, employee list, and store staffing RPCs.
  - Store staffing rows have no detail drawer yet (store-centric detail is not yet implemented).
  - No action mutations yet (Phase 5).
- **Next Phase Steps**:
  1. Keep Store Staffing backend hydration aligned with the deployed grouped metric contract before adding store-detail UX.
  2. Wire operational mutations (transfers, AH requests, separations, clearance ticks) — Phase 5.
