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
import { Modal } from "@/components/shared/Modal";
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
              ? "border border-border-default bg-surface-subtle text-text-primary"
              : "border border-border-danger bg-danger-subtle text-text-danger"
          }`}
        >
          <span>{bulkFeedback.message}</span>
          <button
            type="button"
            onClick={() => setBulkFeedback(null)}
            className="text-text-muted hover:text-text-primary cursor-pointer"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      {/* Multi-selection Bar (Pending only) */}
      {tab === "pending" && requests.length > 0 && (
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2.5 rounded-lg border border-border-default bg-surface-subtle px-3.5 py-2 text-xs">
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
              className="h-4 w-4 rounded border-border-default text-brand-500 focus:ring-brand-500 cursor-pointer"
            />
            <span className="font-medium text-text-primary">
              {selectedIds.size > 0 ? (
                <>
                  <span className="font-bold text-text-brand-bold">{selectedIds.size}</span> of{" "}
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
                className="ml-1 text-2xs text-text-muted hover:text-text-primary underline cursor-pointer"
              >
                Clear
              </button>
            )}
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleOpenBulkReject}
              disabled={isBusy || !canReview}
              className="inline-flex h-7 items-center gap-1 rounded-md border border-border-danger bg-transparent px-2.5 text-xs font-medium text-text-danger hover:bg-danger-subtle disabled:opacity-50 transition cursor-pointer"
            >
              <span>Reject {selectedIds.size > 0 ? `(${selectedIds.size})` : "All"}</span>
            </button>

            <button
              type="button"
              onClick={handleOpenBulkApprove}
              disabled={isBusy || !canReview}
              className="inline-flex h-7 items-center gap-1.5 rounded-md border border-border-brand bg-brand-500 hover:bg-brand-600 px-3 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
            >
              <span>Approve {selectedIds.size > 0 ? `(${selectedIds.size})` : "All"}</span>
            </button>
          </div>
        </div>
      )}

      {/* Table Container */}
      <div className="flex-1 min-h-0 flex flex-col rounded-xl border border-border-default bg-surface overflow-hidden">
        <div className="flex-1 overflow-x-auto">
          <table className="w-full min-w-[980px] border-collapse text-left text-sm">
            <thead className="sticky top-0 z-10 bg-surface-subtle text-xs font-semibold text-text-secondary border-b border-border-default">
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
                      className="h-4 w-4 rounded border-border-default text-brand-500 focus:ring-brand-500 cursor-pointer"
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
            <tbody className="divide-y divide-border-default">
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
                    className={`transition-colors hover:bg-surface-hover ${
                      selectedIds.has(request.requestId) ? "bg-brand-subtle" : ""
                    }`}
                  >
                    {tab === "pending" && (
                      <td className="w-10 px-4 py-2.5 text-left align-middle">
                        <input
                          type="checkbox"
                          checked={selectedIds.has(request.requestId)}
                          onChange={() => toggleSelectOne(request.requestId)}
                          aria-label={`Select reliever request ${request.requestId}`}
                          className="h-4 w-4 rounded border-border-default text-brand-500 focus:ring-brand-500 cursor-pointer"
                        />
                      </td>
                    )}
                    {/* PRIORITY */}
                    <td className="px-4 py-2.5 whitespace-nowrap align-middle">
                      <span
                        className={`inline-flex items-center rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-primary ${
                          priorityLower === "urgent" ? "font-bold" : ""
                        }`}
                      >
                        {request.priority || "Normal"}
                      </span>
                    </td>

                    {/* EMPLOYEE */}
                    <td className="px-4 py-2.5 align-middle">
                      <div className="flex flex-col">
                        <span className="font-medium text-text-primary text-sm">
                          {request.employeeName || "Unassigned"}
                        </span>
                        {request.employeeNumber && (
                          <span className="font-mono text-xs text-text-muted">
                            {request.employeeNumber}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* POOL TYPE */}
                    <td className="px-4 py-2.5 whitespace-nowrap align-middle">
                      <span className="inline-flex items-center rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-primary">
                        {request.poolType || "Reliever"}
                      </span>
                    </td>

                    {/* TARGET ACCOUNT */}
                    <td className="px-4 py-2.5 whitespace-nowrap align-middle">
                      <span className="inline-flex items-center rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-primary">
                        {request.requestedAccount || "—"}
                      </span>
                    </td>

                    {/* TARGET STORE / GROUP */}
                    <td className="px-4 py-2.5 whitespace-nowrap align-middle">
                      <div className="flex flex-col">
                        <span className="text-sm text-text-primary">
                          {request.requestedStore || "—"}
                        </span>
                        {request.requestedGroup && (
                          <span className="text-xs text-text-muted">
                            {request.requestedGroup}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* DATES */}
                    <td className="px-4 py-2.5 whitespace-nowrap font-mono text-sm text-text-primary align-middle">
                      {request.startDate ? (
                        <span className="inline-flex items-center gap-1">
                          <Calendar className="h-3.5 w-3.5 text-text-muted inline" />
                          {formatDate(request.startDate)} → {formatDate(request.endDate)}
                        </span>
                      ) : (
                        "—"
                      )}
                    </td>

                    {/* REASON */}
                    <td className="px-4 py-2.5 max-w-xs truncate text-sm text-text-secondary align-middle" title={request.reason || ""}>
                      {request.reason || "—"}
                    </td>

                    {/* ACTION / REJECTED REASON */}
                    <td
                      className={`px-4 py-2.5 align-middle ${
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
                            className="inline-flex h-7 items-center justify-center rounded-lg border border-border-danger bg-transparent px-2.5 text-xs font-medium text-text-danger hover:bg-danger-subtle disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Reject</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => handleOpenApprove(request)}
                            disabled={isBusy || !canReview}
                            title={!canReview ? "Requires Data Team / Admin role" : undefined}
                            className="inline-flex h-7 items-center justify-center rounded-lg border border-border-brand bg-brand-500 hover:bg-brand-600 px-3 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Approve Reliever</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex flex-col items-end gap-0.5">
                          <span className="inline-flex items-center gap-1.5 text-xs text-text-primary font-medium">
                            <CheckCircle2 className="h-3.5 w-3.5 text-text-muted" />
                            Assigned
                          </span>
                          {request.reviewedAt && (
                            <span className="text-xs text-text-muted font-mono">
                              {formatDate(request.reviewedAt)}
                            </span>
                          )}
                        </div>
                      ) : (
                        <div className="flex flex-col items-start gap-0.5 max-w-xs">
                          <span className="text-xs font-normal text-text-danger border border-border-danger bg-danger-subtle rounded-lg px-2.5 py-1">
                            {request.rejectionReason || "No reason specified"}
                          </span>
                          {request.reviewedAt && (
                            <span className="text-xs text-text-muted mt-1 font-mono">
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
        <Modal
          isOpen={Boolean(selectedApproveRequest)}
          onClose={() => setSelectedApproveRequest(null)}
          title="Approve Reliever Coverage"
          subtitle="Deploy reliever employee to target account/store"
          icon={CheckCircle2}
          isSubmitting={approveMutation.isPending}
          disableBackdropClick={approveMutation.isPending}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <div className="rounded-lg bg-surface-subtle p-3 text-xs space-y-1.5 border border-border-default">
              <div className="flex justify-between">
                <span className="text-text-secondary">Employee:</span>
                <span className="font-semibold text-text-primary">
                  {selectedApproveRequest.employeeName}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Target Store:</span>
                <span className="font-medium text-text-primary">
                  {selectedApproveRequest.requestedStore || "—"} ({selectedApproveRequest.requestedAccount})
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Coverage Period:</span>
                <span className="font-mono text-text-primary">
                  {formatDate(selectedApproveRequest.startDate)} → {formatDate(selectedApproveRequest.endDate)}
                </span>
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Approval Notes (Optional)
              </label>
              <textarea
                value={approveNotes}
                onChange={(e) => setApproveNotes(e.target.value)}
                rows={2}
                placeholder="Add deployment instructions or shift notes..."
                className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-border-brand focus:outline-hidden"
              />
            </div>

            {actionError && (
              <div className="flex items-start gap-2 rounded-md bg-danger-subtle p-2.5 text-xs text-text-danger border border-border-danger">
                <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setSelectedApproveRequest(null)}
                disabled={isBusy}
                className="h-8 rounded-md border border-border-default bg-surface px-3 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={isBusy}
                className="inline-flex h-8 items-center gap-1.5 rounded-md bg-brand-500 hover:bg-brand-600 px-3.5 text-xs font-semibold text-white shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {approveMutation.isPending && (
                  <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                )}
                <span>Confirm Approval</span>
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* Reject Modal */}
      {selectedRejectRequest && (
        <Modal
          isOpen={Boolean(selectedRejectRequest)}
          onClose={() => setSelectedRejectRequest(null)}
          title="Reject Reliever Coverage"
          subtitle="Provide reason for rejecting reliever deployment"
          icon={XCircle}
          isSubmitting={rejectMutation.isPending}
          disableBackdropClick={rejectMutation.isPending}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <div className="space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Rejection Reason <span className="text-text-danger">*</span>
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
                className={`w-full rounded-md border p-2 text-xs text-text-primary bg-surface placeholder:text-text-muted focus:outline-hidden ${
                  rejectReasonError
                    ? "border-border-danger focus:border-border-danger"
                    : "border-border-default focus:border-border-brand"
                }`}
              />
              {rejectReasonError && (
                <p className="text-xs text-text-danger font-medium">
                  Rejection reason is required.
                </p>
              )}
            </div>

            {actionError && (
              <div className="flex items-start gap-2 rounded-md bg-danger-subtle p-2.5 text-xs text-text-danger border border-border-danger">
                <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
              <button
                type="button"
                onClick={() => setSelectedRejectRequest(null)}
                disabled={isBusy}
                className="h-8 rounded-md border border-border-default bg-surface px-3 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={isBusy}
                className="inline-flex h-8 items-center gap-1.5 rounded-md bg-danger-button hover:bg-danger-button-hover px-3.5 text-xs font-semibold text-danger-button-text shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {rejectMutation.isPending && (
                  <RefreshCw className="h-3.5 w-3.5 animate-spin" />
                )}
                <span>Confirm Rejection</span>
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* Bulk Approve Confirmation Modal */}
      {isBulkApproveOpen && (
        <Modal
          isOpen={isBulkApproveOpen}
          onClose={() => setIsBulkApproveOpen(false)}
          title={`Approve ${selectedIds.size} Reliever Request${selectedIds.size === 1 ? "" : "s"}`}
          subtitle="Confirm bulk deployment approval"
          icon={CheckCheck}
          isSubmitting={isBulkProcessing}
          disableBackdropClick={isBulkProcessing}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <p className="text-xs text-text-secondary leading-relaxed">
              You are about to approve{" "}
              <span className="font-semibold text-text-primary">
                {selectedIds.size} reliever coverage request{selectedIds.size === 1 ? "" : "s"}
              </span>
              . The approved relievers will be officially endorsed and deployed for the requested periods.
            </p>

            <div className="flex justify-end gap-2 pt-2 border-t border-border-default">
              <button
                type="button"
                onClick={() => setIsBulkApproveOpen(false)}
                disabled={isBulkProcessing}
                className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkApprove}
                disabled={isBulkProcessing}
                className="inline-flex items-center gap-1.5 rounded-md bg-brand-500 hover:bg-brand-600 px-4 py-1.5 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
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
        </Modal>
      )}

      {/* Bulk Reject Confirmation Modal */}
      {isBulkRejectOpen && (
        <Modal
          isOpen={isBulkRejectOpen}
          onClose={() => setIsBulkRejectOpen(false)}
          title={`Reject ${selectedIds.size} Reliever Request${selectedIds.size === 1 ? "" : "s"}`}
          subtitle="Bulk reliever rejection justification"
          icon={XCircle}
          isSubmitting={isBulkProcessing}
          disableBackdropClick={isBulkProcessing}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <div>
              <label className="block text-xs font-medium text-text-primary mb-1">
                Rejection Reason <span className="text-text-danger">*</span>
              </label>
              <textarea
                rows={3}
                value={bulkRejectionReason}
                onChange={(e) => {
                  setBulkRejectionReason(e.target.value);
                  if (bulkRejectReasonError && e.target.value.trim().length >= 3) {
                    setBulkRejectReasonError(false);
                  }
                }}
                placeholder="State the reason for rejecting these reliever requests..."
                className={`mt-1 w-full rounded-md border p-2.5 text-xs text-text-primary bg-surface placeholder:text-text-muted focus:outline-hidden ${
                  bulkRejectReasonError
                    ? "border-border-danger focus:border-border-danger"
                    : "border-border-default focus:border-border-brand"
                }`}
              />
              {bulkRejectReasonError && (
                <p className="mt-1 text-2xs text-text-danger">
                  Please provide a rejection reason (minimum 3 characters).
                </p>
              )}
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-border-default">
              <button
                type="button"
                onClick={() => setIsBulkRejectOpen(false)}
                disabled={isBulkProcessing}
                className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkReject}
                disabled={isBulkProcessing}
                className="inline-flex items-center gap-1.5 rounded-md bg-danger-button hover:bg-danger-button-hover px-4 py-1.5 text-xs font-medium text-danger-button-text shadow-2xs disabled:opacity-50 transition cursor-pointer"
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
        </Modal>
      )}
    </div>
  );
}
