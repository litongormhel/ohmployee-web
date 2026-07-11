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
| **HR Emploc `row_capabilities` Structural Gap** | RBAC / Permission-shape Mismatch | RPC Change (DB Migration) + Client Update | Resolved | **RESOLVED ON STAGING & PRODUCTION** (ohm#4qwz9tgk — 2026-07-11). Migration `20262606000020_add_hr_emploc_row_capabilities_fields` applied to PROD (`rwxelulyapjgaarlwkus`) via MCP `apply_migration` after CLI `db push` was found unworkable (see section E below). Client expects `can_tag_deficiency`, `can_assign_employee_no`, and `can_review_deletion` to show action buttons — now fully computed and returned by `list_web_hr_emplocs`/`get_web_hr_emploc_detail` on both environments, verified via live RPC calls on PROD. |

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

---

## 5. Supabase CLI / Migration Tracking Drift (ohm#4qwz9tgk — 2026-07-11)

**Finding: `supabase db push` cannot be safely used against PROD (`rwxelulyapjgaarlwkus`) in its current state.**

- This repo's local `supabase/migrations/` directory contains only 2 migration files. PROD's `supabase_migrations.schema_migrations` table has ~400 applied migrations recorded. The overwhelming majority of PROD's schema history was applied directly via MCP (`apply_migration`/`execute_sql`) and was never committed as a local migration file in this repo.
- Separately, migrations applied via MCP `apply_migration` are recorded in `schema_migrations` under an **auto-generated timestamp version**, not the migration's real filename version (e.g. `20262606000010` was recorded as `20260711025531`, `20262606000020` as `20260711034157`). This has been repaired for both of these specific migrations via `supabase migration repair --status applied <version> --linked`, but the same mis-recording will recur for any future migration applied via MCP.
- Live-tested: running `supabase db push --linked --yes` on PROD fails immediately, and the CLI's own suggested remediation is to mark ~400 production migration versions as "reverted" via `migration repair` — which is unsafe to act on blindly and was not executed.
- **Recommendation**: before relying on CLI `db push` for PROD again, run a dedicated reconciliation task — likely `supabase db pull` against PROD to regenerate a complete local migration baseline, or a deliberate one-time backfill of missing local migration files matching PROD's actual history.

---

## 6. Migration Gap Classification & Reconciliation Plan (ohm#3wpx7ldk — 2026-07-11, READ-ONLY) — **FULLY RESOLVED**

Full-shape investigation of the gap identified in Section 5, cross-referenced against the mobile repo (`D:/Projects/OHMployee/supabase/migrations/`). **No files were copied, no tracking rows were touched, no CLI/db commands were run.**

**UPDATE (ohm#6ynv2crx — 2026-07-11): Category-(a) backfill COMPLETE.** The 443 category-(a) files (Section B below) were bulk-copied verbatim from the mobile repo into `ohmployee-web/supabase/migrations/`. Re-verification at copy time reconfirmed the same 443/0/0 split (no drift since this investigation). Byte-for-byte checksum comparison confirmed all 443 copies are identical to source; local file count is now 445 (2 pre-existing web-specific + 443 backfilled). Local migration history is now aligned with PROD's `schema_migrations` for these versions.

**UPDATE (ohm#5jhq8mwv — 2026-07-11): Backfill committed.** The 443 newly backfilled migration files are now committed (git-tracked) under the `finish.js` gate script, ensuring a clean staging environment and repository baseline alignment going forward.

**UPDATE (ohm#9frm5ktz — 2026-07-11): Repair-artifact tracking cleanup COMPLETE.** The 2 stale timestamp-keyed rows (`20260711025531`, `20260711034157`) flagged in Section D were deleted from PROD's `supabase_migrations.schema_migrations` under the PROD Push Gate (fresh passphrase confirmed). Re-query before the delete matched Section D's recorded state exactly (no drift). Post-delete verification confirms exactly 2 rows remain for these migrations (`20262606000010`, `20262606000020`), both correctly keyed. **Both halves of this section's reconciliation plan (backfill + tracking cleanup) are now complete — no outstanding work in Section 6.**

### A. Numeric breakdown

| Bucket | Count |
| :--- | :--- |
| PROD `schema_migrations` rows (total, via MCP `list_migrations`) | 447 |
| Web repo local migration files | 2 |
| Mobile repo local migration files (real `.sql`, excludes reports/legacy folder) | 448 |
| **Category (a)** — missing from web, present in mobile by version, **name matches exactly** | **443** |
| **Category (b)** — missing from web AND mobile (true orphan, needs reconstruction) | **0** |
| Duplicate/stale tracking-only rows (repair artifacts, not real migrations — see D) | 2 |
| Already present locally in web (the 010/020 fixes pushed in ohm#4qwz9tgk/#5tmy2rzk/#7bxk1nte) | 2 |
| 447 total = 2 (already local) + 443 (cat a) + 2 (repair-artifact dupes) | ✓ reconciles |

**Category (c) "unclear/needs individual review": 0.** Every non-local PROD version resolved cleanly into (a) or the repair-artifact bucket — no ambiguous cases.

### B. Category (a) — 443 migrations: safe to bulk-copy from mobile repo

- **Version-to-filename match**: 100% — every one of the 443 mobile filenames' version prefix matches a PROD `schema_migrations.version` exactly.
- **Name match**: 100% — cross-checked the mobile filename's descriptive suffix (after the version prefix) against PROD's recorded `name` column for all 443. **Zero mismatches.** No case where a web-relevant migration was applied under one name/timestamp while mobile's file for that version contains different content.
- **Collision check**: No duplicate version prefixes exist among the 443 mobile files (only the 5 non-migration housekeeping files — `_fn_consolidated.json`, `_fn_drift_report.json`, `_fn_drift_report_v2.json`, `_fn_inventory_raw.json`, and the `_legacy_unversioned/` folder — fall outside the version-prefix scheme, and none of them collide with a real version either).
- **The 2 web-local migrations do not exist in mobile's repo at all** (`20262606000010_fix_vw_vacancy_detail_missing_columns`, `20262606000020_add_hr_emploc_row_capabilities_fields` — confirmed via direct `diff`, files not found on the mobile side). This is expected and correct: those two are web-specific RPC/view fixes authored directly in this repo, applied to STAGING via CLI and PROD via MCP fallback. Copying mobile's 443 files creates **no collision** with these two.
- **Risk level: LOW.** This is a straight file copy of already-PROD-applied SQL with a 1:1 verified version+name match. No re-execution occurs from copying files alone — `schema_migrations` already marks these versions as applied, so a subsequent `supabase migration list --linked` would show them as in-sync rather than pending.

### C. Category (b) — 0 true orphans

None. Every PROD migration not already local to the web repo was traced to an exact mobile-repo file. There is no schema history that exists **only** as raw PROD state with no source-controlled origin anywhere.

Note: the mobile repo's `_legacy_unversioned/` folder holds 54 pre-2026-05-20 migration files (`20260428_...` through `20260526120000_...`) that predate PROD's earliest `schema_migrations` row (`20260520012746`). These are not part of the 447-row gap (PROD's tracking table doesn't reach back that far — consistent with a baseline/history reset that already happened on the mobile side, evidenced by `_legacy_unversioned/schema_migrations_snapshot_20260506.csv` and `repair_history.sh` present in that folder). This predates and is unrelated to the web repo's gap; flagged for awareness only, not actionable here.

### D. Repair-artifact duplicate tracking rows (new finding, not in original ~400 estimate)

Direct query of `supabase_migrations.schema_migrations` on PROD shows **4 rows**, not 2, for the 010/020 work described in Section 5 and `ohm#4qwz9tgk`:

| version | name |
| :--- | :--- |
| `20260711025531` | `20262606000010_fix_vw_vacancy_detail_missing_columns` |
| `20260711034157` | `20262606000020_add_hr_emploc_row_capabilities_fields` |
| `20262606000010` | `fix_vw_vacancy_detail_missing_columns` |
| `20262606000020` | `add_hr_emploc_row_capabilities_fields` |

`supabase migration repair --status applied <version> --linked` **inserted a new row for the correct version** rather than renaming/replacing the original auto-generated-timestamp row. The two mis-recorded rows (`20260711025531`, `20260711034157`) were never removed — they're now stale duplicate bookkeeping entries, not real orphaned migrations (their SQL content is identical to `20262606000010`/`20262606000020`, already present locally). Low risk as-is (CLI already treats the versioned entries as authoritative going forward), but any future reconciliation pass should decide whether to delete the two stale timestamp-keyed rows from `schema_migrations` to avoid confusing future `migration list --linked` output. **Not touched in this investigation** — flagged only.

### E. Proposed reconciliation plan (NOT EXECUTED — plan only)

1. **Bulk-copy step (safe to automate, low risk)**: Copy all 443 category-(a) `.sql` files from `D:/Projects/OHMployee/supabase/migrations/` into `D:/Projects/ohmployee-web/supabase/migrations/`, verbatim, preserving filenames. No SQL re-execution needed — PROD already has these applied; this only backfills the local source-of-truth folder.
2. **Post-copy verification (automate)**: Run `supabase migration list --linked` (read-only comparison) against PROD from the web repo afterward to confirm all versions now show as "in sync" — this is a dry-run comparison, not a mutating command, and validates the copy without pushing anything.
3. **Repair-artifact cleanup decision (manual review, separate scoped prompt)**: Decide whether to `DELETE` the 2 stale timestamp-keyed rows (`20260711025531`, `20260711034157`) from `schema_migrations` on PROD. This is a tracking-table mutation against PROD and must go through the PROD Push Gate (passphrase confirmation) in its own dedicated prompt — not bundled with the read-only file copy.
4. **Guard against recurrence**: Any future MCP `apply_migration` call will keep mis-recording versions the same way (per Section 5). Until that's addressed procedurally (e.g., always following an MCP apply with an immediate `migration repair --status applied <real-version>`), each new PROD push via MCP will need the same repair step, and the resulting stale-row pattern from D will recur.

### F. Is `supabase db pull` the right tool? — No, recommend the surgical approach instead

- **`supabase db pull` against PROD is NOT recommended.** It regenerates migration files from PROD's *current live schema state*, not from the original per-migration SQL history. Given migration `20262606000010` contains a `DROP VIEW ... CASCADE` (per `ohm#4qwz9tgk`'s finding that this could cascade-drop objects added by later, unrelated migrations depending on `vw_vacancy_detail`), a `db pull`-generated single "current state" snapshot would obscure that history and make future incremental changes harder to reason about — it collapses 447 discrete, reviewable changes into one large undifferentiated file.
- **The surgical approach (bulk file copy from mobile + targeted tracking-row cleanup, per plan above) is safer** because: (1) it preserves the real, already-reviewed incremental history rather than flattening it, (2) the version+name match was verified 100% clean with zero collisions, so there's no risk of the copy introducing content that diverges from what's actually applied on PROD, and (3) it doesn't touch `schema_migrations` at all for the 443 files (they're already correctly tracked under their real versions) — only the 2 repair-artifact rows need a deliberate, separately-gated cleanup.
- **Net recommendation**: file-copy backfill (step 1 above) can be automated immediately with low risk since it's local-file-only; the `schema_migrations` cleanup (step 3) needs its own PROD-gated prompt.

---

## 7. Remote Synchronization & Tooling Ignore (ohm#2vbn6xkq — 2026-07-11)
- **.gitignore updated**: Added `.claude/` and `supabase/.temp/` to ignore IDE/agent specific files and temporary Supabase files.
- **Remote Sync**: Pushed local commits to `origin/main` (branch up to date).


