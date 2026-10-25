# loop-engineering

A drop-in skill for **loop engineering** — building a self-running agent loop that keeps working until a goal is met, instead of the manual write → wait → review → re-prompt cycle. Compatible with Antigravity and Claude Code.

The skill walks you through the architecture and asks you the questions to set it up:

- **The honesty test** — four conditions that decide whether a loop is even worth building.
- **Two axes** — manual vs automatic (who closes the loop) and open vs closed (is there a gate).
- **The primitives** — `/goal` vs `/loop` vs routines (`/schedule`), and which one to use.
- **The gate** — a `Stop` hook running a *real* test (un-foolable, zero tokens) for code (via `hooks.json` in Antigravity or `.claude/settings.json` in Claude Code), or a separate LLM-judge + rubric for non-testable work.
- **The ceiling** — `max_turns` / budget limits so the loop never spins forever.
- **Model routing** — cheap models for verification and logs, strong models for code.
- **Inner vs outer loops** — why a network of agents is only as good as the inner loops under it.
