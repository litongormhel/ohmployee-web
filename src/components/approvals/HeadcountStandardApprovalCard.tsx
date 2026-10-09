"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Building2,
  CheckCircle2,
  Clock,
  User,
  Users,
  X,
  XCircle,
} from "lucide-react";
import {
  useApproveHeadcountRequest,
  useRejectHeadcountRequest,
  type HeadcountRequestItem,
} from "@/lib/queries/requests";

interface HeadcountStandardApprovalCardProps {
  request: HeadcountRequestItem;
}

export function HeadcountStandardApprovalCard({
  request,
}: HeadcountStandardApprovalCardProps) {
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [remarks, setRemarks] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const approveMutation = useApproveHeadcountRequest();
  const rejectMutation = useRejectHeadcountRequest();

  const handleOpenApprove = () => {
    setActionError(null);
    setRemarks("");
    setIsApproveOpen(true);
  };

  const handleOpenReject = () => {
    setActionError(null);
    setRemarks("");
    setIsRejectOpen(true);
  };

  const handleConfirmApprove = async () => {
    setActionError(null);
    try {
      await approveMutation.mutateAsync({
        requestId: request.id,
        remarks,
        isQuotaAmendment: false,
      });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      const errorMsg =
        err instanceof Error ? err.message : "Failed to approve headcount request.";
      setActionError(errorMsg);
    }
  };

  const handleConfirmReject = async () => {
    setActionError(null);
    try {
      await rejectMutation.mutateAsync({
        requestId: request.id,
        remarks,
      });
      setIsRejectOpen(false);
    } catch (err: unknown) {
      const errorMsg =
        err instanceof Error ? err.message : "Failed to reject headcount request.";
      setActionError(errorMsg);
    }
  };

  const formatDate = (dateStr: string | null) => {
    if (!dateStr) return "--";
    try {
      const d = new Date(dateStr);
      return d.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
      });
    } catch {
      return dateStr;
    }
  };

  return (
    <div className="rounded-lg border border-border-default bg-surface-base p-5 shadow-xs transition hover:border-slate-300">
      {/* Top Header */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs font-semibold text-blue-700">
              {request.requestType}
            </span>
            {request.urgency && (
              <span className="inline-flex items-center rounded border border-amber-200 bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700">
                {request.urgency} Urgency
              </span>
            )}
            {request.accountName && (
              <span className="text-xs font-medium text-text-muted">
                • {request.accountName}
              </span>
            )}
          </div>
          <h3 className="flex items-center gap-1.5 text-base font-semibold text-text-primary">
            <Building2 className="h-4 w-4 text-text-muted" aria-hidden="true" />
            <span>{request.storeName ?? "Unassigned Store"}</span>
            {request.positionName && (
              <span className="text-sm font-normal text-text-secondary">
                — {request.positionName}
              </span>
            )}
          </h3>
        </div>

        {/* Headcount Needed Pill */}
        <div className="inline-flex items-center gap-1.5 rounded-full border border-blue-200 bg-blue-50 px-3 py-1 font-mono text-xs font-semibold text-blue-800 shadow-2xs">
          <Users className="h-3.5 w-3.5 text-blue-600" />
          <span>+{request.headcountNeeded} requested</span>
        </div>
      </div>

      {/* Operational Justification */}
      <div className="mt-3.5 space-y-1">
        <p className="text-xs font-medium text-text-muted uppercase tracking-wider">
          Operational Justification
        </p>
        <p className="rounded-md border border-slate-150 bg-slate-50 px-3 py-2 text-xs leading-relaxed text-text-secondary">
          {request.reason?.trim() ? (
            request.reason
          ) : (
            <span className="italic text-text-muted">No operational justification provided.</span>
          )}
        </p>
      </div>

      {/* Footer: Requester Meta + Actions */}
      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-border-default pt-3">
        <div className="flex flex-wrap items-center gap-4 text-xs text-text-muted">
          <span className="flex items-center gap-1">
            <User className="h-3.5 w-3.5" />
            <span className="font-medium text-text-secondary">
              {request.requestedByName ?? "System Requester"}
            </span>
            {request.requestedByRole && (
              <span>({request.requestedByRole})</span>
            )}
          </span>
          <span className="flex items-center gap-1">
            <Clock className="h-3.5 w-3.5" />
            <span>{formatDate(request.requestedAt)}</span>
          </span>
        </div>

        {/* Action Buttons */}
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleOpenReject}
            disabled={rejectMutation.isPending || approveMutation.isPending}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-red-200 bg-white px-3 text-xs font-semibold text-red-600 shadow-2xs transition hover:bg-red-50 hover:border-red-300 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <XCircle className="h-3.5 w-3.5" />
            Reject
          </button>
          <button
            type="button"
            onClick={handleOpenApprove}
            disabled={rejectMutation.isPending || approveMutation.isPending}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-emerald-600 bg-emerald-600 px-3.5 text-xs font-semibold text-white shadow-2xs transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <CheckCircle2 className="h-3.5 w-3.5" />
            Approve
          </button>
        </div>
      </div>

      {/* Confirmation Dialog: APPROVE */}
      {isApproveOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-xs animate-in fade-in duration-150"
        >
          <div className="w-full max-w-lg rounded-xl border border-border-default bg-surface-base p-6 shadow-xl">
            <div className="flex items-center justify-between border-b border-border-default pb-3">
              <div className="flex items-center gap-2 text-base font-semibold text-text-primary">
                <CheckCircle2 className="h-5 w-5 text-emerald-600" />
                <span>Confirm Headcount Approval</span>
              </div>
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                className="rounded p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-4 space-y-3 text-xs text-text-secondary">
              <p>
                Approving this request will advance the requisition for{" "}
                <span className="font-semibold text-text-primary">
                  {request.storeName}
                </span>{" "}
                ({request.positionName}) requesting{" "}
                <span className="font-semibold text-text-primary">
                  +{request.headcountNeeded} headcount
                </span>.
              </p>

              {actionError && (
                <div className="rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
                  <div className="flex items-start gap-2">
                    <AlertTriangle className="h-4 w-4 shrink-0 text-red-500" />
                    <span>{actionError}</span>
                  </div>
                </div>
              )}

              <div>
                <label
                  htmlFor={`approve-std-remarks-${request.id}`}
                  className="block text-xs font-medium text-text-primary mb-1"
                >
                  Approver Remarks (Optional)
                </label>
                <textarea
                  id={`approve-std-remarks-${request.id}`}
                  rows={2}
                  value={remarks}
                  onChange={(e) => setRemarks(e.target.value)}
                  placeholder="Administrative approval remarks..."
                  className="w-full rounded-md border border-border-default bg-white p-2 text-xs text-text-primary shadow-2xs focus:border-brand-500 focus:outline-hidden"
                />
              </div>
            </div>

            <div className="mt-5 flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={approveMutation.isPending}
                className="h-8 rounded-md border border-border-default bg-white px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={approveMutation.isPending}
                className="inline-flex h-8 items-center gap-1.5 rounded-md border border-emerald-600 bg-emerald-600 px-4 text-xs font-semibold text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50"
              >
                {approveMutation.isPending ? "Approving..." : "Confirm Approval"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Confirmation Dialog: REJECT */}
      {isRejectOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-xs animate-in fade-in duration-150"
        >
          <div className="w-full max-w-lg rounded-xl border border-border-default bg-surface-base p-6 shadow-xl">
            <div className="flex items-center justify-between border-b border-border-default pb-3">
              <div className="flex items-center gap-2 text-base font-semibold text-text-primary">
                <XCircle className="h-5 w-5 text-red-600" />
                <span>Reject Headcount Request</span>
              </div>
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                className="rounded p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-4 space-y-3 text-xs text-text-secondary">
              <p>
                Are you sure you want to reject the headcount request for{" "}
                <span className="font-semibold text-text-primary">{request.storeName}</span>{" "}
                ({request.positionName})?
              </p>

              {actionError && (
                <div className="rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
                  <div className="flex items-start gap-2">
                    <AlertTriangle className="h-4 w-4 shrink-0 text-red-500" />
                    <span>{actionError}</span>
                  </div>
                </div>
              )}

              <div>
                <label
                  htmlFor={`reject-std-remarks-${request.id}`}
                  className="block text-xs font-medium text-text-primary mb-1"
                >
                  Rejection Reason / Remarks <span className="text-red-500">*</span>
                </label>
                <textarea
                  id={`reject-std-remarks-${request.id}`}
                  rows={2}
                  value={remarks}
                  onChange={(e) => setRemarks(e.target.value)}
                  placeholder="State operational reason for rejecting this request..."
                  className="w-full rounded-md border border-border-default bg-white p-2 text-xs text-text-primary shadow-2xs focus:border-red-500 focus:outline-hidden"
                />
              </div>
            </div>

            <div className="mt-5 flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={rejectMutation.isPending}
                className="h-8 rounded-md border border-border-default bg-white px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={rejectMutation.isPending}
                className="inline-flex h-8 items-center gap-1.5 rounded-md border border-red-600 bg-red-600 px-4 text-xs font-semibold text-white shadow-2xs hover:bg-red-700 disabled:opacity-50"
              >
                {rejectMutation.isPending ? "Rejecting..." : "Confirm Rejection"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
