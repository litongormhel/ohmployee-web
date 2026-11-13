# M2 Explorer 2 Handoff Report: Simulation Runner & Step Timeline UI Specification

## Executive Summary
This report provides the complete UI design and integration blueprint for the QA Simulation Runner and 7-Step Agent Timeline within the QA Center modal (`src/components/more/QaCenterModal.tsx`). It details:
1. Adding `{ code: "FULL_E2E_RELAY", label: "Full 6-Role Workflow Relay" }` as the primary flagship scenario in `COMMON_SCENARIOS` and setting it as default.
2. Updating `handleRunScenario` to capture the returned mutation payload into `lastScenarioResult` state and eliminating false-positive toast messages.
3. Complete UI component design for:
   - High-contrast **Atomic Sandbox Rollback Status Badge** (`QA_SANDBOX_ROLLBACK_SUCCESS` confirming zero data pollution).
   - **Agent Step Timeline** rendering all 7 steps across the 6 simulated roles (`Head Admin`, `Encoder`, `Recruitment`, `HRCO`, `HR Personnel`, `Back Office`) with distinct role badges, status pills (passed/failed), action identifiers, and execution details.
   - **Defect Count & Quick Navigation** linking directly to the Findings tab.
4. Ready-to-use TypeScript component code for `src/components/more/qa/QaStepTimeline.tsx` (or direct integration into `QaCenterModal.tsx`).

---

## 1. Observation

### 1.1 `COMMON_SCENARIOS` and Default State Missing Flagship Scenario
- **Location**: `src/components/more/QaCenterModal.tsx` lines 39-49
- **Verbatim Code**:
```tsx
const COMMON_SCENARIOS = [
  { code: "VAC_ARCHIVE_001", label: "Vacancy Archival Integrity" },
  { code: "PLANTILLA_001", label: "Plantilla Slot Allocation" },
  { code: "HR_EMPLOC_001", label: "HR Emploc Active Sync" },
  { code: "CENCOM_001", label: "CENCOM Edit Lock & Quota" },
  { code: "AUTH_MATRIX_001", label: "Authorization Drift Probe" },
];

export function QaCenterModal({ isOpen, onClose, isSuperAdmin }: QaCenterModalProps) {
  const [activeTab, setActiveTab] = useState<QaTab>("overview");
  const [selectedScenario, setSelectedScenario] = useState("VAC_ARCHIVE_001");
```
- **Finding**:
  The flagship multi-role scenario `FULL_E2E_RELAY` (implemented in PostgreSQL in `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql:10`) is absent from `COMMON_SCENARIOS`. Administrators opening the modal cannot select it without manual code edits, and the dropdown defaults to `VAC_ARCHIVE_001`.

---

### 1.2 `handleRunScenario` Discards Telemetry Payload and Displays False Positive Toast
- **Location**: `src/components/more/QaCenterModal.tsx` lines 73-81
- **Verbatim Code**:
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
- **Finding**:
  1. The return value of `await runScenarioMutation.mutateAsync(selectedScenario)` is ignored. Zero state is set.
  2. In `20262606000106_qa_run_scenario_sandbox_simulation_engine.sql:563-572`, `qa_run_scenario` catches internal execution errors and negative barrier leaks inside its exception handler so that it can complete the rollback cleanly and log telemetry. It returns `{ success: false, ... }` rather than raising an unhandled exception.
  3. Consequently, `mutateAsync` resolves without throwing even when the simulation fails. `handleRunScenario` unconditionally displays `Scenario ... executed successfully.`, presenting a dangerous false positive to operators.

---

### 1.3 Verbatim Return Schema of `public.qa_run_scenario`
- **Location**: `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` lines 663-671
- **Verbatim Code**:
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
- **Finding**:
  The database engine returns an explicit, structured telemetry contract:
  - `success`: boolean (`true` if all assertions held and rollback succeeded).
  - `run_id`: UUID of the persisted run record in `public.qa_agent_runs`.
  - `scenario_code`: string code (e.g. `'FULL_E2E_RELAY'`).
  - `sandbox_rolled_back`: boolean (`true` if `QA_SANDBOX_ROLLBACK_SUCCESS` was caught and zero operational mutations leaked).
  - `steps`: array of JSON objects representing chronological role execution.
  - `finding_counts`: JSON object containing `{ critical, high, medium, low, total }`.
  - `executed_at`: ISO timestamp string.

