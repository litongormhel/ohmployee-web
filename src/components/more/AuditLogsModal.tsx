"use client";

import { useState } from "react";
import {
  ChevronDown,
  Clock,
  Copy,
  FileCode,
  History,
  RefreshCw,
  Search,
  User,
  ArrowRight,
  Code,
  Building2,
} from "lucide-react";
import { useSystemAuditLogs } from "@/lib/queries/governance";
import { Modal } from "@/components/shared/Modal";
import {
  normalizeModuleName,
  formatActionBadge,
  extractEntityDetails,
  formatAuditSentence,
  computeMeaningfulDiff,
  type ActionBadgeVariant,
} from "@/lib/utils/audit_formatter";

export interface AuditLogsModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin?: boolean;
}

const MODULE_OPTIONS = [
  "all",
  "Plantilla",
  "Vacancy",
  "Moses HQ",
  "HR Emploc",
  "Security",
  "Settings",
  "CENCOM",
  "Archival",
];

const ACTION_OPTIONS = [
  "all",
  "INSERT",
  "UPDATE",
  "DELETE",
  "APPROVE",
  "REJECT",
  "ROLE_CHANGE",
  "LOGIN",
  "LOGOUT",
  "TERMINATE_SESSION",
];

export function AuditLogsModal({
  isOpen,
  onClose,
}: AuditLogsModalProps) {
  const [selectedModule, setSelectedModule] = useState("all");
  const [selectedAction, setSelectedAction] = useState("all");
  const [datePreset, setDatePreset] = useState<"today" | "7d" | "30d" | "all">("30d");
  const [searchQuery, setSearchQuery] = useState("");
  const [expandedLogId, setExpandedLogId] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [showRawJsonMap, setShowRawJsonMap] = useState<Record<string, boolean>>({});

  const {
    data: logs = [],
    isLoading,
    isFetching,
    refetch,
  } = useSystemAuditLogs({
    module: selectedModule,
    action: selectedAction,
    search: searchQuery,
    datePreset,
    limit: 100,
  });

  const toggleExpand = (id: string) => {
    setExpandedLogId((prev) => (prev === id ? null : id));
  };

  const toggleRawJson = (id: string) => {
    setShowRawJsonMap((prev) => ({ ...prev, [id]: !prev[id] }));
  };

  const handleCopyRecord = (id: string, text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2500);
  };

  const getActionBadgeClass = (variant: ActionBadgeVariant) => {
    switch (variant) {
      case "danger":
        return "bg-danger-subtle text-danger border-danger-border";
      case "brand":
        return "bg-brand-subtle text-brand-primary border-brand-border";
      case "success":
        return "bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-950/30 dark:text-emerald-400 dark:border-emerald-800";
      case "amber":
        return "bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-950/30 dark:text-amber-400 dark:border-amber-800";
      default:
        return "bg-surface-subtle text-text-primary border-border-default";
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="System Audit Logs & Change Trail"
      subtitle="Comprehensive immutable audit trail of record mutations, administrative actions, and data changes."
      icon={History}
      maxWidthClass="max-w-6xl"
    >
      <div className="flex flex-col h-[75vh]">
        {/* Filters Toolbar */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base px-2 py-3 gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search actor, record, action..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
              />
            </div>

            <select
              value={selectedModule}
              onChange={(e) => setSelectedModule(e.target.value)}
              className="h-8.5 rounded-lg border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
            >
              {MODULE_OPTIONS.map((m) => (
                <option key={m} value={m}>
                  {m === "all" ? "All Modules" : m}
                </option>
              ))}
            </select>

            <select
              value={selectedAction}
              onChange={(e) => setSelectedAction(e.target.value)}
              className="h-8.5 rounded-lg border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
            >
              {ACTION_OPTIONS.map((a) => (
                <option key={a} value={a}>
                  {a === "all" ? "All Actions" : a}
                </option>
              ))}
            </select>

            <div className="flex items-center gap-1">
              {[
                { key: "today", label: "Today" },
                { key: "7d", label: "7 Days" },
                { key: "30d", label: "30 Days" },
                { key: "all", label: "All" },
              ].map((p) => (
                <button
                  key={p.key}
                  type="button"
                  onClick={() => setDatePreset(p.key as "today" | "7d" | "30d" | "all")}
                  className={`rounded-lg px-2.5 py-1 text-xs font-bold transition cursor-pointer ${
                    datePreset === p.key
                      ? "bg-brand-primary text-text-inverse"
                      : "bg-surface-base text-text-secondary hover:bg-surface-hover border border-border-subtle"
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-3">
            <span className="text-xs text-text-muted font-mono">
              Showing {logs.length} audit entries
            </span>
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetching}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetching ? "animate-spin text-brand-primary" : "text-text-muted"
                }`}
              />
              Refresh
            </button>
          </div>
        </div>

        {/* Audit Log Table Body */}
        <div className="flex-1 overflow-y-auto p-4 space-y-3">
          {isLoading ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-brand-primary" />
              <p className="text-xs">Querying audit logs trail...</p>
            </div>
          ) : logs.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
              <History className="mx-auto h-8 w-8 text-text-muted mb-2" />
              <p className="font-semibold text-text-primary">No audit logs match current filters</p>
              <p className="mt-0.5 text-text-muted">
                System activities matching selected module, action, and date range will appear here.
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {logs.map((log) => {
                const isExpanded = expandedLogId === log.id;
                const hasDiff = Boolean(log.oldData || log.newData);
                const badgeInfo = formatActionBadge(log.action);
                const normalizedModule = normalizeModuleName(log.module);
                const entity = extractEntityDetails(log);
                const humanSentence = formatAuditSentence(log);
                const diffList = isExpanded ? computeMeaningfulDiff(log.oldData, log.newData) : [];
                const showRaw = Boolean(showRawJsonMap[log.id]);

                return (
                  <div
                    key={log.id}
                    className="rounded-xl border border-border-default bg-surface-base overflow-hidden shadow-2xs hover:border-border-strong transition"
                  >
                    {/* Header Row */}
                    <div className="flex flex-wrap items-center justify-between gap-3 p-4 border-b border-border-subtle bg-surface-subtle/50">
                      <div className="flex flex-wrap items-center gap-2">
                        <span
                          className={`rounded-md px-2 py-0.5 text-xs font-bold border ${getActionBadgeClass(
                            badgeInfo.variant
                          )}`}
                        >
                          {badgeInfo.label}
                        </span>

                        <span className="font-bold text-sm text-text-primary">
                          {normalizedModule}
                        </span>

                        {entity.subject && (
                          <span className="inline-flex items-center gap-1 rounded-md bg-surface-base px-2 py-0.5 text-xs font-semibold text-text-primary border border-border-subtle shadow-2xs">
                            <User className="h-3 w-3 text-brand-primary" />
                            {entity.subject}
                          </span>
                        )}

                        {entity.vcode && (
                          <span className="font-mono text-xs font-bold rounded bg-surface-base px-1.5 py-0.5 text-text-secondary border border-border-default">
                            {entity.vcode}
                          </span>
                        )}

                        {entity.storeName && (
                          <span className="inline-flex items-center gap-1 text-xs text-text-secondary">
                            <Building2 className="h-3 w-3 text-text-muted" />
                            {entity.storeName}
                            {entity.position ? ` • ${entity.position}` : ""}
                          </span>
                        )}
                      </div>

                      <div className="flex items-center gap-3">
                        <span className="text-xs font-mono text-text-muted flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          {new Date(log.timestamp).toLocaleString()}
                        </span>
                        {hasDiff && (
                          <button
                            type="button"
                            onClick={() => toggleExpand(log.id)}
                            className="inline-flex items-center gap-1 text-xs font-semibold text-brand-primary hover:underline cursor-pointer"
                          >
                            {isExpanded ? "Hide Diff" : "Inspect Diff"}
                            <ChevronDown
                              className={`h-3.5 w-3.5 transition-transform ${
                                isExpanded ? "-rotate-180" : ""
                              }`}
                            />
                          </button>
                        )}
                      </div>
                    </div>

                    {/* Human-Readable Event Summary & Actor Strip */}
                    <div className="p-4 space-y-2.5">
                      <p className="text-sm font-medium text-text-primary leading-relaxed">
                        {humanSentence}
                      </p>

                      <div className="flex flex-wrap items-center justify-between gap-3 pt-1 border-t border-border-subtle text-xs text-text-secondary">
                        <div className="flex items-center gap-2">
                          <span className="text-text-muted">Actor:</span>
                          <span className="font-semibold text-text-primary">
                            {log.actorName ?? "System"}
                          </span>
                          {log.actorRole && (
                            <span className="rounded bg-surface-subtle px-1.5 py-0.5 text-2xs font-bold text-text-secondary border border-border-default">
                              {log.actorRole}
                            </span>
                          )}
                        </div>

                        {log.recordId && (
                          <div className="flex items-center gap-1.5 font-mono text-2xs text-text-muted">
                            <button
                              type="button"
                              onClick={() => handleCopyRecord(log.id, log.recordId!)}
                              className="inline-flex items-center gap-1 hover:text-text-primary cursor-pointer transition"
                              title="Click to copy full record UUID"
                            >
                              <Copy className="h-3 w-3" />
                              <span>{copiedId === log.id ? "Copied Record ID!" : `Record: ${log.recordId}`}</span>
                            </button>
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Expandable Before & After Diff Viewer */}
                    {isExpanded && hasDiff && (
                      <div className="p-4 pt-3 border-t border-border-subtle bg-surface-subtle/30 space-y-3">
                        <div className="flex items-center justify-between">
                          <h4 className="text-xs font-bold text-text-secondary flex items-center gap-1.5">
                            <FileCode className="h-3.5 w-3.5 text-brand-primary" />
                            Change Details
                          </h4>
                          <button
                            type="button"
                            onClick={() => toggleRawJson(log.id)}
                            className="inline-flex items-center gap-1 text-2xs font-semibold text-text-muted hover:text-text-primary cursor-pointer"
                          >
                            <Code className="h-3 w-3" />
                            {showRaw ? "Hide Raw JSON" : "Show Raw JSON"}
                          </button>
                        </div>

                        {/* Meaningful Field Diffs */}
                        {diffList.length > 0 ? (
                          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
                            {diffList.map((diff) => (
                              <div
                                key={diff.key}
                                className="rounded-lg border border-border-default bg-surface-base p-2.5 space-y-1"
                              >
                                <span className="text-2xs font-bold uppercase tracking-wider text-text-muted">
                                  {diff.label}
                                </span>
                                <div className="flex items-center gap-1.5 text-xs font-mono">
                                  <span className="line-through text-danger truncate max-w-[120px]" title={diff.oldValue}>
                                    {diff.oldValue}
                                  </span>
                                  <ArrowRight className="h-3 w-3 shrink-0 text-text-muted" />
                                  <span className="font-semibold text-emerald-600 dark:text-emerald-400 truncate max-w-[120px]" title={diff.newValue}>
                                    {diff.newValue}
                                  </span>
                                </div>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <p className="text-2xs text-text-muted italic">
                            No field-level scalar mutations detected.
                          </p>
                        )}

                        {/* Raw JSON Snapshot (collapsible) */}
                        {showRaw && (
                          <div className="grid grid-cols-1 md:grid-cols-2 gap-3 pt-2">
                            <div>
                              <span className="text-2xs font-bold text-danger">
                                Previous State (old_data):
                              </span>
                              <pre className="mt-1 rounded-lg border border-danger-border bg-danger-subtle/50 p-2.5 font-mono text-2xs text-danger-text overflow-x-auto max-h-48">
                                {log.oldData ? JSON.stringify(log.oldData, null, 2) : "null (New Record)"}
                              </pre>
                            </div>

                            <div>
                              <span className="text-2xs font-bold text-text-primary">
                                Mutated State (new_data):
                              </span>
                              <pre className="mt-1 rounded-lg border border-border-default bg-surface-subtle p-2.5 font-mono text-2xs text-text-primary overflow-x-auto max-h-48">
                                {log.newData ? JSON.stringify(log.newData, null, 2) : "null (Deleted Record)"}
                              </pre>
                            </div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-2 py-3 pt-4">
          <span className="text-xs text-text-muted font-mono">
            Table: public.audit_logs • RPC: log_audit_event
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
