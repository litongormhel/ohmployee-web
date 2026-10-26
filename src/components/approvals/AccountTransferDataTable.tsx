"use client";

import { useMemo, useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  CheckCheck,
  CheckCircle2,
  Layers,
  RefreshCw,
  X,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { TablePagination } from "@/components/shared/TablePagination";
import {
  useApproveAccountGroupTransfer,
  useRejectAccountGroupTransfer,
  type AccountGroupTransferItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";
import { useCurrentUser } from "@/lib/auth";

interface AccountTransferDataTableProps {
  requests: AccountGroupTransferItem[];
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

export function AccountTransferDataTable({
  requests,
  tab,
  page,
  pageSize,
  totalCount,
  onPageChange,
  onPageSizeChange,
}: AccountTransferDataTableProps) {
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
    roleName.includes("super admin") ||
    roleName.includes("head admin");

  // Modal states for single action
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<AccountGroupTransferItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<AccountGroupTransferItem | null>(null);

  const [rejectionReason, setRejectionReason] = useState("");
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

  const approveMutation = useApproveAccountGroupTransfer();
  const rejectMutation = useRejectAccountGroupTransfer();

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

  const handleOpenApprove = (req: AccountGroupTransferItem) => {
    setActionError(null);
    setSelectedApproveRequest(req);
  };

  const handleOpenReject = (req: AccountGroupTransferItem) => {
    setActionError(null);
    setRejectionReason("");
    setRejectReasonError(false);
    setSelectedRejectRequest(req);
  };

  const handleConfirmApprove = async () => {
    if (!selectedApproveRequest) return;
    setActionError(null);
    try {
      await approveMutation.mutateAsync(selectedApproveRequest.id);
      setSelectedApproveRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to approve account group transfer."
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
          : "Failed to reject account group transfer."
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
        await approveMutation.mutateAsync(req.id);
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.requestNumber}`);
      }
    }

    setIsBulkProcessing(false);
    setIsBulkApproveOpen(false);
    setSelectedIds(new Set());

    if (errors.length > 0) {
      setBulkFeedback({
        type: "error",
        message: `Approved ${successCount} transfers, but ${errors.length} failed: ${errors[0]}`,
      });
    } else {
      setBulkFeedback({
        type: "success",
        message: `Successfully approved all ${successCount} selected account group transfers.`,
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
          reason: bulkRejectionReason.trim(),
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.requestNumber}`);
      }
    }

    setIsBulkProcessing(false);
    setIsBulkRejectOpen(false);
    setSelectedIds(new Set());

    if (errors.length > 0) {
      setBulkFeedback({
        type: "error",
        message: `Rejected ${successCount} transfers, but ${errors.length} failed: ${errors[0]}`,
      });
    } else {
      setBulkFeedback({
        type: "success",
        message: `Successfully rejected ${successCount} selected account group transfers.`,
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
          <table className="w-full min-w-[960px] border-collapse text-left text-sm">
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
                  Request #
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Account
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Source group (From)
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Target group (To)
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Reason
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
            <tbody className="divide-y divide-border-default">
              {paginatedRequests.map((request) => {
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
                    className={`transition-colors hover:bg-surface-hover ${
                      isRowSelected ? "bg-brand-subtle" : ""
                    }`}
                  >
                    {tab === "pending" && (
                      <td className="w-10 px-4 py-2.5 text-left align-middle">
                        <input
                          type="checkbox"
                          checked={isRowSelected}
                          onChange={() => toggleSelectOne(request.id)}
                          aria-label={`Select request ${request.requestNumber}`}
                          className="h-4 w-4 rounded border-border-default text-brand-500 focus:ring-brand-500 cursor-pointer"
                        />
                      </td>
                    )}

                    {/* REQUEST # */}
                    <td className="px-4 py-2.5 font-bold font-mono text-sm text-text-primary whitespace-nowrap align-middle">
                      {request.requestNumber}
                    </td>

                    {/* ACCOUNT */}
                    <td className="px-4 py-2.5 whitespace-nowrap align-middle">
                      <span className="inline-flex items-center rounded-md border border-border-default bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-primary">
                        {request.accountName}
                      </span>
                    </td>

                    {/* SOURCE GROUP (FROM) */}
                    <td className="px-4 py-2.5 text-sm text-text-primary whitespace-nowrap align-middle">
                      <span className="inline-flex items-center gap-1 font-medium text-text-primary">
                        <Layers className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
                        {request.fromGroupName}
                      </span>
                      {request.fromGroupCode && (
                        <span className="ml-1 font-mono text-xs text-text-muted">
                          ({request.fromGroupCode})
                        </span>
                      )}
                    </td>

                    {/* TARGET GROUP (TO) */}
                    <td className="px-4 py-2.5 text-sm text-text-primary whitespace-nowrap align-middle">
                      <span className="inline-flex items-center gap-1 font-medium text-text-primary">
                        <ArrowRight className="h-3.5 w-3.5 text-text-muted" aria-hidden="true" />
                        {request.toGroupName}
                      </span>
                      {request.toGroupCode && (
                        <span className="ml-1 font-mono text-xs text-text-muted">
                          ({request.toGroupCode})
                        </span>
                      )}
                    </td>

                    {/* REASON */}
                    <td className="px-4 py-2.5 text-sm text-text-secondary max-w-xs truncate align-middle" title={request.reason}>
                      {request.reason}
                    </td>

                    {/* REQUESTED BY */}
                    <td className="px-4 py-2.5 whitespace-nowrap align-middle">
                      <div className="flex flex-col">
                        <span className="text-sm text-text-primary">
                          {request.requestedByName || "Unknown"}
                        </span>
                        <span className="text-xs text-text-muted font-mono">
                          {formatDate(request.requestedAt)}
                        </span>
                      </div>
                    </td>

                    {/* ACTION / REJECTED REASON */}
                    <td className={`px-4 py-2.5 align-middle ${tab === "rejected" ? "text-left" : "text-right"}`}>
                      {tab === "rejected" ? (
                        <div className="flex flex-col max-w-xs">
                          <span className="text-xs font-normal text-text-danger border border-border-danger bg-danger-subtle rounded-lg px-2.5 py-1">
                            {request.rejectionReason || "No rejection reason provided"}
                          </span>
                          {request.reviewedAt && (
                            <span className="text-xs text-text-muted mt-1 font-mono">
                              {formatDate(request.reviewedAt)}
                            </span>
                          )}
                        </div>
                      ) : isPending ? (
                        <div className="inline-flex items-center justify-end gap-2">
                          <button
                            type="button"
                            onClick={() => handleOpenReject(request)}
                            disabled={isBusy || !canReview}
                            title={!canReview ? "Requires Admin role" : undefined}
                            className="inline-flex h-7 items-center justify-center rounded-lg border border-border-danger bg-transparent px-2.5 text-xs font-medium text-text-danger hover:bg-danger-subtle disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Reject</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => handleOpenApprove(request)}
                            disabled={isBusy || !canReview}
                            title={!canReview ? "Requires Admin role" : undefined}
                            className="inline-flex h-7 items-center justify-center rounded-lg border border-border-brand bg-brand-500 hover:bg-brand-600 px-3 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Approve</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex flex-col items-end gap-0.5">
                          <span className="inline-flex items-center gap-1.5 text-xs text-text-primary font-medium">
                            <CheckCircle2 className="h-3.5 w-3.5 text-text-muted" />
                            Transferred
                          </span>
                          {request.reviewedAt && (
                            <span className="text-xs text-text-muted font-mono">
                              {formatDate(request.reviewedAt)}
                            </span>
                          )}
                        </div>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-surface-subtle px-2.5 py-0.5 text-xs font-medium text-text-secondary border border-border-default">
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
        <Modal
          isOpen={Boolean(selectedApproveRequest)}
          onClose={() => setSelectedApproveRequest(null)}
          title="Approve Account Group Transfer"
          subtitle="Execute account migration between operational groups"
          icon={CheckCircle2}
          isSubmitting={approveMutation.isPending}
          disableBackdropClick={approveMutation.isPending}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <div className="rounded-lg border border-border-default bg-surface-subtle p-3 text-xs space-y-1.5">
              <div className="flex justify-between">
                <span className="text-text-secondary">Request #:</span>
                <span className="font-mono font-bold text-text-primary">
                  {selectedApproveRequest.requestNumber}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Account:</span>
                <span className="font-bold text-text-primary">
                  {selectedApproveRequest.accountName}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Transfer:</span>
                <span className="font-semibold text-text-primary">
                  {selectedApproveRequest.fromGroupName} → {selectedApproveRequest.toGroupName}
                </span>
              </div>
            </div>

            {actionError && (
              <div className="flex items-center gap-2 rounded-md bg-danger-subtle p-2.5 text-xs text-text-danger border border-border-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" />
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
                <span>Confirm Transfer</span>
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* Single Reject Modal */}
      {selectedRejectRequest && (
        <Modal
          isOpen={Boolean(selectedRejectRequest)}
          onClose={() => setSelectedRejectRequest(null)}
          title="Reject Account Group Transfer"
          subtitle="Provide reason for rejecting this transfer request"
          icon={XCircle}
          isSubmitting={rejectMutation.isPending}
          disableBackdropClick={rejectMutation.isPending}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <div className="rounded-lg border border-border-default bg-surface-subtle p-3 text-xs space-y-1.5">
              <div className="flex justify-between">
                <span className="text-text-secondary">Request #:</span>
                <span className="font-mono font-bold text-text-primary">
                  {selectedRejectRequest.requestNumber}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Account:</span>
                <span className="font-bold text-text-primary">
                  {selectedRejectRequest.accountName}
                </span>
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-text-primary">
                Rejection Reason <span className="text-text-danger">*</span>
              </label>
              <textarea
                value={rejectionReason}
                onChange={(e) => {
                  setRejectionReason(e.target.value);
                  if (e.target.value.trim()) setRejectReasonError(false);
                }}
                rows={3}
                placeholder="Explain why this account transfer is being rejected..."
                className={`mt-1 w-full rounded-md border p-2 text-xs text-text-primary bg-surface placeholder:text-text-muted focus:outline-hidden ${
                  rejectReasonError
                    ? "border-border-danger focus:border-border-danger"
                    : "border-border-default focus:border-border-brand"
                }`}
              />
              {rejectReasonError && (
                <p className="mt-1 text-2xs text-text-danger">
                  Rejection reason is required.
                </p>
              )}
            </div>

            {actionError && (
              <div className="flex items-center gap-2 rounded-md bg-danger-subtle p-2.5 text-xs text-text-danger border border-border-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" />
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
          title={`Approve ${selectedIds.size} Account Transfer${selectedIds.size === 1 ? "" : "s"}`}
          subtitle="Bulk account group reassignment confirmation"
          icon={CheckCheck}
          isSubmitting={isBulkProcessing}
          disableBackdropClick={isBulkProcessing}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <div className="rounded-lg border border-border-default bg-surface-subtle p-3 text-xs space-y-2">
              <p className="text-text-primary font-medium">
                Are you sure you want to approve all{" "}
                <span className="font-bold text-text-brand-bold">{selectedIds.size}</span>{" "}
                selected account group transfer requests?
              </p>
              <p className="text-text-secondary">
                This will officially reassign the selected accounts and store branches to their target operational groups.
              </p>
            </div>

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
          title={`Reject ${selectedIds.size} Account Transfer${selectedIds.size === 1 ? "" : "s"}`}
          subtitle="Bulk transfer rejection justification"
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
                  if (e.target.value.trim().length >= 3) setBulkRejectReasonError(false);
                }}
                placeholder="State the reason for rejecting these account group transfers..."
                className={`w-full rounded-md border p-2.5 text-xs text-text-primary bg-surface placeholder:text-text-muted focus:outline-hidden ${
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