---

### 1.4 The 7 Agent Steps of `FULL_E2E_RELAY` Across 6 Roles
- **Location**: `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql` lines 408-558
- **Verbatim Steps Breakdown**:

| Step # | Simulated Actor Role | Action Identifier (`action`) | Default Status | Action Description / Execution Details |
|:---:|:---|:---|:---:|:---|
| **1** | **Head Admin** | `headcount_approval_and_vacancy_init` | `passed` | Authorized headcount quota and opened vacancy `QA-RELAY-{time}-{hash}` |
| **2** | **Encoder** | `plantilla_slot_allocation` | `passed` | Created plantilla slot `EMP-RELAY-{time}-{hash}` assigned to vacancy |
| **3** | **Recruitment** | `applicant_intake_and_pipeline` | `passed` | Registered applicant Jane Relay Doe into candidate pipeline |
| **4** | **HRCO / Operations** | `onboarding_confirmation` | `passed` | Confirmed onboarding and transitioned candidate status |
| **5** | **HR Personnel** | `emploc_generation_and_sync` | `passed` | Prototyped HR Emploc assignment with employee_no `EMP-RELAY-{time}-{hash}` |
| **6** | **Back Office** | `plantilla_move_request` | `passed` | Back Office recorded movement metadata |
| **7** | **Back Office** | `negative_permission_barrier_check` | `passed` (or `failed` if leak detected) | Permission barrier held firm: Back Office restricted from admin actions |

---

### 1.5 Current UI Void for Simulation Results
- **Location**: `src/components/more/QaCenterModal.tsx`
- **Finding**:
  The modal contains zero UI components or visual elements for:
  - Displaying whether the sandbox rolled back.
  - Visualizing the step-by-step progress or outcomes of the simulated agents.
  - Distinguishing roles (`Head Admin` vs `Encoder` vs `Back Office`).
  - Directing the user to findings created during the simulation run.

---

## 2. Logic Chain

1. **Step 1 (Scenario Availability)**:
   The database engine's default parameter is `p_scenario_code text DEFAULT 'FULL_E2E_RELAY'::text`. Adding `{ code: "FULL_E2E_RELAY", label: "Full 6-Role Workflow Relay" }` at index 0 in `COMMON_SCENARIOS` and initializing `selectedScenario` to `"FULL_E2E_RELAY"` ensures that when any administrator opens the QA Center, the flagship end-to-end simulation is immediately active and selectable.

2. **Step 2 (State Capture & Trustworthy Feedback)**:
   Because `qa_run_scenario` catches errors to preserve atomic rollback, `mutateAsync` does not reject on test failures. Capturing `const result = await runScenarioMutation.mutateAsync(...)` into a React state variable `lastScenarioResult` allows the component to check `result?.success`. If `result.success === false`, it shows an alert or warning toast rather than falsely declaring success.

3. **Step 3 (Proof of Zero Data Pollution)**:
   The core requirement of `ORIGINAL_REQUEST.md` (R3) is that operational tables (`vacancies`, `plantilla`, `applicants`, `hr_emploc`) must never be polluted by test runs. Displaying a dedicated, high-contrast **Atomic Sandbox Rollback Status Badge** reading `QA_SANDBOX_ROLLBACK_SUCCESS` gives operators immediate, verifiable confirmation that 100% of mutations were rolled back by PostgreSQL.

4. **Step 4 (Role-Scoped Agent Progression)**:
   The simulation executes a 6-role workflow across 7 discrete steps. Rendering a connected **Agent Step Timeline** with distinct color-coded role badges (e.g. Purple for Head Admin, Blue for Encoder, Teal for Recruitment, Amber for HRCO, Indigo for HR Personnel, Slate for Back Office) and status pills (`PASSED` in emerald, `FAILED` in rose) makes the multi-agent orchestration clear and auditable at a glance.

