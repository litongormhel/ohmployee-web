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
1. **ohm#fix-mig-42p16-detail (Fix Supabase migration 20261014193500 drop vw_vacancy_detail 42P16 error)**: Root-caused Supabase migration failure `cannot drop columns from view (SQLSTATE 42P16)` at statement 8 in `20261014193500_fix_vacancy_closure_lifecycle_and_tab_filtering.sql` to PostgreSQL prohibiting column removal in `CREATE OR REPLACE VIEW public.vw_vacancy_detail`. Analyzed complete schema repository confirming zero dependent views rely on `vw_vacancy_detail`. Inserted `DROP VIEW IF EXISTS public.vw_vacancy_detail CASCADE;` immediately prior to `CREATE OR REPLACE VIEW public.vw_vacancy_detail AS`; preserved full grants on line 867. Verified `npm run lint` clean (0 errors); local commit on main.
2. **ohm#fix-mig-42p16 (Fix Supabase migration 20261014193500 drop view 42P16 error)**: Root-caused Supabase migration failure `cannot drop columns from view (SQLSTATE 42P16)` at statement 0 in `20261014193500_fix_vacancy_closure_lifecycle_and_tab_filtering.sql` to PostgreSQL prohibiting column removal in `CREATE OR REPLACE VIEW public.vw_vacancy_list`. Analyzed complete schema repository confirming zero dependent views rely on `vw_vacancy_list`. Inserted `DROP VIEW IF EXISTS public.vw_vacancy_list CASCADE;` immediately prior to `CREATE OR REPLACE VIEW public.vw_vacancy_list AS`; preserved full grants on line 89. Verified `npm run lint` clean (0 errors); local commit on main.
3. **ohm#syncpnpm (Sync pnpm-lock.yaml with package.json dependencies for Vercel CI)**: Resolved Vercel deployment failure caused by `ERR_PNPM_OUTDATED_LOCKFILE`. Synchronized `pnpm-lock.yaml` with `@ai-sdk/google`, `@ai-sdk/react`, `ai`, and `zod` dependencies; pinned `"packageManager": "pnpm@10.29.3"` in `package.json` maintaining `lockfileVersion: '9.0'`; verified `pnpm install --frozen-lockfile --lockfile-only` succeeds cleanly; verified `npm run lint` clean (0 errors) and `pnpm build` clean (20/20 routes).
4. **ohm#9x4v2m8p (Diagnose and fix HR Emploc "Compliance Queue Data Unavailable" across all tabs)**: Root-caused "Compliance Queue Data Unavailable" across all tabs (`Pending`, `Correction`, `Review`, `Deployed`) on Staging (`qqiiznmqxfoamqytjica`) to PostgreSQL error `42703 (undefined_column)` in `list_web_hr_emplocs`: migration `20262606000081` introduced broken column reference `COALESCE(h.position_snapshot, h.position)` where `position_snapshot` does not exist on `hr_emploc` (actual columns are `position` and `position_id_snapshot`). `get_web_hr_emploc_summary` succeeded because it references valid `h.position`. Created migration `20262606000082_fix_list_web_hr_emplocs_position_column.sql` restoring `h.position AS position_title` with schema cache reload. Surgically patched `000081` line 1957 for future clean PROD promotion. Applied `000082` to Staging only (PROD untouched). Verified live rows and total counts across all 4 tabs match tab badge counters (`pending: 2`, `correction: 3`, `review: 3`, `deployed: 6`). Mechanical gates clean: `npm run lint` clean (0 errors); local commit on main.
5. **ohm#7k2m9x4q (Fix HR Emploc "Approve Correction" RPC signature mismatch (p_employee_no))**: Diagnosed schema cache mismatch on `review_web_hr_emploc_correction` as Cause (a): local environment `.env.local` pointed to Production (`rwxelulyapjgaarlwkus`), which lacks migrations `20262606000080` and `20262606000081` (retaining legacy 4-param signature from `20260609000000`). Realigned `.env.local` to Staging (`qqiiznmqxfoamqytjica`) per briefing rules. Verified zero callers in mobile repository. Confirmed Staging PostgREST cleanly resolves both 5-param (`approveHrEmplocReview`) and 4-param (`revertHrEmplocReview`) invocations without overload ambiguity or schema cache errors. Noted pending Production promotion for migrations `20262606000080` and `20262606000081`. Mechanical gates clean: `npm run lint` clean (0 errors); local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
