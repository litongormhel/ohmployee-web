# Milestone 2 Hardening Investigation Report: Governance Query Hooks

**Agent**: `explorer_m2_r2_3_gen1` (Teamwork Explorer / Forensic Analyst)  
**Target Subject**: Hardening opportunities in `src/lib/queries/governance.ts` (`runQaScenarioRpc`)  
**Context**: Milestone 2 Gate Iteration 1 Review Hardening (incorporating findings from Challenger 1, Challenger 2, and Auditor 1)  
**Deliverable**: Surgical code fix strategy for `teamwork_worker_m2`  

---

## 1. Observation

Direct inspection of `src/lib/queries/governance.ts` lines 562–610 revealed three runtime edge-case vulnerabilities in `runQaScenarioRpc`:

### Obs 1.1: Vulnerability 1 — `rawSteps.map` crashes on explicit `null` items
- **File**: `src/lib/queries/governance.ts`
- **Lines**: 570–577
- **Current Code**:
  ```typescript
  const rawSteps = Array.isArray(raw.steps) ? raw.steps : [];
  const steps: QaScenarioStep[] = rawSteps.map((s: Record<string, unknown>, idx: number) => ({
    step: Number(s.step ?? idx + 1),
    role: String(s.role ?? "System"),
    action: String(s.action ?? "unknown_action"),
    status: (s.status === "failed" ? "failed" : "passed") as "passed" | "failed",
    details: String(s.details ?? ""),
  }));
  ```
- **Observed Behavior**:
  `Array.isArray(raw.steps)` validates only that the outer container is an array. If `raw.steps` contains an explicit `null` or `undefined` item (e.g. `steps: [null]`), the iterator `s` is `null`. At line 572, evaluating `s.step` immediately throws:
  ```
  TypeError: Cannot read properties of null (reading 'step')
  ```
  This unhandled exception rejects the `runQaScenarioRpc` promise, causing `useRunQaScenario` mutation to fail without returning any structured result to the UI.

### Obs 1.2: Vulnerability 2 — Non-numeric strings in `step.step` produce `NaN`
- **File**: `src/lib/queries/governance.ts`
- **Line**: 572
- **Current Code**:
  ```typescript
  step: Number(s.step ?? idx + 1),
  ```
- **Observed Behavior**:
  The nullish coalescing operator `??` only triggers when `s.step` is `null` or `undefined`. If `s.step` is a non-numeric string (e.g., `"step_one"`, `"setup"`, or `"N/A"`), `s.step ?? idx + 1` evaluates to `"step_one"`.
  `Number("step_one")` evaluates to `NaN`.
  Downstream, `step: NaN` serializes to `null` in JSON (`JSON.stringify({ step: NaN }) === '{"step":null}'`), corrupts step ordering in timeline components, and produces `Step NaN` or visual glitches in `<QaStepTimeline />`.

### Obs 1.3: Vulnerability 3 — Non-numeric or missing properties in `finding_counts` produce `NaN`
- **File**: `src/lib/queries/governance.ts`
- **Lines**: 579–586
- **Current Code**:
  ```typescript
  const rawCounts = (raw.finding_counts ?? {}) as Record<string, unknown>;
  const findingCounts = {
    critical: Number(rawCounts.critical ?? 0),
    high: Number(rawCounts.high ?? 0),
    medium: Number(rawCounts.medium ?? 0),
    low: Number(rawCounts.low ?? 0),
    total: Number(rawCounts.total ?? 0),
  };
  ```
- **Observed Behavior**:
  1. If `raw.finding_counts` is non-object (e.g., a primitive string `"uncounted"` or `null`), `(raw.finding_counts ?? {})` may preserve invalid types.
  2. If any property (e.g., `rawCounts.critical`) contains a non-numeric string (e.g., `"uncounted"`, `"NaN"`, or `"error"` from SQL exceptions), `Number("uncounted" ?? 0)` evaluates to `NaN`.
  3. When an exception occurs during scenario completion in PostgreSQL (`supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql:649`), `v_counts` is returned as `jsonb_build_object('error', SQLERRM)`. In that case, `total` is `0`, but individual severities remain uncoalesced if corrupted.
  4. Negative numbers (e.g., `-1`) are not guarded against.

---

## 2. Logic Chain

