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
  X,
  XCircle,
} from "lucide-react";
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

  // Priority color
  const priorityLower = (request.priority || "Normal").toLowerCase();
  const priorityBadgeClass =
    priorityLower === "urgent"
      ? "bg-red-50 text-red-700 border-red-200"
      : priorityLower === "high"
      ? "bg-amber-50 text-amber-700 border-amber-200"
      : "bg-slate-100 text-slate-700 border-slate-200";

  // Pool Type styling
  const poolType = request.poolType || "MOSES HQ Pool";
  const isCommando = poolType.toLowerCase().includes("commando");
  const poolBadgeClass = isCommando
    ? "bg-purple-50 text-purple-700 border-purple-200"
    : "bg-blue-50 text-blue-700 border-blue-200";

  // Escalation / SLA styling
  const escalation = request.escalationLevel || "Normal";
  const isEscalated = escalation !== "Normal";
  const escalationBadgeClass = isEscalated
    ? "bg-rose-50 text-rose-700 border-rose-200"
    : "bg-emerald-50 text-emerald-700 border-emerald-200";

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
      <div className="rounded-xl border border-border-default bg-white p-5 shadow-xs transition hover:border-slate-300">
        {/* Top Meta Bar */}
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle pb-3.5">
          <div className="flex flex-wrap items-center gap-2">
            <span
              className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold ${poolBadgeClass}`}
            >
              <Users className="h-3 w-3" />
              {poolType}
            </span>
            <span
              className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider ${priorityBadgeClass}`}
            >
              <AlertTriangle className="h-3 w-3" />
              {request.priority || "Normal"}
            </span>
            <span
              className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-2xs font-medium ${escalationBadgeClass}`}
            >
              <ShieldAlert className="h-3 w-3" />
              SLA: {escalation}
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

        {/* Reliever & Deployment Route Card */}
        <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
          {/* Employee Info */}
          <div className="rounded-lg border border-border-subtle bg-surface-subtle p-3.5">
            <div className="text-2xs font-semibold uppercase tracking-wider text-text-tertiary">
              Requested Reliever
            </div>
            <div className="mt-1 flex items-center gap-2">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-blue-100 text-blue-700 font-bold text-xs">
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
          <div className="rounded-lg border border-border-subtle bg-surface-subtle p-3.5">
            <div className="text-2xs font-semibold uppercase tracking-wider text-text-tertiary">
              Target Assignment Scope
            </div>
            <div className="mt-1 flex items-start gap-2">
              <MapPin className="h-4 w-4 text-emerald-600 mt-0.5 shrink-0" />
              <div className="min-w-0">
                <div className="text-sm font-semibold text-text-primary truncate">
                  {request.requestedStore || "Unassigned Store"}
                </div>
                <div className="flex flex-wrap items-center gap-1.5 text-2xs text-text-secondary">
                  <span>{request.requestedAccount || "Direct"}</span>
                  {request.requestedGroup && (
                    <>
                      <span>•</span>
                      <span className="rounded bg-slate-200/60 px-1 py-0.2 font-medium text-slate-700">
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
          <div className="flex items-center gap-2.5 rounded-lg border border-border-subtle px-3 py-2 bg-white">
            <Calendar className="h-4 w-4 text-brand-600 shrink-0" />
            <div className="min-w-0">
              <div className="text-2xs text-text-tertiary">Coverage Period</div>
              <div className="text-xs font-semibold text-text-primary">
                {formatDate(request.startDate)} – {formatDate(request.endDate)}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2.5 rounded-lg border border-border-subtle px-3 py-2 bg-white">
            <Clock className="h-4 w-4 text-amber-600 shrink-0" />
            <div className="min-w-0">
              <div className="text-2xs text-text-tertiary">Total Duration</div>
              <div className="text-xs font-semibold text-text-primary">
                {durationDays !== null ? (
                  <span>
                    <strong className="font-mono text-amber-700">{durationDays}</strong> day
                    {durationDays !== 1 ? "s" : ""} deployment
                  </span>
                ) : (
                  "Open-ended"
                )}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2.5 rounded-lg border border-border-subtle px-3 py-2 bg-white sm:col-span-2 lg:col-span-1">
            <User className="h-4 w-4 text-slate-500 shrink-0" />
            <div className="min-w-0">
              <div className="text-2xs text-text-tertiary">Endorsed By</div>
              <div className="text-xs font-semibold text-text-primary truncate">
                {request.requestedBy || "Operations Requester"}
              </div>
            </div>
          </div>
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
            Request ID: <span className="font-mono">{request.requestId.slice(0, 8)}</span>
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
              <span>Approve Deployment</span>
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
                    Approve Reliever Endorsement
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Create active workforce assignment record
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
                You are approving the temporary deployment of{" "}
                <strong className="text-text-primary">{request.employeeName}</strong> to{" "}
                <strong className="text-text-primary">{request.requestedStore}</strong>.
              </p>
              <div className="rounded-lg border border-border-subtle bg-surface-subtle p-3 space-y-1 text-2xs">
                <div>
                  <span className="font-semibold text-text-tertiary">Period: </span>
                  <span className="font-medium text-text-primary">
                    {formatDate(request.startDate)} – {formatDate(request.endDate)}
                    {durationDays !== null ? ` (${durationDays} days)` : ""}
                  </span>
                </div>
                <div>
                  <span className="font-semibold text-text-tertiary">Store & Account: </span>
                  <span className="font-medium text-text-primary">
                    {request.requestedAccount} / {request.requestedStore}
                  </span>
                </div>
              </div>

              <div>
                <label className="block text-2xs font-semibold uppercase tracking-wider text-text-tertiary mb-1">
                  Reviewer Notes (Optional)
                </label>
                <textarea
                  value={approveNotes}
                  onChange={(e) => setApproveNotes(e.target.value)}
                  placeholder="Add deployment remarks or special instructions..."
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
                    Reject Reliever Endorsement
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Decline this workforce deployment request
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
                Please provide an explanatory reason for declining the deployment request for{" "}
                <strong className="text-text-primary">{request.employeeName}</strong>. The requester will be notified.
              </p>

              <div>
                <label className="block text-2xs font-semibold uppercase tracking-wider text-text-tertiary mb-1">
                  Rejection Reason <span className="text-rose-600">*</span>
                </label>
                <textarea
                  value={rejectionReason}
                  onChange={(e) => setRejectionReason(e.target.value)}
                  placeholder="e.g. Employee already assigned to another branch, scheduling conflict, or store quota full..."
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
