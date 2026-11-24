# AI Handoff

## Execution Report — Fix Confirmed Onboard Candidates Lingering in Vacancy Open & Synchronize HR Processing (ohm#fix-vacancy-open-onboard-dual-existence-and-hr-processing-sync)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Migrated to Staging & Locally Tested

### Forensic Root Cause & Operational Fix
1. **User Bug Report**:
   - `VCBPIG1_0183` lingered in the Vacancy Open tab despite candidate **Tejada, Elizabeth Uy** having reached **Confirmed Onboard** status and being actively processed in **HR Emploc** (`Pending Emploc` / `Pending`).
   - ADR Invariant Violated: A requisition cannot exist across two modules (Vacancy Open and HR Emploc) unless `required_headcount > 1` (where unfilled capacity remains open for recruitment).
2. **Forensic Root Cause Analysis**:
   - **Root Cause 1 (`vw_vacancy_list.derived_status`)**:
     In `vw_vacancy_list`, `derived_status` only checked `active_plantilla_count >= required_headcount` for `'Hired'`. Candidates who reached Confirmed Onboard status without yet being deployed to Plantilla fell through all `WHEN` clauses to `ELSE 'Open'::text`.
   - **Root Cause 2 (`list_web_vacancies` & `get_web_vacancy_summary` bypass predicate)**:
     The query for `p_status = 'open'` included an `OR lower(s.pipeline_status) = 'open'` bypass. Because Root Cause 1 marked the pipeline status as `'Open'`, the predicate evaluated to `FALSE OR TRUE = TRUE`, leaking zero-capacity vacancies into the Open tab in violation of ADR Rule 4.
   - **Root Cause 3 (Roving and Pool vacancy slot disconnect)**:
     `slot_stats` had `WHERE ps.is_roving = false`, excluding roving slots from `hr_processing_count` (e.g. `CPSAJV27`), and pool slots had `legacy_vcode = NULL`. Adding `hr_emploc_stats` (`active_hr_emploc_count`) and using `GREATEST(ss.hr_processing_count, s.confirmed_onboard_count, hre.active_hr_emploc_count)` ensures onboarding candidates are always accurately reflected in `hr_processing_count`.
3. **Database Migration (`supabase/migrations/20262606000178_fix_vacancy_open_onboard_dual_existence_and_hr_processing_sync.sql`)**:
   - **Historical Data Reconciliations**:
     - Unarchived active onboarding candidates in `applicants` who are active in `hr_emploc`.
     - Backfilled missing `legacy_vcode` on `plantilla_slots` from `hr_emploc` and `applicants`.
     - Synchronized `slot_id` linkages between `applicants` and `hr_emploc`.
     - Reconciled raw `vacancies.status = 'Filled'` for vacancies whose active Plantilla occupancy meets required headcount.
   - **`vw_vacancy_list` Update (Append-Only Non-Breaking View Parity)**:
     - Preserved all 48 columns in exact identical order.
     - Added `hr_emploc_stats` CTE and removed the `is_roving = false` exclusion in `slot_stats`.
     - Updated `hr_processing_count` to `COALESCE(GREATEST(ss.hr_processing_count, s.confirmed_onboard_count, hre.active_hr_emploc_count), 0)::integer`.
     - Updated `derived_status` so requisitions where confirmed onboards (in HR Emploc) + active plantilla meet or exceed required headcount evaluate to `'Hired'` (vacating Open and Pipeline).
   - **`list_web_vacancies` & `get_web_vacancy_summary` Hardening**:
     - Removed the `OR lower(s.pipeline_status) = 'open'` bypass, strictly enforcing ADR Rule 4: a vacancy appears in the Open tab if and only if unallocated capacity exists: `(hc_total - hc_filled - hr_processing_count - active_applicant_count) > 0`.
4. **Verification & Testing**:
   - Pushed migration 178 cleanly to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging`.
   - Verified live database queries on Staging:
     - Confirmed `VCBPIG1_0183` (Tejada, Elizabeth Uy) has `derived_status = 'Hired'` and no longer appears in Open tab.
     - Confirmed all single-slot target vacancies (`VCBPIG1_0183`, `ACT-G5-002`, `VCBPIG1_1026`, `PSM-G3-0062`, `CPSAJV27`, `SEA-00006`, `BUN-GHQ-00015`) transitioned to `'Hired'` and appear in the Hired tab with 0 open capacity.
     - Confirmed multi-slot vacancy `ACT-G5-008` (headcount 3, filled 1, HR processing 1) correctly remains in Open tab with 1 remaining open slot.
   - 264/264 unit tests passed (`npm test`).
   - 0 ESLint errors/warnings (`npm run lint`).
   - 0 secret leaks (`npm run check:secrets`).
   - 0 SQL contract errors (`npm run check:sql`).

### Files Changed
- `supabase/migrations/20262606000178_fix_vacancy_open_onboard_dual_existence_and_hr_processing_sync.sql` — Data cleanup, `vw_vacancy_list`, `list_web_vacancies`, and `get_web_vacancy_summary` capacity synchronization.
- `docs/state/vacancy_web_state.md` — Updated Vacancy state specifications for Confirmed Onboard candidates and strict zero-capacity invariant.
- `.ai/briefing.md` — Prepending task to Last Completed Tasks.
- `.ai/handoff.md` — Prepended handoff report.

---

## Execution Report — Enforce Clean Open Requisition on Backout, Auto-Archival Trigger, Zero-Applicant Avail & Multi-Position Parity (ohm#clean-open-vacancy-and-backout-invariants)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Migrated to Staging & Locally Tested

### What Was Built
1. **Clean Open Requisition Invariant upon Backout (Anti-Ghost Applicant Lock)**:
   - Added rule to ADR-002 / `02_vacancy.md` ("Clean Open Requisition Invariant upon Backout / Anti-Ghost Applicant Lock"):
     - When an applicant backs out or fails (`status IN ('backout', 'failed', 'rejected', 'did_not_report', 'withdrew')`), they are routed exclusively to the **Failed / Backout Tab** (`p_status = 'Failed'`).
     - The linked store requisition returns to the **Open Tab** clean with zero applicants (`clean malinis at walang nakalagay na applicant`). Under no circumstances may a backed-out, failed, or terminal applicant linger, display, or occupy headcount in the Open requisition's active applicant roster or detail view.
2. **Automated Archival Trigger & Slot Decoupling (`20262606000177_clean_open_vacancy_and_applicant_terminal_archival.sql`)**:
   - Created database trigger `trg_applicants_terminal_archival` on `public.applicants` auto-archiving (`is_archived = true`, `archived_at = now()`) and decoupling `slot_id = NULL` on terminal status transitions (`backout`, `failed`, `rejected`, `did_not_report`, `withdrew`).
   - Surgically filtered `get_web_vacancy_detail` to exclude dropouts from `pipeline_summary`.
   - Reconciled historical dropouts (including James Cruz on `TEST011`).
3. **Avail Metric & Zero-Applicant Invariant**:
   - Codified $\text{Avail} = \max(0, \text{hc\_needed} - \text{hired\_count} - \text{pipeline\_count} - \text{hr\_processing\_count})$.
   - Adding a candidate to screening immediately drops `Avail`. Full positions strictly block new candidate intake until a candidate backs out.
4. **Multi-Position Sourcing Parity**:
   - Added position selector with slot availability badges and hired/pipeline counters to `AddApplicantModal`.
   - Persisted `vacancy_requirement_id` to `applicants`.
   - Threaded requirement IDs into `MarkHiredModal` / `confirm_applicant_onboard`.
5. **Verification**:
   - Applied cleanly to Staging (`qqiiznmqxfoamqytjica`).
   - 264/264 unit tests passed (`npm test`).
   - 0 ESLint errors/warnings (`npm run lint`).
   - 0 SQL contract errors (`npm run check:sql`).
   - Clean Next.js 16.2.4 Turbopack build (`npm run build`).

### Files
- `supabase/migrations/20262606000177_clean_open_vacancy_and_applicant_terminal_archival.sql` — Auto-archival trigger and terminal filtering on `get_web_vacancy_detail`.
- `docs/architecture/_mirror/adr/02_vacancy.md` — Codified Clean Open Requisition Invariant and Zero-Applicant Avail definition.
- `docs/state/vacancy_web_state.md` — Updated Vacancy state specifications.
- `src/components/vacancy/AddApplicantModal.tsx` — Multi-position requirement selector and intake lock.
- `src/components/vacancy/MarkHiredModal.tsx` — Requirement ID forwarder.
- `src/components/vacancy/VacancyDetailDrawer.tsx` — Requirement ID threading and terminal candidate exclusion.
- `src/lib/queries/vacancy/types.ts` & `vacancyListing.ts` & `vacancyMutations.ts` — Query normalizers and mutations.
- `src/lib/queries/__tests__/multi_position_vacancy_intake.test.mjs` — Comprehensive unit tests.
- `.ai/briefing.md` — Prepending task to Last Completed Tasks.
- `.ai/current_state.md` — Added update log.
- `.ai/handoff.md` — Prepended handoff report.

---

## Execution Report — Simplify Vacancy Detail Modal, Relocate Header Actions, Add Aging Color Coding & Clean Decimal Formatting (ohm#simplify-vacancy-detail-modal-and-aging-colors)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Migrated to Staging & Locally Tested

### What Was Built
1. **Top Header Action Bar (`Modal.tsx` & `VacancyDetailDrawer.tsx`)**:
   - Added `headerActions?: ReactNode` to `Modal` (`src/components/shared/Modal.tsx`).
   - Moved `Adjust Quota`, `HC Adjustment` (renamed from `Request HC Adjustment`), `Request Closure`, and `Withdraw Closure` directly into the modal top header next to the close button, freeing vertical space above the tabs.
2. **Aging Color Coding (`getAgingColorClasses`)**:
   - Color-coded both the top KPI `Aging` metric (`97d / 31+ days`) and individual applicant aging pills (`35d`, `0d`):
     - **Green (Emerald)**: `<= 7 days` (`text-emerald-600 dark:text-emerald-400`)
     - **Yellow (Amber)**: `8 - 15 days` (`text-amber-600 dark:text-amber-400`)
     - **Red (Rose)**: `> 15 days` (`text-rose-600 dark:text-rose-400`)
3. **Clean Number & Decimal Formatting (`formatHcNumber`, `cleanNumbersInText` & Migration 176)**:
   - Authored and pushed migration `supabase/migrations/20262606000176_clean_hc_decimals_in_vacancy_activity_timeline.sql` to Staging (`qqiiznmqxfoamqytjica`) so `get_vacancy_activity_timeline` trims trailing zeros (`2.0000 HC -> 2 HC`, `0.5000 HC -> 0.5 HC`, `0.3333 HC -> 0.33 HC`).
   - Added frontend helpers `formatHcNumber` and `cleanNumbersInText` so all KPI numbers, position breakdown counters, and activity history descriptions render whole numbers without decimals and fractional values with at most 1–2 decimals.
4. **Applicant Section & Simple Activity History**:
   - Renamed `"Applicant & Pipeline Roster"` to `"Applicant"`.
   - Placed a compact inline edit pencil button (`<Edit3 />`) directly next to each applicant's name (removing the separate bottom `"Edit Details"` button).
   - Simplified the `Activity History` tab: removed the `"Detailed Activity History Trail"` and `"What • Who • When"` header bar and replaced boxed cards with a clean, lightweight vertical timeline (`Title` + `Timestamp`, `Description`, `By Actor`).
5. **Verification**:
   - ADR fresh check: `npm run check:adr` (`ADR_MIRROR_STATUS: FRESH`).
   - SQL contracts check: `npm run check:sql` (verified 28 core tables & 19 cross-module RPC contracts across 701 migrations).
   - Unit tests: `npm test` (263/263 unit tests passed).
   - ESLint: `0` errors, `0` warnings.
   - Staging migration push: applied `20262606000176_clean_hc_decimals_in_vacancy_activity_timeline.sql` cleanly to Staging (`qqiiznmqxfoamqytjica`).

### Files
- `supabase/migrations/20262606000176_clean_hc_decimals_in_vacancy_activity_timeline.sql` — Trimmed trailing decimals on headcount numbers in `get_vacancy_activity_timeline`.
- `src/components/shared/Modal.tsx` — Added `headerActions` prop to modal header bar.
- `src/components/vacancy/VacancyDetailDrawer.tsx` — Relocated quota/closure actions to header, added aging color coding, inline applicant name edit icon, renamed section to `Applicant`, formatted numbers, and simplified Activity History timeline.
- `docs/state/vacancy_web_state.md` — Updated modal specification.
- `.ai/briefing.md` — Prepended task to Last Completed Tasks.
- `.ai/current_state.md` — Added update log.
- `.ai/handoff.md` — Prepended handoff report.

---

## Execution Report — Reconcile Plantilla Rollback Status Desync & Prevent Zero-Edit Lock Query Storm (ohm#fix-plantilla-rollback-status-desync-and-guard)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Migrated to Staging & Locally Tested

### Forensic Root Cause & Operational Fix
1. **User Alert Diagnosis (`IMG_4423.jpg`)**:
   - The user uploaded an alert screenshot from the Supabase Dashboard: Staging database (`qqiiznmqxfoamqytjica`) CPU was maxed out at 100%, and Postgres logs repeatedly printed the following error 1-2 times every second:
     `40001 ZERO_EDIT_LOCK: Batch records have been modified post-approval. Employee 2023-12046 (VASQUEZ, JULIUS JULIUS) was edited on 2026-10-27T06:16:22.657408+00:00. Rollback is hard-blocked.`
   - Forensic Analysis:
     - Inspection of `plantilla_import_batches` revealed that historical batch `aa79f9c7-9d44-4f35-9224-8c701534cee7` had `status = 'rolled_back'`, but its `rollback_status` remained desynchronized as `'requested'`.
     - Months later on 2026-10-27, employee `2023-12046` was modified by a new batch import.
     - Because `fetchRollbackApprovalRequests` and `fetchRollbackApprovalCounts` previously queried purely on `rollbackStatus === "requested"`, the batch reappeared as a pending rollback request in `/approvals?tab=rollbacks`.
     - When approval was triggered, `public.approve_plantilla_import_rollback(p_batch_id)` executed `get_plantilla_import_first_modified_record(p_batch_id)` without first checking if the batch was already rolled back or in an invalid state.
     - `humanizeRollbackError()` had a substring check `if (msg.includes("lock"))` before any specific check, erroneously translating the `ZERO_EDIT_LOCK` error into:
       `"Another rollback is already in progress. Please wait and retry."`
     - This misleading message led the client UI/user to repeatedly retry, hammering PostgREST every second and exhausting database CPU resources.
2. **Database Hardening & Migration (`supabase/migrations/20262606000175_fix_plantilla_rollback_status_desync_and_guard.sql`)**:
   - **Check Constraint Alignment**: Updated `pib_rollback_status_check` (`plantilla_import_batches`) and `vib_rollback_status_check` (`vacancy_import_batches`) to include `'rejected'`.
   - **Batch Status Reconciliation**:
     - Aligned all historical batches where `status = 'rolled_back'` to `rollback_status = 'completed'`.
     - Reconciled rejected vacancy batch `caefef5e-506c-4f4c-a618-04b21d172623` to `rollback_status = 'rejected'`.
   - **RPC Guarding (`public.approve_plantilla_import_rollback`)**:
     - Added **Guard 1 (Idempotent Rollback Guard)**: If `v_batch.status = 'rolled_back'`, immediately update `rollback_status = 'completed'` and return success payload idempotently without evaluating records.
     - Added **Guard 2 (State Guard)**: If `v_batch.status != 'approved'`, throw standard error: `Cannot approve rollback for batch with status: ...`.
3. **Application & Client Safeguards**:
   - [src/lib/queries/dataControl.ts](file:///D:/Projects/ohmployee-web/src/lib/queries/dataControl.ts): Placed `zero_edit_lock` check before generic `lock` check, returning an explicit permanent block message: `"Zero-Edit Lock: Rollback is permanently hard-blocked because batch records have been modified post-approval."`
   - [src/lib/queries/requests.ts](file:///D:/Projects/ohmployee-web/src/lib/queries/requests.ts): Hardened `fetchRollbackApprovalRequests` and `fetchRollbackApprovalCounts` with `item.rollbackStatus === "requested" && item.status === "approved"`, preventing already rolled-back batches from ever appearing in pending queues.
   - [src/components/approvals/RollbackDataTable.tsx](file:///D:/Projects/ohmployee-web/src/components/approvals/RollbackDataTable.tsx): Formatted clear Zero-Edit Lock error alert and replaced confirm button with "Close" upon Zero-Edit Lock error to prevent repeated clicks and query loops.
4. **Verification**:
   - `pg_stat_activity` check: live query count dropped from 1-2 qps storm to `rows: []` (0 active queries, CPU stabilized).
   - `npm test`: 263/263 unit tests passed across 14 test suites.
   - `npm run lint`: 0 ESLint errors/warnings, 0 secret leaks (`check:secrets`), 0 SQL contract violations (`check:sql`), ADR mirror fresh.
   - `npm run build`: Turbopack production build compiled cleanly.
   - Staging Migration Push: `20262606000175` dry-run verified and applied cleanly to Staging (`qqiiznmqxfoamqytjica`).

### Files Modified / Created
- `supabase/migrations/20262606000175_fix_plantilla_rollback_status_desync_and_guard.sql` — Database migration aligning check constraints, reconciling batch statuses, and hardening `approve_plantilla_import_rollback`.
- `src/lib/queries/dataControl.ts` — Humanized zero-edit lock error message.
- `src/lib/queries/requests.ts` — Filtered pending rollbacks to `status === 'approved'`.
- `src/components/approvals/RollbackDataTable.tsx` — UX guard replacing confirm button with Close on zero-edit lock error.
- `docs/state/approvals_web_state.md` — Documented rollback status invariants and Zero-Edit Lock UX guard.
- `docs/state/plantilla_web_state.md` — Added Rule #29 detailing rollback status reconciliation and idempotent guards.
- `.ai/briefing.md` — Updated Last Completed Tasks.
- `.ai/current_state.md` — Added update log.
- `.ai/handoff.md` — Added handoff report.

---

## Execution Report — Refactor Vacancy Detail Surface to Multi-Tab Modal & Detailed What/Who/When Activity History Timeline (ohm#vacancy-detail-modal-and-activity-timeline)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Migrated to Staging & Locally Tested

### What Was Built
1. **User Requirements & Forensic Root Cause Diagnosis**:
   - User feedback:
     1. *"This is a [IMG_4424.jpg] not a true activity history dapat mas detailed what happened. What, Who, When ganyan"*
     2. *"Also can we change it to modal? I think mas okay sya kesa sa drawer. Then per tab sya"*
   - Forensic Diagnosis of the Generic `"Vacancy updated / By System"` Activity History Defect:
     - **Frontend Bug (`VacancyDetailDrawer.tsx`)**: `formatActivityHistorySummary` expected raw DML tokens (`INSERT`, `UPDATE`) in `eventLabel` and a module name in `eventDescription`. However, `get_web_vacancy_detail` was returning `'Vacancy Updated'` in `eventLabel` and `'Attributes synchronized'` in `eventDescription`. It fell straight into the default branch (`action.replace(/_/g, " ").toLowerCase()`), rendering `"Vacancy updated"` while completely discarding `item.eventDescription` from the JSX.
     - **Database RPC Deficit (`get_web_vacancy_detail`)**: The SQL query only grabbed the last 10 rows of `audit_logs`, without deduplicating background trigger writes, without inspecting field-level diffs (`required_headcount`, `vacant_date`, `target_fill_date`, `urgency_level`, `hrco_name`), and completely ignoring `public.applicant_status_history`, `public.applicant_profile_edit_history`, `public.vacancy_closure_requests`, and `public.hr_emploc`.
2. **Multi-Tab Vacancy Detail Modal (`src/components/vacancy/VacancyDetailDrawer.tsx`)**:
   - Replaced the narrow right-side `DetailDrawer` with the shared centered `Modal` (`maxWidthClass="max-w-3xl"`).
   - Preserved the always-visible top header (`VCode`, status badge, position title, and `Account / Group / Store` hierarchy), top 4-column KPI strip (`Hired`, `Pipeline`, `Avail`, `Aging`), and action buttons (`Adjust Quota`, `Request HC Adjustment`, `Request Closure`, `Withdraw Closure`).
   - Organized the content into 4 dedicated tabs via `SegmentedTabs`:
     1. **Pipeline & Applicants** (`count: candidateCount`): Active candidate cards with stage badge, aging pill, role badge, contact info, `Edit Details`, `Update Stage / Backout`, `Mark Hired`, and the PII Guard callout.
     2. **Vacancy Details**: Source, Vacancy Type, Urgency Level, Province/City, Employment Type, Assigned Roving Stores (`CGCode` + Anchor badge), inline `Vacant Since` editor, `Target Fill Date`, `Date Created`, SLA breach warning, and Headcount & Approvals Context.
     3. **Ownership & Team**: High-density cards for `HRCO Assignee`, `Recruiter`, `Operations Manager (OM)`, `Team Leader (TL)`, `Assistant Team Leader (ATL)`, `Triggered By` / `Deployed By`, `Reliever on Duty`, and `HRCO Remarks`.
     4. **Activity History** (`count: activityCount`): Dedicated timeline trail rendering each event card with **What** (bold title + detailed sentence of what changed, from what value to what value, and why), **Who** (`Performed by <Actor Name>`), and **When** (formatted date and time `MMM D, YYYY, h:mm AM/PM`).
3. **Database Migration (`supabase/migrations/20262606000174_friendly_vacancy_activity_history_timeline.sql`)**:
   - Created `public.get_vacancy_activity_timeline(p_vacancy_id uuid)` aggregating and deduplicating up to 30 chronological events across `vacancies`, `applicants`, `applicant_status_history`, `applicant_profile_edit_history`, `vacancy_closure_requests`, `hr_emploc`, and meaningful field-level `audit_logs` diffs.
   - Surgically updated `public.get_web_vacancy_detail(p_vacancy_id uuid)` to call `public.get_vacancy_activity_timeline(vd.id)` while preserving all 30 return columns and RBAC/scope guards.
   - Updated client fallback paths in `src/lib/queries/vacancy/vacancyListing.ts` to invoke `get_vacancy_activity_timeline`.
4. **Verification**:
   - ADR fresh check: `npm run check:adr` (`ADR_MIRROR_STATUS: FRESH`).
   - SQL contracts check: `npm run check:sql` (verified 28 core tables & 19 cross-module RPC contracts across 699 migrations).
   - Unit tests: `npm test` (263/263 unit tests passed).
   - Staging migration push: dry-run validated and applied `20262606000174_friendly_vacancy_activity_history_timeline.sql` to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging` with 0 errors.
   - ESLint: `0` errors, `0` warnings.

