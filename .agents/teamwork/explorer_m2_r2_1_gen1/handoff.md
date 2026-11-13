# Explorer Investigation Report: Bug 1 & Bug 4 Surgical Remediation Strategy

**Target Files**:
- `src/components/more/qa/QaStepTimeline.tsx`
- `src/components/more/qa/roleBadgeUtils.ts`

**Issues Analyzed**:
1. **Bug 1**: Contradictory "Operational Tables: Clean" in Rollback Failure Banner
2. **Bug 4**: Unhandled TypeError Crash on Null Step Status or Role

---

## 1. Observation

### Obs 1.1: Empirical Reproduction via Stress Test Harness
Execution of `node scripts/test_m2_ui_challenger_stress.mjs` directly reproduced and confirmed both vulnerabilities:
- **Test 2.7**: Confirmed that when `sandbox_rolled_back: false`, `QaStepTimeline` renders `QA_SANDBOX_ROLLBACK_FAILED`, `Leak Warning`, and an isolation warning, while simultaneously displaying `Operational Tables: Clean` in the exact same banner.
- **Test 5.1**: Confirmed `getRoleBadgeConfig(null)` throws verbatim:  
  `TypeError: Cannot read properties of null (reading 'toLowerCase')`.
- **Test 5.2**: Confirmed `QaStepTimeline` with `step.status: null` throws verbatim:  
  `TypeError: Cannot read properties of null (reading 'toLowerCase')`, crashing component rendering.

### Obs 1.2: Code Examination — Bug 1 in `QaStepTimeline.tsx`
In `src/components/more/qa/QaStepTimeline.tsx`:
- Line 72 derives the rollback flag:
  ```tsx
  const isRolledBack = result.sandbox_rolled_back ?? result.sandboxRolledBack ?? false;
  ```
- Lines 139–184 conditionally render the header, icon, and warning messages based on `isRolledBack`:
  - When `false`: renders `QA_SANDBOX_ROLLBACK_FAILED`, `Leak Warning`, and `"Isolation warning: subtransaction rollback was not confirmed. Live tables may have uncommitted test data."`
- Lines 185–188 unconditionally render static text:
  ```tsx
  <div className="flex items-center gap-1.5 text-xs text-text-muted font-mono bg-surface-primary px-2.5 py-1 rounded-lg border border-border-default">
    <Database className="h-3 w-3 text-brand-primary" />
    <span>Operational Tables: Clean</span>
  </div>
  ```
  The badge claims operational tables are "Clean" even when subtransaction rollback failed.

### Obs 1.3: Code Examination — Bug 4 in `roleBadgeUtils.ts`
In `src/components/more/qa/roleBadgeUtils.ts`:
- Lines 6–7:
  ```typescript
  export function getRoleBadgeConfig(roleName: string): RoleBadgeConfig {
    const norm = roleName.toLowerCase();
  ```
- If `roleName` is `null` or `undefined`, calling `.toLowerCase()` immediately throws a runtime `TypeError`.
- Line 47:
  ```typescript
  return {
    label: roleName,
    badgeClass: "bg-surface-subtle text-text-secondary border-border-default",
  };
  ```
  If `roleName` were `null`, returning `label: roleName` violates the TypeScript contract `RoleBadgeConfig { label: string }`.

### Obs 1.4: Code Examination — Bug 4 in `QaStepTimeline.tsx`
In `src/components/more/qa/QaStepTimeline.tsx`:
- Line 64:
  ```tsx
  const steps: QaScenarioStep[] = result.steps ?? [];
  ```
  Does not guard against elements within `steps` that are `null` or non-objects (e.g. `[null]`).
- Line 204:
  ```tsx
  const isStepPassed = st.status.toLowerCase() === "passed";
  ```
  Directly accesses `st.status.toLowerCase()`. If `st.status` is `null` or `undefined`, execution throws `TypeError: Cannot read properties of null (reading 'toLowerCase')`.
