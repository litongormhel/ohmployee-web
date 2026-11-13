# Milestone 2 Explorer 1: Governance Query Hooks & TypeScript Contracts Report

## 1. Observation

### Obs 1.1: Missing Scenario Run Result & Step Interfaces
- In `src/lib/queries/governance.ts` lines 8-32, the QA Center interface block defines only:
  - `QaRunSummary` (lines 8-20)
  - `QaFinding` (lines 22-32)
  - `QaSchedule` (lines 34-42)
  - `QaQueueItem` (lines 44-52)
  - `QaDailyReport` (lines 54-65)
  - `QaNotification`, `QaHealthMetric`, `QaUnstableModule`, `QaFlakyTest` (lines 67-94)
  - `QaCenterSnapshot` (lines 96-106)
- There is **no definition or export** of `QaScenarioStep` or `QaScenarioRunResult`.
- In `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` lines 663-671, `public.qa_run_scenario` returns:
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
Where each element in `v_steps` (lines 234-240, 287-293, 331-337, etc.) is formatted as:
```sql
jsonb_build_object(
  'step', v_step_num,
  'role', 'Head Admin',
  'action', 'create_active_vacancy',
  'status', 'passed',
  'details', 'Created active test vacancy ' || v_vcode
)
```

---

### Obs 1.2: Untyped RPC and Mutation Signatures
- In `src/lib/queries/governance.ts` lines 464-481:
```ts
export async function runQaScenarioRpc(scenarioCode: string) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("qa_run_scenario", {
    p_scenario_code: scenarioCode.trim(),
  });
  if (error) throw error;
  return data;
}

export function useRunQaScenario() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: runQaScenarioRpc,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["qa-center-snapshot"] });
    },
  });
}
```
- The function `runQaScenarioRpc` has an implicit return type of `Promise<any>`.
- The hook is named `useRunQaScenario`, with no alias for `useRunQaScenarioMutation`.
- Because the return type is untyped, callers such as `QaCenterModal.tsx` have no type safety or intellisense on `mutateAsync()`, causing developers to discard the response and show generic toasts.

---

### Obs 1.3: Column Mappings Divergence in `fetchQaCenterSnapshot()`
In `src/lib/queries/governance.ts` lines 328-384:

1. **`v_qa_open_findings` (lines 328-341)**:
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
- **Discrepancies**:
  - `finding_code` and `code` do not exist in the view. The view column is `finding_type` (e.g. `'rbac_leak'`, `'scenario_runtime_error'`). `f.finding_code ?? f.code ?? "QA_FINDING"` always evaluates to `"QA_FINDING"`.
  - `recommendation` (the actionable remediation advice) exists in the view but is completely omitted from `QaFinding` and the mapper.
  - `reference_table`, `reference_record_id`, and `run_id` exist in the view but are dropped by the mapper.

2. **`v_qa_schedules` (lines 343-354)**:
```ts
  const schedules: QaSchedule[] =
    schedulesRes.status === "fulfilled" && schedulesRes.value.data
      ? schedulesRes.value.data.map((s: Record<string, unknown>) => ({
          id: String(s.id ?? ""),
          scheduleName: String(s.schedule_name ?? "Scheduled Run"),
          cronExpression: String(s.cron_expression ?? "@daily"),
          targetModule: String(s.target_module ?? "all"),
          isActive: Boolean(s.is_active ?? true),
          lastRunAt: s.last_run_at ? String(s.last_run_at) : null,
          nextRunAt: s.next_run_at ? String(s.next_run_at) : null,
        }))
      : [];
```
- In `supabase/migrations/20260521062543_remote_schema.sql` lines 5452-5467:
```sql
create or replace view "public"."v_qa_schedules" as  SELECT id,
    schedule_name,
    suite_name,
    frequency,
    run_time,
    timezone,
    environment,
    assigned_agent_name,
    is_enabled,
    last_queued_at,
    last_run_at,
    next_run_at,
    created_at,
    updated_at
   FROM public.qa_schedules
  WHERE (archived_at IS NULL);
```
- **Discrepancies**:
  - `cron_expression` does not exist in the view. The columns are `frequency` (e.g. `'daily'`) and `run_time` (e.g. `'02:00:00'`).
  - `target_module` does not exist in the view. The column is `suite_name`.
  - `is_active` does not exist in the view. The column is `is_enabled` (`boolean`). `Boolean(s.is_active ?? true)` always evaluates to `true`, showing inactive schedules as active.