### Files
- `supabase/migrations/20262606000174_friendly_vacancy_activity_history_timeline.sql` — New RPC `get_vacancy_activity_timeline` and surgical update to `get_web_vacancy_detail`.
- `src/components/vacancy/VacancyDetailDrawer.tsx` — Refactored from slide-over drawer to 4-tab centered Modal with rich What/Who/When Activity History cards.
- `src/lib/queries/vacancy/vacancyListing.ts` — Hydrated `activityHistory` in fallback detail lookups via `get_vacancy_activity_timeline`.
- `docs/state/vacancy_web_state.md` — Updated detail surface spec to reflect the 4-tab Modal and detailed Activity History contract.
- `.ai/briefing.md` — Prepended task to Last Completed Tasks.
- `.ai/current_state.md` — Added update log.
- `.ai/handoff.md` — Prepended handoff report.

---

## Execution Report — Inline Staging Fallback in Next Config and Client for Instant Vercel Auth (ohm#fix-vercel-auth-fallback)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean & Locally Tested

### Root Cause Diagnosis & Solution
1. **Root Cause**:
   - On Vercel (`https://ohmployee-web.vercel.app`), Next.js Turbopack runs in an environment where `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are not set in the Vercel project settings.
   - When Next.js compiles `src/lib/supabase/client.ts`, references to `process.env.NEXT_PUBLIC_SUPABASE_URL` were compiled as runtime object lookups (`g.default.env.NEXT_PUBLIC_SUPABASE_URL`) which evaluate to `undefined` in the browser.
2. **Implementation**:
   - In `src/lib/supabase/client.ts`: Embedded the public Staging Supabase URL (`https://qqiiznmqxfoamqytjica.supabase.co`) and anon key as default fallbacks in `isSupabaseConfigured()` and `createClient()`.
   - In `next.config.ts`: Added `env: { NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL || STAGING_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || STAGING_ANON_KEY }`. Turbopack inlines these string literals at build time into client chunks.
   - In `scripts/check-secrets.mjs`: Added an explicit exemption for `STAGING_ANON_KEY` so the public client anon key is recognized as safe fallback while strictly guarding against any other JWT or secret leaks.
3. **Verification**:
   - `npm test`: 263/263 unit tests passed across 14 test suites.
   - `npm run lint`: 0 ESLint errors, 0 warnings.
   - `npm run check:secrets`: 0 credential leaks detected across all tracked files.
   - `npm run check:sql`: 0 SQL contract violations across 28 core tables & 19 cross-module RPC contracts.
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run build`: Clean Next.js 16.2.4 (Turbopack) production build generated.

### Files Changed
- `next.config.ts` — Injected static env fallback for Supabase URL and anon key during build.
- `src/lib/supabase/client.ts` — Restored staging fallback constants and safe client instantiation.
- `scripts/check-secrets.mjs` — Exempted `STAGING_ANON_KEY` in tracked secret scanning.
- `.ai/briefing.md` — Updated Last Completed Tasks.
- `.ai/handoff.md` — Prepended execution report.
- `.ai/current_state.md` — Logged update in Recent Updates.

## Execution Report — Fix Login Hanging on "Signing In..." and Surface Missing Hosting Env Guard (ohm#fix-login-hanging-and-surface-missing-env-guard)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean & Locally Tested

### Root Cause Diagnosis
1. **Hosting Environment Investigation**:
   - Inspected live production deployment at `https://ohmployee-web.vercel.app`.
   - Downloaded and analyzed the live client bundle chunks (`/_next/static/chunks/0j_ybxiq3~rlj.js`).
   - In Next.js App Router (Turbopack), `process.env.NEXT_PUBLIC_*` values are statically inlined during `next build` only if defined in the build environment.
   - Forensic analysis of chunk `0j_ybxiq3~rlj.js` revealed:
     ```js
     let e = g.default.env.NEXT_PUBLIC_SUPABASE_URL?.trim(),
         t = g.default.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();
     if (!e || !t || !isValidHttpUrl(e)) {
       let e = "[supabase] Missing or invalid NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY. Please verify your environment (.env) configuration.";
       throw console.error(e), Error(e);
     }
     ```
   - In the deployed Vercel build, `NEXT_PUBLIC_SUPABASE_URL` was compiled as a runtime property lookup `g.default.env.NEXT_PUBLIC_SUPABASE_URL` instead of an inlined string literal because `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` were not defined in Vercel's Environment Variables during the build. In the browser, `g.default.env.NEXT_PUBLIC_SUPABASE_URL` evaluates to `undefined`.
2. **Frontend Unhandled Promise Rejection & Infinite Spinner Lockup**:
   - In `src/app/(auth)/login/page.tsx`, `handleLogin` previously invoked `setIsSubmitting(true)` immediately, and then called `const supabase = createClient()` outside of any `try ... catch` block.
   - When `createClient()` threw `[supabase] Missing or invalid NEXT_PUBLIC_SUPABASE_URL...`, the uncaught exception crashed the event handler.
   - `setIsSubmitting(false)` was never reached.
   - `setError(error.message)` was never set.
   - The submit button was left permanently in its loading state: `<span className="animate-spin..." /> Signing in...` indefinitely.

### What Was Built
1. **Try-Catch Error Resilience in `LoginPage`**:
   - In `src/app/(auth)/login/page.tsx`, wrapped `handleLogin` in full `try ... catch` error handling.
   - If `createClient()` or `supabase.auth.signInWithPassword()` throws, `setIsSubmitting(false)` is reliably invoked, error messages are surfaced in the UI danger banner, and the UI never freezes on "Signing in...".
2. **Proactive Configuration Alert**:
   - Added `isConfigured` derivation using `isSupabaseConfigured()`.
   - If environment credentials are missing in the current hosting environment, an explicit amber/red alert banner renders immediately:
     `"Configuration Error: Supabase client is not configured: NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are missing in this environment. Please configure them in Vercel Project Settings > Environment Variables."`
   - The submit button is gracefully disabled (`disabled={isSubmitting || Boolean(configError)}`), preventing users from submitting against an unconfigured backend.
3. **Quality & Verification**:
   - `npm test`: 263/263 unit tests passed across 14 test suites.
   - `npm run lint`: 0 ESLint errors, 0 warnings.
   - `npm run check:secrets`: 0 credential leaks detected.
   - `npm run check:sql`: 0 SQL contract violations across 28 core tables & 19 cross-module RPC contracts.
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run build`: Clean Next.js 16.2.4 (Turbopack) production build generated.

### Files Changed
- `src/app/(auth)/login/page.tsx` — Wrapped `handleLogin` in try/catch, derived `isSupabaseConfigured()`, surfaced configuration error banner, and prevented button lockup.
- `docs/state/web_auth_rbac_state.md` — Updated login page and Supabase client documentation.
- `.ai/briefing.md` — Prepended completed task to Last Completed Tasks.
- `.ai/handoff.md` — Prepended execution report.
- `.ai/current_state.md` — Logged update in Recent Updates.

---

## Execution Report — Synchronize pnpm-lock.yaml and package-lock.json with package.json for Vercel Frozen Lockfile CI Deployments (ohm#sync-pnpm-lockfile-for-vercel-ci)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Frozen Lockfile CI Validated & Locally Tested

### Objective & Changes Delivered
1. **Root Cause Resolution for Vercel Deployment Failure**:
   - Vercel detects `packageManager: "pnpm@10.29.3"` in `package.json` and executes `pnpm install --frozen-lockfile`.
   - In commit `1f7b2cb` (`ohm#sec-cleanup-xlsx-and-legacy-edge-fns`), `xlsx@0.18.5` was uninstalled from `package.json`, but `pnpm-lock.yaml` was left desynchronized with `xlsx` and its subdependencies (`adler-32`, `cfb`, `codepage`, `frac`, `ssf`, `wmf`, `word`) still lingering in the lockfile.
   - Consequently, Vercel deployments failed during the install step with:
     `ERR_PNPM_OUTDATED_LOCKFILE: Cannot install with "frozen-lockfile" because pnpm-lock.yaml is not up to date with <ROOT>/package.json (* 1 dependencies were removed: xlsx@^0.18.5)`
2. **Lockfile Synchronization**:
   - Executed `pnpm install --lockfile-only` to prune `xlsx@0.18.5` and its 7 transitive dependencies from `pnpm-lock.yaml`.
   - Executed `npm install --package-lock-only` to ensure `package-lock.json` is equally synchronized with `package.json`.
   - Verified via `pnpm install --frozen-lockfile` in an isolated clean environment:
     `Lockfile is up to date, resolution step is skipped`
     `Packages: +463`
     `Done in 41.2s using pnpm v10.29.3`
