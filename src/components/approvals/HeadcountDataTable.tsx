"use client";

import { useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  CheckCheck,
  CheckCircle2,
  Clock,
  Layers,
  RefreshCw,
  TrendingDown,
  TrendingUp,
  X,
  XCircle,
} from "lucide-react";
import {
  useApproveHeadcountRequest,
  useRejectHeadcountRequest,
  type HeadcountRequestItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";

interface HeadcountDataTableProps {
  requests: HeadcountRequestItem[];
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

export function HeadcountDataTable({ requests, tab }: HeadcountDataTableProps) {
  // Modal states for single action
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<HeadcountRequestItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<HeadcountRequestItem | null>(null);
  const [remarks, setRemarks] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  // Multi-selector state
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [isBulkApproveOpen, setIsBulkApproveOpen] = useState(false);
  const [isBulkRejectOpen, setIsBulkRejectOpen] = useState(false);
  const [bulkRejectionReason, setBulkRejectionReason] = useState("");
  const [bulkRejectReasonError, setBulkRejectReasonError] = useState(false);
  const [isBulkProcessing, setIsBulkProcessing] = useState(false);
  const [bulkFeedback, setBulkFeedback] = useState<{
    type: "success" | "error";
    message: string;
  } | null>(null);

  const approveMutation = useApproveHeadcountRequest();
  const rejectMutation = useRejectHeadcountRequest();

  const isAllSelected = requests.length > 0 && selectedIds.size === requests.length;

  const toggleSelectAll = () => {
    if (isAllSelected) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(requests.map((r) => r.id)));
    }
  };

  const toggleSelectOne = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleOpenApprove = (req: HeadcountRequestItem) => {
    setActionError(null);
    setRemarks("");
    setSelectedApproveRequest(req);
  };

  const handleOpenReject = (req: HeadcountRequestItem) => {
    setActionError(null);
    setRemarks("");
    setSelectedRejectRequest(req);
  };

  const handleConfirmApprove = async () => {
    if (!selectedApproveRequest) return;
    setActionError(null);
    try {
      await approveMutation.mutateAsync({
        requestId: selectedApproveRequest.id,
        remarks: remarks.trim() || undefined,
        isQuotaAmendment: selectedApproveRequest.isQuotaAmendment,
      });
      setSelectedApproveRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve headcount request."
      );
    }
  };

  const handleConfirmReject = async () => {
    if (!selectedRejectRequest) return;
    setActionError(null);
    try {
      await rejectMutation.mutateAsync({
        requestId: selectedRejectRequest.id,
        remarks: remarks.trim() || undefined,
      });
      setSelectedRejectRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject headcount request."
      );
    }
  };

  // Bulk actions handlers
  const handleOpenBulkApprove = () => {
    if (selectedIds.size === 0) {
      setSelectedIds(new Set(requests.map((r) => r.id)));
    }
    setIsBulkApproveOpen(true);
  };

  const handleOpenBulkReject = () => {
    if (selectedIds.size === 0) {
      setSelectedIds(new Set(requests.map((r) => r.id)));
    }
    setBulkRejectionReason("");
    setBulkRejectReasonError(false);
    setIsBulkRejectOpen(true);
  };

  const handleConfirmBulkApprove = async () => {
    setIsBulkProcessing(true);
    setBulkFeedback(null);
    const targetRequests = requests.filter((r) => selectedIds.has(r.id));
    let successCount = 0;
    const errors: string[] = [];

    for (const req of targetRequests) {
      try {
        await approveMutation.mutateAsync({
          requestId: req.id,
          isQuotaAmendment: req.isQuotaAmendment,
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.storeName}`);
      }
    }

    setIsBulkProcessing(false);
    setIsBulkApproveOpen(false);
    setSelectedIds(new Set());

    if (errors.length > 0) {
      setBulkFeedback({
        type: "error",
        message: `Approved ${successCount} requests, but ${errors.length} failed: ${errors[0]}`,
      });
    } else {
      setBulkFeedback({
        type: "success",
        message: `Successfully approved all ${successCount} selected headcount requests.`,
      });
    }
  };

  const handleConfirmBulkReject = async () => {
    if (!bulkRejectionReason.trim() || bulkRejectionReason.trim().length < 3) {
      setBulkRejectReasonError(true);
      return;
    }
    setIsBulkProcessing(true);
    setBulkFeedback(null);
    const targetRequests = requests.filter((r) => selectedIds.has(r.id));
    let successCount = 0;
    const errors: string[] = [];

    for (const req of targetRequests) {
      try {
        await rejectMutation.mutateAsync({
          requestId: req.id,
          remarks: bulkRejectionReason.trim(),
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.storeName}`);
      }
    }

    setIsBulkProcessing(false);
    setIsBulkRejectOpen(false);
    setSelectedIds(new Set());

    if (errors.length > 0) {
      setBulkFeedback({
        type: "error",
        message: `Rejected ${successCount} requests, but ${errors.length} failed: ${errors[0]}`,
      });
    } else {
      setBulkFeedback({
        type: "success",
        message: `Successfully rejected ${successCount} selected headcount requests.`,
      });
    }
  };

  const isBusy = approveMutation.isPending || rejectMutation.isPending || isBulkProcessing;

  return (
    <div className="flex-1 min-h-0 flex flex-col">
      {/* Feedback banner */}
      {bulkFeedback && (
        <div
          className={`mb-3 flex items-center justify-between rounded-md p-2.5 text-xs ${
            bulkFeedback.type === "success"
              ? "border border-emerald-200 bg-emerald-50 text-emerald-800"
              : "border border-rose-200 bg-rose-50 text-rose-800"
          }`}
        >
          <span>{bulkFeedback.message}</span>
          <button
            type="button"
            onClick={() => setBulkFeedback(null)}
            className="text-text-muted hover:text-text-primary"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      {/* Multi-selection Bar (Pending only) */}
      {tab === "pending" && requests.length > 0 && (
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2.5 rounded-lg border border-border-default bg-slate-50/80 px-3.5 py-2 text-xs">
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={isAllSelected}
              ref={(el) => {
                if (el) {
                  el.indeterminate = selectedIds.size > 0 && !isAllSelected;
                }
              }}
              onChange={toggleSelectAll}
              className="h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500 cursor-pointer"
            />
            <span className="font-medium text-text-primary">
              {selectedIds.size > 0 ? (
                <>
                  <span className="font-bold text-brand-700">{selectedIds.size}</span> of{" "}
                  <span className="font-semibold">{requests.length}</span> selected
                </>
              ) : (
                <span className="text-text-secondary">Select All ({requests.length})</span>
              )}
            </span>
            {selectedIds.size > 0 && (
              <button
                type="button"
                onClick={() => setSelectedIds(new Set())}
                className="ml-1 text-2xs text-text-muted hover:text-text-primary underline"
              >
                Clear
              </button>
            )}
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleOpenBulkReject}
              disabled={isBusy}
              className="inline-flex h-7 items-center gap-1 rounded-md border border-rose-300 bg-white px-2.5 text-xs font-medium text-rose-700 shadow-2xs hover:bg-rose-50 hover:border-rose-400 disabled:opacity-50 transition"
            >
              <XCircle className="h-3 w-3" />
              <span>Reject {selectedIds.size > 0 ? `(${selectedIds.size})` : "All"}</span>
            </button>

            <button
              type="button"
              onClick={handleOpenBulkApprove}
              disabled={isBusy}
              className="inline-flex h-7 items-center gap-1.5 rounded-md border border-emerald-600 bg-emerald-600 px-3 text-xs font-medium text-white shadow-2xs hover:bg-emerald-700 disabled:opacity-50 transition"
            >
              <CheckCircle2 className="h-3 w-3" />
              <span>Approve {selectedIds.size > 0 ? `(${selectedIds.size})` : "All"}</span>
            </button>
          </div>
        </div>
      )}

      {/* Table Container */}
      <div className="flex-1 min-h-0 flex flex-col rounded-lg border border-border-default bg-surface-base shadow-2xs overflow-hidden">
        <div className="flex-1 overflow-x-auto">
          <table className="w-full min-w-[980px] border-collapse text-left text-xs">
            <thead className="sticky top-0 z-10 bg-slate-50 text-[11px] font-semibold uppercase text-text-secondary border-b border-border-default">
              <tr>
                {tab === "pending" && (
                  <th scope="col" className="w-10 px-3.5 py-2.5 text-left">
                    <input
                      type="checkbox"
                      checked={isAllSelected}
                      ref={(el) => {
                        if (el) {
                          el.indeterminate = selectedIds.size > 0 && !isAllSelected;
                        }
                      }}
                      onChange={toggleSelectAll}
                      aria-label="Select all rows"
                      className="h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500 cursor-pointer"
                    />
                  </th>
                )}
                <th scope="col" className="px-3.5 py-2.5">
                  TYPE
                </th>
                <th scope="col" className="px-3.5 py-2.5">
                  GROUP
                </th>
                <th scope="col" className="px-3.5 py-2.5">
                  ACCOUNT
                </th>
                <th scope="col" className="px-3.5 py-2.5">
                  STORE
                </th>
                <th scope="col" className="px-3.5 py-2.5">
                  POSITION / VCODE
                </th>
                <th scope="col" className="px-3.5 py-2.5">
                  PROPOSED CHANGE
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
                  reqStatus === "approved" ||
                  reqStatus === "completed" ||
                  reqStatus === "approved_pending_vcode";
                const isRowSelected = selectedIds.has(request.id);

                return (
                  <tr
                    key={request.id}
                    className={`transition-colors hover:bg-slate-50/80 ${
                      isRowSelected ? "bg-brand-50/30" : ""
                    }`}
                  >
                    {tab === "pending" && (
                      <td className="w-10 px-3.5 py-2.5 text-left">
                        <input
                          type="checkbox"
                          checked={isRowSelected}
                          onChange={() => toggleSelectOne(request.id)}
                          aria-label={`Select request for ${request.storeName}`}
                          className="h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500 cursor-pointer"
                        />
                      </td>
                    )}

                    {/* TYPE */}
                    <td className="px-3.5 py-2.5 whitespace-nowrap">
                      {request.isQuotaAmendment ? (
                        <span className="inline-flex items-center gap-1 rounded border border-purple-200 bg-purple-50 px-2 py-0.5 text-xs font-semibold text-purple-700">
                          Quota Amendment
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs font-semibold text-blue-700">
                          {request.requestType}
                        </span>
                      )}
                    </td>

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
                        {request.accountName || "—"}
                      </span>
                    </td>

                    {/* STORE */}
                    <td className="px-3.5 py-2.5 font-bold text-text-primary text-xs sm:text-[13px] whitespace-nowrap">
                      {request.storeName || "—"}
                    </td>

                    {/* POSITION / VCODE */}
                    <td className="px-3.5 py-2.5 whitespace-nowrap">
                      <div className="flex flex-col">
                        <span className="font-medium text-text-primary text-xs">
                          {request.positionName || "—"}
                        </span>
                        {request.targetVcode && (
                          <span className="font-mono text-[10px] text-text-muted">
                            {request.targetVcode}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* PROPOSED CHANGE */}
                    <td className="px-3.5 py-2.5 whitespace-nowrap">
                      {request.isQuotaAmendment ? (
                        <div className="inline-flex items-center gap-1.5 font-mono text-xs">
                          <span className="text-text-muted">
                            {request.previousTarget ?? 0}
                          </span>
                          <ArrowRight className="h-3 w-3 text-text-muted" />
                          <span className="font-bold text-text-primary">
                            {request.proposedTarget ?? 0}
                          </span>
                          {request.delta !== null && (
                            <span
                              className={`inline-flex items-center gap-0.5 rounded px-1.5 py-0.2 text-[10px] font-bold ${
                                request.isExpansion
                                  ? "bg-emerald-100 text-emerald-800"
                                  : request.isReduction
                                    ? "bg-rose-100 text-rose-800"
                                    : "bg-slate-100 text-slate-700"
                              }`}
                            >
                              {request.isExpansion ? (
                                <TrendingUp className="h-2.5 w-2.5" />
                              ) : request.isReduction ? (
                                <TrendingDown className="h-2.5 w-2.5" />
                              ) : null}
                              {request.delta > 0 ? `+${request.delta}` : request.delta}
                            </span>
                          )}
                        </div>
                      ) : (
                        <span className="font-mono text-xs font-semibold text-text-primary">
                          +{request.headcountNeeded} needed
                        </span>
                      )}
                    </td>

                    {/* REQUESTED BY */}
                    <td className="px-3.5 py-2.5 text-text-secondary whitespace-nowrap">
                      <div className="flex flex-col">
                        <span className="font-medium text-text-primary text-xs">
                          {request.requestedByName || "Unknown"}
                        </span>
                        <span className="font-mono text-[10px] text-text-muted flex items-center gap-1">
                          <Clock className="h-3 w-3 inline text-text-muted" aria-hidden="true" />
                          {formatDate(request.requestedAt)}
                        </span>
                      </div>
                    </td>

                    {/* ACTION / REJECTED REASON */}
                    <td className={`px-3.5 py-2.5 ${tab === "rejected" ? "text-left" : "text-right"}`}>
                      {tab === "rejected" ? (
                        <div className="flex flex-col max-w-xs">
                          <span className="text-xs font-medium text-rose-700 bg-rose-50 border border-rose-200 rounded px-2 py-1">
                            {request.reviewerRemarks || "No rejection remarks recorded"}
                          </span>
                          {request.reviewedAt && (
                            <span className="font-mono text-[10px] text-text-muted mt-1 flex items-center gap-1">
                              <Clock className="h-3 w-3 inline text-text-muted" aria-hidden="true" />
                              {formatDate(request.reviewedAt)}
                            </span>
                          )}
                        </div>
                      ) : isPending ? (
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
                            <span>Approve</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex flex-col items-end gap-0.5">
                          <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 text-[11px] font-semibold text-emerald-800">
                            <CheckCircle2 className="h-3 w-3" aria-hidden="true" />
                            Approved
                          </span>
                          {request.reviewedAt && (
                            <span className="font-mono text-[10px] text-text-muted">
                              {formatDate(request.reviewedAt)}
                            </span>
                          )}
                        </div>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-0.5 text-[11px] font-medium text-slate-700">
                          {request.status}
                        </span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Single Approve Modal */}
      {selectedApproveRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                  <CheckCircle2 className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Approve Headcount Request
                  </h3>
                  <p className="text-xs text-text-secondary">
                    {selectedApproveRequest.isQuotaAmendment
                      ? "Authorize quota amendment and sync target capacities"
                      : "Confirm standard headcount expansion"}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setSelectedApproveRequest(null)}
                disabled={isBusy}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-1.5">
              <div className="flex justify-between">
                <span className="text-text-muted">Store:</span>
                <span className="font-semibold text-text-primary">
                  {selectedApproveRequest.storeName || "—"}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Position:</span>
                <span className="font-medium text-text-primary">
                  {selectedApproveRequest.positionName || "—"}
                </span>
              </div>
              {selectedApproveRequest.isQuotaAmendment ? (
                <div className="flex justify-between">
                  <span className="text-text-muted">Target Change:</span>
                  <span className="font-bold text-emerald-700">
                    {selectedApproveRequest.previousTarget ?? 0} → {selectedApproveRequest.proposedTarget ?? 0}
                  </span>
                </div>
              ) : (
                <div className="flex justify-between">
                  <span className="text-text-muted">Quota Needed:</span>
                  <span className="font-bold text-emerald-700">
                    +{selectedApproveRequest.headcountNeeded}
                  </span>
                </div>
              )}
            </div>

            <div className="mt-4 space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Reviewer Remarks (Optional)
              </label>
              <textarea
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                rows={2}
                placeholder="Optional notes or instructions for this approval..."
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
                <span>Confirm Approval</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Single Reject Modal */}
      {selectedRejectRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-rose-100 text-rose-700">
                  <XCircle className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Reject Headcount Request
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Provide reason for denying this quota adjustment
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setSelectedRejectRequest(null)}
                disabled={isBusy}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-1.5">
              <div className="flex justify-between">
                <span className="text-text-muted">Store:</span>
                <span className="font-semibold text-text-primary">
                  {selectedRejectRequest.storeName || "—"}
                </span>
              </div>
            </div>

            <div className="mt-4 space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Rejection Reason
              </label>
              <textarea
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                rows={3}
                placeholder="Explain why this request is being rejected..."
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

      {/* Bulk Approve Confirmation Modal */}
      {isBulkApproveOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                  <CheckCheck className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Approve {selectedIds.size} Headcount Request{selectedIds.size === 1 ? "" : "s"}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Bulk quota authorization confirmation
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsBulkApproveOpen(false)}
                disabled={isBulkProcessing}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-2">
              <p className="text-text-primary font-medium">
                Are you sure you want to approve all{" "}
                <span className="font-bold text-emerald-700">{selectedIds.size}</span>{" "}
                selected headcount and quota requests?
              </p>
              <p className="text-text-secondary">
                This will automatically apply target adjustments and provision requested staffing quotas in the database.
              </p>
            </div>

            <div className="mt-6 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setIsBulkApproveOpen(false)}
                disabled={isBulkProcessing}
                className="rounded-md border border-border-default bg-white px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkApprove}
                disabled={isBulkProcessing}
                className="inline-flex items-center gap-1.5 rounded-md bg-emerald-600 px-4 py-1.5 text-xs font-medium text-white hover:bg-emerald-700 disabled:opacity-50 transition"
              >
                {isBulkProcessing ? (
                  <>
                    <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                    <span>Processing...</span>
                  </>
                ) : (
                  <>
                    <CheckCheck className="h-3.5 w-3.5" />
                    <span>Confirm Bulk Approve</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Bulk Reject Confirmation Modal */}
      {isBulkRejectOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-rose-100 text-rose-700">
                  <XCircle className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Reject {selectedIds.size} Headcount Request{selectedIds.size === 1 ? "" : "s"}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Bulk rejection justification
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsBulkRejectOpen(false)}
                disabled={isBulkProcessing}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mt-4 space-y-3">
              <div>
                <label className="block text-xs font-medium text-text-primary">
                  Rejection Reason <span className="text-rose-600">*</span>
                </label>
                <textarea
                  rows={3}
                  value={bulkRejectionReason}
                  onChange={(e) => {
                    setBulkRejectionReason(e.target.value);
                    if (e.target.value.trim().length >= 3) setBulkRejectReasonError(false);
                  }}
                  placeholder="State the reason for rejecting these headcount adjustment requests..."
                  className={`mt-1 w-full rounded-md border p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:outline-hidden ${
                    bulkRejectReasonError
                      ? "border-rose-300 focus:border-rose-500"
                      : "border-border-default focus:border-brand-500"
                  }`}
                />
                {bulkRejectReasonError && (
                  <p className="mt-1 text-2xs text-rose-600">
                    Please provide a rejection reason (minimum 3 characters).
                  </p>
                )}
              </div>
            </div>

            <div className="mt-6 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setIsBulkRejectOpen(false)}
                disabled={isBulkProcessing}
                className="rounded-md border border-border-default bg-white px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkReject}
                disabled={isBulkProcessing}
                className="inline-flex items-center gap-1.5 rounded-md bg-rose-600 px-4 py-1.5 text-xs font-medium text-white hover:bg-rose-700 disabled:opacity-50 transition"
              >
                {isBulkProcessing ? (
                  <>
                    <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                    <span>Processing...</span>
                  </>
                ) : (
                  <>
                    <XCircle className="h-3.5 w-3.5" />
                    <span>Confirm Bulk Reject</span>
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
