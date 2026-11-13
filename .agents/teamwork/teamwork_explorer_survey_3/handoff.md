# QA Center UI & Query Hooks Investigation Report

## 1. Observation

### Obs 1.1: Missing Flagship Scenario in Scenario Selector
- In `src/components/more/QaCenterModal.tsx` lines 39-45:
```tsx
const COMMON_SCENARIOS = [
  { code: "VAC_ARCHIVE_001", label: "Vacancy Archival Integrity" },
  { code: "PLANTILLA_001", label: "Plantilla Slot Allocation" },
  { code: "HR_EMPLOC_001", label: "HR Emploc Active Sync" },
  { code: "CENCOM_001", label: "CENCOM Edit Lock & Quota" },
  { code: "AUTH_MATRIX_001", label: "Authorization Drift Probe" },
];
```
- In `supabase/migrations/20262606000045_qa_role_relay_engine.sql` line 7 and 313:
```sql
CREATE OR REPLACE FUNCTION public.qa_run_scenario(p_scenario_code text DEFAULT 'FULL_E2E_RELAY'::text)
...
-- FULL_E2E_RELAY: 6-Role Workflow Sequence
```
- Verbatim comparison: The database engine's default flagship scenario is `'FULL_E2E_RELAY'` (executing the multi-role sequence across Head Admin, Encoder, Recruitment, HRCO, HR Personnel, and Back Office), but it is completely omitted from `COMMON_SCENARIOS` in the frontend UI. The UI defaults to `"VAC_ARCHIVE_001"`.

---

### Obs 1.2: Scenario Run Telemetry and Step Breakdown Completely Discarded
- In `src/components/more/QaCenterModal.tsx` lines 73-81:
```tsx
  const handleRunScenario = async () => {
    if (!selectedScenario) return;
    try {
      await runScenarioMutation.mutateAsync(selectedScenario);
      showToast(`Scenario ${selectedScenario} executed successfully.`);
    } catch (err: unknown) {
      showToast(`Scenario run failed: ${(err as Error).message}`);
    }
  };
```
- In `src/lib/queries/governance.ts` lines 464-471:
```ts
export async function runQaScenarioRpc(scenarioCode: string) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("qa_run_scenario", {
    p_scenario_code: scenarioCode.trim(),
  });
  if (error) throw error;
  return data;
}
```
- In `supabase/migrations/20262606000045_qa_role_relay_engine.sql` lines 509-518:
```sql
  RETURN jsonb_build_object(
    'success', v_is_success AND v_sandbox_rolled_back,
    'run_id', v_run_id,
    'scenario_code', v_code,
    'sandbox_rolled_back', v_sandbox_rolled_back,
    'steps', v_steps,
    'finding_counts', v_counts,
    'executed_at', now()
  );
```
- Verbatim comparison: `qa_run_scenario` returns a detailed payload including `success`, `run_id`, `sandbox_rolled_back`, `steps` (array of role-by-role execution status), and `finding_counts`. `QaCenterModal.tsx` ignores the return value of `runScenarioMutation.mutateAsync()`, sets zero local state, and only shows a toast message before staying on whatever tab the user is on.
- Furthermore, because `qa_run_scenario` catches internal execution errors and returns `{ success: false, ... }` rather than raising an unhandled exception, `mutateAsync` resolves without throwing. If a scenario fails, `handleRunScenario` misleadingly displays `Scenario <name> executed successfully.` even though the simulation failed!

---

### Obs 1.3: Zero Agent Steps / Live Progress UI Architecture
- In `src/components/more/QaCenterModal.tsx`:
  - 0 child components exist. The modal is a monolithic 775-line file.
  - 0 state variables or UI components exist for displaying agent steps, role execution details, pass/fail status per step, or atomic sandbox status (`sandbox_rolled_back`).
  - There is no runner panel, no step timeline, no simulation progress dialog, and no drawer to inspect past or current simulation runs.

---

