# Web Target State & Routing Context

## 1. Environment Split (Staging vs. Production)

To harden security and manage environment risks, the web application separates development/staging and production workflows.

- **Staging Environment**:
  - Supabase Project Ref: `qqiiznmqxfoamqytjica`
  - Local configuration source: `.env.staging` (copied dynamically to `.env` at build/run time)
- **Production Environment**:
  - Supabase Project Ref: `rwxelulyapjgaarlwkus`
  - Local configuration source: `.env.prod` (copied dynamically to `.env` at build/run time)
- **Dynamic Switcher**:
  - Managed via `scripts/switch-env.js` (e.g. `node scripts/switch-env.js staging`).
  - Integrated directly into the `package.json` scripts:
    - `dev`: runs staging and starts development server.
    - `dev:prod`: runs prod and starts development server.
    - `build`: runs staging build.
    - `build:prod`: runs prod build.
- **Fail-Safe Fallback**:
  - `src/lib/supabase/client.ts` falls back to staging URL and anon keys during local development if environment variables are not found, preventing boot failures.

---

## 2. Plantilla UI Current-State Findings (ohm#5r9k2vqp)

This section documents the read-only audit of the Plantilla module UI in the web application prior to scoping any mobile card-parity redesign.

### A. Roster & Table Layouts
- **File Location**: The primary page component is at [page.tsx](file:///d:/Projects/ohmployee-web/src/app/(dashboard)/plantilla/page.tsx).
- **Component Breakdown**:
  - `PlantillaPage`: Orchestrates state, queries, layout, and filter toolbar.
  - `EmployeeTable`: Renders a dense tabular list of active employees.
  - `StoreTable`: Renders a dense tabular list of store staffing levels and capacities.
  - `PlantillaDetailDrawer` (located in [PlantillaDetailDrawer.tsx](file:///d:/Projects/ohmployee-web/src/components/plantilla/PlantillaDetailDrawer.tsx)): Renders detailed employee info inside a slide-over drawer from the right.
- **Display Pattern**: Spreadsheet-based dense tables (`min-w-[1120px]`) rather than cards. No card layouts exist in the current page list.

### B. Tab Structure Comparison (updated ohm#8vt3nkrq — 2026-07-11)
- **Mobile Pattern**: Mirrors a 3-tab layout: "Active", "Vacancy", "Inactive".
- **Current Web Structure**: 3-way segmented toggle: "Employee View" (active only), "Inactive" (new), "Store Staffing". Web stays table-based — no card layout was adopted from mobile, only the structural Active/Inactive data-split pattern.
- **Gaps/Parity Details**:
  - **Active tab**: "Employee View" now shows only active employees — `list_web_plantilla_employees` is called with `p_active_state = 'active'` (RPC-level filter, already existed, just wasn't wired). Previously mixed all statuses together.
  - **No Vacancy tab**: Unchanged — Vacancies on web are managed in a completely separate `/vacancy` route rather than a sub-tab within Plantilla.
  - **Inactive tab (resolved)**: Web now has a dedicated "Inactive" view (`p_active_state = 'inactive'`), reusing `EmployeeTable`/the same query hook with a different `activeState` param — not a separate RPC or component tree. Rows are fully clickable (detail drawer opens, read-only), matching mobile's confirmed Inactive-tab behavior — not disabled. The old `opacity-65` / `pointer-events-none` / line-through dimming in Employee View was removed as dead code now that inactive rows never land there.
  - **Status/filter logic**: Inactive = `plantilla.status`/`deactivated_at`/`date_of_separation` matching mobile's inactive vocabulary (`inactive, deactivated, resigned, separated, endo, terminated`), computed server-side in the RPC's `is_active`/`is_inactive` columns — same semantics mobile's `_paginateAccountQuery` inactive branch uses, not reinvented client-side.
  - **Pre-existing bug fixed in the same pass**: `normalizeEmployeeListRow` (`src/lib/queries/plantilla.ts`) was reading RPC field names (`plantilla_status`, `assignment_type`, `covered_stores_count`, `date_deployed`) that don't exist on the actual deployed `list_web_plantilla_employees` function on either environment — Status badge was always blank in prod before this fix. Corrected via fallback to the real column names (`status`, `deployment_type`, `roving_store_count`, `date_hired`). `plantillaType` (Budgeted/AH) and `baseRateMasked`/`slaBreached` still have no backing RPC column at all — flagged, not fixed (out of this task's visible-column scope).

### C. Multi-Store / Cluster-Group Handling
- **List View**: Multi-store/roving employees are shown under the Assignment column as `Roving (N)` (where N is the covered stores count). No store chips or interactive navigation are available in the table.
- **Detail Drawer**: The "Assignment Coverage" section renders the list of stores loaded from the `coveredStores` array in the `get_web_plantilla_detail` response.
- **Gaps/Parity Details**:
  - Web currently only has read-only lists and lacks the interactive "store-chip navigation" or multi-store scheduling features.

### D. Supabase RPC Field Audit (`get_web_plantilla_detail`)
- **Supported Fields**:
  - Names & Identifiers: `employee_no`, `first_name`, `last_name`, `position_title`.
  - Deployment: `account_name`, `primary_store_name`, `assignment_type`, `plantilla_type`, `plantilla_status`, `date_deployed`, `tenure_description`.
  - Details & PII (masked): `base_rate_masked`, `contact_number`, `email_address`, `residential_address`, `government_ids` JSON.
  - Offboarding: `clearance_status`, `clearance_checklist` JSON, `clearance_documents` JSON.
  - Alerting & SLA: `sla_elapsed_hours`, `sla_breached`, `active_movement_req` JSON, `audit_timeline` JSON.
- **Gaps for Redesign**:
  - **Initials/Avatar Source**: The RPCs return `first_name` and `last_name` (or `employee_name` in lists), which is sufficient to derive initials locally. However, there is no `avatar_url` returned. If a custom profile picture/avatar is needed, the RPCs must be updated.
  - **Badge Fields**: Status badges are fully supported via `plantilla_status`, `plantilla_type`, and `sla_breached`. Specialized compliance or HRCO badges would need to be added to the payload if required.
  - **Store List in List View**: The list RPC `list_web_plantilla_employees` returns `covered_stores_count` (integer) but NOT the full list of covered stores. If we need to render store chips on list cards/rows, the list RPC would require a backend schema update to return the JSONB array of covered stores.

### E. Design Tokens & Styling
- **CSS Architecture**: Exposes semantic surface, text, border, table-specific, and status tokens under `@theme inline` in [globals.css](file:///d:/Projects/ohmployee-web/src/app/globals.css).
- **Typography & Font Divergence**:
  - Blueprints in `docs/state/web_design_tokens.md` specify DM Sans and DM Mono.
  - However, [globals.css](file:///d:/Projects/ohmployee-web/src/app/globals.css) maps fonts to:
    - `--font-sans: Arial, Helvetica, sans-serif;`
    - `--font-mono: "SFMono-Regular", Consolas, "Liberation Mono", monospace;`
  - Standard system fallbacks are used; the project currently diverges by not loading the DM font families.

---

## 3. Vacancy RPC Failure (PROD) Diagnosis (ohm#2fh6xrqw — 2026-07-11)

### A. Symptom Analysis
- **Observed Behavior**: All 4 summary KPI cards display "Retryable summary error" and the vacancy list table renders "Vacancy data unavailable — The vacancy RPC request failed."
- **Root Cause**: A mismatch between the client-side call signature and the server-side RPC signature in Postgres.
  - The client query layer [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts) calls `list_web_vacancies` and `get_web_vacancy_summary` using a wrapped parameter shape: `{ p_queue, p_search, p_filters }`.
  - However, both the Staging (`qqiiznmqxfoamqytjica`) and PROD (`rwxelulyapjgaarlwkus`) databases expose these functions with flat parameter lists (e.g., `p_status`, `p_account_id`, `p_group_id`, etc.).
  - This mismatch results in a Postgres `42883: function does not exist` error, causing the React Query call to fail.

### B. Summary of Additional Mismatches & Internal Database Bugs
- **`list_web_vacancies` Sort Mismatch**: The frontend passes `p_sort` (which gets resolved to `"aging_days"`), but the database function expects `p_sort_by`.
- **`get_web_vacancy_detail` Runtime Bug**: Directly calling this RPC raises `ERROR: 42703: column vd.store_branch does not exist`. The DB function attempts to select `vd.store_branch` and `vd.province` from the view `public.vw_vacancy_detail vd`, but these columns are not projected by the view (they are missing from the SELECT clause of `vw_vacancy_detail` definition on both environments).
- **Field Normalization Divergences**:
  - `urgencyLevel` reads `row.urgency_level`, but the database returns `urgency`.
  - `rowCapabilities` reads `can_request_closure`, but the database returns `can_request_closure_hint`.
  - `activeApplicantsList` reads `row.active_applicants_list`, but the database returns `pipeline_summary`.
  - KPI counts (e.g., `open`, `pendingReview`, `agingWatch`) look for fields like `open_count` or `open`, but the database returns `total_open`, and entirely lacks some counters.

### C. Wider Scope (HR Emploc Mismatches)
- Similar field normalization mismatches were detected in [hr_emploc.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts):
  - `normalizeSummary` expects `total_pending`, `action_needed`, `ready_to_deploy` but the database exposes `pending_count`, `correction_count`, `ready_count`.
  - `normalizeDetailRow` expects `uploaded_attachments` and `audit_logs_timeline` but the database exposes `correction_attachments` and `timeline`.
  - `normalizeListRow` expects `sla_elapsed_days` but the database exposes `aging_days`.

### D. Client-Side Fix Status (ohm#6dq9wshl — 2026-07-11)

**RESOLVED (client-side, staging-verified):** All parameter-shape and field-normalization mismatches in sections A–C above are fixed in [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts) and [hr_emploc.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts). `getVacancyRpcFilters`/`listVacancies`/`getVacancySummary` now send the flat parameter set (`p_status, p_account_id, p_group_id, p_position, p_urgency, p_search, p_vacant_from, p_vacant_to`, plus `p_aging_bucket/p_limit/p_offset/p_sort_by/p_sort_dir` for the list RPC). `p_sort` renamed to `p_sort_by`. All named normalizer field renames applied, plus additional HR Emploc attachment/timeline/deletion-request sub-object field mismatches discovered and fixed during re-verification (see `.ai/handoff.md` for the full list). Verified against live staging RPC calls (both summary and list, for vacancy and HR Emploc) with a simulated authenticated session — all four RPCs return successfully and normalizer output matches actual columns. `pnpm build` passes clean.

**RESOLVED ON STAGING & PRODUCTION (DB Migration applied and verified):**
- `get_web_vacancy_detail` `store_branch`/`province` bug (section B) — view `vw_vacancy_detail` has `store_branch` and `province` added to its SELECT projection, and runtime `source_channel` column reference compiled successfully. Migration `20262606000010_fix_vw_vacancy_detail_missing_columns` is applied and verified on both STAGING (`qqiiznmqxfoamqytjica`) and PRODUCTION (`rwxelulyapjgaarlwkus`).

**DEEP INVESTIGATION FINDINGS (ohm#9plk4jzc — 2026-07-11):**

| Item / Gap | Root Cause Classification | Fix Type | Risk Level | Details & Impact |
| :--- | :--- | :--- | :--- | :--- |
| **Vacancy Aging-Bucket Mismatch** | Taxonomy Disagreement | RPC Change (DB Migration) | Functionally Broken (Medium) | The client UI expects `advance`, `1_15`, `16_30`, `31_60`, `61_120`, `gt121`. The DB RPCs hardcode `0_7`, `8_14`, `15_30`, `31_plus`, `unknown`. Direct string equality check causes the filter to silently return 0 rows. Fix requires using canonical `public.fn_cencom_td_aging_bucket` in the RPCs. |
| **Missing Pipeline-Status Parameter** | Missing DB Capability / Dead UI Control | RPC Change (DB Migration) + Client Update | Functionally Broken (Medium) | The "Pipeline status" dropdown filter is dead in the UI because the DB list and summary RPCs lack a corresponding `p_pipeline_status` parameter. |
| **Omitted / Missing Columns in RPC Output** | Missing DB Projection / Dead UI Columns | RPC Change (DB Migration) + Client Alignment | Cosmetic / Minor (Low) | View-backing fields like `active_applicant_count`, `confirmed_onboard_count`, `has_recent_hire`, `has_pending_closure`, and `closure_request_status` exist in the view but are omitted from RPC projections. `department` does not exist in the DB schema at all. `pending_review` is missing from the summary RPC. |
| **HR Emploc `row_capabilities` Structural Gap** | RBAC / Permission-shape Mismatch | RPC Change (DB Migration) + Client Update | Blocking Workflow (High) | **RESOLVED ON STAGING** (Migration applied and verified). Client expects `can_tag_deficiency`, `can_assign_employee_no`, and `can_review_deletion` to show action buttons. Now fully computed and returned by the RPCs. **PRODUCTION pending.** |

*Note: HR Emploc `coveredStoresCount` on list rows is also omitted from `list_web_hr_emplocs` RPC projection (only returned by the detail RPC), resolving as 0 in list view.*

---

## 4. Git Workflow & Environment Safety Commit Gate (ohm#8kfq3wzn — 2026-07-11)

To protect the shared production environment and streamline repository sync tasks across team boundaries, `ohmployee-web` implements a customized Git Commit gate.

### A. Git Status Auditing
- **Audited Commit Split**: The accumulated changes from prior sprint tasks have been audited and committed separately along task-boundary commits. The working directory is now synchronized with standard prompt IDs.

### B. scripts/finish.js Orchestration Gate
- **Location**: [finish.js](file:///D:/Projects/OHMployee-web/scripts/finish.js)
- **Execution Shortcut**: Wired under `finish` script in `package.json` (`npm run finish` or `pnpm finish`).
- **Environment Detection**:
  - Automatically parses `.env` looking for `NEXT_PUBLIC_SUPABASE_URL`.
  - Maps URL subdomains to Supabase Project Refs:
    - `STAGING`: `qqiiznmqxfoamqytjica`
    - `PRODUCTION`: `rwxelulyapjgaarlwkus`
    - `UNRESOLVED`: fallback state for missing files, invalid URLs, or unrecognized subdomains.
- **Safety Semantics**:
  - **STAGING Target**: The script executes an automatic git commit. It auto-stages modifications/deletions and checks untracked files against the user-provided `OHM_SCOPE_FILES` list (Group A vs. Group B classification) to prevent accidental staging.
  - **PRODUCTION / UNRESOLVED Target**: Auto-commit is blocked. The script halts, prints an environment warning, and requires the operator to manually type the confirmation phrase `CONFIRM-PROD` to allow the commit to proceed. Mismatching or empty inputs abort the commit.


