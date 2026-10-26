"use client";

import { useState } from "react";
import {
  AlertCircle,
  ArrowLeft,
  ChevronRight,
  Eye,
  EyeOff,
  History,
  RefreshCw,
  RotateCcw,
  Search,
  Shield,
  Sliders,
} from "lucide-react";
import {
  ACC_MODULE_KEYS,
  ACC_MODULE_LABELS,
  getRoleModuleDefault,
  useAccUsers,
  useSetModuleVisibilityOverride,
  useUserModuleOverrideAudit,
  useUserModuleOverrides,
  type AccUser,
} from "@/lib/queries/more";
import { Modal } from "@/components/shared/Modal";

export interface AccessControlCenterModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin: boolean;
}

export function AccessControlCenterModal({
  isOpen,
  onClose,
  isSuperAdmin,
}: AccessControlCenterModalProps) {
  const [selectedUser, setSelectedUser] = useState<AccUser | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [activeTab, setActiveTab] = useState<"matrix" | "audit">("matrix");

  // Prompt Modal State for Override Reason
  const [promptData, setPromptData] = useState<{
    permissionKey: string;
    targetState: "allow" | "deny" | "inherit";
    label: string;
  } | null>(null);
  const [reason, setReason] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const { data: users = [], isLoading: isLoadingUsers } = useAccUsers();
  const {
    data: overrides = {} as Record<string, string>,
    isLoading: isLoadingOverrides,
    refetch: refetchOverrides,
    isFetching: isFetchingOverrides,
  } = useUserModuleOverrides(selectedUser?.id ?? null);
  const {
    data: audit = [],
    isLoading: isLoadingAudit,
    refetch: refetchAudit,
  } = useUserModuleOverrideAudit(selectedUser?.id ?? null);

  const setOverrideMutation = useSetModuleVisibilityOverride();

  const filteredUsers = users.filter((u) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      u.fullName.toLowerCase().includes(q) ||
      u.roleName.toLowerCase().includes(q) ||
      u.groups.some((g) => g.toLowerCase().includes(q)) ||
      u.accounts.some((a) => a.toLowerCase().includes(q))
    );
  });

  const handleOpenPrompt = (
    permissionKey: string,
    targetState: "allow" | "deny" | "inherit",
    label: string
  ) => {
    setPromptData({ permissionKey, targetState, label });
    setReason("");
    setActionError(null);
  };

  const handleConfirmOverride = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedUser || !promptData) return;
    if (!reason.trim()) {
      setActionError("A reason is required and recorded in the audit history.");
      return;
    }

    try {
      await setOverrideMutation.mutateAsync({
        userId: selectedUser.id,
        permissionKey: promptData.permissionKey,
        state: promptData.targetState,
        reason: reason.trim(),
      });
      setPromptData(null);
      setReason("");
    } catch (err: unknown) {
      setActionError((err as Error)?.message || "Failed to update override.");
    }
  };

  const isPromptDirty = reason.trim().length > 0;

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title={selectedUser ? selectedUser.fullName : "Access Control Center"}
        subtitle={
          selectedUser
            ? `${selectedUser.roleName} (Level ${selectedUser.roleLevel}) • Override navigation visibility`
            : "Super Admin tool to grant or hide module navigation visibility per user"
        }
        icon={Sliders}
        maxWidthClass="max-w-4xl"
        footer={
          <div className="flex w-full items-center justify-between text-xs text-text-muted">
            <span>Target: module_visibility_overrides</span>
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-primary transition hover:bg-surface-hover cursor-pointer"
            >
              Close
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          {/* Informational Scope Banner */}
          <div className="p-3 bg-surface-subtle border border-border-default rounded-xl text-xs text-text-secondary flex items-start gap-2">
            <Shield className="w-4 h-4 text-brand-primary shrink-0 mt-0.5" />
            <span>
              <strong className="text-text-primary">Visibility overrides only:</strong> Reveal or hide a
              module entry point in navigation for a specific user. Backend RLS, RPC permissions, approvals,
              workflow transitions, and data scope remain authoritative and are unaffected.
            </span>
          </div>

          {!selectedUser ? (
            /* User Directory Selector View */
            <div className="space-y-3">
              <div className="relative">
                <Search className="w-4 h-4 text-text-muted absolute left-3 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  placeholder="Search user by name, role, group or account..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-9 pr-4 py-2 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-brand-primary"
                />
              </div>

              <div className="max-h-[52vh] overflow-y-auto space-y-2 pr-1">
                {isLoadingUsers ? (
                  <div className="py-12 text-center text-xs text-text-muted flex flex-col items-center gap-2">
                    <RefreshCw className="w-5 h-5 animate-spin text-brand-primary" />
                    <span>Loading user directory...</span>
                  </div>
                ) : filteredUsers.length === 0 ? (
                  <div className="py-12 text-center text-xs text-text-muted border border-dashed border-border-default rounded-2xl">
                    No active users found matching your search.
                  </div>
                ) : (
                  filteredUsers.map((user) => (
                    <button
                      key={user.id}
                      type="button"
                      onClick={() => setSelectedUser(user)}
                      className="w-full text-left p-3.5 rounded-xl border border-border-default hover:border-brand-primary hover:bg-surface-hover transition-all flex items-center justify-between group cursor-pointer bg-surface-primary"
                    >
                      <div className="flex items-center gap-3">
                        <div className="w-9 h-9 rounded-xl bg-surface-subtle group-hover:bg-brand-50 text-text-secondary group-hover:text-brand-900 flex items-center justify-center font-bold text-xs transition-colors shrink-0">
                          {user.fullName.slice(0, 2).toUpperCase()}
                        </div>
                        <div>
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-semibold text-text-primary">
                              {user.fullName}
                            </span>
                            <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-surface-subtle text-text-secondary border border-border-default">
                              {user.roleName}
                            </span>
                          </div>
                          <div className="text-xs text-text-muted mt-0.5 flex items-center gap-2">
                            <span>
                              Groups:{" "}
                              {user.groups.length > 0 ? user.groups.join(", ") : "Global Scope"}
                            </span>
                            {user.accounts.length > 0 && (
                              <>
                                <span>•</span>
                                <span>{user.accounts.length} Accounts</span>
                              </>
                            )}
                          </div>
                        </div>
                      </div>
                      <ChevronRight className="w-4 h-4 text-text-muted group-hover:text-brand-primary transition-colors" />
                    </button>
                  ))
                )}
              </div>
            </div>
          ) : (
            /* Selected User Override Matrix & Audit Trail View */
            <div className="space-y-4">
              <div className="flex items-center justify-between border-b border-border-default pb-3">
                <button
                  type="button"
                  onClick={() => setSelectedUser(null)}
                  className="px-3 py-1.5 rounded-xl border border-border-default bg-surface-primary hover:bg-surface-hover text-xs font-semibold text-text-primary transition flex items-center gap-1.5 cursor-pointer"
                >
                  <ArrowLeft className="w-3.5 h-3.5" />
                  <span>Back to User List</span>
                </button>

                <div className="flex items-center gap-2">
                  <div className="flex items-center gap-1 border border-border-default rounded-xl p-0.5 bg-surface-subtle">
                    <button
                      type="button"
                      onClick={() => setActiveTab("matrix")}
                      className={`px-3 py-1 text-xs font-semibold rounded-lg transition cursor-pointer flex items-center gap-1.5 ${
                        activeTab === "matrix"
                          ? "bg-surface-primary text-text-primary shadow-2xs font-bold"
                          : "text-text-secondary hover:text-text-primary"
                      }`}
                    >
                      <Sliders className="w-3.5 h-3.5" />
                      <span>Matrix</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => setActiveTab("audit")}
                      className={`px-3 py-1 text-xs font-semibold rounded-lg transition cursor-pointer flex items-center gap-1.5 ${
                        activeTab === "audit"
                          ? "bg-surface-primary text-text-primary shadow-2xs font-bold"
                          : "text-text-secondary hover:text-text-primary"
                      }`}
                    >
                      <History className="w-3.5 h-3.5" />
                      <span>Audit Trail</span>
                      {audit.length > 0 && (
                        <span className="px-1.5 py-0.2 rounded-full text-xs bg-surface-subtle text-text-muted">
                          {audit.length}
                        </span>
                      )}
                    </button>
                  </div>

                  <button
                    type="button"
                    onClick={() => {
                      refetchOverrides();
                      refetchAudit();
                    }}
                    disabled={isFetchingOverrides}
                    className="p-2 rounded-xl border border-border-default bg-surface-primary hover:bg-surface-hover text-text-secondary transition cursor-pointer disabled:opacity-50"
                    title="Refresh overrides"
                  >
                    <RefreshCw
                      className={`w-4 h-4 ${isFetchingOverrides ? "animate-spin text-brand-primary" : ""}`}
                    />
                  </button>
                </div>
              </div>

              {activeTab === "matrix" ? (
                <div className="max-h-[50vh] overflow-y-auto space-y-2 pr-1">
                  {isLoadingOverrides ? (
                    <div className="py-12 text-center text-xs text-text-muted flex flex-col items-center gap-2">
                      <RefreshCw className="w-5 h-5 animate-spin text-brand-primary" />
                      <span>Loading active module overrides...</span>
                    </div>
                  ) : (
                    <div className="divide-y divide-border-subtle border border-border-default rounded-2xl overflow-hidden bg-surface-primary">
                      {ACC_MODULE_KEYS.map((key) => {
                        const label = ACC_MODULE_LABELS[key] || key;
                        const roleDefault = getRoleModuleDefault(
                          selectedUser.roleName,
                          selectedUser.roleLevel,
                          key
                        );
                        const overrideState = (overrides as Record<string, string>)[key] || "inherit";
                        const effectiveVisible =
                          overrideState === "allow"
                            ? true
                            : overrideState === "deny"
                            ? false
                            : roleDefault;

                        return (
                          <div
                            key={key}
                            className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-surface-hover transition-colors"
                          >
                            <div className="space-y-1">
                              <div className="flex items-center gap-2">
                                <span className="text-sm font-semibold text-text-primary">{label}</span>
                                <span className="text-xs text-text-muted font-mono">({key})</span>
                                {overrideState !== "inherit" && (
                                  <span
                                    className={`px-2 py-0.5 rounded-full text-xs font-semibold  ${
                                      overrideState === "allow"
                                        ? "bg-surface-subtle text-text-primary border border-border-default"
                                        : "bg-danger-surface text-danger-text border border-danger-border"
                                    }`}
                                  >
                                    Override: {overrideState}
                                  </span>
                                )}
                              </div>
                              <div className="flex items-center gap-3 text-xs text-text-secondary">
                                <span>
                                  Role Default:{" "}
                                  <strong className="text-text-primary">
                                    {roleDefault ? "Visible" : "Hidden"}
                                  </strong>
                                </span>
                                <span>•</span>
                                <span>
                                  Effective:{" "}
                                  <strong
                                    className={effectiveVisible ? "text-text-primary" : "text-danger-text"}
                                  >
                                    {effectiveVisible ? "Visible" : "Hidden"}
                                  </strong>
                                </span>
                              </div>
                            </div>

                            {/* Action Segmented Controller */}
                            <div className="flex items-center gap-1.5 self-start sm:self-auto">
                              <button
                                type="button"
                                onClick={() => handleOpenPrompt(key, "allow", label)}
                                disabled={overrideState === "allow" || !isSuperAdmin}
                                className={`px-2.5 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1 transition cursor-pointer ${
                                  overrideState === "allow"
                                    ? "bg-brand-primary text-surface-primary shadow-2xs"
                                    : "bg-surface-subtle hover:bg-surface-hover text-text-secondary border border-border-default"
                                } disabled:opacity-50`}
                                title="Force module visible in navigation"
                              >
                                <Eye className="w-3.5 h-3.5" />
                                <span>Allow</span>
                              </button>

                              <button
                                type="button"
                                onClick={() => handleOpenPrompt(key, "deny", label)}
                                disabled={overrideState === "deny" || !isSuperAdmin}
                                className={`px-2.5 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1 transition cursor-pointer ${
                                  overrideState === "deny"
                                    ? "bg-danger text-surface-primary shadow-2xs"
                                    : "bg-surface-subtle hover:bg-surface-hover text-text-secondary border border-border-default"
                                } disabled:opacity-50`}
                                title="Force module hidden in navigation"
                              >
                                <EyeOff className="w-3.5 h-3.5" />
                                <span>Deny</span>
                              </button>

                              <button
                                type="button"
                                onClick={() => handleOpenPrompt(key, "inherit", label)}
                                disabled={overrideState === "inherit" || !isSuperAdmin}
                                className={`px-2.5 py-1.5 rounded-lg text-xs font-semibold flex items-center gap-1 transition cursor-pointer ${
                                  overrideState === "inherit"
                                    ? "bg-surface-subtle text-text-muted border border-border-default cursor-default"
                                    : "bg-surface-primary hover:bg-surface-hover text-text-primary border border-border-default"
                                } disabled:opacity-50`}
                                title="Restore role default (deletes override)"
                              >
                                <RotateCcw className="w-3.5 h-3.5" />
                                <span>Inherit</span>
                              </button>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              ) : (
                <div className="max-h-[50vh] overflow-y-auto space-y-2 pr-1">
                  {isLoadingAudit ? (
                    <div className="py-12 text-center text-xs text-text-muted flex flex-col items-center gap-2">
                      <RefreshCw className="w-5 h-5 animate-spin text-brand-primary" />
                      <span>Loading audit trail...</span>
                    </div>
                  ) : audit.length === 0 ? (
                    <div className="py-12 text-center text-xs text-text-muted border border-dashed border-border-default rounded-2xl">
                      No override changes recorded for this user yet.
                    </div>
                  ) : (
                    <div className="space-y-2">
                      {audit.map((item) => (
                        <div
                          key={item.id}
                          className="p-3.5 rounded-xl border border-border-default bg-surface-primary text-xs space-y-1.5"
                        >
                          <div className="flex items-center justify-between">
                            <span className="font-semibold text-text-primary">
                              {ACC_MODULE_LABELS[item.permissionKey] || item.permissionKey}
                            </span>
                            <span className="text-xs text-text-muted">
                              {new Date(item.createdAt).toLocaleString()}
                            </span>
                          </div>
                          <div className="flex items-center gap-2 text-xs text-text-secondary">
                            <span>
                              Transition:{" "}
                              <span className="font-mono text-text-muted">
                                {item.previousValue}
                              </span>{" "}
                              ➔{" "}
                              <span className="font-mono font-bold text-text-primary">
                                {item.newValue}
                              </span>
                            </span>
                            <span>•</span>
                            <span>Changed by: {item.changedByName || "Super Admin"}</span>
                          </div>
                          <div className="text-xs text-text-muted italic bg-surface-subtle p-2 rounded-lg border border-border-default">
                            &quot;{item.reason}&quot;
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </Modal>

      {/* Override Reason Prompt Sub-Modal */}
      <Modal
        isOpen={Boolean(promptData && selectedUser)}
        onClose={() => setPromptData(null)}
        title={
          promptData?.targetState === "inherit"
            ? `Restore Role Default for ${promptData.label}`
            : promptData?.targetState === "allow"
            ? `Force Visible: ${promptData?.label}`
            : `Force Hidden: ${promptData?.label}`
        }
        subtitle={
          selectedUser
            ? `Target User: ${selectedUser.fullName}. Audited reason required for Super Admin compliance.`
            : undefined
        }
        icon={Sliders}
        maxWidthClass="max-w-md"
        isSubmitting={setOverrideMutation.isPending}
        disableBackdropClick={setOverrideMutation.isPending}
        isDirty={isPromptDirty}
      >
        {promptData && selectedUser && (
          <form onSubmit={handleConfirmOverride} className="space-y-4">
            {actionError && (
              <div className="p-3 rounded-xl bg-danger-surface border border-danger-border text-danger-text text-xs flex items-center gap-2">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <div>
              <label className="block text-xs font-bold text-text-primary mb-1">
                Reason for Override *
              </label>
              <textarea
                required
                rows={3}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="e.g. temporary coverage during review period or CENCOM inspection"
                className="w-full p-2.5 text-xs rounded-xl border border-border-default bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-brand-primary"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-default">
              <button
                type="button"
                onClick={() => setPromptData(null)}
                className="px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover rounded-xl transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={setOverrideMutation.isPending}
                className="px-4 py-2 text-xs font-semibold text-surface-primary bg-brand-primary hover:bg-brand-primary-hover rounded-xl transition cursor-pointer disabled:opacity-50"
              >
                {setOverrideMutation.isPending ? "Saving..." : "Confirm Override"}
              </button>
            </div>
          </form>
        )}
      </Modal>
    </>
  );
}
