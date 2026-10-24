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
    <div className="space-y-4">
      {/* Header controls: search and refresh */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="relative w-full sm:w-72">
          <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-gray-400" />
          <input
            className="w-full rounded-lg border border-gray-300 bg-white pl-8 pr-3 py-1.5 text-xs text-gray-900 placeholder-gray-400 focus:border-purple-500 focus:outline-hidden focus:ring-1 focus:ring-purple-500 shadow-2xs"
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search pending batches..."
            type="text"
            value={search}
          />
        </div>

        <button
          className="inline-flex items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-xs font-semibold text-gray-700 hover:bg-gray-50 transition shadow-2xs self-start sm:self-auto"
          disabled={isFetching}
          onClick={() => void refetch()}
          type="button"
        >
          <RefreshCw className={`h-3.5 w-3.5 ${isFetching ? "animate-spin" : ""}`} />
          <span>Refresh Queue</span>
        </button>
      </div>

      {actionError && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700 flex items-center justify-between">
          <span>{actionError}</span>
          <button
            className="text-red-500 hover:text-red-700"
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
          <Loader2 className="h-6 w-6 animate-spin text-blue-600" />
          <p className="text-xs text-gray-500">Loading pending batches...</p>
        </div>
      ) : filteredBatches.length === 0 ? (
        <div className="flex h-56 flex-col items-center justify-center rounded-xl border border-dashed border-gray-200 bg-surface-card text-center p-6">
          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-emerald-50 text-emerald-600 mb-2">
            <CheckCircle2 className="h-6 w-6" />
          </div>
          <h4 className="text-sm font-bold text-gray-900">
            {search ? "No matching pending batches" : "No Pending Imports"}
          </h4>
          <p className="mt-1 text-xs text-gray-500 max-w-sm">
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
              className="flex flex-col gap-4 rounded-xl border border-border-default bg-surface-card p-4.5 shadow-xs transition hover:border-gray-300 md:flex-row md:items-center md:justify-between"
            >
              <div className="flex items-start gap-3.5">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-purple-50 text-purple-700 shrink-0 mt-0.5 border border-purple-200">
                  <FileSpreadsheet className="h-5 w-5" />
                </div>
                <div className="space-y-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h4 className="text-sm font-bold text-gray-900">{batch.fileName}</h4>
                    <span className="inline-flex items-center rounded-full bg-amber-100 px-2.5 py-0.5 text-[10px] font-bold text-amber-800">
                      PENDING APPROVAL
                    </span>
                  </div>

                  <p className="text-xs text-gray-600">
                    Group: <span className="font-semibold text-gray-900">{batch.groupName || "—"}</span>
                    {" • "}Uploaded by {batch.uploadedByName || "Encoder"} on{" "}
                    {batch.uploadedAt ? new Date(batch.uploadedAt).toLocaleString() : "—"}
                  </p>

                  <div className="flex flex-wrap items-center gap-2 pt-1">
                    <span className="inline-flex items-center rounded-md bg-gray-100 px-2 py-0.5 text-[11px] font-semibold text-gray-700">
                      {batch.totalRows} total
                    </span>
                    <span className="inline-flex items-center rounded-md bg-emerald-50 px-2 py-0.5 text-[11px] font-semibold text-emerald-700">
                      {batch.validRows} ready to import
                    </span>
                    {batch.blockedRows > 0 && (
                      <span className="inline-flex items-center rounded-md bg-red-50 px-2 py-0.5 text-[11px] font-semibold text-red-700">
                        {batch.blockedRows} blocked
                      </span>
                    )}
                    {batch.duplicateRows > 0 && (
                      <span className="inline-flex items-center rounded-md bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-700">
                        {batch.duplicateRows} duplicate
                      </span>
                    )}
                  </div>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="flex flex-wrap items-center gap-2 border-t border-gray-100 pt-3 md:border-t-0 md:pt-0">
                <button
                  className="rounded-lg border border-gray-300 bg-white px-3.5 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50 transition shadow-2xs"
                  onClick={() => setSelectedBatch(batch)}
                  type="button"
                >
                  Inspect Rows
                </button>

                {canAct && (
                  <>
                    <button
                      className="rounded-lg border border-red-300 bg-white px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-50 transition shadow-2xs"
                      disabled={approveMutation.isPending || rejectMutation.isPending}
                      onClick={() => setRejectingBatch(batch)}
                      type="button"
                    >
                      Reject
                    </button>
                    <button
                      className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-700 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-emerald-800 transition disabled:opacity-50"
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
