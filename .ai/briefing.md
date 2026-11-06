# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.
*Standing UI Standard Loop Override:* The UI Standard loop (`ohm#l0u8s2d9` onward) runs WITHOUT an approval gate. The loop pauses only on the stop conditions in `docs/architecture/ui-standard-briefing.md` section 10 or when verification fails. This overrides the generic "stop and wait" rule for this project only. Do not ask for approval again unless a stop condition triggers.

### ADR Architecture Lock Reference
ADR-001 location (read-only from mobile repo): `/Users/armanjr/Projects/OHMployee/OHMployee/.ai/architecture_locks/adr_001_coverage_architecture_v2.md`.
Do not edit the ADR from this web repo. If a loop requires an ADR update, log it in handoff under "ADR updates needed (Ohm applies in mobile repo)". In every loop report, state "ADR basis: <file + sections>".

### Branch Policy
Work on `main` only. Never create a branch unless the prompt explicitly says "create a branch".
Never merge, push, or delete a branch on your own initiative. If the session environment
created a branch (e.g. remote/cloud task isolation), report it in the handoff entry; Ohm
verifies, merges to `main`, and deletes it.

### Database Access & Modification Rule
No DDL, function execution, or writes against any Supabase project without Ohm's explicit instruction in that prompt, and NEVER from a UI loop. All database access for UI work is strictly prohibited.

### Supabase Environments & Project References
- **Production:** `rwxelulyapjgaarlwkus`
- **Staging:** `qqiiznmqxfoamqytjica`
- Agent sessions and localhost must use staging (`qqiiznmqxfoamqytjica`).
- NEVER connect to the production ref (`rwxelulyapjgaarlwkus`).

### After Every Completed Prompt (mandatory, in this order)
1. `.ai/briefing.md` — prepend PROMPT ID + title to "Last Completed Tasks" (keep only 5)
2. `.ai/handoff.md` — prepend full handoff entry
3. `docs/state/<module>_state.md` — surgical update if behavior changed
4. Local commit (see "Local Commit Rule" below)
5. Branch close-out — if a branch exists, Ohm verifies (`npm run lint` / `npm run build` /
   manual test), merges into `main`, then deletes the branch. AI only reports the branch.

### Local Commit Rule (every prompt, after items 1-3)
- Commit LOCALLY on `main`. NEVER `git push`, merge, rebase, amend, reset, or delete anything.
- Stage ONLY the files this prompt changed, by explicit path. Never `git add .` or `git add -A`.
- Include the doc files updated in items 1-3 (briefing.md, handoff.md, state file) and any new
  migration file this prompt created. Committing a migration file does NOT apply it.
- Before committing, run `git status`. If a file this prompt touched already had uncommitted
  changes from before this prompt started, do NOT stage it. Report it and skip the commit.
- Commit only if verification passed: `npm run lint` clean for any code change (docs-only
  prompts need no lint). If verification fails, do not commit; report the failure.
- Commit only if on `main`. If on any other branch, do not commit; report it.
- Message format: `<PROMPT ID>: <PROMPT TITLE>`.
- After committing, report the commit hash and the exact files included.

State files = current stable behavior only. handoff.md = active sprint continuity only.
Archive obsolete logs to `docs/archive/`.

