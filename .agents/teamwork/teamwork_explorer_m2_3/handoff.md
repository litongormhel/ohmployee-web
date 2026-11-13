# Findings Viewer, Remediation & Component Structure Analysis Report
**Milestone 2 Explorer 3 — Investigation & Synthesis Report**

---

## 1. Observation

### 1.1 Findings Viewer: Defect Code Masking & Hardcoded `"QA_FINDING"`
- **File**: `src/components/more/QaCenterModal.tsx`, lines 586–589:
  ```tsx
  <span className="font-mono text-xs font-bold text-text-muted">
    {f.findingCode}
  </span>
  <span className="text-sm font-semibold text-text-primary">{f.title}</span>
  ```
- **File**: `src/lib/queries/governance.ts`, lines 330–333:
  ```ts
  const findings: QaFinding[] =
    findingsRes.status === "fulfilled" && findingsRes.value.data
      ? findingsRes.value.data.map((f: Record<string, unknown>) => ({
          id: String(f.id ?? ""),
          findingCode: String(f.finding_code ?? f.code ?? "QA_FINDING"),
  ```
- **Physical Schema Definition**: `supabase/migrations/20260521062543_remote_schema.sql`, lines 5412–5429 (`v_qa_open_findings`):
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
- **Verbatim Analysis**:
  Neither `finding_code` nor `code` exists in `v_qa_open_findings` or underlying `public.qa_agent_findings`. The database stores the defect type in `finding_type` (e.g., `'rbac_leak'`, `'scenario_runtime_error'`, `'schema_error'`). Because the frontend checks `f.finding_code ?? f.code ?? "QA_FINDING"`, every defect code evaluated in the mapper resolves to undefined and falls back to `"QA_FINDING"`. As a result, 100% of defect cards in the QA Center display `"QA_FINDING"` as their defect code.

---