- Line 205:
  ```tsx
  const roleConfig = getRoleBadgeConfig(st.role);
  ```
  Passes `st.role` directly to `getRoleBadgeConfig`. If `st.role` is `null` or `undefined`, it triggers the unhandled exception in `roleBadgeUtils.ts`.
- Line 223:
  ```tsx
  {st.step}
  ```
  If `st.step` is missing or not numeric, the badge can render empty or `NaN`.

---

## 2. Logic Chain

1. **Premise 1 (Zero-Pollution Auditability & Operational Truth)**:  
   Per `ORIGINAL_REQUEST.md` R3/R4 and ADR-001/ADR-002 invariants, the QA Center UI must provide unambiguous telemetry. Misrepresenting operational database status after a failed rollback introduces serious triage confusion and false security.
2. **Inference from Obs 1.2 (Bug 1)**:  
   Because lines 185–188 are hardcoded without branching on `isRolledBack`, the UI presents conflicting indicators (an emergency leak banner alongside an emerald/brand "Clean" status pill). Binding this pill dynamically to `isRolledBack` with distinct semantic copy ("Operational Tables: Clean" vs "Operational Tables: Potential Leak") and danger styling eliminates the contradiction.
3. **Premise 2 (Defensive Runtime Resilience)**:  
   React components consuming external API/RPC data must be resilient to null, undefined, or malformed data shapes without unhandled exceptions crashing the entire tree.
4. **Inference from Obs 1.3 & 1.4 (Bug 4)**:  
   - In `roleBadgeUtils.ts`, normalizing `(roleName ?? "").toLowerCase().trim()` guarantees safe string operations regardless of input type.
   - Returning `roleName ?? "Unknown Role"` guarantees that empty string `""` preserves its label (satisfying Test 1.9) while `null`/`undefined` receives a meaningful, typed fallback string `"Unknown Role"`.
   - In `QaStepTimeline.tsx`, filtering `result.steps` for non-null objects and evaluating `String(st.status ?? "").toLowerCase() === "passed"` eliminates all possible null-dereference crashes on step arrays.

---

## 3. Caveats

- **Scope Boundary**: This report focuses strictly on `QaStepTimeline.tsx` and `roleBadgeUtils.ts` (Bug 1 and Bug 4). Findings filtering in `QaFindingsViewer.tsx` (Bug 2), rollback heuristics in `QaRunHistoryTable.tsx` (Bug 3 & 5), and RPC parsing in `governance.ts` are handled by peer explorers (`explorer_m2_r2_2_gen1` and `explorer_m2_r2_3_gen1`).
- **CSS Token Consistency**: All proposed styles use existing design tokens (`text-status-danger-text`, `border-status-danger-border`, `bg-surface-primary`, `text-text-muted`, `border-border-default`, `text-brand-primary`) to guarantee dark/light mode consistency without introducing arbitrary utility classes.

---

## 4. Conclusion & Surgical Fix Recommendations

### 4.1 Recommendation for `src/components/more/qa/roleBadgeUtils.ts`

**Target File**: `src/components/more/qa/roleBadgeUtils.ts`

```typescript
export interface RoleBadgeConfig {
  label: string;
  badgeClass: string;
}

export function getRoleBadgeConfig(roleName?: string | null): RoleBadgeConfig {
  const norm = (roleName ?? "").toLowerCase().trim();

  if (norm.includes("head admin") || norm.includes("super admin")) {
    return {
      label: "Head Admin",
      badgeClass: "bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-500/20",
    };
  }
  if (norm.includes("encoder")) {
    return {
      label: "Encoder",
      badgeClass: "bg-blue-500/10 text-blue-700 dark:text-blue-300 border-blue-500/20",
    };
  }
  if (norm.includes("recruitment") || norm.includes("recruiter")) {
    return {
      label: "Recruitment",
      badgeClass: "bg-teal-500/10 text-teal-700 dark:text-teal-300 border-teal-500/20",
    };
  }
  if (norm.includes("hrco") || norm.includes("operations")) {
    return {
      label: "HRCO",
      badgeClass: "bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/20",
    };
  }
  if (norm.includes("hr personnel") || norm.includes("hr staff") || norm.includes("personnel")) {
    return {
      label: "HR Personnel",
      badgeClass: "bg-indigo-500/10 text-indigo-700 dark:text-indigo-300 border-indigo-500/20",
    };
  }
  if (norm.includes("back office") || norm.includes("bo staff")) {
    return {
      label: "Back Office",
      badgeClass: "bg-slate-500/10 text-slate-700 dark:text-slate-300 border-slate-500/20",
    };
  }

  return {
    label: roleName ?? "Unknown Role",
    badgeClass: "bg-surface-subtle text-text-secondary border-border-default",
  };
}
```

