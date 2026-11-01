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
1. **ohm#0hmn1fix (Fix: OHMni Runtime gemini-3.8-flash Upgrade & Detailed Stream Error Forwarding)**: Resolved runtime `Error: An error occurred.` on `/api/ohmni`. Identified that `gemini-2.5-flash` was deprecated by Google (returning 404), which `toUIMessageStreamResponse` masked by default. Added upfront `GOOGLE_GENERATIVE_AI_API_KEY` presence validation returning 500 with helpful instruction, upgraded model to `google('gemini-3.8-flash')`, added payload array defense for `messages`, and wired `onError: (err) => ...` in `toUIMessageStreamResponse` to stream explicit error details to the UI. Lint clean (0 errors), build clean (20 routes); local commit on main.
2. **ohm#0hmn1cop (OHMni AI Co-Pilot: AI Operations & Data Self-Service Assistant)**: Implemented OHMni Co-Pilot across backend streaming route (`/api/ohmni`) and frontend docked 4-zone right-side drawer (`380px–400px`). Integrated Google Gemini via Vercel AI SDK (`ai` v7, `@ai-sdk/google`, `@ai-sdk/react`, `zod`). Enforced PostgreSQL Row-Level Security (RLS) and user RBAC scopes via Bearer token forwarding (`src/lib/supabase/server.ts`). Built 4 read-only live data tools (`getPlantillaSummary`, `getOpenVacancies`, `getEmplocQueueStatus`, `getHeadcountRequests`) with real-time trust execution indicators (`⚡ Verified Live Data`). Positioned directly below CENCOM in `Sidebar.tsx`, header trigger in `AdminTopbar.tsx`, and wired `⌘K` / `Ctrl+K` keyboard shortcut. Passed mechanical gates: `npm run lint` (0 errors), `npm run build` (20 routes); local commit on main.
3. **ohm#w8e2k7x1 (Fix: Account Archive Request Dispatch via notify_user RPC & Approvals Sync)**: Resolved root cause preventing archive requests from appearing in the Approvals Hub. Replaced direct client `notifications.insert` (which was blocked by RLS policy `notif_insert_service_role` and `recipient_role` NOT NULL constraints) with database SECURITY DEFINER RPC `public.notify_user(...)`. Aligned audit logging with `audit_logs` schema using valid enum `action: 'UPDATE'` (`module = 'plantilla'`, `record_id = accountId`, `new_data = { event: 'ARCHIVE_ACCOUNT_REQUESTED' }`). Updated `ArchiveAccountModal` to pass `authUserId: currentUser.authUserId` and invalidate approval cache keys (`request-category-counts`, `account-archive-requests`, `account-archive-counts`). Hardened `approveAccountArchive` and `rejectAccountArchive` with fallback RPC handling. Lint clean (0 errors), build clean (19 routes); local commit on main.
4. **ohm#a7c3v9k2 (Approvals Hub: Account Archives Review Queue & Approval Window)**: Implemented the dedicated Account Archives approval category and review queue within the Approvals Hub (`/approvals`). Role-gated category visibility strictly to Super Admin (`level >= 100` / `isOwner`) in `src/lib/rbac.ts` and `src/components/approvals/RequestCategoryNavigation.tsx`. Created `AccountArchiveDataTable` with real-time status tabs (Pending, Approved, Rejected), live counter badges, headcount impact snapshots, requester attribution, and search filtering. Integrated Super Admin review actions with confirmation modals for Approve Archive (deactivates account via `accounts.is_active = false, status = 'Inactive'`, marks notification approved, logs audit trail) and Reject Archive (records reviewer justification, marks notification rejected, preserves account active state). Lint clean (0 errors), build clean (19 routes); local commit on main.
5. **ohm#p4a8x2m9 (Plantilla Account Lifecycle: Add Account, Archive Account & Employee Absorption Workflows)**: Implemented the three interconnected account lifecycle features in the Next.js web application (`OHMployee_web`). (1) **Add Account**: Added `+ Add Account` button to Plantilla Directory header, role-gated strictly to Head Admin (`HA`) and Super Admin (`SA`) and hidden for Encoders, with modal fetching groups dynamically from Supabase `public.groups`. (2) **Archive Account**: Integrated three-dot context menu (`⋮`) on account cards; built active employee intercept dialog routing to absorption or proceeding to archive remarks; enforced minimum 30-character remarks validation with live counter; implemented pending approval submission for Super Admin without deleting/hiding the account. (3) **Absorption Workflow**: Built employee transfer modal accessible from card context menus and detailed account view header with target account selection and "Select All" batch employee checklist; role-gated execution routes Encoders to pending `employee_transfers` approvals while HA/SA directly execute Supabase database updates and refresh roster data immediately. Lint clean (0 errors), build clean (19 routes); local commit on main.

> Older entries trimmed 2026-10-28 (`ohm#4x7n2k9w Phase 5 REVISED`) to keep this list to 5 — see git history for earlier entries in full.
