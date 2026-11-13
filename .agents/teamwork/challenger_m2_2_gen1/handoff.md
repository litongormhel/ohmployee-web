# Challenger Verification Report: Milestone 2 QA Center UI Components

**Verdict**: `REQUEST_CHANGES`

---

## 1. Observation

### Obs 1.1: Automated Build, Lint & Existing Test Suite Status
Direct execution commands and tool outputs:
1. `npm run lint`:
   - Command: `node scripts/adr-mirror.mjs check && node scripts/check-sql-contracts.mjs && eslint`
   - Result: Exited with code 0.
   - Output: `ADR_MIRROR_STATUS: FRESH`, `SQL_CONTRACTS_OK — verified 28 core tables & 19 cross-module RPC contracts across 631 migrations`. 0 ESLint errors, 0 warnings.
2. `npm test`:
   - Command: `node --test src/lib/utils/__tests__/*.test.mjs src/lib/queries/__tests__/*.test.mjs`
   - Result: Exited with code 0. 211 tests passed, 0 failed.
3. `npm run build`:
   - Command: `node scripts/adr-mirror.mjs check && next build`
   - Result: Exited with code 0. Compiled successfully in 13.6s, TypeScript finished in 33.0s, all 20 static and dynamic routes generated cleanly.

### Obs 1.2: Empirical Test Harness Results (`scripts/test_m2_ui_challenger_stress.mjs`)
An adversarial stress test suite was created and executed using `ReactDOMServer.renderToStaticMarkup` across 28 edge cases covering `QaStepTimeline.tsx`, `QaFindingsViewer.tsx`, `QaRunHistoryTable.tsx`, and `roleBadgeUtils.ts`.
Command: `node scripts/test_m2_ui_challenger_stress.mjs`
Result: 28 test scenarios executed, revealing **5 concrete empirical vulnerabilities**:

#### Bug 1: Contradictory "Operational Tables: Clean" in Rollback Failure Banner
- File: `src/components/more/qa/QaStepTimeline.tsx`
- Lines: 185–188
- Verbatim code:
  ```tsx
  <div className="flex items-center gap-1.5 text-xs text-text-muted font-mono bg-surface-primary px-2.5 py-1 rounded-lg border border-border-default">
    <Database className="h-3 w-3 text-brand-primary" />
    <span>Operational Tables: Clean</span>
  </div>
  ```
- Empirical proof: When `result.sandbox_rolled_back` is `false`, line 165 renders `QA_SANDBOX_ROLLBACK_FAILED`, line 174 renders `Leak Warning`, and lines 180–181 render `"Isolation warning: subtransaction rollback was not confirmed. Live tables may have uncommitted test data."` However, line 187 unconditionally renders `<span>Operational Tables: Clean</span>` on the right side of the exact same box.

#### Bug 2: Run ID Filter Isolation Leak
- File: `src/components/more/qa/QaFindingsViewer.tsx`
- Lines: 56–59
- Verbatim code:
  ```tsx
  const filteredFindings = findings.filter((f) => {
    if (selectedRunId && f.runId && f.runId !== selectedRunId) {
      return false;
    }
  ```
- Empirical proof: When filtering by a specific `selectedRunId` (e.g. `selectedRunId = "run-target-123"`), any finding where `f.runId` is `null` or `undefined` evaluates `f.runId` as falsy, bypassing `return false;`. Consequently, orphan findings without a `run_id` leak into the run-specific view. Test 3.5 confirmed that orphan defects with `runId: null` are rendered even when filtering for a specific run.

#### Bug 3: Heuristic False Positive "Rolled Back" Badge on Rollback Failures
- File: `src/components/more/qa/QaRunHistoryTable.tsx`
- Lines: 48–53
- Verbatim code:
  ```tsx
  const isRolledBack =
    r.rolledBack ??
    (r.summary
      ? r.summary.toLowerCase().includes("sandbox") ||
        r.summary.toLowerCase().includes("zero data pollution") ||
        r.summary.toLowerCase().includes("rolled back")
      : true);
  ```
- Empirical proof: Since `v_qa_detection_run_summary` does not expose a `rolled_back` column, `r.rolledBack` is `undefined`. When a failed run logs `"Sandbox rollback failed: 4 uncommitted records remained in vacancies"`, `.includes("sandbox")` returns `true`. Test 4.3 proved that `isRolledBack` evaluates to `true`, displaying an emerald `Rolled Back` badge with `ShieldCheck` icon for a run that explicitly failed rollback. Additionally, if `r.summary` is `null`, it unconditionally defaults to `true`.

#### Bug 4: Unhandled TypeError Crash on Null Step Status or Role
- Files: `src/components/more/qa/QaStepTimeline.tsx:204` and `src/components/more/qa/roleBadgeUtils.ts:7`
- Verbatim code:
  - `QaStepTimeline.tsx:204`: `const isStepPassed = st.status.toLowerCase() === "passed";`
  - `roleBadgeUtils.ts:7`: `const norm = roleName.toLowerCase();`
- Empirical proof:
  - `getRoleBadgeConfig(null)` throws `TypeError: Cannot read properties of null (reading 'toLowerCase')`.
  - Rendering `QaStepTimeline` with a step object where `status` is `null` throws `TypeError: Cannot read properties of null (reading 'toLowerCase')`, crashing the entire React render tree.