## Last Completed Tasks
1. **ohm#r4t7y2bn (Plantilla Import — Fix Rollback Readiness & Store Closure Cascade Vacancies Trigger)**: Completed investigation and remediation on Staging (`qqiiznmqxfoamqytjica`): (1) Root-caused `rollback_ready` remaining `false`: migration `20262606000059` (`ohm#f7m2w9x4`) replaced `approve_plantilla_import_batch` with an older function template omitting `rollback_ready = true` and snapshot capturing (BUG-06 pattern), carried forward through `062` and `064`; (2) Root-caused store closure trigger error: migration `20262606000057` from mobile repo introduced `fn_trg_store_closure_cascade_vacancies()` referencing `vacancies.closed_at`, which was never added to the schema in either repository; (3) Created and applied migration `20262606000086_fix_plantilla_import_rollback_ready_and_store_closure_trigger.sql` on Staging: added `closed_at timestamptz` to `public.vacancies`, re-asserted safe `fn_trg_store_closure_cascade_vacancies()`, updated `approve_plantilla_import_batch()` to record commit snapshots for stores, plantilla, allocations, and slots/vacancies while asserting `rollback_ready = true`, updated `rollback_plantilla_import_batch()` to safely restore/deactivate allocations and close/restore slots, and backfilled approved batches; (4) Enhanced and executed self-rolling-back test harness `scripts/tests/plantilla_import_regression.sql` verifying stationary evaluation, roving submission (`pending_approval`, 0 flagged), approval, rollback execution (100% restoration to baseline active plantilla and allocations), blocked file rejection (`BATCH_BLOCKED`), and batch rejection with audit trail (`ALL_ASSERTIONS_PASSED`); (5) Quality gates clean: `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes passing).
2. **ohm#k6w3n8qd (Plantilla Import — Staging Audit, Cleanup Script, Idempotency & SQL Regression Test Harness)**: Completed cleanup audit and test harness tasks: (1) Performed exhaustive read-only audit of staging database (`qqiiznmqxfoamqytjica`) vs baseline for Group 4 / APEX across stores, plantilla, slots, allocations, links, vacancies, views, summaries, and batches; (2) Authored non-executed FK-ordered cleanup script `scripts/staging_cleanup_ohm_k6w3n8qd.sql` targeting explicit IDs, documented how it safely bypasses broken trigger `fn_trg_store_closure_cascade_vacancies` by avoiding UPDATEs on stores; (3) Measured live idempotency inside atomic DO block with 100% rollback (`idem_stores_persisted = 0`): re-submitting and re-approving identical 14 roving rows detects 14 existing stores, 0 new stores, and yields identical counts (14 stores, 14 slots, 14 allocations, 4 plantilla employees, 14 links); (4) Authored self-rolling-back PostgreSQL regression test harness `scripts/tests/plantilla_import_regression.sql` (deleted obsolete `.mjs` script), asserting stationary valid, roving valid (14 rows, 0 flagged, batch `pending_approval`), approve execution, server-side blocking (`BATCH_BLOCKED: ...`), and rejection audit trail with forced rollback; (5) Documented regression suite in `docs/state/plantilla_web_state.md`, updated handoff notes with mobile follow-up and orchestrator corrections; (6) Verified mechanical quality gates: `tsc --noEmit` clean, `npm run lint` clean (0 errors), `npm run build` clean (20/20 routes passing).
3. **ohm#k6w3n8qd (Plantilla Import — Verification, Evidence Pass & Regression Test Suite)**: Executed exhaustive verification and evidence audit across 5 mandatory sections: (1) ADR-002 Gate Check: verified pre-edit ADR-002 Invariant 4 text; confirmed zero mention of roving being flagged or pending_review; verified additive clarification with zero invariant violations; (2) Evidence gathered with raw tool outputs: SHA256 of migration 085, `pg_get_functiondef` for all 3 RPCs, proof submit cannot emit pending_review, verified pre-existing orphans in `schema_migrations`, mobile handling analysis with exact file/line citations (`store_import_screen.dart`), `--danger` token search across codebase (reporting non-canonical usages), fixture HC column check ($1/N$ derived), and secret/leak audit on commit 4c85914 (0 leaks); (3) Live End-to-End Staging Execution: verified BEFORE counts on APEX (5 active / 5 slots / 5 allocations), live submit of 14-row roving fixture (status `pending_approval`, 14 valid, 0 blocked, 0 flagged), live approve without `INVALID_STATE` (after counts: 9 active / 19 slots / 19 allocations matching user prediction), zero double-counting, correct unassigned HRCO behavior, re-submit idempotency (14 existing stores detected), hard-blocked middle-initial test (`BATCH_BLOCKED: import contains 1 blocked row(s)` with 0 persisted writes), reject test (status `rejected`, audit log written, 0 writes to plantilla), and documented `rollback_plantilla_import_batch` requirement (`ROLLBACK_NOT_READY: lineage missing`) followed by manual test cleanup restoring active counts to BEFORE baseline; (4) Created reusable regression suite `scripts/test_plantilla_import_validation.mjs` with dynamic geometry derivation and dual unit/database test modes; (5) Lint (`npm run lint` 0 errors) and build (`npm run build` 20/20 routes passing) clean.
4. **ohm#k6w3n8qd (Plantilla Import — Roving Validation, Approval State Machine, Pre-Upload Blocking & Reject Modal)**: Resolved root causes for batch import failures where roving rows were demoted to flagged (0 valid rows) and locked out of approval (`INVALID_STATE`): (1) In migration `20262606000085_fix_plantilla_roving_validation_and_approval_state.sql`, created single source of truth row evaluator `public._evaluate_plantilla_import_rows` ensuring standard roving assignments ($N \ge 2$) evaluate to `valid` without flags and receive neutral info note (`Roving · N stores · X.XX HC`); promoted data-conflicting store-vcode mismatches to `blocked`; (2) Built dry-run RPC `public.validate_plantilla_baseline_import` (writes nothing, STABLE SECURITY DEFINER, authenticated only); hardened `public.submit_plantilla_baseline_import` to re-validate via shared evaluator and hard-refuse (`RAISE EXCEPTION 'BATCH_BLOCKED: ...'`) if `blocked_rows > 0`; (3) Maintained `public.approve_plantilla_import_batch` strictly locked to `pending_approval` and `commit_failed` only (roving batches now land cleanly in `pending_approval`); (4) Excised all data repair scripts on old batches per user directive; (5) In `PlantillaImportModal.tsx`, implemented pre-upload dry-run validation blocking the whole file at Upload & Preview if any row is blocked; removed "Needs HRCO" chip from Inspect Batch Rows; formatted employee names as "Last, First" via `formatPersonName`; updated batch status breakdown pills; fixed Reject Batch modal with non-empty reason validation, "Confirm Reject" button, and canonical tokens (`var(--danger-button)` / `var(--danger-button-hover)`); (6) Verified fixture evaluation on Staging (14/14 roving rows valid, 0 blocked, 0 flagged), tested single-initial blocking, verified `tsc --noEmit` clean, `npm run lint` clean (0 errors), and `npm run build` clean (20/20 routes passing).
5. **ohm#fix-plantilla-import-roving-invalid-state (Plantilla Import — Fix Roving Validation Demotion & Approval State Machine Rejection)**: Resolved root causes for batch import failures where batches of roving employees were completely flagged (0 valid rows) and rejected on approval with `INVALID_STATE`: (1) In `submit_plantilla_baseline_import`, stopped classifying standard roving assignments across 2..20 stores with fractional headcount (1/N) as advisory warning flags in `validation_flags`, reserving the warning exclusively for allocations exceeding 20 stores (`over_20_stores`); valid roving rows now evaluate cleanly to `validation_status = 'valid'`, yielding valid row counts and `pending_approval` status; (2) In `approve_plantilla_import_batch`, expanded the batch status check from `('pending_approval', 'commit_failed')` to `('pending_approval', 'pending_review', 'commit_failed')`, allowing batches in review with advisory warnings to be approved directly while preserving strict blocking on `blocked` rows (`v_blocked_cnt > 0`); (3) Added migration reconciliation in `20262606000085_fix_plantilla_roving_validation_and_approval_state.sql` to heal existing batches (such as Batch `#4898978`) and rows flagged solely due to `flag = 'roving'`; (4) Verified mechanical quality gates: `tsc --noEmit` clean, `npm run lint` clean (0 errors), and `npm run build` clean (20/20 routes compiled).

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
