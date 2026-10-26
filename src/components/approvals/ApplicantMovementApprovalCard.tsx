"use client";

import { useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  ArrowLeftRight,
  Briefcase,
  Building2,
  Calendar,
  CheckCircle2,
  Clock,
  Layers,
  MessageSquare,
  RefreshCw,
  ShieldAlert,
  User,
  Users,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  useApproveApplicantMovement,
  useRejectApplicantMovement,
  type ApplicantMovementRequestItem,
} from "@/lib/queries/requests";

interface ApplicantMovementApprovalCardProps {
  request: ApplicantMovementRequestItem;
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

function formatRelativeAge(dateStr: string | null): string {
  if (!dateStr) return "";
  try {
    const diffMs = Date.now() - new Date(dateStr).getTime();
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
    if (diffDays > 0) return `${diffDays}d ago`;
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    if (diffHours > 0) return `${diffHours}h ago`;
    const diffMins = Math.floor(diffMs / (1000 * 60));
    return `${Math.max(1, diffMins)}m ago`;
  } catch {
    return "";
  }
}

export function ApplicantMovementApprovalCard({
  request,
}: ApplicantMovementApprovalCardProps) {
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [approveNote, setApproveNote] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
  const [rejectReasonError, setRejectReasonError] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const approveMutation = useApproveApplicantMovement();
  const rejectMutation = useRejectApplicantMovement();

  const handleOpenApprove = () => {
    setActionError(null);
    setApproveNote("");
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
        note: approveNote.trim() || undefined,
      });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve applicant movement request."
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
        reason: rejectionReason.trim(),
      });
      setIsRejectOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject applicant movement request."
      );
    }
  };

  const isBusy = approveMutation.isPending || rejectMutation.isPending;
  const isSwap = request.movementType === "SWAP";
  const relativeAge = formatRelativeAge(request.requestedAt);

  return (
    <div className="rounded-lg border border-border-default bg-surface p-5 shadow-xs transition hover:border-border-brand/40">
      {/* Top Header: Movement Type badge + Request Number + Stage & Status */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            {isSwap ? (
              <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 font-mono text-xs font-semibold text-text-primary">
                <ArrowLeftRight className="h-3 w-3" aria-hidden="true" />
                SWAP MOVEMENT
              </span>
            ) : (
              <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 font-mono text-xs font-semibold text-text-primary">
                <ArrowRight className="h-3 w-3" aria-hidden="true" />
                TRANSFER MOVEMENT
              </span>
            )}

            <span className="inline-flex items-center rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 font-mono text-xs font-semibold text-text-secondary">
              {request.requestNumber}
            </span>

            {request.approvalStage && (
              <span className="inline-flex items-center gap-1 rounded-md bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-medium text-text-secondary">
                <Layers className="h-3 w-3" aria-hidden="true" />
                Stage: {request.approvalStage.toUpperCase()}
              </span>
            )}

            {request.hasActiveReservation && (
              <span className="inline-flex items-center rounded-md bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-medium text-text-brand-bold">
                Slot Reserved
              </span>
            )}

            <span className="inline-flex items-center rounded-md bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-medium text-text-secondary">
              Pending Review
            </span>
          </div>

          <h3 className="flex items-center gap-1.5 text-base font-semibold text-text-primary">
            <User className="h-4 w-4 shrink-0 text-text-muted" aria-hidden="true" />
            <span>{request.sourceApplicantName}</span>
            {request.sourceApplicantStatus && (
              <span className="rounded-md bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-normal text-text-secondary">
                {request.sourceApplicantStatus}
              </span>
            )}
          </h3>
        </div>

        {/* Action Buttons */}
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleOpenReject}
            disabled={isBusy}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-danger/40 bg-surface-subtle px-3 text-xs font-medium text-text-danger shadow-2xs hover:bg-danger-subtle disabled:opacity-50 transition cursor-pointer"
          >
            <XCircle className="h-3.5 w-3.5" aria-hidden="true" />
            <span>Reject</span>
          </button>
          <button
            type="button"
            onClick={handleOpenApprove}
            disabled={isBusy}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-brand-500 bg-brand-500 hover:bg-brand-600 px-3 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
          >
            <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
            <span>Approve Movement</span>
          </button>
        </div>
      </div>

      {/* Execution Error Banner (if any) */}
      {request.executionError && (
        <div className="mt-3 flex items-start gap-2 rounded-md border border-border-danger bg-danger-subtle p-2.5 text-xs text-text-danger">
          <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0 text-text-danger" aria-hidden="true" />
          <div>
            <span className="font-semibold">Prior Execution Error:</span>{" "}
            {request.executionError}
          </div>
        </div>
      )}

      {/* Movement Details Grid: Source Slot -> Target Slot */}
      <div className="mt-4 rounded-md border border-border-default bg-surface-subtle p-3.5 text-xs">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Source Slot */}
          <div className="rounded-md border border-border-default bg-surface p-3 space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-text-secondary uppercase tracking-wider text-2xs">
                {isSwap ? "Candidate A (Source Slot)" : "Origin Slot"}
              </span>
              <span className="font-mono text-xs font-semibold text-text-brand-bold bg-surface-subtle border border-border-default px-1.5 py-0.5 rounded-md">
                {request.sourceVacancyVcode}
              </span>
            </div>

            <div className="text-sm font-medium text-text-primary">
              {request.sourceApplicantName}
            </div>

            <div className="flex items-center gap-1.5 text-text-secondary">
              <Briefcase className="h-3.5 w-3.5 shrink-0 text-text-muted" aria-hidden="true" />
              <span>{request.sourcePosition || "Position Unspecified"}</span>
            </div>

            <div className="flex items-center gap-1.5 text-text-secondary">
              <Building2 className="h-3.5 w-3.5 shrink-0 text-text-muted" aria-hidden="true" />
              <span className="truncate">
                {request.sourceStoreName || "Store Unspecified"}
                {request.sourceAccountName ? ` • ${request.sourceAccountName}` : ""}
              </span>
            </div>
          </div>

          {/* Target Slot */}
          <div className="rounded-md border border-border-default bg-surface p-3 space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-text-secondary uppercase tracking-wider text-2xs">
                {isSwap ? "Candidate B (Counterpart Slot)" : "Destination Slot"}
              </span>
              <span className="font-mono text-xs font-semibold text-text-brand-bold bg-surface-subtle border border-border-default px-1.5 py-0.5 rounded-md">
                {request.targetVacancyVcode}
              </span>
            </div>

            <div className="text-sm font-medium text-text-primary">
              {isSwap ? (
                request.targetApplicantName || "Counterpart Candidate Unspecified"
              ) : (
                <span className="text-text-muted italic">Vacant Requisition Slot</span>
              )}
            </div>

            <div className="flex items-center gap-1.5 text-text-secondary">
              <Briefcase className="h-3.5 w-3.5 shrink-0 text-text-muted" aria-hidden="true" />
              <span>{request.targetPosition || "Position Unspecified"}</span>
            </div>

            <div className="flex items-center gap-1.5 text-text-secondary">
              <Building2 className="h-3.5 w-3.5 shrink-0 text-text-muted" aria-hidden="true" />
              <span className="truncate">
                {request.targetStoreName || "Store Unspecified"}
                {request.targetAccountName ? ` • ${request.targetAccountName}` : ""}
              </span>
            </div>
          </div>
        </div>

        {/* Counterpart Swap Explanation Banner */}
        {isSwap && (
          <div className="mt-2.5 flex items-center gap-2 rounded-md bg-surface border border-border-default px-2.5 py-1.5 text-xs text-text-secondary">
            <Users className="h-3.5 w-3.5 shrink-0 text-text-secondary" aria-hidden="true" />
            <span>
              <strong className="text-text-primary">Reciprocal Swap:</strong> {request.sourceApplicantName} will transition to slot {request.targetVacancyVcode}, while {request.targetApplicantName || "counterpart"} will be assigned to slot {request.sourceVacancyVcode}.
            </span>
          </div>
        )}
      </div>

      {/* Rationale & Stated Remarks */}
      <div className="mt-3.5 rounded-md border border-border-default bg-surface p-3 text-xs space-y-1.5">
        <div className="flex items-start gap-2">
          <MessageSquare className="mt-0.5 h-3.5 w-3.5 shrink-0 text-text-muted" aria-hidden="true" />
          <div>
            <span className="font-medium text-text-primary">Stated Reason:</span>{" "}
            <span className="text-text-secondary">{request.reason}</span>
            {request.remarks && (
              <p className="mt-1 text-text-secondary italic">
                &ldquo;{request.remarks}&rdquo;
              </p>
            )}
          </div>
        </div>
      </div>

      {/* Footer Metadata: Requester info & Effective Date */}
      <div className="mt-3.5 flex flex-wrap items-center justify-between gap-3 border-t border-border-default pt-3 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5">
          <User className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
          <span>
            Requested by <strong className="text-text-primary font-medium">{request.requestedByName}</strong>
            {request.requestedByRole ? ` (${request.requestedByRole})` : ""}
          </span>
        </div>

        <div className="flex flex-wrap items-center gap-4">
          <div className="flex items-center gap-1 text-text-muted">
            <Clock className="h-3.5 w-3.5" aria-hidden="true" />
            <span>Requested: {formatDate(request.requestedAt)}</span>
            {relativeAge && <span className="font-mono text-2xs">({relativeAge})</span>}
          </div>

          {request.effectiveDate && (
            <div className="flex items-center gap-1 text-text-secondary">
              <Calendar className="h-3.5 w-3.5 text-text-brand-bold" aria-hidden="true" />
              <span>Effective: {formatDate(request.effectiveDate)}</span>
            </div>
          )}
        </div>
      </div>

      {/* ── Approve Modal ── */}
      {isApproveOpen && (
        <Modal
          isOpen={isApproveOpen}
          onClose={() => setIsApproveOpen(false)}
          title="Approve Movement Request"
          subtitle={request.requestNumber}
          icon={CheckCircle2}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          isDirty={Boolean(approveNote.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-3 text-xs">
            <p className="text-text-secondary leading-relaxed">
              Confirm approval for candidate movement of{" "}
              <strong className="text-text-primary">{request.sourceApplicantName}</strong> from slot{" "}
              <span className="font-mono font-semibold text-text-primary">{request.sourceVacancyVcode}</span>{" "}
              to slot <span className="font-mono font-semibold text-text-primary">{request.targetVacancyVcode}</span>.
            </p>

            {isSwap && (
              <div className="rounded-md border border-border-default bg-surface-subtle p-2.5 text-text-secondary">
                <strong className="font-semibold text-text-primary">Counterpart Impact:</strong>{" "}
                {request.targetApplicantName || "Counterpart candidate"} will simultaneously move to{" "}
                <span className="font-mono font-semibold text-text-primary">{request.sourceVacancyVcode}</span>.
              </div>
            )}

            <div>
              <label
                htmlFor="amr-approval-note"
                className="block font-medium text-text-primary mb-1"
              >
                Approval Note / Remarks (Optional)
              </label>
              <textarea
                id="amr-approval-note"
                rows={2}
                value={approveNote}
                onChange={(e) => setApproveNote(e.target.value)}
                placeholder="Optional instruction or transition endorsement..."
                className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-border-brand focus:outline-hidden"
              />
            </div>

            {actionError && (
              <div className="flex items-center gap-2 rounded-md border border-border-danger bg-danger-subtle p-2.5 text-xs text-text-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={isBusy}
                className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md bg-brand-500 hover:bg-brand-600 px-4 py-1.5 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
              >
                {isBusy && <RefreshCw className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />}
                <span>Confirm & Advance Approval</span>
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* ── Reject Modal ── */}
      {isRejectOpen && (
        <Modal
          isOpen={isRejectOpen}
          onClose={() => setIsRejectOpen(false)}
          title="Reject Movement Request"
          subtitle={request.requestNumber}
          icon={XCircle}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-3 text-xs">
            <p className="text-text-secondary leading-relaxed">
              Rejecting this request will release any active slot reservations and retain{" "}
              <strong className="text-text-primary">{request.sourceApplicantName}</strong> at their current assignment.
            </p>

            <div>
              <label
                htmlFor="amr-rejection-reason"
                className="block font-medium text-text-primary mb-1"
              >
                Rejection Reason <span className="text-text-danger">*</span>
              </label>
              <textarea
                id="amr-rejection-reason"
                rows={3}
                value={rejectionReason}
                onChange={(e) => {
                  setRejectionReason(e.target.value);
                  if (rejectReasonError && e.target.value.trim()) {
                    setRejectReasonError(false);
                  }
                }}
                placeholder="State the justification or compliance reason for rejecting this movement request..."
                className={`w-full rounded-md border p-2 text-xs text-text-primary bg-surface placeholder:text-text-muted focus:outline-hidden ${
                  rejectReasonError
                    ? "border-border-danger focus:border-border-danger"
                    : "border-border-default focus:border-border-brand"
                }`}
              />
              {rejectReasonError && (
                <p className="mt-1 text-2xs text-text-danger font-medium">
                  A rejection reason is required before proceeding.
                </p>
              )}
            </div>

            {actionError && (
              <div className="flex items-center gap-2 rounded-md border border-border-danger bg-danger-subtle p-2.5 text-xs text-text-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={isBusy}
                className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md bg-danger-button hover:bg-danger-button-hover px-4 py-1.5 text-xs font-medium text-danger-button-text shadow-2xs disabled:opacity-50 transition cursor-pointer"
              >
                {isBusy && <RefreshCw className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />}
                <span>Confirm Rejection</span>
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
