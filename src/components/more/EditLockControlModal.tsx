"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Clock,
  Lock,
  LockOpen,
  RefreshCw,
  ShieldAlert,
} from "lucide-react";
import {
  useEditLockStatus,
  useLockVacancyEditing,
  useUnlockVacancyEditing,
} from "@/lib/queries/more";
import { Modal } from "@/components/shared/Modal";

export interface EditLockControlModalProps {
  isOpen: boolean;
  onClose: () => void;
  canManageOverrides: boolean;
}

export function EditLockControlModal({
  isOpen,
  onClose,
  canManageOverrides,
}: EditLockControlModalProps) {
  const { data: status, isLoading, refetch, isFetching } = useEditLockStatus();
  const lockMutation = useLockVacancyEditing();
  const unlockMutation = useUnlockVacancyEditing();

  const [promptAction, setPromptAction] = useState<"lock" | "unlock" | null>(null);
  const [reason, setReason] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const isLocked = status?.isLocked ?? false;
  const isOverrideActive = status?.isOverrideActive ?? false;

  const handleOpenPrompt = (action: "lock" | "unlock") => {
    setPromptAction(action);
    setReason("");
    setErrorMessage(null);
  };

  const handleClosePrompt = () => {
    setPromptAction(null);
    setReason("");
    setErrorMessage(null);
  };

  const handleSubmitAction = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!reason.trim()) {
      setErrorMessage("Please enter an audited reason for this action.");
      return;
    }

    try {
      setErrorMessage(null);
      if (promptAction === "lock") {
        await lockMutation.mutateAsync({ reason });
      } else if (promptAction === "unlock") {
        await unlockMutation.mutateAsync({ reason });
      }
      handleClosePrompt();
      refetch();
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to update vacancy editing lock.";
      setErrorMessage(msg);
    }
  };

  const isActionPending = lockMutation.isPending || unlockMutation.isPending;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Edit Lock Control"
      subtitle="System-wide freeze period control for Vacancy & CENCOM cutoffs."
      icon={isLocked ? Lock : LockOpen}
      maxWidthClass="max-w-xl"
      isSubmitting={isActionPending}
      disableBackdropClick={isActionPending}
      isDirty={Boolean(reason)}
    >
      <div className="space-y-5">
        {/* Status Banner */}
        <div className="p-4 rounded-xl border border-border-default bg-surface-subtle flex items-start gap-3.5 text-text-primary">
          <div className="p-1 rounded-md bg-surface-base shrink-0 border border-border-default">
            {isLocked ? (
              <ShieldAlert className="w-5 h-5 text-text-secondary" />
            ) : isOverrideActive ? (
              <AlertTriangle className="w-5 h-5 text-text-secondary" />
            ) : (
              <LockOpen className="w-5 h-5 text-text-secondary" />
            )}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <span className="font-bold text-sm">
                {isOverrideActive
                  ? "Override Active — Normal Editing Restored"
                  : isLocked
                  ? "Vacancy Editing is Currently Locked"
                  : "Vacancy Editing is Unlocked"}
              </span>
              <span className="px-2 py-0.5 text-xs font-semibold rounded-full bg-surface-base text-text-secondary border border-border-default">
                {status?.lockType ?? "Default"}
              </span>
            </div>
            <p className="text-xs text-text-secondary mt-1">
              {isLocked
                ? "Standard users cannot modify requisitions, applicants, or vacancy fields during lock periods."
                : "All users with edit permissions can create, update, and manage vacancy allocations."}
            </p>
          </div>
        </div>

        {/* Details Table */}
        <div className="border border-border-default rounded-xl overflow-hidden text-sm">
          <div className="bg-surface-subtle px-4 py-2.5 font-semibold text-text-primary border-b border-border-default flex items-center justify-between text-xs">
            <span>Lock Governance Metadata</span>
            <button
              type="button"
              onClick={() => refetch()}
              disabled={isFetching}
              className="flex items-center gap-1 font-normal text-text-secondary hover:text-text-primary cursor-pointer"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${isFetching ? "animate-spin text-brand-primary" : ""}`} />
              <span>Refresh</span>
            </button>
          </div>
          <div className="divide-y divide-border-subtle text-text-secondary">
            <div className="flex px-4 py-2.5">
              <span className="w-32 font-medium text-text-muted">Schedule Window</span>
              <span className="flex-1 font-medium text-text-primary flex items-center gap-1.5">
                <Clock className="w-3.5 h-3.5 text-text-muted" />
                {status?.scheduleText || "Monday 5:00 PM to Tuesday 2:00 PM PH time"}
              </span>
            </div>
            <div className="flex px-4 py-2.5">
              <span className="w-32 font-medium text-text-muted">Locked By</span>
              <span className="flex-1 text-text-primary">{status?.lockedByName || "—"}</span>
            </div>
            <div className="flex px-4 py-2.5">
              <span className="w-32 font-medium text-text-muted">Lock Reason</span>
              <span className="flex-1 text-text-primary italic">
                {status?.reason ? `“${status.reason}”` : "—"}
              </span>
            </div>
            {isOverrideActive && (
              <>
                <div className="flex px-4 py-2.5 bg-surface-subtle/50">
                  <span className="w-32 font-medium text-text-primary">Override By</span>
                  <span className="flex-1 text-text-primary font-semibold">
                    {status?.overrideByName || "—"}
                  </span>
                </div>
                {status?.overrideUntil && (
                  <div className="flex px-4 py-2.5 bg-surface-subtle/50">
                    <span className="w-32 font-medium text-text-primary">Override Until</span>
                    <span className="flex-1 text-text-primary">
                      {new Date(status.overrideUntil).toLocaleString()}
                    </span>
                  </div>
                )}
              </>
            )}
            <div className="flex px-4 py-2.5">
              <span className="w-32 font-medium text-text-muted">Last Updated</span>
              <span className="flex-1 text-text-secondary">
                {status?.updatedAt ? new Date(status.updatedAt).toLocaleString() : "—"}
              </span>
            </div>
          </div>
        </div>

        {/* Prompt Section for reason input */}
        {promptAction && (
          <form onSubmit={handleSubmitAction} className="p-4 rounded-xl border border-brand-border bg-brand-subtle space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-text-primary flex items-center gap-1.5">
                <ShieldAlert className="w-4 h-4 text-brand-primary" />
                {promptAction === "lock" ? "Lock Vacancy Editing" : "Unlock / Override Vacancy Editing"}
              </span>
              <button
                type="button"
                onClick={handleClosePrompt}
                className="text-text-muted hover:text-text-primary text-xs cursor-pointer"
              >
                Cancel
              </button>
            </div>

            <div>
              <label className="block text-xs font-medium text-text-secondary mb-1">
                Audited Reason <span className="text-danger">*</span>
              </label>
              <textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder={
                  promptAction === "lock"
                    ? "e.g., Freezing edits for weekly CENCOM cutoff review..."
                    : "e.g., Emergency requisition update approved by Super Admin..."
                }
                rows={2}
                className="w-full text-xs px-3 py-2 border border-border-default rounded-lg focus:outline-hidden focus:border-brand-default focus:ring-1 focus:ring-brand-default bg-surface-base text-text-primary"
                autoFocus
              />
            </div>

            {errorMessage && (
              <p className="text-xs text-danger font-medium">{errorMessage}</p>
            )}

            <div className="flex justify-end gap-2 pt-1">
              <button
                type="button"
                onClick={handleClosePrompt}
                className="px-3 py-1.5 text-xs text-text-secondary bg-surface-base border border-border-default rounded-lg hover:bg-surface-hover cursor-pointer"
              >
                Dismiss
              </button>
              <button
                type="submit"
                disabled={isActionPending}
                className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer disabled:opacity-50 ${
                  promptAction === "lock"
                    ? "bg-danger-button text-danger-button-text hover:bg-danger-button-hover"
                    : "bg-brand-primary text-text-inverse hover:bg-brand-primary/90"
                }`}
              >
                {isActionPending ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : null}
                {promptAction === "lock" ? "Confirm Lock" : "Confirm Unlock / Override"}
              </button>
            </div>
          </form>
        )}

        {!canManageOverrides && (
          <div className="p-3 bg-surface-subtle border border-border-default text-text-secondary rounded-lg text-xs flex items-center gap-2">
            <AlertTriangle className="w-4 h-4 shrink-0 text-text-muted" />
            <span>You have read-only access. Only Super Admin and Head Admin can toggle edit locks.</span>
          </div>
        )}

        {/* Footer Actions */}
        <div className="flex items-center justify-between pt-4 border-t border-border-subtle">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-text-secondary bg-surface-base border border-border-default rounded-xl hover:bg-surface-hover transition-colors cursor-pointer"
          >
            Close
          </button>

          {canManageOverrides && !promptAction && (
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => handleOpenPrompt("lock")}
                disabled={isLoading || isLocked}
                className="px-4 py-2 text-xs font-semibold text-danger-button-text bg-danger-button hover:bg-danger-button-hover disabled:opacity-50 disabled:cursor-not-allowed rounded-xl transition-colors flex items-center gap-1.5 cursor-pointer"
              >
                <Lock className="w-3.5 h-3.5" />
                <span>Lock Now</span>
              </button>
              <button
                type="button"
                onClick={() => handleOpenPrompt("unlock")}
                disabled={isLoading}
                className="px-4 py-2 text-xs font-semibold text-text-inverse bg-brand-primary hover:bg-brand-primary/90 disabled:opacity-50 disabled:cursor-not-allowed rounded-xl transition-colors flex items-center gap-1.5 cursor-pointer"
              >
                <LockOpen className="w-3.5 h-3.5" />
                <span>Unlock / Override</span>
              </button>
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
