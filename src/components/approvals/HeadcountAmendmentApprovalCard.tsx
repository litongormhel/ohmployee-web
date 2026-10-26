"use client";

import { useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  Building2,
  CheckCircle2,
  Clock,
  ShieldCheck,
  TrendingDown,
  TrendingUp,
  User,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useVcodeQuotaDetails } from "@/lib/queries/quota";
import {
  useApproveHeadcountRequest,
  useRejectHeadcountRequest,
  type HeadcountRequestItem,
} from "@/lib/queries/requests";

interface HeadcountAmendmentApprovalCardProps {
  request: HeadcountRequestItem;
}

export function HeadcountAmendmentApprovalCard({
  request,
}: HeadcountAmendmentApprovalCardProps) {
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [remarks, setRemarks] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const approveMutation = useApproveHeadcountRequest();
  const rejectMutation = useRejectHeadcountRequest();

  // Fetch live commitments and safety floor calculation
  const { data: vcodeDetails, isLoading: isLoadingDetails } =
    useVcodeQuotaDetails(request.targetVcode);

  const previousTarget =
    request.previousTarget ?? vcodeDetails?.currentQuota ?? 1;
  const proposedTarget = request.proposedTarget ?? previousTarget;
  const delta = proposedTarget - previousTarget;
  const isExpansion = delta > 0;
  const isReduction = delta < 0;

  // Safety floor validation
  const safetyFloor = vcodeDetails?.safetyFloor ?? 1;
  const commitments = vcodeDetails?.commitments ?? 0;
  const isSafetyFloorMet = proposedTarget >= safetyFloor;

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
        isQuotaAmendment: true,
      });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      const errorMsg =
        err instanceof Error ? err.message : "Failed to approve quota amendment.";
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
        err instanceof Error ? err.message : "Failed to reject quota amendment.";
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
      {/* Top Header: VCode, Store Name & Type */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 font-mono text-xs font-semibold text-text-primary">
              {request.targetVcode ?? "NO-VCODE"}
            </span>
            <span className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-secondary">
              Quota Amendment
            </span>
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

        {/* Quota Change Pill */}
        <div className="flex items-center">
          {isExpansion && (
            <div className="inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-subtle px-3 py-1 font-mono text-xs font-semibold text-text-primary shadow-2xs">
              <TrendingUp className="h-3.5 w-3.5 text-text-primary" />
              <span>
                {previousTarget} → {proposedTarget}
              </span>
              <span className="rounded-md bg-surface border border-border-default px-1.5 py-0.2 text-2xs text-text-primary">
                +{delta} Expansion
              </span>
            </div>
          )}

          {isReduction && (
            <div className="inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-subtle px-3 py-1 font-mono text-xs font-semibold text-text-primary shadow-2xs">
              <TrendingDown className="h-3.5 w-3.5 text-text-primary" />
              <span>
                {previousTarget} → {proposedTarget}
              </span>
              <span className="rounded-md bg-surface border border-border-default px-1.5 py-0.2 text-2xs text-text-secondary">
                {delta} Reduction
              </span>
            </div>
          )}

          {!isExpansion && !isReduction && (
            <div className="inline-flex items-center gap-2 rounded-md border border-border-default bg-surface-subtle px-3 py-1 font-mono text-xs font-medium text-text-secondary shadow-2xs">
              <span>
                {previousTarget} → {proposedTarget}
              </span>
              <span className="text-2xs text-text-muted">(No Change)</span>
            </div>
          )}
        </div>
      </div>

      {/* Safety Floor Validation Indicator */}
      <div className="mt-4 rounded-md border border-border-default bg-surface-subtle p-3 text-xs">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            {isLoadingDetails ? (
              <span className="text-text-muted">Loading live commitments...</span>
            ) : isSafetyFloorMet ? (
              <div className="flex items-center gap-1.5 font-medium text-text-brand-bold">
                <ShieldCheck className="h-4 w-4 shrink-0 text-text-brand-bold" />
                <span>Safety Floor Validated: {safetyFloor} slot{safetyFloor !== 1 ? "s" : ""} min</span>
              </div>
            ) : (
              <div className="flex items-center gap-1.5 font-semibold text-text-danger">
                <AlertTriangle className="h-4 w-4 shrink-0 text-text-danger" />
                <span>Safety Floor Warning: Proposed ({proposedTarget}) is below minimum ({safetyFloor})</span>
              </div>
            )}
          </div>

          {vcodeDetails && (
            <div className="flex items-center gap-3 font-mono text-2xs text-text-muted">
              <span>Occupied: {vcodeDetails.occupied}</span>
              <span>HR: {vcodeDetails.hrProcessing}</span>
              <span>Pipeline: {vcodeDetails.pipeline}</span>
              <span className="font-semibold text-text-secondary">
                Total: {commitments}
              </span>
            </div>
          )}
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
          title="Confirm Quota Amendment Approval"
          subtitle={request.targetVcode ?? "Quota Amendment"}
          icon={CheckCircle2}
          isSubmitting={approveMutation.isPending}
          disableBackdropClick={approveMutation.isPending}
          maxWidthClass="max-w-lg"
        >
          <div className="space-y-3 text-xs text-text-secondary">
            <p>
              Approving this request will immediately execute the authoritative quota revision RPC on{" "}
              <span className="font-mono font-semibold text-text-primary">
                {request.targetVcode}
              </span>{" "}
              at <span className="font-medium text-text-primary">{request.storeName}</span>.
            </p>

            <div className="rounded-lg border border-border-default bg-surface-subtle p-3">
              <div className="flex items-center justify-between">
                <span className="text-text-muted">Quota Transition:</span>
                <div className="flex items-center gap-2 font-mono font-semibold">
                  <span>{previousTarget}</span>
                  <ArrowRight className="h-3.5 w-3.5 text-text-muted" />
                  <span className="text-text-brand-bold">{proposedTarget} slots</span>
                  <span className="rounded-md border border-border-default bg-surface px-1 text-2xs text-text-primary">
                    {isExpansion ? `+${delta}` : delta}
                  </span>
                </div>
              </div>

              <div className="mt-2 flex items-center justify-between border-t border-border-default pt-2 text-2xs">
                <span className="text-text-muted">Safety Floor Status:</span>
                <span className={isSafetyFloorMet ? "font-medium text-text-brand-bold" : "font-semibold text-text-danger"}>
                  {isSafetyFloorMet ? `Validated (Min: ${safetyFloor})` : `Below Floor (Min: ${safetyFloor})`}
                </span>
              </div>
            </div>

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
                htmlFor={`approve-remarks-${request.id}`}
                className="block text-xs font-medium text-text-primary mb-1"
              >
                Approver Remarks (Optional)
              </label>
              <textarea
                id={`approve-remarks-${request.id}`}
                rows={2}
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                placeholder="Operational approval notes or justification verification..."
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
          title="Reject Quota Amendment"
          subtitle={request.targetVcode ?? "Quota Amendment"}
          icon={XCircle}
          isSubmitting={rejectMutation.isPending}
          disableBackdropClick={rejectMutation.isPending}
          isDirty={Boolean(remarks.trim())}
          maxWidthClass="max-w-lg"
        >
          <div className="space-y-3 text-xs text-text-secondary">
            <p>
              Are you sure you want to reject the quota amendment request for{" "}
              <span className="font-mono font-semibold text-text-primary">
                {request.targetVcode}
              </span>{" "}
              ({request.storeName})? The target quota will remain unchanged at{" "}
              <span className="font-mono font-semibold text-text-primary">
                {previousTarget}
              </span>{" "}
              slots.
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
                htmlFor={`reject-remarks-${request.id}`}
                className="block text-xs font-medium text-text-primary mb-1"
              >
                Rejection Reason / Remarks <span className="text-text-danger">*</span>
              </label>
              <textarea
                id={`reject-remarks-${request.id}`}
                rows={2}
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                placeholder="State operational reason for rejecting this amendment..."
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
