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
1. **ohm#branch2-fix-audit-logs-fk-and-inactive-retention (Fix Audit Log Foreign Key Constraint Error on Status Update & Retain Inactive Tab Visibility on Branch2)**: Root-caused audit log foreign key error `23503: insert or update on table "audit_logs" violates foreign key constraint "audit_logs_actor_id_fkey"` to `fn_audit_log()` trigger function inserting unverified `auth.uid()` directly into `audit_logs.actor_id`. Created and applied migration `20262606000087` to live Staging (`qqiiznmqxfoamqytjica`), deploying `public.resolve_audit_actor_id(uuid)` to safely validate candidate IDs against the FK target with graceful fallback to `NULL`, and wrapping `fn_audit_log()` inserts in an exception block trapping `foreign_key_violation` to guarantee status updates (Resigned, AWOL, Terminated) never abort. Reverted strict exclusivity check in `isInactiveRecord` (`src/app/(dashboard)/plantilla/page.tsx`) by removing `if (isDeactivationRecord(emp)) return false;` and ensuring all separated, inactive (`isActive === false`), and pending-deactivation records remain permanently visible in the Inactive Tab roster for historical and reporting continuity. Verified `npm run lint` clean (0 errors); isolated on `Branch2`.
2. **ohm#branch2-deactivation-tab-routing-and-drawer-state (Fix Plantilla Deactivation Tab Routing, Auto-Navigate & Drawer State on Branch2)**: Root-caused `VCAG5_0056` remaining in Inactive tab instead of Deactivation tab to `isInactiveRecord` matching `emp.isActive === false` and `isDeactivationRecord` yielding to `isInactiveRecord`. Prioritized `isDeactivationRecord(emp)` to directly match pending/active deactivation statuses, and updated `isInactiveRecord`, `isFloatingRecord`, and `isOnLeaveRecord` to yield to `isDeactivationRecord(emp)`. Added `onNavigateStatusTab` to `RequestDeactivationModal.tsx` and wired it in `PlantillaDetailDrawer.tsx` to switch to `deactivation` on submit. Updated drawer action button to display `"Deactivation Pending"` (disabled) and suppressed the misleading "must be set to Floating or Inactive" warning when deactivation is already pending. Verified `npm run lint` clean (0 errors); isolated on `Branch2`.
3. **ohm#branch2-separation-vacancy-reopen-applicant-archive (Plantilla Separation Vacancy Reopening & Applicant Archiving on Branch2)**: Root-caused separated employees remaining tagged to reopened store vacancies (e.g., `VCTG2_0005` under `THREE`) to prior hire applicant rows remaining unarchived (`status = 'Confirmed Onboard', is_archived = false`), causing `vw_vacancy_list` to derive status `'Hired'` and `get_web_vacancy_detail` to display them as the hired occupant. Applied migration `20262606000086` to live Staging (`qqiiznmqxfoamqytjica`), updating `reopen_or_create_vacancy_for_plantilla` and `fn_plantilla_separation_to_vacancy` to auto-archive prior hires (`is_archived = true, archived_at = NOW()`) on vacancy reopen; executed backfill resetting `VCTG2_0005` to clean unoccupied state (`status = 'Open', derived_status = 'Open', hc_filled = 0`); preserved full historical assignment records on `public.plantilla` for Inactive Tab viewing; and disabled "Request Deactivation" in `PlantillaDetailDrawer.tsx` when employee is Active/On Leave with helper guidance. Verified `npm run lint` clean (0 errors); isolated on `Branch2`.
4. **ohm#branch2-plantilla-nsr-workflow (Plantilla Floating status routing, deactivation validation & NSR Data Team workflow on Branch2)**: Patched trigger function `fn_plantilla_separation_to_vacancy()` via migration `20262606000085` to resolve 42703 `is_roving` column error; routed `Floating` employees directly to the Floating Tab via defensive classification guards in `plantilla/page.tsx` and tab switching callback in `UpdateEmploymentStatusModal.tsx`; hid `Active` card when employee is active; made deactivation `remarks` optional and removed gray clearance notice banners; fixed unstyled white-on-white "Request New Store" button in `RequestHeadcountModal.tsx`; and implemented two-tier NSR review architecture with Data Team queue permissions, approval/rejection/forward RPCs, and UI cards in `/approvals`. Verified `npm run lint` clean (0 errors); changes isolated on `Branch2`.
5. **ohm#fix-mig-23502-slot-ordinal (Fix Supabase migration 20262606000079 null value in column slot_ordinal of relation plantilla_slots)**: Root-caused Supabase migration failure `null value in column "slot_ordinal" of relation "plantilla_slots" violates not-null constraint (SQLSTATE 23502)` at statement 2 in `20262606000079_reopen_vacancies_for_inactive_plantilla.sql` on Production (`rwxelulyapjgaarlwkus`) to `INSERT INTO public.plantilla_slots` omitting `slot_ordinal` (enforced as `NOT NULL` with check `>= 1` in `20260816000000`). Added `slot_ordinal` using the canonical ordinal derivation `COALESCE((SELECT MAX(ps.slot_ordinal) FROM public.plantilla_slots ps WHERE ps.legacy_vcode = rec.vcode), 0) + 1`. Verified `npm run lint` clean (0 errors); local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