3. **`v_qa_run_queue` (lines 356-367)**:
```ts
  const queueItems: QaQueueItem[] =
    queueRes.status === "fulfilled" && queueRes.value.data
      ? queueRes.value.data.map((q: Record<string, unknown>) => ({
          id: String(q.id ?? ""),
          scheduleId: q.schedule_id ? String(q.schedule_id) : null,
          status: String(q.status ?? "queued"),
          priority: Number(q.priority ?? 0),
          queuedAt: q.queued_at ? String(q.queued_at) : null,
          startedAt: q.started_at ? String(q.started_at) : null,
          errorMessage: q.error_message ? String(q.error_message) : null,
        }))
      : [];
```
- In `supabase/migrations/20260521062543_remote_schema.sql` lines 5432-5450:
```sql
create or replace view "public"."v_qa_run_queue" as  SELECT q.id,
    q.schedule_id,
    s.schedule_name,
    q.suite_name,
    q.environment,
    q.queue_status,
    q.run_id,
    q.lock_key,
    q.retry_count,
    q.max_retries,
    q.failure_type,
    q.error_message,
    q.queued_at,
    q.started_at,
    q.completed_at,
    q.lock_expires_at
   FROM (public.qa_run_queue q
     LEFT JOIN public.qa_schedules s ON ((s.id = q.schedule_id)));
```
- **Discrepancies**:
  - `status` does not exist in the view. The column is `queue_status` (`'queued'`, `'running'`, `'completed'`, `'failed'`). `String(q.status ?? "queued")` always evaluates to `"queued"`.

4. **`v_qa_daily_reports` & `generateDailyQaReportRpc` (lines 369-383 and 483-490)**:
```ts
  const reports: QaDailyReport[] =
    reportsRes.status === "fulfilled" && reportsRes.value.data
      ? reportsRes.value.data.map((dr: Record<string, unknown>) => ({
          id: String(dr.id ?? ""),
          reportDate: String(dr.report_date ?? ""),
          environment: String(dr.environment ?? "production"),
          healthScore: dr.health_score != null ? Number(dr.health_score) : null,
          totalRuns: Number(dr.total_runs ?? 0),
          passedRuns: Number(dr.passed_runs ?? 0),
          failedRuns: Number(dr.failed_runs ?? 0),
          criticalFindings: Number(dr.critical_findings ?? 0),
          executiveSummary: dr.executive_summary ? String(dr.executive_summary) : null,
          createdAt: dr.created_at ? String(dr.created_at) : null,
        }))
      : [];

export async function generateDailyQaReportRpc(environment = "production") {
...
```
- In `supabase/migrations/20260520012857_remote_schema.sql` lines 17116-17140:
  - Columns are: `id, report_date, environment, total_runs, passed_runs, failed_runs, blocked_runs, cancelled_runs, critical_count, high_count, medium_count, low_count, top_failed_modules, average_runtime_seconds, most_unstable_workflow, flaky_tests, health_score, health_status, generated_by, generated_at, archived_at`.
- **Discrepancies**:
  - Fallback environment is `"production"`. Both frontend mapper and RPC default to `"production"`, whereas the database function `public.generate_daily_qa_report` defaults to `'staging'`.
  - `critical_findings` does not exist; the view column is `critical_count`.
  - `created_at` does not exist; the view column is `generated_at`.
  - `executive_summary` does not exist; the view columns are `health_status` and `most_unstable_workflow`.

5. **`v_qa_detection_run_summary` (lines 311-326)**:
- In `supabase/migrations/20260603000001_security_advisor_phase1_low_risk.sql` lines 225-245, `r.summary` exists, but is dropped from `QaRunSummary`.

---

## 2. Logic Chain

