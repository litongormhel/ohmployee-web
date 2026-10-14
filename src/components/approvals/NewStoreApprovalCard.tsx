"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Building2,
  CheckCircle2,
  Clock,
  Layers,
  MapPin,
  MessageSquare,
  RefreshCw,
  Store,
  User,
  X,
  XCircle,
} from "lucide-react";
import {
  useApproveNewStoreRequest,
  useRejectNewStoreRequest,
  type NewStoreRequestItem,
} from "@/lib/queries/requests";

interface NewStoreApprovalCardProps {
  request: NewStoreRequestItem;
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

export function NewStoreApprovalCard({ request }: NewStoreApprovalCardProps) {
  const [isApproveOpen, setIsApproveOpen] = useState(false);
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [rejectionReason, setRejectionReason] = useState("");
  const [rejectReasonError, setRejectReasonError] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const approveMutation = useApproveNewStoreRequest();
  const rejectMutation = useRejectNewStoreRequest();

  const handleOpenApprove = () => {
    setActionError(null);
    setIsApproveOpen(true);
  };

  const handleOpenReject = () => {
    setActionError(null);
    setRejectionReason("");
    setRejectReasonError(false);
    setIsRejectOpen(true);
  };

  const handleConfirmApprove = async () => {
    setActionError(null);
    try {
      await approveMutation.mutateAsync({ requestId: request.id });
      setIsApproveOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : "Failed to approve new store request."
      );
    }
  };

