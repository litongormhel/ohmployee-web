"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Building2,
  CheckCircle2,
  Clock,
  FileX2,
  RefreshCcw,
  Tag,
  User,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  useApproveEmplocDeletion,
  useRejectEmplocDeletion,
  type EmplocDeletionRequestItem,
} from "@/lib/queries/hr_emploc";

interface HrEmplocDeletionReviewCardProps {
  request: EmplocDeletionRequestItem;
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return "--";
  try {
    return new Date(dateStr).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
  } catch {
    return dateStr;
  }
}

function isDeletionTypeBackout(deletionType: string): boolean {
  return deletionType.toLowerCase() === "backout";
}

export function HrEmplocDeletionReviewCard({
  request,
}: HrEmplocDeletionReviewCardProps) {
  const isBackout = isDeletionTypeBackout(request.deletionType);

  // Modal open states
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);

  // Approve form state
  const [reopenVacancy, setReopenVacancy] = useState(isBackout);
  const [approveNotes, setApproveNotes] = useState("");

  // Reject form state
  const [rejectionReason, setRejectionReason] = useState("");
  const [rejectReasonError, setRejectReasonError] = useState(false);

  const [actionError, setActionError] = useState<string | null>(null);

  const approveMutation = useApproveEmplocDeletion();
  const rejectMutation = useRejectEmplocDeletion();

  const handleOpenApprove = () => {
    setActionError(null);
    setApproveNotes("");
    setReopenVacancy(isBackout);
    setIsApproveOpen(true);
  };

  const handleOpenReject = () => {
    setActionError(null);
    setRejectionReason("");
    setRejectReasonError(false);
    setIsRejectOpen(true);
  };

  const handleConfirmApprove = async () => {
    setActionError(null);
    try {
      await approveMutation.mutateAsync({
        requestId: request.id,
        reopenVacancy,
        notes: approveNotes || null,
      });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : "Failed to approve deletion request."
      );
    }
  };

  const handleConfirmReject = async () => {
    setActionError(null);
    if (!rejectionReason.trim()) {
      setRejectReasonError(true);
      return;
    }
    try {
      await rejectMutation.mutateAsync({
        requestId: request.id,
        rejectionReason: rejectionReason.trim(),
      });
      setIsRejectOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : "Failed to reject deletion request."
      );
    }
  };

  const isBusy = approveMutation.isPending || rejectMutation.isPending;

  return (
    <div className="rounded-lg border border-border-default bg-surface p-5 shadow-xs transition hover:border-border-brand/40">
      {/* Header: Employee identity + Deletion Type badge */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            {/* VCode pill */}
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 font-mono text-xs font-semibold text-text-primary">
              {request.vcode}
            </span>

            {/* Deletion type badge */}
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-primary">
              {isBackout ? (
                <>
                  <FileX2 className="h-3 w-3" aria-hidden="true" />
                  Backout
                </>
              ) : (
                <>
                  <Tag className="h-3 w-3" aria-hidden="true" />
                  Duplicate Record
                </>
              )}
            </span>
          </div>

          {/* Employee name */}
          <h3 className="flex items-center gap-1.5 text-base font-semibold text-text-primary">
            <User className="h-4 w-4 shrink-0 text-text-muted" aria-hidden="true" />
            <span className="truncate">{request.applicantName}</span>
            {request.employeeNo && (
              <span className="ml-1 font-mono text-sm font-normal text-text-secondary">
                #{request.employeeNo}
              </span>
            )}
          </h3>
        </div>
      </div>

      {/* Employee placement context */}
      <div className="mt-3 grid grid-cols-1 gap-2 rounded-md border border-border-default bg-surface-subtle p-3 text-xs sm:grid-cols-2">
        {request.storeName && (
          <div className="flex items-center gap-1.5 text-text-secondary">
            <Building2 className="h-3.5 w-3.5 shrink-0 text-text-muted" aria-hidden="true" />
            <span className="font-medium text-text-primary">{request.storeName}</span>
          </div>
        )}
        {request.positionTitle && (
          <div className="flex items-center gap-1.5 text-text-muted">
            <span className="font-medium text-text-secondary">{request.positionTitle}</span>
          </div>
        )}
      </div>

      {/* Reason / remarks */}
      {request.reason && (
        <div className="mt-3.5 space-y-1">
          <p className="text-xs font-medium uppercase tracking-wider text-text-muted">
            Requester Remarks
          </p>
          <p className="rounded-md border border-border-default bg-surface px-3 py-2 text-xs leading-relaxed text-text-secondary">
            {request.reason}
          </p>
        </div>
      )}

      {/* Footer: Requester meta + Actions */}
      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-border-default pt-3">
        <div className="flex flex-wrap items-center gap-4 text-xs text-text-muted">
          <span className="flex items-center gap-1">
            <User className="h-3.5 w-3.5" aria-hidden="true" />
            <span className="font-medium text-text-secondary">
              {request.requestedByName ?? "Unknown Requester"}
            </span>
          </span>
          <span className="flex items-center gap-1">
            <Clock className="h-3.5 w-3.5" aria-hidden="true" />
            <span>{formatDate(request.requestedAt)}</span>
          </span>
        </div>

        {/* Action Buttons */}
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleOpenReject}
            disabled={isBusy}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-danger/40 bg-surface-subtle px-3 text-xs font-semibold text-text-danger shadow-2xs transition hover:bg-danger-subtle disabled:cursor-not-allowed disabled:opacity-50 cursor-pointer"
          >
            <XCircle className="h-3.5 w-3.5" aria-hidden="true" />
            Reject
          </button>
          <button
            type="button"
            onClick={handleOpenApprove}
            disabled={isBusy}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-brand-500 bg-brand-500 hover:bg-brand-600 px-3.5 text-xs font-semibold text-white shadow-2xs transition disabled:cursor-not-allowed disabled:opacity-50 cursor-pointer"
          >
            <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
            Approve Deletion
          </button>
        </div>
      </div>

      {/* ── Confirmation Dialog: APPROVE ───────────────────────────────────── */}
      {isApproveOpen && (
        <Modal
          isOpen={isApproveOpen}
          onClose={() => setIsApproveOpen(false)}
          title="Confirm Emploc Deletion"
          subtitle={request.applicantName}
          icon={CheckCircle2}
          isSubmitting={approveMutation.isPending}
          disableBackdropClick={approveMutation.isPending}
          maxWidthClass="max-w-lg"
        >
          <div className="space-y-4 text-xs text-text-secondary">
            <p>
              You are approving the{" "}
              <span className="font-semibold text-text-primary">
                {request.deletionType}
              </span>{" "}
              deletion request for{" "}
              <span className="font-semibold text-text-primary">
                {request.applicantName}
              </span>
              {request.employeeNo && (
                <>
                  {" "}
                  <span className="font-mono text-text-secondary">
                    (#{request.employeeNo})
                  </span>
                </>
              )}
              . This action is irreversible and will remove the HR Emploc record.
            </p>

            {/* Reopen Vacancy Toggle */}
            <div className="rounded-lg border border-border-default bg-surface-subtle p-3">
              <label className="flex cursor-pointer items-start gap-3">
                <div className="relative mt-0.5 flex-shrink-0">
                  <input
                    type="checkbox"
                    id={`reopen-vacancy-${request.id}`}
                    checked={reopenVacancy}
                    onChange={(e) => setReopenVacancy(e.target.checked)}
                    className="h-4 w-4 cursor-pointer rounded border-border-default text-text-brand-bold focus:ring-brand-500"
                  />
                </div>
                <div>
                  <p className="flex items-center gap-1.5 font-semibold text-text-primary">
                    <RefreshCcw className="h-3.5 w-3.5 text-text-brand-bold" aria-hidden="true" />
                    Reopen Vacancy Slot?
                  </p>
                  <p className="mt-0.5 text-text-muted leading-relaxed">
                    {isBackout
                      ? "Recommended for Backout — restores the vacancy so the position can be re-filled."
                      : "For Duplicate Record, the original record remains active. Uncheck unless the slot needs to be reopened."}
                  </p>
                </div>
              </label>
            </div>

            {actionError && (
              <div className="rounded-md border border-border-danger bg-danger-subtle p-3 text-xs text-text-danger">
                <div className="flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 shrink-0 text-text-danger" aria-hidden="true" />
                  <span>{actionError}</span>
                </div>
              </div>
            )}

            {/* Optional notes */}
            <div>
              <label
                htmlFor={`approve-notes-${request.id}`}
                className="mb-1 block font-medium text-text-primary"
              >
                Reviewer Notes (Optional)
              </label>
              <textarea
                id={`approve-notes-${request.id}`}
                rows={2}
                value={approveNotes}
                onChange={(e) => setApproveNotes(e.target.value)}
                placeholder="Add any relevant review notes or context..."
                className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary shadow-2xs focus:border-border-brand focus:outline-hidden"
              />
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={approveMutation.isPending}
                className="h-8 rounded-md border border-border-default bg-surface px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={approveMutation.isPending}
                className="inline-flex h-8 items-center gap-1.5 rounded-md bg-brand-500 hover:bg-brand-600 px-4 text-xs font-semibold text-white shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {approveMutation.isPending ? "Approving..." : "Confirm Approval"}
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* ── Confirmation Dialog: REJECT ────────────────────────────────────── */}
      {isRejectOpen && (
        <Modal
          isOpen={isRejectOpen}
          onClose={() => setIsRejectOpen(false)}
          title="Reject Deletion Request"
          subtitle={request.applicantName}
          icon={XCircle}
          isSubmitting={rejectMutation.isPending}
          disableBackdropClick={rejectMutation.isPending}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-lg"
        >
          <div className="space-y-4 text-xs text-text-secondary">
            <p>
              Rejecting this deletion request will leave the HR Emploc record for{" "}
              <span className="font-semibold text-text-primary">
                {request.applicantName}
              </span>{" "}
              intact and restore it to its active state.
            </p>

            {actionError && (
              <div className="rounded-md border border-border-danger bg-danger-subtle p-3 text-xs text-text-danger">
                <div className="flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 shrink-0 text-text-danger" aria-hidden="true" />
                  <span>{actionError}</span>
                </div>
              </div>
            )}

            {/* Required rejection reason */}
            <div>
              <label
                htmlFor={`reject-reason-${request.id}`}
                className="mb-1 block font-medium text-text-primary"
              >
                Rejection Reason{" "}
                <span className="text-text-danger" aria-hidden="true">
                  *
                </span>
              </label>
              <textarea
                id={`reject-reason-${request.id}`}
                rows={3}
                value={rejectionReason}
                onChange={(e) => {
                  setRejectionReason(e.target.value);
                  if (e.target.value.trim()) setRejectReasonError(false);
                }}
                placeholder="State the operational reason for rejecting this deletion request..."
                className={`w-full rounded-md border bg-surface p-2 text-xs text-text-primary shadow-2xs focus:outline-hidden ${
                  rejectReasonError
                    ? "border-border-danger focus:border-border-danger"
                    : "border-border-default focus:border-border-brand"
                }`}
                aria-required="true"
                aria-invalid={rejectReasonError}
                aria-describedby={
                  rejectReasonError
                    ? `reject-reason-error-${request.id}`
                    : undefined
                }
              />
              {rejectReasonError && (
                <p
                  id={`reject-reason-error-${request.id}`}
                  className="mt-1 text-2xs text-text-danger"
                >
                  A rejection reason is required to proceed.
                </p>
              )}
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={rejectMutation.isPending}
                className="h-8 rounded-md border border-border-default bg-surface px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={rejectMutation.isPending}
                className="inline-flex h-8 items-center gap-1.5 rounded-md bg-danger-button hover:bg-danger-button-hover px-4 text-xs font-semibold text-danger-button-text shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {rejectMutation.isPending ? "Rejecting..." : "Confirm Rejection"}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