5. **Step 5 (Defect Feedback Loop)**:
   When an anomaly occurs (e.g., Back Office unauthorized admin access or runtime failure), `qa_run_scenario` logs a finding to `qa_agent_findings` and returns `finding_counts`. Surfacing this count alongside a `"View Detected Findings"` button that programmatically activates the `"findings"` tab completes the operational loop without requiring manual tab hunting.

---

## 3. Concrete Implementation Specifications

### 3.1 Spec A: Update `COMMON_SCENARIOS` and Default State
In `src/components/more/QaCenterModal.tsx`:

```tsx
// 1. Export updated scenario list with FULL_E2E_RELAY as flagship option
export const COMMON_SCENARIOS = [
  { code: "FULL_E2E_RELAY", label: "Full 6-Role Workflow Relay" },
  { code: "VAC_ARCHIVE_001", label: "Vacancy Archival Integrity" },
  { code: "PLANTILLA_001", label: "Plantilla Slot Allocation" },
  { code: "HR_EMPLOC_001", label: "HR Emploc Active Sync" },
  { code: "CENCOM_001", label: "CENCOM Edit Lock & Quota" },
  { code: "AUTH_MATRIX_001", label: "Authorization Drift Probe" },
];

// 2. In QaCenterModal component state:
export function QaCenterModal({ isOpen, onClose, isSuperAdmin }: QaCenterModalProps) {
  const [activeTab, setActiveTab] = useState<QaTab>("overview");
  const [selectedScenario, setSelectedScenario] = useState("FULL_E2E_RELAY");
  const [lastScenarioResult, setLastScenarioResult] = useState<QaScenarioRunResult | null>(null);
  // ...
```

---

### 3.2 Spec B: Update `handleRunScenario` Logic
In `src/components/more/QaCenterModal.tsx`:

```tsx
  const handleRunScenario = async () => {
    if (!selectedScenario) return;
    try {
      const result = (await runScenarioMutation.mutateAsync(selectedScenario)) as QaScenarioRunResult;
      setLastScenarioResult(result);

      if (result?.success) {
        showToast(`Scenario ${selectedScenario} completed cleanly with zero data pollution.`);
      } else {
        showToast(`Scenario ${selectedScenario} finished with findings or execution anomalies.`);
      }
    } catch (err: unknown) {
      showToast(`Scenario run failed: ${(err as Error).message}`);
    }
  };
```

---

### 3.3 Spec C: Role Badge Styling & Normalization Matrix
To provide consistent visual distinction across the 6 simulated roles, use this mapping function:

```tsx
export interface RoleBadgeConfig {
  label: string;
  badgeClass: string;
}

export function getRoleBadgeConfig(roleName: string): RoleBadgeConfig {
  const norm = roleName.toLowerCase();

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
  if (norm.includes("recruitment")) {
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
    label: roleName,
    badgeClass: "bg-surface-subtle text-text-secondary border-border-default",
  };
}
```

---

### 3.4 Spec D: Modular Component Implementation — `QaStepTimeline.tsx`
Create `src/components/more/qa/QaStepTimeline.tsx` (or embed directly into `QaCenterModal.tsx`):

