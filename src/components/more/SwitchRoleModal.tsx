"use client";

import { useMemo, useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  Lock,
  RefreshCw,
  RotateCcw,
  Sliders,
  UserCheck,
  Users2,
  X,
} from "lucide-react";
import {
  useActiveActingSession,
  useScopeGroups,
  useScopeAccounts,
  useStartActingSession,
  useStopActingSession,
} from "@/lib/queries/more";
import { useCurrentUser } from "@/lib/auth";

export interface SwitchRoleModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const QUICK_ROLES = [
  "Head Admin",
  "Encoder",
  "Operations Manager",
  "HRCO",
  "HR Personnel",
  "Recruitment Team",
  "Viewer",
] as const;

const ACTABLE_ROLES = [
  "Head Admin",
  "Encoder",
  "Operations Manager",
  "HRCO",
  "ATL",
  "TL",
  "HR Personnel",
  "Recruitment Team",
  "Back Office",
  "Viewer",
] as const;

export function SwitchRoleModal({ isOpen, onClose }: SwitchRoleModalProps) {
  const currentUser = useCurrentUser();

  // Selected parameters
  const [selectedRole, setSelectedRole] = useState<string>(ACTABLE_ROLES[0]);
  const [selectedGroupIds, setSelectedGroupIds] = useState<string[]>([]);
  const [selectedAccountIds, setSelectedAccountIds] = useState<string[]>([]);
  const [reasonInput, setReasonInput] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Queries
  const { data: activeSession, isLoading: sessionLoading } = useActiveActingSession();
  const { data: groups = [] } = useScopeGroups();
  const { data: accounts = [] } = useScopeAccounts(
    selectedGroupIds.length > 0 ? selectedGroupIds : undefined,
  );

  const startMutation = useStartActingSession();
  const stopMutation = useStopActingSession();

  if (!isOpen) return null;

  const handleToggleGroup = (groupId: string) => {
    setSelectedGroupIds((prev) => {
      const exists = prev.includes(groupId);
      const next = exists ? prev.filter((id) => id !== groupId) : [...prev, groupId];
      return next;
    });
  };

  const handleToggleAccount = (accountId: string) => {
    setSelectedAccountIds((prev) =>
      prev.includes(accountId)
        ? prev.filter((id) => id !== accountId)
        : [...prev, accountId],
    );
  };

  const handleQuickSwitch = async (role: string) => {
    setErrorMessage(null);
    try {
      await startMutation.mutateAsync({
        role,
        reason: `Quick switch to ${role} via Web More Panel`,
      });
      onClose();
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Failed to switch role.",
      );
    }
  };

  const handleStartSession = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!reasonInput.trim()) {
      setErrorMessage("Please enter an operational justification reason.");
      return;
    }

    setErrorMessage(null);
    try {
      await startMutation.mutateAsync({
        role: selectedRole,
        groupIds: selectedGroupIds,
        accountIds: selectedAccountIds,
        reason: reasonInput.trim(),
      });
      setReasonInput("");
      onClose();
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Failed to start acting session.",
      );
    }
  };

  const handleStopSession = async () => {
    setErrorMessage(null);
    try {
      await stopMutation.mutateAsync();
      onClose();
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Failed to revert to default role.",
      );
    }
  };

  const isPending = startMutation.isPending || stopMutation.isPending;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="switch-role-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/70 backdrop-blur-xs animate-in fade-in duration-200"
    >
      <div className="relative w-full max-w-2xl bg-white rounded-2xl shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4.5 border-b border-slate-200 bg-slate-50/80">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-purple-100 text-purple-700 flex items-center justify-center">
              <Sliders className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 id="switch-role-title" className="text-base font-bold text-slate-900 leading-tight">
                  Switch Role (Testing Mode)
                </h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-100 text-rose-800">
                  SUPER ADMIN TOOL
                </span>
              </div>
              <p className="text-xs text-slate-500">
                Impersonate scoped operational roles to inspect UI capabilities and data filters without logging out
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-200/60 transition-colors"
            aria-label="Close modal"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Current Active Acting Session Banner */}
        {activeSession && !activeSession.isExpired ? (
          <div className="px-6 py-3 bg-amber-500 text-slate-950 flex items-center justify-between text-xs font-semibold">
            <div className="flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0 text-slate-950" />
              <span>
                Currently acting as <strong>{activeSession.actingRole}</strong>{" "}
                (Expires: {new Date(activeSession.expiresAt).toLocaleTimeString()})
              </span>
            </div>
            <button
              type="button"
              onClick={handleStopSession}
              disabled={isPending}
              className="px-3 py-1 rounded-lg bg-white text-slate-900 font-bold hover:bg-slate-100 shadow-xs transition-colors flex items-center gap-1"
            >
              <RotateCcw className="w-3 h-3" />
              <span>Reset to Super Admin</span>
            </button>
          </div>
        ) : null}

        {/* Form Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-5">
          {errorMessage && (
            <div className="p-3 bg-rose-50 border border-rose-200 text-xs text-rose-700 rounded-xl">
              {errorMessage}
            </div>
          )}

          {/* Quick Switch Chips */}
          <div>
            <label className="block text-xs font-bold text-slate-700 uppercase tracking-wider mb-2">
              Quick Role Switch
            </label>
            <div className="flex flex-wrap gap-2">
              {QUICK_ROLES.map((role) => (
                <button
                  key={role}
                  type="button"
                  disabled={isPending}
                  onClick={() => handleQuickSwitch(role)}
                  className="px-3 py-1.5 rounded-xl border border-slate-200 hover:border-purple-400 bg-white hover:bg-purple-50 text-xs font-semibold text-slate-700 transition-colors shadow-2xs"
                >
                  {role}
                </button>
              ))}
            </div>
          </div>

          <div className="border-t border-slate-200 pt-4" />

          {/* Scoped Role Impersonation Form */}
          <form onSubmit={handleStartSession} className="space-y-4">
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                Select Target Role
              </label>
              <select
                value={selectedRole}
                onChange={(e) => setSelectedRole(e.target.value)}
                className="w-full px-3 py-2 text-xs border border-slate-300 rounded-xl bg-white focus:outline-hidden focus:ring-2 focus:ring-purple-500 font-medium"
              >
                {ACTABLE_ROLES.map((role) => (
                  <option key={role} value={role}>
                    {role}
                  </option>
                ))}
              </select>
            </div>

            {/* Optional Group Scope Filter */}
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                Limit to Group Scope (Optional)
              </label>
              <p className="text-[11px] text-slate-500 mb-2">
                Leaving all unchecked simulates global group access for roles with broad permissions.
              </p>
              <div className="max-h-28 overflow-y-auto border border-slate-200 rounded-xl p-2.5 space-y-1.5 bg-slate-50/50">
                {groups.length === 0 ? (
                  <div className="text-[11px] text-slate-400">Loading groups...</div>
                ) : (
                  groups.map((g) => {
                    const isChecked = selectedGroupIds.includes(g.id);
                    return (
                      <label
                        key={g.id}
                        className="flex items-center gap-2 text-xs text-slate-700 cursor-pointer hover:bg-slate-100 p-1 rounded-md"
                      >
                        <input
                          type="checkbox"
                          checked={isChecked}
                          onChange={() => handleToggleGroup(g.id)}
                          className="rounded text-purple-600 focus:ring-purple-500"
                        />
                        <span className="font-semibold">{g.groupName}</span>
                        <span className="text-[10px] text-slate-400">({g.groupCode})</span>
                      </label>
                    );
                  })
                )}
              </div>
            </div>

            {/* Optional Account Scope Filter */}
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                Limit to Account Scope (Optional)
              </label>
              <div className="max-h-28 overflow-y-auto border border-slate-200 rounded-xl p-2.5 space-y-1.5 bg-slate-50/50">
                {accounts.length === 0 ? (
                  <div className="text-[11px] text-slate-400">
                    {selectedGroupIds.length > 0 ? "No accounts found for selected groups." : "Select groups to filter accounts or leave empty."}
                  </div>
                ) : (
                  accounts.map((a) => {
                    const isChecked = selectedAccountIds.includes(a.id);
                    return (
                      <label
                        key={a.id}
                        className="flex items-center gap-2 text-xs text-slate-700 cursor-pointer hover:bg-slate-100 p-1 rounded-md"
                      >
                        <input
                          type="checkbox"
                          checked={isChecked}
                          onChange={() => handleToggleAccount(a.id)}
                          className="rounded text-purple-600 focus:ring-purple-500"
                        />
                        <span>{a.accountName}</span>
                        {a.accountCode && (
                          <span className="text-[10px] text-slate-400 font-mono">
                            [{a.accountCode}]
                          </span>
                        )}
                      </label>
                    );
                  })
                )}
              </div>
            </div>

            {/* Audited Reason */}
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                Reason for Impersonation (Required)
              </label>
              <input
                type="text"
                required
                value={reasonInput}
                onChange={(e) => setReasonInput(e.target.value)}
                placeholder="e.g. Verify Encoder CENCOM quota input permissions"
                className="w-full px-3 py-2 text-xs border border-slate-300 rounded-xl focus:outline-hidden focus:ring-2 focus:ring-purple-500"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isPending}
                className="px-5 py-2 text-xs font-bold text-white bg-purple-600 hover:bg-purple-700 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
              >
                {isPending && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                <span>Start Acting Session</span>
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
