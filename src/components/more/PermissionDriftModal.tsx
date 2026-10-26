"use client";

import { useState } from "react";
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  ChevronDown,
  Code2,
  RefreshCw,
  Search,
  ShieldAlert,
  Sparkles,
  TrendingUp,
} from "lucide-react";
import {
  usePermissionDriftFindings,
  usePermissionDriftSummary,
} from "@/lib/queries/governance";
import { Modal } from "@/components/shared/Modal";

export interface PermissionDriftModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin?: boolean;
}

export function PermissionDriftModal({
  isOpen,
  onClose,
}: PermissionDriftModalProps) {
  const [selectedStatus, setSelectedStatus] = useState<string>("open");
  const [selectedSeverity, setSelectedSeverity] = useState<string>("all");
  const [selectedModule, setSelectedModule] = useState<string>("all");
  const [searchQuery, setSearchQuery] = useState("");
  const [expandedFindings, setExpandedFindings] = useState<Record<string, boolean>>({});

  const {
    data: summary,
    refetch: refetchSummary,
  } = usePermissionDriftSummary();

  const {
    data: findings = [],
    isLoading: isLoadingFindings,
    isFetching: isFetchingFindings,
    refetch: refetchFindings,
  } = usePermissionDriftFindings({
    status: selectedStatus,
    severity: selectedSeverity,
    moduleKey: selectedModule,
  });

  const handleRefresh = () => {
    refetchSummary();
    refetchFindings();
  };

  const toggleExpand = (id: string) => {
    setExpandedFindings((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const filteredFindings = findings.filter((f) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      f.findingCode.toLowerCase().includes(q) ||
      f.moduleKey.toLowerCase().includes(q) ||
      f.findingSummary.toLowerCase().includes(q) ||
      f.recommendation.toLowerCase().includes(q) ||
      f.driftCategory.toLowerCase().includes(q)
    );
  });

  const modulesList = Array.from(new Set(findings.map((f) => f.moduleKey))).filter(Boolean);

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Permission Drift & Authorization Gaps"
      subtitle="Automated detection of mismatches between backend code enforcement, RLS policies, and matrix grants."
      icon={TrendingUp}
      maxWidthClass="max-w-6xl"
    >
      <div className="flex flex-col h-[75vh]">
        {/* KPI Summary Cards */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 border-b border-border-subtle bg-surface-base px-2 py-4">
          <div className="rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>Open Drift Gaps</span>
              <AlertCircle className="h-4 w-4 text-brand-primary" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-text-primary">
                {summary?.openFindings ?? 0}
              </span>
              <span className="text-xs font-semibold text-text-muted">Active</span>
            </div>
          </div>

          <div className="rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-danger font-semibold">
              <span>Critical Gaps</span>
              <AlertTriangle className="h-4 w-4 text-danger" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-danger">
                {summary?.criticalCount ?? 0}
              </span>
              <span className="text-xs font-bold text-danger">Immediate Action</span>
            </div>
          </div>

          <div className="rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>High Severity</span>
              <ShieldAlert className="h-4 w-4 text-text-secondary" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-text-primary">
                {summary?.highCount ?? 0}
              </span>
              <span className="text-xs font-semibold text-text-muted">Elevated</span>
            </div>
          </div>

          <div className="rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs">
            <div className="flex items-center justify-between text-xs text-text-secondary font-semibold">
              <span>Resolved / Accepted</span>
              <CheckCircle2 className="h-4 w-4 text-brand-primary" />
            </div>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-text-primary">
                {(summary?.resolvedCount ?? 0) + (summary?.acceptedRiskCount ?? 0)}
              </span>
              <span className="text-xs font-semibold text-text-muted">Compliant</span>
            </div>
          </div>
        </div>

        {/* Filter Controls Bar */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base px-2 py-3 gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search findings, code, summary..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
              />
            </div>

            <div className="flex items-center gap-1">
              {[
                { key: "open", label: "Open" },
                { key: "resolved", label: "Resolved" },
                { key: "accepted_risk", label: "Accepted Risk" },
                { key: "all", label: "All" },
              ].map((st) => (
                <button
                  key={st.key}
                  type="button"
                  onClick={() => setSelectedStatus(st.key)}
                  className={`rounded-lg px-2.5 py-1 text-xs font-bold transition cursor-pointer ${
                    selectedStatus === st.key
                      ? "bg-brand-primary text-text-inverse"
                      : "bg-surface-base text-text-secondary hover:bg-surface-hover border border-border-subtle"
                  }`}
                >
                  {st.label}
                </button>
              ))}
            </div>

            <select
              value={selectedSeverity}
              onChange={(e) => setSelectedSeverity(e.target.value)}
              className="h-8.5 rounded-lg border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
            >
              <option value="all">All Severities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
            </select>

            {modulesList.length > 0 && (
              <select
                value={selectedModule}
                onChange={(e) => setSelectedModule(e.target.value)}
                className="h-8.5 rounded-lg border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
              >
                <option value="all">All Modules</option>
                {modulesList.map((m) => (
                  <option key={m} value={m}>
                    {m}
                  </option>
                ))}
              </select>
            )}
          </div>

          <div className="flex items-center gap-3">
            <span className="text-xs text-text-muted font-mono">
              Showing {filteredFindings.length} findings
            </span>
            <button
              type="button"
              onClick={handleRefresh}
              disabled={isFetchingFindings}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetchingFindings ? "animate-spin text-brand-primary" : "text-text-muted"
                }`}
              />
              Refresh
            </button>
          </div>
        </div>

        {/* Findings List Body */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {isLoadingFindings ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-brand-primary" />
              <p className="text-xs">Querying drift detector findings from database...</p>
            </div>
          ) : filteredFindings.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
              <CheckCircle2 className="mx-auto h-8 w-8 text-brand-primary mb-2" />
              <p className="font-semibold text-text-primary">No permission drift detected</p>
              <p className="mt-0.5 text-text-muted">
                All role permissions match observed backend execution enforcement.
              </p>
            </div>
          ) : (
            filteredFindings.map((finding) => {
              const isExpanded = expandedFindings[finding.findingId];
              const isCrit = finding.severity.toLowerCase() === "critical";

              return (
                <div
                  key={finding.findingId}
                  className={`rounded-xl border transition shadow-2xs overflow-hidden ${
                    isCrit
                      ? "border-danger-border bg-danger-subtle/50"
                      : "border-border-default bg-surface-base"
                  }`}
                >
                  {/* Card Header Bar */}
                  <div className="flex flex-wrap items-center justify-between gap-3 p-4 border-b border-border-subtle bg-surface-subtle/50">
                    <div className="flex items-center gap-2.5">
                      <span
                        className={`rounded-md px-2 py-0.5 text-xs font-bold uppercase tracking-wider ${
                          isCrit
                            ? "bg-danger-subtle text-danger border border-danger-border"
                            : "bg-surface-subtle text-text-primary border border-border-default"
                        }`}
                      >
                        {finding.severity}
                      </span>
                      <span className="font-mono text-sm font-bold text-text-primary">
                        {finding.findingCode}
                      </span>
                      <span className="rounded-md bg-surface-subtle px-2 py-0.5 font-mono text-xs font-semibold text-text-muted border border-border-subtle">
                        {finding.moduleKey}
                      </span>
                      <span className="text-xs font-medium text-text-secondary">
                        ({finding.driftCategory})
                      </span>
                    </div>

                    <div className="flex items-center gap-3">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-bold uppercase ${
                          finding.status === "open"
                            ? "bg-danger-subtle text-danger border border-danger-border"
                            : "bg-surface-subtle text-text-primary border border-border-default"
                        }`}
                      >
                        {finding.status}
                      </span>
                      <button
                        type="button"
                        onClick={() => toggleExpand(finding.findingId)}
                        className="inline-flex items-center gap-1 text-xs font-semibold text-brand-primary hover:underline cursor-pointer"
                      >
                        {isExpanded ? "Hide Details" : "Inspect Gap"}
                        <ChevronDown
                          className={`h-3.5 w-3.5 transition-transform ${
                            isExpanded ? "-rotate-180" : ""
                          }`}
                        />
                      </button>
                    </div>
                  </div>

                  {/* Card Main Summary */}
                  <div className="p-4 space-y-3">
                    <h3 className="text-sm font-bold text-text-primary">
                      {finding.findingSummary}
                    </h3>

                    {/* Comparison Grid: Expected vs Observed */}
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                      <div className="rounded-lg border border-border-default bg-surface-subtle p-3">
                        <span className="text-xs font-bold uppercase tracking-wider text-text-secondary">
                          Expected Enforcement:
                        </span>
                        <p className="mt-1 font-mono text-xs text-text-primary font-medium">
                          {finding.expectedEnforcement}
                        </p>
                      </div>

                      <div className="rounded-lg border border-border-default bg-surface-subtle p-3">
                        <span className="text-xs font-bold uppercase tracking-wider text-text-secondary">
                          Observed / Code Enforcement:
                        </span>
                        <p className="mt-1 font-mono text-xs text-text-primary font-medium">
                          {finding.observedEnforcement}
                        </p>
                      </div>
                    </div>

                    {/* Recommendation */}
                    {finding.recommendation && (
                      <div className="rounded-lg border border-brand-border bg-brand-subtle p-3 text-xs">
                        <strong className="text-brand-primary font-semibold flex items-center gap-1.5">
                          <Sparkles className="h-3.5 w-3.5 text-brand-primary" />
                          Remediation Recommendation:
                        </strong>
                        <p className="mt-1 text-text-primary leading-relaxed text-xs">
                          {finding.recommendation}
                        </p>
                      </div>
                    )}

                    {/* Expandable Evidence Details */}
                    {isExpanded && (
                      <div className="pt-3 border-t border-border-subtle space-y-3">
                        <h4 className="text-xs font-bold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
                          <Code2 className="h-3.5 w-3.5 text-brand-primary" />
                          Code & Runtime Evidence Trace
                        </h4>

                        {finding.evidence.length === 0 ? (
                          <p className="text-xs text-text-muted italic">
                            No discrete evidence line traces registered for this finding.
                          </p>
                        ) : (
                          <div className="space-y-2">
                            {finding.evidence.map((ev, i) => (
                              <div
                                key={i}
                                className="rounded-lg bg-surface-subtle p-2.5 border border-border-default font-mono text-xs space-y-1"
                              >
                                <div className="flex items-center justify-between text-text-muted">
                                  <span className="font-bold text-text-primary">{ev.evidenceType}</span>
                                  {ev.filePath && <span>{ev.filePath}</span>}
                                </div>
                                <div className="text-brand-primary">
                                  Key: <span className="font-semibold">{ev.evidenceKey}</span> → Value: {ev.evidenceValue}
                                </div>
                                {ev.lineNote && (
                                  <div className="text-text-secondary italic">{ev.lineNote}</div>
                                )}
                              </div>
                            ))}
                          </div>
                        )}

                        <div className="flex flex-wrap items-center justify-between text-xs text-text-muted pt-2 border-t border-border-subtle">
                          <span>Target Resource: <code className="font-mono">{finding.resourceKey}</code> ({finding.actionKey})</span>
                          <span>Detected: {new Date(finding.createdAt).toLocaleString()}</span>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-2 py-3 pt-4">
          <span className="text-xs text-text-muted font-mono">
            Detector: fn_get_permission_drift_findings • fn_get_permission_drift_summary
          </span>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>
    </Modal>
  );
}
