# Handoff Report: Bug 2, Bug 3 & Bug 5 Deep-Dive Analysis & Surgical Fix Recommendations

**Author**: `explorer_m2_r2_2_gen1` (teamwork_explorer)  
**Target Components**:  
- `src/components/more/qa/QaFindingsViewer.tsx` (Bug 2)  
- `src/components/more/qa/QaRunHistoryTable.tsx` (Bug 3 & Bug 5)  
**Milestone**: Milestone 2 Gate Iteration 2  
**Recipient**: Parent Orchestrator (`b9c903a7-45a1-4b34-80f4-3b6e156a03d2`) / Worker  

---

## 1. Observation

### Obs 1.1: Bug 2 — Run ID Filter Isolation Leak (`QaFindingsViewer.tsx`)
- **File Location**: `src/components/more/qa/QaFindingsViewer.tsx`, lines 56–59.
- **Verbatim Current Code**:
  ```tsx
  const filteredFindings = findings.filter((f) => {
    if (selectedRunId && f.runId && f.runId !== selectedRunId) {
      return false;
    }
  ```
- **Observed Behavior**:
  - `selectedRunId` is passed from `QaCenterModal` when an operator clicks `Findings (N)` in `QaRunHistoryTable` (or filters by a specific simulation run).
  - In the telemetry database (`v_qa_audit_findings`, `v_qa_open_findings`), background probes, schema checks, and legacy anomalies can produce orphan findings where `run_id` is `NULL` (mapped to `f.runId?: string | null`).
  - When filtering by `selectedRunId = "run-target-123"`, an orphan finding with `f.runId = null` (or `undefined`) causes `f.runId` in the condition `selectedRunId && f.runId && f.runId !== selectedRunId` to evaluate to `false` (falsy).
  - Consequently, `return false;` is bypassed, and the orphan defect with `runId: null` leaks directly into the run-specific view.
  - **Empirical Proof**: Challenger harness test 3.5 (`scripts/test_m2_ui_challenger_stress.mjs:446-498`) proved that rendering findings containing target run findings, other run findings, and null-runId findings resulted in `containsOrphanNull === true`.

---

### Obs 1.2: Bug 3 — Heuristic False-Positive "Rolled Back" Badge on Rollback Failures (`QaRunHistoryTable.tsx`)
- **File Location**: `src/components/more/qa/QaRunHistoryTable.tsx`, lines 46–54.
- **Verbatim Current Code**:
  ```tsx
  // Check if sandbox rolled back based on rolledBack property or summary text
  const isRolledBack =
    r.rolledBack ??
    (r.summary
      ? r.summary.toLowerCase().includes("sandbox") ||
        r.summary.toLowerCase().includes("zero data pollution") ||
        r.summary.toLowerCase().includes("rolled back")
      : true);
  ```
- **Observed Behavior**:
  1. The Postgres view `v_qa_detection_run_summary` (`src/lib/queries/governance.ts:367-384`) does not have a dedicated `rolled_back` column, so `r.rolledBack` is `undefined` at runtime for all queried database runs.
  2. If a simulation suffers a subtransaction rollback failure, its summary explicitly logs:  
     `"Sandbox rollback failed: 4 uncommitted records remained in vacancies table."`
  3. The substring check `r.summary.toLowerCase().includes("sandbox")` matches `"sandbox"`, evaluating `isRolledBack` to `true`.
  4. Lines 114–124 render the emerald `Rolled Back` badge with `ShieldCheck` icon:
     ```tsx
     <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border border-emerald-500/30">
       <ShieldCheck className="h-3 w-3" />
       <span>Rolled Back</span>
     </span>
     ```
  5. Furthermore, if `r.summary` is `null` or missing, the ternary fallback defaults to `true`, unconditionally awarding a positive rollback badge to unverified runs.
  - **Empirical Proof**: Challenger harness test 4.3 (`scripts/test_m2_ui_challenger_stress.mjs:570-602`) proved that a run with `status: "failed"` and `summary: "Sandbox rollback failed: 4 uncommitted records remained in vacancies table"` rendered emerald `Rolled Back` without displaying `Check Rollback`.

---

