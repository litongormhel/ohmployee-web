"use client";

import { useMemo, useState } from "react";
import {
  AlertTriangle,
  Calendar,
  CheckCheck,
  CheckCircle2,
  RefreshCw,
  X,
  XCircle,
} from "lucide-react";
import { TablePagination } from "@/components/shared/TablePagination";
import {
  useApproveRelieverCoverage,
  useRejectRelieverCoverage,
  type RelieverEndorsementItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";
import { useCurrentUser } from "@/lib/auth";

interface RelieverDataTableProps {
  requests: RelieverEndorsementItem[];
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
    });
  } catch {
    return dateStr;
  }
}

export function RelieverDataTable({
  requests,
  tab,
  page,
  pageSize,
  totalCount,
  onPageChange,
  onPageSizeChange,
}: RelieverDataTableProps) {
  const currentPage = page ?? 1;
  const currentPageSize = pageSize ?? 10;
  const count = totalCount ?? requests.length;

  const paginatedRequests = useMemo(() => {
    const start = (currentPage - 1) * currentPageSize;
    return requests.slice(start, start + currentPageSize);
  }, [requests, currentPage, currentPageSize]);

  const currentUser = useCurrentUser();
  const roleKey = currentUser?.roleKey?.toLowerCase() || "";
  const roleName = currentUser?.roleName?.toLowerCase() || "";
  const canReview =
    roleKey === "super_admin" ||
    roleKey === "head_admin" ||
    roleKey === "data_team" ||
    roleName.includes("super admin") ||
    roleName.includes("head admin") ||
    roleName.includes("data team");

  // Multi-selection states
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

  // Modal states
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<RelieverEndorsementItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<RelieverEndorsementItem | null>(null);

  const [approveNotes, setApproveNotes] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
  const [rejectReasonError, setRejectReasonError] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const approveMutation = useApproveRelieverCoverage();
  const rejectMutation = useRejectRelieverCoverage();

  const isAllSelected =
    paginatedRequests.length > 0 &&
    paginatedRequests.every((r) => selectedIds.has(r.requestId));

  const toggleSelectAll = () => {
    if (isAllSelected) {
      setSelectedIds((prev) => {
        const next = new Set(prev);
        paginatedRequests.forEach((r) => next.delete(r.requestId));
        return next;
      });
    } else {
      setSelectedIds((prev) => {
        const next = new Set(prev);
        paginatedRequests.forEach((r) => next.add(r.requestId));
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

  const handleOpenApprove = (req: RelieverEndorsementItem) => {
    setActionError(null);
    setApproveNotes("");
    setSelectedApproveRequest(req);
  };

  const handleOpenReject = (req: RelieverEndorsementItem) => {
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
        requestId: selectedApproveRequest.requestId,
        notes: approveNotes.trim() || undefined,
      });
      setSelectedApproveRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve reliever coverage."
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
        requestId: selectedRejectRequest.requestId,
        reason: rejectionReason.trim(),
      });
      setSelectedRejectRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject reliever coverage."
      );
    }
  };

  // Bulk actions handlers
  const handleOpenBulkApprove = () => {
    if (selectedIds.size === 0) {
      setSelectedIds(new Set(requests.map((r) => r.requestId)));
    }
    setIsBulkApproveOpen(true);
  };

  const handleOpenBulkReject = () => {
    if (selectedIds.size === 0) {
      setSelectedIds(new Set(requests.map((r) => r.requestId)));
    }
    setBulkRejectionReason("");
    setBulkRejectReasonError(false);
    setIsBulkRejectOpen(true);
  };

  const handleConfirmBulkApprove = async () => {
    setIsBulkProcessing(true);
    setBulkFeedback(null);
    const targetRequests = requests.filter((r) => selectedIds.has(r.requestId));
    let successCount = 0;
    const errors: string[] = [];

    for (const req of targetRequests) {
      try {
        await approveMutation.mutateAsync({
          requestId: req.requestId,
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.employeeName || req.requestId}`);
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
        message: `Successfully approved all ${successCount} selected reliever requests.`,
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
    const targetRequests = requests.filter((r) => selectedIds.has(r.requestId));
    let successCount = 0;
    const errors: string[] = [];

    for (const req of targetRequests) {
      try {
        await rejectMutation.mutateAsync({
          requestId: req.requestId,
          reason: bulkRejectionReason.trim(),
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.employeeName || req.requestId}`);
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
        message: `Successfully rejected ${successCount} selected reliever requests.`,
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
          <table className="w-full min-w-[980px] border-collapse text-left text-xs">
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
                  Priority
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Employee
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Pool type
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Target account
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Target store / group
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Dates
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Reason
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
                  reqStatus === "for review";
                const isApproved =
                  reqStatus === "approved" || reqStatus === "completed";

                const priorityLower = (request.priority || "Normal").toLowerCase();

                return (
                  <tr
                    key={request.requestId}
                    className={`transition-colors hover:bg-[var(--soft)] ${
                      selectedIds.has(request.requestId) ? "bg-[var(--pillbg)]/40" : ""
                    }`}
                  >
                    {tab === "pending" && (
                      <td className="w-10 px-4 py-3.5 text-left align-middle">
                        <input
                          type="checkbox"
                          checked={selectedIds.has(request.requestId)}
                          onChange={() => toggleSelectOne(request.requestId)}
                          aria-label={`Select reliever request ${request.requestId}`}
                          className="h-4 w-4 rounded border-[var(--line)] text-[var(--accent)] focus:ring-[var(--accent)] cursor-pointer"
                        />
                      </td>
                    )}
                    {/* PRIORITY */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      <span
                        className={`inline-flex items-center rounded-[6px] border px-2 py-0.5 text-xs font-medium ${
                          priorityLower === "urgent"
                            ? "border-rose-200/50 bg-rose-50/60 text-rose-800 dark:bg-rose-950/30 dark:text-rose-300"
                            : priorityLower === "high"
                            ? "border-amber-200/50 bg-amber-50/60 text-amber-800 dark:bg-amber-950/30 dark:text-amber-300"
                            : "border-[var(--line)] bg-[var(--soft)] text-[var(--muted)]"
                        }`}
                      >
                        {request.priority || "Normal"}
                      </span>
                    </td>

                    {/* EMPLOYEE */}
                    <td className="px-4 py-3.5 align-middle">
                      <div className="flex flex-col">
                        <span className="font-medium text-[var(--text)] text-xs">
                          {request.employeeName || "Unassigned"}
                        </span>
                        {request.employeeNumber && (
                          <span className="font-mono text-[10.5px] text-[var(--muted)]">
                            {request.employeeNumber}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* POOL TYPE */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      <span className="inline-flex items-center rounded-[6px] border border-[var(--status-accent-border)] bg-[var(--pillbg)] px-2 py-0.5 text-xs font-medium text-[var(--accent)]">
                        {request.poolType || "Reliever"}
                      </span>
                    </td>

                    {/* TARGET ACCOUNT */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      <span className="inline-flex items-center rounded-[6px] border border-[var(--status-accent-border)] bg-[var(--pillbg)] px-2 py-0.5 text-xs font-medium text-[var(--accent)]">
                        {request.requestedAccount || "—"}
                      </span>
                    </td>

                    {/* TARGET STORE / GROUP */}
                    <td className="px-4 py-3.5 whitespace-nowrap align-middle">
                      <div className="flex flex-col">
                        <span className="text-xs text-[var(--text)]">
                          {request.requestedStore || "—"}
                        </span>
                        {request.requestedGroup && (
                          <span className="text-[12.5px] text-[var(--muted)]">
                            {request.requestedGroup}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* DATES */}
                    <td className="px-4 py-3.5 whitespace-nowrap font-mono text-xs text-[var(--text)] align-middle">
                      {request.startDate ? (
                        <span className="inline-flex items-center gap-1">
                          <Calendar className="h-3 w-3 text-[var(--muted)] inline" />
                          {formatDate(request.startDate)} → {formatDate(request.endDate)}
                        </span>
                      ) : (
                        "—"
                      )}
                    </td>

                    {/* REASON */}
                    <td className="px-4 py-3.5 max-w-xs truncate text-xs text-[var(--muted)] align-middle" title={request.reason || ""}>
                      {request.reason || "—"}
                    </td>

                    {/* ACTION / REJECTED REASON */}
                    <td
                      className={`px-4 py-3.5 align-middle ${
                        tab === "rejected" ? "text-left" : "text-right whitespace-nowrap"
                      }`}
                    >
                      {isPending ? (
                        <div className="inline-flex items-center justify-end gap-2">
                          <button
                            type="button"
                            onClick={() => handleOpenReject(request)}
                            disabled={isBusy || !canReview}
                            title={!canReview ? "Requires Data Team / Admin role" : undefined}
                            className="inline-flex h-8 items-center justify-center rounded-lg border border-[var(--bad)]/40 bg-transparent px-3 text-xs font-normal text-[var(--bad)] hover:bg-[var(--bad)]/10 disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Reject</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => handleOpenApprove(request)}
                            disabled={isBusy || !canReview}
                            title={!canReview ? "Requires Data Team / Admin role" : undefined}
                            className="inline-flex h-8 items-center justify-center rounded-lg border border-[var(--ok)] bg-[var(--ok)] px-3.5 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Approve Reliever</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex flex-col items-end gap-0.5">
                          <span className="inline-flex items-center gap-1.5 text-xs text-[var(--ok)] font-normal">
                            <span className="w-1.5 h-1.5 rounded-full bg-[var(--ok)]" />
                            Assigned
                          </span>
                          {request.reviewedAt && (
                            <span className="text-[12.5px] text-[var(--muted)]">
                              {formatDate(request.reviewedAt)}
                            </span>
                          )}
                        </div>
                      ) : (
                        <div className="flex flex-col items-start gap-0.5 max-w-xs">
                          <span className="text-xs font-normal text-[var(--bad)] border border-[var(--bad)]/30 rounded-lg px-2.5 py-1">
                            {request.rejectionReason || "No reason specified"}
                          </span>
                          {request.reviewedAt && (
                            <span className="text-[12.5px] text-[var(--muted)] mt-1">
                              {formatDate(request.reviewedAt)}
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
                    Approve Reliever Coverage
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Deploy reliever employee to target account/store
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
                <span className="text-text-muted">Employee:</span>
                <span className="font-semibold text-text-primary">
                  {selectedApproveRequest.employeeName}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Target Store:</span>
                <span className="font-medium text-text-primary">
                  {selectedApproveRequest.requestedStore || "—"} ({selectedApproveRequest.requestedAccount})
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Coverage Period:</span>
                <span className="font-mono text-text-secondary">
                  {formatDate(selectedApproveRequest.startDate)} → {formatDate(selectedApproveRequest.endDate)}
                </span>
              </div>
            </div>

            <div className="mt-4 space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Approval Notes (Optional)
              </label>
              <textarea
                value={approveNotes}
                onChange={(e) => setApproveNotes(e.target.value)}
                rows={2}
                placeholder="Add deployment instructions or shift notes..."
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
                    Reject Reliever Coverage
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Provide reason for rejecting reliever deployment
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
                placeholder="Explain why this reliever endorsement is rejected..."
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

      {/* Bulk Approve Confirmation Modal */}
      {isBulkApproveOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md rounded-xl border border-border-default bg-surface-base p-6 shadow-xl animate-drawer-in">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-2">
                <div className="flex h-9 w-9 items-center justify-center rounded-full bg-emerald-100 text-emerald-700">
                  <CheckCircle2 className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-semibold text-text-primary">
                    Approve {selectedIds.size} Reliever Request{selectedIds.size === 1 ? "" : "s"}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Confirm bulk deployment approval
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

            <div className="mt-4 space-y-3">
              <p className="text-xs text-text-secondary leading-relaxed">
                You are about to approve{" "}
                <span className="font-semibold text-text-primary">
                  {selectedIds.size} reliever coverage request{selectedIds.size === 1 ? "" : "s"}
                </span>
                . The approved relievers will be officially endorsed and deployed for the requested periods.
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
                    Reject {selectedIds.size} Reliever Request{selectedIds.size === 1 ? "" : "s"}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Bulk reliever rejection justification
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
                  placeholder="State the reason for rejecting these reliever requests..."
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
