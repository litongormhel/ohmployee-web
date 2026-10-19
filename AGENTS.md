## Core Workflow Rules (apply to EVERY prompt, even if the prompt body does not mention them)
- Read `.ai/briefing.md` first. Follow its "Mandatory Workflow Rules" section on EVERY prompt.
- The post-prompt documentation update is mandatory on EVERY prompt, even if the prompt body
  does not mention it. Checklist: `.ai/briefing.md` § After Every Completed Prompt.
- Approval & Regression Gate: before any code, schema, or migration change, present a short
  plan + regression risk assessment, then STOP and WAIT for explicit user approval. Do not
  implement in the same turn.
- Work on `main` only. Never create a branch unless the prompt says "create a branch". Never
  merge, push, or delete a branch on your own. If the environment created a branch, report it
  in the handoff entry; Ohm verifies (`npm run lint` / `npm run build` / manual test), merges
  to `main`, and deletes it.

<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->