### 4.2 Recommendation for `src/components/more/qa/QaStepTimeline.tsx`

**Target File**: `src/components/more/qa/QaStepTimeline.tsx`

#### Surgical Diff 1: Step array sanitization & total findings NaN defense (Lines 64–71)
**Before**:
```tsx
  const steps: QaScenarioStep[] = result.steps ?? [];
  const findingCounts = result.finding_counts ?? result.findingCounts ?? {};
  const totalFindings =
    findingCounts.total ??
    (Number(findingCounts.critical ?? 0) +
      Number(findingCounts.high ?? 0) +
      Number(findingCounts.medium ?? 0) +
      Number(findingCounts.low ?? 0));
```
**After**:
```tsx
  const steps: QaScenarioStep[] = (result.steps ?? []).filter(
    (s): s is QaScenarioStep => Boolean(s && typeof s === "object")
  );
  const findingCounts = result.finding_counts ?? result.findingCounts ?? {};
  const totalFindings = Number.isFinite(Number(findingCounts.total))
    ? Math.max(0, Number(findingCounts.total))
    : (Number(findingCounts.critical ?? 0) || 0) +
      (Number(findingCounts.high ?? 0) || 0) +
      (Number(findingCounts.medium ?? 0) || 0) +
      (Number(findingCounts.low ?? 0) || 0);
```

#### Surgical Diff 2: Dynamic operational tables status pill (Lines 185–188)
**Before**:
```tsx
        <div className="flex items-center gap-1.5 text-xs text-text-muted font-mono bg-surface-primary px-2.5 py-1 rounded-lg border border-border-default">
          <Database className="h-3 w-3 text-brand-primary" />
          <span>Operational Tables: Clean</span>
        </div>
```
**After**:
```tsx
        <div
          className={`flex items-center gap-1.5 text-xs font-mono px-2.5 py-1 rounded-lg border ${
            isRolledBack
              ? "text-text-muted bg-surface-primary border-border-default"
              : "text-status-danger-text bg-surface-primary border-status-danger-border"
          }`}
        >
          <Database
            className={`h-3 w-3 ${
              isRolledBack ? "text-brand-primary" : "text-status-danger-text"
            }`}
          />
          <span>
            {isRolledBack
              ? "Operational Tables: Clean"
              : "Operational Tables: Potential Leak"}
          </span>
        </div>
```

