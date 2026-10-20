"use client";

import React, { useMemo, useRef, useState } from "react";
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Download,
  FileSpreadsheet,
  History,
  Layers,
  Loader2,
  RefreshCw,
  RotateCcw,
  Send,
  ShieldAlert,
  ShieldCheck,
  UploadCloud,
  X,
} from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { useCurrentUser } from "@/lib/auth";
import {
  downloadVacancyImportTemplate,
  parseSpreadsheetToRows,
  VACANCY_REQUIRED_HEADERS,
} from "@/lib/utils/data_control_xlsx";
import {
  approveVacancyImportBatch,
  approveVacancyImportRollback,
  emergencyRollbackVacancyImport,
  formatRollbackRemaining,
  humanizeRollbackError,
  IMPORT_ROLLBACK_REASONS,
  rejectVacancyImportBatch,
  requestVacancyImportRollback,
  submitVacancyImport,
  useDataControlAccounts,
  useDataControlGroups,
  useVacancyImportBatches,
  useVacancyImportRollbackHistory,
  useVacancyImportRows,
  VacancyImportBatch,
} from "@/lib/queries/dataControl";

export interface VacancyImportModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type TabType = "upload" | "review" | "history";

export function VacancyImportModal({ isOpen, onClose }: VacancyImportModalProps) {
  const queryClient = useQueryClient();
  const currentUser = useCurrentUser();
  const [activeTab, setActiveTab] = useState<TabType>("upload");

  // Selection & staging
  const [selectedGroupId, setSelectedGroupId] = useState<string>("");
  const [selectedAccountId, setSelectedAccountId] = useState<string>("");
  const [file, setFile] = useState<File | null>(null);
  const [parsedRows, setParsedRows] = useState<Record<string, string>[]>([]);
  const [parseError, setParseError] = useState<string | null>(null);
  const [isParsing, setIsParsing] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitSuccess, setSubmitSuccess] = useState<string | null>(null);

  // Review detail & action
  const [selectedBatchId, setSelectedBatchId] = useState<string | null>(null);
  const [actionReason, setActionReason] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [isActionPending, setIsActionPending] = useState(false);

  // Rollback Governance & History state
  const [historySelectedBatch, setHistorySelectedBatch] = useState<VacancyImportBatch | null>(null);
  const [isRequestRollbackOpen, setIsRequestRollbackOpen] = useState(false);
  const [selectedRollbackReason, setSelectedRollbackReason] = useState<string>("wrong_batch");
  const [rollbackRemarks, setRollbackRemarks] = useState("");
  const [isApproveRollbackConfirmOpen, setIsApproveRollbackConfirmOpen] = useState(false);
  const [isEmergencyRollbackOpen, setIsEmergencyRollbackOpen] = useState(false);
  const [emergencyReason, setEmergencyReason] = useState("");
  const [isRollbackHistoryOpen, setIsRollbackHistoryOpen] = useState(false);
  const [rollbackActionBusy, setRollbackActionBusy] = useState(false);
  const [rollbackActionError, setRollbackActionError] = useState<string | null>(null);
  const [rollbackActionSuccess, setRollbackActionSuccess] = useState<string | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const { data: groups = [] } = useDataControlGroups();
  const { data: accounts = [], isLoading: isLoadingAccounts } = useDataControlAccounts(selectedGroupId || null);
  const { data: batches = [], refetch: refetchBatches, isLoading: isLoadingBatches } = useVacancyImportBatches();
  const { data: previewRows = [], isLoading: isLoadingPreviewRows } = useVacancyImportRows(selectedBatchId);

  // RBAC resolution (1:1 Mobile Parity: Super Admin & Head Admin only for Vacancy Rollback Request)
  const roleStr = useMemo(() => {
    return (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
  }, [currentUser]);

  const isSuperAdmin = useMemo(() => {
    return roleStr.includes("super_admin") || roleStr === "sa";
  }, [roleStr]);

  const isHeadAdmin = useMemo(() => {
    return roleStr.includes("head_admin") || roleStr === "ha";
  }, [roleStr]);

  const canApprove = useMemo(() => {
    return isSuperAdmin || isHeadAdmin;
  }, [isSuperAdmin, isHeadAdmin]);

  const canRequestRollback = useMemo(() => {
    return isSuperAdmin || isHeadAdmin;
  }, [isSuperAdmin, isHeadAdmin]);

  const handleRollbackSuccess = (msg: string) => {
    setRollbackActionSuccess(msg);
    setRollbackActionError(null);
    refetchBatches();
    queryClient.invalidateQueries({ queryKey: ["vacancy-import-batches"] });
    queryClient.invalidateQueries({ queryKey: ["vacancy-import-rollback-history"] });
    queryClient.invalidateQueries({ queryKey: ["vacancies"] });
    queryClient.invalidateQueries({ queryKey: ["vacancies-list"] });
    queryClient.invalidateQueries({ queryKey: ["vacancy-counts"] });
  };

  const handleDoRequestRollback = async () => {
    if (!historySelectedBatch || !selectedRollbackReason || rollbackRemarks.trim().length < 10) return;
    setRollbackActionBusy(true);
    setRollbackActionError(null);
    try {
      await requestVacancyImportRollback({
        batchId: historySelectedBatch.id,
        reasonCode: selectedRollbackReason,
        reasonNote: rollbackRemarks.trim(),
      });
      setIsRequestRollbackOpen(false);
      setRollbackRemarks("");
      handleRollbackSuccess("Rollback request submitted for Super Admin approval.");
    } catch (err: unknown) {
      setRollbackActionError(humanizeRollbackError(err instanceof Error ? err.message : String(err)));
    } finally {
      setRollbackActionBusy(false);
    }
  };

  const handleDoApproveRollback = async () => {
    if (!historySelectedBatch) return;
    setRollbackActionBusy(true);
    setRollbackActionError(null);
    try {
      await approveVacancyImportRollback(historySelectedBatch.id);
      setIsApproveRollbackConfirmOpen(false);
      handleRollbackSuccess("Rollback executed. Requester notified.");
    } catch (err: unknown) {
      setRollbackActionError(humanizeRollbackError(err instanceof Error ? err.message : String(err)));
    } finally {
      setRollbackActionBusy(false);
    }
  };

  const handleDoEmergencyRollback = async () => {
    if (!historySelectedBatch || emergencyReason.trim().length < 50) return;
    setRollbackActionBusy(true);
    setRollbackActionError(null);
    try {
      await emergencyRollbackVacancyImport({
        batchId: historySelectedBatch.id,
        reason: emergencyReason.trim(),
      });
      setIsEmergencyRollbackOpen(false);
      setEmergencyReason("");
      handleRollbackSuccess("Emergency rollback override executed.");
    } catch (err: unknown) {
      setRollbackActionError(humanizeRollbackError(err instanceof Error ? err.message : String(err)));
    } finally {
      setRollbackActionBusy(false);
    }
  };

  if (!isOpen) return null;

  const handleGroupSelect = (gId: string) => {
    setSelectedGroupId(gId);
    setSelectedAccountId("");
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const picked = e.target.files?.[0];
    if (!picked) return;
    setFile(picked);
    setParseError(null);
    setSubmitSuccess(null);
    setIsParsing(true);

    try {
      const { headers, rows } = await parseSpreadsheetToRows(picked);
      const upperHeaders = new Set(headers.map((h) => h.toUpperCase()));
      const missing = VACANCY_REQUIRED_HEADERS.filter((req) => !upperHeaders.has(req));

      if (missing.length > 0) {
        throw new Error(`Missing required columns: ${missing.join(", ")}`);
      }
      setParsedRows(rows);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : "Failed to parse spreadsheet file.");
      setParsedRows([]);
    } finally {
      setIsParsing(false);
    }
  };

  const handleSubmit = async () => {
    if (!selectedGroupId || !selectedAccountId || parsedRows.length === 0 || !file) {
      setParseError("Please select an operational Group, Account, and a valid spreadsheet.");
      return;
    }

    setIsSubmitting(true);
    setParseError(null);
    try {
      const batchId = await submitVacancyImport({
        fileName: file.name,
        groupId: selectedGroupId,
        accountId: selectedAccountId,
        rows: parsedRows,
      });

      setSubmitSuccess(`Vacancy batch #${batchId} submitted successfully for review.`);
      setFile(null);
      setParsedRows([]);
      if (fileInputRef.current) fileInputRef.current.value = "";
      refetchBatches();
      setActiveTab("review");
      setSelectedBatchId(batchId);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : "Failed to submit vacancy import batch.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleApproveBatch = async (batchId: string) => {
    setIsActionPending(true);
    setActionError(null);
    try {
      await approveVacancyImportBatch(batchId);
      refetchBatches();
      setSelectedBatchId(null);
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to approve vacancy batch.");
    } finally {
      setIsActionPending(false);
    }
  };

  const handleRejectBatch = async (batchId: string) => {
    if (!actionReason.trim()) {
      setActionError("Please provide an audited reason note for rejection.");
      return;
    }
    setIsActionPending(true);
    setActionError(null);
    try {
      await rejectVacancyImportBatch({
        batchId,
        reasonCode: "other",
        reasonNote: actionReason.trim(),
      });
      refetchBatches();
      setSelectedBatchId(null);
      setActionReason("");
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to reject vacancy batch.");
    } finally {
      setIsActionPending(false);
    }
  };

  const pendingBatches = batches.filter((b) => b.status === "pending_approval" || b.status === "draft_uploaded");
  const historyBatches = batches.filter((b) => b.status !== "pending_approval" && b.status !== "draft_uploaded");

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 sm:p-6 overflow-y-auto">
      <div className="relative flex w-full max-w-5xl max-h-[92vh] flex-col rounded-2xl border border-border-subtle bg-surface shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-subtle px-6 py-4 bg-surface-subtle">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-purple-50 text-purple-700 border border-purple-200">
              <FileSpreadsheet className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-base font-bold text-text-primary">Import Vacancy</h2>
                <span className="rounded-md bg-purple-100 text-purple-800 px-2 py-0.5 text-3xs font-bold uppercase tracking-wider">
                  MIGRATION INTAKE
                </span>
              </div>
              <p className="text-xs text-text-secondary">
                Bulk intake vacancy requisitions and pipeline allocations into operational scope groups.
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-text-muted hover:bg-surface-hover hover:text-text-primary transition"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Tab Switcher */}
        <div className="flex items-center border-b border-border-subtle px-6 bg-surface">
          <button
            onClick={() => setActiveTab("upload")}
            className={`flex items-center gap-2 py-3 px-4 text-xs font-semibold border-b-2 transition ${
              activeTab === "upload"
                ? "border-purple-600 text-purple-700"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            <UploadCloud className="h-4 w-4" />
            Upload & Preview
          </button>
          <button
            onClick={() => setActiveTab("review")}
            className={`flex items-center gap-2 py-3 px-4 text-xs font-semibold border-b-2 transition ${
              activeTab === "review"
                ? "border-purple-600 text-purple-700"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            <Layers className="h-4 w-4" />
            Review Queue
            {pendingBatches.length > 0 && (
              <span className="rounded-full bg-purple-100 text-purple-700 font-bold px-1.5 py-0.2 text-3xs">
                {pendingBatches.length}
              </span>
            )}
          </button>
          <button
            onClick={() => setActiveTab("history")}
            className={`flex items-center gap-2 py-3 px-4 text-xs font-semibold border-b-2 transition ${
              activeTab === "history"
                ? "border-purple-600 text-purple-700"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            <History className="h-4 w-4" />
            Import History
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {activeTab === "upload" && (
            <div className="space-y-6">
              {submitSuccess && (
                <div className="rounded-xl border border-emerald-200 bg-emerald-50/80 p-3.5 flex items-start gap-3">
                  <CheckCircle2 className="h-5 w-5 text-emerald-600 shrink-0 mt-0.5" />
                  <p className="text-xs font-medium text-emerald-800">{submitSuccess}</p>
                </div>
              )}

              {parseError && (
                <div className="rounded-xl border border-rose-200 bg-rose-50/80 p-3.5 flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-rose-600 shrink-0 mt-0.5" />
                  <p className="text-xs font-medium text-rose-800">{parseError}</p>
                </div>
              )}

              {/* Scope & Template */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-2xs font-bold text-text-secondary uppercase mb-1.5">
                    1. Target Group
                  </label>
                  <select
                    value={selectedGroupId}
                    onChange={(e) => handleGroupSelect(e.target.value)}
                    className="w-full h-9 rounded-lg border border-border-subtle bg-surface px-3 text-xs font-medium text-text-primary focus:outline-hidden"
                  >
                    <option value="">Select Operational Group...</option>
                    {groups.map((g) => (
                      <option key={g.id} value={g.id}>
                        {g.label}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-2xs font-bold text-text-secondary uppercase mb-1.5">
                    2. Target Account
                  </label>
                  <select
                    value={selectedAccountId}
                    onChange={(e) => setSelectedAccountId(e.target.value)}
                    disabled={!selectedGroupId || isLoadingAccounts}
                    className="w-full h-9 rounded-lg border border-border-subtle bg-surface px-3 text-xs font-medium text-text-primary focus:outline-hidden disabled:opacity-50"
                  >
                    <option value="">
                      {!selectedGroupId
                        ? "Select a group first..."
                        : isLoadingAccounts
                        ? "Loading accounts..."
                        : "Select Account Scope..."}
                    </option>
                    {accounts.map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="flex flex-col justify-end">
                  <button
                    onClick={downloadVacancyImportTemplate}
                    className="h-9 inline-flex items-center justify-center gap-2 rounded-lg border border-border-subtle bg-surface hover:bg-surface-hover text-text-primary text-xs font-semibold transition"
                  >
                    <Download className="h-4 w-4 text-purple-600" />
                    Download Vacancy Template
                  </button>
                </div>
              </div>

              {/* Dropzone */}
              <div
                onClick={() => fileInputRef.current?.click()}
                className="border-2 border-dashed border-border-subtle hover:border-purple-400 bg-surface-subtle hover:bg-purple-50/20 rounded-2xl p-8 flex flex-col items-center justify-center cursor-pointer transition text-center"
              >
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".xlsx,.csv"
                  onChange={handleFileChange}
                  className="hidden"
                />
                <div className="h-12 w-12 rounded-xl bg-purple-100 flex items-center justify-center text-purple-700 mb-3">
                  <UploadCloud className="h-6 w-6" />
                </div>
                <p className="text-sm font-semibold text-text-primary">
                  {file ? file.name : "Click or drag & drop Vacancy XLSX or CSV file here"}
                </p>
                <p className="text-xs text-text-muted mt-1">
                  Supports Google Sheets migration exports and legacy vacancy requisitions.
                </p>
                {isParsing && (
                  <div className="flex items-center gap-2 mt-3 text-xs text-purple-700">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Validating vacancy requisition columns...
                  </div>
                )}
              </div>

              {/* Preview Table */}
              {parsedRows.length > 0 && (
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
                      File Preview ({parsedRows.length} total rows)
                    </h3>
                    <span className="text-xs text-emerald-600 font-semibold flex items-center gap-1">
                      <CheckCircle2 className="h-3.5 w-3.5" /> Required vacancy fields validated
                    </span>
                  </div>

                  <div className="rounded-xl border border-border-subtle overflow-hidden max-h-60 overflow-y-auto">
                    <table className="w-full text-left text-xs">
                      <thead className="bg-surface-subtle border-b border-border-subtle sticky top-0 text-2xs uppercase text-text-muted font-bold">
                        <tr>
                          <th className="py-2 px-3">#</th>
                          <th className="py-2 px-3">VCode</th>
                          <th className="py-2 px-3">Store Name</th>
                          <th className="py-2 px-3">Position</th>
                          <th className="py-2 px-3">HC</th>
                          <th className="py-2 px-3">Type</th>
                          <th className="py-2 px-3">Vacant Date</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-border-subtle">
                        {parsedRows.slice(0, 10).map((row, idx) => (
                          <tr key={idx} className="hover:bg-surface-hover/50">
                            <td className="py-2 px-3 text-text-muted">{idx + 1}</td>
                            <td className="py-2 px-3 font-semibold text-text-primary">{row.VCODE || "—"}</td>
                            <td className="py-2 px-3 text-text-primary">{row.STORE_NAME || "—"}</td>
                            <td className="py-2 px-3 text-text-secondary">{row.POSITION || "—"}</td>
                            <td className="py-2 px-3 font-mono text-purple-700">{row.HC || "1"}</td>
                            <td className="py-2 px-3 text-text-secondary">{row.REQUEST_TYPE || "—"}</td>
                            <td className="py-2 px-3 text-text-muted">{row.VACANT_DATE || "—"}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>

                  <div className="flex justify-end pt-2">
                    <button
                      onClick={handleSubmit}
                      disabled={isSubmitting || !selectedGroupId || !selectedAccountId}
                      className="inline-flex items-center gap-2 rounded-xl bg-purple-600 hover:bg-purple-700 text-white font-semibold text-xs px-5 py-2.5 transition disabled:opacity-50"
                    >
                      {isSubmitting ? (
                        <>
                          <Loader2 className="h-4 w-4 animate-spin" />
                          Submitting Vacancies...
                        </>
                      ) : (
                        <>
                          <Send className="h-4 w-4" />
                          Submit Batch for HA/SA Review
                        </>
                      )}
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}

          {activeTab === "review" && (
            <div className="space-y-4">
              {actionError && (
                <div className="rounded-xl border border-rose-200 bg-rose-50/80 p-3.5 flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-rose-600 shrink-0 mt-0.5" />
                  <p className="text-xs font-medium text-rose-800">{actionError}</p>
                </div>
              )}
              <div className="flex items-center justify-between">
                <p className="text-xs text-text-secondary">
                  Pending vacancy migration batches awaiting administrative approval.
                </p>
                <button
                  onClick={() => refetchBatches()}
                  className="inline-flex items-center gap-1.5 text-xs text-text-muted hover:text-text-primary transition"
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                  Refresh
                </button>
              </div>

              {isLoadingBatches ? (
                <div className="flex justify-center p-8 text-xs text-text-muted">
                  <Loader2 className="h-5 w-5 animate-spin mr-2" /> Loading batches...
                </div>
              ) : pendingBatches.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border-subtle p-8 text-center text-xs text-text-muted">
                  No vacancy batches currently awaiting approval.
                </div>
              ) : (
                <div className="space-y-3">
                  {pendingBatches.map((batch) => (
                    <div
                      key={batch.id}
                      className="rounded-xl border border-border-subtle bg-surface p-4 flex flex-col md:flex-row items-start md:items-center justify-between gap-4"
                    >
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-xs text-text-primary">{batch.fileName}</span>
                          <span className="rounded-md bg-amber-100 text-amber-800 text-3xs font-bold px-2 py-0.5">
                            {batch.status.toUpperCase()}
                          </span>
                        </div>
                        <div className="text-2xs text-text-muted flex flex-wrap gap-x-3 gap-y-1">
                          <span>Batch #{batch.id.slice(0, 8)}</span>
                          <span>Scope: {batch.groupName || "Group"} / {batch.accountName || "Account"}</span>
                          <span>Uploaded by: {batch.uploadedBy || "System"}</span>
                          <span>Rows: {batch.totalRows}</span>
                        </div>
                      </div>

                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => setSelectedBatchId(selectedBatchId === batch.id ? null : batch.id)}
                          className="h-8 px-3 rounded-lg border border-border-subtle text-xs font-semibold text-text-secondary hover:text-text-primary hover:bg-surface-hover transition"
                        >
                          {selectedBatchId === batch.id ? "Hide Rows" : "Inspect Rows"}
                        </button>

                        {canApprove && (
                          <>
                            <button
                              onClick={() => handleApproveBatch(batch.id)}
                              disabled={isActionPending}
                              className="h-8 px-3 rounded-lg bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold transition disabled:opacity-50"
                            >
                              Approve & Migrate
                            </button>
                            <button
                              onClick={() => handleRejectBatch(batch.id)}
                              disabled={isActionPending}
                              className="h-8 px-3 rounded-lg bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 text-xs font-semibold transition disabled:opacity-50"
                            >
                              Reject
                            </button>
                          </>
                        )}
                      </div>
                    </div>
                  ))}

                  {/* Batch Row Inspection Drawer */}
                  {selectedBatchId && (
                    <div className="rounded-xl border border-purple-200 bg-purple-50/20 p-4 space-y-3">
                      <div className="flex items-center justify-between">
                        <h4 className="text-xs font-bold text-text-primary">
                          Inspect Batch Requisitions (#{selectedBatchId.slice(0, 8)})
                        </h4>
                        <span className="text-2xs text-text-muted">{previewRows.length} requisitions</span>
                      </div>

                      {isLoadingPreviewRows ? (
                        <div className="flex justify-center p-6 text-xs text-text-muted">
                          <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rows...
                        </div>
                      ) : (
                        <div className="rounded-lg border border-border-subtle bg-surface overflow-x-auto max-h-56">
                          <table className="w-full text-left text-xs">
                            <thead className="bg-surface-subtle border-b border-border-subtle sticky top-0 text-2xs uppercase text-text-muted font-bold">
                              <tr>
                                <th className="py-2 px-3">#</th>
                                <th className="py-2 px-3">Status</th>
                                <th className="py-2 px-3">VCode</th>
                                <th className="py-2 px-3">Store</th>
                                <th className="py-2 px-3">Position</th>
                                <th className="py-2 px-3">Tab</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-border-subtle">
                              {previewRows.map((r) => (
                                <tr key={r.rowNumber}>
                                  <td className="py-1.5 px-3 text-text-muted">{r.rowNumber}</td>
                                  <td className="py-1.5 px-3">
                                    <span className="rounded-md bg-slate-100 text-slate-800 text-3xs font-bold px-1.5 py-0.5">
                                      {r.validationStatus}
                                    </span>
                                  </td>
                                  <td className="py-1.5 px-3 font-semibold">{r.vcode}</td>
                                  <td className="py-1.5 px-3">{r.storeName}</td>
                                  <td className="py-1.5 px-3 text-text-secondary">{r.position}</td>
                                  <td className="py-1.5 px-3 uppercase text-3xs text-purple-700 font-bold">{r.tab}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      )}

                      {canApprove && (
                        <div className="pt-2">
                          <input
                            type="text"
                            placeholder="Rejection note or audit remarks (required if rejecting)..."
                            value={actionReason}
                            onChange={(e) => setActionReason(e.target.value)}
                            className="w-full h-8 rounded-lg border border-border-subtle bg-surface px-3 text-xs text-text-primary focus:outline-hidden"
                          />
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {activeTab === "history" && (
            <div className="space-y-4">
              {historyBatches.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border-subtle p-8 text-center text-xs text-text-muted">
                  No historical vacancy import logs recorded yet.
                </div>
              ) : (
                <div className="rounded-xl border border-border-subtle bg-surface overflow-hidden">
                  <table className="w-full text-left text-xs">
                    <thead className="bg-surface-subtle border-b border-border-subtle text-2xs uppercase text-text-muted font-bold">
                      <tr>
                        <th className="py-2.5 px-4">File Name</th>
                        <th className="py-2.5 px-4">Status</th>
                        <th className="py-2.5 px-4">Rollback State & Window</th>
                        <th className="py-2.5 px-4">Scope</th>
                        <th className="py-2.5 px-4">Uploaded By</th>
                        <th className="py-2.5 px-4">Date</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {historyBatches.map((b) => {
                        const isSelected = historySelectedBatch?.id === b.id;
                        const isApproved = b.status.toLowerCase().includes("approved");

                        return (
                          <tr
                            key={b.id}
                            onClick={() => setHistorySelectedBatch(isSelected ? null : b)}
                            className={`cursor-pointer transition ${
                              isSelected ? "bg-purple-50/50 dark:bg-purple-950/20" : "hover:bg-surface-hover/50"
                            }`}
                          >
                            <td className="py-2.5 px-4 font-semibold text-text-primary">
                              <div className="flex items-center gap-2">
                                <span>{b.fileName}</span>
                                {isSelected && (
                                  <span className="rounded-full bg-purple-100 text-purple-700 text-3xs font-bold px-1.5 py-0.2">
                                    Selected
                                  </span>
                                )}
                              </div>
                            </td>
                            <td className="py-2.5 px-4">
                              <span
                                className={`rounded-md px-2 py-0.5 text-3xs font-bold uppercase ${
                                  isApproved
                                    ? "bg-emerald-100 text-emerald-800"
                                    : b.status.includes("rolled_back")
                                    ? "bg-purple-100 text-purple-800"
                                    : "bg-rose-100 text-rose-800"
                                }`}
                              >
                                {b.status}
                              </span>
                            </td>
                            <td className="py-2.5 px-4">
                              {b.rollbackStatus === "requested" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-amber-100 text-amber-800 px-2 py-0.5 text-3xs font-bold uppercase">
                                  <Clock className="h-3 w-3" /> Rollback Requested
                                </span>
                              ) : b.rollbackStatus === "completed" || b.status === "rolled_back" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-purple-100 text-purple-800 px-2 py-0.5 text-3xs font-bold uppercase">
                                  <RotateCcw className="h-3 w-3" /> Rolled Back
                                </span>
                              ) : b.rollbackStatus === "failed" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-rose-100 text-rose-800 px-2 py-0.5 text-3xs font-bold uppercase">
                                  <AlertCircle className="h-3 w-3" /> Rollback Failed
                                </span>
                              ) : isApproved ? (
                                b.rollbackAllowed ? (
                                  <span className="inline-flex items-center gap-1 rounded-md bg-blue-50 text-blue-700 border border-blue-200 px-2 py-0.5 text-3xs font-medium">
                                    <Clock className="h-3 w-3 text-blue-500" />
                                    Expires: {formatRollbackRemaining(b.rollbackRemainingSeconds)}
                                  </span>
                                ) : (
                                  <span className="rounded-md bg-slate-100 text-slate-600 px-2 py-0.5 text-3xs font-medium">
                                    Window Expired
                                  </span>
                                )
                              ) : (
                                <span className="text-text-muted text-3xs">—</span>
                              )}
                            </td>
                            <td className="py-2.5 px-4 text-text-secondary">
                              {b.groupName ?? "—"} / {b.accountName ?? "—"}
                            </td>
                            <td className="py-2.5 px-4 text-text-secondary">{b.uploadedBy || "—"}</td>
                            <td className="py-2.5 px-4 text-text-muted">
                              {b.createdAt ? new Date(b.createdAt).toLocaleDateString() : "—"}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}

              {/* Rollback Governance & Detail Drawer */}
              {historySelectedBatch && (
                <div className="rounded-xl border border-purple-200 bg-purple-50/20 p-4 space-y-4 animate-in fade-in duration-150">
                  <div className="flex items-center justify-between border-b border-border-subtle pb-3">
                    <div className="flex items-center gap-2">
                      <RotateCcw className="h-4 w-4 text-purple-700" />
                      <h4 className="text-xs font-bold text-text-primary">
                        Rollback Governance — #{historySelectedBatch.id.slice(0, 8)} ({historySelectedBatch.fileName})
                      </h4>
                    </div>
                    <button
                      onClick={() => setHistorySelectedBatch(null)}
                      className="text-text-muted hover:text-text-primary text-xs"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </div>

                  {/* Summary / Meta */}
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-2xs">
                    <div className="p-2 rounded-lg bg-surface border border-border-subtle">
                      <span className="text-text-muted block">Batch Status</span>
                      <span className="font-bold text-text-primary uppercase mt-0.5 block">
                        {historySelectedBatch.status}
                      </span>
                    </div>
                    <div className="p-2 rounded-lg bg-surface border border-border-subtle">
                      <span className="text-text-muted block">Rollback Status</span>
                      <span className="font-bold text-text-primary uppercase mt-0.5 block">
                        {historySelectedBatch.rollbackStatus || "None"}
                      </span>
                    </div>
                    <div className="p-2 rounded-lg bg-surface border border-border-subtle">
                      <span className="text-text-muted block">Governance Window</span>
                      <span className="font-semibold text-text-primary mt-0.5 block">
                        {historySelectedBatch.rollbackAllowed
                          ? `Active (${formatRollbackRemaining(historySelectedBatch.rollbackRemainingSeconds)} left)`
                          : "Expired / Inactive"}
                      </span>
                    </div>
                    <div className="p-2 rounded-lg bg-surface border border-border-subtle">
                      <span className="text-text-muted block">Total Vacancy Rows</span>
                      <span className="font-bold text-text-primary mt-0.5 block">
                        {historySelectedBatch.totalRows} requisitions
                      </span>
                    </div>
                  </div>

                  {/* Block / Notice Warnings */}
                  {historySelectedBatch.rollbackBlockReason && (
                    <div className="rounded-lg border border-rose-200 bg-rose-50/80 p-3 text-xs text-rose-800 flex items-start gap-2 font-medium">
                      <AlertTriangle className="h-4 w-4 text-rose-600 shrink-0 mt-0.5" />
                      <div>{humanizeRollbackError(historySelectedBatch.rollbackBlockReason)}</div>
                    </div>
                  )}

                  {historySelectedBatch.rollbackErrorDetail && (
                    <div className="rounded-lg border border-rose-200 bg-rose-50/80 p-3 text-xs text-rose-800 flex items-start gap-2">
                      <AlertCircle className="h-4 w-4 text-rose-600 shrink-0 mt-0.5" />
                      <div>
                        Rollback attempt failed: {humanizeRollbackError(historySelectedBatch.rollbackErrorDetail)}
                      </div>
                    </div>
                  )}

                  {rollbackActionSuccess && (
                    <div className="rounded-lg border border-emerald-200 bg-emerald-50/80 p-3 text-xs text-emerald-800 flex items-center gap-2">
                      <CheckCircle2 className="h-4 w-4 text-emerald-600 shrink-0" />
                      <span>{rollbackActionSuccess}</span>
                    </div>
                  )}

                  {rollbackActionError && (
                    <div className="rounded-lg border border-rose-200 bg-rose-50/80 p-3 text-xs text-rose-800 flex items-center gap-2">
                      <AlertCircle className="h-4 w-4 text-rose-600 shrink-0" />
                      <span>{rollbackActionError}</span>
                    </div>
                  )}

                  {/* Actions Bar */}
                  <div className="flex flex-wrap items-center gap-2 pt-1">
                    {/* View History Button */}
                    <button
                      onClick={() => setIsRollbackHistoryOpen(true)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-primary hover:bg-surface-hover shadow-xs transition"
                    >
                      <History className="h-3.5 w-3.5 text-text-secondary" />
                      View Rollback History
                    </button>

                    {/* Step 1: Request Rollback Button (Super Admin or Head Admin) */}
                    {canRequestRollback &&
                      historySelectedBatch.rollbackAllowed &&
                      historySelectedBatch.rollbackStatus !== "requested" &&
                      historySelectedBatch.rollbackStatus !== "completed" && (
                        <button
                          onClick={() => {
                            setSelectedRollbackReason("wrong_batch");
                            setRollbackRemarks("");
                            setRollbackActionError(null);
                            setIsRequestRollbackOpen(true);
                          }}
                          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-rose-300 bg-rose-50/60 text-xs font-semibold text-rose-800 hover:bg-rose-100/80 shadow-xs transition"
                        >
                          <RotateCcw className="h-3.5 w-3.5 text-rose-700" />
                          Request Rollback
                        </button>
                      )}

                    {/* Step 2: Approve & Execute Rollback Button (Super Admin Only) */}
                    {isSuperAdmin &&
                      historySelectedBatch.status.toLowerCase().includes("approved") &&
                      historySelectedBatch.rollbackStatus === "requested" && (
                        <button
                          onClick={() => {
                            setRollbackActionError(null);
                            setIsApproveRollbackConfirmOpen(true);
                          }}
                          className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-rose-700 text-xs font-semibold text-white hover:bg-rose-800 shadow-xs transition"
                        >
                          <ShieldCheck className="h-3.5 w-3.5" />
                          Approve & Execute Rollback
                        </button>
                      )}

                    {/* Emergency Rollback Override (Super Admin Only) */}
                    {isSuperAdmin && historySelectedBatch.canEmergencyRollback && (
                      <button
                        onClick={() => {
                          setEmergencyReason("");
                          setRollbackActionError(null);
                          setIsEmergencyRollbackOpen(true);
                        }}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-rose-950 text-xs font-semibold text-rose-100 hover:bg-black shadow-xs transition"
                      >
                        <ShieldAlert className="h-3.5 w-3.5 text-rose-400" />
                        Emergency Rollback Override
                      </button>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle px-6 py-3 bg-surface-subtle">
          <p className="text-2xs text-text-muted">
            Full Mobile Vacancy Import Parity with slot binding and audit controls.
          </p>
          <button
            onClick={onClose}
            className="px-4 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-primary hover:bg-surface-hover transition"
          >
            Close
          </button>
        </div>
      </div>

      {/* MODAL 1: Request Rollback Modal */}
      {isRequestRollbackOpen && historySelectedBatch && (
        <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
          <div className="relative w-full max-w-md rounded-2xl border border-border-subtle bg-surface p-6 shadow-2xl animate-in fade-in zoom-in-95 duration-150 space-y-4">
            <div className="flex items-center justify-between pb-3 border-b border-border-subtle">
              <div className="flex items-center gap-2">
                <RotateCcw className="h-4 w-4 text-rose-700" />
                <h3 className="text-sm font-bold text-text-primary">Request Vacancy Import Rollback</h3>
              </div>
              <button
                onClick={() => setIsRequestRollbackOpen(false)}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="text-2xs text-text-secondary bg-surface-subtle p-3 rounded-xl border border-border-subtle space-y-1">
              <div>
                <span className="font-semibold text-text-primary">Batch:</span> #{historySelectedBatch.id.slice(0, 8)} (
                {historySelectedBatch.fileName})
              </div>
              <div>
                <span className="font-semibold text-text-primary">Scope:</span> {historySelectedBatch.groupName} /{" "}
                {historySelectedBatch.accountName}
              </div>
            </div>

            <div className="space-y-3">
              <div>
                <label className="text-xs font-semibold text-text-primary block mb-1">Rollback Reason (Required)</label>
                <select
                  value={selectedRollbackReason}
                  onChange={(e) => setSelectedRollbackReason(e.target.value)}
                  className="w-full h-9 rounded-lg border border-border-subtle bg-surface px-3 text-xs text-text-primary focus:outline-hidden"
                >
                  {IMPORT_ROLLBACK_REASONS.map((r) => (
                    <option key={r.code} value={r.code}>
                      {r.label}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="text-xs font-semibold text-text-primary block mb-1">
                  Remarks / Justification (Min 10 characters)
                </label>
                <textarea
                  value={rollbackRemarks}
                  onChange={(e) => setRollbackRemarks(e.target.value)}
                  rows={3}
                  placeholder="Provide detailed audited reason for requesting this vacancy rollback..."
                  className="w-full rounded-lg border border-border-subtle bg-surface p-2.5 text-xs text-text-primary focus:outline-hidden resize-none"
                />
                <span
                  className={`text-3xs block text-right mt-1 ${
                    rollbackRemarks.trim().length >= 10 ? "text-emerald-700 font-semibold" : "text-text-muted"
                  }`}
                >
                  {rollbackRemarks.trim().length >= 10
                    ? "Remarks length requirement satisfied."
                    : `${10 - rollbackRemarks.trim().length} more characters required.`}
                </span>
              </div>
            </div>

            {rollbackActionError && (
              <div className="rounded-lg border border-rose-200 bg-rose-50 p-2.5 text-2xs text-rose-800">
                {rollbackActionError}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-border-subtle">
              <button
                onClick={() => setIsRequestRollbackOpen(false)}
                disabled={rollbackActionBusy}
                className="px-3.5 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                onClick={handleDoRequestRollback}
                disabled={rollbackActionBusy || rollbackRemarks.trim().length < 10}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-rose-700 text-xs font-semibold text-white hover:bg-rose-800 disabled:opacity-50"
              >
                {rollbackActionBusy && <Loader2 className="h-3 w-3 animate-spin" />}
                Submit Request
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 2: Approve & Execute Rollback Modal */}
      {isApproveRollbackConfirmOpen && historySelectedBatch && (
        <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
          <div className="relative w-full max-w-md rounded-2xl border border-border-subtle bg-surface p-6 shadow-2xl animate-in fade-in zoom-in-95 duration-150 space-y-4">
            <div className="flex items-center gap-2 pb-3 border-b border-border-subtle">
              <ShieldAlert className="h-5 w-5 text-rose-700" />
              <h3 className="text-sm font-bold text-text-primary">Approve and Execute Rollback?</h3>
            </div>

            <div className="rounded-xl border border-rose-200 bg-rose-50/90 p-3.5 text-2xs text-rose-900 leading-relaxed font-medium">
              This will soft-delete the imported vacancies from this batch and archive any seeded applicants. Records
              are preserved for audit. The same VCODE may be re-imported afterwards.
            </div>

            <div className="space-y-1.5 text-2xs bg-surface-subtle p-3 rounded-xl border border-border-subtle">
              <div>
                <span className="text-text-muted">Requested Reason:</span>{" "}
                <span className="font-semibold text-text-primary">
                  {IMPORT_ROLLBACK_REASONS.find((r) => r.code === historySelectedBatch.rollbackReasonCode)?.label ||
                    historySelectedBatch.rollbackReason ||
                    "—"}
                </span>
              </div>
              {historySelectedBatch.rollbackReasonNote && (
                <div>
                  <span className="text-text-muted">Remarks:</span>{" "}
                  <span className="text-text-secondary">{historySelectedBatch.rollbackReasonNote}</span>
                </div>
              )}
              {historySelectedBatch.rollbackRequestedBy && (
                <div>
                  <span className="text-text-muted">Requested By:</span>{" "}
                  <span className="font-semibold text-text-primary">{historySelectedBatch.rollbackRequestedBy}</span>
                </div>
              )}
            </div>

            {rollbackActionError && (
              <div className="rounded-lg border border-rose-200 bg-rose-50 p-2.5 text-2xs text-rose-800">
                {rollbackActionError}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-border-subtle">
              <button
                onClick={() => setIsApproveRollbackConfirmOpen(false)}
                disabled={rollbackActionBusy}
                className="px-3.5 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                onClick={handleDoApproveRollback}
                disabled={rollbackActionBusy}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-rose-800 text-xs font-semibold text-white hover:bg-rose-900 disabled:opacity-50"
              >
                {rollbackActionBusy && <Loader2 className="h-3 w-3 animate-spin" />}
                Execute Rollback
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 3: Emergency Rollback Override Modal */}
      {isEmergencyRollbackOpen && historySelectedBatch && (
        <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
          <div className="relative w-full max-w-md rounded-2xl border border-border-subtle bg-surface p-6 shadow-2xl animate-in fade-in zoom-in-95 duration-150 space-y-4">
            <div className="flex items-center justify-between pb-3 border-b border-border-subtle">
              <div className="flex items-center gap-2">
                <ShieldAlert className="h-5 w-5 text-rose-700" />
                <h3 className="text-sm font-bold text-text-primary">Emergency Rollback Override</h3>
              </div>
              <button
                onClick={() => setIsEmergencyRollbackOpen(false)}
                className="text-text-muted hover:text-text-primary"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="rounded-xl border border-rose-300 bg-rose-50 p-3 text-2xs text-rose-900 leading-relaxed font-medium">
              Super Admin Emergency Override: Bypasses standard window or block constraints. All actions are
              permanently recorded in immutable audit logs.
            </div>

            <div>
              <label className="text-xs font-semibold text-text-primary block mb-1">
                Emergency Justification (Minimum 50 characters required)
              </label>
              <textarea
                value={emergencyReason}
                onChange={(e) => setEmergencyReason(e.target.value)}
                rows={4}
                placeholder="State the comprehensive business and operational justification for this emergency override..."
                className="w-full rounded-lg border border-border-subtle bg-surface p-2.5 text-xs text-text-primary focus:outline-hidden resize-none"
              />
              <span
                className={`text-3xs block text-right mt-1 ${
                  emergencyReason.trim().length >= 50 ? "text-emerald-700 font-semibold" : "text-text-muted"
                }`}
              >
                {emergencyReason.trim().length >= 50
                  ? "Emergency justification requirement satisfied."
                  : `${50 - emergencyReason.trim().length} more characters required.`}
              </span>
            </div>

            {rollbackActionError && (
              <div className="rounded-lg border border-rose-200 bg-rose-50 p-2.5 text-2xs text-rose-800">
                {rollbackActionError}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-border-subtle">
              <button
                onClick={() => setIsEmergencyRollbackOpen(false)}
                disabled={rollbackActionBusy}
                className="px-3.5 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                onClick={handleDoEmergencyRollback}
                disabled={rollbackActionBusy || emergencyReason.trim().length < 50}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-lg bg-rose-950 text-xs font-semibold text-rose-100 hover:bg-black disabled:opacity-50"
              >
                {rollbackActionBusy && <Loader2 className="h-3 w-3 animate-spin" />}
                Execute Override
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 4: Rollback History View Modal */}
      <VacancyRollbackHistoryModal
        isOpen={isRollbackHistoryOpen}
        onClose={() => setIsRollbackHistoryOpen(false)}
        batchId={historySelectedBatch?.id ?? null}
      />
    </div>
  );
}

function VacancyRollbackHistoryModal({
  isOpen,
  onClose,
  batchId,
}: {
  isOpen: boolean;
  onClose: () => void;
  batchId: string | null;
}) {
  const { data: history, isLoading, refetch } = useVacancyImportRollbackHistory(isOpen ? batchId : null);

  if (!isOpen || !batchId) return null;

  return (
    <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
      <div className="relative w-full max-w-lg rounded-2xl border border-border-subtle bg-surface p-6 shadow-2xl animate-in fade-in zoom-in-95 duration-150 space-y-4">
        <div className="flex items-center justify-between pb-3 border-b border-border-subtle">
          <div className="flex items-center gap-2">
            <History className="h-5 w-5 text-purple-600" />
            <h3 className="text-sm font-bold text-text-primary">Vacancy Rollback Audit History</h3>
          </div>
          <button
            onClick={onClose}
            className="flex h-7 w-7 items-center justify-center rounded-lg text-text-muted hover:bg-surface-hover hover:text-text-primary"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="py-2 space-y-3">
          {isLoading ? (
            <div className="flex items-center justify-center py-8 text-xs text-text-muted">
              <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rollback timeline...
            </div>
          ) : !history || !history.status ? (
            <div className="py-8 text-center text-xs text-text-muted">
              No rollback request has been submitted for this vacancy batch.
            </div>
          ) : (
            <div className="space-y-3 text-xs">
              <div className="flex items-center justify-between p-3 rounded-xl bg-surface-subtle border border-border-subtle">
                <span className="font-semibold text-text-secondary">Current Status</span>
                <span
                  className={`rounded-md px-2 py-0.5 text-3xs font-bold uppercase ${
                    history.status === "completed"
                      ? "bg-emerald-100 text-emerald-800"
                      : history.status === "requested"
                      ? "bg-amber-100 text-amber-800"
                      : "bg-rose-100 text-rose-800"
                  }`}
                >
                  {history.status}
                </span>
              </div>

              <div className="space-y-2 p-3 rounded-xl border border-border-subtle bg-surface">
                <div className="flex justify-between text-2xs">
                  <span className="text-text-muted">Requested By:</span>
                  <span className="font-medium text-text-primary">{history.requestedBy || "—"}</span>
                </div>
                <div className="flex justify-between text-2xs">
                  <span className="text-text-muted">Requested At:</span>
                  <span className="font-medium text-text-primary">
                    {history.requestedAt ? new Date(history.requestedAt).toLocaleString() : "—"}
                  </span>
                </div>
                <div className="pt-2 border-t border-border-subtle">
                  <span className="text-2xs text-text-muted block">Reason:</span>
                  <span className="font-semibold text-text-primary block mt-0.5">
                    {IMPORT_ROLLBACK_REASONS.find((r) => r.code === history.reasonCode)?.label ||
                      history.reason ||
                      "—"}
                  </span>
                </div>
                {history.reasonNote && (
                  <div className="pt-1">
                    <span className="text-2xs text-text-muted block">Remarks:</span>
                    <span className="text-text-secondary block mt-0.5 bg-surface-subtle p-2 rounded-lg border border-border-subtle">
                      {history.reasonNote}
                    </span>
                  </div>
                )}
              </div>

              {history.approvedAt && (
                <div className="space-y-2 p-3 rounded-xl border border-border-subtle bg-surface">
                  <div className="flex justify-between text-2xs">
                    <span className="text-text-muted">Approved By:</span>
                    <span className="font-medium text-text-primary">{history.approvedBy || "—"}</span>
                  </div>
                  <div className="flex justify-between text-2xs">
                    <span className="text-text-muted">Approved At:</span>
                    <span className="font-medium text-text-primary">
                      {new Date(history.approvedAt).toLocaleString()}
                    </span>
                  </div>
                  {history.completedAt && (
                    <div className="flex justify-between text-2xs">
                      <span className="text-text-muted">Completed At:</span>
                      <span className="font-medium text-emerald-700">
                        {new Date(history.completedAt).toLocaleString()}
                      </span>
                    </div>
                  )}
                  {history.vacanciesCount !== undefined && (
                    <div className="flex justify-between text-2xs">
                      <span className="text-text-muted">Vacancies Rolled Back:</span>
                      <span className="font-semibold text-text-primary">{history.vacanciesCount}</span>
                    </div>
                  )}
                  {history.applicantsCount !== undefined && (
                    <div className="flex justify-between text-2xs">
                      <span className="text-text-muted">Applicants Archived:</span>
                      <span className="font-semibold text-text-primary">{history.applicantsCount}</span>
                    </div>
                  )}
                  {history.errorDetail && (
                    <div className="pt-2 border-t border-border-subtle text-rose-700 text-2xs font-semibold">
                      Error: {humanizeRollbackError(history.errorDetail)}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>

        <div className="flex justify-between items-center pt-3 border-t border-border-subtle">
          <button
            onClick={() => refetch()}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-border-subtle text-2xs font-semibold text-text-secondary hover:bg-surface-hover"
          >
            <RefreshCw className="h-3.5 w-3.5" /> Refresh
          </button>
          <button
            onClick={onClose}
            className="px-4 py-1.5 rounded-lg bg-surface-subtle border border-border-subtle text-xs font-semibold text-text-primary hover:bg-surface-hover"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
