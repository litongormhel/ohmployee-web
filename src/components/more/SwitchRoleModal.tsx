"use client";

import { useState } from "react";
import {
  AlertCircle,
  RefreshCw,
  RotateCcw,
  Sliders,
} from "lucide-react";
import {
  useActiveActingSession,
  useScopeGroups,
  useScopeAccounts,
  useStartActingSession,
  useStopActingSession,
} from "@/lib/queries/more";
import { Modal } from "@/components/shared/Modal";

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
  // Selected parameters
  const [selectedRole, setSelectedRole] = useState<string>(ACTABLE_ROLES[0]);
  const [selectedGroupIds, setSelectedGroupIds] = useState<string[]>([]);
  const [selectedAccountIds, setSelectedAccountIds] = useState<string[]>([]);
  const [reasonInput, setReasonInput] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Queries
  const { data: activeSession } = useActiveActingSession();
  const { data: groups = [] } = useScopeGroups();
  const { data: accounts = [] } = useScopeAccounts(
    selectedGroupIds.length > 0 ? selectedGroupIds : undefined,
  );

  const startMutation = useStartActingSession();
  const stopMutation = useStopActingSession();

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
  const isDirty = Boolean(reasonInput || selectedGroupIds.length || selectedAccountIds.length);

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Switch Role (Testing Mode)"
      subtitle="Impersonate scoped operational roles to inspect UI capabilities and data filters without logging out."
      icon={Sliders}
      maxWidthClass="max-w-2xl"
      isSubmitting={isPending}
      disableBackdropClick={isPending}
      isDirty={isDirty}
    >
      <div className="space-y-5">
        {/* Current Active Acting Session Banner */}
        {activeSession && !activeSession.isExpired ? (
          <div className="px-4 py-3 rounded-xl border border-border-default bg-surface-subtle text-text-primary flex items-center justify-between text-xs font-semibold">
            <div className="flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0 text-brand-primary" />
              <span>
                Currently acting as <strong>{activeSession.actingRole}</strong>{" "}
                (Expires: {new Date(activeSession.expiresAt).toLocaleTimeString()})
              </span>
            </div>
            <button
              type="button"
              onClick={handleStopSession}
              disabled={isPending}
              className="px-3 py-1 rounded-lg bg-surface-base border border-border-default text-text-primary font-bold hover:bg-surface-hover shadow-2xs transition-colors flex items-center gap-1 cursor-pointer"
            >
              <RotateCcw className="w-3 h-3" />
              <span>Reset to Super Admin</span>
            </button>
          </div>
        ) : null}

        {errorMessage && (
          <div className="p-3 bg-danger-subtle border border-danger-border text-xs text-danger rounded-xl">
            {errorMessage}
          </div>
        )}

        {/* Quick Switch Chips */}
        <div>
          <label className="block text-xs font-bold text-text-secondary uppercase tracking-wider mb-2">
            Quick Role Switch
          </label>
          <div className="flex flex-wrap gap-2">
            {QUICK_ROLES.map((role) => (
              <button
                key={role}
                type="button"
                disabled={isPending}
                onClick={() => handleQuickSwitch(role)}
                className="px-3 py-1.5 rounded-xl border border-border-default hover:border-brand-default bg-surface-base hover:bg-surface-hover text-xs font-semibold text-text-primary transition-colors shadow-2xs cursor-pointer"
              >
                {role}
              </button>
            ))}
          </div>
        </div>

        <div className="border-t border-border-subtle pt-2" />

        {/* Scoped Role Impersonation Form */}
        <form onSubmit={handleStartSession} className="space-y-4">
          <div>
            <label className="block text-xs font-bold text-text-primary mb-1">
              Select Target Role
            </label>
            <select
              value={selectedRole}
              onChange={(e) => setSelectedRole(e.target.value)}
              className="w-full px-3 py-2 text-xs border border-border-default rounded-xl bg-surface-base text-text-primary focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default font-medium cursor-pointer"
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
            <label className="block text-xs font-bold text-text-primary mb-1">
              Limit to Group Scope (Optional)
            </label>
            <p className="text-xs text-text-muted mb-2">
              Leaving all unchecked simulates global group access for roles with broad permissions.
            </p>
            <div className="max-h-28 overflow-y-auto border border-border-default rounded-xl p-2.5 space-y-1.5 bg-surface-subtle/50">
              {groups.length === 0 ? (
                <div className="text-xs text-text-muted">Loading groups...</div>
              ) : (
                groups.map((g) => {
                  const isChecked = selectedGroupIds.includes(g.id);
                  return (
                    <label
                      key={g.id}
                      className="flex items-center gap-2 text-xs text-text-primary cursor-pointer hover:bg-surface-hover p-1 rounded-md"
                    >
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={() => handleToggleGroup(g.id)}
                        className="rounded-sm border-border-default text-brand-primary focus:ring-brand-default"
                      />
                      <span className="font-semibold">{g.groupName}</span>
                      <span className="text-xs text-text-muted">({g.groupCode})</span>
                    </label>
                  );
                })
              )}
            </div>
          </div>

          {/* Optional Account Scope Filter */}
          <div>
            <label className="block text-xs font-bold text-text-primary mb-1">
              Limit to Account Scope (Optional)
            </label>
            <div className="max-h-28 overflow-y-auto border border-border-default rounded-xl p-2.5 space-y-1.5 bg-surface-subtle/50">
              {accounts.length === 0 ? (
                <div className="text-xs text-text-muted">
                  {selectedGroupIds.length > 0 ? "No accounts found for selected groups." : "Select groups to filter accounts or leave empty."}
                </div>
              ) : (
                accounts.map((a) => {
                  const isChecked = selectedAccountIds.includes(a.id);
                  return (
                    <label
                      key={a.id}
                      className="flex items-center gap-2 text-xs text-text-primary cursor-pointer hover:bg-surface-hover p-1 rounded-md"
                    >
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={() => handleToggleAccount(a.id)}
                        className="rounded-sm border-border-default text-brand-primary focus:ring-brand-default"
                      />
                      <span>{a.accountName}</span>
                      {a.accountCode && (
                        <span className="text-xs text-text-muted font-mono">
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
            <label className="block text-xs font-bold text-text-primary mb-1">
              Reason for Impersonation (Required)
            </label>
            <input
              type="text"
              required
              value={reasonInput}
              onChange={(e) => setReasonInput(e.target.value)}
              placeholder="e.g. Verify Encoder CENCOM quota input permissions"
              className="w-full px-3 py-2 text-xs border border-border-default rounded-xl bg-surface-base text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default"
            />
          </div>

          <div className="flex items-center justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              disabled={isPending}
              className="px-4 py-2 text-xs font-medium text-text-secondary hover:bg-surface-hover rounded-xl border border-border-default transition-colors cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isPending}
              className="px-5 py-2 text-xs font-bold text-text-inverse bg-brand-primary hover:bg-brand-primary/90 rounded-xl shadow-xs transition-colors flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
            >
              {isPending && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
              <span>Start Acting Session</span>
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
