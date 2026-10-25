"use client";

import React, { useMemo, useState } from "react";
import {
  FileSpreadsheet,
  History,
  Loader2,
  RefreshCw,
  Search,
  Undo2,
} from "lucide-react";
import {
  type HrEmplocImportBatch,
  useImportBatches,
  useRollbackImportBatch,
} from "@/lib/queries/hr_emploc_import";
import { BatchDetailsModal } from "./BatchDetailsModal";
import { RollbackBatchModal } from "./RollbackBatchModal";

interface HistoryTabProps {
  canAct: boolean;
}

export function HistoryTab({ canAct }: HistoryTabProps) {
  const [search, setSearch] = useState("");
  const [selectedBatch, setSelectedBatch] = useState<HrEmplocImportBatch | null>(
    null,
  );
  const [rollingBackBatch, setRollingBackBatch] =
    useState<HrEmplocImportBatch | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const { data: batches = [], isLoading, refetch, isFetching } = useImportBatches();
  const rollbackMutation = useRollbackImportBatch();

  const historyBatches = useMemo(() => {
    return batches.filter((b) => b.status !== "pending_approval");
  }, [batches]);

  const filteredBatches = useMemo(() => {
    if (!search.trim()) return historyBatches;
    const q = search.toLowerCase();
    return historyBatches.filter(
      (b) =>
        b.fileName.toLowerCase().includes(q) ||
        (b.groupName && b.groupName.toLowerCase().includes(q)) ||
        (b.uploadedByName && b.uploadedByName.toLowerCase().includes(q)) ||
        (b.approvedByName && b.approvedByName.toLowerCase().includes(q)) ||
        (b.rejectedByName && b.rejectedByName.toLowerCase().includes(q)),
    );
  }, [historyBatches, search]);

  return (
    <div className="space-y-4 text-xs">
      {/* Search and refresh toolbar */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative w-full sm:w-72">
          <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
          <input
            className="w-full rounded-lg border border-border-default bg-surface pl-8 pr-3 py-1.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden focus:ring-1 focus:ring-brand-primary shadow-2xs"
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search processed batches..."
            type="text"
            value={search}
          />
        </div>

        <button
          className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition shadow-2xs self-start sm:self-auto cursor-pointer"
          disabled={isFetching}
          onClick={() => void refetch()}
          type="button"
        >
          <RefreshCw className={`h-3.5 w-3.5 ${isFetching ? "animate-spin" : ""}`} />
          <span>Refresh History</span>
        </button>
      </div>

      {actionError && (
        <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] flex items-center justify-between">
          <span>{actionError}</span>
          <button
            className="text-[var(--danger-text)] hover:opacity-80 font-semibold cursor-pointer"
            onClick={() => setActionError(null)}
            type="button"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* History List */}
      {isLoading ? (
        <div className="flex h-56 flex-col items-center justify-center gap-2">
          <Loader2 className="h-6 w-6 animate-spin text-brand-primary" />
          <p className="text-xs text-text-muted">Loading import history...</p>
        </div>
      ) : filteredBatches.length === 0 ? (
        <div className="flex h-56 flex-col items-center justify-center rounded-xl border border-dashed border-border-default bg-surface text-center p-6">
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-muted text-text-muted mb-2 border border-border-subtle">
            <History className="h-6 w-6" />
          </div>
          <h4 className="text-sm font-bold text-text-primary">No Import History</h4>
          <p className="mt-1 text-xs text-text-muted max-w-sm">
            {search
              ? "No history records match your search criteria."
              : "Processed batches (Approved, Rejected, Rolled Back) will appear here for audit traceability."}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {filteredBatches.map((batch) => {
            const isApproved = batch.status === "approved";
            const isRejected = batch.status === "rejected";
            const isRolledBack = batch.status === "rolled_back";

            return (
              <div
                key={batch.id}
                className="flex flex-col gap-4 rounded-xl border border-border-default bg-surface p-4.5 shadow-xs transition hover:border-border-strong md:flex-row md:items-center md:justify-between"
              >
                <div className="flex items-start gap-3.5">
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-surface-muted text-brand-primary shrink-0 mt-0.5 border border-border-subtle">
                    <FileSpreadsheet className="h-5 w-5" />
                  </div>
                  <div className="space-y-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <h4 className="text-sm font-bold text-text-primary">{batch.fileName}</h4>
                      <span
                        className="inline-flex items-center rounded-full border border-border-default bg-surface-muted px-2.5 py-0.5 text-[10px] font-bold text-text-primary font-mono"
                      >
                        {batch.status.replace("_", " ").toUpperCase()}
                      </span>
                    </div>

                    <p className="text-xs text-text-muted">
                      Group: <span className="font-semibold text-text-primary">{batch.groupName || "—"}</span>
                      {" • "}Uploaded by {batch.uploadedByName || "Encoder"} on{" "}
                      {batch.uploadedAt ? new Date(batch.uploadedAt).toLocaleString() : "—"}
                    </p>

                    {/* Status specific audit detail */}
                    <div className="text-xs text-text-muted pt-0.5 space-y-0.5">
                      {isApproved && (
                        <p className="text-text-primary font-medium">
                          ✓ {batch.createdRows} record(s) created • Approved by{" "}
                          <span className="font-semibold text-text-primary">{batch.approvedByName || "Admin"}</span>
                          {batch.approvedAt && ` on ${new Date(batch.approvedAt).toLocaleString()}`}
                        </p>
                      )}

                      {isRejected && (
                        <p className="text-[var(--danger-text)]">
                          ✕ Rejected by{" "}
                          <span className="font-semibold">{batch.rejectedByName || "Admin"}</span>
                          {" • Reason: "}{batch.rejectionReasonCode || "—"}
                          {batch.rejectionReasonNote && ` (${batch.rejectionReasonNote})`}
                        </p>
                      )}

                      {isRolledBack && (
                        <p className="text-text-primary">
                          ↺ Rolled back by{" "}
                          <span className="font-semibold">{batch.rolledBackByName || "Admin"}</span>
                          {batch.rolledBackAt && ` on ${new Date(batch.rolledBackAt).toLocaleString()}`}
                          {batch.rollbackReason && ` • Reason: "${batch.rollbackReason}"`}
                        </p>
                      )}
                    </div>
                  </div>
                </div>

                {/* Actions */}
                <div className="flex flex-wrap items-center gap-2 border-t border-border-subtle pt-3 md:border-t-0 md:pt-0">
                  <button
                    className="rounded-lg border border-border-default bg-surface px-3.5 py-2 text-xs font-semibold text-text-primary hover:bg-surface-hover transition shadow-2xs cursor-pointer"
                    onClick={() => setSelectedBatch(batch)}
                    type="button"
                  >
                    View Batch Rows
                  </button>

                  {/* Rollback button: approved batches only for Head Admin / Super Admin */}
                  {isApproved && canAct && (
                    <button
                      className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] px-3.5 py-2 text-xs font-semibold text-[var(--danger-text)] hover:opacity-90 transition shadow-2xs cursor-pointer"
                      disabled={rollbackMutation.isPending}
                      onClick={() => setRollingBackBatch(batch)}
                      type="button"
                    >
                      <Undo2 className="h-3.5 w-3.5" />
                      <span>Rollback Import</span>
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Row inspector modal */}
      <BatchDetailsModal
        batch={selectedBatch}
        canAct={false}
        isOpen={Boolean(selectedBatch)}
        onClose={() => setSelectedBatch(null)}
      />

      {/* Rollback confirmation modal */}
      {rollingBackBatch && (
        <RollbackBatchModal
          fileName={rollingBackBatch.fileName}
          isOpen={Boolean(rollingBackBatch)}
          onClose={() => setRollingBackBatch(null)}
          onConfirm={async (reason) => {
            setActionError(null);
            try {
              await rollbackMutation.mutateAsync({
                batchId: rollingBackBatch.id,
                reason,
              });
              void refetch();
            } catch (err: unknown) {
              setActionError(
                err instanceof Error ? err.message : "Failed to rollback import",
              );
            }
          }}
        />
      )}
    </div>
  );
}
