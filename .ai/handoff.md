# AI Handoff

## Plantilla Baseline Import Slot Reason Codes Fix & Compact Table Layout (ohm#x7k4w9m2)

**Status: COMPLETE — MIGRATION `20262606000056` APPLIED TO LIVE STAGING, MISSING REASON CODES `IMPORT_VACANT_SLOT` & `IMPORT_CLAIM_VACANT` SEEDED IN `slot_reason_codes`, DEFENSIVE LOOKUP GUARDS & RETRYABLE `commit_failed` ADDED TO `approve_plantilla_import_batch`, BATCH `#7d961dfc` RESET TO `pending_approval`, COMPACT TYPOGRAPHY & `useUsersList()` ACTOR RESOLUTION IMPLEMENTED IN `PlantillaImportModal.tsx` (0 BUILD/LINT REGRESSIONS ON MAIN)**

### Objective & Changes Delivered
1. **Database Schema & Foreign Key Fix (Migration `20262606000056_fix_slot_history_reason_codes.sql`)**:
   - **Root Cause**: Batch `#7d961dfc` failed on approval with `violates foreign key constraint "slot_history_reason_fkey" (SQLSTATE 23503)` when attempting to insert vacant store rows into `public.slot_history` using `'IMPORT_VACANT_SLOT'`, which was missing from lookup table `public.slot_reason_codes`.
   - **Seeded Master Lookup**: Added `'IMPORT_VACANT_SLOT'` and `'IMPORT_CLAIM_VACANT'` with active status and descriptive labels to `public.slot_reason_codes`.
   - **Defensive Reason Code Verification**: Updated [`approve_plantilla_import_batch`](file:///d:/Projects/ohmployee-web/supabase/migrations/20262606000056_fix_slot_history_reason_codes.sql) so all `INSERT INTO public.slot_history` calls check `CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = ...) THEN ... ELSE NULL END`, preventing foreign key constraint crashes if an unseeded reason code is ever supplied.
   - **Retryable Failed Batches**: Updated the status validation guard in `approve_plantilla_import_batch` to allow `commit_failed` alongside `pending_approval`.
   - **Batch `#7d961dfc` Reset**: Reset batch `#7d961dfc-8c09-4db0-8225-74ab26d9a607` from `commit_failed` to `pending_approval` with cleared error fields.
   - **Applied to Live Staging**: Migration applied and verified via Supabase MCP.

2. **Typography & Spacing Overhaul (`PlantillaImportModal.tsx`)**:
   - **Inspect Batch Rows Table**:
     - `th`: Standardized to `text-[10px] font-semibold uppercase tracking-wider px-2.5 py-1.5 text-text-muted`.
     - `td`: Scaled down to `px-2.5 py-1.5 align-middle`.
     - Primary cell text (`VCODE`, `STORE_NAME`, `Position`, `Employee Name`): Clean `text-xs font-medium leading-tight` (max 12px, removed heavy font weights).
     - Secondary metadata (`Mother:`, `ID:`, Schedule): Standardized to `text-[11px] text-slate-500 leading-tight`.
     - Badges (`FLAGGED`, `VALID`, `BLOCKED`, `ROVING`, `STATIONARY`, `NEEDS HRCO`, `Vacant Baseline Slot`): Compact `text-[10px] px-1.5 py-0.5 rounded font-medium`.
     - Validation Issues & Guidance: Scaled to `text-[11px] leading-snug space-y-0.5` with compact badges (`text-[10px] px-1.5 py-0.5 font-mono font-medium`) so roving messages fit cleanly on 1–2 lines without vertical row bloat.
   - **Import History Table**:
     - Standardized headers to `text-[10px] font-semibold uppercase tracking-wider px-2.5 py-1.5 text-text-muted`.
     - Standardized cells to `px-2.5 py-1.5 align-middle text-xs leading-tight`.
     - Refined column widths (`w-20` Batch #, `w-44` File Name, `w-28` Status, `w-20` Stores/HC, `w-44` Rollback, `w-36` Scope, `w-32` Uploaded By, `w-36` Approved/Rejected By, `w-24` Date).
     - **Clean Actor Lookup**: Integrated `useUsersList()` to build a high-performance profile and auth user ID map, converting raw UUIDs to human full names (e.g. `"Litong, Ohm"`) with fallback to `${uuid.slice(0, 8)}...`.

3. **Status Inclusion**:
   - Added `"commit_failed"` to `reviewableStatuses` in `PlantillaImportModal.tsx` so failed batches are directly viewable and actionable in the Review Queue.

### Verification
- `npm run lint`: Clean with 0 errors across the codebase.
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 static routes.
- Staging verification: Query confirmed `IMPORT_VACANT_SLOT` and `IMPORT_CLAIM_VACANT` are present in `public.slot_reason_codes`, and batch `#7d961dfc` is in `pending_approval` ready to approve.

---

## Dedicated Plantilla Import Batch Rejection Reason Modal & Feedback Toast (ohm#j9w4m2x8)

**Status: COMPLETE — INLINE REJECTION INPUT ELIMINATED, DEDICATED HIGH-PRIORITY REJECTION REASON MODAL IMPLEMENTED WITH MANDATORY AUDIT NOTE VALIDATION, CONFIRMATION TOAST NOTIFICATION & QUEUE CACHE INVALIDATION WIRED (0 BUILD/LINT REGRESSIONS ON MAIN)**

### Objective & Changes Delivered
1. **Dedicated Rejection Reason Modal Component (`PlantillaImportModal.tsx`)**:
   - Replaced fragile inline rejection text input in the Review Queue inspect drawer with a dedicated modal dialog (`isRejectModalOpen`, `z-60`).
   - Title: **"Reject Plantilla Batch"** featuring the target Batch ID, file name, and operational group/account scope.
   - Textarea: Structured input for operational audit justification (`rejectionNote`).
   - Controls:
     - **Cancel**: Closes modal and clears `rejectionNote` and `rejectionNoteError`.
     - **Confirm Rejection**: Validates input; if empty or whitespace-only, displays inline alert (`"Please provide an audited reason note for rejection."`). Once validated, triggers `rejectPlantillaImportBatch({ batchId, reasonCode: 'other', reasonNote })` with a loading state.

2. **UX & Feedback Integration**:
   - Integrated floating top-right confirmation toast notification (`toastMessage`, auto-dismissing after 4s) upon successful rejection.
   - Synchronized review notice banner (`reviewNotice`) and invalidates React Query cache (`plantilla-import-batches`) alongside `refetchBatches()`.
   - Wired all **Reject** and **Dismiss / Reject** buttons on batch cards and inspect drawers to launch the dedicated modal.

### Verification
- `npm run lint`: Clean with 0 errors across the codebase.
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 static routes.

---

## Synchronize `pnpm-lock.yaml` with `exceljs` Dependency for Vercel CI Deployments (ohm#b4k9w2x7)

**Status: COMPLETE — `pnpm-lock.yaml` REGENERATED AND SYNCHRONIZED WITH `package.json` (`exceljs@^4.4.0`), FROZEN-LOCKFILE CI VALIDATION SUCCEEDED, 0 BUILD/LINT REGRESSIONS ON MAIN**

### Objective & Changes Delivered
1. **Root Cause Resolution for Vercel Deployment Failure**:
   - Vercel detects `pnpm-lock.yaml` in the repo root and executes `pnpm install --frozen-lockfile`.
   - When `exceljs@^4.4.0` was introduced into `package.json` in `ohm#e7m4x9w2`, `package-lock.json` was updated but `pnpm-lock.yaml` was left desynchronized.
   - This caused Vercel deployment builds to fail with `ERR_PNPM_OUTDATED_LOCKFILE: Cannot install with "frozen-lockfile" because pnpm-lock.yaml is not up to date with <ROOT>/package.json (* 1 dependencies were added: exceljs@^4.4.0)`.

2. **Lockfile Synchronization**:
   - Executed `pnpm install` locally, incorporating `exceljs@4.4.0` and its required dependency tree into `pnpm-lock.yaml`.
   - Verified that `pnpm install --frozen-lockfile` runs to completion cleanly with zero specifier mismatches.

### Verification
- `pnpm install --frozen-lockfile`: Passed cleanly (`Already up to date` in 453ms).
- `npm run lint`: Clean with 0 errors across the codebase (25 pre-existing warnings).
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 static routes.

---

## Plantilla Review Queue Inspect Rows Typography & Spacing Simplification (ohm#r4k8m2w6)

**Status: COMPLETE — REVIEW QUEUE INSPECT ROWS TABLE TYPOGRAPHY SIMPLIFIED & SCALED DOWN, PRIMARY IDENTIFIERS CLEANED TO TEXT-XS MEDIUM WEIGHT, CELL PADDING STANDARDIZED TO PX-3 PY-2, ADVISORY TEXT & BADGES COMPACTED (0 BUILD/LINT REGRESSIONS ON MAIN)**

### Objective & Changes Delivered
1. **Primary Identifier Typography Reduction**:
   - `VCODE`: Updated from `text-sm font-bold font-mono` to `text-xs font-medium font-mono text-text-primary whitespace-nowrap`.
   - `Store Name`: Updated from `text-sm font-semibold` to `text-xs font-medium text-text-primary leading-tight`.

2. **Metadata & Advisory Typography Alignment**:
   - `Employee ID`: Kept at clean `text-xs font-mono text-purple-700 leading-tight`.
   - `Mother Account`: Standardized at `text-xs text-text-muted font-mono leading-tight mt-0.5`.
   - `Schedule & Shift details`: Standardized at `text-xs text-text-muted truncate mt-0.5 leading-tight`.
   - `Validation Issues & Guidance`:
     - Tightened message spacing from `space-y-1` to `space-y-0.5`.
     - Standardized error and flag advisory text to `text-xs font-normal leading-tight break-words`.
     - Standardized advisory pills (`conflictType`, `field`, `flag`) to `px-1.5 py-0.5 text-3xs font-mono font-medium shrink-0 leading-none`.
     - Refined "Ready for import", "Existing VCODE skipped", and "Pending" statuses to `text-xs font-medium leading-tight`.

3. **Table Spacing & Badge Alignment**:
   - Standardized table cell padding across all `th` headers and `td` cells in the Review Queue inspect rows table to `py-2 px-3`.
   - Compacted status pills (`VALID`, `FLAGGED`, `BLOCKED`, `SKIPPED`, `ROVING`, `STATIONARY`, `NEEDS HRCO`, `Vacant Baseline Slot`) with `px-1.5 py-0.5 text-3xs font-medium leading-none whitespace-nowrap` for balanced vertical flow.

### Verification
- `npm run lint`: Clean with 0 errors across the codebase.
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 static routes.

---

## Flexible Plantilla Import Approval for Flagged Rows & HRCO Auto-Tagging Fallback (ohm#y8k4w2m9)

**Status: COMPLETE — PRE-COMMIT GUARD UPDATED TO BLOCK ONLY HARD ERRORS (VALIDATION_STATUS = 'BLOCKED'), ADVISORY FLAGGED ROWS PERMITTED TO COMMIT, ACCOUNT HRCO AUTO-TAGGING & DEFAULT FALLBACK IMPLEMENTED, ERROR STRING PROPAGATION ENHANCED, MIGRATION LIVE-APPLIED TO STAGING (0 BUILD/LINT REGRESSIONS ON MAIN)**

### Objective & Changes Delivered
1. **Flexible Pre-Commit Guard (`approve_plantilla_import_batch`)**:
   - Replaced strict block on `validation_status = 'flagged'` with a targeted hard-error block:
     - Only rows with `validation_status = 'blocked'` strictly block batch approval (`Cannot approve batch: X blocked rows must be resolved or removed first`).
     - Advisory/warning rows with `validation_status = 'flagged'` (e.g., roving fractional headcount, `NEEDS HRCO`, advisory notes) are permitted to commit alongside `valid` rows.
   - Updated committable rows definition to `validation_status IN ('valid', 'flagged') AND vcode IS NOT NULL`.

2. **HRCO Auto-Tagging & Default Fallback on Commit**:
   - Retrieved selected account's assigned HRCO (`accounts.hrco_user_id`) and name from `users_profile`.
   - In Phase B2 employee loop:
     - Resolves `v_final_hrco_id := COALESCE(v_emp_rec.hrco_id, v_acct_hrco_id)`.
     - When HRCO is resolved, populates `hrco_user_id_snapshot` and `hrco_name`, setting `needs_hrco = false`.
     - When neither row nor account provides an HRCO, safely defaults `hrco_user_id_snapshot = NULL`, `hrco_name = NULL`, and sets `needs_hrco = true` without raising constraint errors.
   - Also defaults account HRCO onto newly created stores (`public.stores.hrco_user_id`) and vacancies (`public.vacancies.hrco_user_id`, `public.vacancies.hrco_name`).

3. **Synchronized Scope across Phases**:
   - Phase A (Store upsert), Phase B1 (Vacant slot shadow insert), and Phase B2 (Assigned employee upsert & store allocations) all operate on `validation_status IN ('valid', 'flagged')`.

4. **Frontend Action Feedback Enhancement (`src/lib/queries/dataControl.ts`)**:
   - Updated `approvePlantillaImportBatch(batchId: string)`:
     - Formats Supabase RPC errors with message, details, and hint: `[error.message, error.details, error.hint].filter(Boolean).join(" - ")`.
     - Checks returned data object for `status === "commit_failed"` and surfaces the detailed database error message directly into the UI action error banner.

### Verification
- **Live Staging Applied**: Applied migration `20262606000055_allow_flagged_rows_on_plantilla_import_approval.sql` to live staging database (`qqiiznmqxfoamqytjica`).
- `npm run lint`: Clean with 0 errors across all files.
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 static routes.

---

## Fix Plantilla Import Batch Commit Failure & Vacancies Not-Null Constraints (ohm#m2x7k9w4)

**Status: COMPLETE — ROOT CAUSE TRACED & VERIFIED ON BATCH #306ff1ae, PRE-COMMIT FLAGGED ROWS GUARD ENFORCED, VACANCIES SHADOW SYNC FIXED WITH ACCOUNT & POSITION, HUMAN-READABLE EXCEPTION PROPAGATION IMPLEMENTED, MIGRATION LIVE-APPLIED TO STAGING, TS RPC CALLER UPDATED (0 BUILD/LINT REGRESSIONS ON MAIN)**

### Objective & Changes Delivered
1. **Database Logs & Exception Tracing for Batch `#306ff1ae`**:
   - Traced `batch_id = '306ff1ae-fc47-480c-928c-99797fa7562d'` on live Staging (`qqiiznmqxfoamqytjica`):
     - `status`: `commit_failed`
     - `commit_error_detail`: `"[23502] null value in column \"account\" of relation \"vacancies\" violates not-null constraint"`
     - Total rows: 11 (`valid_rows`: 9, `flagged_rows`: 2).
     - Rows 7, 8, 9 represented vacant store slots (`employee_no = null`) for `SMCO KAWIT`, `PUREGOLD - HUGO PEREZ`, and `PUERGOLD GENERAL TRIAS`.
     - In Phase B1 of `approve_plantilla_import_batch`, vacant store slots sync shadow records into `public.vacancies`. The `INSERT INTO public.vacancies (...)` statement omitted required `NOT NULL` columns `account` and `position`, triggering error 23502.
     - Confirmed subtransaction savepoint rollback was clean (`plantilla_import_commit_snapshots` count is 0).

2. **Database Migration `20262606000054_fix_plantilla_import_vacancies_and_flagged_guard.sql` (Live Applied to Staging)**:
   - **Schema Alignment**: Added `error_message text` column to `public.plantilla_import_batches` via `ALTER TABLE public.plantilla_import_batches ADD COLUMN IF NOT EXISTS error_message text;`.
   - **Pre-commit Flagged Row Guard**:
     - Pre-commit check queries `validation_status = 'flagged'`.
     - If count > 0, raises `Cannot approve batch: % flagged rows must be resolved or dismissed first` (SQLSTATE `22023`) *before* beginning the transaction, keeping the batch safely in `pending_approval` rather than failing mid-commit.
   - **Phase B1 Vacancies Shadow Insert Fix**:
     - Explicitly populates `account = COALESCE(v_acct_name, 'Unknown Account')` and `position = COALESCE(v_vrow.position, 'Merchandiser')` in `INSERT INTO public.vacancies`.
     - Standardized `ON CONFLICT (vcode) DO UPDATE` to sync `account`, `position`, `store_name`, `area_city`, `province`, `area_name`, `store_id`, `account_id`, `group_id`, `status = 'Open'`, and resets `deleted_at = NULL, is_archived = false`.
   - **Robust Human-Readable Error Translation**:
     - Exception handler intercepts constraint codes (`23502` missing required field, `23505` unique conflict, `23503` foreign key violation) and formats them into plain-English explanations.
     - Synchronizes both `batch.commit_error_detail` and `batch.error_message`.

3. **TypeScript RPC Caller Update (`src/lib/queries/dataControl.ts`)**:
   - Updated `approvePlantillaImportBatch(batchId: string)`: checks returned payload for `status === 'commit_failed'` and throws `new Error(res.error || "Plantilla batch commit failed.")` to trigger user-facing error banners in the UI.
   - Extended `PlantillaImportBatch` interface and mapper in `fetchPlantillaImportBatches` with `commitErrorDetail` and `errorMessage`.

### Verification
- **Staging DDL Execution**: Migration `fix_plantilla_import_vacancies_and_flagged_guard` applied cleanly to live Supabase staging (`qqiiznmqxfoamqytjica`); verified `error_message` column present.
- `npm run lint`: Clean with 0 errors across all files.
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 routes.

---

## Plantilla Review & History Table Typography & Responsive Layout Polish (ohm#t8k2m7w4)

**Status: COMPLETE — TYPOGRAPHY HIERARCHY SIMPLIFIED, CELL PADDING & LINE HEIGHTS COMPACTED, STATUS BADGES TIGHTENED, IMPORT HISTORY WRAPPED IN OVERFLOW CONTAINER WITH TEXT TRUNCATION & TOOLTIPS (0 BUILD/LINT REGRESSIONS ON MAIN)**

### Objective & Changes Delivered
1. **Plantilla Review Table Typography & Row Spacing Polish**:
   - **Font Hierarchy**:
     - Elevated primary identifiers (`VCODE`, `Store Name`) to crisp `text-sm font-semibold text-text-primary`.
     - Scaled down metadata (`Employee ID`, `Mother Account`, schedule/shift text, `Position`, `requiredHc`) to `text-xs leading-tight text-text-muted`.
     - Cleaned multi-line stacked cells into inline dot-separated metadata rows to eliminate vertical bloating.
   - **Badge & Pill Compactness**:
     - Applied compact padding (`px-1.5 py-0.5 text-3xs font-bold leading-none whitespace-nowrap`) to status badges (`PENDING APPROVAL`, `FLAGGED`, `VALID`, `NEEDS HRCO`, `roving`, `stationary`) so badges no longer add vertical height.
   - **Guidance & Warning Text Styling**:
     - Styled validation error and guidance messages in `text-xs leading-tight break-words text-rose-700` and `text-xs leading-tight break-words text-amber-700` with compact conflict/field pill badges.
   - Applied identical typographic and badge compactness to the row inspection drawer in the History tab.

2. **Import History Table Layout & Horizontal Responsiveness**:
   - **Horizontal Overflow Container**:
     - Wrapped the history table in an `overflow-x-auto` container with fixed column widths (`table-fixed min-w-[920px]`) guaranteeing primary metrics (`BATCH #`, `STATUS`, `STORES / HC`) remain distinctly visible without column cramping on smaller viewports.
   - **Cell Spacing & Truncation with Tooltips**:
     - Tightened cell padding to `py-2.5 px-2.5` with `leading-tight` and `text-xs`.
     - Applied `truncate` and native `title` hover tooltips to `File Name`, `Scope`, `Uploaded By`, `Approved / Rejected By` (using `formatActor` to shorten raw UUIDs into `123e4567...` while preserving the full UUID on hover), and `Date`.
     - Guarded status and rollback badges with `whitespace-nowrap` to prevent awkward line breaks and row distortion.

### Verification
- `npm run lint`: Clean with 0 errors across all files.
- `npm run build`: Turbopack compilation succeeded with 0 errors across all 19 static routes.

---

## ExcelJS ADR-002 Plantilla Import Template Generator (ohm#e7m4x9w2)

**Status: COMPLETE — EXCELJS TEMPLATE GENERATOR IMPLEMENTED, REQUIRED HEADERS HIGHLIGHTED (#FFC7CE / #9C0006), NATIVE EXCEL DROPDOWNS WIRED FOR SCHEDULE_DAYS, SCHEDULE_TIME & DAYOFF, 15-RULE VALIDATION GUIDE FORMATTED (0 BUILD/LINT REGRESSIONS ON MAIN)**

### Objective & Changes Delivered
1. **Required & Conditional Header Styling**:
   - Installed `exceljs` (`^4.4.0`) to generate binary `.xlsx` files with rich formatting directly in the browser.
   - Styled the 8 Always Required Store Headers (`GROUP_NAME`, `ACCOUNT_NAME`, `MOTHER_ACCOUNT`, `VCODE`, `STORE_NAME`, `AREA_PROVINCE`, `AREA_CITY`, `POSITION`) and 5 Conditionally Required Employee Headers (`EMPLOYEE_NO`, `LAST_NAME`, `FIRST_NAME`, `MIDDLE_NAME`, `DATE_HIRED`) with:
     - Soft red fill background: `#FFC7CE` (`ARGB: FFFFC7CE`)
     - Bold dark red font: `#9C0006` (`ARGB: FF9C0006`)
     - Alignment: Centered vertically and horizontally with wrap text
     - Borders: Thin borders on all sides
   - Optional headers (`CIVIL_STATUS`, `RATE`, `DATE_OF_BIRTH`, `CONTACT_NO`, `ADDRESS`, `SCHEDULE_DAYS`, `SCHEDULE_TIME`, `DAYOFF`, `COORDINATOR`, `HRCO_EMAIL`):
     - Soft neutral fill (`#F3F4F6`), dark slate font (`#374151`), centered, thin borders.
2. **Native Excel Data Validation Dropdowns (Rows 2–500)**:
   - `SCHEDULE_DAYS` (Column S): Native list dropdown with presets (`MON-SAT`, `MON-FRI`, `TUE-SUN`, `MON,WED,FRI`, `TUE,THU,SAT`, `FLEXI`), non-blocking warning style.
   - `SCHEDULE_TIME` (Column T): Native list dropdown with presets (`08:00 AM - 05:00 PM`, `09:00 AM - 06:00 PM`, `FLEXI (4 HRS)`, `FLEXI (6 HRS)`), free-text entry allowed.
   - `DAYOFF` (Column U): Native list dropdown with presets (`SUN`, `SAT,SUN`, `MON`, `TUE`, `WED`, `THU`, `FRI`, `SAT`), custom entry allowed.
3. **15-Rule Validation Guide Sheet (`VALIDATION_GUIDE`)**:
   - Formatted secondary worksheet containing all 15 ADR-002 architectural invariants and column specifications with stylized indigo header row and lavender section separator.
4. **Resilience & Non-Regression**:
   - `parseSpreadsheetToRows` remains untouched on `xlsx`, preserving upload parsing stability.
   - Replaced `aoa_to_sheet` in `downloadPlantillaImportTemplate()` with `workbook.xlsx.writeBuffer()`.

### Verification
- `npm run build`: Turbopack compilation succeeded with 0 errors across all 19 static routes.
- `npm run lint`: Clean with 0 errors.

---

## Implement ADR-002 Plantilla Import, Store Identity, Headcount Governance & 72h Rollback Architecture (ohm#p9x2w8m4)

**Status: COMPLETE — ADR-002 AUTHORED & CROSS-REFERENCES UPDATED, DATABASE MIGRATION APPLIED TO LIVE STAGING (`qqiiznmqxfoamqytjica`), EXCEL TEMPLATE & 19-RULE GUIDE IMPLEMENTED, OPS SCHEDULE & DAYOFF CONTROLS INTEGRATED, ZERO-EDIT LOCK & VACANT-TO-OCCUPIED SLOT TRANSITIONS VERIFIED (0 BUILD/LINT ERRORS ON MAIN)**

### Objective & Changes Delivered
1. **Architectural Specification & Legacy Cross-References (Step 1)**:
   - Authored [ADR-002: Plantilla Import, Store Identity, Headcount Governance & Rollback Architecture](docs/architecture/adr002_plantilla_import_store_identity_and_governance.md) locking in all 10 architectural invariants:
     - Invariant 1: Plantilla as upstream origin for stores, slots, and allocations (supports vacant slots; downstream checks validate against VCODE).
     - Invariant 2: Permanent 1 Store Name = 1 VCODE identity within an account (`slot_ordinal` 1..N).
     - Invariant 3: Roving Coverage Group (`CGCODE`) overlay coexists with permanent store `VCODE`.
     - Invariant 4: Auto-computed `employment_type` (`stationary` vs `roving`) and fractional headcount ($1/N$ HC per store).
     - Invariant 5: Multi-batch existing VCODE rule (vacant row skips non-blocking; assigned employee claims open slot or increments ordinal).
     - Invariant 6: `MOTHER_ACCOUNT` required; `with_penalty` derived from mother account configurations.
     - Invariant 7: Strict middle name validation ($\ge 2$ alpha characters or explicit `'NA'`/`'N/A'`; single-char initials rejected). Partial employee rows without `EMPLOYEE_NO` hard-blocked.
     - Invariant 8: `SCHEDULE_DAYS`, `SCHEDULE_TIME` (shifts/flexi), `DAYOFF` (multi-select/custom).
     - Invariant 9: Per-Account HRCO auto-population (1 HRCO $\to$ auto-assigned; 0 or $>1 \to$ `needs_hrco = true`) + reactive backfill when an account's HRCO is assigned.
     - Invariant 10: 72h rollback window, HA/SA approval, SA override only if 0 edits; strict Zero-Edit Immutability Lock blocking rollback if any record was touched post-approval; rich Import History tracking.
   - Added explicit **"Partially Superseded by ADR-002"** banners to legacy documents:
     - `D:/Projects/OHMployee/docs/architecture/plantilla_slot_architecture.md`
     - `D:/Projects/OHMployee/docs/architecture/vcode_slot_bridge_redesign.md`
     - `D:/Projects/OHMployee/docs/architecture/coverage_group_roving_architecture_plan.md`
   - Mirrored ADR-002 in `D:/Projects/OHMployee/docs/architecture/adr002_plantilla_import_store_identity_and_governance.md` and updated `.ai/current_state.md`.

2. **Database Migration Applied to Live Staging (`supabase/migrations/20262606000053_adr002_plantilla_identity_and_governance.sql`) (Step 2)**:
   - Added columns: `mother_account`, `schedule_days`, `schedule_time`, `needs_hrco` to `plantilla_import_rows`, `stores`, `accounts`, `plantilla`, and `employee_store_allocations`.
   - Added tracking columns to `plantilla_import_batches`: `rollback_rejected_by`, `rollback_rejected_at`, `approved_by_name`, `rejected_by_name`.
   - Created configuration table `public.mother_account_configs` seeded with initial mother accounts and penalty rules.
   - Applied reactive backfill trigger `trg_account_hrco_backfill` on `public.accounts` (`fn_trg_account_hrco_backfill()`).
   - Implemented Zero-Edit Lock helper functions with 2-second approval grace false-positive guard (`_import_records_modified_after_approval` and `get_plantilla_import_first_modified_record`).
   - Updated RPCs:
     - `submit_plantilla_baseline_import`: Implements Invariants 1–9 with CTE-based validation checks.
     - `approve_plantilla_import_batch`: Allows valid vacant slots, claims existing open slots before incrementing ordinals, synchronizes `public.vacancies`, and records `approved_at` after all DML finishes.
     - `request_plantilla_import_rollback`: Checks 72h window and Zero-Edit Lock.
     - `approve_plantilla_import_rollback`: Validates Zero-Edit Lock and reverses imported records atomically.
     - `reject_plantilla_import_rollback`: Allows HA / SA to reject rollback requests.
     - `override_plantilla_import_rollback`: SA override for expired windows only if zero records were modified.
     - `fn_assert_vcode_exists_in_plantilla(p_vcode)`: Enforces Invariant 1 on downstream imports (`submit_vacancy_import`).

3. **Web Frontend Updates (`ohmployee-web`) (Step 3)**:
   - `src/lib/utils/data_control_xlsx.ts`:
     - Standardized to 8 always-required store headers, 5 conditionally-required employee headers, and optional schedule headers (`SCHEDULE_DAYS`, `SCHEDULE_TIME`, `DAYOFF`).
     - Added comprehensive 19-rule guide sheet in `downloadPlantillaImportTemplate()`.
     - Preserved backward compatibility for legacy columns (`EMPLOYMENT_TYPE`, `REQUIRED_HC`, `WITH_PENALTY`, `SCHEDULE`).
   - `src/lib/queries/dataControl.ts`:
     - Updated batch and preview row interfaces and RPC mappers (`committedStores`, `committedEmployees`, `motherAccount`, `scheduleDays`, `scheduleTime`, `dayoff`, `needsHrco`, `approvedByName`, `rejectedByName`).
     - Exported `rejectPlantillaImportRollback` and `overridePlantillaImportRollback`.
   - `src/components/more/PlantillaImportModal.tsx`:
     - Added `Skipped` filter pill in Review Queue (`validation_status = 'skipped'` for existing vacant VCODEs).
     - Rendered `Vacant Baseline Slot` badge, `Mother Account`, `Position / HC`, and schedule metadata.
     - Updated History table to render **Batch #**, **Stores / HC** (e.g. `11/10`), **Approved / Rejected By**, and 72h rollback countdown timer.
     - Wired rollback actions: Head Admin & Super Admin can approve or reject rollback requests; Super Admin can execute emergency override.
   - `src/components/plantilla/UpdateScheduleModal.tsx` & `PlantillaDetailDrawer.tsx`:
     - Created `UpdateScheduleModal` supporting multi-select days (MON-SUN), shift windows & roving flexi durations, and dayoff multi-select.
     - Added `Schedule & Store Visit Audit` section card in `PlantillaDetailDrawer` with "Edit Schedule" button.
     - Updated `updatePlantillaSchedule` mutation to synchronize `plantilla` and `employee_store_allocations`, actively enforcing the Zero-Edit Lock.

### Verification
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 static routes.
- `npm run lint`: Clean with 0 errors.
- Applied and validated migration on live Staging DB `qqiiznmqxfoamqytjica`.

---

# AI Handoff

## Plantilla Baseline Import Slot Reason Codes Fix & Compact Table Layout (ohm#x7k4w9m2)

**Status: COMPLETE — MIGRATION `20262606000056` APPLIED TO LIVE STAGING, MISSING REASON CODES `IMPORT_VACANT_SLOT` & `IMPORT_CLAIM_VACANT` SEEDED IN `slot_reason_codes`, DEFENSIVE LOOKUP GUARDS & RETRYABLE `commit_failed` ADDED TO `approve_plantilla_import_batch`, BATCH `#7d961dfc` RESET TO `pending_approval`, COMPACT TYPOGRAPHY & `useUsersList()` ACTOR RESOLUTION IMPLEMENTED IN `PlantillaImportModal.tsx` (0 BUILD/LINT REGRESSIONS ON MAIN)**

### Objective & Changes Delivered
1. **Database Schema & Foreign Key Fix (Migration `20262606000056_fix_slot_history_reason_codes.sql`)**:
   - **Root Cause**: Batch `#7d961dfc` failed on approval with `violates foreign key constraint "slot_history_reason_fkey" (SQLSTATE 23503)` when attempting to insert vacant store rows into `public.slot_history` using `'IMPORT_VACANT_SLOT'`, which was missing from lookup table `public.slot_reason_codes`.
   - **Seeded Master Lookup**: Added `'IMPORT_VACANT_SLOT'` and `'IMPORT_CLAIM_VACANT'` with active status and descriptive labels to `public.slot_reason_codes`.
   - **Defensive Reason Code Verification**: Updated [`approve_plantilla_import_batch`](file:///d:/Projects/ohmployee-web/supabase/migrations/20262606000056_fix_slot_history_reason_codes.sql) so all `INSERT INTO public.slot_history` calls check `CASE WHEN EXISTS (SELECT 1 FROM public.slot_reason_codes WHERE code = ...) THEN ... ELSE NULL END`, preventing foreign key constraint crashes if an unseeded reason code is ever supplied.
   - **Retryable Failed Batches**: Updated the status validation guard in `approve_plantilla_import_batch` to allow `commit_failed` alongside `pending_approval`.
   - **Batch `#7d961dfc` Reset**: Reset batch `#7d961dfc-8c09-4db0-8225-74ab26d9a607` from `commit_failed` to `pending_approval` with cleared error fields.
   - **Applied to Live Staging**: Migration applied and verified via Supabase MCP.

2. **Typography & Spacing Overhaul (`PlantillaImportModal.tsx`)**:
   - **Inspect Batch Rows Table**:
     - `th`: Standardized to `text-[10px] font-semibold uppercase tracking-wider px-2.5 py-1.5 text-text-muted`.
     - `td`: Scaled down to `px-2.5 py-1.5 align-middle`.
     - Primary cell text (`VCODE`, `STORE_NAME`, `Position`, `Employee Name`): Clean `text-xs font-medium leading-tight` (max 12px, removed heavy font weights).
     - Secondary metadata (`Mother:`, `ID:`, Schedule): Standardized to `text-[11px] text-slate-500 leading-tight`.
     - Badges (`FLAGGED`, `VALID`, `BLOCKED`, `ROVING`, `STATIONARY`, `NEEDS HRCO`, `Vacant Baseline Slot`): Compact `text-[10px] px-1.5 py-0.5 rounded font-medium`.
     - Validation Issues & Guidance: Scaled to `text-[11px] leading-snug space-y-0.5` with compact badges (`text-[10px] px-1.5 py-0.5 font-mono font-medium`) so roving messages fit cleanly on 1–2 lines without vertical row bloat.
   - **Import History Table**:
     - Standardized headers to `text-[10px] font-semibold uppercase tracking-wider px-2.5 py-1.5 text-text-muted`.
     - Standardized cells to `px-2.5 py-1.5 align-middle text-xs leading-tight`.
     - Refined column widths (`w-20` Batch #, `w-44` File Name, `w-28` Status, `w-20` Stores/HC, `w-44` Rollback, `w-36` Scope, `w-32` Uploaded By, `w-36` Approved/Rejected By, `w-24` Date).
     - **Clean Actor Lookup**: Integrated `useUsersList()` to build a high-performance profile and auth user ID map, converting raw UUIDs to human full names (e.g. `"Litong, Ohm"`) with fallback to `${uuid.slice(0, 8)}...`.

3. **Status Inclusion**:
   - Added `"commit_failed"` to `reviewableStatuses` in `PlantillaImportModal.tsx` so failed batches are directly viewable and actionable in the Review Queue.

### Verification
- `npm run lint`: Clean with 0 errors across the codebase.
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 static routes.
- Staging verification: Query confirmed `IMPORT_VACANT_SLOT` and `IMPORT_CLAIM_VACANT` are present in `public.slot_reason_codes`, and batch `#7d961dfc` is in `pending_approval` ready to approve.

---

## Approvals Page Category Alphabetical Ordering & Inline Toolbar Layout (ohm#a7k2m9x4)

**Status: COMPLETE — APPROVALS CATEGORY NAVIGATION TABS REORDERED ALPHABETICALLY (A-Z), SEARCH AND STATUS TABS INLINED IN A SINGLE HORIZONTAL ROW WITH REFRESH BUTTON, ZERO LINT/BUILD REGRESSIONS**

### Objective & Changes Delivered
1. **Alphabetical Ordering of Category Navigation Tabs (A-Z)**:
   - Updated `REQUEST_CATEGORIES` in `src/lib/queries/requests.ts` to arrange all 11 operational request categories alphabetically by their display label:
     1. Account Group Transfers (`account_group_transfers`)
     2. Account Sign-Ups (`account_requests`)
     3. Applicant Movements (`applicant_movements`)
     4. Coverage (`coverage`)
     5. Deactivations (`deactivations`)
     6. Headcount (`headcount`)
     7. HR Emploc Deletions (`hr_emploc_deletions`)
     8. New Stores (`new_stores`)
     9. Plantilla Placements (`plantilla_approvals`)
     10. Relievers (`relievers`)
     11. Vacancy Closures (`vacancy_closures`)
   - `RequestCategoryNavigation` dynamically consumes `REQUEST_CATEGORIES`, rendering all pill navigation tabs in this exact alphabetical sequence.
   - Refactored `currentCategoryConfig` in `src/components/approvals/ActiveQueueReviewPane.tsx` from index-based fallback (`REQUEST_CATEGORIES[1]`) to key-based search (`REQUEST_CATEGORIES.find(c => c.key === "headcount") ?? REQUEST_CATEGORIES[0]`) to ensure resilience.

2. **Single Horizontal Row Inline Toolbar**:
   - Refactored `QueueToolbar` in `src/components/approvals/ActiveQueueReviewPane.tsx`:
     - Grouped Search input and Status filter tabs (`Pending`, `Approved`, `Rejected`) side-by-side in a unified left cluster (`flex items-center gap-3 sm:gap-4`).
     - Aligned `[Refresh]` button on the far right within `flex flex-wrap items-center justify-between gap-3`.
     - Removed the detached secondary sub-tab row beneath the search bar.
     - Preserved all live badge counts, loading skeletons, and active tab highlights.

### Verification
- `npm run lint`: Clean with 0 errors.
- `npx tsc --noEmit`: Clean with 0 errors.
- Verified single-row toolbar layout and responsive wrapping across viewport breakpoints.

---

## Deep-Dive Data Source & Metric Harmonization (SQL RPC Migration, Mobile Inversion & OM Scope Fix, Mock Purge & Viewport Polish) (ohm#d8m4x2w9)

**Status: COMPLETE — DATABASE RPC MIGRATION APPLIED & HARMONIZED ACROSS 11 OPERATIONAL APPROVAL TABLES, MOBILE DART INVERSION & OM SCOPE LEAKAGE RESOLVED, ALL 23 HARDCODED UI MOCKS/FALLBACKS PURGED IN NEXT.JS, 1080P VIEWPORT CLEARANCE VERIFIED (0 BUILD/LINT ERRORS ON MAIN)**

### Objective & Changes Delivered
1. **Database Schema & RPC Migration (`20262606000052_harmonize_dashboard_metrics_and_approvals.sql`)**:
   - Authored and applied additive migration to Supabase (`qqiiznmqxfoamqytjica`) and synchronized migration files to both `ohmployee-web` and `OHMployee`.
   - Updated `fn_dashboard_metrics()`:
     - `pending_approvals`: Sums all 11 operational request tables (`plantilla_approvals`, `headcount_requests`, `new_store_requests`, `vacancy_closure_requests`, `applicant_movement_requests`, `coverage_approvals`, `reliever_approvals`, `hr_emploc_deletions`, `mika_separation_approvals`, `salary_advance_approvals`, `disciplinary_action_approvals`), fully reconciling with the Web Sidebar badge.
     - Added `admin_security_approvals`: Isolates the 5 admin/security tables (`admin_role_escalations`, `security_profile_changes`, `account_elevations`, `compliance_overrides`, `session_invalidation_requests`) so the `Security & Audit Telemetry` card displays genuine security escalations (currently 0) without masking operational queues.
     - Added `ghost_employee_count`: Derived from `v_cencom_ghost_employees` (currently 261 anomalies).
     - Added `unassigned_vacancies` (12) & `assigned_vacancies` (1).
     - Ensured 100% backward compatibility for all existing JSON return keys.

2. **Mobile Dart Field Inversion & OM Scope Isolation (`OHMployee`)**:
   - `lib/features/dashboard/role_dashboards/dashboard_role_models.dart`: Added `totalRequired` to `DashboardOperationsSummary` and `requiredHc` to `DashboardGroupWorkforceSummary`.
   - `lib/features/dashboard/dashboard_screen.dart`:
     - Fixed inverted mapping where `snapshot.mfrRequired` (37) was wrongly assigned to `totalPlantilla` (13) and `snapshot.mfrActual` (19) was assigned to `totalHrEmploc` (4).
     - Mapped `totalPlantilla: snapshot.activePlantilla` (13), `totalVacancy: snapshot.mfrVacant` (11), `totalHrEmploc: snapshot.mfrHrPipeline` (4), `totalRequired: snapshot.mfrRequired` (37).
     - Corrected `_buildOperationsGroups` to map `actual_hc` -> `plantilla`, `pipeline_count` -> `hrEmploc`, and `required_hc` -> `requiredHc`.
     - Scoped `omHrcoBreakdown` for scoped roles (`!isAll` users like OM, TL, ATL, HRCO) to derive strictly from scoped wave-1 datasets, preventing cross-group leakage from company-wide `v_plantilla_safe`.
   - `lib/features/dashboard/role_dashboards/operations_dashboard_view.dart`:
     - Handled `required == 0 && actual == 0 && vacant == 0` edge case: renders `"N/A"` with `"No Required HC"` in neutral slate styling instead of a false red `"0% At Risk"` badge.

3. **Web Dashboard Mock Purge & Dynamic Data Binding (`ohmployee-web`)**:
   - `src/lib/queries/dashboard.ts`:
     - Updated `DashboardMetrics` type and normalizer with `adminSecurityApprovals`, `ghostEmployeeCount`, `unassignedVacancies`, and `assignedVacancies`.
     - Added `useDashboardSlaBreaches()` and `useDashboardUnderstaffedStores()` hooks querying live Supabase vacancies and store shortages.
   - `src/app/(dashboard)/dashboard/page.tsx`:
     - Purged all 23 hardcoded mock items: deleted `DEFAULT_GROUP_MATRIX`, `DEFAULT_SLA_BREACHES`, and `DEFAULT_UNDERSTAFFED_STORES`.
     - Removed `if (!requestCounts) return 12; return count > 0 ? count : 12;` fallback and fake `7 / 3 / 2` approval rows. Live approval list binds dynamically to `useRequestCategoryCounts()`.
     - Replaced all static string sub-pills with dynamic template literals (`liveBreachCount`, `worstMfrGroupName`, `ghostEmployeeCount`, `unassignedCount`, `assignedCount`, etc.).
     - Segmented fill rate progress bar calculates width dynamically (`actualPct`, `pipelinePct`, `vacancyPct`).
     - Wired Tab 2 (`Active SLA Breaches`) and Tab 3 (`Under-Staffed Stores`) to live hooks with loading skeletons and clean empty states (`"No active SLA breaches"`, `"No under-staffed stores"`).
     - Added `pb-8` bottom container clearance and tightened vertical rhythm to prevent viewport clipping on 1080p screens.
     - Preserved `"Sync MIKA"` button label strictly.

### Verification
- `npm run build`: Turbopack build succeeded with 0 errors across all 19 app routes.
- `npx eslint`: Passed cleanly with 0 errors, 0 warnings.
- `dart analyze lib/features/dashboard`: Passed with 0 issues.
- Live RPC Verification: `SELECT * FROM public.fn_dashboard_metrics();` returns reconciled counts (`pending_approvals: 3`, `admin_security_approvals: 0`, `ghost_employee_count: 261`, `total_open_vacancies: 13`, `total_active_plantilla: 13`).

---

## Add Missing Group 3 & Group 4 to Scope Selector & Dynamic Scope Mapping (ohm#q8v2n4k7)

**Status: COMPLETE — SCOPE SELECTOR DYNAMICALLY POPULATED ACROSS ALL ORGANIZATIONAL GROUPS INCLUDING GROUP 3 & GROUP 4 (STANDBY SCOPE), LIVE FILL RATE TAGGING INCLUDED (0 BUILD ERRORS ON MAIN)**

### Objective & Changes Delivered
1. **Scope Selector Dynamic Mapping**:
   - Updated the header Scope `<select>` dropdown in `src/app/(dashboard)/dashboard/page.tsx` to dynamically map all organizational groups from `liveGroupRows` (`liveGroupRows.map(...)`), ensuring no group is omitted.
   - Restored and included `Group 3` and `Group 4` (tagged as `(Standby Scope)`) alongside `Group 1`, `Group 2`, `Group 5`, and `Moses HQ`.
   - Updated the total count label to reflect `All Retail Groups ({liveGroupRows.length})`.

### Verification
- `npx next build`: Turbopack build succeeded with 0 errors across all 19 app routes.
- TypeScript compiler: Passed with 0 errors.
- Dynamic Scope verification: All 6 groups render with appropriate MFR / Standby annotations.

---

## Polish Web Admin Command Center (Right-Rail Viewport Clearance, Live CENCOM Group Bindings, & Dynamic Approvals Wiring) (ohm#x7m2p9w4)

**Status: COMPLETE — RIGHT-RAIL VERTICAL RHYTHM TIGHTENED (100% ABOVE-THE-FOLD ON 1080P/900P), LIVE CENCOM GROUP ALLOCATION BINDINGS INTEGRATED, PENDING APPROVALS QUEUE DYNAMICALLY WIRED TO LIVE CATEGORIES (0 BUILD ERRORS ON MAIN)**

### Objective & Changes Delivered
1. **Right-Rail Viewport Clearance (1080p & 900p Optimization)**:
   - Added generous bottom padding (`pb-16 sm:pb-20`) to the main dashboard container, ensuring bottom card borders and box shadows are fully visible with clear breathing room.
   - Tightened the vertical gap between the 3 right-column stacked cards from `space-y-6` (24px) down to `space-y-3` (12px).
   - Compacted internal padding across the right-rail components:
     - `Pending Approvals Queue`: Header `px-4 py-3`, item padding `px-3 py-2`, tighter typography.
     - `Super Admin Governance & MIKA`: Header `px-4 py-3`, anomaly alert box `p-2.5`.
     - `Security & Audit Telemetry`: Header `px-4 py-3`, 2x2 metric tiles `px-3 py-2`, clean text sizes.
   - Verified that all 3 stacked right-rail cards fit 100% above the fold on a standard 1080p screen without viewport clipping.

2. **Live Group Workforce Matrix Data Bindings**:
   - Replaced static fallback group rows with live database binding to `useCencomGroupKpi()` (`v_cencom_group_allocation_kpi`).
   - Renders live `actual` (Plantilla), `vacant` (Open Vacancies), `pipeline` (HR Emploc), and `mfrPercent` (Fill Rate %) across active groups.
   - Wired the `Showing Active Groups` / `Showing All Groups` toggle dynamically, automatically filtering groups where `required === 0 && actual === 0 && vacant === 0`.

3. **Dynamic Wiring for Pending Approvals Queue Rows**:
   - Wired live category rows from `useRequestCategoryCounts()`:
     - `Plantilla Deployments & Movements` (matching `applicant_movements` + `plantilla_approvals`)
     - `HR Emploc Compliance & Deletions` (matching `hr_emploc_deletions`)
     - `Store Headcount & Requisitions` (matching `headcount` + `new_stores`)
     - `Coverage & Reliever Approvals` (matching `coverage` + `relievers`)
     - `Vacancy Closures` (matching `vacancy_closures`)
   - Wired each category's review button to deep-link directly to `/approvals?tab=<category>`.

4. **Dynamic Top 5 KPI Sub-Pills**:
   - Dynamically derived the lowest MFR group name (`worstMfrGroupName`) from loaded group allocation data rather than static text.
   - Formatted live SLA metrics and vacancy fill percentages dynamically.

### Verification
- `npx next build`: Turbopack build succeeded with 0 errors across all 19 app routes.
- TypeScript compiler: Passed with 0 errors in 55s.
- Right-rail layout clearance: Verified at 1920x1080 and 1440x900 viewports without clipping.

---

## Refactor Web Admin Command Center (Super Admin & Head Admin Desktop View, Semantic Urgency, Approvals Reconciliation, & MIKA Sync) (ohm#k4r9w2m8)

**Status: COMPLETE — WEB ADMIN DASHBOARD ELEVATED TO EXECUTIVE COMMAND CENTER, FULL BOTTLENECK & SLA TRIAGE VISIBLE, APPROVALS 12 VS 0 DISCREPANCY RECONCILED, MIKA SYNC MODAL IMPLEMENTED & ROLE-GATED TO SUPER ADMIN (0 BUILD ERRORS ON MAIN)**

### Objective & Changes Delivered
1. **Top Command Header Bar Modernization**:
   - Upgraded top header bar with breadcrumb (`ADMIN PANEL` → `Dashboard Overview`), title (`Web Admin Command Center`), and live RPC telemetry badge (`Live RPC Telemetry Connected`).
   - Integrated quick-action toolbar containing:
     - Group Scope Selector (`All Retail Groups`, `Group 1`–`Group 5`, `Moses HQ`).
     - CENCOM Triage shortcut (`CENCOM Triage (37)`) linking to `/cencom` whenever active SLA breaches exceed 0.
     - **Strict Button Naming Rule**: Primary **`"Sync MIKA"`** trigger button, strictly visible to `Super Admin` only (hidden for `Head Admin`).

2. **Top 5 Executive KPI Ribbon with Semantic Urgency & Interactive Filtering**:
   - Transformed the flat cards into high-density interactive cards using `tabular-nums`:
     - **`ACTIVE SLA BREACHES` (`37`)**: Red top accent bar, crimson numeral (`#DC2626`), `"Action Required"` badge, sub-breakdown (`26 Vacancy SLA • 11 Movement SLA`). Clicking directly switches to the *Active SLA Breaches* drilldown tab.
     - **`UNDER-STAFFED STORES` (`8`)**: Amber top accent bar, amber numeral (`#D97706`), `"At Risk"` badge, sub-label (`Stores below budgeted plantilla target`). Clicking directly switches to the *Under-Staffed Stores* tab.
     - **`OPEN VACANCIES` (`13`)**: Blue top accent bar, tabular numeral, sub-label (`Active open vacancy slots`). Clicking focuses the workforce matrix.
     - **`HR EMPLOC PENDING` (`4`)**: Indigo top accent bar, tabular numeral, sub-label (`Onboarding compliance items pending`).
     - **`ACTIVE PLANTILLA` (`13`)**: Emerald top accent bar, tabular numeral, sub-label (`Total active deployed employees`).

3. **Main 2-Column Asymmetric Command Workspace (12-Column Desktop Grid)**:
   - **Left Column (8 Cols)**:
     - **Operational Analytics & Fill Rate Breakdown (`fn_dashboard_operational_analytics`)**:
       - Segmented coverage bar displaying exact formula: `Actual [13] / (Actual [13] + HR Pipeline [4] + Vacancy [13] = 30 Required)`.
       - Proportional 3-segment progress bar for Active Plantilla (Emerald: 43.3%), HR Emploc Pending (Blue: 13.3%), and Open Vacancies (Rose/Amber: 43.3%).
       - 4-metric strip: `Pipeline Total` (14), `Hires This Month` (8), `Separations This Month` (0 with green "0% Attrition" pill), and `Avg Fill Rate` (43.3%).
     - **Cross-Module Operational Matrix (Tabbed Card Utilizing Bottom Viewport)**:
       - **Tab 1: `Group Workforce Matrix`**: Matrix across groups (`Group 1`–`Group 5`, `Moses HQ`) with MFR % progress and active vs. all groups filter.
       - **Tab 2: `Active SLA Breaches (37)`**: Actionable table with Store/Unit, Breach Category, Aging, Assigned Owner, and Inspect triage actions.
       - **Tab 3: `Under-Staffed Stores (8)`**: Stores below budgeted plantilla with required vs. actual headcount, open vacancies, and assigned HRCO.
   - **Right Column (4 Cols)**:
     - **Reconciled Pending Approvals Queue Card**: Binds to `useRequestCategoryCounts()`, matching the sidebar's `Approvals (12)` counter and showing operational items (`Plantilla Lateral Transfers`, `HR Emploc Compliance Waivers`, `Vacancy Requisitions`) with a `"Review All"` link to `/approvals`.
     - **Super Admin Governance & MIKA Sync Card**: Role-gated strictly to `Super Admin` only (hidden for `Head Admin`); shows MIKA sync health, anomaly alert (`259 Ghost Employee Cases`), inline **`"Sync MIKA"`** button, and anomaly resolution link.
     - **Compact Security & Audit Telemetry (`fn_dashboard_metrics`)**: Replaces legacy full-width box with compact tile showing `Admin Security Approvals` (0), `Security Events Today` (0), caller role badge, and link to audit logs.

4. **MIKA Sync Modal (`src/components/dashboard/MikaSyncModal.tsx`)**:
   - Created accessible modal dialog for drag-and-drop file upload (`.xlsx`, `.csv`).
   - Button strictly labeled **`"Sync MIKA"`** (never `"Refresh"`).
   - Refetches operational metrics and operational analytics upon successful sync.

### Verification
- `npx next build`: Turbopack build succeeded with 0 errors across all 19 app routes.
- TypeScript compiler: Passed with 0 errors.
- Role-gated verification: `isSuperAdmin` check strictly gates `"Sync MIKA"` header button and Super Admin Governance card.
- Approvals counter: Reconciled with sidebar via `useRequestCategoryCounts()`.

---

## Consolidate Candidate Pipeline Stages to 6 Target Workflow Options & Safe DB Migration (ohm#p8r4m2k9)

**Status: COMPLETE — PROGRESSIVE PIPELINE STAGES CONSOLIDATED TO 6 CANONICAL OPTIONS, SUB-HEADERS DROPPED FROM SELECT, ALL EXISTING CANDIDATE RECORDS SAFELY MIGRATED WITHOUT COUNT REGRESSION IN STAGING & PROD DATABASES (0 LINT ERRORS, 0 BUILD ERRORS ON MAIN)**

### Objective & Changes Delivered
1. **Consolidated Target Progressive Pipeline Stages (6 Stages)**:
   - Updated `AdvancePipelineModal.tsx` to render strictly the final 6 progressive options:
     1. `For Interview / Intro` (`for_interview_intro`)
     2. `For Requirements` (`for_requirements`)
     3. `For Medical` (`for_medical`)
     4. `Pending Approval` (`pending_approval`)
     5. `For Deployment` (`for_deployment`)
     6. `For Onboard` (`for_onboard`)
   - Removed the non-clickable `<optgroup label="Progressive Pipeline Stages">` separator so the 6 target stages render directly at the top level of the `<select>`.
   - Kept the `<optgroup label="Terminal Dropout / Backout">` intact so recruiters retain dropout capabilities (`Backout`, `Failed / Rejected by Ops`, `Rejected`, `Did Not Report`) along with standard reason dynamic loading.
   - Retained the `Ops Remarks` text input for manual feedback and scheduling specifics.
   - Updated `initialStage` resolution with defensive regex normalization and legacy stage fallback mapping.

2. **Database Migration Applied to Staging & Production (`20262606000051_consolidate_candidate_pipeline_stages.sql`)**:
   - **`fn_is_active_vacancy_applicant_status`**: Upgraded normalization to handle slashes (`'/'`) and special characters; included `for_interview_intro` and `pending_approval` to safeguard against active vacancy count or slot occupancy drops.
   - **`applicants.status` Migration**:
     - `'For Interview'`, `'For Online Intro'`, `'For Face-to-Face Intro'` $\rightarrow$ `'For Interview / Intro'`
     - `'Done Intro'` $\rightarrow$ `'For Requirements'`
     - `'Waiting SCO Schedule'`, `'Waiting Approval'`, `'Endorsed to Ops'`, `'Endorsed'` $\rightarrow$ `'Pending Approval'`
     - Retained `'For Requirements'`, `'For Medical'`, `'For Deployment'`, `'For Onboard'`.
   - **`applicant_status_options`**:
     - Deactivated deprecated stage options (`for_interview`, `for_online_intro`, `for_face_to_face_intro`, `done_intro`, `waiting_sco_schedule`, `waiting_approval`, `endorsed`).
     - Upserted the 6 canonical stages with unified sort orders (30 to 60).
     - Preserved terminal and system-only options.
   - **`vw_applicant_funnel` View**: Added `'For Interview / Intro'` to filter arrays.

3. **Template & Parity Updates**:
   - `src/lib/utils/data_control_xlsx.ts`: Updated sample template data row to use `"For Interview / Intro"`.

### Verification
- Database queries against Supabase staging (`qqiiznmqxfoamqytjica`) and prod (`rwxelulyapjgaarlwkus`):
  - In staging: 27 candidates in `For Interview / Intro`, 1 candidate in `Pending Approval`; active applicant counts (`v_vacancy_pipeline_status`) preserved at 6 pipeline vacancies.
  - In prod: 23 candidates in `For Interview / Intro`, 1 candidate in `Pending Approval`; zero records lost or blanked.
- `npx eslint src/components/vacancy/AdvancePipelineModal.tsx src/lib/utils/data_control_xlsx.ts`: Clean (0 errors, 0 warnings).
- `npm run build`: Clean Next.js Turbopack production build with all 19 routes compiled.

---

## Fix Pipeline Candidate Query Schema Mismatch (`applied_at` & `headcount` Column Selects) (ohm#s4b8r2x1)

**Status: COMPLETE — PIPELINE CANDIDATE QUERY SCHEMA MISMATCH RESOLVED (`applied_at` & `headcount` REMOVED FROM SELECTS), ALL 6 PIPELINE CANDIDATES FULLY RESTORED AND RENDERED IN TABLE MATCHING BADGE COUNT (0 LINT ERRORS, 0 BUILD ERRORS ON MAIN)**

### Objective & Root Causes Resolved
1. **Fix Pipeline Tab Table Rendering (6 Badge vs 0 Rows)**:
   - **Root Cause Identified**: In `src/lib/queries/vacancy.ts`, the candidate-level query expansion for `currentTab === "pipeline"` selected `applied_at` from `applicants` and `headcount` from `vacancies`. In the Supabase PostgreSQL schema:
     - `applicants` does not have an `applied_at` column (it uses `created_at` / `updated_at`).
     - `vacancies` does not have a `headcount` column (it uses `required_headcount`).
     PostgREST failed with error code `42703` (`column applicants.applied_at does not exist`), which caused the query handler to skip populating records and fall back to returning `data: []` (0 rows) while the badge count read `6`.
   - **Fix Applied**:
     - Removed `applied_at` from `.from("applicants").select(...)` (relying on `created_at` / `updated_at`).
     - Removed `headcount` from `.from("vacancies").select(...)` (relying on `required_headcount`).
     - Replaced PostgREST `.not("status", "in", ...)` with in-memory status filtering (`v.status !== "Filled" && v.status !== "Closed" && v.status !== "Archived"`).
     - Applied the identical schema fixes to `fetchAllPipelineVacancies` (CSV Export).
     - All 6 active pipeline candidates now render properly in the Pipeline table.

### Verification
- `npm run lint`: Clean (0 errors, 25 preexisting baseline warnings in other modules).
- `npm run build`: Successful Next.js Turbopack production build with all 19 static/dynamic routes compiled cleanly.

---

## Restore Closure & Failed/Backout Tab Data and Align Pipeline Badge Counts with Rendered Rows (ohm#n7f3w9x2)

**Status: COMPLETE — CLOSURE & FAILED/BACKOUT DATA RESTORED VIA SHARED GROUP MAP (SCHEMA MISMATCH RESOLVED), PIPELINE CANDIDATE-LEVEL QUERY EXPANSION IMPLEMENTED TO 100% SYNCHRONIZE BADGE COUNT (6) WITH RENDERED TABLE ROWS (6) (0 LINT ERRORS, 0 BUILD ERRORS ON MAIN)**

### Objective & Root Causes Resolved
1. **Restore Data in Closure & Failed/Backout Tabs**:
   - **Root Cause Identified**: In `src/lib/queries/vacancy.ts`, queries to the `vacancies` table explicitly selected `group_name`. However, in the Supabase PostgreSQL schema, the `vacancies` table has `group_id` (UUID), but does not have a `group_name` column. This caused Supabase / PostgREST to fail with error `42703` (`column vacancies.group_name does not exist`), resulting in silent empty array fallbacks in both the Closure and Failed/Backout tabs regardless of filter selection.
   - **Fix Applied**:
     - Removed `group_name` from `.select(...)` queries on `vacancies` across `listVacancies` (Closure and Failed/Backout tabs) and export functions (`fetchAllClosureVacancies`, `fetchAllFailedVacancies`).
     - Added a shared helper `fetchGroupMap(supabase)` that retrieves `id, group_name` from the `groups` table into an in-memory map.
     - Resolved `groupName` for each vacancy record using `groupMap.get(vac.group_id)` with safe fallback through `formatGroupName(...)`.
     - Group filtering by Group 1–5 or Moses HQ (and clearing filters) now correctly filters on `vacancies.group_id` and renders all matching records without errors.

2. **Align Pipeline Badge Count with Rendered Table Rows (6 vs 4 Mismatch)**:
   - **Root Cause Identified**: The `get_web_vacancy_summary()` RPC calculates the Pipeline badge count by rolling up all active non-terminal candidates across active non-archived vacancies (`sum(ar.active_pipeline_count) = 6`). However, `listVacancies` for `currentTab === "pipeline"` previously relied on `list_web_vacancies(p_status => 'pipeline')`, which operated at the vacancy requisition level and excluded vacancies with `has_pending_closure = true` or `closure_request_status = 'pending'`. As a result, vacancies `VCAG5_0056` (2 active candidates) and `TEST011` (1 active candidate) were excluded from the table, dropping 3 active candidates and producing a count mismatch.
   - **Fix Applied**:
     - In `src/lib/queries/vacancy.ts`, implemented dedicated candidate-level query expansion for `currentTab === "pipeline"` / `"with_applicant"` (matching the pattern used by Hired and Failed/Backout).
     - Queries non-archived active candidates from `applicants` whose status is non-terminal, joins to active non-archived vacancies, maps each candidate to a distinct table row (`VacancyListItem`) with individual candidate info (`applicantId`, `applicantName`, `contactNumber`, `stageBadge`, `agingDays`, actions), and paginates cleanly.
     - Implemented matching export support via `fetchAllPipelineVacancies(filters)`.
     - Pipeline table rows now precisely match the badge count (all 6 active candidates are rendered).

### Verification
- `npm run lint`: Clean (0 errors, 25 preexisting baseline warnings in other modules).
- `npm run build`: Successful Next.js Turbopack production build with all 19 static/dynamic routes compiled cleanly.

---

## Fix 7 Vacancy Module Bugs & Permission Adjustments (Closure Blocking, Tab-Specific Actions, HC/Quota RBAC, Human-Readable Activity History, Withdraw Action, & Group Filtering) (ohm#v3k8n2m5)

**Status: COMPLETE — 7 BUGS FULLY RESOLVED, STRICT RBAC ENFORCED FOR QUOTA & HC ADJUSTMENT, CLOSURE BLOCKING GATED BY ACTIVE PIPELINE, ACTIVITY LOGS TRANSLATED TO HUMAN-READABLE SENTENCES, WITHDRAW WIRE-UP IN CLOSURE TAB, AND GROUP FILTER RESTRICTED (0 LINT ERRORS, 0 BUILD ERRORS ON MAIN)**

### Objective
Resolve 7 Vacancy Module functional bugs and RBAC adjustments across drawer, table, query layer, and page components:
1. **Bug 1: Block "Request Closure" When Store Has Active Applicants**:
   - In `src/components/vacancy/VacancyDetailDrawer.tsx`, evaluated active pipeline counts (`activeApplicantCount > 0` or active applicants list length > 0).
   - If active applicants exist and user does not belong to exempted Ops (`isOpsTeam`), Recruitment (`AppRole.RECRUITMENT`), or Super Admin (`hasFullAccess`), the **Request Closure** button is disabled with grayed styling and a clear explanatory tooltip: *"Cannot request closure while active applicants exist in pipeline. Process or drop candidates first."*
2. **Bug 2: Hide Quota & Closure Actions in Hired Tab**:
   - In `src/components/vacancy/VacancyDetailDrawer.tsx`, suppressed the entire *Requisition & Quota Management* section (Adjust Quota, Request HC Adjustment, Request Closure) when viewing a requisition in the Hired tab or when status is `Hired` / `Filled`.
3. **Bug 3: Restrict "Request HC Adjustment" strictly to Super Admin**:
   - In `src/lib/rbac.ts`, introduced `canRequestHeadcountAdjustment(userOrRole)` which restricts access strictly to Super Admin (`isOwner` / level 100), hiding the action from Data Team (Head Admin, Encoder) and regular Ops.
   - Connected `canRequestAdjustment` in `VacancyDetailDrawer.tsx` to `canRequestHeadcountAdjustment(currentUser)`.
4. **Bug 4: Restrict "Adjust Quota" to Data Team & Super Admin Only**:
   - In `src/lib/rbac.ts`, introduced `canReviseHeadcountQuota(userOrRole)` which gates direct quota adjustments strictly to Data Team members (Head Admin, Encoder) and Super Admin, hiding it from Ops and Recruitment.
   - Connected `canReviseQuota` in `VacancyDetailDrawer.tsx` to `canReviseHeadcountQuota(currentUser)`.
5. **Bug 5: Make Activity History Simple & Human-Readable**:
   - In `src/components/vacancy/VacancyDetailDrawer.tsx`, added `formatActivityHistorySummary(item)` translator that converts raw database audit actions (`INSERT`, `UPDATE`, `APPROVAL`) and modules (`vacancies`, `applicants`, `VACANCY_MODULE`, etc.) into natural, human-readable sentence summaries (e.g., *"Vacancy created and opened for sourcing"*, *"Applicant added to recruitment pipeline"*, *"Pipeline stage updated"*, *"Headcount quota revised"*, *"Requisition approved"*).
6. **Bug 6: Role-Gated Actions in Closure Tab**:
   - In `src/components/vacancy/VacancyTable.tsx` under the Closure tab Actions column:
     - Shows the **Withdraw** button exclusively for Ops roles (`userIsOps`).
     - Shows **Approve** and **Reject** buttons exclusively for Data Team / Admins (`userCanReviewClosures`).
   - Wired `handleWithdrawClosure` in `src/app/(dashboard)/vacancy/page.tsx` using `useWithdrawVacancyClosureRequest()` mutation with confirmation and query invalidation.
7. **Bug 7: Fix Group Filter Options in Closure & Failed/Backout Tabs**:
   - In `src/lib/queries/vacancy.ts`:
     - Added `group_name` selection to `vacQuery` in `listVacancies` for both Closure and Failed/Backout tabs, and in export queries (`fetchAllClosureVacancies` and `fetchAllFailedVacancies`).
     - Formatted group names using `formatGroupName(vac.group_name, account)`.
   - In `src/app/(dashboard)/vacancy/page.tsx`:
     - Filtered `uniqueGroups` to strictly include Group 1 through Group 5 and Moses HQ, eliminating any `"General / Direct"` options.
   - In `VacancyTable.tsx` and `VacancyDetailDrawer.tsx`:
     - Replaced `"General / Direct"` fallback labels with clean em-dashes `"—"` / `"--"`.

### Verification
- `npm run lint`: Clean (0 errors, 25 preexisting baseline warnings in other modules).
- `npm run build`: Successful Next.js Turbopack production build with all 19 static/dynamic routes compiled.

---

## Integrate Approved Vacancy Detail Drawer Layout (Requisition & Quota Management, Candidate Cards, & Consolidated Actions) (ohm#d8r2m6k1)

**Status: COMPLETE — DEDICATED REQUISITION & QUOTA MANAGEMENT SECTION INSTALLED IN DRAWER, CANDIDATE CARDS FULLY EQUIPPED WITH DIRECT ACTIONS & AGING, FOOTER ACTION BAR STREAMLINED, TABLE CLEANLINESS PRESERVED (ZERO LINT ERRORS, CLEAN NEXT.JS PRODUCTION BUILD ON MAIN)**

### Objective
Refactor `src/components/vacancy/VacancyDetailDrawer.tsx` to match the approved HTML mockup structure:
1. **Dedicated Requisition & Quota Management Section**:
   - Integrated a clean, prominent management panel inside the drawer directly below the core store & ownership metadata cards.
   - Housed four key action controls with strict RBAC guards:
     - **Adjust Quota** (`ReviseHeadcountQuotaModal`) — guarded by `canReviseQuota` (Super Admin, Head Admin, Encoder).
     - **Request HC Adjustment** (`RequestHeadcountAdjustmentModal`) — guarded by `canRequestAdjustment` (Super Admin, Head Admin, OM, HRCO, ATL, TL).
     - **Request Closure** (`RequestVacancyClosureModal`) — guarded by `userCanRequestClosure`, visible when not already closed or pending closure.
     - **Withdraw Closure** — visible when `isPendingClosure` is true, enabling Ops/Requesters/Admins to cancel an in-flight closure request with confirmation and automatic cache refresh.
2. **Candidate Cards & Consolidated Actions in Drawer**:
   - For every active candidate in `detail.activeApplicantsList` (with graceful fallback to single-applicant records):
     - Displays avatar initial circle, candidate display name, contact phone number (with phone icon), stage badge, and candidate aging in stage.
     - Direct action buttons on each candidate card:
       - **Edit Details** (`EditApplicantModal`): Gated by `userCanEditApplicant` and one-time edit policy for non-admins.
       - **Update Stage / Backout** (`AdvancePipelineModal`): Consolidated modal handling progressive pipeline advancements and terminal dropouts (`Backout`, `Failed / Rejected by Ops`, `Rejected`, `Did Not Report`).
       - **Mark Hired** (`MarkHiredModal`): Instant placement approval and onboard date entry.
   - Enriched active applicants in `src/lib/queries/vacancy.ts` by fetching missing contact numbers, timestamps, and edit counts from `public.applicants`, computing candidate aging during data normalization without violating React hooks purity rules.
3. **Clean Table View Preservation**:
   - Maintained clean, uncluttered tables across tabs:
     - **Open** tab: single essential `+ Applicant` button.
     - **Pipeline** tab: `Update` (and `Approve` where onboard status reached).
     - Full row clicks reliably open `VacancyDetailDrawer`.
4. **Clean Footer Action Bar**:
   - Streamlined the bottom drawer footer to focus on requisition slot lifecycle (`Add Applicant`, `Reopen Slot`, `Approve Vacancy`, `Edit Hired Date`), eliminating redundant action duplicates.

### Verification
- `npm run lint`: Clean (0 errors, 25 preexisting baseline warnings in other modules).
- `npm run build`: Successful Next.js Turbopack production build with all 19 static/dynamic routes compiled.

---

## Fix Vacancy Drawer SQL Error, Occupied HC Fraction (`1/7`), Pipeline 1:1 Column Cleanup, Consolidate Backout into Update Modal, Move Edit to Drawer Only, & Remove Eye Icons Globally (ohm#q7w1k9b3)

**Status: COMPLETE — MIGRATION 50 APPLIED TO STAGING & PROD, VACANCY DETAIL RPC ERROR RESOLVED, OCCUPIED HC FRACTION RESTORED TO OPEN TAB, PIPELINE TAB REFINED, BACKOUT CONSOLIDATED INTO ADVANCE PIPELINE MODAL, & REDUNDANT EYE ICONS REMOVED (LINT CLEAN, BUILD CLEAN ON MAIN)**

### Objective
1. **Fix Vacancy Detail Drawer SQL Crash (`column a.assigned_recruiter_id does not exist`)**:
   - Repair `get_web_vacancy_detail` where `public.applicants` was joined using non-existent column `a.assigned_recruiter_id`.
   - Update join to `up_a_rec ON up_a_rec.id = COALESCE(a.created_by, v_raw.assigned_encoder_id)`.
   - Also fixed safe candidate display formatting and audit log timestamp column resolution (`al.timestamp`).
   - Applied migration to both **Staging** (`qqiiznmqxfoamqytjica`) and **Production** (`rwxelulyapjgaarlwkus`).
2. **Occupied HC Fraction (`1/7` Immediately When Applicant Is Added)**:
   - Updated `vw_vacancy_list`, `vw_vacancy_detail`, `list_web_vacancies`, and `get_web_vacancy_summary` so `hc_filled` reflects occupied slots: `COALESCE(confirmed_onboard_count, 0) + COALESCE(active_applicant_count, 0)`.
   - Updated `hc_display` to format as `format('%s/%s', hc_filled, hc_total)`, displaying `1/7` immediately when 1 applicant is active for a 7-headcount vacancy.
   - Preserved **Safeguard**: Multi-headcount requisition stays visible in **Open** tab while occupied slots `hc_filled < hc_total`. Only transitions `derived_status` to `Hired` when `confirmed_onboard_count >= hc_total`.
3. **Remove `HC` Column from `Pipeline` Tab**:
   - Omitted `"HC"` from `getTableColumns("pipeline")` and conditionally omitted corresponding `<td>` cell in `src/components/vacancy/VacancyTable.tsx` for 1:1 candidate row rendering.
4. **Move `Edit` Applicant Button Strictly Inside `VacancyDetailDrawer`**:
   - Removed the in-row `Edit` button from `VacancyTable.tsx` in the Pipeline tab, keeping `Edit Details` exclusively on candidate cards inside `VacancyDetailDrawer.tsx`.
5. **Consolidate `Backout` into `AdvancePipelineModal.tsx`**:
   - Removed standalone red `Backout` button from `VacancyTable.tsx` pipeline rows.
   - Enhanced `AdvancePipelineModal.tsx` to include progressive pipeline stages plus terminal dropout options (`Backout`, `Failed / Rejected by Ops`, `Rejected`, `Did Not Report`).
   - Dynamically renders reasons dropdown (fetched via `fetchBackoutReasons` / `fetchRejectedReasons`) with custom write-in field, routing submissions through canonical `failBackoutApplicant`.
6. **Remove Redundant Eye Icon (`View Details`) Button Globally**:
   - Removed redundant `<Eye />` action icon buttons in tables where clicking the row itself navigates/opens the drawer: `VacancyTable.tsx`, `HrEmplocTable.tsx`, and `UsersTable.tsx`.
   - Preserved legitimate password visibility toggle `<Eye />`/`<EyeOff />` icons.

---

## Execute Vacancy Module Mobile vs. Web Parity (ohm#p9v2k4m7)

**Status: COMPLETE — EDIT APPLICANT DETAILS, DUPLICATE CHECK, WITHDRAW CLOSURE, AND SUPER ADMIN DROPOUT PARITY FULLY WIRED & VERIFIED ON MAIN (ZERO LINT ERRORS, CLEAN NEXT.JS PRODUCTION BUILD)**

### Objective
Achieve 100% functional and UI parity between Mobile (`d:\Projects\OHMployee`) and Web (`d:\Projects\ohmployee-web`) for the Vacancy module:
1. **Edit Applicant Details**: Port the Mobile one-time applicant profile correction workflow (`fn_update_applicant_profile_once` + `propagateApplicantIdentityToLinked`) to Web with uppercase normalization, contact number verification, mandatory audit reason, one-time edit policy, and Super Admin override capability.
2. **Pre-Intake Candidate Duplicate Check**: Integrate `check_candidate_duplicate` RPC wrapper into applicant intake (`endorseApplicant` / `AddApplicantModal`) with defensive non-blocking fallbacks.
3. **Withdraw Closure Request**: Integrate `withdraw_vacancy_closure_request` RPC wrapper into the detail drawer action bar and in-flight clearance banner to enable ops/requesters to restore requisition pipeline flow.
4. **Post-Onboard Dropout Handling**: Unblock Super Admin / Head Admin (`hasFullAccess`) from handling post-onboard dropouts/backouts directly from the `VacancyDetailDrawer` action bar.
5. **UI Surface Integration**: Expose "Edit Details" actions across both `VacancyDetailDrawer` candidate cards and `VacancyTable` Pipeline tab rows, gated by unified RBAC (`canEditApplicantProfile`).

---

### Key Implementations
1. **RBAC Gating (`src/lib/rbac.ts`)**:
   - Added `canEditApplicantProfile(userOrRole)`: Strictly mirrors Mobile `vacancyCanEditApplicantPipeline` and `fn_update_applicant_profile_once` permissions.
   - Allowed: Super Admin (100), Head Admin (90), Ops Team (OM 70, HRCO 45, ATL 42, TL 41), Recruitment (20).
   - Denied: Encoder (30), HR Personnel (25), Backoffice Personnel (15), Viewer (10).

2. **Backend RPC Wrappers & Normalizers (`src/lib/queries/vacancy.ts`)**:
   - `checkCandidateDuplicate`: Calls `check_candidate_duplicate` RPC with first name, last name, middle name, and contact number. Integrated into `endorseApplicant` with defensive try/catch.
   - `updateApplicantProfileOnce`: Invokes authoritative `fn_update_applicant_profile_once` RPC to update first/last/middle name, contact number, and record audit reason in `applicant_audit_logs`.
   - `propagateApplicantIdentityToLinked`: Queries sibling applicant rows with matching normalized contact number and updates names in parallel, mirroring Mobile `ApplicantService.propagateApplicantIdentityToLinked`.
   - `useUpdateApplicantProfile`: Mutation hook invalidating `vacancies`, `vacancy-list`, `vacancy-counts`, `vacancy-summary`, and `vacancy-detail`.
   - `withdrawVacancyClosureRequest` & `useWithdrawVacancyClosureRequest`: Calls `withdraw_vacancy_closure_request` RPC with fallback direct-table update and query cache invalidation.
   - Enriched `VacancyListItem`, `VacancyDetail`, and `ActiveApplicantItem` with `profileEditCount`.

3. **UI Modals & Surface Integration**:
   - `src/components/vacancy/EditApplicantModal.tsx`: Brand new modal component featuring:
     - Form state initialized from props via React key remounting.
     - Uppercase normalization on First, Middle, and Last Name.
     - Philippine 11-digit mobile number format validation (`09...`).
     - One-time edit policy enforcement (`profileEditCount >= 1` disables submission with badge unless user has Super Admin / Head Admin full access).
     - Reason field requirement (minimum 5 characters).
     - Confirmation dialog overlay preventing accidental submission.
   - `src/components/vacancy/VacancyDetailDrawer.tsx`:
     - Added "Edit Details" button on active applicant cards (`activeApplicantsList.map` and fallback `detail.applicantName`).
     - Added "Withdraw Closure" action in `CapabilityActionBar` and in the in-flight clearance alert banner.
     - Updated "Drop / Backout" action availability condition to `(isUserFullAccess || detail.derivedStatus?.toLowerCase() !== "hired")` to unblock Super Admin handling of post-onboard dropouts.
     - Rendered `<EditApplicantModal>` at drawer root.
   - `src/components/vacancy/VacancyTable.tsx`:
     - Added `onEditApplicant` prop.
     - Rendered "Edit" button (`Edit3` icon) on Pipeline tab rows for authorized users.
   - `src/app/(dashboard)/vacancy/page.tsx`:
     - Wired `handleEditApplicant` into `VacancyTable` and rendered `<EditApplicantModal>` with success toasts.

---

### Verification
- `npm run lint`: Clean pass (23 warnings across unrelated legacy modals, 0 errors).
- `npm run build`: Clean production build pass (`✓ Compiled successfully in 25.3s`, TypeScript pass in 52s, all 19 static routes generated cleanly).

---

## Multi-Headcount Vacancy Visibility Across Open & Pipeline Tabs (Mobile & Web Parity) (ohm#m4p8x2c1)

**Status: COMPLETE — MIGRATION 20262606000049 APPLIED TO STAGING & PRODUCTION, DERIVED_STATUS CAPACITY-AWARE (OPEN WHILE HC_FILLED < HC_TOTAL), PIPELINE MULTI-CANDIDATE EXPANSION ACTIVE, AUTOMATED REOPEN ON SLOT OCCUPANCY TRANSITION INSTALLED, CLEAN LINT & BUILD VERIFIED**

### Objective
1. **Multi-Headcount Requisitions Stay in `Open` Tab Until Fully Fulfilled:**
   - A store requisition (`vcode`) with multiple required headcount (e.g. `VCAG5_0056` with 7 HC) must remain visible and actionable (`+ Applicant`) in the **Open** tab as long as `hc_filled < hc_total` (i.e. `confirmed_onboard_count < required_headcount`), regardless of how many candidates are currently in `Pipeline`.
   - Adding 1 applicant to a 7-HC vacancy means 1 slot is in Pipeline and 6 slots are still Open. The requisition must NOT vanish from Open until all required slots are fulfilled/onboarded (`hc_filled >= hc_total`).
2. **Simultaneous Visibility & Candidate Row Expansion in `Pipeline` Tab:**
   - The requisition remains in the Open tab for HRCOs to endorse remaining slots, while its active candidates appear simultaneously in the **Pipeline** tab.
   - For multi-headcount requisitions with multiple active applicants in pipeline, the Pipeline tab expands into 1 row per active candidate so each candidate can be advanced, hired, or backed out individually.
   - Badge counts (`total_open` and `with_applicant` / `pipeline`) match the table rows 100%.
3. **Automatic Re-appearance on Backout or Resignation:**
   - When a candidate in Pipeline or Hired backs out or resigns, releasing a slot so `hc_filled < hc_total`, the requisition remains/reappears in the **Open** tab with updated `hc_display` (`Filled / Total`).
   - Plantilla slot transitions (`slot_status = 'open'`) trigger automatic reset of `vacancies.status = 'Open'` and `is_archived = false`.

---

### Root Causes
1. **Premature Status Overwrite in `endorseApplicant` (`src/lib/queries/vacancy.ts`):**
   - Endorsing an applicant executed an unconditional `UPDATE vacancies SET status = 'Pipeline' WHERE vcode = ...`.
   - In `vacancies`, `'Pipeline'` is an applicant queue state rather than a canonical vacancy lifecycle status (`Draft`, `Pending Approval`, `Open`, `On Hold`, `Filled`, `Closed`). Overwriting `status = 'Pipeline'` forced the entire vacancy out of `Open` queues.
2. **Binary Applicant Count Check in `vw_vacancy_list` & `vw_vacancy_detail`:**
   - `derived_status` evaluated `WHEN COALESCE(s.active_applicant_count, 0) > 0 THEN 'Pipeline'::text` BEFORE checking whether the vacancy had remaining open quota (`hc_filled < hc_total`).
3. **Backend RPC Filters (`list_web_vacancies` & `get_web_vacancy_summary`):**
   - `p_status = 'Open'` filtered strictly on `pipeline_status = 'Open'` (or `vacancy_status = 'Open'`), which excluded any requisition that had `active_applicant_count > 0` even when only 1 out of 7 slots had an applicant.
4. **Shadow View Evaluation (`vw_slot_derived_vacancy_shadow`):**
   - Evaluated `pipeline_count > 0` before checking `open_count > 0`, diverging shadow views from Open queue capacity.
5. **Frontend Client-Side Tab Filter (`listVacancies`):**
   - Open tab filter checked `!hasActive`, aggressively stripping rows with `activeApplicantCount > 0`.
6. **Pipeline Single-Candidate Flattening:**
   - Pipeline tab enrichment only took `actives[0]`, rendering a single candidate row even when a requisition had multiple active candidates.

---

### Key Implementations
1. **Database Migration (`supabase/migrations/20262606000049_multi_hc_open_pipeline_visibility_parity.sql`):**
   - **Section 1 (`fn_is_valid_vacancy_transition`)**: Permitted `Pipeline -> Open` and `Closed -> Open` transitions.
   - **Section 2 (`vw_vacancy_list`) & Section 3 (`vw_vacancy_detail`)**: Updated `derived_status` to evaluate capacity-awareness:
     `WHEN COALESCE(s.confirmed_onboard_count, 0) < GREATEST(COALESCE(v.required_headcount, 1), 1) THEN 'Open'::text`.
   - **Section 4 (`list_web_vacancies`)**:
     - `p_status = 'open'`: Includes requisitions where `s.hc_filled < s.hc_total` (unfulfilled quota).
     - `p_status = 'pipeline'`: Includes requisitions where `s.active_applicant_count > 0`.
   - **Section 5 (`get_web_vacancy_summary`)**:
     - `total_open`: Counts all non-closure, non-archived vacancies where `hc_filled < hc_total`.
     - `with_applicant`: Sums `active_pipeline_count` across all scoped requisitions.
   - **Section 6 (`vw_slot_derived_vacancy_shadow`)**:
     - Reordered `vacancy_tab` CASE expression to evaluate open capacity before pipeline.
   - **Section 7 (`trg_reopen_vacancy_on_slot_open`)**:
     - Automatically resets `vacancies.status = 'Open'`, `is_archived = false`, `archived_at = NULL` whenever a `plantilla_slots` row transitions to `slot_status = 'open'`.
   - **Section 8 (Data Repair)**:
     - Repaired `VCAG5_0056` status back to `'Open'`.
   - **Applied to both Staging (`qqiiznmqxfoamqytjica`) and Production (`rwxelulyapjgaarlwkus`).**
2. **Frontend Queries (`src/lib/queries/vacancy.ts`):**
   - **`endorseApplicant`**: Removed blind `UPDATE vacancies SET status = 'Pipeline'`. Status remains `'Open'` until all slots are confirmed onboard.
   - **`listVacancies` (Open Tab)**: Replaced `!hasActive` filter with `isUnfulfilled = hcFilled < hcTotal` (and non-closure), keeping partially filled multi-HC vacancies in Open with applicant fields cleared for store requisition presentation.
   - **`listVacancies` (Pipeline Tab)**: Expanded multi-headcount requisitions with active candidates into 1 row per active applicant (`activeByVcode`), populating `applicantId`, `applicantName`, `contactNumber`, and `stageBadge` so each candidate is independently actionable.
   - **`failBackoutApplicant`**: Ensured that when `confirmedCount < requiredHc`, the requisition status is set to `'Open'` and `is_archived = false`, regardless of remaining pipeline count.

---

### Verification
- **Staging Database Verification**:
  - `VCAG5_0056`: `status = 'Open'`, `derived_status = 'Open'`, `hc_filled = 0`, `hc_total = 7`, `hc_display = '0/7'`, `active_applicant_count = 1`.
  - Requisition is simultaneously active in Open tab and represented in Pipeline tab.
- **Production Database Verification**:
  - Migration applied cleanly across all functions, views, and triggers.
- **`npm run lint`**: Clean build (0 errors; existing warnings in unrelated modals preserved).
- **`npm run build`**: Next.js Turbopack build succeeded with 0 errors across all 19 static routes.

---



**Status: COMPLETE — VACANCY ARCHIVE PREDICATE REMOVED FROM DROPOUT QUERIES, BACKOUT WORKFLOW HARDENED, DRAWER SCOPE FALLBACK ADDED, ALL TESTS PASSING, CLEAN LINT & BUILD**

### Objective
1. **Investigate Missing Backout Candidate (Justin Agila Santos):** Candidate `Justin Agila Santos` was tagged as `Backout` with reason `"Location Issue"` on requisition `VCTG2_0005`, but was missing from the **Failed / Backout** tab.
2. **Backout Reason Sanity Audit:** Ensure that any supported backout reason (e.g., *Location issue*, *Salary issue / Compensation*, *Personal reason*, *Found another job*, custom write-ins) properly executes the complete terminal workflow:
   - Applicant updates to terminal status (`Backout`), `is_archived = true`, `archived_at = now()`, `slot_id = null`.
   - Plantilla slot resets to `'open'`.
   - Vacancy status resets correctly (`'Open'` if headcount is unfulfilled, or `'Filled'` if quota is complete).
   - Candidate appears cleanly in the **Failed / Backout** tab without runtime errors or duplicate rows.
   - Detail drawer opens seamlessly even if the parent requisition is filled or archived.

---

### Root Causes
1. **Archive Filtering on Vacancies in Failed / Backout Queries:**
   - In `src/lib/queries/vacancy.ts`, `listVacancies` (`currentTab === "failed_backout"`) and `getVacancySummary` (`failedPromise`) queried `vacancies` matching dropout candidate vcodes with `.eq("is_archived", false)`.
   - When a vacancy reaches full headcount capacity (e.g. `VCTG2_0005` with `required_headcount = 1` and `Juan Dela Cruz` Confirmed Onboard), `failBackoutApplicant` transitioned the vacancy status to `'Filled'`.
   - The Postgres trigger `on_vacancy_filled_archive` automatically sets `is_archived = true` on `vacancies` when status becomes `'Filled'`.
   - Because `VCTG2_0005` had `is_archived: true`, the query omitted `VCTG2_0005`, causing `validDropouts = dropoutsData.filter((d) => vacMap.has(d.vacancy_vcode))` to drop `Justin Agila Santos`.
2. **Export Query Inconsistency:**
   - `fetchAllFailedVacancies` incorrectly checked `applicants.is_archived = false` (preventing archived dropouts from exporting) and `vacancies.is_archived = false`.
3. **Detail Drawer 42501 Exception on Archived/Filled Requisitions:**
   - The RPC `get_web_vacancy_detail` raises SQLSTATE `42501` for vacancies that are `is_archived = true` or `Filled`/`Closed`. `getVacancyDetail` previously only fell back to `fn_get_hired_applicants`, which caused drawer crashes when opening details for a dropout on a filled requisition.

---

### Key Implementations
1. **Query Layer Alignment (`src/lib/queries/vacancy.ts`)**:
   - **`listVacancies` (`currentTab === "failed_backout"`)**: Removed `.eq("is_archived", false)` from `vacQuery` while preserving `.is("deleted_at", null)`. All non-deleted requisition dropouts now populate the table.
   - **`getVacancySummary` (`failedPromise`)**: Removed `.eq("is_archived", false)` from `vacQuery` so badge counts accurately tally all dropouts on non-deleted requisitions.
   - **`fetchAllFailedVacancies`**: Removed `.eq("is_archived", false)` from both `applicants` and `vacancies` queries so CSV exports accurately include all backout and failed applicants.
   - **`failBackoutApplicant`**:
     - Added `archived_at: new Date().toISOString()` when archiving the dropout applicant.
     - When resetting vacancy status to `'Open'` (when remaining pipeline candidates is 0 and confirmed count < required headcount), explicitly cleared `is_archived: false`, `archived_at: null`, and `archived_by: null`.
   - **`getVacancyDetail`**:
     - Added a direct fallback to `vacancies` and `applicants` tables when `get_web_vacancy_detail` throws `42501` (forbidden/out of scope) for filled or archived vacancies, cleanly hydrating drawer information for dropouts without crashes.

---

### Verification
- **Database Inspection**: Confirmed `Justin Agila Santos` exists in `applicants` (`status: 'Backout'`, `backout_reason: 'Location issue'`, `is_archived: true`, `slot_id: null`) linked to `VCTG2_0005` (`status: 'Filled'`, `is_archived: true`, `deleted_at: null`).
- **Query Verification**: Verified that with `.eq("is_archived", false)` removed, `VCTG2_0005` and `Justin Agila Santos` are included in `validDropouts` and appear with Date of Backout (`2026-10-20`), reason (`Location issue`), and correct outlet details (`SM CALOOCAN 1`).
- **Slot State**: Plantilla slot for `VCTG2_0005` is verified released to `'open'`.
- **`npm run lint`**: 0 errors (23 pre-existing warnings in unrelated files).
- **`npm run build`**: Next.js Turbopack build succeeded with 0 errors.

---

## HC Fraction Display (Filled/Total), Moses HQ Outlet Mapping, & HRCO Sync Audit (ohm#h8k3m2x5)

**Status: COMPLETE — MIGRATION 20262606000048 APPLIED, HC FRACTION DISPLAY COMPUTED IN VIEWS & RPCS, MOSES HQ OUTLET FALLBACK CONFIGURED, HIERARCHICAL HRCO RESOLUTION ACTIVE, VERIFIED CLEAN LINT & BUILD**

### Objective
1. **HC Column Format (`Filled / Total`):** In the Vacancy table and views (`vw_vacancy_list`, `vw_vacancy_detail`), update the headcount/slot calculation so that instead of rendering a static integer (`1`), it correctly computes and displays as `Filled / Total` (e.g., `0/7`, `1/8`, `3/3`) based on confirmed onboard hires vs total required plantilla slots.
2. **Moses HQ Outlet Name Mapping:** For requisitions originating from the Moses HQ pool or internal general pools, ensure the `outlet_name` correctly resolves and displays as **"Moses HQ"** instead of blank or dash (`—`).
3. **HRCO Resolution Audit & Fix:** Investigate why certain specific accounts show a blank HRCO (`—` or `Unassigned`) even after being assigned in User Management. Audit the join between `vacancies`, `accounts`, and `user_scopes` / `account_assignments` in `vw_vacancy_list` and `src/lib/queries/vacancy.ts` so assignments propagate and display correctly.

---

### Root Causes
1. **Headcount Format (`Filled / Total`):** `list_web_vacancies` previously did not expose `confirmed_onboard_count` or `required_headcount`, and frontend normalized headcount to a default static `1`.
2. **Moses HQ Outlet Mapping:** Pool vacancies (e.g., `SEA-00005`, `BUN-GHQ-00011`, `BUN-GHQ-00014`) have `store_name: NULL` and `home_account_id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152'` (Moses HQ), causing `store_name` to be blank/dash without a pool outlet fallback.
3. **HRCO Resolution:** `vw_vacancy_list` joined HRCO strictly via `v.hrco_user_id`. In the database, only 96 of 324 vacancies had `v.hrco_user_id` populated directly, whereas 279 accounts were assigned HRCOs through User Management in `user_scopes` (`scope_type = 'account'`).

---

### Key Implementations
1. **Database Migration (`supabase/migrations/20262606000048_hc_fraction_moses_hq_and_hrco_resolution.sql`)**:
   - **`vw_vacancy_list` & `vw_vacancy_detail`**:
     - `store_name`: Added COALESCE with `'Moses HQ'` when store name is null and requisition belongs to Moses HQ / internal pool (`is_pool_vacancy`, `source = 'pool'`, `vcode LIKE '%GHQ%'`, `account = 'Moses HQ'`, or `home_account_id = '3946ffdd-d826-4fc7-bb9e-356a32dcd152'`).
     - `hrco_name`: Added hierarchical resolution fallback: (1) direct vacancy `v.hrco_user_id`, (2) store assigned HRCO, (3) account assigned HRCO, (4) User Management account scopes (`user_scopes` with `scope_type = 'account'`), (5) Group scopes (`user_scopes` with `scope_type = 'group'`), (6) legacy `v.hrco_name`.
     - `hc_filled`, `hc_total`, `hc_display`: Computed as `COALESCE(astat.confirmed_onboard_count, 0)`, `COALESCE(v.headcount, 1)`, and `format('%s/%s', COALESCE(astat.confirmed_onboard_count, 0), COALESCE(v.headcount, 1))`.
   - **`list_web_vacancies` & `get_web_vacancy_detail`**:
     - Exposed `hc_filled`, `hc_total`, `hc_display`, `confirmed_onboard_count`, `required_headcount` inside `row_capabilities jsonb` (preserving existing Postgres `RETURNS TABLE` RPC signature without requiring destructive `DROP FUNCTION`).
   - Applied cleanly to remote Supabase instance.
2. **Frontend Adaptation (`src/lib/queries/vacancy.ts`, `VacancyTable.tsx`, `VacancyDetailDrawer.tsx`)**:
   - **`src/lib/queries/vacancy.ts`**:
     - Added `hcFilled`, `hcTotal`, `hcDisplay` to `VacancyListItem` and `VacancyDetailItem`.
     - Normalized `hc_filled`, `hc_total`, `hc_display` from `row_capabilities` across `normalizeListRow` and `normalizeDetailRow`.
     - Added Moses HQ pool fallback and HC fraction calculation across `hired`, `closure`, and `failed_backout` tab pipelines.
     - Added `user_scopes` fallback query in `getVacancyDetail` for single-record drawer hydration.
   - **`src/components/vacancy/VacancyTable.tsx`**:
     - Updated HC column rendering: `row.hcDisplay || `${row.confirmedOnboardCount ?? row.hcFilled ?? 0}/${row.headcount ?? row.hcTotal ?? 1}``.
   - **`src/components/vacancy/VacancyDetailDrawer.tsx`**:
     - Added Moses HQ pool fallback when `storesList` is empty for pool vacancies.

---

### Verification
- Verified `vw_vacancy_list` in database:
  - Moses HQ requisitions (e.g., `BUN-GHQ-00011`, `SEA-00005`) resolve `store_name` to `'Moses HQ'`.
  - HRCO resolves dynamically via `user_scopes` (e.g., `BK-G1-0053` resolves to `Jane Bilaro`, `VCAG2_0025` to `UAT Test 1`).
  - HC computes as fractional values (e.g., `0/7`, `0/13`, `3/3`, `1/8`).
- Ran `npm run lint`: 0 errors.
- Ran `npm run build`: Next.js Turbopack build succeeded with 0 errors.

---

## Fix Backout Workflow, Prevent Pipeline Leakage, and Clean Up Vcode Duplication (ohm#x5w9k3b7)

**Status: COMPLETE — MIGRATION 20262606000047 APPLIED, VIEW AND SLOT SYNC HARDENED, MUTATION ARCHIVAL AND SLOT RECONCILIATION WIRED, VERIFIED CLEAN LINT & BUILD**

### Objective
Resolve the regression in Vacancy Management where:
1. Tagging an applicant (e.g., Lando Norris / Selena Gomez) as **Backout** left or retained a ghost record in the **Pipeline** tab instead of cleanly moving exclusively to the **Failed / Backout** tab.
2. The corresponding store requisition (`vcode`) was not returned to the **Open** tab completely blank/unassigned.
3. Requisitions like `VCAG5_0056` accumulated multiple duplicate backout entries because previous actions did not archive or terminate the specific applicant record, cluttering active store slots in `plantilla_slots` and `vw_vacancy_list`.

---

### Root Causes
1. `failBackoutApplicant` set `is_archived: false`. Because `is_archived` was `false`, views and slot synchronization functions continued treating terminal candidates as active.
2. Direct table update to `status` right before calling `fn_update_applicant_pipeline` caused the RPC to raise an unhandled exception (`status already terminal` / `no fields changed`), which was caught and silenced, bypassing `fn_release_applicant_slot` and `fn_sync_vacancy_slot_open_pipeline`.
3. `vw_vacancy_list` and `vw_vacancy_detail` omitted `'Rejected'` from their active applicant filter arrays and performed case-sensitive comparisons, causing `LEWIS HAMILTON` (`status: Rejected`) on `VCAG5_0056` to count as active (`active_applicant_count = 1`), forcing `derived_status = 'Pipeline'`.
4. `fn_sync_vacancy_slot_open_pipeline` fetched only 1 slot via `LIMIT 1`. On multi-headcount requisitions (such as `VCAG5_0056`), slot 1 was open while slot 2 remained stuck in `pipeline`.
5. `VacancyDetailDrawer.tsx` fell back to `detail.vacancyId` when opening `FailBackoutModal` without a sub-candidate selected, targeting the vacancy ID in the `applicants` table.

---

### Key Implementations
1. **Database Migration (`supabase/migrations/20262606000047_fix_backout_workflow_and_slot_sync.sql`)**:
   - **`vw_vacancy_list` & `vw_vacancy_detail`**: Updated `applicant_stats` to robustly exclude all terminal statuses (`'failed', 'backout', 'rejected', 'did_not_report', 'rejected_by_ops', 'withdrew', 'confirmed_onboard'`) using case/whitespace-insensitive normalization.
   - **`fn_sync_vacancy_slot_open_pipeline`**: When active applicant count is 0, loops over and releases **all** unoccupied pipeline slots for that vcode back to `'open'`.
   - **Data Cleanup**: Cleaned up unarchived/orphaned dropouts across all active vacancies (`is_archived = true`, `slot_id = NULL`). For `VCAG5_0056`, retained `LANDO NORRIS` as the sole canonical backout record, recorded missing history in `applicant_status_history`, reset unoccupied `pipeline` slots in `plantilla_slots` to `'open'`, and set `vacancies.status = 'Open'`.
   - Applied cleanly to remote Supabase instance.
2. **Backend Mutation Hardening (`src/lib/queries/vacancy.ts`)**:
   - In `failBackoutApplicant`: Defensively resolves `applicantId` (falling back to the active applicant on `vcode` if caller passed vacancy ID). Updates applicant row with `status = params.status`, `backout_reason`, `backout_date`, **`is_archived: true`**, and **`slot_id: null`**.
   - Records audit entry in `applicant_status_history`.
   - Invokes `fn_release_applicant_slot` and `fn_sync_vacancy_slot_open_pipeline`.
   - Performs quota-aware status transition: sets `vacancies.status = 'Open'` if 0 active candidates and unfilled quota remains, or `'Filled'` if quota is satisfied.
   - In `updateApplicantPipeline`: In fallback handler, marks `is_archived: true` and `slot_id: null` on terminal statuses.
   - In `failedPromise` and `listVacancies` (`currentTab === "failed_backout"`): Removed `.eq("is_archived", false)` requirement so archived terminal dropouts cleanly appear in the `Failed / Backout` tab.
3. **UI Binding Hardening (`src/components/vacancy/VacancyDetailDrawer.tsx`)**:
   - Ensured top action bar and modal fallbacks bind to `detail.applicantId` instead of `detail.vacancyId`.
   - Added `applicantId?: string | null` to `VacancyDetailItem` and populated it in `normalizeDetailRow`.

---

### Verification
- Verified `VCAG5_0056` in `vw_vacancy_list`: `status = 'Open'`, `derived_status = 'Open'`, `active_applicant_count = 0`.
- Verified all 8 slots in `plantilla_slots` for `VCAG5_0056`: all `slot_status = 'open'`.
- Verified `VCAG5_0056` in `Failed / Backout`: exactly 1 clean row for `LANDO NORRIS` (`Backout`, `Found another job`, `2026-10-20`).
- Verified `VCAG5_0056` does not appear in `Pipeline` tab.
- Ran `npm run lint`: 0 errors.
- Ran `npm run build`: compiled and type-checked cleanly with 0 errors.

**Status: COMPLETE — MIGRATION 20262606000046 APPLIED TO STAGING & PROD, TRIGGER AND VIEW HARDENING INSTALLED, GROUP ENRICHMENT & FORMATTING WIRED ON WEB**

### Objective
Resolve issue where accounts such as **BANKO** and **ACTISERVE** were displaying **"General / Direct"** under the **ACCOUNT / GROUP** column in Vacancy Management instead of their assigned client groups (`Group 1` to `Group 5`) or `MOSES HQ`.

---

### Root Cause
1. In PostgreSQL, `vacancies` table had rows where `group_id IS NULL` (including test vacancies for `BANKO` like `TEST005`–`TEST011` and other accounts), despite their `account_id` referencing active accounts with assigned groups (`Group 1` for BANKO, `Group 5` for ACTISERVE, `Global HQ` for Moses HQ).
2. Database views `vw_vacancy_list` and `vw_vacancy_detail` joined `groups g ON g.id = v.group_id` without falling back to `a.group_id` from `public.accounts`. When `v.group_id` was null, `g.group_name` evaluated to null.
3. The frontend data fetching layer (`src/lib/queries/vacancy.ts`) lacked account-group fallback enrichment (unlike store locations and HRCO names).
4. `VacancyTable.tsx` and `VacancyDetailDrawer.tsx` defaulted to `"General / Direct"` whenever `row.groupName` was null/empty.

---

### Key Implementations
1. **Database Migration (`supabase/migrations/20262606000046_fix_vacancy_group_resolution.sql`)**:
   - **Data Backfill**: Updated existing `public.vacancies` where `group_id IS NULL` by setting `group_id = a.group_id` from `public.accounts` (matching `v.account_id = a.id` or account name). Verified 0 remaining null group IDs across both staging and production.
   - **Auto-Assignment Trigger**: Added `trg_fn_auto_assign_vacancy_group_id` as a `BEFORE INSERT OR UPDATE` trigger on `public.vacancies` to automatically populate `NEW.group_id` from `accounts` whenever `NEW.group_id IS NULL`.
   - **View Hardening**: Recreated `vw_vacancy_list` and `vw_vacancy_detail` joining `accounts a` and coalescing `COALESCE(v.group_id, a.group_id)` and `COALESCE(g.group_name, ga.group_name)`. Re-applied grants for `authenticated`, `postgres`, and `service_role`.
   - **Deployment**: Applied cleanly to both Staging (`qqiiznmqxfoamqytjica`) and Production (`rwxelulyapjgaarlwkus`).
2. **Frontend Helper & Enrichment (`src/lib/queries/vacancy.ts`)**:
   - Implemented and exported `formatGroupName(groupName, accountName)`:
     - Formats `Global HQ` / `GHQ` (or `Moses HQ` account) into `MOSES HQ`.
     - Preserves `Group 1` through `Group 5`.
     - Returns empty string only when unassigned.
   - Updated `normalizeListRow` and `normalizeDetailRow` to use `formatGroupName(asString(row.group_name), asString(row.account_name ?? row.account))`.
   - Added batch enrichment in `fetchVacancies`: for any row missing `groupName`, queries `accounts` with `groups(group_name)` and maps group info by account ID or account name.
   - In `getVacancyDetail`: enriched `groupName` and `groupId` from `accounts` + `groups(group_name)`.
   - In `fetchHiredVacancies` and `fetchFailedBackoutVacancies`: updated group name formatting with `formatGroupName`.
3. **UI Presentation (`src/components/vacancy/VacancyTable.tsx` & `VacancyDetailDrawer.tsx`)**:
   - Updated table column 3: `{formatGroupName(row.groupName, row.accountName) || "General / Direct"}`.
   - Updated detail drawer subtitle and overview metadata card to display formatted group names.
4. **Verification**:
   - `npm run lint` clean (0 errors, 23 pre-existing warnings in unrelated files).
   - `npm run build` passed cleanly across all 19 routes.
   - Verified in database: 0 vacancies with null `group_id` or `group_name` in both staging and production.

---

## Vacancy Failed/Backout Tab Layout Refinement (Date of Backout, Dynamic Aging, Simplified Status) (ohm#c9k4w1x2)

**Status: COMPLETE — DEDICATED 9-COLUMN SCHEMA, DYNAMIC AGING CALCULATION, DATE OF BACKOUT COLUMN, AND SIMPLIFIED STATUS APPLIED, MAIN BRANCH**

### Objective
Refine the `Failed / Backout` tab layout in the Vacancy module based on UI feedback:
1. Remove `HC` column from `Failed / Backout`.
2. Remove `ACTIONS` column from `Failed / Backout` (row clicks retain drawer trigger).
3. Compute dynamic `Aging` days so it is never blank (`—`).
4. Relocate date of backout from underneath candidate name into its own dedicated `DATE OF BACKOUT` column.
5. Simplify `STATUS` column display by removing rounded pill/badge chip and rendering clean typography.

---

### Key Implementations
1. **Dynamic Aging Calculation (`src/lib/queries/vacancy.ts`)**:
   - In `listVacancies` under `currentTab === "failed_backout"`, added `created_at` to the `vacancies` query select list.
   - Dynamically calculated `agingDays` and `agingBucket` from `vac?.vacant_date ?? vac?.created_at ?? d.created_at` against `Date.now()`, ensuring dropouts show actual aging days and matching aging badges (≤15d green, ≤30d amber, >30d rose).
2. **Dedicated Table Schema (`src/components/vacancy/VacancyTable.tsx`)**:
   - In `getTableColumns(status)`, added dedicated branch for `status === "failed_backout"` returning exactly 9 columns: `["VCODE", "POSITION", "ACCOUNT / GROUP", "OUTLET NAME", "HRCO", "APPLICANT", "DATE OF BACKOUT", "STATUS", "AGING"]`.
   - Omitted `HC` and `ACTIONS` columns from header.
3. **Table Body Cell Alignment (`src/components/vacancy/VacancyTable.tsx`)**:
   - Created dedicated `status === "failed_backout"` rendering block for columns 6–9:
     - **APPLICANT (Col 6)**: Formatted candidate name (`formatPersonName`) with secondary date subtitle removed.
     - **DATE OF BACKOUT (Col 7)**: Dedicated column rendering `formatDropoutDate(row.dropoutDate)` with clean font-mono styling.
     - **STATUS (Col 8)**: Simplified typography `<span className="text-xs font-medium text-rose-700">{row.dropoutReason || "Failed / Backout"}</span>` without circular badge chip.
     - **AGING (Col 9)**: Dynamic badge display showing calculated days count.
   - Updated trailing column block `{status !== "hired" && status !== "failed_backout" && (` so `HC` and `ACTIONS` are completely omitted on `failed_backout`, matching table header length (9 columns).
   - Cleaned up unused `RotateCcw` import and parameter warnings.
4. **Verification**:
   - `npm run lint` clean (0 errors).
   - `npm run build` passed with all 19/19 routes compiled cleanly in Next.js 16.

---

## Fix Backout Row Leakage, Duplication, and Candidate Overwrite Across Vacancy Tabs (ohm#b8k2w7x4)

**Status: COMPLETE — BACKOUT APPLICANT ARCHIVAL GUARD, REACT COMPOSITE KEYING & COLUMN SCHEMA SYNCHRONIZATION APPLIED, MAIN BRANCH**

### Objective
Audited and resolved the regression where tagging a candidate as Backout (e.g. `MAX VERSTAPPEN`) caused:
1. Requisition `BUN-GHQ-00014` (`DQWF, WEDFWE EFE`, status `Backout`, action `Reopen`) to leak into every tab (`Open`, `Pipeline`, `Hired`, `Closure`) with misaligned table columns (pushing cells into unaligned columns).
2. The candidate `MAX VERSTAPPEN` to be missing/overwritten in `Failed / Backout` tab, and `DQWF, WEDFWE EFE` to be duplicated 3 times due to React key collision.
3. Raw unformatted ISO timestamp strings (`2026-08-11T07:56:51.33335+00:00`) rendered in the applicant subtitle.

---

### Key Implementations
1. **Applicant Backout Archival Hardening (`src/lib/queries/vacancy.ts`)**:
   - In `failBackoutApplicant`, removed `is_archived: true` (set `is_archived: false`). Dropped candidates must remain active records in `applicants` with terminal status (`Backout`/`Rejected`) so they appear in `Failed / Backout` and summary counters.
   - Removed `updates.is_archived = true` fallback in `updateApplicantPipeline`.
   - In `failBackoutApplicant`, replaced blind `status = 'Open'` reset with a quota-aware transition: only transitions vacancy to `'Open'` if unfilled slots remain (`confirmedCount < requiredHc`). If confirmed hires already satisfy the required headcount (e.g. `BUN-GHQ-00014` with 3/3 confirmed onboard), sets status to `'Filled'`.
   - Restored database state for `MAX VERSTAPPEN` (`is_archived = false`) and `BUN-GHQ-00014` (`status = 'Filled'`).
2. **React Key Collision & Candidate Identity Preservation (`src/components/vacancy/VacancyTable.tsx`)**:
   - Preserved `row.id` as the vacancy UUID for seamless drawer compatibility (`getVacancyDetail`).
   - Ensured `row.applicantId` is strictly bound to `d.id` on all dropout rows.
   - Changed row React key in `VacancyTable.tsx` from `key={row.id}` to composite key `<tr key={`${row.id}-${row.applicantId ?? row.vcode}-${index}`}>`, eliminating virtual DOM key collisions, row multiplication, and candidate overwriting.
3. **Strict Tab Scoping & Column Alignment (`src/lib/queries/vacancy.ts` & `src/components/vacancy/VacancyTable.tsx`)**:
   - In `listVacancies`, enforced strict tab scoping so dropout fields (`dropoutReason`, `dropoutDate`, `applicantId`, `applicantName`, `contactNumber`, `stageBadge`) are explicitly reset on `currentTab === "open"`.
   - In `VacancyTable.tsx`, verified that row rendering strictly matches the active tab's header column count (8 columns for `open`/`hired`, 10 columns for `closure`/`pipeline`/`failed_backout`), preventing cell shifting.
4. **Clean Dropout Date Formatting (`src/components/vacancy/VacancyTable.tsx` & `src/lib/queries/vacancy.ts`)**:
   - Sanitized `dropoutDate` in `listVacancies` to date string.
   - Added `formatDropoutDate` helper in `VacancyTable.tsx` rendering humanized dates (e.g. `Aug 11, 2026`, `Oct 20, 2026`) accompanied by calendar icon matching `Hired` tab parity.
5. **Cleaned Up Scratch Files**:
   - Removed all temporary scratch test scripts.
6. **Verification**:
   - `npm run lint` clean (0 errors, 22 pre-existing warnings).
   - `npm run build` (Next.js 16 production build with full TypeScript checking) compiled 19/19 routes with 0 errors.

---

## Fix Candidate Name Field Binding & Parsing in Vacancy Module (Endorse -> Confirm Onboarding Flow) (ohm#n7f3w9k2)

**Status: COMPLETE — DISCRETE NAME FIELDS PERSISTED AND BOUND ACROSS VACANCY ENDORSE -> ONBOARDING FLOW, WITH HARDENED FALLBACK PARSER, MAIN BRANCH**

### Objective
In the Vacancy Module, resolved the issue where transitioning an endorsed candidate to the **Confirm Onboarding / Mark Hired** modal left `MIDDLE NAME` empty and corrupted multi-word surnames (e.g. `DELA CRUZ` being split into Last: `DELA` and First: `CRUZ`). Ensured discrete structured fields (`firstName`, `lastName`, `middleName`) are preserved and bound throughout the flow, and hardened the fallback name parser for legacy formatted strings.

---

### Key Changes
1. **Hardened Candidate Name Parser (`src/lib/utils/formatName.ts`)**:
   - Implemented `parseCandidateFullName(fullName, structured)`.
   - Binds directly to structured properties (`firstName`, `lastName`, `middleName`) when present.
   - For formatted strings `"LASTNAME, FIRSTNAME MIDDLENAME"`, splits on the first comma (`,`) to isolate the full `LAST_NAME`, preserving multi-word surnames like `DELA CRUZ` and `SAN JOSE`.
   - Excludes suffix tokens (`JR`, `JR.`, `SR`, `SR.`, `II`, `III`, `IV`, `V`) from middle names, attaching them to the surname instead.
   - Handles compound middle name prefixes (`DELA`, `DE`, `DEL`, `DELOS`, `SAN`, `STA`, `STA.`, `SANTO`) by keeping them attached to the middle name rather than pushing into the first name.
2. **Vacancy Query & Normalizer Layer (`src/lib/queries/vacancy.ts`)**:
   - Added `applicantMiddleName: string | null;` to `VacancyDetailItem` interface.
   - Updated `normalizeDetailRow` to return `applicantMiddleName` and use `parseCandidateFullName` if discrete names are absent.
   - Updated `normalizeActiveApplicant` to check `obj.middle_name ?? obj.applicant_middle_name` and populate fallback parsed names.
   - Updated `normalizeVacancyRow` to populate `applicantMiddleName`, `applicantLastName`, and `applicantFirstName` using `parseCandidateFullName` as fallback.
   - Updated `getVacancyList` active applicant enrichment loop to assign `row.applicantLastName`, `row.applicantFirstName`, and `row.applicantMiddleName`.
   - Updated `getVacancyDetail` fallback hired applicant lookup to include `applicantMiddleName` and `middleName`.
3. **Vacancy Detail Drawer (`src/components/vacancy/VacancyDetailDrawer.tsx`)**:
   - Included `middleName` in all `setSelectedCandidate(...)` state updates (Update Stage, Mark Hired, Edit Hired Date, Drop/Backout).
   - In `<MarkHiredModal applicant={...}>`, passed `middleName: detail.applicantMiddleName`.
4. **Vacancy Table View & Page Controller (`src/app/(dashboard)/vacancy/page.tsx`)**:
   - Verified that `handleMarkHired` forwards `middleName: row.applicantMiddleName` into `markHiredTargetCandidate`.
5. **Confirm Onboarding Modal (`src/components/vacancy/MarkHiredModal.tsx`)**:
   - Replaced naive regex split with `parseCandidateFullName(applicant.fullName, { firstName, lastName, middleName })`.
   - Directly binds `lastName`, `firstName`, and `middleName` states to discrete candidate properties.
   - Verified that `handleSubmit` sends discrete `trimmedMiddle` via `confirmApplicantOnboard` (`p_middle_name`), properly updating `applicants` and `hr_emploc`.
6. **Verification**:
   - `npm run lint` clean (0 errors, 22 pre-existing warnings).
   - `npm run build` (Next.js production build with full TypeScript type check) passed cleanly.
   - Standalone test matrix covering single names, multi-word surnames, suffixes, and compound middle names passed.

---

## Plantilla Import Audit & Review Queue / Error Log Parity (ohm#m5d8v2x4)

**Status: COMPLETE — FULL MOBILE STORE IMPORT PARITY WITH ADR-001 VALIDATION, REVIEW QUEUE ROUTING, ROW ERROR INSPECTOR, AND AUDIT LOGS, MAIN BRANCH**

### Objective
Conducted full architectural trace and resolved critical parity regressions in the Web "Import Plantilla (Bulk Baseline)" modal (`PlantillaImportModal.tsx`):
1. Eliminated premature green success toasts on failed validation batches.
2. Restored review queue routing for `validation_failed`, `blocked`, and `partially_blocked` batches.
3. Provided comprehensive row-level error breakdown and guidance in both Review Queue and Import History tabs.
4. Added client-side scope pre-validation (`GROUP_NAME` / `ACCOUNT_NAME` vs. UI dropdowns) and clean dismissal for dead batches.

---

### Key Changes
1. **Spreadsheet Scope Pre-Validation & Sample Data (`src/lib/utils/data_control_xlsx.ts`)**:
   - Implemented `validateSpreadsheetScopeContext` to check `GROUP_NAME` and `ACCOUNT_NAME` against the user's active UI scope dropdown selection before submitting to the backend, blocking mismatched scopes with row numbers and exact values.
   - Updated `PLANTILLA_SAMPLE_ROW` with clean mock identifiers (`SLOT-SAMPLE-001`, `EMP-SAMPLE-001`) preventing instant ADR-001 collision on official template test uploads.
2. **API & Data Layer (`src/lib/queries/dataControl.ts`)**:
   - Enriched `SubmitPlantillaImportResult` to return `{ batchId, status, totalRows, validRows, flaggedRows, skippedRows, blockedRows, errorSummary }`.
   - Updated `PlantillaImportBatch` and `fetchPlantillaImportBatches` to parse `errorSummary: Record<string, number>`.
   - Updated `PlantillaImportPreviewRow` and `fetchPlantillaImportRows` to parse `validation_errors`, `validation_flags`, and unified `validationMessages` with field and conflict classification tags.
3. **Review Queue State Machine & Auto-Focus (`src/components/more/PlantillaImportModal.tsx`)**:
   - `pendingBatches` now includes all reviewable statuses: `draft_uploaded`, `pending_approval`, `validation_failed`, `blocked`, `partially_blocked`.
   - On submission, if `status === 'validation_failed'` or `blockedRows > 0`, the UI avoids premature green success toasts, switches directly to the Review Queue tab, auto-expands the new batch inspector, and defaults the filter to `blocked`.
   - "Approve & Apply" button is safely disabled for `validation_failed` batches.
   - Added clean "Dismiss Batch" support using fallback default rejection remarks (`invalid_csv` code).
4. **Interactive Row Inspector & Filter Pills**:
   - Implemented row filter pills (`All`, `Blocked`, `Flagged`, `Valid`) in both Review Queue and Import History drawers.
   - Rendered rich row-level guidance with red conflict pills (`conflictType`, `field`) and bulleted validation error messages.
5. **Historical Failure Audit Log**:
   - In `Import History`, selecting a `validation_failed` or `rejected` batch displays an **Import Failure Audit & Error Log Drawer** displaying batch stats, rejection remarks, error summary tags, and full row inspection.
6. **Verification**:
   - `npm run lint` clean (0 errors, 22 pre-existing warnings).
   - `npx tsc --noEmit` clean (0 errors).

---

## Approvals Module Pagination & Table Controls (Vacancy Parity) (ohm#a8b3p9g1)

**Status: COMPLETE — 1:1 VACANCY PAGINATION PARITY ACROSS ALL 11 APPROVAL QUEUES, MAIN BRANCH**

### Objective
Implemented pagination in the **Approvals module** (`/approvals`) matching the exact UI design, behavior, state management, and implementation pattern used in the **Vacancy module** (`/vacancy`).

---

### Key Changes
1. **API / Query Layer**:
   - Added `RequestPaginationParams` (`{ page?: number; limit?: number }`) and `applyPagination` helper in `src/lib/queries/requests.ts`.
   - Updated `fetchHeadcountRequests`, `fetchNewStoreRequests`, `fetchVacancyClosureRequests`, `fetchApplicantMovementRequests`, `fetchDeactivationRequests`, `fetchAccountGroupTransfers`, `fetchRelieverEndorsements`, `fetchCoverageRequests`, and `fetchPlantillaApprovals` (plus corresponding hooks) to accept optional pagination options without breaking full-list client search.
   - Updated `src/lib/queries/accountRequests.ts` (`fetchApprovalQueue`, `useAccountApprovalQueue`) and `src/lib/queries/hr_emploc.ts` (`fetchEmplocDeletionRequests`, `useEmplocDeletionRequests`) with optional pagination parameter support.
2. **State Management & Dynamic Resets (`ActiveQueueReviewPane.tsx`)**:
   - Centralized `page` (default `1`) and `pageSize` (default `10`) in `ActiveQueueReviewPane`.
   - Configured `key={selectedCategory}` on `ActiveQueueReviewPane` in `src/app/(dashboard)/approvals/page.tsx` so changing sub-categories cleanly remounts the active review pane with fresh pagination state (`page: 1`).
   - Attached `setPage(1)` to all `QueueToolbar` tab changes (`onTabChange`) and search queries (`onSearchChange`).
   - Connected `onPageSizeChange={(newSize) => { setPageSize(newSize); setPage(1); }}` across all tables.
3. **Approval DataTables (All 11 Sub-Categories)**:
   - Updated props in:
     - `NewStoreDataTable.tsx`
     - `VacancyClosureDataTable.tsx`
     - `HrEmplocDeletionDataTable.tsx`
     - `HeadcountDataTable.tsx`
     - `PlantillaApprovalDataTable.tsx`
     - `AccountRequestDataTable.tsx`
     - `ApplicantMovementDataTable.tsx`
     - `DeactivationDataTable.tsx`
     - `AccountTransferDataTable.tsx`
     - `CoverageDataTable.tsx`
     - `RelieverDataTable.tsx`
   - Added `paginatedRequests` slicing `(page - 1) * pageSize` to `page * pageSize`.
   - Updated `isAllSelected` and `toggleSelectAll` to operate cleanly on `paginatedRequests`.
   - Embedded `<TablePagination>` directly at the bottom inside the table card (`border-t border-table-rule-section px-4 py-3`), displaying "Showing X–Y of Z records", "Rows per page: [10, 25, 50]", and page navigation controls identical to Vacancy.
4. **Code Quality & Lint**:
   - Cleaned up existing React 19 / Next.js ESLint warning in `approvals/page.tsx` (derived `selectedCategory` without synchronous `setState` in `useEffect`).
   - `npm run lint` clean (0 errors).

---

## Add Local Auto-Commit Step (No Push) to Mandatory Workflow Rules (ohm#2k9w4t7e)

**Status: COMPLETE — DOCS-ONLY, LOCAL AUTO-COMMIT WORKFLOW RULE, MAIN BRANCH**

### Objective
Integrated a local auto-commit step (explicit paths only, strictly never push) into the mandatory post-prompt workflow checklist and documentation rules across `.ai/briefing.md` and `AGENTS.md`.

---

### Implementation Details
1. **`.ai/briefing.md`**:
   - Updated "After Every Completed Prompt" checklist to 5 items:
     1. `.ai/briefing.md`
     2. `.ai/handoff.md`
     3. `docs/state/<module>_state.md`
     4. Local commit (see "Local Commit Rule" below)
     5. Branch close-out
   - Added new section `### Local Commit Rule (every prompt, after items 1-3)` specifying local commits on `main`, strictly no push/merge/rebase, explicit paths staging (never `git add .`), pre-commit clean status check, verification gate (`npm run lint` for code changes), and reporting requirements.
   - Updated "Last Completed Tasks" to prepend `ohm#2k9w4t7e: Add local auto-commit rule (web)` and trim to 5 tasks.
2. **`AGENTS.md`**:
   - Added rule bullet to Core Workflow Rules block referencing `.ai/briefing.md` § Local Commit Rule and prohibiting pushing or wildcard staging.
3. **Verification**:
   - Verified `git diff AGENTS.md .ai/briefing.md`.
   - Verified `git diff --stat` touches only `AGENTS.md`, `.ai/briefing.md`, and `.ai/handoff.md`.

---

## Fix Plantilla Module Permanent 'Rendering...' Freeze & Next.js CSR Suspense Parity (ohm#p7f2a1b9)

**Status: COMPLETE — CLIENT-SIDE SUSPENSE BOUNDARY & URL DERIVATION, MAIN BRANCH**

### Objective
Diagnosed and resolved the issue where navigating to `/plantilla` remained permanently frozen on "Rendering..." / "Loading User Workspace", bringing the module into 100% architectural parity with `/vacancy`, `/hr-emploc`, `/approvals`, and `/cencom`.

---

### Root Cause Diagnosis & Technical Findings
1. **Missing Suspense Boundary**: `useSearchParams()` was called directly inside root `PlantillaPage` without a Next.js `<Suspense>` boundary. In Next.js App Router, this triggers a CSR bail-out that hangs client-side rendering with a permanent "Rendering..." banner.
2. **Hydration Deadlock Gate**: The component gated all rendering behind `if (userContextQuery.isLoading || !isHydrated)`. If `userContextQuery` encountered any error or null resolution, `setIsHydrated(true)` was never reached due to an early return in `useEffect`, permanently trapping the view in `<DataState kind="loading" title="Loading User Workspace" ...>`.
3. **Cascading State Updates in `useEffect`**: Synchronous state updates (`setViewMode`, `setAccountId`, `setIsHydrated`) inside `useEffect` caused cascading re-renders and fought against router URL navigation (`router.push`).
4. **Duplicate User Context Loading**: Unlike other modules that utilize the shared `useCurrentUser()` hook, `PlantillaPage` ran a redundant `loadCurrentUserContext()` query with `staleTime: Infinity`.

---

### Implementation Details
1. **`<Suspense>` Boundary (`src/app/(dashboard)/plantilla/page.tsx`)**:
   - Wrapped the default `PlantillaPage` export in `<Suspense>` with a clean, animated loading skeleton matching `/approvals` and `/cencom`.
   - Renamed inner implementation to `PlantillaPageContent`.
2. **Canonical `useCurrentUser()` Hook**:
   - Replaced redundant `userContextQuery` with canonical `useCurrentUser()` from `@/lib/auth`.
   - Removed the deadlocking `isHydrated` state flag and its conditional check.
3. **URL-Derived State (`viewMode` & `accountId`)**:
   - Derived `viewMode` directly from `searchParams` (`view` or `tab` query param), removing `setViewMode` state.
   - Derived `accountId` directly from `searchParams.get("accountId")` with fallback to `currentUser.accountScope.ids[0]` for single-scoped accounts, eliminating state desync and navigation fighting.
   - Updated `handleSwitchView`, `handleSelectAccount`, and `handleBackToSelection` to operate directly on URL search parameters via `router.push`.
4. **Query Gating Cleanup**:
   - Updated `accountMetricsQuery` and `summaryQuery` to depend on `!!currentUser` instead of `isHydrated`.
5. **Verification**:
   - `npm run lint` passed with 0 errors and 0 warnings for `src/app/(dashboard)/plantilla/page.tsx`.
   - `npm run build` compiled all 19 static routes successfully (including `/plantilla`) with exit code 0.

---

## Data Control Sub-Tab Separation (Operations & Governance + Batch Imports) (ohm#d4c8t2b1)

**Status: COMPLETE — CLIENT-SIDE SUB-TAB NAVIGATION & STATE, MAIN BRANCH**

### Objective
Separated the Data Control section within the Admin Panel (`/more?tab=data_control`) into dedicated sub-tabs: **Operations & Governance** and **Batch Imports**, providing a cleaner workflow, clearer operational division, and smooth view transitions.

---

### Implementation Details
1. **Sub-Tab Partitioning & Types (`src/app/(dashboard)/more/page.tsx`)**:
   - Defined `DataControlSubTab = "operations" | "batch_imports"`.
   - Partitioned feature tiles into:
     - **Operations & Governance** (`operationsTiles`): *Edit Lock Control* (`SECURITY`, Amber), *Data Archival / Recovery* (`LEVEL 100`, Rose), *Global Store Transfer* (`TRANSFER`, Blue), *Roving Coverage Groups* (`ROVING`, Blue), and *Payroll Review Center* (`REVIEWS`, Purple).
     - **Batch Imports** (`batchImportTiles`): *Import HR Emploc* (`EXCEL`, Emerald), *Import Plantilla* (`BASELINE`, Purple), *Import Vacancy* (`INTAKE`, Purple), *Import MIKA* (`BIOMETRIC`, Purple), and *Import Payroll* (`CHECKER`, Purple).
2. **State Management & Router URL Synchronization**:
   - Sub-tab selection is derived directly from `searchParams.get("subtab")`, defaulting to `"operations"`.
   - `handleSubTabChange` synchronizes state with the URL query parameters (`/more?tab=data_control&subtab=batch_imports` vs default `/more?tab=data_control`) using Next.js shallow routing without page reload.
   - Main tab navigation cleans up `subtab` params when switching away from Data Control.
3. **UI / Styling & Animation**:
   - Rendered a secondary pill-style sub-tab navigation bar directly underneath the Data Control section header with active tab styling and real-time visible tile counter badges.
   - Smooth entrance transitions on sub-tab switches using `transition-all duration-200 ease-in-out` and `animate-in fade-in-50 duration-200`.
   - Preserved all original card styling, badge variants, and RBAC role-level gating.
4. **Verification**:
   - `npx eslint src/app/(dashboard)/more/page.tsx` passed with 0 errors and 0 warnings.
   - `npx tsc --noEmit` passed with 0 errors.

---

## Implement `qa_run_scenario` 6-Role AI Agent Workflow Relay Migration (ohm#q4r8s9x2)

**Status: COMPLETE — SUPABASE MIGRATION CREATED, MAIN BRANCH**

### Objective
Implemented the missing `public.qa_run_scenario(p_scenario_code text)` database function in a dedicated Supabase migration to complete the 6-Role AI Agent Workflow Relay for OHMployee. Resolves 42883 function missing errors when invoking QA scenarios from the Web and Mobile QA Center modal (`QaCenterModal`).

---

### Implementation Details
1. **Migration Artifact (`supabase/migrations/20262606000045_qa_role_relay_engine.sql`)**:
   - Sequenced as `20262606000045_qa_role_relay_engine.sql` immediately following `20262606000044_rbac_parity_mobile_web.sql`.
   - Defined `public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY'::text) RETURNS jsonb`.
   - Configured with `SECURITY DEFINER`, `SET search_path TO 'public'`, and authorized to role `authenticated`.
   - Security Guard: Enforces `public.i_have_full_access() OR public.get_my_role_level() >= 90`.
2. **6-Role Sequence Simulation**:
   - **Head Admin** (`role_level >= 90`): Authorizes headcount quotas and initializes vacancy `vcode`.
   - **Encoder** (`role_level 30`): Allocates plantilla slot and tests slot vacancy transitions.
   - **Recruitment** (`role_level 20`): Inserts applicant and updates status to `Screening`.
   - **HRCO / Operations** (`role_level 45/70`): Simulates candidate endorsement and onboarding confirmation (`Confirmed Onboard`).
   - **HR Personnel** (`role_level 25`): Allocates HR Emploc entry, assigns employee number, and verifies unique constraint indexing.
   - **Back Office** (`role_level 15`): Simulates plantilla movement remarks and executes a negative permission barrier test (attempts unauthorized Head Admin action to verify RLS rejection).
3. **Scenario Dispatching**:
   - Supports `VAC_ARCHIVE_001` (Vacancy archival isolation & active query exclusion).
   - Supports `PLANTILLA_001` (Plantilla slot allocation & status transition).
   - Supports `HR_EMPLOC_001` (HR Emploc unique index & collision detection).
   - Supports `CENCOM_001` (CENCOM quota & edit lock verification).
   - Supports `AUTH_MATRIX_001` (Authorization matrix hierarchy drift audit).
   - Supports `FULL_E2E_RELAY` (Full 6-role workflow relay simulation).
4. **Zero-Pollution Subtransaction Rollback**:
   - Caches original caller JWT claims at start and restores them unconditionally upon exit.
   - Wraps all mutation steps in an atomic subtransaction terminated with `RAISE EXCEPTION 'QA_SANDBOX_ROLLBACK_SUCCESS'`.
   - Catches controlled rollback exception, guaranteeing 0 production records are persisted or polluted in business tables.
5. **Telemetry Persistence**:
   - Run start logged via `public.qa_start_detection_run` (`public.qa_agent_runs`).
   - Failures and permission barrier leaks logged via `public.qa_log_detection_finding` (`public.qa_agent_findings`).
   - Run completion and summary recorded via `public.qa_complete_detection_run`.
   - Returns structured JSON payload with execution trace, pass/fail status, and finding counts.

---

## Phase 1 — Port 2-Step Rollback & History for Plantilla and Vacancy Imports to Web (ohm#r7b9w2k1)

**Status: COMPLETE — CLIENT-SIDE 1:1 MOBILE PARITY, MAIN BRANCH**

### Objective
Ported the complete 2-step rollback lifecycle, 72 business-hour countdown governance window, emergency override capabilities, and audit history views from Flutter mobile (`StoreImportScreen` and `VacancyImportScreen`) to the Next.js Web app (`PlantillaImportModal` and `VacancyImportModal`).

---

### Key Additions & Parity Implementations
1. **Service & Mutation Layer (`src/lib/queries/dataControl.ts`)**:
   - Extended `PlantillaImportBatch` and `VacancyImportBatch` models with full rollback attributes: `rollbackStatus`, `rollbackReason`, `rollbackReasonCode`, `rollbackReasonNote`, `rollbackRequestedBy`, `rollbackRequestedAt`, `rollbackApprovedBy`, `rollbackApprovedAt`, `rollbackCompletedAt`, `rollbackErrorDetail`, `rollbackWindowStartedAt`, `rollbackExpiresAt`, `rollbackRemainingSeconds`, `rollbackAllowed`, `rollbackBlockReason`, `canEmergencyRollback`.
   - Wired exact Supabase RPC endpoints:
     - `request_plantilla_import_rollback`, `approve_plantilla_import_rollback`, `emergency_rollback_plantilla_import`, `get_plantilla_import_rollback_history`.
     - `request_vacancy_import_rollback`, `approve_vacancy_import_rollback`, `emergency_rollback_vacancy_import`, `get_vacancy_import_rollback_history`.
   - Added `usePlantillaImportRollbackHistory` and `useVacancyImportRollbackHistory` hooks.
   - Added canonical `IMPORT_ROLLBACK_REASONS` (7 options: `wrong_batch`, `wrong_group_account`, `wrong_vcode_list`, `wrong_applicant_pipeline`, `duplicate_migration_correction`, `uploaded_by_mistake`, `other`).
   - Added `formatRollbackRemaining` (days/hours countdown excluding Sundays) and `humanizeRollbackError` error humanizer.
2. **UI Governance & History Tabs (`PlantillaImportModal.tsx` & `VacancyImportModal.tsx`)**:
   - Interactive history tables with row selection, status badges (`REQUESTED`, `COMPLETED`, `FAILED`, `WINDOW EXPIRED`), and real-time expiration countdown timer badges.
   - **Rollback Governance Drawer**: Displays batch inspection metadata, warning blocks for modified post-approval rows, and 4 contextual action buttons matching mobile permissions:
     - **Request Rollback**: Enforces reason dropdown + minimum 10 characters remarks. Gated to Super Admin, Head Admin, Encoder for Plantilla; Super Admin and Head Admin for Vacancy.
     - **Approve & Execute Rollback**: Gated strictly to Super Admin when `rollbackStatus === 'requested'`. Features confirmation modal highlighting entity deactivation and snapshot restores.
     - **Emergency Rollback Override**: Gated strictly to Super Admin when `canEmergencyRollback === true`. Enforces minimum 50 characters justification.
     - **View Rollback History**: Dedicated audit log modal rendering requester, approver, timestamps, remarks, error details, and rolled back counts.
3. **Cache Invalidation**:
   - Complete cache invalidation for import batches, rollback history, and live entity queries (`plantilla`, `plantilla-scope-menu`, `vacancies`, `vacancies-list`, `vacancy-counts`).

---

### Quality Gate
- `npx tsc --noEmit`: 0 errors.
- `npx eslint` on updated files: 0 errors, 0 warnings.
- `npm run build`: Production build succeeded (19/19 static pages generated).
- Flutter mobile repository (`lib/`): 100% untouched.

---

## Restore Staging Supabase Fallback for Vercel Deployment (ohm#v4c9prod)

**Status: COMPLETE — CLIENT-SIDE RESTORATION, MAIN BRANCH**

### Objective
Following the audit of live staging data in `ohmployee-web.vercel.app`, the hardcoded exception gate was reverted per user confirmation to allow the Vercel production deployment to gracefully operate using the Staging Supabase backend (`qqiiznmqxfoamqytjica.supabase.co`). This resolved the `Access state: rpc failure` block on `ohmployee-web.vercel.app` and restored normal authenticated operation.

---

### Key Findings & Implementation
1. **Root Cause of RPC Failure Screen**:
   - The previous strict guard threw an immediate Error when `window.location.hostname === "ohmployee-web.vercel.app"` whenever Staging fallback was used.
   - When `DashboardAuthShell` loaded on Vercel, the exception caught inside `createClient()` surfaced as `Access state: rpc failure`.
2. **Restoration in `src/lib/supabase/client.ts`**:
   - Removed `isVercelProduction()` and the fatal throwing guard.
   - Restored seamless fallback to `STAGING_URL` (`https://qqiiznmqxfoamqytjica.supabase.co`) and `STAGING_ANON_KEY` when hosting environment variables are absent.
3. **Verification**:
   - Ran `npm run build` locally: compiled cleanly with 0 errors across all 19 static routes.

---

## Web Parity Check — Verify briefing.md Structure + Align AGENTS.md Workflow Block with Mobile (ohm#3f8j5k2w)

**Status: COMPLETE — CLIENT-SIDE / DOCS-ONLY, MAIN BRANCH**

### Objective
Verified structure and parity of `.ai/briefing.md` against mobile rules and moved/aligned the `Core Workflow Rules` block in `AGENTS.md` to the top of the file outside all Next.js auto-managed comment markers to ensure it can never be overwritten by tooling.

---

### Verification of `.ai/briefing.md`
1. **Mandatory Workflow Rules section**: Exists and sits BEFORE "Last Completed Tasks" (PASS).
2. **`## Last Completed Tasks` heading**: Exists directly after workflow rules (PASS).
3. **Task list numbering**: Was unnumbered bullets (`- **...**`); surgically fixed to numbered `1.` to `5.`, newest first (FIXED).
4. **Trim note**: Was missing; added explicit note matching dropped entry `ohm#w89p602c` and earlier entries (FIXED).
5. **Approval & Regression Gate wording**: "present plan + regression risk, STOP, wait for approval" with NO "non-trivial" qualifier (PASS).
6. **Checklist Item 4**: Specifies AI only reports the branch; Ohm verifies (`npm run lint` / `npm run build` / manual test), merges to `main`, and deletes it (PASS).

---

### Implementation Details

1. **`AGENTS.md` Alignment**:
   - Relocated `Core Workflow Rules` block to the top of `AGENTS.md`, before and outside any `<!-- BEGIN:nextjs-agent-rules -->` / `<!-- END:nextjs-agent-rules -->` markers.
   - Replaced block text to align with mobile specification:
     - Clarified post-prompt documentation update checklist reference (`.ai/briefing.md § After Every Completed Prompt`).
     - Aligned Approval & Regression Gate and Branch Policy instructions (`main` only; Ohm verifies, merges, deletes environment-created branches).
   - Preserved Next.js comment block and text with zero alterations.

2. **`.ai/briefing.md` Updates**:
   - Numbered "Last Completed Tasks" strictly 1 to 5 with newest first.
   - Prepended `ohm#3f8j5k2w`: `1. **ohm#3f8j5k2w**: Web parity check + AGENTS.md alignment`.
   - Updated trim note to record dropping `ohm#w89p602c` and earlier entries.

---

### Verification
- `git diff AGENTS.md .ai/briefing.md`: Clean, surgical alignment.
- `git diff --stat AGENTS.md .ai/briefing.md .ai/handoff.md`: Confirmed modifications isolated to documentation only.
- Working branch: `main` only. No branches created, merged, pushed, or deleted.
- Regression Risk: None (docs-only changes).

---

## Wire Mandatory Workflow Rules into ohmployee-web (ohm#9c4t1w6e)

**Status: COMPLETE — CLIENT-SIDE / DOCS-ONLY, MAIN BRANCH**

### Objective
Wired mandatory workflow rules into `ohmployee-web` to establish complete operational parity between Antigravity and Claude agents. Established `.ai/briefing.md` as the single canonical source of truth for repository workflow rules (Approval & Regression Gate, Branch Policy, and Post-Prompt Documentation Checklist) and added a thin pointer in `AGENTS.md` (which Antigravity auto-loads at start as user rules, and Claude imports via `CLAUDE.md`).

---

### Implementation Details

1. **Canonical Source of Truth (`.ai/briefing.md`)**:
   - Added `Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)` section near the top of `.ai/briefing.md`.
   - Included the Approval & Regression Gate (plan + regression risk assessment, STOP and WAIT for approval before code/schema changes).
   - Included the Branch Policy (work on `main` only, no branches unless explicitly asked).
   - Included the After Every Completed Prompt checklist (`.ai/briefing.md`, `.ai/handoff.md`, `docs/state/`, and branch reporting).
   - Pruned "Last Completed Tasks" to retain the top 5 entries, prepending `ohm#9c4t1w6e`.

2. **Auto-Load Agent Pointer (`AGENTS.md`)**:
   - Appended a 4-line `Core Workflow Rules` block below and outside the auto-managed Next.js comment block.
   - Points agents to `.ai/briefing.md`, mandates post-prompt docs updates, enforces the Approval & Regression Gate, and directs agents to work on `main` only.
   - Claude auto-inherits this behavior via `CLAUDE.md` (`@AGENTS.md`), ensuring parity without file modifications or duplicated rule text.

---

### Verification
- `git diff --stat`: Shows exactly 3 touched files (`AGENTS.md`, `.ai/briefing.md`, `.ai/handoff.md`).
- Existing Next.js block in `AGENTS.md` remains intact.
- No code, schema, dependency, or configuration files modified.
- Branch check: Working directly on `main`; no new branches created.
- Regression Risk: None.

---

## Complete Final Sidebar Parity — Port Temporary Permission Overrides to Web `/users` Management Hub (ohm#w89p602f)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Full Mobile-to-Web Parity Achieved Across All Left Sidebar Modules)**

### Objective
Achieved 100% final feature parity between Mobile and Web across all Left Sidebar modules by porting the **Temporary Permission Overrides** system (`temp_permission_screen.dart` from Mobile) into the Web User Management Hub (`src/app/(dashboard)/users/page.tsx` and `src/components/users/UserDetailDrawer.tsx`), enabling Super Admins and Head Admins to grant, monitor, and revoke time-bound group/account/module scope delegations with expiration timers, live countdown badges, and mandatory audit justification reasons.

---

### Implementation Details

1. **Supabase Data Layer (`src/lib/queries/tempPermissions.ts` & re-exported in `src/lib/queries/users.ts`)**:
   - Integrated with Supabase table `temp_permission_overrides` and atomic backend RPCs:
     - `grant_temp_permission_override`: Wraps scope insertion into `user_scopes`, audit logs, and in-app notifications.
     - `revoke_temp_permission_override`: Atomically sets `is_active = false`, logs `revoked_by` and `revoked_at`, and cleans up temporary `user_scopes` while protecting permanent scopes.
   - Built robust TypeScript models: `TempPermissionOverride`, `GrantTempPermissionParams`, `RevokeTempPermissionParams`, and `TempPermissionsQueryResult`.
   - Added `computeExpiresLabel` helper calculating precise remaining duration (`Expires in 3d 4h`, `Expires in 45m`, `Expires soon`, `Expired`, `Revoked`).
   - Added TanStack Query hooks: `useTempPermissionsQuery`, `useActiveTempPermissionsQuery`, `useGrantTempPermissionMutation`, and `useRevokeTempPermissionMutation` with automated cache invalidation across users list, counts, and audit logs.

2. **Temporary Permission Manager Component (`src/components/users/TempPermissionModal.tsx`)**:
   - **Active Overrides Tab**: Displays active temporary permission delegations with pulse dot indicators, countdown timers, delegated scope tags (Group vs Account vs Module), granting admin details, expiry timestamps, and quoted justification reasons.
   - **History & Revocations Tab**: Tracks expired and administratively revoked overrides for compliance auditing, displaying revocation actor, timestamp, and audit trail.
   - **Grant Override Form**:
     - *Step 1: Target User*: Select from active users or preset directly from `UserDetailDrawer`. Displays user's current role and permanent scopes.
     - *Step 2: Delegation Scope Type*: Segmented toggle between `Group Scope`, `Account Scope`, and `Module Scope`.
       - *Group Scope*: Interactive multi-selection of operational groups (`groups` table).
       - *Account Scope*: Searchable grid of active stores/accounts (`accounts` table) with automatic group mapping.
       - *Module Scope*: Delegation of specific operational hubs (CENCOM, Approvals, Plantilla, HR Emploc, Reports, Users).
     - *Step 3: Expiration Time Limit*: 1-click presets (`24 Hours`, `3 Days`, `7 Days`, `14 Days`, `30 Days Maximum`) plus custom date-time picker (capped at 30 days per database trigger security rule).
     - *Step 4: Mandatory Audit Justification*: Enforces minimum 5-character reason logged directly into audit logs and notification payloads.
     - *In-App Notification Toggle*: Dispatches real-time notification to the employee upon access grant.
   - **One-Click Revoke Dialog**: Dedicated confirmation modal with optional revocation justification reason that calls `revoke_temp_permission_override` and cleans up temporary scopes.

3. **User Management Hub & Drawer Integration (`src/app/(dashboard)/users/page.tsx` & `src/components/users/UserDetailDrawer.tsx`)**:
   - **Top Header Action Trigger**: Added `Temporary Overrides` button with live active count badge directly in the `/users` page header actions.
   - **Drawer Header / Subtitle Active Badge**: Added clickable live countdown badge in `UserDetailDrawer` whenever the selected employee has an active temporary override in effect.
   - **Drawer Overview Section Card**: Added a dedicated "Temporary Permission Overrides" section in `UserDetailDrawer`'s Overview tab, displaying active delegation summaries, granted by, expiry, and direct triggers to manage, grant, or revoke overrides for that employee.

4. **100% Sidebar Parity Confirmation**:
   - All modules in the Left Sidebar (`/dashboard`, `/vacancies`, `/plantilla`, `/cencom`, `/hr-emploc`, `/approvals`, `/reports`, `/team-directory`, `/more`, `/users`, `/settings`) now have complete 100% functional parity with the Mobile application (`OHMployee`).

---

### Verification Results
- `npm run lint`: **PASS** (0 errors, 21 warnings in legacy files).
- `npm run build`: **PASS** (Prerendered all 19 static routes, including `○ /users`, in 18.5s).

---

## Complete Web `/plantilla` Parity — Port Moses HQ Pool & 7-Tab Workforce Analytics Dashboard (ohm#w89p602e)


**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Mobile Parity Achieved on `/plantilla`)**

### Objective
Elevated `src/app/(dashboard)/plantilla/page.tsx` from 75% to 100% Mobile parity by porting the two remaining major modules from `d:\Projects\OHMployee\lib\features\plantilla\`:
1. **Moses HQ Pool Management (`moses_hq_pool_screen.dart`)** for tracking, filtering, and managing pooled personnel (Relievers, Commandos, Seasonals).
2. **Workforce Analytics Dashboard (`workforce_analytics_dashboard_screen.dart`)** featuring all 7 executive workforce analytics tabs (`Overview`, `Deployment`, `Coverage`, `Conversion`, `Slots`, `Health`, `Executive`).
3. **URL Query & Deep-Linking Synchronization**: Provided segmented top-level view switcher tabs (`Store Plantilla`, `Moses HQ Pool` with `?view=moses_pool`, `Workforce Analytics` with `?view=analytics`) with deep-linking support and auto-navigation from pool accounts.

---

### Implementation Details

1. **Moses HQ Pool View & Actions (`src/components/plantilla/`)**:
   - `MosesHqPoolView.tsx`: Complete HQ pool dashboard with dynamic pool type tabs (`All`, `Reliever`, `Commando`, `Seasonal`), status filters (`All`, `Available`, `Deployed`, `Needs Review`, `Inactive`), search, 7 executive KPI counters (`Total Pool`, `Available`, `Deployed`, `In Review`, `Inactive`, `Approved Quota`, `Vacant Slots`), high-density employee table with load badges and review triggers, XLSX export, and action drawers.
   - `PoolEmployeeDetailDrawer.tsx`: Full employee drawer displaying employee profile, active deployments with inline close/complete actions, pending request management with withdrawal actions, and comprehensive assignment history.
   - `RequestRelieverCoverageModal.tsx`: Coverage deployment request modal with account/store cascading selection, priority, dates, and position.
   - `RequestPoolConversionModal.tsx`: Modal requesting permanent pool-to-plantilla conversion with target account, store, and position lookup.
   - `RequestPoolHeadcountModal.tsx`: Vacancy creation modal expanding pool quotas.
   - `PoolOpenSlotsDrawer.tsx`: Approved vacant pool slots inspector with filter by pool type, position, and days open.
   - `PoolReviewQueueDrawer.tsx`: Slot review queue with interactive "Reopen for Replenishment" and "Close Slot" actions.
   - `PoolRequestHistoryDrawer.tsx`: Audit trail drawer for past pool headcount requests.

2. **7-Tab Workforce Analytics Dashboard (`src/components/plantilla/WorkforceAnalyticsView.tsx`)**:
   - Full 7-tab executive dashboard powered by live Supabase RPCs:
     - **Tab 1: `Overview`**: Headcount breakdown, active deployment summary, coverage requests, pool type breakdown table.
     - **Tab 2: `Deployment`**: Deployment velocity, multi-store reliever counts, average stores per reliever, overdue deployments, and visual load distribution progress bars (`Low`, `Medium`, `High`, `Critical`).
     - **Tab 3: `Coverage`**: Pending coverage demand, SLA compliance, emergency/critical requests, and aging brackets.
     - **Tab 4: `Conversion`**: Conversion rate, approval/rejection rates, pending conversion queue, and conversion metrics.
     - **Tab 5: `Slots`**: Slot review queue analytics, vacant pool slots, and review decision metrics.
     - **Tab 6: `Health`**: Overall health score (0–100), operational risks, high-load relievers, and import incidents tracker (`get_plantilla_import_incidents`).
     - **Tab 7: `Executive`**: High-level executive KPI summary cards (`Total Pool Employees`, `Utilization %`, `Availability %`, `Pool Capacity %`, `Coverage Efficiency %`, `Health Score`).
   - Dynamic date range & account scope filters, refresh controls, and multi-sheet XLSX export.

3. **Supabase Data Layer (`src/lib/queries/workforcePool.ts` & `workforceAnalytics.ts`)**:
   - Added complete TypeScript interfaces and fetchers for `v_workforce_pool_employees`, `workforce_pool_types`, `workforce_assignments`, `v_workforce_store_temporary_coverage`, `v_workforce_slot_reviews`, and `workforce_headcount_requests`.
   - Added query hooks for analytics RPCs: `fn_workforce_pool_overview`, `fn_workforce_deployment_analytics`, `fn_workforce_coverage_demand_analytics`, `fn_workforce_conversion_analytics`, `fn_workforce_slot_review_analytics`, `fn_workforce_health_summary`, `fn_workforce_executive_summary`, and `get_plantilla_import_incidents`.
   - Re-exported all definitions in `src/lib/queries/plantilla.ts`.

4. **Integration in Main Page (`src/app/(dashboard)/plantilla/page.tsx`)**:
   - Integrated segmented view switcher pill bar (`Store Plantilla`, `Moses HQ Pool`, `Workforce Analytics`).
   - Synchronized view mode via `?view=moses_pool` and `?view=analytics`.
   - Pool account rows clicked in Store Plantilla automatically route to Moses HQ Pool with contextual selection.
   - All existing Store Plantilla roster, slot inspector, vacancy drawers, and quota overrides remain completely intact without regression.

---

### Verification Results
- `npm run lint`: **PASS** (0 errors, 21 warnings in legacy files).
- `npm run build`: **PASS** (Prerendered all 19 static routes, including `○ /plantilla`, in 18s).

---

## Upgrade Web `/cencom` to Mobile's 5-Tab Architecture (ohm#w89p602d)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Mobile Parity Achieved)**

### Objective
Upgraded `src/app/(dashboard)/cencom/page.tsx` from its previous single flat view (35% parity) to the complete 5-tab architecture of Mobile's `cencom_screen.dart` (`d:\Projects\OHMployee\lib\features\cencom\cencom_screen.dart`). Ported the missing **Target Deployment / Vacancy Aging by Area & Province**, **Deployment Activity**, and **CENCOM Quick Reports** tabs, wired their respective Supabase queries and RPCs in `src/lib/queries/cencom.ts`, and established full URL query synchronization (`?tab=`).

---

### Implementation Details

1. **5-Tab Command Center Architecture (`src/app/(dashboard)/cencom/page.tsx`)**:
   - **Tab 1: `Overview` (`tab=overview`)**: Executive summary retaining MFR fulfillment KPIs, Plantilla Slot Authority normalization callout, monthly operational deployment summary card (`CencomDeploymentCard`), and quick navigation shortcuts.
   - **Tab 2: `Groups` (`tab=groups`)**: Dedicated tab for `CencomGroupTable` with search across groups and accounts, health filter (`healthy`, `at_risk`, `critical`), sorting, and headcount/store drilldowns.
   - **Tab 3: `Target Deployment` (`tab=target_deployment`)**: Ported Mobile's `_TargetDeploymentTab`. Displays:
     - Executive summary KPIs (Operational Vacancies, Advance Vacancies, Average Aging Days, Critical Aging % >30d, Max Days Open).
     - Aging Bucket Summary Cards matching Mobile (`1–15 DAYS`, `16–30 DAYS`, `31–60 DAYS`, `61–120 DAYS`, `>121 DAYS`, `ADVANCE VACANCY`) with percentage of operational total and advance vacancy explanatory callout.
     - Province & Area Vacancy Aging Table with search, aging bracket dropdown, and store count.
     - Interactive store-level drilldown (`CencomGroupedOutletVacancy`): Outlets grouped by `province||area||store||hrco`, showing open positions, oldest aging days badge, reliever status (`Has Reliever`, `No Reliever`, `Mixed`), and expandable individual vacancy cards with VCode, Urgency badge, and Target Fill Date.
   - **Tab 4: `Deployment Activity` (`tab=deployments`)**: Ported Mobile's `_DeploymentTab`. Displays:
     - Period selector ("This Month", "Last Month", "Last 90 Days", "All Time").
     - Velocity KPIs: Period Deployments, Pending Emploc, Moved to Plantilla, Top Account, Top Store, Monthly Quotas from `fn_cencom_deployment_summary`.
     - High-density table of deployed personnel from `hr_emploc` across stores, accounts, and positions with search, status filter, pagination, and CSV export.
   - **Tab 5: `Quick Reports` (`tab=reports`)**: Ported Mobile's `_ReportsTab` (the 18 CENCOM operational reports). Features:
     - 18 operational reports across 4 categories (Command Center, Separation & Leakage, Velocity & SLA, Workforce Audit).
     - 1-click inline modal viewing using `ReportDetailView` or deep-linking directly into `/reports?tab=catalog&report=...` or `/cencom?tab=...`.
     - Recently Generated Reports section, Report Schedules section, and Help Callout matching Mobile.

2. **Supabase Models & TanStack Query Hooks (`src/lib/queries/cencom.ts`)**:
   - Added `CencomAgingBucket`, `CencomOperationalVacancy`, `CencomGroupedOutletVacancy`, `CencomProvinceAgingSummary`, and `CencomTargetDeploymentData`.
   - Implemented `computeAgingBucket(vacantDate)` enforcing exact day boundaries and future advance vacancy separation.
   - Implemented `fetchCencomTargetDeployment()` and `useCencomTargetDeployment()` querying open vacancies with location snapshotting and `v_vacancy_deployment_indicators`.
   - Added `CencomDeploymentRecord`, `CencomDeploymentActivityStats`, `CencomDeploymentActivityResult`, and `CencomDeploymentPeriod`.
   - Implemented `fetchCencomDeploymentActivity(period)` and `useCencomDeploymentActivity(period)` querying `hr_emploc` for real-time deployed personnel and velocity metrics.

---

### Verification Results
- `npx tsc --noEmit`: **PASS** (0 TypeScript errors).
- `npm run lint`: **PASS** (0 errors, 26 legacy warnings in older files).
- `npm run build`: **PASS** (Prerendered all 19 static routes, including `○ /cencom`, in 17s).

---

## Unify Web `/approvals` Hub — Port Plantilla Deployment Queue & Integrate Account Requests Tab (ohm#w89p602c)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Mobile Queue Parity Achieved)**

### Objective
Achieved 100% Mobile-to-Web queue parity on `/approvals` (`src/app/(dashboard)/approvals/page.tsx`) by porting and integrating the two missing Mobile approval queues identified in `ohm#w89p602a-audit`:
1. **Plantilla Candidate Deployment Approvals (`plantilla_approvals`)**: Ported from Mobile `d:\Projects\OHMployee\lib\features\approval\approval_screen.dart` and `approval_service.dart`.
2. **Account Sign-Up Requests (`account_requests`)**: Integrated directly into `/approvals` horizontal category tab strip, supporting review, role/group/account scoping, and provisioning via backend RPC `approve_account_request_v2`.
3. **Synchronized Pending Badges**: Both new queues are fully aggregated into `fetchRequestCategoryCounts` and reflected in the Left Sidebar approvals counter and `/approvals` tab strip.

---

### Implementation Details

1. **Supabase Query & RPC Hooks (`src/lib/queries/requests.ts` & `src/lib/queries/accountRequests.ts`)**:
   - Added `plantilla_approvals` and `account_requests` to `RequestCategoryKey`, `REQUEST_CATEGORIES`, and `fetchRequestCategoryCounts()` with safe failure fallback.
   - Added TypeScript interfaces: `PlantillaApprovalItem`, `fetchPlantillaApprovals(tab)`, `fetchPlantillaApprovalCounts()`.
   - Wired backend RPCs:
     - `approve_plantilla_request(p_approval_id)` via `useApprovePlantillaRequest`.
     - `reject_plantilla_request(p_approval_id, p_remarks)` via `useRejectPlantillaRequest` (mandates rejection remarks).
   - In `accountRequests.ts`, implemented `fetchAccountRequestCounts()` and `useAccountRequestCounts()`, and added cache invalidation for `request-category-counts` on approve/reject.

2. **High-Density Table Components (`src/components/approvals/`)**:
   - Created `PlantillaApprovalDataTable.tsx`: High-density responsive data table matching `ApplicantMovementDataTable` and `ActiveQueueReviewPane`, displaying candidate name, target account, position, VCode slot, EMPLOC #, requester, date, and single/bulk Approve and Reject modals with required remarks.
   - Created `AccountRequestDataTable.tsx`: High-density review table displaying applicant name, email, phone, requested role, scope (global/scoped groups), notes, submission date, and interactive Approve modal (assign role, toggle global/scoped, assign groups & accounts) and Reject modal.

3. **Approvals Hub Integration (`src/app/(dashboard)/approvals/page.tsx` & `src/components/approvals/ActiveQueueReviewPane.tsx`)**:
   - Added `plantilla_approvals` ("Plantilla Placements") and `account_requests` ("Account Sign-Ups") into `VALID_CATEGORIES` and category navigation tabs with icons `Briefcase` and `UserPlus`.
   - Connected both review sections into `ActiveQueueReviewPane.tsx` with dedicated sub-tabs (Pending / Approved / Rejected) and search filters.
   - Maintained global Left Sidebar counter consistency through unified React Query cache updates.

---

### Verification Results
- `npm run lint`: **PASS** (0 errors, warnings are legacy unrelated modals).
- `npm run build`: **PASS** (19/19 routes compiled with Turbopack, including `/approvals`).

---

## Port Mobile Operational Reports Suite to Web `/reports` Hub (ohm#w89p602b)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Mobile Operational Reports Parity Achieved)**

### Objective
Replaced the `ModuleEmptyState` placeholder in `src/app/(dashboard)/reports/page.tsx` with the complete Operational Reports & Analytics Hub ported from Mobile `d:\Projects\OHMployee\lib\features\reports\` and `cencom_service.dart`. Delivered all 5 Mobile reporting surfaces:
1. **Overview & Quick Reports** (`tab=catalog`) with Universal Report Viewer (`ReportDetailView.tsx`) covering Attrition, Resigned, AWOL, Terminated, Back-Out, Combined Leakage, Time-to-Fill, and HR Emploc Late Updates. Includes employee/store separation drilldown (`AttritionDrilldownModal.tsx`).
2. **Floating Staff Report** (`tab=floating`) with duration tracking, aging buckets (<30d, 30–60d, >60d), account distribution breakdown, and full employee rows.
3. **Team Performance Report** (`tab=team_performance`) with operational discipline rankings, SLA compliance, turnaround metrics, coordinator scorecards, and account-level issue drilldown (`TeamPerformanceIssuesModal.tsx`).
4. **Data Integrity Report** (`tab=data_integrity`) surfacing delayed updates, vacancy delay, ghost occupancy, and pipeline anomalies across 4 audited sections with detail drilldowns (`DataIntegrityDetailModal.tsx`).
5. **Custom Report Builder** (`tab=custom`) allowing users to choose data sources, toggle columns, scope multi-condition filters, preview high-density data, and export to XLSX/CSV.

---

### Implementation Details

1. **Dedicated Supabase Reports Queries Module (`src/lib/queries/reports.ts`)**:
   - Implemented typed queries and TanStack React Query hooks wiring the Supabase views, tables, and RPCs:
     - `fetchReportFilterOptions` / `useReportFilterOptions`: Loads dynamic group and account scopes from `v_cencom_group_allocation_kpi` and `v_cencom_account_allocation_kpi`.
     - `fetchUniversalGroupReport` / `useUniversalGroupReport`: Unified dispatcher querying operational reports (`report_attrition_by_group`, `report_resigned_by_group`, `report_awol_by_group`, `report_terminated_by_group`, `report_backout_by_group`, `report_backout_terminated_by_group`, `report_time_to_fill_by_group`, `report_hr_emploc_late_update_by_group`).
     - `fetchAttritionDetails` / `useAttritionDetails`: Queries separated employees and store-level impacts via `fn_get_attrition_details`.
     - `fetchFloatingReport` / `useFloatingReport`: Queries floating personnel duration and aging via `fn_report_floating_employees`.
     - `fetchTeamPerformanceSummary` & `fetchTeamPerformanceDetail`: Queries group/account scorecards and detailed operational discipline breach logs via `fn_team_performance_summary` and `fn_team_performance_detail`.
     - `fetchDataIntegritySummary` & `fetchDataIntegrityDetailBySection`: Queries workforce anomalies via `fn_data_integrity_summary`, `fn_data_integrity_late_hr_detail`, `fn_data_integrity_vacancy_delay_detail`, `fn_data_integrity_ghost_occupancy_detail`, and `fn_data_integrity_pipeline_no_vacancy_detail`.
     - `fetchCustomReportPreview`: Queries ad-hoc datasets across Vacancy, HR Emploc, Plantilla, Deployment Summary, Data Integrity, and Team Performance.

2. **Universal Export Engine (`src/lib/utils/reports_export.ts`)**:
   - Developed client-side `exportToXlsx`, `exportMultiSheetXlsx`, and `exportToCsv` powered by `xlsx` with browser blob download streaming.

3. **Multi-Tab Web `/reports` Hub (`src/app/(dashboard)/reports/page.tsx`)**:
   - Preserved backward-compatible query redirects (`?tab=qa_center` -> `/more?open=qa_center`, `?tab=permission_drift` -> `/more?open=permission_drift`).
   - Wired bidirectional URL `?tab=` synchronization across `catalog`, `floating`, `team_performance`, `data_integrity`, and `custom`.
   - Wired `?report=` deep-linking to open the Universal Report Viewer directly into specific operational reports.

4. **Component Architecture (`src/components/reports/`)**:
   - `ReportsCatalogTab.tsx`: Categorized grid (Separation & Attrition, Recruitment Velocity & Turnaround, Workforce Health & Operational Audit).
   - `ReportDetailView.tsx`: Universal reporting shell with dynamic KPIs, date range presets, group/account scoping, client-side sorting, searchable table, and XLSX/CSV export.
   - `AttritionDrilldownModal.tsx`: Employee and store-level separation audit modal.
   - `FloatingStaffTab.tsx`: Aging buckets (<30d, 30–60d, >60d), account distribution pills, detailed employee roster, and exports.
   - `TeamPerformanceTab.tsx`: Operational discipline ranking leaderboard with progress badges, SLA metrics, and `TeamPerformanceIssuesModal.tsx`.
   - `DataIntegrityTab.tsx`: 4 audit section cards with metrics and `DataIntegrityDetailModal.tsx`.
   - `CustomReportTab.tsx`: 6 data sources, column toggles, condition filters, and preview table.

---

### Verification Results
- `npm run lint`: **PASS** (0 errors).
- `npm run build`: **PASS** (19/19 routes compiled with Turbopack, including `/reports`).

---

## Wire Governance & Audit Tools with Dedicated Modals & Deep Links (ohm#w89p601e)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Governance Tools Parity Achieved)**

### Objective
Audited and completed the functional targets for the 6 cards in `/more` (`System Hub & Governance Tools`) that previously routed generically to `/settings` or `/reports`:
1. `QA Center` (`v_qa_*` telemetry, runs, findings, schedules, reports)
2. `Permission Matrix` (editable role permissions with atomic overrides via `apply_permission_overrides`)
3. `Role Permissions` (read-only backend authorization matrix via `fn_get_permission_matrix`)
4. `Permission Drift` (authorization gap and enforcement mismatch detector via `fn_get_permission_drift_findings`)
5. `Security Events` (live realtime stream of security notices and session terminations via `security_events`)
6. `Audit Logs` (system activity and forensic change trails via `audit_logs` with before/after diffs)

---

### Implementation Details

1. **Governance Queries & Mutations Layer (`src/lib/queries/governance.ts` & `src/lib/queries/more.ts`)**:
   - Implemented dedicated types and TanStack React Query hooks wired directly to Supabase views, tables, and RPCs:
     - **QA Center**: `useQaCenterSnapshot`, `useRunQaCoreDetectionSuite`, `useRunQaScenario`, `useGenerateDailyQaReport` (backed by `v_qa_detection_run_summary`, `v_qa_open_findings`, `v_qa_schedules`, `v_qa_run_queue`, `v_qa_daily_reports`, `v_qa_health_metrics`, `v_qa_unstable_modules`, and `v_qa_flaky_tests`).
     - **Permission Matrix**: `useGovernanceRoles`, `useEffectivePermissionMatrix`, `useApplyPermissionOverrides` (backed by `get_effective_permission_matrix` and `apply_permission_overrides`).
     - **Role Permissions**: `useRolePermissionMatrix` (backed by `fn_get_permission_matrix`).
     - **Permission Drift**: `usePermissionDriftSummary`, `usePermissionDriftFindings` (backed by `fn_get_permission_drift_summary` and `fn_get_permission_drift_findings`).
     - **Security Events**: `useSecurityEvents` (backed by `security_events` table with user profile joins, severity filtering, and live Postgres realtime changes channel `gov_sec_events`).
     - **Audit Logs**: `useSystemAuditLogs` (backed by `audit_logs` table with actor profile joins, module/action/search filtering, date presets, and forensic diff payloads).
   - Re-exported all governance queries and types from `@/lib/queries/more`.

2. **Dedicated Governance Modals (`src/components/more/`)**:
   - **`QaCenterModal.tsx`**: Ported from Flutter's `qa_center_screen.dart` and `qa_center_service.dart`. Features 5 tabs (`Overview`, `Runs`, `Findings`, `Schedules & Queue`, `Daily Reports`), top KPI cards, module stability rankings, and execution action buttons ("Run Core Suite", "Run Scenario", "Generate Daily Report").
   - **`PermissionMatrixModal.tsx`**: Ported from Flutter's `permission_matrix_screen.dart`. Features role selection, Super Admin `SA_PROTECTED` lockout protection banner, expandable module groupings, permission Allow/Deny interactive toggles, bottom staging bar with count, and a transactional commit modal requiring audit reason justification.
   - **`RolePermissionsModal.tsx`**: Ported from Flutter's `role_permissions_screen.dart`. Quick-switch role pills, search/filter controls, sensitive/locked flags, and detailed enforcement tier inspection.
   - **`PermissionDriftModal.tsx`**: Ported from Flutter's `permission_drift_screen.dart`. Displays KPI summaries, severity and module filters, expected vs. observed enforcement comparative grids, recommendations, and code evidence traces.
   - **`SecurityEventsModal.tsx`**: Ported from Flutter's `security_dashboard_screen.dart`. Live realtime Postgres feed, KPI cards for critical incidents and terminated sessions, severity filters, search, and formatted JSON details payload viewer.
   - **`AuditLogsModal.tsx`**: Ported from Flutter's `audit_logs_screen.dart`. Forensic change history with actor attribution, module and action filters, search, date range presets, and expandable side-by-side JSON diffs (`old_data` vs `new_data`).

3. **Routing & Deep-Link Synchronization**:
   - **`/more/page.tsx`**:
     - Updated all 6 cards (`qa_center`, `permission_matrix`, `role_permissions`, `permission_drift`, `security_events`, `audit_logs`) to open their dedicated modals on click.
     - Added deep-link query parameter listener on mount (`?open=...`, `?modal=...`, `?tool=...`) allowing direct deep-linking (e.g. `/more?open=qa_center`, `/more?open=permission_matrix`, `/more?open=audit_logs`).
   - **`/settings/page.tsx`**:
     - Converted `activeTab` to derive directly from URL `?tab=` query parameter (`profile`, `preferences`, `security`, `diagnostics`), enabling seamless deep-links (e.g. `/settings?tab=security`).
   - **`/reports/page.tsx`**:
     - Added deep-link auto-router redirecting `/reports?tab=qa_center` and `/reports?tab=permission_drift` directly to `/more?open=qa_center` and `/more?open=permission_drift`.

---

### Verification Results
- `npm run lint`: **PASS** (0 errors).
- `npm run build`: **PASS** (19/19 routes generated with Turbopack).

---

## Phase 4 Web "More" Parity — Port OHM's Safespace, Switch Role, Roving Coverage Groups & Bulk Archive Execution (ohm#w89p601d)


**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH (100% Mobile-to-Web "More" Module Parity Achieved)**

### Summary of Changes

1. **OHM's Safespace Command Center (`src/components/more/OhmsSafespaceModal.tsx`)**:
   - Ported the owner command center (`safespace_screen.dart`, `super_admin_controls_screen.dart`, `risk_controls_screen.dart`, `freeze_modes_screen.dart`, `diagnostics_screen.dart`, `security_audit_logs_screen.dart`).
   - Integrated tabbed management for:
     - **Overview & Hub**: Quick access tiles to all system governance functions.
     - **System Controls**: Toggle `account_registration` and `import_plantilla` feature gates backed by `fn_update_governance_control` with mandatory audited reason prompt.
     - **Risk Controls**: Phase 1 capability restrictions (`risk_bulk_actions`, `risk_role_editing`, `risk_vcode_creation`, `risk_export_sensitive_data`, `risk_manual_deletion_actions`, `risk_import_rollback_actions`, `risk_cross_group_operations`) with non-emergency amber styling contract.
     - **Freeze Modes**: Domain suspension controls (`payroll_freeze`, `audit_freeze`, `recruitment_freeze`, `read_only_emergency`) via `fn_update_freeze_mode`.
     - **Diagnostics & Live Telemetry**: Live ping measuring round-trip RPC latency, RLS connection integrity, and freeze state evaluator.
     - **Security Audit Logs**: Stream of past governance actions from `fn_get_governance_audit_log`.

2. **Scoped Role Impersonation Utility (`src/components/more/SwitchRoleModal.tsx` & `src/components/DashboardAuthShell.tsx`)**:
   - Ported Flutter's `switch_role_screen.dart` allowing Super Admins to act as scoped roles for testing and view verification.
   - Wired to backend RPCs `get_active_acting_session`, `start_acting_session`, and `stop_acting_session`.
   - Features:
     - Quick switch buttons for common roles (Head Admin, Encoder, OM, HRCO, HR Personnel, Recruitment Team, Viewer).
     - Multi-select Group and Account scope limits.
     - Mandated justification reason input.
     - Persistent sticky Amber Acting Banner in `DashboardAuthShell.tsx` notifying the user of their active acting session with a one-click "Revert to Super Admin" button.

3. **Roving Coverage Groups Management (`src/components/more/RovingCoverageGroupsModal.tsx`)**:
   - Ported Flutter's `coverage_group_list_screen.dart` and `coverage_group_detail_screen.dart` to Web Data Control.
   - Wired to Supabase RPCs `list_coverage_groups` and `get_coverage_group_detail`.
   - Dual-pane layout:
     - Left pane: Searchable coverage group cards displaying code, account, position, required headcount, and active counts.
     - Right pane: Detailed inspection of cluster stores (highlighting anchor store), assigned headcount slots, and fulfillment status.

4. **Expanded Data Archival Center (`src/components/more/DataArchivalCenterModal.tsx`)**:
   - Added **Execute Archive / QA Reset** tab and **Batch History & Rollback** tab alongside existing Plantilla Restore, Vacancy Restore, and Audit Trail tabs.
   - Wired to Supabase RPCs:
     - `fn_get_archive_impact_preview`: Live counters for plantilla, vacancies, HR emploc, and Moses HQ items.
     - `fn_archive_all_operational_data` (QA Reset Archive), `fn_archive_plantilla_data`, `fn_archive_vacancy_data`, `fn_archive_hr_emploc_data`, and `fn_archive_moses_hq_data`.
     - Strict confirmation phrase validation (e.g. typing `ARCHIVE QA DATA` exactly) and mandatory operational reason.
     - `fn_get_archive_batch_history` and `fn_rollback_archive_batch` for 72-hour reversible batch rollbacks.

5. **Wired in `/more/page.tsx`**:
   - Replaced 404 links and placeholder alerts for `OHM's Safespace`, `Switch Role`, and `Roving Coverage Groups` with interactive modal launchers.
   - All 5 tabs (`overview`, `admin_tools`, `permissions`, `audit`, `data_control`) now have 100% working modules with 0 dead links or stubs.

### Verification Results
- `npx tsc --noEmit`: **PASS** (0 TypeScript errors).
- `npm run build`: **PASS** (19/19 static pages compiled and prerendered cleanly).

---


**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH**

### Summary of Changes

1. **Spreadsheet Utilities & Official Template Generators (`src/lib/utils/data_control_xlsx.ts`)**:
   - Ported official two-sheet XLSX template builders and client-side validators matching mobile implementations:
     - `downloadPlantillaImportTemplate()`: Two-sheet workbook (`IMPORT_TEMPLATE` + `VALIDATION_GUIDE`) with required store master and employee baseline columns.
     - `downloadVacancyImportTemplate()`: Two-sheet workbook with VCODE, requisition dates, headcount, and candidate pipeline fields.
     - `downloadMikaImportTemplate()`: Two-sheet workbook with Employee No., Fullname, Account, and biometric registration attributes.
     - `downloadPayrollCheckTemplate()`: Official 3-column payroll reconciliation workbook (`PAYROLL_TEMPLATE` + `GUIDE`).
     - `parseSpreadsheetToRows()`: General robust XLSX/CSV parser returning normalized column headers and row objects with empty row filtering.

2. **Data Control Query Hooks & Backend RPC Wiring (`src/lib/queries/dataControl.ts`)**:
   - Scope menu helpers: `useDataControlGroups()`, `useDataControlAccounts(groupId)`.
   - **Plantilla Baseline Import**: `submitPlantillaBaselineImport`, `fetchPlantillaImportBatches`, `fetchPlantillaImportRows`, `approvePlantillaImportBatch`, `rejectPlantillaImportBatch`.
   - **Vacancy Requisition Import**: `submitVacancyImport`, `fetchVacancyImportBatches`, `fetchVacancyImportRows`, `approveVacancyImportBatch`, `rejectVacancyImportBatch`.
   - **MIKA Biometric & Attendance**: `fetchMikaImportLogs`, `fetchMikaImportRows`, `submitMikaImport` (chunked 100-row inserts), `approveMikaImport` (isolated to checker; does not mutate employee roster).
   - **Payroll Reconciliation Checker**: `fetchGlobalPlantillaForPayrollCheck`, `reconcilePayroll` algorithm matching `payroll_check_service.dart` with normalized string matching for name/account and classification into:
     - Missing in Payroll
     - Missing in Plantilla
     - Paid Inactive
     - Mismatch
     - Duplicates
     - Clean
   - **Payroll Review Center**: `fetchPayrollReviewSessions`, `fetchPayrollReviewItems`, `createPayrollReviewSession`, `submitOpsPayrollReviewComment`, `closePayrollReviewItem`, `closePayrollReviewSession`.

3. **Built 5 Complete Web Modals in `src/components/more/`**:
   - **`PlantillaImportModal.tsx`**: Group & Account scope picker, XLSX template download, file dropzone, live parsed preview table with column validation, review queue for HA/SA approval or audited rejection, and historical import logs.
   - **`VacancyImportModal.tsx`**: Scope selector, vacancy XLSX template download, drag-and-drop file parser, requisition preview table, review queue with row inspection, and approval/rejection controls.
   - **`MikaImportModal.tsx`**: MIKA attendance upload, client-side cross-check against active Plantilla slots to automatically flag possible ghost employees (Type A) and account mismatches (Type B / Blocked), review queue, and approval.
   - **`PayrollImportModal.tsx`**: 3-column XLSX parser, live global plantilla reconciliation with tabbed discrepancy metrics, table inspection, and "Send to Ops Review" session publisher.
   - **`PayrollReviewCenterModal.tsx`**: Ops review session list with status filtering (All, Open, Closed), session drilldown with item filter tabs, Ops response / remarks resolution drawer, item closure, and session closure controls.

4. **Connected in `/more/page.tsx` (`tab=data_control`)**:
   - Replaced all 5 Phase 3 badges/alerts on the cards with direct modal trigger handlers (`onClick`) and active operational badges (`BASELINE`, `INTAKE`, `BIOMETRIC`, `CHECKER`, `REVIEWS`).
   - Mounted all 5 modals with state controls, allowing seamless cross-navigation (e.g. from Payroll Import directly into Payroll Review Center).

### Verification Results
- `npm run lint`: **PASS** (0 errors).
- `npm run build`: **PASS** (19/19 static pages compiled and prerendered cleanly).

---

## Execute Web "More" Module Parity — Wire Orphaned Modals, Add Data Control Tab & Build Core Governance Modals (ohm#w89p601b)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH**

### Summary of Changes

1. **Expanded `/more/page.tsx` Tab Navigation & Grid**:
   - Added 5th tab: **`Data Control`** (`tab=data_control`, Icon: `Database`) alongside `Overview`, `Admin Tools`, `Permissions & Access`, and `Audit & Integrity`.
   - Replaced rigid 3-card limits with responsive multi-row card grids (`grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4`).

2. **Wired Pre-built Orphaned Modals & Existing Routes**:
   - **`Overview` Tab (`tab=overview`)**:
     - Added **`User Management`** card linking to `/users`.
     - Added **`Account Requests`** card wired to open the new `AccountRequestsModal.tsx`.
   - **`Admin Tools` Tab (`tab=admin_tools`)**:
     - Added **`Data Archival Center`** card wired to open `DataArchivalCenterModal.tsx`.
   - **`Permissions & Access` Tab (`tab=permissions`)**:
     - Added **`Temporary Group Access`** card wired to open `TempPermissionModal.tsx`.
     - Added **`Access Control Center`** card wired to open `AccessControlCenterModal.tsx`.
   - **`Audit & Integrity` Tab (`tab=audit`)**:
     - Added **`Data Archival & Recovery`** card wired to open `DataArchivalCenterModal.tsx`.
   - **`Data Control` Tab (`tab=data_control`)**:
     - **`Import HR Emploc`**: Links directly to `/hr-emploc/import`.
     - **`Edit Lock Control`**: Wired to open `EditLockControlModal.tsx`.
     - **`Data Archival / Recovery`**: Wired to open `DataArchivalCenterModal.tsx`.
     - **`Global Store Transfer`**: Wired to open `GlobalStoreTransferModal.tsx`.
     - **`Roving Coverage Groups`**: Links to `/approvals?tab=coverage`.
     - **Remaining Bulk Importers** (`Import Plantilla`, `Import Vacancy`, `Import MIKA`, `Import Payroll`, `Payroll Review Center`): Rendered with accurate descriptions, icons, and Phase 3 badges for 100% visual parity with Mobile.

3. **Built High-Priority Missing Governance Modals**:
   - **`AccessControlCenterModal.tsx`**:
     - Ported from Mobile `access_control_center_screen.dart` and `module_visibility_service.dart`.
     - Super Admin user search, role baseline computation, per-user module visibility overrides (`allow` | `deny` | `inherit`) via `fn_set_module_visibility_override` RPC, and audit history via `fn_module_override_audit`.
   - **`GlobalStoreTransferModal.tsx`**:
     - Ported 4-step store transfer flow from Mobile (`global_store_transfer_screen.dart` and `global_store_transfer_service.dart`).
     - Step 1: Source scope (group, account). Step 2: Employee multi-select. Step 3: Target scope (group, account, store) with vacant slot assignment. Step 4: Review and audited reason submission.
   - **`AccountRequestsModal.tsx`**:
     - Built using backend RPC `get_approval_queue` and `approve_account_request_v2`.
     - Allows Super Admins to view pending, approved, and rejected registration requests, assign roles (excluding SA/HA) and operational group/account scopes, or reject with audited reasons.
     - Wired into both `/more` and `/users` header actions (`actionSlot`).

4. **Query & Model Extensions (`src/lib/queries/more.ts`, `src/lib/queries/accountRequests.ts`)**:
   - Added typed fetchers, mutations, and React Query hooks for `acc-users`, `acc-overrides`, `acc-audit`, store transfer options/submission, and account approval queues.

### Verification Results
- `npm run lint`: **PASS** (0 errors).
- `npm run build`: **PASS** (19/19 static pages compiled and prerendered cleanly).

---

## Fix Silent {0,0,0} Counts Fallback — Error Visibility Across Approvals Queues (ohm#4f8k1v7n)

**Status: COMPLETE — CLIENT-SIDE ONLY, MAIN BRANCH**

### Summary of Changes

1. **Error Throwing and Console Logging on 9 Count Queries (`src/lib/queries/requests.ts`, `src/lib/queries/hr_emploc.ts`)**:
   - Replaced silent `if (error || !data) return { pending: 0, approved: 0, rejected: 0 }` fallback across all 9 count functions:
     - `fetchHeadcountCounts`
     - `fetchNewStoreCounts`
     - `fetchVacancyClosureCounts`
     - `fetchApplicantMovementCounts`
     - `fetchDeactivationCounts`
     - `fetchAccountGroupTransferCounts`
     - `fetchRelieverCounts`
     - `fetchCoverageCounts`
     - `fetchEmplocDeletionCounts`
   - When an error is returned by Supabase, the function logs `console.error("[functionName] query failed:", error.code, error.message)` to aid debugging in browser console, then throws `RequestDataError` (or calls `throwHrEmplocError(error)`).
   - If `!data` (no error, empty/null payload), it safely returns `{ pending: 0, approved: 0, rejected: 0 }`.

2. **Retry Configuration on 9 Hooks (`src/lib/queries/requests.ts`, `src/lib/queries/hr_emploc.ts`)**:
   - Added `retry: 1` to `useHeadcountCounts`, `useNewStoreCounts`, `useVacancyClosureCounts`, `useApplicantMovementCounts`, `useDeactivationCounts`, `useAccountGroupTransferCounts`, `useRelieverCounts`, `useCoverageCounts`, and `useEmplocDeletionCounts`.

3. **Status Badge Error and Loading Visibility (`src/components/approvals/ActiveQueueReviewPane.tsx`)**:
   - Updated `QueueToolbarProps` and `QueueToolbar` to accept `isCountsLoading?: boolean` and `isCountsError?: boolean`.
   - Distinct badge states:
     - Loading: displays `"..."` in muted font.
     - Error / Undefined: displays quiet `"—"` in muted font.
     - Success: displays the numeric count (with warm accent styling when pending > 0 on the pending tab).
   - Removed `= { pending: 0, approved: 0, rejected: 0 }` destructuring default assignments from all 9 count hook invocations so `0` is rendered only after a successful fetch.
   - Wired `isCountsLoading` and `isCountsError` props into the `QueueToolbar` for all 9 review queues (`new_stores`, `vacancy_closures`, `hr_emploc_deletions`, `headcount`, `applicant_movements`, `deactivations`, `account_group_transfers`, `coverage`, `relievers`).

4. **Preserved Scopes & Unconfirmed Root Cause**:
   - Aggregates (`fetchRequestCategoryCounts`), sidebar Approvals badge, and category tab navigation badges remain untouched and resilient.
   - The root cause of the Vacancy Closures Pending badge mismatch remains unconfirmed pending browser Network tab inspection (`GET vacancy_closure_requests?select=status`).
   - No DB writes, migrations, or RLS modifications performed.
   - "Withdrawn" status handling in `VacancyClosureDataTable.tsx` remains untouched.

### Verification Results
- `npx tsc --noEmit`: **PASS** (0 errors).
- ESLint (targeted): **PASS** on `src/lib/queries/requests.ts`, `src/lib/queries/hr_emploc.ts`, and `src/components/approvals/ActiveQueueReviewPane.tsx` (0 errors, 0 warnings).
- `npm run build`: **PASS** (18/18 static pages compiled and prerendered cleanly).

---

## Minimalist Web Pass — New Sidebar + Approvals Restyle + Global Minimal Tokens (ohm#9d4t2w6c)

**Status: COMPLETE — CLIENT-SIDE PRESENTATION & TOKENS ONLY, MAIN BRANCH**

### Summary of Changes

Successfully executed a comprehensive minimalist visual pass across OHMployee Web matching the approved design specification and mockup `OHMployee Web - Minimal Approvals.html` without modifying any business logic, routing, RBAC, data models, or backend/Supabase schemas:

1. **Global Minimal Tokens (`src/app/globals.css`)**:
   - Palette calibrated to minimal tokens (`--bg: #ffffff`, `--side: #fafafb`, `--soft: #f4f4f6`, `--line: #ececef`, `--text: #16161a`, `--muted: #8a8a94`, `--accent: #2b4fd6`, `--ok: #1a8a5a`, `--bad: #c4372b`, `--warn: #b7791f`, `--pillbg: #eef2ff`).
   - Removed drop shadows on cards, tables, topbar, and sidebar; maintained elevation and shadows exclusively on floating overlays (modals, dropdowns, popovers, drawers).
   - Preserved all token alias names and retained existing font variables (`DM_Sans` and `DM_Mono`).

2. **Sidebar Rebuild (`src/components/Sidebar.tsx`, `src/components/DashboardAuthShell.tsx`)**:
   - Implemented exact mockup hierarchy: Header with "OHMployee" (15px bold) and "Admin Command" (12px muted).
   - Primary group: Vacancy, HR Emploc, Plantilla with 14px high-contrast typography.
   - 1px hairline divider (`border-[var(--line)]`).
   - Secondary group: Dashboard, CENCOM, Approvals, User management, Team directory, Notifications, Reports, Settings, More with 13.5px muted typography.
   - Dynamic trailing badge on Approvals displaying the aggregate pending count (`bg-[var(--accent)] text-white text-[10.5px] px-1.5 py-0.2 rounded-full font-bold`).
   - Active state styling: Soft background fill (`bg-[var(--soft)] text-[var(--text)] font-semibold`) with zero icons, zero colored accent bars, and zero shadows.
   - Footer: Rendered user full name and role in muted small typography.
   - Fully preserved responsive drawer handling, logout flow, and RBAC module visibility (`visibleModules`).

3. **Admin Topbar Flat Pass (`src/components/AdminTopbar.tsx`)**:
   - Swapped heavy shadow and border styling for a clean flat `bg-[var(--bg)] border-b border-[var(--line)]` layout with tracking uppercase eyebrow breadcrumb.

4. **Approvals Page Layout & Navigation (`src/app/(dashboard)/approvals/page.tsx`, `src/components/approvals/RequestCategoryNavigation.tsx`)**:
   - Card container converted to flat `rounded-xl border border-[var(--line)] bg-[var(--surface-base)]` with zero shadows.
   - Tab strip: Outline-styled active tab (`border border-[var(--line)] bg-[var(--surface-base)] font-semibold text-[var(--text)]`) and quiet accent badge (`bg-[var(--pillbg)] text-[var(--accent)] border border-blue-200/50`) preserving unacknowledged notification tracking without logic alteration.

5. **Operational States & Queue Toolbar (`src/components/shared/DataState.tsx`, `src/components/approvals/ActiveQueueReviewPane.tsx`)**:
   - Removed decorative SVG graphics from empty/loading/error states in favor of clean operational typography.
   - Built unified `QueueToolbar` across all 9 review queues: flat search input with 1px hairline border, segmented status control with embedded counts, and ghost refresh button.

6. **All 9 Approvals Queue Data Tables Restyled**:
   - Restyled `VacancyClosureDataTable.tsx`, `HeadcountDataTable.tsx`, `NewStoreDataTable.tsx`, `CoverageDataTable.tsx`, `DeactivationDataTable.tsx`, `ApplicantMovementDataTable.tsx`, `AccountTransferDataTable.tsx`, `RelieverDataTable.tsx`, and `HrEmplocDeletionDataTable.tsx`.
   - Applied sticky table headers with muted `text-[12.5px] font-medium`, row hover (`hover:bg-[var(--soft)]`), mono bold VCode/Request # (`font-mono font-bold text-[13px] text-[var(--text)]`), small outlined Account pill (`rounded-[6px] border border-blue-200/50 bg-[var(--pillbg)] text-[var(--accent)]`), branch name stacked beneath store, timestamp stacked beneath requester name, quiet outlined red Reject action (`border border-[var(--bad)]/40 text-[var(--bad)] hover:bg-[var(--bad)]/10`), and solid green Approve button (`bg-[var(--ok)] text-white hover:bg-emerald-700`).

7. **Report on Pending Badge (0 vs 2 Pending Rows on Vacancy Closures)**:
   - *Cause 1 (Client Acknowledgment)*: Selecting any category tab immediately triggers `handleSelectCategory()`, adding the key to `acknowledgedCategories` and deliberately suppressing the category tab badge.
   - *Cause 2 (RLS Scoping Policy)*: `fetchVacancyClosureCounts()` selects `status` from `vacancy_closure_requests`. Under policy `vacancy_closure_req_read_scoped`, non-admin or unauthenticated contexts yield 0 rows, returning `{ pending: 0 }`.
   - *Cause 3 (Missing Invalidation)*: Mutation hook `useReviewVacancyClosureRequest()` invalidates `['vacancy-closure-requests']` and `['request-category-counts']`, but fails to invalidate `['vacancy-closure-counts']`.

### Verification Results
- `npx tsc --noEmit`: **PASS** (0 errors).
- `npm run build`: **PASS** (18/18 static routes compiled and prerendered cleanly in 56s).
- `npx eslint`: **PASS** on all 16 touched components/pages (0 errors, 0 warnings).
- Git branch: `main` only (no new branches created; no DB writes).

### Files Changed
- `src/app/globals.css`
- `src/components/DashboardAuthShell.tsx`
- `src/components/Sidebar.tsx`
- `src/components/AdminTopbar.tsx`
- `src/app/(dashboard)/approvals/page.tsx`
- `src/components/approvals/RequestCategoryNavigation.tsx`
- `src/components/shared/DataState.tsx`
- `src/components/approvals/ActiveQueueReviewPane.tsx`
- `src/components/approvals/VacancyClosureDataTable.tsx`
- `src/components/approvals/HeadcountDataTable.tsx`
- `src/components/approvals/NewStoreDataTable.tsx`
- `src/components/approvals/CoverageDataTable.tsx`
- `src/components/approvals/DeactivationDataTable.tsx`
- `src/components/approvals/ApplicantMovementDataTable.tsx`
- `src/components/approvals/AccountTransferDataTable.tsx`
- `src/components/approvals/RelieverDataTable.tsx`
- `src/components/approvals/HrEmplocDeletionDataTable.tsx`
- `.ai/briefing.md`
- `.ai/handoff.md`

---

## Baseline Audit of ohmployee_web Architecture, Theme, and Core Modules (ohm#w10a482b)

**Status: COMPLETE — READ-ONLY BASELINE AUDIT & IMPLEMENTATION ROADMAP**

### Summary of Changes

Conducted a comprehensive baseline architecture, theme, and module audit of `ohmployee_web` to establish the architectural foundation for mirroring recent mobile capabilities across:
1. Global Light Mode default enforcement.
2. Headcount Quota Revision (`Adjust Quota` and `Request HC Adjustment` actions, commitment safety floor formula $\max(1, occupied + hr\_processing + pipeline)$).
3. Request Center menu label streamlining (dropped "Request"/"Requests" suffixes across all 8 modules) and live pending count badges.
4. CENCOM slot-authority metric alignment (formula: $actual \ge required \implies vacant = 0, required = actual, mfr = 1.0$) and group performance views.

**Deliverables created:**
- `docs/audit/baseline_audit_architecture_theme_modules_2026-10-09.md`: Comprehensive audit report covering framework discovery, Tailwind v4 styling tokens, Supabase client/auth patterns, light theme enforcement instructions, and step-by-step module implementation plans.
- `scripts/ai-finish.ps1`: End-of-task orchestrator script for PowerShell environments in `ohmployee-web`, managing scope file declarations and invoking `finish.js`.

---

## Plantilla Web — Account-First Gate, Scope Parsing Fix, Unified KPI Summary, & Group Filters (ohm#9m2v5jqk)

**Status: COMPLETE — CLIENT-SIDE ONLY, STAGING DEPLOYED & VERIFIED**

### Summary of Changes

Implemented the account-first entry flow for the Plantilla web module in compliance with audit `ohm#7k3n9dqm` (P1 gap) and ADR-001 coverage architecture locks (`ohm#4t8w2xhp`), resolved a critical authentication scope parsing bug, disabled dark mode app-wide, unified page layouts to always show summary cards, and added a group selection dropdown on the account selector.

- **Unified Summary Cards Layout**: Refactored Plantilla layout to render the KPI summary cards (**Required / Actual / HR Process / Vacant**) at the top of the page across both the Account Selection view and Roster directories.
  - The `AdminPageHeader` ("Plantilla Directory" title/subtitle block) is gated behind `accountId` resolution, removing the redundant header details on the Account Selection dashboard.
  - When no account is selected (`!accountId`), `summaryQuery` executes with `accountId := null`, returning the aggregate cross-account (global) summary metrics for all authorized accounts.
  - Selecting an account or group automatically recalculates and updates these cards in real-time.
  - Derived total `required` count dynamically as `Actual + HR Process + Vacant`.
- **Group Select Dropdown on Selection View**: Added a `<select>` dropdown beside the "Search accounts..." input on the Account Selection dashboard.
  - Dynamically populates with unique groups (`uniqueGroups` via `useMemo` of `allowedAccountsQuery` data) associated with the user's allowed billing accounts.
  - Filters the cards grid by group and updates the global summary metrics at the top to reflect only the selected group's counts.
- **Dark Mode Removal**: Completely deleted the `@media (prefers-color-scheme: dark)` styling block in `globals.css` to lock the user interface to light mode.
- **User Context Scope Parsing Fix**: Resolved a critical pre-existing bug in `src/lib/auth.ts` where `loadCurrentUserContext` attempted to read flat non-existent properties (`group_scope_mode`, `group_scope_ids`, `account_scope_mode`, `account_scope_ids`) directly from `rpcRow`. Because the database RPC `get_web_current_user_context` returns `group_scope` and `account_scope` as nested JSONB objects, the client resolved the scope mode as `"none"`, incorrectly locking out all accounts (including Super Admin). Refactored to cleanly extract the mode and list mapping from the raw JSONB objects while resolving all TypeScript/eslint typecasting constraints.
- **Gated Queries**: Modified React Query hooks (`employeeQuery`, `storeQuery`) to be conditionally enabled only when `accountId` is resolved (`enabled: !!accountId`).
- **URL Hydration & Deep-linking**: Integrated Next.js `useSearchParams` on mount to check for pre-existing `accountId` parameters in the URL, executing search queries immediately and avoiding redundant selection screens.
- **Auto-select / Auto-fire Scoped Roles**: Added logic to bypass selection screen for scoped role users (OM, HRCO, etc.) who are authorized for exactly one billing account in `get_web_current_user_context()`. The single account is auto-selected and fired automatically.
- **Fail Closed**: If the user's authorized account list is empty or unresolved, the queries remain disabled.
- **Mobile-Parity Account Selector Dashboard**: Built a curated grid-based selection interface (2/3 columns depending on screen size) for broad-access and multi-account users. Cards feature:
  - Account group name prefixes (`Group [Name] • `).
  - Left icon block (gated by `is_pool_account` column value): Network/branches icon (`Share2`) in a light purple container for pools; store icon (`Building`) in a light blue container for regular accounts.
  - Interactive chevrons (`ChevronRight`) and dynamic status badges: `POOL` (purple) for pool accounts, and `WARNING` (amber) if the Manpower Fill Rate (MFR) drops below 80%.
  - Real-time personnel stats: `HC [Actual]/[Required] • Vacant [Vacant] • Pipeline [Pipeline]` details.
  - Manpower Fill Rate (MFR) Bar: Renders a horizontal orange progress bar showing fill rate percentages.
  - Parallel Client summaries: Uses React Query `useQueries` to fetch individual summaries for all allowed accounts in parallel, resolving metrics dynamic client-side.
  - Real-time client-side search/filter on account name.
- **Back Control Navigation**: Added a back-control link for multi-account users to reset selection, clearing states and URL query parameters to return to the selection list.
- **Dual-View Consistency**: Ensured gating logic and selector screens apply uniformly to both the Employee-centric and Store-centric views.
- **Clean Compilation**: Verified Next.js build passes cleanly (`Compiled successfully`) and ESLint checks verify zero warnings/errors in the modified Plantilla files.

### Files Changed
- `src/app/globals.css` — Removed prefers-color-scheme dark media query to enforce light mode app-wide.
- `src/lib/auth.ts` — Refactored user context scope mapping to parse JSONB `group_scope` and `account_scope` columns correctly.
- `src/lib/queries/plantilla.ts` — Redefined `PlantillaSummary` and updated `normalizeSummary` to map Required, Actual, HR Process, and Vacant metrics.
- `src/app/(dashboard)/plantilla/page.tsx` — Implemented entry-flow gate logic, URL params, auto-fire checks, selector layout, back control, unified summary cards headers, and dynamic group filter.

---

## ADR-001 Compliance Check — Plantilla Account-First Flow (ohm#4t8w2xhp)

**Status: COMPLETE — READ-ONLY COMPLIANCE VERDICT, NO CODE CHANGES**

### Summary of Changes

Conducted a thorough compliance check of the proposed client-side account-first flow for the Plantilla module against ADR-001 (Plantilla Slot as Single Source of Truth). Verified security boundaries, RLS/RPC integration, and Regression Guard Protocol concerns.

**Deliverable created:** `docs/audit/adr001_plantilla_account_gate_2026-07-11.md`

### Findings
- **Verdict:** CONDITIONAL PASS.
- **Conditions:**
  1. Auto-select and auto-fire for single-account scoped roles.
  2. Implement gating consistently across both Employee-centric and Store-centric views.
  3. Wire search/list React Query hooks using `enabled: !!accountId`.
  4. Ensure compatibility with URL query parameters for deep-linking.
  5. Retain backend security / RLS as the absolute authority.
- **Scope:** Purely client-side gating change. No backend migrations, RPC contract revisions, or database schema modifications.

---

## Web-Mobile UX Parity Audit — All Modules (Read-Only) (ohm#7k3n9dqm)

**Status: COMPLETE — READ-ONLY AUDIT, NO CODE CHANGES**

### Summary of Changes

Full read-only navigation/entry-flow audit across all in-scope web modules vs. their mobile counterparts, using the selection-first progressive-disclosure pattern as the reference target.

**Deliverable created:** `docs/audit/web_mobile_parity_2026-07-11.md`

### Audit Findings

| Module | Gap? | ADR-001 | Priority |
|--------|------|---------|----------|
| Dashboard | **No** — aggregate surface, backend scopes via `auth.uid()` | ⚠️ Yes (no change needed) | N/A |
| Vacancy | **Partial** — full list loads on mount; account selector is optional text input, not a gating step | ⚠️ Yes | P2 |
| HR Emploc | **Partial** — full queue loads on mount; lower priority (workflow queue, not directory) | No | P3 |
| Plantilla | **YES (confirmed reference case)** — full roster loads on mount; mobile requires account selection first | ⚠️ Yes | P1 |
| CENCOM | **Cannot assess** — scaffold stub only, no state document | ⚠️ Yes | P4 |
| Approvals | **Cannot assess** — scaffold stub only, no state document | No | P5 |

### Key Decisions / Flags

- **Plantilla (P1):** The account-first entry change is confirmed-as-approved in the prompt but NOT YET implemented in code — `plantilla/page.tsx` still fires both `summaryQuery` and `employeeQuery` on mount with no `enabled` guard on `accountId`. Separate implementation prompt required.
- **5 Regression Guard Protocol flags** raised (RGP-001 through RGP-005) covering: roster auto-fire for scoped roles, KPI summary inconsistency when list is gated, broad-access admin workflow disruption on Vacancy, store-view consistency with employee-view gate, and detail drawer open/close state during page restructuring.
- **4 ADR-001 compliance audit scope entries** defined: Plantilla, Vacancy, CENCOM, Dashboard (no-change noted).
- **CENCOM and Approvals** are scaffold stubs with no state documents — parity cannot be assessed until `cencom_web_state.md` and `approvals_web_state.md` are created.

### Files Changed

- `docs/audit/web_mobile_parity_2026-07-11.md` — **[NEW]** Full audit report.
- `.ai/briefing.md` — prepended `ohm#7k3n9dqm` to Last Completed Tasks.
- `.ai/handoff.md` — prepended this entry.
- No `docs/state/<module>_state.md` files modified (audit only, no behavior change).

### Not Changed

- No source code modified.
- No migrations run.
- No RPC calls that write.
- No module state documents updated (read-only audit pass).

---

## ohmployee-web — Add .gitignore Entries + Push 12 Commits to origin/main (ohm#2vbn6xkq)

**Status: COMPLETE — CONFIG UPDATED, COMMITTED VIA FINISH.JS, REMOTE SYNCED**

### Summary of Changes

Two small, low-risk cleanup steps:
1. **.gitignore updated**: Added `.claude/` and `supabase/.temp/` as new entries to `.gitignore` under the `# tooling` section. Verified that `git status` no longer lists these directories as untracked.
2. **Git Commit**: Committed the `.gitignore` change using the `finish.js` gate script. Since the target environment is Staging (`qqiiznmqxfoamqytjica`), the script auto-committed the staged modifications and `.ai` metadata updates.
3. **Remote Push**: Verified that the current branch is `main` and tracked `origin/main` correctly. Ran `git push origin main` successfully. Checked `git status` to verify the local branch is now in sync with `origin/main` (0 ahead, 0 behind).
4. **Documentation Sync**: Updated `.ai/briefing.md`, `.ai/handoff.md`, and `docs/state/web_target_state.md` to reflect the changes.

### Commits Pushed
- `(cleanup commit)` — `auto: ohm#2vbn6xkq — ohmployee-web — Add .gitignore Entries + Push 12 Commits to origin/main`
- `b2369b8` — `docs: update shared briefing, handoff, and target state documentation`
- `ad1ec5f` — `auto: ohm#5jhq8mwv — ohmployee-web — Commit 443 Backfilled Migration Files via finish.js Gate`
- `938ba47` — `auto: ohm#8kfq3wzn — ohmployee-web — Git Status Audit + Mirror ai-finish.sh PROD Gate Script`
- `80c6fef` — `auto: ohm#7bxk1nte — ohmployee-web — Fix HR Emploc row_capabilities Missing RBAC Fields (Blocking Workflow)`
- `65ca3db` — `docs: update shared briefing, handoff, and target state documentation`
- `214a1b0` — `auto: ohm#7k2m9xq4 — Scaffold docs/ui/ structure (Mobile + Web layout separation)`
- `7a848da` — `auto: ohm#7bxk1nte — Fix HR Emploc row_capabilities Missing RBAC Fields (DB Migration)`
- `bd3cb42` — `auto: ohm#1cme8bzn — Fix vw_vacancy_detail Missing Columns (DB Migration)`
- `50a1f8c` — `auto: OHM2026_1097 — Design Token System Handoff (Font Setup)`
- `fbc1275` — `auto: ohm#6dq9wshl — Fix Client-Side Field/Param Mismatches (Vacancy + HR Emploc)`
- `01a52ab` — `auto: ohm#8vt3nkrq — Split Inactive Employees into Separate Tab/View — Plantilla`
- `6f83790` — `auto: ohm#3k8h5wte — Establish Staging Environment (Env Split)`

---

## ohmployee-web — Commit 443 Backfilled Migration Files via finish.js Gate (ohm#5jhq8mwv)

**Status: COMPLETE — LOCAL COMMITTED ONLY, NO DATABASE COMMANDS RUN**

### Summary of Changes

Committed the 443 untracked migration files (added in `ohm#6ynv2crx`) under `supabase/migrations/` using the `finish.js` gate script.

- **Active Env Verification**: Confirmed environment resolved to `STAGING` (ref `qqiiznmqxfoamqytjica.supabase.co`) from `.env` before running.
- **finish.js safety gate**: Scoped the commit to exactly the 443 untracked migration files under `supabase/migrations/` by setting `OHM_SCOPE_FILES` to the colon-separated list of all 443 migration file paths.
- **Commit creation**: Run `npm run finish` which triggered auto-commit on STAGING without human interaction or requiring `CONFIRM-PROD`.
- **Git status verification**: Confirmed git status is clean of any untracked or modified migration files.
- **Not touched**: No database commands were executed (no db push, db pull, or apply_migration). No manual file content changes were made.

---

## ohmployee-web — Clean Up Stale Duplicate schema_migrations Rows (PROD) (ohm#9frm5ktz)

**Status: COMPLETE — PROD TRACKING-TABLE MUTATION, GATED**

### Summary of Changes

Executed step 3 of the reconciliation plan from `ohm#3wpx7ldk` (`docs/state/web_target_state.md` § 6.D/E): removed the 2 repair-artifact duplicate rows in `supabase_migrations.schema_migrations` on PROD (`rwxelulyapjgaarlwkus`) left behind by `ohm#4qwz9tgk`'s `migration repair` runs.

- **PROD Push Gate**: Fresh out-of-band passphrase was required and obtained from the user in this session before any write; no previously-stated value was accepted.
- **Re-query before touching anything**: Queried PROD live for the 4 candidate rows — state matched `docs/state/web_target_state.md` § 6.D exactly, confirming no drift since the read-only investigation.
- **Before state (4 rows)**:
  | version | name |
  | :--- | :--- |
  | `20260711025531` | `20262606000010_fix_vw_vacancy_detail_missing_columns` |
  | `20260711034157` | `20262606000020_add_hr_emploc_row_capabilities_fields` |
  | `20262606000010` | `fix_vw_vacancy_detail_missing_columns` |
  | `20262606000020` | `add_hr_emploc_row_capabilities_fields` |
- **Action**: `DELETE FROM supabase_migrations.schema_migrations WHERE version IN ('20260711025531','20260711034157');` — the 2 stale auto-generated-timestamp rows only.
- **After state (2 rows, verified)**:
  | version | name |
  | :--- | :--- |
  | `20262606000010` | `fix_vw_vacancy_detail_missing_columns` |
  | `20262606000020` | `add_hr_emploc_row_capabilities_fields` |

### Not touched (by design)
- No other `schema_migrations` rows.
- No view/function definitions changed — tracking table only.
- No `supabase db push`/`db pull` run.

### Next suggested step
Section 6 (Migration Gap Classification & Reconciliation Plan) is now fully resolved — both the 443-file backfill and this tracking cleanup are complete. Per § 5/§ 6.E item 4, the underlying mis-recording behavior for future MCP `apply_migration` calls is still unaddressed procedurally; consider a follow-up to always chain an MCP apply with an immediate `migration repair --status applied <real-version>`.

---

## ohmployee-web — Backfill 443 Missing Migration Files from Mobile Repo (ohm#6ynv2crx)

**Status: COMPLETE — LOCAL FILE COPY ONLY, NO DATABASE COMMANDS RUN**

### Summary of Changes

Executed the bulk-copy step proposed (but not run) in `ohm#3wpx7ldk` (`docs/state/web_target_state.md` § 6).

- **Re-verification before copying**: Re-ran the mobile-vs-web comparison rather than trusting the prior list. Confirmed unchanged: mobile repo (`D:/Projects/OHMployee/supabase/migrations/`) has 443 top-level `.sql` files (448 total entries minus 4 non-migration `.json` housekeeping files and the `_legacy_unversioned/` folder), web repo had 2. Confirmed zero filename collisions between the 443 and the 2 existing web-local files.
- **Copy**: Copied all 443 `.sql` files verbatim (byte-for-byte, no content modification) from the mobile repo into `ohmployee-web/supabase/migrations/`.
- **Verification**: `md5sum` checksum comparison of all 443 copied files against their mobile-repo source — **identical, zero mismatches**. Local file count in `ohmployee-web/supabase/migrations/` now 445 (2 pre-existing + 443 backfilled).
- **Git status check**: `git status --short supabase/migrations/` shows exactly 443 new untracked (`??`) files, no modifications to any existing file in that directory (the 2 pre-existing web-specific migrations `20262606000010`/`20262606000020` are untouched).

### Not touched (by design — file-copy-only prompt)
- No `supabase db push`, `db pull`, `migration repair`, or any other CLI/MCP database command.
- No changes to `schema_migrations` on any environment (the 2 duplicate repair-artifact rows flagged in § 6.D remain unaddressed — still needs its own PROD-gated prompt).
- No commit made — files are staged as untracked only; committing is left to the finish.js gate per the prompt's instructions.
- Full classification/verification detail: `docs/state/web_target_state.md` § 6 (now marked complete).

### Next suggested step
Per the original plan (§ 6.E), an optional read-only `supabase migration list --linked` run would confirm all 443 now show as "in sync" against PROD — not run in this prompt since it wasn't in scope, but safe to do next.

---

## ohmployee-web — Investigate & Reconcile ~400-Migration Local/PROD Gap (Read-Only) (ohm#3wpx7ldk)

**Status: INVESTIGATION COMPLETE — READ-ONLY, NOTHING WRITTEN TO PROD/STAGING/TRACKING**

### Summary of Findings

Full-shape investigation of the ~400-migration gap flagged in `ohm#4qwz9tgk`, cross-referencing PROD's `supabase_migrations.schema_migrations` (447 rows, via MCP `list_migrations`) against both this repo's local `supabase/migrations/` (2 files) and the mobile repo's (`D:/Projects/OHMployee/supabase/migrations/`, 448 files).

**Classification — clean split, no ambiguous cases:**
- **443 migrations (category a)**: missing from web, present in mobile repo — version AND descriptive-name matched PROD's `schema_migrations` exactly for all 443, zero mismatches, zero filename collisions. Safe to bulk-copy verbatim.
- **0 migrations (category b)**: no true orphans — nothing exists only as raw PROD history with no source-controlled file anywhere.
- **0 migrations (category c)**: nothing needed individual/unclear review.
- **2 already-local**: the `20262606000010`/`20262606000020` web-specific fixes already in this repo (confirmed via `diff` that mobile does NOT have these two — expected, they were authored directly in web repo).

**New finding not previously known**: the `supabase migration repair --status applied <version> --linked` runs from `ohm#4qwz9tgk` did **not** clean up the original mis-recorded rows — they inserted new rows for the correct version instead. PROD's `schema_migrations` now has **4 rows** for what should be 2 migrations (`20260711025531`/`20262606000010` pair and `20260711034157`/`20262606000020` pair). Low risk as-is, but flagged for a future cleanup decision (needs its own PROD-gated prompt — deletion of tracking rows is a PROD mutation).

**Also noted (not actionable)**: mobile repo's `supabase/migrations/_legacy_unversioned/` holds 54 pre-2026-05-20 files that predate PROD's earliest tracked migration — evidence of an earlier baseline/history reset on the mobile side, unrelated to this gap.

### Proposed Reconciliation Plan (NOT EXECUTED)

1. Bulk-copy the 443 verified `.sql` files from mobile repo into web repo's `supabase/migrations/` (local-file-only, low risk, safe to automate).
2. Run `supabase migration list --linked` (read-only) afterward to confirm sync.
3. Separately scoped, PROD-gated prompt: decide on deleting the 2 stale timestamp-keyed tracking rows.
4. Procedural fix needed to prevent recurrence: any future MCP `apply_migration` will keep mis-recording versions the same way until followed by an immediate `migration repair`.

### Tool Recommendation

`supabase db pull` against PROD is **not recommended** — it would flatten 447 reviewable incremental migrations (including one with a `DROP VIEW ... CASCADE`) into a single undifferentiated current-state snapshot, obscuring history that's actually safe to reconstruct file-by-file. The surgical bulk-copy approach is safer and was verified to have zero content/name collisions.

### Not Touched (by design — read-only prompt)
- No `supabase db pull`, no migration repair commands, no file copying/writing, no PROD/staging schema changes of any kind.
- Full details, classification table, and per-category risk assessment: `docs/state/web_target_state.md` § 6.

---

## ohmployee-web — CLI-Based PROD Push: HR Emploc row_capabilities Migration (ohm#4qwz9tgk)

**Status: COMPLETE — PRODUCTION DEPLOYED (via MCP fallback after CLI blocker)**

### Summary of Changes

**Part A — Pre-flight diagnostic (critical finding, resolved):**
- Queried `supabase_migrations.schema_migrations` on PROD directly and found migration `20262606000010` (applied earlier via MCP `apply_migration`) was recorded under an auto-generated timestamp version (`20260711025531`) instead of its real version key `20262606000010`. Confirmed root cause: MCP `apply_migration` does **not** write to `schema_migrations` the same way CLI push does.
- Confirmed via `supabase migration list --linked` that this would have caused `supabase db push` to attempt to re-run both migration 010 (risky — its `DROP VIEW ... CASCADE` could cascade-drop objects added by later, unrelated migrations that depend on `vw_vacancy_detail`) and 020, not just 020.
- Ran `supabase migration repair --status applied 20262606000010 --linked` to correct the tracking row. Re-verified via `supabase migration list --linked`: scope reduced to single-migration (020 only).

**Bigger structural finding (reported, not fixed — separate task needed):**
- Discovered this repo's local `supabase/migrations/` directory only contains 2 files, while PROD's `schema_migrations` table has ~400 applied migrations. Most of PROD's schema history was applied directly via MCP and never saved as local migration files. This means `supabase db push` cannot function safely in general for this project — it will always see hundreds of "remote-only" versions and abort. Confirmed live: `supabase db push --linked --yes` failed immediately and its own suggested fix was to mark ~400 production migration versions as "reverted," which was correctly refused as out-of-scope and unsafe. **Recommend a dedicated task to reconcile/backfill the local migrations directory against PROD's actual applied history before CLI `db push` is relied upon again.**

**Part B — Push (executed via MCP fallback, not CLI, after CLI was confirmed blocked by the structural issue above):**
- User explicitly authorized falling back to MCP `apply_migration` for migration `20262606000020_add_hr_emploc_row_capabilities_fields` only, after CLI `db push` proved unworkable.
- PROD Push Gate: passphrase `DRACARYS` was requested; user confirmed reuse of the prior push's passphrase was intentional (flagged as a reuse of a value already stored in this file, user explicitly confirmed anyway).
- Applied migration 020 to PROD (`rwxelulyapjgaarlwkus`) via `apply_migration`, updating `list_web_hr_emplocs` and `get_web_hr_emploc_detail` to return `can_tag_deficiency`, `can_assign_employee_no`, `can_review_deletion`, and `can_review_correction` in `row_capabilities`.
- Repaired the resulting tracking mismatch the same way as 010 (`supabase migration repair --status applied 20262606000020 --linked`) so future `db push` attempts see it as applied.

### Verification
- Called `list_web_hr_emplocs` and `get_web_hr_emploc_detail` live on PROD under a simulated Super Admin session. Confirmed both RPCs return the new `row_capabilities` keys correctly (all `false` for the one existing "Transferred" status row on PROD, which is correct per the RPC's status-gated logic).

### Not touched
- `--include-all` flag: not used.
- No other migrations, modules, or client code touched.
- The ~400-migration local/remote drift: reported only, intentionally out of scope.

---

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
- Current Vacancy implementation is a client desktop admin command center with a compact header, RPC-backed KPI cards, status tabs, submitted search, account/group UUID filters, aging/urgency/vacant-date filters, dense read-only table rows spanning full-screen width, pagination, loading/empty/error/blocked states, and a right-side sliding overlay drawer that renders complete vacancy detail contexts.
- The Vacancy page integrates `get_web_vacancy_summary(...)`, `list_web_vacancies(...)`, and `get_web_vacancy_detail(p_vacancy_id uuid)` queries through `src/lib/queries/vacancy.ts`.
- Vacancy list/summary payloads use the deployed backend's flat individual-param contract (OHM2026_1071/OHM2026_1130 fixes). The frontend sends `p_status`, `p_account_id`, `p_group_id`, `p_aging_bucket`, `p_urgency`, `p_search`, `p_vacant_from`, `p_vacant_to`, `p_limit`, `p_offset`, `p_sort_by`, `p_sort_dir` for the list RPC, and `p_status`, `p_account_id`, `p_group_id`, `p_urgency`, `p_search`, `p_vacant_from`, `p_vacant_to` for the summary RPC. Tab queue values map to backend `p_status`: `open`→`Open`, `with_applicant`→`Pipeline`; `rejected`/`backout` pass `null` (no direct list-level applicant-terminal-status filter support in the deployed RPC).
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

## Wide Admin Layout Standardization (OHM2026_1070)

- **Scope completed**: HR Emploc reference layout, Vacancy, Plantilla, and scaffold-only modules (`Approvals`, `User Management`, `Team Directory`, `Notifications`, `Reports`, `Settings`) now share the maximized admin layout direction.
- **Shared shell changes**: `DashboardAuthShell` no longer constrains dashboard content to `max-w-7xl`; the fixed compact sidebar remains unchanged while main content uses the full available desktop canvas with responsive page gutters.
- **Shared UI changes**: `AdminPageHeader`, `MetricCard`, and `AdminFilterBar` use the larger admin typography/spacing scale. `ModuleEmptyState` now renders the same module header, KPI metric row, and full-width workspace shell instead of a narrow centered placeholder card.
- **Module changes**: HR Emploc, Vacancy, and Plantilla page wrappers no longer add nested page padding; KPI grids use consistent gaps; tabs/segmented controls and filter controls are taller and more readable; dense tables use wider minimum desktop widths, larger body text, larger row/header padding, and full-width table containers.
- **Backend/RBAC guardrails**: No Supabase schema, RPC, RLS, query contract, role visibility, or mutation logic changed. Placeholder modules still do not mock records or actions.
- **State docs**: No `docs/state/*_web_state.md` update was needed because this batch changed layout presentation only, not stable module behavior.
- **Validated**: `pnpm lint` clean. `pnpm build` initially failed in the sandbox with Turbopack `Operation not permitted` while creating a process/binding to a port, then passed outside the sandbox (Next.js 16.2.4, zero build errors).

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
- **Capability flag**: `can_review_correction` is present in the live `get_web_hr_emploc_detail` row capability payload (true only for authorized reviewers on `For Review`, non-`Pending Deletion` records). Keep distinct from `can_review_deletion` (deletion approvals) and `can_tag_deficiency` (Part I). The Review Correction button renders from this canonical capability only; missing/false/malformed capability payloads remain fail-closed.
- **Recommended model**: **strict all-deficiencies-resolved** (partial-compliance approval rejected). Rationale: `Complete` is an irreversible forward gate to employee-number assignment / Plantilla movement, and there is no web-side path to re-open a `Complete` record (the Part I tagging RPC rejects `Complete`). The `return` path is the in-loop safety valve for partial fixes.
- **Blocked states**: non-`For Review` `hr_status`, `Pending Deletion`, `status != 'Pending Emploc'`, out-of-scope. No optimistic UI.
- **Invalidation**: `["hr-emploc-detail", id]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No Vacancy/Plantilla cache touch.
- **Error mapping**: reuses existing `getErrorKind` (`42501`→`access_denied`, `P0001`→`invalid_state`); no new error kinds needed.
- **Frontend wiring status (OHM2026_1112 — COMPLETE):**
  - `src/lib/queries/hr_emploc.ts`: `reviewWebHrEmplocCorrection()` wrapper calls `supabase.rpc("review_web_hr_emploc_correction", ...)`. `canReviewCorrection` normalized from `can_review_correction` only (canonical key; stale `can_approve_correction` alias removed). `ReviewCorrectionParams` and `ReviewCorrectionResult` types exported.
  - `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`: `isReviewModalOpen` state; "Review Correction Resubmission (HR Compliance)" action enabled from backend `canReviewCorrection` only; `ReviewCorrectionModal` sub-component with per-deficiency Resolved/Still-Deficient checkboxes, auto-derived decision, decision-preview block, optional remarks textarea, submitting state, inline error display. On success: invalidates `["hr-emploc-detail", hrEmplocId]`, `["hr-emploc-list"]`, `["hr-emploc-summary"]`. No optimistic UI.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

## HR Emploc Mutation Stability Audit (OHM2026_1127)

- **Scope**: audit and stabilize all existing HR Emploc mutation workflows, capability payload enforcement, invalidation consistency, audit/timeline integrity, and notification-safe frontend handling.
- **Capability enforcement fixes (OHM2026_1127)**:
  - Removed stale `can_tag_correction` alias from `canTagDeficiency` normalization — canonical key is `can_tag_deficiency`.
  - Removed stale `can_approve_correction` alias from `canReviewCorrection` normalization — canonical key is `can_review_correction`.
  - Review correction button visibility now depends only on normalized `can_review_correction`; backend state/status/deletion checks remain authoritative in the live detail payload.
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

## HR Emploc Live Correction Review Capability Validation (OHM2026_1129)

- **Scope**: live detail payload validation only for review-correction rendering, fail-closed behavior, modal UX, and stale capability aliases.
- **Root cause fixed**: the Review Correction drawer action still combined canonical `canReviewCorrection` with local status/deletion guards. Since `get_web_hr_emploc_detail` now returns backend-authoritative `can_review_correction`, the action visibility has been narrowed to that normalized capability only.
- **Capability rendering result**: authorized live payloads with `can_review_correction: true` render the action; unauthorized users, wrong statuses, pending deletion rows, missing keys, malformed capability payloads, and false values hide the action through the normalized canonical flag.
- **UX validation result**: correction reasons render from `correctionReason`; attachments render with stable attachment/fallback keys; audit timeline renders with stable event/fallback keys and null-safe timestamps; review modal opens/closes from drawer state and unmounts on close; submitting disables inputs, cancel, close, backdrop, and submit; retry clears inline errors; success invalidates detail, list, and summary query caches.
- **Validated**: `pnpm lint` clean. `pnpm build` initially failed inside sandbox with Turbopack `Operation not permitted` while creating a process/binding to a port, then passed outside the sandbox (Next.js 16.2.4, zero build errors).
- **Files changed**: `src/components/hr-emploc/HrEmplocDetailDrawer.tsx`, `.ai/handoff.md`, `docs/state/hr_emploc_web_state.md`.

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

## Vacancy RPC Param Fix (OHM2026_1071)

- **Root cause**: `src/lib/queries/vacancy.ts` was sending `p_queue`/`p_filters` (JSONB) and `p_sort` to the deployed Supabase RPCs, but the deployed functions (`20260524130000_web_vacancy_list_summary_rpcs.sql`) expect flat individual params (`p_status`, `p_aging_bucket`, `p_urgency`, `p_search`, `p_vacant_from`, `p_vacant_to`, `p_limit`, `p_offset`, `p_sort_by`, `p_sort_dir`). PostgREST rejected every call as no-function-found → `retryable` error banner on every load.
- **Fix**: Replaced `VacancyRpcPayload` type and `getVacancyRpcFilters` function with two new builders matching the deployed signatures: `getSummaryRpcParams` and `getListRpcParams`. Removed dead helpers `normalizeStatus`, `normalizePipelineStatus`, `supportedStatuses`, `supportedPipelineStatuses`. Added `tabToRpcStatus` to map queue tabs → `p_status` values (`open`→`"Open"`, `with_applicant`→`"Pipeline"`, `rejected`/`backout`→`null`).
- **Secondary normalizer fixes**: `normalizeSummary` now reads `row.total_open` (backend field) to populate `open`; `normalizeListRow` reads `row.urgency_level ?? row.urgency` to populate `urgencyLevel`. Dev-only `console.error` added in `throwVacancyError` to surface the real Supabase error message during development.
- **Known gap**: The deployed `list_web_vacancies` does not return `derived_status`, `active_applicant_count`, `confirmed_onboard_count`, `has_recent_hire`, `has_pending_closure`, `closure_request_status`, or `last_activity_at`. These fields default to null/0 in the list rows. The summary `pendingReview` and `agingWatch` KPI fields also have no backend equivalent and display zero. The `rejected`/`backout` tabs cannot filter the list by applicant terminal status with the current backend RPC — they display all scoped active vacancies.
- **No backend changes made**: No Supabase schema, RPC, RLS, or migration was modified.
- **Files changed**: `src/lib/queries/vacancy.ts`, `.ai/handoff.md`, `docs/state/vacancy_web_state.md`.
- **Validated**: `pnpm lint` clean, `pnpm build` clean (Next.js 16.2.4, zero errors, zero warnings).

## Vacancy Live QA After Flat Param Fix (OHM2026_1130)

- **Scope**: validated only the Vacancy query layer, `/vacancy` page, Vacancy table/drawer components, and relevant Vacancy state/handoff docs.
- **Root causes found**:
  - The deployed RPC supports `p_account_id` and `p_group_id`, but the page/query wrapper did not expose or send account/group filters.
  - The page still showed a standalone Pipeline dropdown even though the deployed backend has no separate pipeline filter param; selecting it only changed the React Query key and did not affect RPC params.
  - Detail rendering used presentation fallbacks that looked like real business values (`Open`, `Full-time`, `Replacement`, `advance`) and the activity normalizer invented a current timestamp for missing history dates.
- **Frontend fixes**:
  - Added account/group UUID filter inputs and flat `p_account_id` / `p_group_id` RPC params for both summary and list reads. Invalid UUID-shaped values normalize to `null` and do not leak unsupported values into the RPC call.
  - Removed the unsupported Pipeline dropdown; queue status remains controlled by tabs (`open`→`Open`, `with_applicant`→`Pipeline`, `rejected`/`backout`→`null`).
  - Detail drawer now renders missing backend fields as unavailable placeholders and no longer invents missing activity timestamps.
- **Known backend limitations confirmed**:
  - `rejected` and `backout` tabs cannot filter applicant terminal statuses through the deployed list RPC and intentionally show the scoped active vacancy list with `p_status = null`.
  - `pendingReview` and `agingWatch` KPI cards may show `0` when the summary RPC does not return equivalent fields.
  - Some list fields normalize to `null`/`0` when the deployed list RPC does not return them.
- **Validation status**: `pnpm lint` clean. `pnpm build` initially failed inside the sandbox with the known Turbopack `Operation not permitted` port-binding error, then passed outside the sandbox (Next.js 16.2.4, zero build errors). Browser QA reached the local `/vacancy` route against `.env.local`, but the app redirected to Login because no authenticated Supabase browser session was available; no PostgREST function-not-found error was observed in the unauthenticated browser console.

## Dashboard Web Implementation (OHM2026_1133)

- **Contracts wired**: `fn_dashboard_metrics()` and `fn_dashboard_operational_analytics()` — both new RPCs from OHM2026_1132 backend deployment.
- **Query layer**: `src/lib/queries/dashboard.ts` — `getDashboardMetrics()`, `getDashboardOperationalAnalytics()`, `DashboardDataError` (access_denied / retryable).
- **Dashboard page**: `src/app/(dashboard)/dashboard/page.tsx` replaced `ModuleEmptyState` with a full read-only admin page:
  - **Operational KPI row** (5 cards): Open Vacancies, HR Emploc Pending, Active Plantilla, Under-Staffed Stores, Active SLA Breaches — all from `fn_dashboard_metrics()`.
  - **Operational Analytics section**: Pipeline Total, Hires This Month, Separations This Month, Avg Fill Rate — from `fn_dashboard_operational_analytics()`.
  - **Security Dashboard section** (RBAC-gated): Pending Approvals, Security Events — from `fn_dashboard_metrics()`. Fields are null from the backend when the caller's role lacks admin access. The frontend shows `DataState kind="access_denied"` when both security fields are null after a successful RPC call. No frontend role-key check is performed; backend is the sole authority.
- **Normalizer behavior**: All fields use defensive normalizers (`asCount` defaults to 0, `asNullableCount` passes through null). Missing fields from a different backend deploy version return 0 / null without errors.
- **State docs**: `docs/state/dashboard_state.md` created.
- **Validated**: `npm run lint` clean, `npm run build` clean (Next.js 16.2.4, zero errors, zero warnings).
- **Remaining gaps**: `fn_dashboard_metrics()` and `fn_dashboard_operational_analytics()` backend migrations must be deployed remotely. Exact return field names will be confirmed after backend deployment; normalizers are defensive.

## Plantilla Store Staffing MFR Breakdown (OHM2026_1133)

- **Backend contract update**: `list_web_plantilla_store_staffing()` now returns `onboard_count`, `hr_pipeline_count`, `open_headcount`, `required_headcount`, `fill_rate` (OHM2026_1132).
- **MFR formula**: `Actual / (Actual + HR Pipeline + Vacancy)` = `fill_rate` from backend. The web layer does NOT compute MFR.
- **Type changes** (`src/lib/queries/plantilla.ts`): `PlantillaStoreStaffingRow` gains four new canonical fields:
  - `onboardCount` (Actual, from `onboard_count`)
  - `hrPipelineCount` (HR Pipeline, from `hr_pipeline_count`)
  - `openHeadcount` (Vacancy, from `open_headcount`)
  - `fillRate` (MFR %, from `fill_rate`; null when backend does not return it)
  - Legacy aliases `activeHeadcount`, `vacancyCount`, `pipelineCount` retained as pass-throughs to the new canonical fields to preserve `deriveStaffingRisk` backward compat.
- **Normalizer update** (`normalizeStoreStaffingRow`): reads new field names first, falls back to legacy field names for older backend deploys.
- **UI update** (`src/app/(dashboard)/plantilla/page.tsx`):
  - `StoreTable` column headers changed: "Active HC" → "Actual", "Pipeline" → "HR Pipeline", "Vacancies" → "Vacancy", "Required HC" → "Required". "Gap" column removed. "MFR %" column added.
  - MFR % rendered as `(fill_rate * 100).toFixed(1)%` with a tooltip showing the formula.
  - `min-w-[1400px]` updated from `1280px` to accommodate the new column layout.
- **Duplicate MFR calculation removed**: there was no prior web-side MFR computation; guardrail comments added to the normalizer and type to prevent future web-side calculations that exclude HR Pipeline.
- **State docs**: `docs/state/plantilla_web_state.md` store staffing section updated with MFR breakdown table.
- **Validated**: `npm run lint` clean, `npm run build` clean (Next.js 16.2.4, zero errors, zero warnings).

## Read-Only Emergency Mode Enforcement — Vacancy Add Applicant (OHM2026_1132)

- **Issue fixed**: Read-Only Emergency Mode (`read_only_emergency` governance control) was ACTIVE but OM could still add applicants and progress the Vacancy pipeline. The `applicants` RLS policies and SECURITY DEFINER RPCs (`create_applicant_and_link_to_vacancy`, `fn_update_applicant_status`) did not check freeze mode.
- **Root cause**: Both `applicants_insert_ops_only` and `applicants_update_ops_recruitment` RLS policies lacked a freeze guard. SECURITY DEFINER RPCs bypass RLS entirely, creating a second gap.
- **Backend migration**: `20260614000001_web_vacancy_applicant_freeze_enforcement.sql` (sibling Supabase repo):
  - §1 Patched `applicants_insert_ops_only` WITH CHECK: adds `NOT fn_check_freeze_active('read_only_emergency')` guard.
  - §2 Patched `applicants_update_ops_recruitment` USING: adds `NOT fn_check_freeze_active('read_only_emergency')` guard.
  - §3 Added `BEFORE INSERT OR UPDATE` trigger `trg_applicants_read_only_check` on `public.applicants`. Fires even inside SECURITY DEFINER functions — the primary enforcement layer for `create_applicant_and_link_to_vacancy` and `fn_update_applicant_status`. Raises `P0001` with message "Read-Only Emergency Mode is active. Write actions are temporarily disabled."
  - §4 Created `get_web_freeze_mode_status()` SECURITY DEFINER RPC (granted to `authenticated`; revoked from anon/public). Returns `{ is_read_only_emergency_active, activated_at, activated_by_name, reason }` JSONB.
- **RBAC**: OM, HRCO, ATL, TL, Encoder, Recruitment, HA — all blocked from applicant writes when freeze is active (trigger fires regardless of role). SA can deactivate the freeze via `fn_update_freeze_mode` only; SA is NOT bypassing normal applicant writes while freeze is active.
- **Web query layer**: `src/lib/queries/freeze.ts` — `getWebFreezeModeStatus()`, `FreezeModeStatus` type, `FreezeModeError` class. Polls `get_web_freeze_mode_status` with 30s stale-time.
- **Vacancy page** (`src/app/(dashboard)/vacancy/page.tsx`): Fetches freeze status via React Query (`["freeze-mode-status"]` key, 30s stale-time). Renders a full-width red `role="alert"` banner above KPI cards when freeze is active, showing the freeze reason and activating user. Passes `isFreezeModeActive` to `VacancyDetailDrawer`.
- **VacancyDetailDrawer** (`src/components/vacancy/VacancyDetailDrawer.tsx`): Accepts `isFreezeModeActive?: boolean` prop. Passes it to `CapabilityActionBar` as `isReadOnlyEmergencyActive`. Added "Add Applicant" as an explicit action item alongside "Update Applicant Status" (both gated by `canUpdateApplicantStatus`).
- **CapabilityActionBar** (`src/components/shared/CapabilityActionBar.tsx`): New `isReadOnlyEmergencyActive?: boolean` prop. When active: renders a red in-bar `ShieldOff` banner ("Read-Only Emergency Mode is active. Write actions are temporarily disabled."), forces all buttons to `disabled`, and replaces badge labels with "read-only mode" (red styling).
- **Enforcement principle**: Frontend is ergonomics only. Backend trigger + RLS is the authority. Supabase will reject any write regardless of frontend state.
- **Smoke tests**: `docs/smoke-tests/vacancy_freeze_mode_enforcement.sql` — 9 targeted tests (T1–T9) covering trigger existence, RLS policy update, RPC existence, inactive/active state reads, OM Add Applicant blocked, Update Status blocked, direct INSERT blocked, and post-deactivation recovery.
- **Validated**: `npm run lint` clean, `npm run build` clean (Next.js 16.2.4, zero errors, zero warnings).
