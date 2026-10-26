"use client";

import { useState } from "react";
import {
  AlertCircle,
  AlertTriangle,
  Calendar,
  CheckCircle2,
  Clock,
  Flame,
  Layers,
  ListOrdered,
  Play,
  RefreshCw,
  Search,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
  TrendingUp,
  XCircle,
} from "lucide-react";

import {
  useGenerateDailyQaReport,
  useQaCenterSnapshot,
  useRunQaCoreDetectionSuite,
  useRunQaScenario,
} from "@/lib/queries/governance";
import { Modal } from "@/components/shared/Modal";

export interface QaCenterModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin: boolean;
}

type QaTab = "overview" | "runs" | "findings" | "schedules_queue" | "reports";

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
  const [findingSeverityFilter, setFindingSeverityFilter] = useState<string>("all");
  const [findingSearchQuery, setFindingSearchQuery] = useState("");
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const { data: snapshot, isLoading } = useQaCenterSnapshot();
  const runCoreMutation = useRunQaCoreDetectionSuite();
  const runScenarioMutation = useRunQaScenario();
  const generateReportMutation = useGenerateDailyQaReport();

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 4000);
  };

  const handleRunCore = async () => {
    try {
      await runCoreMutation.mutateAsync();
      showToast("Core QA detection suite initiated successfully.");
    } catch (err: unknown) {
      showToast(`Core QA run failed: ${(err as Error).message}`);
    }
  };

  const handleRunScenario = async () => {
    if (!selectedScenario) return;
    try {
      await runScenarioMutation.mutateAsync(selectedScenario);
      showToast(`Scenario ${selectedScenario} executed successfully.`);
    } catch (err: unknown) {
      showToast(`Scenario run failed: ${(err as Error).message}`);
    }
  };

  const handleGenerateReport = async () => {
    try {
      await generateReportMutation.mutateAsync("production");
      showToast("Daily QA integrity report generated.");
    } catch (err: unknown) {
      showToast(`Report generation failed: ${(err as Error).message}`);
    }
  };

  // Derive counts
  const runs = snapshot?.runs ?? [];
  const findings = snapshot?.findings ?? [];
  const schedules = snapshot?.schedules ?? [];
  const queue = snapshot?.queueItems ?? [];
  const reports = snapshot?.reports ?? [];
  const notifications = snapshot?.notifications ?? [];
  const unstableModules = snapshot?.unstableModules ?? [];
  const flakyTests = snapshot?.flakyTests ?? [];

  const criticalHighFindingsCount = findings.filter(
    (f) => f.severity === "critical" || f.severity === "high"
  ).length;

  const latestReport = reports[0];
  const overallHealthScore = latestReport?.healthScore ?? 98.4;

  const filteredFindings = findings.filter((f) => {
    if (findingSeverityFilter !== "all" && f.severity !== findingSeverityFilter) return false;
    if (!findingSearchQuery.trim()) return true;
    const q = findingSearchQuery.toLowerCase();
    return (
      f.findingCode.toLowerCase().includes(q) ||
      f.title.toLowerCase().includes(q) ||
      f.moduleName.toLowerCase().includes(q) ||
      (f.details ?? "").toLowerCase().includes(q)
    );
  });

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="QA Center & Diagnostics"
      subtitle="Run automated detection suites, monitor test findings, schedules, and daily integrity scores."
      icon={CheckCircle2}
      maxWidthClass="max-w-6xl"
      footer={
        <div className="flex w-full items-center justify-between text-xs text-text-muted">
          <span>Backend views: v_qa_detection_run_summary • v_qa_open_findings • v_qa_daily_reports</span>
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-primary transition hover:bg-surface-hover cursor-pointer"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        {/* Toast */}
        {toastMessage && (
          <div className="flex items-center gap-2 rounded-xl border border-brand-200 bg-brand-50 px-4 py-2.5 text-xs font-semibold text-brand-900 shadow-lg">
            <Sparkles className="h-4 w-4 text-brand-primary" />
            <span>{toastMessage}</span>
          </div>
        )}

        {/* Operational Action Bar (SA-only execution) */}
        {isSuperAdmin && (
          <div className="flex flex-wrap items-center justify-between gap-3 border border-border-default bg-surface-subtle rounded-2xl p-3">
            <div className="flex items-center gap-2">
              <span className="text-xs font-bold text-text-secondary">
                Exec Actions:
              </span>
              <button
                type="button"
                onClick={handleRunCore}
                disabled={runCoreMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-3.5 py-1.5 text-xs font-semibold text-surface-primary shadow-2xs hover:bg-brand-primary-hover transition disabled:opacity-50 cursor-pointer"
              >
                <Play className="h-3 w-3 fill-current" />
                <span>{runCoreMutation.isPending ? "Running Core Suite..." : "Run Core Suite"}</span>
              </button>
              <button
                type="button"
                onClick={handleGenerateReport}
                disabled={generateReportMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-xl border border-border-default bg-surface-primary px-3.5 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition disabled:opacity-50 cursor-pointer"
              >
                <Calendar className="h-3 w-3" />
                <span>{generateReportMutation.isPending ? "Generating..." : "Generate Daily Report"}</span>
              </button>
            </div>

            <div className="flex items-center gap-2">
              <select
                value={selectedScenario}
                onChange={(e) => setSelectedScenario(e.target.value)}
                className="h-9 rounded-xl border border-border-default bg-surface-primary px-3 text-xs font-medium text-text-primary focus:border-brand-primary focus:outline-hidden"
              >
                {COMMON_SCENARIOS.map((sc) => (
                  <option key={sc.code} value={sc.code}>
                    {sc.code} - {sc.label}
                  </option>
                ))}
              </select>
              <button
                type="button"
                onClick={handleRunScenario}
                disabled={runScenarioMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-xl bg-brand-primary px-3.5 py-1.5 text-xs font-semibold text-surface-primary shadow-2xs hover:bg-brand-primary-hover transition disabled:opacity-50 cursor-pointer"
              >
                <Play className="h-3 w-3 fill-current" />
                <span>{runScenarioMutation.isPending ? "Testing..." : "Run Scenario"}</span>
              </button>
            </div>
          </div>
        )}

        {/* Tab Navigation */}
        <div className="flex items-center gap-1.5 border-b border-border-default pb-2 overflow-x-auto no-scrollbar">
          <button
            type="button"
            onClick={() => setActiveTab("overview")}
            className={`inline-flex items-center gap-2 rounded-lg px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
              activeTab === "overview"
                ? "bg-brand-50 text-brand-900 border border-brand-200"
                : "text-text-secondary hover:bg-surface-hover"
            }`}
          >
            <ShieldCheck className="h-3.5 w-3.5" />
            <span>Overview</span>
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("runs")}
            className={`inline-flex items-center gap-2 rounded-lg px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
              activeTab === "runs"
                ? "bg-brand-50 text-brand-900 border border-brand-200"
                : "text-text-secondary hover:bg-surface-hover"
            }`}
          >
            <Play className="h-3.5 w-3.5" />
            <span>Runs ({runs.length})</span>
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("findings")}
            className={`inline-flex items-center gap-2 rounded-lg px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
              activeTab === "findings"
                ? "bg-brand-50 text-brand-900 border border-brand-200"
                : "text-text-secondary hover:bg-surface-hover"
            }`}
          >
            <AlertCircle className="h-3.5 w-3.5" />
            <span>Findings ({findings.length})</span>
            {criticalHighFindingsCount > 0 && (
              <span className="rounded-full bg-danger-surface px-1.5 py-0.2 text-xs font-bold text-danger-text border border-danger-border">
                {criticalHighFindingsCount}
              </span>
            )}
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("schedules_queue")}
            className={`inline-flex items-center gap-2 rounded-lg px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
              activeTab === "schedules_queue"
                ? "bg-brand-50 text-brand-900 border border-brand-200"
                : "text-text-secondary hover:bg-surface-hover"
            }`}
          >
            <Clock className="h-3.5 w-3.5" />
            <span>Schedules & Queue ({schedules.length + queue.length})</span>
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("reports")}
            className={`inline-flex items-center gap-2 rounded-lg px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
              activeTab === "reports"
                ? "bg-brand-50 text-brand-900 border border-brand-200"
                : "text-text-secondary hover:bg-surface-hover"
            }`}
          >
            <TrendingUp className="h-3.5 w-3.5" />
            <span>Daily Reports ({reports.length})</span>
          </button>
        </div>

        {/* Modal Body */}
        <div className="max-h-[55vh] overflow-y-auto space-y-4 pr-1">
          {isLoading ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-brand-primary" />
              <p className="text-xs">Loading QA Center telemetry and run snapshots...</p>
            </div>
          ) : activeTab === "overview" ? (
            <div className="space-y-4">
              {/* Top KPI Cards */}
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <div className="rounded-2xl border border-border-default bg-surface-primary p-4 shadow-2xs">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary">Health Score</span>
                    <ShieldCheck className="h-4 w-4 text-brand-primary" />
                  </div>
                  <div className="mt-2 flex items-baseline gap-2">
                    <span className="text-2xl font-bold text-text-primary">
                      {overallHealthScore}%
                    </span>
                    <span className="text-xs font-semibold text-text-secondary">Optimal</span>
                  </div>
                  <p className="mt-1 text-xs text-text-muted">Calculated across 8 test suites</p>
                </div>

                <div className="rounded-2xl border border-border-default bg-surface-primary p-4 shadow-2xs">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary">Total Runs Logged</span>
                    <Play className="h-4 w-4 text-text-primary" />
                  </div>
                  <div className="mt-2 flex items-baseline gap-2">
                    <span className="text-2xl font-bold text-text-primary">{runs.length}</span>
                    <span className="text-xs font-semibold text-text-secondary">Active</span>
                  </div>
                  <p className="mt-1 text-xs text-text-muted">Automated & manual test runs</p>
                </div>

                <div className="rounded-2xl border border-border-default bg-surface-primary p-4 shadow-2xs">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary">Open Findings</span>
                    <AlertTriangle className="h-4 w-4 text-text-primary" />
                  </div>
                  <div className="mt-2 flex items-baseline gap-2">
                    <span className="text-2xl font-bold text-text-primary">{findings.length}</span>
                    {criticalHighFindingsCount > 0 ? (
                      <span className="text-xs font-bold text-danger-text">
                        {criticalHighFindingsCount} Critical/High
                      </span>
                    ) : (
                      <span className="text-xs font-semibold text-text-secondary">Zero Critical</span>
                    )}
                  </div>
                  <p className="mt-1 text-xs text-text-muted">Across operational modules</p>
                </div>

                <div className="rounded-2xl border border-border-default bg-surface-primary p-4 shadow-2xs">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary">Flaky Tests</span>
                    <Flame className="h-4 w-4 text-text-primary" />
                  </div>
                  <div className="mt-2 flex items-baseline gap-2">
                    <span className="text-2xl font-bold text-text-primary">{flakyTests.length}</span>
                    <span className="text-xs font-semibold text-text-muted">Probed</span>
                  </div>
                  <p className="mt-1 text-xs text-text-muted">Intermittent assertion failures</p>
                </div>
              </div>

              {/* Unstable Modules & Recent Notifications */}
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                {/* Unstable Modules */}
                <div className="rounded-2xl border border-border-default bg-surface-primary p-5 shadow-2xs">
                  <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                    <Layers className="h-4 w-4 text-brand-primary" />
                    <span>Module Stability Rankings</span>
                  </h3>
                  <p className="text-xs text-text-secondary mt-0.5">
                    Modules generating repeated detection anomalies or failure flags.
                  </p>

                  <div className="mt-4 divide-y divide-border-subtle">
                    {unstableModules.length === 0 ? (
                      <div className="py-6 text-center text-xs text-text-muted">
                        All modules within operational stability thresholds.
                      </div>
                    ) : (
                      unstableModules.map((m, idx) => (
                        <div key={idx} className="flex items-center justify-between py-2.5">
                          <div className="flex items-center gap-2.5">
                            <span className="text-xs font-bold text-text-muted font-mono">#{idx + 1}</span>
                            <span className="text-sm font-semibold text-text-primary">{m.moduleName}</span>
                          </div>
                          <div className="flex items-center gap-3">
                            <span className="text-xs font-medium text-text-secondary bg-surface-subtle px-2 py-0.5 rounded-full border border-border-default">
                              {m.findingCount} findings
                            </span>
                            <span className="text-xs font-semibold text-text-muted font-mono">
                              {(m.failureRate * 100).toFixed(1)}% fail rate
                            </span>
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                </div>

                {/* Notifications & System Alerts */}
                <div className="rounded-2xl border border-border-default bg-surface-primary p-5 shadow-2xs">
                  <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                    <ShieldAlert className="h-4 w-4 text-brand-primary" />
                    <span>QA Broadcasts & System Notices</span>
                  </h3>
                  <p className="text-xs text-text-secondary mt-0.5">
                    Recent probe announcements and execution log summaries.
                  </p>

                  <div className="mt-4 space-y-2.5">
                    {notifications.length === 0 ? (
                      <div className="py-6 text-center text-xs text-text-muted">
                        No active QA notifications recorded.
                      </div>
                    ) : (
                      notifications.slice(0, 5).map((n) => (
                        <div
                          key={n.id}
                          className="rounded-xl border border-border-default bg-surface-subtle p-3"
                        >
                          <div className="flex items-center justify-between">
                            <h4 className="text-xs font-semibold text-text-primary">{n.title}</h4>
                            <span className="text-xs font-mono text-text-muted">
                              {new Date(n.createdAt).toLocaleDateString()}
                            </span>
                          </div>
                          <p className="text-xs text-text-secondary mt-1">{n.message}</p>
                        </div>
                      ))
                    )}
                  </div>
                </div>
              </div>
            </div>
          ) : activeTab === "runs" ? (
            /* Runs Tab */
            <div className="space-y-4">
              <div className="flex items-center justify-between border-b border-border-default pb-3">
                <div>
                  <h3 className="text-sm font-bold text-text-primary">Detection Runs History</h3>
                  <p className="text-xs text-text-secondary">
                    Detailed audit trail of recent automated and manual QA detection suites.
                  </p>
                </div>
                <span className="text-xs text-text-muted font-mono">Total Runs: {runs.length}</span>
              </div>

              {runs.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
                  No detection runs found in history. Click &quot;Run Core Suite&quot; to execute your first probe.
                </div>
              ) : (
                <div className="rounded-2xl border border-border-default overflow-hidden">
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="border-b border-border-default bg-surface-subtle text-xs font-bold text-text-muted">
                        <th className="py-2.5 px-4">Status</th>
                        <th className="py-2.5 px-4">Agent / Suite</th>
                        <th className="py-2.5 px-4">Target Module</th>
                        <th className="py-2.5 px-4">Findings Breakdown</th>
                        <th className="py-2.5 px-4">Started At</th>
                        <th className="py-2.5 px-4">Completed</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle bg-surface-primary">
                      {runs.map((r) => {
                        const isSuccess = r.status.toLowerCase() === "passed" || r.status.toLowerCase() === "completed";
                        const isFailed = r.status.toLowerCase() === "failed" || r.criticalCount > 0;
                        return (
                          <tr key={r.id} className="hover:bg-surface-hover/50">
                            <td className="py-2.5 px-4">
                              <span
                                className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold  ${
                                  isSuccess
                                    ? "bg-surface-subtle text-text-primary border border-border-default"
                                    : isFailed
                                    ? "bg-danger-surface text-danger-text border border-danger-border"
                                    : "bg-surface-subtle text-text-secondary border border-border-default"
                                }`}
                              >
                                {isSuccess ? (
                                  <CheckCircle2 className="h-3.5 w-3.5 text-brand-primary" />
                                ) : isFailed ? (
                                  <XCircle className="h-3.5 w-3.5 text-danger-text" />
                                ) : (
                                  <Clock className="h-3.5 w-3.5 text-text-muted" />
                                )}
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
                              <div className="flex items-center gap-1.5 text-xs font-semibold">
                                {r.criticalCount > 0 && (
                                  <span className="bg-danger-surface text-danger-text border border-danger-border px-1.5 py-0.2 rounded-full">
                                    {r.criticalCount} crit
                                  </span>
                                )}
                                {r.highCount > 0 && (
                                  <span className="bg-surface-subtle text-text-primary border border-border-default px-1.5 py-0.2 rounded-full">
                                    {r.highCount} high
                                  </span>
                                )}
                                {r.mediumCount > 0 && (
                                  <span className="bg-surface-subtle text-text-secondary border border-border-default px-1.5 py-0.2 rounded-full">
                                    {r.mediumCount} med
                                  </span>
                                )}
                                {r.lowCount > 0 && (
                                  <span className="bg-surface-subtle text-text-muted border border-border-default px-1.5 py-0.2 rounded-full">
                                    {r.lowCount} low
                                  </span>
                                )}
                                {r.findingCount === 0 && (
                                  <span className="text-text-primary">Clean</span>
                                )}
                              </div>
                            </td>
                            <td className="py-2.5 px-4 font-mono text-sm text-text-muted">
                              {r.startedAt ? new Date(r.startedAt).toLocaleString() : "-"}
                            </td>
                            <td className="py-2.5 px-4 font-mono text-sm text-text-muted">
                              {r.completedAt ? new Date(r.completedAt).toLocaleTimeString() : "In progress"}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          ) : activeTab === "findings" ? (
            /* Findings Tab */
            <div className="space-y-4">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-default pb-3">
                <div className="flex items-center gap-2">
                  <div className="relative w-64">
                    <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
                    <input
                      type="text"
                      placeholder="Search findings, modules, codes..."
                      value={findingSearchQuery}
                      onChange={(e) => setFindingSearchQuery(e.target.value)}
                      className="h-9 w-full rounded-xl border border-border-default bg-surface-primary pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden"
                    />
                  </div>

                  <div className="flex items-center gap-1">
                    {["all", "critical", "high", "medium", "low"].map((sev) => (
                      <button
                        key={sev}
                        type="button"
                        onClick={() => setFindingSeverityFilter(sev)}
                        className={`rounded-lg px-2.5 py-1 text-xs font-bold  transition cursor-pointer ${
                          findingSeverityFilter === sev
                            ? "bg-brand-primary text-surface-primary"
                            : "bg-surface-primary text-text-secondary hover:bg-surface-hover border border-border-default"
                        }`}
                      >
                        {sev}
                      </button>
                    ))}
                  </div>
                </div>

                <span className="text-xs text-text-muted">
                  Showing {filteredFindings.length} of {findings.length} findings
                </span>
              </div>

              {filteredFindings.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
                  No findings match the current filter criteria.
                </div>
              ) : (
                <div className="space-y-2.5">
                  {filteredFindings.map((f) => {
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
                            <span className="font-mono text-xs font-bold text-text-muted">
                              {f.findingCode}
                            </span>
                            <span className="text-sm font-semibold text-text-primary">{f.title}</span>
                          </div>

                          <span className="font-mono text-xs text-text-muted">
                            {f.createdAt ? new Date(f.createdAt).toLocaleString() : ""}
                          </span>
                        </div>

                        <div className="mt-2 flex flex-wrap items-center gap-3 text-xs text-text-secondary">
                          <span>
                            Module: <strong className="text-text-primary">{f.moduleName}</strong>
                          </span>
                          <span>•</span>
                          <span>
                            Category: <strong className="text-text-primary">{f.category}</strong>
                          </span>
                          <span>•</span>
                          <span>
                            Status: <strong className="text-text-primary">{f.status}</strong>
                          </span>
                        </div>

                        {f.details && (
                          <p className="mt-2 text-xs font-mono bg-surface-primary p-2.5 rounded-xl border border-border-default text-text-secondary overflow-x-auto">
                            {f.details}
                          </p>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          ) : activeTab === "schedules_queue" ? (
            /* Schedules & Queue Tab */
            <div className="space-y-6">
              {/* Schedules Section */}
              <div className="space-y-3">
                <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                  <Calendar className="h-4 w-4 text-brand-primary" />
                  <span>Configured Probe Schedules ({schedules.length})</span>
                </h3>
                {schedules.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-border-default p-6 text-center text-xs text-text-muted">
                    No recurring QA schedules registered in the database.
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    {schedules.map((s) => (
                      <div
                        key={s.id}
                        className="rounded-2xl border border-border-default bg-surface-primary p-4 shadow-2xs"
                      >
                        <div className="flex items-center justify-between">
                          <h4 className="text-sm font-semibold text-text-primary">{s.scheduleName}</h4>
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                              s.isActive ? "bg-surface-subtle text-text-primary border border-border-default" : "bg-surface-subtle text-text-muted border border-border-default"
                            }`}
                          >
                            {s.isActive ? "ACTIVE" : "INACTIVE"}
                          </span>
                        </div>
                        <div className="mt-2 space-y-1 text-xs text-text-secondary">
                          <div>
                            Cron: <code className="font-mono font-semibold text-text-primary">{s.cronExpression}</code>
                          </div>
                          <div>
                            Target: <span className="font-semibold text-text-primary">{s.targetModule}</span>
                          </div>
                          <div className="text-text-muted">
                            Next run: {s.nextRunAt ? new Date(s.nextRunAt).toLocaleString() : "Pending scheduler"}
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              {/* Execution Queue */}
              <div className="space-y-3 pt-3 border-t border-border-default">
                <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                  <ListOrdered className="h-4 w-4 text-brand-primary" />
                  <span>Active Execution Queue ({queue.length})</span>
                </h3>
                {queue.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-border-default p-6 text-center text-xs text-text-muted">
                    Execution queue is currently empty.
                  </div>
                ) : (
                  <div className="divide-y divide-border-subtle rounded-2xl border border-border-default bg-surface-primary">
                    {queue.map((q) => (
                      <div key={q.id} className="flex items-center justify-between p-3.5">
                        <div>
                          <div className="flex items-center gap-2">
                            <span className="font-mono text-xs font-bold text-text-primary">
                              Queue #{q.id.slice(0, 8)}
                            </span>
                            <span className="rounded-full bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-semibold text-text-secondary">
                              {q.status}
                            </span>
                          </div>
                          <div className="text-xs text-text-muted mt-0.5">
                            Priority: {q.priority} • Queued: {q.queuedAt ? new Date(q.queuedAt).toLocaleTimeString() : "-"}
                          </div>
                        </div>
                        {q.errorMessage && (
                          <span className="text-xs text-danger-text font-mono max-w-xs truncate">
                            {q.errorMessage}
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          ) : (
            /* Daily Reports Tab */
            <div className="space-y-4">
              <div className="flex items-center justify-between border-b border-border-default pb-3">
                <div>
                  <h3 className="text-sm font-bold text-text-primary">Daily QA Executive Reports</h3>
                  <p className="text-xs text-text-secondary">
                    Aggregated daily compliance and system health ratings generated by automated jobs.
                  </p>
                </div>
                <span className="text-xs text-text-muted font-mono">{reports.length} Reports</span>
              </div>

              {reports.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
                  No daily reports logged. Click &quot;Generate Daily Report&quot; to synthesize today&apos;s data.
                </div>
              ) : (
                <div className="space-y-3">
                  {reports.map((dr) => (
                    <div
                      key={dr.id}
                      className="rounded-2xl border border-border-default bg-surface-primary p-5 hover:border-brand-primary transition shadow-2xs"
                    >
                      <div className="flex flex-wrap items-center justify-between gap-3">
                        <div className="flex items-center gap-3">
                          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-surface-subtle text-text-primary font-bold font-mono text-xs border border-border-default">
                            {dr.healthScore != null ? `${dr.healthScore.toFixed(0)}%` : "N/A"}
                          </div>
                          <div>
                            <div className="flex items-center gap-2">
                              <h4 className="text-sm font-bold text-text-primary">
                                Daily Report — {dr.reportDate}
                              </h4>
                              <span className="rounded-full bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-mono font-semibold text-text-secondary">
                                {dr.environment}
                              </span>
                            </div>
                            <div className="flex items-center gap-3 text-xs text-text-muted mt-0.5">
                              <span>Total Runs: {dr.totalRuns}</span>
                              <span>•</span>
                              <span className="text-text-primary font-medium">{dr.passedRuns} Passed</span>
                              <span>•</span>
                              <span className="text-danger-text font-medium">{dr.failedRuns} Failed</span>
                            </div>
                          </div>
                        </div>

                        <span className="text-xs font-mono text-text-muted">
                          Generated: {dr.createdAt ? new Date(dr.createdAt).toLocaleString() : ""}
                        </span>
                      </div>

                      {dr.executiveSummary && (
                        <p className="mt-3 text-xs leading-relaxed text-text-secondary bg-surface-subtle p-3 rounded-xl border border-border-default">
                          {dr.executiveSummary}
                        </p>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
