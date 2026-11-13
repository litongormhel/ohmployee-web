## 2026-11-13T03:25:40Z
Implement the surgical fixes for Milestone 2 Iteration 2 identified by the Explorers:
- Explorer 1 report: d:\Projects\ohmployee-web\.agents\teamwork\explorer_m2_r2_1_gen1\handoff.md
- Explorer 2 report: d:\Projects\ohmployee-web\.agents\teamwork\explorer_m2_r2_2_gen1\handoff.md
- Explorer 3 report: d:\Projects\ohmployee-web\.agents\teamwork\explorer_m2_r2_3_gen1\handoff.md
- Challenger 2 report: d:\Projects\ohmployee-web\.agents\teamwork\challenger_m2_2_gen1\handoff.md
- User request: d:\Projects\ohmployee-web\.agents\teamwork\ORIGINAL_REQUEST.md
- Project plan: d:\Projects\ohmployee-web\PROJECT.md

Exclusive Write Ownership:
- `src/components/more/qa/roleBadgeUtils.ts`
- `src/components/more/qa/QaStepTimeline.tsx`
- `src/components/more/qa/QaFindingsViewer.tsx`
- `src/components/more/qa/QaRunHistoryTable.tsx`
- `src/lib/queries/governance.ts`
- `scripts/test_m2_ui_challenger_stress.mjs`

Changes to implement:
1. `src/components/more/qa/roleBadgeUtils.ts`:
   Add null/undefined guard to `getRoleBadgeConfig(roleName: string | null | undefined)` so `(roleName ?? "").toLowerCase().trim()` never crashes on null.
2. `src/components/more/qa/QaStepTimeline.tsx`:
   - Change static `<span>Operational Tables: Clean</span>` to dynamic `<span>{isRolledBack ? "Operational Tables: Clean" : "Operational Tables: Potential Leak"}</span>` and adjust Database icon color (`isRolledBack ? "text-brand-primary" : "text-amber-500"`).
   - Guard step status lowercasing: `(st?.status ?? "").toLowerCase() === "passed"`.
   - Filter `(result.steps ?? []).filter(Boolean)`.
3. `src/components/more/qa/QaFindingsViewer.tsx`:
   - Fix run isolation filter: `if (selectedRunId && f.runId !== selectedRunId) return false;` so findings with null runId do not leak into run-specific views.
4. `src/components/more/qa/QaRunHistoryTable.tsx`:
   - Refine `isRolledBack` heuristic to require positive confirmation (`qa_sandbox_rollback_success`, `zero data pollution`, or `rolled back` without `failed` or `leak`), and default to `false`.
   - Add fallback rendering for uncategorized findings: when `r.findingCount > 0` but severity breakdown counts are all 0, render `<span className="text-text-secondary text-xs">{r.findingCount} total</span>`.
   - Add null guard for status lowercasing: `(r.status ?? "").toLowerCase()`.
5. `src/lib/queries/governance.ts`:
   - Filter `rawSteps` with `s !== null && typeof s === "object" && !Array.isArray(s)` before mapping.
   - Guard `s.step` numeric conversion to avoid `NaN`.
   - Guard `finding_counts` with safe non-negative integer fallback.
6. `scripts/test_m2_ui_challenger_stress.mjs`:
   - Update any test assertions to reflect the new dynamic text (`Operational Tables: Potential Leak`, `Check Rollback`, etc.) and ensure all 28 stress scenarios pass.

Verification Commands to run:
- `node scripts/test_m2_ui_challenger_stress.mjs`
- `npm run check:adr`
- `npm run check:sql`
- `npm run lint`
- `npm test`
- `npm run build`
