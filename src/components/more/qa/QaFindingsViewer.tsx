"use client";

import React, { useState } from "react";
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  Database,
  Hash,
  Search,
  ShieldAlert,
  Wrench,
  X,
} from "lucide-react";
import type { QaFinding } from "@/lib/queries/governance";

export interface QaFindingsViewerProps {
  findings: QaFinding[];
  selectedRunId?: string | null;
  onClearRunFilter?: () => void;
  onSelectRun?: (runId: string) => void;
}

const SEVERITY_CONFIG: Record<string, { pill: string; card: string; icon: React.ComponentType<{ className?: string }> }> = {
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

export function QaFindingsViewer({
  findings,
  selectedRunId,
  onClearRunFilter,
  onSelectRun,
}: QaFindingsViewerProps) {
  const [severityFilter, setSeverityFilter] = useState<string>("all");
  const [searchQuery, setSearchQuery] = useState("");

  const filteredFindings = findings.filter((f) => {
    if (selectedRunId && f.runId !== selectedRunId) {
      return false;
    }
    if (severityFilter !== "all" && f.severity !== severityFilter) {
      return false;
    }
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    const findingType = (f.findingType ?? f.findingCode ?? "").toLowerCase();
    const title = (f.title ?? "").toLowerCase();
    const moduleName = (f.moduleName ?? "").toLowerCase();
    const details = (f.details ?? "").toLowerCase();
    const recommendation = (f.recommendation ?? "").toLowerCase();
    const refTable = (f.referenceTable ?? "").toLowerCase();

    return (
      findingType.includes(q) ||
      title.includes(q) ||
      moduleName.includes(q) ||
      details.includes(q) ||
      recommendation.includes(q) ||
      refTable.includes(q)
    );
  });

  return (
    <div className="space-y-4">
      {/* Search and Filters Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-default pb-3">
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative w-64">
            <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
            <input
              type="text"
              placeholder="Search defects, codes, recommendations..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="h-9 w-full rounded-xl border border-border-default bg-surface-primary pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden"
            />
          </div>

          <div className="flex items-center gap-1">
            {["all", "critical", "high", "medium", "low"].map((sev) => (
              <button
                key={sev}
                type="button"
                onClick={() => setSeverityFilter(sev)}
                className={`rounded-lg px-2.5 py-1 text-xs font-bold transition cursor-pointer ${
                  severityFilter === sev
                    ? "bg-brand-primary text-surface-primary"
                    : "bg-surface-primary text-text-secondary hover:bg-surface-hover border border-border-default"
                }`}
              >
                {sev}
              </button>
            ))}
          </div>

          {/* Active Run Filter Indicator */}
          {selectedRunId && (
            <div className="flex items-center gap-1.5 rounded-xl bg-brand-50 px-2.5 py-1 text-xs font-medium text-brand-900 border border-brand-200 dark:bg-brand-950/40 dark:border-brand-800">
              <span>
                Run: <code className="font-mono font-bold">{selectedRunId.slice(0, 8)}</code>
              </span>
              <button
                type="button"
                onClick={onClearRunFilter}
                className="text-brand-700 hover:text-brand-950 font-bold ml-1 cursor-pointer"
                title="Clear run filter"
              >
                <X className="h-3 w-3" />
              </button>
            </div>
          )}
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
        <div className="space-y-3">
          {filteredFindings.map((f) => {
            const config = SEVERITY_CONFIG[f.severity] ?? SEVERITY_CONFIG.medium;
            const Icon = config.icon;
            const defectCode = f.findingType ?? f.findingCode ?? "defect_logged";

            return (
              <div
                key={f.id}
                className={`rounded-2xl border p-4 transition ${config.card}`}
              >
                {/* Header Row */}
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex flex-wrap items-center gap-2">
                    {/* Severity Badge */}
                    <span
                      className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-bold border ${config.pill}`}
                    >
                      <Icon className="h-3 w-3" />
                      <span className="uppercase">{f.severity}</span>
                    </span>

                    {/* True Defect Code */}
                    <code className="font-mono text-xs font-bold text-text-primary bg-surface-subtle px-2 py-0.5 rounded-md border border-border-default">
                      {defectCode}
                    </code>

                    {/* Finding Title */}
                    <span className="text-sm font-semibold text-text-primary">
                      {f.title}
                    </span>
                  </div>

                  {/* Timestamp */}
                  <span className="font-mono text-xs text-text-muted">
                    {f.createdAt ? new Date(f.createdAt).toLocaleString() : ""}
                  </span>
                </div>

                {/* Metadata Context Row */}
                <div className="mt-2.5 flex flex-wrap items-center gap-3 text-xs text-text-secondary">
                  <span>
                    Module: <strong className="text-text-primary">{f.moduleName}</strong>
                  </span>
                  <span>•</span>
                  <span>
                    Status: <strong className="text-text-primary uppercase">{f.status}</strong>
                  </span>

                  {/* Entity Reference */}
                  {f.referenceTable && (
                    <>
                      <span>•</span>
                      <span className="inline-flex items-center gap-1 font-mono text-xs text-text-secondary bg-surface-subtle px-2 py-0.5 rounded-lg border border-border-default">
                        <Database className="h-3 w-3 text-text-muted" />
                        <span>Entity:</span>
                        <strong className="text-text-primary">{f.referenceTable}</strong>
                        {f.referenceRecordId && (
                          <span className="text-text-muted">
                            ({f.referenceRecordId.slice(0, 8)}...)
                          </span>
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
                        onClick={() => onSelectRun?.(f.runId!)}
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
                  <p className="mt-2.5 text-xs font-mono bg-surface-subtle p-2.5 rounded-xl border border-border-default text-text-secondary overflow-x-auto leading-relaxed">
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
            );
          })}
        </div>
      )}
    </div>
  );
}