1. **Step 1 — Execution Surface Mapping**:
   The TypeScript function `runQaScenarioRpc` deserializes JSON returned from Supabase RPC `public.qa_run_scenario`. While standard database executions construct `v_steps` using `jsonb_build_object` and `v_counts` via `public.qa_complete_detection_run`, defensive programming standards require that frontend query hooks safely handle corrupted payloads, unexpected database error payloads, and mock test fixtures without throwing unhandled runtime exceptions.

2. **Step 2 — Root Cause Analysis of Bug 1 (Null Steps Array Element)**:
   - `Array.isArray(raw.steps)` is `true` for `[null]`.
   - The type assertion `(s: Record<string, unknown>, idx: number)` is a compile-time assertion that does not enforce runtime non-nullity.
   - At runtime, `null.step` is an illegal property access in JavaScript.
   - **Remedy**: Filter `raw.steps` before mapping with a strict runtime type guard:
     `s !== null && typeof s === "object" && !Array.isArray(s)`
     This discards explicit `null`, `undefined`, and primitive array elements before they reach property accessors.

3. **Step 3 — Root Cause Analysis of Bug 2 (`NaN` Step Number)**:
   - In JavaScript, `Number("invalid_string")` is `NaN`.
   - `NaN` is of type `number`, but `Number.isFinite(NaN)` is `false`.
   - Steps in the simulation engine are strictly 1-based positive integers (`v_step_num := 1..7`).
   - **Remedy**: Evaluate `const rawStepNum = Number(s?.step);`. If `Number.isFinite(rawStepNum) && rawStepNum > 0`, return `Math.floor(rawStepNum)`; otherwise fallback safely to `idx + 1`.

4. **Step 4 — Root Cause Analysis of Bug 3 (`NaN` in Finding Counts)**:
   - When converting arbitrary external values to non-negative integer counts, `Number.isFinite(n) && n >= 0 ? Math.floor(n) : 0` guarantees that `NaN`, `Infinity`, negative numbers, strings, and `undefined` coalesce cleanly to `0`.
   - If `rawCounts.total` is missing or `0`, but individual severity counts (`critical`, `high`, `medium`, `low`) exist, computing `critical + high + medium + low` preserves truthful reporting of defects.

5. **Step 5 — Empirical Proof**:
   An empirical verification script (`test_hardening.mjs`) was executed across 7 adversarial edge cases (including `[null]`, non-numeric strings, negative numbers, missing counts, and SQL error shapes). All 7 evaluated cleanly without throwing exceptions, producing 100% finite, non-negative, and properly indexed output structures.

---

## 3. Caveats

1. **Database Contract Parity**:
   In normal operation against PostgreSQL (`supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`), `qa_run_scenario` constructs `v_steps` via PL/pgSQL `jsonb_build_object` and `v_counts` via SQL aggregations. Normal database execution will not produce `null` step items. However, client-side hardening is essential for defending against:
   - Partial JSON serialization failures or HTTP truncation.
   - Adversarial or mock test fixtures.
   - Future migrations that might introduce optional or asynchronous step generation.
2. **Scope Boundary**:
   This report specifically scopes hardening to `src/lib/queries/governance.ts` (`runQaScenarioRpc`). UI component hardening (`QaStepTimeline.tsx`, `QaRunHistoryTable.tsx`, `QaFindingsViewer.tsx`, and `roleBadgeUtils.ts`) addresses Bug 1–5 identified by Challenger 2, which are complementary and should be applied in tandem by the Worker.

---

## 4. Conclusion & Surgical Fix Recommendation

### Exact Surgical Replacement for `src/lib/queries/governance.ts`

**Location**: Lines 569–608 in `src/lib/queries/governance.ts`

