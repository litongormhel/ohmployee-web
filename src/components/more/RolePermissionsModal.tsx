"use client";

import { useMemo, useState } from "react";
import {
  CheckCircle2,
  ChevronDown,
  Layers,
  Lock,
  RefreshCw,
  Search,
  ShieldCheck,
  X,
  XCircle,
} from "lucide-react";
import {
  useGovernanceRoles,
  useRolePermissionMatrix,
  type RolePermissionMatrixItem,
} from "@/lib/queries/governance";

export interface RolePermissionsModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin?: boolean;
}

export function RolePermissionsModal({
  isOpen,
  onClose,
}: RolePermissionsModalProps) {
  const { data: roles = [] } = useGovernanceRoles();
  const [selectedRoleId, setSelectedRoleId] = useState<string>("");


  const selectedRole = useMemo(() => {
    if (!roles.length) return null;
    if (selectedRoleId) return roles.find((r) => r.id === selectedRoleId) ?? roles[0];
    return roles[0];
  }, [roles, selectedRoleId]);

  const {
    data: matrix = [],
    isLoading: isLoadingMatrix,
    isFetching: isFetchingMatrix,
    refetch,
  } = useRolePermissionMatrix(selectedRole?.id ?? null);

  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<"all" | "allowed" | "denied">("all");
  const [sensitiveOnly, setSensitiveOnly] = useState(false);
  const [lockedOnly, setLockedOnly] = useState(false);
  const [collapsedModules, setCollapsedModules] = useState<Record<string, boolean>>({});

  if (!isOpen) return null;

  const filteredItems = matrix.filter((item) => {
    if (statusFilter === "allowed" && !item.isAllowed) return false;
    if (statusFilter === "denied" && item.isAllowed) return false;
    if (sensitiveOnly && !item.isSensitive) return false;
    if (lockedOnly && !item.isSystemLocked) return false;

    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      item.moduleKey.toLowerCase().includes(q) ||
      item.resourceKey.toLowerCase().includes(q) ||
      item.actionKey.toLowerCase().includes(q) ||
      (item.description ?? "").toLowerCase().includes(q)
    );
  });

  const matrixByModule = filteredItems.reduce<Record<string, RolePermissionMatrixItem[]>>(
    (acc, row) => {
      if (!acc[row.moduleKey]) acc[row.moduleKey] = [];
      acc[row.moduleKey].push(row);
      return acc;
    },
    {}
  );

  const toggleModuleCollapse = (mod: string) => {
    setCollapsedModules((prev) => ({ ...prev, [mod]: !prev[mod] }));
  };

  const allowedCount = matrix.filter((m) => m.isAllowed).length;
  const deniedCount = matrix.length - allowedCount;

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
              <ShieldCheck className="h-6 w-6" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-text-primary">Role Permissions Matrix</h2>
                <span className="rounded-md bg-purple-50 px-2 py-0.5 text-2xs font-extrabold text-purple-700 border border-purple-200 uppercase">
                  Read-Only Audit
                </span>
                <span className="rounded-md bg-slate-100 px-2 py-0.5 text-2xs font-bold text-slate-700 border border-slate-200">
                  fn_get_permission_matrix
                </span>
              </div>
              <p className="text-xs text-text-secondary mt-0.5">
                Authoritative backend permission mapping for every system role, enforcement tier, and sensitivity tier.
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetchingMatrix}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-card px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetchingMatrix ? "animate-spin text-purple-600" : "text-text-muted"
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

        {/* Role Selector Tabs (Quick Pill Switching) */}
        <div className="flex items-center gap-1.5 border-b border-border-subtle bg-surface-base px-6 py-2.5 overflow-x-auto">
          <span className="text-2xs font-bold uppercase tracking-wider text-text-muted mr-1">
            Role:
          </span>
          {roles.map((r) => {
            const isSelected = selectedRole?.id === r.id;
            return (
              <button
                key={r.id}
                type="button"
                onClick={() => setSelectedRoleId(r.id)}
                className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold whitespace-nowrap transition cursor-pointer ${
                  isSelected
                    ? "bg-purple-600 text-white shadow-2xs"
                    : "bg-surface-card text-text-secondary hover:bg-surface-hover border border-border-subtle"
                }`}
              >
                <span>{r.name}</span>
                <span
                  className={`rounded-full px-1.5 py-0.2 text-2xs font-mono ${
                    isSelected ? "bg-white/20 text-white" : "bg-surface-base text-text-muted"
                  }`}
                >
                  Lvl {r.level}
                </span>
              </button>
            );
          })}
        </div>

        {/* Filter and Stats Bar */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-card px-6 py-3 gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search modules, actions..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>

            <div className="flex items-center gap-1">
              {(["all", "allowed", "denied"] as const).map((st) => (
                <button
                  key={st}
                  type="button"
                  onClick={() => setStatusFilter(st)}
                  className={`rounded-lg px-2.5 py-1 text-2xs font-bold uppercase transition cursor-pointer ${
                    statusFilter === st
                      ? "bg-purple-100 text-purple-800 border border-purple-300"
                      : "bg-surface-base text-text-secondary hover:bg-surface-hover"
                  }`}
                >
                  {st}
                </button>
              ))}
            </div>

            <label className="flex items-center gap-1.5 text-xs text-text-secondary cursor-pointer select-none">
              <input
                type="checkbox"
                checked={sensitiveOnly}
                onChange={(e) => setSensitiveOnly(e.target.checked)}
                className="rounded-sm border-border-default text-purple-600 focus:ring-purple-500"
              />
              <span>Sensitive Only</span>
            </label>

            <label className="flex items-center gap-1.5 text-xs text-text-secondary cursor-pointer select-none">
              <input
                type="checkbox"
                checked={lockedOnly}
                onChange={(e) => setLockedOnly(e.target.checked)}
                className="rounded-sm border-border-default text-purple-600 focus:ring-purple-500"
              />
              <span>Locked Only</span>
            </label>
          </div>

          <div className="flex items-center gap-3 text-xs">
            <span className="text-emerald-700 font-semibold bg-emerald-50 px-2 py-0.5 rounded-md border border-emerald-200">
              {allowedCount} Allowed
            </span>
            <span className="text-red-700 font-semibold bg-red-50 px-2 py-0.5 rounded-md border border-red-200">
              {deniedCount} Denied
            </span>
            <span className="text-text-muted font-mono text-2xs">
              Showing {filteredItems.length} rules
            </span>
          </div>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {isLoadingMatrix ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-purple-600" />
              <p className="text-xs">Loading authorization matrix for {selectedRole?.name}...</p>
            </div>
          ) : filteredItems.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
              No permission rules found matching search criteria.
            </div>
          ) : (
            Object.entries(matrixByModule).map(([moduleKey, rows]) => {
              const isCollapsed = collapsedModules[moduleKey];
              const modAllowed = rows.filter((r) => r.isAllowed).length;
              return (
                <div
                  key={moduleKey}
                  className="rounded-xl border border-border-default bg-surface-card overflow-hidden shadow-2xs"
                >
                  <button
                    type="button"
                    onClick={() => toggleModuleCollapse(moduleKey)}
                    className="flex w-full items-center justify-between bg-surface-base px-4 py-3 text-left border-b border-border-subtle hover:bg-surface-hover/50 transition cursor-pointer"
                  >
                    <div className="flex items-center gap-2">
                      <ChevronDown
                        className={`h-4 w-4 text-text-muted transition-transform ${
                          isCollapsed ? "-rotate-90" : ""
                        }`}
                      />
                      <Layers className="h-4 w-4 text-purple-600" />
                      <span className="text-xs font-bold uppercase tracking-wider text-text-primary">
                        {moduleKey}
                      </span>
                      <span className="rounded-full bg-surface-hover px-2 py-0.5 text-2xs font-mono font-semibold text-text-muted">
                        {rows.length} actions
                      </span>
                    </div>

                    <div className="flex items-center gap-2 text-2xs">
                      <span className="text-emerald-600 font-semibold">{modAllowed} allowed</span>
                      <span className="text-text-muted">•</span>
                      <span className="text-red-500 font-semibold">{rows.length - modAllowed} denied</span>
                    </div>
                  </button>

                  {!isCollapsed && (
                    <div className="divide-y divide-border-subtle">
                      {rows.map((row) => (
                        <div
                          key={`${row.moduleKey}-${row.resourceKey}-${row.actionKey}`}
                          className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 px-4 py-3 hover:bg-surface-hover/30 transition"
                        >
                          <div className="space-y-1">
                            <div className="flex flex-wrap items-center gap-2">
                              <span className="font-mono text-xs font-bold text-text-primary">
                                {row.resourceKey}
                              </span>
                              <span className="rounded-md bg-surface-base px-1.5 py-0.5 font-mono text-2xs font-bold text-text-muted uppercase border border-border-subtle">
                                {row.actionKey}
                              </span>

                              {row.isSystemLocked && (
                                <span className="inline-flex items-center gap-1 rounded-md bg-slate-100 px-1.5 py-0.2 text-2xs font-medium text-slate-700">
                                  <Lock className="h-3 w-3" /> System Locked
                                </span>
                              )}

                              {row.isSensitive && (
                                <span className="inline-flex items-center gap-1 rounded-md bg-red-50 px-1.5 py-0.2 text-2xs font-bold text-red-700 border border-red-200">
                                  Sensitive
                                </span>
                              )}
                            </div>

                            {row.description && (
                              <p className="text-2xs text-text-secondary">{row.description}</p>
                            )}

                            <div className="flex flex-wrap items-center gap-3 text-2xs text-text-muted">
                              <span>Enforcement: <code className="font-mono">{row.enforcementType}</code></span>
                              <span>•</span>
                              <span>Scope: <code className="font-mono">{row.scopeMode}</code></span>
                              <span>•</span>
                              <span>Source: <code className="font-mono">{row.sourceType}</code></span>
                            </div>
                          </div>

                          <div className="shrink-0">
                            <span
                              className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1 text-xs font-bold ${
                                row.isAllowed
                                  ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                                  : "bg-red-50 text-red-700 border border-red-200"
                              }`}
                            >
                              {row.isAllowed ? (
                                <>
                                  <CheckCircle2 className="h-3.5 w-3.5" />
                                  Allowed
                                </>
                              ) : (
                                <>
                                  <XCircle className="h-3.5 w-3.5" />
                                  Denied
                                </>
                              )}
                            </span>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-6 py-3">
          <span className="text-2xs text-text-muted font-mono">
            Direct database authority: public.fn_get_permission_matrix(p_role_id)
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
