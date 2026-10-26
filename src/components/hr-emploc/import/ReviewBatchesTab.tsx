"use client";

import React, { useMemo, useState } from "react";
import {
  CheckCircle2,
  FileSpreadsheet,
  Loader2,
  RefreshCw,
  Search,
} from "lucide-react";
import {
  type HrEmplocImportBatch,
  useApproveImportBatch,
  useImportBatches,
  useRejectImportBatch,
} from "@/lib/queries/hr_emploc_import";
import { BatchDetailsModal } from "./BatchDetailsModal";
import { RejectBatchModal } from "./RejectBatchModal";

interface ReviewBatchesTabProps {
  canAct: boolean;
  onBatchApprovedOrRejected?: () => void;
}

export function ReviewBatchesTab({
  canAct,
  onBatchApprovedOrRejected,
}: ReviewBatchesTabProps) {
  const [search, setSearch] = useState("");
  const [selectedBatch, setSelectedBatch] = useState<HrEmplocImportBatch | null>(
    null,
  );
  const [rejectingBatch, setRejectingBatch] = useState<HrEmplocImportBatch | null>(
    null,
  );
  const [actionError, setActionError] = useState<string | null>(null);

  const { data: batches = [], isLoading, refetch, isFetching } = useImportBatches();
  const approveMutation = useApproveImportBatch();
  const rejectMutation = useRejectImportBatch();

  const pendingBatches = useMemo(() => {
    return batches.filter((b) => b.status === "pending_approval");
  }, [batches]);

  const filteredBatches = useMemo(() => {
    if (!search.trim()) return pendingBatches;
    const q = search.toLowerCase();
    return pendingBatches.filter(
      (b) =>
        b.fileName.toLowerCase().includes(q) ||
        (b.groupName && b.groupName.toLowerCase().includes(q)) ||
        (b.uploadedByName && b.uploadedByName.toLowerCase().includes(q)),
    );
  }, [pendingBatches, search]);

  async function handleQuickApprove(batch: HrEmplocImportBatch) {
    const confirmMsg =
      batch.blockedRows > 0
        ? `Approve "${batch.fileName}"? This will create ${batch.validRows} HR Emploc record(s). ${batch.blockedRows} blocked row(s) will be excluded.`
        : `Approve "${batch.fileName}" and create ${batch.validRows} HR Emploc record(s)?`;

    if (!window.confirm(confirmMsg)) return;

    setActionError(null);
    try {
      await approveMutation.mutateAsync({ batchId: batch.id });
      void refetch();
      onBatchApprovedOrRejected?.();
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : "Failed to approve import batch",
      );
    }
  }

  return (
    <div className="space-y-4 text-xs">
      {/* Header controls: search and refresh */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative w-full sm:w-72">
          <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
          <input
            className="w-full rounded-lg border border-border-default bg-surface pl-8 pr-3 py-1.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden focus:ring-1 focus:ring-brand-primary shadow-2xs"
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search pending batches..."
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
          <span>Refresh Queue</span>
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

      {/* Batches List */}
      {isLoading ? (
        <div className="flex h-56 flex-col items-center justify-center gap-2">
          <Loader2 className="h-6 w-6 animate-spin text-brand-primary" />
          <p className="text-xs text-text-muted">Loading pending batches...</p>
        </div>
      ) : filteredBatches.length === 0 ? (
        <div className="flex h-56 flex-col items-center justify-center rounded-xl border border-dashed border-border-default bg-surface text-center p-6">
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-muted text-text-muted mb-2 border border-border-subtle">
            <CheckCircle2 className="h-6 w-6" />
          </div>
          <h4 className="text-sm font-bold text-text-primary">
            {search ? "No matching pending batches" : "No Pending Imports"}
          </h4>
          <p className="mt-1 text-xs text-text-muted max-w-sm">
            {search
              ? "Try adjusting your search criteria."
              : "All submitted import batches have been reviewed, approved, or rejected."}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {filteredBatches.map((batch) => (
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
                    <span className="inline-flex items-center rounded-full border border-border-default bg-surface-muted px-2.5 py-0.5 text-xs font-semibold text-text-primary">
                      Pending approval
                    </span>
                  </div>

                  <p className="text-xs text-text-muted">
                    Group: <span className="font-semibold text-text-primary">{batch.groupName || "—"}</span>
                    {" • "}Uploaded by {batch.uploadedByName || "Encoder"} on{" "}
                    {batch.uploadedAt ? new Date(batch.uploadedAt).toLocaleString() : "—"}
                  </p>

                  <div className="flex flex-wrap items-center gap-2 pt-1">
                    <span className="inline-flex items-center rounded-md border border-border-subtle bg-surface-muted px-2 py-0.5 text-[11px] font-semibold text-text-primary">
                      {batch.totalRows} total
                    </span>
                    <span className="inline-flex items-center rounded-md border border-border-subtle bg-surface-muted px-2 py-0.5 text-[11px] font-semibold text-text-primary">
                      {batch.validRows} ready to import
                    </span>
                    {batch.blockedRows > 0 && (
                      <span className="inline-flex items-center rounded-md border border-border-subtle bg-surface-muted px-2 py-0.5 text-[11px] font-semibold text-text-primary">
                        {batch.blockedRows} blocked
                      </span>
                    )}
                    {batch.duplicateRows > 0 && (
                      <span className="inline-flex items-center rounded-md border border-border-subtle bg-surface-muted px-2 py-0.5 text-[11px] font-semibold text-text-primary">
                        {batch.duplicateRows} duplicate
                      </span>
                    )}
                  </div>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="flex flex-wrap items-center gap-2 border-t border-border-subtle pt-3 md:border-t-0 md:pt-0">
                <button
                  className="rounded-lg border border-border-default bg-surface px-3.5 py-2 text-xs font-semibold text-text-primary hover:bg-surface-hover transition shadow-2xs cursor-pointer"
                  onClick={() => setSelectedBatch(batch)}
                  type="button"
                >
                  Inspect Rows
                </button>

                {canAct && (
                  <>
                    <button
                      className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] px-3 py-2 text-xs font-semibold text-[var(--danger-text)] hover:opacity-90 transition shadow-2xs cursor-pointer"
                      disabled={approveMutation.isPending || rejectMutation.isPending}
                      onClick={() => setRejectingBatch(batch)}
                      type="button"
                    >
                      Reject
                    </button>
                    <button
                      className="inline-flex items-center gap-1.5 rounded-lg bg-brand-button px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-primary-hover transition disabled:opacity-50 cursor-pointer"
                      disabled={
                        approveMutation.isPending ||
                        rejectMutation.isPending ||
                        batch.validRows === 0
                      }
                      onClick={() => handleQuickApprove(batch)}
                      type="button"
                    >
                      {approveMutation.isPending ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      ) : (
                        <span>Approve ({batch.validRows})</span>
                      )}
                    </button>
                  </>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Row details modal */}
      <BatchDetailsModal
        batch={selectedBatch}
        canAct={canAct}
        isOpen={Boolean(selectedBatch)}
        onClose={() => setSelectedBatch(null)}
        onRefresh={() => {
          void refetch();
          onBatchApprovedOrRejected?.();
        }}
      />

      {/* Rejection modal */}
      {rejectingBatch && (
        <RejectBatchModal
          fileName={rejectingBatch.fileName}
          isOpen={Boolean(rejectingBatch)}
          onClose={() => setRejectingBatch(null)}
          onConfirm={async (reasonCode, reasonNote) => {
            await rejectMutation.mutateAsync({
              batchId: rejectingBatch.id,
              reasonCode,
              reasonNote,
            });
            void refetch();
            onBatchApprovedOrRejected?.();
          }}
        />
      )}
    </div>
  );
}