### Obs 1.4: Schema Mismatch in Findings View (`finding_type` vs `findingCode`, Omitted `recommendation`)
- In `src/lib/queries/governance.ts` lines 328-341:
```ts
  const findings: QaFinding[] =
    findingsRes.status === "fulfilled" && findingsRes.value.data
      ? findingsRes.value.data.map((f: Record<string, unknown>) => ({
          id: String(f.id ?? ""),
          findingCode: String(f.finding_code ?? f.code ?? "QA_FINDING"),
          category: String(f.category ?? "General"),
          severity: (f.severity as "critical" | "high" | "medium" | "low") ?? "medium",
          moduleName: String(f.module_name ?? f.module ?? "System"),
          status: String(f.status ?? "open"),
          title: String(f.title ?? f.finding_summary ?? "Detected Anomaly"),
          details: f.details || f.error_message ? String(f.details ?? f.error_message) : null,
          createdAt: f.created_at ? String(f.created_at) : null,
        }))
      : [];
```
- In `supabase/migrations/20260521062543_remote_schema.sql` lines 5412-5429:
```sql
create or replace view "public"."v_qa_open_findings" as  SELECT f.id,
    f.run_id,
    f.severity,
    f.finding_type,
    f.module_name,
    f.reference_table,
    f.reference_record_id,
    f.title,
    f.details,
    f.recommendation,
    f.status,
    f.created_at,
    r.agent_name,
    r.target_module,
    r.started_at AS run_started_at
   FROM (public.qa_agent_findings f
     JOIN public.qa_agent_runs r ON ((r.id = f.run_id)))
  WHERE (f.status = 'open'::text);
```
- Discrepancies:
  1. `finding_code` and `code` do NOT exist on `v_qa_open_findings`. The actual column is `finding_type` (e.g. `'rbac_leak'`, `'scenario_runtime_error'`). Consequently, `f.finding_code ?? f.code ?? "QA_FINDING"` ALWAYS falls back to `"QA_FINDING"` on every finding card in `QaCenterModal.tsx`.
  2. `category` does NOT exist on `v_qa_open_findings`. The frontend maps `f.category ?? "General"`, so every finding displays `Category: General`.
  3. `recommendation` (the actionable remediation details logged by the QA engine, e.g. `'Audit get_my_role_level() and RLS security definer policies.'`) is returned by `v_qa_open_findings`, but completely omitted from the `QaFinding` TypeScript interface in `governance.ts`, never mapped, and never rendered in `QaCenterModal.tsx`.
  4. `run_id`, `reference_table`, and `reference_record_id` are returned by the view, but dropped by the frontend mapper.

---

### Obs 1.5: Schema Mismatches Across Other Views (`v_qa_schedules`, `v_qa_run_queue`, `v_qa_daily_reports`, `v_qa_unstable_modules`, `v_qa_flaky_tests`)
1. **`v_qa_schedules`** (`supabase/migrations/20260521062543_remote_schema.sql:5452-5467`):
   - View columns: `id, schedule_name, suite_name, frequency, run_time, timezone, environment, assigned_agent_name, is_enabled, last_queued_at, last_run_at, next_run_at, created_at, updated_at`.
   - Frontend mapper looks for: `cron_expression`, `target_module`, `is_active`.
   - Result in `QaCenterModal.tsx`:
     - `cronExpression` always falls back to `"@daily"` (`s.cron_expression ?? "@daily"`).
     - `targetModule` always falls back to `"all"` (`s.target_module ?? "all"`).
     - `isActive` is `Boolean(s.is_active ?? true)` which evaluates to `true` on every schedule, even disabled ones!
2. **`v_qa_run_queue`** (`supabase/migrations/20260521062543_remote_schema.sql:5432-5450`):
   - View columns: `id, schedule_id, schedule_name, suite_name, environment, queue_status, run_id, lock_key, retry_count, max_retries, failure_type, error_message, queued_at, started_at, completed_at, lock_expires_at`.
   - Frontend mapper looks for: `status`, `priority`.
   - Result in `QaCenterModal.tsx`:
     - `status` always falls back to `"queued"` because `q.status` is undefined (`q.queue_status` is the actual column).
     - `priority` is always `0` (`Number(q.priority ?? 0)`).
3. **`v_qa_unstable_modules`** (`supabase/migrations/20260521062543_remote_schema.sql:5470-5479`):
   - View columns: `module_name, finding_count, critical_count, high_count, latest_finding_at`.
   - Frontend mapper looks for: `failure_rate` (which does not exist in the view).
   - Result in `QaCenterModal.tsx:369`: `{(m.failureRate * 100).toFixed(1)}% fail rate` always renders `0.0% fail rate`.