1. **Step 1 (Interface Contracts)**: The database engine `public.qa_run_scenario` executes multi-role workflows inside a subtransaction and returns an atomic payload containing `success`, `run_id`, `scenario_code`, `sandbox_rolled_back`, `steps`, and `finding_counts` (Obs 1.1). Without TypeScript types for this structure (`QaScenarioStep`, `QaScenarioRunResult`), UI components cannot safely parse, render, or track agent simulation steps and rollback isolation.
2. **Step 2 (RPC and Hook Return Types)**: Updating `runQaScenarioRpc` to return `Promise<QaScenarioRunResult>` with a defensive normalizer guarantees that `steps` is always an array of typed objects, `status` is `"passed" | "failed"`, and `sandbox_rolled_back` is a boolean (Obs 1.2). Adding `useRunQaScenarioMutation = useRunQaScenario` ensures both names work cleanly with React Query typing.
3. **Step 3 (Finding Remediation & Identity Restoration)**: In `v_qa_open_findings`, mapping `f.finding_type` into both `findingCode` and `findingType`, while extracting `f.recommendation`, `f.reference_table`, `f.reference_record_id`, and `f.run_id`, fixes the hardcoded `"QA_FINDING"` defect label and restores actionable remediation advice in the UI (Obs 1.3).
4. **Step 4 (Schedule and Queue Real-Time Accuracy)**: Mapping `frequency` + `run_time` into `cronExpression`, `is_enabled` into `isActive`/`isEnabled`, and `queue_status` into `status`/`queueStatus` restores true schedule cadences, active/inactive state, and active queue job execution states (Obs 1.3).
5. **Step 5 (Environment Safety & Daily Report Restoration)**: Aligning default environment in `generateDailyQaReportRpc` and the snapshot report mapper to `'staging'` prevents staging runs from being mislabeled as `"production"`. Mapping `critical_count` to `criticalFindings` and `generated_at` to `createdAt` restores report analytics (Obs 1.3).

---

## 3. Caveats

- **No direct source modification**: As an Explorer agent, no modifications were made to `src/lib/queries/governance.ts`. All proposed changes are documented as exact code diffs and replacement specifications for the implementer.
- **Backwards compatibility**: Existing properties consumed by `QaCenterModal.tsx` (`findingCode`, `category`, `isActive`, `cronExpression`, `targetModule`, `status`, `criticalFindings`, `createdAt`) are preserved alongside the newly mapped fields (`findingType`, `recommendation`, `isEnabled`, `queueStatus`, `generatedAt`, etc.) to guarantee zero regressions for existing UI code.

---

## 4. Conclusion & Concrete Specification

### 4.1. TypeScript Interfaces to Add and Export

Add the following interfaces to `src/lib/queries/governance.ts` (directly above `QaCenterSnapshot`):

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
  // Ergonomic camelCase aliases for React UI components
  runId?: string;
  scenarioCode?: string;
  sandboxRolledBack?: boolean;
  findingCounts?: {
    critical?: number;
    high?: number;
    medium?: number;
    low?: number;
    total?: number;
  };
  executedAt?: string;
}
```

### 4.2. Enhanced Snapshot Interfaces

Update existing interfaces in `src/lib/queries/governance.ts`:

```ts
export interface QaRunSummary {
  id: string;
  agentName: string;
  status: string;
  targetModule: string;
  findingCount: number;
  criticalCount: number;
  highCount: number;
  mediumCount: number;
  lowCount: number;
  startedAt: string | null;
  completedAt: string | null;
  summary?: string | null;
  executionType?: string;
}

export interface QaFinding {
  id: string;
  findingCode: string;
  findingType?: string;
  category: string;
  severity: "critical" | "high" | "medium" | "low";
  moduleName: string;
  status: string;
  title: string;
  details: string | null;
  recommendation?: string | null;
  referenceTable?: string | null;
  referenceRecordId?: string | null;
  runId?: string | null;
  createdAt: string | null;
}

export interface QaSchedule {
  id: string;
  scheduleName: string;
  cronExpression: string;
  frequency?: string;
  runTime?: string | null;
  targetModule: string;
  suiteName?: string;
  isActive: boolean;
  isEnabled?: boolean;
  lastRunAt: string | null;
  nextRunAt: string | null;
}

