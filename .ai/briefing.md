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
1. **ohm#e8m3p0p0 (HR Emploc Pending-Deletion Row Lock & Human-Readable Activity History)**: `HrEmplocListItem` now carries `isPendingDeletion` (from `list_web_hr_emplocs.is_pending_deletion`); Pending tab `+ Add Emploc` / `! For Correction` are disabled with a tooltip while a deletion request is active (until withdrawn). Rewrote `get_correction_timeline` (migration `20262606000075`, applied to staging `qqiiznmqxfoamqytjica` at Ohm's request) to return actor-first sentences (e.g. "Litong, Ohm requested deletion of Santos, Jayson Mendez due to <reason>."), drop duplicate/no-op "Status Updated" rows, and include deletion request lifecycle events. Drawer renders server sentences. `npm run lint` (0 errors) and `npm run build` clean; local commit on main.
2. **ohm#e8m3p0o9 (HR Emploc Deployed Tab Separate Emploc ID & Applicant Columns)**: In `HrEmplocTable`, Deployed (and shared Ready) columns are now `Group, Account, Emploc ID, Applicant, Position, HRCO, SLA, Actions`; split the stacked Emploc ID / Applicant cell into two cells, keeping For Deletion badge and strike-through. Other tabs unchanged. `npm run lint` (0 errors) and `npm run build` clean; local commit on main.
3. **ohm#e8m3p0o8 (Fix Revert-to-Pending plantilla_status_check Violation)**: `revert_hr_emploc_to_pending` set `plantilla.status = 'Separated'`, violating `plantilla_status_check`. Added migration `20262606000074_fix_revert_hr_emploc_plantilla_status.sql` that sets `'Deactivated'` (row stays soft-deleted, so `uq_plantilla_employee_no_active` frees the ID). Migration NOT applied to staging (awaiting Ohm). Docs-only/SQL change, no lint needed; local commit on main.
4. **ohm#e8m3p0o7 (HR Emploc Attachment Download Icon-Only & Strict Blank Remarks)**: Updated `HrEmplocTable` to render an icon-only download button (`Download` icon with tooltip/aria-label) in the Attachment column, excluding the filename text to conserve space. In `submitHrcoCorrection` and `UploadAttachmentModal`, removed synthetic `"Compliance document uploaded: <filename>"` string injection and made notes optional so only user-typed remarks are stored. In `HrEmplocTable`, configured Remarks to display only user-entered remarks and leave the cell blank when empty. Verified `npm run lint` (0 errors) and `npm run build` clean (19/19 routes compiled); local commit on main.
5. **ohm#e8m3p0o6 (HR Emploc Review Queue Remarks Column & Direct Attachment Download)**: Updated `list_web_hr_emplocs` RPC on staging `qqiiznmqxfoamqytjica` to include `remarks` (coalescing `ops_remarks` and `hr_remarks`), `attachment_url`, and `attachment_file_name` inside `row_capabilities` JSONB. Renamed the 8th column in the `Review` queue from `Notes` to `Remarks` and displayed the actual correction remarks entered. Updated `getCorrectionAttachmentSignedUrl` and `handleDownloadAttachment` in `page.tsx` to generate signed download URLs with `{ download: true }` and trigger direct browser file download for compliance attachments. Verified `npm run lint` (0 errors) and `npm run build` clean (19/19 routes compiled); local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
