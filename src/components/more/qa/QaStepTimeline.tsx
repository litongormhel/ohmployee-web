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

export interface QaStepTimelineProps {
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
              Simulating Head Admin, Encoder, Recruitment, HRCO, HR Personnel, and Back Office actors in an isolated atomic sandbox.
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

  const steps: QaScenarioStep[] = (result.steps ?? []).filter(
    (s): s is QaScenarioStep => Boolean(s && typeof s === "object")
  );
  const findingCounts = result.finding_counts ?? result.findingCounts ?? {};
  const totalFindings = Number.isFinite(Number(findingCounts.total))
    ? Math.max(0, Number(findingCounts.total))
    : (Number(findingCounts.critical ?? 0) || 0) +
      (Number(findingCounts.high ?? 0) || 0) +
      (Number(findingCounts.medium ?? 0) || 0) +
      (Number(findingCounts.low ?? 0) || 0);
  const isRolledBack = result.sandbox_rolled_back ?? result.sandboxRolledBack ?? false;
  const isSuccess = result.success;
  const runId = result.run_id ?? result.runId ?? "";
  const scenarioCode = result.scenario_code ?? result.scenarioCode ?? selectedScenarioCode;
  const executedAt = result.executed_at ?? result.executedAt ?? "";

  return (
    <div className="rounded-2xl border border-border-default bg-surface-primary p-5 shadow-2xs space-y-4">
      {/* 1. Header Banner & Scenario Status */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-default pb-3.5">
        <div className="flex items-center gap-2.5">
          <div
            className={`flex h-8 w-8 items-center justify-center rounded-xl font-bold ${
              isSuccess
                ? "bg-status-success-bg text-status-success-text border border-status-success-border"
                : "bg-status-danger-bg text-status-danger-text border border-status-danger-border"
            }`}
          >
            {isSuccess ? (
              <CheckCircle2 className="h-4 w-4" />
            ) : (
              <XCircle className="h-4 w-4" />
            )}
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-bold text-text-primary">
                Scenario Run: {scenarioCode}
              </h3>
              <span
                className={`rounded-full px-2 py-0.5 text-xs font-bold border ${
                  isSuccess
                    ? "bg-status-success-bg text-status-success-text border-status-success-border"
                    : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
                }`}
              >
                {isSuccess ? "PASSED CLEANLY" : "ANOMALIES DETECTED"}
              </span>
            </div>
            <p className="text-xs text-text-muted mt-0.5 font-mono">
              Run ID: {runId} {executedAt ? `• Executed: ${new Date(executedAt).toLocaleTimeString()}` : ""}
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
          isRolledBack
            ? "border-status-success-border bg-status-success-bg/60 text-text-primary"
            : "border-status-danger-border bg-status-danger-bg/60 text-text-primary"
        }`}
      >
        <div className="flex items-center gap-2.5">
          <div
            className={`flex h-7 w-7 items-center justify-center rounded-lg border ${
              isRolledBack
                ? "bg-status-success-bg text-status-success-text border-status-success-border"
                : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
            }`}
          >
            {isRolledBack ? (
              <ShieldCheck className="h-4 w-4 text-status-success-text" />
            ) : (
              <ShieldAlert className="h-4 w-4 text-status-danger-text" />
            )}
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="font-mono text-xs font-bold text-text-primary tracking-wide">
                {isRolledBack
                  ? "QA_SANDBOX_ROLLBACK_SUCCESS"
                  : "QA_SANDBOX_ROLLBACK_FAILED"}
              </span>
              <span
                className={`rounded-full px-2 py-0.2 text-[10px] font-mono font-bold uppercase border ${
                  isRolledBack
                    ? "bg-surface-primary text-status-success-text border-status-success-border"
                    : "bg-surface-primary text-status-danger-text border-status-danger-border"
                }`}
              >
                {isRolledBack ? "100% Rolled Back" : "Leak Warning"}
              </span>
            </div>
            <p className="text-xs text-text-secondary mt-0.5">
              {isRolledBack
                ? "Zero data pollution confirmed: all test mutations across vacancies, plantilla, applicants, and hr_emploc were atomically reverted."
                : "Isolation warning: subtransaction rollback was not confirmed. Live tables may have uncommitted test data."}
            </p>
          </div>
        </div>

        <div
          className={`flex items-center gap-1.5 text-xs font-mono px-2.5 py-1 rounded-lg border ${
            isRolledBack
              ? "text-text-muted bg-surface-primary border-border-default"
              : "text-amber-600 dark:text-amber-400 bg-surface-primary border-amber-500/30"
          }`}
        >
          <Database
            className={`h-3 w-3 ${
              isRolledBack ? "text-brand-primary" : "text-amber-500"
            }`}
          />
          <span>
            {isRolledBack
              ? "Operational Tables: Clean"
              : "Operational Tables: Potential Leak"}
          </span>
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
              const isStepPassed = (st?.status ?? "").toLowerCase() === "passed";
              const roleConfig = getRoleBadgeConfig(st?.role);
              const isLast = idx === steps.length - 1;
              const stepNumber = Number.isFinite(Number(st?.step)) ? Number(st.step) : idx + 1;
              const actionName = st?.action ? String(st.action) : "unknown_action";

              return (
                <div key={st?.step ?? idx} className="relative flex items-start gap-3">
                  {/* Step Connector Line */}
                  {!isLast && (
                    <div className="absolute left-3.5 top-7 bottom-0 w-0.5 bg-border-subtle" />
                  )}

                  {/* Step Circle Badge */}
                  <div
                    className={`relative z-10 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border text-xs font-mono font-bold ${
                      isStepPassed
                        ? "bg-status-success-bg text-status-success-text border-status-success-border"
                        : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
                    }`}
                  >
                    {stepNumber}
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
                          {actionName}
                        </code>
                      </div>

                      {/* Status Pill */}
                      <span
                        className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold border ${
                          isStepPassed
                            ? "bg-status-success-bg text-status-success-text border-status-success-border"
                            : "bg-status-danger-bg text-status-danger-text border-status-danger-border"
                        }`}
                      >
                        {isStepPassed ? (
                          <CheckCircle2 className="h-3 w-3" />
                        ) : (
                          <XCircle className="h-3 w-3" />
                        )}
                        <span>{isStepPassed ? "PASSED" : "FAILED"}</span>
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
