"use client";

import { useState, useMemo } from "react";
import {
  Plus,
  X,
  CheckCircle,
  AlertTriangle,
  Check,
} from "lucide-react";
import {
  useUpsertUser,
  useRolesQuery,
  useGroupsQuery,
  useAccountsByGroupsQuery,
  friendlyUserError,
} from "@/lib/queries/users";

export interface CreateUserModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

export function CreateUserModal({ isOpen, onClose, onSuccess }: CreateUserModalProps) {
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [selectedRoleId, setSelectedRoleId] = useState("");
  const [selectedGroupIds, setSelectedGroupIds] = useState<string[]>([]);
  const [selectedAccountIds, setSelectedAccountIds] = useState<string[]>([]);
  const [accountSearch, setAccountSearch] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const { data: roles = [] } = useRolesQuery();
  const { data: groups = [], isLoading: groupsLoading } = useGroupsQuery();
  const { data: accounts = [], isLoading: accountsLoading } = useAccountsByGroupsQuery(selectedGroupIds);

  const upsertMutation = useUpsertUser();

  const isGlobalHQSelected = useMemo(() => {
    return selectedGroupIds.some((gid) => {
      const g = groups.find((group) => group.id === gid);
      return g?.name.trim().toLowerCase() === "global hq";
    });
  }, [selectedGroupIds, groups]);

  // Filter accounts
  const selectableAccounts = useMemo(() => {
    if (isGlobalHQSelected) return accounts;
    return accounts.filter((acc) => selectedGroupIds.includes(acc.group_id));
  }, [accounts, selectedGroupIds, isGlobalHQSelected]);

  const filteredAccounts = useMemo(() => {
    if (!accountSearch.trim()) return selectableAccounts;
    const q = accountSearch.toLowerCase();
    return selectableAccounts.filter((a) => a.account_name.toLowerCase().includes(q));
  }, [selectableAccounts, accountSearch]);

  const toggleGroup = (groupId: string) => {
    setSelectedGroupIds((prev) => {
      const isSelected = prev.includes(groupId);
      const next = isSelected ? prev.filter((id) => id !== groupId) : [...prev, groupId];
      return next;
    });
  };

  const toggleAccount = (accountId: string) => {
    setSelectedAccountIds((prev) => {
      const isSelected = prev.includes(accountId);
      return isSelected ? prev.filter((id) => id !== accountId) : [...prev, accountId];
    });
  };

  const selectAllAccounts = () => {
    setSelectedAccountIds(selectableAccounts.map((a) => a.id));
  };

  const clearAllAccounts = () => {
    setSelectedAccountIds([]);
  };

  const handleReset = () => {
    setFullName("");
    setEmail("");
    setSelectedRoleId("");
    setSelectedGroupIds([]);
    setSelectedAccountIds([]);
    setAccountSearch("");
    setErrorMessage(null);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!fullName.trim()) {
      setErrorMessage("Please enter a full name.");
      return;
    }
    if (!email.trim() || !email.includes("@")) {
      setErrorMessage("Please enter a valid email address.");
      return;
    }
    if (!selectedRoleId) {
      setErrorMessage("Please select a role.");
      return;
    }

    try {
      await upsertMutation.mutateAsync({
        fullName: fullName.trim(),
        email: email.trim(),
        roleId: selectedRoleId,
        groupIds: selectedGroupIds,
        accountIds: isGlobalHQSelected ? [] : selectedAccountIds,
        existingProfileId: null, // Creation mode
      });

      handleReset();
      onSuccess?.();
      onClose();
    } catch (err) {
      setErrorMessage(friendlyUserError(err));
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/40 backdrop-blur-xs transition-opacity"
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Modal Dialog */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="create-user-modal-title"
        className="relative z-50 flex max-h-[90vh] w-full max-w-2xl flex-col rounded-xl border border-border-default bg-surface-base shadow-2xl"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-default px-6 py-4">
          <div className="flex items-center gap-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-50 text-blue-600">
              <Plus className="h-4 w-4" />
            </div>
            <div>
              <h2 id="create-user-modal-title" className="text-base font-bold text-text-primary">
                Create New User
              </h2>
              <p className="text-xs text-text-secondary">
                Add an authorized user and configure their initial organizational scopes.
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-md p-1.5 text-text-muted hover:bg-surface-muted hover:text-text-primary transition-colors"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto px-6 py-5 space-y-5">
          {errorMessage && (
            <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-xs font-medium text-red-700">
              <AlertTriangle className="h-4 w-4 shrink-0" />
              <span>{errorMessage}</span>
            </div>
          )}

          {/* Basic Information */}
          <div className="space-y-3">
            <h3 className="text-xs font-bold uppercase tracking-wider text-text-muted">
              Basic Information
            </h3>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div>
                <label className="block text-xs font-semibold text-text-primary mb-1">
                  Full Name <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Juan Dela Cruz"
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                />
              </div>
              <div>
                <label className="block text-xs font-semibold text-text-primary mb-1">
                  Email Address <span className="text-red-500">*</span>
                </label>
                <input
                  type="email"
                  required
                  placeholder="juan@company.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-text-primary mb-1">
                Assign Role <span className="text-red-500">*</span>
              </label>
              <select
                required
                value={selectedRoleId}
                onChange={(e) => setSelectedRoleId(e.target.value)}
                className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
              >
                <option value="">Select a role...</option>
                {roles.map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Group Scope Assignment */}
          <div className="space-y-3 border-t border-border-subtle pt-4">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold uppercase tracking-wider text-text-muted">
                Group Scopes
              </h3>
              <span className="text-[11px] text-text-secondary">
                {selectedGroupIds.length} selected
              </span>
            </div>
            <p className="text-xs text-text-secondary">
              Selecting &quot;Global HQ&quot; will grant access across all organizational accounts.
            </p>
            <div className="flex flex-wrap gap-2 max-h-36 overflow-y-auto p-1">
              {groupsLoading ? (
                <span className="text-xs text-text-muted">Loading groups...</span>
              ) : (
                groups.map((group) => {
                  const isSelected = selectedGroupIds.includes(group.id);
                  return (
                    <button
                      key={group.id}
                      type="button"
                      onClick={() => toggleGroup(group.id)}
                      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold transition-colors ${
                        isSelected
                          ? "bg-blue-100 text-blue-700 border border-blue-300"
                          : "bg-surface-muted text-text-secondary border border-border-default hover:bg-surface-hover"
                      }`}
                    >
                      {isSelected && <Check className="h-3 w-3" />}
                      {group.name}
                    </button>
                  );
                })
              )}
            </div>
          </div>

          {/* Account Scope Assignment */}
          <div className="space-y-3 border-t border-border-subtle pt-4">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold uppercase tracking-wider text-text-muted">
                Account Scopes
              </h3>
              {!isGlobalHQSelected && selectedGroupIds.length > 0 && (
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={selectAllAccounts}
                    className="text-xs font-semibold text-brand-600 hover:underline"
                  >
                    Select All
                  </button>
                  <span className="text-text-muted">•</span>
                  <button
                    type="button"
                    onClick={clearAllAccounts}
                    className="text-xs font-semibold text-red-600 hover:underline"
                  >
                    Clear All
                  </button>
                </div>
              )}
            </div>

            {selectedGroupIds.length === 0 ? (
              <div className="rounded-lg border border-dashed border-border-default p-4 text-center text-xs text-text-muted">
                Select one or more group scopes above to configure specific account access.
              </div>
            ) : isGlobalHQSelected ? (
              <div className="flex items-center gap-2 rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-800">
                <CheckCircle className="h-4 w-4 shrink-0 text-blue-600" />
                <span>
                  <strong>Global HQ Selected:</strong> User automatically inherits all active accounts across all groups.
                </span>
              </div>
            ) : (
              <div className="space-y-2">
                <input
                  type="text"
                  placeholder="Filter accounts..."
                  value={accountSearch}
                  onChange={(e) => setAccountSearch(e.target.value)}
                  className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500"
                />
                <div className="max-h-40 overflow-y-auto rounded-lg border border-border-default bg-surface-muted/30 divide-y divide-border-subtle">
                  {accountsLoading ? (
                    <div className="p-3 text-center text-xs text-text-muted">Loading accounts...</div>
                  ) : filteredAccounts.length === 0 ? (
                    <div className="p-3 text-center text-xs text-text-muted">No matching accounts found.</div>
                  ) : (
                    filteredAccounts.map((acc) => {
                      const isChecked = selectedAccountIds.includes(acc.id);
                      return (
                        <label
                          key={acc.id}
                          className="flex items-center gap-2.5 px-3 py-2 text-xs hover:bg-surface-hover cursor-pointer"
                        >
                          <input
                            type="checkbox"
                            checked={isChecked}
                            onChange={() => toggleAccount(acc.id)}
                            className="rounded border-border-default text-brand-600 focus:ring-brand-500"
                          />
                          <span className="font-medium text-text-primary">{acc.account_name}</span>
                        </label>
                      );
                    })
                  )}
                </div>
                <p className="text-[11px] text-text-muted">
                  Leaving account selections empty grants access to all accounts within selected groups.
                </p>
              </div>
            )}
          </div>

          {/* Footer Actions */}
          <div className="flex items-center justify-end gap-3 border-t border-border-default pt-4">
            <button
              type="button"
              onClick={onClose}
              disabled={upsertMutation.isPending}
              className="rounded-md border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={upsertMutation.isPending}
              className="inline-flex items-center gap-1.5 rounded-md bg-blue-600 px-4 py-2 text-xs font-bold text-white shadow-xs hover:bg-blue-700 disabled:opacity-50"
            >
              {upsertMutation.isPending ? "Creating..." : "Create User"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
