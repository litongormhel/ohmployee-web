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
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
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
  const isSuperAdmin =
    currentUser?.roleKey?.toLowerCase() === "super_admin" ||
    currentUser?.roleName?.toLowerCase().includes("super admin");

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
    <article className="rounded-xl border border-border-default bg-surface p-5 shadow-xs transition hover:border-border-brand/40">
      {/* ── Top Row: Request Badge, Timestamps, and Action Controls ── */}
      <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border-default pb-4">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-mono text-xs font-bold text-text-brand-bold bg-surface-subtle border border-border-default px-2.5 py-0.5 rounded-md">
              {request.requestNumber}
            </span>

            <span className="inline-flex items-center gap-1 text-xs text-text-muted">
              <Clock className="h-3.5 w-3.5" aria-hidden="true" />
              <span>{formatRelativeAge(request.requestedAt)}</span>
              <span className="text-text-muted">({formatDate(request.requestedAt)})</span>
            </span>

            <span className="inline-flex items-center rounded-md bg-surface-subtle border border-border-default px-2 py-0.5 text-xs font-medium text-text-secondary">
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
                <span>Approve & Execute</span>
              </button>
            </>
          ) : isOwnRequest ? (
            <span className="inline-flex items-center gap-1 rounded-md bg-surface-subtle border border-border-default px-2.5 py-1 text-xs text-text-secondary">
              <AlertTriangle className="h-3.5 w-3.5" aria-hidden="true" />
              Self-approval blocked
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 rounded-md bg-surface-subtle border border-border-default px-2.5 py-1 text-xs text-text-secondary">
              Super Admin approval required
            </span>
          )}
        </div>
      </div>

      {/* ── Route Banner: Origin Group -> Destination Group ── */}
      <div className="mt-4 rounded-lg border border-border-default bg-surface-subtle p-3.5">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            {/* From Group */}
            <div className="flex flex-col">
              <span className="text-2xs font-semibold uppercase tracking-wider text-text-muted">
                From Group
              </span>
              <div className="flex items-center gap-1.5">
                <span className="text-xs font-semibold text-text-primary">
                  {request.fromGroupName}
                </span>
                <span className="rounded-md border border-border-default bg-surface px-1.5 py-0.2 text-2xs font-mono font-medium text-text-secondary">
                  {request.fromGroupCode}
                </span>
              </div>
            </div>

            <ArrowRight className="h-4 w-4 shrink-0 text-text-muted" aria-hidden="true" />

            {/* To Group */}
            <div className="flex flex-col">
              <span className="text-2xs font-semibold uppercase tracking-wider text-text-muted">
                To Group
              </span>
              <div className="flex items-center gap-1.5">
                <span className="text-xs font-bold text-text-brand-bold">
                  {request.toGroupName}
                </span>
                <span className="rounded-md border border-border-default bg-surface px-1.5 py-0.2 text-2xs font-mono font-bold text-text-brand-bold">
                  {request.toGroupCode}
                </span>
              </div>
            </div>
          </div>

          {/* Requester & Reason */}
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-text-secondary border-t md:border-t-0 md:border-l border-border-default pt-2 md:pt-0 md:pl-4">
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
      <div className="mt-4 rounded-lg border border-border-default bg-surface p-3.5">
        <div className="flex items-center justify-between pb-2 border-b border-border-default">
          <span className="text-xs font-bold uppercase tracking-wider text-text-primary flex items-center gap-1.5">
            <Layers className="h-3.5 w-3.5 text-text-brand-bold" aria-hidden="true" />
            Impact Simulation (Live Snapshot)
          </span>
          <span className="text-2xs text-text-muted">
            Computed at submission
          </span>
        </div>

        {/* Metric Grid */}
        <div className="mt-3 grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-2">
          <div className="rounded-md border border-border-default bg-surface-subtle p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-2xs text-text-muted">
              <Store className="h-3 w-3" />
              <span>Stores</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              {affectedStores}
            </div>
          </div>

          <div className="rounded-md border border-border-default bg-surface-subtle p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-2xs text-text-muted">
              <Users className="h-3 w-3" />
              <span>Plantilla</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              {affectedPlantilla}
            </div>
          </div>

          <div className="rounded-md border border-border-default bg-surface-subtle p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-2xs text-text-muted">
              <Building2 className="h-3 w-3" />
              <span>Vacancies</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              {affectedVacancies}
            </div>
          </div>

          <div className="rounded-md border border-border-default bg-surface-subtle p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-2xs text-text-muted">
              <MapPin className="h-3 w-3" />
              <span>HR Emploc</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              {affectedHrEmploc}
            </div>
          </div>

          <div className="rounded-md border border-border-default bg-surface-subtle p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-2xs text-text-brand-bold">
              <Eye className="h-3 w-3" />
              <span>Visibility +</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-brand-bold">
              +{usersGaining}
            </div>
          </div>

          <div className="rounded-md border border-border-default bg-surface-subtle p-2 text-center">
            <div className="flex items-center justify-center gap-1 text-2xs text-text-secondary">
              <Eye className="h-3 w-3" />
              <span>Visibility −</span>
            </div>
            <div className="mt-1 text-base font-bold font-mono text-text-primary">
              −{usersLosing}
            </div>
          </div>
        </div>

        {/* Warnings or Clean State */}
        <div className="mt-3">
          {warningsList.length > 0 ? (
            <div className="rounded-md border border-border-danger bg-danger-subtle p-3 text-xs text-text-danger">
              <div className="flex items-center gap-1.5 font-bold text-text-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                <span>Simulation Warnings ({warningsList.length}) — Informational:</span>
              </div>
              <ul className="mt-1.5 space-y-1 pl-5 list-disc text-text-danger">
                {warningsList.map((w, idx) => (
                  <li key={idx} className="leading-relaxed">
                    {w}
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <div className="flex items-center gap-1.5 rounded-md border border-border-default bg-surface-subtle p-2 text-xs text-text-secondary">
              <CheckCircle2 className="h-4 w-4 shrink-0 text-text-brand-bold" aria-hidden="true" />
              <span>No simulation conflicts or cross-group warnings detected. Ready for transfer.</span>
            </div>
          )}
        </div>
      </div>

      {/* ── Approve Modal ── */}
      {isApproveOpen && (
        <Modal
          isOpen={isApproveOpen}
          onClose={() => setIsApproveOpen(false)}
          title="Approve Account Transfer"
          subtitle={request.requestNumber}
          icon={CheckCircle2}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4 text-xs">
            <p className="text-text-secondary leading-relaxed">
              Are you sure you want to approve the organizational ownership transfer for account{" "}
              <strong className="text-text-primary">{request.accountName}</strong> from{" "}
              <strong className="text-text-primary">{request.fromGroupName} ({request.fromGroupCode})</strong> to{" "}
              <strong className="text-text-primary">{request.toGroupName} ({request.toGroupCode})</strong>?
            </p>

            <div className="rounded-md border border-border-default bg-surface-subtle p-3 space-y-1.5 text-text-secondary">
              <div className="font-semibold text-text-primary">Execution Impact Summary:</div>
              <div className="grid grid-cols-2 gap-1 text-2xs">
                <div>• Affected Stores: <strong>{affectedStores}</strong></div>
                <div>• Active Headcount: <strong>{affectedPlantilla}</strong></div>
                <div>• Open Vacancies: <strong>{affectedVacancies}</strong></div>
                <div>• HR Emploc Links: <strong>{affectedHrEmploc}</strong></div>
              </div>
              <p className="text-2xs text-text-muted pt-1">
                All active stores linked to this account will immediately change group ownership to {request.toGroupName}.
              </p>
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
                <span>Confirm & Execute Transfer</span>
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
          title="Reject Account Transfer"
          subtitle={request.requestNumber}
          icon={XCircle}
          isSubmitting={isBusy}
          disableBackdropClick={isBusy}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4 text-xs">
            <p className="text-text-secondary leading-relaxed">
              Reject transfer of <strong className="text-text-primary">{request.accountName}</strong> to{" "}
              <strong className="text-text-primary">{request.toGroupName}</strong>. Please provide a clear operational reason for the requester.
            </p>

            <div>
              <label
                htmlFor="agt-rejection-reason"
                className="block font-medium text-text-primary mb-1"
              >
                Rejection Reason <span className="text-text-danger">*</span>{" "}
                <span className="font-normal text-text-muted">(Minimum 10 characters)</span>
              </label>
              <textarea
                id="agt-rejection-reason"
                rows={3}
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                placeholder="Explain why this account group transfer cannot be approved..."
                className="w-full rounded-md border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-border-brand focus:outline-hidden"
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
                disabled={isBusy || rejectionReason.trim().length < 10}
                className="inline-flex items-center gap-1.5 rounded-md bg-danger-button hover:bg-danger-button-hover px-4 py-1.5 text-xs font-medium text-danger-button-text shadow-2xs disabled:opacity-50 transition cursor-pointer"
              >
                {isBusy && <RefreshCw className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />}
                <span>Reject Transfer</span>
              </button>
            </div>
          </div>
        </Modal>
      )}
    </article>
  );
}