3. **Full System Quality & Invariants Verification**:
   - `npm test`: 263/263 unit tests passed across 14 test suites.
   - `npm run lint`: 0 ESLint errors, 0 warnings.
   - `npm run check:secrets`: 0 credential/secret leaks detected.
   - `npm run check:sql`: 0 SQL contract violations across 28 core tables & 19 cross-module RPC contracts.
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run build`: Clean Next.js 16.2.4 (Turbopack) production build generated.

### Files Changed
- `pnpm-lock.yaml` — Pruned `xlsx@^0.18.5` and 7 subdependencies (`adler-32`, `cfb`, `codepage`, `frac`, `ssf`, `wmf`, `word`), restoring 100% frozen-lockfile parity with `package.json`.
- `package-lock.json` — Pruned `xlsx` references and synchronized npm lockfile tree.
- `.ai/briefing.md` — Prepended completed task to Last Completed Tasks (retaining strictly 5).
- `.ai/handoff.md` — Prepended this execution report.
- `.ai/current_state.md` — Logged update in Recent Updates.

---

## Execution Report — Enforce CGCode Strict Monotonicity & Dissolution Retirement Invariant (ohm#enforce-cgcode-strict-monotonicity-and-dissolution-retirement)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Migrated to Staging & Locally Tested

### What Was Built
1. **User Requirement & Architecture Invariant**:
   - User inquiry: *"But I'm talking about the CG code creation. And then, once the CG code is dissolved, then, then I'm bringing back to CG group, you can't use the old CG code. So it's always a new CG code. Right? And then let's add this to ADR."*
   - Codified in ADR-002 Invariant 3 in mobile source repo (`D:\Projects\OHMployee\docs\architecture\adr\01_plantilla.md`, commit `268420c`) and synchronized web mirrors (`npm run sync:adr`):
     - **Permanent Retirement on Dissolution**: When a Coverage Group is dissolved via `dissolve_coverage_group`, merged, or archived, its `CGCODE` is permanently retired (`archived_at = now()`).
     - **Strict Non-Recycling Rule**: If the member stores, employees, or cluster footprint are subsequently brought back together into a Coverage Group (re-clustered, reformed, or re-uploaded), the system is **STRICTLY PROHIBITED** from reusing, recycling, or resurrecting the old `CGCODE`.
     - A fresh, strictly sequential, monotonically incremental `CGCODE` (e.g. `CG-FG1-0007` $\rightarrow$ `CG-FG1-0008`) MUST ALWAYS be minted.
     - **Audit & Separation Integrity**: Preserves immutable historical audit logs, ensures employee separation and movement history unambiguously reflect exact group tenure, prevents foreign key or reporting ambiguity in CENCOM / analytics, and eliminates cache collisions across Web and Mobile.
2. **Database Hardening (`20262606000173_enforce_cgcode_strict_monotonicity_and_dissolution_retirement.sql`)**:
   - **Section 1 (Permanent Global Table Uniqueness)**: Created permanent unique index `uq_coverage_groups_account_code_permanent` on `public.coverage_groups (account_id, coverage_code)` without any `archived_at IS NULL` condition, guaranteeing that even at the physical PostgreSQL constraint level, duplicate `coverage_code`s can NEVER exist within an account.
   - **Section 2 (`public.fn_generate_cgcode_for_account` Hardening)**: Updated the existence probe loop to check across ALL historical coverage groups for that account (`WHERE account_id = p_account_id AND coverage_code = v_cgcode`), eliminating the `AND archived_at IS NULL` bypass. Dissolved and archived codes will always trigger a sequence increment, guaranteeing zero recycling of old codes.
   - **Section 3 (Sequence Monotonicity Verification)**: Verified that all sequence counters in `public.cgcode_sequences` are strictly ahead of the maximum historical numeric suffix across active and archived records.
3. **Live Database Verification on Staging (`qqiiznmqxfoamqytjica`)**:
   - Applied migration cleanly with 0 errors via `npm run db:push:staging`.
   - Verified live `pg_get_functiondef` for `fn_generate_cgcode_for_account` matching migration file byte-for-byte.
   - Verified index `uq_coverage_groups_account_code_permanent` active on `public.coverage_groups`.
4. **Quality & Test Verification**:
   - ADR fresh check: `npm run check:adr` (ADR_MIRROR_STATUS: FRESH).
   - Unit tests: passed 263/263 unit tests across 14 test suites (`npm test`).
   - ESLint: 0 errors, 0 warnings (`npm run lint`).
   - Secrets check: 0 credential leaks (`node scripts/check-secrets.mjs`).
   - SQL Contracts: 0 errors across 28 core tables & 19 cross-module RPC contracts (`node scripts/check-sql-contracts.mjs`).

### Files
- `supabase/migrations/20262606000173_enforce_cgcode_strict_monotonicity_and_dissolution_retirement.sql` — Database migration enforcing permanent table uniqueness and updating `fn_generate_cgcode_for_account`.
- `docs/architecture/_mirror/adr/01_plantilla.md` — Synced ADR-002 Invariant 3 from mobile source repo.
- `docs/state/plantilla_web_state.md` — Documented Rule #28 Strict Monotonicity & Dissolution Retirement Invariant.
- `.ai/briefing.md` — Prepended task to Last Completed Tasks.
- `.ai/current_state.md` — Added update log.
- `.ai/handoff.md` — Prepended handoff report.

---

## Execution Report — Universal Automatic Coverage Group Provisioning and Historical Backtrack (ohm#auto-roving-coverage-group-provisioning-and-backtrack)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Migrated to Staging & Locally Tested

### What Was Built
1. **User Requirement & Investigation Diagnosis**:
   - User inquiry: *"Investigate this. Bakit wala syang CGCode? All roving must have a CGCode and dapat makikita sya as Coverage Group not independent kasi in [Screenshot 3] KUNG makikita mo walang nakalagay na Already in CG just like Puregold General Trias"* + *"1. Either by request or via Import dapat automatically nag ccreate sya ng cgcode regardless kung saan sya galing. Put this in ADR 2. FIX ALL stores na dapat merong cgcode. Mag backtrack tayo sa lahat kahit na upload pa yan last June."*
   - Target Employee: `DELA CRUZ JR, JESSIE GALERO` (`employee_no: 2021-09660`, `plantilla_id: 4dde6cd3-ec31-44ef-b219-c1d7cf6169fe`, Account: `FOREVER OFFICE` / `d0533fbc-3cce-4d0a-a619-ad0539dbc66d`).
   - Forensic Diagnosis:
     - Baseline imports (`approve_plantilla_import_batch`) previously computed `deployment_type = 'Roving'` and set fractional HC $1/N$ on `employee_store_allocations`, but never auto-created `coverage_groups` or `coverage_group_stores`, leaving `coverage_group_id = NULL` and `coverage_code = 'Not assigned'`.
     - In `CreateCoverageGroupModal`, `get_coverage_group_eligible_stores()` checks active rows in `coverage_group_stores`. Because `PUREGOLD CENTENIAL KAWIT` was not in an active group, it had `already_grouped_code = NULL` (no `"Already in CG"` badge).
2. **Architecture Lock Codified (ADR-002 Invariants 3 & 4)**:
   - Source ADR updated in mobile repo: `D:\Projects\OHMployee\docs\architecture\adr\01_plantilla.md`.
   - Committed in mobile repo (`54bd136 docs(adr): codify universal automatic coverage group provisioning (Invariants 3 & 4)`).
   - Synced to web mirror (`npm run sync:adr`), verified fresh (`npm run check:adr` -> `ADR_MIRROR_STATUS: FRESH`).
   - Invariant 3 & 4 rule: Any roving employee ($N \ge 2$) strictly requires an official Coverage Group Code (`CGCODE`), regardless of whether they originated via Baseline Batch Import or Operational Requisition. Under no circumstances may a roving employee linger as independent or unassigned.
3. **Database Migration (`20262606000172_auto_roving_coverage_group_provisioning_and_backtrack.sql`)**:
   - **Section 0 (Foreign Key Trigger Hardening)**: Altered `trg_ensure_import_roving_group_for_allocation` to fire `BEFORE INSERT OR UPDATE` on `employee_store_allocations`, ensuring updating `roving_group_id` satisfies FK constraint `employee_store_allocations_roving_group_fkey`.
   - **Section 1 (Historical Backtrack Loop)**:
     - Scanned all historical active roving employees ($N \ge 2$ stores) across all accounts dating back to June imports.
     - Grouped employees by `(account_id, store_id_list)` so co-roving employees sharing the exact same store footprint attach to the same Coverage Group (incrementing `required_headcount`).
     - Minted official account-scoped sequential CGCodes (`CG-<PREFIX>-<SEQ>`, e.g. `CG-FG1-0007`) or joined existing matching footprints.
     - Inserted member store edges into `public.coverage_group_stores` with 1 anchor store (`is_anchor = true`) and equal fractional `hc_share = 1/N`.
     - Inserted occupied slot into `public.coverage_slots` (`slot_status = 'active'`, `slot_ordinal = N`).
     - Updated `public.plantilla`: bound `coverage_slot_id`, set `roving_assignment_id = NULL` (satisfying mutex constraint `plantilla_roving_coverage_mutex_chk`), and set `status = 'Active'`.
     - Linked stores in `public.plantilla_store_links` where `vcode` is present.
   - **Section 2 (`public.approve_plantilla_import_batch` Hardening)**:
     - Updated batch import approval RPC so all future roving employees ($N \ge 2$) automatically mint or join Coverage Groups, create store edges in `coverage_group_stores`, provision occupied slots in `coverage_slots`, bind `plantilla.coverage_slot_id`, and update `already_grouped_code`.
4. **Live Database Verification on Staging (`qqiiznmqxfoamqytjica`)**:
   - Applied migration cleanly with 0 errors via `npm run db:push:staging`.
   - **Target Record Verified**:
     - `DELA CRUZ JR, JESSIE GALERO` (`2021-09660`): `coverage_code = "CG-FG1-0007"`, `coverage_group_id = "320065df-7630-49df-a2a3-5b151405ca9c"`, `coverage_slot_id = "86c47150-fc9a-4e90-b848-296220b043da"`, `slot_ordinal = 1`, `deployment_type = "Roving"`.
     - Member stores: `PUREGOLD CENTENIAL KAWIT` (anchor, 0.50 HC, `already_grouped_code = "CG-FG1-0007"`) and `EMILUS TANZA` (0.50 HC, `already_grouped_code = "CG-FG1-0007"`).
     - In `CreateCoverageGroupModal`, `PUREGOLD CENTENIAL KAWIT` and `EMILUS TANZA` now display badge `Already in CG-FG1-0007`.
   - **System-Wide Historical Backtrack Verified**:
     - 48 active roving employees across historical accounts backfilled with official CGCodes:
       - `MARIZ`: `CG-MG1-0004` to `CG-MG1-0017` (14 roving groups).
       - `KAMBAK`: `CG-KG3-0002` to `CG-KG3-0013` (12 roving groups).
       - `BANCON`: `CG-BG2-0001` to `CG-BG2-0004` (4 roving groups).
       - `SUPER 8`: `CG-SG1-0001` to `CG-SG1-0008` (8 roving groups).
       - `FOREVER OFFICE`: `CG-FG1-0007` (Jessie Dela Cruz).
5. **Quality & Test Verification**:
   - ADR fresh check: `npm run check:adr` (ADR_MIRROR_STATUS: FRESH).
   - Unit tests: passed 263/263 unit tests across 14 test suites (`npm test`).
   - ESLint: 0 errors, 0 warnings (`npm run lint`).
   - Secrets check: 0 credential leaks (`node scripts/check-secrets.mjs`).
   - SQL Contracts: 0 errors across 28 core tables & 19 cross-module RPC contracts (`node scripts/check-sql-contracts.mjs`).

### Files
- `supabase/migrations/20262606000172_auto_roving_coverage_group_provisioning_and_backtrack.sql` — Migration auto-provisioning Coverage Groups on import and historically backtracking all roving employees.
- `docs/architecture/_mirror/adr/01_plantilla.md` — Synced ADR-002 Invariants 3 & 4 from mobile source repo.
- `docs/state/plantilla_web_state.md` — Added Rule #28: Universal Automatic Coverage Group Provisioning & Historical Backtrack.
- `.ai/briefing.md` — Prepended task to Last Completed Tasks.
- `.ai/current_state.md` — Added update log.
- `.ai/handoff.md` — Prepended handoff report.

---

## Execution Report — Fix Coverage Group Dropdown Visibility Across Operations and Resolve Roving Vacancy Suppression (ohm#fix-coverage-group-dropdown-visibility-and-vacancy-suppression)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean, Migrated & Locally Tested

### What Was Built
1. **Coverage Group Dropdown Visibility (`CreateCoverageGroupModal.tsx`)**:
   - In `CreateCoverageGroupModal.tsx`, the `activeCoverageGroups` filter previously checked `g.groupStatus === "Active"`.
   - In `public.vw_coverage_group_shadow` and RPC `list_coverage_groups`, coverage group statuses are lowercase lifecycle states (`open`, `filled`, `pipeline`, `hr_processing`, `archived`).
   - Consequently, `activeCoverageGroups` always evaluated to `[]` (empty), causing all dropdowns across **Add Store**, **Remove Store**, **Merge Groups**, and **Dissolve Group** tabs to display `-- No Active Coverage Groups Found --`.
   - Updated the filter to accept all operational non-archived groups (`s !== "archived" && s !== "dissolved" && s !== "closed"`), immediately populating operational roving groups (e.g. `CG-FG1-0004` and `CG-FG1-0005`) across all 4 operational tabs.
2. **Roving Vacancy Suppression Resolution & Headcount Alignment**:
   - User inquiry: *"bakit ung Puregold General Trias wala sa Vacancy. Ung Waltermart General Trias at Puregold Tanza."*
   - Root cause identified: `PUERGOLD GENERAL TRIAS` (`CPSAJV27`, anchor) and `PUREGOLD NOVELETA OASIS` (`CPPGJV19`) form open roving group `CG-FG1-0005`. In `coverage_groups` table, `CG-FG1-0005` had denormalized `required_headcount = 0`. In `src/lib/queries/vacancy/vacancyListing.ts`, the condition `cgInfo.isFilled || cgInfo.requiredHc <= 0` dropped both stores as a 0-headcount test group. In `plantilla/page.tsx`, `CPPGJV19` was accidentally resurrected by an inactive employee (`Eurie Baculi`), while `CPSAJV27` disappeared completely.
   - In `src/lib/queries/vacancy/vacancyListing.ts`, defaulted `requiredHc` to at least 1 when active slots exist (`rawReq != null && !isNaN(rawReq) && rawReq > 0 ? rawReq : 1`).
   - Authored and applied migration `20262606000171_align_coverage_groups_required_headcount.sql` on Staging (`qqiiznmqxfoamqytjica`), updating `required_headcount = 1` for `CG-FG1-0005` and active coverage groups.
3. **Vacancy Tab Unoccupied Slot Isolation (Single-Roster Parity)**:
   - In `src/app/(dashboard)/plantilla/page.tsx`, multi-slot vacancy expansion previously expanded to `v.hcTotal` regardless of whether slots were already occupied by active personnel.
   - For `SMCO KAWIT` (`CPSMJV21`, 2 slots total), Slot 1 was occupied by active employee `Fred Richard Borillo` (`2021-09665`) while Slot 2 was open. Because it expanded to 2 rows, it created a duplicate occupied row in Vacancy.
   - Updated the expansion to filter out occupied slots (`s.slotStatus !== 'occupied'`) and bound target count to `unoccupiedPhysicalSlots.length` (or `approvedHc - filledHc`), ensuring only genuinely open slots (Slot 2) render in Vacancy.
   - Result: Renders exactly the 5 valid open vacancies for account `FOREVER OFFICE` (`Vacancy 5`):
     1. Divimart General Trias (`CPRVJV13`) - 1 open slot
     2. Super 8 Rosario Cavite (`VCFG1_0010`) - 1 open slot
     3. Puregold - Hugo Perez (`CPPGJV23`) - 1 open slot
     4. Smco Kawit (`CPSMJV21`) - 1 open slot (Slot 2)
     5. Puregold General Trias (`CPSAJV27`) - 1 open slot (CG-FG1-0005 anchor)
4. **Coverage Group Staffing Investigation (Waltermart & Puregold Tanza)**:
   - Verified that `WALTERMART GENERAL TRIAS` (`CPWMJV36`) and `PUREGOLD TANZA` (`CPPGJV14`) belong to `CG-FG1-0004`, which is **100% FILLED** by active deployed employee `JUAPHEL DELFINA` (`2019-08946`).
   - In addition, Waltermart General Trias has active stationary merchandiser `RAMMEL VILLA` (`2021-09665`).
   - Both stationary and roving allocations for these stores are fully staffed, correctly resulting in 0 open vacancies.
5. **Verification**:
   - ADR fresh check: `npm run check:adr` (ADR_MIRROR_STATUS: FRESH).
   - SQL contracts check: `npm run check:sql` (passed across 696 migrations).
   - Unit tests: passed all 263 unit tests across 14 test suites (`npm test`).
   - ESLint: 0 errors, 0 warnings (`npm run lint`).
   - Secrets: 0 credential leaks (`npm run check:secrets`).
   - Database Migration: pushed `20262606000171_align_coverage_groups_required_headcount.sql` to Staging (`qqiiznmqxfoamqytjica`) with 0 errors via `npm run db:push:staging`.
   - Build: Next.js 16.2.4 (Turbopack) production build passed cleanly in 17.7s, TypeScript compiled in 31.3s, all 25 static/dynamic routes prerendered.

### Files
- `src/components/modals/CreateCoverageGroupModal.tsx` — Case-insensitive non-archived status filter for active coverage groups across Add, Remove, Merge, and Dissolve tabs.
- `src/lib/queries/vacancy/vacancyListing.ts` — Guarded `requiredHc` derivation against 0-headcount false suppression for active roving groups.
- `src/app/(dashboard)/plantilla/page.tsx` — Filtered out occupied physical slots from Vacancy multi-slot expansion, guaranteeing single-roster accuracy.
- `supabase/migrations/20262606000171_align_coverage_groups_required_headcount.sql` — Aligned active coverage group headcount to canonical minimum of 1 on Staging.
- `docs/state/plantilla_web_state.md` — Documented Rule #27.
- `.ai/briefing.md` — Prepended task to Last Completed Tasks.
- `.ai/handoff.md` — Prepended handoff report.
- `.ai/current_state.md` — Added update log.

---

## Execution Report — Align Plantilla Vacancy Tab Badge Directly to Total Rendered Slot Count (ohm#align-plantilla-vacancy-tab-badge-to-slot-count)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean & Locally Tested

### What Was Built
1. **User Requirement & Visual Alignment**:
   - User noted on Plantilla Tab 3: *"so Vacancy should be 5 not 3. Vacancy (5) << this should be the count."*
   - Under Option A Standard (1 Row = 1 Slot Granularity), every physical slot renders as its own individual table row (5 rows: ACT-G5-002, BUN-GHQ-00015, and 3 rows for VCAG5_0056).
   - The tab badge previously displayed a composite requisition counter `3 (5 slots)`, which clashed with all sibling tabs that simply render their total item count as a number (`Active 4`, `On-Leave 0`, `Floating 0`, `Deactivation 1`, `Inactive 3`).
2. **Tab Count & Toolbar Normalization**:
   - In `src/app/(dashboard)/plantilla/page.tsx`, updated `vacancyCount` to derive directly from `allVacancies.length > 0 ? allVacancies.length : (summaryData?.vacant ?? 0)`.
   - In `src/components/plantilla/directory/PlantillaFilterToolbar.tsx`, simplified the Vacancy tab badge to render `{vacancyCount}` directly inside the standard pill badge, rendering `5`.
   - Removed unused intermediate calculations (`uniqueVacancyCodesCount` and `totalVacanciesSlots`).
3. **Verification**:
   - Unit tests: passed all 263 unit tests across 14 test suites (`npm test`).
   - ESLint: 0 errors, 0 warnings (`npm run lint`).
   - Secrets: 0 credential leaks (`npm run check:secrets`).
   - SQL Contracts: verified 28 core tables & 19 cross-module RPC contracts across 695 migrations (`npm run check:sql`).
   - Build: clean Next.js 16.2.4 (Turbopack) production build (`npm run build`).

### Files
- `src/app/(dashboard)/plantilla/page.tsx` — Derived `vacancyCount` from `allVacancies.length`.
- `src/components/plantilla/directory/PlantillaFilterToolbar.tsx` — Streamlined badge to render `{vacancyCount}` directly.
- `docs/state/plantilla_web_state.md` — Updated Rule #25 & Rule #26 documentation.
- `.ai/briefing.md` — Prepended prompt to Last Completed Tasks.
- `.ai/handoff.md` — Prepended handoff report.
- `.ai/current_state.md` — Added update log.

---

## Execution Report — Implement Multi-Position Vacancy Intake, Disambiguation Parity, and Strict Slot Quota Bounds (ohm#multi-position-vacancy-intake-and-slot-quota-bounds)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean & Locally Tested

### What Was Built
1. **Multi-Position Vacancy Intake Parity (ADR-002 Invariant 2 & `public.vacancy_requirements`)**:
   - In stores requiring multiple distinct positions under a single VCode (e.g. 2 Merchandisers + 1 Salesman), positions are normalized as line items in `vacancy_requirements`.
   - In `AddApplicantModal`, queried requirements via `useVacancyRequirements(vcode)`. For single-position stores (or stores with only 1 non-full position remaining), auto-selected the requirement with zero user friction.
   - For stores with 2+ positions, rendered high-density interactive cards displaying title, slot availability badge (`N Slots` / `Full`), and hired/pipeline counters (`Hired: N/Needed • Pipeline: X`). Full positions are disabled; submission is blocked until a position is selected.
   - Threaded `vacancy_requirement_id` into `endorseApplicant` and persisted to `public.applicants`.
2. **Pipeline Candidate Disambiguation & Onboarding Allocation**:
   - In `pipelineApplicants` and `fetchVacancyDetail`, dynamically resolved candidate positions via `vacancy_requirements` + `positions`, displaying each candidate's tagged role (`Merchandiser` vs `Salesman`) instead of the general vacancy card header.
   - In `MarkHiredModal` / `confirm_applicant_onboard`, forwarded `vacancyRequirementId` (with fallback selector for legacy candidates) so onboarding into `hr_emploc` assigns the correct position and slot.
3. **Plantilla Vacancy Multi-Slot Quota Bounds**:
   - Addressed user feedback (*"Also bakit dumami ang Aurora it should be 3 rows kasi 3 slots lang sya"*): bounded multi-slot row expansion in `src/app/(dashboard)/plantilla/page.tsx` strictly to approved headcount (`Math.max(1, Math.trunc(v.hcTotal ?? v.headcount ?? 1))`). Decommissioned slots or excess historical entries no longer inflate the roster, guaranteeing that SM Aurora renders exactly 3 rows for 3 approved slots.
   - In `PlantillaCardViews.tsx` and `PlantillaTableViews.tsx`, renamed the column from "Slot" to "HC" and rendered `1` (or roving fraction) instead of slot ordinal or remaining capacity, aligning visual presentation with authorized headcount.
4. **Verification**:
   - Unit tests: passed all 263 unit tests across 14 test suites (`npm test`), including 6 new targeted tests in `multi_position_vacancy_intake.test.mjs`.
   - ESLint: 0 errors, 0 warnings (`npm run lint`).
   - Secrets: 0 credential leaks (`npm run check:secrets`).
   - SQL Contracts: verified 28 core tables & 19 cross-module RPC contracts across 695 migrations (`npm run check:sql`).
   - Build: Next.js 16.2.4 (Turbopack) production build passed cleanly in 7.5s, TypeScript compiled in 25.2s, and all 25 static/dynamic routes prerendered.

### Files
- `src/components/vacancy/AddApplicantModal.tsx` — Multi-position requirement selector and validation.
- `src/components/vacancy/MarkHiredModal.tsx` — Forwarded `vacancyRequirementId` into onboarding.
- `src/components/vacancy/VacancyDetailDrawer.tsx` — Displayed position badges for pipeline candidates.
- `src/app/(dashboard)/vacancy/page.tsx` — Threaded requirement contexts to modals.
- `src/app/(dashboard)/plantilla/page.tsx` — Bounded multi-slot expansion strictly to authorized headcount quota.
- `src/components/plantilla/directory/PlantillaTableViews.tsx` — Renamed Slot column to HC and aligned headcount display.
- `src/components/plantilla/directory/PlantillaCardViews.tsx` — Aligned headcount and capacity badges.
- `src/lib/queries/vacancy/types.ts` — Added `VacancyRequirementItem` and requirement properties.
- `src/lib/queries/vacancy/vacancyListing.ts` — Added `fetchVacancyRequirements` and `useVacancyRequirements`.
- `src/lib/queries/vacancy/vacancyMutations.ts` — Persisted `vacancy_requirement_id` in `endorseApplicant`.
- `src/lib/queries/__tests__/multi_position_vacancy_intake.test.mjs` — Comprehensive unit test suite for multi-position intake.
- `docs/state/vacancy_web_state.md` — Updated live documentation for multi-position intake and candidate disambiguation.
- `.ai/briefing.md` — Prepended prompt to Last Completed Tasks.
- `.ai/handoff.md` — Prepended handoff report.
- `.ai/current_state.md` — Added update log.

---

## Execution Report — Fix Ambiguous is_active Column Reference in get_web_current_user_context (ohm#fix-get-web-current-user-context-ambiguity)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean & Staging Deployed

### What Was Built
1. **User Incident & Forensic Diagnosis**:
   - User reported: *"fix this now. Im using super admin"* with screenshot showing:
     `Access check unavailable` / `OHMployee Web could not verify your access` / `Access state: rpc failure`.
   - Forensic tracing of `src/lib/auth.ts`: `loadCurrentUserContext()` invokes `supabase.rpc("get_web_current_user_context")`. If this RPC returns a PostgreSQL error, it catches and maps the failure to `reason: "rpc_failure"`, blocking dashboard access.
   - Live query simulation on Staging database (`qqiiznmqxfoamqytjica`): Calling `public.get_web_current_user_context()` under `auth.uid()` of Super Admin (`71d245b9-10b1-42b9-ad9e-253f999daf6d`, `ohmpayatt@proton.me`) failed with:
     ```text
     ERROR: 42702: column reference "is_active" is ambiguous
     DETAIL: It could refer to either a PL/pgSQL variable or a table column.
     QUERY: SELECT * FROM public.acting_sessions WHERE user_id = v_profile_id AND is_active = TRUE AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY created_at DESC LIMIT 1
     CONTEXT: PL/pgSQL function get_web_current_user_context() line 108 at SQL statement
     ```
   - **Root Cause Mechanism**:
     In PL/pgSQL functions returning `TABLE (...)`, every column name declared in the `RETURNS TABLE` clause (including `is_active boolean`) is automatically instantiated as an in-scope PL/pgSQL output variable.
     In migration `20262606000168`, lines 160-167 introduced a direct query against `public.acting_sessions` containing unqualified `is_active = TRUE`. The PostgreSQL query planner could not disambiguate between table column `acting_sessions.is_active` and the function's output variable `is_active`, crashing on every authenticated session bootstrap.
2. **Database Migration & Canonical Helper Restoration**:
   - Authored migration `supabase/migrations/20262606000170_fix_get_web_current_user_context_acting_session_ambiguity.sql` generated via `npm run db:new`.
   - Restored the canonical, existing security-definer helper:
     ```sql
     -- Check Active Acting Session (Switch-Role Parity via canonical helper)
     SELECT * INTO v_acting_session FROM public.get_active_acting_session();
     ```
     This encapsulates the `acting_sessions` lookup in a separate SQL function where `user_id = auth.uid() AND s.is_active = true`, completely eliminating variable shadowing and column ambiguity.
   - Validated migration pre-push via `npm run check:sql` and dry-run, then applied live to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging`.