#### Bug 5: Blank Findings Breakdown in Runs Table
- File: `src/components/more/qa/QaRunHistoryTable.tsx`
- Lines: 140–165
- Empirical proof: If `r.findingCount > 0` but severity counts are all `0` (e.g., uncategorized run findings), all conditional severity pills (`r.criticalCount > 0`, etc.) evaluate to false, and `r.findingCount === 0` ("Clean") is also false. The `<td>` element renders an empty `<div></div>`, leaving the column completely blank while the Actions column displays `Findings (N)`.

---

## 2. Logic Chain

1. **Premise 1 (Zero-Pollution Auditability Contract)**:
   The core value proposition of the More Module QA Center (`ORIGINAL_REQUEST.md` R3 & R4) is guaranteeing that simulations roll back cleanly (`QA_SANDBOX_ROLLBACK_SUCCESS`) and that telemetry truthfully reports defects and rollback failures without false positives or ambiguity.

2. **Inference from Obs 1.2 (Bug 1 & Bug 3)**:
   - In `QaStepTimeline.tsx`, displaying `Operational Tables: Clean` alongside `QA_SANDBOX_ROLLBACK_FAILED` presents contradictory information that may mislead an operator into assuming database tables are clean after a failed rollback.
   - In `QaRunHistoryTable.tsx`, matching the substring `"sandbox"` in `r.summary` incorrectly treats `"Sandbox rollback failed"` as a successful rollback. Defaulting missing summaries to `true` further obscures failures.

3. **Inference from Obs 1.2 (Bug 2)**:
   - In `QaFindingsViewer.tsx`, the condition `if (selectedRunId && f.runId && f.runId !== selectedRunId)` fails to filter out findings where `f.runId == null`. When an operator clicks "Findings (N)" from `QaRunHistoryTable`, unrelated orphan findings are injected into that run's defect list.

4. **Inference from Obs 1.2 (Bug 4)**:
   - In `QaStepTimeline.tsx` and `roleBadgeUtils.ts`, directly calling `.toLowerCase()` on `st.status` and `roleName` without nullish coalescing violates defensive programming contracts and causes unhandled React crashes when unexpected null/undefined data arrives from external telemetry.

5. **Conclusion from Inferences**:
   While the core integration, query typing, and Next.js builds are functioning cleanly, these 5 UI defects compromise telemetry accuracy, risk misleading operators during failure triage, and introduce runtime crash surfaces. Therefore, changes must be requested before Milestone 2 can be approved.

---

## 3. Caveats

- **Compilation Cleanliness**: TypeScript compilation, ESLint, and Next.js production builds compile without warnings.
- **Physical View Alignments**: The mappings in `governance.ts` (`finding_type`, `recommendation`, `is_enabled`, `queue_status`) are structurally sound and pass all contract checks.
- **Scope**: Live Supabase database simulation against staging is reserved for Milestone 3 (E2E integration & zero-pollution database verification).

---

## 4. Conclusion

**Verdict: REQUEST_CHANGES**

The Milestone 2 UI components require surgical remediation for the 5 identified defects:

1. **`QaStepTimeline.tsx:185–188`**:
   Change static `<span>Operational Tables: Clean</span>` to:
   ```tsx
   <span>{isRolledBack ? "Operational Tables: Clean" : "Operational Tables: Potential Leak"}</span>
   ```

2. **`QaFindingsViewer.tsx:57`**:
   Fix filter condition from:
   ```tsx
   if (selectedRunId && f.runId && f.runId !== selectedRunId) return false;
   ```
   to:
   ```tsx
   if (selectedRunId && f.runId !== selectedRunId) return false;
   ```

3. **`QaRunHistoryTable.tsx:48–53`**:
   Fix rollback heuristic to require positive confirmation rather than loose `"sandbox"` substring matching, and default to `false` when unknown:
   ```tsx
   const isRolledBack =
     r.rolledBack ??
     (r.summary
       ? (r.summary.toLowerCase().includes("qa_sandbox_rollback_success") ||
          r.summary.toLowerCase().includes("zero data pollution") ||
          (r.summary.toLowerCase().includes("rolled back") && !r.summary.toLowerCase().includes("failed")))
       : false);
   ```

4. **`QaStepTimeline.tsx:204` & `roleBadgeUtils.ts:6–7`**:
   Add null guards:
   ```tsx
   // roleBadgeUtils.ts
   export function getRoleBadgeConfig(roleName: string | null | undefined): RoleBadgeConfig {
     const norm = (roleName ?? "").toLowerCase();
   ```
   ```tsx
   // QaStepTimeline.tsx:204
   const isStepPassed = (st.status ?? "").toLowerCase() === "passed";
   ```

5. **`QaRunHistoryTable.tsx:140–165`**:
   Add fallback for uncategorized findings:
   ```tsx
   {r.findingCount > 0 &&
    r.criticalCount === 0 &&
    r.highCount === 0 &&
    r.mediumCount === 0 &&
    r.lowCount === 0 && (
      <span className="text-text-secondary text-xs">{r.findingCount} total</span>
    )}
   ```

---

## 5. Verification Method

To independently reproduce all observations and confirm the findings:
1. Run the empirical stress harness:
   ```bash
   node scripts/test_m2_ui_challenger_stress.mjs
   ```
2. Verify baseline lint, unit tests, and production build:
   ```bash
   npm run lint
   npm test
   npm run build
   ```
3. Inspect lines:
   - `src/components/more/qa/QaStepTimeline.tsx:185-188, 204`
   - `src/components/more/qa/QaFindingsViewer.tsx:56-59`
   - `src/components/more/qa/QaRunHistoryTable.tsx:48-53, 140-165`
   - `src/components/more/qa/roleBadgeUtils.ts:6-8`
