---
name: ohmployee-cross-repo-parity
description: >
  Enforces 100% functional, schema, RPC, View, and RBAC parity between OHMployee
  Web (d:\Projects\ohmployee-web, Next.js 16 + TypeScript) and OHMployee Mobile
  (D:\Projects\OHMployee, Flutter/Dart) backed by the shared Supabase database.
  Activate whenever adding or modifying a Supabase RPC, database view, migration,
  RBAC role/capability rule, queue/tab status lifecycle, or cross-platform
  workflow across Web and Mobile.
license: MIT
---

# OHMployee Cross-Repo Parity (`ohmployee-web` + `OHMployee` Mobile)

Both **OHMployee Web** (`d:\Projects\ohmployee-web`) and **OHMployee Mobile** (`D:\Projects\OHMployee`) run against the exact same Supabase PostgreSQL database (`qqiiznmqxfoamqytjica` on Staging, `rwxelulyapjgaarlwkus` on Production). A breaking change in a migration, RPC parameter name, view column order, or status enum immediately breaks the sibling client if parity is not enforced.

## 1. Non-Breaking Database & Migration Contract

Before authoring or editing any SQL migration in `supabase/migrations/`:

1. **Auto-Numbered Migrations Only**:
   - Always generate migration files using `npm run db:new <migration_name>` (`scripts/new-migration.mjs`).
   - This scans both Web (`d:\Projects\ohmployee-web\supabase\migrations`) and Mobile (`D:\Projects\OHMployee\supabase\migrations`) and increments the highest numeric prefix so version collisions never happen.
2. **Surgical-Diff Lock on SQL Functions (`CREATE OR REPLACE FUNCTION`)**:
   - Never rewrite an RPC or trigger function from memory or an older migration.
   - Locate the latest definition: `git grep -l "FUNCTION public.<name>" supabase/migrations/`.
   - Copy the exact latest function body and apply only the minimal surgical diff.
   - Always preserve `SET search_path = public` on `SECURITY DEFINER` functions.
3. **Default-Safe RPC Parameters (Mobile Protection Lock)**:
   - Any new parameter added to an existing RPC **MUST** have `DEFAULT NULL` (or a backward-compatible wrapper overload) so existing Mobile `.rpc('<name>', params: {...})` calls continue working without throwing `PGRST202` (function not found).
   - Never rename an existing parameter key (`p_reason`, `p_reason_code`, `p_rejection_reason`, `p_input`, etc.) unless both Web (`src/lib/queries/**/*.ts`) and Mobile (`D:\Projects\OHMployee\lib\**\*.dart`) are updated in lockstep.
4. **Append-Only Views (`WITH (security_invoker = true)`)**:
   - In `CREATE OR REPLACE VIEW`, new columns **MUST** be appended at the very end of the `SELECT` list.
   - Never drop, rename, or reorder existing columns in views (`PostgreSQL CREATE OR REPLACE VIEW` forbids changing column positions/types, and Mobile models depend on existing column names).
   - Core operational views (`vw_vacancy_list`, `v_plantilla_safe`, `vw_vacancy_detail`, `v_dashboard_hrco_breakdown`, `headcount_summary`, `vw_vacancy_requirements`) must always retain `WITH (security_invoker = true)`.

## 2. Static-to-Dynamic RPC & Column Audit Checklist

When touching any query in `src/lib/queries/*.ts` or `D:\Projects\OHMployee\lib\**\*.dart`:

1. **Cross-Repo Call-Site Grep**:
   - Search Web: `git grep "<rpc_or_view_name>" src/`
   - Search Mobile: search `D:\Projects\OHMployee\lib` for `<rpc_or_view_name>`
