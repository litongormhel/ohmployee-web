"use client";

import { useState } from "react";
import {
  AlertTriangle,
  Calendar,
  CheckCircle2,
  Clock,
  FileSpreadsheet,
  Layers,
  Loader2,
  RotateCcw,
  User,
  XCircle,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { Pagination } from "@/components/shared/Pagination";
import {
  useApproveRollbackRequest,
  useRejectRollbackRequest,
  type RollbackApprovalItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";

interface RollbackDataTableProps {
  requests: RollbackApprovalItem[];
  tab: ApprovalStatusTab;
  page?: number;
  pageSize?: number;
  totalCount?: number;
  onPageChange?: (newPage: number) => void;
  onPageSizeChange?: (newPageSize: number) => void;
}

function formatDate(dateStr?: string | null): string {
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

function formatRollbackRemaining(seconds?: number): string {
  if (!seconds || seconds <= 0) return "Expired / Inactive";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m remaining`;
  return `${m}m remaining`;
}

export function RollbackDataTable({
  requests,
  tab,
  page = 1,
  pageSize = 10,
  totalCount = requests.length,
  onPageChange,
  onPageSizeChange,
}: RollbackDataTableProps) {
  const [selectedDetailItem, setSelectedDetailItem] = useState<RollbackApprovalItem | null>(null);
  const [selectedApproveItem, setSelectedApproveItem] = useState<RollbackApprovalItem | null>(null);
  const [selectedRejectItem, setSelectedRejectItem] = useState<RollbackApprovalItem | null>(null);
  const [rejectRemarks, setRejectRemarks] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const approveMutation = useApproveRollbackRequest();
  const rejectMutation = useRejectRollbackRequest();

  const handleApprove = async () => {
    if (!selectedApproveItem) return;
    setErrorMessage(null);
    try {
      await approveMutation.mutateAsync({
        id: selectedApproveItem.id,
        batchType: selectedApproveItem.batchType,
      });
      setSelectedApproveItem(null);
      if (selectedDetailItem?.id === selectedApproveItem.id) {
        setSelectedDetailItem(null);
      }
    } catch (err: unknown) {
      setErrorMessage(err instanceof Error ? err.message : "Failed to execute rollback.");
    }
  };

  const handleReject = async () => {
    if (!selectedRejectItem) return;
    if (!rejectRemarks.trim()) {
      setErrorMessage("Please enter a rejection reason.");
      return;
    }
    setErrorMessage(null);
    try {
      await rejectMutation.mutateAsync({
        id: selectedRejectItem.id,
        batchType: selectedRejectItem.batchType,
        reason: rejectRemarks.trim(),
      });
      setSelectedRejectItem(null);
      setRejectRemarks("");
      if (selectedDetailItem?.id === selectedRejectItem.id) {
        setSelectedDetailItem(null);
      }
    } catch (err: unknown) {
      setErrorMessage(err instanceof Error ? err.message : "Failed to reject rollback request.");
    }
  };

  if (requests.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-center border border-dashed border-border-default rounded-xl bg-surface-base">
        <RotateCcw className="h-10 w-10 text-text-muted/60 mb-3" />
        <h4 className="text-sm font-semibold text-text-primary">
          {tab === "pending"
            ? "No pending rollback requests"
            : tab === "approved"
            ? "No executed rollbacks"
            : "No rejected rollback requests"}
        </h4>
        <p className="text-xs text-text-muted mt-1 max-w-sm">
          {tab === "pending"
            ? "When a store or vacancy import rollback is requested by an administrator, it will appear here for review."
            : "No import batch reversals recorded for this status."}
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col flex-1 min-h-0 bg-surface-base rounded-xl border border-border-default overflow-hidden">
      <div className="overflow-x-auto flex-1 min-h-0">
        <table className="w-full text-left text-xs border-collapse">
          <thead className="sticky top-0 bg-surface-muted border-b border-border-subtle z-10">
            <tr>
              <th className="p-3 font-semibold text-text-secondary">Batch #</th>
              <th className="p-3 font-semibold text-text-secondary">Module</th>
              <th className="p-3 font-semibold text-text-secondary">File Name</th>
              <th className="p-3 font-semibold text-text-secondary">Scope</th>
              <th className="p-3 font-semibold text-text-secondary">Rollback Reason / Note</th>
              <th className="p-3 font-semibold text-text-secondary">Requester & Submitted</th>
              <th className="p-3 font-semibold text-text-secondary">Window / Status</th>
              <th className="p-3 font-semibold text-text-secondary text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-subtle">
            {requests.map((item) => {
              const isPending = item.rollbackStatus === "requested";
              const isCompleted = item.rollbackStatus === "completed" || item.status === "rolled_back";

              return (
                <tr
                  key={item.id}
                  className="hover:bg-surface-hover transition-colors cursor-pointer"
                  onClick={() => setSelectedDetailItem(item)}
                >
                  {/* Batch # */}
                  <td className="p-3">
                    <div className="flex items-center gap-2">
                      <div className="p-1.5 rounded-lg bg-surface-muted border border-border-default text-text-secondary">
                        <FileSpreadsheet className="h-4 w-4" />
                      </div>
                      <div>
                        <p className="font-mono font-bold text-text-primary">
                          #{item.id.slice(0, 8)}
                        </p>
                        <p className="text-[10px] text-text-muted">
                          {item.totalRows ?? 0} rows
                        </p>
                      </div>
                    </div>
                  </td>

                  {/* Module */}
                  <td className="p-3">
                    <span
                      className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[11px] font-semibold border ${
                        item.batchType === "plantilla"
                          ? "bg-brand-subtle text-text-brand-bold border-border-brand/40"
                          : "bg-surface-muted text-text-secondary border-border-subtle"
                      }`}
                    >
                      {item.batchType === "plantilla" ? "Plantilla" : "Vacancy"}
                    </span>
                  </td>

                  {/* File Name */}
                  <td className="p-3 max-w-[180px]">
                    <p className="font-medium text-text-primary truncate" title={item.fileName}>
                      {item.fileName}
                    </p>
                    <p className="text-[10px] text-text-muted">
                      Uploaded by {item.uploadedBy || "Unknown"}
                    </p>
                  </td>

                  {/* Scope */}
                  <td className="p-3">
                    <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-text-secondary border border-border-subtle truncate max-w-[160px]">
                      <Layers className="h-3 w-3 shrink-0 text-text-muted" />
                      <span className="truncate">
                        {item.groupName || "—"} / {item.accountName || "—"}
                      </span>
                    </span>
                  </td>

                  {/* Rollback Reason / Note */}
                  <td className="p-3 max-w-xs">
                    <div className="flex flex-col items-start gap-1">
                      {item.rollbackReasonCode && (
                        <span className="inline-block rounded bg-danger-bg text-danger-text px-1.5 py-0.5 text-[10px] font-mono font-bold border border-danger-border">
                          {item.rollbackReasonCode}
                        </span>
                      )}
                      <span
                        className="text-text-secondary text-xs leading-relaxed line-clamp-2 break-words"
                        title={item.rollbackReasonNote || item.rollbackReason || undefined}
                      >
                        {item.rollbackReasonNote || item.rollbackReason || (item.rollbackReasonCode ? null : "No note provided")}
                      </span>
                    </div>
                  </td>

                  {/* Requester & Date */}
                  <td className="p-3">
                    <div className="space-y-0.5">
                      <p className="font-medium text-text-primary flex items-center gap-1">
                        <User className="h-3 w-3 text-text-muted" />
                        <span>{item.rollbackRequestedByName || item.rollbackRequestedBy || "Admin"}</span>
                      </p>
                      <p className="text-[10px] text-text-muted flex items-center gap-1">
                        <Calendar className="h-3 w-3" />
                        <span>{formatDate(item.rollbackRequestedAt || item.uploadedAt)}</span>
                      </p>
                    </div>
                  </td>

                  {/* Window / Status */}
                  <td className="p-3">
                    {isPending ? (
                      <div className="space-y-0.5">
                        <span className="inline-flex items-center gap-1 rounded-full bg-pct-warn-bg/50 border border-pct-warn-border px-2 py-0.5 text-[11px] font-semibold text-pct-warn-text">
                          <Clock className="h-3 w-3" />
                          Requested
                        </span>
                        <p className="text-[10px] text-text-muted">
                          {formatRollbackRemaining(item.rollbackRemainingSeconds)}
                        </p>
                      </div>
                    ) : isCompleted ? (
                      <span className="inline-flex items-center gap-1 rounded-full bg-pct-good-bg/50 border border-pct-good-border px-2 py-0.5 text-[11px] font-semibold text-pct-good-text">
                        <CheckCircle2 className="h-3 w-3" />
                        Rolled Back
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 rounded-full bg-danger-bg/50 border border-danger-border px-2 py-0.5 text-[11px] font-semibold text-danger-text">
                        <XCircle className="h-3 w-3" />
                        Rejected
                      </span>
                    )}
                  </td>

                  {/* Actions */}
                  <td className="p-3 text-right" onClick={(e) => e.stopPropagation()}>
                    <div className="flex items-center justify-end gap-1.5">
                      {isPending && (
                        <>
                          <button
                            type="button"
                            onClick={() => {
                              setSelectedRejectItem(item);
                              setRejectRemarks("");
                              setErrorMessage(null);
                            }}
                            className="rounded-lg border border-danger-border/60 bg-danger-bg/30 px-2.5 py-1 text-xs font-semibold text-danger-text hover:bg-danger-bg transition cursor-pointer"
                          >
                            Reject
                          </button>
                          <button
                            type="button"
                            onClick={() => {
                              setSelectedApproveItem(item);
                              setErrorMessage(null);
                            }}
                            className="rounded-lg bg-[var(--danger-button)] hover:bg-[var(--danger-button-hover)] px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition cursor-pointer flex items-center gap-1"
                          >
                            <RotateCcw className="h-3 w-3" />
                            <span>Approve</span>
                          </button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {totalCount > 0 && onPageChange && (
        <Pagination
          page={page}
          pageSize={pageSize}
          totalCount={totalCount}
          onPageChange={onPageChange}
          onPageSizeChange={onPageSizeChange}
          limitOptions={[10, 25, 50]}
        />
      )}

      {/* DETAIL MODAL */}
      {selectedDetailItem && (
        <Modal
          isOpen={Boolean(selectedDetailItem)}
          onClose={() => setSelectedDetailItem(null)}
          title={
            <div className="flex items-center gap-2 flex-wrap">
              <span>Batch #{selectedDetailItem.id.slice(0, 8)}</span>
              <span
                className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-semibold ${
                  selectedDetailItem.rollbackStatus === "completed" ||
                  selectedDetailItem.status === "rolled_back"
                    ? "bg-danger-bg text-danger-text border border-danger-border"
                    : selectedDetailItem.rollbackStatus === "requested"
                    ? "bg-pct-warn-bg/50 text-pct-warn-text border border-pct-warn-border"
                    : "bg-surface-muted text-text-secondary border border-border-subtle"
                }`}
              >
                {selectedDetailItem.rollbackStatus
                  ? `ROLLBACK: ${selectedDetailItem.rollbackStatus.toUpperCase()}`
                  : selectedDetailItem.status.toUpperCase()}
              </span>
            </div>
          }
          subtitle={`File: ${selectedDetailItem.fileName} (${selectedDetailItem.batchType === "plantilla" ? "Plantilla Structure" : "Vacancy Roster"})`}
          icon={FileSpreadsheet}
          maxWidthClass="max-w-3xl"
        >
          <div className="space-y-4">
            {/* Meta Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
              <div className="p-2.5 rounded-lg bg-surface-muted border border-border-subtle">
                <span className="text-text-muted block">Batch Status</span>
                <span className="font-bold text-text-primary mt-0.5 block">
                  {selectedDetailItem.status}
                </span>
              </div>
              <div className="p-2.5 rounded-lg bg-surface-muted border border-border-subtle">
                <span className="text-text-muted block">Rollback Status</span>
                <span className="font-bold text-text-primary mt-0.5 block">
                  {selectedDetailItem.rollbackStatus || "None"}
                </span>
              </div>
              <div className="p-2.5 rounded-lg bg-surface-muted border border-border-subtle">
                <span className="text-text-muted block">Governance Window</span>
                <span className="font-semibold text-text-primary mt-0.5 block">
                  {formatRollbackRemaining(selectedDetailItem.rollbackRemainingSeconds)}
                </span>
              </div>
              <div className="p-2.5 rounded-lg bg-surface-muted border border-border-subtle">
                <span className="text-text-muted block">Total Rows</span>
                <span className="font-bold text-text-primary mt-0.5 block">
                  {selectedDetailItem.totalRows ?? 0} rows
                </span>
              </div>
            </div>

            {/* Scope & Requester Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
              <div className="p-2.5 rounded-lg bg-surface-muted border border-border-subtle">
                <span className="text-text-muted block">Assigned Scope</span>
                <span className="font-semibold text-text-primary mt-0.5 block truncate">
                  {selectedDetailItem.groupName || "—"} / {selectedDetailItem.accountName || "—"}
                </span>
              </div>
              <div className="p-2.5 rounded-lg bg-surface-muted border border-border-subtle">
                <span className="text-text-muted block">Uploaded By</span>
                <span className="font-semibold text-text-primary mt-0.5 block truncate">
                  {selectedDetailItem.uploadedBy || "Unknown"}
                  {selectedDetailItem.uploadedAt && (
                    <span className="text-text-muted font-normal ml-1">
                      ({formatDate(selectedDetailItem.uploadedAt)})
                    </span>
                  )}
                </span>
              </div>
            </div>

            {/* Rollback Details Card */}
            {(selectedDetailItem.rollbackReasonCode ||
              selectedDetailItem.rollbackReasonNote ||
              selectedDetailItem.rollbackReason) && (
              <div className="rounded-lg border border-border-default bg-surface-muted p-3 text-xs space-y-1.5">
                <div className="flex items-center justify-between">
                  <span className="font-bold text-text-primary">Rollback Justification:</span>
                  {selectedDetailItem.rollbackReasonCode && (
                    <span className="rounded bg-danger-bg text-danger-text px-1.5 py-0.5 text-[10px] font-mono font-bold border border-danger-border">
                      {selectedDetailItem.rollbackReasonCode}
                    </span>
                  )}
                </div>
                <p className="text-text-secondary leading-relaxed">
                  {selectedDetailItem.rollbackReasonNote || selectedDetailItem.rollbackReason}
                </p>
                {selectedDetailItem.rollbackRequestedBy && (
                  <p className="text-[11px] text-text-muted pt-1">
                    Requested by <strong className="text-text-primary">{selectedDetailItem.rollbackRequestedByName || selectedDetailItem.rollbackRequestedBy}</strong> on {formatDate(selectedDetailItem.rollbackRequestedAt)}
                  </p>
                )}
              </div>
            )}

            {/* Block Warnings if any */}
            {selectedDetailItem.rollbackBlockReason && (
              <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text flex items-start gap-2 font-medium">
                <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
                <div>
                  <span className="font-bold">Rollback Block Notice: </span>
                  <span>{selectedDetailItem.rollbackBlockReason}</span>
                </div>
              </div>
            )}

            {/* Modal Actions */}
            {selectedDetailItem.rollbackStatus === "requested" && (
              <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-subtle">
                <button
                  type="button"
                  onClick={() => {
                    setSelectedRejectItem(selectedDetailItem);
                    setRejectRemarks("");
                    setErrorMessage(null);
                  }}
                  className="rounded-lg border border-danger-border/60 bg-danger-bg/30 px-3 py-1.5 text-xs font-semibold text-danger-text hover:bg-danger-bg transition cursor-pointer"
                >
                  Reject Request
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedApproveItem(selectedDetailItem);
                    setErrorMessage(null);
                  }}
                  className="rounded-lg bg-[var(--danger-button)] hover:bg-[var(--danger-button-hover)] px-3.5 py-1.5 text-xs font-semibold text-white shadow-2xs transition cursor-pointer flex items-center gap-1.5"
                >
                  <RotateCcw className="h-3.5 w-3.5" />
                  <span>Approve & Execute Rollback</span>
                </button>
              </div>
            )}
          </div>
        </Modal>
      )}

      {/* APPROVE CONFIRMATION MODAL */}
      {selectedApproveItem && (
        <Modal
          isOpen={Boolean(selectedApproveItem)}
          onClose={() => setSelectedApproveItem(null)}
          title="Approve & Execute Rollback"
          subtitle={`Batch #${selectedApproveItem.id.slice(0, 8)} (${selectedApproveItem.fileName})`}
          icon={RotateCcw}
          maxWidthClass="max-w-md"
          isSubmitting={approveMutation.isPending}
          footer={
            <div className="flex items-center justify-end gap-2.5 w-full">
              <button
                type="button"
                onClick={() => setSelectedApproveItem(null)}
                disabled={approveMutation.isPending}
                className="rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleApprove}
                disabled={approveMutation.isPending}
                className="inline-flex items-center justify-center gap-1.5 rounded-lg bg-[var(--danger-button)] hover:bg-[var(--danger-button-hover)] px-4 py-2 text-xs font-semibold text-white shadow-2xs transition cursor-pointer"
              >
                {approveMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                <span>{approveMutation.isPending ? "Executing..." : "Confirm & Execute Rollback"}</span>
              </button>
            </div>
          }
        >
          <div className="space-y-3">
            {errorMessage && (
              <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text">
                {errorMessage}
              </div>
            )}
            <p className="text-xs text-text-secondary leading-relaxed">
              Are you sure you want to approve and execute rollback for batch <strong className="text-text-primary">#{selectedApproveItem.id.slice(0, 8)}</strong> ({selectedApproveItem.batchType === "plantilla" ? "Plantilla Structure" : "Vacancy Roster"})?
            </p>
            <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text space-y-1">
              <p className="font-semibold flex items-center gap-1.5">
                <AlertTriangle className="h-4 w-4 shrink-0" />
                <span>Irreversible Operation</span>
              </p>
              <p>
                This will immediately restore snapshot baselines and deactivate or expunge imported rows committed by this batch.
              </p>
            </div>
          </div>
        </Modal>
      )}

      {/* REJECT CONFIRMATION MODAL */}
      {selectedRejectItem && (
        <Modal
          isOpen={Boolean(selectedRejectItem)}
          onClose={() => setSelectedRejectItem(null)}
          title="Reject Rollback Request"
          subtitle={`Batch #${selectedRejectItem.id.slice(0, 8)} (${selectedRejectItem.fileName})`}
          icon={XCircle}
          maxWidthClass="max-w-md"
          isSubmitting={rejectMutation.isPending}
          footer={
            <div className="flex items-center justify-end gap-2.5 w-full">
              <button
                type="button"
                onClick={() => setSelectedRejectItem(null)}
                disabled={rejectMutation.isPending}
                className="rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleReject}
                disabled={rejectMutation.isPending}
                className="inline-flex items-center justify-center gap-1.5 rounded-lg border border-danger-border bg-danger-bg px-4 py-2 text-xs font-semibold text-danger-text hover:bg-danger-border/30 transition cursor-pointer"
              >
                {rejectMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                <span>{rejectMutation.isPending ? "Rejecting..." : "Confirm Rejection"}</span>
              </button>
            </div>
          }
        >
          <div className="space-y-3">
            {errorMessage && (
              <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text">
                {errorMessage}
              </div>
            )}
            <p className="text-xs text-text-secondary leading-relaxed">
              Please specify the administrative justification for rejecting this rollback request:
            </p>
            <div>
              <textarea
                value={rejectRemarks}
                onChange={(e) => setRejectRemarks(e.target.value)}
                placeholder="Enter rejection reason (required)..."
                rows={3}
                className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:border-border-brand focus:outline-none"
              />
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