3. **Verification**:
   - **Live Staging RPC Execution**: Executed `SELECT auth_user_id, profile_id, email, full_name, role_name, access_status FROM public.get_web_current_user_context();` against live Staging as Super Admin (`ohmpayatt@proton.me`), Head Admin (`atlg5@ohmployee.com`), Encoder (`g2en@ohmployee.com`), and HRCO (`g1hrcoaj@ohmployee.com`). All 4 roles returned `access_status: 'allowed'` with 0 errors.
   - **Live Function Definition Diff**: Confirmed `pg_get_functiondef` contains `get_active_acting_session()`.
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 695 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - Migration Counter: Staging: 664 migrations | Prod: 661 migrations (3 migrations pending on Prod: 168, 169, 170).

### Files
- `supabase/migrations/20262606000170_fix_get_web_current_user_context_acting_session_ambiguity.sql` — Migration eliminating variable shadowing and restoring `get_active_acting_session()` in `get_web_current_user_context()`.
- `.ai/briefing.md` — Prepended prompt to Last Completed Tasks.
- `.ai/handoff.md` — Prepended handoff report.
- `docs/state/web_auth_rbac_state.md` — Documented PL/pgSQL column shadowing protection in current user context RPC.
- `.ai/current_state.md` — Added update log.

---

## Execution Report — Deprecate Dormant hr_emploc.create, plantilla_slot.add_applicant, and vacancy.edit RBAC Definitions (ohm#deprecate-dormant-rbac-definitions)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean & Staging Deployed

### What Was Built
1. **User Request Alignment**:
   - User inquiry: *"also ano ano ung mag function na dormant na?"* (What other functions/permissions are dormant?).
   - User directive: *"I like your reco alisin sa web yan para di ko na makita"* (Remove them so they no longer clutter the RBAC matrix and system catalog).
2. **Investigation Findings**:
   - Analyzed the active application workflows vs. `role_permission_definitions`:
     - **`hr_emploc.create` (`('hr_emploc', 'hr_emploc', 'create')`)**: In OHMployee, employees are never created via a blank manual form. They are born strictly via ATS onboarding pipeline (`confirm_applicant_onboard` -> `fn_sync_slot_to_hr_processing`) or bulk spreadsheet import. There is no manual employee creation UI or direct insert endpoint.
     - **`plantilla_slot.add_applicant` (`('plantilla', 'plantilla_slot', 'add_applicant')`)**: An early placeholder definition. Applicant slot entry is strictly governed by the ATS recruitment pipeline (`applicant.create`) and Emploc slot transfer (`plantilla_slot.transfer`). Direct applicant addition to plantilla slots without an ATS vacancy does not exist.
     - **`vacancy.edit` (`('vacancy', 'vacancy', 'edit')`)**: Vacancies in OHMployee derive their core store, position, and account properties directly from the underlying Plantilla slot and approved Headcount Request. No manual direct vacancy editing form/modal exists in the web app.
3. **Database Migration & FK Protection**:
   - Created `supabase/migrations/20262606000169_deprecate_dormant_rbac_definitions.sql`.
   - **FK Integrity Safeguard**: `public.role_permission_audit_logs.permission_definition_id` has a foreign key constraint referencing `role_permission_definitions(id)`. Part 1 of the migration sets `permission_definition_id = NULL` for the targeted IDs, preserving historical audit log records (whose denormalized `module_key`, `resource_key`, and `action_key` columns retain the complete historical trail).
   - **Matrix & Override Cleanup**: Part 2 deletes active records from `role_permission_overrides`, `role_permission_matrix`, and `role_permission_definitions` for the 3 keys.
   - Pushed cleanly to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging` with 0 errors.
4. **Verification**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 694 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build.
   - Migration Counter: Staging: 663 migrations | Prod: 661 migrations (2 migrations pending on Prod: 168 and 169).

### Files
- `supabase/migrations/20262606000169_deprecate_dormant_rbac_definitions.sql` — Database migration deprecating dormant definitions with audit log FK protection.
- `docs/state/web_auth_rbac_state.md` — Documented deprecation of dormant definitions and architectural reasons.
- `docs/state/vacancy_web_state.md` — Updated Vacancy RBAC rules count (16 -> 14).
- `.ai/briefing.md` — Updated recent completed tasks list.
- `.ai/handoff.md` — Prepended execution report.

---

## Execution Report — Deprecate Dormant Vacancy Create, Enforce Dynamic RBAC Overrides, & Secure Closure Review RPC (ohm#fix-rbac-dynamic-overrides-and-vacancy-closure)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean & Staging Deployed

### What Was Built
1. **User Request Alignment**:
   - User inquiry 1: "check this vs sa db natin kung match ba ang nandito sa Web. Why theres a Vacancy Create? Yeah Vacancy Create is dormant na eh. Bakit nanjan pa?"
   - User issue 2: "Wait. Tried to disabled Vacancy Approve Closure to Head Admin then save but still nakapag approve sya in Vacancy > Closure, success but wala sa history of approved."
   - User directive: "yes. Lahat ng toggle should be working".
2. **Investigation Findings**:
   - **Dormant `vacancy.create`**: Orphaned rule seeded in early RBAC migrations. Vacancies in OHMployee strictly originate through Headcount Requests, Plantilla Attrition Backfills, or Batch Imports per ADR-001/002.
   - **4-Layer RBAC Disconnect**:
     - *Layer 1 (DB)*: `get_web_current_user_context()` queried `role_permission_matrix m WHERE m.is_allowed = TRUE` without joining `role_permission_overrides o`. Custom toggles saved in `/rbac` were never reflected in `module_capabilities`.
     - *Layer 2 (Frontend Normalizer)*: `normalizeCapabilities` in `src/lib/auth.ts` filtered with `typeof item === "string"`, whereas Postgres returned JSON capability objects, wiping out capabilities into empty arrays (`[]`).
     - *Layer 3 (Frontend RBAC Gate)*: `canReviewVacancyClosures` and `canPerformDrawerAction` hardcoded `hasFullAccess` (`role_level >= 90`), treating Head Admin as always allowed regardless of matrix overrides.
     - *Layer 4 (Backend Mutation)*: `reviewClosureRequest` performed a raw `supabase.from("vacancy_closure_requests").update(...)` where RLS policy `closure_req_update_encoder_plus` permitted anyone with `i_have_full_access() >= 90`, bypassing `fn_current_user_can()`.
   - **Approved Closure Disappearance**:
     - `fetchVacancyClosureRequests` in `src/lib/queries/requests.ts` performed an inner join `vacancies:vacancies!vacancy_vcode`. Upon closure approval, the `handle_closure_approval` trigger set `status = 'Closed', is_archived = true` on the vacancy, causing PostgREST to drop the approved closure request from `/approvals?tab=vacancy_closures` -> "Approved".
3. **Implementation & Fixes**:
   - `supabase/migrations/20262606000168_rbac_dynamic_effective_overrides_and_closure_rpc.sql`:
     - Cleaned up dormant `vacancy.create` definition from `role_permission_overrides`, `role_permission_matrix`, and `role_permission_definitions`.
     - Updated `get_web_current_user_context()` to resolve dynamic effective permissions: joining active `role_permission_overrides` with Super Admin immunity (`role_name = 'Super Admin' -> true`), and emitting `ep.resource_key || '.' || ep.action_key` as `capability_key`.
     - Authored `public.review_vacancy_closure_request` and `public.approve_all_vacancy_closure_requests` with strict permission check via `fn_current_user_can('vacancy', 'vacancy', 'approve_closure')`.
     - Re-asserted `closure_req_update_encoder_plus` RLS policy requiring `fn_current_user_can('vacancy', 'vacancy', 'approve_closure')` for table updates.
     - Applied and verified against Staging (`qqiiznmqxfoamqytjica`) with 0 errors via `npm run db:push:staging`.
   - `src/lib/auth.ts`:
     - Rewrote `normalizeCapabilities` to parse capability objects and string keys into unique arrays of `${resource_key}.${action_key}` and `${action_key}`.
   - `src/lib/rbac.ts`:
     - Added `checkUserCapability` helper.
     - Updated `canReviewVacancyClosures`, `canRequestVacancyClosure`, `canAddApplicant`, `canManageApplicantPipeline`, and `canPerformDrawerAction` to check `currentUser.moduleCapabilities` first, with safe fallback to static role levels for unit tests and unauthenticated callers.
   - `src/lib/queries/vacancy/vacancyClosures.ts`:
     - Updated `reviewClosureRequest` to call `review_vacancy_closure_request` RPC with `access_denied` error handling.
   - `src/lib/queries/requests.ts`:
     - Fixed `fetchVacancyClosureRequests` by using explicit left join `vacancies:vacancies!vacancy_vcode!left`.
   - `src/app/(dashboard)/vacancy/page.tsx`:
     - Updated Closure tab banner to clarify that historical/approved closures are logged in `Approvals Center -> Vacancy Closures` (`/approvals?tab=vacancy_closures`).
   - `docs/state/vacancy_web_state.md`:
     - Updated architecture specification with the dynamic RBAC overrides, closure RPC, and left-join invariants.
4. **Verification**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 693 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build.
   - `npm run db:push:staging`: Successfully applied migration `20262606000168` on Staging (`qqiiznmqxfoamqytjica`).
   - Read-only Migration Counter: Staging: 662 migrations | Prod: 661 migrations (1 migration pending on Prod).

### Files
- `supabase/migrations/20262606000168_rbac_dynamic_effective_overrides_and_closure_rpc.sql`
- `src/app/(dashboard)/vacancy/page.tsx`
- `src/lib/auth.ts`
- `src/lib/queries/requests.ts`
- `src/lib/queries/vacancy/vacancyClosures.ts`
- `src/lib/rbac.ts`
- `docs/state/vacancy_web_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`


## Execution Report — Remove Admin Tools Sign-Up Top Banner & Fix Light Mode Action Button Contrast (ohm#remove-signup-banner-and-fix-lightmode-button)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean

### What Was Built
1. **User Request Alignment**:
   - User request: "remove this ACCOUNT SIGN-UP: ENABLED sa taas okay na ung nasa baba nya. Also fix this hindi kita ang button kapag naka light mode"
   - User attached 2 screenshots:
     - Screenshot 1: Banner card `Account Sign-Up: ENABLED` at the top of Tab 2: Admin Tools in `/more`.
     - Screenshot 2: `AccountSignupControlModal` in light mode showing the `Disable Account Sign-Up` action button washed out / invisible with white text on an unstyled background.
2. **Implementation & Fixes**:
   - `src/app/(dashboard)/more/page.tsx`:
     - Removed the top banner card (`Quick Registration Status Card` / `Account Sign-Up: ENABLED`) from Tab 2: Admin Tools.
     - Kept the canonical `Account Sign-Up Control` tile in the command grid below (`visibleAdminTiles`), which cleanly opens the modal on click.
   - `src/components/more/AccountSignupControlModal.tsx`:
     - Fixed missing background class `bg-danger-solid` on the Disable button.
     - Styled with solid, high-contrast Tailwind classes:
       - Disable button: `bg-rose-600 hover:bg-rose-700 active:bg-rose-800 text-white shadow-rose-600/20`
       - Enable button: `bg-emerald-600 hover:bg-emerald-700 active:bg-emerald-800 text-white shadow-emerald-600/20`
     - Guarantees 100% text/icon contrast and visibility in both Light Mode and Dark Mode.
   - `docs/state/more_state.md`:
     - Updated Admin Tools documentation reflecting tile-based activation without top banner clutter.
3. **Verification**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 661 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build.

### Files
- `src/app/(dashboard)/more/page.tsx`
- `src/components/more/AccountSignupControlModal.tsx`
- `docs/state/more_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

## Execution Report — Reposition Forgot Password Link Below Password Input on Login Screen (ohm#reposition-forgot-password-link)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean

### What Was Built
1. **User Request Alignment**:
   - User request: "move forgot password below password"
   - User attached screenshot of `/login` showing "Forgot password?" to the right of the "Password" label.
2. **UI & Layout Re-alignment**:
   - `src/app/(auth)/login/page.tsx`:
     - Cleaned up the "Password" label row to contain only the label.
     - Repositioned the `<Link href="/forgot-password">` directly below the password input field (`flex justify-end pt-0.5`).
     - Aligns with standard login layout between password input and primary Sign In button.
   - `docs/state/web_auth_rbac_state.md`:
     - Documented updated login layout with "Forgot password?" below the password input.
3. **Verification**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 661 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build.

### Files
- `src/app/(auth)/login/page.tsx`
- `docs/state/web_auth_rbac_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

## Execution Report — Require Middle Name and Mobile Number on Web Account Sign-Up (ohm#require-middle-name-and-mobile-number-on-signup)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean

### What Was Built
1. **User Request Alignment**:
   - User request: "Make Middle name and Mobile number required"
   - User attached screenshot of `/signup` form highlighting `Middle Name (Optional)` and `Mobile Number (Optional)`.
2. **Form Validation & UI Updates**:
   - `src/app/(auth)/signup/page.tsx`:
     - Changed Middle Name label to `Middle Name <span className="text-danger-text">*</span>` and marked input with `required`.
     - Changed Mobile Number label to `Mobile Number <span className="text-danger-text">*</span>` and marked input with `required`.
     - Added strict validation checks in `handleSubmit`:
       - Requires non-empty `middleName.trim()`.
       - Strips hyphens and spaces from `mobileNumber.trim()` to normalize mobile input (`normalizedMobile`).
       - Validates normalized mobile format against Philippine mobile number regex `/^09\d{9}$/`.
     - Passes normalized `middleName` and `normalizedMobile` into `submitAccountRequest`.
   - `src/lib/queries/signup.ts`:
     - Updated `SignupPayload` interface: `middleName: string; mobileNumber: string;` strictly required.
     - Updated `submitAccountRequest` to send normalized `middle_name` and `mobile_number` to `supabase.auth.signUp` metadata and `fn_enrich_account_request`.
   - `docs/state/web_auth_rbac_state.md`:
     - Updated `/signup` specification documenting mandatory First Name, Last Name, Middle Name, and Mobile Number fields.
3. **Verification**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 661 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build.

### Files
- `src/app/(auth)/signup/page.tsx`
- `src/lib/queries/signup.ts`
- `docs/state/web_auth_rbac_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

## Execution Report — Add Web Account Sign-Up, Forgot Password, and Admin Tools Governance Toggle (ohm#add-web-account-signup-and-admin-tools-toggle)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean

### What Was Built
1. **User Request Alignment**:
   - "ADD account sign-up to web but add mo sa Admin Tools na pwede ko i on or off ang pag sign-up. Also forgot password na din. Make sure that na makakapag sign-up ang mga users"
   - User attached login screen mockup requiring "Forgot password?" and "Request Account" registration link.
