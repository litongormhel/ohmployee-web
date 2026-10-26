"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Archive,
  Building2,
  Briefcase,
  CheckCircle2,
  Clock,
  FileText,
  RefreshCw,
  User,
  X,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useCurrentUser } from "@/lib/auth";
import {
  useReviewVacancyClosureRequest,
  type VacancyClosureRequestItem,
} from "@/lib/queries/requests";

interface VacancyClosureApprovalCardProps {
  request: VacancyClosureRequestItem;
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

export function VacancyClosureApprovalCard({
  request,
}: VacancyClosureApprovalCardProps) {
  const currentUser = useCurrentUser();
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [approveRemarks, setApproveRemarks] = useState("");
  const [rejectionRemarks, setRejectionRemarks] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const reviewMutation = useReviewVacancyClosureRequest();

  const reviewerName =
    currentUser?.displayName || currentUser?.email || "Admin Reviewer";

  const handleOpenApprove = () => {
    setActionError(null);
    setApproveRemarks("");
    setIsApproveOpen(true);
  };

  const handleOpenReject = () => {
    setActionError(null);
    setRejectionRemarks("");
    setIsRejectOpen(true);
  };

  const handleConfirmApprove = async () => {
    setActionError(null);
    try {
      await reviewMutation.mutateAsync({
        requestId: request.id,
        status: "Approved",
        reviewedBy: reviewerName,
        remarks: approveRemarks.trim() || undefined,
      });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve vacancy closure request."
      );
    }
  };

