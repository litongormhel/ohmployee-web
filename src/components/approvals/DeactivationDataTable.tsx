"use client";

import { useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Clock,
  Layers,
  RefreshCw,
  X,
  XCircle,
} from "lucide-react";
import {
  useCompleteDeactivation,
  useRejectDeactivation,
  type DeactivationRequestItem,
  type DeactivationStatusTab,
} from "@/lib/queries/requests";

interface DeactivationDataTableProps {
  requests: DeactivationRequestItem[];
  tab: DeactivationStatusTab;
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

function SeparationStatusBadge({ status }: { status: string }) {
  const s = status.toLowerCase();
  let badgeClasses = "bg-slate-100 text-slate-700 border-slate-200";

  if (s.includes("awol")) {
    badgeClasses = "bg-rose-100 text-rose-800 border-rose-200";
  } else if (s.includes("contract") || s.includes("eoc")) {
    badgeClasses = "bg-purple-100 text-purple-800 border-purple-200";
  } else if (s.includes("resigned")) {
    badgeClasses = "bg-amber-100 text-amber-800 border-amber-200";
  } else if (s.includes("term") || s.includes("dismiss")) {
    badgeClasses = "bg-red-100 text-red-800 border-red-200";
  }

  return (
    <span
      className={`inline-flex items-center rounded border px-2 py-0.5 text-xs font-semibold ${badgeClasses}`}
    >
      {status}
    </span>
  );
}

export function DeactivationDataTable({ requests, tab }: DeactivationDataTableProps) {
  // Modal states
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<DeactivationRequestItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<DeactivationRequestItem | null>(null);
  const [approveRemarks, setApproveRemarks] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
  const [rejectionRemarks, setRejectionRemarks] = useState("");
  const [rejectReasonError, setRejectReasonError] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const completeMutation = useCompleteDeactivation();
  const rejectMutation = useRejectDeactivation();

  const handleOpenApprove = (req: DeactivationRequestItem) => {
    setActionError(null);
    setApproveRemarks("");
    setSelectedApproveRequest(req);
  };

  const handleOpenReject = (req: DeactivationRequestItem) => {
    setActionError(null);
    setRejectionReason("");
    setRejectionRemarks("");
    setRejectReasonError(false);
    setSelectedRejectRequest(req);
  };

  const handleConfirmApprove = async () => {
    if (!selectedApproveRequest) return;
    setActionError(null);
    try {
      await completeMutation.mutateAsync({
        requestId: selectedApproveRequest.id,
        plantillaId: selectedApproveRequest.plantillaId,
        remarks: approveRemarks.trim() || undefined,
      });
      setSelectedApproveRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to complete employee deactivation."
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
        plantillaId: selectedRejectRequest.plantillaId,
        reason: rejectionReason.trim(),
        remarks: rejectionRemarks.trim() || undefined,
      });
      setSelectedRejectRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject deactivation request."
      );
    }
  };

  const isBusy = completeMutation.isPending || rejectMutation.isPending;

  return (
    <div className="flex-1 min-h-0 flex flex-col rounded-lg border border-border-default bg-surface-base shadow-2xs overflow-hidden">
      <div className="flex-1 overflow-x-auto">
        <table className="w-full min-w-[960px] border-collapse text-left text-xs">
          <thead className="sticky top-0 z-10 bg-slate-50 text-[11px] font-semibold uppercase text-text-secondary border-b border-border-default">
            <tr>
              <th scope="col" className="px-3.5 py-2.5">
                GROUP
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                ACCOUNT
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                EMPLOC
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                FULLNAME
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                POSITION
              </th>
              <th scope="col" className="px-3.5 py-2.5">
                SEPARATION STATUS
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
              const isPending =
                tab === "pending" ||
                reqStatus === "pending" ||
                reqStatus === "under_review";
              const isApproved =
                reqStatus === "approved" || reqStatus === "completed";

              return (
                <tr
                  key={request.id}
                  className="transition-colors hover:bg-slate-50/80"
                >
                  {/* GROUP */}
                  <td className="px-3.5 py-2.5 text-text-secondary whitespace-nowrap">
                    {request.groupName ? (
                      <span className="inline-flex items-center gap-1 font-medium text-slate-700">
                        <Layers className="h-3 w-3 text-text-muted" aria-hidden="true" />
                        {request.groupName}
                      </span>
                    ) : (
                      <span className="text-text-muted">—</span>
                    )}
                  </td>

                  {/* ACCOUNT */}
                  <td className="px-3.5 py-2.5 whitespace-nowrap">
                    <span className="inline-flex items-center rounded border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs font-semibold text-blue-700">
                      {request.accountName}
                    </span>
                  </td>

                  {/* EMPLOC */}
                  <td className="px-3.5 py-2.5 font-mono text-xs text-text-secondary whitespace-nowrap">
                    {request.employeeNo || "—"}
                  </td>

                  {/* FULLNAME */}
                  <td className="px-3.5 py-2.5">
                    <div className="flex flex-col">
                      <span className="font-bold text-text-primary text-xs sm:text-[13px]">
                        {request.employeeName}
                      </span>
                      {request.resubmitCount > 0 && (
                        <span className="inline-flex items-center text-[10px] font-medium text-amber-700 mt-0.5">
                          Resubmit #{request.resubmitCount}
                        </span>
                      )}
                    </div>
                  </td>

                  {/* POSITION */}
                  <td className="px-3.5 py-2.5 text-text-secondary whitespace-nowrap">
                    {request.positionTitle || "—"}
                  </td>

                  {/* SEPARATION STATUS */}
                  <td className="px-3.5 py-2.5 whitespace-nowrap">
                    <SeparationStatusBadge status={request.separationStatus} />
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
                  <td className={`px-3.5 py-2.5 ${tab === "rejected" ? "text-left" : "text-right whitespace-nowrap"}`}>
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
                          <span>Approve Deactivation</span>
                        </button>
                      </div>
                    ) : isApproved ? (
                      <div className="inline-flex flex-col items-end gap-0.5">
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 text-[11px] font-semibold text-emerald-800">
                          <CheckCircle2 className="h-3 w-3" aria-hidden="true" />
                          Deactivated
                        </span>
                        {request.processedAt && (
                          <span className="text-[10px] font-mono text-text-muted">
                            {formatDate(request.processedAt)}
                          </span>
                        )}
                      </div>
                    ) : (
                      <div className="flex flex-col items-start gap-0.5 max-w-xs">
                        <span className="font-semibold text-rose-700 text-xs break-words">
                          {request.rejectionReason || request.remarks || "No reason specified"}
                        </span>
                        {request.processedAt && (
                          <span className="text-[10px] font-mono text-text-muted">
                            Rejected: {formatDate(request.processedAt)}
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

      {/* ── Approve Modal (Clearance Confirmation) ── */}
      {selectedApproveRequest && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-xs"
          role="dialog"
          aria-modal="true"
          aria-labelledby="approve-deact-title"
        >
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                  <CheckCircle2 className="h-5 w-5" aria-hidden="true" />
                </div>
                <div>
                  <h4
                    id="approve-deact-title"
                    className="text-base font-semibold text-text-primary"
                  >
                    Clear & Deactivate Employee
                  </h4>
                  <p className="text-xs text-text-secondary font-mono">
                    {selectedApproveRequest.employeeName}
                  </p>
                </div>
              </div>

              <button
                type="button"
                onClick={() => setSelectedApproveRequest(null)}
                disabled={isBusy}
                className="rounded-md p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary"
              >
                <X className="h-4 w-4" aria-hidden="true" />
              </button>
            </div>

            <div className="mt-4 space-y-3 text-xs">
              <p className="text-text-secondary leading-relaxed">
                Approving this deactivation will transition employee{" "}
                <strong className="text-text-primary">
                  {selectedApproveRequest.employeeName}
                </strong>{" "}
                ({selectedApproveRequest.employeeNo || "No ID"}) to{" "}
                <strong>Deactivated</strong> status, clear plantilla allocation,
                and maintain compliance records under the 15-day deactivation
                visibility window.
              </p>

              <div className="rounded-md border border-slate-200 bg-slate-50 p-2.5 text-text-secondary">
                <div className="font-medium text-slate-800">Clearance Impact:</div>
                <ul className="mt-1 list-disc pl-4 space-y-0.5">
                  <li>Plantilla slot marked deactivated</li>
                  <li>Account access disabled</li>
                  <li>Requisition slot unlocked for backfill</li>
                </ul>
              </div>

              <div>
                <label
                  htmlFor="deact-approval-remarks"
                  className="block font-medium text-text-primary mb-1"
                >
                  Clearance Remarks / Administrative Note (Optional)
                </label>
                <textarea
                  id="deact-approval-remarks"
                  rows={2}
                  value={approveRemarks}
                  onChange={(e) => setApproveRemarks(e.target.value)}
                  placeholder="Final clearance notes or separation confirmation..."
                  className="w-full rounded-md border border-border-default bg-white p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
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
                onClick={() => setSelectedApproveRequest(null)}
                disabled={isBusy}
                className="rounded-md border border-border-default bg-surface-base px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md border border-emerald-600 bg-emerald-600 px-4 py-1.5 text-xs font-medium text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50 transition"
              >
                {isBusy && (
                  <RefreshCw
                    className="h-3 w-3 animate-spin"
                    aria-hidden="true"
                  />
                )}
                <span>Confirm Deactivation</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Reject Modal (Revert Separation) ── */}
      {selectedRejectRequest && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-xs"
          role="dialog"
          aria-modal="true"
          aria-labelledby="reject-deact-title"
        >
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-rose-100 text-rose-700">
                  <XCircle className="h-5 w-5" aria-hidden="true" />
                </div>
                <div>
                  <h4
                    id="reject-deact-title"
                    className="text-base font-semibold text-text-primary"
                  >
                    Reject Deactivation Request
                  </h4>
                  <p className="text-xs text-text-secondary font-mono">
                    {selectedRejectRequest.employeeName}
                  </p>
                </div>
              </div>

              <button
                type="button"
                onClick={() => setSelectedRejectRequest(null)}
                disabled={isBusy}
                className="rounded-md p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary"
              >
                <X className="h-4 w-4" aria-hidden="true" />
              </button>
            </div>

            <div className="mt-4 space-y-3 text-xs">
              <p className="text-text-secondary leading-relaxed">
                Rejecting this request will mark the request as Rejected and retain{" "}
                <strong className="text-text-primary">
                  {selectedRejectRequest.employeeName}
                </strong>{" "}
                for Operations review and potential resubmission.
              </p>

              <div>
                <label
                  htmlFor="deact-rejection-reason"
                  className="block font-medium text-text-primary mb-1"
                >
                  Rejection Reason <span className="text-rose-600">*</span>
                </label>
                <input
                  id="deact-rejection-reason"
                  type="text"
                  value={rejectionReason}
                  onChange={(e) => {
                    setRejectionReason(e.target.value);
                    if (rejectReasonError && e.target.value.trim()) {
                      setRejectReasonError(false);
                    }
                  }}
                  placeholder="e.g. Clearance incomplete, Pending turnover, Record discrepancy"
                  className={`w-full rounded-md border p-2 text-xs text-text-primary placeholder:text-text-muted focus:outline-hidden ${
                    rejectReasonError
                      ? "border-rose-300 bg-rose-50/50 focus:border-rose-500"
                      : "border-border-default bg-white focus:border-brand-500"
                  }`}
                />
                {rejectReasonError && (
                  <p className="mt-1 text-[11px] text-rose-600 font-medium">
                    A rejection reason is required before proceeding.
                  </p>
                )}
              </div>

              <div>
                <label
                  htmlFor="deact-rejection-remarks"
                  className="block font-medium text-text-primary mb-1"
                >
                  Additional Remarks / Instructions (Optional)
                </label>
                <textarea
                  id="deact-rejection-remarks"
                  rows={2}
                  value={rejectionRemarks}
                  onChange={(e) => setRejectionRemarks(e.target.value)}
                  placeholder="Provide specific notes or steps required by requester..."
                  className="w-full rounded-md border border-border-default bg-white p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
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
                onClick={() => setSelectedRejectRequest(null)}
                disabled={isBusy}
                className="rounded-md border border-border-default bg-surface-base px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={isBusy}
                className="inline-flex items-center gap-1.5 rounded-md border border-rose-300 bg-rose-600 px-4 py-1.5 text-xs font-medium text-white shadow-2xs hover:bg-rose-700 disabled:opacity-50 transition"
              >
                {isBusy && (
                  <RefreshCw
                    className="h-3 w-3 animate-spin"
                    aria-hidden="true"
                  />
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
