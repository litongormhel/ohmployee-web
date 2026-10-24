"use client";

import React, { useMemo, useState } from "react";
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  FileSpreadsheet,
  Loader2,
  Search,
  X,
} from "lucide-react";
import {
  type HrEmplocImportBatch,
  useBatchRows,
  useApproveImportBatch,
} from "@/lib/queries/hr_emploc_import";
import { RejectBatchModal } from "./RejectBatchModal";

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
    <div
      aria-modal="true"
      className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4 backdrop-blur-xs animate-fade-in"
      role="dialog"
    >
      <div className="relative flex flex-col h-[90vh] w-full max-w-5xl rounded-2xl border border-border-default bg-surface-card shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-default px-6 py-4 bg-slate-50/50">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-100 text-blue-700">
              <FileSpreadsheet className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-base font-bold text-gray-900">{batch.fileName}</h2>
                <span
                  className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${
                    batch.status === "approved"
                      ? "bg-emerald-100 text-emerald-800"
                      : batch.status === "rejected"
                      ? "bg-red-100 text-red-800"
                      : batch.status === "rolled_back"
                      ? "bg-amber-100 text-amber-800"
                      : "bg-blue-100 text-blue-800"
                  }`}
                >
                  {batch.status.replace("_", " ").toUpperCase()}
                </span>
              </div>
              <p className="text-xs text-gray-500">
                Group: <span className="font-semibold text-gray-700">{batch.groupName || "—"}</span>
                {" • "}Submitted by {batch.uploadedByName || "Encoder"} on{" "}
                {batch.uploadedAt ? new Date(batch.uploadedAt).toLocaleDateString() : "—"}
              </p>
            </div>
          </div>
          <button
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition"
            onClick={onClose}
            type="button"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Action Error Banner */}
        {actionError && (
          <div className="px-6 py-2.5 bg-red-50 border-b border-red-200 text-xs text-red-700 flex items-center justify-between">
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

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-4">
          {/* KPI metrics bar */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="rounded-xl border border-gray-200 bg-white p-3.5 shadow-2xs">
              <p className="text-[11px] font-medium text-gray-500 uppercase tracking-wider">
                Total Rows
              </p>
              <p className="mt-1 text-2xl font-bold text-gray-900">
                {summary?.totalRows ?? batch.totalRows}
              </p>
            </div>
            <div className="rounded-xl border border-emerald-200 bg-emerald-50/40 p-3.5 shadow-2xs">
              <p className="text-[11px] font-medium text-emerald-700 uppercase tracking-wider">
                Ready to Import
              </p>
              <p className="mt-1 text-2xl font-bold text-emerald-800">
                {summary?.validRows ?? batch.validRows}
              </p>
            </div>
            <div className="rounded-xl border border-red-200 bg-red-50/40 p-3.5 shadow-2xs">
              <p className="text-[11px] font-medium text-red-700 uppercase tracking-wider">
                Blocked Rows
              </p>
              <p className="mt-1 text-2xl font-bold text-red-800">
                {summary?.blockedRows ?? batch.blockedRows}
              </p>
            </div>
            <div className="rounded-xl border border-amber-200 bg-amber-50/40 p-3.5 shadow-2xs">
              <p className="text-[11px] font-medium text-amber-700 uppercase tracking-wider">
                Duplicates
              </p>
              <p className="mt-1 text-2xl font-bold text-amber-800">
                {summary?.duplicateRows ?? batch.duplicateRows}
              </p>
            </div>
          </div>

          {/* Blocked errors summary breakdown if any */}
          {summary && summary.blockedRows > 0 && (
            <div className="rounded-xl border border-amber-200 bg-amber-50/50 p-4">
              <div className="flex items-start gap-2.5">
                <AlertTriangle className="h-5 w-5 text-amber-700 mt-0.5 shrink-0" />
                <div className="flex-1">
                  <h4 className="text-xs font-bold text-amber-900">
                    {summary.blockedRows} Row(s) Blocked by Slot / Validation Checks
                  </h4>
                  <p className="mt-0.5 text-xs text-amber-800">
                    Blocked rows will not be imported into HR Emploc upon approval:
                  </p>
                  <ul className="mt-2 space-y-1 text-xs text-amber-900">
                    {Object.entries(summary.errorsByReason).map(([reason, rows]) => (
                      <li key={reason} className="flex items-center gap-2">
                        <span className="inline-flex items-center justify-center rounded-full bg-amber-200/80 px-1.5 py-0.2 text-[10px] font-bold text-amber-900">
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
            <div className="inline-flex rounded-lg border border-gray-200 bg-gray-50/80 p-0.5">
              <button
                className={`rounded-md px-3 py-1.5 text-xs font-semibold transition ${
                  filterMode === "all"
                    ? "bg-white text-gray-900 shadow-2xs"
                    : "text-gray-600 hover:text-gray-900"
                }`}
                onClick={() => setFilterMode("all")}
                type="button"
              >
                All Rows ({summary?.totalRows ?? batch.totalRows})
              </button>
              <button
                className={`rounded-md px-3 py-1.5 text-xs font-semibold transition ${
                  filterMode === "valid"
                    ? "bg-white text-emerald-800 shadow-2xs"
                    : "text-gray-600 hover:text-gray-900"
                }`}
                onClick={() => setFilterMode("valid")}
                type="button"
              >
                Valid ({summary?.validRows ?? batch.validRows})
              </button>
              <button
                className={`rounded-md px-3 py-1.5 text-xs font-semibold transition ${
                  filterMode === "blocked"
                    ? "bg-white text-red-800 shadow-2xs"
                    : "text-gray-600 hover:text-gray-900"
                }`}
                onClick={() => setFilterMode("blocked")}
                type="button"
              >
                Blocked ({summary?.blockedRows ?? batch.blockedRows})
              </button>
            </div>

            <div className="relative w-full sm:w-64">
              <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-gray-400" />
              <input
                className="w-full rounded-lg border border-gray-200 bg-white pl-8 pr-3 py-1.5 text-xs text-gray-900 placeholder-gray-400 focus:border-blue-500 focus:outline-hidden focus:ring-1 focus:ring-blue-500"
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
              <Loader2 className="h-6 w-6 animate-spin text-blue-600" />
            </div>
          ) : rowsError ? (
            <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-xs text-red-700">
              Failed to load batch rows: {(rowsError as Error).message}
            </div>
          ) : filteredRows.length === 0 ? (
            <div className="flex h-36 flex-col items-center justify-center rounded-xl border border-dashed border-gray-200 text-center">
              <p className="text-xs text-gray-500">No rows match the active filter.</p>
            </div>
          ) : (
            <div className="rounded-xl border border-gray-200 overflow-hidden shadow-2xs">
              <div className="max-h-[380px] overflow-y-auto">
                <table className="w-full border-collapse text-left text-xs">
                  <thead className="sticky top-0 bg-gray-100 text-gray-600 border-b border-gray-200 font-semibold z-10">
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
                  <tbody className="divide-y divide-gray-100 bg-white">
                    {filteredRows.map((row) => {
                      const isValid = row.validationStatus === "valid";
                      return (
                        <tr
                          key={row.id}
                          className={`hover:bg-gray-50/80 transition ${
                            !isValid ? "bg-red-50/20" : ""
                          }`}
                        >
                          <td className="py-2 px-3 font-mono text-[11px] text-gray-500">
                            {row.rowNumber}
                          </td>
                          <td className="py-2 px-3">
                            <span
                              className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[10px] font-bold ${
                                isValid
                                  ? "bg-emerald-100 text-emerald-800"
                                  : "bg-red-100 text-red-800"
                              }`}
                            >
                              {isValid ? (
                                <CheckCircle2 className="h-3 w-3" />
                              ) : (
                                <AlertCircle className="h-3 w-3" />
                              )}
                              {isValid ? "VALID" : "BLOCKED"}
                            </span>
                          </td>
                          <td className="py-2 px-3 font-semibold text-gray-900">
                            {row.displayName}
                          </td>
                          <td className="py-2 px-3 font-mono text-gray-700">
                            {row.vcode || "—"}
                          </td>
                          <td className="py-2 px-3 text-gray-700">
                            {row.storeName || "—"}
                          </td>
                          <td className="py-2 px-3 text-gray-600">
                            {row.positionName || "—"}
                          </td>
                          <td className="py-2 px-3 text-gray-600">
                            {row.accountName || "—"}
                          </td>
                          <td className="py-2 px-3 text-gray-600">
                            {row.dateHired || "—"}
                          </td>
                          <td className="py-2 px-3 max-w-xs">
                            {isValid ? (
                              <span className="text-[11px] text-emerald-700">
                                Slot reserved in Plantilla
                              </span>
                            ) : (
                              <div className="space-y-0.5">
                                {row.validationErrors.map((err, idx) => (
                                  <p
                                    key={idx}
                                    className="text-[11px] text-red-600 leading-tight"
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
        <div className="flex items-center justify-between border-t border-border-default px-6 py-4 bg-slate-50/70">
          <div>
            {!canAct && isPending && (
              <p className="text-xs text-amber-700">
                Viewing in read-only mode. Head Admin or Super Admin role is required to approve or reject.
              </p>
            )}
          </div>

          <div className="flex items-center gap-3">
            <button
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50 transition"
              onClick={onClose}
              type="button"
            >
              Close
            </button>

            {canAct && isPending && (
              <>
                <button
                  className="rounded-lg border border-red-300 bg-white px-4 py-2 text-xs font-semibold text-red-700 hover:bg-red-50 transition"
                  disabled={approveMutation.isPending}
                  onClick={() => setIsRejectOpen(true)}
                  type="button"
                >
                  Reject Batch
                </button>

                <button
                  className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-700 px-5 py-2 text-xs font-semibold text-white shadow-xs hover:bg-emerald-800 transition disabled:opacity-50"
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
    </div>
  );
}
