# AI Handoff

## ohmployee-web — Git Status Audit + Mirror ai-finish.sh PROD Gate Script (ohm#8kfq3wzn)

**Status: COMPLETE — CLIENT-SIDE ONLY, STAGING VERIFIED**

### Summary of Changes

1. **Git Status Audit (Part A)**:
   - Audited the uncommitted repository state. Identified 9 files containing modifications or additions accumulated from prior tasks (`ohm#3k8h5wte`, `ohm#8vt3nkrq`, `ohm#6dq9wshl`, `OHM2026_1097`, `ohm#1cme8bzn`, `ohm#7bxk1nte`, `ohm#7k2m9xq4`).
   - Staged and committed these changes in 8 distinct git commits corresponding to each task boundary.

2. **Mirror PROD Gate Script (Part B)**:
   - Designed and created a cross-platform, environment-aware Node script [finish.js](file:///D:/Projects/OHMployee-web/scripts/finish.js) to act as the git commit safety orchestrator.
   - The script parses [.env](file:///D:/Projects/OHMployee-web/.env) to read the active `NEXT_PUBLIC_SUPABASE_URL` and matches the project reference:
     - **STAGING** (`qqiiznmqxfoamqytjica`) target: proceeds to auto-stage in-scope files and commit automatically.
     - **PRODUCTION** (`rwxelulyapjgaarlwkus`) or **UNRESOLVED** (ambiguous/missing env) target: halts the process, warns the user, and requires them to manually enter `CONFIRM-PROD` to proceed.
   - Integrates with git to stage tracked changes and task-scoped untracked files declared in `OHM_SCOPE_FILES`.
   - Wired `finish` script as a command shortcut inside `package.json` (`npm run finish` or `pnpm finish`).

3. **Verification**:
   - Verified Staging auto-commit behavior successfully (committed the orchestrator files automatically with `auto` prefix and parsed briefing metadata).
   - Verified Production safety gate (blocked commit and aborted when `CONFIRM-PROD` was refused).
   - Verified Unresolved safety gate (blocked commit and aborted when `.env` was missing/unparsed).

---

## ohmployee-web — Fix HR Emploc row_capabilities Missing RBAC Fields (Blocking Workflow) (ohm#7bxk1nte)

**Status: COMPLETE — STAGING DEPLOYED & VERIFIED**

### Summary of Changes

Fixed the `row_capabilities` structural gap blocking HR Emploc admin workflows on STAGING:
1. **Migration Version**:
   - Created and applied DB migration version `20262606000020_add_hr_emploc_row_capabilities_fields.sql` to STAGING (`qqiiznmqxfoamqytjica`) only.
2. **RPC and View Logic Updates**:
   - Updated `list_web_hr_emplocs` and `get_web_hr_emploc_detail` to compute and return the missing keys (`can_tag_deficiency`, `can_assign_employee_no`, `can_review_deletion`) in the `row_capabilities` JSONB payload.
   - Also projected `can_review_correction` to `list_web_hr_emplocs` for consistency.
   - Refactored `is_pending_deletion` and capabilities like `can_withdraw_deletion_request`, `can_approve_deletion`, `can_reject_deletion`, and `can_review_deletion` to check for active deletion requests in the `hr_emploc_deletion_requests` table using `EXISTS (...)` rather than looking for `hr_status = 'Pending Deletion'` in the table (which is prevented by check constraints).
3. **Verification**:
   - Simulated different roles (`HR Personnel`, `Encoder`, `Head Admin`, `Super Admin`) across different workflow states (Pending, Complete, Pending Deletion) inside a transaction.
   - Confirmed the RPCs return correct capability bits for all roles and lock-states (e.g. `Head Admin` is blocked from `can_assign_employee_no` but can review deletions; `Encoder` can assign IDs when Complete and review deletions; `HR Personnel` can tag deficiencies).
4. **Client-Side Validation**:
   - Confirmed client-side normalizers map these new fields cleanly.
   - Ran `pnpm build` locally under staging environment. Build completed successfully with zero type or bundling errors.

**PROD not touched — awaiting separate push prompt with passphrase gate**

---

## ohmployee-web — PROD Push: vw_vacancy_detail store_branch/province + source_channel Fix (ohm#5tmy2rzk)

**Status: COMPLETE — PRODUCTION DEPLOYED**

### Summary of Changes

Applied the staging-verified migration `20262606000010_fix_vw_vacancy_detail_missing_columns` to the PRODUCTION database (`rwxelulyapjgaarlwkus`):
1. **Passphrase Authorization**:
   - Honored the mandatory PROD Push Gate. Requested and received the out-of-band passphrase (`DRACARYS`) before applying the migration.
2. **`vw_vacancy_detail` View Update**:
   - Added `province` and `store_branch` to the view projection `public.vw_vacancy_detail` on PRODUCTION.
   - Re-applied select grants to `authenticated` and `service_role`.
3. **`get_web_vacancy_detail` RPC Fix**:
   - Fixed the runtime compiling error `column a.source_channel does not exist` by re-mapping it to the existing `a.applicant_source` column on PRODUCTION.
   - Re-applied execute grants to `authenticated` and `service_role`.
4. **Post-Apply Verification**:
   - Verified execution on the PRODUCTION database. Called `get_web_vacancy_detail` with active vacancy ID `0775ccc6-a5ce-4f02-8af3-0d3bbad3e121` under a simulated authenticated user session.
   - Confirmed the RPC compiles and returns the correct payload, including resolving `province` ("Laguna"), `store_branch` (`null`), and the candidate's `source_channel` ("manual") inside the `pipeline_summary` array.

---

## ohmployee-web — Deep Investigation: Vacancy Aging/Pipeline + HR Emploc row_capabilities Gaps (ohm#9plk4jzc)

**Status: INVESTIGATION COMPLETE — READ-ONLY**

### Summary of Findings

#### 1. Vacancy Aging-Bucket Taxonomy Mismatch
- **Root Cause**: Taxonomy disagreement. The database RPCs (`list_web_vacancies`, `get_web_vacancy_summary`, and `get_web_vacancy_detail`) hardcode a simplified 5-bucket system (`0_7`, `8_14`, `15_30`, `31_plus`, `unknown`). Meanwhile, the UI dropdown and client query expect a 6-bucket system (`advance`, `1_15`, `16_30`, `31_60`, `61_120`, `gt121`). When the client sends the UI-selected value, the RPC does a direct string match and silently returns zero rows.
- **Fix Path**: RPC change + DB Migration (to update the RPC definitions to compute `aging_bucket` via the existing canonical DB function `public.fn_cencom_td_aging_bucket`).
- **Risk Level**: Functionally broken (medium risk).

#### 2. Missing Pipeline-Status Parameter
- **Root Cause**: Missing DB capability. The client dropdown filter "Pipeline status" in the UI does nothing because the database list and summary RPCs do not accept an independent parameter to filter by `derived_status` (they only have `p_status`, which is bound to the list tab's selected state).
- **Fix Path**: RPC change + DB Migration (extend RPC parameters with `p_pipeline_status` / `p_derived_status` and apply filter) + Client wiring.
- **Risk Level**: Functionally broken / dead UI control (medium risk).

#### 3. Columns with no Backing RPC Field
- **Root Cause**: Missing DB projections & dead UI columns.
  - `department` / `business_unit`: Does not exist anywhere in the database schema.
  - `active_applicant_count`, `confirmed_onboard_count`, `has_recent_hire`, `has_pending_closure`, `closure_request_status`: Exist in views `vw_vacancy_list`/`vw_vacancy_detail` but are omitted from the RPC output.
  - `derivedStatus`: Omitted from RPC output (only `pipeline_status` is returned).
  - `last_activity_at`: Does not exist in the database (could map to `latest_hire_at` or `updated_at`).
  - `pending_review` summary count: Omitted from summary RPC output.
- **Fix Path**: RPC change + DB Migration (project view-backing columns and calculate pending closure counts) + Client update (clean up normalizers, map `derivedStatus` properly, drop `department`).
- **Risk Level**: Cosmetic / Minor functionally broken (low risk).

#### 4. HR Emploc row_capabilities Structural Gap
- **Root Cause**: RBAC / permission-shape mismatch. The web client hides/disables crucial administrative action buttons ("Tag Deficiency", "Enter Employee ID", "Review Deletion") because it expects `can_tag_deficiency`, `can_assign_employee_no`, and `can_review_deletion` flags inside the `row_capabilities` JSON object returned by the RPCs. However, the database does not compute or return these keys.
- **Fix Path**: RPC change + DB Migration (compute and return these keys in `list_web_hr_emplocs` and `get_web_hr_emploc_detail`) + Client cleanup.
- **Risk Level**: Blocking a real user workflow (high risk).

---

## ohmployee-web — Fix vw_vacancy_detail Missing store_branch/province Columns (DB Migration) (ohm#1cme8bzn)

**Status: COMPLETE — STAGING ONLY**

### Summary of Changes

Fixed the database view `vw_vacancy_detail` and function `get_web_vacancy_detail` on STAGING to resolve the runtime crash:
1. **`vw_vacancy_detail` View Update**:
   - Added `province` and `store_branch` to the view projection `public.vw_vacancy_detail`, matching `vw_vacancy_list`.
   - Re-applied select grants to `authenticated` and `service_role`.
2. **`get_web_vacancy_detail` RPC Fix**:
   - Fixed the runtime compilation error `column a.source_channel does not exist` by re-mapping `a.source_channel` to the existing table column `a.applicant_source`.
   - Re-applied execute grants to `authenticated` and `service_role`.
3. **Migration Version**:
   - Created and applied DB migration version `20262606000010_fix_vw_vacancy_detail_missing_columns` to STAGING (`qqiiznmqxfoamqytjica`) only.
4. **Verification**:
   - Verified that `get_web_vacancy_detail('f0690db0-825a-443d-9688-fb94106ad268')` executes successfully and returns the expected columns, including `province` ("Kalinga") and `store_branch` (`null`).

**PROD not touched — awaiting manual confirmation gate**

---

## Remove misplaced Mobile UI docs from Web repo (ohm#4t8w1z6p)

**Status: COMPLETE**

### Summary of Changes

1. **Deleted Mobile UI Layout Documents**:
   - Removed the directory `docs/ui/mobile/` and its 4 misplaced markdown layout specification files:
     - `vacancy_layout.md`
     - `plantilla_layout.md`
     - `hr_emploc_layout.md`
     - `dashboard_layout.md`
   - Mobile layout documentation now lives exclusively in the separate Mobile repository (`D:/Projects/OHMployee/docs/ui/mobile/`).
   
2. **Preserved Web UI Layout Documents**:
   - `docs/ui/web/*` layout documents remain untouched under the correct location in this repository.

3. **Confirmed State File Links**:
   - Confirmed each remaining `docs/ui/web/*_layout.md` file's "Linked state file" path.
   - Updated [dashboard_layout.md](file:///d:/Projects/ohmployee-web/docs/ui/web/dashboard_layout.md) to point to the correct, existing [web_foundation_state.md](file:///d:/Projects/ohmployee-web/docs/state/web_foundation_state.md) state file path since `docs/state/dashboard_state.md` does not exist.
   - Verified that `vacancy_layout.md`, `plantilla_layout.md`, and `hr_emploc_layout.md` correctly point to existing state files under `docs/state/` (`vacancy_web_state.md`, `plantilla_web_state.md`, and `hr_emploc_web_state.md` respectively).

4. **Shared Documentation Integrity**:
   - Did not modify `docs/architecture/` or `docs/state/` content (except for validating the link paths), preserving this repo as the single source of truth for shared documentation.

---

## Fix Client-Side Field/Param Mismatches (Vacancy + HR Emploc) (ohm#6dq9wshl)

**Status: COMPLETE — CLIENT-SIDE ONLY, STAGING VERIFIED**

### Summary of Changes

Fixed the client-side RPC parameter and field-normalization mismatches confirmed by `ohm#2fh6xrqw` (root cause: commit `f1f965c` refactored client payloads without matching deployed DB signatures). All fixes are in [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts) and [hr_emploc.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts) only. No DB migration. Verified live against staging (`qqiiznmqxfoamqytjica`) by re-reading `pg_proc` signatures/definitions and executing each RPC with a simulated authenticated session (`set_config('request.jwt.claims', ...)`).

1. **`vacancy.ts` — parameter shape**:
   - `getVacancyRpcFilters` rewritten from the wrapped `{ p_queue, p_search, p_filters }` payload to the flat parameter set the deployed `get_web_vacancy_summary` / `list_web_vacancies` actually accept: `p_status, p_account_id, p_group_id, p_position, p_urgency, p_search, p_vacant_from, p_vacant_to` (+ `p_aging_bucket, p_limit, p_offset, p_sort_by, p_sort_dir` for the list RPC only — the summary RPC has no `p_aging_bucket` parameter).
   - Renamed `p_sort` → `p_sort_by` in `listVacancies`.
   - `VacancySortField`/`supportedSortFields` corrected to the DB's real sort whitelist (`urgency` instead of `urgency_level`, dropped nonexistent `updated_at`, added `vacancy_status`/`pipeline_status`).
   - Removed `normalizePipelineStatus`/`supportedPipelineStatuses` — the deployed RPCs have no `p_pipeline_status` parameter; `p_status` alone matches either `vacancy_status` or `pipeline_status` server-side, so the client's "Pipeline status" dropdown filter (Open/Pipeline) in `vacancy/page.tsx` cannot currently be forwarded to the RPC at all. **Flagged, not fixed — needs a follow-up decision on whether the dropdown should be removed or the RPC needs a dedicated param.**

2. **`vacancy.ts` — field normalization** (`normalizeListRow`, `normalizeCapabilities`, `normalizeSummary`):
   - `urgencyLevel` now reads `row.urgency` (was `row.urgency_level`).
   - `canRequestClosure` now reads `row.row_capabilities.can_request_closure_hint` (was `can_request_closure`).
   - `normalizeSummary` rewritten against the live `RETURNS TABLE(total_open, with_applicant, rejected, backout, aging_0_7, aging_8_14, aging_15_30, aging_31_plus, aging_unknown, critical_urgency, high_urgency)`: `open`←`total_open`, `withApplicant`←`with_applicant`, `rejected`/`backout` unchanged (already matched), `agingWatch` derived as `aging_31_plus + aging_unknown` (no single "aging watch" counter exists server-side), `total` derived as the sum of the four status buckets. **`pendingReview` has no backing column anywhere in the RPC output — left at 0, flagged, not fabricated.**
   - Additional discovered mismatches in `list_web_vacancies`' actual output vs. `VacancyListItem` — **no backing RPC columns exist for**: `department`, `derivedStatus`, `activeApplicantCount`, `confirmedOnboardCount`, `hasRecentHire`, `hasPendingClosure`, `closureRequestStatus`, `lastActivityAt`, `canApprove`, `canUpdateApplicantStatus`. These fields will continue to render as null/false/0. Flagged, not fixed (would require DB projection changes).
   - **Discovered but not fixed**: the client's aging-bucket filter vocabulary (`advance/1_15/16_30/31_60/61_120/gt121`, used by the `agingBucket` dropdown in `vacancy/page.tsx`) does not match the DB's actual bucket taxonomy (`0_7/8_14/15_30/31_plus/unknown`), so the aging-bucket filter will silently return zero rows whenever applied. This is a business-logic/taxonomy gap, not a simple rename, and needs its own follow-up (touches `page.tsx` UI options too).
   - `normalizeDetailRow`/`getVacancyDetail` intentionally left untouched — `get_web_vacancy_detail` still throws at runtime (`store_branch`/`province` bug, separate DB migration prompt) so its output can't be live-verified right now.

3. **`hr_emploc.ts` — field normalization**:
   - `normalizeSummary`: `totalPending`←`pending_count`, `actionNeeded`←`correction_count`, `readyToDeploy`←`ready_count` (as specified). `pendingDeletion`/`slaBreaches` were already correctly falling back to `pending_deletion_count`/`sla_breached_count` — no change needed there.
   - `normalizeListRow`/`normalizeDetailRow`: `slaElapsedDays` now reads `row.aging_days` (was `sla_elapsed_days`, which doesn't exist).
   - `normalizeDetailRow`: `uploadedAttachments` now sourced from `row.correction_attachments` (was `row.uploaded_attachments`); `auditLogsTimeline` now sourced from `row.timeline` (was `row.audit_logs_timeline`); `activeDeletionRequest` now sourced from `row.deletion_request` (was `row.active_deletion_request`).
   - **Additional mismatches found and fixed** (same class, not explicitly named in the prompt but discovered by re-deriving the full field list from the live RPC definitions):
     - `normalizeAttachment`: DB attachment shape is `{id, original_filename, mime_type, size_bytes, uploaded_by, uploaded_at, storage_path}`, not `{attachment_id, file_name, file_url, file_size, ...}`. Fixed `attachmentId`←`id`, `fileName`←`original_filename`, `fileUrl`←`storage_path`, `fileSize`←`size_bytes`.
     - `normalizeAuditLog`: DB timeline event shape has `remarks`/`actor_name`, not `event_description`/`profile_name`. Fixed `eventDescription`←`remarks`, `profileName`←`actor_name`.
     - `normalizeDeletionRequest`: DB deletion-request object shape has `id`/`created_at`, not `request_id`/`requested_at`. Fixed `requestId`←`id`, `requestedAt`←`created_at`.
     - `deficiencySummary`: type was declared `string | null` but the DB returns a jsonb object `{active_count, issues: [{code, comment, label}]}`, so `asString()` on it always evaluated to `null`. Added `summarizeDeficiency()` to join issue labels into a display string (rendered directly in `HrEmplocTable.tsx`).
   - **Discovered but not fixed**: `HrEmplocRowCapabilities` (`canTagDeficiency`, `canAssignEmployeeNo`, `canReviewDeletion`) has no matching keys in the DB's actual `row_capabilities` (`can_view_detail, can_request_deletion, can_withdraw_deletion_request, can_approve_deletion, can_reject_deletion, can_approve_correction, can_revert_correction, can_review_correction, can_submit_correction, can_move_to_plantilla`). These three capabilities will always resolve to `false`. Structural mismatch, not a rename — flagged for a follow-up decision rather than guessed at.
     `coveredStoresCount` on the list row also has no backing column in `list_web_hr_emplocs` (only the detail RPC returns `covered_stores`) — flagged, not fixed.

### Verification
- `pnpm build` (staging env) — compiles clean, typechecks clean, static generation succeeds for all 17 routes including `/vacancy` and `/hr-emploc`.
- Live staging RPC calls (via Supabase MCP, simulated authenticated session):
  - `get_web_vacancy_summary()` → `{total_open:3, with_applicant:2, rejected:0, backout:2, aging_0_7:5, ...}` — succeeds, matches new normalizer.
  - `list_web_vacancies(p_limit:=3, p_sort_by:='aging_days', p_sort_dir:='desc')` → rows returned with `urgency`, `row_capabilities.can_request_closure_hint` present — succeeds, matches new normalizer.
  - `get_web_hr_emploc_summary()` → `{pending_count:1, correction_count:0, review_count:0, ready_count:0, ...}` — succeeds, matches new normalizer.
  - `list_web_hr_emplocs(p_limit:=3)` → rows returned with `aging_days`, `deficiency_summary` object, `row_capabilities` present — succeeds, matches new normalizer.
- No in-browser smoke test performed (per prompt — user performs UI smoke test manually).

### Still Outstanding (separate prompts)
- `get_web_vacancy_detail` `store_branch`/`province` DB bug — server-side/DB migration, explicitly out of scope here.
- Aging-bucket filter taxonomy mismatch (vacancy) — needs a decision + `page.tsx` UI change.
- Pipeline-status filter has no backing RPC param (vacancy) — needs a decision + possible DB change.
- HR Emploc `row_capabilities` structural mismatch (3 capabilities with no DB analog) — needs a decision on what the correct capability model should be.

---

## Scaffold docs/ui/ structure (Mobile + Web layout separation) (ohm#7k2m9xq4)

**Status: COMPLETE**

### Summary of Changes

1. **Scaffolded Layout Documentation Folder Structure**:
   - Created the folder structure:
     - `docs/ui/mobile/`
     - `docs/ui/web/`
   - Generated standard TBD layout spec templates for all modules present (`vacancy`, `plantilla`, `hr_emploc`, `dashboard`) under both platforms.

2. **Files Created/Modified**:
   - **Created**:
     - [vacancy_layout.md (mobile)](file:///d:/Projects/ohmployee-web/docs/ui/mobile/vacancy_layout.md)
     - [vacancy_layout.md (web)](file:///d:/Projects/ohmployee-web/docs/ui/web/vacancy_layout.md)
     - [plantilla_layout.md (mobile)](file:///d:/Projects/ohmployee-web/docs/ui/mobile/plantilla_layout.md)
     - [plantilla_layout.md (web)](file:///d:/Projects/ohmployee-web/docs/ui/web/plantilla_layout.md)
     - [hr_emploc_layout.md (mobile)](file:///d:/Projects/ohmployee-web/docs/ui/mobile/hr_emploc_layout.md)
     - [hr_emploc_layout.md (web)](file:///d:/Projects/ohmployee-web/docs/ui/web/hr_emploc_layout.md)
     - [dashboard_layout.md (mobile)](file:///d:/Projects/ohmployee-web/docs/ui/mobile/dashboard_layout.md)
     - [dashboard_layout.md (web)](file:///d:/Projects/ohmployee-web/docs/ui/web/dashboard_layout.md)
   - **Modified**:
     - [.ai/briefing.md](file:///d:/Projects/ohmployee-web/.ai/briefing.md)
     - [.ai/handoff.md](file:///d:/Projects/ohmployee-web/.ai/handoff.md)

3. **Content Extraction Audit**:
   - Audited all existing state documentation under `docs/state/*_state.md`.
   - Found no embedded mobile UI/UX layout notes or layout specifications inside the state files (references to Mobile were only related to matching backend RPC interfaces/behaviors). Therefore, no content extraction or file stripping of existing state docs was required.

---

## Diagnose Vacancy RPC Failure (PROD) (ohm#2fh6xrqw)

**Status: DIAGNOSIS COMPLETE — READ-ONLY INVESTIGATION**

### Findings & Root Cause

1. **RPC Parameter Signature Mismatch**:
   - The query code in [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts) (updated in commit `f1f965c`) was rewritten to pass query filters in a wrapped shape:
     - `list_web_vacancies` calls: `{ p_queue, p_search, p_filters, p_limit, p_offset, p_sort, p_sort_dir }`
     - `get_web_vacancy_summary` calls: `{ p_queue, p_search, p_filters }`
   - However, the deployed database functions on both Staging (`qqiiznmqxfoamqytjica`) and PROD (`rwxelulyapjgaarlwkus`) still expect the old flat filter parameters:
     - `list_web_vacancies` expects: `(p_status, p_account_id, p_group_id, p_position, p_urgency, p_aging_bucket, p_search, p_vacant_from, p_vacant_to, p_limit, p_offset, p_sort_by, p_sort_dir)`
     - `get_web_vacancy_summary` expects: `(p_status, p_account_id, p_group_id, p_position, p_urgency, p_search, p_vacant_from, p_vacant_to)`
   - This signature mismatch causes the calls to fail with Postgres error `42883: function does not exist`, which is caught and thrown as a `"retryable"` error in the UI.

2. **Database View Column Mismatch in `get_web_vacancy_detail`**:
   - Calling the detail RPC `get_web_vacancy_detail(p_vacancy_id)` on PROD throws a database runtime exception: `ERROR: 42703: column vd.store_branch does not exist`.
   - The SQL definition of `get_web_vacancy_detail` references `vd.store_branch` and `vd.province` from `public.vw_vacancy_detail vd`, but these columns are omitted from the SELECT clause of the `vw_vacancy_detail` view in the database (even though they are present in `vw_vacancy_list`).

3. **Field Normalization Mismatches**:
   - Multiple columns returned by database functions do not match what is read in [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts):
     - `urgencyLevel` is read as `row.urgency_level` but returned as `urgency`.
     - `rowCapabilities` reads `can_request_closure` but DB returns `can_request_closure_hint`.
     - `activeApplicantsList` reads `row.active_applicants_list` but DB returns `pipeline_summary`.
     - Summary KPI normalizer reads `open` from `row.open_count`/`row.open` but DB returns `total_open`.
     - Several list/detail operational columns (e.g., `active_applicant_count`, `confirmed_onboard_count`, `has_recent_hire`, `has_pending_closure`) are missing from the SQL projections.

4. **Wider Impact (Other Modules)**:
   - A quick audit of [hr_emploc.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts) queries shows the same class of normalization mismatches. For example:
     - `normalizeSummary` reads `total_pending`, `action_needed`, and `ready_to_deploy` but the database returns `pending_count`, `correction_count`, and `ready_count`.
     - `normalizeDetailRow` reads `uploaded_attachments` and `audit_logs_timeline` but the database returns `correction_attachments` and `timeline`.
     - `normalizeListRow` reads `sla_elapsed_days` but the database returns `aging_days`.

### Proposed Fix Plan

1. **Option A: Align Frontend Code (Recommended)**
   Update the query file [vacancy.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/vacancy.ts) to:
   - Flatten parameters in `getVacancyRpcFilters` to match the current database signature.
   - Map `p_sort` parameter to `p_sort_by`.
   - Correct the field name maps in the normalization layer (e.g., read `row.urgency` instead of `row.urgency_level`, read `total_open` instead of `open`, etc.).
   - Adjust `get_web_vacancy_detail` query fields to read from `pipeline_summary` instead of `active_applicants_list`.
   
2. **Option B: Align Database Functions via Migration**
   Deploy a migration to:
   - Update `list_web_vacancies` and `get_web_vacancy_summary` functions to accept the `{ p_queue, p_filters }` schema design.
   - Fix `get_web_vacancy_detail` function by joining/reading `store_branch` and `province` from `public.vacancies v_raw` instead of `vd.store_branch` / `vd.province`, or update `public.vw_vacancy_detail` to select these columns.

3. **Spot-check and Fix HR Emploc Normalization**:
   Apply similar alignment changes in [hr_emploc.ts](file:///d:/Projects/ohmployee-web/src/lib/queries/hr_emploc.ts) to resolve hidden bugs in badge counts and attachment/timeline displays.

---

## Split Inactive Employees into Separate Tab/View — Plantilla (ohm#8vt3nkrq)

**Status: COMPLETE — WEB ONLY, NO MIGRATIONS**

Mirrors the *structural* pattern of mobile's Active/Vacancy/Inactive tab split (data filtering, status logic) — web stays table-based, no card redesign.

**RPC-level change needed: NONE.** `list_web_plantilla_employees` already accepts `p_active_state` (`'active' | 'inactive' | 'all' | null`), computed server-side from `plantilla.status`/`deactivated_at`/`date_of_separation` against the same inactive-status vocabulary mobile uses (`inactive, deactivated, resigned, separated, endo, terminated`). Only client-side wiring was needed — `PlantillaEmployeeListParams.activeState` already existed in `plantilla.ts` but `page.tsx` wasn't passing it.

**Blocking bug found and fixed in the same pass (pre-existing, not introduced by this task):** `normalizeEmployeeListRow` in `src/lib/queries/plantilla.ts` read RPC field names (`plantilla_status`, `assignment_type`, `covered_stores_count`, `date_deployed`) that do not exist on the actual deployed `list_web_plantilla_employees` function (confirmed via `pg_get_function_result` on both staging `qqiiznmqxfoamqytjica` and prod `rwxelulyapjgaarlwkus` — real columns are `status`, `deployment_type`, `roving_store_count`, `date_hired`). This meant the Status badge was always blank and the dimming logic never fired in production prior to this fix. Fixed with `??` fallbacks to the real column names (`row.plantilla_status ?? row.status`, etc.) — no RPC/migration touched. `plantillaType` (Budgeted/AH) and `baseRateMasked`/`slaBreached` still have no backing RPC column at all (not part of this task's visible table columns — left as pre-existing gaps, flagged, not fixed).

**Changes in `src/app/(dashboard)/plantilla/page.tsx`:**
- `ViewMode` extended to `"employee" | "inactive" | "store"`; third toggle button "Inactive" added next to "Employee View" / "Store Staffing".
- `employeeQuery` now passes `activeState: view === "inactive" ? "inactive" : "active"` and is `enabled` for both `employee` and `inactive` views (reuses the same query/table, just a different `activeState` + cache key) — no separate query hook needed.
- Filter bar: Store ID + Deployment Type filters now show for both Employee and Inactive views; the employment-Status dropdown (`STATUS_OPTIONS`) is Employee-view-only (redundant inside a view that's already status-partitioned).
- `EmployeeTable`: removed all `opacity-65` / `pointer-events-none` / `line-through` dimming (the `isDimmed` branch of `deriveDeactivationOverlay`) — dead now that inactive rows never reach the Employee view. Rows are unconditionally clickable/keyboard-navigable in both views, matching mobile's confirmed behavior (Inactive tab keeps tap-to-detail, per `plantilla_state.md` ohm#a3d9k7q2 — no card visual, since web stays table-based). The `isPendingSeparation` dashed-red-border banner treatment was kept (not part of the "dimming" being removed — it's a still-active-but-flagged state, not disabled).

**Verified:**
- `pnpm build` — clean, 0 type errors.
- Row-count parity confirmed via direct SQL against staging (`qqiiznmqxfoamqytjica`), replicating the RPC's own `is_active`/`is_inactive` predicate over all of `public.plantilla` (excluding `source_headcount_request_id IS NOT NULL` rows, same as the RPC's base filter): **376 active + 3448 inactive = 3824 total**, exact partition, no loss/duplication.
- Live in-browser click-through **not done this session** — no test login credentials are checked into either repo (confirmed via repo-wide search), and the dev server on :3000 required auth past the login screen. Verification relied on `pnpm build` + direct DB-level partition-count confirmation instead.

**Not touched:** Store Staffing view, card layouts, RPC/migrations, `plantillaType`/`baseRateMasked`/`slaBreached` field gaps (flagged only).

---

## Plantilla UI Current-State Audit (ohm#5r9k2vqp)

- **Audit Purpose**: Assess existing Plantilla module UI, queries, and styling to scope a future mobile card-parity redesign.
- **Current Display Pattern**: Table-based dense rows in `src/app/(dashboard)/plantilla/page.tsx` (`EmployeeTable` and `StoreTable`), not cards.
- **Tab Structure**: Toggles between "Employee View" and "Store Staffing". There is no Active / Vacancy / Inactive tab structure (Vacancy has its own module, and Inactive personnel are styled as dimmed/strikethrough rows in the employee table).
- **Multi-store Handling**: Handled in detail drawer (`PlantillaDetailDrawer.tsx` roving stores list) but not in list view (rendered only as a roving count badge, no store-chip navigation).
- **RPC Support**: `get_web_plantilla_detail` exposes employee metadata, status, type, roving covered stores array, and capabilities. However, `list_web_plantilla_employees` only exposes `covered_stores_count` (integer), not the full store list. To support store chips in the list, list RPC updates would be required. No dedicated avatar URL field exists (initials derived from first/last name).
- **Design Tokens**: Exposes theme variables via Tailwind v4, but currently uses default system fallbacks for font-sans/font-mono instead of DM Sans/DM Mono.

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