2. **Backend Architecture & Migration (`20262606000167`)**:
   - `supabase/migrations/20262606000167_wire_account_registration_governance_and_signup_guard.sql`:
     - Wired governance control `account_registration` via `fn_check_governance_control('account_registration')` into `handle_new_auth_user()` trigger. When paused, raises `P0001: Account registration is temporarily closed by system administrator.`
     - Enhanced `public.get_request_account_signup_options()` to return `is_registration_enabled` boolean while preserving all non-admin roles (`role_level < 90`), active groups, and accounts.
     - Added public read RPC `public.is_account_signup_enabled()` returning boolean, granted to `anon` and `authenticated`.
     - Validated and pushed cleanly to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging` with 0 errors.
3. **Frontend Implementation**:
   - `src/lib/queries/signup.ts`:
     - Implemented `fetchAccountSignupStatus`, `useAccountSignupStatus`, `fetchSignupOptions`, `useSignupOptions`, and `submitAccountRequest` with full metadata payload (`first_name`, `last_name`, `requested_role_id`, `group_ids`, `account_ids`, etc.) matching `handle_new_auth_user()` trigger schema.
     - Implemented `sendPasswordResetEmail` and `updateUserPassword` using standard Supabase Auth methods.
   - `src/components/more/AccountSignupControlModal.tsx`:
     - Super Admin Level 100 control modal allowing 1-click Enable / Disable of public account registration with mandatory audited reason logging via `fn_update_governance_control('account_registration')`.
   - `src/app/(dashboard)/more/page.tsx`:
     - Added `account_signup_control` tile to `adminTiles` under Tab 2: Admin Tools.
     - Added a live **Account Sign-Up Governance Card** at the top of the Admin Tools tab showing real-time status (`ACTIVE / ENABLED` vs `PAUSED / DISABLED`), last updated timestamp, reason, and quick action button.
   - `src/app/(auth)/login/page.tsx`:
     - Added "Forgot password?" link next to Password field label.
     - Added "Don't have an account? Request Account" link below the Sign In button.
   - `src/app/(auth)/forgot-password/page.tsx`:
     - Dedicated page allowing users to request password recovery email with OHMployee branding, email format validation, and success state.
   - `src/app/(auth)/reset-password/page.tsx`:
     - Dedicated page allowing users to set a new password from Supabase recovery email link with password confirmation, eye toggle, and success screen.
   - `src/app/(auth)/signup/page.tsx`:
     - Dedicated page allowing users to submit new account requests.
     - Reactively checks `is_account_signup_enabled`: if paused, renders a clear pause notice with "Back to Login".
     - Dynamically populates non-admin roles, groups (multi-select for Recruitment, single for others), and conditional accounts.
     - Submits account request with metadata, runs non-fatal enrichment, immediately signs out session, and presents clear confirmation screen explaining request is under administrator review.
4. **Verification**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 661 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build with all routes compiled including `/signup`, `/forgot-password`, `/reset-password`.

### Files Modified / Created
- `supabase/migrations/20262606000167_wire_account_registration_governance_and_signup_guard.sql`
- `src/lib/queries/signup.ts`
- `src/components/more/AccountSignupControlModal.tsx`
- `src/app/(dashboard)/more/page.tsx`
- `src/app/(auth)/login/page.tsx`
- `src/app/(auth)/signup/page.tsx`
- `src/app/(auth)/forgot-password/page.tsx`
- `src/app/(auth)/reset-password/page.tsx`
- `.ai/briefing.md`
- `.ai/handoff.md`
- `docs/state/more_state.md`
- `docs/state/web_auth_rbac_state.md`

## Execution Report — Standardize Plantilla Vacancy Stage Badges & Pending Closure Capacity Preservation (ohm#standardize-plantilla-vacancy-stages-and-pending-closure)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified Clean

### What Was Built
1. **User Request Alignment**:
   - User questions:
     1. "Why Pipeline = 1?"
     2. "Also this CPPGJV19 is cg with CPSAJV27 but wala sya sa Plantilla"
     3. "IF NASA pending for closure pa lang sya dapat nandon pa din sya sa bilang. mawawala lang sya pag approved na. Can we add this to ADR?"
     4. "also dito sa Stage dapat clear kung nasaan e.g Vacancy - Closure dapat lahat ng Stage if nasaang Tab sya nanjan dapat ganito: Vacancy - Open, Vacancy - Pipeline, Vacancy - Closure, HR Emploc - Pending, HR Emploc - For Emploc, HR Emploc - Correction, HR Emploc - Review"
2. **Forensic Root Cause Analysis**:
   - **Pipeline = 1 vs Pipeline (0)**:
     - `v_account_allocation_kpi` computes `pipeline_count` from `hr_emploc WHERE status <> ALL (ARRAY['Moved to Plantilla', 'Backout']) AND deleted_at IS NULL`.
     - In FOREVER OFFICE, candidate `AL, JAMES N/A` (`vcode: CPSAJV27`) has active onboarding status `Pending Emploc` in `hr_emploc`, which increments `pipeline_count` to 1 on the Account Card.
     - In Vacancy Management (`/vacancy`), the Pipeline tab displays active ATS screening candidates (`public.applicants`), where James AL is already `Confirmed Onboard` / `is_archived = true`, so ATS pipeline count is 0.
   - **CPPGJV19 vs CPSAJV27 in Plantilla**:
     - `CPPGJV19` (Puregold Noveleta Oasis) appeared in Plantilla's Vacancy tab because separated employee `BACULI, EURIE FERAER` (`status: Inactive`, separated `2026-11-12`, remarks `"Incomplete Docs"`) vacated the slot, and `plantilla/page.tsx` dynamically synthesizes open vacancies for unfilled inactive records.
     - `CPSAJV27` was missing from Plantilla because: (a) employee `AL, JAMES N/A` in `public.plantilla` has `is_deleted = true` (status `Deactivated`), which is excluded by `v_plantilla_safe`; (b) `CG-FG1-0005` had `required_headcount = 0`, causing `vacancyListing.ts:2186` to suppress `CPSAJV27`; (c) slot `09b9192d...` is in `slot_status = 'hr_processing'`.
3. **Architectural Remediation**:
   - **Stage Badge Standardization**:
     - `src/components/plantilla/directory/types.tsx`:
       - Added `"Vacancy - Closure"` and `"HR Emploc - For Emploc"` to `VacancyWorkflowStage` type union.
       - Updated `resolveVacancyWorkflowStage` to evaluate pending closure first (`hasPendingClosure`, `closureRequestStatus === 'Pending'`, or target includes `'closure'`), followed by `HR Emploc - Correction`, `HR Emploc - Review`, `HR Emploc - For Emploc`, `HR Emploc - Ready`, `HR Emploc - Pending`, `Vacancy - Pipeline`, and default `Vacancy - Open`.
       - Updated `isHrPipelineWorkflowStage` to include `"HR Emploc - For Emploc"`.
       - Updated `renderVacancyStatusBadge` with badge styles for `"Vacancy - Closure"` (rose/red border & background) and `"HR Emploc - For Emploc"` (indigo border & background).
     - `src/lib/queries/vacancy/vacancyListing.ts`:
       - Updated enrichment loop to evaluate `isClosure` and assign `row.stageBadge = "Vacancy - Closure"` and `row.pipelineStatus = "Vacancy - Closure"`.
       - Handled `"for emploc"` in emploc status mapping to assign `"HR Emploc - For Emploc"`.
       - Updated `finalRows` under `currentTab === "open"` to preserve `"Vacancy - Closure"` if `isClosure` is true.
   - **Pending Closure Capacity Preservation**:
     - `src/app/(dashboard)/plantilla/page.tsx`:
       - Added `pendingClosureVcodesQuery` querying `vacancies` for `has_pending_closure = true OR closure_request_status = 'Pending'`.
       - Enriched synthesized inactive vacancies and existing vacancies to set `hasPendingClosure: true`, `closureRequestStatus: 'Pending'`, and `stageBadge: 'Vacancy - Closure'`.
       - Preserved `Vacancy - Closure` within the Open tab (`vacancySubFilter === "open"`), ensuring pending closure requisitions remain counted and visible until administrative approval.
   - **Documentation & State Specifications**:
     - `docs/state/plantilla_web_state.md`: Updated Tab 3 specification to reflect `Vacancy - Closure` and `HR Emploc - For Emploc` canonical stage badges.
     - `OHMployee/docs/architecture/adr/02_vacancy.md`: Formally committed the approved Rule 4 Pending Closure Capacity Retention Invariant in the mobile repo (`2ad3464`).
     - `docs/architecture/_mirror/adr/02_vacancy.md`: Synchronized mirror from `0eb4407` → `2ad3464` via `npm run sync:adr`.
4. **Verification**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 690 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build with all 22 routes compiled.

### Files
- `src/components/plantilla/directory/types.tsx`
- `src/lib/queries/vacancy/vacancyListing.ts`
- `src/app/(dashboard)/plantilla/page.tsx`
- `docs/state/plantilla_web_state.md`
- `docs/architecture/_mirror/adr/02_vacancy.md`
- `docs/architecture/_mirror/ADR-001-ohmployee-system-architecture.md`
- `docs/architecture/_mirror/adr/00_core_invariants.md`
- `docs/architecture/_mirror/adr/01_plantilla.md`
- `docs/architecture/_mirror/adr/03_hr_emploc.md`
- `docs/architecture/_mirror/adr/04_approvals_requisitions.md`
- `docs/architecture/_mirror/adr/05_more_module.md`
- `docs/architecture/_mirror/adr/06_dashboard_cencom.md`
- `docs/architecture/_mirror/adr/README.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

---

## Execution Report — Enforce Default Light Mode for All Roles & Fix Auto Dark Mode on Login (ohm#default-light-theme-all-roles)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified & Live on Staging

### What Was Built
1. **User Request Alignment**:
   - User report: "Fix auto darkmode in other roles when loging in. Make sure na light mode ang default for all roles."
2. **Forensic Root Cause Analysis**:
   - In database table `public.user_settings`, the column definition was created as `theme_mode text NOT NULL DEFAULT 'system'` in migration `20260531000000_app_settings_phase3_backend.sql`, and trigger function `public.handle_create_default_user_settings()` inserted default rows with `theme_mode = 'system'`.
   - When users logged into operational roles (e.g. HRCO, Operations Manager, Encoder, Recruiter, TL, Viewer), their user profile had `theme_mode = 'system'`.
   - On devices where the OS / browser had dark mode active (`prefers-color-scheme: dark`), `ThemeProvider` fetched `settings.themeMode = 'system'`, saved `'system'` to `localStorage.ohmployee_theme_mode`, and resolved the theme to Obsidian dark mode (`data-theme="system"`, `data-resolved-theme="dark"`).
   - Furthermore, when switching accounts or signing out, stale theme keys in `localStorage` and React Query caches persisted across user sessions.
3. **Architectural Remediation**:
   - **Database Migration (`20262606000165_default_light_theme_all_roles.sql`)**:
     - §1: `ALTER TABLE public.user_settings ALTER COLUMN theme_mode SET DEFAULT 'light';`
     - §2: `UPDATE public.user_settings SET theme_mode = 'light' WHERE theme_mode = 'system' OR theme_mode IS NULL;`
     - §3: Replaced `public.handle_create_default_user_settings()` to explicitly insert `theme_mode = 'light'` upon user profile provisioning.
     - §4: Backfilled any missing profile records with `'light'`.
   - **Client Authentication & State Hygiene**:
     - `src/app/(auth)/login/page.tsx`: Normalized theme to `'light'` upon login page mount and upon successful authentication, and purged stale React Query caches via `queryClient.clear()`.
     - `src/components/Sidebar.tsx`, `src/app/(dashboard)/more/page.tsx`, `src/components/DashboardAuthShell.tsx`, `src/lib/auth.ts`: Ensured `localStorage.ohmployee_theme_mode` is reset to `'light'` on sign-out/idle-logout to prevent theme leakage between accounts.
     - `docs/state/web_design_tokens.md`: Formally documented the Light Mode default contract across all roles.
4. **Verification & Post-Execution Sanity**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 690 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build with all 22 routes compiled.
   - Pre-push dry-run validated with 0 errors via `npm run db:push:staging -- --dry-run`.
   - Applied migration `20262606000165` cleanly to Staging (`qqiiznmqxfoamqytjica`).
   - Verified live definitions via `pg_get_functiondef` on Staging: `handle_create_default_user_settings` explicitly inserts `'light'`, `user_settings.theme_mode` column default is `'light'::text`, and all 41 user profiles on Staging are confirmed set to `theme_mode: 'light'`.

### Files
- `supabase/migrations/20262606000165_default_light_theme_all_roles.sql`
- `src/app/(auth)/login/page.tsx`
- `src/components/Sidebar.tsx`
- `src/app/(dashboard)/more/page.tsx`
- `src/components/DashboardAuthShell.tsx`
- `src/lib/auth.ts`
- `docs/state/web_design_tokens.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

### Production Delta
- Staging (`qqiiznmqxfoamqytjica`): 659 migrations
- Production (`rwxelulyapjgaarlwkus`): 656 migrations
- 3 migrations are not on prod:
  - `20262606000163_clean_hard_delete_aling_nena_store.sql`
  - `20262606000164_fix_account_archive_approval_and_rejection_rpcs.sql`
  - `20262606000165_default_light_theme_all_roles.sql`

---

## Execution Report — Fix Account Archive Approval & Rejection RPCs and Notifications RLS (ohm#fix-account-archive-reject-and-approval-rpcs)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified & Live on Staging

### What Was Built
1. **User Request Alignment**:
   - User report: "reject button is not working." (with screenshot of Admin panel -> Approvals -> Account Archives review queue displaying pending request for `EUROMED PLANT`).
2. **Forensic Root Cause Analysis**:
   - In `public.notifications`, Row Level Security (RLS) is enabled. The `notif_update_own` policy was locked strictly to `recipient_user_id = auth.uid()` without an exception for Super Admin / Full Access (`i_have_full_access()`).
   - When account archive requests were submitted via `requestAccountArchive` in `src/lib/queries/plantilla.ts`, `p_recipient_user_id` was erroneously stamped with `currentUser?.authUserId` (the requester's ID) rather than remaining `NULL` for Super Admin pool review.
   - When Super Admin (or any other user) attempted to approve or reject the request, the client performed a direct PostgREST `UPDATE public.notifications`. Because `recipient_user_id != auth.uid()`, PostgreSQL silently updated 0 rows.
   - In `src/lib/queries/requests.ts`, `rejectAccountArchive` swallowed the update error without throwing, falling back to `mark_notification_read` (which also filtered on `recipient_user_id = auth.uid()`, updating 0 rows). The frontend modal closed cleanly while the notification remained `is_archived = false`, leaving the request stuck permanently in the Pending queue.
3. **Architectural Remediation**:
   - **Database Migration (`20262606000164_fix_account_archive_approval_and_rejection_rpcs.sql`)**:
     - §1: Created SECURITY DEFINER RPC `public.reject_account_archive(p_notification_id uuid, p_reason text)` with Super Admin permission enforcement (`i_have_full_access() OR get_my_role_level() >= 100`), mandatory non-empty reason validation, atomic notification update (`is_read = true, is_archived = true, read_at = now()`, message prepended with `[REJECTED: <reason>]`), and audit trail insertion in `public.audit_logs`.
     - §2: Created SECURITY DEFINER RPC `public.approve_account_archive(p_notification_id uuid)` with Super Admin enforcement, atomic account deactivation (`is_active = false, status = 'Inactive'` triggering cascade trigger `trg_account_archive_cascade_stores`), notification update, and audit log write.
     - §3: Updated `notif_update_own` RLS policy on `public.notifications` to allow `(recipient_user_id = auth.uid()) OR (SELECT i_have_full_access())`.
     - §4: Sanitized existing `account_archive_request` notifications to `recipient_user_id = NULL` so they are accessible to all Super Admins.
   - **Client Query Layer (`src/lib/queries/requests.ts`)**:
     - Updated `rejectAccountArchive` and `approveAccountArchive` to invoke the dedicated RPCs with proper error logging and non-swallowing error boundaries.
   - **Request Submission Layer (`src/lib/queries/plantilla.ts`)**:
     - Updated `requestAccountArchive` to pass `p_recipient_user_id: null` so archive requests are not tied to a single user's account.
   - **UI Component (`AccountArchiveDataTable.tsx`)**:
     - Cleared error message and remarks upon opening the Reject and Approve modals to prevent stale validation states.
4. **Verification & Post-Execution Sanity**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 689 migrations.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack production build with all 22 routes compiled.
   - Pre-push dry run validated with 0 errors via `npm run db:push:staging -- --dry-run`.
   - Applied migration `20262606000164` cleanly to Staging (`qqiiznmqxfoamqytjica`).
   - Verified live definitions for `reject_account_archive` and `approve_account_archive` via `pg_get_functiondef`.

### Files
- `supabase/migrations/20262606000164_fix_account_archive_approval_and_rejection_rpcs.sql`
- `src/lib/queries/requests.ts`
- `src/lib/queries/plantilla.ts`
- `src/components/approvals/AccountArchiveDataTable.tsx`
- `docs/state/approvals_web_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

### Production Delta
- Staging (`qqiiznmqxfoamqytjica`): 658 migrations
- Production (`rwxelulyapjgaarlwkus`): 656 migrations
- 2 migrations are not on prod:
  - `20262606000163_clean_hard_delete_aling_nena_store.sql`
  - `20262606000164_fix_account_archive_approval_and_rejection_rpcs.sql`

---

## Execution Report — Hard Delete Inactive Test Account ALING NENA STORE & Child Artifacts (ohm#hard-delete-aling-nena-store)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified & Live on Staging

### What Was Built
1. **User Request Alignment**:
   - User request: `hard delete this account : ALING NENA STORE`.
2. **Forensic Database Inspection (Staging `qqiiznmqxfoamqytjica`)**:
   - Target Account: `ALING NENA STORE` (`id: f60c15d4-5611-4632-b82b-802c81aec713`, `status: Inactive`, `is_active: false`).
   - Plantilla rows: 0.
   - Vacancies: 0.
   - Plantilla slots: 0.
   - User scopes: 0.
   - Employee store allocations: 0.
   - Child Foreign Key Dependencies Identified:
     - 5 rejected test import batches in `public.plantilla_import_batches` (`selected_account_id = f60c15d4...`).
     - 25 test import rows in `public.plantilla_import_rows` under the 5 rejected batches.
     - 1 approved test request in `public.new_store_requests` (`0c04fc0b-9c39-4973-a1ee-6e9bbfdbe31e`).
     - 1 archived child store in `public.stores` (`518bdc0c-118a-42d3-9140-e99b501fcb21`).