4. **`v_qa_flaky_tests`** (`supabase/migrations/20260521062543_remote_schema.sql:5370-5380`):
   - View columns: `finding_type, module_name, occurrence_count, first_seen_at, last_seen_at`.
   - Frontend mapper looks for: `test_code`, `last_failed_at`.
   - Result: `testCode` is `""`, `lastFailedAt` is `null`.
5. **`v_qa_daily_reports`** (`supabase/migrations/20260520012857_remote_schema.sql:17116-17140`):
   - View columns: `id, report_date, environment, total_runs, passed_runs, failed_runs, blocked_runs, cancelled_runs, critical_count, high_count, medium_count, low_count, top_failed_modules, average_runtime_seconds, most_unstable_workflow, flaky_tests, health_score, health_status, generated_by, generated_at, archived_at`.
   - Frontend mapper looks for: `critical_findings`, `created_at`, `executive_summary`.
   - Result in `QaCenterModal.tsx`:
     - `dr.criticalFindings` is always `0` (actual column is `critical_count`).
     - `dr.createdAt` is always `null` / empty (actual column is `generated_at`).
     - `dr.executiveSummary` is always `null` (actual columns are `health_status`, `most_unstable_workflow`), so the summary block never renders.

---

### Obs 1.6: Monolithic Snapshot Query Swallowing View Failures
- In `src/lib/queries/governance.ts` lines 250-310:
  `fetchQaCenterSnapshot()` fires 9 distinct Supabase view queries in `Promise.allSettled()`.
  If any view fails (e.g. RLS policy issue, permission denied, or schema mismatch), the failure is silently coerced to an empty array `[]` without console warning, error toast, or error boundary.

---

### Obs 1.7: Non-Interactive Runs Table & Unlinkable Findings
- In `src/components/more/QaCenterModal.tsx` lines 444-511:
  - Table rows in "Detection Runs History" are non-interactive `<tr key={r.id}>` without `onClick` handlers.
  - The `summary` column from `v_qa_detection_run_summary` (e.g. `"Scenario FULL_E2E_RELAY passed cleanly in sandbox with zero data pollution."`) is not mapped into `QaRunSummary` and not displayed in the table.
  - There is no run detail modal/drawer to inspect what occurred during a run.
  - The Findings tab displays all open findings globally without ability to filter by a selected `run_id`.

---

### Obs 1.8: Dangerous Hardcoded `"production"` Tag in Report Generator
- In `src/lib/queries/governance.ts` lines 483-490:
```ts
export async function generateDailyQaReportRpc(environment = "production") {
  const supabase = createClient();
  const today = new Date().toISOString().substring(0, 10);
  const { data, error } = await supabase.rpc("generate_daily_qa_report", {
    p_report_date: today,
    p_environment: environment,
  });
```
- In `src/components/more/QaCenterModal.tsx` line 85:
```tsx
await generateReportMutation.mutateAsync("production");
```
- In `supabase/migrations/20260520012857_remote_schema.sql` line 8609:
```sql
CREATE OR REPLACE FUNCTION public.generate_daily_qa_report(p_report_date date DEFAULT CURRENT_DATE, p_environment text DEFAULT 'staging'::text)
```
- Verbatim comparison: The database function safely defaults `p_environment` to `'staging'`, but the frontend explicitly hardcodes `"production"`, tagging daily QA reports generated from web as `"production"` even when running against the Staging database.

---

## 2. Logic Chain

