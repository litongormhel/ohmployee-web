"use client";

import { useState } from "react";
import {
  AlertTriangle,
  CheckCheck,
  CheckCircle2,
  Clock,
  RefreshCw,
  X,
  XCircle,
} from "lucide-react";
import {
  useReviewVacancyClosureRequest,
  type VacancyClosureRequestItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";
import { useCurrentUser } from "@/lib/auth";

interface VacancyClosureDataTableProps {
  requests: VacancyClosureRequestItem[];
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

export function VacancyClosureDataTable({ requests, tab }: VacancyClosureDataTableProps) {
  const currentUser = useCurrentUser();
  const reviewerName = currentUser?.displayName || currentUser?.email || "Admin";

  // Modal states for single action
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<VacancyClosureRequestItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<VacancyClosureRequestItem | null>(null);
  const [approveRemarks, setApproveRemarks] = useState("");
  const [rejectionRemarks, setRejectionRemarks] = useState("");
  const [rejectReasonError, setRejectReasonError] = useState(false);
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

  const reviewMutation = useReviewVacancyClosureRequest();

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

  const handleOpenApprove = (req: VacancyClosureRequestItem) => {
    setActionError(null);
    setApproveRemarks("");
    setSelectedApproveRequest(req);
  };

  const handleOpenReject = (req: VacancyClosureRequestItem) => {
    setActionError(null);
    setRejectionRemarks("");
    setRejectReasonError(false);
    setSelectedRejectRequest(req);
  };

  const handleConfirmApprove = async () => {
    if (!selectedApproveRequest) return;
    setActionError(null);
    try {
      await reviewMutation.mutateAsync({
        requestId: selectedApproveRequest.id,
        status: "Approved",
        reviewedBy: reviewerName,
        remarks: approveRemarks.trim() || undefined,
      });
      setSelectedApproveRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve vacancy closure request."
      );
    }
  };

  const handleConfirmReject = async () => {
    if (!selectedRejectRequest) return;
    setActionError(null);
    if (!rejectionRemarks.trim()) {
      setRejectReasonError(true);
      return;
    }
    try {
      await reviewMutation.mutateAsync({
        requestId: selectedRejectRequest.id,
        status: "Rejected",
        reviewedBy: reviewerName,
        remarks: rejectionRemarks.trim(),
      });
      setSelectedRejectRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject vacancy closure request."
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
        await reviewMutation.mutateAsync({
          requestId: req.id,
          status: "Approved",
          reviewedBy: reviewerName,
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.vacancyVcode}`);
      }
    }

    setIsBulkProcessing(false);
    setIsBulkApproveOpen(false);
    setSelectedIds(new Set());

    if (errors.length > 0) {
      setBulkFeedback({
        type: "error",
        message: `Approved ${successCount} closures, but ${errors.length} failed: ${errors[0]}`,
      });
    } else {
      setBulkFeedback({
        type: "success",
        message: `Successfully approved all ${successCount} selected vacancy closure requests.`,
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
        await reviewMutation.mutateAsync({
          requestId: req.id,
          status: "Rejected",
          reviewedBy: reviewerName,
          remarks: bulkRejectionReason.trim(),
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.vacancyVcode}`);
      }
    }

    setIsBulkProcessing(false);
    setIsBulkRejectOpen(false);
    setSelectedIds(new Set());

    if (errors.length > 0) {
      setBulkFeedback({
        type: "error",
        message: `Rejected ${successCount} closures, but ${errors.length} failed: ${errors[0]}`,
      });
    } else {
      setBulkFeedback({
        type: "success",
        message: `Successfully rejected ${successCount} selected vacancy closure requests.`,
      });
    }
  };

  const isBusy = reviewMutation.isPending || isBulkProcessing;

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
          <table className="w-full min-w-[960px] border-collapse text-left text-xs">
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
                  VCODE
                </th>
                <th scope="col" className="px-3.5 py-2.5">
                  ACCOUNT
                </th>
                <th scope="col" className="px-3.5 py-2.5">
                  STORE / BRANCH
                </th>
                <th scope="col" className="px-3.5 py-2.5">
                  POSITION
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
                const isPending =
                  tab === "pending" ||
                  reqStatus === "pending" ||
                  reqStatus === "under_review";
                const isApproved =
                  reqStatus === "approved" || reqStatus === "completed";
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
                          aria-label={`Select closure for ${request.vacancyVcode}`}
                          className="h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500 cursor-pointer"
                        />
                      </td>
                    )}

                    {/* VCODE */}
                    <td className="px-3.5 py-2.5 font-bold font-mono text-xs text-text-primary whitespace-nowrap">
                      {request.vacancyVcode}
                    </td>

                    {/* ACCOUNT */}
                    <td className="px-3.5 py-2.5 whitespace-nowrap">
                      <span className="inline-flex items-center rounded border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs font-semibold text-blue-700">
                        {request.account || "—"}
                      </span>
                    </td>

                    {/* STORE / BRANCH */}
                    <td className="px-3.5 py-2.5 whitespace-nowrap">
                      <div className="flex flex-col">
                        <span className="font-semibold text-text-primary text-xs">
                          {request.storeName || "—"}
                        </span>
                        {request.storeBranch && (
                          <span className="text-[10px] text-text-muted">
                            {request.storeBranch}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* POSITION */}
                    <td className="px-3.5 py-2.5 text-text-secondary whitespace-nowrap">
                      {request.position || "—"}
                    </td>

                    {/* REASON */}
                    <td className="px-3.5 py-2.5 text-text-secondary max-w-xs truncate" title={request.reason}>
                      {request.reason || "—"}
                    </td>

                    {/* REQUESTED BY */}
                    <td className="px-3.5 py-2.5 text-text-secondary whitespace-nowrap">
                      <div className="flex flex-col">
                        <span className="font-medium text-text-primary text-xs">
                          {request.requestedBy || "Unknown"}
                        </span>
                        <span className="font-mono text-[10px] text-text-muted flex items-center gap-1">
                          <Clock className="h-3 w-3 inline text-text-muted" aria-hidden="true" />
                          {formatDate(request.createdAt)}
                        </span>
                      </div>
                    </td>

                    {/* ACTION / REJECTED REASON */}
                    <td className={`px-3.5 py-2.5 ${tab === "rejected" ? "text-left" : "text-right"}`}>
                      {tab === "rejected" ? (
                        <div className="flex flex-col max-w-xs">
                          <span className="text-xs font-medium text-rose-700 bg-rose-50 border border-rose-200 rounded px-2 py-1">
                            {request.reviewerRemarks || "No rejection reason provided"}
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
                            <span>Approve Closure</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex flex-col items-end gap-0.5">
                          <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 text-[11px] font-semibold text-emerald-800">
                            <CheckCircle2 className="h-3 w-3" aria-hidden="true" />
                            Closed
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
                    Approve Vacancy Closure
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Close vacancy slot and reconcile plantilla quota
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

            <div className="mt-4 space-y-3">
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-1.5">
                <div className="flex justify-between">
                  <span className="text-text-muted">VCode:</span>
                  <span className="font-mono font-bold text-text-primary">
                    {selectedApproveRequest.vacancyVcode}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-muted">Store:</span>
                  <span className="font-semibold text-text-primary">
                    {selectedApproveRequest.storeName}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-muted">Reason:</span>
                  <span className="text-text-primary">
                    {selectedApproveRequest.reason}
                  </span>
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-text-primary">
                  Reviewer Remarks (Optional)
                </label>
                <textarea
                  value={approveRemarks}
                  onChange={(e) => setApproveRemarks(e.target.value)}
                  rows={2}
                  placeholder="Notes on closure approval..."
                  className="mt-1 w-full rounded-md border border-border-default bg-white p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
                />
              </div>

              {actionError && (
                <div className="flex items-center gap-2 rounded-md bg-rose-50 p-2.5 text-xs text-rose-700 border border-rose-200">
                  <AlertTriangle className="h-4 w-4 shrink-0" />
                  <span>{actionError}</span>
                </div>
              )}
            </div>

            <div className="mt-5 flex items-center justify-end gap-2 border-t border-border-default pt-4">
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
                {reviewMutation.isPending && (
                  <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                )}
                <span>Confirm Closure</span>
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
                    Reject Vacancy Closure
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Provide reason for rejecting this closure requisition
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

            <div className="mt-4 space-y-3">
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs space-y-1.5">
                <div className="flex justify-between">
                  <span className="text-text-muted">VCode:</span>
                  <span className="font-mono font-bold text-text-primary">
                    {selectedRejectRequest.vacancyVcode}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-muted">Store:</span>
                  <span className="font-semibold text-text-primary">
                    {selectedRejectRequest.storeName}
                  </span>
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-text-primary">
                  Rejection Reason <span className="text-rose-600">*</span>
                </label>
                <textarea
                  value={rejectionRemarks}
                  onChange={(e) => {
                    setRejectionRemarks(e.target.value);
                    if (e.target.value.trim()) setRejectReasonError(false);
                  }}
                  rows={3}
                  placeholder="Explain why this closure request is being rejected..."
                  className={`mt-1 w-full rounded-md border p-2 text-xs text-text-primary placeholder:text-text-muted focus:outline-hidden ${
                    rejectReasonError
                      ? "border-rose-300 focus:border-rose-500"
                      : "border-border-default focus:border-brand-500"
                  }`}
                />
                {rejectReasonError && (
                  <p className="mt-1 text-2xs text-rose-600">
                    Rejection reason is required.
                  </p>
                )}
              </div>

              {actionError && (
                <div className="flex items-center gap-2 rounded-md bg-rose-50 p-2.5 text-xs text-rose-700 border border-rose-200">
                  <AlertTriangle className="h-4 w-4 shrink-0" />
                  <span>{actionError}</span>
                </div>
              )}
            </div>

            <div className="mt-5 flex items-center justify-end gap-2 border-t border-border-default pt-4">
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
                {reviewMutation.isPending && (
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
                    Approve {selectedIds.size} Vacancy Closure{selectedIds.size === 1 ? "" : "s"}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Bulk closure clearance confirmation
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
                selected vacancy closure requests?
              </p>
              <p className="text-text-secondary">
                This action will permanently close and archive each corresponding vacancy and reconcile active plantilla slots per ADR-001.
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
                    Reject {selectedIds.size} Vacancy Closure{selectedIds.size === 1 ? "" : "s"}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Bulk closure rejection justification
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
                  placeholder="State the reason for rejecting these closure requisitions..."
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
