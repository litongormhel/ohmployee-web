# AI Briefing

## Mandatory Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)

### Approval & Regression Gate
Before writing any code, schema change, or migration: present a short implementation plan
plus a regression risk assessment (what could break, what's untouched). STOP and WAIT for
explicit user approval. Do not implement in the same turn the plan is presented. This applies
even when the prompt already describes the approach in detail.

### Branch Policy
Work on `main` only. Never create a branch unless the prompt explicitly says "create a branch".
Never merge, push, or delete a branch on your own initiative. If the session environment
created a branch (e.g. remote/cloud task isolation), report it in the handoff entry; Ohm
verifies, merges to `main`, and deletes it.

### After Every Completed Prompt (mandatory, in this order)
1. `.ai/briefing.md` — prepend PROMPT ID + title to "Last Completed Tasks" (keep only 5)
2. `.ai/handoff.md` — prepend full handoff entry
3. `docs/state/<module>_state.md` — surgical update if behavior changed
4. Branch close-out — if a branch exists, Ohm verifies (`npm run lint` / `npm run build` /
   manual test), merges into `main`, then deletes the branch. This is a normal step, not a
   separate cleanup task. AI only reports the branch; it does not merge or delete it.

State files = current stable behavior only. handoff.md = active sprint continuity only.
Archive obsolete logs to `docs/archive/`.

## Last Completed Tasks
1. **ohm#r7b9w2k1**: Phase 1 — Port 2-Step Rollback & History for Plantilla and Vacancy Imports (1:1 Mobile Parity)
2. **ohm#v4c9prod**: Restore Staging Supabase Fallback for Vercel Deployment
3. **ohm#3f8j5k2w**: Web parity check + AGENTS.md alignment
4. **ohm#9c4t1w6e**: Wire Mandatory Workflow Rules (web)
5. **ohm#w89p602f**: Complete Final Sidebar Parity — Port Temporary Permission Overrides to Web `/users` Management Hub

> Older entries trimmed 2026-10-20 (`ohm#r7b9w2k1`) to keep this list to 5 — dropped `ohm#w89p602e` and earlier entries — see git history for that and earlier entries in full.
