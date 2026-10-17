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
  X,
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

  if (!isOpen) return null;

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

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-in fade-in duration-200">
      <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-4xl max-h-[90vh] flex flex-col overflow-hidden">
        {/* Header Strip */}
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50/50">
          <div className="flex items-center gap-3">
            {selectedUser && (
              <button
                type="button"
                onClick={() => setSelectedUser(null)}
                className="p-1.5 hover:bg-slate-200/80 rounded-lg text-slate-500 hover:text-slate-800 transition cursor-pointer"
                title="Back to user list"
              >
                <ArrowLeft className="w-4 h-4" />
              </button>
            )}
            <div className="w-9 h-9 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center font-bold">
              <Sliders className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-base font-bold text-slate-900">
                  {selectedUser ? selectedUser.fullName : "Access Control Center"}
                </h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-purple-100 text-purple-800 uppercase tracking-wider">
                  Module Overrides
                </span>
              </div>
              <p className="text-xs text-slate-500">
                {selectedUser
                  ? `${selectedUser.roleName} (Level ${selectedUser.roleLevel}) • Override navigation visibility`
                  : "Super Admin tool to grant or hide module navigation visibility per user"}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {selectedUser && (
              <button
                type="button"
                onClick={() => {
                  refetchOverrides();
                  refetchAudit();
                }}
                disabled={isFetchingOverrides}
                className="p-2 hover:bg-slate-100 rounded-lg text-slate-500 hover:text-slate-700 transition cursor-pointer"
                title="Refresh user data"
              >
                <RefreshCw
                  className={`w-4 h-4 ${isFetchingOverrides ? "animate-spin text-purple-600" : ""}`}
                />
              </button>
            )}
            <button
              type="button"
              onClick={onClose}
              className="p-2 hover:bg-slate-100 rounded-lg text-slate-400 hover:text-slate-600 transition cursor-pointer"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Informational Banner */}
        <div className="px-6 py-2.5 bg-blue-50/70 border-b border-blue-100 text-[11px] text-blue-900 flex items-start gap-2">
          <Shield className="w-4 h-4 text-blue-600 shrink-0 mt-0.5" />
          <span>
            <strong>Visibility overrides only:</strong> They reveal or hide a module entry point in
            navigation for a specific user. Backend RLS, RPC permissions, approvals, workflow
            transitions, and data scope remain authoritative and are unaffected.
          </span>
        </div>

        {/* Main Body */}
        {!selectedUser ? (
          /* User Selector View */
          <div className="p-6 flex-1 flex flex-col overflow-hidden">
            <div className="mb-4 relative">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                placeholder="Search user by name, role, group or account..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-9 pr-4 py-2 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-purple-500 focus:ring-1 focus:ring-purple-500"
              />
            </div>

            <div className="flex-1 overflow-y-auto space-y-2 pr-1">
              {isLoadingUsers ? (
                <div className="py-12 text-center text-xs text-slate-400 flex flex-col items-center gap-2">
                  <RefreshCw className="w-5 h-5 animate-spin text-purple-600" />
                  <span>Loading user directory...</span>
                </div>
              ) : filteredUsers.length === 0 ? (
                <div className="py-12 text-center text-xs text-slate-400">
                  No active users found matching your search.
                </div>
              ) : (
                filteredUsers.map((user) => (
                  <button
                    key={user.id}
                    type="button"
                    onClick={() => setSelectedUser(user)}
                    className="w-full text-left p-3.5 rounded-xl border border-slate-200/80 hover:border-purple-300 hover:bg-purple-50/30 transition-all flex items-center justify-between group cursor-pointer"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 rounded-xl bg-slate-100 group-hover:bg-purple-100 text-slate-700 group-hover:text-purple-700 flex items-center justify-center font-bold text-xs transition-colors shrink-0">
                        {user.fullName.slice(0, 2).toUpperCase()}
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-xs font-bold text-slate-900 group-hover:text-purple-950">
                            {user.fullName}
                          </span>
                          <span className="px-2 py-0.5 rounded-full text-[9px] font-bold uppercase tracking-wider bg-slate-100 text-slate-700">
                            {user.roleName}
                          </span>
                        </div>
                        <div className="text-[11px] text-slate-500 mt-0.5 flex items-center gap-2">
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
                    <ChevronRight className="w-4 h-4 text-slate-300 group-hover:text-purple-600 transition-colors" />
                  </button>
                ))
              )}
            </div>
          </div>
        ) : (
          /* User Override Matrix & Audit View */
          <div className="flex-1 flex flex-col overflow-hidden">
            {/* View Sub-Tabs */}
            <div className="px-6 border-b border-slate-200 flex items-center gap-4 bg-white">
              <button
                type="button"
                onClick={() => setActiveTab("matrix")}
                className={`py-3 text-xs font-bold border-b-2 transition cursor-pointer flex items-center gap-1.5 ${
                  activeTab === "matrix"
                    ? "border-purple-600 text-purple-700"
                    : "border-transparent text-slate-500 hover:text-slate-800"
                }`}
              >
                <Sliders className="w-3.5 h-3.5" />
                <span>Module Visibility Matrix</span>
              </button>
              <button
                type="button"
                onClick={() => setActiveTab("audit")}
                className={`py-3 text-xs font-bold border-b-2 transition cursor-pointer flex items-center gap-1.5 ${
                  activeTab === "audit"
                    ? "border-purple-600 text-purple-700"
                    : "border-transparent text-slate-500 hover:text-slate-800"
                }`}
              >
                <History className="w-3.5 h-3.5" />
                <span>Audit History</span>
                {audit.length > 0 && (
                  <span className="px-1.5 py-0.2 rounded-full text-[10px] bg-slate-100 text-slate-700">
                    {audit.length}
                  </span>
                )}
              </button>
            </div>

            {/* Matrix View Content */}
            {activeTab === "matrix" ? (
              <div className="p-6 flex-1 overflow-y-auto space-y-3">
                {isLoadingOverrides ? (
                  <div className="py-12 text-center text-xs text-slate-400 flex flex-col items-center gap-2">
                    <RefreshCw className="w-5 h-5 animate-spin text-purple-600" />
                    <span>Loading active module overrides...</span>
                  </div>
                ) : (
                  <div className="divide-y divide-slate-100 border border-slate-200 rounded-2xl overflow-hidden bg-white">
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
                          className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-slate-50/50 transition-colors"
                        >
                          <div className="space-y-1">
                            <div className="flex items-center gap-2">
                              <span className="text-xs font-bold text-slate-900">{label}</span>
                              <span className="text-[10px] text-slate-400 font-mono">({key})</span>
                              {overrideState !== "inherit" && (
                                <span
                                  className={`px-2 py-0.2 rounded-full text-[9px] font-bold uppercase tracking-wider ${
                                    overrideState === "allow"
                                      ? "bg-emerald-100 text-emerald-800"
                                      : "bg-rose-100 text-rose-800"
                                  }`}
                                >
                                  Override: {overrideState}
                                </span>
                              )}
                            </div>
                            <div className="flex items-center gap-3 text-[11px] text-slate-500">
                              <span>
                                Role Default:{" "}
                                <strong
                                  className={roleDefault ? "text-emerald-700" : "text-slate-500"}
                                >
                                  {roleDefault ? "Visible" : "Hidden"}
                                </strong>
                              </span>
                              <span>•</span>
                              <span>
                                Effective:{" "}
                                <strong
                                  className={
                                    effectiveVisible ? "text-purple-700" : "text-rose-700"
                                  }
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
                                  ? "bg-emerald-600 text-white shadow-2xs"
                                  : "bg-slate-100 hover:bg-slate-200 text-slate-700"
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
                                  ? "bg-rose-600 text-white shadow-2xs"
                                  : "bg-slate-100 hover:bg-slate-200 text-slate-700"
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
                                  ? "bg-slate-200 text-slate-500 cursor-default"
                                  : "bg-purple-50 hover:bg-purple-100 text-purple-700 border border-purple-200"
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
              /* Audit History View Content */
              <div className="p-6 flex-1 overflow-y-auto space-y-3">
                {isLoadingAudit ? (
                  <div className="py-12 text-center text-xs text-slate-400 flex flex-col items-center gap-2">
                    <RefreshCw className="w-5 h-5 animate-spin text-purple-600" />
                    <span>Loading audit trail...</span>
                  </div>
                ) : audit.length === 0 ? (
                  <div className="py-12 text-center text-xs text-slate-400">
                    No override changes recorded for this user yet.
                  </div>
                ) : (
                  <div className="space-y-2">
                    {audit.map((item) => (
                      <div
                        key={item.id}
                        className="p-3.5 rounded-xl border border-slate-200 bg-white text-xs space-y-1.5"
                      >
                        <div className="flex items-center justify-between">
                          <span className="font-bold text-slate-900">
                            {ACC_MODULE_LABELS[item.permissionKey] || item.permissionKey}
                          </span>
                          <span className="text-[10px] text-slate-400">
                            {new Date(item.createdAt).toLocaleString()}
                          </span>
                        </div>
                        <div className="flex items-center gap-2 text-[11px] text-slate-600">
                          <span>
                            Transition:{" "}
                            <span className="font-mono uppercase text-slate-500">
                              {item.previousValue}
                            </span>{" "}
                            ➔{" "}
                            <span className="font-mono uppercase font-bold text-purple-700">
                              {item.newValue}
                            </span>
                          </span>
                          <span>•</span>
                          <span>Changed by: {item.changedByName || "Super Admin"}</span>
                        </div>
                        <div className="text-[11px] text-slate-500 italic bg-slate-50 p-2 rounded-lg border border-slate-100">
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

        {/* Footer */}
        <div className="px-6 py-3 border-t border-slate-200 bg-slate-50/70 flex items-center justify-between text-xs text-slate-500">
          <span>Target: module_visibility_overrides</span>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-semibold text-slate-700 bg-white hover:bg-slate-100 border border-slate-200 rounded-xl transition cursor-pointer"
          >
            Close
          </button>
        </div>
      </div>

      {/* Override Reason Prompt Modal */}
      {promptData && selectedUser && (
        <div className="fixed inset-0 z-60 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl shadow-xl border border-slate-200 w-full max-w-md p-5 space-y-4">
            <div>
              <h3 className="text-sm font-bold text-slate-900">
                {promptData.targetState === "inherit"
                  ? `Restore Role Default for ${promptData.label}`
                  : promptData.targetState === "allow"
                  ? `Force Visible: ${promptData.label}`
                  : `Force Hidden: ${promptData.label}`}
              </h3>
              <p className="text-xs text-slate-500 mt-0.5">
                Target User: <strong className="text-slate-800">{selectedUser.fullName}</strong>. A
                reason is required for Super Admin audit compliance.
              </p>
            </div>

            {actionError && (
              <div className="p-3 rounded-xl bg-rose-50 border border-rose-200 text-rose-800 text-xs flex items-center gap-2">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <form onSubmit={handleConfirmOverride} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Reason for Override *
                </label>
                <textarea
                  required
                  rows={3}
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. temporary coverage during review period or CENCOM inspection"
                  className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-white focus:outline-hidden focus:border-purple-500 focus:ring-1 focus:ring-purple-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setPromptData(null)}
                  className="px-3.5 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={setOverrideMutation.isPending}
                  className="px-4 py-2 text-xs font-bold text-white bg-purple-600 hover:bg-purple-700 rounded-xl transition cursor-pointer disabled:opacity-50"
                >
                  {setOverrideMutation.isPending ? "Saving..." : "Confirm Override"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
