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
  X,
  XCircle,
} from "lucide-react";
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
    <div className="rounded-lg border border-border-default bg-surface-base p-5 shadow-xs transition hover:border-slate-300">
      {/* Top Header: VCode, Store Name & Type */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded border border-blue-200 bg-blue-50 px-2 py-0.5 font-mono text-xs font-semibold text-blue-700">
              {request.targetVcode ?? "NO-VCODE"}
            </span>
            <span className="inline-flex items-center gap-1 rounded border border-purple-200 bg-purple-50 px-2 py-0.5 text-xs font-medium text-purple-700">
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
            <div className="inline-flex items-center gap-2 rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1 font-mono text-xs font-semibold text-emerald-800 shadow-2xs">
              <TrendingUp className="h-3.5 w-3.5 text-emerald-600" />
              <span>
                {previousTarget} → {proposedTarget}
              </span>
              <span className="rounded-full bg-emerald-200/60 px-1.5 py-0.2 text-[11px] text-emerald-900">
                +{delta} Expansion
              </span>
            </div>
          )}

          {isReduction && (
            <div className="inline-flex items-center gap-2 rounded-full border border-amber-200 bg-amber-50 px-3 py-1 font-mono text-xs font-semibold text-amber-800 shadow-2xs">
              <TrendingDown className="h-3.5 w-3.5 text-amber-600" />
              <span>
                {previousTarget} → {proposedTarget}
              </span>
              <span className="rounded-full bg-amber-200/60 px-1.5 py-0.2 text-[11px] text-amber-900">
                {delta} Reduction
              </span>
            </div>
          )}

          {!isExpansion && !isReduction && (
            <div className="inline-flex items-center gap-2 rounded-full border border-slate-200 bg-slate-100 px-3 py-1 font-mono text-xs font-medium text-slate-700 shadow-2xs">
              <span>
                {previousTarget} → {proposedTarget}
              </span>
              <span className="text-[11px] text-slate-500">(No Change)</span>
            </div>
          )}
        </div>
      </div>

      {/* Safety Floor Validation Indicator */}
      <div className="mt-4 rounded-md border border-slate-200 bg-slate-50/70 p-3 text-xs">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            {isLoadingDetails ? (
              <span className="text-text-muted">Loading live commitments...</span>
            ) : isSafetyFloorMet ? (
              <div className="flex items-center gap-1.5 font-medium text-emerald-700">
                <ShieldCheck className="h-4 w-4 shrink-0 text-emerald-600" />
                <span>Safety Floor Validated: {safetyFloor} slot{safetyFloor !== 1 ? "s" : ""} min</span>
              </div>
            ) : (
              <div className="flex items-center gap-1.5 font-semibold text-amber-700">
                <AlertTriangle className="h-4 w-4 shrink-0 text-amber-600" />
                <span>Safety Floor Warning: Proposed ({proposedTarget}) is below minimum ({safetyFloor})</span>
              </div>
            )}
          </div>

          {vcodeDetails && (
            <div className="flex items-center gap-3 font-mono text-[11px] text-text-muted">
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
                <span>Confirm Quota Amendment Approval</span>
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
                Approving this request will immediately execute the authoritative quota revision RPC on{" "}
                <span className="font-mono font-semibold text-text-primary">
                  {request.targetVcode}
                </span>{" "}
                at <span className="font-medium text-text-primary">{request.storeName}</span>.
              </p>

              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
                <div className="flex items-center justify-between">
                  <span className="text-text-muted">Quota Transition:</span>
                  <div className="flex items-center gap-2 font-mono font-semibold">
                    <span>{previousTarget}</span>
                    <ArrowRight className="h-3.5 w-3.5 text-text-muted" />
                    <span className="text-emerald-700">{proposedTarget} slots</span>
                    <span className="rounded bg-emerald-100 px-1 text-[11px] text-emerald-800">
                      {isExpansion ? `+${delta}` : delta}
                    </span>
                  </div>
                </div>

                <div className="mt-2 flex items-center justify-between border-t border-slate-200/80 pt-2 text-[11px]">
                  <span className="text-text-muted">Safety Floor Status:</span>
                  <span className={isSafetyFloorMet ? "font-medium text-emerald-700" : "font-semibold text-amber-700"}>
                    {isSafetyFloorMet ? `Validated (Min: ${safetyFloor})` : `Below Floor (Min: ${safetyFloor})`}
                  </span>
                </div>
              </div>

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
                <span>Reject Quota Amendment</span>
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
                <div className="rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
                  <div className="flex items-start gap-2">
                    <AlertTriangle className="h-4 w-4 shrink-0 text-red-500" />
                    <span>{actionError}</span>
                  </div>
                </div>
              )}

              <div>
                <label
                  htmlFor={`reject-remarks-${request.id}`}
                  className="block text-xs font-medium text-text-primary mb-1"
                >
                  Rejection Reason / Remarks <span className="text-red-500">*</span>
                </label>
                <textarea
                  id={`reject-remarks-${request.id}`}
                  rows={2}
                  value={remarks}
                  onChange={(e) => setRemarks(e.target.value)}
                  placeholder="State operational reason for rejecting this amendment..."
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
