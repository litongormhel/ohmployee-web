"use client";

import { useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  Building2,
  CheckCircle2,
  Clock,
  Eye,
  FileText,
  Layers,
  MapPin,
  RefreshCw,
  Store,
  User,
  Users,
  X,
  XCircle,
} from "lucide-react";
import {
  useApproveAccountGroupTransfer,
  useRejectAccountGroupTransfer,
  type AccountGroupTransferItem,
} from "@/lib/queries/requests";
import { useCurrentUser } from "@/lib/auth";

interface StoreTransferApprovalCardProps {
  request: AccountGroupTransferItem;
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

export function StoreTransferApprovalCard({
  request,
}: StoreTransferApprovalCardProps) {
  const currentUser = useCurrentUser();
  const approveMutation = useApproveAccountGroupTransfer();
  const rejectMutation = useRejectAccountGroupTransfer();

  // Role permissions:
  // Super Admin check: roleKey === 'super_admin' or roleName matches Super Admin
  const isSuperAdmin =
    currentUser?.roleKey?.toLowerCase() === "super_admin" ||
    currentUser?.roleName?.toLowerCase().includes("super admin");

  // Prevent self-approval if requester is caller (unless caller is Super Admin who can override)
  const isOwnRequest =
    !!currentUser?.profileId &&
    currentUser.profileId === request.requestedBy &&
    !isSuperAdmin;

  const canReview = isSuperAdmin && !isOwnRequest;

  // Dialog states
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [rejectionReason, setRejectionReason] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const isBusy = approveMutation.isPending || rejectMutation.isPending;

  const snapshot = request.simulationSnapshot || {};
  const affectedStores = Number(snapshot.affected_stores ?? 0);
  const affectedPlantilla = Number(snapshot.affected_plantilla_count ?? 0);
  const affectedVacancies = Number(snapshot.affected_vacancies_count ?? 0);
  const affectedHrEmploc = Number(snapshot.affected_hr_emploc_count ?? 0);
  const usersGaining = Number(snapshot.users_gaining_visibility ?? 0);
  const usersLosing = Number(snapshot.users_losing_visibility ?? 0);

  // Warnings normalization
  const warningsList: string[] = [];
  if (Array.isArray(snapshot.warnings) && snapshot.warnings.length > 0) {
    warningsList.push(...(snapshot.warnings as string[]));
  } else if (
    Array.isArray(snapshot.coverage_group_conflicts) &&
    snapshot.coverage_group_conflicts.length > 0
  ) {
    for (const conf of snapshot.coverage_group_conflicts) {
      warningsList.push(
        `Active reliever/commando deployment: ${conf.employee_name} deployed at ${conf.store_name} (Home Group: ${conf.home_group_name}).`
      );
    }
  }

  const handleOpenApprove = () => {
    setActionError(null);
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
      await approveMutation.mutateAsync(request.id);
      setIsApproveOpen(false);
    } catch (err) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve account group transfer."
      );
    }
  };

  const handleConfirmReject = async () => {
    const trimmed = rejectionReason.trim();
    if (!trimmed || trimmed.length < 10) {
      setActionError(
        "Please provide a substantive rejection reason (at least 10 characters)."
      );
      return;
    }

    setActionError(null);
    try {
      await rejectMutation.mutateAsync({
        requestId: request.id,
        reason: trimmed,
      });
      setIsRejectOpen(false);
    } catch (err) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject account group transfer."
      );
    }
  };

  return (
    <article className="rounded-xl border border-border-default bg-surface-base p-5 shadow-xs transition hover:border-border-hover">
      {/* ── Top Row: Request Badge, Timestamps, and Action Controls ── */}
      <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border-default pb-4">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-mono text-xs font-bold text-brand-700 bg-brand-50 border border-brand-200 px-2.5 py-0.5 rounded-md">
              {request.requestNumber}
            </span>

            <span className="inline-flex items-center gap-1 text-xs text-text-muted">
              <Clock className="h-3.5 w-3.5" aria-hidden="true" />
              <span>{formatRelativeAge(request.requestedAt)}</span>
              <span className="text-text-disabled">({formatDate(request.requestedAt)})</span>
            </span>

            <span className="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800">
              Pending Review
            </span>
          </div>

          <div className="mt-2 flex items-center gap-2">
            <span className="text-xs font-semibold text-text-muted uppercase tracking-wider">
              Account:
            </span>
            <h3 className="text-base font-bold text-text-primary">
              {request.accountName}
            </h3>
          </div>
        </div>

        {/* Action Controls */}
        <div className="flex items-center gap-2">
          {canReview ? (
            <>
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
                <span>Approve & Execute</span>
              </button>
            </>
          ) : isOwnRequest ? (
            <span className="inline-flex items-center gap-1 rounded-md bg-amber-50 border border-amber-200 px-2.5 py-1 text-xs text-amber-800">
              <AlertTriangle className="h-3.5 w-3.5" aria-hidden="true" />
              Self-approval blocked
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 rounded-md bg-slate-100 border border-slate-200 px-2.5 py-1 text-xs text-slate-600">
              Super Admin approval required
            </span>
          )}
        </div>
      </div>

      {/* ── Route Banner: Origin Group -> Destination Group ── */}
      <div className="mt-4 rounded-lg border border-border-default bg-slate-50/70 p-3.5">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            {/* From Group */}
            <div className="flex flex-col">
              <span className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
                From Group
              </span>
              <div className="flex items-center gap-1.5">
                <span className="text-xs font-semibold text-text-primary">
                  {request.fromGroupName}
                </span>
                <span className="rounded bg-slate-200 px-1.5 py-0.2 text-[10px] font-mono font-medium text-slate-700">
                  {request.fromGroupCode}
                </span>
              </div>
            </div>

            <ArrowRight className="h-4 w-4 shrink-0 text-slate-400" aria-hidden="true" />

            {/* To Group */}
            <div className="flex flex-col">
              <span className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
                To Group
              </span>
              <div className="flex items-center gap-1.5">
                <span className="text-xs font-bold text-brand-800">
                  {request.toGroupName}
                </span>
                <span className="rounded bg-brand-100 px-1.5 py-0.2 text-[10px] font-mono font-bold text-brand-700">
                  {request.toGroupCode}
                </span>
              </div>
            </div>
          </div>

          {/* Requester & Reason */}
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-text-secondary border-t md:border-t-0 md:border-l border-slate-200 pt-2 md:pt-0 md:pl-4">
            <div className="flex items-center gap-1.5">
              <User className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
              <span>Requested by:</span>
              <span className="font-semibold text-text-primary">
                {request.requestedByName}
              </span>
            </div>

            <div className="flex items-center gap-1.5">
              <FileText className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
              <span>Reason:</span>
              <span className="font-medium text-text-primary">
                &ldquo;{request.reason}&rdquo;
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* ── Impact Simulation Snapshot Panel ── */}
      <div className="mt-4 rounded-lg border border-border-default bg-white p-3.5">
        <div className="flex items-center justify-between pb-2 border-b border-border-subtle">
          <span className="text-[11px] font-bold uppercase tracking-wider text-slate-700 flex items-center gap-1.5">
            <Layers className="h-3.5 w-3.5 text-brand-600" aria-hidden="true" />
            Impact Simulation (Live Snapshot)
          </span>
          <span className="text-[11px] text-text-muted">
            Computed at submission
          </span>
        </div>

        {/* Metric Grid */}
        <div className="mt-3 grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-2">
          <div className="rounded-md border border-slate-200 bg-slate-50/50 p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-[11px] text-text-muted">
              <Store className="h-3 w-3" />
              <span>Stores</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              {affectedStores}
            </div>
          </div>

          <div className="rounded-md border border-slate-200 bg-slate-50/50 p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-[11px] text-text-muted">
              <Users className="h-3 w-3" />
              <span>Plantilla</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              {affectedPlantilla}
            </div>
          </div>

          <div className="rounded-md border border-slate-200 bg-slate-50/50 p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-[11px] text-text-muted">
              <Building2 className="h-3 w-3" />
              <span>Vacancies</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              {affectedVacancies}
            </div>
          </div>

          <div className="rounded-md border border-slate-200 bg-slate-50/50 p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-[11px] text-text-muted">
              <MapPin className="h-3 w-3" />
              <span>HR Emploc</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              {affectedHrEmploc}
            </div>
          </div>

          <div className="rounded-md border border-emerald-200 bg-emerald-50/50 p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-[11px] text-emerald-800">
              <Eye className="h-3 w-3" />
              <span>Visibility +</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-emerald-700">
              +{usersGaining}
            </div>
          </div>

          <div className="rounded-md border border-slate-200 bg-slate-50/50 p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-[11px] text-slate-600">
              <Eye className="h-3 w-3" />
              <span>Visibility −</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-slate-700">
              −{usersLosing}
            </div>
          </div>
        </div>

        {/* Warnings or Clean State */}
        <div className="mt-3">
          {warningsList.length > 0 ? (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
              <div className="flex items-center gap-1.5 font-bold text-amber-800">
                <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                <span>Simulation Warnings ({warningsList.length}) — Informational:</span>
              </div>
              <ul className="mt-1.5 space-y-1 pl-5 list-disc text-amber-800">
                {warningsList.map((w, idx) => (
                  <li key={idx} className="leading-relaxed">
                    {w}
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <div className="flex items-center gap-1.5 rounded-md border border-emerald-200 bg-emerald-50/60 p-2 text-xs text-emerald-800">
              <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-600" aria-hidden="true" />
              <span>No simulation conflicts or cross-group warnings detected. Ready for transfer.</span>
            </div>
          )}
        </div>
      </div>

      {/* ── Approve Modal ── */}
      {isApproveOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-xs"
          role="dialog"
          aria-modal="true"
          aria-labelledby="approve-transfer-title"
        >
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                  <CheckCircle2 className="h-5 w-5" aria-hidden="true" />
                </div>
                <div>
                  <h4 id="approve-transfer-title" className="text-base font-semibold text-text-primary">
                    Approve Account Transfer
                  </h4>
                  <p className="text-xs text-text-secondary font-mono">{request.requestNumber}</p>
                </div>
              </div>

              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={isBusy}
                className="rounded-md p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary"
              >
                <X className="h-4 w-4" aria-hidden="true" />
              </button>
            </div>

            <div className="mt-4 space-y-3 text-xs">
              <p className="text-text-secondary leading-relaxed">
                Are you sure you want to approve the organizational ownership transfer for account{" "}
                <strong className="text-text-primary">{request.accountName}</strong> from{" "}
                <strong className="text-text-primary">{request.fromGroupName} ({request.fromGroupCode})</strong> to{" "}
                <strong className="text-text-primary">{request.toGroupName} ({request.toGroupCode})</strong>?
              </p>

              <div className="rounded-md border border-border-default bg-slate-50 p-3 space-y-1.5 text-slate-700">
                <div className="font-semibold text-slate-900">Execution Impact Summary:</div>
                <div className="grid grid-cols-2 gap-1 text-[11px]">
                  <div>• Affected Stores: <strong>{affectedStores}</strong></div>
                  <div>• Active Headcount: <strong>{affectedPlantilla}</strong></div>
                  <div>• Open Vacancies: <strong>{affectedVacancies}</strong></div>
                  <div>• HR Emploc Links: <strong>{affectedHrEmploc}</strong></div>
                </div>
                <p className="text-[10px] text-slate-500 pt-1">
                  All active stores linked to this account will immediately change group ownership to {request.toGroupName}.
                </p>
              </div>

              {actionError && (
                <div className="flex items-center gap-2 rounded-md border border-rose-200 bg-rose-50 p-2.5 text-xs text-rose-700">
                  <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                  <span>{actionError}</span>
                </div>
              )}
            </div>

            <div className="mt-6 flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={isBusy}
                className="rounded-md border border-border-default bg-surface-base px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md border border-emerald-300 bg-emerald-600 px-4 py-1.5 text-xs font-medium text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50 transition"
              >
                {isBusy && <RefreshCw className="h-3 w-3 animate-spin" aria-hidden="true" />}
                <span>Confirm & Execute Transfer</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Reject Modal ── */}
      {isRejectOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-xs"
          role="dialog"
          aria-modal="true"
          aria-labelledby="reject-transfer-title"
        >
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-rose-100 text-rose-700">
                  <XCircle className="h-5 w-5" aria-hidden="true" />
                </div>
                <div>
                  <h4 id="reject-transfer-title" className="text-base font-semibold text-text-primary">
                    Reject Account Transfer
                  </h4>
                  <p className="text-xs text-text-secondary font-mono">{request.requestNumber}</p>
                </div>
              </div>

              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={isBusy}
                className="rounded-md p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary"
              >
                <X className="h-4 w-4" aria-hidden="true" />
              </button>
            </div>

            <div className="mt-4 space-y-3 text-xs">
              <p className="text-text-secondary leading-relaxed">
                Reject transfer of <strong className="text-text-primary">{request.accountName}</strong> to{" "}
                <strong className="text-text-primary">{request.toGroupName}</strong>. Please provide a clear operational reason for the requester.
              </p>

              <div>
                <label
                  htmlFor="agt-rejection-reason"
                  className="block font-medium text-text-primary mb-1"
                >
                  Rejection Reason <span className="text-rose-500">*</span>{" "}
                  <span className="font-normal text-text-muted">(Minimum 10 characters)</span>
                </label>
                <textarea
                  id="agt-rejection-reason"
                  rows={3}
                  value={rejectionReason}
                  onChange={(e) => setRejectionReason(e.target.value)}
                  placeholder="Explain why this account group transfer cannot be approved..."
                  className="w-full rounded-md border border-border-default bg-white p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {actionError && (
                <div className="flex items-center gap-2 rounded-md border border-rose-200 bg-rose-50 p-2.5 text-xs text-rose-700">
                  <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                  <span>{actionError}</span>
                </div>
              )}
            </div>

            <div className="mt-6 flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={isBusy}
                className="rounded-md border border-border-default bg-surface-base px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={isBusy || rejectionReason.trim().length < 10}
                className="inline-flex items-center gap-1.5 rounded-md border border-rose-300 bg-rose-600 px-4 py-1.5 text-xs font-medium text-white shadow-2xs hover:bg-rose-700 disabled:opacity-50 transition"
              >
                {isBusy && <RefreshCw className="h-3 w-3 animate-spin" aria-hidden="true" />}
                <span>Reject Transfer</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </article>
  );
}