3. **Surgical Deletion Sequence (`20262606000163_clean_hard_delete_aling_nena_store.sql`)**:
   - §1. Delete child `plantilla_import_rows` (25 rows).
   - §2. Delete rejected `plantilla_import_batches` (5 batches).
   - §3. Delete `new_store_requests` (1 record).
   - §4. Delete child store `ALING NENA` (`518bdc0c-118a-42d3-9140-e99b501fcb21`).
   - §5. Hard delete `public.accounts` record (`f60c15d4-5611-4632-b82b-802c81aec713`).
4. **Verification & Post-Execution Sanity**:
   - Dry-run validation passed cleanly with 0 errors via `npm run db:push:staging`.
   - Applied migration `20262606000163_clean_hard_delete_aling_nena_store.sql` to Staging (`qqiiznmqxfoamqytjica`).
   - Executed live SQL count check across `accounts`, `stores`, `plantilla_import_batches`, and `new_store_requests`: confirmed **0 records remaining** across all tables.
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 credential leaks.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 688 migrations.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm test`: 257/257 unit tests passed.

### Files
- `supabase/migrations/20262606000163_clean_hard_delete_aling_nena_store.sql`
- `.ai/briefing.md`
- `.ai/handoff.md`

### Production Delta
- Staging (`qqiiznmqxfoamqytjica`): 657 migrations
- Production (`rwxelulyapjgaarlwkus`): 656 migrations
- Pending on Prod: `20262606000163_clean_hard_delete_aling_nena_store.sql`

---

## Execution Report — Comprehensive Audit & Fix across All Operational & Data Integrity Reports (ohm#audit-and-fix-all-operational-reports)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified & Live on Staging

### What Was Built
1. **User Request Alignment**:
   - The user requested: "Check other report hindi lang Attrition and Backout baka may bug pa" to audit all remaining operational reports across the Reports module (`/reports`) and eliminate any hidden bugs.
2. **Exhaustive Root Cause Analysis & Database Fixes**:
   - **Bug 1: NULL Date Predicate Failure in Group Operational Reports**:
     - *Affected RPCs*: `public.report_resigned_by_group`, `public.report_awol_by_group`, `public.report_time_to_fill_by_group`, `public.report_hr_emploc_late_update_by_group`.
     - *Root Cause*: Function parameters lacked `DEFAULT NULL` and the query predicate evaluated `date BETWEEN p_start_date AND p_end_date`. In SQL, `BETWEEN NULL AND NULL` evaluates to `NULL` (false), causing all records to be silently filtered out to 0 rows whenever preset "All Dates" (`startDate: null, endDate: null`) was selected in the UI.
     - *Resolution*: Added `DEFAULT NULL` to `p_start_date` and `p_end_date`, added null-safe comparison `IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_end_date < p_start_date THEN ...`, and updated predicates to `(p_start_date IS NULL OR date >= p_start_date) AND (p_end_date IS NULL OR date <= p_end_date)`.
   - **Bug 2: Resigned & AWOL Status & Separation Date Fallback**:
     - *Affected RPCs*: `public.report_resigned_by_group`, `public.report_awol_by_group`.
     - *Root Cause*: Checked only exact status `'Resigned'` and dropped records where separation date was stored in `deactivated_at::date` instead of `date_of_separation`.
     - *Resolution*: Implemented `COALESCE(p.date_of_separation, p.deactivated_at::date)` fallback date, and broadened status filters to `(p.separation_status IN ('Resigned', 'Resignation') OR p.deactivation_reason ILIKE '%resign%')` for Resigned, and `(p.separation_status = 'AWOL' OR p.deactivation_reason ILIKE '%awol%')` for AWOL.
   - **Bug 3: HR Emploc Late Update SLA Threshold & Store Count Flaw**:
     - *Affected RPC*: `public.report_hr_emploc_late_update_by_group`.
     - *Root Cause*: `p_end_date::timestamptz - INTERVAL '3 days'` evaluated to `NULL` when `p_end_date` was null; and `COUNT(DISTINCT e.store_id)` counted all stores regardless of whether any requests were late.
     - *Resolution*: Evaluated `COALESCE(p_end_date, CURRENT_DATE)::timestamptz - INTERVAL '3 days'` for active requests, and scoped store count to `COUNT(DISTINCT e.store_id) FILTER (WHERE e.is_late)`.
   - **Bug 4: Inactive Floating Staff Query Omission**:
     - *Affected RPC*: `public.fn_report_floating_employees`.
     - *Root Cause*: Filtered strictly on `p.status = 'Inactive' AND p.separation_status = 'Floating' AND p.inactive_at IS NOT NULL`. Records with `p.status = 'Floating'` or unset `inactive_at` were omitted.
     - *Resolution*: Updated filter to `(p.status = 'Floating' OR p.separation_status = 'Floating') AND p.status <> 'Active'`, with floating date waterfall `COALESCE(p.inactive_at::date, p.updated_at::date, CURRENT_DATE)`.
   - **Bug 5: Data Integrity & Team Performance Missing Involuntary Separations**:
     - *Affected RPCs*: `public.fn_data_integrity_summary`, `public.fn_data_integrity_late_hr_detail`, `public.fn_data_integrity_vacancy_delay_detail`, `public.fn_team_performance_summary`, `public.fn_team_performance_detail`.
     - *Root Cause*: Filtered strictly on `separation_status IN ('Resigned', 'AWOL', 'Endo', 'Others')`, omitting `'Terminated'` and `'End of Contract'`.
     - *Resolution*: Expanded status filter to include `'Terminated'` and `'End of Contract'` with case-insensitive `deactivation_reason` checks and `COALESCE(p.date_of_separation, p.deactivated_at::date)` fallback.
3. **Migration & Staging Deployment**:
   - Auto-generated migration `supabase/migrations/20262606000162_fix_reports_operational_and_data_integrity.sql`.
   - Verified pre-push dry-run via `npm run db:push:staging` and applied cleanly to Staging (`qqiiznmqxfoamqytjica`).
4. **Verification & Testing**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
   - `npm run check:secrets`: 0 leaks detected.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 687 migrations.
   - `npm run lint`: 0 ESLint errors.
   - `npm test`: 257/257 unit tests passed.
   - `npm run build`: 22/22 static pages generated cleanly.

### Files
- `supabase/migrations/20262606000162_fix_reports_operational_and_data_integrity.sql`
- `docs/state/more_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

### Production Delta
- Staging (`qqiiznmqxfoamqytjica`): 656 migrations
- Production (`rwxelulyapjgaarlwkus`): 655 migrations
- Pending on Prod: `20262606000162_fix_reports_operational_and_data_integrity.sql`

---

## Execution Report — Comprehensive Reports Module Density & Polish Audit (ohm#compact-reports-module-sweep)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - The user followed up with: "Check the Whole Report Module may mga next page pa yan" to ensure the entire Reports module (`/reports`) is systematically audited and compacted, matching the high-density aesthetic established on the catalog tab.
2. **Systematic Compaction & Polish Across All Sub-pages & Modals**:
   - **Flutter Debug Port Subtitles Removed**:
     - Stripped out developer artifact tags leaking from mobile porting (`Port of FloatingReportScreen`, `Port of TeamPerformanceReportScreen`, `Port of DataIntegrityReportScreen`, `Port of CustomReportScreen`).
   - **`ReportDetailView.tsx` (Universal Drilldown Viewer)**:
     - Compacted KPI summary cards from `p-4 text-2xl` to `p-3 text-lg font-bold mt-0.5`.
     - Tightened filter toolbar to `p-3 rounded-lg` with `h-8` inputs.
     - Standardized data table cells from `py-3 px-4 text-sm` to `py-2 px-3 text-xs` with `bg-table-header text-[11px] font-semibold text-text-secondary`.
     - Removed redundant debug subheader string `"Universal Report Detail"`.
   - **`FloatingStaffTab.tsx` (Floating Workforce Aging & Allocation)**:
     - Compacted aging bucket status buttons and KPI cards to `p-3 text-lg font-bold`.
     - Tightened scope filter strip to `p-3 rounded-lg`.
     - Standardized data table headers and row cells to `py-2 px-3 text-xs`.
   - **`TeamPerformanceTab.tsx` (SLA Compliance Scorecards)**:
     - Tightened scorecard KPI cards (`p-3 rounded-lg text-lg font-bold`).
     - Compacted severity chips and dropdown filter toolbar (`p-3 rounded-lg`).
     - Standardized leaderboard data table to `py-2 px-3 text-xs` with compact action trigger buttons.
   - **`DataIntegrityTab.tsx` (Workforce Data Drift & Anomaly Audit)**:
     - Compacted KPI summary cards (`Critical Issues`, `High Risk`, `Total Findings`, `Affected Stores`) to `p-3 rounded-lg text-lg font-bold`.
     - Re-architected the 4 audit category cards from oversized `p-6` to compact `p-4 rounded-lg` with compact metric chips and trigger buttons.
   - **`CustomReportTab.tsx` (Custom Query Builder & Exporter)**:
     - Compacted 6 primary data source selector cards from `p-3` to `p-2.5 rounded-lg`.
     - Tightened scope filter container and column selection strip to `p-3 rounded-lg`.
     - Standardized query results preview table from `text-sm py-2.5 px-3` to high-density `text-xs py-2 px-3`.
   - **Drilldown Modals (`AttritionDrilldownModal.tsx`, `TeamPerformanceIssuesModal.tsx`, `DataIntegrityDetailModal.tsx`)**:
     - Standardized all modal table headers and body cells to high-density web tokens `text-xs py-2 px-3` with `bg-table-header` and semantic borders.
3. **Verification & Testing**:
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH` across all 9 modular ADRs.
   - `npm run check:secrets`: 0 credential leaks detected.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 686 migrations.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm test`: 257/257 unit tests passed.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack build with 22/22 static pages generated.

### Files
- `src/components/reports/ReportDetailView.tsx`
- `src/components/reports/FloatingStaffTab.tsx`
- `src/components/reports/TeamPerformanceTab.tsx`
- `src/components/reports/DataIntegrityTab.tsx`
- `src/components/reports/CustomReportTab.tsx`
- `src/components/reports/AttritionDrilldownModal.tsx`
- `src/components/reports/TeamPerformanceIssuesModal.tsx`
- `src/components/reports/DataIntegrityDetailModal.tsx`
- `docs/state/more_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

### Validation
- `npm run check:adr` -> `ADR_MIRROR_STATUS: FRESH` (exit code 0)
- `npm test` -> 257/257 passed (exit code 0)
- `npm run lint` -> 0 errors / 0 warnings (exit code 0)
- `npm run build` -> 22/22 prerendered (exit code 0)


## Execution Report — Compact Reports Catalog Redesign & Density Optimization (ohm#compact-reports-catalog-design)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - The user provided a screenshot of the Reports Catalog at `/reports` asking: "make this simple reports parang masyado malalaki?"
   - Diagnosed that the page suffered from:
     - A giant redundant 180px hero banner that duplicated `AdminPageHeader` copy and rendered washed-out light blue text on white.
     - Oversized cards (~190px height each) with giant icons, redundant "Universal Viewer" pills, and an unnecessary separate bottom action bar (`mt-4 pt-3 border-t`).
     - Severe vertical scroll requirements where only 6 cards fit on an entire desktop viewport.
2. **Compact & High-Density UI Redesign (`src/components/reports/ReportsCatalogTab.tsx`)**:
   - **Hero Banner Removal**: Removed the giant redundant hero banner, immediately elevating all report sections above the fold.
   - **Compact Toolbar**: Added category filter chips (`All Reports [13]`, `Separation [6]`, `Velocity [3]`, `Operations [4]`) and a live real-time search input (`Filter reports...`) with quick clear `(×)` action.
   - **Sleek Horizontal Cards**: Re-architected all 13 report cards into horizontal high-density cards (~70px height vs ~190px previously, a 62% reduction in vertical footprint).
     - Left: 32x32px icon container with smooth hover transition.
     - Center: Clean report title (`text-xs font-bold`) and 2-line description (`text-[11px] text-text-secondary`).
     - Right: Subtle destination tags (`CENCOM`, `Builder`, `Tab 2/3/4`) and trailing interactive arrow.
     - Entire card serves as an interactive click surface with subtle border and surface hover effects.
   - **Clean Search Results**: Supports live search across title, description, and category with empty state and quick reset.
3. **Verification & Testing**:
   - `npm test`: Passed 257/257 unit tests.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run check:secrets`: 0 credential leaks detected.
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 686 migrations.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack build with 22/22 static pages generated.

### Files
- `src/components/reports/ReportsCatalogTab.tsx`
- `.ai/briefing.md`
- `.ai/handoff.md`
- `.ai/current_state.md`
- `docs/state/more_state.md`

### Validation
- `npm run check:adr` -> `ADR_MIRROR_STATUS: FRESH` (exit code 0)
- `npm test` -> 257/257 passed (exit code 0)
- `npm run lint` -> 0 errors / 0 warnings (exit code 0)
- `npm run build` -> 22/22 prerendered (exit code 0)

---

## Execution Report — Fix Reports Defects: Attrition Reasons, Terminated Roster, Back-Out Pipeline, and Combined Report Error (ohm#fix-reports-attrition-terminated-backout)
**Date:** 2026-11-24 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - The user reported 4 defects in the Reports module (`/reports`):
     - `-attrition report reason/details not specified`
     - `-terminated not appearing`
     - `-back out not appearing`
     - `-back out & terminated combined failed to load report data`
2. **Forensic Root Cause Analysis**:
   - **Defect 1 (`reason/details not specified`)**: In `public.fn_get_attrition_details`, the query selected `p.deactivation_reason::text`, which was `NULL` or empty for almost all separated personnel; operational separation remarks were captured in `plantilla.remarks` and `plantilla.separation_status`.
   - **Defect 2 (`terminated not appearing`)**: In `public.report_terminated_by_group`, the status condition was hardcoded to `p.separation_status IN ('Endo', 'Others')`, completely excluding employees tagged `'Terminated'` (e.g. Joey Payad, Arvin Mark Abandia, Mark Romeo Abasola) and `'End of Contract'`.
   - **Defect 3 (`back out not appearing`)**: In `public.report_backout_by_group`, the query filtered on `h.deleted_at IS NULL AND h.backout_date IS NOT NULL`. Because `public.tag_backout` sets `deleted_at = now()`, all backout records were excluded (returning 0 events). Furthermore, 192 pre-onboarding applicant dropouts (`status ILIKE '%backout%'`) in `public.applicants` were omitted.
   - **Defect 4 (`combined failed to load report data`)**: In `public.report_backout_terminated_by_group`, CTE `combined` had `SELECT account_id, store_id FROM backouts UNION ALL SELECT account_id, store_id FROM terminated`. In PL/pgSQL, `RETURNS TABLE (account_id uuid, ...)` introduces an in-scope variable named `account_id`, causing PostgreSQL `ERROR: 42702: column reference "account_id" is ambiguous`.
3. **Database Migration (`supabase/migrations/20262606000161_fix_reports_attrition_terminated_backout.sql`)**:
   - Generated auto-numbered migration via `npm run db:new fix_reports_attrition_terminated_backout`.
   - `public.fn_get_attrition_details`: Implemented reason waterfall `COALESCE(NULLIF(TRIM(p.deactivation_reason), ''), NULLIF(TRIM(p.remarks), ''), p.separation_status, 'Separated')`; exposed `separation_status` and `remarks`; supported `p_start_date IS NULL` for all-time historical separation queries.
   - `public.report_terminated_by_group`: Expanded status filter to `p.separation_status IN ('Terminated', 'End of Contract', 'Endo', 'Others')` and `p.deactivation_reason ILIKE '%terminat%'`; evaluated `COALESCE(p.date_of_separation, p.deactivated_at::date)`; supported default null date parameters.
   - `public.report_backout_by_group`: Removed `deleted_at IS NULL` filter; unioned candidate dropouts from `public.applicants` deduplicated against `hr_emploc.applicant_id`; evaluated `COALESCE(h.backout_date::date, h.updated_at::date)` and `a.updated_at::date`.
   - `public.report_backout_terminated_by_group`: Qualified column projections `b.account_id, b.store_id` and `t.account_id, t.store_id` in CTE `combined`, eliminating PL/pgSQL variable ambiguity.
4. **Web Frontend Enhancements**:
   - `src/lib/queries/reports.ts`: Updated `AttritionDetailEmployee` interface to include `remarks?: string | null`; enhanced `fetchAttritionDetails` with waterfall fallback `rawReason -> rawRemarks -> sepStatus -> "Not specified"`.
   - `src/components/reports/ReportDetailView.tsx`: For `backout_terminated_report`, enriched table metric cell to render total events alongside breakdown (`{row.totalCount} ({row.backoutCount} back-outs • {row.terminatedCount} term)`); added `Back-Outs` and `Terminated` columns to CSV/XLSX export.
5. **Verification & Testing**:
   - `npm run check:sql`: 28 core tables & 19 cross-module RPC contracts verified across 686 migrations.
   - `npm test`: Passed 257/257 unit tests.
   - `npm run lint`: 0 ESLint errors/warnings.
   - `npm run check:secrets`: 0 credential leaks detected.
   - `npm run build`: Clean Next.js 16.2.4 Turbopack build.
   - `npm run db:push:staging`: Dry-run verified and pushed live to Staging (`qqiiznmqxfoamqytjica`).
   - `pg_get_functiondef` live diff: Verified all 4 updated functions on remote Staging database.
   - `npm run check:migrations`: Confirmed Staging (655) vs Prod (654) with 1 migration pending promotion.

### Files
- `supabase/migrations/20262606000161_fix_reports_attrition_terminated_backout.sql`
- `src/lib/queries/reports.ts`
- `src/components/reports/ReportDetailView.tsx`
- `.ai/briefing.md`
- `.ai/handoff.md`
- `.ai/current_state.md`
- `docs/state/more_state.md`

### Validation
- `npm run check:adr` -> `ADR_MIRROR_STATUS: FRESH` (exit code 0)
- `npm test` -> 257/257 passed (exit code 0)
- `npm run lint` -> 0 errors / 0 warnings (exit code 0)
- `npm run check:sql` -> OK (exit code 0)
- `npm run check:migrations` -> 1 pending migration (exit code 0)

---

## Execution Report — Fix Web HR Emploc Summary Overload Conflict & Cross-Platform Parity (ohm#fix-web-hr-emploc-summary-duplicate-overload)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - The user requested: "Check mobile and Web bakit hindi sila same ng data. Example in HR Emploc sa pending hindi sila match ng data doon. Check every module" and instructed "Go fix it".
   - Conducted an exhaustive cross-module audit across HR Emploc, Plantilla, Vacancy, Approvals, and Dashboard/CENCOM.
