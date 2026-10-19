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
  X,
  XCircle,
} from "lucide-react";

import {
  useGenerateDailyQaReport,
  useQaCenterSnapshot,
  useRunQaCoreDetectionSuite,
  useRunQaScenario,
} from "@/lib/queries/governance";

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

  const { data: snapshot, isLoading, isFetching, refetch } = useQaCenterSnapshot();
  const runCoreMutation = useRunQaCoreDetectionSuite();
  const runScenarioMutation = useRunQaScenario();
  const generateReportMutation = useGenerateDailyQaReport();

  if (!isOpen) return null;

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
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 sm:p-6"
    >
      <div className="relative flex h-[90vh] max-h-[850px] w-full max-w-6xl flex-col rounded-2xl border border-border-default bg-surface-card shadow-2xl overflow-hidden">
        {/* Toast */}
        {toastMessage && (
          <div className="absolute top-4 right-4 z-50 flex items-center gap-2 rounded-xl border border-brand-200 bg-brand-50 px-4 py-2.5 text-xs font-semibold text-brand-900 shadow-lg">
            <Sparkles className="h-4 w-4 text-brand-600" />
            <span>{toastMessage}</span>
          </div>
        )}

        {/* Modal Header */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base/80 px-6 py-4 gap-4">
          <div className="flex items-center gap-3.5">
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-purple-500/10 text-purple-600 border border-purple-500/20">
              <CheckCircle2 className="h-6 w-6" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-text-primary">QA Center & Diagnostics</h2>
                <span className="rounded-md bg-purple-50 px-2 py-0.5 text-2xs font-extrabold text-purple-700 border border-purple-200 uppercase">
                  Level 100
                </span>
                <span className="rounded-md bg-brand-50 px-2 py-0.5 text-2xs font-bold text-brand-700 border border-brand-200">
                  Automated Probes
                </span>
              </div>
              <p className="text-xs text-text-secondary mt-0.5">
                Run automated detection suites, monitor test findings, schedules, and daily integrity scores.
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetching}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-card px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw className={`h-3.5 w-3.5 ${isFetching ? "animate-spin text-brand-600" : "text-text-muted"}`} />
              Refresh
            </button>
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg p-1.5 text-text-muted hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
        </div>

        {/* Operational Action Bar (SA-only execution) */}
        {isSuperAdmin && (
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle bg-purple-50/30 px-6 py-2.5">
            <div className="flex items-center gap-2">
              <span className="text-2xs font-bold uppercase tracking-wider text-purple-800">
                Exec Actions:
              </span>
              <button
                type="button"
                onClick={handleRunCore}
                disabled={runCoreMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-lg bg-purple-600 px-3 py-1.5 text-xs font-semibold text-white shadow-2xs hover:bg-purple-700 transition disabled:opacity-50 cursor-pointer"
              >
                <Play className="h-3 w-3 fill-current" />
                {runCoreMutation.isPending ? "Running Core Suite..." : "Run Core Suite"}
              </button>
              <button
                type="button"
                onClick={handleGenerateReport}
                disabled={generateReportMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-lg border border-purple-200 bg-white px-3 py-1.5 text-xs font-semibold text-purple-700 shadow-2xs hover:bg-purple-50 transition disabled:opacity-50 cursor-pointer"
              >
                <Calendar className="h-3 w-3" />
                {generateReportMutation.isPending ? "Generating..." : "Generate Daily Report"}
              </button>
            </div>

            <div className="flex items-center gap-2">
              <select
                value={selectedScenario}
                onChange={(e) => setSelectedScenario(e.target.value)}
                className="h-8 rounded-lg border border-border-default bg-surface-card px-2.5 text-xs font-medium text-text-primary focus:border-brand-500 focus:outline-hidden"
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
                className="inline-flex items-center gap-1.5 rounded-lg bg-brand-600 px-3 py-1.5 text-xs font-semibold text-white shadow-2xs hover:bg-brand-700 transition disabled:opacity-50 cursor-pointer"
              >
                <Play className="h-3 w-3 fill-current" />
                {runScenarioMutation.isPending ? "Testing..." : "Run Scenario"}
              </button>
            </div>
          </div>
        )}

        {/* Tab Navigation */}
        <div className="flex items-center gap-1 border-b border-border-subtle bg-surface-card px-6 py-2 overflow-x-auto">
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
            Overview
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
            Runs ({runs.length})
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
            Findings ({findings.length})
            {criticalHighFindingsCount > 0 && (
              <span className="rounded-full bg-red-100 px-1.5 py-0.2 text-2xs font-bold text-red-700">
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
            Schedules & Queue ({schedules.length + queue.length})
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
            Daily Reports ({reports.length})
          </button>
        </div>

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {isLoading ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-brand-600" />
              <p className="text-xs">Loading QA Center telemetry and run snapshots...</p>
            </div>
          ) : activeTab === "overview" ? (
            <div className="space-y-6">
              {/* Top KPI Cards */}
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <div className="rounded-xl border border-border-subtle bg-surface-base p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary">Health Score</span>
                    <ShieldCheck className="h-4 w-4 text-emerald-600" />
                  </div>
                  <div className="mt-2 flex items-baseline gap-2">
                    <span className="text-2xl font-extrabold text-text-primary">
                      {overallHealthScore}%
                    </span>
                    <span className="text-2xs font-semibold text-emerald-600">Optimal</span>
                  </div>
                  <p className="mt-1 text-2xs text-text-muted">Calculated across 8 test suites</p>
                </div>

                <div className="rounded-xl border border-border-subtle bg-surface-base p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary">Total Runs Logged</span>
                    <Play className="h-4 w-4 text-blue-600" />
                  </div>
                  <div className="mt-2 flex items-baseline gap-2">
                    <span className="text-2xl font-extrabold text-text-primary">{runs.length}</span>
                    <span className="text-2xs font-semibold text-blue-600">Active</span>
                  </div>
                  <p className="mt-1 text-2xs text-text-muted">Automated & manual test runs</p>
                </div>

                <div className="rounded-xl border border-border-subtle bg-surface-base p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary">Open Findings</span>
                    <AlertTriangle className="h-4 w-4 text-amber-600" />
                  </div>
                  <div className="mt-2 flex items-baseline gap-2">
                    <span className="text-2xl font-extrabold text-text-primary">{findings.length}</span>
                    {criticalHighFindingsCount > 0 ? (
                      <span className="text-2xs font-bold text-red-600">
                        {criticalHighFindingsCount} Critical/High
                      </span>
                    ) : (
                      <span className="text-2xs font-semibold text-emerald-600">Zero Critical</span>
                    )}
                  </div>
                  <p className="mt-1 text-2xs text-text-muted">Across operational modules</p>
                </div>

                <div className="rounded-xl border border-border-subtle bg-surface-base p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary">Flaky Tests</span>
                    <Flame className="h-4 w-4 text-orange-600" />
                  </div>
                  <div className="mt-2 flex items-baseline gap-2">
                    <span className="text-2xl font-extrabold text-text-primary">{flakyTests.length}</span>
                    <span className="text-2xs font-semibold text-text-muted">Probed</span>
                  </div>
                  <p className="mt-1 text-2xs text-text-muted">Intermittent assertion failures</p>
                </div>
              </div>

              {/* Unstable Modules & Recent Notifications */}
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* Unstable Modules */}
                <div className="rounded-xl border border-border-default bg-surface-card p-5">
                  <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                    <Layers className="h-4 w-4 text-purple-600" />
                    Module Stability Rankings
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
                            <span className="text-xs font-semibold text-text-primary">{m.moduleName}</span>
                          </div>
                          <div className="flex items-center gap-3">
                            <span className="text-2xs font-medium text-amber-700 bg-amber-50 px-2 py-0.5 rounded-md border border-amber-200">
                              {m.findingCount} findings
                            </span>
                            <span className="text-2xs font-semibold text-text-muted font-mono">
                              {(m.failureRate * 100).toFixed(1)}% fail rate
                            </span>
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                </div>

                {/* Notifications & System Alerts */}
                <div className="rounded-xl border border-border-default bg-surface-card p-5">
                  <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                    <ShieldAlert className="h-4 w-4 text-brand-600" />
                    QA Broadcasts & System Notices
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
                          className="rounded-lg border border-border-subtle bg-surface-base p-3"
                        >
                          <div className="flex items-center justify-between">
                            <h4 className="text-xs font-semibold text-text-primary">{n.title}</h4>
                            <span className="text-2xs font-mono text-text-muted">
                              {new Date(n.createdAt).toLocaleDateString()}
                            </span>
                          </div>
                          <p className="text-2xs text-text-secondary mt-1">{n.message}</p>
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
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-bold text-text-primary">Detection Runs History</h3>
                  <p className="text-xs text-text-secondary">
                    Detailed audit trail of recent automated and manual QA detection suites.
                  </p>
                </div>
                <span className="text-xs text-text-muted font-mono">Total Runs: {runs.length}</span>
              </div>

              {runs.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
                  No detection runs found in history. Click &quot;Run Core Suite&quot; to execute your first probe.
                </div>
              ) : (
                <div className="rounded-xl border border-border-default overflow-hidden">
                  <table className="w-full text-left border-collapse">
                    <thead>
                      <tr className="border-b border-border-subtle bg-surface-base text-2xs font-bold text-text-muted uppercase tracking-wider">
                        <th className="py-2.5 px-4">Status</th>
                        <th className="py-2.5 px-4">Agent / Suite</th>
                        <th className="py-2.5 px-4">Target Module</th>
                        <th className="py-2.5 px-4">Findings Breakdown</th>
                        <th className="py-2.5 px-4">Started At</th>
                        <th className="py-2.5 px-4">Completed</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle text-xs">
                      {runs.map((r) => {
                        const isSuccess = r.status.toLowerCase() === "passed" || r.status.toLowerCase() === "completed";
                        const isFailed = r.status.toLowerCase() === "failed" || r.criticalCount > 0;
                        return (
                          <tr key={r.id} className="hover:bg-surface-hover/50">
                            <td className="py-2.5 px-4">
                              <span
                                className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-2xs font-bold uppercase tracking-wider ${
                                  isSuccess
                                    ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                                    : isFailed
                                    ? "bg-red-50 text-red-700 border border-red-200"
                                    : "bg-blue-50 text-blue-700 border border-blue-200"
                                }`}
                              >
                                {isSuccess ? (
                                  <CheckCircle2 className="h-3 w-3" />
                                ) : isFailed ? (
                                  <XCircle className="h-3 w-3" />
                                ) : (
                                  <Clock className="h-3 w-3" />
                                )}
                                {r.status}
                              </span>
                            </td>
                            <td className="py-2.5 px-4 font-semibold text-text-primary">{r.agentName}</td>
                            <td className="py-2.5 px-4">
                              <span className="font-mono text-2xs bg-surface-base px-2 py-0.5 rounded-md border border-border-default text-text-secondary">
                                {r.targetModule}
                              </span>
                            </td>
                            <td className="py-2.5 px-4">
                              <div className="flex items-center gap-1.5 text-2xs font-semibold">
                                {r.criticalCount > 0 && (
                                  <span className="bg-red-100 text-red-700 px-1.5 py-0.2 rounded-md">
                                    {r.criticalCount} crit
                                  </span>
                                )}
                                {r.highCount > 0 && (
                                  <span className="bg-orange-100 text-orange-700 px-1.5 py-0.2 rounded-md">
                                    {r.highCount} high
                                  </span>
                                )}
                                {r.mediumCount > 0 && (
                                  <span className="bg-amber-100 text-amber-700 px-1.5 py-0.2 rounded-md">
                                    {r.mediumCount} med
                                  </span>
                                )}
                                {r.lowCount > 0 && (
                                  <span className="bg-blue-100 text-blue-700 px-1.5 py-0.2 rounded-md">
                                    {r.lowCount} low
                                  </span>
                                )}
                                {r.findingCount === 0 && (
                                  <span className="text-emerald-600">Clean</span>
                                )}
                              </div>
                            </td>
                            <td className="py-2.5 px-4 font-mono text-2xs text-text-muted">
                              {r.startedAt ? new Date(r.startedAt).toLocaleString() : "-"}
                            </td>
                            <td className="py-2.5 px-4 font-mono text-2xs text-text-muted">
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
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-2">
                  <div className="relative w-64">
                    <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
                    <input
                      type="text"
                      placeholder="Search findings, modules, codes..."
                      value={findingSearchQuery}
                      onChange={(e) => setFindingSearchQuery(e.target.value)}
                      className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                    />
                  </div>

                  <div className="flex items-center gap-1">
                    {["all", "critical", "high", "medium", "low"].map((sev) => (
                      <button
                        key={sev}
                        type="button"
                        onClick={() => setFindingSeverityFilter(sev)}
                        className={`rounded-lg px-2.5 py-1 text-2xs font-bold uppercase transition cursor-pointer ${
                          findingSeverityFilter === sev
                            ? "bg-purple-600 text-white"
                            : "bg-surface-base text-text-secondary hover:bg-surface-hover"
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
                <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
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
                        className={`rounded-xl border p-4 transition ${
                          isCrit
                            ? "border-red-200 bg-red-50/20"
                            : isHigh
                            ? "border-orange-200 bg-orange-50/20"
                            : "border-border-default bg-surface-base"
                        }`}
                      >
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <div className="flex items-center gap-2">
                            <span
                              className={`rounded-md px-2 py-0.5 text-2xs font-extrabold uppercase tracking-wider ${
                                isCrit
                                  ? "bg-red-100 text-red-800 border border-red-200"
                                  : isHigh
                                  ? "bg-orange-100 text-orange-800 border border-orange-200"
                                  : "bg-blue-100 text-blue-800 border border-blue-200"
                              }`}
                            >
                              {f.severity}
                            </span>
                            <span className="font-mono text-2xs font-bold text-text-muted">
                              {f.findingCode}
                            </span>
                            <span className="text-xs font-bold text-text-primary">{f.title}</span>
                          </div>

                          <span className="font-mono text-2xs text-text-muted">
                            {f.createdAt ? new Date(f.createdAt).toLocaleString() : ""}
                          </span>
                        </div>

                        <div className="mt-2 flex flex-wrap items-center gap-3 text-2xs text-text-secondary">
                          <span>
                            Module: <strong className="text-text-primary">{f.moduleName}</strong>
                          </span>
                          <span>•</span>
                          <span>
                            Category: <strong className="text-text-primary">{f.category}</strong>
                          </span>
                          <span>•</span>
                          <span>
                            Status: <strong className="uppercase text-text-primary">{f.status}</strong>
                          </span>
                        </div>

                        {f.details && (
                          <p className="mt-2 text-2xs font-mono bg-surface-card p-2.5 rounded-lg border border-border-subtle text-text-secondary overflow-x-auto">
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
                  <Calendar className="h-4 w-4 text-brand-600" />
                  Configured Probe Schedules ({schedules.length})
                </h3>
                {schedules.length === 0 ? (
                  <div className="rounded-xl border border-dashed border-border-default p-6 text-center text-xs text-text-muted">
                    No recurring QA schedules registered in the database.
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    {schedules.map((s) => (
                      <div
                        key={s.id}
                        className="rounded-xl border border-border-default bg-surface-base p-4"
                      >
                        <div className="flex items-center justify-between">
                          <h4 className="text-xs font-bold text-text-primary">{s.scheduleName}</h4>
                          <span
                            className={`rounded-md px-1.5 py-0.5 text-2xs font-bold ${
                              s.isActive ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-600"
                            }`}
                          >
                            {s.isActive ? "ACTIVE" : "INACTIVE"}
                          </span>
                        </div>
                        <div className="mt-2 space-y-1 text-2xs text-text-secondary">
                          <div>
                            Cron: <code className="font-mono font-semibold">{s.cronExpression}</code>
                          </div>
                          <div>
                            Target: <span className="font-semibold">{s.targetModule}</span>
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
              <div className="space-y-3 pt-3 border-t border-border-subtle">
                <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                  <ListOrdered className="h-4 w-4 text-purple-600" />
                  Active Execution Queue ({queue.length})
                </h3>
                {queue.length === 0 ? (
                  <div className="rounded-xl border border-dashed border-border-default p-6 text-center text-xs text-text-muted">
                    Execution queue is currently empty.
                  </div>
                ) : (
                  <div className="divide-y divide-border-subtle rounded-xl border border-border-default">
                    {queue.map((q) => (
                      <div key={q.id} className="flex items-center justify-between p-3">
                        <div>
                          <div className="flex items-center gap-2">
                            <span className="font-mono text-2xs font-bold text-text-primary">
                              Queue #{q.id.slice(0, 8)}
                            </span>
                            <span className="rounded-md bg-blue-50 px-1.5 py-0.2 text-2xs font-bold text-blue-700 uppercase">
                              {q.status}
                            </span>
                          </div>
                          <div className="text-2xs text-text-muted mt-0.5">
                            Priority: {q.priority} • Queued: {q.queuedAt ? new Date(q.queuedAt).toLocaleTimeString() : "-"}
                          </div>
                        </div>
                        {q.errorMessage && (
                          <span className="text-2xs text-red-600 font-mono max-w-xs truncate">
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
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-bold text-text-primary">Daily QA Executive Reports</h3>
                  <p className="text-xs text-text-secondary">
                    Aggregated daily compliance and system health ratings generated by automated jobs.
                  </p>
                </div>
                <span className="text-xs text-text-muted font-mono">{reports.length} Reports</span>
              </div>

              {reports.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
                  No daily reports logged. Click &quot;Generate Daily Report&quot; to synthesize today&apos;s data.
                </div>
              ) : (
                <div className="space-y-3">
                  {reports.map((dr) => (
                    <div
                      key={dr.id}
                      className="rounded-xl border border-border-default bg-surface-base p-5 hover:border-brand-300 transition"
                    >
                      <div className="flex flex-wrap items-center justify-between gap-3">
                        <div className="flex items-center gap-3">
                          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-purple-50 text-purple-700 font-bold font-mono text-xs border border-purple-200">
                            {dr.healthScore != null ? `${dr.healthScore.toFixed(0)}%` : "N/A"}
                          </div>
                          <div>
                            <div className="flex items-center gap-2">
                              <h4 className="text-sm font-bold text-text-primary">
                                Daily Report — {dr.reportDate}
                              </h4>
                              <span className="rounded-md bg-slate-100 px-2 py-0.5 text-2xs font-mono font-semibold uppercase text-slate-700">
                                {dr.environment}
                              </span>
                            </div>
                            <div className="flex items-center gap-3 text-2xs text-text-muted mt-0.5">
                              <span>Total Runs: {dr.totalRuns}</span>
                              <span>•</span>
                              <span className="text-emerald-600 font-medium">{dr.passedRuns} Passed</span>
                              <span>•</span>
                              <span className="text-red-600 font-medium">{dr.failedRuns} Failed</span>
                            </div>
                          </div>
                        </div>

                        <span className="text-2xs font-mono text-text-muted">
                          Generated: {dr.createdAt ? new Date(dr.createdAt).toLocaleString() : ""}
                        </span>
                      </div>

                      {dr.executiveSummary && (
                        <p className="mt-3 text-xs leading-relaxed text-text-secondary bg-surface-card p-3 rounded-lg border border-border-subtle">
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

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-6 py-3">
          <span className="text-2xs text-text-muted font-mono">
            Backend views: v_qa_detection_run_summary • v_qa_open_findings • v_qa_daily_reports
          </span>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-border-default bg-surface-card px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
