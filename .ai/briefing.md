# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.
*Standing UI Standard Loop Override:* The UI Standard loop (`ohm#l0u8s2d9` onward) runs WITHOUT an approval gate. The loop pauses only on the stop conditions in `docs/architecture/ui-standard-briefing.md` section 10 or when verification fails. This overrides the generic "stop and wait" rule for this project only. Do not ask for approval again unless a stop condition triggers.

### Branch Policy
Work on `main` only. Never create a branch unless the prompt explicitly says "create a branch".
Never merge, push, or delete a branch on your own initiative. If the session environment
created a branch (e.g. remote/cloud task isolation), report it in the handoff entry; Ohm
verifies, merges to `main`, and deletes it.

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
1. **ohm#l5br4m1k**: UI Standard & Motion System — Loop 5B Audit & Clarifications (Completed report-only audit answering all 4 mandated questions: [1] Listed contents of parent repo `.ai/architecture_locks/` with 1 file `adr_001_coverage_architecture_v2.md` and plainly reported that `ADR-001-ohmployee-system-architecture.md` does not exist without citing another file; [2] Provided full diff of `gate.py` across Loops 3-5B and confirmed 0 checks loosened with HEAD byte-for-byte identical to hardened Loop 3 gate; [3] Exhaustive audit table of all 30 elements/files across `src/` using `--danger-*` strictly classified as validation errors, destructive actions, or failed-state alerts with 0 decorative or count usage; [4] Documented build evidence showing real `npm run build` [Next.js 16.2.4 Turbopack] passing with 0 errors across all 19 static routes without needing tsc fallback; 0 code changes; paused waiting for Ohm prior to Plantilla)
2. **ohm#s4k9w2x7**: Plantilla Bulk Baseline Import Performance Optimization & Statement Timeout Hardening (Investigated and eliminated `canceling statement due to statement timeout` error during 1,326-row bulk import; identified Supabase role-level 8s timeout and O(N^2) JSON scans + row-by-row queries in `submit_plantilla_baseline_import`; created migration `20262606000065_optimize_plantilla_import_bulk_performance.sql` adding functional indexes on `stores(upper(vcode))` and active `plantilla(employee_no, account_id)`; expanded `pib_status_check` constraint on `plantilla_import_batches`; refactored `submit_plantilla_baseline_import` to O(N) set-based CTE evaluation and single bulk insert; attached 60s statement_timeout across submit, approve, and rollback RPCs; benchmarked on live prod with synthetic 1,326 rows completing in 7.4s roundtrip with 0 errors; applied to both Prod and Staging; 0 lint errors on `main`)
3. **ohm#m8k3w7x2**: Fix Plantilla Bulk Baseline Missing mother_account_configs and ADR-002 Prod Parity (Investigated and resolved Postgres exception `relation "public.mother_account_configs" does not exist` occurring during Plantilla Bulk Baseline import; audited schema divergence between staging and live prod `rwxelulyapjgaarlwkus` revealing missed migration 53 objects; created and applied migration `20262606000064_fix_plantilla_mother_account_configs_and_columns.sql` to prod creating `public.mother_account_configs` with RLS, policies, authenticated grants, and 17 seeded accounts; added 21 companion columns across `plantilla_import_rows`, `stores`, `accounts`, `plantilla`, `employee_store_allocations`, `plantilla_import_batches`, and `employees`; synchronized full ADR-002 parity for `trg_account_hrco_backfill`, Zero-Edit lock helpers, `fn_assert_vcode_exists_in_plantilla`, and 6 batch review/approve/rollback RPCs; verified clean lint on `main`)
4. **ohm#l5b9k4x2**: UI Standard & Motion System — Loop 5B HR Emploc Import Align (Aligned HR Emploc import flow across UploadTab, ReviewBatchesTab, HistoryTab, BatchDetailsModal, RejectBatchModal, and RollbackBatchModal; preserved 100% of exceljs parsing, validation rules, batch RPCs, and 72h rollback logic; neutralized batch counts, row counts, and countdowns; applied modal guards with z-[70] submodal stacking, disableBackdropClick, isSubmitting, and isDirty Esc-guard; applied --danger tokens to destructive actions and error banners; restored gate.py to check real module hr-emploc; color literals dropped from 351 to 0 across import tree [entire HR Emploc at 0 literals]; verified build green and gate allow on `main`; stopped before Plantilla for Ohm checkpoint)
5. **ohm#l5a7m3p9**: UI Standard & Motion System — Danger Tokens & Loop 5A HR Emploc Align (Implemented approved `--danger` token set in `globals.css` with WCAG AA contrast $\ge 4.5:1$ strictly scoped to errors/destructive actions; hardened `Modal` at `z-[60]` with `disableBackdropClick`, `isSubmitting`, and `isDirty` guards across 9 Vacancy modals, `MikaSyncModal`, and 9 HR Emploc modals; restored danger styling across Dashboard, CENCOM, and Vacancy; inspected ADR-001 System Architecture v2 in parent repository; completed Loop 5A HR Emploc alignment dropping color literals from 694 to 0 across list, table, drawer, and all 9 modals; mechanical gate passed with decision allow on `main`)

> Older entries trimmed 2026-10-26 (`ohm#l5br4m1k`) to keep this list to 5 — dropped `ohm#l4v9k2x1` and earlier entries — see git history for that and earlier entries in full.
