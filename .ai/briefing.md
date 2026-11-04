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
1. **ohm#q3v8n2kd (HR Emploc — Stage 2b-DB on STAGING (For Emploc status, scoped Ops docs, private Storage, 3-day purge queue, cross-module pipeline fixes) + Migration History Hygiene (20262606000083 & 20262606000084))**: Implemented Stage 2b-DB on STAGING (`qqiiznmqxfoamqytjica`); PROD (`rwxelulyapjgaarlwkus`) frozen read-only awaiting single coordinated release (`…83` + `…84` + web + mobile). Restored `20262606000081` and `…82` to exact `bb2e31f` blobs (verified MD5s); generated delta migration `20262606000083_hr_emploc_phase2a_fix_delta.sql` with verified 100% no-op on STAGING and dry-run against PROD; authored and applied `20262606000084_hr_emploc_for_emploc_and_scoped_docs.sql` and `supabase/rollbacks/rollback_20262606000084.sql`. Verified 100% rollback match (all 21 modified objects identical to pre-84 definitions) and 100% re-apply idempotency. Configured private bucket `hr-corrections`, scoped doc authorization, `storage_cleanup_queue` with 3-day TTL via pg_net and cron, and report-only orphan sweeper. Proven 100% pending deletion locks (13/13 blocked), 100% scope parity and dashboard metric invariance, real Storage API purge with signed URL 404, and 31/31 comprehensive test suite cases passing on Staging.
2. **ohm#7k4w9xqn (HR Emploc — Phase 2a-fix: close DB gaps (list/summary RPCs, mobile approve path, rules b/d, test coverage, rollback) on STAGING)**: Closed all Phase 2a DB + doc gaps on STAGING (`qqiiznmqxfoamqytjica`) in `20262606000081_hr_emploc_final_workflow_and_registry.sql`, `20262606000082_fix_list_web_hr_emplocs_position_column.sql`, and `supabase/rollbacks/rollback_20262606000081.sql`. Captured all 17 live pre-change RPC definitions in `/scratch/captured/`; applied surgical patches (`diff -u` verified) to `list_web_hr_emplocs`, `get_web_hr_emploc_summary`, `get_web_hr_emploc_detail`, and `update_deployed_employee_id`; gated `approve_correction_request`, `reject_correction_request`, `reopen_correction_request`, and `mark_for_correction` with `can_tag_or_review_hr_emploc()` and routed `approve_correction_request` through `_assign_and_deploy_emploc_core`; implemented Decision 1 (same `hr_emploc` + same person re-assigning same number after Revert requires no rehire confirm), Rule b across all active Plantilla/HR Emploc statuses, Rule d and Rule a using `fn_match_person_name` (middle initial + missing middle warning + alias), and Decision 2 typo release across both table update orders (`hr_emploc` -> `plantilla` and `plantilla` -> `hr_emploc`). Reconciled 2,435 vs 2,429 registry rows (added 6 historical archived `Ready for Plantilla` rows; 2,437 total with 2 manual test rows). Verified rollback + 100% MD5 match + re-apply cycle and 37/37 smoke tests + 2-session concurrency test on Staging.
3. **ohm#fix-mig-23502-slot-ordinal (Fix Supabase migration 20262606000079 null value in column slot_ordinal of relation plantilla_slots)**: Root-caused Supabase migration failure `null value in column "slot_ordinal" of relation "plantilla_slots" violates not-null constraint (SQLSTATE 23502)` at statement 2 in `20262606000079_reopen_vacancies_for_inactive_plantilla.sql` on Production (`rwxelulyapjgaarlwkus`) to `INSERT INTO public.plantilla_slots` omitting `slot_ordinal` (enforced as `NOT NULL` with check `>= 1` in `20260816000000`). Added `slot_ordinal` using the canonical ordinal derivation `COALESCE((SELECT MAX(ps.slot_ordinal) FROM public.plantilla_slots ps WHERE ps.legacy_vcode = rec.vcode), 0) + 1`. Verified `npm run lint` clean (0 errors); local commit on main.
4. **ohm#fix-mig-23502-slots (Fix Supabase migration 20262606000079 null value in column position of relation plantilla_slots)**: Root-caused Supabase migration failure `null value in column "position" of relation "plantilla_slots" violates not-null constraint (SQLSTATE 23502)` at statement 2 in `20262606000079_reopen_vacancies_for_inactive_plantilla.sql` on Production (`rwxelulyapjgaarlwkus`) to `INSERT INTO public.plantilla_slots` omitting `position` and `employment_type` (which are NOT NULL in `plantilla_slots`). Added `position` with fallback to `COALESCE(NULLIF(btrim(rec.position), ''), (SELECT v.position FROM public.vacancies v WHERE v.vcode = rec.vcode LIMIT 1), 'Motorized Collector')` and `employment_type` with fallback to `CASE WHEN COALESCE(rec.deployment_type, '') = 'Roving' THEN 'Roving' ELSE 'Stationary' END`, plus hardened `position = COALESCE(position, rec.position, 'Motorized Collector')` in `UPDATE public.vacancies`. Verified `npm run lint` clean (0 errors); local commit on main.
5. **ohm#fix-mig-42703-esa (Fix Supabase migration 20262606000079 undefined column updated_at on employee_store_allocations)**: Root-caused Supabase migration failure `column "updated_at" of relation "employee_store_allocations" does not exist (SQLSTATE 42703)` at statement 1 in `20262606000079_reopen_vacancies_for_inactive_plantilla.sql` on Production (`rwxelulyapjgaarlwkus`) to `UPDATE public.employee_store_allocations` referencing nonexistent `updated_at` (ESA is an append-only historical table without `updated_at`). Removed `updated_at = now()` from lines 14 and 233, added `DROP FUNCTION IF EXISTS public.plantilla_update_separation` guards, and restored execution grants. Verified `npm run lint` clean (0 errors); local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