export interface QaQueueItem {
  id: string;
  scheduleId: string | null;
  status: string;
  queueStatus?: string;
  suiteName?: string;
  runId?: string | null;
  priority: number;
  retryCount?: number;
  maxRetries?: number;
  queuedAt: string | null;
  startedAt: string | null;
  errorMessage: string | null;
}

export interface QaDailyReport {
  id: string;
  reportDate: string;
  environment: string;
  healthScore: number | null;
  totalRuns: number;
  passedRuns: number;
  failedRuns: number;
  criticalFindings: number;
  criticalCount?: number;
  executiveSummary: string | null;
  createdAt: string | null;
  generatedAt?: string | null;
}
```

---

### 4.3. Surgical Updates to `fetchQaCenterSnapshot()`

Replace lines 311-384 of `src/lib/queries/governance.ts`:

```ts
  const runs: QaRunSummary[] =
    runsRes.status === "fulfilled" && runsRes.value.data
      ? runsRes.value.data.map((r: Record<string, unknown>) => ({
          id: String(r.id ?? ""),
          agentName: String(r.agent_name ?? "QA Core Agent"),
          status: String(r.status ?? "unknown"),
          targetModule: String(r.target_module ?? "all"),
          findingCount: Number(r.finding_count ?? 0),
          criticalCount: Number(r.critical_count ?? 0),
          highCount: Number(r.high_count ?? 0),
          mediumCount: Number(r.medium_count ?? 0),
          lowCount: Number(r.low_count ?? 0),
          startedAt: r.started_at ? String(r.started_at) : null,
          completedAt: r.completed_at ? String(r.completed_at) : null,
          summary: r.summary ? String(r.summary) : null,
          executionType: r.execution_type ? String(r.execution_type) : undefined,
        }))
      : [];

  const findings: QaFinding[] =
    findingsRes.status === "fulfilled" && findingsRes.value.data
      ? findingsRes.value.data.map((f: Record<string, unknown>) => {
          const findingType = String(f.finding_type ?? f.finding_code ?? f.code ?? "QA_FINDING");
          return {
            id: String(f.id ?? ""),
            findingCode: findingType,
            findingType,
            category: String(f.category ?? f.finding_type ?? "General"),
            severity: (f.severity as "critical" | "high" | "medium" | "low") ?? "medium",
            moduleName: String(f.module_name ?? f.module ?? "System"),
            status: String(f.status ?? "open"),
            title: String(f.title ?? f.finding_summary ?? "Detected Anomaly"),
            details: f.details || f.error_message ? String(f.details ?? f.error_message) : null,
            recommendation: f.recommendation ? String(f.recommendation) : null,
            referenceTable: f.reference_table ? String(f.reference_table) : null,
            referenceRecordId: f.reference_record_id ? String(f.reference_record_id) : null,
            runId: f.run_id ? String(f.run_id) : null,
            createdAt: f.created_at ? String(f.created_at) : null,
          };
        })
      : [];

  const schedules: QaSchedule[] =
    schedulesRes.status === "fulfilled" && schedulesRes.value.data
      ? schedulesRes.value.data.map((s: Record<string, unknown>) => {
          const frequency = s.frequency ? String(s.frequency) : "";
          const runTime = s.run_time ? String(s.run_time) : "";
          const cronExpression = String(
            s.cron_expression ?? (runTime ? `${frequency} at ${runTime}` : frequency || "@daily")
          );
          const suiteName = String(s.suite_name ?? s.target_module ?? "all");
          const isEnabled = Boolean(s.is_enabled ?? s.is_active ?? true);
          return {
            id: String(s.id ?? ""),
            scheduleName: String(s.schedule_name ?? "Scheduled Run"),
            cronExpression,
            frequency: frequency || undefined,
            runTime: runTime || null,
            targetModule: suiteName,
            suiteName,
            isActive: isEnabled,
            isEnabled,
            lastRunAt: s.last_run_at ? String(s.last_run_at) : null,
            nextRunAt: s.next_run_at ? String(s.next_run_at) : null,
          };
        })
      : [];

  const queueItems: QaQueueItem[] =
    queueRes.status === "fulfilled" && queueRes.value.data
      ? queueRes.value.data.map((q: Record<string, unknown>) => {
          const queueStatus = String(q.queue_status ?? q.status ?? "queued");
          return {
            id: String(q.id ?? ""),
            scheduleId: q.schedule_id ? String(q.schedule_id) : null,
            status: queueStatus,
            queueStatus,
            suiteName: q.suite_name ? String(q.suite_name) : undefined,
            runId: q.run_id ? String(q.run_id) : null,
            priority: Number(q.priority ?? 0),
            retryCount: q.retry_count != null ? Number(q.retry_count) : undefined,
            maxRetries: q.max_retries != null ? Number(q.max_retries) : undefined,
            queuedAt: q.queued_at ? String(q.queued_at) : null,
            startedAt: q.started_at ? String(q.started_at) : null,
            errorMessage: q.error_message ? String(q.error_message) : null,
          };
        })
      : [];

  const reports: QaDailyReport[] =
    reportsRes.status === "fulfilled" && reportsRes.value.data
      ? reportsRes.value.data.map((dr: Record<string, unknown>) => {
          const createdAt = (dr.generated_at ?? dr.created_at) ? String(dr.generated_at ?? dr.created_at) : null;
          const criticalCount = Number(dr.critical_count ?? dr.critical_findings ?? 0);
          const executiveSummary = dr.executive_summary
            ? String(dr.executive_summary)
            : dr.health_status
            ? `Status: ${dr.health_status}${dr.most_unstable_workflow ? ` • Unstable: ${dr.most_unstable_workflow}` : ""}`
            : null;
          return {
            id: String(dr.id ?? ""),
            reportDate: String(dr.report_date ?? ""),
            environment: String(dr.environment ?? "staging"),
            healthScore: dr.health_score != null ? Number(dr.health_score) : null,
            totalRuns: Number(dr.total_runs ?? 0),
            passedRuns: Number(dr.passed_runs ?? 0),
            failedRuns: Number(dr.failed_runs ?? 0),
            criticalFindings: criticalCount,
            criticalCount,
            executiveSummary,
            createdAt,
            generatedAt: createdAt,
          };
        })
      : [];