#### Surgical Diff 3: Null-safe step iteration and fallbacks (Lines 203–242)
**Before**:
```tsx
            {steps.map((st, idx) => {
              const isStepPassed = st.status.toLowerCase() === "passed";
              const roleConfig = getRoleBadgeConfig(st.role);
              const isLast = idx === steps.length - 1;

              return (
                <div key={st.step ?? idx} className="relative flex items-start gap-3">
                  {/* Step Connector Line */}
                  {!isLast && (
                    <div className="absolute left-3.5 top-7 bottom-0 w-0.5 bg-border-subtle" />
                  )}

                  {/* Step Circle Badge */}
                  <div
                    className={`relative z-10 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border text-xs font-mono font-bold ${
                      isStepPassed
                        ? "bg-status-success-bg text-status-success-text border-status-success-border"
                        : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
                    }`}
                  >
                    {st.step}
                  </div>

                  {/* Step Card */}
                  <div className="flex-1 rounded-xl border border-border-default bg-surface-subtle p-3 space-y-1.5 transition hover:border-border-strong">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        {/* Role Badge */}
                        <span
                          className={`rounded-full px-2.5 py-0.5 text-xs font-bold border ${roleConfig.badgeClass}`}
                        >
                          {roleConfig.label}
                        </span>

                        {/* Action Identifier */}
                        <code className="font-mono text-xs font-semibold text-text-primary">
                          {st.action}
                        </code>
                      </div>
```
**After**:
```tsx
            {steps.map((st, idx) => {
              const isStepPassed = String(st.status ?? "").toLowerCase() === "passed";
              const roleConfig = getRoleBadgeConfig(st.role);
              const isLast = idx === steps.length - 1;
              const stepNumber = Number.isFinite(Number(st.step)) ? Number(st.step) : idx + 1;
              const actionName = st.action ? String(st.action) : "unknown_action";

              return (
                <div key={st.step ?? idx} className="relative flex items-start gap-3">
                  {/* Step Connector Line */}
                  {!isLast && (
                    <div className="absolute left-3.5 top-7 bottom-0 w-0.5 bg-border-subtle" />
                  )}

                  {/* Step Circle Badge */}
                  <div
                    className={`relative z-10 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border text-xs font-mono font-bold ${
                      isStepPassed
                        ? "bg-status-success-bg text-status-success-text border-status-success-border"
                        : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
                    }`}
                  >
                    {stepNumber}
                  </div>

                  {/* Step Card */}
                  <div className="flex-1 rounded-xl border border-border-default bg-surface-subtle p-3 space-y-1.5 transition hover:border-border-strong">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        {/* Role Badge */}
                        <span
                          className={`rounded-full px-2.5 py-0.5 text-xs font-bold border ${roleConfig.badgeClass}`}
                        >
                          {roleConfig.label}
                        </span>

                        {/* Action Identifier */}
                        <code className="font-mono text-xs font-semibold text-text-primary">
                          {actionName}
                        </code>
                      </div>
```

---

## 5. Verification Method

### 5.1 Stress Harness Updates & Verification (`scripts/test_m2_ui_challenger_stress.mjs`)
Once the Worker applies the above surgical changes, update the adversarial assertions in `scripts/test_m2_ui_challenger_stress.mjs` to confirm remediation:

1. **Test 2.7 (Remediated Assertion)**:
   ```js
   const html = ReactDOMServer.renderToStaticMarkup(
     React.createElement(QaStepTimeline, {
       result: mockResult,
       isRunning: false,
       selectedScenarioCode: "FULL_E2E_RELAY",
     })
   );
   assert.equal(html.includes("Operational Tables: Clean"), false, "Contradictory Clean status must not be rendered on rollback failure");
   assert.ok(html.includes("Operational Tables: Potential Leak"), "Potential Leak status must be rendered on rollback failure");
   ```

2. **Test 5.1 (Remediated Assertion)**:
   ```js
   assert.doesNotThrow(() => {
     const confNull = getRoleBadgeConfig(null);
     assert.equal(confNull.label, "Unknown Role");
     assert.ok(confNull.badgeClass.includes("border-border-default"));

     const confUndef = getRoleBadgeConfig(undefined);
     assert.equal(confUndef.label, "Unknown Role");
   });
   ```

3. **Test 5.2 (Remediated Assertion)**:
   ```js
   assert.doesNotThrow(() => {
     const html = ReactDOMServer.renderToStaticMarkup(
       React.createElement(QaStepTimeline, {
         result: malformedResult,
         isRunning: false,
         selectedScenarioCode: "FULL_E2E_RELAY",
       })
     );
     assert.ok(html.includes("FAILED"), "Null status must safely render as FAILED pill without crashing");
   });
   ```

### 5.2 Independent Commands
1. Run the updated stress harness:
   ```bash
   node scripts/test_m2_ui_challenger_stress.mjs
   ```
2. Run standard project checks:
   ```bash
   npm run lint
   npm test
   npm run build
   ```
