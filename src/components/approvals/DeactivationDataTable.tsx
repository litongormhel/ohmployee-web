"use client";

import { useState } from "react";
import {
  AlertTriangle,
  CheckCheck,
  CheckCircle2,
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
  // Modal states for single actions
  const [selectedApproveRequest, setSelectedApproveRequest] =
    useState<DeactivationRequestItem | null>(null);
  const [selectedRejectRequest, setSelectedRejectRequest] =
    useState<DeactivationRequestItem | null>(null);
  const [approveRemarks, setApproveRemarks] = useState("");
  const [rejectionReason, setRejectionReason] = useState("");
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

  const completeMutation = useCompleteDeactivation();
  const rejectMutation = useRejectDeactivation();

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
        await completeMutation.mutateAsync({
          requestId: req.id,
          plantillaId: req.plantillaId,
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.employeeName}`);
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
        message: `Successfully approved ${successCount} deactivation request${successCount === 1 ? "" : "s"}.`,
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
          plantillaId: req.plantillaId,
          reason: bulkRejectionReason.trim(),
        });
        successCount++;
      } catch (err: unknown) {
        errors.push(err instanceof Error ? err.message : `Failed on ${req.employeeName}`);
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
        message: `Successfully rejected ${successCount} deactivation request${successCount === 1 ? "" : "s"}.`,
      });
    }
  };

  const isBusy = completeMutation.isPending || rejectMutation.isPending || isBulkProcessing;

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
                <th scope="col" className="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider text-[var(--muted)]">
                  GROUP
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider text-[var(--muted)]">
                  ACCOUNT
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider text-[var(--muted)]">
                  EMPLOC
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider text-[var(--muted)]">
                  FULLNAME
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider text-[var(--muted)]">
                  POSITION
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider text-[var(--muted)]">
                  SEPARATION STATUS
                </th>
                <th scope="col" className="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider text-[var(--muted)]">
                  REQUESTED BY
                </th>
                <th
                  scope="col"
                  className="px-4 py-2.5 font-semibold text-[11px] uppercase tracking-wider text-[var(--muted)] text-right"
                >
                  ACTION
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--line)]">
              {requests.map((request) => {
                const reqStatus = (request.status || "").toLowerCase();
                const isPending =
                  tab === "pending" ||
                  reqStatus === "pending" ||
                  reqStatus === "under_review";
                const isApproved =
                  tab === "approved" ||
                  reqStatus === "approved" ||
                  reqStatus === "completed";
                const isRejected =
                  tab === "rejected" ||
                  reqStatus === "rejected" ||
                  reqStatus === "cancelled";
                const isRowSelected = selectedIds.has(request.id);

                return (
                  <tr
                    key={request.id}
                    className={`transition-colors hover:bg-[var(--soft)] ${
                      isRowSelected ? "bg-[var(--pillbg)]/40" : ""
                    }`}
                  >
                    {tab === "pending" && (
                      <td className="w-10 px-4 py-3 text-left align-middle">
                        <input
                          type="checkbox"
                          checked={isRowSelected}
                          onChange={() => toggleSelectOne(request.id)}
                          aria-label={`Select ${request.employeeName}`}
                          className="h-4 w-4 rounded border-[var(--line)] text-[var(--accent)] focus:ring-[var(--accent)] cursor-pointer"
                        />
                      </td>
                    )}

                    {/* GROUP */}
                    <td className="px-4 py-3 text-xs text-[var(--text)] whitespace-nowrap align-middle font-medium">
                      {request.groupName || "—"}
                    </td>

                    {/* ACCOUNT */}
                    <td className="px-4 py-3 whitespace-nowrap align-middle">
                      <span className="inline-flex items-center rounded-[6px] border border-[var(--status-accent-border)] bg-[var(--pillbg)] px-2 py-0.5 text-xs font-semibold text-[var(--accent)]">
                        {request.accountName}
                      </span>
                    </td>

                    {/* EMPLOC */}
                    <td className="px-4 py-3 font-mono text-xs text-[var(--text)] whitespace-nowrap align-middle">
                      {request.employeeNo || "—"}
                    </td>

                    {/* FULLNAME */}
                    <td className="px-4 py-3 align-middle">
                      <div className="flex flex-col">
                        <span className="font-bold text-[var(--text)] text-xs">
                          {request.employeeName}
                        </span>
                        {request.resubmitCount > 0 && (
                          <span className="inline-flex items-center text-[10px] font-medium text-amber-700 dark:text-amber-400 mt-0.5">
                            Resubmit #{request.resubmitCount}
                          </span>
                        )}
                        {request.storeName && (
                          <span className="text-[11px] text-[var(--muted)]">
                            {request.storeName}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* POSITION */}
                    <td className="px-4 py-3 text-xs text-[var(--text)] whitespace-nowrap align-middle">
                      {request.positionTitle || "—"}
                    </td>

                    {/* SEPARATION STATUS */}
                    <td className="px-4 py-3 whitespace-nowrap align-middle">
                      <SeparationStatusBadge status={request.separationStatus} />
                    </td>

                    {/* REQUESTED BY */}
                    <td className="px-4 py-3 whitespace-nowrap align-middle">
                      <div className="flex flex-col">
                        <span className="text-xs font-medium text-[var(--text)]">
                          {request.requestedByName || "Unknown"}
                        </span>
                        <span className="text-[11px] text-[var(--muted)]">
                          {formatDate(request.requestedAt)}
                        </span>
                      </div>
                    </td>

                    {/* ACTION */}
                    <td className="px-4 py-3 align-middle text-right">
                      {isPending ? (
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
                            <span>Approve Deactivation</span>
                          </button>
                        </div>
                      ) : isApproved ? (
                        <div className="inline-flex flex-col items-end gap-0.5">
                          <span className="inline-flex items-center gap-1.5 text-xs text-[var(--ok)] font-medium">
                            <span className="w-1.5 h-1.5 rounded-full bg-[var(--ok)]" />
                            Deactivated
                          </span>
                          {request.processedAt && (
                            <span className="text-[11px] text-[var(--muted)]">
                              {formatDate(request.processedAt)}
                            </span>
                          )}
                        </div>
                      ) : isRejected ? (
                        <div className="inline-flex flex-col items-end gap-0.5">
                          <span className="inline-flex items-center gap-1.5 text-xs text-[var(--bad)] font-medium">
                            <span className="w-1.5 h-1.5 rounded-full bg-[var(--bad)]" />
                            Rejected
                          </span>
                          {request.processedAt && (
                            <span className="text-[11px] text-[var(--muted)]">
                              {formatDate(request.processedAt)}
                            </span>
                          )}
                          {request.rejectionReason && (
                            <span
                              className="text-[10px] text-[var(--muted)] max-w-[200px] truncate"
                              title={request.rejectionReason}
                            >
                              {request.rejectionReason}
                            </span>
                          )}
                        </div>
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
      </div>

      {/* Approve Confirmation Modal (Single) */}
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
                    Approve Employee Deactivation
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Confirm separation clearance and record archiving
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
                  <span className="text-text-secondary">Employee:</span>
                  <span className="font-bold text-text-primary">
                    {selectedApproveRequest.employeeName}
                  </span>
                </div>
                {selectedApproveRequest.employeeNo && (
                  <div className="flex justify-between">
                    <span className="text-text-secondary">Employee No:</span>
                    <span className="font-mono font-medium text-text-primary">
                      {selectedApproveRequest.employeeNo}
                    </span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span className="text-text-secondary">Account:</span>
                  <span className="font-medium text-text-primary">
                    {selectedApproveRequest.accountName}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-secondary">Separation:</span>
                  <SeparationStatusBadge status={selectedApproveRequest.separationStatus} />
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-text-primary">
                  Approval Remarks (Optional)
                </label>
                <textarea
                  rows={2}
                  value={approveRemarks}
                  onChange={(e) => setApproveRemarks(e.target.value)}
                  placeholder="Additional clearance notes or reference..."
                  className="mt-1 w-full rounded-md border border-border-default bg-white p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-hidden"
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

      {/* Reject Confirmation Modal (Single) */}
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
                    Reject Deactivation Request
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Provide reason for denying separation clearance
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
                  <span className="text-text-secondary">Employee:</span>
                  <span className="font-bold text-text-primary">
                    {selectedRejectRequest.employeeName}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-secondary">Account:</span>
                  <span className="font-medium text-text-primary">
                    {selectedRejectRequest.accountName}
                  </span>
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-text-primary">
                  Reason for Rejection <span className="text-rose-600">*</span>
                </label>
                <input
                  type="text"
                  value={rejectionReason}
                  onChange={(e) => {
                    setRejectionReason(e.target.value);
                    if (e.target.value.trim()) setRejectReasonError(false);
                  }}
                  placeholder="e.g., Incomplete clearance, Active store endorsement pending..."
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

              <div>
                <label className="block text-xs font-medium text-text-primary">
                  Actionable Remarks / Instructions (Optional)
                </label>
                <textarea
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
                    Approve {selectedIds.size} Deactivation Request{selectedIds.size === 1 ? "" : "s"}
                  </h3>
                  <p className="text-xs text-text-secondary">
                    Bulk separation clearance confirmation
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
                Are you sure you want to approve and deactivate all{" "}
                <span className="font-bold text-emerald-700">{selectedIds.size}</span>{" "}
                selected employee records?
              </p>
              <p className="text-text-secondary">
                This will officially terminate their active emploc records and reconcile corresponding plantilla capacity.
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
                    Reject {selectedIds.size} Deactivation Request{selectedIds.size === 1 ? "" : "s"}
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
                  placeholder="State the reason for rejecting these deactivation requests..."
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
