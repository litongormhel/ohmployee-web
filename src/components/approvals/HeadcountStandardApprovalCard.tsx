"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Building2,
  CheckCircle2,
  Clock,
  Sparkles,
  User,
  Users,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  useApproveHeadcountRequest,
  useRejectHeadcountRequest,
  useHcRequestStores,
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

  const isRoving = request.workforceType?.toLowerCase() === "roving";
  const { data: rovingStores = [] } = useHcRequestStores(request.id, {
    enabled: isRoving,
  });

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
    <div className="rounded-lg border border-border-default bg-surface p-5 shadow-xs transition hover:border-border-brand/40">
      {/* Top Header */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-semibold text-text-primary">
              {request.requestType}
            </span>
            {request.urgency && (
              <span className="inline-flex items-center rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-secondary">
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
        <div className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-subtle px-3 py-1 font-mono text-xs font-semibold text-text-primary shadow-2xs">
          <Users className="h-3.5 w-3.5 text-text-primary" />
          <span>+{request.headcountNeeded} requested</span>
        </div>
      </div>

      {/* Operational Justification */}
      <div className="mt-3.5 space-y-1">
        <p className="text-xs font-medium text-text-muted">
          Operational Justification
        </p>
        <p className="rounded-md border border-border-default bg-surface px-3 py-2 text-xs leading-relaxed text-text-secondary">
          {request.reason?.trim() ? (
            request.reason
          ) : (
            <span className="italic text-text-muted">No operational justification provided.</span>
          )}
        </p>
      </div>

      {/* Roving Stores Breakdown */}
      {isRoving && rovingStores.length > 0 && (
        <div className="mt-3.5 space-y-1.5">
          <div className="flex items-center justify-between text-xs font-medium text-text-muted">
            <span>Roving Cluster Breakdown ({rovingStores.length} stores)</span>
            {rovingStores.some((s) => s.is_new_store) && (
              <span className="text-[11px] text-amber-600 dark:text-amber-400 font-semibold">
                ✨ {rovingStores.filter((s) => s.is_new_store).length} new store(s) pending creation
              </span>
            )}
          </div>
          <div className="flex flex-wrap gap-1.5 rounded-md border border-border-default bg-surface-subtle p-2.5">
            {rovingStores.map((s) => (
              <span
                key={s.id}
                className={`inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium border ${
                  s.is_new_store
                    ? "bg-amber-500/10 border-amber-500/30 text-amber-700 dark:text-amber-300"
                    : "bg-surface border-border-default text-text-primary"
                }`}
              >
                {s.is_new_store ? (
                  <Sparkles className="h-3 w-3 text-amber-500 shrink-0" />
                ) : (
                  <Building2 className="h-3 w-3 text-text-muted shrink-0" />
                )}
                <span className="font-semibold">{s.store_name}</span>
                <span className="text-[10px] text-text-muted">
                  • {[s.city, s.province].filter(Boolean).join(", ")}
                </span>
                {s.is_new_store && (
                  <span className="rounded bg-amber-500/20 px-1 text-[9px] font-semibold text-amber-600 dark:text-amber-400">
                    New Store — Will be created on approval
                  </span>
                )}
              </span>
            ))}
          </div>
        </div>
      )}

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
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-danger/40 bg-surface-subtle px-3 text-xs font-semibold text-text-danger shadow-2xs transition hover:bg-danger-subtle disabled:cursor-not-allowed disabled:opacity-50 cursor-pointer"
          >
            <XCircle className="h-3.5 w-3.5" />
            Reject
          </button>
          <button
            type="button"
            onClick={handleOpenApprove}
            disabled={rejectMutation.isPending || approveMutation.isPending}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-brand-500 bg-brand-500 hover:bg-brand-600 px-3.5 text-xs font-semibold text-white shadow-2xs transition disabled:cursor-not-allowed disabled:opacity-50 cursor-pointer"
          >
            <CheckCircle2 className="h-3.5 w-3.5" />
            Approve
          </button>
        </div>
      </div>

      {/* Confirmation Dialog: APPROVE */}
      {isApproveOpen && (
        <Modal
          isOpen={isApproveOpen}
          onClose={() => setIsApproveOpen(false)}
          title="Confirm Headcount Approval"
          subtitle={request.storeName ?? "Headcount Request"}
          icon={CheckCircle2}
          isSubmitting={approveMutation.isPending}
          disableBackdropClick={approveMutation.isPending}
          maxWidthClass="max-w-lg"
        >
          <div className="space-y-3 text-xs text-text-secondary">
            <p>
              Approving this request will advance the requisition for{" "}
              <span className="font-semibold text-text-primary">
                {request.storeName || (isRoving ? "Roving Cluster" : "Headcount Requisition")}
              </span>{" "}
              ({request.positionName}) requesting{" "}
              <span className="font-semibold text-text-primary">
                +{request.headcountNeeded} headcount
              </span>.
            </p>

            {isRoving && rovingStores.some((s) => s.is_new_store) && (
              <div className="rounded-md border border-amber-500/30 bg-amber-500/10 p-2.5 text-xs text-amber-700 dark:text-amber-300">
                <div className="flex items-start gap-1.5">
                  <Sparkles className="h-4 w-4 shrink-0 text-amber-500 mt-0.5" />
                  <div>
                    <span className="font-semibold">Atomic Store Provisioning: </span>
                    Approving will automatically register{" "}
                    <span className="font-semibold">
                      {rovingStores.filter((s) => s.is_new_store).length} new store(s)
                    </span>{" "}
                    ({rovingStores.filter((s) => s.is_new_store).map((s) => s.store_name).join(", ")}) into the store registry and bind them to the new Coverage Group.
                  </div>
                </div>
              </div>
            )}

            {actionError && (
              <div className="rounded-md border border-border-danger bg-danger-subtle p-3 text-xs text-text-danger">
                <div className="flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 shrink-0 text-text-danger" />
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
                className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary shadow-2xs focus:border-border-brand focus:outline-hidden"
              />
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={approveMutation.isPending}
                className="h-8 rounded-md border border-border-default bg-surface px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={approveMutation.isPending}
                className="inline-flex h-8 items-center gap-1.5 rounded-md bg-brand-500 hover:bg-brand-600 px-4 text-xs font-semibold text-white shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {approveMutation.isPending ? "Approving..." : "Confirm Approval"}
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* Confirmation Dialog: REJECT */}
      {isRejectOpen && (
        <Modal
          isOpen={isRejectOpen}
          onClose={() => setIsRejectOpen(false)}
          title="Reject Headcount Request"
          subtitle={request.storeName ?? "Headcount Request"}
          icon={XCircle}
          isSubmitting={rejectMutation.isPending}
          disableBackdropClick={rejectMutation.isPending}
          isDirty={Boolean(remarks.trim())}
          maxWidthClass="max-w-lg"
        >
          <div className="space-y-3 text-xs text-text-secondary">
            <p>
              Are you sure you want to reject the headcount request for{" "}
              <span className="font-semibold text-text-primary">{request.storeName}</span>{" "}
              ({request.positionName})?
            </p>

            {actionError && (
              <div className="rounded-md border border-border-danger bg-danger-subtle p-3 text-xs text-text-danger">
                <div className="flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 shrink-0 text-text-danger" />
                  <span>{actionError}</span>
                </div>
              </div>
            )}

            <div>
              <label
                htmlFor={`reject-std-remarks-${request.id}`}
                className="block text-xs font-medium text-text-primary mb-1"
              >
                Rejection Reason / Remarks <span className="text-text-danger">*</span>
              </label>
              <textarea
                id={`reject-std-remarks-${request.id}`}
                rows={2}
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                placeholder="State operational reason for rejecting this request..."
                className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary shadow-2xs focus:border-border-brand focus:outline-hidden"
              />
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={rejectMutation.isPending}
                className="h-8 rounded-md border border-border-default bg-surface px-3 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={rejectMutation.isPending}
                className="inline-flex h-8 items-center gap-1.5 rounded-md bg-danger-button hover:bg-danger-button-hover px-4 text-xs font-semibold text-danger-button-text shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {rejectMutation.isPending ? "Rejecting..." : "Confirm Rejection"}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
