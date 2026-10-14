"use client";

import { useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  ArrowLeftRight,
  CheckCircle2,
  Clock,
  RefreshCw,
  X,
  XCircle,
} from "lucide-react";
import {
  useApproveApplicantMovement,
  useRejectApplicantMovement,
  type ApplicantMovementRequestItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";

interface ApplicantMovementDataTableProps {
  requests: ApplicantMovementRequestItem[];
  tab: ApprovalStatusTab;
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

export function ApplicantMovementDataTable({
  requests,
  tab,
}: ApplicantMovementDataTableProps) {
  // Modal states
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<ApplicantMovementRequestItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<ApplicantMovementRequestItem | null>(null);

  const [approveNote, setApproveNote] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
  const [rejectReasonError, setRejectReasonError] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const approveMutation = useApproveApplicantMovement();
  const rejectMutation = useRejectApplicantMovement();

  const handleOpenApprove = (req: ApplicantMovementRequestItem) => {
    setActionError(null);
    setApproveNote("");
    setSelectedApproveRequest(req);
  };

  const handleOpenReject = (req: ApplicantMovementRequestItem) => {
    setActionError(null);
    setRejectionReason("");
    setRejectReasonError(false);
    setSelectedRejectRequest(req);
  };

  const handleConfirmApprove = async () => {
    if (!selectedApproveRequest) return;
    setActionError(null);
    try {
      await approveMutation.mutateAsync({
        requestId: selectedApproveRequest.id,
        note: approveNote.trim() || undefined,
      });
      setSelectedApproveRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve applicant movement request."
      );
    }
  };

  const handleConfirmReject = async () => {
    if (!selectedRejectRequest) return;
    setActionError(null);
    if (!rejectionReason.trim()) {
      setRejectReasonError(true);
      return;
    }
    try {
      await rejectMutation.mutateAsync({
        requestId: selectedRejectRequest.id,
        reason: rejectionReason.trim(),
      });
      setSelectedRejectRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject applicant movement request."
      );
    }
  };

  const isBusy = approveMutation.isPending || rejectMutation.isPending;

  return (
    <div className="flex-1 min-h-0 flex flex-col rounded-lg border border-border-default bg-surface-base shadow-2xs overflow-hidden">
      <div className="flex-1 overflow-x-auto">
        <table className="w-full min-w-[980px] border-collapse text-left text-xs">
          <thead className="sticky top-0 z-10 bg-slate-50 text-[11px] font-semibold uppercase text-text-secondary border-b border-border-default">
            <tr>
              <th scope="col" className="px-3.5 py-2.5">
                REQ NO
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                TYPE
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                SOURCE
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                TARGET DESTINATION
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                REASON
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                REQUESTED BY
              </th>
              <th
                scope="col"
                className={`px-3.5 py-2.5 ${tab === "rejected" ? "text-left" : "text-right"}`}
              >
                {tab === "rejected" ? "REJECTED REASON" : "ACTION"}
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-default">
            {requests.map((request) => {
              const reqStatus = (request.status || "").toLowerCase();
              const isPending = tab === "pending" || reqStatus === "pending";
              const isApproved =
                reqStatus === "approved" || reqStatus === "completed";
              const isSwap = request.movementType === "SWAP";

              return (
                <tr
                  key={request.id}
                  className="transition-colors hover:bg-slate-50/80"
                >
                  {/* REQ NO */}
                  <td className="px-3.5 py-2.5 font-mono font-bold text-text-primary text-xs whitespace-nowrap">
                    {request.requestNumber}
                  </td>

                  {/* TYPE */}
                  <td className="px-3.5 py-2.5 whitespace-nowrap">
                    <span
                      className={`inline-flex items-center gap-1 rounded border px-2 py-0.5 text-xs font-semibold ${
                        isSwap
                          ? "border-purple-200 bg-purple-50 text-purple-800"
                          : "border-blue-200 bg-blue-50 text-blue-800"
                      }`}
                    >
                      {isSwap ? (
                        <ArrowLeftRight className="h-3 w-3" />
                      ) : (
                        <ArrowRight className="h-3 w-3" />
                      )}
                      {request.movementType}
                    </span>
                  </td>

                  {/* SOURCE */}
                  <td className="px-3.5 py-2.5">
                    <div className="flex flex-col">
                      <span className="font-bold text-text-primary text-xs sm:text-[13px]">
                        {request.sourceApplicantName}
                      </span>
                      <span className="text-[11px] text-text-muted">
                        {request.sourceStoreName || "Store"} • {request.sourceVacancyVcode}
                      </span>
                    </div>
                  </td>

                  {/* TARGET DESTINATION */}
                  <td className="px-3.5 py-2.5">
                    <div className="flex flex-col">
                      {isSwap && request.targetApplicantName ? (
                        <span className="font-bold text-text-primary text-xs sm:text-[13px]">
                          ↔ {request.targetApplicantName}
                        </span>
                      ) : null}
                      <span className="font-medium text-text-primary text-xs">
                        {request.targetStoreName || "Target Store"}
                      </span>
                      <span className="font-mono text-[10px] text-text-muted">
                        {request.targetVacancyVcode}
                      </span>
                    </div>
                  </td>

                  {/* REASON */}
                  <td className="px-3.5 py-2.5 max-w-xs truncate text-text-secondary" title={request.remarks || request.reason}>
                    <div className="flex flex-col">
                      <span className="font-medium text-text-primary text-xs truncate">
                        {request.reason}
                      </span>
                      {request.remarks && (
                        <span className="text-[10px] text-text-muted truncate">
                          {request.remarks}
                        </span>
                      )}
                    </div>
                  </td>

                  {/* REQUESTED BY */}
                  <td className="px-3.5 py-2.5 whitespace-nowrap">
                    <div className="flex flex-col">
                      <span className="font-medium text-text-primary text-xs">
                        {request.requestedByName}
                      </span>
                      <span className="text-[11px] text-text-muted flex items-center gap-1">
                        <Clock className="h-3 w-3 inline text-text-muted" aria-hidden="true" />
                        {formatDate(request.requestedAt)}
                      </span>
                    </div>
                  </td>

                  {/* ACTION / REJECTED REASON */}
                  <td
                    className={`px-3.5 py-2.5 ${
                      tab === "rejected" ? "text-left" : "text-right whitespace-nowrap"
                    }`}
                  >
                    {isPending ? (
                      <div className="inline-flex items-center justify-end gap-2">
                        <button
                          type="button"
                          onClick={() => handleOpenReject(request)}
                          disabled={isBusy}
                          className="inline-flex h-7 items-center gap-1 rounded-md border border-rose-300 bg-white px-2.5 text-xs font-medium text-rose-700 shadow-2xs hover:bg-rose-50 hover:border-rose-400 disabled:opacity-50 transition"
                        >
                          <XCircle className="h-3 w-3" aria-hidden="true" />
                          <span>Reject</span>
                        </button>
                        <button
                          type="button"
                          onClick={() => handleOpenApprove(request)}
                          disabled={isBusy}
                          className="inline-flex h-7 items-center gap-1 rounded-md border border-emerald-600 bg-emerald-600 px-2.5 text-xs font-medium text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50 transition"
                        >
                          <CheckCircle2 className="h-3 w-3" aria-hidden="true" />
                          <span>Approve Movement</span>
                        </button>
                      </div>
                    ) : isApproved ? (
                      <div className="inline-flex flex-col items-end gap-0.5">
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 text-[11px] font-semibold text-emerald-800">
                          <CheckCircle2 className="h-3 w-3" aria-hidden="true" />
                          Moved
                        </span>
                        {request.createdAt && (
                          <span className="text-[10px] font-mono text-text-muted">
                            {formatDate(request.effectiveDate || request.createdAt)}
                          </span>
                        )}
                      </div>
                    ) : (
                      <div className="flex flex-col items-start gap-0.5 max-w-xs">
                        <span className="font-semibold text-rose-700 text-xs break-words">
                          {request.rejectionReason || request.remarks || "No reason specified"}
                        </span>
                        {request.effectiveDate && (
                          <span className="text-[10px] font-mono text-text-muted">
                            Rejected: {formatDate(request.effectiveDate)}
                          </span>
                        )}
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Approve Modal */}
      {selectedApproveRequest && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-xs"
          role="dialog"
          aria-modal="true"
        >
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-in fade-in zoom-in-95">
            <div className="flex items-start justify-between gap-4">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700">
                  <CheckCircle2 className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="font-bold text-text-primary text-sm">
                    Approve {selectedApproveRequest.movementType}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Confirm reassignment of applicant slots
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setSelectedApproveRequest(null)}
                disabled={isBusy}
                className="rounded-md p-1 text-text-muted hover:bg-slate-100 hover:text-text-primary"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-4 rounded-lg bg-slate-50 p-3 text-xs space-y-1.5 border border-border-default">
              <div className="flex justify-between">
                <span className="text-text-muted">Applicant:</span>
                <span className="font-semibold text-text-primary">
                  {selectedApproveRequest.sourceApplicantName}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Destination:</span>
                <span className="font-medium text-emerald-800">
                  {selectedApproveRequest.targetStoreName} ({selectedApproveRequest.targetVacancyVcode})
                </span>
              </div>
            </div>

            <div className="mt-4 space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Approval Note (Optional)
              </label>
              <textarea
                value={approveNote}
                onChange={(e) => setApproveNote(e.target.value)}
                rows={2}
                placeholder="Add approval remarks or instructions..."
                className="w-full rounded-md border border-border-default bg-white p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
              />
            </div>

            {actionError && (
              <div className="mt-3 flex items-start gap-2 rounded-md bg-rose-50 p-2.5 text-xs text-rose-700 border border-rose-200">
                <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="mt-5 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setSelectedApproveRequest(null)}
                disabled={isBusy}
                className="h-8 rounded-md border border-border-default bg-white px-3 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={isBusy}
                className="inline-flex h-8 items-center gap-1.5 rounded-md bg-emerald-600 px-3.5 text-xs font-semibold text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50"
              >
                {approveMutation.isPending && (
                  <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                )}
                <span>Confirm Movement</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reject Modal */}
      {selectedRejectRequest && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-xs"
          role="dialog"
          aria-modal="true"
        >
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-in fade-in zoom-in-95">
            <div className="flex items-start justify-between gap-4">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-rose-100 text-rose-700">
                  <XCircle className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="font-bold text-text-primary text-sm">
                    Reject Applicant Movement
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Provide reason for rejecting transfer request
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setSelectedRejectRequest(null)}
                disabled={isBusy}
                className="rounded-md p-1 text-text-muted hover:bg-slate-100 hover:text-text-primary"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-4 space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Rejection Reason <span className="text-rose-500">*</span>
              </label>
              <textarea
                value={rejectionReason}
                onChange={(e) => {
                  setRejectionReason(e.target.value);
                  if (rejectReasonError && e.target.value.trim()) {
                    setRejectReasonError(false);
                  }
                }}
                rows={3}
                placeholder="Explain why this movement request is rejected..."
                className={`w-full rounded-md border p-2 text-xs text-text-primary placeholder:text-text-muted focus:outline-hidden ${
                  rejectReasonError
                    ? "border-rose-400 bg-rose-50/30 focus:border-rose-500"
                    : "border-border-default bg-white focus:border-brand-500"
                }`}
              />
              {rejectReasonError && (
                <p className="text-[11px] text-rose-600 font-medium">
                  Rejection reason is required.
                </p>
              )}
            </div>

            {actionError && (
              <div className="mt-3 flex items-start gap-2 rounded-md bg-rose-50 p-2.5 text-xs text-rose-700 border border-rose-200">
                <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="mt-5 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => setSelectedRejectRequest(null)}
                disabled={isBusy}
                className="h-8 rounded-md border border-border-default bg-white px-3 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={isBusy}
                className="inline-flex h-8 items-center gap-1.5 rounded-md bg-rose-600 px-3.5 text-xs font-semibold text-white shadow-2xs hover:bg-rose-700 disabled:opacity-50"
              >
                {rejectMutation.isPending && (
                  <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                )}
                <span>Confirm Rejection</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