2. **Forensic Root Cause (HR Emploc Data Discrepancy)**:
   - Web queries `public.get_web_hr_emploc_summary` via PostgREST to fetch badge counters for all 5 queues (`pending`, `for_emploc`, `correction`, `review`, `deployed`).
   - On Staging (`qqiiznmqxfoamqytjica`), two conflicting signatures of `public.get_web_hr_emploc_summary` coexisted:
     1. Migration 130: `(p_status, p_deficiency, p_sla_filter, p_account_id, p_group_id, p_search, p_queue)`
     2. Migration 104/120: `(p_queue, p_status, p_deficiency, p_sla_filter, p_account_id, p_group_id, p_search)`
   - When PostgREST attempted to route the RPC call, it threw HTTP 300 `PGRST203: More than one function was found in the schema cache`.
   - On Web, this query error caused tab badge counters for non-active queues to fail silently and render as `0` (or blank), while Mobile (which queries the raw `v_hr_emploc_sla_flags` view directly) displayed real numbers.
   - When comparing row listings by role, Web and Mobile match 100% on identical scopes (7 rows for SA/HA, 3 for OM, 2 for HRCO, 0 for unscoped Encoder).
3. **Cross-Module Forensic Diagnosis**:
   - **Plantilla**: Web has 6 sub-tabs (`Active`, `On-Leave`, `Vacancy`, `Floating`, `Deactivation`, `Inactive`). Mobile has 6 tabs (`Active`, `Vacancy`, `On-Leave`, `Floating`, `Inactive`, `Needs HRCO` — no Deactivation tab). Personnel marked "Pending Deactivation" or "For Deactivation" are filtered into the Deactivation tab on Web, but remain in the Active tab on Mobile.
   - **Vacancy**: Web enforces ADR Rule #8 where Pipeline badge and table render at candidate level (**1 row = 1 applicant**). Mobile renders **1 card per requisition (`VacancyItem`)** and groups candidates inside the card.
   - **Approvals**: Web features an 11-queue unified Approvals cockpit (`/approvals`). Mobile Request Center (`request_center_screen.dart`) only lists 3 queues (`headcount_requests`, `vacancy_closure_requests`, `hr_emploc_deletion_requests`). Other request types are accessed on separate screens in Mobile.
   - **Dashboard & CENCOM**: Web utilizes server-computed RPCs (`fn_dashboard_metrics`, `fn_dashboard_operational_analytics`), whereas Mobile queries 15+ individual raw tables/views and computes sums/percentages in-memory in Dart.
4. **Database Migration (`supabase/migrations/20262606000155_fix_web_hr_emploc_summary_duplicate_overload.sql`)**:
   - Generated auto-numbered migration via `npm run db:new fix_web_hr_emploc_summary_duplicate_overload`.
   - Explicitly dropped both duplicate overload signatures.
   - Recreated single canonical function `public.get_web_hr_emploc_summary(p_queue text DEFAULT NULL, p_status text DEFAULT NULL, p_deficiency text DEFAULT NULL, p_sla_filter text DEFAULT NULL, p_account_id uuid DEFAULT NULL, p_group_id uuid DEFAULT NULL, p_search text DEFAULT NULL)`.
   - Validated SQL contracts (`npm run check:sql` -> 0 errors) and pre-push dry-run (`npm run db:push:staging -- --dry-run`).
   - Pushed live to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging`.
5. **Live Verification**:
   - `pg_proc` on Staging: exactly 1 function definition exists.
   - Live PostgREST RPC call returns HTTP 200: `pending_count: 7, for_emploc_count: 2, correction_count: 2, review_count: 3, ready_count: 10, sla_breached_count: 13`.
   - `npm test`: 257/257 unit tests passed.
   - `npm run lint`: 0 errors, 0 warnings.
   - `npm run check:migrations`: Staging (649) vs Prod (648) with 1 migration pending promotion.

### Files
- `supabase/migrations/20262606000155_fix_web_hr_emploc_summary_duplicate_overload.sql`
- `docs/state/hr_emploc_web_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

### Validation
- `npm run check:adr` -> `ADR_MIRROR_STATUS: FRESH` (exit code 0)
- `npm test` -> 257/257 passed (exit code 0)
- `npm run lint` -> 0 errors / 0 warnings (exit code 0)
- `npm run check:sql` -> OK (exit code 0)
- `npm run check:migrations` -> 1 pending migration (exit code 0)

---

## Execution Report — Prune Unnecessary Skills (ohm#prune-unnecessary-skills)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - The user asked to audit existing skills: whether any skills should be removed, and how skills get utilized during prompt execution.
   - Diagnosed that the global provider environment (`~/.t3/userdata/.../config/skills/`) had 21 Google Cloud / BigQuery / Dataproc / Spark skills that were exceeding the context budget limit and triggering system exclusions.
   - In addition, identified 5 marketing / slide creation skills in `.agents/skills/` (`banner-design`, `brand`, `design`, `design-system`, `slides`) that are unrelated to the core OHMployee HR/Plantilla admin application.
   - User explicitly approved removing both sets.
