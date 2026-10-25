// components/hr-emploc/RequestEmplocDeletionModal.tsx
"use client";

import { useState } from "react";
import { AlertCircle, AlertTriangle, Loader2, Trash2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useRequestEmplocDeletion, HrEmplocDataError } from "@/lib/queries/hr_emploc";

type RequestEmplocDeletionModalProps = {
  hrEmplocId: string;
  candidateName: string;
  vcode: string;
  onClose: () => void;
  onSuccess: () => void;
};

export function RequestEmplocDeletionModal({
  hrEmplocId,
  candidateName,
  vcode,
  onClose,
  onSuccess,
}: RequestEmplocDeletionModalProps) {
  const [deletionType, setDeletionType] = useState<"backout" | "duplicate">("backout");
  const [reason, setReason] = useState("");
  const [originalEmplocId, setOriginalEmplocId] = useState("");
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const requestDeletionMutation = useRequestEmplocDeletion();

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErrorMsg(null);

    const trimmedReason = reason.trim();
    if (!trimmedReason) {
      setErrorMsg("A detailed justification or remarks explaining the deletion is required.");
      return;
    }

    if (deletionType === "duplicate" && !originalEmplocId.trim()) {
      setErrorMsg("Please provide the original / master HR Emploc Record UUID to merge against.");
      return;
    }

    requestDeletionMutation.mutate(
      {
        hrEmplocId,
        reason: trimmedReason,
        deletionType,
        originalEmplocId: deletionType === "duplicate" ? originalEmplocId.trim() : null,
      },
      {
        onSuccess: () => {
          onSuccess();
        },
        onError: (err) => {
          if (err instanceof HrEmplocDataError) {
            setErrorMsg(err.message);
          } else if (err instanceof Error) {
            setErrorMsg(err.message);
          } else {
            setErrorMsg("Failed to submit deletion request. Please try again.");
          }
        },
      }
    );
  }

  const isDirty = Boolean(reason.trim() || originalEmplocId.trim());

  return (
    <Modal
      isOpen={true}
      onClose={onClose}
      title="Request Placement Separation / Deletion"
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={requestDeletionMutation.isPending}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        <div className="flex items-center gap-2 pb-2 border-b border-border-subtle">
          <div className="p-1.5 bg-[var(--danger-bg)] text-[var(--danger-text)] rounded border border-[var(--danger-border)]">
            <Trash2 className="h-4 w-4" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-text-primary">
              Separation Request
            </h4>
            <p className="text-[11px] text-text-muted">
              Submit an auditable request to remove or backout this recruit
            </p>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Target Record Details */}
          <div className="rounded-md border border-border-subtle bg-surface-muted p-3 text-xs space-y-1">
            <div className="flex justify-between items-center">
              <span className="text-text-muted">Candidate:</span>
              <span className="font-semibold text-text-primary">{candidateName}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-text-muted">VCode:</span>
              <span className="font-mono text-text-primary bg-surface px-1.5 py-0.5 rounded border border-border-default">
                {vcode}
              </span>
            </div>
          </div>

          {/* Deletion Reason Radio Selector */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-text-primary">
              Reason for Deletion <span className="text-[var(--danger-text)]">*</span>
            </label>
            <div className="grid grid-cols-2 gap-3">
              <label
                className={`flex flex-col p-3 rounded-md border cursor-pointer transition-colors ${
                  deletionType === "backout"
                    ? "border-[var(--danger-border)] bg-[var(--danger-bg)] text-[var(--danger-text)]"
                    : "border-border-default bg-surface hover:bg-surface-hover text-text-primary"
                }`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <input
                    type="radio"
                    name="deletionReason"
                    value="backout"
                    checked={deletionType === "backout"}
                    onChange={() => setDeletionType("backout")}
                    disabled={requestDeletionMutation.isPending}
                    className="h-4 w-4 border-border-default"
                  />
                  <span className="text-xs font-bold">Applicant Backout</span>
                </div>
                <span className="text-[11px] opacity-80 pl-6 leading-tight">
                  Candidate declined offer, backed out, or failed to report on start date.
                </span>
              </label>

              <label
                className={`flex flex-col p-3 rounded-md border cursor-pointer transition-colors ${
                  deletionType === "duplicate"
                    ? "border-[var(--danger-border)] bg-[var(--danger-bg)] text-[var(--danger-text)]"
                    : "border-border-default bg-surface hover:bg-surface-hover text-text-primary"
                }`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <input
                    type="radio"
                    name="deletionReason"
                    value="duplicate"
                    checked={deletionType === "duplicate"}
                    onChange={() => setDeletionType("duplicate")}
                    disabled={requestDeletionMutation.isPending}
                    className="h-4 w-4 border-border-default"
                  />
                  <span className="text-xs font-bold">Duplicate Record</span>
                </div>
                <span className="text-[11px] opacity-80 pl-6 leading-tight">
                  Accidental multiple creation or import of the same applicant.
                </span>
              </label>
            </div>
          </div>

          {/* Original Record ID input (for Duplicate) */}
          {deletionType === "duplicate" && (
            <div className="space-y-1.5 p-3 rounded-md border border-border-default bg-surface-muted">
              <label htmlFor="originalRecordIdInput" className="block text-xs font-semibold text-text-primary">
                Original Record UUID <span className="text-[var(--danger-text)]">*</span>
              </label>
              <input
                id="originalRecordIdInput"
                type="text"
                required
                disabled={requestDeletionMutation.isPending}
                value={originalEmplocId}
                onChange={(e) => setOriginalEmplocId(e.target.value)}
                placeholder="e.g. 550e8400-e29b-41d4-a716-446655440000"
                className="w-full rounded border border-border-default bg-surface px-3 py-1.5 text-xs font-mono text-text-primary focus:outline-none focus:ring-1 focus:ring-border-strong"
              />
              <p className="text-[10px] text-text-muted">
                Identifier of the legitimate record that will remain active in the system.
              </p>
            </div>
          )}

          {/* Justification remarks textarea */}
          <div className="space-y-1.5">
            <label htmlFor="justificationInput" className="block text-xs font-semibold text-text-primary">
              Justification & Operational Remarks <span className="text-[var(--danger-text)]">*</span>
            </label>
            <textarea
              id="justificationInput"
              required
              rows={3}
              maxLength={1000}
              disabled={requestDeletionMutation.isPending}
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                setErrorMsg(null);
              }}
              placeholder="Detail reasons for separation, date of notice, or coordination background..."
              className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-border-strong resize-none disabled:opacity-50"
            />
            <p className="text-[11px] text-text-muted">
              This reason will be visible to Encoders and Super Admins during request review.
            </p>
          </div>

          {/* Locking Alert */}
          <div className="rounded border border-[var(--danger-border)] bg-[var(--danger-bg)] p-2.5 text-[11px] text-[var(--danger-text)] flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>
              <strong>Lock Notice:</strong> Submitting this request will lock this record into <em>Pending Deletion</em> status and temporarily prevent modifications, approvals, and employee number assignments until reviewed or withdrawn.
            </span>
          </div>

          {/* Error Message */}
          {errorMsg && (
            <div className="rounded border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
              <span>{errorMsg}</span>
            </div>
          )}

          {/* Footer Actions */}
          <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-border-subtle">
            <button
              type="button"
              disabled={requestDeletionMutation.isPending}
              onClick={onClose}
              className="rounded-md border border-border-default bg-surface px-4 py-2 text-xs font-medium text-text-primary hover:bg-surface-hover transition disabled:opacity-50 cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={requestDeletionMutation.isPending || !reason.trim()}
              className="inline-flex items-center gap-1.5 rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] px-4 py-2 text-xs font-semibold text-[var(--danger-text)] hover:opacity-90 transition disabled:opacity-50 disabled:cursor-not-allowed shadow-xs cursor-pointer"
            >
              {requestDeletionMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              {requestDeletionMutation.isPending ? "Submitting..." : "Submit Deletion Request"}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
