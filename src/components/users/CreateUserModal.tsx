"use client";

import { useState, useMemo } from "react";
import {
  Plus,
  CheckCircle,
  AlertTriangle,
  Check,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
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

  const isDirty = Boolean(
    fullName || email || selectedRoleId || selectedGroupIds.length || selectedAccountIds.length
  );
  const isBusy = upsertMutation.isPending;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Create New User"
      subtitle="Add an authorized user and configure their initial organizational scopes."
      icon={Plus}
      isSubmitting={isBusy}
      disableBackdropClick={isBusy}
      isDirty={isDirty}
      maxWidthClass="max-w-2xl"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        {errorMessage && (
          <div className="flex items-center gap-2 rounded-lg border border-danger-border bg-danger-subtle p-3 text-xs font-medium text-danger-text">
            <AlertTriangle className="h-4 w-4 shrink-0 text-danger-icon" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Basic Information */}
        <div className="space-y-3">
          <h3 className="text-xs font-bold text-text-muted">
            Basic Information
          </h3>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <label className="block text-xs font-semibold text-text-primary mb-1">
                Full Name <span className="text-danger-icon">*</span>
              </label>
              <input
                type="text"
                required
                placeholder="e.g. Juan Dela Cruz"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-text-primary mb-1">
                Email Address <span className="text-danger-icon">*</span>
              </label>
              <input
                type="email"
                required
                placeholder="juan@company.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-primary mb-1">
              Assign Role <span className="text-danger-icon">*</span>
            </label>
            <select
              required
              value={selectedRoleId}
              onChange={(e) => setSelectedRoleId(e.target.value)}
              className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
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
            <h3 className="text-xs font-bold text-text-muted">
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
                        ? "bg-brand-50 text-brand-700 border border-brand-200"
                        : "bg-surface-subtle text-text-secondary border border-border-default hover:bg-surface-hover"
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
            <h3 className="text-xs font-bold text-text-muted">
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
                  className="text-xs font-semibold text-danger-text hover:underline"
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
            <div className="flex items-center gap-2 rounded-lg border border-border-default bg-surface-subtle p-3 text-xs text-text-primary">
              <CheckCircle className="h-4 w-4 shrink-0 text-text-secondary" />
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
                className="w-full rounded-md border border-border-default bg-surface px-3 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500"
              />
              <div className="max-h-40 overflow-y-auto rounded-lg border border-border-default bg-surface-subtle divide-y divide-border-subtle">
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
            disabled={isBusy}
            className="rounded-md border border-border-default bg-surface px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={isBusy}
            className="inline-flex items-center gap-1.5 rounded-md bg-brand-500 px-4 py-2 text-xs font-bold text-white shadow-xs hover:bg-brand-600 disabled:opacity-50"
          >
            {isBusy ? "Creating..." : "Create User"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
