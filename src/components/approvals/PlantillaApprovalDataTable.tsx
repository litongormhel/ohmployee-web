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
              ? "border border-emerald-200 bg-emerald-50 text-emerald-800"
              : "border border-rose-200 bg-rose-50 text-rose-800"
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
                  Candidate Name
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Target Account
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Position
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  VCode (Plantilla Slot)
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  EMPLOC #
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Requested By
                </th>
                <th scope="col" className="px-4 py-2.5 font-medium">
                  Date
                </th>
                <th
                  scope="col"
                  className={`px-4 py-2.5 font-medium ${
                    tab === "rejected" ? "text-left" : "text-right"
                  }`}
                >
                  {tab === "rejected" ? "Rejection Remarks" : "Action"}
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
                  reqStatus === "approved" || reqStatus === "completed";
                const isRowSelected = selectedIds.has(request.id);

                return (
                  <tr
                    key={request.id}
                    className={`transition-colors hover:bg-[var(--soft)] ${
                      isRowSelected ? "bg-[var(--pillbg)]/40" : ""
                    }`}
                  >
                    {tab === "pending" && (
                      <td className="px-4 py-3">
                        <input
                          type="checkbox"
                          checked={isRowSelected}
                          onChange={() => toggleSelectOne(request.id)}
                          aria-label={`Select deployment for ${request.applicantName}`}
                          className="h-4 w-4 rounded border-[var(--line)] text-[var(--accent)] focus:ring-[var(--accent)] cursor-pointer"
                        />
                      </td>
                    )}
                    <td className="px-4 py-3">
                      <div className="font-semibold text-[var(--text)]">
                        {request.applicantName}
                      </div>
                      <div className="text-[11px] text-[var(--muted)]">
                        ID: {request.id.slice(0, 8)}…
                      </div>
                    </td>
                    <td className="px-4 py-3 text-[var(--text)]">
                      <span className="font-medium">{request.account || "—"}</span>
                    </td>
                    <td className="px-4 py-3 text-[var(--text)]">
                      <span className="inline-flex items-center rounded-md bg-[var(--soft)] px-2 py-0.5 text-xs font-medium text-[var(--text)]">
                        {request.position || "—"}
                      </span>
                    </td>
                    <td className="px-4 py-3 font-mono text-[var(--accent)] font-semibold">
                      {request.vcode}
                    </td>
                    <td className="px-4 py-3 text-[var(--text)] font-mono text-xs">
                      {request.emplocNo || "—"}
                    </td>
                    <td className="px-4 py-3 text-[var(--text)]">
                      <div>{request.requestedBy}</div>
                    </td>
                    <td className="px-4 py-3 text-[var(--muted)] whitespace-nowrap">
                      {formatDate(request.createdAt)}
                    </td>
                    <td
                      className={`px-4 py-3 ${
                        tab === "rejected" ? "text-left" : "text-right"
                      }`}
                    >
                      {isPending ? (
                        <div className="flex items-center justify-end gap-1.5">
                          <button
                            type="button"
                            onClick={() => handleOpenReject(request)}
                            disabled={isBusy}
                            className="inline-flex h-7 items-center rounded-md border border-[var(--bad)]/40 bg-transparent px-2 text-xs font-medium text-[var(--bad)] hover:bg-[var(--bad)]/10 disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Reject</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => handleOpenApprove(request)}
                            disabled={isBusy}
                            className="inline-flex h-7 items-center rounded-md border border-[var(--ok)] bg-[var(--ok)] px-2.5 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 transition cursor-pointer"
                          >
                            <span>Approve</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex items-center gap-1 text-xs font-medium text-[var(--ok)]">
                          <CheckCircle2 className="h-3.5 w-3.5" />
                          <span>Approved</span>
                          {request.reviewedBy && (
                            <span className="text-[11px] text-[var(--muted)] ml-1">
                              by {request.reviewedBy}
                            </span>
                          )}
                        </div>
                      ) : (
                        <div className="text-xs text-[var(--bad)] max-w-xs truncate">
                          {request.remarks || "Rejected"}
                          {request.reviewedBy && (
                            <div className="text-[10px] text-[var(--muted)]">
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
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-md rounded-xl border border-[var(--line)] bg-[var(--bg)] p-5 shadow-xl animate-in fade-in-0 zoom-in-95">
            <div className="flex items-start justify-between gap-3 border-b border-[var(--line)] pb-3">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[var(--ok)]/15 text-[var(--ok)]">
                  <UserCheck className="h-4 w-4" />
                </div>
                <div>
                  <h3 className="text-sm font-semibold text-[var(--text)]">
                    Approve Plantilla Deployment
                  </h3>
                  <p className="text-xs text-[var(--muted)]">
                    Candidate will be officially linked to slot {selectedApproveRequest.vcode}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setSelectedApproveRequest(null)}
                className="text-[var(--muted)] hover:text-[var(--text)] cursor-pointer"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {actionError && (
              <div className="mt-3 flex items-center gap-2 rounded-md border border-rose-200 bg-rose-50 p-2 text-xs text-rose-800">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="mt-4 space-y-2 text-xs">
              <div className="flex justify-between border-b border-[var(--line)] pb-1.5">
                <span className="text-[var(--muted)]">Candidate:</span>
                <span className="font-semibold text-[var(--text)]">
                  {selectedApproveRequest.applicantName}
                </span>
              </div>
              <div className="flex justify-between border-b border-[var(--line)] pb-1.5">
                <span className="text-[var(--muted)]">Account & Position:</span>
                <span className="text-[var(--text)]">
                  {selectedApproveRequest.account} · {selectedApproveRequest.position}
                </span>
              </div>
              <div className="flex justify-between border-b border-[var(--line)] pb-1.5">
                <span className="text-[var(--muted)]">VCode Slot:</span>
                <span className="font-mono text-[var(--accent)] font-semibold">
                  {selectedApproveRequest.vcode}
                </span>
              </div>
              <div className="flex justify-between border-b border-[var(--line)] pb-1.5">
                <span className="text-[var(--muted)]">EMPLOC #:</span>
                <span className="font-mono text-[var(--text)]">
                  {selectedApproveRequest.emplocNo}
                </span>
              </div>
              <div className="flex justify-between pb-1">
                <span className="text-[var(--muted)]">Requested By:</span>
                <span className="text-[var(--text)]">
                  {selectedApproveRequest.requestedBy}
                </span>
              </div>
            </div>

            <div className="mt-5 flex items-center justify-end gap-2 border-t border-[var(--line)] pt-3">
              <button
                type="button"
                onClick={() => setSelectedApproveRequest(null)}
                disabled={approveMutation.isPending}
                className="rounded-lg border border-[var(--line)] bg-transparent px-3 py-1.5 text-xs font-medium text-[var(--text)] hover:bg-[var(--soft)] disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                disabled={approveMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--ok)] bg-[var(--ok)] px-3 py-1.5 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 cursor-pointer"
              >
                {approveMutation.isPending && (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                )}
                <span>Confirm Approval</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Single Reject Modal */}
      {selectedRejectRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-md rounded-xl border border-[var(--line)] bg-[var(--bg)] p-5 shadow-xl animate-in fade-in-0 zoom-in-95">
            <div className="flex items-start justify-between gap-3 border-b border-[var(--line)] pb-3">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[var(--bad)]/15 text-[var(--bad)]">
                  <XCircle className="h-4 w-4" />
                </div>
                <div>
                  <h3 className="text-sm font-semibold text-[var(--text)]">
                    Reject Plantilla Deployment
                  </h3>
                  <p className="text-xs text-[var(--muted)]">
                    Provide a mandatory reason for candidate rejection
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setSelectedRejectRequest(null)}
                className="text-[var(--muted)] hover:text-[var(--text)] cursor-pointer"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {actionError && (
              <div className="mt-3 flex items-center gap-2 rounded-md border border-rose-200 bg-rose-50 p-2 text-xs text-rose-800">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>{actionError}</span>
              </div>
            )}

            <div className="mt-3 space-y-3">
              <div className="text-xs text-[var(--muted)]">
                Rejecting deployment for{" "}
                <strong className="text-[var(--text)]">
                  {selectedRejectRequest.applicantName}
                </strong>{" "}
                (Slot {selectedRejectRequest.vcode}).
              </div>

              <div>
                <label className="block text-xs font-medium text-[var(--text)] mb-1">
                  Rejection Remarks <span className="text-[var(--bad)]">*</span>
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
                  className={`w-full rounded-lg border p-2.5 text-xs text-[var(--text)] bg-[var(--bg)] placeholder:text-[var(--muted)] focus:outline-hidden ${
                    rejectReasonError
                      ? "border-[var(--bad)] focus:border-[var(--bad)]"
                      : "border-[var(--line)] focus:border-[var(--accent)]"
                  }`}
                />
                {rejectReasonError && (
                  <p className="mt-1 text-2xs text-[var(--bad)]">
                    Rejection remarks are required.
                  </p>
                )}
              </div>
            </div>

            <div className="mt-5 flex items-center justify-end gap-2 border-t border-[var(--line)] pt-3">
              <button
                type="button"
                onClick={() => setSelectedRejectRequest(null)}
                disabled={rejectMutation.isPending}
                className="rounded-lg border border-[var(--line)] bg-transparent px-3 py-1.5 text-xs font-medium text-[var(--text)] hover:bg-[var(--soft)] disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                disabled={rejectMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--bad)] bg-[var(--bad)] px-3 py-1.5 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 cursor-pointer"
              >
                {rejectMutation.isPending && (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                )}
                <span>Confirm Rejection</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Bulk Approve Modal */}
      {isBulkApproveOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-md rounded-xl border border-[var(--line)] bg-[var(--bg)] p-5 shadow-xl animate-in fade-in-0 zoom-in-95">
            <div className="flex items-start justify-between gap-3 border-b border-[var(--line)] pb-3">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[var(--ok)]/15 text-[var(--ok)]">
                  <UserCheck className="h-4 w-4" />
                </div>
                <div>
                  <h3 className="text-sm font-semibold text-[var(--text)]">
                    Bulk Approve Deployments
                  </h3>
                  <p className="text-xs text-[var(--muted)]">
                    Deploy {selectedIds.size} candidate(s) to permanent plantilla
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsBulkApproveOpen(false)}
                className="text-[var(--muted)] hover:text-[var(--text)] cursor-pointer"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <p className="mt-3 text-xs text-[var(--muted)]">
              Are you sure you want to approve all {selectedIds.size} selected candidate deployments?
              This will update their HR Emploc status and place them into their assigned plantilla slots.
            </p>

            <div className="mt-5 flex items-center justify-end gap-2 border-t border-[var(--line)] pt-3">
              <button
                type="button"
                onClick={() => setIsBulkApproveOpen(false)}
                disabled={isBulkProcessing}
                className="rounded-lg border border-[var(--line)] bg-transparent px-3 py-1.5 text-xs font-medium text-[var(--text)] hover:bg-[var(--soft)] disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkApprove}
                disabled={isBulkProcessing}
                className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--ok)] bg-[var(--ok)] px-3 py-1.5 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 cursor-pointer"
              >
                {isBulkProcessing && (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                )}
                <span>Approve All ({selectedIds.size})</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Bulk Reject Modal */}
      {isBulkRejectOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-xs p-4">
          <div className="w-full max-w-md rounded-xl border border-[var(--line)] bg-[var(--bg)] p-5 shadow-xl animate-in fade-in-0 zoom-in-95">
            <div className="flex items-start justify-between gap-3 border-b border-[var(--line)] pb-3">
              <div className="flex items-center gap-2">
                <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[var(--bad)]/15 text-[var(--bad)]">
                  <XCircle className="h-4 w-4" />
                </div>
                <div>
                  <h3 className="text-sm font-semibold text-[var(--text)]">
                    Bulk Reject Deployments
                  </h3>
                  <p className="text-xs text-[var(--muted)]">
                    Reject {selectedIds.size} candidate deployment(s)
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsBulkRejectOpen(false)}
                className="text-[var(--muted)] hover:text-[var(--text)] cursor-pointer"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-3 space-y-3">
              <div>
                <label className="block text-xs font-medium text-[var(--text)] mb-1">
                  Reason for Bulk Rejection <span className="text-[var(--bad)]">*</span>
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
                  className={`w-full rounded-lg border p-2.5 text-xs text-[var(--text)] bg-[var(--bg)] placeholder:text-[var(--muted)] focus:outline-hidden ${
                    bulkRejectReasonError
                      ? "border-[var(--bad)] focus:border-[var(--bad)]"
                      : "border-[var(--line)] focus:border-[var(--accent)]"
                  }`}
                />
                {bulkRejectReasonError && (
                  <p className="mt-1 text-2xs text-[var(--bad)]">
                    A valid rejection reason (minimum 3 characters) is required.
                  </p>
                )}
              </div>
            </div>

            <div className="mt-5 flex items-center justify-end gap-2 border-t border-[var(--line)] pt-3">
              <button
                type="button"
                onClick={() => setIsBulkRejectOpen(false)}
                disabled={isBulkProcessing}
                className="rounded-lg border border-[var(--line)] bg-transparent px-3 py-1.5 text-xs font-medium text-[var(--text)] hover:bg-[var(--soft)] disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkReject}
                disabled={isBulkProcessing}
                className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--bad)] bg-[var(--bad)] px-3 py-1.5 text-xs font-medium text-white hover:brightness-105 disabled:opacity-50 cursor-pointer"
              >
                {isBulkProcessing && (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                )}
                <span>Reject All ({selectedIds.size})</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
