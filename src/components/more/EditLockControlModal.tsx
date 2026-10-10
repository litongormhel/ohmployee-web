"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Clock,
  Lock,
  LockOpen,
  RefreshCw,
  ShieldAlert,
  X,
} from "lucide-react";
import {
  useEditLockStatus,
  useLockVacancyEditing,
  useUnlockVacancyEditing,
} from "@/lib/queries/more";

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

  if (!isOpen) return null;

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
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="edit-lock-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/60 backdrop-blur-xs animate-in fade-in duration-200"
    >
      <div className="relative w-full max-w-xl bg-white rounded-2xl shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4.5 border-b border-slate-200 bg-slate-50/80">
          <div className="flex items-center gap-3">
            <div
              className={`w-9 h-9 rounded-xl flex items-center justify-center ${
                isLocked
                  ? "bg-rose-100 text-rose-700"
                  : isOverrideActive
                  ? "bg-amber-100 text-amber-700"
                  : "bg-emerald-100 text-emerald-700"
              }`}
            >
              {isLocked ? <Lock className="w-5 h-5" /> : <LockOpen className="w-5 h-5" />}
            </div>
            <div>
              <h2 id="edit-lock-title" className="text-base font-bold text-slate-900 leading-tight">
                Edit Lock Control
              </h2>
              <p className="text-xs text-slate-500">
                System-wide freeze period control for Vacancy & CENCOM cutoffs
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

        {/* Content */}
        <div className="p-6 overflow-y-auto space-y-5 flex-1">
          {/* Status Banner */}
          <div
            className={`p-4 rounded-xl border flex items-start gap-3.5 ${
              isLocked
                ? "bg-rose-50/70 border-rose-200/80 text-rose-900"
                : isOverrideActive
                ? "bg-amber-50/70 border-amber-200/80 text-amber-900"
                : "bg-emerald-50/70 border-emerald-200/80 text-emerald-900"
            }`}
          >
            <div className="p-1 rounded-md bg-white/70 shrink-0">
              {isLocked ? (
                <ShieldAlert className="w-5 h-5 text-rose-600" />
              ) : isOverrideActive ? (
                <AlertTriangle className="w-5 h-5 text-amber-600" />
              ) : (
                <LockOpen className="w-5 h-5 text-emerald-600" />
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
                <span
                  className={`px-2 py-0.5 text-xs font-semibold rounded-full uppercase tracking-wider ${
                    isLocked
                      ? "bg-rose-200/80 text-rose-800"
                      : isOverrideActive
                      ? "bg-amber-200/80 text-amber-800"
                      : "bg-emerald-200/80 text-emerald-800"
                  }`}
                >
                  {status?.lockType ?? "Default"}
                </span>
              </div>
              <p className="text-xs text-slate-600 mt-1">
                {isLocked
                  ? "Standard users cannot modify requisitions, applicants, or vacancy fields during lock periods."
                  : "All users with edit permissions can create, update, and manage vacancy allocations."}
              </p>
            </div>
          </div>

          {/* Details Table */}
          <div className="border border-slate-200 rounded-xl overflow-hidden text-xs">
            <div className="bg-slate-50 px-4 py-2.5 font-semibold text-slate-700 border-b border-slate-200 flex items-center justify-between">
              <span>Lock Governance Metadata</span>
              <button
                type="button"
                onClick={() => refetch()}
                disabled={isFetching}
                className="flex items-center gap-1 text-[11px] font-normal text-slate-500 hover:text-slate-800"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${isFetching ? "animate-spin" : ""}`} />
                <span>Refresh</span>
              </button>
            </div>
            <div className="divide-y divide-slate-100 text-slate-700">
              <div className="flex px-4 py-2.5">
                <span className="w-32 font-medium text-slate-500">Schedule Window</span>
                <span className="flex-1 font-medium text-slate-900 flex items-center gap-1.5">
                  <Clock className="w-3.5 h-3.5 text-slate-400" />
                  {status?.scheduleText || "Monday 5:00 PM to Tuesday 2:00 PM PH time"}
                </span>
              </div>
              <div className="flex px-4 py-2.5">
                <span className="w-32 font-medium text-slate-500">Locked By</span>
                <span className="flex-1 text-slate-900">{status?.lockedByName || "—"}</span>
              </div>
              <div className="flex px-4 py-2.5">
                <span className="w-32 font-medium text-slate-500">Lock Reason</span>
                <span className="flex-1 text-slate-900 italic">
                  {status?.reason ? `“${status.reason}”` : "—"}
                </span>
              </div>
              {isOverrideActive && (
                <>
                  <div className="flex px-4 py-2.5 bg-amber-50/40">
                    <span className="w-32 font-medium text-amber-700">Override By</span>
                    <span className="flex-1 text-slate-900 font-semibold">
                      {status?.overrideByName || "—"}
                    </span>
                  </div>
                  {status?.overrideUntil && (
                    <div className="flex px-4 py-2.5 bg-amber-50/40">
                      <span className="w-32 font-medium text-amber-700">Override Until</span>
                      <span className="flex-1 text-slate-900">
                        {new Date(status.overrideUntil).toLocaleString()}
                      </span>
                    </div>
                  )}
                </>
              )}
              <div className="flex px-4 py-2.5">
                <span className="w-32 font-medium text-slate-500">Last Updated</span>
                <span className="flex-1 text-slate-600">
                  {status?.updatedAt ? new Date(status.updatedAt).toLocaleString() : "—"}
                </span>
              </div>
            </div>
          </div>

          {/* Prompt Section for reason input */}
          {promptAction && (
            <form onSubmit={handleSubmitAction} className="p-4 rounded-xl border border-blue-200 bg-blue-50/40 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-slate-900 flex items-center gap-1.5">
                  <ShieldAlert className="w-4 h-4 text-blue-600" />
                  {promptAction === "lock" ? "Lock Vacancy Editing" : "Unlock / Override Vacancy Editing"}
                </span>
                <button
                  type="button"
                  onClick={handleClosePrompt}
                  className="text-slate-400 hover:text-slate-600 text-xs"
                >
                  Cancel
                </button>
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-700 mb-1">
                  Audited Reason <span className="text-rose-500">*</span>
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
                  className="w-full text-xs px-3 py-2 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
                  autoFocus
                />
              </div>

              {errorMessage && (
                <p className="text-xs text-rose-600 font-medium">{errorMessage}</p>
              )}

              <div className="flex justify-end gap-2 pt-1">
                <button
                  type="button"
                  onClick={handleClosePrompt}
                  className="px-3 py-1.5 text-xs text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50"
                >
                  Dismiss
                </button>
                <button
                  type="submit"
                  disabled={isActionPending}
                  className={`px-3 py-1.5 text-xs font-semibold text-white rounded-lg transition-colors flex items-center gap-1.5 ${
                    promptAction === "lock"
                      ? "bg-rose-600 hover:bg-rose-700"
                      : "bg-emerald-600 hover:bg-emerald-700"
                  }`}
                >
                  {isActionPending ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : null}
                  {promptAction === "lock" ? "Confirm Lock" : "Confirm Unlock / Override"}
                </button>
              </div>
            </form>
          )}

          {!canManageOverrides && (
            <div className="p-3 bg-amber-50 text-amber-800 rounded-lg text-xs flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 shrink-0 text-amber-600" />
              <span>You have read-only access. Only Super Admin and Head Admin can toggle edit locks.</span>
            </div>
          )}
        </div>

        {/* Footer Actions */}
        <div className="flex items-center justify-between px-6 py-4 border-t border-slate-200 bg-slate-50/50">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-slate-700 bg-white border border-slate-300 rounded-xl hover:bg-slate-50 transition-colors"
          >
            Close
          </button>

          {canManageOverrides && !promptAction && (
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => handleOpenPrompt("lock")}
                disabled={isLoading || isLocked}
                className="px-4 py-2 text-xs font-semibold text-white bg-rose-600 hover:bg-rose-700 disabled:opacity-50 disabled:cursor-not-allowed rounded-xl transition-colors flex items-center gap-1.5"
              >
                <Lock className="w-3.5 h-3.5" />
                <span>Lock Now</span>
              </button>
              <button
                type="button"
                onClick={() => handleOpenPrompt("unlock")}
                disabled={isLoading}
                className="px-4 py-2 text-xs font-semibold text-white bg-slate-900 hover:bg-slate-800 disabled:opacity-50 disabled:cursor-not-allowed rounded-xl transition-colors flex items-center gap-1.5"
              >
                <LockOpen className="w-3.5 h-3.5" />
                <span>Unlock / Override</span>
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
