# Forensic Audit Report: Milestone 2 (Governance Query Hooks & QA Center UI Integration)

**Work Product**: Milestone 2 Deliverables (`src/lib/queries/governance.ts`, `src/components/more/QaCenterModal.tsx`, `src/components/more/qa/*`)  
**Profile**: General Project  
**Integrity Mode**: Development Mode (as specified in `ORIGINAL_REQUEST.md`)  
**Verdict**: **CLEAN**

---

## Phase Results

| Check Name | Status | Details |
|---|:---:|---|
| **Hardcoded Test Results** | **PASS** | No hardcoded simulation steps, pass/fail results, or fake counts found in `governance.ts` or UI components. Steps are dynamically parsed from Supabase RPC payload. |
| **Facade Implementations** | **PASS** | `runQaScenarioRpc` genuinely invokes Supabase RPC `public.qa_run_scenario`. Query hook `useRunQaScenario` binds mutation and triggers reactive snapshot invalidation. |
| **View Contract Fidelity** | **PASS** | View mappers in `fetchQaCenterSnapshot` correspond exactly to physical database views in `supabase/migrations/20260521062543_remote_schema.sql` (`v_qa_open_findings`, `v_qa_schedules`, `v_qa_run_queue`, `v_qa_daily_reports`, `v_qa_detection_run_summary`). No fabricated data. |
| **Execution Validation** | **PASS** | `QaCenterModal` wires to live hooks (`useQaCenterSnapshot`, `useRunQaScenario`, `useRunQaCoreDetectionSuite`, `useGenerateDailyQaReport`). Execution state triggers reactive UI updates in `QaStepTimeline`, `QaFindingsViewer`, and `QaRunHistoryTable`. |
| **SQL Contract Guard** | **PASS** | `npm run check:sql` verified 28 core tables & 19 cross-module RPC contracts across 631 migrations (`SQL_CONTRACTS_OK`). |
| **ADR Freshness Check** | **PASS** | `npm run check:adr` confirmed ADR-001 and ADR-002 are up to date (`ADR_MIRROR_STATUS: FRESH`). |
| **Lint & TypeScript Validation** | **PASS** | `npm run lint` exited with code 0 (0 errors, 0 warnings). |
| **Independent Unit Test Suite** | **PASS** | `npm test` executed 211 tests with 211 pass, 0 fail. |
| **Production Build Execution** | **PASS** | `npm run build` compiled all 20 static and dynamic Next.js routes successfully using Turbopack in 10.0s. |

---

## 5-Component Handoff Protocol

### 1. Observation

- **Obs 1.1 (Dynamic Parsing vs Hardcoded Stubs)**:
  In `src/lib/queries/governance.ts:563-611`:
  ```ts
  export async function runQaScenarioRpc(scenarioCode: string): Promise<QaScenarioRunResult> {
    const supabase = createClient();
    const { data, error } = await supabase.rpc("qa_run_scenario", {
      p_scenario_code: scenarioCode.trim(),
    });
    if (error) throw error;

    const raw = (data ?? {}) as Record<string, unknown>;
    const rawSteps = Array.isArray(raw.steps) ? raw.steps : [];
    const steps: QaScenarioStep[] = rawSteps.map((s: Record<string, unknown>, idx: number) => ({
      step: Number(s.step ?? idx + 1),
      role: String(s.role ?? "System"),
      action: String(s.action ?? "unknown_action"),
      status: (s.status === "failed" ? "failed" : "passed") as "passed" | "failed",
      details: String(s.details ?? ""),
    }));
  ...
  ```
  `runQaScenarioRpc` calls the physical database RPC function `public.qa_run_scenario` with parameter `p_scenario_code`. There are no hardcoded step arrays or stubbed return values.

- **Obs 1.2 (View Column Fidelity Against Physical Schema)**:
  In `supabase/migrations/20260521062543_remote_schema.sql`:
  - `v_qa_open_findings` (lines 5412-5429) returns `f.id`, `f.run_id`, `f.severity`, `f.finding_type`, `f.module_name`, `f.reference_table`, `f.reference_record_id`, `f.title`, `f.details`, `f.recommendation`, `f.status`, `f.created_at`.
  - `v_qa_schedules` (lines 5452-5467) returns `schedule_name`, `suite_name`, `frequency`, `run_time`, `is_enabled`, `last_run_at`, `next_run_at`.
  - `v_qa_run_queue` (lines 5432-5449) returns `schedule_id`, `suite_name`, `queue_status`, `run_id`, `retry_count`, `max_retries`.
  - `v_qa_daily_reports` (lines 5325-5348) returns `critical_count`, `generated_at`, `health_status`, `most_unstable_workflow`.
  - `v_qa_detection_run_summary` (lines 5351-5367) returns `r.summary`, `r.execution_type`.
  In `src/lib/queries/governance.ts:367-488`, each of these view fields is explicitly parsed and mapped into the respective TypeScript interfaces, resolving previous property mismatches (`f.finding_code`, `s.cron_expression`, `s.is_active`, `q.status`, `dr.critical_findings`).