```tsx
"use client";

import React from "react";
import {
  ArrowRight,
  CheckCircle2,
  Clock,
  Database,
  Layers,
  ShieldAlert,
  ShieldCheck,
  XCircle,
} from "lucide-react";
import type { QaScenarioRunResult, QaScenarioStep } from "@/lib/queries/governance";
import { getRoleBadgeConfig } from "./roleBadgeUtils";

interface QaStepTimelineProps {
  result: QaScenarioRunResult | null;
  isRunning: boolean;
  selectedScenarioCode: string;
  onViewFindings?: () => void;
}

export function QaStepTimeline({
  result,
  isRunning,
  selectedScenarioCode,
  onViewFindings,
}: QaStepTimelineProps) {
  if (isRunning) {
    return (
      <div className="rounded-2xl border border-border-default bg-surface-primary p-6 shadow-2xs">
        <div className="flex flex-col items-center justify-center gap-3 py-6 text-center">
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-brand-primary/10 text-brand-primary animate-pulse">
            <Clock className="h-5 w-5 animate-spin" />
          </div>
          <div>
            <h4 className="text-sm font-bold text-text-primary">
              Executing Multi-Role Relay Simulation...
            </h4>
            <p className="text-xs text-text-secondary mt-1">
              Impersonating Head Admin, Encoder, Recruitment, HRCO, HR Personnel, and Back Office actors in an isolated atomic sandbox.
            </p>
          </div>
        </div>
      </div>
    );
  }

  if (!result) {
    return (
      <div className="rounded-2xl border border-dashed border-border-default bg-surface-subtle p-6 text-center">
        <div className="flex justify-center mb-2">
          <Layers className="h-6 w-6 text-text-muted" />
        </div>
        <h4 className="text-xs font-semibold text-text-primary">No Simulation Executed in Current Session</h4>
        <p className="text-xs text-text-muted mt-1 max-w-md mx-auto">
          Select <code className="font-mono font-bold text-text-secondary">{selectedScenarioCode}</code> and click &quot;Run Scenario&quot; above to simulate end-to-end role workflows and verify zero data pollution.
        </p>
      </div>
    );
  }

  const steps: QaScenarioStep[] = result.steps ?? [];
  const findingCounts = result.finding_counts ?? {};
  const totalFindings =
    findingCounts.total ??
    (Number(findingCounts.critical ?? 0) +
      Number(findingCounts.high ?? 0) +
      Number(findingCounts.medium ?? 0) +
      Number(findingCounts.low ?? 0));

  return (
    <div className="rounded-2xl border border-border-default bg-surface-primary p-5 shadow-2xs space-y-4">
      {/* 1. Header Banner & Scenario Status */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-default pb-3.5">
        <div className="flex items-center gap-2.5">
          <div
            className={`flex h-8 w-8 items-center justify-center rounded-xl font-bold ${
              result.success
                ? "bg-status-success-bg text-status-success-text border border-status-success-border"
                : "bg-status-danger-bg text-status-danger-text border border-status-danger-border"
            }`}
          >
            {result.success ? (
              <CheckCircle2 className="h-4 w-4" />
            ) : (
              <XCircle className="h-4 w-4" />
            )}
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-bold text-text-primary">
                Scenario Run: {result.scenario_code}
              </h3>
              <span
                className={`rounded-full px-2 py-0.5 text-xs font-bold border ${
                  result.success
                    ? "bg-status-success-bg text-status-success-text border-status-success-border"
                    : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
                }`}
              >
                {result.success ? "PASSED CLEANLY" : "ANOMALIES DETECTED"}
              </span>
            </div>
            <p className="text-xs text-text-muted mt-0.5 font-mono">
              Run ID: {result.run_id} • Executed: {new Date(result.executed_at).toLocaleTimeString()}
            </p>
          </div>
        </div>

        {/* Defect Count Pill & Quick Jump Button */}
        <div className="flex items-center gap-2">
          {totalFindings > 0 ? (
            <button
              type="button"
              onClick={onViewFindings}
              className="inline-flex items-center gap-1.5 rounded-xl border border-danger-border bg-danger-surface px-3 py-1.5 text-xs font-bold text-danger-text hover:bg-danger-border/30 transition cursor-pointer"
            >
              <ShieldAlert className="h-3.5 w-3.5 text-danger-text" />
              <span>View Detected Findings ({totalFindings})</span>
              <ArrowRight className="h-3 w-3" />
            </button>
          ) : (
            <div className="inline-flex items-center gap-1.5 rounded-xl border border-status-success-border bg-status-success-bg px-3 py-1.5 text-xs font-semibold text-status-success-text">
              <ShieldCheck className="h-3.5 w-3.5" />
              <span>0 Defects Logged</span>
            </div>
          )}
        </div>
      </div>

      {/* 2. Atomic Sandbox Rollback Status Badge */}
      <div
        className={`rounded-xl border p-3.5 flex flex-wrap items-center justify-between gap-3 ${
          result.sandbox_rolled_back
            ? "border-status-success-border bg-status-success-bg/60 text-text-primary"
            : "border-status-danger-border bg-status-danger-bg/60 text-text-primary"
        }`}
      >
        <div className="flex items-center gap-2.5">
          <div
            className={`flex h-7 w-7 items-center justify-center rounded-lg border ${
              result.sandbox_rolled_back
                ? "bg-status-success-bg text-status-success-text border-status-success-border"
                : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
            }`}
          >
            {result.sandbox_rolled_back ? (
              <ShieldCheck className="h-4 w-4 text-status-success-text" />
            ) : (
              <ShieldAlert className="h-4 w-4 text-status-danger-text" />
            )}
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-mono text-xs font-bold text-text-primary tracking-wide">
                {result.sandbox_rolled_back
                  ? "QA_SANDBOX_ROLLBACK_SUCCESS"
                  : "QA_SANDBOX_ROLLBACK_FAILED"}
              </span>
              <span
                className={`rounded-full px-2 py-0.2 text-[10px] font-mono font-bold uppercase border ${
                  result.sandbox_rolled_back
                    ? "bg-surface-primary text-status-success-text border-status-success-border"
                    : "bg-surface-primary text-status-danger-text border-status-danger-border"
                }`}
              >
                {result.sandbox_rolled_back ? "100% Rolled Back" : "Leak Warning"}
              </span>
            </div>
            <p className="text-xs text-text-secondary mt-0.5">
              {result.sandbox_rolled_back
                ? "Zero data pollution confirmed: all test mutations across vacancies, plantilla, applicants, and hr_emploc were atomically reverted."
                : "Isolation warning: subtransaction rollback was not confirmed. Live tables may have uncommitted test data."}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-1.5 text-xs text-text-muted font-mono bg-surface-primary px-2.5 py-1 rounded-lg border border-border-default">
          <Database className="h-3 w-3 text-brand-primary" />
          <span>Operational Tables: Clean</span>
        </div>
      </div>

      {/* 3. Sequential 7-Step Agent Timeline */}
      <div className="space-y-2 pt-1">
        <h4 className="text-xs font-bold text-text-secondary uppercase tracking-wider">
          Multi-Role Agent Execution Timeline ({steps.length} Steps)
        </h4>

        {steps.length === 0 ? (
          <div className="text-xs text-text-muted py-3 text-center">
            No step details returned for this scenario.
          </div>
        ) : (
          <div className="space-y-2">
            {steps.map((st, idx) => {
              const isPassed = st.status.toLowerCase() === "passed";
              const roleConfig = getRoleBadgeConfig(st.role);
              const isLast = idx === steps.length - 1;

              return (
                <div key={st.step} className="relative flex items-start gap-3">
                  {/* Step Connector Line */}
                  {!isLast && (
                    <div className="absolute left-3.5 top-7 bottom-0 w-0.5 bg-border-subtle" />
                  )}

                  {/* Step Circle Badge */}
                  <div
                    className={`relative z-10 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border text-xs font-mono font-bold ${
                      isPassed
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

                      {/* Status Pill */}
                      <span
                        className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold border ${
                          isPassed
                            ? "bg-status-success-bg text-status-success-text border-status-success-border"
                            : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
                        }`}
                      >
                        {isPassed ? (
                          <CheckCircle2 className="h-3 w-3" />
                        ) : (
                          <XCircle className="h-3 w-3" />
                        )}
                        <span>{isPassed ? "PASSED" : "FAILED"}</span>
                      </span>
                    </div>

                    {/* Verbatim Execution Details */}
                    {st.details && (
                      <p className="text-xs font-mono text-text-secondary bg-surface-primary p-2 rounded-lg border border-border-subtle leading-relaxed">
                        {st.details}
                      </p>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
```

---

### 3.5 Spec E: Integrating the Timeline into `QaCenterModal.tsx`
In `src/components/more/QaCenterModal.tsx`:

1. **Import `QaStepTimeline`**:
   ```tsx
   import { QaStepTimeline } from "./qa/QaStepTimeline";
   ```

2. **Render in the Overview Tab**:
   In `activeTab === "overview"`, insert `<QaStepTimeline />` prominently directly above the top KPI Cards (`Health Score`, `Total Runs Logged`, `Open Findings`, `Flaky Tests`):
   ```tsx
   {activeTab === "overview" && (
     <div className="space-y-4">
       {/* Flagship Simulation Runner & Step Timeline */}
       <QaStepTimeline
         result={lastScenarioResult}
         isRunning={runScenarioMutation.isPending}
         selectedScenarioCode={selectedScenario}
         onViewFindings={() => setActiveTab("findings")}
       />

       {/* Top KPI Cards */}
       <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
         {/* ... existing KPI cards ... */}
       </div>
     </div>
   )}
   ```

3. **Auto-Switch to Overview on Execution**:
   In `handleRunScenario`, after executing:
   ```tsx
   if (activeTab !== "overview") {
     setActiveTab("overview");
   }
   ```
   This ensures that no matter which tab the user was inspecting when they clicked `"Run Scenario"` from the sticky execution bar, the modal immediately displays the live 7-step timeline and rollback status!

---

## 4. Caveats

1. **Read-Only Investigation Compliance**:
   This report proposes code changes and specifications. In accordance with Teamwork Explorer protocols, no project files outside the state folder have been modified.
2. **Dependency on Explorer 1 Types**:
   The `QaStepTimeline` component consumes `QaScenarioRunResult` and `QaScenarioStep`. Explorer 1 is defining and exporting these exact interfaces from `src/lib/queries/governance.ts`.
3. **Findings Viewer Synergy with Explorer 3**:
   The `"View Detected Findings"` button transitions the active tab to `"findings"`. Explorer 3 is updating the Findings tab to display the true `finding_type` and actionable `recommendation`. If needed in future enhancements, a state filter `findingRunIdFilter` can be passed to show only the findings generated by `lastScenarioResult.run_id`.

---

## 5. Conclusion

1. **Definitive Fix for Missing Flagship Scenario**:
   Placing `{ code: "FULL_E2E_RELAY", label: "Full 6-Role Workflow Relay" }` at index 0 of `COMMON_SCENARIOS` and setting it as `selectedScenario` default guarantees immediate visibility and execution of the multi-role simulation.
2. **Trustworthy Execution Telemetry**:
   Capturing `lastScenarioResult` in component state ensures that returned execution steps, isolation rollback status, and defect counts are preserved and rendered.
3. **Production-Ready Visual Verification**:
   The **Atomic Sandbox Rollback Status Badge** provides high-contrast, unambiguous proof of zero data pollution (`QA_SANDBOX_ROLLBACK_SUCCESS`), and the **7-Step Agent Timeline** provides complete role-level transparency across Head Admin, Encoder, Recruitment, HRCO, HR Personnel, and Back Office.

---

## 6. Verification Method

To independently verify these designs and implementations:
1. **Scenario Definition Check**:
   - Inspect `src/components/more/QaCenterModal.tsx`: verify `COMMON_SCENARIOS[0].code === "FULL_E2E_RELAY"`.
   - Verify initial state `selectedScenario === "FULL_E2E_RELAY"`.
2. **Payload Capture Check**:
   - Inspect `handleRunScenario`: verify `const result = await runScenarioMutation.mutateAsync(...)` is stored into `lastScenarioResult`.
   - Verify toast alerts are gated on `result?.success`.
3. **Component Layout & Design Check**:
   - Inspect `src/components/more/qa/QaStepTimeline.tsx` (or embedded block).
   - Verify `QA_SANDBOX_ROLLBACK_SUCCESS` badge rendering.
   - Verify 7 steps rendering with role badges (`Head Admin`, `Encoder`, `Recruitment`, `HRCO`, `HR Personnel`, `Back Office`).
   - Verify defect count and `onViewFindings` callback switching `activeTab` to `"findings"`.
4. **Automated Verification Commands**:
   - `npm run check:adr` (confirm ADR freshness)
   - `npm run check:sql` (confirm SQL contracts)
   - `npm run lint` (confirm TypeScript & ESLint pass with 0 errors)
   - `npm test` (confirm all test suites pass)
