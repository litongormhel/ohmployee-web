## Core Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)
- Read `.ai/briefing.md` first. Follow its "Mandatory Workflow Rules" section on EVERY prompt.
- Context routing: use `.ai/current_state.md` to pick the module state file and ADR-001 sections.
  All paths in a prompt's Context block are relative to THIS web repo. Fail loudly: if any
  required context file is missing, STOP and report the missing path. Never proceed silently.
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
