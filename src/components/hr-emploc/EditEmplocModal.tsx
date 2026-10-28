// components/hr-emploc/EditEmplocModal.tsx
"use client";

import { useState } from "react";
import { AlertCircle, Edit3, Loader2, RotateCcw, AlertTriangle } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  checkEcosystemEmployeeIdUnique,
  useUpdateDeployedEmployeeId,
  useRevertHrEmplocToPending,
} from "@/lib/queries/hr_emploc";

export type EditEmplocModalProps = {
  isOpen?: boolean;
  hrEmplocId: string;
  candidateName?: string;
  applicantName?: string;
  vcode: string;
  accountName?: string | null;
  storeName?: string | null;
  currentEmployeeNo?: string | null;
  currentEmployeeId?: string | null;
  onClose: () => void;
  onSuccess: (message: string) => void;
};

const EDIT_REASONS = [
  "Typo in Employee ID",
  "Incorrect Format / Prefix",
  "Encoding Correction",
  "ID Series Reassignment",
  "Other",
];

const REVERT_REASONS = [
  "Wrong applicant row encoded",
  "Incorrect candidate selected during Emploc creation",
  "Endorsement error (re-queuing candidate)",
  "Other",
];

export function EditEmplocModal({
  isOpen = true,
  hrEmplocId,
  candidateName,
  applicantName,
  vcode,
  accountName,
  storeName,
  currentEmployeeNo,
  currentEmployeeId,
  onClose,
  onSuccess,
}: EditEmplocModalProps) {
  const effectiveCandidateName = candidateName || applicantName || "Candidate";
  const effectiveEmployeeNo = currentEmployeeNo || currentEmployeeId || "";
  const [activeTab, setActiveTab] = useState<"edit" | "revert">("edit");
  const [newEmployeeNo, setNewEmployeeNo] = useState("");
  const [editReasonOption, setEditReasonOption] = useState(EDIT_REASONS[0]);
  const [editCustomReason, setEditCustomReason] = useState("");
  const [revertReasonOption, setRevertReasonOption] = useState(REVERT_REASONS[0]);
  const [revertCustomReason, setRevertCustomReason] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const updateMutation = useUpdateDeployedEmployeeId();
  const revertMutation = useRevertHrEmplocToPending();

  const isSubmitting = updateMutation.isPending || revertMutation.isPending;

  const resolvedEditReason =
    editReasonOption === "Other" ? editCustomReason.trim() : editReasonOption;
  const resolvedRevertReason =
    revertReasonOption === "Other" ? revertCustomReason.trim() : revertReasonOption;

  async function handleUpdateSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErrorMessage(null);

    const cleanId = newEmployeeNo.trim();
    if (!cleanId) {
      setErrorMessage("New Employee ID is required.");
      return;
    }

    if (cleanId.toLowerCase() === effectiveEmployeeNo.toLowerCase().trim()) {
      setErrorMessage("New Employee ID must be different from current ID.");
      return;
    }

    if (!resolvedEditReason) {
      setErrorMessage("Please specify a reason for this edit.");
      return;
    }

    // 1. Ecosystem-wide uniqueness check
    const check = await checkEcosystemEmployeeIdUnique(cleanId, hrEmplocId);
    if (!check.isUnique) {
      setErrorMessage(
        check.message ||
          `Employee ID ${cleanId} already exists in the system. Duplicate Emploc numbers are not allowed.`
      );
      return;
    }

    // 2. Perform update
    updateMutation.mutate(
      {
        hrEmplocId,
        newEmployeeNo: cleanId,
        reason: resolvedEditReason,
      },
      {
        onSuccess: () => {
          onSuccess(
            `Updated Employee ID from ${effectiveEmployeeNo || "None"} to ${cleanId} for ${effectiveCandidateName}.`
          );
        },
        onError: (err) => {
          setErrorMessage(err instanceof Error ? err.message : "Failed to update Employee ID.");
        },
      }
    );
  }

  function handleRevertSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErrorMessage(null);

    if (!resolvedRevertReason) {
      setErrorMessage("Please specify a reason for reverting to Pending.");
      return;
    }

    revertMutation.mutate(
      {
        hrEmplocId,
        reason: resolvedRevertReason,
        vcode,
      },
      {
        onSuccess: () => {
          onSuccess(
            `Reverted ${effectiveCandidateName} from Deployed to Pending and freed Employee ID ${effectiveEmployeeNo || ""}.`
          );
        },
        onError: (err) => {
          setErrorMessage(err instanceof Error ? err.message : "Failed to revert record to Pending.");
        },
      }
    );
  }

  const locationContext = [accountName, storeName].filter(Boolean).join(" / ");
  const isDirty = Boolean(newEmployeeNo || editCustomReason || revertCustomReason);

  if (!isOpen) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Edit Emploc & Deployment Management"
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        {/* Context Header */}
        <div className="rounded-lg border border-border-default bg-surface-muted p-3.5 space-y-1">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-bold text-text-primary">{effectiveCandidateName}</h4>
            <span className="font-mono text-xs font-semibold px-2 py-0.5 rounded border border-border-default bg-surface text-text-secondary">
              {vcode}
            </span>
          </div>
          {locationContext && (
            <p className="text-xs text-text-secondary font-medium">📍 {locationContext}</p>
          )}
          <div className="mt-2 pt-2 border-t border-border-subtle flex items-center justify-between text-xs">
            <span className="text-text-muted">Current Employee ID:</span>
            <span className="font-mono font-bold text-text-primary bg-surface px-2 py-0.5 rounded border border-border-default">
              {effectiveEmployeeNo || "None Assigned"}
            </span>
          </div>
        </div>

        {/* Tab Switcher */}
        <div className="flex rounded-md border border-border-default bg-surface-muted p-1">
          <button
            type="button"
            onClick={() => {
              setActiveTab("edit");
              setErrorMessage(null);
            }}
            className={`flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs font-semibold rounded transition cursor-pointer ${
              activeTab === "edit"
                ? "bg-surface text-text-primary shadow-2xs border border-border-default"
                : "text-text-secondary hover:text-text-primary"
            }`}
          >
            <Edit3 className="h-3.5 w-3.5" />
            <span>Edit Employee ID (Typo)</span>
          </button>
          <button
            type="button"
            onClick={() => {
              setActiveTab("revert");
              setErrorMessage(null);
            }}
            className={`flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs font-semibold rounded transition cursor-pointer ${
              activeTab === "revert"
                ? "bg-surface text-[var(--danger-text)] shadow-2xs border border-[var(--danger-border)]"
                : "text-text-secondary hover:text-[var(--danger-text)]"
            }`}
          >
            <RotateCcw className="h-3.5 w-3.5" />
            <span>Revert to Pending</span>
          </button>
        </div>

        {/* Error Notice */}
        {errorMessage && (
          <div className="rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] flex items-start gap-2">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <span className="leading-relaxed">{errorMessage}</span>
          </div>
        )}

        {/* Tab 1: Edit Emploc (Typo in ID) */}
        {activeTab === "edit" && (
          <form onSubmit={handleUpdateSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <label
                htmlFor="newEmployeeNo"
                className="block text-xs font-semibold text-text-primary"
              >
                New Employee ID <span className="text-[var(--danger-text)]">*</span>
              </label>
              <input
                id="newEmployeeNo"
                type="text"
                required
                disabled={isSubmitting}
                value={newEmployeeNo}
                onChange={(e) => {
                  setNewEmployeeNo(e.target.value);
                  setErrorMessage(null);
                }}
                placeholder="e.g. 2024-0099 or EMP1044"
                className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary focus:border-brand-primary"
              />
              <p className="text-[11px] text-text-muted">
                Validation checks across all modules (HR Emploc, Plantilla, and Users).
              </p>
            </div>

            <div className="space-y-1.5">
              <label
                htmlFor="editReasonSelect"
                className="block text-xs font-semibold text-text-primary"
              >
                Reason for Edit <span className="text-[var(--danger-text)]">*</span>
              </label>
              <select
                id="editReasonSelect"
                disabled={isSubmitting}
                value={editReasonOption}
                onChange={(e) => setEditReasonOption(e.target.value)}
                className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-xs text-text-primary font-medium focus:outline-none focus:ring-1 focus:ring-brand-primary focus:border-brand-primary"
              >
                {EDIT_REASONS.map((r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ))}
              </select>

              {editReasonOption === "Other" && (
                <input
                  type="text"
                  required
                  disabled={isSubmitting}
                  value={editCustomReason}
                  onChange={(e) => setEditCustomReason(e.target.value)}
                  placeholder="Specify reason..."
                  className="mt-2 w-full rounded-md border border-border-default bg-surface px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary focus:border-brand-primary"
                />
              )}
            </div>

            <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-border-subtle">
              <button
                type="button"
                disabled={isSubmitting}
                onClick={onClose}
                className="rounded-md border border-border-default bg-surface px-4 py-2 text-xs font-medium text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isSubmitting || !newEmployeeNo.trim()}
                className="inline-flex items-center gap-1.5 rounded-md bg-brand-button px-4 py-2 text-xs font-semibold text-white hover:bg-brand-button-hover transition shadow-xs cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isSubmitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                {isSubmitting ? "Updating..." : "Update Employee ID"}
              </button>
            </div>
          </form>
        )}

        {/* Tab 2: Revert to Pending */}
        {activeTab === "revert" && (
          <form onSubmit={handleRevertSubmit} className="space-y-4">
            <div className="rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 space-y-2 text-xs text-[var(--danger-text)]">
              <div className="flex items-start gap-2">
                <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
                <div className="space-y-1">
                  <span className="font-bold">Revert & Unlink Impact:</span>
                  <p className="leading-relaxed">
                    This action will <strong>remove and unlink</strong> the candidate from the active
                    Plantilla directory and <strong>hard-clear (NULL)</strong> their Employee ID.
                    The ID number will be immediately freed up for re-assignment.
                  </p>
                </div>
              </div>
            </div>

            <div className="space-y-1.5">
              <label
                htmlFor="revertReasonSelect"
                className="block text-xs font-semibold text-text-primary"
              >
                Reason for Revert <span className="text-[var(--danger-text)]">*</span>
              </label>
              <select
                id="revertReasonSelect"
                disabled={isSubmitting}
                value={revertReasonOption}
                onChange={(e) => setRevertReasonOption(e.target.value)}
                className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-xs text-text-primary font-medium focus:outline-none focus:ring-1 focus:ring-brand-primary focus:border-brand-primary"
              >
                {REVERT_REASONS.map((r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ))}
              </select>

              {revertReasonOption === "Other" && (
                <input
                  type="text"
                  required
                  disabled={isSubmitting}
                  value={revertCustomReason}
                  onChange={(e) => setRevertCustomReason(e.target.value)}
                  placeholder="Specify reason..."
                  className="mt-2 w-full rounded-md border border-border-default bg-surface px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary focus:border-brand-primary"
                />
              )}
            </div>

            <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-border-subtle">
              <button
                type="button"
                disabled={isSubmitting}
                onClick={onClose}
                className="rounded-md border border-border-default bg-surface px-4 py-2 text-xs font-medium text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isSubmitting}
                className="inline-flex items-center gap-1.5 rounded-md bg-[var(--danger-bg)] border border-[var(--danger-border)] text-[var(--danger-text)] hover:opacity-90 px-4 py-2 text-xs font-bold transition shadow-xs cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isSubmitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                {isSubmitting ? "Reverting..." : "Confirm Revert to Pending"}
              </button>
            </div>
          </form>
        )}
      </div>
    </Modal>
  );
}