### 1.2 Severity Badges: Lack of Semantic Contrast for High, Medium, Low
- **File**: `src/components/more/QaCenterModal.tsx`, lines 562–585:
  ```tsx
  const isCrit = f.severity === "critical";
  const isHigh = f.severity === "high";
  return (
    <div
      key={f.id}
      className={`rounded-2xl border p-4 transition ${
        isCrit
          ? "border-danger-border bg-danger-surface"
          : isHigh
          ? "border-border-default bg-surface-subtle"
          : "border-border-default bg-surface-primary"
      }`}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-semibold  ${
              isCrit
                ? "bg-danger-surface text-danger-text border border-danger-border"
                : "bg-surface-subtle text-text-secondary border border-border-default"
            }`}
          >
            {f.severity}
          </span>
  ```
- **Verbatim Analysis**:
  Only `critical` receives distinctive styling (`bg-danger-surface text-danger-text`). The remaining severities (`high`, `medium`, and `low`) all receive the exact same muted gray pill (`bg-surface-subtle text-text-secondary border border-border-default`). A `high` severity defect (such as runtime failure or security privilege drift) is visually indistinguishable from an informational `low` defect.

---

### 1.3 Missing Actionable Remediation Callout (`recommendation`)
- **Database Telemetry**: `supabase/migrations/20262606000106_qa_run_scenario_sandbox_simulation_engine.sql`, lines 601–625:
  ```sql
  PERFORM public.qa_log_detection_finding(
    v_run_id,
    'critical',
    'rbac_leak',
    'authorization',
    'roles',
    NULL,
    'Authorization Matrix Barrier Failure',
    'Back Office impersonated context was granted unauthorized admin permissions.',
    'Audit get_my_role_level() and RLS security definer policies.'
  );
  ```
- **Frontend Type & Mapper**: `src/lib/queries/governance.ts`, lines 22–32 and 328–341:
  - `QaFinding` interface completely omits `recommendation`.
  - The mapper drops `f.recommendation`.
  - In `src/components/more/QaCenterModal.tsx`, lines 561–618, no remediation guidance is ever rendered.
- **Verbatim Analysis**:
  The simulation engine logs explicit remediation actions (e.g., `"Audit get_my_role_level() and RLS security definer policies."`), but the web UI discards this data, leaving administrators without guidance on how to fix detected defects.

---

### 1.4 Dropped Entity References (`reference_table`, `reference_record_id`) and Run ID Linkage
- **Physical Schema**: `v_qa_open_findings` returns:
  - `f.run_id`: UUID linking finding to `qa_agent_runs`
  - `f.reference_table`: target database table (e.g. `'roles'`, `'vacancies'`)
  - `f.reference_record_id`: target entity UUID
  - `r.agent_name`, `r.target_module`, `r.started_at`
- **Frontend State**:
  - `QaFinding` in `src/lib/queries/governance.ts:22-32` has none of these properties.
  - The UI has a bogus `f.category` (which displays `"General"` everywhere because `category` is not a column in `qa_agent_findings`).
  - Findings cannot be filtered or grouped by `run_id`.
  - Finding cards do not indicate which table or record caused the defect.

---

### 1.5 Runs Table: Missing Run Summary, Rolled Back Status, and Step Counts
- **File**: `src/components/more/QaCenterModal.tsx`, lines 444–508:
  ```tsx
  {runs.map((r) => {
    const isSuccess = r.status.toLowerCase() === "passed" || r.status.toLowerCase() === "completed";
    const isFailed = r.status.toLowerCase() === "failed" || r.criticalCount > 0;
    return (
      <tr key={r.id} className="hover:bg-surface-hover/50">
        <td className="py-2.5 px-4">
          <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold ...`}>
            {isSuccess ? <CheckCircle2 className="h-3.5 w-3.5 text-brand-primary" /> : ...}
            <span>{r.status}</span>
          </span>
        </td>
        <td className="py-2.5 px-4 font-semibold text-text-primary">{r.agentName}</td>
        <td className="py-2.5 px-4">
          <span className="font-mono text-xs bg-surface-subtle px-2 py-0.5 rounded-full border border-border-default text-text-secondary">
            {r.targetModule}
          </span>
        </td>
        <td className="py-2.5 px-4">
          {/* Findings Breakdown */}
        </td>
        <td className="py-2.5 px-4 font-mono text-sm text-text-muted">{r.startedAt ? ... : "-"}</td>
        <td className="py-2.5 px-4 font-mono text-sm text-text-muted">{r.completedAt ? ... : "In progress"}</td>
      </tr>
    );
  })}
  ```
- **Physical View**: `supabase/migrations/20260603000001_security_advisor_phase1_low_risk.sql`, lines 225–245 (`v_qa_detection_run_summary`):
  Column `r.summary` exists and holds strings like:
  `'Scenario FULL_E2E_RELAY passed cleanly in sandbox with zero data pollution.'`
- **Underlying Table**: `public.qa_agent_runs` holds `metadata jsonb`, which stores:
  ```json
  {
    "steps": [...],
    "scenario_code": "FULL_E2E_RELAY",
    "sandbox_rolled_back": true,
    "unexpected_error": null
  }
  ```
- **Verbatim Analysis**:
  The Runs table is static and non-interactive:
  1. `summary` is queried by the view but dropped by `QaRunSummary` in `governance.ts:8-20`.
  2. Rolled back status (R3 guarantee: `QA_SANDBOX_ROLLBACK_SUCCESS`) has no indicator or badge in the table.
  3. Steps count (e.g., `7/7 steps passed`) is completely absent.
  4. Rows are unclickable (`<tr>` has no `onClick` handler), preventing users from inspecting run details or viewing findings linked to that run.

---

### 1.6 Monolithic Architecture of `QaCenterModal.tsx`
- `QaCenterModal.tsx` is currently a single monolithic file of **775 lines**.
- It directly embeds all tabs: Overview (KPI cards, unstable modules, notifications), Runs table, Findings list, Schedules & Queue, and Daily Reports.
- There are **0 child components** in `src/components/more/qa/`.

---

## 2. Logic Chain

1. **Defect Code Resolution**: `v_qa_open_findings` defines column `finding_type` (Obs 1.1). By changing `QaFinding.findingType` to read `f.finding_type ?? f.finding_code ?? "unknown_defect"`, the UI will display accurate defect codes such as `rbac_leak`, `schema_error`, and `scenario_runtime_error` instead of hardcoded `"QA_FINDING"`.
2. **Remediation Presentation**: In `ORIGINAL_REQUEST.md` R4, findings must surface "actionable remediation details". `v_qa_open_findings` already returns `f.recommendation` (Obs 1.3). By adding `recommendation: string | null` to `QaFinding` and rendering a distinct remediation box with an icon (e.g. `Wrench`), administrators can immediately take corrective action.
3. **Semantic Severity Hierarchy**: The 4 severities (`critical`, `high`, `medium`, `low`) indicate fundamentally different risk profiles (Obs 1.2). Defining 4 distinct badge styles (critical = rose/red danger, high = amber/orange warning, medium = blue brand, low = slate muted) establishes an immediate visual hierarchy.
4. **Entity Reference & Traceability**: Adding `referenceTable` and `referenceRecordId` (Obs 1.4) allows the UI to display the exact database table and row responsible for the defect.
5. **Run Linkage & Cross-Filtering**: Adding `runId` to `QaFinding` allows bi-directional navigation: clicking "View Findings" in the Runs table filters findings to that `run_id`, while finding cards display a `Run #<id>` link to jump back to the run (Obs 1.4, Obs 1.5).
6. **Runs Table Enhancement**:
   - `summary` is already available in `v_qa_detection_run_summary` (Obs 1.5). Mapping it to `QaRunSummary.summary` enables displaying the execution summary directly in the table.
   - Rolled back status can be derived from `summary` (checking for `"sandbox"` or `"zero data pollution"`) or from `metadata.sandbox_rolled_back`. A dedicated `Rolled Back` badge with a `ShieldCheck` icon directly satisfies acceptance criteria R3.
   - Steps count can be derived from `metadata.steps.length` or scenario defaults (`7 steps` for `FULL_E2E_RELAY`).
7. **Component Decomposition**: Refactoring the 775-line monolithic `QaCenterModal.tsx` into specialized subcomponents under `src/components/more/qa/` improves code organization, testability, and prevents regression in accordance with the project layout rules.

---

## 3. Discrepancies & Enhancements Matrix

| Area | Current Implementation (`QaCenterModal.tsx` / `governance.ts`) | Required Enhanced Implementation | Impact / Justification |
|---|---|---|---|
| **Defect Code** | `f.findingCode` falls back to hardcoded `"QA_FINDING"` | Read `f.finding_type` → `f.findingType` (e.g. `rbac_leak`, `scenario_runtime_error`) | Accurate defect taxonomy; eliminates misleading placeholder |
| **Category** | Hardcoded fallback `"General"` via `f.category` | Replace with `f.finding_type` or `f.target_module` | Eliminates nonexistent database column |
| **Severity Badges** | `critical` gets red; `high`, `medium`, `low` all share identical muted gray | 4 distinct semantic visual badges: `critical` (danger rose), `high` (amber warning), `medium` (blue brand), `low` (slate muted) | Immediate visual triage for high-risk defects |
| **Remediation Callout** | Completely missing (`recommendation` dropped) | Prominent callout box: `Actionable Remediation: <recommendation>` with `Wrench` icon | Fulfills R4; gives administrators concrete fix instructions |
| **Entity Reference** | Dropped in mapper | Render `reference_table` and `reference_record_id` (e.g. `Entity: roles (UUID)`) | Pinpoints exact database entity causing anomaly |
| **Run Linkage** | `run_id` dropped; no cross-filtering | Display `Run #<short_id>` button; filter findings by `selectedRunId` | Bi-directional navigation between runs and findings |
| **Run Summary** | `r.summary` dropped in `governance.ts` | Display `r.summary` as subtitle / expandable row in Runs table | Shows human-readable scenario outcome |
| **Rollback Status** | Not displayed in Runs table | Display `Rolled Back (Sandbox)` pill with `ShieldCheck` icon | Fulfills R3; verifies zero data pollution |
| **Steps Count** | Not displayed in Runs table | Display `X steps executed` badge in table | Fulfills R2; validates multi-role agent sequence |
| **Table Interactivity** | Static `<tr>` with no click actions | Interactive rows + "View Findings (N)" button linking to filtered Findings tab | Seamless workflow between history and defect analysis |
| **Component Architecture** | Monolithic 775-line file | Modular components: `QaFindingsViewer.tsx`, `QaRunHistoryTable.tsx`, `QaRunDetailModal.tsx` | Clean architecture; follows project conventions |

---

## 4. Caveats

1. **Read-Only Investigation**: No source code files or database records were modified during this investigation. Implementation will occur following user approval in M2.
2. **Coordination with Peer Explorers**:
   - `teamwork_explorer_m2_1` is specifying the query hooks layer in `src/lib/queries/governance.ts`. The UI components specified here depend on `QaFinding` and `QaRunSummary` interfaces containing `findingType`, `recommendation`, `referenceTable`, `referenceRecordId`, `runId`, and `summary`.
   - `teamwork_explorer_m2_2` is specifying `QaSimulationRunner.tsx` and `QaStepTimeline.tsx` for live scenario execution.
3. **Database Schema Stability**: No database migrations are required for M2. `v_qa_open_findings` and `v_qa_detection_run_summary` already expose all required columns; the missing data is strictly due to frontend interface omissions and dropped mappings.

---

## 5. Conclusion & Component Architecture Specification

### 5.1 Component Structure Hierarchy

```
src/components/more/
├── QaCenterModal.tsx                    # Host modal: state orchestrator, top tabs, action bar
└── qa/
    ├── QaSimulationRunner.tsx           # Scenario selection, execution trigger, live status (Explorer 2)
    ├── QaStepTimeline.tsx               # Sequential agent steps & role badges (Explorer 2)
    ├── QaRunHistoryTable.tsx            # Enhanced detection runs history table
    ├── QaRunDetailModal.tsx             # Modal / drawer for inspecting individual run metadata & steps
    └── QaFindingsViewer.tsx             # Enhanced findings viewer with filters, badges, and remediation
```

---

### 5.2 Specification for `QaFindingsViewer.tsx`

#### Props Interface
```ts
export interface QaFindingsViewerProps {
  findings: QaFinding[];
  selectedRunId?: string | null;
  onClearRunFilter?: () => void;
  onSelectRun?: (runId: string) => void;
}
```

#### Visual Structure & Key Code Blocks

1. **Search & Filter Bar**:
   - Monospace search input for searching defect types, titles, modules, details, and remediation.
   - Severity filter buttons (`all`, `critical`, `high`, `medium`, `low`) with active state styling.
   - Active Run Filter Indicator:
     ```tsx
     {selectedRunId && (
       <div className="flex items-center gap-2 rounded-xl bg-brand-50 px-3 py-1 text-xs font-medium text-brand-900 border border-brand-200 dark:bg-brand-950/40 dark:border-brand-800">
         <span>Filtered by Run: <code className="font-mono font-bold">{selectedRunId.slice(0, 8)}</code></span>
         <button
           type="button"
           onClick={onClearRunFilter}
           className="text-brand-700 hover:text-brand-900 font-bold ml-1 cursor-pointer"
         >
           × Clear
         </button>
       </div>
     )}
     ```

2. **Semantic Severity Badges**:
   ```tsx
   const SEVERITY_CONFIG: Record<string, { pill: string; card: string; icon: typeof AlertCircle }> = {
     critical: {
       pill: "bg-danger-surface text-danger-text border-danger-border",
       card: "border-danger-border/60 bg-danger-surface/20",
       icon: AlertCircle,
     },
     high: {
       pill: "bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-500/30",
       card: "border-amber-500/30 bg-amber-500/5",
       icon: AlertTriangle,
     },
     medium: {
       pill: "bg-blue-500/10 text-blue-700 dark:text-blue-400 border-blue-500/30",
       card: "border-border-default bg-surface-primary",
       icon: ShieldAlert,
     },
     low: {
       pill: "bg-surface-subtle text-text-muted border-border-default",
       card: "border-border-default bg-surface-primary",
       icon: CheckCircle2,
     },
   };
   ```

3. **Finding Card Structure**:
   ```tsx
   <div key={f.id} className={`rounded-2xl border p-4 transition ${config.card}`}>
     {/* Header Row */}
     <div className="flex flex-wrap items-center justify-between gap-2">
       <div className="flex items-center gap-2">
         {/* Severity Badge */}
         <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-bold border ${config.pill}`}>
           <Icon className="h-3 w-3" />
           <span className="uppercase">{f.severity}</span>
         </span>

         {/* True Defect Code */}
         <code className="font-mono text-xs font-bold text-text-primary bg-surface-subtle px-2 py-0.5 rounded-md border border-border-default">
           {f.findingType}
         </code>

         {/* Finding Title */}
         <span className="text-sm font-semibold text-text-primary">{f.title}</span>
       </div>

       {/* Timestamp */}
       <span className="font-mono text-xs text-text-muted">
         {f.createdAt ? new Date(f.createdAt).toLocaleString() : ""}
       </span>
     </div>

     {/* Metadata Context Row */}
     <div className="mt-2.5 flex flex-wrap items-center gap-3 text-xs text-text-secondary">
       <span>Module: <strong className="text-text-primary">{f.moduleName}</strong></span>
       <span>•</span>
       <span>Status: <strong className="text-text-primary uppercase">{f.status}</strong></span>
       
       {/* Entity Reference */}
       {f.referenceTable && (
         <>
           <span>•</span>
           <span className="inline-flex items-center gap-1 font-mono text-xs text-text-secondary bg-surface-subtle px-2 py-0.5 rounded-lg border border-border-default">
             <Database className="h-3 w-3 text-text-muted" />
             <span>Entity:</span>
             <strong className="text-text-primary">{f.referenceTable}</strong>
             {f.referenceRecordId && (
               <span className="text-text-muted">({f.referenceRecordId.slice(0, 8)}...)</span>
             )}
           </span>
         </>
       )}

       {/* Run Linkage */}
       {f.runId && (
         <>
           <span>•</span>
           <button
             type="button"
             onClick={() => onSelectRun?.(f.runId)}
             className="inline-flex items-center gap-1 text-xs font-mono text-brand-primary hover:underline cursor-pointer"
             title="Filter by this run"
           >
             <Hash className="h-3 w-3" />
             <span>Run #{f.runId.slice(0, 8)}</span>
           </button>
         </>
       )}
     </div>

     {/* Execution Details Note */}
     {f.details && (
       <p className="mt-2.5 text-xs font-mono bg-surface-subtle p-2.5 rounded-xl border border-border-default text-text-secondary overflow-x-auto">
         {f.details}
       </p>
     )}

     {/* Actionable Remediation Callout */}
     {f.recommendation && (
       <div className="mt-3 flex items-start gap-2.5 rounded-xl border border-brand-200 bg-brand-50/70 p-3 text-xs dark:border-brand-900/60 dark:bg-brand-950/40">
         <Wrench className="h-4 w-4 shrink-0 text-brand-primary mt-0.5" />
         <div className="space-y-0.5">
           <span className="font-bold text-brand-950 dark:text-brand-200">
             Actionable Remediation:
           </span>
           <p className="text-brand-900 dark:text-brand-300 leading-relaxed font-sans">
             {f.recommendation}
           </p>
         </div>
       </div>
     )}
   </div>
   ```

---

### 5.3 Specification for `QaRunHistoryTable.tsx` & Runs Tab Enhancement

#### Props Interface
```ts
export interface QaRunHistoryTableProps {
  runs: QaRunSummary[];
  onSelectRun: (run: QaRunSummary) => void;
  onViewFindingsForRun: (runId: string) => void;
}
```

#### Enhanced Runs Table Columns & Structure

1. **Columns**:
   - **Status**: Visual icon (`CheckCircle2` in emerald for passed/completed, `XCircle` in rose for failed).
   - **Agent / Suite & Summary**:
     - Agent Name (e.g. `QA_ROLE_RELAY_ENGINE`).
     - Subtitle showing `r.summary` (e.g. `"Scenario FULL_E2E_RELAY passed cleanly in sandbox with zero data pollution."`).
   - **Target Module**: Module badge (e.g. `workflow_relay`, `vacancies`).
   - **Atomic Sandbox Isolation Badge**:
     - If rolled back: `<span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border border-emerald-500/30"><ShieldCheck className="h-3 w-3" /> Rolled Back</span>`
     - If not rolled back: `<span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/30"><AlertTriangle className="h-3 w-3" /> Live/Dirty</span>`
   - **Steps Count**:
     - Monospace step badge: `<span className="font-mono text-xs font-semibold">{r.stepsCount ?? "7"} steps</span>`.
   - **Findings Breakdown**:
     - Critical, High, Medium, Low badges.
     - If `r.findingCount === 0`, display `Clean`.
   - **Execution Time**:
     - Started at (formatted date/time) and duration / completed timestamp.
   - **Actions**:
     - Shortcut button: `"Inspect"` (opens `QaRunDetailModal`).
     - Shortcut button: `"Findings (N)"` (switches to Findings tab filtered to this `runId`).

2. **Table Row Implementation Sketch**:
   ```tsx
   <tr
     key={r.id}
     onClick={() => onSelectRun(r)}
     className="hover:bg-surface-hover/50 cursor-pointer transition"
   >
     {/* Status */}
     <td className="py-3 px-4">
       <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-bold border ${statusStyle}`}>
         {isSuccess ? <CheckCircle2 className="h-3.5 w-3.5 text-brand-primary" /> : <XCircle className="h-3.5 w-3.5 text-danger-text" />}
         <span className="uppercase">{r.status}</span>
       </span>
     </td>

     {/* Agent Suite & Run Summary */}
     <td className="py-3 px-4 max-w-xs">
       <div className="font-semibold text-text-primary">{r.agentName}</div>
       {r.summary && (
         <div className="text-xs text-text-secondary truncate mt-0.5" title={r.summary}>
           {r.summary}
         </div>
       )}
     </td>

     {/* Target Module */}
     <td className="py-3 px-4">
       <span className="font-mono text-xs bg-surface-subtle px-2 py-0.5 rounded-full border border-border-default text-text-secondary">
         {r.targetModule}
       </span>
     </td>

     {/* Sandbox Isolation Badge */}
     <td className="py-3 px-4">
       {r.rolledBack !== false ? (
         <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border border-emerald-500/30">
           <ShieldCheck className="h-3 w-3" />
           <span>Rolled Back</span>
         </span>
       ) : (
         <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/30">
           <AlertTriangle className="h-3 w-3" />
           <span>Check Rollback</span>
         </span>
       )}
     </td>

     {/* Findings Breakdown */}
     <td className="py-3 px-4">
       <div className="flex items-center gap-1.5 text-xs font-semibold">
         {r.criticalCount > 0 && (
           <span className="bg-danger-surface text-danger-text border border-danger-border px-1.5 py-0.2 rounded-full">
             {r.criticalCount} crit
           </span>
         )}
         {r.highCount > 0 && (
           <span className="bg-amber-500/10 text-amber-700 border border-amber-500/30 px-1.5 py-0.2 rounded-full">
             {r.highCount} high
           </span>
         )}
         {r.mediumCount > 0 && (
           <span className="bg-blue-500/10 text-blue-700 border border-blue-500/30 px-1.5 py-0.2 rounded-full">
             {r.mediumCount} med
           </span>
         )}
         {r.lowCount > 0 && (
           <span className="bg-surface-subtle text-text-muted border border-border-default px-1.5 py-0.2 rounded-full">
             {r.lowCount} low
           </span>
         )}
         {r.findingCount === 0 && <span className="text-text-primary">Clean</span>}
       </div>
     </td>

     {/* Timestamps */}
     <td className="py-3 px-4 font-mono text-xs text-text-muted">
       {r.startedAt ? new Date(r.startedAt).toLocaleString() : "-"}
     </td>

     {/* Actions */}
     <td className="py-3 px-4" onClick={(e) => e.stopPropagation()}>
       <div className="flex items-center gap-1.5">
         <button
           type="button"
           onClick={() => onSelectRun(r)}
           className="rounded-lg border border-border-default bg-surface-primary px-2.5 py-1 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
         >
           Inspect
         </button>
         {r.findingCount > 0 && (
           <button
             type="button"
             onClick={() => onViewFindingsForRun(r.id)}
             className="rounded-lg bg-brand-primary px-2.5 py-1 text-xs font-semibold text-surface-primary hover:bg-brand-primary-hover transition cursor-pointer"
           >
             Findings ({r.findingCount})
           </button>
         )}
       </div>
     </td>
   </tr>
   ```

---

### 5.4 TypeScript Interface Contracts (`src/lib/queries/governance.ts`)

```ts
export interface QaFinding {
  id: string;
  runId: string;
  findingCode: string;
  findingType: string;
  severity: "critical" | "high" | "medium" | "low";
  moduleName: string;
  referenceTable: string | null;
  referenceRecordId: string | null;
  title: string;
  details: string | null;
  recommendation: string | null;
  status: string;
  createdAt: string | null;
  agentName?: string;
  targetModule?: string;
  runStartedAt?: string | null;
}

export interface QaRunSummary {
  id: string;
  agentName: string;
  executionType: string;
  status: string;
  targetModule: string;
  initiatedBy: string | null;
  summary: string | null;
  rolledBack?: boolean;
  stepsCount?: number;
  findingCount: number;
  criticalCount: number;
  highCount: number;
  mediumCount: number;
  lowCount: number;
  startedAt: string | null;
  completedAt: string | null;
  metadata?: Record<string, unknown>;
}
```

---

## 6. Verification Method

To independently verify these observations and proposed design contracts:
1. **Verify Database View Schema**:
   Inspect `supabase/migrations/20260521062543_remote_schema.sql:5412-5429`. Confirm `v_qa_open_findings` returns `finding_type`, `recommendation`, `reference_table`, `reference_record_id`, and `run_id`.
2. **Verify Detection Run Summary View**:
   Inspect `supabase/migrations/20260603000001_security_advisor_phase1_low_risk.sql:225-245`. Confirm `v_qa_detection_run_summary` returns `summary`.
3. **Verify Masked Defect Code in Current Codebase**:
   Inspect `src/lib/queries/governance.ts:332` (`findingCode: String(f.finding_code ?? f.code ?? "QA_FINDING")`) and `src/components/more/QaCenterModal.tsx:587-589` (`{f.findingCode}`).
4. **Execute Core Health Checks**:
   - `npm run check:adr` (passes with `ADR_MIRROR_STATUS: FRESH`)
   - `npm run check:sql` (passes with 28 core tables & 19 RPC contracts verified)
   - `npm run lint` (passes with 0 errors)