2. **Physical Schema Verification (`scripts/check-sql-contracts.mjs`)**:
   - Before adding joined columns in PostgREST `.select('..., stores(area_city, area_province)')`, verify the exact physical column names in `scripts/check-sql-contracts.mjs` (`PHYSICAL_TABLES`).
   - Common traps to avoid:
     - `stores` has `area_city, area_province, island_group` (NOT `area_name`).
     - `employees` has `full_name, position, store_name` (no `search_deployers` RPC).
     - `hc_request_stores` supports polymorphic new/existing store snapshots (`store_id`, `is_new_store`, `store_name`, `area_province`, `area_city`, `island_group`, `created_store_id`).
3. **No Silent Catch Guard**:
   - Never swallow Supabase/PostgREST errors in empty `catch {}` blocks.
   - On Web, always log `console.error('[PostgREST Schema Error]', error)` with the query context.

## 3. Shared Lifecycle & Status Queue Invariants

Keep status tabs, badges, and capabilities aligned across both platforms:

| Module | Canonical Queues / Tabs | Core Parity Rule |
|---|---|---|
| **HR Emploc** | `Pending`, `For Emploc`, `Correction`, `Review`, `Deployed` | 5-queue lifecycle (`hr_status`). `Upload Docs` restricted to `Pending` and `For Correction`. `Add Emploc` on `For Emploc` (with SA override on `Pending`). |
| **Plantilla** | `Active`, `On-Leave`, `Vacancy`, `Floating`, `Deactivation`, `Inactive` | `fn_set_slot_status` is sole slot authority. `hired_count` derives strictly from `plantilla.status = 'Active'`. `Inactive` tab persists separated staff (`Resigned`, `AWOL`, `Terminated`). Floating tracks 180-day DOLE Art. 301 compliance and transitions to `Active` + `Stationary` upon store assignment. |
| **Vacancy** | `Open`, `Pipeline`, `Filled`, `Pending Requests`, `Archival` | Pipeline tab operates on candidate-level granularity (1 row = 1 applicant / per tao). Coverage Group (`CGCode`) consolidates member stores into 1 row in `/vacancy` but keeps 1:1 per-store rows in `/plantilla` Vacancy tab ($1/N$ fractional slot). |
| **RBAC (11 Roles)** | `Super Admin (100)`, `Head Admin (90)`, `OM (70)`, `HRCO (45)`, `ATL (42)`, `TL (41)`, `Encoder (30)`, `HR Personnel (25)`, `Recruitment (20)`, `Backoffice (15)`, `Viewer (10)` | Head Admin has administrative immunity on operational actions except the 4 SA-only actions (`Archive / Soft-Delete User Account`, `Terminate Active User Sessions`, `Toggle System Edit Lock`, `Manage Permission Matrix Overrides`) and `/rbac` route. |
| **OHMni Copilot** | Web `/api/ohmni` (`OhmniDrawer.tsx`) & Mobile `ohmni_service.dart` (`ohmni_chat_screen.dart`) | Shared tool definitions, active screen context pills, role-adaptive starter prompts, interactive action draft cards (`submit_headcount_request`, `request_vacancy_closure`), and deep-link navigation pills. |

## 4. Verification Protocol Before Closing a Cross-Repo Task

Run these mechanical checks before committing:

1. **ADR Freshness**:
   - `npm run check:adr` (if `STALE`, run `npm run sync:adr`).
2. **Web Verification (`d:\Projects\ohmployee-web`)**:
   - `npm run check:sql` (validates 28 core tables & 19 critical RPC contracts)
   - `npm run check:secrets` (scans for leaked JWTs, DB URLs, and API keys)
   - `npm test` (runs all unit, RBAC sanity, import sanity, and ADR contract tests)
   - `npm run lint` (0 ESLint errors and 0 warnings)
   - `npm run build` (Next.js 16 Turbopack compile check)
3. **Mobile Verification (`D:\Projects\OHMployee`, when Mobile files or shared RPCs are touched)**:
   - `flutter analyze` (0 issues)
   - `flutter test` (all unit & service tests passing)
4. **Staging Live Diff (when a migration is pushed)**:
   - Push to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging`.
   - Diff live `pg_get_functiondef` against the committed SQL migration for every modified function.