#### Current Code (Lines 569–608):
```typescript
  const raw = (data ?? {}) as Record<string, unknown>;
  const rawSteps = Array.isArray(raw.steps) ? raw.steps : [];
  const steps: QaScenarioStep[] = rawSteps.map((s: Record<string, unknown>, idx: number) => ({
    step: Number(s.step ?? idx + 1),
    role: String(s.role ?? "System"),
    action: String(s.action ?? "unknown_action"),
    status: (s.status === "failed" ? "failed" : "passed") as "passed" | "failed",
    details: String(s.details ?? ""),
  }));

  const rawCounts = (raw.finding_counts ?? {}) as Record<string, unknown>;
  const findingCounts = {
    critical: Number(rawCounts.critical ?? 0),
    high: Number(rawCounts.high ?? 0),
    medium: Number(rawCounts.medium ?? 0),
    low: Number(rawCounts.low ?? 0),
    total: Number(rawCounts.total ?? 0),
  };

  const success = Boolean(raw.success);
  const runId = String(raw.run_id ?? "");
  const scenarioCodeResolved = String(raw.scenario_code ?? scenarioCode);
  const sandboxRolledBack = Boolean(raw.sandbox_rolled_back);
  const executedAt = String(raw.executed_at ?? new Date().toISOString());

  return {
    success,
    run_id: runId,
    scenario_code: scenarioCodeResolved,
    sandbox_rolled_back: sandboxRolledBack,
    steps,
    finding_counts: findingCounts,
    executed_at: executedAt,
    // Convenience aliases
    runId,
    scenarioCode: scenarioCodeResolved,
    sandboxRolledBack,
    findingCounts,
    executedAt,
  };
```

#### Recommended Hardened Code:
```typescript
  const raw = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;

  // Defend against null, undefined, primitive, or array items inside steps array
  const rawSteps = Array.isArray(raw.steps)
    ? raw.steps.filter(
        (s): s is Record<string, unknown> => s !== null && typeof s === "object" && !Array.isArray(s)
      )
    : [];

  const steps: QaScenarioStep[] = rawSteps.map((s: Record<string, unknown>, idx: number) => {
    const rawStepNum = Number(s?.step);
    const step = Number.isFinite(rawStepNum) && rawStepNum > 0 ? Math.floor(rawStepNum) : idx + 1;
    const rawStatus = typeof s?.status === "string" ? s.status.trim().toLowerCase() : "";
    const status: "passed" | "failed" = rawStatus === "failed" ? "failed" : "passed";

    return {
      step,
      role: String(s?.role ?? "System"),
      action: String(s?.action ?? "unknown_action"),
      status,
      details: String(s?.details ?? ""),
    };
  });

  // Defend against non-object or malformed finding_counts
  const rawCounts = (raw.finding_counts &&
  typeof raw.finding_counts === "object" &&
  !Array.isArray(raw.finding_counts)
    ? raw.finding_counts
    : {}) as Record<string, unknown>;

  const toSafeCount = (val: unknown): number => {
    const num = Number(val);
    return Number.isFinite(num) && num >= 0 ? Math.floor(num) : 0;
  };

  const critical = toSafeCount(rawCounts.critical);
  const high = toSafeCount(rawCounts.high);
  const medium = toSafeCount(rawCounts.medium);
  const low = toSafeCount(rawCounts.low);
  const rawTotal = toSafeCount(rawCounts.total);
  const total = rawTotal > 0 ? rawTotal : critical + high + medium + low;

  const findingCounts = {
    critical,
    high,
    medium,
    low,
    total,
  };

  const success = Boolean(raw.success);
  const runId = String(raw.run_id ?? "");
  const scenarioCodeResolved = String(raw.scenario_code ?? scenarioCode);
  const sandboxRolledBack = Boolean(raw.sandbox_rolled_back);
  const executedAt = String(raw.executed_at ?? new Date().toISOString());

  return {
    success,
    run_id: runId,
    scenario_code: scenarioCodeResolved,
    sandbox_rolled_back: sandboxRolledBack,
    steps,
    finding_counts: findingCounts,
    executed_at: executedAt,
    // Convenience aliases
    runId,
    scenarioCode: scenarioCodeResolved,
    sandboxRolledBack,
    findingCounts,
    executedAt,
  };
```

---

## 5. Verification Method

To independently verify the hardened logic:

1. **Run the dedicated empirical test harness**:
   ```bash
   node .agents/teamwork/explorer_m2_r2_3_gen1/test_hardening.mjs
   ```
   *Expected Output*: `=== ALL SCENARIOS EVALUATED CLEANLY WITH ZERO EXCEPTIONS ===` across all 7 scenarios (including `[null]` steps and non-numeric counts).

2. **Run repository contract and build tests**:
   ```bash
   npm run check:adr
   npm run check:sql
   npm run lint
   npm test
   npm run build
   ```
   *Expected Output*:
   - `check:adr`: `ADR_MIRROR_STATUS: FRESH`
   - `check:sql`: `SQL_CONTRACTS_OK` (28 core tables & 19 RPC contracts verified)
   - `lint`: 0 errors, 0 warnings
   - `test`: 211 tests pass
   - `build`: 20/20 routes compiled successfully with Turbopack
