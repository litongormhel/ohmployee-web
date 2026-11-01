"use client";

import { useState } from "react";
import { Building2, Loader2, AlertCircle } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useGroupsQuery } from "@/lib/queries/users";
import { useCurrentUser } from "@/lib/auth";
import { createAccount } from "@/lib/queries/plantilla";
import { useQueryClient } from "@tanstack/react-query";

export interface AddAccountModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: (accountName: string) => void;
}

export function AddAccountModal({ isOpen, onClose, onSuccess }: AddAccountModalProps) {
  const [accountName, setAccountName] = useState("");
  const [accountCode, setAccountCode] = useState("");
  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const currentUser = useCurrentUser();
  const queryClient = useQueryClient();
  const { data: groups = [], isLoading: isGroupsLoading } = useGroupsQuery();

  const handleClose = () => {
    if (isSubmitting) return;
    setAccountName("");
    setAccountCode("");
    setSelectedGroupId("");
    setErrorMessage(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!accountName.trim()) {
      setErrorMessage("Account name is required.");
      return;
    }
    if (!selectedGroupId) {
      setErrorMessage("Please select a group for this account.");
      return;
    }

    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      await createAccount({
        accountName: accountName.trim(),
        accountCode: accountCode.trim().toUpperCase() || null,
        groupId: selectedGroupId,
        createdBy: currentUser?.profileId ?? currentUser?.authUserId,
      });

      // Invalidate relevant queries so directory updates immediately
      queryClient.invalidateQueries({ queryKey: ["plantilla", "allowed-accounts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla", "account-metrics"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["users-accounts-by-groups"] });

      const createdName = accountName.trim();
      handleClose();
      onSuccess?.(createdName);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Failed to create account. Please try again.";
      setErrorMessage(msg);
    } finally {
      setIsSubmitting(false);
    }
  };

  const isDirty = accountName.trim() !== "" || accountCode.trim() !== "" || selectedGroupId !== "";

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Create New Account"
      subtitle="Add a new client billing account to the Plantilla organizational directory."
      icon={Building2}
      maxWidthClass="max-w-lg"
      isDirty={isDirty}
      isSubmitting={isSubmitting}
      footer={
        <div className="flex items-center justify-end gap-3 w-full">
          <button
            type="button"
            onClick={handleClose}
            disabled={isSubmitting}
            className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={isSubmitting || !accountName.trim() || !selectedGroupId}
            className="inline-flex items-center justify-center gap-1.5 rounded-lg bg-brand-button px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover transition cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isSubmitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            <span>{isSubmitting ? "Creating Account..." : "Create Account"}</span>
          </button>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <div className="flex items-start gap-2.5 rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <p className="leading-relaxed">{errorMessage}</p>
          </div>
        )}

        {/* Account Name */}
        <div>
          <label className="block text-xs font-semibold text-text-primary mb-1">
            Account Name <span className="text-danger-text">*</span>
          </label>
          <input
            type="text"
            required
            placeholder="e.g. Watsons, SM Retail, Robinson's"
            value={accountName}
            onChange={(e) => setAccountName(e.target.value)}
            disabled={isSubmitting}
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none transition-colors"
          />
        </div>

        {/* Account Code */}
        <div>
          <label className="block text-xs font-semibold text-text-primary mb-1">
            Account Code <span className="text-text-muted font-normal">(Optional)</span>
          </label>
          <input
            type="text"
            placeholder="e.g. WTS, SMR, ROB"
            value={accountCode}
            onChange={(e) => setAccountCode(e.target.value.toUpperCase())}
            disabled={isSubmitting}
            maxLength={10}
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm font-mono uppercase text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none transition-colors"
          />
          <p className="mt-1 text-[11px] text-text-muted">
            Short identifier used for billing and system reference codes.
          </p>
        </div>

        {/* Group Selection */}
        <div>
          <label className="block text-xs font-semibold text-text-primary mb-1">
            Assigned Group <span className="text-danger-text">*</span>
          </label>
          {isGroupsLoading ? (
            <div className="flex items-center gap-2 py-2 text-xs text-text-secondary">
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
              <span>Fetching organizational groups...</span>
            </div>
          ) : (
            <select
              value={selectedGroupId}
              onChange={(e) => setSelectedGroupId(e.target.value)}
              disabled={isSubmitting}
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none transition-colors"
            >
              <option value="">Select a group...</option>
              {groups.map((group) => (
                <option key={group.id} value={group.id}>
                  {group.name}
                </option>
              ))}
            </select>
          )}
          <p className="mt-1 text-[11px] text-text-muted">
            The operational group that supervises and governs this account&apos;s headcount.
          </p>
        </div>
      </form>
    </Modal>
  );
}
