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
  downloadPlantillaImportTemplate,
  parseSpreadsheetToRows,
  PLANTILLA_REQUIRED_HEADERS,
  validateSpreadsheetScopeContext,
} from "@/lib/utils/data_control_xlsx";
import {
  approvePlantillaImportBatch,
  approvePlantillaImportRollback,
  emergencyRollbackPlantillaImport,
  formatRollbackRemaining,
  humanizeRollbackError,
  IMPORT_ROLLBACK_REASONS,
  PlantillaImportBatch,
  rejectPlantillaImportBatch,
  rejectPlantillaImportRollback,
  requestPlantillaImportRollback,
  submitPlantillaBaselineImport,
  SubmitPlantillaImportResult,
  useDataControlAccounts,
  useDataControlGroups,
  usePlantillaImportBatches,
  usePlantillaImportRollbackHistory,
  usePlantillaImportRows,
} from "@/lib/queries/dataControl";

export interface PlantillaImportModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type TabType = "upload" | "review" | "history";

function formatActor(actor?: string | null): string {
  if (!actor) return "—";
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (uuidRegex.test(actor)) {
    return `${actor.slice(0, 8)}...`;
  }
  return actor;
}

export function PlantillaImportModal({ isOpen, onClose }: PlantillaImportModalProps) {
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
  const [historySelectedBatch, setHistorySelectedBatch] = useState<PlantillaImportBatch | null>(null);
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

  type RowFilterType = "all" | "blocked" | "flagged" | "valid" | "skipped";
  const [rowFilter, setRowFilter] = useState<RowFilterType>("all");
  const [historyRowFilter, setHistoryRowFilter] = useState<RowFilterType>("all");
  const [reviewNotice, setReviewNotice] = useState<{ type: "error" | "warning" | "success"; message: string } | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const { data: groups = [] } = useDataControlGroups();
  const { data: accounts = [], isLoading: isLoadingAccounts } = useDataControlAccounts(selectedGroupId || null);
  const { data: batches = [], refetch: refetchBatches, isLoading: isLoadingBatches } = usePlantillaImportBatches();
  const { data: previewRows = [], isLoading: isLoadingPreviewRows } = usePlantillaImportRows(selectedBatchId);
  const { data: historyRows = [], isLoading: isLoadingHistoryRows } = usePlantillaImportRows(historySelectedBatch?.id || null);

  const filteredPreviewRows = useMemo(() => {
    if (rowFilter === "all") return previewRows;
    return previewRows.filter((r) => r.validationStatus === rowFilter);
  }, [previewRows, rowFilter]);

  const filteredHistoryRows = useMemo(() => {
    if (historyRowFilter === "all") return historyRows;
    return historyRows.filter((r) => r.validationStatus === historyRowFilter);
  }, [historyRows, historyRowFilter]);

  // RBAC resolution
  const roleStr = useMemo(() => {
    return (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
  }, [currentUser]);

  const isSuperAdmin = useMemo(() => {
    return roleStr.includes("super_admin") || roleStr === "sa";
  }, [roleStr]);

  const isHeadAdmin = useMemo(() => {
    return roleStr.includes("head_admin") || roleStr === "ha";
  }, [roleStr]);

  const isEncoder = useMemo(() => {
    return roleStr.includes("encoder");
  }, [roleStr]);

  const canApprove = useMemo(() => {
    return isSuperAdmin || isHeadAdmin;
  }, [isSuperAdmin, isHeadAdmin]);

  const canRequestRollback = useMemo(() => {
    return isSuperAdmin || isHeadAdmin || isEncoder;
  }, [isSuperAdmin, isHeadAdmin, isEncoder]);

  const reviewableStatuses = useMemo(
    () => new Set(["draft_uploaded", "pending_approval", "validation_failed", "blocked", "partially_blocked"]),
    []
  );
  const pendingBatches = useMemo(
    () => batches.filter((b) => reviewableStatuses.has(b.status)),
    [batches, reviewableStatuses]
  );
  const historyBatches = useMemo(
    () => batches.filter((b) => !reviewableStatuses.has(b.status)),
    [batches, reviewableStatuses]
  );

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
      const missing = PLANTILLA_REQUIRED_HEADERS.filter((req) => !upperHeaders.has(req));

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

    const currentGroup = groups.find((g) => g.id === selectedGroupId);
    const currentAccount = accounts.find((a) => a.id === selectedAccountId);
    const scopeCheck = validateSpreadsheetScopeContext(
      parsedRows,
      currentGroup?.label,
      currentAccount?.name
    );
    if (!scopeCheck.valid) {
      setParseError(scopeCheck.errors.join(" | "));
      return;
    }

    setIsSubmitting(true);
    setParseError(null);
    setReviewNotice(null);
    try {
      const result: SubmitPlantillaImportResult = await submitPlantillaBaselineImport({
        fileName: file.name,
        groupId: selectedGroupId,
        accountId: selectedAccountId,
        rows: parsedRows,
      });

      if (result.status === "validation_failed" || result.blockedRows > 0) {
        setSubmitSuccess(null);
        setReviewNotice({
          type: "error",
          message: `Plantilla batch #${result.batchId.slice(0, 8)} uploaded but has ${result.blockedRows} row(s) failing validation. Review row details below.`,
        });
        setRowFilter("blocked");
      } else {
        setSubmitSuccess(
          `Plantilla batch #${result.batchId} submitted successfully for review (${result.validRows} valid rows).`
        );
        setReviewNotice({
          type: "success",
          message: `Plantilla batch #${result.batchId.slice(0, 8)} submitted successfully for review (${result.validRows} valid rows).`,
        });
        setRowFilter("all");
      }

      setFile(null);
      setParsedRows([]);
      if (fileInputRef.current) fileInputRef.current.value = "";
      refetchBatches();
      setActiveTab("review");
      setSelectedBatchId(result.batchId);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : "Failed to submit plantilla import batch.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleApproveBatch = async (batchId: string) => {
    setIsActionPending(true);
    setActionError(null);
    try {
      await approvePlantillaImportBatch(batchId);
      refetchBatches();
      setSelectedBatchId(null);
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to approve plantilla batch.");
    } finally {
      setIsActionPending(false);
    }
  };

  const handleRejectBatch = async (batchId: string, isValidationFailed?: boolean) => {
    setIsActionPending(true);
    setActionError(null);
    try {
      const note = actionReason.trim()
        ? actionReason.trim()
        : isValidationFailed
        ? "Dismissed: Batch failed ADR-001 or row validation checks."
        : "";
      if (!note && !isValidationFailed) {
        setActionError("Please provide an audited reason note for rejection.");
        setIsActionPending(false);
        return;
      }
      await rejectPlantillaImportBatch({
        batchId,
        reasonCode: isValidationFailed ? "invalid_csv" : "other",
        reasonNote: note,
      });
      refetchBatches();
      setSelectedBatchId(null);
      setActionReason("");
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to reject plantilla batch.");
    } finally {
      setIsActionPending(false);
    }
  };

  const handleRollbackSuccess = (msg: string) => {
    setRollbackActionSuccess(msg);
    setRollbackActionError(null);
    refetchBatches();
    queryClient.invalidateQueries({ queryKey: ["plantilla-import-batches"] });
    queryClient.invalidateQueries({ queryKey: ["plantilla-import-rollback-history"] });
    queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    queryClient.invalidateQueries({ queryKey: ["plantilla-scope-menu"] });
  };

  const handleDoRequestRollback = async () => {
    if (!historySelectedBatch || !selectedRollbackReason || rollbackRemarks.trim().length < 10) return;
    setRollbackActionBusy(true);
    setRollbackActionError(null);
    try {
      await requestPlantillaImportRollback({
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
      await approvePlantillaImportRollback(historySelectedBatch.id);
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
      await emergencyRollbackPlantillaImport({
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
                <h2 className="text-base font-bold text-text-primary">Import Plantilla</h2>
                <span className="rounded-md bg-purple-100 text-purple-800 px-2 py-0.5 text-3xs font-bold uppercase tracking-wider">
                  BULK BASELINE
                </span>
              </div>
              <p className="text-xs text-text-secondary">
                Ingest master store plantilla baselines, slot capacities, and employee assignments via CSV/XLSX.
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

        {/* Body content */}
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

              {/* Scope selectors & Template Download */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-2xs font-bold text-text-secondary uppercase mb-1.5">
                    1. Target Group
                  </label>
                  <select
                    value={selectedGroupId}
                    onChange={(e) => handleGroupSelect(e.target.value)}
                    className="w-full h-9 rounded-lg border border-border-subtle bg-surface px-3 text-xs font-medium text-text-primary focus:outline-hidden focus:ring-1 focus:ring-purple-500"
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
                    className="w-full h-9 rounded-lg border border-border-subtle bg-surface px-3 text-xs font-medium text-text-primary focus:outline-hidden focus:ring-1 focus:ring-purple-500 disabled:opacity-50"
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
                    onClick={downloadPlantillaImportTemplate}
                    className="h-9 inline-flex items-center justify-center gap-2 rounded-lg border border-border-subtle bg-surface hover:bg-surface-hover text-text-primary text-xs font-semibold transition"
                  >
                    <Download className="h-4 w-4 text-purple-600" />
                    Download Official Template
                  </button>
                </div>
              </div>

              {/* Upload Dropzone */}
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
                  {file ? file.name : "Click or drag & drop Plantilla XLSX or CSV file here"}
                </p>
                <p className="text-xs text-text-muted mt-1">
                  Supports Store Master & Baseline Plantilla with slot capacities and initial employee bindings.
                </p>
                {isParsing && (
                  <div className="flex items-center gap-2 mt-3 text-xs text-purple-700">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Parsing and validating columns...
                  </div>
                )}
              </div>

              {/* Parsed Preview Table */}
              {parsedRows.length > 0 && (
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
                      File Preview ({parsedRows.length} total rows)
                    </h3>
                    <span className="text-xs text-emerald-600 font-semibold flex items-center gap-1">
                      <CheckCircle2 className="h-3.5 w-3.5" /> All required headers present
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
                          <th className="py-2 px-3">Emp No</th>
                          <th className="py-2 px-3">Employee Name</th>
                          <th className="py-2 px-3">Date Hired</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-border-subtle">
                        {parsedRows.slice(0, 10).map((row, idx) => {
                          const isVacant = !row.EMPLOYEE_NO && !row.LAST_NAME && !row.FIRST_NAME;
                          return (
                            <tr key={idx} className="hover:bg-surface-hover/50">
                              <td className="py-2 px-3 text-text-muted">{idx + 1}</td>
                              <td className="py-2 px-3 font-semibold text-text-primary">{row.VCODE || "—"}</td>
                              <td className="py-2 px-3 text-text-primary">{row.STORE_NAME || "—"}</td>
                              <td className="py-2 px-3 text-text-secondary">{row.POSITION || "—"}</td>
                              <td className="py-2 px-3 font-mono text-purple-700">
                                {row.EMPLOYEE_NO ? (
                                  row.EMPLOYEE_NO
                                ) : (
                                  <span className="italic text-text-muted font-sans font-normal">(Vacant Slot)</span>
                                )}
                              </td>
                              <td className="py-2 px-3 font-medium text-text-primary">
                                {[row.LAST_NAME, row.FIRST_NAME, row.MIDDLE_NAME].filter(Boolean).join(", ") || (
                                  isVacant ? <span className="italic text-text-muted font-normal">(Vacant Slot)</span> : "—"
                                )}
                              </td>
                              <td className="py-2 px-3 text-text-secondary">{row.DATE_HIRED || "—"}</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                  {parsedRows.length > 10 && (
                    <p className="text-2xs text-text-muted text-right">
                      Showing first 10 rows of {parsedRows.length}.
                    </p>
                  )}

                  <div className="flex justify-end pt-2">
                    <button
                      onClick={handleSubmit}
                      disabled={isSubmitting || !selectedGroupId || !selectedAccountId}
                      className="inline-flex items-center gap-2 rounded-xl bg-purple-600 hover:bg-purple-700 text-white font-semibold text-xs px-5 py-2.5 transition disabled:opacity-50"
                    >
                      {isSubmitting ? (
                        <>
                          <Loader2 className="h-4 w-4 animate-spin" />
                          Submitting Baseline Import...
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
              {reviewNotice && (
                <div
                  className={`rounded-xl border p-3.5 flex items-start gap-3 ${
                    reviewNotice.type === "error"
                      ? "border-rose-200 bg-rose-50/90 text-rose-800"
                      : reviewNotice.type === "warning"
                      ? "border-amber-200 bg-amber-50/90 text-amber-800"
                      : "border-emerald-200 bg-emerald-50/90 text-emerald-800"
                  }`}
                >
                  {reviewNotice.type === "error" ? (
                    <AlertCircle className="h-5 w-5 text-rose-600 shrink-0 mt-0.5" />
                  ) : reviewNotice.type === "warning" ? (
                    <AlertTriangle className="h-5 w-5 text-amber-600 shrink-0 mt-0.5" />
                  ) : (
                    <CheckCircle2 className="h-5 w-5 text-emerald-600 shrink-0 mt-0.5" />
                  )}
                  <p className="text-xs font-medium">{reviewNotice.message}</p>
                </div>
              )}

              {actionError && (
                <div className="rounded-xl border border-rose-200 bg-rose-50/80 p-3.5 flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-rose-600 shrink-0 mt-0.5" />
                  <p className="text-xs font-medium text-rose-800">{actionError}</p>
                </div>
              )}

              <div className="flex items-center justify-between">
                <p className="text-xs text-text-secondary">
                  Pending plantilla baseline batches awaiting administrative approval or validation error review.
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
                  No batches currently awaiting approval or validation review.
                </div>
              ) : (
                <div className="space-y-4">
                  {pendingBatches.map((batch) => {
                    const isSelected = selectedBatchId === batch.id;
                    const isValidationFailed =
                      batch.status === "validation_failed" || batch.blockedRows > 0;

                    return (
                      <div
                        key={batch.id}
                        className={`rounded-xl border bg-surface p-4 transition ${
                          isSelected ? "border-purple-300 ring-1 ring-purple-200" : "border-border-subtle"
                        }`}
                      >
                        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
                          <div className="space-y-1">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className="font-semibold text-xs text-text-primary">{batch.fileName}</span>
                              <span
                                className={`rounded-md text-3xs font-bold px-1.5 py-0.5 uppercase whitespace-nowrap leading-none ${
                                  isValidationFailed
                                    ? "bg-rose-100 text-rose-800 border border-rose-200"
                                    : "bg-amber-100 text-amber-800 border border-amber-200"
                                }`}
                              >
                                {batch.status.replace("_", " ")}
                              </span>
                              {batch.blockedRows > 0 && (
                                <span className="rounded-md bg-rose-50 text-rose-700 text-3xs font-semibold px-1.5 py-0.5 border border-rose-200 whitespace-nowrap leading-none">
                                  {batch.blockedRows} Blocked
                                </span>
                              )}
                              {batch.flaggedRows > 0 && (
                                <span className="rounded-md bg-amber-50 text-amber-700 text-3xs font-semibold px-1.5 py-0.5 border border-amber-200 whitespace-nowrap leading-none">
                                  {batch.flaggedRows} Flagged
                                </span>
                              )}
                              {batch.validRows > 0 && (
                                <span className="rounded-md bg-emerald-50 text-emerald-700 text-3xs font-semibold px-1.5 py-0.5 border border-emerald-200 whitespace-nowrap leading-none">
                                  {batch.validRows} Valid
                                </span>
                              )}
                            </div>

                            <div className="text-2xs text-text-muted flex flex-wrap gap-x-3 gap-y-1">
                              <span>Batch #{batch.id.slice(0, 8)}</span>
                              <span>Scope: {batch.groupName || "Group"} / {batch.accountName || "Account"}</span>
                              <span>Uploaded by: {batch.uploadedBy || "System"}</span>
                              <span>Rows: {batch.totalRows}</span>
                            </div>

                            {batch.errorSummary && Object.keys(batch.errorSummary).length > 0 && (
                              <div className="flex flex-wrap items-center gap-1.5 pt-1">
                                <span className="text-3xs text-rose-700 font-bold uppercase">Errors:</span>
                                {Object.entries(batch.errorSummary).map(([f, cnt]) => (
                                  <span
                                    key={f}
                                    className="rounded-md bg-rose-100 text-rose-800 text-3xs font-mono font-semibold px-2 py-0.5"
                                  >
                                    {f}: {cnt}
                                  </span>
                                ))}
                              </div>
                            )}
                          </div>

                          <div className="flex items-center gap-2 shrink-0">
                            <button
                              onClick={() => setSelectedBatchId(isSelected ? null : batch.id)}
                              className={`h-8 px-3 rounded-lg border text-xs font-semibold transition ${
                                isSelected
                                  ? "bg-purple-100 text-purple-800 border-purple-300"
                                  : "border-border-subtle text-text-secondary hover:text-text-primary hover:bg-surface-hover"
                              }`}
                            >
                              {isSelected ? "Hide Rows" : "Inspect Rows"}
                            </button>

                            {canApprove && (
                              <>
                                <button
                                  onClick={() => handleApproveBatch(batch.id)}
                                  disabled={isActionPending || isValidationFailed}
                                  title={
                                    isValidationFailed
                                      ? `Cannot approve batch: ${batch.blockedRows} row(s) failed validation.`
                                      : "Approve & Apply batch"
                                  }
                                  className={`h-8 px-3 rounded-lg text-white text-xs font-semibold transition ${
                                    isValidationFailed
                                      ? "bg-emerald-600/40 cursor-not-allowed text-white/70"
                                      : "bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50"
                                  }`}
                                >
                                  Approve & Apply
                                </button>
                                <button
                                  onClick={() => handleRejectBatch(batch.id, isValidationFailed)}
                                  disabled={isActionPending}
                                  className="h-8 px-3 rounded-lg bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 text-xs font-semibold transition disabled:opacity-50"
                                >
                                  {isValidationFailed ? "Dismiss / Reject" : "Reject"}
                                </button>
                              </>
                            )}
                          </div>
                        </div>

                        {/* Batch Row Inspection Drawer */}
                        {isSelected && (
                          <div className="mt-4 pt-4 border-t border-purple-200 bg-purple-50/20 rounded-xl p-3.5 space-y-3 animate-in fade-in duration-150">
                            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                              <h4 className="text-xs font-bold text-text-primary">
                                Inspect Batch Rows (#{batch.id.slice(0, 8)})
                              </h4>

                              {/* Quick Filter Pills */}
                              <div className="flex items-center gap-1.5 flex-wrap">
                                <span className="text-2xs font-semibold text-text-secondary mr-1">Filter:</span>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("all")}
                                  className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                                    rowFilter === "all"
                                      ? "bg-purple-600 text-white shadow-xs"
                                      : "bg-surface border border-border-subtle text-text-secondary hover:text-text-primary"
                                  }`}
                                >
                                  All ({previewRows.length})
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("blocked")}
                                  className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                                    rowFilter === "blocked"
                                      ? "bg-rose-600 text-white shadow-xs"
                                      : "bg-rose-50 border border-rose-200 text-rose-700 hover:bg-rose-100"
                                  }`}
                                >
                                  Blocked ({previewRows.filter((r) => r.validationStatus === "blocked").length})
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("flagged")}
                                  className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                                    rowFilter === "flagged"
                                      ? "bg-amber-600 text-white shadow-xs"
                                      : "bg-amber-50 border border-amber-200 text-amber-700 hover:bg-amber-100"
                                  }`}
                                >
                                  Flagged ({previewRows.filter((r) => r.validationStatus === "flagged").length})
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("valid")}
                                  className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                                    rowFilter === "valid"
                                      ? "bg-emerald-600 text-white shadow-xs"
                                      : "bg-emerald-50 border border-emerald-200 text-emerald-700 hover:bg-emerald-100"
                                  }`}
                                >
                                  Valid ({previewRows.filter((r) => r.validationStatus === "valid").length})
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("skipped")}
                                  className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                                    rowFilter === "skipped"
                                      ? "bg-slate-600 text-white shadow-xs"
                                      : "bg-slate-50 border border-slate-200 text-slate-700 hover:bg-slate-100"
                                  }`}
                                >
                                  Skipped ({previewRows.filter((r) => r.validationStatus === "skipped").length})
                                </button>
                              </div>
                            </div>

                            {isLoadingPreviewRows ? (
                              <div className="flex justify-center p-6 text-xs text-text-muted">
                                <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rows...
                              </div>
                            ) : filteredPreviewRows.length === 0 ? (
                              <div className="rounded-lg border border-dashed border-border-subtle p-6 text-center text-xs text-text-muted">
                                No rows match the selected filter ({rowFilter}).
                              </div>
                            ) : (
                              <div className="rounded-lg border border-border-subtle bg-surface overflow-x-auto max-h-72">
                                <table className="w-full text-left text-xs">
                                  <thead className="bg-surface-subtle border-b border-border-subtle sticky top-0 text-2xs uppercase text-text-muted font-bold">
                                    <tr>
                                      <th className="py-2 px-2.5 w-10">#</th>
                                      <th className="py-2 px-2.5 w-24">Status</th>
                                      <th className="py-2 px-2.5 w-28">VCode</th>
                                      <th className="py-2 px-2.5">Store & Mother</th>
                                      <th className="py-2 px-2.5">Employee</th>
                                      <th className="py-2 px-2.5">Position / HC</th>
                                      <th className="py-2 px-2.5">Validation Issues & Guidance</th>
                                    </tr>
                                  </thead>
                                  <tbody className="divide-y divide-border-subtle">
                                    {filteredPreviewRows.map((r) => {
                                      const isRowBlocked = r.validationStatus === "blocked";
                                      const isRowFlagged = r.validationStatus === "flagged";
                                      const isRowValid = r.validationStatus === "valid";
                                      const isRowSkipped = r.validationStatus === "skipped";

                                      return (
                                        <tr
                                          key={r.rowNumber}
                                          className={`${
                                            isRowBlocked
                                              ? "bg-rose-50/70 hover:bg-rose-50"
                                              : isRowFlagged
                                              ? "bg-amber-50/70 hover:bg-amber-50"
                                              : isRowSkipped
                                              ? "bg-slate-50/70 hover:bg-slate-50 text-text-muted"
                                              : "hover:bg-surface-hover/50"
                                          }`}
                                        >
                                          <td className="py-2 px-2.5 font-mono text-xs text-text-muted">{r.rowNumber}</td>
                                          <td className="py-2 px-2.5 whitespace-nowrap">
                                            <span
                                              className={`inline-flex items-center rounded-md px-1.5 py-0.5 text-3xs font-bold uppercase whitespace-nowrap leading-none ${
                                                isRowBlocked
                                                  ? "bg-rose-200 text-rose-900"
                                                  : isRowFlagged
                                                  ? "bg-amber-200 text-amber-900"
                                                  : isRowValid
                                                  ? "bg-emerald-100 text-emerald-800"
                                                  : isRowSkipped
                                                  ? "bg-slate-200 text-slate-800"
                                                  : "bg-slate-100 text-slate-700"
                                              }`}
                                            >
                                              {r.validationStatus}
                                            </span>
                                          </td>
                                          <td className="py-2 px-2.5 font-bold font-mono text-text-primary text-sm whitespace-nowrap">
                                            {r.vcode || "—"}
                                          </td>
                                          <td className="py-2 px-2.5">
                                            <div className="font-semibold text-text-primary text-sm leading-tight">{r.storeName || "—"}</div>
                                            {r.motherAccount && (
                                              <div className="text-xs text-text-muted font-mono leading-tight mt-0.5">
                                                Mother: {r.motherAccount}
                                              </div>
                                            )}
                                          </td>
                                          <td className="py-2 px-2.5">
                                            {r.employeeNo || r.employeeName ? (
                                              <div className="space-y-0.5">
                                                <div className="font-medium text-text-primary text-xs leading-tight">{r.employeeName || "—"}</div>
                                                <div className="flex items-center gap-1.5 flex-wrap leading-tight">
                                                  {r.employeeNo && (
                                                    <span className="text-xs font-mono text-purple-700">ID: {r.employeeNo}</span>
                                                  )}
                                                  {r.needsHrco && (
                                                    <span className="rounded bg-amber-100 text-amber-800 text-3xs font-bold px-1.5 py-0.5 whitespace-nowrap leading-none">
                                                      NEEDS HRCO
                                                    </span>
                                                  )}
                                                </div>
                                              </div>
                                            ) : (
                                              <span className="inline-flex items-center px-1.5 py-0.5 rounded text-3xs font-semibold bg-blue-50 text-blue-700 border border-blue-200 whitespace-nowrap leading-none">
                                                (Vacant Baseline Slot)
                                              </span>
                                            )}
                                          </td>
                                          <td className="py-2 px-2.5 text-text-secondary">
                                            <div className="font-medium text-text-primary text-xs leading-tight">{r.position || "—"}</div>
                                            <div className="text-xs text-text-muted flex items-center gap-1.5 flex-wrap mt-0.5 leading-tight">
                                              {r.employmentType && (
                                                <span
                                                  className={`rounded px-1.5 py-0.5 text-3xs font-bold uppercase whitespace-nowrap leading-none ${
                                                    r.employmentType.toLowerCase().includes("roving")
                                                      ? "bg-purple-100 text-purple-800 border border-purple-200"
                                                      : r.employmentType.toLowerCase().includes("stationary")
                                                      ? "bg-sky-100 text-sky-800 border border-sky-200"
                                                      : "bg-surface-subtle text-text-secondary border border-border-subtle"
                                                  }`}
                                                >
                                                  {r.employmentType}
                                                </span>
                                              )}
                                              {r.requiredHc !== undefined && <span>{r.requiredHc} HC</span>}
                                            </div>
                                            {(r.scheduleDays || r.scheduleTime || r.dayoff) && (
                                              <div
                                                className="text-xs text-text-muted truncate mt-0.5 leading-tight"
                                                title={[r.scheduleDays, r.scheduleTime, r.dayoff ? `Off: ${r.dayoff}` : null].filter(Boolean).join(" • ")}
                                              >
                                                {[r.scheduleDays, r.scheduleTime, r.dayoff ? `Off: ${r.dayoff}` : null].filter(Boolean).join(" • ")}
                                              </div>
                                            )}
                                          </td>
                                          <td className="py-2 px-2.5">
                                            {isRowBlocked && (
                                              <div className="space-y-1">
                                                {r.validationErrors && r.validationErrors.length > 0 ? (
                                                  r.validationErrors.map((err, errIdx) => (
                                                    <div
                                                      key={errIdx}
                                                      className="flex items-start gap-1.5 text-rose-700 text-xs leading-tight"
                                                    >
                                                      {err.conflictType && (
                                                        <span className="rounded bg-rose-200 text-rose-900 px-1.5 py-0.5 text-3xs font-mono font-bold shrink-0 leading-none">
                                                          {err.conflictType}
                                                        </span>
                                                      )}
                                                      {!err.conflictType && err.field && (
                                                        <span className="rounded bg-rose-200 text-rose-900 px-1.5 py-0.5 text-3xs font-mono font-bold shrink-0 leading-none">
                                                          {err.field}
                                                        </span>
                                                      )}
                                                      <span className="font-medium break-words leading-tight">{err.msg}</span>
                                                    </div>
                                                  ))
                                                ) : (
                                                  r.validationMessages.map((msg, mIdx) => (
                                                    <div key={mIdx} className="text-rose-700 text-xs font-medium break-words leading-tight">
                                                      • {msg}
                                                    </div>
                                                  ))
                                                )}
                                              </div>
                                            )}
                                            {isRowFlagged && (
                                              <div className="space-y-1">
                                                {r.validationFlags && r.validationFlags.length > 0 ? (
                                                  r.validationFlags.map((flag, fIdx) => (
                                                    <div
                                                      key={fIdx}
                                                      className="flex items-start gap-1.5 text-amber-700 text-xs leading-tight"
                                                    >
                                                      {flag.flag && (
                                                        <span className="rounded bg-amber-200 text-amber-900 px-1.5 py-0.5 text-3xs font-mono font-bold shrink-0 leading-none">
                                                          {flag.flag}
                                                        </span>
                                                      )}
                                                      <span className="font-medium break-words leading-tight">{flag.msg}</span>
                                                    </div>
                                                  ))
                                                ) : (
                                                  r.validationMessages.map((msg, mIdx) => (
                                                    <div key={mIdx} className="text-amber-700 text-xs font-medium break-words leading-tight">
                                                      • {msg}
                                                    </div>
                                                  ))
                                                )}
                                              </div>
                                            )}
                                            {isRowValid && (
                                              <span className="inline-flex items-center gap-1 text-emerald-700 text-xs font-semibold leading-tight">
                                                <CheckCircle2 className="h-3.5 w-3.5 shrink-0" /> Ready for import
                                              </span>
                                            )}
                                            {isRowSkipped && (
                                              <span className="inline-flex items-center gap-1 text-slate-600 text-xs font-medium leading-tight">
                                                Existing VCODE skipped (vacant row)
                                              </span>
                                            )}
                                            {!isRowBlocked && !isRowFlagged && !isRowValid && !isRowSkipped && (
                                              <span className="text-text-muted text-xs leading-tight">Pending</span>
                                            )}
                                          </td>
                                        </tr>
                                      );
                                    })}
                                  </tbody>
                                </table>
                              </div>
                            )}

                            {canApprove && (
                              <div className="pt-2 flex gap-2">
                                <input
                                  type="text"
                                  placeholder={
                                    isValidationFailed
                                      ? "Audit note (optional: default will be used if left blank)..."
                                      : "Rejection note or audit remarks (required if rejecting)..."
                                  }
                                  value={actionReason}
                                  onChange={(e) => setActionReason(e.target.value)}
                                  className="flex-1 h-8 rounded-lg border border-border-subtle bg-surface px-3 text-xs text-text-primary focus:outline-hidden"
                                />
                                <button
                                  onClick={() => handleRejectBatch(batch.id, isValidationFailed)}
                                  disabled={isActionPending}
                                  className="h-8 px-3 rounded-lg bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 text-xs font-semibold transition disabled:opacity-50 shrink-0"
                                >
                                  {isValidationFailed ? "Dismiss Batch" : "Reject Batch"}
                                </button>
                              </div>
                            )}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}

          {activeTab === "history" && (
            <div className="space-y-4">
              {historyBatches.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border-subtle p-8 text-center text-xs text-text-muted">
                  No historical import logs recorded yet.
                </div>
              ) : (
                <div className="rounded-xl border border-border-subtle bg-surface overflow-x-auto">
                  <table className="w-full min-w-[920px] table-fixed text-left text-xs">
                    <thead className="bg-surface-subtle border-b border-border-subtle text-2xs uppercase text-text-muted font-bold">
                      <tr>
                        <th className="py-2.5 px-2.5 w-24">Batch #</th>
                        <th className="py-2.5 px-2.5 w-48">File Name</th>
                        <th className="py-2.5 px-2.5 w-32">Status</th>
                        <th className="py-2.5 px-2.5 w-24">Stores / HC</th>
                        <th className="py-2.5 px-2.5 w-48">Rollback State & Window</th>
                        <th className="py-2.5 px-2.5 w-40">Scope</th>
                        <th className="py-2.5 px-2.5 w-32">Uploaded By</th>
                        <th className="py-2.5 px-2.5 w-40">Approved / Rejected By</th>
                        <th className="py-2.5 px-2.5 w-24">Date</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {historyBatches.map((b) => {
                        const isSelected = historySelectedBatch?.id === b.id;
                        const isApproved = b.status.toLowerCase().includes("approved");
                        const rawActor = b.approvedByName || b.approvedBy || b.rejectedByName || b.rejectedBy || null;
                        const isRejection = !!(b.rejectedByName || b.rejectedBy);
                        const actorDisplay = formatActor(rawActor);

                        return (
                          <tr
                            key={b.id}
                            onClick={() => setHistorySelectedBatch(isSelected ? null : b)}
                            className={`cursor-pointer transition ${
                              isSelected ? "bg-purple-50/50 dark:bg-purple-950/20" : "hover:bg-surface-hover/50"
                            }`}
                          >
                            <td className="py-2.5 px-2.5 font-mono text-xs font-semibold text-purple-700 whitespace-nowrap leading-tight">
                              #{b.id.slice(0, 8)}
                            </td>
                            <td className="py-2.5 px-2.5 font-semibold text-text-primary text-xs leading-tight">
                              <div className="flex items-center gap-1.5 min-w-0" title={b.fileName}>
                                <span className="truncate">{b.fileName}</span>
                                {isSelected && (
                                  <span className="rounded-full bg-purple-100 text-purple-700 text-3xs font-bold px-1.5 py-0.5 whitespace-nowrap shrink-0">
                                    Selected
                                  </span>
                                )}
                              </div>
                            </td>
                            <td className="py-2.5 px-2.5 whitespace-nowrap leading-tight">
                              <span
                                className={`inline-flex items-center rounded-md px-1.5 py-0.5 text-3xs font-bold uppercase whitespace-nowrap leading-none ${
                                  isApproved
                                    ? "bg-emerald-100 text-emerald-800"
                                    : b.status.includes("rolled_back")
                                    ? "bg-purple-100 text-purple-800"
                                    : "bg-rose-100 text-rose-800"
                                }`}
                              >
                                {b.status.replace("_", " ")}
                              </span>
                            </td>
                            <td className="py-2.5 px-2.5 font-mono text-xs font-bold text-text-primary whitespace-nowrap leading-tight">
                              {b.committedStores ?? b.totalRows} / {b.committedEmployees ?? b.validRows}
                            </td>
                            <td className="py-2.5 px-2.5 whitespace-nowrap leading-tight">
                              {b.rollbackStatus === "requested" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-amber-100 text-amber-800 px-1.5 py-0.5 text-3xs font-bold uppercase whitespace-nowrap leading-none">
                                  <Clock className="h-3 w-3 shrink-0" /> Rollback Requested
                                </span>
                              ) : b.rollbackStatus === "completed" || b.status === "rolled_back" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-purple-100 text-purple-800 px-1.5 py-0.5 text-3xs font-bold uppercase whitespace-nowrap leading-none">
                                  <RotateCcw className="h-3 w-3 shrink-0" /> Rolled Back
                                </span>
                              ) : b.rollbackStatus === "failed" ? (
                                <span className="inline-flex items-center gap-1 rounded-md bg-rose-100 text-rose-800 px-1.5 py-0.5 text-3xs font-bold uppercase whitespace-nowrap leading-none">
                                  <AlertCircle className="h-3 w-3 shrink-0" /> Rollback Failed
                                </span>
                              ) : isApproved ? (
                                b.rollbackAllowed ? (
                                  <span className="inline-flex items-center gap-1 rounded-md bg-blue-50 text-blue-700 border border-blue-200 px-1.5 py-0.5 text-3xs font-medium whitespace-nowrap leading-none">
                                    <Clock className="h-3 w-3 text-blue-500 shrink-0" />
                                    Expires: {formatRollbackRemaining(b.rollbackRemainingSeconds)}
                                  </span>
                                ) : (
                                  <span className="rounded-md bg-slate-100 text-slate-600 px-1.5 py-0.5 text-3xs font-medium whitespace-nowrap leading-none">
                                    Window Expired
                                  </span>
                                )
                              ) : (
                                <span className="text-text-muted text-xs">—</span>
                              )}
                            </td>
                            <td
                              className="py-2.5 px-2.5 text-text-secondary text-xs leading-tight"
                              title={`${b.groupName ?? "—"} / ${b.accountName ?? "—"}`}
                            >
                              <span className="truncate block max-w-full">
                                {b.groupName ?? "—"} / {b.accountName ?? "—"}
                              </span>
                            </td>
                            <td
                              className="py-2.5 px-2.5 text-text-secondary text-xs leading-tight"
                              title={b.uploadedBy || "—"}
                            >
                              <span className="truncate block max-w-full">
                                {formatActor(b.uploadedBy)}
                              </span>
                            </td>
                            <td
                              className="py-2.5 px-2.5 text-text-secondary text-xs leading-tight"
                              title={rawActor || "—"}
                            >
                              <span className="truncate block max-w-full">
                                {isRejection && rawActor ? `[Rej] ${actorDisplay}` : actorDisplay}
                              </span>
                            </td>
                            <td
                              className="py-2.5 px-2.5 text-text-muted text-xs leading-tight whitespace-nowrap"
                              title={b.uploadedAt ? new Date(b.uploadedAt).toLocaleString() : "—"}
                            >
                              {b.uploadedAt ? new Date(b.uploadedAt).toLocaleDateString() : "—"}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}

              {/* DRAWER OPTION A: Import Failure Audit & Error Log Drawer for validation_failed or rejected batches */}
              {historySelectedBatch &&
                (historySelectedBatch.status === "validation_failed" ||
                  historySelectedBatch.status === "rejected") && (
                  <div className="rounded-xl border border-rose-200 bg-rose-50/20 p-4 space-y-4 animate-in fade-in duration-150">
                    <div className="flex items-center justify-between border-b border-border-subtle pb-3">
                      <div className="flex items-center gap-2">
                        <AlertCircle className="h-4 w-4 text-rose-700" />
                        <h4 className="text-xs font-bold text-text-primary">
                          Import Failure Audit & Error Log — #{historySelectedBatch.id.slice(0, 8)} (
                          {historySelectedBatch.fileName})
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
                        <span className="font-bold text-rose-700 uppercase mt-0.5 block">
                          {historySelectedBatch.status.replace("_", " ")}
                        </span>
                      </div>
                      <div className="p-2 rounded-lg bg-surface border border-border-subtle">
                        <span className="text-text-muted block">Scope</span>
                        <span className="font-bold text-text-primary mt-0.5 block truncate">
                          {historySelectedBatch.groupName || "—"} / {historySelectedBatch.accountName || "—"}
                        </span>
                      </div>
                      <div className="p-2 rounded-lg bg-surface border border-border-subtle">
                        <span className="text-text-muted block">Failed / Blocked Rows</span>
                        <span className="font-bold text-rose-700 mt-0.5 block">
                          {historySelectedBatch.blockedRows} / {historySelectedBatch.totalRows} rows
                        </span>
                      </div>
                      <div className="p-2 rounded-lg bg-surface border border-border-subtle">
                        <span className="text-text-muted block">Valid Rows</span>
                        <span className="font-bold text-emerald-700 mt-0.5 block">
                          {historySelectedBatch.validRows} rows
                        </span>
                      </div>
                    </div>

                    {(historySelectedBatch.rejectionReasonNote ||
                      historySelectedBatch.rejectionReason) && (
                      <div className="rounded-lg border border-rose-200 bg-rose-50/80 p-3 text-xs text-rose-800 space-y-1">
                        <div className="font-bold uppercase text-3xs text-rose-900">Rejection Reason / Note:</div>
                        <div>
                          {historySelectedBatch.rejectionReasonNote ||
                            historySelectedBatch.rejectionReason}
                        </div>
                      </div>
                    )}

                    {historySelectedBatch.errorSummary &&
                      Object.keys(historySelectedBatch.errorSummary).length > 0 && (
                        <div className="flex flex-wrap items-center gap-1.5 p-2 rounded-lg bg-surface border border-border-subtle">
                          <span className="text-3xs text-rose-700 font-bold uppercase">
                            Field error breakdown:
                          </span>
                          {Object.entries(historySelectedBatch.errorSummary).map(([f, cnt]) => (
                            <span
                              key={f}
                              className="rounded-md bg-rose-100 text-rose-800 text-3xs font-mono font-semibold px-2 py-0.5"
                            >
                              {f}: {cnt}
                            </span>
                          ))}
                        </div>
                      )}

                    {/* Row Inspection in History */}
                    <div className="space-y-3 pt-2">
                      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                        <h5 className="text-xs font-bold text-text-primary">
                          Row Error Breakdown ({historyRows.length} total rows)
                        </h5>

                        {/* Quick Filter Pills */}
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="text-2xs font-semibold text-text-secondary mr-1">Filter:</span>
                          <button
                            type="button"
                            onClick={() => setHistoryRowFilter("all")}
                            className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                              historyRowFilter === "all"
                                ? "bg-purple-600 text-white shadow-xs"
                                : "bg-surface border border-border-subtle text-text-secondary hover:text-text-primary"
                            }`}
                          >
                            All ({historyRows.length})
                          </button>
                          <button
                            type="button"
                            onClick={() => setHistoryRowFilter("blocked")}
                            className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                              historyRowFilter === "blocked"
                                ? "bg-rose-600 text-white shadow-xs"
                                : "bg-rose-50 border border-rose-200 text-rose-700 hover:bg-rose-100"
                            }`}
                          >
                            Blocked ({historyRows.filter((r) => r.validationStatus === "blocked").length})
                          </button>
                          <button
                            type="button"
                            onClick={() => setHistoryRowFilter("flagged")}
                            className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                              historyRowFilter === "flagged"
                                ? "bg-amber-600 text-white shadow-xs"
                                : "bg-amber-50 border border-amber-200 text-amber-700 hover:bg-amber-100"
                            }`}
                          >
                            Flagged ({historyRows.filter((r) => r.validationStatus === "flagged").length})
                          </button>
                          <button
                            type="button"
                            onClick={() => setHistoryRowFilter("valid")}
                            className={`px-2 py-0.5 rounded-md text-3xs font-semibold transition ${
                              historyRowFilter === "valid"
                                ? "bg-emerald-600 text-white shadow-xs"
                                : "bg-emerald-50 border border-emerald-200 text-emerald-700 hover:bg-emerald-100"
                            }`}
                          >
                            Valid ({historyRows.filter((r) => r.validationStatus === "valid").length})
                          </button>
                        </div>
                      </div>

                      {isLoadingHistoryRows ? (
                        <div className="flex justify-center p-6 text-xs text-text-muted">
                          <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rows...
                        </div>
                      ) : filteredHistoryRows.length === 0 ? (
                        <div className="rounded-lg border border-dashed border-border-subtle p-6 text-center text-xs text-text-muted">
                          No rows match the selected filter ({historyRowFilter}).
                        </div>
                      ) : (
                        <div className="rounded-lg border border-border-subtle bg-surface overflow-x-auto max-h-72">
                          <table className="w-full text-left text-xs">
                            <thead className="bg-surface-subtle border-b border-border-subtle sticky top-0 text-2xs uppercase text-text-muted font-bold">
                              <tr>
                                <th className="py-2 px-2.5 w-10">#</th>
                                <th className="py-2 px-2.5 w-24">Status</th>
                                <th className="py-2 px-2.5 w-28">VCode</th>
                                <th className="py-2 px-2.5">Store</th>
                                <th className="py-2 px-2.5">Employee</th>
                                <th className="py-2 px-2.5">Position</th>
                                <th className="py-2 px-2.5">Validation Issues & Guidance</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-border-subtle">
                              {filteredHistoryRows.map((r) => {
                                const isRowBlocked = r.validationStatus === "blocked";
                                const isRowFlagged = r.validationStatus === "flagged";
                                const isRowValid = r.validationStatus === "valid";

                                return (
                                  <tr
                                    key={r.rowNumber}
                                    className={`${
                                      isRowBlocked
                                        ? "bg-rose-50/70 hover:bg-rose-50"
                                        : isRowFlagged
                                        ? "bg-amber-50/70 hover:bg-amber-50"
                                        : "hover:bg-surface-hover/50"
                                    }`}
                                  >
                                    <td className="py-2 px-2.5 font-mono text-xs text-text-muted">{r.rowNumber}</td>
                                    <td className="py-2 px-2.5 whitespace-nowrap">
                                      <span
                                        className={`inline-flex items-center rounded-md px-1.5 py-0.5 text-3xs font-bold uppercase whitespace-nowrap leading-none ${
                                          isRowBlocked
                                            ? "bg-rose-200 text-rose-900"
                                            : isRowFlagged
                                            ? "bg-amber-200 text-amber-900"
                                            : isRowValid
                                            ? "bg-emerald-100 text-emerald-800"
                                            : "bg-slate-100 text-slate-700"
                                        }`}
                                      >
                                        {r.validationStatus}
                                      </span>
                                    </td>
                                    <td className="py-2 px-2.5 font-bold font-mono text-text-primary text-sm whitespace-nowrap">
                                      {r.vcode || "—"}
                                    </td>
                                    <td className="py-2 px-2.5">
                                      <div className="font-semibold text-text-primary text-sm leading-tight">{r.storeName || "—"}</div>
                                    </td>
                                    <td className="py-2 px-2.5">
                                      {r.employeeNo || r.employeeName ? (
                                        <div className="space-y-0.5">
                                          <div className="font-medium text-text-primary text-xs leading-tight">{r.employeeName || "—"}</div>
                                          {r.employeeNo && (
                                            <div className="text-xs font-mono text-purple-700 leading-tight">
                                              ID: {r.employeeNo}
                                            </div>
                                          )}
                                        </div>
                                      ) : (
                                        <span className="inline-flex items-center px-1.5 py-0.5 rounded text-3xs font-semibold bg-blue-50 text-blue-700 border border-blue-200 whitespace-nowrap leading-none">
                                          (Vacant Slot)
                                        </span>
                                      )}
                                    </td>
                                    <td className="py-2 px-2.5 text-text-secondary">
                                      <div className="font-medium text-text-primary text-xs leading-tight">{r.position || "—"}</div>
                                      {r.employmentType && (
                                        <div className="mt-0.5 leading-tight">
                                          <span
                                            className={`rounded px-1.5 py-0.5 text-3xs font-bold uppercase whitespace-nowrap leading-none ${
                                              r.employmentType.toLowerCase().includes("roving")
                                                ? "bg-purple-100 text-purple-800 border border-purple-200"
                                                : r.employmentType.toLowerCase().includes("stationary")
                                                ? "bg-sky-100 text-sky-800 border border-sky-200"
                                                : "bg-surface-subtle text-text-secondary border border-border-subtle"
                                            }`}
                                          >
                                            {r.employmentType}
                                          </span>
                                        </div>
                                      )}
                                    </td>
                                    <td className="py-2 px-2.5">
                                      {isRowBlocked && (
                                        <div className="space-y-1">
                                          {r.validationErrors && r.validationErrors.length > 0 ? (
                                            r.validationErrors.map((err, errIdx) => (
                                              <div
                                                key={errIdx}
                                                className="flex items-start gap-1.5 text-rose-700 text-xs leading-tight"
                                              >
                                                {err.conflictType && (
                                                  <span className="rounded bg-rose-200 text-rose-900 px-1.5 py-0.5 text-3xs font-mono font-bold shrink-0 leading-none">
                                                    {err.conflictType}
                                                  </span>
                                                )}
                                                {!err.conflictType && err.field && (
                                                  <span className="rounded bg-rose-200 text-rose-900 px-1.5 py-0.5 text-3xs font-mono font-bold shrink-0 leading-none">
                                                    {err.field}
                                                  </span>
                                                )}
                                                <span className="font-medium break-words leading-tight">{err.msg}</span>
                                              </div>
                                            ))
                                          ) : (
                                            r.validationMessages.map((msg, mIdx) => (
                                              <div key={mIdx} className="text-rose-700 text-xs font-medium break-words leading-tight">
                                                • {msg}
                                              </div>
                                            ))
                                          )}
                                        </div>
                                      )}
                                      {isRowFlagged && (
                                        <div className="space-y-1">
                                          {r.validationFlags && r.validationFlags.length > 0 ? (
                                            r.validationFlags.map((flag, fIdx) => (
                                              <div
                                                key={fIdx}
                                                className="flex items-start gap-1.5 text-amber-700 text-xs leading-tight"
                                              >
                                                {flag.flag && (
                                                  <span className="rounded bg-amber-200 text-amber-900 px-1.5 py-0.5 text-3xs font-mono font-bold shrink-0 leading-none">
                                                    {flag.flag}
                                                  </span>
                                                )}
                                                <span className="font-medium break-words leading-tight">{flag.msg}</span>
                                              </div>
                                            ))
                                          ) : (
                                            r.validationMessages.map((msg, mIdx) => (
                                              <div key={mIdx} className="text-amber-700 text-xs font-medium break-words leading-tight">
                                                • {msg}
                                              </div>
                                            ))
                                          )}
                                        </div>
                                      )}
                                      {isRowValid && (
                                        <span className="inline-flex items-center gap-1 text-emerald-700 text-xs font-semibold leading-tight">
                                          <CheckCircle2 className="h-3.5 w-3.5 shrink-0" /> Valid slot
                                        </span>
                                      )}
                                      {!isRowBlocked && !isRowFlagged && !isRowValid && (
                                        <span className="text-text-muted text-xs leading-tight">Skipped</span>
                                      )}
                                    </td>
                                  </tr>
                                );
                              })}
                            </tbody>
                          </table>
                        </div>
                      )}
                    </div>
                  </div>
                )}

              {/* DRAWER OPTION B: Rollback Governance Drawer for approved / rolled back batches */}
              {historySelectedBatch &&
                historySelectedBatch.status !== "validation_failed" &&
                historySelectedBatch.status !== "rejected" && (
                  <div className="rounded-xl border border-purple-200 bg-purple-50/20 p-4 space-y-4 animate-in fade-in duration-150">
                    <div className="flex items-center justify-between border-b border-border-subtle pb-3">
                      <div className="flex items-center gap-2">
                        <RotateCcw className="h-4 w-4 text-purple-700" />
                        <h4 className="text-xs font-bold text-text-primary">
                          Rollback Governance — #{historySelectedBatch.id.slice(0, 8)} (
                          {historySelectedBatch.fileName})
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
                        <span className="text-text-muted block">Total Headcount Rows</span>
                        <span className="font-bold text-text-primary mt-0.5 block">
                          {historySelectedBatch.totalRows} rows
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
                          Rollback attempt failed:{" "}
                          {humanizeRollbackError(historySelectedBatch.rollbackErrorDetail)}
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

                      {/* Step 1: Request Rollback Button */}
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

                      {/* Step 2: Approve & Execute Rollback Button (Head Admin or Super Admin) */}
                      {canApprove &&
                        historySelectedBatch.status.toLowerCase().includes("approved") &&
                        historySelectedBatch.rollbackStatus === "requested" && (
                          <>
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

                            <button
                              onClick={async () => {
                                setRollbackActionBusy(true);
                                setRollbackActionError(null);
                                try {
                                  await rejectPlantillaImportRollback({
                                    batchId: historySelectedBatch.id,
                                    reason: "Rejected by Administrator",
                                  });
                                  setRollbackActionSuccess("Rollback request rejected successfully.");
                                  refetchBatches();
                                } catch (err) {
                                  setRollbackActionError(humanizeRollbackError(err instanceof Error ? err.message : String(err)));
                                } finally {
                                  setRollbackActionBusy(false);
                                }
                              }}
                              disabled={rollbackActionBusy}
                              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-300 bg-surface text-xs font-semibold text-slate-700 hover:bg-slate-100 shadow-xs transition"
                            >
                              <X className="h-3.5 w-3.5 text-slate-500" />
                              Reject Rollback Request
                            </button>
                          </>
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
            Full Mobile Store Import Parity with ADR-001 slot validation and rollback governance.
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
                <h3 className="text-sm font-bold text-text-primary">Request Import Rollback</h3>
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
                  placeholder="Provide detailed audited reason for requesting this rollback..."
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
              <h3 className="text-sm font-bold text-text-primary">Approve & Execute Rollback?</h3>
            </div>

            <div className="rounded-xl border border-rose-200 bg-rose-50/90 p-3.5 text-2xs text-rose-900 leading-relaxed font-medium">
              WARNING: This will immediately deactivate plantilla rows and store allocations mutated by this batch and
              restore pre-commit snapshots. Rollback safety rules are still enforced server-side (newer approved imports
              for the same Group/Account will block this).
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
                Approve & Execute
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
      <PlantillaRollbackHistoryModal
        isOpen={isRollbackHistoryOpen}
        onClose={() => setIsRollbackHistoryOpen(false)}
        batchId={historySelectedBatch?.id ?? null}
      />
    </div>
  );
}

function PlantillaRollbackHistoryModal({
  isOpen,
  onClose,
  batchId,
}: {
  isOpen: boolean;
  onClose: () => void;
  batchId: string | null;
}) {
  const { data: history, isLoading, refetch } = usePlantillaImportRollbackHistory(isOpen ? batchId : null);

  if (!isOpen || !batchId) return null;

  return (
    <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
      <div className="relative w-full max-w-lg rounded-2xl border border-border-subtle bg-surface p-6 shadow-2xl animate-in fade-in zoom-in-95 duration-150 space-y-4">
        <div className="flex items-center justify-between pb-3 border-b border-border-subtle">
          <div className="flex items-center gap-2">
            <History className="h-5 w-5 text-purple-600" />
            <h3 className="text-sm font-bold text-text-primary">Rollback Audit History</h3>
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
          ) : !history || !history.rollbackStatus ? (
            <div className="py-8 text-center text-xs text-text-muted">
              No rollback request has been submitted for this batch.
            </div>
          ) : (
            <div className="space-y-3 text-xs">
              <div className="flex items-center justify-between p-3 rounded-xl bg-surface-subtle border border-border-subtle">
                <span className="font-semibold text-text-secondary">Current Status</span>
                <span
                  className={`rounded-md px-2 py-0.5 text-3xs font-bold uppercase ${
                    history.rollbackStatus === "completed"
                      ? "bg-emerald-100 text-emerald-800"
                      : history.rollbackStatus === "requested"
                      ? "bg-amber-100 text-amber-800"
                      : "bg-rose-100 text-rose-800"
                  }`}
                >
                  {history.rollbackStatus}
                </span>
              </div>

              <div className="space-y-2 p-3 rounded-xl border border-border-subtle bg-surface">
                <div className="flex justify-between text-2xs">
                  <span className="text-text-muted">Requested By:</span>
                  <span className="font-medium text-text-primary">
                    {history.rollbackRequestedByName || history.rollbackRequestedBy || "—"}
                  </span>
                </div>
                <div className="flex justify-between text-2xs">
                  <span className="text-text-muted">Requested At:</span>
                  <span className="font-medium text-text-primary">
                    {history.rollbackRequestedAt ? new Date(history.rollbackRequestedAt).toLocaleString() : "—"}
                  </span>
                </div>
                <div className="pt-2 border-t border-border-subtle">
                  <span className="text-2xs text-text-muted block">Reason:</span>
                  <span className="font-semibold text-text-primary block mt-0.5">
                    {IMPORT_ROLLBACK_REASONS.find((r) => r.code === history.rollbackReasonCode)?.label ||
                      history.rollbackReason ||
                      "—"}
                  </span>
                </div>
                {history.rollbackReasonNote && (
                  <div className="pt-1">
                    <span className="text-2xs text-text-muted block">Remarks:</span>
                    <span className="text-text-secondary block mt-0.5 bg-surface-subtle p-2 rounded-lg border border-border-subtle">
                      {history.rollbackReasonNote}
                    </span>
                  </div>
                )}
              </div>

              {history.rollbackApprovedAt && (
                <div className="space-y-2 p-3 rounded-xl border border-border-subtle bg-surface">
                  <div className="flex justify-between text-2xs">
                    <span className="text-text-muted">Approved By:</span>
                    <span className="font-medium text-text-primary">
                      {history.rollbackApprovedByName || history.rollbackApprovedBy || "—"}
                    </span>
                  </div>
                  <div className="flex justify-between text-2xs">
                    <span className="text-text-muted">Approved At:</span>
                    <span className="font-medium text-text-primary">
                      {new Date(history.rollbackApprovedAt).toLocaleString()}
                    </span>
                  </div>
                  {history.rollbackCompletedAt && (
                    <div className="flex justify-between text-2xs">
                      <span className="text-text-muted">Completed At:</span>
                      <span className="font-medium text-emerald-700">
                        {new Date(history.rollbackCompletedAt).toLocaleString()}
                      </span>
                    </div>
                  )}
                  {history.rollbackErrorDetail && (
                    <div className="pt-2 border-t border-border-subtle text-rose-700 text-2xs font-semibold">
                      Error: {humanizeRollbackError(history.rollbackErrorDetail)}
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