  const handleConfirmReject = async () => {
    setActionError(null);
    try {
      await reviewMutation.mutateAsync({
        requestId: request.id,
        status: "Rejected",
        reviewedBy: reviewerName,
        remarks: rejectionRemarks.trim() || undefined,
      });
      setIsRejectOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject vacancy closure request."
      );
    }
  };

  const isBusy = reviewMutation.isPending;

  return (
    <div className="rounded-lg border border-border-default bg-surface-base p-5 shadow-xs transition hover:border-border-strong">
      {/* Top Header: VCode mono pill + Category badge + Position */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-subtle px-2 py-0.5 font-mono text-xs font-semibold text-text-primary">
              {request.vacancyVcode}
            </span>
            <span className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-secondary">
              <Archive className="h-3 w-3" aria-hidden="true" />
              Closure Request
            </span>
            {request.account && (
              <span className="text-xs font-medium text-text-muted">
                • {request.account}
              </span>
            )}
            <span className="inline-flex items-center rounded-full border border-border-default bg-surface-subtle px-2 py-0.5 text-[11px] font-medium text-text-secondary">
              Pending
            </span>
          </div>

          <h3 className="flex items-center gap-1.5 text-base font-semibold text-text-primary">
            <Briefcase className="h-4 w-4 shrink-0 text-text-muted" aria-hidden="true" />
            <span>{request.position || "Position Unspecified"}</span>
            {request.storeName && (
              <span className="text-sm font-normal text-text-secondary">
                — {request.storeName}
                {request.storeBranch ? ` (${request.storeBranch})` : ""}
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
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-default bg-surface px-3 text-xs font-medium text-danger-text shadow-2xs hover:bg-surface-hover disabled:opacity-50 transition"
          >
            <XCircle className="h-3.5 w-3.5" aria-hidden="true" />
            <span>Reject</span>
          </button>
          <button
            type="button"
            onClick={handleOpenApprove}
            disabled={isBusy}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-transparent bg-brand-500 px-3 text-xs font-medium text-white shadow-2xs hover:bg-brand-600 disabled:opacity-50 transition"
          >
            <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
            <span>Approve Closure</span>
          </button>
        </div>
      </div>

      {/* Action Error Banner */}
      {actionError && (
        <div className="mt-3 flex items-start gap-2 rounded-md border border-danger-border bg-danger-subtle p-2.5 text-xs text-danger-text">
          <AlertTriangle className="h-4 w-4 shrink-0 text-danger-icon mt-0.5" />
          <div className="flex-1">{actionError}</div>
          <button
            type="button"
            onClick={() => setActionError(null)}
            className="text-danger-text hover:opacity-80"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      {/* Structured Metadata Grid */}
      <div className="mt-4 grid grid-cols-1 gap-3 rounded-md border border-border-default bg-surface-subtle p-3.5 text-xs sm:grid-cols-2 lg:grid-cols-4">
        {/* Target VCode */}
        <div>
          <span className="block font-medium text-text-muted">Target VCode</span>
          <span className="mt-0.5 block font-mono font-semibold text-text-primary">
            {request.vacancyVcode}
          </span>
        </div>

        {/* Position */}
        <div>
          <span className="block font-medium text-text-muted">Position</span>
          <span className="mt-0.5 block font-semibold text-text-primary">
            {request.position || "—"}
          </span>
        </div>

        {/* Outlet / Store */}
        <div>
          <span className="block font-medium text-text-muted">Outlet / Store</span>
          <span className="mt-0.5 flex items-center gap-1 font-semibold text-text-primary">
            <Building2 className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
            <span className="truncate">{request.storeName || "—"}</span>
          </span>
        </div>

        {/* Requester & Date */}
        <div>
          <span className="block font-medium text-text-muted">Requested By</span>
          <div className="mt-0.5 flex items-center gap-1.5 font-medium text-text-primary">
            <User className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
            <span className="truncate">{request.requestedBy || "Ops Requester"}</span>
          </div>
          <span className="flex items-center gap-1 text-[11px] text-text-secondary mt-0.5">
            <Clock className="h-3 w-3" aria-hidden="true" />
            {formatDate(request.createdAt)}
          </span>
        </div>
      </div>

      {/* Closure Justification */}
      <div className="mt-3 rounded-md border border-border-default bg-surface p-3 text-xs">
        <div className="flex items-center gap-1.5 font-medium text-text-secondary">
          <FileText className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
          <span>Closure Justification</span>
        </div>
        <p className="mt-1 font-medium text-text-primary">
          {request.reason || <span className="italic text-text-muted">No primary reason stated.</span>}
        </p>
        {request.details && (
          <p className="mt-1 text-text-secondary leading-relaxed whitespace-pre-wrap border-t border-border-default pt-1.5">
            {request.details}
          </p>
        )}
      </div>

      {/* ── Approve Modal ─────────────────────────────────────────────────────── */}
      <Modal
        isOpen={isApproveOpen}
        onClose={() => setIsApproveOpen(false)}
        title="Approve Vacancy Closure"
        subtitle={`Archive requisition ${request.vacancyVcode}`}
        isSubmitting={isBusy}
        disableBackdropClick={isBusy}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setIsApproveOpen(false)}
              disabled={isBusy}
              className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleConfirmApprove}
              disabled={isBusy}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-500 px-4 py-1.5 text-xs font-medium text-white hover:bg-brand-600 disabled:opacity-50 transition"
            >
              {isBusy ? (
                <>
                  <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                  <span>Archiving Vacancy...</span>
                </>
              ) : (
                <>
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  <span>Confirm &amp; Close</span>
                </>
              )}
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          <div className="rounded-lg border border-border-default bg-surface-subtle p-3 text-xs space-y-1.5">
            <div className="flex justify-between">
              <span className="text-text-muted">VCode:</span>
              <span className="font-mono font-semibold text-text-primary">{request.vacancyVcode}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-muted">Position:</span>
              <span className="font-medium text-text-primary">{request.position || "—"}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-muted">Outlet:</span>
              <span className="font-medium text-text-primary">{request.storeName || "—"}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-text-muted">Justification:</span>
              <span className="font-medium text-text-primary">{request.reason}</span>
            </div>
          </div>

          <div>
            <label
              htmlFor={`approve-remarks-${request.id}`}
              className="block text-xs font-medium text-text-primary"
            >
              Reviewer Remarks (Optional)
            </label>
            <input
              id={`approve-remarks-${request.id}`}
              type="text"
              placeholder="Optional notes for closure approval..."
              value={approveRemarks}
              onChange={(e) => setApproveRemarks(e.target.value)}
              className="mt-1.5 w-full rounded-md border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
            />
          </div>

          <p className="text-xs text-text-secondary leading-relaxed">
            Upon approval, the vacancy will be permanently closed and archived, and any linked open plantilla slots will be reconciled.
          </p>
        </div>
      </Modal>

      {/* ── Reject Modal ──────────────────────────────────────────────────────── */}
      <Modal
        isOpen={isRejectOpen}
        onClose={() => setIsRejectOpen(false)}
        title="Reject Vacancy Closure"
        subtitle={`Decline closure request for ${request.vacancyVcode}`}
        isSubmitting={isBusy}
        disableBackdropClick={isBusy}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setIsRejectOpen(false)}
              disabled={isBusy}
              className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleConfirmReject}
              disabled={isBusy}
              className="inline-flex items-center gap-1.5 rounded-md bg-danger-button px-4 py-1.5 text-xs font-medium text-danger-button-text hover:bg-danger-button-hover disabled:opacity-50 transition"
            >
              {isBusy ? (
                <>
                  <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                  <span>Rejecting...</span>
                </>
              ) : (
                <>
                  <XCircle className="h-3.5 w-3.5" />
                  <span>Reject Request</span>
                </>
              )}
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          <div>
            <label
              htmlFor={`rejection-remarks-${request.id}`}
              className="block text-xs font-medium text-text-primary"
            >
              Rejection Remarks
            </label>
            <textarea
              id={`rejection-remarks-${request.id}`}
              rows={3}
              placeholder="Reason for declining this closure request..."
              value={rejectionRemarks}
              onChange={(e) => setRejectionRemarks(e.target.value)}
              className="mt-1.5 w-full rounded-md border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
            />
          </div>
        </div>
      </Modal>
    </div>
  );
}