1. **Premise 1 (Execution Visibility)**: The user initiates a simulation via `handleRunScenario` (Obs 1.1, Obs 1.2). The underlying database function `qa_run_scenario` executes and returns a rich JSON object containing `success`, `run_id`, `sandbox_rolled_back`, `steps` (the 6-role agent execution sequence), and `finding_counts` (Obs 1.2).
2. **Premise 2 (State Dropping)**: Because `handleRunScenario` ignores the return value of `runScenarioMutation.mutateAsync()` and maintains no `lastRunResult` state, the execution telemetry is dropped immediately upon completion (Obs 1.2).
3. **Premise 3 (False Positive Messaging)**: Because `qa_run_scenario` traps simulation failures inside its exception handler to ensure atomic rollback and returns `{ success: false, ... }`, `mutateAsync` does not reject (Obs 1.2). `handleRunScenario` displays `showToast("Scenario ... executed successfully.")` even when `success` is `false`, giving administrators false confidence.
4. **Premise 4 (Missing Role Relay Scenario)**: The flagship 6-role relay (`FULL_E2E_RELAY`) is missing from `COMMON_SCENARIOS` (Obs 1.1), meaning administrators cannot select or trigger the multi-role simulation from the UI dropdown without manually writing code.
5. **Premise 5 (No Step Viewer UI)**: `QaCenterModal.tsx` has no child components and no UI views to display individual agent steps, pass/fail status, role badges, or atomic sandbox rollback verification badges (Obs 1.3).
6. **Premise 6 (Finding Identity Masking)**: `v_qa_open_findings` returns `finding_type`, but `governance.ts` attempts to read `finding_code` and `code` (Obs 1.4). Every single finding is thus labeled `"QA_FINDING"` in the UI, destroying defect categorization.
7. **Premise 7 (Missing Remediation Guidance)**: `v_qa_open_findings` returns actionable remediation guidance in `recommendation`, but `governance.ts` omits this field from `QaFinding`, leaving administrators unable to act on detected defects (Obs 1.4).
8. **Premise 8 (Widespread Schema Divergence)**: Five additional views (`v_qa_schedules`, `v_qa_run_queue`, `v_qa_unstable_modules`, `v_qa_flaky_tests`, `v_qa_daily_reports`) suffer from mismatched property names, resulting in hardcoded fallbacks (`@daily`, `Target: all`, `0.0% fail rate`, missing dates, missing summaries) across the modal tabs (Obs 1.5).
9. **Conclusion**: The QA Center UI currently functions as a partial, un-wired mockup where simulation telemetry is discarded, the 6-role relay is inaccessible, detected defects lack type and remediation details, and historical views display fallback placeholder values due to schema column mismatches.

---

## 3. Discrepancies Table: Database/Telemetry vs Frontend Types

| Database Source / View | DB Column / Return Field | Frontend Interface Property (`governance.ts`) | Frontend Property Read (`QaCenterModal.tsx`) | Impact / Current Bug |
|---|---|---|---|---|
| `qa_run_scenario()` RPC return | `success: boolean` | Dropped / untyped | Untyped / ignored | Fails to detect simulation failures; displays false "success" toast |
| `qa_run_scenario()` RPC return | `steps: jsonb[]` (`step`, `role`, `action`, `status`, `details`) | Dropped / untyped | Not rendered | Role relay step-by-step outcomes completely invisible to user |
| `qa_run_scenario()` RPC return | `sandbox_rolled_back: boolean` | Dropped / untyped | Not rendered | Zero visibility into atomic sandbox rollback verification |
| `qa_run_scenario()` RPC return | `finding_counts: jsonb` | Dropped / untyped | Not rendered | Run-level finding counts ignored upon execution |
| `v_qa_open_findings` | `finding_type` | `findingCode: f.finding_code ?? f.code ?? "QA_FINDING"` | `f.findingCode` | Every defect renders as `"QA_FINDING"` instead of its true code |
| `v_qa_open_findings` | (no `category` column; has `finding_type`, `target_module`) | `category: f.category ?? "General"` | `f.category` | Every defect renders as `"General"` |
| `v_qa_open_findings` | `recommendation` | Missing from `QaFinding` | Not rendered | Remediation instructions completely hidden from UI |
| `v_qa_open_findings` | `run_id`, `reference_table`, `reference_record_id` | Missing from `QaFinding` | Not rendered | Defect cannot be linked to specific run or target entity |
| `v_qa_detection_run_summary` | `summary` | Missing from `QaRunSummary` | Not rendered | High-level run outcome message dropped |
| `v_qa_schedules` | `frequency`, `run_time` | `cronExpression: s.cron_expression ?? "@daily"` | `s.cronExpression` | Displays `Cron: @daily` on all schedules regardless of real cadence |
| `v_qa_schedules` | `suite_name` | `targetModule: s.target_module ?? "all"` | `s.targetModule` | Displays `Target: all` on all schedules |
| `v_qa_schedules` | `is_enabled` | `isActive: s.is_active ?? true` | `s.isActive` | Inactive schedules display as `ACTIVE` |
| `v_qa_run_queue` | `queue_status` | `status: q.status ?? "queued"` | `q.status` | Running/failed queue items display as `queued` |
| `v_qa_run_queue` | `retry_count`, `max_retries` | `priority: q.priority ?? 0` | `q.priority` | Always displays `Priority: 0` |
| `v_qa_unstable_modules` | `critical_count`, `high_count` | `failureRate: u.failure_rate ?? 0` | `m.failureRate` | Always displays `0.0% fail rate` |
| `v_qa_flaky_tests` | `finding_type` | `testCode: fl.test_code ?? ""` | `fl.testCode` | Test code is always empty string `""` |
| `v_qa_flaky_tests` | `last_seen_at` | `lastFailedAt: fl.last_failed_at ?? null` | `fl.lastFailedAt` | Last failed timestamp is always `null` |
| `v_qa_daily_reports` | `critical_count` | `criticalFindings: dr.critical_findings ?? 0` | `dr.criticalFindings` | Always displays `0 Critical` |
| `v_qa_daily_reports` | `generated_at` | `createdAt: dr.created_at ?? null` | `dr.createdAt` | Report generation date is always blank |
| `v_qa_daily_reports` | `most_unstable_workflow`, `health_status` | `executiveSummary: dr.executive_summary ?? null` | `dr.executiveSummary` | Executive summary block never renders (`null`) |
| `generate_daily_qa_report()` RPC | `p_environment` (default: `'staging'`) | `environment = "production"` | Passed `"production"` | Daily reports generated from web tag staging data as `"production"` |

