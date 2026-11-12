"use client";

import { useState } from "react";
import {
  Archive,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  Loader2,
  Building,
  User,
  Calendar,
  Layers,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { TablePagination } from "@/components/shared/TablePagination";
import {
  useApproveAccountArchive,
  useRejectAccountArchive,
  type AccountArchiveItem,
  type ApprovalStatusTab,
} from "@/lib/queries/requests";

interface AccountArchiveDataTableProps {
  requests: AccountArchiveItem[];
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

export function AccountArchiveDataTable({
  requests,
  tab,
  page = 1,
  pageSize = 10,
  totalCount = requests.length,
  onPageChange,
  onPageSizeChange,
}: AccountArchiveDataTableProps) {
  const [selectedApproveItem, setSelectedApproveItem] = useState<AccountArchiveItem | null>(null);
  const [selectedRejectItem, setSelectedRejectItem] = useState<AccountArchiveItem | null>(null);
  const [rejectRemarks, setRejectRemarks] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const approveMutation = useApproveAccountArchive();
  const rejectMutation = useRejectAccountArchive();

  const handleApprove = async () => {
    if (!selectedApproveItem) return;
    setErrorMessage(null);
    try {
      await approveMutation.mutateAsync({
        notificationId: selectedApproveItem.id,
        accountId: selectedApproveItem.accountId,
        accountName: selectedApproveItem.accountName,
      });
      setSelectedApproveItem(null);
    } catch (err: unknown) {
      setErrorMessage(err instanceof Error ? err.message : "Failed to approve archive request.");
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
        notificationId: selectedRejectItem.id,
        accountId: selectedRejectItem.accountId,
        accountName: selectedRejectItem.accountName,
        remarks: rejectRemarks.trim(),
      });
      setSelectedRejectItem(null);
      setRejectRemarks("");
    } catch (err: unknown) {
      setErrorMessage(err instanceof Error ? err.message : "Failed to reject archive request.");
    }
  };

  return (
    <div className="flex flex-col flex-1 min-h-0 bg-surface-base rounded-xl border border-border-default overflow-hidden">
      <div className="overflow-x-auto flex-1 min-h-0">
        <table className="w-full text-left text-xs border-collapse">
          <thead className="sticky top-0 bg-surface-muted border-b border-border-subtle z-10">
            <tr>
              <th className="p-3 font-semibold text-text-secondary">Billing Account</th>
              <th className="p-3 font-semibold text-text-secondary">Assigned Group</th>
              <th className="p-3 font-semibold text-text-secondary">Headcount Impact</th>
              <th className="p-3 font-semibold text-text-secondary">Requester & Submitted</th>
              <th className="p-3 font-semibold text-text-secondary">Justification Remarks</th>
              <th className="p-3 font-semibold text-text-secondary">Status</th>
              {tab === "pending" && (
                <th className="p-3 font-semibold text-text-secondary text-right">Actions</th>
              )}
            </tr>
          </thead>
          <tbody className="divide-y divide-border-subtle">
            {requests.map((item) => (
              <tr key={item.id} className="hover:bg-surface-hover transition-colors">
                {/* Billing Account */}
                <td className="p-3">
                  <div className="flex items-center gap-2">
                    <div className="p-1.5 rounded-lg bg-surface-muted border border-border-default text-text-secondary">
                      <Building className="h-4 w-4" />
                    </div>
                    <div>
                      <p className="font-bold text-text-primary">{item.accountName}</p>
                      {item.accountCode && (
                        <p className="text-[10px] font-mono text-text-muted">{item.accountCode}</p>
                      )}
                    </div>
                  </div>
                </td>

                {/* Assigned Group */}
                <td className="p-3">
                  <span className="inline-flex items-center gap-1 rounded-md bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-text-secondary border border-border-subtle">
                    <Layers className="h-3 w-3 text-text-muted" />
                    <span>{item.groupName || "Unassigned Group"}</span>
                  </span>
                </td>

                {/* Headcount Impact */}
                <td className="p-3">
                  <div className="flex items-center gap-2 text-xs">
                    <span className="font-semibold text-text-primary">
                      {item.activeHeadcount} Active
                    </span>
                    <span className="text-text-muted">•</span>
                    <span className="text-text-secondary">{item.vacantHeadcount} Vacant</span>
                  </div>
                  {item.activeHeadcount > 0 && (
                    <p className="text-[10px] text-pct-warn-text mt-0.5 flex items-center gap-1">
                      <AlertTriangle className="h-3 w-3 shrink-0" />
                      <span>Has active deployed roster</span>
                    </p>
                  )}
                </td>

                {/* Requester & Date */}
                <td className="p-3">
                  <div className="space-y-0.5">
                    <p className="font-medium text-text-primary flex items-center gap-1">
                      <User className="h-3 w-3 text-text-muted" />
                      <span>{item.requestedBy}</span>
                    </p>
                    <p className="text-[10px] text-text-muted flex items-center gap-1">
                      <Calendar className="h-3 w-3" />
                      <span>{formatDate(item.requestedAt)}</span>
                    </p>
                  </div>
                </td>

                {/* Remarks */}
                <td className="p-3 max-w-xs">
                  <p className="line-clamp-2 text-text-secondary text-xs leading-relaxed" title={item.remarks}>
                    {item.remarks}
                  </p>
                  {item.reviewerRemarks && (
                    <p className="mt-1 text-[11px] text-danger-text italic">
                      Reviewer Note: {item.reviewerRemarks}
                    </p>
                  )}
                </td>

                {/* Status Badge */}
                <td className="p-3">
                  {item.status === "pending" ? (
                    <span className="inline-flex items-center gap-1 rounded-full bg-pct-warn-bg/50 border border-pct-warn-border px-2 py-0.5 text-[11px] font-semibold text-pct-warn-text">
                      Pending SA
                    </span>
                  ) : item.status === "approved" ? (
                    <span className="inline-flex items-center gap-1 rounded-full bg-pct-good-bg/50 border border-pct-good-border px-2 py-0.5 text-[11px] font-semibold text-pct-good-text">
                      <CheckCircle2 className="h-3 w-3" />
                      Archived
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1 rounded-full bg-danger-bg/50 border border-danger-border px-2 py-0.5 text-[11px] font-semibold text-danger-text">
                      <XCircle className="h-3 w-3" />
                      Rejected
                    </span>
                  )}
                </td>

                {/* Actions (Only in Pending tab) */}
                {tab === "pending" && (
                  <td className="p-3 text-right">
                    <div className="flex items-center justify-end gap-1.5">
                      <button
                        type="button"
                        onClick={() => setSelectedRejectItem(item)}
                        className="rounded-lg border border-danger-border/60 bg-danger-bg/30 px-2.5 py-1 text-xs font-semibold text-danger-text hover:bg-danger-bg transition cursor-pointer"
                      >
                        Reject
                      </button>
                      <button
                        type="button"
                        onClick={() => setSelectedApproveItem(item)}
                        className="rounded-lg bg-brand-button px-2.5 py-1 text-xs font-semibold text-white shadow-2xs hover:bg-brand-button-hover transition cursor-pointer"
                      >
                        Approve
                      </button>
                    </div>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {totalCount > pageSize && onPageChange && onPageSizeChange && (
        <TablePagination
          page={page}
          totalCount={totalCount}
          pageSize={pageSize}
          onPageChange={onPageChange}
          onPageSizeChange={onPageSizeChange}
        />
      )}

      {/* Approve Confirmation Modal */}
      {selectedApproveItem && (
        <Modal
          isOpen={Boolean(selectedApproveItem)}
          onClose={() => setSelectedApproveItem(null)}
          title="Approve Account Archive"
          subtitle={`Account: ${selectedApproveItem.accountName}`}
          icon={Archive}
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
                className="inline-flex items-center justify-center gap-1.5 rounded-lg bg-danger-bg border border-danger-border px-4 py-2 text-xs font-semibold text-danger-text hover:bg-danger-border/30 transition cursor-pointer"
              >
                {approveMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                <span>{approveMutation.isPending ? "Archiving..." : "Confirm & Archive Account"}</span>
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
              Are you sure you want to approve archiving <strong className="text-text-primary">{selectedApproveItem.accountName}</strong>? This action marks the account as inactive in the database and updates Plantilla visibility.
            </p>
            {selectedApproveItem.activeHeadcount > 0 && (
              <div className="rounded-lg border border-pct-warn-border bg-pct-warn-bg/30 p-3 text-xs space-y-1">
                <p className="font-semibold text-pct-warn-text flex items-center gap-1.5">
                  <AlertTriangle className="h-4 w-4 shrink-0" />
                  <span>Warning: Active Personnel Remaining</span>
                </p>
                <p className="text-text-secondary">
                  This account still has {selectedApproveItem.activeHeadcount} active personnel assigned. They will remain linked until absorbed or separated.
                </p>
              </div>
            )}
            <div className="rounded-lg border border-border-subtle bg-surface-muted p-3 text-xs">
              <p className="text-[11px] font-semibold text-text-muted uppercase">Requester Justification:</p>
              <p className="mt-1 text-text-primary italic">&ldquo;{selectedApproveItem.remarks}&rdquo;</p>
            </div>
          </div>
        </Modal>
      )}

      {/* Reject Confirmation Modal */}
      {selectedRejectItem && (
        <Modal
          isOpen={Boolean(selectedRejectItem)}
          onClose={() => {
            setSelectedRejectItem(null);
            setRejectRemarks("");
          }}
          title="Reject Archive Request"
          subtitle={`Account: ${selectedRejectItem.accountName}`}
          icon={XCircle}
          maxWidthClass="max-w-md"
          isSubmitting={rejectMutation.isPending}
          footer={
            <div className="flex items-center justify-end gap-2.5 w-full">
              <button
                type="button"
                onClick={() => {
                  setSelectedRejectItem(null);
                  setRejectRemarks("");
                }}
                disabled={rejectMutation.isPending}
                className="rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleReject}
                disabled={rejectMutation.isPending || !rejectRemarks.trim()}
                className="inline-flex items-center justify-center gap-1.5 rounded-lg bg-danger-bg border border-danger-border px-4 py-2 text-xs font-semibold text-danger-text hover:bg-danger-border/30 transition cursor-pointer disabled:opacity-50"
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
              Rejecting this request will keep <strong className="text-text-primary">{selectedRejectItem.accountName}</strong> active and remove it from the pending archive queue.
            </p>
            <div>
              <label className="block text-xs font-semibold text-text-primary mb-1">
                Rejection Reason <span className="text-danger-text">*</span>
              </label>
              <textarea
                required
                rows={3}
                placeholder="Provide a reason for rejecting the archive request..."
                value={rejectRemarks}
                onChange={(e) => setRejectRemarks(e.target.value)}
                disabled={rejectMutation.isPending}
                className="w-full rounded-lg border border-border-default bg-surface-base p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none transition-colors"
              />
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
