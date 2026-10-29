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
} from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { Modal } from "@/components/shared/Modal";
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
  const isBusy = isSubmitting || isActionPending || rollbackActionBusy;

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title={
          <span className="flex items-center gap-2">
            <span>Import Vacancy</span>
            <span className="rounded-md bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-semibold px-2 py-0.5 border border-[var(--border-subtle)]">
              Migration intake
            </span>
          </span>
        }
        subtitle="Bulk intake vacancy requisitions and pipeline allocations into operational scope groups."
        icon={FileSpreadsheet}
        maxWidthClass="max-w-5xl"
        disableBackdropClick={isBusy}
        isSubmitting={isBusy}
        footer={
          <div className="flex items-center justify-between w-full">
            <p className="text-xs text-[var(--text-muted)]">
              Full Mobile Vacancy Import Parity with slot binding and audit controls.
            </p>
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] text-sm font-semibold text-[var(--foreground)] hover:bg-[var(--surface-muted)] transition"
            >
              Close
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          {/* Tab Switcher */}
          <div className="flex items-center border-b border-[var(--border-subtle)] pb-2 gap-2">
            <button
              type="button"
              onClick={() => setActiveTab("upload")}
              className={`flex items-center gap-2 py-2 px-3 text-sm font-semibold border-b-2 transition ${
                activeTab === "upload"
                  ? "border-[var(--primary)] text-[var(--foreground)]"
                  : "border-transparent text-[var(--text-muted)] hover:text-[var(--foreground)]"
              }`}
            >
              <UploadCloud className="h-4 w-4" />
              Upload & Preview
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("review")}
              className={`flex items-center gap-2 py-2 px-3 text-sm font-semibold border-b-2 transition ${
                activeTab === "review"
                  ? "border-[var(--primary)] text-[var(--foreground)]"
                  : "border-transparent text-[var(--text-muted)] hover:text-[var(--foreground)]"
              }`}
            >
              <Layers className="h-4 w-4" />
              Review Queue
              {pendingBatches.length > 0 && (
                <span className="rounded-full bg-[var(--surface-sunken)] text-[var(--foreground)] font-bold px-1.5 py-0.5 text-xs">
                  {pendingBatches.length}
                </span>
              )}
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("history")}
              className={`flex items-center gap-2 py-2 px-3 text-sm font-semibold border-b-2 transition ${
                activeTab === "history"
                  ? "border-[var(--primary)] text-[var(--foreground)]"
                  : "border-transparent text-[var(--text-muted)] hover:text-[var(--foreground)]"
              }`}
            >
              <History className="h-4 w-4" />
              Import History
            </button>
          </div>

          {/* Tab 1: Upload */}
          {activeTab === "upload" && (
            <div className="space-y-6">
              {submitSuccess && (
                <div className="rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-muted)] p-3.5 flex items-start gap-3">
                  <CheckCircle2 className="h-5 w-5 text-[var(--foreground)] shrink-0 mt-0.5" />
                  <p className="text-sm font-medium text-[var(--foreground)]">{submitSuccess}</p>
                </div>
              )}

              {parseError && (
                <div className="rounded-xl border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3.5 flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-[var(--danger)] shrink-0 mt-0.5" />
                  <p className="text-sm font-medium text-[var(--danger)]">{parseError}</p>
                </div>
              )}

              {/* Scope & Template */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs font-bold text-[var(--text-muted)] mb-1.5">
                    1. Target Group
                  </label>
                  <select
                    value={selectedGroupId}
                    onChange={(e) => handleGroupSelect(e.target.value)}
                    className="w-full h-10 rounded-lg border border-border-default bg-surface-card px-3 text-sm font-medium text-text-primary focus:outline-hidden focus:border-brand-500 transition-colors"
                  >
                    <option value="" className="bg-surface-card text-text-primary">Select Operational Group...</option>
                    {groups.map((g) => (
                      <option key={g.id} value={g.id} className="bg-surface-card text-text-primary">
                        {g.label}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-bold text-[var(--text-muted)] mb-1.5">
                    2. Target Account
                  </label>
                  <select
                    value={selectedAccountId}
                    onChange={(e) => setSelectedAccountId(e.target.value)}
                    disabled={!selectedGroupId || isLoadingAccounts}
                    className="w-full h-10 rounded-lg border border-border-default bg-surface-card px-3 text-sm font-medium text-text-primary focus:outline-hidden focus:border-brand-500 transition-colors disabled:opacity-50"
                  >
                    <option value="" className="bg-surface-card text-text-primary">
                      {!selectedGroupId
                        ? "Select a group first..."
                        : isLoadingAccounts
                        ? "Loading accounts..."
                        : "Select Account Scope..."}
                    </option>
                    {accounts.map((a) => (
                      <option key={a.id} value={a.id} className="bg-surface-card text-text-primary">
                        {a.name}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="flex flex-col justify-end">
                  <button
                    type="button"
                    onClick={downloadVacancyImportTemplate}
                    className="h-10 inline-flex items-center justify-center gap-2 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] hover:bg-[var(--surface-muted)] text-[var(--foreground)] text-sm font-semibold transition"
                  >
                    <Download className="h-4 w-4" />
                    Download Vacancy Template
                  </button>
                </div>
              </div>

              {/* Dropzone */}
              <div
                onClick={() => fileInputRef.current?.click()}
                className="border-2 border-dashed border-[var(--border-subtle)] hover:border-[var(--primary)] bg-[var(--surface-muted)] hover:bg-[var(--surface-sunken)] rounded-2xl p-8 flex flex-col items-center justify-center cursor-pointer transition text-center"
              >
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".xlsx,.csv"
                  onChange={handleFileChange}
                  className="hidden"
                />
                <div className="h-12 w-12 rounded-xl bg-[var(--surface-sunken)] flex items-center justify-center text-[var(--foreground)] mb-3">
                  <UploadCloud className="h-6 w-6" />
                </div>
                <p className="text-sm font-semibold text-[var(--foreground)]">
                  {file ? file.name : "Click or drag & drop Vacancy XLSX or CSV file here"}
                </p>
                <p className="text-xs text-[var(--text-muted)] mt-1">
                  Supports Google Sheets migration exports and legacy vacancy requisitions.
                </p>
                {isParsing && (
                  <div className="flex items-center gap-2 mt-3 text-sm text-[var(--text-muted)]">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Validating vacancy requisition columns...
                  </div>
                )}
              </div>

              {/* Preview Table */}
              {parsedRows.length > 0 && (
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="text-sm font-bold text-[var(--foreground)]">
                      File Preview ({parsedRows.length} total rows)
                    </h3>
                    <span className="text-sm text-[var(--foreground)] font-semibold flex items-center gap-1">
                      <CheckCircle2 className="h-4 w-4 text-[var(--text-muted)]" /> Required vacancy fields validated
                    </span>
                  </div>

                  <div className="rounded-xl border border-[var(--border-subtle)] overflow-hidden max-h-60 overflow-y-auto">
                    <table className="w-full text-left text-sm">
                      <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)] sticky top-0 text-xs text-[var(--text-muted)] font-bold">
                        <tr>
                          <th className="py-2.5 px-3">#</th>
                          <th className="py-2.5 px-3">VCode</th>
                          <th className="py-2.5 px-3">Store Name</th>
                          <th className="py-2.5 px-3">Position</th>
                          <th className="py-2.5 px-3">HC</th>
                          <th className="py-2.5 px-3">Type</th>
                          <th className="py-2.5 px-3">Vacant Date</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-[var(--border-subtle)]">
                        {parsedRows.slice(0, 10).map((row, idx) => (
                          <tr key={idx} className="hover:bg-[var(--surface-muted)]/50">
                            <td className="py-2 px-3 text-[var(--text-muted)]">{idx + 1}</td>
                            <td className="py-2 px-3 font-semibold text-[var(--foreground)]">{row.VCODE || "—"}</td>
                            <td className="py-2 px-3 text-[var(--foreground)]">{row.STORE_NAME || "—"}</td>
                            <td className="py-2 px-3 text-[var(--text-muted)]">{row.POSITION || "—"}</td>
                            <td className="py-2 px-3 font-mono font-bold text-[var(--foreground)]">{row.HC || "1"}</td>
                            <td className="py-2 px-3 text-[var(--text-muted)]">{row.REQUEST_TYPE || "—"}</td>
                            <td className="py-2 px-3 text-[var(--text-subtle)]">{row.VACANT_DATE || "—"}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>

                  <div className="flex justify-end pt-2">
                    <button
                      type="button"
                      onClick={handleSubmit}
                      disabled={isSubmitting || !selectedGroupId || !selectedAccountId}
                      className="inline-flex items-center gap-2 rounded-xl bg-brand-button hover:bg-brand-button-hover text-white font-semibold text-sm px-5 py-2.5 transition shadow-xs disabled:opacity-50 cursor-pointer"
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

          {/* Tab 2: Review Queue */}
          {activeTab === "review" && (
            <div className="space-y-4">
              {actionError && (
                <div className="rounded-xl border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3.5 flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-[var(--danger)] shrink-0 mt-0.5" />
                  <p className="text-sm font-medium text-[var(--danger)]">{actionError}</p>
                </div>
              )}
              <div className="flex items-center justify-between">
                <p className="text-sm text-[var(--text-muted)]">
                  Pending vacancy migration batches awaiting administrative approval.
                </p>
                <button
                  type="button"
                  onClick={() => refetchBatches()}
                  className="inline-flex items-center gap-1.5 text-sm text-[var(--text-muted)] hover:text-[var(--foreground)] transition"
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                  Refresh
                </button>
              </div>

              {isLoadingBatches ? (
                <div className="flex justify-center p-8 text-sm text-[var(--text-muted)]">
                  <Loader2 className="h-5 w-5 animate-spin mr-2" /> Loading batches...
                </div>
              ) : pendingBatches.length === 0 ? (
                <div className="rounded-xl border border-dashed border-[var(--border-subtle)] p-8 text-center text-sm text-[var(--text-muted)]">
                  No vacancy batches currently awaiting approval.
                </div>
              ) : (
                <div className="space-y-3">
                  {pendingBatches.map((batch) => (
                    <div
                      key={batch.id}
                      className="rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] p-4 flex flex-col md:flex-row items-start md:items-center justify-between gap-4"
                    >
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-sm text-[var(--foreground)]">{batch.fileName}</span>
                          <span className="rounded-md bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-bold px-2 py-0.5 border border-[var(--border-subtle)]">
                            {batch.status.toUpperCase()}
                          </span>
                        </div>
                        <div className="text-xs text-[var(--text-muted)] flex flex-wrap gap-x-3 gap-y-1">
                          <span>Batch #{batch.id.slice(0, 8)}</span>
                          <span>Scope: {batch.groupName || "Group"} / {batch.accountName || "Account"}</span>
                          <span>Uploaded by: {batch.uploadedBy || "System"}</span>
                          <span>Rows: {batch.totalRows}</span>
                        </div>
                      </div>

                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => setSelectedBatchId(selectedBatchId === batch.id ? null : batch.id)}
                          className="h-9 px-3 rounded-lg border border-[var(--border-subtle)] text-sm font-semibold text-[var(--text-muted)] hover:text-[var(--foreground)] hover:bg-[var(--surface-muted)] transition"
                        >
                          {selectedBatchId === batch.id ? "Hide Rows" : "Inspect Rows"}
                        </button>

                        {canApprove && (
                          <>
                            <button
                              type="button"
                              onClick={() => handleApproveBatch(batch.id)}
                              disabled={isActionPending}
                              className="h-9 px-3 rounded-lg bg-brand-button hover:bg-brand-button-hover text-white text-sm font-semibold transition disabled:opacity-50"
                            >
                              Approve & Migrate
                            </button>
                            <button
                              type="button"
                              onClick={() => handleRejectBatch(batch.id)}
                              disabled={isActionPending}
                              className="h-9 px-3 rounded-lg bg-[var(--danger-bg)] hover:opacity-90 text-[var(--danger)] border border-[var(--danger-border)] text-sm font-semibold transition disabled:opacity-50"
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
                    <div className="rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-muted)]/50 p-4 space-y-3">
                      <div className="flex items-center justify-between">
                        <h4 className="text-sm font-bold text-[var(--foreground)]">
                          Inspect Batch Requisitions (#{selectedBatchId.slice(0, 8)})
                        </h4>
                        <span className="text-xs text-[var(--text-muted)]">{previewRows.length} requisitions</span>
                      </div>

                      {isLoadingPreviewRows ? (
                        <div className="flex justify-center p-6 text-sm text-[var(--text-muted)]">
                          <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rows...
                        </div>
                      ) : (
                        <div className="rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] overflow-x-auto max-h-56">
                          <table className="w-full text-left text-sm">
                            <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)] sticky top-0 text-xs text-[var(--text-muted)] font-bold">
                              <tr>
                                <th className="py-2 px-3">#</th>
                                <th className="py-2 px-3">Status</th>
                                <th className="py-2 px-3">VCode</th>
                                <th className="py-2 px-3">Store</th>
                                <th className="py-2 px-3">Position</th>
                                <th className="py-2 px-3">Tab</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-[var(--border-subtle)]">
                              {previewRows.map((r) => (
                                <tr key={r.rowNumber}>
                                  <td className="py-2 px-3 text-[var(--text-muted)]">{r.rowNumber}</td>
                                  <td className="py-2 px-3">
                                    <span className="rounded-md bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-bold px-1.5 py-0.5 border border-[var(--border-subtle)]">
                                      {r.validationStatus}
                                    </span>
                                  </td>
                                  <td className="py-2 px-3 font-semibold text-[var(--foreground)]">{r.vcode}</td>
                                  <td className="py-2 px-3 text-[var(--foreground)]">{r.storeName}</td>
                                  <td className="py-2 px-3 text-[var(--text-muted)]">{r.position}</td>
                                  <td className="py-2 px-3 text-sm font-bold text-[var(--foreground)]">{r.tab}</td>
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
                            className="w-full h-9 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] px-3 text-sm text-[var(--foreground)] focus:outline-hidden"
                          />
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {/* Tab 3: History */}
          {activeTab === "history" && (
            <div className="space-y-4">
              {historyBatches.length === 0 ? (
                <div className="rounded-xl border border-dashed border-[var(--border-subtle)] p-8 text-center text-sm text-[var(--text-muted)]">
                  No historical vacancy import logs recorded yet.
                </div>
              ) : (
                <div className="rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] overflow-hidden">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)] text-xs text-[var(--text-muted)] font-bold">
                      <tr>
                        <th className="py-2.5 px-4">File Name</th>
                        <th className="py-2.5 px-4">Status</th>
                        <th className="py-2.5 px-4">Rollback State & Window</th>
                        <th className="py-2.5 px-4">Scope</th>
                        <th className="py-2.5 px-4">Uploaded By</th>
                        <th className="py-2.5 px-4">Date</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--border-subtle)]">
                      {historyBatches.map((b) => {
                        const isSelected = historySelectedBatch?.id === b.id;
                        const isApproved = b.status.toLowerCase().includes("approved");

                        return (
                          <tr
                            key={b.id}
                            onClick={() => setHistorySelectedBatch(isSelected ? null : b)}
                            className={`cursor-pointer transition ${
                              isSelected ? "bg-[var(--surface-muted)]" : "hover:bg-[var(--surface-muted)]/50"
                            }`}
                          >
                            <td className="py-2.5 px-4 font-semibold text-[var(--foreground)]">
                              <div className="flex items-center gap-2">
                                <span>{b.fileName}</span>
                                {isSelected && (
                                  <span className="rounded-full bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-bold px-1.5 py-0.5 border border-[var(--border-subtle)]">
                                    Selected
                                  </span>
                                )}
                              </div>
                            </td>
                            <td className="py-2.5 px-4">
                              <span
                                className={`rounded-md px-2 py-0.5 text-xs font-bold  ${
                                  b.status.includes("rolled_back") || b.status.includes("reject")
                                    ? "bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)]"
                                    : "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                                }`}
                              >
                                {b.status}
                              </span>
                            </td>
                            <td className="py-2.5 px-4">
                              {b.rollbackStatus === "requested" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-[var(--surface-sunken)] text-[var(--foreground)] px-2 py-0.5 text-xs font-bold border border-[var(--border-subtle)]">
                                  <Clock className="h-3 w-3" /> Rollback Requested
                                </span>
                              ) : b.rollbackStatus === "completed" || b.status === "rolled_back" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-[var(--danger-bg)] text-[var(--danger)] px-2 py-0.5 text-xs font-bold border border-[var(--danger-border)]">
                                  <RotateCcw className="h-3 w-3" /> Rolled Back
                                </span>
                              ) : b.rollbackStatus === "failed" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-[var(--danger-bg)] text-[var(--danger)] px-2 py-0.5 text-xs font-bold border border-[var(--danger-border)]">
                                  <AlertCircle className="h-3 w-3" /> Rollback Failed
                                </span>
                              ) : isApproved ? (
                                b.rollbackAllowed ? (
                                  <span className="inline-flex items-center gap-1 rounded-md bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)] px-2 py-0.5 text-xs font-medium">
                                    <Clock className="h-3 w-3 text-[var(--text-muted)]" />
                                    Expires: {formatRollbackRemaining(b.rollbackRemainingSeconds)}
                                  </span>
                                ) : (
                                  <span className="rounded-md bg-[var(--surface-muted)] text-[var(--text-muted)] px-2 py-0.5 text-xs font-medium">
                                    Window Expired
                                  </span>
                                )
                              ) : (
                                <span className="text-[var(--text-subtle)] text-xs">—</span>
                              )}
                            </td>
                            <td className="py-2.5 px-4 text-[var(--text-muted)]">
                              {b.groupName ?? "—"} / {b.accountName ?? "—"}
                            </td>
                            <td className="py-2.5 px-4 text-[var(--text-muted)]">{b.uploadedBy || "—"}</td>
                            <td className="py-2.5 px-4 text-[var(--text-subtle)]">
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
                <div className="rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-muted)]/40 p-4 space-y-4">
                  <div className="flex items-center justify-between border-b border-[var(--border-subtle)] pb-3">
                    <div className="flex items-center gap-2">
                      <RotateCcw className="h-4 w-4 text-[var(--foreground)]" />
                      <h4 className="text-sm font-bold text-[var(--foreground)]">
                        Rollback Governance — #{historySelectedBatch.id.slice(0, 8)} ({historySelectedBatch.fileName})
                      </h4>
                    </div>
                    <button
                      type="button"
                      onClick={() => setHistorySelectedBatch(null)}
                      className="text-[var(--text-muted)] hover:text-[var(--foreground)] text-sm"
                    >
                      Close
                    </button>
                  </div>

                  {/* Summary / Meta */}
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                    <div className="p-2.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                      <span className="text-[var(--text-muted)] block">Batch Status</span>
                      <span className="font-bold text-[var(--foreground)] mt-0.5 block">
                        {historySelectedBatch.status}
                      </span>
                    </div>
                    <div className="p-2.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                      <span className="text-[var(--text-muted)] block">Rollback Status</span>
                      <span className="font-bold text-[var(--foreground)] mt-0.5 block">
                        {historySelectedBatch.rollbackStatus || "None"}
                      </span>
                    </div>
                    <div className="p-2.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                      <span className="text-[var(--text-muted)] block">Governance Window</span>
                      <span className="font-semibold text-[var(--foreground)] mt-0.5 block">
                        {historySelectedBatch.rollbackAllowed
                          ? `Active (${formatRollbackRemaining(historySelectedBatch.rollbackRemainingSeconds)} left)`
                          : "Expired / Inactive"}
                      </span>
                    </div>
                    <div className="p-2.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                      <span className="text-[var(--text-muted)] block">Total Vacancy Rows</span>
                      <span className="font-bold text-[var(--foreground)] mt-0.5 block">
                        {historySelectedBatch.totalRows} requisitions
                      </span>
                    </div>
                  </div>

                  {/* Block / Notice Warnings */}
                  {historySelectedBatch.rollbackBlockReason && (
                    <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-sm text-[var(--danger)] flex items-start gap-2 font-medium">
                      <AlertTriangle className="h-4 w-4 text-[var(--danger)] shrink-0 mt-0.5" />
                      <div>{humanizeRollbackError(historySelectedBatch.rollbackBlockReason)}</div>
                    </div>
                  )}

                  {historySelectedBatch.rollbackErrorDetail && (
                    <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-sm text-[var(--danger)] flex items-start gap-2">
                      <AlertCircle className="h-4 w-4 text-[var(--danger)] shrink-0 mt-0.5" />
                      <div>
                        Rollback attempt failed: {humanizeRollbackError(historySelectedBatch.rollbackErrorDetail)}
                      </div>
                    </div>
                  )}

                  {rollbackActionSuccess && (
                    <div className="rounded-lg border border-[var(--border-subtle)] bg-[var(--surface-muted)] p-3 text-sm text-[var(--foreground)] flex items-center gap-2">
                      <CheckCircle2 className="h-4 w-4 shrink-0" />
                      <span>{rollbackActionSuccess}</span>
                    </div>
                  )}

                  {rollbackActionError && (
                    <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-sm text-[var(--danger)] flex items-center gap-2">
                      <AlertCircle className="h-4 w-4 text-[var(--danger)] shrink-0" />
                      <span>{rollbackActionError}</span>
                    </div>
                  )}

                  {/* Actions Bar */}
                  <div className="flex flex-wrap items-center gap-2 pt-1">
                    <button
                      type="button"
                      onClick={() => setIsRollbackHistoryOpen(true)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] text-sm font-semibold text-[var(--foreground)] hover:bg-[var(--surface-muted)] transition"
                    >
                      <History className="h-4 w-4 text-[var(--text-muted)]" />
                      View Rollback History
                    </button>

                    {canRequestRollback &&
                      historySelectedBatch.rollbackAllowed &&
                      historySelectedBatch.rollbackStatus !== "requested" &&
                      historySelectedBatch.rollbackStatus !== "completed" && (
                        <button
                          type="button"
                          onClick={() => {
                            setSelectedRollbackReason("wrong_batch");
                            setRollbackRemarks("");
                            setRollbackActionError(null);
                            setIsRequestRollbackOpen(true);
                          }}
                          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] text-sm font-semibold text-[var(--danger)] hover:opacity-90 transition"
                        >
                          <RotateCcw className="h-4 w-4 text-[var(--danger)]" />
                          Request Rollback
                        </button>
                      )}

                    {isSuperAdmin &&
                      historySelectedBatch.status.toLowerCase().includes("approved") &&
                      historySelectedBatch.rollbackStatus === "requested" && (
                        <button
                          type="button"
                          onClick={() => {
                            setRollbackActionError(null);
                            setIsApproveRollbackConfirmOpen(true);
                          }}
                          className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-[var(--danger)] text-sm font-semibold text-white hover:opacity-90 transition"
                        >
                          <ShieldCheck className="h-4 w-4" />
                          Approve & Execute Rollback
                        </button>
                      )}

                    {isSuperAdmin && historySelectedBatch.canEmergencyRollback && (
                      <button
                        type="button"
                        onClick={() => {
                          setEmergencyReason("");
                          setRollbackActionError(null);
                          setIsEmergencyRollbackOpen(true);
                        }}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--danger)] text-sm font-semibold text-white hover:opacity-90 transition"
                      >
                        <ShieldAlert className="h-4 w-4" />
                        Emergency Rollback Override
                      </button>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </Modal>

      {/* SUB-MODAL 1: Request Rollback Modal */}
      {isRequestRollbackOpen && historySelectedBatch && (
        <Modal
          isOpen={isRequestRollbackOpen}
          onClose={() => setIsRequestRollbackOpen(false)}
          title={
            <span className="flex items-center gap-2">
              <span>Request Vacancy Import Rollback</span>
              <span className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] text-xs font-semibold px-2 py-0.5 border border-[var(--danger-border)]">
                Destructive
              </span>
            </span>
          }
          subtitle={`Batch: #${historySelectedBatch.id.slice(0, 8)} (${historySelectedBatch.fileName})`}
          icon={RotateCcw}
          maxWidthClass="max-w-md"
          disableBackdropClick={rollbackActionBusy}
          isSubmitting={rollbackActionBusy}
          isDirty={Boolean(rollbackRemarks.trim())}
        >
          <div className="space-y-4">
            <div className="text-xs text-[var(--text-muted)] bg-[var(--surface-muted)] p-3 rounded-xl border border-[var(--border-subtle)] space-y-1">
              <div>
                <span className="font-semibold text-[var(--foreground)]">Batch:</span> #{historySelectedBatch.id.slice(0, 8)} (
                {historySelectedBatch.fileName})
              </div>
              <div>
                <span className="font-semibold text-[var(--foreground)]">Scope:</span> {historySelectedBatch.groupName} /{" "}
                {historySelectedBatch.accountName}
              </div>
            </div>

            <div className="space-y-3">
              <div>
                <label className="text-sm font-semibold text-[var(--foreground)] block mb-1">
                  Rollback Reason (Required)
                </label>
                <select
                  value={selectedRollbackReason}
                  onChange={(e) => setSelectedRollbackReason(e.target.value)}
                  className="w-full h-10 rounded-lg border border-border-default bg-surface-card px-3 text-sm text-text-primary focus:outline-hidden focus:border-brand-500 transition-colors"
                >
                  {IMPORT_ROLLBACK_REASONS.map((r) => (
                    <option key={r.code} value={r.code} className="bg-surface-card text-text-primary">
                      {r.label}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="text-sm font-semibold text-[var(--foreground)] block mb-1">
                  Remarks / Justification (Min 10 characters)
                </label>
                <textarea
                  value={rollbackRemarks}
                  onChange={(e) => setRollbackRemarks(e.target.value)}
                  rows={3}
                  placeholder="Provide detailed audited reason for requesting this vacancy rollback..."
                  className="w-full rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] p-2.5 text-sm text-[var(--foreground)] focus:outline-hidden resize-none"
                />
                <span
                  className={`text-xs block text-right mt-1 ${
                    rollbackRemarks.trim().length >= 10 ? "text-[var(--foreground)] font-semibold" : "text-[var(--text-muted)]"
                  }`}
                >
                  {rollbackRemarks.trim().length >= 10
                    ? "Remarks length requirement satisfied."
                    : `${10 - rollbackRemarks.trim().length} more characters required.`}
                </span>
              </div>
            </div>

            {rollbackActionError && (
              <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-2.5 text-xs text-[var(--danger)]">
                {rollbackActionError}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border-subtle)]">
              <button
                type="button"
                onClick={() => setIsRequestRollbackOpen(false)}
                disabled={rollbackActionBusy}
                className="px-3.5 py-2 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] text-sm font-semibold text-[var(--text-muted)] hover:bg-[var(--surface-muted)]"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleDoRequestRollback}
                disabled={rollbackActionBusy || rollbackRemarks.trim().length < 10}
                className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-[var(--danger)] text-sm font-semibold text-white hover:opacity-90 disabled:opacity-50"
              >
                {rollbackActionBusy && <Loader2 className="h-4 w-4 animate-spin" />}
                Submit Request
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* SUB-MODAL 2: Approve & Execute Rollback Modal */}
      {isApproveRollbackConfirmOpen && historySelectedBatch && (
        <Modal
          isOpen={isApproveRollbackConfirmOpen}
          onClose={() => setIsApproveRollbackConfirmOpen(false)}
          title={
            <span className="flex items-center gap-2">
              <span>Approve and Execute Rollback?</span>
              <span className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] text-xs font-semibold px-2 py-0.5 border border-[var(--danger-border)]">
                Destructive
              </span>
            </span>
          }
          icon={ShieldAlert}
          maxWidthClass="max-w-md"
          disableBackdropClick={rollbackActionBusy}
          isSubmitting={rollbackActionBusy}
        >
          <div className="space-y-4">
            <div className="rounded-xl border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3.5 text-sm text-[var(--danger)] leading-relaxed font-medium">
              This will soft-delete the imported vacancies from this batch and archive any seeded applicants. Records
              are preserved for audit. The same VCODE may be re-imported afterwards.
            </div>

            <div className="space-y-1.5 text-xs bg-[var(--surface-muted)] p-3 rounded-xl border border-[var(--border-subtle)]">
              <div>
                <span className="text-[var(--text-muted)]">Requested Reason:</span>{" "}
                <span className="font-semibold text-[var(--foreground)]">
                  {IMPORT_ROLLBACK_REASONS.find((r) => r.code === historySelectedBatch.rollbackReasonCode)?.label ||
                    historySelectedBatch.rollbackReason ||
                    "—"}
                </span>
              </div>
              {historySelectedBatch.rollbackReasonNote && (
                <div>
                  <span className="text-[var(--text-muted)]">Remarks:</span>{" "}
                  <span className="text-[var(--foreground)]">{historySelectedBatch.rollbackReasonNote}</span>
                </div>
              )}
              {historySelectedBatch.rollbackRequestedBy && (
                <div>
                  <span className="text-[var(--text-muted)]">Requested By:</span>{" "}
                  <span className="font-semibold text-[var(--foreground)]">{historySelectedBatch.rollbackRequestedBy}</span>
                </div>
              )}
            </div>

            {rollbackActionError && (
              <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-2.5 text-xs text-[var(--danger)]">
                {rollbackActionError}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border-subtle)]">
              <button
                type="button"
                onClick={() => setIsApproveRollbackConfirmOpen(false)}
                disabled={rollbackActionBusy}
                className="px-3.5 py-2 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] text-sm font-semibold text-[var(--text-muted)] hover:bg-[var(--surface-muted)]"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleDoApproveRollback}
                disabled={rollbackActionBusy}
                className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-[var(--danger)] text-sm font-semibold text-white hover:opacity-90 disabled:opacity-50"
              >
                {rollbackActionBusy && <Loader2 className="h-4 w-4 animate-spin" />}
                Execute Rollback
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* SUB-MODAL 3: Emergency Rollback Override Modal */}
      {isEmergencyRollbackOpen && historySelectedBatch && (
        <Modal
          isOpen={isEmergencyRollbackOpen}
          onClose={() => setIsEmergencyRollbackOpen(false)}
          title={
            <span className="flex items-center gap-2">
              <span>Emergency Rollback Override</span>
              <span className="rounded-md bg-surface-muted text-text-primary text-xs font-semibold px-2 py-0.5 border border-border-default">
                Emergency override
              </span>
            </span>
          }
          icon={ShieldAlert}
          maxWidthClass="max-w-md"
          disableBackdropClick={rollbackActionBusy}
          isSubmitting={rollbackActionBusy}
          isDirty={Boolean(emergencyReason.trim())}
        >
          <div className="space-y-4">
            <div className="rounded-xl border border-border-default bg-surface-muted p-3 text-sm text-text-primary leading-relaxed font-medium">
              Super Admin Emergency Override: Bypasses standard window or block constraints. All actions are
              permanently recorded in immutable audit logs.
            </div>

            <div>
              <label className="text-sm font-semibold text-[var(--foreground)] block mb-1">
                Emergency Justification (Minimum 50 characters required)
              </label>
              <textarea
                value={emergencyReason}
                onChange={(e) => setEmergencyReason(e.target.value)}
                rows={4}
                placeholder="State the comprehensive business and operational justification for this emergency override..."
                className="w-full rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] p-2.5 text-sm text-[var(--foreground)] focus:outline-hidden resize-none"
              />
              <span
                className={`text-xs block text-right mt-1 ${
                  emergencyReason.trim().length >= 50 ? "text-[var(--foreground)] font-semibold" : "text-[var(--text-muted)]"
                }`}
              >
                {emergencyReason.trim().length >= 50
                  ? "Emergency justification requirement satisfied."
                  : `${50 - emergencyReason.trim().length} more characters required.`}
              </span>
            </div>

            {rollbackActionError && (
              <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-2.5 text-xs text-[var(--danger)]">
                {rollbackActionError}
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border-subtle)]">
              <button
                type="button"
                onClick={() => setIsEmergencyRollbackOpen(false)}
                disabled={rollbackActionBusy}
                className="px-3.5 py-2 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] text-sm font-semibold text-[var(--text-muted)] hover:bg-[var(--surface-muted)]"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleDoEmergencyRollback}
                disabled={rollbackActionBusy || emergencyReason.trim().length < 50}
                className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-[var(--danger)] text-sm font-semibold text-white hover:opacity-90 disabled:opacity-50"
              >
                {rollbackActionBusy && <Loader2 className="h-4 w-4 animate-spin" />}
                Execute Override
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* MODAL 4: Rollback History View Modal */}
      <VacancyRollbackHistoryModal
        isOpen={isRollbackHistoryOpen}
        onClose={() => setIsRollbackHistoryOpen(false)}
        batchId={historySelectedBatch?.id ?? null}
      />
    </>
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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Vacancy Rollback Audit History"
      icon={History}
      maxWidthClass="max-w-lg"
      footer={
        <div className="flex justify-between items-center w-full">
          <button
            type="button"
            onClick={() => refetch()}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[var(--border-subtle)] text-xs font-semibold text-[var(--text-muted)] hover:text-[var(--foreground)] hover:bg-[var(--surface-muted)]"
          >
            <RefreshCw className="h-3.5 w-3.5" /> Refresh
          </button>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-1.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)] text-sm font-semibold text-[var(--foreground)] hover:bg-[var(--surface-muted)]"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="py-2 space-y-3">
        {isLoading ? (
          <div className="flex items-center justify-center py-8 text-sm text-[var(--text-muted)]">
            <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rollback timeline...
          </div>
        ) : !history || !history.status ? (
          <div className="py-8 text-center text-sm text-[var(--text-muted)]">
            No rollback request has been submitted for this vacancy batch.
          </div>
        ) : (
          <div className="space-y-3 text-sm">
            <div className="flex items-center justify-between p-3 rounded-xl bg-[var(--surface-muted)] border border-[var(--border-subtle)]">
              <span className="font-semibold text-[var(--foreground)]">Current Status</span>
              <span
                className={`rounded-md px-2 py-0.5 text-xs font-bold  ${
                  history.status === "failed"
                    ? "bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)]"
                    : "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                }`}
              >
                {history.status}
              </span>
            </div>

            <div className="space-y-2 p-3 rounded-xl border border-[var(--border-subtle)] bg-[var(--card)]">
              <div className="flex justify-between text-xs">
                <span className="text-[var(--text-muted)]">Requested By:</span>
                <span className="font-medium text-[var(--foreground)]">{history.requestedBy || "—"}</span>
              </div>
              <div className="flex justify-between text-xs">
                <span className="text-[var(--text-muted)]">Requested At:</span>
                <span className="font-medium text-[var(--foreground)]">
                  {history.requestedAt ? new Date(history.requestedAt).toLocaleString() : "—"}
                </span>
              </div>
              <div className="pt-2 border-t border-[var(--border-subtle)]">
                <span className="text-xs text-[var(--text-muted)] block">Reason:</span>
                <span className="font-semibold text-[var(--foreground)] block mt-0.5">
                  {IMPORT_ROLLBACK_REASONS.find((r) => r.code === history.reasonCode)?.label ||
                    history.reason ||
                    "—"}
                </span>
              </div>
              {history.reasonNote && (
                <div className="pt-1">
                  <span className="text-xs text-[var(--text-muted)] block">Remarks:</span>
                  <span className="text-[var(--text-muted)] block mt-0.5 bg-[var(--surface-muted)] p-2 rounded-lg border border-[var(--border-subtle)]">
                    {history.reasonNote}
                  </span>
                </div>
              )}
            </div>

            {history.approvedAt && (
              <div className="space-y-2 p-3 rounded-xl border border-[var(--border-subtle)] bg-[var(--card)]">
                <div className="flex justify-between text-xs">
                  <span className="text-[var(--text-muted)]">Approved By:</span>
                  <span className="font-medium text-[var(--foreground)]">{history.approvedBy || "—"}</span>
                </div>
                <div className="flex justify-between text-xs">
                  <span className="text-[var(--text-muted)]">Approved At:</span>
                  <span className="font-medium text-[var(--foreground)]">
                    {new Date(history.approvedAt).toLocaleString()}
                  </span>
                </div>
                {history.completedAt && (
                  <div className="flex justify-between text-xs">
                    <span className="text-[var(--text-muted)]">Completed At:</span>
                    <span className="font-medium text-[var(--foreground)]">
                      {new Date(history.completedAt).toLocaleString()}
                    </span>
                  </div>
                )}
                {history.vacanciesCount !== undefined && (
                  <div className="flex justify-between text-xs">
                    <span className="text-[var(--text-muted)]">Vacancies Rolled Back:</span>
                    <span className="font-semibold text-[var(--foreground)]">{history.vacanciesCount}</span>
                  </div>
                )}
                {history.applicantsCount !== undefined && (
                  <div className="flex justify-between text-xs">
                    <span className="text-[var(--text-muted)]">Applicants Archived:</span>
                    <span className="font-semibold text-[var(--foreground)]">{history.applicantsCount}</span>
                  </div>
                )}
                {history.errorDetail && (
                  <div className="pt-2 border-t border-[var(--border-subtle)] text-[var(--danger)] text-xs font-semibold">
                    Error: {humanizeRollbackError(history.errorDetail)}
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </Modal>
  );
}