---

## 4. Caveats

- Database write/DDL execution was not performed (strictly read-only investigation per rules).
- Live query inspection of Staging data was not executed directly in this turn to avoid unauthorized network database calls; all findings are derived directly from the physical migration definitions (`supabase/migrations/`) and frontend codebase (`src/`).
- The `v_qa_*` views exist in migration `20260521062543_remote_schema.sql` and `20260603000001_security_advisor_phase1_low_risk.sql` with `security_invoker = true`. If RLS on base tables (`qa_agent_runs`, `qa_agent_findings`) restricts non-admin roles, only users with `role_level >= 90` or Super Admins can query them. In `more/page.tsx`, the QA Center tile is gated to `minRoleLevel: 100`, which satisfies the authorization requirements.

---

## 5. Conclusion & Recommended Component & Query Architecture

### Assessment
The QA Center modal cannot currently meet the requirements of `ORIGINAL_REQUEST.md` (R1-R4) in its current state:
1. **R1 (Audit Architecture)**: The UI is completely disconnected from the returned telemetry of `qa_run_scenario`.
2. **R2 (Multi-Role Simulation)**: The 6-Role Workflow Relay (`FULL_E2E_RELAY`) cannot be selected from the UI dropdown, and its agent steps are never displayed.
3. **R3 (Sandbox Isolation)**: The atomic rollback status (`sandbox_rolled_back`) is received from PostgreSQL but discarded, giving users no confirmation of zero data pollution.
4. **R4 (Telemetry & Bug Reporting)**: Defect findings lack actual finding codes (showing `"QA_FINDING"`), lack remediation details (omitting `recommendation`), and cannot be linked to specific simulation runs.

---

### Concrete Recommended Implementation Plan

#### Component Breakdown & Architecture
Decompose the monolithic `QaCenterModal.tsx` into clean, specialized components under `src/components/more/qa/`:

1. **`QaCenterModal.tsx` (Host Modal)**:
   - Manages top-level tabs: `overview`, `runner`, `runs`, `findings`, `schedules_queue`, `reports`.
   - Hosts header, status banner, and tab switcher.
