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
1. **ohm#4c8x1nw6 (Hotfix A: Secure audit_logs RLS & Close v_audit_activity_feed Backdoor)**: Tightened `audit_logs_select` RLS policy on `public.audit_logs` to require Super Admin / Head Admin (`role_level >= 90` or `i_have_full_access()`), eliminating direct REST table leakage of PII/compensations to roles >= 30 (OM, HRCO, Encoder). Discovered and closed RLS bypass on `v_audit_activity_feed` by setting `security_invoker = true` and revoking SELECT privileges from public, anon, and authenticated. Confirmed via live database tests that OM, HRCO, and Encoder receive 0 rows from `audit_logs`, while SA and HA retain full access. Verified that timeline RPCs (`get_correction_timeline`, `get_web_hr_emploc_detail`, `get_web_vacancy_detail`) strictly check caller scope. Applied migration `20262606000076_hotfix_a_secure_audit_logs_rls.sql` to staging only (`qqiiznmqxfoamqytjica`).
2. **ohm#7k2m9q4x (Super Admin Dashboard Simplification & Group Matrix Parity - Phase 2A UI)**: Streamlined Dashboard (`/dashboard`) header to "Command Center" with Scope selector only; removed `Live RPC Telemetry Connected` chip, `CENCOM Triage` header button, and `Sync MIKA` button from header & cards (preserves anomaly link to `/plantilla`). Replaced 5-card ribbon and standalone analytics card with 4-column executive KPI row (`Workforce Coverage` with 3-segment bar & fill rate, `Open Vacancies`, `Hiring Pipeline`, `SLA Breaches`) clickable to respective modules. Enclosed group allocation matrix under "Where is the gap?" card; enforced persistent listing of Group 1 to Group 5 with MOSES HQ pinned last. Groups with zero allocations render `—` rather than disappearing; MOSES HQ displays real values (2 active plantilla, 2 HR Emploc pending) derived from global-to-CENCOM delta without view/schema modifications, with fill rate `—` and Standby status (never Critical). Critical rows highlighted in red. Replaced right-column pending approvals with compact "Needs your attention" list (Critical groups, Pending approvals synced with sidebar badge, Under-staffed stores, Ghost employee alerts). Replaced Card E with single footer status line. UI-only; zero database changes; clean lint (0 errors) and build; local commit on main.
3. **ohm#7q3m9xwk (Settings & More cleanup: Profile & Security fix, structure consolidation, sessions audit, human-readable audit trail)**: Resolved `PGRST200` relation error in `fetchOwnProfile` by querying valid `user_scopes` and direct `groups`/`accounts` relations instead of non-existent `user_groups`/`user_accounts`. Added 15s timeout safeguard with "Couldn't load profile information" and Retry button in `ProfileTab.tsx`. Relocated System Diagnostics from Settings to More > Admin Tools with legacy URL page-level redirection. Consolidated Data Archival entries to canonical location in More > Data Control > Operations & Governance. Retained Payroll Review Center shortcut in Overview for OM (who cannot access Data Control). Performed deep DB sessions audit on staging diagnosing 376 suspicious sessions and lack of session TTL automation. Transformed System Audit Logs modal (`AuditLogsModal.tsx`, `audit_formatter.ts`) into human-readable actor-first operational summaries; eliminated raw UUIDs and raw JSON dumps, replacing them with human targets and clean scalar diff cards. UI-only; clean lint and build; local commits on main.
4. **ohm#e8m3p0p2 (HR Emploc Withdrawn Deletion Request Still Shown as Active)**: `get_web_hr_emploc_detail` returns the latest deletion request regardless of status, so the drawer kept showing "Deletion Requested", the Active Deletion Request banner and strike-through after withdrawal. `normalizeDetailRow` now sets `activeDeletionRequest` only when the request status is `Pending`. UI-only; no DB change. `npm run lint` (0 errors) and `npm run build` clean; local commit on main.
5. **ohm#e8m3p0p1 (HR Emploc Activity History Latest-First Sort)**: In `HrEmplocDetailDrawer`, the Activity History Trail is sorted by `createdAt` descending (copy of list; undated rows last) so the latest event shows first. UI-only; `get_correction_timeline` unchanged. `npm run lint` (0 errors) and `npm run build` clean; local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
