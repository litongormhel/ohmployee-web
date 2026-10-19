"use client";

import { useMemo, useState } from "react";
import {
  Check,
  ChevronDown,
  Key,
  Layers,
  Lock,
  RefreshCw,
  Search,
  ShieldAlert,
  Sparkles,
  Undo2,
  X,
} from "lucide-react";
import {
  useApplyPermissionOverrides,
  useEffectivePermissionMatrix,
  useGovernanceRoles,
  type EffectivePermissionRow,
} from "@/lib/queries/governance";

export interface PermissionMatrixModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin?: boolean;
}

export function PermissionMatrixModal({
  isOpen,
  onClose,
}: PermissionMatrixModalProps) {

  const { data: roles = [], isLoading: isLoadingRoles } = useGovernanceRoles();
  const [selectedRoleId, setSelectedRoleId] = useState<string>("");

  // Auto-select first non-SA or first role
  const selectedRole = useMemo(() => {
    if (!roles.length) return null;
    if (selectedRoleId) return roles.find((r) => r.id === selectedRoleId) ?? roles[0];
    // Default to Head Admin or first role
    return roles.find((r) => r.level === 90) ?? roles[0];
  }, [roles, selectedRoleId]);

  const {
    data: matrix = [],
    isLoading: isLoadingMatrix,
    isFetching: isFetchingMatrix,
    refetch: refetchMatrix,
  } = useEffectivePermissionMatrix(selectedRole?.name ?? null);

  const applyOverridesMutation = useApplyPermissionOverrides();

  // Staged changes: key = `${moduleKey}::${resourceKey}::${actionKey}` -> targetAllowed
  const [stagedChanges, setStagedChanges] = useState<Record<string, boolean>>({});
  const [searchQuery, setSearchQuery] = useState("");
  const [filterModule, setFilterModule] = useState<string>("all");
  const [collapsedModules, setCollapsedModules] = useState<Record<string, boolean>>({});

  // Review / Commit Dialog
  const [isCommitModalOpen, setIsCommitModalOpen] = useState(false);
  const [commitReason, setCommitReason] = useState("");
  const [commitError, setCommitError] = useState<string | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  if (!isOpen) return null;

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 4000);
  };

  const isRoleProtected = selectedRole ? selectedRole.level >= 100 : false;

  // Staging key helper
  const getChangeKey = (row: EffectivePermissionRow) =>
    `${row.moduleKey}::${row.resourceKey}::${row.actionKey}`;

  // Get effective displayed value (staged value overrides saved value)
  const getDisplayedValue = (row: EffectivePermissionRow) => {
    const key = getChangeKey(row);
    if (key in stagedChanges) {
      return stagedChanges[key];
    }
    return row.isAllowed;
  };

  const isRowStaged = (row: EffectivePermissionRow) => {
    const key = getChangeKey(row);
    return key in stagedChanges;
  };

  const handleToggle = (row: EffectivePermissionRow) => {
    if (isRoleProtected) return;
    if (row.isSystemLocked) return;

    const key = getChangeKey(row);
    const currentValue = getDisplayedValue(row);
    const targetValue = !currentValue;

    if (targetValue === row.isAllowed) {
      // Un-stage if toggled back to original state
      const next = { ...stagedChanges };
      delete next[key];
      setStagedChanges(next);
    } else {
      setStagedChanges((prev) => ({
        ...prev,
        [key]: targetValue,
      }));
    }
  };

  const handleDiscardStaged = () => {
    setStagedChanges({});
  };

  const stagedCount = Object.keys(stagedChanges).length;

  const handleOpenCommit = () => {
    setCommitReason("");
    setCommitError(null);
    setIsCommitModalOpen(true);
  };

  const handleConfirmCommit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedRole) return;
    if (!commitReason.trim()) {
      setCommitError("An audit justification reason is required for governance tracking.");
      return;
    }

    const changesToSubmit = Object.entries(stagedChanges).map(([key, isAllowed]) => {
      const [moduleKey, resourceKey, actionKey] = key.split("::");
      return {
        role_name: selectedRole.name,
        module_key: moduleKey,
        resource_key: resourceKey,
        action_key: actionKey,
        is_allowed: isAllowed,
      };
    });

    try {
      await applyOverridesMutation.mutateAsync({
        changes: changesToSubmit,
        reason: commitReason.trim(),
      });
      setStagedChanges({});
      setIsCommitModalOpen(false);
      refetchMatrix();
      showToast(`Successfully applied ${changesToSubmit.length} permission overrides for ${selectedRole.name}.`);
    } catch (err: unknown) {
      setCommitError((err as Error).message);
    }
  };

  // Group matrix by module
  const modules = Array.from(new Set(matrix.map((m) => m.moduleKey))).sort();

  const filteredMatrix = matrix.filter((row) => {
    if (filterModule !== "all" && row.moduleKey !== filterModule) return false;
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      row.moduleKey.toLowerCase().includes(q) ||
      row.resourceKey.toLowerCase().includes(q) ||
      row.actionKey.toLowerCase().includes(q) ||
      (row.description ?? "").toLowerCase().includes(q)
    );
  });

  const matrixByModule = filteredMatrix.reduce<Record<string, EffectivePermissionRow[]>>((acc, row) => {
    if (!acc[row.moduleKey]) acc[row.moduleKey] = [];
    acc[row.moduleKey].push(row);
    return acc;
  }, {});

  const toggleModuleCollapse = (mod: string) => {
    setCollapsedModules((prev) => ({ ...prev, [mod]: !prev[mod] }));
  };

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
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-brand-500/10 text-brand-600 border border-brand-500/20">
              <Key className="h-6 w-6" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-text-primary">Permission Matrix & Overrides</h2>
                <span className="rounded-md bg-purple-50 px-2 py-0.5 text-2xs font-extrabold text-purple-700 border border-purple-200 uppercase">
                  Super Admin
                </span>
                <span className="rounded-md bg-amber-50 px-2 py-0.5 text-2xs font-bold text-amber-700 border border-amber-200">
                  Atomic Overrides
                </span>
              </div>
              <p className="text-xs text-text-secondary mt-0.5">
                Inspect and stage transactional role permission overrides with full audit accountability.
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => refetchMatrix()}
              disabled={isFetchingMatrix}
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-card px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 ${
                  isFetchingMatrix ? "animate-spin text-brand-600" : "text-text-muted"
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

        {/* Controls Toolbar: Role Selector & Filters */}
        <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-card px-6 py-3 gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="flex items-center gap-2">
              <label htmlFor="role-select" className="text-xs font-bold text-text-secondary">Target Role:</label>
              <select
                id="role-select"
                value={selectedRole?.id ?? ""}
                onChange={(e) => {
                  setSelectedRoleId(e.target.value);
                  setStagedChanges({});
                }}
                disabled={isLoadingRoles}
                className="h-8.5 rounded-lg border border-border-default bg-surface-base px-3 text-xs font-semibold text-text-primary focus:border-brand-500 focus:outline-hidden"
              >
                {roles.map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.name} (Level {r.level})
                  </option>
                ))}
              </select>
            </div>

            <div className="relative w-56">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                type="text"
                placeholder="Search permissions..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              >
              </input>
            </div>

            <select
              value={filterModule}
              onChange={(e) => setFilterModule(e.target.value)}
              className="h-8.5 rounded-lg border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary focus:border-brand-500 focus:outline-hidden"
            >
              <option value="all">All Modules ({modules.length})</option>
              {modules.map((m) => (
                <option key={m} value={m}>
                  {m}
                </option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2 text-2xs text-text-muted">
            <span className="inline-flex items-center gap-1">
              <span className="h-2 w-2 rounded-full bg-emerald-500" /> Allowed
            </span>
            <span className="inline-flex items-center gap-1">
              <span className="h-2 w-2 rounded-full bg-red-400" /> Denied
            </span>
            <span className="inline-flex items-center gap-1">
              <span className="h-2 w-2 rounded-full bg-amber-500" /> Overridden
            </span>
          </div>
        </div>

        {/* Protection Banner for Super Admin */}
        {isRoleProtected && (
          <div className="flex items-center gap-2.5 bg-amber-500/10 px-6 py-2.5 border-b border-amber-500/20 text-xs font-medium text-amber-800">
            <ShieldAlert className="h-4 w-4 shrink-0 text-amber-600" />
            <span>
              <strong>Super Admin Role Protected:</strong> Level 100 role permissions are strictly system-guarded (<code className="font-mono text-2xs">SA_PROTECTED</code>) and cannot be overridden to prevent administrative lockouts.
            </span>
          </div>
        )}

        {/* Main Grid Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {isLoadingMatrix ? (
            <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
              <RefreshCw className="h-8 w-8 animate-spin text-brand-600" />
              <p className="text-xs">Resolving effective matrix permissions for {selectedRole?.name}...</p>
            </div>
          ) : filteredMatrix.length === 0 ? (
            <div className="rounded-xl border border-dashed border-border-default p-12 text-center text-xs text-text-muted">
              No permissions found matching query filters.
            </div>
          ) : (
            Object.entries(matrixByModule).map(([moduleKey, rows]) => {
              const isCollapsed = collapsedModules[moduleKey];
              return (
                <div
                  key={moduleKey}
                  className="rounded-xl border border-border-default bg-surface-card overflow-hidden shadow-2xs"
                >
                  {/* Module Group Header */}
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
                      <Layers className="h-4 w-4 text-brand-600" />
                      <span className="text-xs font-bold uppercase tracking-wider text-text-primary">
                        {moduleKey}
                      </span>
                      <span className="rounded-full bg-surface-hover px-2 py-0.5 text-2xs font-mono font-semibold text-text-muted">
                        {rows.length} rules
                      </span>
                    </div>

                    <span className="text-2xs text-text-muted">
                      {isCollapsed ? "Click to expand" : "Click to collapse"}
                    </span>
                  </button>

                  {/* Rows Table */}
                  {!isCollapsed && (
                    <div className="divide-y divide-border-subtle">
                      {rows.map((row) => {
                        const isAllowed = getDisplayedValue(row);
                        const isStaged = isRowStaged(row);
                        const hasActiveOverride = row.hasOverride;

                        return (
                          <div
                            key={getChangeKey(row)}
                            className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 px-4 py-3 hover:bg-surface-hover/40 transition ${
                              isStaged
                                ? "bg-amber-500/10 border-l-4 border-l-amber-500"
                                : hasActiveOverride
                                ? "bg-purple-500/5"
                                : ""
                            }`}
                          >
                            <div className="space-y-1">
                              <div className="flex flex-wrap items-center gap-2">
                                <span className="font-mono text-xs font-bold text-text-primary">
                                  {row.resourceKey}
                                </span>
                                <span className="rounded-md bg-surface-base px-1.5 py-0.5 font-mono text-2xs font-bold text-text-muted uppercase border border-border-subtle">
                                  {row.actionKey}
                                </span>

                                {hasActiveOverride && (
                                  <span className="inline-flex items-center gap-1 rounded-md bg-purple-50 px-1.5 py-0.2 text-2xs font-bold text-purple-700 border border-purple-200">
                                    <Sparkles className="h-3 w-3" />
                                    Active Override
                                  </span>
                                )}

                                {isStaged && (
                                  <span className="inline-flex items-center gap-1 rounded-md bg-amber-100 px-1.5 py-0.2 text-2xs font-bold text-amber-900 border border-amber-300">
                                    Staged for Commit
                                  </span>
                                )}

                                {row.isSystemLocked && (
                                  <span className="inline-flex items-center gap-1 rounded-md bg-slate-100 px-1.5 py-0.2 text-2xs font-medium text-slate-700">
                                    <Lock className="h-3 w-3" /> Locked
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
                                <span>Tier: <code className="font-mono">{row.enforcementTier}</code></span>
                                <span>•</span>
                                <span>Scope: <code className="font-mono">{row.scopeMode}</code></span>
                                <span>•</span>
                                <span>Base: <strong className={row.baseAllowed ? "text-emerald-600" : "text-red-500"}>{row.baseAllowed ? "Allowed" : "Denied"}</strong></span>
                                {row.overrideReason && (
                                  <>
                                    <span>•</span>
                                    <span className="italic truncate max-w-xs">
                                      &quot;{row.overrideReason}&quot;
                                    </span>
                                  </>
                                )}
                              </div>
                            </div>

                            {/* Toggle Button */}
                            <div className="flex items-center gap-3 shrink-0">
                              <button
                                type="button"
                                disabled={isRoleProtected || row.isSystemLocked}
                                onClick={() => handleToggle(row)}
                                className={`inline-flex items-center gap-2 rounded-xl px-3 py-1.5 text-xs font-bold transition shadow-2xs cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed ${
                                  isAllowed
                                    ? "bg-emerald-500 text-white hover:bg-emerald-600"
                                    : "bg-red-500 text-white hover:bg-red-600"
                                }`}
                              >
                                {isAllowed ? (
                                  <>
                                    <Check className="h-3.5 w-3.5" />
                                    Allowed
                                  </>
                                ) : (
                                  <>
                                    <X className="h-3.5 w-3.5" />
                                    Denied
                                  </>
                                )}
                              </button>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>

        {/* Staged Changes Bottom Bar */}
        {stagedCount > 0 && (
          <div className="flex flex-wrap items-center justify-between border-t border-amber-300 bg-amber-50 px-6 py-3 gap-3">
            <div className="flex items-center gap-2">
              <span className="flex h-6 w-6 items-center justify-center rounded-full bg-amber-600 text-white font-bold text-xs">
                {stagedCount}
              </span>
              <div>
                <h4 className="text-xs font-bold text-amber-950">
                  {stagedCount} staged permission {stagedCount === 1 ? "override" : "overrides"} ready for commit
                </h4>
                <p className="text-2xs text-amber-800">
                  Changes will be atomically applied to {selectedRole?.name} with audit trail logging.
                </p>
              </div>
            </div>

            <div className="flex items-center gap-2.5">
              <button
                type="button"
                onClick={handleDiscardStaged}
                className="inline-flex items-center gap-1.5 rounded-lg border border-amber-300 bg-white px-3 py-1.5 text-xs font-semibold text-amber-900 shadow-2xs hover:bg-amber-100 transition cursor-pointer"
              >
                <Undo2 className="h-3.5 w-3.5" />
                Discard
              </button>
              <button
                type="button"
                onClick={handleOpenCommit}
                className="inline-flex items-center gap-1.5 rounded-lg bg-amber-700 px-4 py-1.5 text-xs font-bold text-white shadow-xs hover:bg-amber-800 transition cursor-pointer"
              >
                Review & Apply Overrides
              </button>
            </div>
          </div>
        )}

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-6 py-3">
          <span className="text-2xs text-text-muted font-mono">
            RPCs: get_effective_permission_matrix • apply_permission_overrides
          </span>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-border-default bg-surface-card px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer"
          >
            Close
          </button>
        </div>

        {/* Commit Overrides Confirmation Modal */}
        {isCommitModalOpen && (
          <div
            role="dialog"
            aria-modal="true"
            className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4"
          >
            <div className="w-full max-w-lg rounded-2xl border border-border-default bg-surface-card p-6 shadow-2xl space-y-4">
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-amber-500/10 text-amber-600">
                  <Key className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-text-primary">
                    Commit Permission Overrides
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Applying {stagedCount} rule overrides to role <strong>{selectedRole?.name}</strong>
                  </p>
                </div>
              </div>

              {commitError && (
                <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700">
                  {commitError}
                </div>
              )}

              <form onSubmit={handleConfirmCommit} className="space-y-4">
                <div>
                  <label htmlFor="audit-justification" className="block text-xs font-bold text-text-secondary mb-1">
                    Audit Justification & Reason *
                  </label>
                  <textarea
                    id="audit-justification"
                    rows={3}
                    placeholder="Provide a mandatory operational reason (e.g. Approved temporary privilege escalation for HR Audit)..."
                    value={commitReason}
                    onChange={(e) => setCommitReason(e.target.value)}
                    className="w-full rounded-xl border border-border-default bg-surface-base p-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                  />
                </div>

                <div className="rounded-lg bg-surface-base p-3 border border-border-subtle max-h-36 overflow-y-auto space-y-1.5 text-2xs font-mono">
                  {Object.entries(stagedChanges).map(([key, val]) => (
                    <div key={key} className="flex items-center justify-between">
                      <span className="text-text-primary">{key}</span>
                      <span className={val ? "text-emerald-600 font-bold" : "text-red-600 font-bold"}>
                        → {val ? "ALLOW" : "DENY"}
                      </span>
                    </div>
                  ))}
                </div>

                <div className="flex items-center justify-end gap-3 pt-2">
                  <button
                    type="button"
                    onClick={() => setIsCommitModalOpen(false)}
                    className="rounded-lg border border-border-default px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover cursor-pointer"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={applyOverridesMutation.isPending}
                    className="rounded-lg bg-amber-700 px-4 py-2 text-xs font-bold text-white shadow-xs hover:bg-amber-800 disabled:opacity-50 cursor-pointer"
                  >
                    {applyOverridesMutation.isPending ? "Applying Overrides..." : "Confirm & Apply"}
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