2. **`QaSimulationRunner.tsx` (Dedicated Simulation Panel)**:
   - Scenario selector including:
     - `FULL_E2E_RELAY` (Primary: "6-Role AI Agent Workflow Relay" — Head Admin -> Encoder -> Recruitment -> HRCO -> HR Personnel -> Back Office)
     - `VAC_ARCHIVE_001` ("Vacancy Archival Integrity")
     - `PLANTILLA_001` ("Plantilla Slot Allocation")
     - `HR_EMPLOC_001` ("HR Emploc Active Sync")
     - `CENCOM_001` ("CENCOM Edit Lock & Quota")
     - `AUTH_MATRIX_001` ("Authorization Drift Probe")
   - "Execute Simulation" button with loading state.
   - **Live / Completed Execution View**:
     - Status Banner: Pass / Fail status, duration, executed timestamp.
     - **Atomic Sandbox Isolation Card**: High-contrast badge confirming `QA_SANDBOX_ROLLBACK_SUCCESS` (Zero operational records committed to `vacancies`, `plantilla`, `applicants`, `hr_emploc`).
     - **Agent Steps Timeline**: Sequential cards for each step:
       - Step number & Role badge (e.g. `Head Admin`, `Encoder`, `Recruitment`, `HRCO`, `HR Personnel`, `Back Office`).
       - Action tag (e.g. `headcount_approval_and_vacancy_init`, `negative_permission_barrier_check`).
       - Outcome pill (`PASSED` in emerald, `FAILED` in rose).
       - Verbatim execution details note.
     - Defect Summary Pill: Total findings count with shortcut button: "View Detected Findings (N)".
3. **`QaRunHistoryTable.tsx` & `QaRunDetailModal.tsx`**:
   - Enhanced runs table displaying: Status, Agent/Suite, Scenario Code, Target Module, Summary, Findings Breakdown, Started At, Completed At.
   - Clickable table rows that open `QaRunDetailModal`:
     - Full execution metadata.
     - Link to filter findings by `run_id`.
4. **`QaFindingsViewer.tsx`**:
   - Fixed mapping: Displays true `finding_type` instead of `"QA_FINDING"`.
   - Severity badges (`critical`, `high`, `medium`, `low`).
   - Remediation Box: Displays `recommendation` in a distinct callout ("Recommended Remediation: ...").
   - Entity Context: Displays `reference_table` and `reference_record_id` when present.
   - Filters: By Severity, Module, and Run ID.
5. **`src/lib/queries/governance.ts` Normalization**:
   - Add TypeScript contracts:
     ```ts
     export interface QaScenarioStep {
       step: number;
       role: string;
       action: string;
       status: "passed" | "failed";
       details: string;
     }

     export interface QaScenarioRunResult {
       success: boolean;
       run_id: string;
       scenario_code: string;
       sandbox_rolled_back: boolean;
       steps: QaScenarioStep[];
       finding_counts: {
         critical?: number;
         high?: number;
         medium?: number;
         low?: number;
         total?: number;
       };
       executed_at: string;
     }
     ```
   - Update `runQaScenarioRpc` to return `QaScenarioRunResult`.
   - Fix all column mappings for `v_qa_open_findings`, `v_qa_schedules`, `v_qa_run_queue`, `v_qa_unstable_modules`, `v_qa_flaky_tests`, `v_qa_daily_reports`.
   - Fix `generateDailyQaReportRpc` default environment from `"production"` to `"staging"`.

---

## 6. Verification Method

To independently verify these findings:
1. **Inspect Scenario Selector & Handler**:
   - Open `src/components/more/QaCenterModal.tsx:39-45` and `73-81`. Confirm `FULL_E2E_RELAY` is absent and `mutateAsync` return value is unassigned.
2. **Inspect Migration Definition**:
   - Open `supabase/migrations/20262606000045_qa_role_relay_engine.sql:7-25` and `509-518`. Confirm `qa_run_scenario` defaults to `'FULL_E2E_RELAY'` and returns `{ success, run_id, scenario_code, sandbox_rolled_back, steps, finding_counts, executed_at }`.
3. **Inspect View Schemas**:
   - Open `supabase/migrations/20260521062543_remote_schema.sql:5412-5429` (`v_qa_open_findings`). Confirm `finding_type` and `recommendation` exist, while `finding_code` and `category` do not.
   - Open `supabase/migrations/20260521062543_remote_schema.sql:5452-5467` (`v_qa_schedules`). Confirm `frequency`, `run_time`, `suite_name`, `is_enabled` exist, while `cron_expression`, `target_module`, `is_active` do not.
4. **Run Verification Commands**:
   - `npm run check:adr` (confirm ADR mirrors remain FRESH)
   - `npm run check:sql` (confirm all SQL contracts are satisfied)
   - `npm run lint` (confirm 0 ESLint errors)
   - `npm test` (confirm all 211 test suites pass)
