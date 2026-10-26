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
  XCircle,
} from "lucide-react";
import {
  useGovernanceRoles,
  useRolePermissionMatrix,
  type RolePermissionMatrixItem,
} from "@/lib/queries/governance";
import { Modal } from "@/components/shared/Modal";

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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Role Permissions Matrix"
      subtitle="Authoritative backend permission mapping for every system role, enforcement tier, and sensitivity tier."
      icon={ShieldCheck}
      maxWidthClass="max-w-6xl"
    >
      <div className="flex flex-col h-[75vh]">
        {/* Role Selector Tabs (Quick Pill Switching) */}
        <div className="flex items-center gap-1.5 border-b border-border-subtle bg-surface-base px-2 py-2.5 overflow-x-auto">
          <span className="text-xs font-bold text-text-muted mr-1">
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
                    ? "bg-brand-primary text-text-inverse shadow-2xs"
                    : "bg-surface-base text-text-secondary hover:bg-surface-hover border border-border-subtle"
                }`}
              >
                <span>{r.name}</span>
                <span
                  className={`rounded-full px-1.5 py-0.2 text-xs font-mono ${
                    isSelected ? "bg-[var(--surface-overlay)] text-[var(--foreground)]" : "bg-surface-subtle text-text-muted"
                  }`}
                >
                  Lvl {r.level}
                </span>
              </button>
            );
          })}
        </div>

        {/* Filter and Stats Bar */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base px-2 py-3 gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search modules, actions..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
              />
            </div>

            <div className="flex items-center gap-1">
              {(["all", "allowed", "denied"] as const).map((st) => (
                <button
                  key={st}
                  type="button"
                  onClick={() => setStatusFilter(st)}
                  className={`rounded-lg px-2.5 py-1 text-xs font-bold  transition cursor-pointer ${
                    statusFilter === st
                      ? "bg-brand-primary text-text-inverse"
                      : "bg-surface-base text-text-secondary hover:bg-surface-hover border border-border-subtle"
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
                className="rounded-sm border-border-default text-brand-primary focus:ring-brand-default"
              />
              <span>Sensitive Only</span>
            </label>

            <label className="flex items-center gap-1.5 text-xs text-text-secondary cursor-pointer select-none">
              <input
                type="checkbox"
                checked={lockedOnly}
                onChange={(e) => setLockedOnly(e.target.checked)}
                className="rounded-sm border-border-default text-brand-primary focus:ring-brand-default"
              />
              <span>Locked Only</span>
            </label>
          </div>

          <div className="flex items-center gap-3 text-xs">
            <span className="text-text-primary font-semibold bg-surface-subtle px-2 py-0.5 rounded-md border border-border-default">
              {allowedCount} Allowed
            </span>
            <span className="text-danger font-semibold bg-danger-subtle px-2 py-0.5 rounded-md border border-danger-border">
              {deniedCount} Denied
            </span>
            <span className="text-text-muted font-mono text-xs">
              Showing {filteredItems.length} rules
            </span>
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetchingMatrix}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetchingMatrix ? "animate-spin text-brand-primary" : "text-text-muted"
                }`}
              />
              Refresh
            </button>
          </div>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-4 space-y-6">
          {isLoadingMatrix ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-brand-primary" />
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
                  className="rounded-xl border border-border-default bg-surface-base overflow-hidden shadow-2xs"
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
                      <Layers className="h-4 w-4 text-brand-primary" />
                      <span className="text-xs font-bold text-text-primary">
                        {moduleKey}
                      </span>
                      <span className="rounded-full bg-surface-subtle px-2 py-0.5 text-xs font-mono font-semibold text-text-muted">
                        {rows.length} actions
                      </span>
                    </div>

                    <div className="flex items-center gap-2 text-xs">
                      <span className="text-text-primary font-semibold">{modAllowed} allowed</span>
                      <span className="text-text-muted">•</span>
                      <span className="text-danger font-semibold">{rows.length - modAllowed} denied</span>
                    </div>
                  </button>

                  {!isCollapsed && (
                    <div className="divide-y divide-border-subtle font-medium text-text-primary">
                      {rows.map((row) => (
                        <div
                          key={`${row.moduleKey}-${row.resourceKey}-${row.actionKey}`}
                          className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 px-4 py-3 hover:bg-surface-hover/30 transition text-sm"
                        >
                          <div className="space-y-1">
                            <div className="flex flex-wrap items-center gap-2">
                              <span className="font-mono text-sm font-bold text-text-primary">
                                {row.resourceKey}
                              </span>
                              <span className="rounded-md bg-surface-subtle px-1.5 py-0.5 font-mono text-xs font-bold text-text-muted border border-border-subtle">
                                {row.actionKey}
                              </span>

                              {row.isSystemLocked && (
                                <span className="inline-flex items-center gap-1 rounded-md bg-surface-subtle px-1.5 py-0.2 text-xs font-medium text-text-secondary border border-border-default">
                                  <Lock className="h-3 w-3" /> System Locked
                                </span>
                              )}

                              {row.isSensitive && (
                                <span className="inline-flex items-center gap-1 rounded-md bg-danger-subtle px-1.5 py-0.2 text-xs font-bold text-danger border border-danger-border">
                                  Sensitive
                                </span>
                              )}
                            </div>

                            {row.description && (
                              <p className="text-xs text-text-secondary">{row.description}</p>
                            )}

                            <div className="flex flex-wrap items-center gap-3 text-xs text-text-muted">
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
                                  ? "bg-surface-subtle text-text-primary border border-border-default"
                                  : "bg-danger-subtle text-danger border border-danger-border"
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
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-2 py-3 pt-4">
          <span className="text-xs text-text-muted font-mono">
            Direct database authority: public.fn_get_permission_matrix(p_role_id)
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