### Obs 1.3: Bug 5 — Blank Findings Breakdown in Runs Table (`QaRunHistoryTable.tsx`)
- **File Location**: `src/components/more/qa/QaRunHistoryTable.tsx`, lines 139–165.
- **Verbatim Current Code**:
  ```tsx
  {/* Findings Breakdown */}
  <td className="py-3 px-4">
    <div className="flex items-center gap-1 text-xs font-semibold">
      {r.criticalCount > 0 && (
        <span className="bg-danger-surface text-danger-text border border-danger-border px-1.5 py-0.2 rounded-full">
          {r.criticalCount} crit
        </span>
      )}
      {r.highCount > 0 && (
        <span className="bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/30 px-1.5 py-0.2 rounded-full">
          {r.highCount} high
        </span>
      )}
      {r.mediumCount > 0 && (
        <span className="bg-blue-500/10 text-blue-700 dark:text-blue-400 border border-blue-500/30 px-1.5 py-0.2 rounded-full">
          {r.mediumCount} med
        </span>
      )}
      {r.lowCount > 0 && (
        <span className="bg-surface-subtle text-text-muted border border-border-default px-1.5 py-0.2 rounded-full">
          {r.lowCount} low
        </span>
      )}
      {r.findingCount === 0 && (
        <span className="text-text-primary text-xs font-medium">Clean</span>
      )}
    </div>
  </td>
  ```
- **Observed Behavior**:
  - In telemetry runs where `r.findingCount > 0` but severity counts are all `0` (e.g., uncategorized defects, custom probe findings, or unaggregated severities):
    - `r.criticalCount > 0` is `false`
    - `r.highCount > 0` is `false`
    - `r.mediumCount > 0` is `false`
    - `r.lowCount > 0` is `false`
    - `r.findingCount === 0` is `false`
  - The `<td>` element renders an empty `<div className="flex items-center gap-1 text-xs font-semibold"></div>`.
  - The cell appears completely blank, while the adjacent Actions column displays a prominent red button: `Findings (N)`.
  - **Empirical Proof**: Challenger stress inspection confirmed that any non-zero finding run without breakdown severities produces an empty cell.

---

### Obs 1.4: Secondary Boundary Vulnerability in `QaRunHistoryTable.tsx`
- **File Location**: `src/components/more/qa/QaRunHistoryTable.tsx`, line 42.
- **Verbatim Code**:
  ```tsx
  const statusLower = r.status.toLowerCase();
  ```
- **Observed Behavior**: If `r.status` is nullish from malformed telemetry, calling `.toLowerCase()` throws an unhandled `TypeError: Cannot read properties of null (reading 'toLowerCase')`, crashing the table.

---

## 2. Logic Chain

1. **Bug 2 Isolation Logic**:
   - The user's contract when specifying `selectedRunId` is strict run isolation: only findings generated by that exact simulation run must be shown.
   - In JavaScript, `A && B && B !== C`:
     - When $A = \text{"run-123"}$, $B = \text{null}$, the expression evaluates to `null` (falsy).
     - The filter callback does NOT return `false`, so the null item is retained.
   - The required predicate is: "If a run filter is active, any finding whose `runId` does not equal `selectedRunId` MUST be excluded."
   - In code: `if (selectedRunId && f.runId !== selectedRunId) return false;`.
   - When $f.runId = \text{null}$, $\text{null} \neq \text{"run-123"}$ is `true`. The condition fires, returning `false`, cleanly excluding the orphan finding.

2. **Bug 3 Rollback Telemetry Truthfulness Logic**:
   - The primary invariant of QA simulation (`ORIGINAL_REQUEST.md` R3) is zero data pollution via verified subtransaction rollback.
   - An emerald "Rolled Back" badge (`ShieldCheck`) conveys absolute safety to compliance and QA operators.
   - Substring `"sandbox"` is an environmental qualifier, not an outcome assertion (e.g. `"sandbox rollback failed"` contains `"sandbox"`).
   - Missing summary cannot be assumed safe; unverified runs must default to `false` (`ShieldAlert` "Check Rollback").
   - Rollback confirmation must strictly require:
     1. Direct `r.rolledBack === true`, OR
     2. Verifiable success tokens: `"qa_sandbox_rollback_success"` or `"zero data pollution"`, OR
     3. Positive `"rolled back"` WITHOUT negative qualifier words (`"failed"`, `"leak"`, `"error"`).

3. **Bug 5 Telemetry Visual Completeness Logic**:
   - Every table row must visually account for `findingCount`.
   - If specific severity counts sum to 0 but `findingCount > 0`, the UI must display a fallback summary pill (`{r.findingCount} total`).
   - If `findingCount === 0`, it displays `Clean`.
   - The cell should never render an empty container.

