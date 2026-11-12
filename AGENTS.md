## Core Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)
- Read `.ai/briefing.md` first. Follow its "Mandatory Workflow Rules" section on EVERY prompt.
- Auto Context Loading (EVERY prompt, no Context block needed):
  1. `.ai/briefing.md`
  2. `.ai/current_state.md` → "Routing Index" section only
  3. Infer the module(s) from the prompt (route, component, RPC, or module name). Load each
     module's web state file(s) and its ADR-001 sections from the Routing Index table.
  4. ADR mirror → § Core Cross-Module Invariants + the module section(s).
  If the module is ambiguous, ask before loading. Start every report with
  "Context loaded: <files + ADR sections>". Fail loudly: if any file is missing, STOP and report
  the missing path. Never proceed silently. All paths are relative to THIS web repo.
  A Context block in the prompt is optional: it overrides or extends this default.
- ADR Mirror: ADR-001 is read from `docs/architecture/_mirror/ADR-001-ohmployee-system-architecture.md`
  (read-only copy; source of truth is the mobile repo). At the start of EVERY prompt run
  `npm run check:adr` and act on `ADR_MIRROR_STATUS`:
  `FRESH` → proceed. `STALE` / `MIRROR_MISSING` / `MIRROR_EDITED` → run `npm run sync:adr`
  (exempt from the Approval Gate: copy only, no code/logic), then include the mirror file in the
  prompt's local commit and report "ADR mirror synced: <old> → <new>". `NOT_VERIFIED` → use the
  mirror and write "ADR freshness: NOT VERIFIED" in the report. Never edit the mirror by hand.
- The post-prompt documentation update is mandatory on EVERY prompt, even if the prompt body
  does not mention it. Checklist: `.ai/briefing.md` § After Every Completed Prompt.
- Approval & Regression Gate: before any code, schema, or migration change, present a short
  plan + regression risk assessment, then STOP and WAIT for explicit user approval. Do not
  implement in the same turn.
- Uncertainty & Clarification Gate: If requirements, user intent, edge cases, or scope boundaries
  are unclear or ambiguous, NEVER make assumptions or proceed blindly. Always STOP, ask clarifying
  questions, and explicitly provide 1–3 concrete recommendations with rationale.
- ADR & Architecture Conflict Gate: If a user instruction directly conflicts with ADR-001/ADR-002
  architectural locks, permanent rule locks, or database contracts, NEVER implement it silently.
  STOP immediately, cite the conflicting ADR section/rule, explain the specific risks and breakages
  if implemented as requested, and provide a safe recommendation that satisfies the objective without
  violating architectural integrity. Wait for explicit confirmation or override.
- Workflow & Visibility Regression Guard: If any proposed change risks breaking an existing workflow,
  regressing visibility (e.g., role-scoped action buttons, tab rosters, historical separation logs),
  or corrupting state transitions, STOP immediately. Detail what breaks, ask the user, and present
  a safe recommendation that avoids regression.
- Task Decomposition & Subagent Delegation Gate: When a prompt or task is heavy, multi-surface, or
  architecturally complex (e.g., spans multiple modules, involves large refactoring, requires deep
  codebase or RPC tracing, or carries high regression risk), the agent MUST decompose the problem.
  It should spawn specialized subagents (e.g., Codebase Researcher, Schema/RPC Auditor, or Verification
  Specialist via `invoke_subagent`) to perform isolated investigations or checks without polluting the
  primary context window. The primary agent remains the orchestrator: it synthesizes subagent findings,
  enforces the Approval Gate and ADR contracts, and delivers the unified report and recommendations to the user.
- Work on `main` only. Never create a branch unless the prompt says "create a branch". Never
  merge, push, or delete a branch on your own. If the environment created a branch, report it
  in the handoff entry; Ohm verifies (`npm run lint` / `npm run build` / manual test), merges
  to `main`, and deletes it.
- After items 1-3 of the checklist, make a LOCAL commit of only the files this prompt changed
  (explicit paths, never `git add .`). NEVER push. Rules: `.ai/briefing.md` § Local Commit Rule.
- Environment Safety Guard: If the workspace or Supabase CLI is detected pointing to Production (`rwxelulyapjgaarlwkus` in `.env` or `supabase/.temp/project-ref`), immediately switch back to Staging (`qqiiznmqxfoamqytjica` via `.env.staging` / `npx supabase link --project-ref qqiiznmqxfoamqytjica`) before executing tasks.
- Conclude every turn report with both: (1) an explicit **Next Steps** section covering immediate actions/guidance, and (2) a helpful `> [!TIP]` callout covering operational tips, verification commands, or deployment commands.

<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->
