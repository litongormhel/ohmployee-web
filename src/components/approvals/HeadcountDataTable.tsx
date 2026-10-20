"use client";

import { useMemo, useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  CheckCheck,
  CheckCircle2,
  Layers,
  RefreshCw,
  Sparkles,
  TrendingDown,
  TrendingUp,
  X,
  XCircle,
} from "lucide-react";
import { TablePagination } from "@/components/shared/TablePagination";
import {
  useApproveHeadcountRequest,
  useRejectHeadcountRequest,
  useGenerateVcodeFromHeadcountRequest,
  type HeadcountRequestItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";

interface HeadcountDataTableProps {
  requests: HeadcountRequestItem[];
  tab: ApprovalStatusTab;
  page?: number;
  pageSize?: number;
  totalCount?: number;
  onPageChange?: (newPage: number) => void;
  onPageSizeChange?: (newPageSize: number) => void;
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

export function HeadcountDataTable({
  requests,
  tab,
  page,
  pageSize,
  totalCount,
  onPageChange,
  onPageSizeChange,
}: HeadcountDataTableProps) {
  const currentPage = page ?? 1;
  const currentPageSize = pageSize ?? 10;
  const count = totalCount ?? requests.length;

  const paginatedRequests = useMemo(() => {
    const start = (currentPage - 1) * currentPageSize;
    return requests.slice(start, start + currentPageSize);
  }, [requests, currentPage, currentPageSize]);

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
  const generateVcodeMutation = useGenerateVcodeFromHeadcountRequest();
  const [generatingId, setGeneratingId] = useState<string | null>(null);
  const [generateError, setGenerateError] = useState<{ id: string; message: string } | null>(null);

  const handleGenerateVcode = async (req: HeadcountRequestItem) => {
    setGeneratingId(req.id);
    setGenerateError(null);
    try {
      await generateVcodeMutation.mutateAsync(req.id);
      setBulkFeedback({
        type: "success",
        message: `Successfully generated VCode for ${req.storeName || req.positionName || "request"}.`,
      });
    } catch (err: unknown) {
      const errMsg = err instanceof Error ? err.message : "Failed to generate VCode.";
      setGenerateError({ id: req.id, message: errMsg });
      setBulkFeedback({
        type: "error",
        message: `Failed to generate VCode for ${req.storeName || "request"}: ${errMsg}`,
      });
    } finally {
      setGeneratingId(null);
    }
  };

  const isAllSelected =
    paginatedRequests.length > 0 && paginatedRequests.every((r) => selectedIds.has(r.id));

  const toggleSelectAll = () => {
    if (isAllSelected) {
      setSelectedIds((prev) => {
        const next = new Set(prev);
        paginatedRequests.forEach((r) => next.delete(r.id));
        return next;
      });
    } else {
      setSelectedIds((prev) => {
        const next = new Set(prev);
        paginatedRequests.forEach((r) => next.add(r.id));
        return next;
      });
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

  const isBusy =
    approveMutation.isPending ||
    rejectMutation.isPending ||
    generateVcodeMutation.isPending ||
    isBulkProcessing;

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
              className="inline-flex h-7 items-center gap-1 rounded-md border border-[var(--bad)]/40 bg-transparent px-2.5 text-xs font-medium text-[var(--bad)] hover:bg-[var(--bad)]/10 disabled:opacity-50 transition cursor-pointer"
            >
              <span>Reject {selectedIds.size > 0 ? `(${selectedIds.size})` : "All"}</span>
            </button>

            <button
              type="button"
              onClick={handleOpenBulkApprove}
              disabled={isBusy}
              className="inline-flex h-7 items-center gap-1.5 rounded-md border border-[var(--ok)] bg-[var(--ok)] px-3 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 transition cursor-pointer"
            >
              <span>Approve {selectedIds.size > 0 ? `(${selectedIds.size})` : "All"}</span>
            </button>
          </div>
        </div>
      )}

      {/* Table Container */}
      <div className="flex-1 min-h-0 flex flex-col rounded-xl border border-[var(--line)] bg-[var(--bg)] overflow-hidden">
        <div className="flex-1 overflow-x-auto">
          <table className="w-full min-w-[960px] border-collapse text-left text-xs">
            <thead className="sticky top-0 z-10 bg-[var(--bg)] text-[12.5px] font-medium text-[var(--muted)] border-b border-[var(--line)]">
              <tr>
                {tab === "pending" && (
                  <th scope="col" className="w-10 px-4 py-2.5 text-left">
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
                      className="h-4 w-4 rounded border-[var(--line)] text-[var(--accent)] focus:ring-[var(--accent)] cursor-pointer"
                    />
                  </th>
                )}
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Type
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Group
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Account
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Store
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Position / VCode
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Proposed change
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Requested by
                </th>
                <th
                  scope="col"
                  className={`px-4 py-2.5 font-medium ${tab === "rejected" ? "text-left" : "text-right"}`}
                >
                  {tab === "rejected" ? "Rejected reason" : "Action"}
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--line)]">
              {paginatedRequests.map((request) => {
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
                    className={`transition-colors hover:bg-[var(--soft)] ${
                      isRowSelected ? "bg-[var(--pillbg)]/40" : ""
                    }`}
                  >
                    {tab === "pending" && (
                      <td className="w-10 px-4 py-3.5 text-left align-middle">
                        <input
                          type="checkbox"
                          checked={isRowSelected}
                          onChange={() => toggleSelectOne(request.id)}
                          aria-label={`Select request for ${request.storeName}`}
                          className="h-4 w-4 rounded border-[var(--line)] text-[var(--accent)] focus:ring-[var(--accent)] cursor-pointer"
                        />
                      </td>
                    )}

                    {/* TYPE */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      {request.isQuotaAmendment ? (
                        <span className="inline-flex items-center rounded-[6px] border border-purple-200/50 bg-purple-50/50 dark:bg-purple-950/20 px-2 py-0.5 text-xs font-medium text-purple-700 dark:text-purple-400">
                          Quota Amendment
                        </span>
                      ) : (
                        <span className="inline-flex items-center rounded-[6px] border border-[var(--status-accent-border)] bg-[var(--pillbg)] px-2 py-0.5 text-xs font-medium text-[var(--accent)]">
                          {request.requestType}
                        </span>
                      )}
                    </td>

                    {/* GROUP */}
                    <td className="px-4 py-3.5 text-xs text-[var(--text)] whitespace-nowrap align-middle">
                      {request.groupName ? (
                        <span className="inline-flex items-center gap-1 font-medium text-[var(--text)]">
                          <Layers className="h-3 w-3 text-[var(--muted)]" aria-hidden="true" />
                          {request.groupName}
                        </span>
                      ) : (
                        <span className="text-[var(--muted)]">—</span>
                      )}
                    </td>

                    {/* ACCOUNT */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      <span className="inline-flex items-center rounded-[6px] border border-[var(--status-accent-border)] bg-[var(--pillbg)] px-2 py-0.5 text-xs font-medium text-[var(--accent)]">
                        {request.accountName || "—"}
                      </span>
                    </td>

                    {/* STORE */}
                    <td className="px-4 py-3.5 font-medium text-[var(--text)] text-xs whitespace-nowrap align-middle">
                      {request.storeName || "—"}
                    </td>

                    {/* POSITION / VCODE */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      <div className="flex flex-col">
                        <span className="text-xs text-[var(--text)]">
                          {request.positionName || "—"}
                        </span>
                        {(request.createdVcode || (request.createdVcodes && request.createdVcodes.length > 0 ? request.createdVcodes.join(", ") : null) || request.targetVcode) && (
                          <span className="font-mono text-[10.5px] text-[var(--muted)]">
                            {request.createdVcode || (request.createdVcodes && request.createdVcodes.length > 0 ? request.createdVcodes.join(", ") : null) || request.targetVcode}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* PROPOSED CHANGE */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      {request.isQuotaAmendment ? (
                        <div className="inline-flex items-center gap-1.5 font-mono text-xs">
                          <span className="text-[var(--muted)]">
                            {request.previousTarget ?? 0}
                          </span>
                          <ArrowRight className="h-3 w-3 text-[var(--muted)]" />
                          <span className="font-bold text-[var(--text)]">
                            {request.proposedTarget ?? 0}
                          </span>
                          {request.delta !== null && (
                            <span
                              className={`inline-flex items-center gap-0.5 rounded px-1.5 py-0.2 text-[10px] font-bold ${
                                request.isExpansion
                                  ? "bg-emerald-100/70 text-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-300"
                                  : request.isReduction
                                    ? "bg-rose-100/70 text-rose-800 dark:bg-rose-950/40 dark:text-rose-300"
                                    : "bg-[var(--soft)] text-[var(--muted)]"
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
                        <span className="font-mono text-xs font-semibold text-[var(--text)]">
                          +{request.headcountNeeded} needed
                        </span>
                      )}
                    </td>

                    {/* REQUESTED BY */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      <div className="flex flex-col">
                        <span className="text-xs text-[var(--text)]">
                          {request.requestedByName || "Unknown"}
                        </span>
                        <span className="text-[12.5px] text-[var(--muted)]">
                          {formatDate(request.requestedAt)}
                        </span>
                      </div>
                    </td>

                    {/* ACTION / REJECTED REASON */}
                    <td className={`px-4 py-3.5 align-middle ${tab === "rejected" ? "text-left" : "text-right"}`}>
                      {tab === "rejected" ? (
                        <div className="flex flex-col max-w-xs">
                          <span className="text-xs font-normal text-[var(--bad)] border border-[var(--bad)]/30 rounded-lg px-2.5 py-1">
                            {request.reviewerRemarks || "No rejection remarks recorded"}
                          </span>
                          {request.reviewedAt && (
                            <span className="text-[12.5px] text-[var(--muted)] mt-1">
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
                            className="inline-flex h-8 items-center justify-center rounded-lg border border-[var(--bad)]/40 bg-transparent px-3 text-xs font-normal text-[var(--bad)] hover:bg-[var(--bad)]/10 disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Reject</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => handleOpenApprove(request)}
                            disabled={isBusy}
                            className="inline-flex h-8 items-center justify-center rounded-lg border border-[var(--ok)] bg-[var(--ok)] px-3.5 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Approve</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        (() => {
                          const hasCreatedVcode = Boolean(
                            request.createdVcode ||
                              (request.createdVcodes && request.createdVcodes.length > 0)
                          );
                          const isPendingVcode =
                            reqStatus === "approved_pending_vcode" ||
                            (!request.isQuotaAmendment && !hasCreatedVcode);

                          if (isPendingVcode) {
                            return (
                              <div className="inline-flex flex-col items-end gap-1">
                                <button
                                  type="button"
                                  onClick={() => handleGenerateVcode(request)}
                                  disabled={isBusy || generatingId === request.id}
                                  className="inline-flex h-7 items-center justify-center gap-1.5 rounded-md border border-amber-300 bg-amber-50 dark:bg-amber-950/30 dark:border-amber-700 px-2.5 text-xs font-medium text-amber-800 dark:text-amber-300 hover:bg-amber-100 dark:hover:bg-amber-900/40 disabled:opacity-50 transition cursor-pointer"
                                  title="Mint VCode and create plantilla slot"
                                >
                                  {generatingId === request.id ? (
                                    <RefreshCw className="h-3 w-3 animate-spin" />
                                  ) : (
                                    <Sparkles className="h-3 w-3" />
                                  )}
                                  <span>Generate VCode</span>
                                </button>
                                {generateError?.id === request.id && (
                                  <span
                                    className="text-[10px] text-rose-600 max-w-[140px] truncate"
                                    title={generateError.message}
                                  >
                                    {generateError.message}
                                  </span>
                                )}
                              </div>
                            );
                          }

                          return (
                            <div className="inline-flex flex-col items-end gap-0.5">
                              <span className="inline-flex items-center gap-1.5 text-xs text-[var(--ok)] font-normal">
                                <span className="w-1.5 h-1.5 rounded-full bg-[var(--ok)]" />
                                Approved
                              </span>
                              {request.reviewedAt && (
                                <span className="text-[12.5px] text-[var(--muted)]">
                                  {formatDate(request.reviewedAt)}
                                </span>
                              )}
                            </div>
                          );
                        })()
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-[var(--soft)] px-2.5 py-0.5 text-[11px] font-medium text-[var(--text)]">
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

        {onPageChange && (
          <TablePagination
            page={currentPage}
            pageSize={currentPageSize}
            totalCount={count}
            pageSizeOptions={[10, 25, 50]}
            onPageChange={onPageChange}
            onPageSizeChange={onPageSizeChange}
          />
        )}
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