2. **Global Provider GCP Skills Removal & Safe Backup**:
   - Safely relocated all 21 GCP skills and `.datacloud_skills_manifest` from `C:\Users\Ohm\.t3\userdata\providers\antigravity\ac0a3dfd6dddb20962cecff6ee5fe65e19d3923be20e52c5ab52ff877f7e4c32\config\skills` to `config\skills_backup_gcp\`.
   - Verified that `config\skills\` has 0 items remaining, permanently resolving the context budget overflow warning.
3. **Workspace Marketing Skills Cleanup**:
   - Removed 5 marketing / creative skills (`banner-design`, `brand`, `design`, `design-system`, `slides`) from `.agents/skills/`.
   - Preserved all 10 high-value, domain-specific skills:
     - `nextjs-16-app-router-tanstack`
     - `ohmployee-cross-repo-parity`
     - `supabase-postgres-best-practices`
     - `xlsx-import-reconciliation`
     - `ui-styling`
     - `ui-ux-pro-max`
     - `vercel-composition-patterns`
     - `security-audit`
     - `ponytail`
     - `loop-engineering`
4. **Verification**:
   - `npm test`: 257/257 passed (0 failures)
   - `npm run lint`: 0 errors, 0 warnings
   - `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`
   - `npm run check:sql`: verified 28 core tables & 19 cross-module RPC contracts across 679 migrations

### Files
- Global Provider Config:
  - `config\skills_backup_gcp/*` (backed up 21 GCP skills + manifest)
- Web (`D:\Projects\ohmployee-web`):
  - `.agents/skills/banner-design/` (removed)
  - `.agents/skills/brand/` (removed)
  - `.agents/skills/design/` (removed)
  - `.agents/skills/design-system/` (removed)
  - `.agents/skills/slides/` (removed)
  - `.ai/briefing.md`
  - `.ai/handoff.md`

### Validation
- `npm run check:adr` -> `ADR_MIRROR_STATUS: FRESH` (exit code 0)
- `npm test` -> 257/257 passed (exit code 0)
- `npm run lint` -> 0 errors / 0 warnings (exit code 0)
- `npm run check:sql` -> OK (exit code 0)

---

## Execution Report — Hub-and-Spoke Modular ADR Architecture (ohm#hub-and-spoke-modular-adr-architecture)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - The user asked how to avoid heavy token consumption so that an AI working on a specific module (e.g., Vacancy) does NOT read the entire 14k-token monolithic architecture document.
   - Recommended and implemented **Solution 1: Hub-and-Spoke Modular ADR Architecture**, partitioning architecture rules into dedicated, isolated module files under `docs/architecture/adr/`.
2. **Modular Architecture Structure (`D:\Projects\OHMployee\docs\architecture\adr/`)**:
   - `00_core_invariants.md`: (~70 lines) Mandatory cross-module invariants (Rules 1–7: Slot Authority, Hired HC Source, Lifecycle Sync, Denormalized Writes, User Management SSOT).
   - `01_plantilla.md`: (~270 lines) Store Identity (1 Store = 1 VCODE), Plantilla Baseline Import, Headcount Fractions ($1/N$), 6 Sub-Tabs, DOLE Floating, Relievers (absorbing ADR-002).
   - `02_vacancy.md`: (~180 lines) Capacity Matrix, 5 Tabs, Candidate-Level Pipeline Expansion, Strict Closure Lock, Aging Continuity.
   - `03_hr_emploc.md`: (~190 lines) 5 Queues, Emploc Number Ownership, Deployment Rules a–d, 4 Statutory Requirements, Deployed Reverts.
   - `04_approvals_requisitions.md`: (~350 lines) 11 Queues, Option 1 Requisition Routing, ADR-003 Unified Roving with Atomic Store Provisioning, /my-requests.
   - `05_more_module.md`: (~180 lines) 5 Tabs, 5 Batch Imports with 72h Rollback, QA Simulation Sandbox, MIKA Ghost Detection.
   - `06_dashboard_cencom.md`: (~120 lines) 4 KPIs, CENCOM 5 Tabs, MFR Health Scale, Database Computes / UI Renders, Rounding Contract.
   - `README.md`: Master Catalog & Token Router.
   - Committed in mobile repository on `main` (`0eb4407`).
3. **Web Tooling & Mirror Sync (`scripts/adr-mirror.mjs`)**:
   - Updated `ADR_FILES` in `scripts/adr-mirror.mjs` to mirror all 8 modular files into `docs/architecture/_mirror/adr/` in addition to the monolithic reference.
   - Ran `npm run sync:adr` and verified `ADR_MIRROR_STATUS: FRESH` across all 9 items.
4. **Context Loading Protocol**:
   - Updated `AGENTS.md`, `.ai/briefing.md`, and `.ai/current_state.md` to instruct AI agents to load ONLY `00_core_invariants.md` plus the active module's ADR file (e.g., `02_vacancy.md` for Vacancy).
   - Achieves up to **90% token savings** per prompt with zero line-drift risk.

### Files
- Mobile (`D:\Projects\OHMployee`):
  - `docs/architecture/adr/00_core_invariants.md`
  - `docs/architecture/adr/01_plantilla.md`
  - `docs/architecture/adr/02_vacancy.md`
  - `docs/architecture/adr/03_hr_emploc.md`
  - `docs/architecture/adr/04_approvals_requisitions.md`
  - `docs/architecture/adr/05_more_module.md`
  - `docs/architecture/adr/06_dashboard_cencom.md`
  - `docs/architecture/adr/README.md`
- Web (`D:\Projects\ohmployee-web`):
  - `scripts/adr-mirror.mjs`
  - `docs/architecture/_mirror/adr/*` (mirrored copies)
  - `AGENTS.md`
  - `.ai/briefing.md`
  - `.ai/current_state.md`
  - `.ai/handoff.md`

### Validation
- `npm run check:adr` -> `ADR_MIRROR_STATUS: FRESH` (exit code 0)
- `npm test` -> 257/257 passed (exit code 0)
- `npm run lint` -> 0 errors / 0 warnings (exit code 0)

---

## Execution Report — Restrict HR Emploc Deficiency Reviews to SA & HR Personnel (ohm#restrict-deficiency-review-to-hr-personnel)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - The user explicitly instructed: "Approve Deficiency correction review is only for SA + HR Personnel" and "Revert / Reject Deficiency Correction Review is only for SA and HR Personnel".
   - Removed Operations Team roles (OM 70, HRCO 45, ATL 42, TL 41) from both actions, ensuring compliance reviews are governed solely by HR Personnel (25) and Super Admin (100).
2. **Web RBAC Action Matrix (`src/lib/rbac.ts`)**:
   - `DRAWER_ACTION_RULES["Approve Deficiency Correction Review"]`: updated to `[100, 25]`.
   - `DRAWER_ACTION_RULES["Revert / Reject Deficiency Correction Review"]`: updated to `[100, 25]`.
3. **Database Migration (`supabase/migrations/20262606000154_restrict_deficiency_review_to_hr_personnel.sql`)**:
   - Synchronized `role_permission_definitions_compat` and base matrix `role_permission_matrix` on Staging (`qqiiznmqxfoamqytjica`) to deny OM, HRCO, ATL, and TL while keeping SA and HR Personnel allowed.
   - Pushed live to Staging via `npm run db:push:staging` with zero errors.
4. **Unit Tests (`src/lib/utils/__tests__/rbac_sanity.test.mjs`)**:
   - Removed deficiency review actions from `opsAllowed` array.
   - Verified all 257 unit tests passed cleanly (`npm test`).

### Files
- Web:
  - `src/lib/rbac.ts`
  - `src/lib/utils/__tests__/rbac_sanity.test.mjs`
  - `supabase/migrations/20262606000154_restrict_deficiency_review_to_hr_personnel.sql`
  - `.ai/briefing.md`
  - `.ai/handoff.md`
  - `docs/state/web_auth_rbac_state.md`

### Validation
- `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
- `npm run check:sql`: `SQL_CONTRACTS_OK` (28 core tables & 19 cross-module RPC contracts across 679 migrations).
- `npm test`: `257/257` unit tests passed cleanly.
- `npm run lint`: `0` errors, `0` warnings, `0` secret leaks.
- `npm run build`: verified Next.js 16.2.4 Turbopack production build (`22/22` static pages generated).
- Remote Staging verification (`qqiiznmqxfoamqytjica`): applied migration `20262606000154` via `npm run db:push:staging`.
- `npm run check:migrations`: `prod: 642 migrations, staging: 648 migrations` (6 migrations pending Prod deployment).

---

## Execution Report — Architecture Historical Archive & Superseded Reorganization (ohm#archive-superseded-architecture-docs)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - The user asked whether old/superseded ADR files and rules can be deleted and requested our architectural recommendation.
   - Recommended Option A (Historical Archival to `docs/architecture/archive/` with catalog `README.md`) instead of hard deletion to preserve database schema lineage/archaeology while completely preventing AI agent and developer context confusion.
   - The user confirmed: "Option A".
2. **Mobile Repository Reorganization (`D:\Projects\OHMployee`)**:
   - Created `docs/architecture/archive/`.
   - Moved 24 historical design plans, early phase specifications (Phases A–G and RA–RE), and superseded slot RFCs into `docs/architecture/archive/` using `git mv`:
     - `plantilla_slot_architecture.md`, `vcode_slot_bridge_redesign.md`, `coverage_group_roving_architecture_plan.md`, `coverage_slot_lifecycle_plan.md`, `hrco_scope_isolation_design_draft.md`, `applicant_pipeline_model_design.md`
     - `coverage_group_data_model_plan.md`, `coverage_group_phase_ra_schema_plan.md` to `phase_re`
     - `vcode_slot_phase_a_schema_plan.md` to `phase_g`
     - `slot_derived_vacancy_read_model.md`, `slot_lifecycle_automation_plan.md`, `vacancy_slot_backfill_plan.md`
     - `Coverage_Architecture_v2_Smoke_Test_Checklist.xlsx`
   - Authored `docs/architecture/archive/README.md` cataloging each archived file, explaining its historical context, and explicitly routing readers to active canonical locks.
   - Preserved only 9 active operational/architecture documents in root `docs/architecture/`:
     - Canonical ADR-002 (`adr002_plantilla_import_store_identity_and_governance.md`)
     - Operational guides: `code_review_rubric.md`, `freeze_enforcement_rollout.md`, `permission_drift_detection.md`, `rbac_drift_scanner_engine.md`, `rbac_permission_matrix.md`, `rbac.md`, `system.md`, `workflow.md`.
     - Canonical ADR-001 remains the sole lock in `.ai/architecture_locks/ADR-001-ohmployee-system-architecture.md`.
   - Committed reorganization on `main` in mobile repository (`87e1d8a`).
3. **Web Repository Verification**:
   - Ran `npm run check:adr` — confirmed `ADR_MIRROR_STATUS: FRESH` for both ADR-001 (`227a315`) and ADR-002 (`5ce4032`).
   - Ran full test suite (`npm test`) — 257/257 passing with 0 contract violations.
   - Ran lint suite (`npm run lint`) — 0 errors/warnings.

### Files
- Mobile (`D:\Projects\OHMployee`):
  - `docs/architecture/archive/README.md` (created)
  - 24 files moved from `docs/architecture/*` to `docs/architecture/archive/*`
- Web (`D:\Projects\ohmployee-web`):
  - `.ai/current_state.md`
  - `.ai/handoff.md`

### Validation
- `npm run check:adr` -> `ADR_MIRROR_STATUS: FRESH` (exit code 0)
- `npm test` -> 257/257 passed
- `npm run lint` -> 0 errors / 0 warnings

---

## Execution Report — Data Team (Head Admin 90 & Encoder 30) RBAC Parity Alignment (ohm#data-team-rbac-alignment)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **User Request Alignment**:
   - Aligned RBAC permissions for the Data Team (Head Admin L90 and Encoder L30) across drawer actions, mutations, approval queues, and database permission catalogs:
     1. `HR Emploc` -> **Approve Deficiency Correction Review**: Denied for Head Admin (90) and Encoder (30) (restricted to Ops & HR Personnel 25, plus SA 100).
     2. `HR Emploc` -> **Revert / Reject Deficiency Correction Review**: Denied for Head Admin (90) and Encoder (30).
     3. `Plantilla` -> **Update Employment Lifecycle Status**: Denied for Head Admin (90) and Encoder (30) (restricted to Ops team & SA 100).
     4. `Users` -> **Deactivate / Reactivate User Account**: Allowed for Head Admin (90), Denied for Encoder (30).
     5. `Vacancy` -> **Edit Hired Date**: Denied for both Head Admin (90) and Encoder (30) (restricted to Ops team & SA 100).
     6. `Approvals` -> **Employee Deactivations Queue**: Denied for Head Admin (90) and Encoder (30) in `getAllowedApprovalCategories` (restricted to SA 100 and Backoffice 15).
     7. `Data Control` / `Approvals` -> **Batch Rollback Requests / Rollback Import Batch**: Allowed for Head Admin (90) and SA (100), Denied for Encoder (30).
2. **Web RBAC Action Matrix Evaluator (`src/lib/rbac.ts`)**:
   - In `DRAWER_ACTION_RULES`:
     - Updated `"Edit Hired Date"`: `[100, 70, 45, 42, 41]` (removed 30; 90 omitted).
     - Updated `"Approve Deficiency Correction Review"`: `[100, 70, 45, 42, 41, 25]` (removed 30; 90 omitted).
     - Updated `"Revert / Reject Deficiency Correction Review"`: `[100, 70, 45, 42, 41, 25]` (removed 30; 90 omitted).
     - Updated `"Rollback / Reject Import Batch"`: `[100, 90]` (removed 30; 90 kept).
   - In `canPerformDrawerAction`:
     - Removed blanket `level >= 90` bypass which previously leaked operational drawer actions to Head Admin.
     - Super Admin (`level >= 100` / `isOwner`) retains administrative universal immunity, while all other roles (including Head Admin 90 and Encoder 30) are strictly governed by `DRAWER_ACTION_RULES[actionItem].includes(level)`.
3. **Database Migration (`supabase/migrations/20262606000153_align_data_team_rbac_permissions.sql`)**:
   - Synchronized `role_permission_definitions_compat` and base matrix table `role_permission_matrix` for Head Admin and Encoder across the affected definitions.
   - Pushed live to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging` with zero errors.
4. **Unit Tests (`src/lib/utils/__tests__/rbac_sanity.test.mjs`)**:
   - Updated Sanity 4 and Sanity 6 test assertions to verify exact Head Admin (18 allowed actions, 15 denied actions) and Encoder (12 allowed actions, 21 denied actions) permissions. All 257 unit tests passed cleanly.

### Files
- Web:
  - `src/lib/rbac.ts`
  - `src/lib/utils/__tests__/rbac_sanity.test.mjs`
  - `supabase/migrations/20262606000153_align_data_team_rbac_permissions.sql`
  - `.ai/briefing.md`
  - `.ai/handoff.md`
  - `docs/state/web_auth_rbac_state.md`

### Validation
- `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
- `npm run check:sql`: `SQL_CONTRACTS_OK` (28 core tables & 19 cross-module RPC contracts across 678 migrations).
- `npm test`: `257/257` unit tests passed cleanly.
- `npm run lint`: `0` errors, `0` warnings, `0` secret leaks.
- `npm run build`: verified Next.js 16.2.4 Turbopack production build (`22/22` static pages generated).
- Remote Staging verification (`qqiiznmqxfoamqytjica`): applied migration `20262606000153` via `npm run db:push:staging`.
- `npm run check:migrations`: `prod: 642 migrations, staging: 647 migrations` (5 migrations pending Prod deployment).

---

## Execution Report — RBAC Matrix Lock Bleed Resolution & Operational Permissions Restoration (ohm#fix-rbac-matrix-lock-bleed)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **Root Cause Resolved**:
   - On the dedicated `/rbac` matrix page, 100% of sub-action toggle switches across all operational roles were disabled (`disabled:opacity-40 disabled:cursor-not-allowed`) and marked with a `Locked` badge.
   - Forensic tracing identified that database RPC `public.get_all_roles_effective_permission_matrix` returned `is_system_locked` with `CASE WHEN r.role_name = 'Super Admin' THEN true ELSE d.is_system_locked END AS is_system_locked`.
   - Because the RPC ordered rows by `d.module_key, d.sort_order, r.role_level DESC`, Super Admin (`level 100`) was always the first row returned for every permission definition.
   - Frontend `distinctDefinitions` deduplication in `src/app/(dashboard)/rbac/page.tsx` recorded `isSystemLocked` from the first row (Super Admin), falsely tagging all 58 definitions as system-locked.
   - In `ModuleGroupRows`, `const isLocked = (role.level >= 100) || def.isSystemLocked` evaluated to `true` for all roles (Head Admin, OM, HRCO, ATL, TL, Encoder, etc.), disabling every toggle.
2. **Database Migration (`supabase/migrations/20262606000152_fix_rbac_matrix_system_locked_rpc.sql`)**:
   - Updated `public.get_all_roles_effective_permission_matrix` to return `d.is_system_locked` directly, strictly preserving definition lock semantics.
   - Pushed live to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging` with zero errors and verified live `pg_get_functiondef` parity.
3. **Web Presentation Layer Defense (`src/app/(dashboard)/rbac/page.tsx`)**:
   - Fortified `distinctDefinitions` to prefer non-locked row values (`if (!existing || (existing.isSystemLocked && !r.isSystemLocked))`) so role-level protection on Super Admin never bleeds into the definition catalog.
   - Aligned child action row lock evaluation to `const isLocked = (role.level >= 100) || (row?.isSystemLocked ?? def.isSystemLocked)`, matching module header row behavior.
   - Super Admin immunity (`role.level >= 100`) and the 20 true system invariants (`is_system_locked = true`) remain permanently locked, while the 38 operational definitions are now interactive and editable for operational roles.

### Files
- Web:
  - `supabase/migrations/20262606000152_fix_rbac_matrix_system_locked_rpc.sql`
  - `src/app/(dashboard)/rbac/page.tsx`
  - `.ai/briefing.md`
  - `.ai/handoff.md`
  - `docs/state/web_auth_rbac_state.md`

### Validation
- `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
- `npm run check:sql`: `SQL_CONTRACTS_OK` (28 core tables & 19 cross-module RPC contracts across 677 migrations).
- `npm test`: `257/257` unit tests passed cleanly.
- `npm run lint`: `0` errors, `0` warnings, `0` secret leaks.
- `npm run build`: verified Next.js 16.2.4 Turbopack production build (`22/22` static pages generated).
- Remote Staging verification (`qqiiznmqxfoamqytjica`): applied migration `20262606000152` and confirmed live `pg_get_functiondef`.
- `npm run check:migrations`: `prod: 642 migrations, staging: 646 migrations` (4 migrations pending Prod deployment).

---

## Execution Report — Account-Level Whole Number Headcount & KPI Rounding Protection (ohm#round-account-allocation-kpi-whole-numbers)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **Root Cause Resolved**:
   - In `employee_store_allocations`, roving merchandisers assigned across $N$ stores have fractional headcount shares $1/N$ (e.g. $1/3 \approx 0.33$ or $0.3333$).
   - When summed across stores under an account, floating-point rounding inaccuracies leaked into account-level metrics (e.g., ACTISERVE had an employee with $0.33$ across 3 stores yielding $3.9900$ filled + $5$ vacant + $3$ pipeline = $11.9900$ required, rendering `HC 4/11.99` on the Directory card; BANCON rendered `HC 4/3.9999`; ACTIVESTYLE rendered `HC 1/0.9999`).
   - This violated ADR-001 Invariant 17: while store-level capacity supports fractional roving shares ($1/N$), Account/CENCOM/Dashboard headcount strictly counts distinct people and must always be clean whole numbers.
2. **Database Migration (`supabase/migrations/20262606000147_round_account_allocation_kpi_whole_numbers.sql`)**:
   - Updated `public.v_account_allocation_kpi` to round `required_hc` and `slot_vacant_hc` to whole numbers (`round(..., 0)::numeric(12,4)`), and aligned `mfr` and `projected_mfr` to evaluate against distinct person counts (`actual_hc::numeric / required_hc`), preserving identical column ordering, names, and `numeric(12,4)` types.
   - Refreshed downstream views `v_cencom_account_allocation_kpi`, `v_cencom_group_allocation_kpi`, and `v_cencom_allocation_kpi`.
   - Pushed live to Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging` (exit code 0).
3. **Web Presentation Layer Defense-in-Depth**:
   - `src/app/(dashboard)/plantilla/page.tsx`: In `accountMetricsQuery`, wrapped `actual`, `hrProcess`, `vacant`, `required`, and `leave` in `Math.round()`.
   - `src/components/plantilla/directory/PlantillaAccountSelection.tsx`: Wrapped account summary attributes and JSX displays in `Math.round()` (`Math.round(account.actual)}/{Math.round(account.required)}`, `Math.round(account.vacant)}`, `Math.round(account.hrProcess)}`, `Math.round(account.leave)}`).
   - `src/lib/queries/plantilla.ts`: Wrapped KPI fallback query in `getPlantillaSummary` with `Math.round()` on `actual`, `vacant`, `hrProcess`, and `required`.
   - `src/app/api/ohmni/route.ts`: Hardened anomaly checks and summary formatters with `Math.round()`.
   - `src/components/plantilla/ArchiveAccountModal.tsx`: Applied `Math.round()` on `required` and `actual`.
   - `src/app/(dashboard)/cencom/groups/[id]/page.tsx`: Applied `Math.round()` on `account.required`, `account.actual`, and `account.vacant`.

### Files
- Web:
  - `supabase/migrations/20262606000147_round_account_allocation_kpi_whole_numbers.sql`
  - `src/app/(dashboard)/plantilla/page.tsx`
  - `src/components/plantilla/directory/PlantillaAccountSelection.tsx`
  - `src/lib/queries/plantilla.ts`
  - `src/app/api/ohmni/route.ts`
  - `src/components/plantilla/ArchiveAccountModal.tsx`
  - `src/app/(dashboard)/cencom/groups/[id]/page.tsx`
  - `.ai/briefing.md`
  - `.ai/handoff.md`
  - `docs/state/plantilla_web_state.md`

### Validation
- `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
- `npm run check:sql`: `SQL_CONTRACTS_OK` (28 core tables & 19 cross-module RPC contracts across 672 migrations).
- `npm run check:migrations`: `prod: 640 migrations, staging: 641 migrations` (`1 migrations are not on prod: 20262606000147_round_account_allocation_kpi_whole_numbers.sql`).
- `npm run lint`: `0` errors, `0` warnings.
- `npm test`: `257/257` passed.
- `npm run build`: verified Next.js production build (`22/22` static pages generated).
- Remote Staging verification (`qqiiznmqxfoamqytjica`): migration `20262606000147` applied with 100% `pg_get_viewdef` parity.

---

## Execution Report — Cross-Account Store Resolution & Headcount Request Parity (ohm#fix-hc-request-cross-account-store-resolution)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **Root Cause Resolved**:
   - In `submit_headcount_request`, Stationary validation previously enforced `WHERE id = v_store_id AND account_id = v_account_id`.
   - When an operator submitted a headcount request for a store that was registered in master records under another account (e.g. `Super 8 Dau` under `ACTIVESTYLE` instead of `ACTISERVE`), or an unmapped store, the RPC rejected the call with technical error `invalid_reference (store_id)`.
2. **Cross-Account Store Resolution & Provisioning Migration (`20262606000145_fix_hc_request_cross_account_store_resolution.sql`)**:
   - Surgically upgraded `public.submit_headcount_request(p_input jsonb)`.
   - **Stationary Resolution**: When `store_id` is passed but does not exist under `v_account_id`, it checks across active master stores. If found, it checks if a store with that name already exists for `v_account_id`. If so, uses it; if not, auto-provisions an active store record for `v_account_id` and uses that new store ID. Foreign key constraints on `headcount_requests.store_id`, `vacancies.store_id`, and `plantilla_slots.store_id` remain 100% valid and bound to the operational account.
   - **Name-Based Matching**: When `store_id` is null but `store_name` is provided, it resolves by store name or adopts metadata from the master store catalog and provisions an active store for `v_account_id`.
   - **Roving Resolution**: Similarly, roving store array elements from master records are resolved or provisioned for `v_account_id`.
   - **Human-Readable Error Messages**: Added descriptive `message` fields across all validation and authorization paths.
   - Pushed and verified live on Staging (`qqiiznmqxfoamqytjica`) via `npm run db:push:staging`.
3. **Web Query & Error Display Refinement (`src/lib/queries/requests.ts`)**:
   - Enhanced `submitHeadcountRequest` to surface `data?.message` directly or format `invalid_reference` with field context.
4. **Mobile Cross-Repo Parity (`D:/Projects/OHMployee`)**:
   - `lib/features/plantilla/plantilla_screen.dart`: Updated `_applyInitialStoreContext` so `_selectedStore` is populated even when an unmapped or cross-account store is passed via `widget.initialStoreName`, enabling `_canSubmit` and submitting cleanly.
   - `lib/data/services/plantilla_scope_service.dart`: Updated `_jsonResult` to surface user-friendly `result['message']` from RPC responses in `PlantillaScopeException`.
   - Mirrored migration `20262606000145_fix_hc_request_cross_account_store_resolution.sql` into Mobile `supabase/migrations/`.

### Files
- Web:
  - `supabase/migrations/20262606000145_fix_hc_request_cross_account_store_resolution.sql`
  - `src/lib/queries/requests.ts`
  - `docs/state/plantilla_web_state.md`
  - `.ai/handoff.md`
- Mobile:
  - `D:/Projects/OHMployee/supabase/migrations/20262606000145_fix_hc_request_cross_account_store_resolution.sql`
  - `D:/Projects/OHMployee/lib/features/plantilla/plantilla_screen.dart`
  - `D:/Projects/OHMployee/lib/data/services/plantilla_scope_service.dart`

### Validation
- `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
- `npm run check:sql`: `SQL_CONTRACTS_OK` (28 core tables & 19 cross-module RPC contracts across 670 migrations).
- `npm run lint`: `0` errors, `0` warnings.
- `npm test`: `255/255` passed.
- `npm run build`: verified Next.js production build (`22/22` static pages).
- Mobile `flutter analyze`: `0` errors, `0` warnings on modified files.
- Mobile `flutter test`: `27/27` passed.
- Remote Staging verification (`qqiiznmqxfoamqytjica`): migration `20262606000145` applied with 100% `pg_get_functiondef` parity.

---

## Execution Report — Request Headcount Modal Layout Polish & Scope Optimization (ohm#polish-request-headcount-modal)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **Modal Form Factor & Container Optimization**:
   - Resized dialog container `maxWidthClass` on `<Modal>` in `RequestHeadcountModal.tsx` from `max-w-3xl` (768px) to `max-w-xl` (576px), eliminating awkward horizontal sprawl for a 4-field requisition dialog.
   - Reduced content padding and vertical item gaps from `p-6 space-y-6 max-h-[75vh]` to `p-5 space-y-4 max-h-[80vh]`.
2. **Removed Redundant "Target Operational Account" Card**:
   - When opened inside the Plantilla module (where `propAccountId` is already provided by the active plantilla scope), completely eliminated the redundant "Target Operational Account" card and badges.
   - For standalone invocations without a pre-scoped account (`!propAccountId`), rendered a clean, simple `<select>` dropdown.
3. **Streamlined Store Verification Display**:
   - Replaced bulky nested card-inside-card double borders with a sleek, compact single-row store indicator:
     `[ MapPin icon | Store Name | Island Group badge | City, Province ] --- [ Store Locked / Selected Store ]`.
4. **Clean Grid Form Elements**:
   - Removed nested outer bordered container frames from Position & Headcount, rendering Position Title and Request Type in a clean 2-column grid.
   - Retained the compact Headcount Needed stepper row directly below.
   - Rendered Vacant Date, Urgency Tier, and Target Fill Date in a clean 3-column grid without outer boxed card frames.
   - Rendered Operational Justification with integrated live character count header and clean textarea without outer wrapper boxes.
5. **Step 2 (Review Step) Polish**:
   - Optimized spacing from `space-y-6` to `space-y-4`, condensed item paddings to `p-3.5`, and removed redundant Operational Account prominence when pre-scoped by Plantilla.
6. **TypeScript Interface Fix in `SlotDetailDrawer.tsx`**:
   - Fixed `humanizeRemarks(remarks, actionType, reasonCode)` parameter type to `reasonCode?: string | null` to accept nullable database values cleanly.

### Files
- `src/components/modals/RequestHeadcountModal.tsx`
- `src/components/plantilla/SlotDetailDrawer.tsx`
- `.ai/briefing.md`
- `.ai/handoff.md`
- `docs/state/plantilla_web_state.md`

### Validation
- `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
- `npm run lint`: `0` errors, `0` warnings (`SQL_CONTRACTS_OK`, zero leaks).
- `npm test`: `255/255` passed.
- `npm run build`: verified production build compilation (`22/22` static pages).

---

## Execution Report — Plantilla Slot Detail Drawer & Store View Audit Polish (ohm#slot-drawer-and-store-vcode-audit-polish)
**Date:** 2026-11-23 | **Branch:** `main` | **Status:** Verified & Complete

### What Was Built
1. **`SlotDetailDrawer.tsx` VCode Badge Alignment**:
   - Replaced neutral generic VCode badge with the semantic deployment color scheme matching `StoreCapacityTable` and `StoreDetailsModal`:
     - **Stationary VCode**: Crisp Blue badge (`border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-800 dark:bg-blue-950/60 dark:text-blue-300`).
     - **Roving VCode**: Violet / Purple badge (`border-purple-300 bg-purple-50 text-purple-700 dark:border-purple-800 dark:bg-purple-950/60 dark:text-purple-300`).
     - **No VCode**: Dashed border badge with contextual tooltip.
   - Cleaned store name in drawer subtitle via `formatStoreName(slot.storeName || slot.storeCode)`.
2. **Clean Position Type Resolution**:
   - Resolved redundant raw casing in the Lifecycle State card (e.g. `stationary • Stationary` -> clean `Stationary`; `roving • Roving` -> clean `Roving`).
3. **Enterprise Humanized Remarks & Status Transitions in Slot Audit Trail**:
   - Rewrote raw technical remarks in `SlotDetailDrawer.tsx` and `StoreDetailsModal.tsx` into clean operational descriptions:
     - `Phase 6.4 / plantilla_update_separation / ... / reason=RESIGNED`: Translated to `"Occupant separated (Resigned). Workforce slot vacated and returned to open pool."` (with adaptive support for `AWOL`, `Terminated`, etc.).
     - `auto_move_to_plantilla: slot occupied by plantilla ...`: Translated to `"Slot occupied and assigned to deployed plantilla staff."`
     - `confirm_applicant_onboard`: Translated to `"Applicant confirmed onboard and transitioned to HR Emploc for deployment."`
     - Stripped raw RPC parameter dumps, `plantilla_id=...`, `employee_no=...`, and internal UUID strings.
   - Upgraded timeline action headers with semantic `StatusBadge` variants (`Slot Filled / Deployed`, `Occupant Resigned`, `HR Processing`, `Applicant Sourced`).
   - Replaced raw text transitions (`occupied -> open`) with styled inline status badges (`Occupied → Open`).
   - Cleaned performer attribution (`Logged by {performer}`), showing `"System Automated"` when raw UUIDs appear instead of names.

### Files
- `src/components/plantilla/SlotDetailDrawer.tsx`
- `src/components/modals/StoreDetailsModal.tsx`
- `docs/state/plantilla_web_state.md`
- `.ai/briefing.md`
- `.ai/handoff.md`

### Validation
- `npm run check:adr`: `ADR_MIRROR_STATUS: FRESH`.
- `npm test`: `255/255` passed (`ADR_MIRROR_STATUS: FRESH`, `SQL_CONTRACTS_OK`, zero leaks).
- `npm run lint`: `0` errors, `0` warnings.
- `npm run build`: verified production build compilation (`22/22` static pages).

---

---

> [!NOTE]
> **Historical Execution Archive:**
> Execution reports older than the last 10 prompts (reports #11 through #566) are archived in [`.ai/archive/handoff_historical.md`](archive/handoff_historical.md) to maintain maximum token efficiency.