  const handleConfirmReject = async () => {
    setActionError(null);
    if (!rejectionReason.trim()) {
      setRejectReasonError(true);
      return;
    }
    try {
      await rejectMutation.mutateAsync({
        requestId: request.id,
        reason: rejectionReason.trim(),
      });
      setIsRejectOpen(false);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : "Failed to reject new store request."
      );
    }
  };

  const isBusy = approveMutation.isPending || rejectMutation.isPending;
  const location = [request.city, request.province].filter(Boolean).join(", ") || "Location unspecified";
  const displayRequester = (() => {
    const raw = (request.requestedByName || "").trim();
    if (!raw || raw === "," || raw.replace(/[,\s]/g, "") === "" || raw.toLowerCase() === "unknown") {
      return "Admin / Ops";
    }
    return raw;
  })();

  return (
    <div className="rounded-lg border border-border-default bg-surface-base p-5 shadow-xs transition hover:border-slate-300">
      {/* Top Header: Category badge + Target Account + Proposed Store Name */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded border border-emerald-200 bg-emerald-50 px-2 py-0.5 font-mono text-xs font-semibold text-emerald-800">
              <Store className="h-3 w-3" aria-hidden="true" />
              NEW STORE
            </span>
            <span className="inline-flex items-center gap-1 rounded border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700">
              {request.accountName || "Unassigned Account"}
            </span>
            <span className="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800">
              Pending Verification
            </span>
          </div>

          <h3 className="flex items-center gap-1.5 text-base font-semibold text-text-primary">
            <Building2 className="h-4 w-4 shrink-0 text-text-muted" aria-hidden="true" />
            <span className="truncate">{request.storeName}</span>
          </h3>
        </div>

        {/* Action Buttons */}
        <div className="flex items-center gap-2">
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
            <span>Approve Store</span>
          </button>
        </div>
      </div>

      {/* Action Error Banner */}
      {actionError && (
        <div className="mt-3 flex items-start gap-2 rounded-md border border-rose-200 bg-rose-50 p-2.5 text-xs text-rose-800">
          <AlertTriangle className="h-4 w-4 shrink-0 text-rose-600 mt-0.5" />
          <div className="flex-1">{actionError}</div>
          <button
            type="button"
            onClick={() => setActionError(null)}
            className="text-rose-500 hover:text-rose-700"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      {/* Structured Metadata Grid */}
      <div className="mt-4 grid grid-cols-1 gap-3 rounded-md border border-border-default bg-slate-50/60 p-3.5 text-xs sm:grid-cols-2 lg:grid-cols-4">
        {/* Account */}
        <div>
          <span className="block font-medium text-text-muted">Target Account</span>
          <span className="mt-0.5 block font-semibold text-text-primary">
            {request.accountName || "—"}
          </span>
        </div>

        {/* Cencom Group */}
        <div>
          <span className="block font-medium text-text-muted">CENCOM Group</span>
          <span className="mt-0.5 flex items-center gap-1 font-semibold text-text-primary">
            <Layers className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
            {request.groupName || "General / Direct"}
          </span>
        </div>

        {/* Region / Location */}
        <div>
          <span className="block font-medium text-text-muted">Region / Location</span>
          <span className="mt-0.5 flex items-center gap-1 font-semibold text-text-primary">
            <MapPin className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
            <span className="truncate">{location}</span>
          </span>
        </div>

        {/* Requester & Date */}
        <div>
          <span className="block font-medium text-text-muted">Requested By</span>
          <div className="mt-0.5 flex items-center gap-1.5 font-medium text-text-primary">
            <User className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
            <span className="truncate">{displayRequester}</span>
          </div>
          <span className="flex items-center gap-1 text-[11px] text-text-secondary mt-0.5">
            <Clock className="h-3 w-3" aria-hidden="true" />
            {formatDate(request.requestedAt)}
          </span>
        </div>
      </div>

      {/* Requester Remarks / Justification */}
      <div className="mt-3 rounded-md border border-slate-200/80 bg-white p-3 text-xs">
        <div className="flex items-center gap-1.5 font-medium text-text-secondary">
          <MessageSquare className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
          <span>Operational Justification & Remarks</span>
        </div>
        <p className="mt-1 text-text-primary leading-relaxed whitespace-pre-wrap">
          {request.reason ? request.reason : <span className="italic text-text-muted">No justification remarks provided.</span>}
        </p>
      </div>

      {/* ── Approve Confirmation Modal ────────────────────────────────────────── */}
      {isApproveOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                  <CheckCircle2 className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Approve Store Addition
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Confirm adding this branch to the active store registry
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={approveMutation.isPending}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-1.5">
              <div className="flex justify-between">
                <span className="text-text-muted">Store Name:</span>
                <span className="font-semibold text-text-primary">{request.storeName}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Account:</span>
                <span className="font-medium text-text-primary">{request.accountName}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Location:</span>
                <span className="font-medium text-text-primary">{location}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Group:</span>
                <span className="font-medium text-text-primary">{request.groupName || "General / Direct"}</span>
              </div>
            </div>

            <p className="mt-3 text-xs text-text-secondary leading-relaxed">
              Upon approval, this store will be instantly created with active status in the database store registry and unlocked for headcount planning and allocations.
            </p>

            <div className="mt-6 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setIsApproveOpen(false)}
                disabled={approveMutation.isPending}
                className="rounded-md border border-border-default bg-white px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={approveMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-md bg-emerald-600 px-4 py-1.5 text-xs font-medium text-white hover:bg-emerald-700 disabled:opacity-50 transition"
              >
                {approveMutation.isPending ? (
                  <>
                    <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                    <span>Activating Store...</span>
                  </>
                ) : (
                  <>
                    <CheckCircle2 className="h-3.5 w-3.5" />
                    <span>Confirm & Activate</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Reject Reason Dialog ──────────────────────────────────────────────── */}
      {isRejectOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-rose-100 text-rose-700">
                  <XCircle className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Reject New Store Request
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Decline branch onboarding for {request.storeName}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={rejectMutation.isPending}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-4">
              <label
                htmlFor={`rejection-reason-${request.id}`}
                className="block text-xs font-medium text-text-primary"
              >
                Rejection Reason <span className="text-rose-500">*</span>
              </label>
              <textarea
                id={`rejection-reason-${request.id}`}
                rows={3}
                placeholder="Explain why this new store request is being rejected..."
                value={rejectionReason}
                onChange={(e) => {
                  setRejectionReason(e.target.value);
                  if (rejectReasonError && e.target.value.trim()) {
                    setRejectReasonError(false);
                  }
                }}
                className={`mt-1.5 w-full rounded-md border p-2.5 text-xs text-text-primary focus:outline-hidden ${
                  rejectReasonError
                    ? "border-rose-400 focus:border-rose-500 bg-rose-50/20"
                    : "border-border-default focus:border-brand-500 bg-white"
                }`}
              />
              {rejectReasonError && (
                <p className="mt-1 text-[11px] font-medium text-rose-600">
                  Please provide a reason for rejecting this request.
                </p>
              )}
            </div>

            <div className="mt-6 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setIsRejectOpen(false)}
                disabled={rejectMutation.isPending}
                className="rounded-md border border-border-default bg-white px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={rejectMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-md bg-rose-600 px-4 py-1.5 text-xs font-medium text-white hover:bg-rose-700 disabled:opacity-50 transition"
              >
                {rejectMutation.isPending ? (
                  <>
                    <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                    <span>Rejecting...</span>
                  </>
                ) : (
                  <>
                    <XCircle className="h-3.5 w-3.5" />
                    <span>Reject Request</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
