"use client";

import { useMemo, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  RefreshCw,
  UserCheck,
  X,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { TablePagination } from "@/components/shared/TablePagination";
import {
  useApprovePlantillaRequest,
  useRejectPlantillaRequest,
  type PlantillaApprovalItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";

interface PlantillaApprovalDataTableProps {
  requests: PlantillaApprovalItem[];
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

export function PlantillaApprovalDataTable({
  requests,
  tab,
  page,
  pageSize,
  totalCount,
  onPageChange,
  onPageSizeChange,
}: PlantillaApprovalDataTableProps) {
  const currentPage = page ?? 1;
  const currentPageSize = pageSize ?? 10;
  const count = totalCount ?? requests.length;

  const paginatedRequests = useMemo(() => {
    const start = (currentPage - 1) * currentPageSize;
    return requests.slice(start, start + currentPageSize);
  }, [requests, currentPage, currentPageSize]);

  // Modal states for single action
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<PlantillaApprovalItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<PlantillaApprovalItem | null>(null);

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

  const approveMutation = useApprovePlantillaRequest();
  const rejectMutation = useRejectPlantillaRequest();

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

  const handleOpenApprove = (req: PlantillaApprovalItem) => {
    setActionError(null);
    setSelectedApproveRequest(req);
  };

  const handleOpenReject = (req: PlantillaApprovalItem) => {
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
          : "Failed to approve candidate plantilla deployment."
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
        approvalId: selectedRejectRequest.id,
        remarks: rejectionReason.trim(),
      });
      setSelectedRejectRequest(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error
          ? err.message
          : "Failed to reject candidate plantilla deployment."
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
        errors.push(err instanceof Error ? err.message : `Failed on ${req.applicantName}`);
      }
    }

    setIsBulkProcessing(false);
    setIsBulkApproveOpen(false);
    setSelectedIds(new Set());

    if (errors.length > 0) {
      setBulkFeedback({
        type: "error",
        message: `Approved ${successCount} candidates, but ${errors.length} failed: ${errors[0]}`,
      });
    } else {
      setBulkFeedback({
        type: "success",
        message: `Successfully approved all ${successCount} selected plantilla deployments.`,
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
          approvalId: req.id,
          remarks: bulkRejectionReason.trim(),
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.applicantName}`);
      }
    }

    setIsBulkProcessing(false);
    setIsBulkRejectOpen(false);
    setSelectedIds(new Set());

    if (errors.length > 0) {
      setBulkFeedback({
        type: "error",
        message: `Rejected ${successCount} deployments, but ${errors.length} failed: ${errors[0]}`,
      });
    } else {
      setBulkFeedback({
        type: "success",
        message: `Successfully rejected ${successCount} selected candidate deployments.`,
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
              disabled={isBusy}
              className="inline-flex h-7 items-center gap-1 rounded-md border border-border-danger bg-transparent px-2.5 text-xs font-medium text-text-danger hover:bg-danger-subtle disabled:opacity-50 transition cursor-pointer"
            >
              <span>Reject {selectedIds.size > 0 ? `(${selectedIds.size})` : "All"}</span>
            </button>

            <button
              type="button"
              onClick={handleOpenBulkApprove}
              disabled={isBusy}
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
            <thead className="sticky top-0 z-10 bg-table-header text-sm font-semibold text-text-secondary border-b border-table-rule-section">
              <tr>
                {tab === "pending" && (
                  <th scope="col" className="w-10 px-4 py-2.5 text-left whitespace-nowrap">
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
                <th scope="col" className="px-4 py-2.5 font-semibold whitespace-nowrap">
                  Candidate name
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold whitespace-nowrap">
                  Target account
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold whitespace-nowrap">
                  Position
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold whitespace-nowrap">
                  VCODE (Plantilla slot)
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold whitespace-nowrap">
                  EMPLOC #
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold whitespace-nowrap">
                  Requested by
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold whitespace-nowrap">
                  Date
                </th>
                <th
                  scope="col"
                  className={`px-4 py-2.5 font-semibold whitespace-nowrap ${
                    tab === "rejected" ? "text-left" : "text-right"
                  }`}
                >
                  {tab === "rejected" ? "Rejection remarks" : "Action"}
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
                      <td className="px-4 py-2.5">
                        <input
                          type="checkbox"
                          checked={isRowSelected}
                          onChange={() => toggleSelectOne(request.id)}
                          aria-label={`Select deployment for ${request.applicantName}`}
                          className="h-4 w-4 rounded border-border-default text-brand-500 focus:ring-brand-500 cursor-pointer"
                        />
                      </td>
                    )}
                    <td className="px-4 py-2.5">
                      <div className="font-semibold text-text-primary text-sm">
                        {request.applicantName}
                      </div>
                      <div className="text-xs text-text-muted font-mono">
                        ID: {request.id.slice(0, 8)}…
                      </div>
                    </td>
                    <td className="px-4 py-2.5 text-text-primary text-sm">
                      <span className="font-medium">{request.account || "—"}</span>
                    </td>
                    <td className="px-4 py-2.5 text-text-primary text-sm">
                      <span className="inline-flex items-center rounded-md bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-primary border border-border-default">
                        {request.position || "—"}
                      </span>
                    </td>
                    <td className="px-4 py-2.5 font-mono text-text-brand-bold font-semibold text-sm">
                      {request.vcode}
                    </td>
                    <td className="px-4 py-2.5 text-text-primary font-mono text-sm">
                      {request.emplocNo || "—"}
                    </td>
                    <td className="px-4 py-2.5 text-text-primary text-sm">
                      <div>{request.requestedBy}</div>
                    </td>
                    <td className="px-4 py-2.5 text-text-secondary whitespace-nowrap text-sm font-sans tabular-nums">
                      {formatDate(request.createdAt)}
                    </td>
                    <td
                      className={`px-4 py-2.5 ${
                        tab === "rejected" ? "text-left" : "text-right"
                      }`}
                    >
                      {isPending ? (
                        <div className="flex items-center justify-end gap-1.5">
                          <button
                            type="button"
                            onClick={() => handleOpenReject(request)}
                            disabled={isBusy}
                            className="inline-flex h-7 items-center rounded-md border border-border-danger bg-transparent px-2.5 text-xs font-medium text-text-danger hover:bg-danger-subtle disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Reject</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => handleOpenApprove(request)}
                            disabled={isBusy}
                            className="inline-flex h-7 items-center rounded-md border border-border-brand bg-brand-500 hover:bg-brand-600 px-2.5 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Approve</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex items-center gap-1 text-xs font-medium text-text-primary">
                          <CheckCircle2 className="h-3.5 w-3.5 text-text-muted" />
                          <span>Approved</span>
                          {request.reviewedBy && (
                            <span className="text-xs text-text-muted ml-1">
                              by {request.reviewedBy}
                            </span>
                          )}
                        </div>
                      ) : (
                        <div className="text-xs text-text-danger max-w-xs truncate">
                          {request.remarks || "Rejected"}
                          {request.reviewedBy && (
                            <div className="text-xs text-text-muted">
                              by {request.reviewedBy}
                            </div>
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

      {/* Single Approve Modal */}
      {selectedApproveRequest && (
        <Modal
          isOpen={Boolean(selectedApproveRequest)}
          onClose={() => setSelectedApproveRequest(null)}
          title="Approve Plantilla Deployment"
          subtitle={`Candidate will be officially linked to slot ${selectedApproveRequest.vcode}`}
          icon={UserCheck}
          isSubmitting={approveMutation.isPending}
          disableBackdropClick={approveMutation.isPending}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            {actionError && (
              <div className="flex items-center gap-2 rounded-md border border-border-danger bg-danger-subtle p-2 text-xs text-text-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="space-y-2 text-xs">
              <div className="flex justify-between border-b border-border-default pb-1.5">
                <span className="text-text-secondary">Candidate:</span>
                <span className="font-semibold text-text-primary">
                  {selectedApproveRequest.applicantName}
                </span>
              </div>
              <div className="flex justify-between border-b border-border-default pb-1.5">
                <span className="text-text-secondary">Account & Position:</span>
                <span className="text-text-primary">
                  {selectedApproveRequest.account} · {selectedApproveRequest.position}
                </span>
              </div>
              <div className="flex justify-between border-b border-border-default pb-1.5">
                <span className="text-text-secondary">VCode Slot:</span>
                <span className="font-mono text-text-brand-bold font-semibold">
                  {selectedApproveRequest.vcode}
                </span>
              </div>
              <div className="flex justify-between border-b border-border-default pb-1.5">
                <span className="text-text-secondary">EMPLOC #:</span>
                <span className="font-mono text-text-primary">
                  {selectedApproveRequest.emplocNo}
                </span>
              </div>
              <div className="flex justify-between pb-1">
                <span className="text-text-secondary">Requested By:</span>
                <span className="text-text-primary">
                  {selectedApproveRequest.requestedBy}
                </span>
              </div>
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-3">
              <button
                type="button"
                onClick={() => setSelectedApproveRequest(null)}
                disabled={approveMutation.isPending}
                className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={approveMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-lg border border-border-brand bg-brand-500 hover:bg-brand-600 px-3 py-1.5 text-xs font-medium text-white shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {approveMutation.isPending && (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                )}
                <span>Confirm Approval</span>
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
          title="Reject Plantilla Deployment"
          subtitle="Provide a mandatory reason for candidate rejection"
          icon={XCircle}
          isSubmitting={rejectMutation.isPending}
          disableBackdropClick={rejectMutation.isPending}
          isDirty={Boolean(rejectionReason.trim())}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            {actionError && (
              <div className="flex items-center gap-2 rounded-md border border-border-danger bg-danger-subtle p-2 text-xs text-text-danger">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="space-y-3">
              <div className="text-xs text-text-secondary">
                Rejecting deployment for{" "}
                <strong className="text-text-primary">
                  {selectedRejectRequest.applicantName}
                </strong>{" "}
                (Slot {selectedRejectRequest.vcode}).
              </div>

              <div>
                <label className="block text-xs font-medium text-text-primary mb-1">
                  Rejection Remarks <span className="text-text-danger">*</span>
                </label>
                <textarea
                  rows={3}
                  value={rejectionReason}
                  onChange={(e) => {
                    setRejectionReason(e.target.value);
                    if (rejectReasonError && e.target.value.trim()) {
                      setRejectReasonError(false);
                    }
                  }}
                  placeholder="e.g. Candidate failed qualification check, slot freeze active, etc."
                  className={`w-full rounded-lg border p-2.5 text-xs text-text-primary bg-surface placeholder:text-text-muted focus:outline-hidden ${
                    rejectReasonError
                      ? "border-border-danger focus:border-border-danger"
                      : "border-border-default focus:border-border-brand"
                  }`}
                />
                {rejectReasonError && (
                  <p className="mt-1 text-2xs text-text-danger">
                    Rejection remarks are required.
                  </p>
                )}
              </div>
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-3">
              <button
                type="button"
                onClick={() => setSelectedRejectRequest(null)}
                disabled={rejectMutation.isPending}
                className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={rejectMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-lg border border-border-danger bg-danger-button hover:bg-danger-button-hover px-3 py-1.5 text-xs font-medium text-danger-button-text shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {rejectMutation.isPending && (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                )}
                <span>Confirm Rejection</span>
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* Bulk Approve Modal */}
      {isBulkApproveOpen && (
        <Modal
          isOpen={isBulkApproveOpen}
          onClose={() => setIsBulkApproveOpen(false)}
          title="Bulk Approve Deployments"
          subtitle={`Deploy ${selectedIds.size} candidate(s) to permanent plantilla`}
          icon={UserCheck}
          isSubmitting={isBulkProcessing}
          disableBackdropClick={isBulkProcessing}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <p className="text-xs text-text-secondary">
              Are you sure you want to approve all {selectedIds.size} selected candidate deployments?
              This will update their HR Emploc status and place them into their assigned plantilla slots.
            </p>

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-3">
              <button
                type="button"
                onClick={() => setIsBulkApproveOpen(false)}
                disabled={isBulkProcessing}
                className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkApprove}
                disabled={isBulkProcessing}
                className="inline-flex items-center gap-1.5 rounded-lg border border-border-brand bg-brand-500 hover:bg-brand-600 px-3 py-1.5 text-xs font-medium text-white shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {isBulkProcessing && (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                )}
                <span>Approve All ({selectedIds.size})</span>
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* Bulk Reject Modal */}
      {isBulkRejectOpen && (
        <Modal
          isOpen={isBulkRejectOpen}
          onClose={() => setIsBulkRejectOpen(false)}
          title="Bulk Reject Deployments"
          subtitle={`Reject ${selectedIds.size} candidate deployment(s)`}
          icon={XCircle}
          isSubmitting={isBulkProcessing}
          disableBackdropClick={isBulkProcessing}
          maxWidthClass="max-w-md"
        >
          <div className="space-y-4">
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-text-primary mb-1">
                  Reason for Bulk Rejection <span className="text-text-danger">*</span>
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
                  placeholder="Provide a reason for rejecting all selected deployments (min 3 chars)..."
                  className={`w-full rounded-lg border p-2.5 text-xs text-text-primary bg-surface placeholder:text-text-muted focus:outline-hidden ${
                    bulkRejectReasonError
                      ? "border-border-danger focus:border-border-danger"
                      : "border-border-default focus:border-border-brand"
                  }`}
                />
                {bulkRejectReasonError && (
                  <p className="mt-1 text-2xs text-text-danger">
                    A valid rejection reason (minimum 3 characters) is required.
                  </p>
                )}
              </div>
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-border-default pt-3">
              <button
                type="button"
                onClick={() => setIsBulkRejectOpen(false)}
                disabled={isBulkProcessing}
                className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkReject}
                disabled={isBulkProcessing}
                className="inline-flex items-center gap-1.5 rounded-lg border border-border-danger bg-danger-button hover:bg-danger-button-hover px-3 py-1.5 text-xs font-medium text-danger-button-text shadow-2xs disabled:opacity-50 cursor-pointer"
              >
                {isBulkProcessing && (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                )}
                <span>Reject All ({selectedIds.size})</span>
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
