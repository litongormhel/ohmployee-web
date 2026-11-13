"use client";

import React from "react";
import { CheckCircle2, Clock, ShieldAlert, ShieldCheck, XCircle } from "lucide-react";
import type { QaRunSummary } from "@/lib/queries/governance";

export interface QaRunHistoryTableProps {
  runs: QaRunSummary[];
  onViewFindingsForRun?: (runId: string) => void;
}

export function QaRunHistoryTable({
  runs,
  onViewFindingsForRun,
}: QaRunHistoryTableProps) {
  if (runs.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
        No test runs logged yet. Execute a simulation above or run the core detection suite.
      </div>
    );
  }

  return (
    <div className="rounded-2xl border border-border-default overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b border-border-default bg-surface-subtle text-xs font-bold text-text-muted">
              <th className="py-2.5 px-4">Status</th>
              <th className="py-2.5 px-4">Agent / Suite & Summary</th>
              <th className="py-2.5 px-4">Target Module</th>
              <th className="py-2.5 px-4">Isolation</th>
              <th className="py-2.5 px-4">Steps</th>
              <th className="py-2.5 px-4">Findings</th>
              <th className="py-2.5 px-4">Started At</th>
              <th className="py-2.5 px-4">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-subtle bg-surface-primary">
            {runs.map((r) => {
              const statusLower = (r.status ?? "").toLowerCase();
              const isSuccess = statusLower === "passed" || statusLower === "completed";
              const isFailed = statusLower === "failed" || r.criticalCount > 0;

              // Check if sandbox rolled back based on rolledBack property or positive confirmation in summary text
              const summaryLower = (r.summary ?? "").toLowerCase();
              const isRolledBack =
                r.rolledBack ??
                (Boolean(r.summary) &&
                  (summaryLower.includes("qa_sandbox_rollback_success") ||
                    summaryLower.includes("zero data pollution") ||
                    (summaryLower.includes("rolled back") &&
                      !summaryLower.includes("failed") &&
                      !summaryLower.includes("leak"))));

              // Steps count default to 7 if role relay
              const stepsCount =
                r.stepsCount ??
                (r.agentName.includes("RELAY") || (r.summary && r.summary.includes("RELAY"))
                  ? 7
                  : undefined);

              return (
                <tr key={r.id} className="hover:bg-surface-hover/50 transition">
                  {/* Status */}
                  <td className="py-3 px-4">
                    <span
                      className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold ${
                        isSuccess
                          ? "bg-status-success-bg text-status-success-text border border-status-success-border"
                          : isFailed
                          ? "bg-status-danger-bg text-status-danger-text border border-status-danger-border"
                          : "bg-surface-subtle text-text-secondary border border-border-default"
                      }`}
                    >
                      {isSuccess ? (
                        <CheckCircle2 className="h-3.5 w-3.5 text-status-success-text" />
                      ) : isFailed ? (
                        <XCircle className="h-3.5 w-3.5 text-status-danger-text" />
                      ) : (
                        <Clock className="h-3.5 w-3.5 text-text-muted" />
                      )}
                      <span className="uppercase">{r.status}</span>
                    </span>
                  </td>

                  {/* Agent Suite & Run Summary */}
                  <td className="py-3 px-4 max-w-sm">
                    <div className="font-semibold text-text-primary text-xs">
                      {r.agentName}
                    </div>
                    {r.summary ? (
                      <div
                        className="text-xs text-text-secondary truncate mt-0.5 font-mono"
                        title={r.summary}
                      >
                        {r.summary}
                      </div>
                    ) : (
                      <div className="text-xs text-text-muted mt-0.5 font-mono">
                        Run ID: {r.id.slice(0, 8)}...
                      </div>
                    )}
                  </td>

                  {/* Target Module */}
                  <td className="py-3 px-4">
                    <span className="font-mono text-xs bg-surface-subtle px-2 py-0.5 rounded-full border border-border-default text-text-secondary">
                      {r.targetModule}
                    </span>
                  </td>

                  {/* Atomic Sandbox Isolation Badge */}
                  <td className="py-3 px-4">
                    {isRolledBack ? (
                      <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border border-emerald-500/30">
                        <ShieldCheck className="h-3 w-3" />
                        <span>Rolled Back</span>
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/30">
                        <ShieldAlert className="h-3 w-3" />
                        <span>Check Rollback</span>
                      </span>
                    )}
                  </td>

                  {/* Steps Count */}
                  <td className="py-3 px-4">
                    {stepsCount ? (
                      <span className="font-mono text-xs font-semibold text-text-secondary bg-surface-subtle px-2 py-0.5 rounded-md border border-border-default">
                        {stepsCount} steps
                      </span>
                    ) : (
                      <span className="text-xs text-text-muted">-</span>
                    )}
                  </td>

                  {/* Findings Breakdown */}
                  <td className="py-3 px-4">
                    <div className="flex items-center gap-1 text-xs font-semibold">
                      {r.criticalCount > 0 && (
                        <span className="bg-danger-surface text-danger-text border border-danger-border px-1.5 py-0.2 rounded-full">
                          {r.criticalCount} crit
                        </span>
                      )}
                      {r.highCount > 0 && (
                        <span className="bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/30 px-1.5 py-0.2 rounded-full">
                          {r.highCount} high
                        </span>
                      )}
                      {r.mediumCount > 0 && (
                        <span className="bg-blue-500/10 text-blue-700 dark:text-blue-400 border border-blue-500/30 px-1.5 py-0.2 rounded-full">
                          {r.mediumCount} med
                        </span>
                      )}
                      {r.lowCount > 0 && (
                        <span className="bg-surface-subtle text-text-muted border border-border-default px-1.5 py-0.2 rounded-full">
                          {r.lowCount} low
                        </span>
                      )}
                      {r.findingCount > 0 &&
                        r.criticalCount === 0 &&
                        r.highCount === 0 &&
                        r.mediumCount === 0 &&
                        r.lowCount === 0 && (
                          <span className="text-text-secondary text-xs">
                            {r.findingCount} total
                          </span>
                        )}
                      {r.findingCount === 0 && (
                        <span className="text-text-primary text-xs font-medium">Clean</span>
                      )}
                    </div>
                  </td>

                  {/* Started At */}
                  <td className="py-3 px-4 font-mono text-xs text-text-muted">
                    {r.startedAt ? new Date(r.startedAt).toLocaleString() : "-"}
                  </td>

                  {/* Actions */}
                  <td className="py-3 px-4">
                    {r.findingCount > 0 ? (
                      <button
                        type="button"
                        onClick={() => onViewFindingsForRun?.(r.id)}
                        className="rounded-lg bg-danger-surface border border-danger-border px-2.5 py-1 text-xs font-semibold text-danger-text hover:bg-danger-border/30 transition cursor-pointer"
                      >
                        Findings ({r.findingCount})
                      </button>
                    ) : (
                      <span className="text-xs text-text-muted font-mono">0 defects</span>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
