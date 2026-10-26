"use client";

import React, { useEffect, useMemo, useState } from "react";
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  FileSpreadsheet,
  Loader2,
  Search,
} from "lucide-react";
import {
  type HrEmplocImportBatch,
  useBatchRows,
  useApproveImportBatch,
} from "@/lib/queries/hr_emploc_import";
import { RejectBatchModal } from "./RejectBatchModal";
import { Modal } from "@/components/shared/Modal";

interface BatchDetailsModalProps {
  isOpen: boolean;
  onClose: () => void;
  batch: HrEmplocImportBatch | null;
  canAct: boolean;
  onRefresh?: () => void;
}

export function BatchDetailsModal({
  isOpen,
  onClose,
  batch,
  canAct,
  onRefresh,
}: BatchDetailsModalProps) {
  const [filterMode, setFilterMode] = useState<"all" | "valid" | "blocked">("all");
  const [search, setSearch] = useState("");
  const [isRejectOpen, setIsRejectOpen] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const { data: summary, isLoading, error: rowsError } = useBatchRows(
    batch?.id ?? null,
  );
  const approveMutation = useApproveImportBatch();

  const filteredRows = useMemo(() => {
    if (!summary?.rows) return [];
    let list = summary.rows;

    if (filterMode === "valid") {
      list = list.filter((r) => r.validationStatus === "valid");
    } else if (filterMode === "blocked") {
      list = list.filter((r) => r.validationStatus === "blocked");
    }

    if (search.trim()) {
      const q = search.toLowerCase();
      list = list.filter(
        (r) =>
          r.displayName.toLowerCase().includes(q) ||
          (r.vcode && r.vcode.toLowerCase().includes(q)) ||
          (r.accountName && r.accountName.toLowerCase().includes(q)) ||
          (r.storeName && r.storeName.toLowerCase().includes(q)),
      );
    }

    return list;
  }, [summary, filterMode, search]);

  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (approveMutation.isPending || isRejectOpen) return;
        onClose();
      }
    };
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, approveMutation.isPending, isRejectOpen, onClose]);

  if (!isOpen || !batch) return null;

  async function handleApprove() {
    if (!batch) return;
    const validCount = summary?.validRows ?? batch.validRows;
    const blockedCount = summary?.blockedRows ?? batch.blockedRows;

    const confirmMsg =
      blockedCount > 0
        ? `Approve this import batch? This will create ${validCount} HR Emploc record(s). ${blockedCount} blocked row(s) will be excluded.`
        : `Approve this import batch and create ${validCount} HR Emploc record(s)?`;

    if (!window.confirm(confirmMsg)) return;

    setActionError(null);
    try {
      await approveMutation.mutateAsync({ batchId: batch.id });
      onRefresh?.();
      onClose();
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : "Failed to approve import batch",
      );
    }
  }

  const isPending = batch.status === "pending_approval";

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title={
          <span className="flex items-center gap-2">
            <span>{batch.fileName}</span>
            <span className="inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold border border-border-default bg-surface-muted text-text-primary font-mono">
              {batch.status.replace("_", " ").toUpperCase()}
            </span>
          </span>
        }
        subtitle={`Group: ${batch.groupName || "—"} • Submitted by ${batch.uploadedByName || "Encoder"} on ${
          batch.uploadedAt ? new Date(batch.uploadedAt).toLocaleDateString() : "—"
        }`}
        icon={FileSpreadsheet}
        maxWidthClass="max-w-5xl"
        disableBackdropClick={approveMutation.isPending}
        isSubmitting={approveMutation.isPending}
        isDirty={isRejectOpen || approveMutation.isPending}
      >
        <div className="flex flex-col h-[75vh] overflow-hidden">

        {/* Action Error Banner */}
        {actionError && (
          <div className="px-6 py-2.5 bg-[var(--danger-bg)] border-b border-[var(--danger-border)] text-xs text-[var(--danger-text)] flex items-center justify-between">
            <span>{actionError}</span>
            <button
              className="text-[var(--danger-text)] hover:opacity-80 cursor-pointer font-semibold"
              onClick={() => setActionError(null)}
              type="button"
            >
              Dismiss
            </button>
          </div>
        )}

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-4 text-xs">
          {/* KPI metrics bar: row counts are neutral */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="rounded-xl border border-border-default bg-surface-muted/50 p-3.5 shadow-2xs">
              <p className="text-[11px] font-medium text-text-muted uppercase tracking-wider">
                Total Rows
              </p>
              <p className="mt-1 text-2xl font-bold text-text-primary">
                {summary?.totalRows ?? batch.totalRows}
              </p>
            </div>
            <div className="rounded-xl border border-border-default bg-surface-muted/50 p-3.5 shadow-2xs">
              <p className="text-[11px] font-medium text-text-muted uppercase tracking-wider">
                Ready to Import
              </p>
              <p className="mt-1 text-2xl font-bold text-text-primary">
                {summary?.validRows ?? batch.validRows}
              </p>
            </div>
            <div className="rounded-xl border border-border-default bg-surface-muted/50 p-3.5 shadow-2xs">
              <p className="text-[11px] font-medium text-text-muted uppercase tracking-wider">
                Blocked Rows
              </p>
              <p className="mt-1 text-2xl font-bold text-text-primary">
                {summary?.blockedRows ?? batch.blockedRows}
              </p>
            </div>
            <div className="rounded-xl border border-border-default bg-surface-muted/50 p-3.5 shadow-2xs">
              <p className="text-[11px] font-medium text-text-muted uppercase tracking-wider">
                Duplicates
              </p>
              <p className="mt-1 text-2xl font-bold text-text-primary">
                {summary?.duplicateRows ?? batch.duplicateRows}
              </p>
            </div>
          </div>

          {/* Blocked errors summary breakdown if any */}
          {summary && summary.blockedRows > 0 && (
            <div className="rounded-xl border border-border-default bg-surface-muted p-4">
              <div className="flex items-start gap-2.5">
                <AlertTriangle className="h-5 w-5 text-text-muted mt-0.5 shrink-0" />
                <div className="flex-1">
                  <h4 className="text-xs font-bold text-text-primary">
                    {summary.blockedRows} Row(s) Blocked by Slot / Validation Checks
                  </h4>
                  <p className="mt-0.5 text-xs text-text-muted">
                    Blocked rows will not be imported into HR Emploc upon approval:
                  </p>
                  <ul className="mt-2 space-y-1 text-xs text-text-primary">
                    {Object.entries(summary.errorsByReason).map(([reason, rows]) => (
                      <li key={reason} className="flex items-center gap-2">
                        <span className="inline-flex items-center justify-center rounded-full bg-surface border border-border-default px-1.5 py-0.2 text-[10px] font-bold text-text-primary">
                          {rows.length}x
                        </span>
                        <span>{reason}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            </div>
          )}

          {/* Toolbar: filter tabs + search */}
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between pt-2">
            <div className="inline-flex rounded-lg border border-border-default bg-surface-muted p-0.5">
              <button
                className={`rounded-md px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
                  filterMode === "all"
                    ? "bg-surface text-text-primary shadow-2xs"
                    : "text-text-muted hover:text-text-primary"
                }`}
                onClick={() => setFilterMode("all")}
                type="button"
              >
                All Rows ({summary?.totalRows ?? batch.totalRows})
              </button>
              <button
                className={`rounded-md px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
                  filterMode === "valid"
                    ? "bg-surface text-text-primary shadow-2xs"
                    : "text-text-muted hover:text-text-primary"
                }`}
                onClick={() => setFilterMode("valid")}
                type="button"
              >
                Valid ({summary?.validRows ?? batch.validRows})
              </button>
              <button
                className={`rounded-md px-3 py-1.5 text-xs font-semibold transition cursor-pointer ${
                  filterMode === "blocked"
                    ? "bg-surface text-text-primary shadow-2xs"
                    : "text-text-muted hover:text-text-primary"
                }`}
                onClick={() => setFilterMode("blocked")}
                type="button"
              >
                Blocked ({summary?.blockedRows ?? batch.blockedRows})
              </button>
            </div>

            <div className="relative w-full sm:w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
              <input
                className="w-full rounded-lg border border-border-default bg-surface pl-8 pr-3 py-1.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden focus:ring-1 focus:ring-brand-primary"
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search candidate, VCode..."
                type="text"
                value={search}
              />
            </div>
          </div>

          {/* Staged Rows Table */}
          {isLoading ? (
            <div className="flex h-48 items-center justify-center">
              <Loader2 className="h-6 w-6 animate-spin text-brand-primary" />
            </div>
          ) : rowsError ? (
            <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-4 text-xs text-[var(--danger-text)]">
              Failed to load batch rows: {(rowsError as Error).message}
            </div>
          ) : filteredRows.length === 0 ? (
            <div className="flex h-36 flex-col items-center justify-center rounded-xl border border-dashed border-border-default text-center">
              <p className="text-xs text-text-muted">No rows match the active filter.</p>
            </div>
          ) : (
            <div className="rounded-xl border border-border-default overflow-hidden shadow-2xs">
              <div className="max-h-[380px] overflow-y-auto">
                <table className="w-full border-collapse text-left text-sm">
                  <thead className="sticky top-0 bg-surface-muted text-text-muted border-b border-border-default text-xs font-semibold z-10">
                    <tr>
                      <th className="py-2.5 px-3">#</th>
                      <th className="py-2.5 px-3">Status</th>
                      <th className="py-2.5 px-3">Candidate Name</th>
                      <th className="py-2.5 px-3">VCode</th>
                      <th className="py-2.5 px-3">Store Name</th>
                      <th className="py-2.5 px-3">Position</th>
                      <th className="py-2.5 px-3">Account</th>
                      <th className="py-2.5 px-3">Hired Date</th>
                      <th className="py-2.5 px-3">Reconciliation / Errors</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-subtle bg-surface">
                    {filteredRows.map((row) => {
                      const isValid = row.validationStatus === "valid";
                      return (
                        <tr
                          key={row.id}
                          className={`hover:bg-surface-hover transition ${
                            !isValid ? "bg-[var(--danger-bg)]/20" : ""
                          }`}
                        >
                          <td className="py-2 px-3 font-mono text-sm text-text-muted">
                            {row.rowNumber}
                          </td>
                          <td className="py-2 px-3">
                            <span
                              className="inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-semibold border border-border-default bg-surface text-text-primary"
                            >
                              {isValid ? (
                                <CheckCircle2 className="h-3 w-3 text-text-primary" />
                              ) : (
                                <AlertCircle className="h-3 w-3 text-[var(--danger-text)]" />
                              )}
                              {isValid ? "VALID" : "BLOCKED"}
                            </span>
                          </td>
                          <td className="py-2 px-3 font-semibold text-text-primary">
                            {row.displayName}
                          </td>
                          <td className="py-2 px-3 font-mono text-text-primary">
                            {row.vcode || "—"}
                          </td>
                          <td className="py-2 px-3 text-text-primary">
                            {row.storeName || "—"}
                          </td>
                          <td className="py-2 px-3 text-text-muted">
                            {row.positionName || "—"}
                          </td>
                          <td className="py-2 px-3 text-text-muted">
                            {row.accountName || "—"}
                          </td>
                          <td className="py-2 px-3 text-text-muted">
                            {row.dateHired || "—"}
                          </td>
                          <td className="py-2 px-3 max-w-xs text-sm">
                            {isValid ? (
                              <span className="text-text-muted">
                                Slot reserved in Plantilla
                              </span>
                            ) : (
                              <div className="space-y-0.5">
                                {row.validationErrors.map((err, idx) => (
                                  <p
                                    key={idx}
                                    className="text-[11px] text-[var(--danger-text)] leading-tight"
                                  >
                                    • {err.msg}
                                  </p>
                                ))}
                              </div>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>

        {/* Footer Actions (HA / SA Decision Gate) */}
        <div className="flex items-center justify-between border-t border-border-subtle px-6 py-4 bg-surface-muted/30">
          <div>
            {!canAct && isPending && (
              <p className="text-xs text-text-muted">
                Viewing in read-only mode. Head Admin or Super Admin role is required to approve or reject.
              </p>
            )}
          </div>

          <div className="flex items-center gap-3">
            <button
              className="rounded-lg border border-border-default bg-surface px-4 py-2 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer"
              onClick={onClose}
              type="button"
            >
              Close
            </button>

            {canAct && isPending && (
              <>
                <button
                  className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] px-4 py-2 text-xs font-semibold text-[var(--danger-text)] hover:opacity-90 transition cursor-pointer"
                  disabled={approveMutation.isPending}
                  onClick={() => setIsRejectOpen(true)}
                  type="button"
                >
                  Reject Batch
                </button>

                <button
                  className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-5 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-primary-hover transition disabled:opacity-50 cursor-pointer"
                  disabled={
                    approveMutation.isPending || (summary?.validRows ?? batch.validRows) === 0
                  }
                  onClick={handleApprove}
                  type="button"
                >
                  {approveMutation.isPending ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      <span>Approving...</span>
                    </>
                  ) : (
                    <span>
                      Approve & Create {summary?.validRows ?? batch.validRows} Record(s)
                    </span>
                  )}
                </button>
              </>
            )}
          </div>
        </div>
        </div>
      </Modal>

      <RejectBatchModal
        fileName={batch.fileName}
        isOpen={isRejectOpen}
        onClose={() => setIsRejectOpen(false)}
        onConfirm={async (reasonCode, reasonNote) => {
          const { rejectImportBatch } = await import("@/lib/queries/hr_emploc_import");
          await rejectImportBatch(batch.id, reasonCode, reasonNote);
          onRefresh?.();
          onClose();
        }}
      />
    </>
  );
}
