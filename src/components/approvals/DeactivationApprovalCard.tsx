"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Briefcase,
  Building2,
  CheckCircle2,
  Clock,
  Layers,
  MessageSquare,
  RefreshCw,
  ShieldAlert,
  User,
  UserMinus,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  useCompleteDeactivation,
  useRejectDeactivation,
  type DeactivationRequestItem,
} from "@/lib/queries/requests";

interface DeactivationApprovalCardProps {
  request: DeactivationRequestItem;
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

export function DeactivationApprovalCard({
  request,
}: DeactivationApprovalCardProps) {
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [approveRemarks, setApproveRemarks] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
  const [rejectionRemarks, setRejectionRemarks] = useState("");
  const [rejectReasonError, setRejectReasonError] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const completeMutation = useCompleteDeactivation();
  const rejectMutation = useRejectDeactivation();

  const handleOpenApprove = () => {
    setActionError(null);
    setApproveRemarks("");
    setIsApproveOpen(true);
  };

  const handleOpenReject = () => {
    setActionError(null);
    setRejectionReason("");
    setRejectionRemarks("");
    setRejectReasonError(false);
    setIsRejectOpen(true);
  };

  const handleConfirmApprove = async () => {
    setActionError(null);
    try {
      await completeMutation.mutateAsync({
        requestId: request.id,
        plantillaId: request.plantillaId,
        remarks: approveRemarks.trim() || undefined,
      });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to complete employee deactivation."
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
        plantillaId: request.plantillaId,
        reason: rejectionReason.trim(),
        remarks: rejectionRemarks.trim() || undefined,
      });
      setIsRejectOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject deactivation request."
      );
    }
  };

  const isBusy = completeMutation.isPending || rejectMutation.isPending;
  const relativeAge = formatRelativeAge(request.requestedAt);

  return (
    <div className="rounded-lg border border-border-default bg-surface p-5 shadow-xs transition hover:border-border-brand/40">
      {/* Top Header: Category badge + Employee No + Account & Group */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-semibold text-text-primary">
              <UserMinus className="h-3 w-3" aria-hidden="true" />
              Deactivation
            </span>

            {request.employeeNo && (
              <span className="inline-flex items-center rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 font-mono text-xs font-semibold text-text-secondary">
                ID: {request.employeeNo}
              </span>
            )}

            <span className="inline-flex items-center rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-secondary">
              {request.accountName}
            </span>

            {request.groupName && (
              <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-secondary">
                <Layers className="h-3 w-3 text-text-muted" aria-hidden="true" />
                {request.groupName}
              </span>
            )}

            {request.resubmitCount > 0 && (
              <span className="inline-flex items-center rounded-md bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-medium text-text-secondary">
                Resubmit #{request.resubmitCount}
              </span>
            )}

            <span className="inline-flex items-center rounded-md bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-medium text-text-secondary">
              Pending Clearance
            </span>
          </div>

          <h3 className="flex items-center gap-1.5 text-base font-semibold text-text-primary">
            <User className="h-4 w-4 shrink-0 text-text-muted" aria-hidden="true" />
            <span className="truncate">{request.employeeName}</span>
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
            <span>Approve Deactivation</span>
          </button>
        </div>
      </div>

      {/* Employee Context Grid */}
      <div className="mt-4 grid grid-cols-1 md:grid-cols-3 gap-3 rounded-md border border-border-default bg-surface-subtle p-3 text-xs">
        {/* Position Title */}
        <div className="flex items-center gap-2">
          <Briefcase className="h-4 w-4 shrink-0 text-text-muted" aria-hidden="true" />
          <div className="min-w-0">
            <div className="text-2xs font-medium text-text-muted">Position</div>
            <div className="truncate font-semibold text-text-primary">
              {request.positionTitle || "Position Unspecified"}
            </div>
          </div>
        </div>

        {/* Assigned Store */}
        <div className="flex items-center gap-2">
          <Building2 className="h-4 w-4 shrink-0 text-text-muted" aria-hidden="true" />
          <div className="min-w-0">
            <div className="text-2xs font-medium text-text-muted">Assigned Store / Outlet</div>
            <div className="truncate font-semibold text-text-primary">
              {request.storeName || "Store Unassigned"}
            </div>
          </div>
        </div>

        {/* Separation Status Rationale */}
        <div className="flex items-center gap-2">
          <ShieldAlert className="h-4 w-4 shrink-0 text-text-secondary" aria-hidden="true" />
          <div className="min-w-0">
            <div className="text-2xs font-medium text-text-muted">Separation Status</div>
            <div className="inline-flex items-center rounded-md border border-border-default bg-surface px-2 py-0.5 text-xs font-semibold text-text-primary">
              {request.separationStatus}
            </div>
          </div>
        </div>
      </div>

      {/* Requester Remarks / Rationale */}
      {request.remarks && (
        <div className="mt-3.5 rounded-md border border-border-default bg-surface p-3 text-xs">
          <div className="flex items-start gap-2">
            <MessageSquare className="mt-0.5 h-3.5 w-3.5 shrink-0 text-text-muted" aria-hidden="true" />
            <div>
              <span className="font-medium text-text-primary">Requester Remarks:</span>{" "}
              <span className="text-text-secondary italic">&ldquo;{request.remarks}&rdquo;</span>
            </div>
          </div>
        </div>
      )}

      {/* Footer Metadata: Requester profile & Timestamp */}
      <div className="mt-3.5 flex flex-wrap items-center justify-between gap-3 border-t border-border-default pt-3 text-xs text-text-secondary">
        <div className="flex items-center gap-1.5">
          <User className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
          <span>
            Requested by <strong className="text-text-primary font-medium">{request.requestedByName}</strong>
          </span>
        </div>

        <div className="flex items-center gap-1 text-text-muted">
          <Clock className="h-3.5 w-3.5" aria-hidden="true" />
          <span>Requested: {formatDate(request.requestedAt)}</span>
          {relativeAge && <span className="font-mono text-2xs">({relativeAge})</span>}
        </div>
      </div>

      {/* ── Approve Modal (Clearance Confirmation) ── */}
      {isApproveOpen && (
        <Modal
          isOpen={isApproveOpen}
          onClose={() => setIsApproveOpen(false)}
          title="Clear & Deactivate Employee"
          subtitle={request.employeeName}
          icon={CheckCircle2}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-3 text-xs">
            <p className="text-text-secondary leading-relaxed">
              Approving this deactivation will transition employee{" "}
              <strong className="text-text-primary">{request.employeeName}</strong> (
              {request.employeeNo || "No ID"}) to <strong>Deactivated</strong> status, clear plant allocation,
              and maintain compliance records under the 15-day deactivation visibility window.
            </p>

            <div className="rounded-md border border-border-default bg-surface-subtle p-2.5 text-text-secondary">
              <div className="font-medium text-text-primary">Clearance Impact:</div>
              <ul className="mt-1 list-disc pl-4 space-y-0.5">
                <li>Plantilla slot marked deactivated</li>
                <li>Account access disabled</li>
                <li>Requisition slot unlocked for backfill</li>
              </ul>
            </div>

            <div>
              <label
                htmlFor="deact-approval-remarks"
                className="block font-medium text-text-primary mb-1"
              >
                Clearance Remarks / Administrative Note (Optional)
              </label>
              <textarea
                id="deact-approval-remarks"
                rows={2}
                value={approveRemarks}
                onChange={(e) => setApproveRemarks(e.target.value)}
                placeholder="Final clearance notes or separation confirmation..."
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
                <span>Confirm Deactivation</span>
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* ── Reject Modal (Revert Separation) ── */}
      {isRejectOpen && (
        <Modal
          isOpen={isRejectOpen}
          onClose={() => setIsRejectOpen(false)}
          title="Reject Deactivation Request"
          subtitle={request.employeeName}
          icon={XCircle}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-3 text-xs">
            <p className="text-text-secondary leading-relaxed">
              Rejecting this request will mark the request as Rejected and retain{" "}
              <strong className="text-text-primary">{request.employeeName}</strong> for Operations review and potential resubmission.
            </p>

            <div>
              <label
                htmlFor="deact-rejection-reason"
                className="block font-medium text-text-primary mb-1"
              >
                Rejection Reason <span className="text-text-danger">*</span>
              </label>
              <input
                id="deact-rejection-reason"
                type="text"
                value={rejectionReason}
                onChange={(e) => {
                  setRejectionReason(e.target.value);
                  if (rejectReasonError && e.target.value.trim()) {
                    setRejectReasonError(false);
                  }
                }}
                placeholder="e.g. Clearance incomplete, Pending turnover, Record discrepancy"
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

            <div>
              <label
                htmlFor="deact-rejection-remarks"
                className="block font-medium text-text-primary mb-1"
              >
                Additional Remarks / Instructions (Optional)
              </label>
              <textarea
                id="deact-rejection-remarks"
                rows={2}
                value={rejectionRemarks}
                onChange={(e) => setRejectionRemarks(e.target.value)}
                placeholder="Provide specific notes or steps required by requester..."
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
