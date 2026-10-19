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
  X,
} from "lucide-react";
import { useSystemAuditLogs } from "@/lib/queries/governance";

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


  if (!isOpen) return null;

  const toggleExpand = (id: string) => {
    setExpandedLogId((prev) => (prev === id ? null : id));
  };

  const handleCopyRecord = (id: string, text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2500);
  };

  const getActionBadgeColor = (act: string) => {
    const upper = act.toUpperCase();
    if (upper === "DELETE" || upper.includes("REVOKE") || upper.includes("TERMINATE")) {
      return "bg-red-50 text-red-700 border-red-200";
    }
    if (upper === "UPDATE" || upper === "ROLE_CHANGE" || upper.includes("OVERRIDE")) {
      return "bg-amber-50 text-amber-700 border-amber-200";
    }
    if (upper === "INSERT" || upper === "APPROVE" || upper === "LOGIN") {
      return "bg-emerald-50 text-emerald-700 border-emerald-200";
    }
    return "bg-blue-50 text-blue-700 border-blue-200";
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 sm:p-6"
    >
      <div className="relative flex h-[90vh] max-h-[850px] w-full max-w-6xl flex-col rounded-2xl border border-border-default bg-surface-card shadow-2xl overflow-hidden">
        {/* Modal Header */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base/80 px-6 py-4 gap-4">
          <div className="flex items-center gap-3.5">
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-purple-500/10 text-purple-600 border border-purple-500/20">
              <History className="h-6 w-6" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-text-primary">System Audit Logs & Change Trail</h2>
                <span className="rounded-md bg-purple-50 px-2 py-0.5 text-2xs font-extrabold text-purple-700 border border-purple-200 uppercase">
                  Super Admin
                </span>
                <span className="rounded-md bg-slate-100 px-2 py-0.5 text-2xs font-bold text-slate-700 border border-slate-200">
                  Forensic Trail
                </span>
              </div>
              <p className="text-xs text-text-secondary mt-0.5">
                Comprehensive immutable audit trail of record mutations, administrative actions, and data changes.
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
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetching ? "animate-spin text-purple-600" : "text-text-muted"
                }`}
              />
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

        {/* Filters Toolbar */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base px-6 py-3 gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search actor, record, action..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-card pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>

            <select
              value={selectedModule}
              onChange={(e) => setSelectedModule(e.target.value)}
              className="h-8.5 rounded-lg border border-border-default bg-surface-card px-2.5 text-xs font-medium text-text-primary focus:border-brand-500 focus:outline-hidden"
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
              className="h-8.5 rounded-lg border border-border-default bg-surface-card px-2.5 text-xs font-medium text-text-primary focus:border-brand-500 focus:outline-hidden"
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
                  className={`rounded-lg px-2.5 py-1 text-2xs font-bold transition cursor-pointer ${
                    datePreset === p.key
                      ? "bg-purple-600 text-white"
                      : "bg-surface-card text-text-secondary hover:bg-surface-hover border border-border-subtle"
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>

          <span className="text-2xs text-text-muted font-mono">
            Showing {logs.length} audit entries
          </span>
        </div>

        {/* Audit Log Table Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {isLoading ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-purple-600" />
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
                const hasDiff = log.oldData || log.newData;

                return (
                  <div
                    key={log.id}
                    className="rounded-xl border border-border-default bg-surface-card overflow-hidden shadow-2xs hover:border-brand-200 transition"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-3 p-4 border-b border-border-subtle bg-surface-base/30">
                      <div className="flex items-center gap-2.5">
                        <span
                          className={`rounded-md px-2 py-0.5 text-2xs font-extrabold uppercase tracking-wider border ${getActionBadgeColor(
                            log.action
                          )}`}
                        >
                          {log.action}
                        </span>
                        <span className="font-bold text-xs text-text-primary">{log.module}</span>
                        {log.recordId && (
                          <span className="font-mono text-2xs text-text-muted">
                            Record: {log.recordId.slice(0, 8)}...
                          </span>
                        )}
                      </div>

                      <div className="flex items-center gap-3">
                        <span className="text-2xs font-mono text-text-muted flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          {new Date(log.timestamp).toLocaleString()}
                        </span>
                        {hasDiff && (
                          <button
                            type="button"
                            onClick={() => toggleExpand(log.id)}
                            className="inline-flex items-center gap-1 text-xs font-semibold text-brand-600 hover:text-brand-700 cursor-pointer"
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

                    <div className="p-4 flex flex-wrap items-center justify-between gap-4 text-xs">
                      <div className="flex items-center gap-3 text-text-secondary">
                        <div className="flex items-center gap-1.5 font-medium">
                          <User className="h-3.5 w-3.5 text-text-muted" />
                          <span>
                            Actor: <strong className="text-text-primary">{log.actorName ?? "System"}</strong>
                          </span>
                        </div>
                        {log.actorRole && (
                          <span className="rounded-md bg-purple-50 px-2 py-0.5 text-2xs font-bold text-purple-700 border border-purple-200">
                            {log.actorRole}
                          </span>
                        )}
                      </div>

                      {log.recordId && (
                        <div className="flex items-center gap-2">
                          <button
                            type="button"
                            onClick={() => handleCopyRecord(log.id, log.recordId!)}
                            className="inline-flex items-center gap-1 font-mono text-2xs text-text-muted hover:text-text-primary cursor-pointer"
                          >
                            <Copy className="h-3 w-3" />
                            {copiedId === log.id ? "Copied ID!" : `ID: ${log.recordId}`}
                          </button>
                        </div>
                      )}
                    </div>

                    {/* Expandable Before & After Diff Viewer */}
                    {isExpanded && hasDiff && (
                      <div className="p-4 pt-0 border-t border-border-subtle bg-surface-base/50">
                        <h4 className="text-xs font-bold uppercase tracking-wider text-text-secondary my-3 flex items-center gap-1.5">
                          <FileCode className="h-3.5 w-3.5 text-brand-600" />
                          Forensic Change Snapshot
                        </h4>

                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                          <div>
                            <span className="text-2xs font-bold uppercase tracking-wider text-red-700">
                              Previous Data (old_data):
                            </span>
                            <pre className="mt-1 rounded-lg border border-red-200 bg-red-50/30 p-3 font-mono text-2xs text-red-950 overflow-x-auto max-h-56">
                              {log.oldData ? JSON.stringify(log.oldData, null, 2) : "null (New Record Creation)"}
                            </pre>
                          </div>

                          <div>
                            <span className="text-2xs font-bold uppercase tracking-wider text-emerald-700">
                              Mutated Data (new_data):
                            </span>
                            <pre className="mt-1 rounded-lg border border-emerald-200 bg-emerald-50/30 p-3 font-mono text-emerald-950 overflow-x-auto max-h-56">
                              {log.newData ? JSON.stringify(log.newData, null, 2) : "null (Record Deletion)"}
                            </pre>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-6 py-3">
          <span className="text-2xs text-text-muted font-mono">
            Table: public.audit_logs • RPC: log_audit_event
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