```

---

### 4.4. Surgical Updates to `runQaScenarioRpc` & `useRunQaScenarioMutation`

Replace lines 464-502 of `src/lib/queries/governance.ts`:

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
}

export function useRunQaScenario() {
  const queryClient = useQueryClient();
  return useMutation<QaScenarioRunResult, Error, string>({
    mutationFn: runQaScenarioRpc,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["qa-center-snapshot"] });
    },
  });
}

export const useRunQaScenarioMutation = useRunQaScenario;

export async function generateDailyQaReportRpc(environment = "staging") {
  const supabase = createClient();
  const today = new Date().toISOString().substring(0, 10);
  const { data, error } = await supabase.rpc("generate_daily_qa_report", {
    p_report_date: today,
    p_environment: environment,
  });
  if (error) throw error;
  return data;
}

export function useGenerateDailyQaReport() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (environment: string = "staging") => generateDailyQaReportRpc(environment),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["qa-center-snapshot"] });
    },
  });
}
```

---

## 5. Verification Method

1. **Verify Interface Definitions**:
   - Inspect `src/lib/queries/governance.ts` lines 8-106 after applying the changes. Ensure `QaScenarioStep` and `QaScenarioRunResult` are properly exported.
2. **Verify TypeScript Typecheck & Lint**:
   - Run `npx tsc --noEmit` to verify 0 type errors across `src/lib/queries/governance.ts` and its consumers.
   - Run `npm run lint` to verify 0 ESLint errors.
3. **Verify SQL & ADR Guards**:
   - Run `npm run check:adr` to ensure ADR mirror freshness.
   - Run `npm run check:sql` to ensure all 28 core tables and 19 RPC contracts are verified.
4. **Invalidation Conditions**:
   - If `qa_run_scenario` in migration `20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` changes its return keys from `steps` or `finding_counts`, `runQaScenarioRpc` parser must be updated accordingly.
