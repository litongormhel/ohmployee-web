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
import { Modal } from "@/components/shared/Modal";

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

  const selectedRole = useMemo(() => {
    if (!roles.length) return null;
    if (selectedRoleId) return roles.find((r) => r.id === selectedRoleId) ?? roles[0];
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

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 4000);
  };

  const isRoleProtected = selectedRole ? selectedRole.level >= 100 : false;

  const getChangeKey = (row: EffectivePermissionRow) =>
    `${row.moduleKey}::${row.resourceKey}::${row.actionKey}`;

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
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Permission Matrix & Overrides"
        subtitle="Inspect and stage transactional role permission overrides with full audit accountability."
        icon={Key}
        maxWidthClass="max-w-6xl"
      >
        <div className="flex flex-col h-[75vh]">
          {/* Toast */}
          {toastMessage && (
            <div className="mb-3 flex items-center gap-2 rounded-xl border border-brand-border bg-brand-subtle px-4 py-2.5 text-xs font-semibold text-brand-primary shadow-xs">
              <Sparkles className="h-4 w-4 text-brand-primary" />
              <span>{toastMessage}</span>
            </div>
          )}

          {/* Controls Toolbar: Role Selector & Filters */}
          <div className="flex flex-wrap items-center justify-between border-b border-border-subtle bg-surface-base px-2 py-3 gap-3">
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
                  className="h-8.5 rounded-lg border border-border-default bg-surface-base px-3 text-xs font-semibold text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
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
                  className="h-8.5 w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
                />
              </div>

              <select
                value={filterModule}
                onChange={(e) => setFilterModule(e.target.value)}
                className="h-8.5 rounded-lg border border-border-default bg-surface-base px-2.5 text-xs font-medium text-text-primary focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default cursor-pointer"
              >
                <option value="all">All Modules ({modules.length})</option>
                {modules.map((m) => (
                  <option key={m} value={m}>
                    {m}
                  </option>
                ))}
              </select>
            </div>

            <div className="flex items-center gap-3">
              <div className="flex items-center gap-2 text-xs text-text-muted">
                <span className="inline-flex items-center gap-1">
                  <span className="h-2 w-2 rounded-full bg-border-strong" /> Allowed
                </span>
                <span className="inline-flex items-center gap-1">
                  <span className="h-2 w-2 rounded-full bg-danger" /> Denied
                </span>
                <span className="inline-flex items-center gap-1">
                  <span className="h-2 w-2 rounded-full bg-brand-primary" /> Overridden
                </span>
              </div>
              <button
                type="button"
                onClick={() => refetchMatrix()}
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

          {/* Protection Banner for Super Admin */}
          {isRoleProtected && (
            <div className="flex items-center gap-2.5 bg-surface-subtle px-4 py-2.5 border-b border-border-default text-xs font-medium text-text-primary">
              <ShieldAlert className="h-4 w-4 shrink-0 text-text-secondary" />
              <span>
                <strong>Super Admin Role Protected:</strong> Level 100 role permissions are strictly system-guarded (<code className="font-mono text-xs">SA_PROTECTED</code>) and cannot be overridden to prevent administrative lockouts.
              </span>
            </div>
          )}

          {/* Main Grid Body */}
          <div className="flex-1 overflow-y-auto p-4 space-y-6">
            {isLoadingMatrix ? (
              <div className="flex h-64 flex-col items-center justify-center gap-3 text-text-muted">
                <RefreshCw className="h-8 w-8 animate-spin text-brand-primary" />
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
                    className="rounded-xl border border-border-default bg-surface-base overflow-hidden shadow-2xs"
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
                        <Layers className="h-4 w-4 text-brand-primary" />
                        <span className="text-xs font-bold uppercase tracking-wider text-text-primary">
                          {moduleKey}
                        </span>
                        <span className="rounded-full bg-surface-subtle px-2 py-0.5 text-xs font-mono font-semibold text-text-muted">
                          {rows.length} rules
                        </span>
                      </div>

                      <span className="text-xs text-text-muted">
                        {isCollapsed ? "Click to expand" : "Click to collapse"}
                      </span>
                    </button>

                    {/* Rows Table */}
                    {!isCollapsed && (
                      <div className="divide-y divide-border-subtle font-medium text-text-primary">
                        {rows.map((row) => {
                          const isAllowed = getDisplayedValue(row);
                          const isStaged = isRowStaged(row);
                          const hasActiveOverride = row.hasOverride;

                          return (
                            <div
                              key={getChangeKey(row)}
                              className={`flex flex-col sm:flex-row sm:items-center justify-between gap-4 px-4 py-3 hover:bg-surface-hover/40 transition text-sm ${
                                isStaged
                                  ? "bg-brand-subtle/40 border-l-4 border-l-brand-primary"
                                  : hasActiveOverride
                                  ? "bg-surface-subtle"
                                  : ""
                              }`}
                            >
                              <div className="space-y-1">
                                <div className="flex flex-wrap items-center gap-2">
                                  <span className="font-mono text-sm font-bold text-text-primary">
                                    {row.resourceKey}
                                  </span>
                                  <span className="rounded-md bg-surface-subtle px-1.5 py-0.5 font-mono text-xs font-bold text-text-muted uppercase border border-border-subtle">
                                    {row.actionKey}
                                  </span>

                                  {hasActiveOverride && (
                                    <span className="inline-flex items-center gap-1 rounded-md bg-brand-subtle px-1.5 py-0.2 text-xs font-bold text-brand-primary border border-brand-border">
                                      <Sparkles className="h-3 w-3" />
                                      Active Override
                                    </span>
                                  )}

                                  {isStaged && (
                                    <span className="inline-flex items-center gap-1 rounded-md bg-brand-subtle px-1.5 py-0.2 text-xs font-bold text-brand-primary border border-brand-border">
                                      Staged for Commit
                                    </span>
                                  )}

                                  {row.isSystemLocked && (
                                    <span className="inline-flex items-center gap-1 rounded-md bg-surface-subtle px-1.5 py-0.2 text-xs font-medium text-text-secondary border border-border-default">
                                      <Lock className="h-3 w-3" /> Locked
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
                                  <span>Tier: <code className="font-mono">{row.enforcementTier}</code></span>
                                  <span>•</span>
                                  <span>Scope: <code className="font-mono">{row.scopeMode}</code></span>
                                  <span>•</span>
                                  <span>Base: <strong className={row.baseAllowed ? "text-text-primary" : "text-danger"}>{row.baseAllowed ? "Allowed" : "Denied"}</strong></span>
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
                                      ? "bg-surface-subtle text-text-primary border border-border-default hover:bg-surface-hover"
                                      : "bg-danger-subtle text-danger border border-danger-border hover:bg-danger-subtle/80"
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
            <div className="flex flex-wrap items-center justify-between border-t border-brand-border bg-brand-subtle px-4 py-3 gap-3">
              <div className="flex items-center gap-2">
                <span className="flex h-6 w-6 items-center justify-center rounded-full bg-brand-primary text-text-inverse font-bold text-xs">
                  {stagedCount}
                </span>
                <div>
                  <h4 className="text-xs font-bold text-brand-primary">
                    {stagedCount} staged permission {stagedCount === 1 ? "override" : "overrides"} ready for commit
                  </h4>
                  <p className="text-xs text-text-secondary">
                    Changes will be atomically applied to {selectedRole?.name} with audit trail logging.
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-2.5">
                <button
                  type="button"
                  onClick={handleDiscardStaged}
                  className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-secondary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
                >
                  <Undo2 className="h-3.5 w-3.5" />
                  Discard
                </button>
                <button
                  type="button"
                  onClick={handleOpenCommit}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-4 py-1.5 text-xs font-bold text-text-inverse shadow-xs hover:bg-brand-primary/90 transition cursor-pointer"
                >
                  Review & Apply Overrides
                </button>
              </div>
            </div>
          )}

          {/* Modal Footer */}
          <div className="flex items-center justify-between border-t border-border-subtle bg-surface-base px-2 py-3 pt-4">
            <span className="text-xs text-text-muted font-mono">
              RPCs: get_effective_permission_matrix • apply_permission_overrides
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

      {/* Commit Overrides Confirmation Modal */}
      <Modal
        isOpen={isCommitModalOpen}
        onClose={() => setIsCommitModalOpen(false)}
        title="Commit Permission Overrides"
        subtitle={`Applying ${stagedCount} rule overrides to role ${selectedRole?.name}`}
        icon={Key}
        maxWidthClass="max-w-lg"
        isSubmitting={applyOverridesMutation.isPending}
        disableBackdropClick={applyOverridesMutation.isPending}
        isDirty={Boolean(commitReason)}
      >
        <div className="space-y-4">
          {commitError && (
            <div className="rounded-lg border border-danger-border bg-danger-subtle p-3 text-xs text-danger">
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
                className="w-full rounded-xl border border-border-default bg-surface-base p-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
              />
            </div>

            <div className="rounded-lg bg-surface-subtle p-3 border border-border-default max-h-36 overflow-y-auto space-y-1.5 text-xs font-mono">
              {Object.entries(stagedChanges).map(([key, val]) => (
                <div key={key} className="flex items-center justify-between">
                  <span className="text-text-primary">{key}</span>
                  <span className={val ? "text-brand-primary font-bold" : "text-danger font-bold"}>
                    → {val ? "ALLOW" : "DENY"}
                  </span>
                </div>
              ))}
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={() => setIsCommitModalOpen(false)}
                disabled={applyOverridesMutation.isPending}
                className="rounded-lg border border-border-default px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover cursor-pointer disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={applyOverridesMutation.isPending}
                className="rounded-lg bg-brand-primary px-4 py-2 text-xs font-bold text-text-inverse shadow-xs hover:bg-brand-primary/90 disabled:opacity-50 cursor-pointer"
              >
                {applyOverridesMutation.isPending ? "Applying Overrides..." : "Confirm & Apply"}
              </button>
            </div>
          </form>
        </div>
      </Modal>
    </>
  );
}
