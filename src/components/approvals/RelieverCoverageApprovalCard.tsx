"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Calendar,
  CheckCircle2,
  Clock,
  MapPin,
  RefreshCw,
  ShieldAlert,
  User,
  Users,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  useApproveRelieverCoverage,
  useRejectRelieverCoverage,
  type RelieverEndorsementItem,
} from "@/lib/queries/requests";
import { useCurrentUser } from "@/lib/auth";

interface RelieverCoverageApprovalCardProps {
  request: RelieverEndorsementItem;
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return "—";
  try {
    return new Date(dateStr).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  } catch {
    return dateStr;
  }
}

function formatRelativeAge(dateStr: string | null, ageDays: number | null): string {
  if (ageDays !== null && ageDays !== undefined) {
    if (ageDays === 0) return "Today";
    return `${ageDays}d ago`;
  }
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

function calculateDurationDays(start: string | null, end: string | null): number | null {
  if (!start || !end) return null;
  try {
    const s = new Date(start).getTime();
    const e = new Date(end).getTime();
    const diff = Math.round((e - s) / (1000 * 60 * 60 * 24)) + 1;
    return diff > 0 ? diff : null;
  } catch {
    return null;
  }
}

export function RelieverCoverageApprovalCard({
  request,
}: RelieverCoverageApprovalCardProps) {
  const currentUser = useCurrentUser();
  const approveMutation = useApproveRelieverCoverage();
  const rejectMutation = useRejectRelieverCoverage();

  // Dialog & state
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [approveNotes, setApproveNotes] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const isBusy = approveMutation.isPending || rejectMutation.isPending;

  // Role permissions: Data Team (30), Head Admin (90), Super Admin (100) or full access
  const roleKey = currentUser?.roleKey?.toLowerCase() || "";
  const roleName = currentUser?.roleName?.toLowerCase() || "";
  const canReview =
    roleKey === "super_admin" ||
    roleKey === "head_admin" ||
    roleKey === "data_team" ||
    roleName.includes("super admin") ||
    roleName.includes("head admin") ||
    roleName.includes("data team");

  // Pool Type styling
  const poolType = request.poolType || "MOSES HQ Pool";
  const escalation = request.escalationLevel || "Normal";

  const durationDays = calculateDurationDays(request.startDate, request.endDate);
  const ageDisplay = formatRelativeAge(request.createdAt, request.requestAgeDays);

  const handleOpenApprove = () => {
    setActionError(null);
    setApproveNotes("");
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
        requestId: request.requestId,
        notes: approveNotes.trim() || undefined,
      });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve reliever coverage request."
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
        requestId: request.requestId,
        reason: trimmed,
      });
      setIsRejectOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject reliever coverage request."
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
              <Users className="h-3 w-3" />
              {poolType}
            </span>
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2.5 py-0.5 text-xs font-semibold text-text-secondary">
              <AlertTriangle className="h-3 w-3" />
              {request.priority || "Normal"}
            </span>
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-2xs font-medium text-text-secondary">
              <ShieldAlert className="h-3 w-3" />
              SLA: {escalation}
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

        {/* Reliever & Deployment Route Card */}
        <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
          {/* Employee Info */}
          <div className="rounded-lg border border-border-default bg-surface-subtle p-3.5">
            <div className="text-2xs font-semibold text-text-muted">
              Requested Reliever
            </div>
            <div className="mt-1 flex items-center gap-2">
              <div className="flex h-8 w-8 items-center justify-center rounded-md border border-border-default bg-surface text-text-primary font-bold text-xs">
                {(request.employeeName || "E").charAt(0).toUpperCase()}
              </div>
              <div className="min-w-0">
                <div className="text-sm font-semibold text-text-primary truncate">
                  {request.employeeName || "Unnamed Employee"}
                </div>
                <div className="font-mono text-2xs text-text-secondary">
                  {request.employeeNumber ? `ID: ${request.employeeNumber}` : "No Employee Number"}
                </div>
              </div>
            </div>
          </div>

          {/* Target Location & Assignment */}
          <div className="rounded-lg border border-border-default bg-surface-subtle p-3.5">
            <div className="text-2xs font-semibold text-text-muted">
              Target Assignment Scope
            </div>
            <div className="mt-1 flex items-start gap-2">
              <MapPin className="h-4 w-4 text-text-brand-bold mt-0.5 shrink-0" />
              <div className="min-w-0">
                <div className="text-sm font-semibold text-text-primary truncate">
                  {request.requestedStore || "Unassigned Store"}
                </div>
                <div className="flex flex-wrap items-center gap-1.5 text-2xs text-text-secondary">
                  <span>{request.requestedAccount || "Direct"}</span>
                  {request.requestedGroup && (
                    <>
                      <span>•</span>
                      <span className="rounded-md border border-border-default bg-surface px-1 py-0.2 font-medium text-text-primary">
                        {request.requestedGroup}
                      </span>
                    </>
                  )}
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Coverage Schedule & Duration */}
        <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <div className="flex items-center gap-2.5 rounded-lg border border-border-default px-3 py-2 bg-surface">
            <Calendar className="h-4 w-4 text-text-brand-bold shrink-0" />
            <div className="min-w-0">
              <div className="text-2xs text-text-muted">Coverage Period</div>
              <div className="text-xs font-semibold text-text-primary">
                {formatDate(request.startDate)} – {formatDate(request.endDate)}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2.5 rounded-lg border border-border-default px-3 py-2 bg-surface">
            <Clock className="h-4 w-4 text-text-secondary shrink-0" />
            <div className="min-w-0">
              <div className="text-2xs text-text-muted">Total Duration</div>
              <div className="text-xs font-semibold text-text-primary">
                {durationDays !== null ? (
                  <span>
                    <strong className="font-sans tabular-nums font-semibold text-text-primary">{durationDays}</strong> day
                    {durationDays !== 1 ? "s" : ""} deployment
                  </span>
                ) : (
                  "Open-ended"
                )}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2.5 rounded-lg border border-border-default px-3 py-2 bg-surface sm:col-span-2 lg:col-span-1">
            <User className="h-4 w-4 text-text-muted shrink-0" />
            <div className="min-w-0">
              <div className="text-2xs text-text-muted">Endorsed By</div>
              <div className="text-xs font-semibold text-text-primary truncate">
                {request.requestedBy || "Operations Requester"}
              </div>
            </div>
          </div>
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
            Request ID: <span className="font-mono">{request.requestId.slice(0, 8)}</span>
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
              <span>Approve Deployment</span>
            </button>
          </div>
        </div>
      </div>

      {/* Approve Confirmation Modal */}
      {isApproveOpen && (
        <Modal
          isOpen={isApproveOpen}
          onClose={() => setIsApproveOpen(false)}
          title="Approve Reliever Endorsement"
          subtitle="Create active workforce assignment record"
          icon={CheckCircle2}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-3 text-xs leading-relaxed text-text-secondary">
            <p>
              You are approving the temporary deployment of{" "}
              <strong className="text-text-primary">{request.employeeName}</strong> to{" "}
              <strong className="text-text-primary">{request.requestedStore}</strong>.
            </p>
            <div className="rounded-lg border border-border-default bg-surface-subtle p-3 space-y-1 text-2xs">
              <div>
                <span className="font-semibold text-text-muted">Period: </span>
                <span className="font-medium text-text-primary">
                  {formatDate(request.startDate)} – {formatDate(request.endDate)}
                  {durationDays !== null ? ` (${durationDays} days)` : ""}
                </span>
              </div>
              <div>
                <span className="font-semibold text-text-muted">Store & Account: </span>
                <span className="font-medium text-text-primary">
                  {request.requestedAccount} / {request.requestedStore}
                </span>
              </div>
            </div>

            <div>
              <label className="block text-2xs font-semibold text-text-muted mb-1">
                Reviewer Notes (Optional)
              </label>
              <textarea
                value={approveNotes}
                onChange={(e) => setApproveNotes(e.target.value)}
                placeholder="Add deployment remarks or special instructions..."
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
          title="Reject Reliever Endorsement"
          subtitle="Decline this workforce deployment request"
          icon={XCircle}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-3 text-xs leading-relaxed text-text-secondary">
            <p>
              Please provide an explanatory reason for declining the deployment request for{" "}
              <strong className="text-text-primary">{request.employeeName}</strong>. The requester will be notified.
            </p>

            <div>
              <label className="block text-2xs font-semibold text-text-muted mb-1">
                Rejection Reason <span className="text-text-danger">*</span>
              </label>
              <textarea
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                placeholder="e.g. Employee already assigned to another branch, scheduling conflict, or store quota full..."
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
