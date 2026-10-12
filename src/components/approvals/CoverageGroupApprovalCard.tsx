"use client";

import { useState } from "react";
import {
  Building2,
  CheckCircle2,
  Clock,
  Layers,
  RefreshCw,
  User,
  X,
  XCircle,
} from "lucide-react";
import {
  useApproveCoverageRequest,
  useRejectCoverageRequest,
  type CoverageGroupRequestItem,
} from "@/lib/queries/requests";
import { useCurrentUser } from "@/lib/auth";

interface CoverageGroupApprovalCardProps {
  request: CoverageGroupRequestItem;
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return "—";
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
    const days = Math.floor(diffMs / (1000 * 60 * 60 * 24));
    if (days > 0) return `${days}d ago`;
    const hours = Math.floor(diffMs / (1000 * 60 * 60));
    if (hours > 0) return `${hours}h ago`;
    const mins = Math.floor(diffMs / (1000 * 60));
    return `${Math.max(1, mins)}m ago`;
  } catch {
    return "";
  }
}

function humanizeRequestType(type: string): string {
  switch (type) {
    case "create_coverage_group":
      return "Create Coverage Group";
    case "add_store":
      return "Add Store(s) to Group";
    case "remove_store":
      return "Remove Store(s) from Group";
    case "convert_stationary_to_roving":
      return "Convert Stationary to Roving";
    case "convert_roving_to_stationary":
      return "Convert Roving to Stationary";
    case "merge_coverage_groups":
      return "Merge Coverage Groups";
    case "dissolve_coverage_group":
      return "Dissolve Coverage Group";
    default:
      return type.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

export function CoverageGroupApprovalCard({
  request,
}: CoverageGroupApprovalCardProps) {
  const currentUser = useCurrentUser();
  const approveMutation = useApproveCoverageRequest();
  const rejectMutation = useRejectCoverageRequest();

  // Dialog & state
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [reviewerRemarks, setReviewerRemarks] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const isBusy = approveMutation.isPending || rejectMutation.isPending;

  // Role permissions: Head Admin or Super Admin
  const roleKey = currentUser?.roleKey?.toLowerCase() || "";
  const roleName = currentUser?.roleName?.toLowerCase() || "";
  const canReview =
    roleKey === "super_admin" ||
    roleKey === "head_admin" ||
    roleName.includes("super admin") ||
    roleName.includes("head admin");

  const ageDisplay = formatRelativeAge(request.createdAt);

  // Payload extraction
  const payload = request.payload || {};
  const storeIds = Array.isArray(payload.store_ids) ? payload.store_ids : [];
  const groupName =
    request.targetCoverageGroupName ||
    (typeof payload.group_name === "string" ? payload.group_name : null) ||
    "Roving Group";
  const groupCode =
    request.targetCoverageGroupCode ||
    (typeof payload.group_code === "string" ? payload.group_code : null);

  const handleOpenApprove = () => {
    setActionError(null);
    setReviewerRemarks("");
    setIsApproveOpen(true);
  };

  const handleOpenReject = () => {
    setActionError(null);
    setRejectionReason("");
    setIsRejectOpen(true);
  };

  const handleConfirmApprove = async () => {
    setActionError(null);
    try {
      await approveMutation.mutateAsync({
        coverageRequestId: request.id,
        reviewerRemarks: reviewerRemarks.trim() || undefined,
      });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve coverage structure request."
      );
    }
  };

  const handleConfirmReject = async () => {
    const trimmed = rejectionReason.trim();
    if (!trimmed) {
      setActionError("A rejection reason is required.");
      return;
    }
    setActionError(null);
    try {
      await rejectMutation.mutateAsync({
        coverageRequestId: request.id,
        rejectionReason: trimmed,
        reviewerRemarks: reviewerRemarks.trim() || undefined,
      });
      setIsRejectOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject coverage structure request."
      );
    }
  };

  return (
    <>
      <div className="rounded-xl border border-border-default bg-white p-5 shadow-xs transition hover:border-slate-300">
        {/* Top Meta Bar */}
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle pb-3.5">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded-full border border-indigo-200 bg-indigo-50 px-2.5 py-0.5 text-xs font-semibold text-indigo-700">
              <Layers className="h-3 w-3" />
              {humanizeRequestType(request.requestType)}
            </span>
            <span className="inline-flex items-center gap-1 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-0.5 text-2xs font-semibold uppercase tracking-wider text-amber-700">
              {request.status}
            </span>
          </div>

          <div className="flex items-center gap-2 text-xs text-text-tertiary">
            <Clock className="h-3.5 w-3.5" />
            <span>{formatDate(request.createdAt)}</span>
            {ageDisplay && (
              <span className="font-medium text-text-secondary">({ageDisplay})</span>
            )}
          </div>
        </div>

        {/* Target Scope & Coverage Details */}
        <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
          {/* Target Group */}
          <div className="rounded-lg border border-border-subtle bg-surface-subtle p-3.5">
            <div className="text-2xs font-semibold uppercase tracking-wider text-text-tertiary">
              Target Coverage Group
            </div>
            <div className="mt-1 flex items-center gap-2">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-indigo-100 text-indigo-700 font-bold text-xs">
                CG
              </div>
              <div className="min-w-0">
                <div className="text-sm font-semibold text-text-primary truncate">
                  {groupName}
                </div>
                <div className="font-mono text-2xs text-text-secondary">
                  {groupCode ? `Code: ${groupCode}` : "New Cluster Definition"}
                </div>
              </div>
            </div>
          </div>

          {/* Account / Store Allocation */}
          <div className="rounded-lg border border-border-subtle bg-surface-subtle p-3.5">
            <div className="text-2xs font-semibold uppercase tracking-wider text-text-tertiary">
              Scope & Allocation
            </div>
            <div className="mt-1 flex items-start gap-2">
              <Building2 className="h-4 w-4 text-brand-600 mt-0.5 shrink-0" />
              <div className="min-w-0">
                <div className="text-sm font-semibold text-text-primary truncate">
                  {request.accountName || "Account-Wide"}
                </div>
                <div className="text-2xs text-text-secondary">
                  {storeIds.length > 0 ? (
                    <span>
                      <strong className="font-mono text-brand-700">{storeIds.length}</strong> store
                      {storeIds.length !== 1 ? "s" : ""} impacted
                    </span>
                  ) : (
                    "Cluster-level configuration"
                  )}
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Requester & Metadata */}
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border-subtle bg-white px-3 py-2 text-xs">
          <div className="flex items-center gap-2 text-text-secondary">
            <User className="h-3.5 w-3.5 text-text-tertiary" />
            <span>
              Requested by <strong className="text-text-primary">{request.requestedByName}</strong>
              {request.requestedByRole && ` (${request.requestedByRole})`}
            </span>
          </div>

          {request.employmentType && (
            <div className="text-2xs text-text-tertiary">
              Employment: <span className="font-medium text-text-secondary">{request.employmentType}</span>
            </div>
          )}
        </div>

        {/* Stated Purpose & Justification */}
        {request.reason && (
          <div className="mt-3 rounded-lg border border-slate-100 bg-slate-50/70 p-3 text-xs leading-relaxed text-slate-700">
            <span className="font-semibold text-slate-900">Justification / Reason: </span>
            {request.reason}
          </div>
        )}

        {/* Card Actions Footer */}
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-border-subtle pt-3.5">
          <div className="text-2xs text-text-tertiary">
            Coverage Request ID: <span className="font-mono">{request.id.slice(0, 8)}</span>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleOpenReject}
              disabled={isBusy || !canReview}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-rose-200 bg-rose-50 px-3 text-xs font-semibold text-rose-700 shadow-2xs hover:bg-rose-100 disabled:cursor-not-allowed disabled:opacity-50 transition"
            >
              <XCircle className="h-3.5 w-3.5" />
              <span>Reject</span>
            </button>

            <button
              type="button"
              onClick={handleOpenApprove}
              disabled={isBusy || !canReview}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-brand-600 bg-brand-600 px-3.5 text-xs font-semibold text-white shadow-2xs hover:bg-brand-700 disabled:cursor-not-allowed disabled:opacity-50 transition"
            >
              <CheckCircle2 className="h-3.5 w-3.5" />
              <span>Approve Structure</span>
            </button>
          </div>
        </div>
      </div>

      {/* Approve Confirmation Modal */}
      {isApproveOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4"
        >
          <div
            className="fixed inset-0 bg-slate-900/40 backdrop-blur-xs transition-opacity"
            onClick={() => !isBusy && setIsApproveOpen(false)}
          />
          <div className="relative w-full max-w-md rounded-xl border border-border-default bg-white p-6 shadow-xl">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2.5">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                  <CheckCircle2 className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Approve Coverage Group Request
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Confirm cluster structural configuration
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => !isBusy && setIsApproveOpen(false)}
                disabled={isBusy}
                className="rounded-lg p-1 text-text-tertiary hover:bg-surface-hover hover:text-text-primary"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-4 space-y-3 text-xs leading-relaxed text-text-secondary">
              <p>
                You are approving the roving structural operation:{" "}
                <strong className="text-text-primary">{humanizeRequestType(request.requestType)}</strong> for{" "}
                <strong className="text-text-primary">{groupName}</strong>.
              </p>
              <div className="rounded-lg border border-amber-200 bg-amber-50 p-2.5 text-2xs text-amber-800">
                <span className="font-semibold">Note: </span>
                Approving this request records operational intent and updates status to approved.
              </div>

              <div>
                <label className="block text-2xs font-semibold uppercase tracking-wider text-text-tertiary mb-1">
                  Reviewer Remarks (Optional)
                </label>
                <textarea
                  value={reviewerRemarks}
                  onChange={(e) => setReviewerRemarks(e.target.value)}
                  placeholder="Add approval remarks or instructions..."
                  rows={2}
                  disabled={isBusy}
                  className="w-full rounded-md border border-border-default p-2 text-xs text-text-primary focus:border-brand-500 focus:outline-none"
                />
              </div>

              {actionError && (
                <div className="rounded-lg border border-rose-200 bg-rose-50 p-2.5 text-2xs text-rose-700">
                  {actionError}
                </div>
              )}
            </div>

            <div className="mt-5 flex items-center justify-end gap-2.5">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={isBusy}
                className="rounded-md border border-border-default px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md bg-emerald-600 px-4 py-1.5 text-xs font-semibold text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50"
              >
                {isBusy ? (
                  <>
                    <RefreshCw className="h-3 w-3 animate-spin" />
                    <span>Approving...</span>
                  </>
                ) : (
                  <span>Confirm Approval</span>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reject Reason Dialog */}
      {isRejectOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4"
        >
          <div
            className="fixed inset-0 bg-slate-900/40 backdrop-blur-xs transition-opacity"
            onClick={() => !isBusy && setIsRejectOpen(false)}
          />
          <div className="relative w-full max-w-md rounded-xl border border-border-default bg-white p-6 shadow-xl">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2.5">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-rose-100 text-rose-700">
                  <XCircle className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Reject Coverage Group Request
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Decline this roving cluster request
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => !isBusy && setIsRejectOpen(false)}
                disabled={isBusy}
                className="rounded-lg p-1 text-text-tertiary hover:bg-surface-hover hover:text-text-primary"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-4 space-y-3 text-xs leading-relaxed text-text-secondary">
              <p>
                Please provide an explanatory reason for declining the coverage request for{" "}
                <strong className="text-text-primary">{groupName}</strong>.
              </p>

              <div>
                <label className="block text-2xs font-semibold uppercase tracking-wider text-text-tertiary mb-1">
                  Rejection Reason <span className="text-rose-600">*</span>
                </label>
                <textarea
                  value={rejectionReason}
                  onChange={(e) => setRejectionReason(e.target.value)}
                  placeholder="e.g. Incompatible store clustering, overlapping coverage group, or invalid position..."
                  rows={3}
                  disabled={isBusy}
                  className="w-full rounded-md border border-border-default p-2 text-xs text-text-primary focus:border-rose-500 focus:outline-none"
                />
              </div>

              {actionError && (
                <div className="rounded-lg border border-rose-200 bg-rose-50 p-2.5 text-2xs text-rose-700">
                  {actionError}
                </div>
              )}
            </div>

            <div className="mt-5 flex items-center justify-end gap-2.5">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={isBusy}
                className="rounded-md border border-border-default px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md bg-rose-600 px-4 py-1.5 text-xs font-semibold text-white shadow-2xs hover:bg-rose-700 disabled:opacity-50"
              >
                {isBusy ? (
                  <>
                    <RefreshCw className="h-3 w-3 animate-spin" />
                    <span>Rejecting...</span>
                  </>
                ) : (
                  <span>Reject Request</span>
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