- **Obs 1.3 (Component Live Wiring)**:
  In `src/components/more/QaCenterModal.tsx`:
  - Lines 57-60 instantiate `useQaCenterSnapshot()`, `useRunQaCoreDetectionSuite()`, `useRunQaScenario()`, and `useGenerateDailyQaReport()`.
  - Lines 78-92 handle scenario execution by calling `runScenarioMutation.mutateAsync(selectedScenario)`, saving the typed return payload into `lastScenarioResult`, and routing alerts based on `res?.success`.
  - Line 281 passes `lastScenarioResult` to `<QaStepTimeline result={lastScenarioResult} isRunning={runScenarioMutation.isPending} selectedScenarioCode={selectedScenario} />`.
  - Lines 433-448 integrate `<QaRunHistoryTable runs={runs} />` and `<QaFindingsViewer findings={findings} />`.

- **Obs 1.4 (Build & Test Tool Outputs)**:
  - `npm run check:adr` -> `[adr] ADR_MIRROR_STATUS: FRESH — ADR-001 (3729ccb), ADR-002 (49d7a40)`
  - `npm run check:sql` -> `[sql-guard] SQL_CONTRACTS_OK — verified 28 core tables & 19 cross-module RPC contracts across 631 migrations.`
  - `npm test` -> `ℹ tests 211, ℹ suites 0, ℹ pass 211, ℹ fail 0, ℹ duration_ms 5140.5`
  - `npm run lint` -> Exited 0 with 0 errors, 0 warnings.
  - `npm run build` -> Exited 0, Turbopack compiled 20/20 routes successfully.

---

### 2. Logic Chain

1. **Step 1 (Integrity Mode Identification)**:
   `ORIGINAL_REQUEST.md` specifies `Integrity mode: development`. In development mode, the auditor checks specifically for hardcoded test results, facade implementations, and fabricated verification artifacts.
2. **Step 2 (Empirical Verification of RPC Call & Hooks)**:
   Inspection of `src/lib/queries/governance.ts` lines 563-622 confirms that `runQaScenarioRpc` directly invokes `supabase.rpc("qa_run_scenario")` and returns the actual RPC payload. It does not short-circuit or return canned responses.
3. **Step 3 (Schema Parity)**:
   Cross-checking the 5 updated view mappings in `fetchQaCenterSnapshot` against `supabase/migrations/20260521062543_remote_schema.sql` confirms that all mapped columns exist in physical views. Defect codes, remediation guidance, schedule frequencies, and queue statuses reflect authentic database values.
4. **Step 4 (UI Wiring & Feedback Loop)**:
   Trace of `QaCenterModal.tsx` confirms that clicking "Run Scenario" executes the mutation against the backend and feeds the result into `<QaStepTimeline />`. The timeline dynamically iterates over `result.steps` and renders the `QA_SANDBOX_ROLLBACK_SUCCESS` badge based on `result.sandbox_rolled_back`.
5. **Step 5 (Empirical Build & Test Verification)**:
   Independent execution of `npm run check:adr`, `npm run check:sql`, `npm test`, `npm run lint`, and `npm run build` confirmed zero compilation errors, zero lint warnings, and 100% passing tests.

---

### 3. Caveats & Adversarial Findings

While no integrity violations exist, adversarial stress testing revealed 3 defensive edge-case opportunities for Milestone 3 hardening:

1. **Adversarial Finding 1 (Medium - Null element in steps array)**:
   In `src/lib/queries/governance.ts:571`:
   `rawSteps.map((s: Record<string, unknown>, idx: number) => ({ step: Number(s.step ?? idx + 1) ... }))`
   If the database RPC returns an array containing `null` (e.g., `steps: [null]`), `s.step` throws `TypeError: Cannot read properties of null (reading 'step')`. While the database function `qa_run_scenario` builds valid objects via `jsonb_build_object()`, adding optional chaining (`s?.step`) would provide complete defensive hardening.
2. **Adversarial Finding 2 (Low - Status toLowerCase on malformed step object)**:
   In `src/components/more/qa/QaStepTimeline.tsx:204`:
   `const isStepPassed = st.status.toLowerCase() === "passed";`
   If a custom scenario returns a step missing the `status` property, calling `.toLowerCase()` on undefined will throw. Using `(st.status ?? "passed").toLowerCase()` guards against this.
3. **Adversarial Finding 3 (Low - Non-numeric string in counts)**:
   In `src/lib/queries/governance.ts:581`:
   `Number(rawCounts.critical ?? 0)` evaluates to `NaN` if a non-numeric string is supplied.

---

### 4. Conclusion

**Verdict: CLEAN**.  
The Milestone 2 deliverables authentically implement governance query hooks, view contracts, and QA Center UI components without taking shortcuts, using facades, or hardcoding test outputs. The implementation fully satisfies the requirements of Milestone 2 and is cleared to proceed to Milestone 3 (E2E Verification & Hardening).

---

### 5. Verification Method

To independently reproduce this forensic audit:
1. `npm run check:adr` (Must return `FRESH`)
2. `npm run check:sql` (Must return `SQL_CONTRACTS_OK`)
3. `npm run lint` (Must return exit code 0)
4. `npm test` (Must pass all 211 tests)
5. `npm run build` (Must compile 20 routes with exit code 0)
6. Inspect `src/lib/queries/governance.ts` lines 563-611 and `src/components/more/QaCenterModal.tsx` lines 76-92 for live RPC invocation and reactive state binding.