---

## 3. Caveats

1. **Database Schema Continuity**: We are NOT modifying database migrations or views in this step (`v_qa_detection_run_summary` remains untouched). The fixes operate purely within React UI components to handle existing database contracts defensively.
2. **Sibling Component Scope**: Bug 1 and Bug 4 (in `QaStepTimeline.tsx` and `roleBadgeUtils.ts`) are being addressed in parallel by `explorer_m2_r2_1_gen1`. This handoff focuses exclusively on `QaFindingsViewer.tsx` (Bug 2) and `QaRunHistoryTable.tsx` (Bug 3 & 5).
3. **Adversarial Harness Transition**: In `scripts/test_m2_ui_challenger_stress.mjs`, Challenger 2's tests 3.5 and 4.3 were written to assert that vulnerabilities existed. The Worker must update those assertions to verify the fixed behavior (e.g. `assert.equal(containsOrphanNull, false)`).

---

## 4. Conclusion & Surgical Fix Recommendations

### Recommendation 1: Fix Bug 2 in `src/components/more/qa/QaFindingsViewer.tsx`

**Target Lines**: 56–59  
Remove the middle `&& f.runId` check so that `null` or `undefined` `runId`s are strictly filtered out when `selectedRunId` is active.

#### Exact Code Diff:
```diff
--- a/src/components/more/qa/QaFindingsViewer.tsx
+++ b/src/components/more/qa/QaFindingsViewer.tsx
@@ -56,3 +56,3 @@
   const filteredFindings = findings.filter((f) => {
-    if (selectedRunId && f.runId && f.runId !== selectedRunId) {
+    if (selectedRunId && f.runId !== selectedRunId) {
       return false;
```

---

### Recommendation 2: Fix Bug 3 & Defensive Status in `src/components/more/qa/QaRunHistoryTable.tsx`

**Target Lines**: 42–54  
Add null guard to `r.status`, rewrite the rollback heuristic to require positive confirmation and reject negative qualifiers (`failed`, `leak`), and default unknown/null summaries to `false`.

#### Exact Code Diff:
```diff
--- a/src/components/more/qa/QaRunHistoryTable.tsx
+++ b/src/components/more/qa/QaRunHistoryTable.tsx
@@ -42,13 +42,17 @@
-              const statusLower = r.status.toLowerCase();
+              const statusLower = (r.status ?? "").toLowerCase();
               const isSuccess = statusLower === "passed" || statusLower === "completed";
               const isFailed = statusLower === "failed" || r.criticalCount > 0;
 
-              // Check if sandbox rolled back based on rolledBack property or summary text
+              // Check if sandbox rolled back based on rolledBack property or positive confirmation in summary text
+              const summaryLower = (r.summary ?? "").toLowerCase();
               const isRolledBack =
                 r.rolledBack ??
-                (r.summary
-                  ? r.summary.toLowerCase().includes("sandbox") ||
-                    r.summary.toLowerCase().includes("zero data pollution") ||
-                    r.summary.toLowerCase().includes("rolled back")
-                  : true);
+                (Boolean(r.summary) &&
+                  (summaryLower.includes("qa_sandbox_rollback_success") ||
+                    summaryLower.includes("zero data pollution") ||
+                    (summaryLower.includes("rolled back") &&
+                      !summaryLower.includes("failed") &&
+                      !summaryLower.includes("leak"))));
```

---

### Recommendation 3: Fix Bug 5 in `src/components/more/qa/QaRunHistoryTable.tsx`

**Target Lines**: 139–165  
Introduce a structured ternary: if any specific severity count is $> 0$, render the severity pills; otherwise, if `r.findingCount > 0`, render `{r.findingCount} total`; otherwise, render `Clean`.

