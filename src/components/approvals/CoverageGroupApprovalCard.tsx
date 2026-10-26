"use client";

import { useState } from "react";
import {
  Building2,
  CheckCircle2,
  Clock,
  Layers,
  RefreshCw,
  User,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
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
      <div className="rounded-xl border border-border-default bg-surface p-5 shadow-xs transition hover:border-border-brand/40">
        {/* Top Meta Bar */}
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-default pb-3.5">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2.5 py-0.5 text-xs font-semibold text-text-primary">
              <Layers className="h-3 w-3" />
              {humanizeRequestType(request.requestType)}
            </span>
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2.5 py-0.5 text-2xs font-semibold text-text-secondary">
              {request.status}
            </span>
          </div>

          <div className="flex items-center gap-2 text-xs text-text-muted">
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
          <div className="rounded-lg border border-border-default bg-surface-subtle p-3.5">
            <div className="text-2xs font-semibold text-text-muted">
              Target Coverage Group
            </div>
            <div className="mt-1 flex items-center gap-2">
              <div className="flex h-8 w-8 items-center justify-center rounded-md border border-border-default bg-surface text-text-primary font-bold text-xs">
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
          <div className="rounded-lg border border-border-default bg-surface-subtle p-3.5">
            <div className="text-2xs font-semibold text-text-muted">
              Scope & Allocation
            </div>
            <div className="mt-1 flex items-start gap-2">
              <Building2 className="h-4 w-4 text-text-brand-bold mt-0.5 shrink-0" />
              <div className="min-w-0">
                <div className="text-sm font-semibold text-text-primary truncate">
                  {request.accountName || "Account-Wide"}
                </div>
                <div className="text-2xs text-text-secondary">
                  {storeIds.length > 0 ? (
                    <span>
                      <strong className="font-mono text-text-primary">{storeIds.length}</strong> store
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
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border-default bg-surface px-3 py-2 text-xs">
          <div className="flex items-center gap-2 text-text-secondary">
            <User className="h-3.5 w-3.5 text-text-muted" />
            <span>
              Requested by <strong className="text-text-primary">{request.requestedByName}</strong>
              {request.requestedByRole && ` (${request.requestedByRole})`}
            </span>
          </div>

          {request.employmentType && (
            <div className="text-2xs text-text-muted">
              Employment: <span className="font-medium text-text-secondary">{request.employmentType}</span>
            </div>
          )}
        </div>

        {/* Stated Purpose & Justification */}
        {request.reason && (
          <div className="mt-3 rounded-lg border border-border-default bg-surface-subtle p-3 text-xs leading-relaxed text-text-secondary">
            <span className="font-semibold text-text-primary">Justification / Reason: </span>
            {request.reason}
          </div>
        )}

        {/* Card Actions Footer */}
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-border-default pt-3.5">
          <div className="text-2xs text-text-muted">
            Coverage Request ID: <span className="font-mono">{request.id.slice(0, 8)}</span>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleOpenReject}
              disabled={isBusy || !canReview}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-danger/40 bg-surface-subtle px-3 text-xs font-semibold text-text-danger shadow-2xs hover:bg-danger-subtle disabled:cursor-not-allowed disabled:opacity-50 transition cursor-pointer"
            >
              <XCircle className="h-3.5 w-3.5" />
              <span>Reject</span>
            </button>

            <button
              type="button"
              onClick={handleOpenApprove}
              disabled={isBusy || !canReview}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border border-brand-500 bg-brand-500 hover:bg-brand-600 px-3.5 text-xs font-semibold text-white shadow-2xs disabled:cursor-not-allowed disabled:opacity-50 transition cursor-pointer"
            >
              <CheckCircle2 className="h-3.5 w-3.5" />
              <span>Approve Structure</span>
            </button>
          </div>
        </div>
      </div>

      {/* Approve Confirmation Modal */}
      {isApproveOpen && (
        <Modal
          isOpen={isApproveOpen}
          onClose={() => setIsApproveOpen(false)}
          title="Approve Coverage Group Request"
          subtitle="Confirm cluster structural configuration"
          icon={CheckCircle2}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-3 text-xs leading-relaxed text-text-secondary">
            <p>
              You are approving the roving structural operation:{" "}
              <strong className="text-text-primary">{humanizeRequestType(request.requestType)}</strong> for{" "}
              <strong className="text-text-primary">{groupName}</strong>.
            </p>
            <div className="rounded-lg border border-border-default bg-surface-subtle p-2.5 text-xs text-text-secondary">
              <span className="font-semibold text-text-primary">Note: </span>
              Approving this request records operational intent and updates status to approved.
            </div>

            <div>
              <label className="block text-2xs font-semibold text-text-muted mb-1">
                Reviewer Remarks (Optional)
              </label>
              <textarea
                value={reviewerRemarks}
                onChange={(e) => setReviewerRemarks(e.target.value)}
                placeholder="Add approval remarks or instructions..."
                rows={2}
                disabled={isBusy}
                className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-border-brand focus:outline-hidden"
              />
            </div>

            {actionError && (
              <div className="rounded-lg border border-border-danger bg-danger-subtle p-2.5 text-xs text-text-danger">
                {actionError}
              </div>
            )}

            <div className="flex items-center justify-end gap-2.5 pt-3 border-t border-border-default">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={isBusy}
                className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md bg-brand-500 hover:bg-brand-600 px-4 py-1.5 text-xs font-semibold text-white shadow-2xs disabled:opacity-50 cursor-pointer"
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
        </Modal>
      )}

      {/* Reject Reason Dialog */}
      {isRejectOpen && (
        <Modal
          isOpen={isRejectOpen}
          onClose={() => setIsRejectOpen(false)}
          title="Reject Coverage Group Request"
          subtitle="Decline this roving cluster request"
          icon={XCircle}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-3 text-xs leading-relaxed text-text-secondary">
            <p>
              Please provide an explanatory reason for declining the coverage request for{" "}
              <strong className="text-text-primary">{groupName}</strong>.
            </p>

            <div>
              <label className="block text-2xs font-semibold text-text-muted mb-1">
                Rejection Reason <span className="text-text-danger">*</span>
              </label>
              <textarea
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                placeholder="e.g. Incompatible store clustering, overlapping coverage group, or invalid position..."
                rows={3}
                disabled={isBusy}
                className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-border-brand focus:outline-hidden"
              />
            </div>

            {actionError && (
              <div className="rounded-lg border border-border-danger bg-danger-subtle p-2.5 text-xs text-text-danger">
                {actionError}
              </div>
            )}

            <div className="flex items-center justify-end gap-2.5 pt-3 border-t border-border-default">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={isBusy}
                className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md bg-danger-button hover:bg-danger-button-hover px-4 py-1.5 text-xs font-semibold text-danger-button-text shadow-2xs disabled:opacity-50 cursor-pointer"
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
        </Modal>
      )}
    </>
  );
}
