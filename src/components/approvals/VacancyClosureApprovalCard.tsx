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
    <div className="rounded-lg border border-border-default bg-surface-base p-5 shadow-xs transition hover:border-slate-300">
      {/* Top Header: VCode mono pill + Category badge + Position */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded border border-indigo-200 bg-indigo-50 px-2 py-0.5 font-mono text-xs font-semibold text-indigo-700">
              {request.vacancyVcode}
            </span>
            <span className="inline-flex items-center gap-1 rounded border border-amber-200 bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-800">
              <Archive className="h-3 w-3" aria-hidden="true" />
              Closure Request
            </span>
            {request.account && (
              <span className="text-xs font-medium text-text-muted">
                • {request.account}
              </span>
            )}
            <span className="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800">
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
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-rose-200 bg-rose-50 px-3 text-xs font-medium text-rose-700 shadow-2xs hover:bg-rose-100 disabled:opacity-50 transition"
          >
            <XCircle className="h-3.5 w-3.5" aria-hidden="true" />
            <span>Reject</span>
          </button>
          <button
            type="button"
            onClick={handleOpenApprove}
            disabled={isBusy}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-emerald-300 bg-emerald-600 px-3 text-xs font-medium text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50 transition"
          >
            <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
            <span>Approve Closure</span>
          </button>
        </div>
      </div>

      {/* Action Error Banner */}
      {actionError && (
        <div className="mt-3 flex items-start gap-2 rounded-md border border-rose-200 bg-rose-50 p-2.5 text-xs text-rose-800">
          <AlertTriangle className="h-4 w-4 shrink-0 text-rose-600 mt-0.5" />
          <div className="flex-1">{actionError}</div>
          <button
            type="button"
            onClick={() => setActionError(null)}
            className="text-rose-500 hover:text-rose-700"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      {/* Structured Metadata Grid */}
      <div className="mt-4 grid grid-cols-1 gap-3 rounded-md border border-border-default bg-slate-50/60 p-3.5 text-xs sm:grid-cols-2 lg:grid-cols-4">
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
      <div className="mt-3 rounded-md border border-slate-200/80 bg-white p-3 text-xs">
        <div className="flex items-center gap-1.5 font-medium text-text-secondary">
          <FileText className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
          <span>Closure Justification</span>
        </div>
        <p className="mt-1 font-medium text-text-primary">
          {request.reason || <span className="italic text-text-muted">No primary reason stated.</span>}
        </p>
        {request.details && (
          <p className="mt-1 text-text-secondary leading-relaxed whitespace-pre-wrap border-t border-slate-100 pt-1.5">
            {request.details}
          </p>
        )}
      </div>

      {/* ── Approve Modal ─────────────────────────────────────────────────────── */}
      {isApproveOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                  <CheckCircle2 className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Approve Vacancy Closure
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Archive requisition {request.vacancyVcode}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={reviewMutation.isPending}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-1.5">
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

            <div className="mt-4">
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
                className="mt-1.5 w-full rounded-md border border-border-default bg-white p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>

            <p className="mt-3 text-xs text-text-secondary leading-relaxed">
              Upon approval, the vacancy will be permanently closed and archived, and any linked open plantilla slots will be reconciled.
            </p>

            <div className="mt-6 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={reviewMutation.isPending}
                className="rounded-md border border-border-default bg-white px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={reviewMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-md bg-emerald-600 px-4 py-1.5 text-xs font-medium text-white hover:bg-emerald-700 disabled:opacity-50 transition"
              >
                {reviewMutation.isPending ? (
                  <>
                    <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                    <span>Archiving Vacancy...</span>
                  </>
                ) : (
                  <>
                    <CheckCircle2 className="h-3.5 w-3.5" />
                    <span>Confirm & Close</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Reject Modal ──────────────────────────────────────────────────────── */}
      {isRejectOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-rose-100 text-rose-700">
                  <XCircle className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Reject Vacancy Closure
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Decline closure request for {request.vacancyVcode}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={reviewMutation.isPending}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-4">
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
                className="mt-1.5 w-full rounded-md border border-border-default bg-white p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>

            <div className="mt-6 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={reviewMutation.isPending}
                className="rounded-md border border-border-default bg-white px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={reviewMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-md bg-rose-600 px-4 py-1.5 text-xs font-medium text-white hover:bg-rose-700 disabled:opacity-50 transition"
              >
                {reviewMutation.isPending ? (
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
          </div>
        </div>
      )}
    </div>
  );
}