#### Exact Code Diff:
```diff
--- a/src/components/more/qa/QaRunHistoryTable.tsx
+++ b/src/components/more/qa/QaRunHistoryTable.tsx
@@ -140,26 +140,32 @@
                     <div className="flex items-center gap-1 text-xs font-semibold">
-                      {r.criticalCount > 0 && (
-                        <span className="bg-danger-surface text-danger-text border border-danger-border px-1.5 py-0.2 rounded-full">
-                          {r.criticalCount} crit
-                        </span>
-                      )}
-                      {r.highCount > 0 && (
-                        <span className="bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/30 px-1.5 py-0.2 rounded-full">
-                          {r.highCount} high
-                        </span>
-                      )}
-                      {r.mediumCount > 0 && (
-                        <span className="bg-blue-500/10 text-blue-700 dark:text-blue-400 border border-blue-500/30 px-1.5 py-0.2 rounded-full">
-                          {r.mediumCount} med
-                        </span>
-                      )}
-                      {r.lowCount > 0 && (
-                        <span className="bg-surface-subtle text-text-muted border border-border-default px-1.5 py-0.2 rounded-full">
-                          {r.lowCount} low
-                        </span>
-                      )}
-                      {r.findingCount === 0 && (
+                      {r.criticalCount > 0 || r.highCount > 0 || r.mediumCount > 0 || r.lowCount > 0 ? (
+                        <>
+                          {r.criticalCount > 0 && (
+                            <span className="bg-danger-surface text-danger-text border border-danger-border px-1.5 py-0.2 rounded-full">
+                              {r.criticalCount} crit
+                            </span>
+                          )}
+                          {r.highCount > 0 && (
+                            <span className="bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/30 px-1.5 py-0.2 rounded-full">
+                              {r.highCount} high
+                            </span>
+                          )}
+                          {r.mediumCount > 0 && (
+                            <span className="bg-blue-500/10 text-blue-700 dark:text-blue-400 border border-blue-500/30 px-1.5 py-0.2 rounded-full">
+                              {r.mediumCount} med
+                            </span>
+                          )}
+                          {r.lowCount > 0 && (
+                            <span className="bg-surface-subtle text-text-muted border border-border-default px-1.5 py-0.2 rounded-full">
+                              {r.lowCount} low
+                            </span>
+                          )}
+                        </>
+                      ) : r.findingCount > 0 ? (
+                        <span className="bg-surface-subtle text-text-secondary border border-border-default px-2 py-0.5 rounded-full text-xs font-medium">
+                          {r.findingCount} total
+                        </span>
+                      ) : (
                         <span className="text-text-primary text-xs font-medium">Clean</span>
                       )}
                     </div>
```

---

## 5. Verification Method

### Step 1: Stress Test Harness Assertions Update (`scripts/test_m2_ui_challenger_stress.mjs`)
Update the adversarial assertions in the stress test suite to verify that the vulnerabilities are resolved:
1. **Test 3.5 (Run ID Isolation)**:
   ```javascript
   assert.equal(containsTarget, true, "Target run defect must be shown");
   assert.equal(containsOther, false, "Other run defect must be filtered out");
   assert.equal(containsOrphanNull, false, "Orphan defect with null runId must NOT leak into filtered run view");
   ```
2. **Test 4.3 (Rollback False Positive)**:
   ```javascript
   const falselyAwardedRolledBack = html.includes("Rolled Back") && !html.includes("Check Rollback");
   assert.equal(falselyAwardedRolledBack, false, "Failed rollback must NOT be awarded green Rolled Back badge");
   assert.ok(html.includes("Check Rollback"), "Failed rollback must display Check Rollback warning badge");
   ```
3. **Test 4.6 (Add Uncategorized Findings Test)**:
   ```javascript
   runChallengerTest("4.6: Uncategorized findings render fallback total pill", () => {
     const uncatRun = [{
       id: "run-uncat",
       agentName: "Probe",
       status: "failed",
       targetModule: "vacancies",
       findingCount: 3,
       criticalCount: 0,
       highCount: 0,
       mediumCount: 0,
       lowCount: 0,
       startedAt: null,
       completedAt: null,
       summary: null,
     }];
     const html = ReactDOMServer.renderToStaticMarkup(React.createElement(QaRunHistoryTable, { runs: uncatRun }));
     assert.ok(html.includes("3 total"), "Must render '3 total' for uncategorized findings");
   });
   ```

### Step 2: Independent Verification Commands
Execute the following verification sequence:
```bash
# 1. Run the stress test suite
node scripts/test_m2_ui_challenger_stress.mjs

# 2. Run lint and SQL contract checks
npm run lint

# 3. Run unit tests
npm test

# 4. Verify Next.js production build
npm run build
```

### Invalidation Conditions
- Any orphan defect (`runId === null` or `runId === undefined`) renders when `selectedRunId` is set to any valid string.
- Any run whose summary reports a rollback failure, leak, or error renders the green `Rolled Back` badge.
- Any run with `findingCount > 0` renders an empty `<div></div>` in the Findings column.
