"use client";

import { useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  Clock,
  Download,
  FileSpreadsheet,
  GitFork,
  Ghost,
  Loader2,
  RefreshCw,
  ShieldAlert,
  ShieldCheck,
  Store,
} from "lucide-react";
import {
  useDataIntegritySummary,
  useReportFilterOptions,
} from "@/lib/queries/reports";
import { exportToCsv, exportToXlsx } from "@/lib/utils/reports_export";
import { DataIntegrityDetailModal } from "./DataIntegrityDetailModal";

type SectionType = "late_hr" | "vacancy_delay" | "ghost_occupancy" | "pipeline_no_vacancy";

export function DataIntegrityTab() {
  const [selectedGroupId, setSelectedGroupId] = useState<string>("");
  const [selectedAccountId, setSelectedAccountId] = useState<string>("");
  const [activeSection, setActiveSection] = useState<{
    key: SectionType;
    title: string;
  } | null>(null);

  const { data: filterOpts } = useReportFilterOptions();
  const groups = filterOpts?.groups ?? [];
  const accounts = filterOpts?.accounts ?? [];

  const filteredAccounts = selectedGroupId
    ? accounts.filter((a) => a.groupId === selectedGroupId)
    : accounts;

  const {
    data: summary,
    isLoading,
    isRefetching,
    error,
    refetch,
  } = useDataIntegritySummary(selectedGroupId || null, selectedAccountId || null);

  const criticalIssues = summary?.criticalIssues ?? 0;
  const highRiskIssues = summary?.highRiskIssues ?? 0;
  const totalFindings = summary?.totalFindings ?? 0;
  const affectedStores = summary?.affectedStores ?? 0;

  const lateHr = summary?.lateHrUpdates ?? { totalFindings: 0, affectedStores: 0 };
  const vacDelay = summary?.vacancyCreationDelay ?? { totalFindings: 0, affectedStores: 0 };
  const ghost = summary?.ghostOccupancy ?? { totalFindings: 0, affectedStores: 0 };
  const pipe = summary?.pipelineNoVacancy ?? { totalFindings: 0, affectedStores: 0 };

  const handleExportSummaryXlsx = () => {
    if (!summary) return;
    exportToXlsx(
      [
        {
          Section: "Late HR Updates",
          "Total Findings": lateHr.totalFindings,
          "Affected Stores": lateHr.affectedStores,
          "Worst Delay (Days)": lateHr.worstDelay ?? "—",
        },
        {
          Section: "Vacancy Creation Delay",
          "Total Findings": vacDelay.totalFindings,
          "Affected Stores": vacDelay.affectedStores,
          "Worst Delay (Days)": vacDelay.worstDelay ?? "—",
        },
        {
          Section: "Ghost Occupancy",
          "Total Findings": ghost.totalFindings,
          "Affected Stores": ghost.affectedStores,
          "Active Findings": ghost.activeFindings ?? "—",
        },
        {
          Section: "Pipeline Without Vacancy",
          "Total Findings": pipe.totalFindings,
          "Affected Stores": pipe.affectedStores,
          "Critical Findings": pipe.criticalFindings ?? "—",
        },
      ],
      `Data_Integrity_Audit_Summary_${new Date().toISOString().split("T")[0]}`
    );
  };

  const handleExportSummaryCsv = () => {
    if (!summary) return;
    exportToCsv(
      [
        {
          Section: "Late HR Updates",
          "Total Findings": lateHr.totalFindings,
          "Affected Stores": lateHr.affectedStores,
          "Worst Delay (Days)": lateHr.worstDelay ?? "—",
        },
        {
          Section: "Vacancy Creation Delay",
          "Total Findings": vacDelay.totalFindings,
          "Affected Stores": vacDelay.affectedStores,
          "Worst Delay (Days)": vacDelay.worstDelay ?? "—",
        },
        {
          Section: "Ghost Occupancy",
          "Total Findings": ghost.totalFindings,
          "Affected Stores": ghost.affectedStores,
          "Active Findings": ghost.activeFindings ?? "—",
        },
        {
          Section: "Pipeline Without Vacancy",
          "Total Findings": pipe.totalFindings,
          "Affected Stores": pipe.affectedStores,
          "Critical Findings": pipe.criticalFindings ?? "—",
        },
      ],
      `Data_Integrity_Audit_Summary_${new Date().toISOString().split("T")[0]}`
    );
  };

  return (
    <div className="space-y-6 animate-in fade-in duration-150">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-border-subtle">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-[10px] font-bold text-danger bg-danger-subtle px-2 py-0.5 rounded border border-danger-border">
              Data Audit & Compliance
            </span>
            <span className="text-xs text-text-muted">Port of DataIntegrityReportScreen</span>
          </div>
          <h2 className="text-xl font-bold text-text-primary mt-0.5 tracking-tight">
            Workforce Data Integrity & Delay Audit
          </h2>
          <p className="text-xs text-text-secondary mt-0.5">
            Identify delayed status updates, stale ghost occupancies, unlinked applicants, and workforce data drift across accounts.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => refetch()}
            disabled={isLoading || isRefetching}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isRefetching ? "animate-spin text-brand-primary" : ""}`} />
            Refresh
          </button>
          <button
            onClick={handleExportSummaryXlsx}
            disabled={isLoading || !summary}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
          >
            <FileSpreadsheet className="w-3.5 h-3.5" />
            Export XLSX
          </button>
          <button
            onClick={handleExportSummaryCsv}
            disabled={isLoading || !summary}
            className="flex items-center gap-1.5 h-8 px-3 text-xs font-semibold text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-lg transition cursor-pointer disabled:opacity-50"
          >
            <Download className="w-3.5 h-3.5" />
            CSV
          </button>
        </div>
      </div>

      {/* KPI Cards Strip */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
          <div className="text-[11px] font-semibold text-danger flex items-center justify-between">
            <span>Critical Issues</span>
            <ShieldAlert className="w-4 h-4 text-danger" />
          </div>
          <div className="text-2xl font-bold text-danger mt-1">
            {criticalIssues}
          </div>
          <div className="text-[11px] text-danger/80 mt-0.5">Requires immediate remediation</div>
        </div>

        <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
          <div className="text-[11px] font-semibold text-text-secondary flex items-center justify-between">
            <span>High Risk Issues</span>
            <AlertTriangle className="w-4 h-4 text-text-secondary" />
          </div>
          <div className="text-2xl font-bold text-text-primary mt-1">
            {highRiskIssues}
          </div>
          <div className="text-[11px] text-text-muted mt-0.5">SLA delayed submissions</div>
        </div>

        <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
          <div className="text-[11px] font-semibold text-text-muted flex items-center justify-between">
            <span>Total Findings</span>
            <ShieldCheck className="w-4 h-4 text-brand-primary" />
          </div>
          <div className="text-2xl font-bold text-text-primary mt-1">
            {totalFindings}
          </div>
          <div className="text-[11px] text-text-muted mt-0.5">Cumulative anomalies flagged</div>
        </div>

        <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs">
          <div className="text-[11px] font-semibold text-text-muted flex items-center justify-between">
            <span>Affected Stores</span>
            <Store className="w-4 h-4 text-brand-primary" />
          </div>
          <div className="text-2xl font-bold text-text-primary mt-1">
            {affectedStores}
          </div>
          <div className="text-[11px] text-text-muted mt-0.5">Branches with open anomalies</div>
        </div>
      </div>

      {/* Scope Filter Strip */}
      <div className="p-4 rounded-xl border border-border-default bg-surface-base shadow-2xs grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div>
          <select
            value={selectedGroupId}
            onChange={(e) => {
              setSelectedGroupId(e.target.value);
              setSelectedAccountId("");
            }}
            className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default cursor-pointer text-text-primary"
          >
            <option value="">All Groups (Entire Organization)</option>
            {groups.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <select
            value={selectedAccountId}
            onChange={(e) => setSelectedAccountId(e.target.value)}
            className="w-full h-8 px-2.5 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default cursor-pointer text-text-primary"
          >
            <option value="">All Accounts</option>
            {filteredAccounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* 4 Section Cards Grid */}
      {isLoading ? (
        <div className="flex flex-col items-center justify-center py-24 text-text-muted">
          <Loader2 className="w-8 h-8 animate-spin text-brand-primary mb-2" />
          <p className="text-xs font-medium">Scanning workforce database for integrity anomalies...</p>
        </div>
      ) : error ? (
        <div className="p-8 text-center rounded-xl border border-danger-border bg-danger-subtle">
          <p className="text-sm font-semibold text-danger">Failed to load data integrity report</p>
          <p className="text-xs text-text-muted mt-1">{String(error)}</p>
          <button
            onClick={() => refetch()}
            className="mt-4 px-4 py-1.5 text-xs font-semibold text-danger bg-surface-base border border-danger-border rounded-lg hover:bg-danger-subtle transition cursor-pointer"
          >
            Retry Scan
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
          {/* Section 1: Late HR Updates */}
          <div className="p-6 rounded-xl border border-border-default bg-surface-base shadow-2xs hover:border-border-strong hover:shadow-md transition flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Clock className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  SLA Compliance
                </span>
              </div>
              <h3 className="text-base font-bold text-text-primary mt-3">
                Late HR Emploc Updates
              </h3>
              <p className="text-xs text-text-secondary mt-1">
                Employee location requests submitted or processed beyond the allowable SLA threshold.
              </p>

              <div className="grid grid-cols-3 gap-2 mt-4 p-3 rounded-lg bg-surface-muted/60 border border-border-subtle">
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Findings</div>
                  <div className="text-base font-bold text-text-primary mt-0.5">{lateHr.totalFindings}</div>
                </div>
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Stores</div>
                  <div className="text-base font-bold text-text-primary mt-0.5">{lateHr.affectedStores}</div>
                </div>
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Worst Delay</div>
                  <div className="text-base font-bold text-danger mt-0.5">
                    {lateHr.worstDelay ? `${lateHr.worstDelay}d` : "—"}
                  </div>
                </div>
              </div>
            </div>

            <button
              onClick={() =>
                setActiveSection({ key: "late_hr", title: "Late HR Updates" })
              }
              className="mt-5 w-full flex items-center justify-between px-3 py-2 text-xs font-semibold text-brand-primary bg-brand-subtle hover:bg-brand-subtle/80 border border-brand-border rounded-lg transition cursor-pointer"
            >
              <span>Audit Late HR Finding Rows</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </button>
          </div>

          {/* Section 2: Vacancy Creation Delay */}
          <div className="p-6 rounded-xl border border-border-default bg-surface-base shadow-2xs hover:border-border-strong hover:shadow-md transition flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <AlertTriangle className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Requisition Delay
                </span>
              </div>
              <h3 className="text-base font-bold text-text-primary mt-3">
                Vacancy Creation Delay
              </h3>
              <p className="text-xs text-text-secondary mt-1">
                Vacancies initiated late following official employee separation or departure dates.
              </p>

              <div className="grid grid-cols-3 gap-2 mt-4 p-3 rounded-lg bg-surface-muted/60 border border-border-subtle">
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Findings</div>
                  <div className="text-base font-bold text-text-primary mt-0.5">{vacDelay.totalFindings}</div>
                </div>
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Stores</div>
                  <div className="text-base font-bold text-text-primary mt-0.5">{vacDelay.affectedStores}</div>
                </div>
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Worst Delay</div>
                  <div className="text-base font-bold text-danger mt-0.5">
                    {vacDelay.worstDelay ? `${vacDelay.worstDelay}d` : "—"}
                  </div>
                </div>
              </div>
            </div>

            <button
              onClick={() =>
                setActiveSection({
                  key: "vacancy_delay",
                  title: "Vacancy Creation Delay",
                })
              }
              className="mt-5 w-full flex items-center justify-between px-3 py-2 text-xs font-semibold text-brand-primary bg-brand-subtle hover:bg-brand-subtle/80 border border-brand-border rounded-lg transition cursor-pointer"
            >
              <span>Audit Vacancy Delay Rows</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </button>
          </div>

          {/* Section 3: Ghost Occupancy */}
          <div className="p-6 rounded-xl border border-border-default bg-surface-base shadow-2xs hover:border-border-strong hover:shadow-md transition flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <Ghost className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-danger-subtle text-danger border border-danger-border">
                  Plantilla Ghost
                </span>
              </div>
              <h3 className="text-base font-bold text-text-primary mt-3">
                Ghost Occupancy Anomaly
              </h3>
              <p className="text-xs text-text-secondary mt-1">
                Slots occupied by separated personnel or records lacking authentic payroll activity.
              </p>

              <div className="grid grid-cols-2 gap-2 mt-4 p-3 rounded-lg bg-surface-muted/60 border border-border-subtle">
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Ghost Findings</div>
                  <div className="text-base font-bold text-danger mt-0.5">{ghost.totalFindings}</div>
                </div>
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Affected Stores</div>
                  <div className="text-base font-bold text-text-primary mt-0.5">{ghost.affectedStores}</div>
                </div>
              </div>
            </div>

            <button
              onClick={() =>
                setActiveSection({
                  key: "ghost_occupancy",
                  title: "Ghost Occupancy",
                })
              }
              className="mt-5 w-full flex items-center justify-between px-3 py-2 text-xs font-semibold text-brand-primary bg-brand-subtle hover:bg-brand-subtle/80 border border-brand-border rounded-lg transition cursor-pointer"
            >
              <span>Audit Ghost Occupancy Rows</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </button>
          </div>

          {/* Section 4: Pipeline Without Vacancy */}
          <div className="p-6 rounded-xl border border-border-default bg-surface-base shadow-2xs hover:border-border-strong hover:shadow-md transition flex flex-col justify-between">
            <div>
              <div className="flex items-center justify-between">
                <div className="p-2.5 rounded-lg bg-surface-subtle text-text-secondary border border-border-default">
                  <GitFork className="w-5 h-5" />
                </div>
                <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-surface-subtle text-text-secondary border border-border-default">
                  Unlinked Pipeline
                </span>
              </div>
              <h3 className="text-base font-bold text-text-primary mt-3">
                Pipeline Without Vacancy
              </h3>
              <p className="text-xs text-text-secondary mt-1">
                Applicants progressing in recruitment pipeline without a valid authorized VCode slot.
              </p>

              <div className="grid grid-cols-2 gap-2 mt-4 p-3 rounded-lg bg-surface-muted/60 border border-border-subtle">
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Unlinked Records</div>
                  <div className="text-base font-bold text-text-primary mt-0.5">{pipe.totalFindings}</div>
                </div>
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">Affected Stores</div>
                  <div className="text-base font-bold text-text-primary mt-0.5">{pipe.affectedStores}</div>
                </div>
              </div>
            </div>

            <button
              onClick={() =>
                setActiveSection({
                  key: "pipeline_no_vacancy",
                  title: "Pipeline Without Vacancy",
                })
              }
              className="mt-5 w-full flex items-center justify-between px-3 py-2 text-xs font-semibold text-brand-primary bg-brand-subtle hover:bg-brand-subtle/80 border border-brand-border rounded-lg transition cursor-pointer"
            >
              <span>Audit Unlinked Pipeline Rows</span>
              <ArrowRight className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      )}

      {/* Detail Modal */}
      {activeSection && (
        <DataIntegrityDetailModal
          sectionKey={activeSection.key}
          sectionTitle={activeSection.title}
          groupId={selectedGroupId || null}
          accountId={selectedAccountId || null}
          onClose={() => setActiveSection(null)}
        />
      )}
    </div>
  );
}
