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
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Modal } from "@/components/shared/Modal";
import { useCurrentUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { useUsersList } from "@/lib/queries/users";
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

const METRIC_SUMMARY_KEYS = new Set([
  "total_rows",
  "valid_rows",
  "flagged_rows",
  "skipped_rows",
  "blocked_rows",
  "roving_detected",
  "new_stores_count",
  "existing_stores_count",
  "existing_employees_count",
  "over_20_store_warnings",
]);

function getActualErrorEntries(errorSummary?: Record<string, number | unknown>): [string, number][] {
  if (!errorSummary || typeof errorSummary !== "object") return [];
  return Object.entries(errorSummary)
    .filter(([key, val]) => {
      if (METRIC_SUMMARY_KEYS.has(key)) return false;
      const num = Number(val);
      return !isNaN(num) && num > 0;
    })
    .map(([key, val]) => [key, Number(val)]);
}

type TabType = "upload" | "review" | "history";

export function PlantillaImportModal({ isOpen, onClose }: PlantillaImportModalProps) {
  const queryClient = useQueryClient();
  const currentUser = useCurrentUser();
  const { data: usersList = [] } = useUsersList();

  const userMap = useMemo(() => {
    const map = new Map<string, string>();
    for (const u of usersList) {
      if (u.fullName) {
        if (u.id) map.set(u.id.toLowerCase(), u.fullName);
        if (u.authUserId) map.set(u.authUserId.toLowerCase(), u.fullName);
      }
    }
    return map;
  }, [usersList]);

  const formatActor = (actor?: string | null): string => {
    if (!actor) return "—";
    const trimmed = actor.trim();
    const lower = trimmed.toLowerCase();
    if (userMap.has(lower)) {
      return userMap.get(lower)!;
    }
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (uuidRegex.test(trimmed)) {
      return `${trimmed.slice(0, 8)}...`;
    }
    return trimmed;
  };

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
  const [actionError, setActionError] = useState<string | null>(null);
  const [isActionPending, setIsActionPending] = useState(false);

  // Dedicated Rejection Modal state
  const [rejectTargetBatch, setRejectTargetBatch] = useState<PlantillaImportBatch | null>(null);
  const [isRejectModalOpen, setIsRejectModalOpen] = useState(false);
  const [rejectionNote, setRejectionNote] = useState("");
  const [rejectionNoteError, setRejectionNoteError] = useState<string | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => {
      setToastMessage((prev) => (prev === msg ? null : prev));
    }, 4000);
  };

  const openRejectModal = (batch: PlantillaImportBatch) => {
    setRejectTargetBatch(batch);
    setRejectionNote("");
    setRejectionNoteError(null);
    setIsRejectModalOpen(true);
  };

  const closeRejectModal = () => {
    if (isActionPending) return;
    setIsRejectModalOpen(false);
    setRejectTargetBatch(null);
    setRejectionNote("");
    setRejectionNoteError(null);
  };

  const handleConfirmRejection = async () => {
    if (!rejectTargetBatch) return;

    const trimmed = rejectionNote.trim();
    if (!trimmed) {
      setRejectionNoteError("Please provide an audited reason note for rejection.");
      return;
    }

    setIsActionPending(true);
    setRejectionNoteError(null);
    setActionError(null);
    try {
      await rejectPlantillaImportBatch({
        batchId: rejectTargetBatch.id,
        reasonCode: "other",
        reasonNote: trimmed,
      });
      const batchShortId = rejectTargetBatch.id.slice(0, 8);
      closeRejectModal();
      refetchBatches();
      queryClient.invalidateQueries({ queryKey: ["plantilla-import-batches"] });
      setSelectedBatchId(null);
      showToast(`Plantilla batch #${batchShortId} has been successfully rejected.`);
      setReviewNotice({
        type: "success",
        message: `Plantilla batch #${batchShortId} has been rejected.`,
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      setRejectionNoteError(msg || "Failed to reject plantilla batch.");
    } finally {
      setIsActionPending(false);
    }
  };

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

  const selectedBatch = useMemo(
    () => batches.find((b) => b.id === selectedBatchId),
    [batches, selectedBatchId]
  );

  const { data: batchAccountHrco } = useQuery({
    queryKey: ["plantilla-import-batch-account-hrco", selectedBatch?.accountId],
    queryFn: async () => {
      if (!selectedBatch?.accountId) return null;
      const supabase = createClient();
      const { data } = await supabase
        .from("accounts")
        .select("hrco_user_id, hrco_name")
        .eq("id", selectedBatch.accountId)
        .single();
      return data;
    },
    enabled: !!selectedBatch?.accountId,
    staleTime: 60000,
  });

  const accountHasAssignedHrco = Boolean(
    selectedBatch?.hrcoUserId ||
    batchAccountHrco?.hrco_user_id ||
    (batchAccountHrco?.hrco_name && batchAccountHrco.hrco_name.trim() !== "")
  );

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
    () => new Set(["draft_uploaded", "pending_approval", "pending_review", "validation_failed", "blocked", "partially_blocked"]),
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
      const msg = err instanceof Error ? err.message : (err as { message?: string })?.message || "Failed to submit plantilla import batch.";
      setParseError(msg);
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

  const isBusy = isSubmitting || isActionPending || rollbackActionBusy;

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title={
          <span className="flex items-center gap-2">
            <span>Import Plantilla</span>
            <span className="rounded-md bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-bold px-2 py-0.5 border border-[var(--border-subtle)]">
              BULK BASELINE
            </span>
          </span>
        }
        subtitle="Ingest master store plantilla baselines, slot capacities, and employee assignments via CSV/XLSX."
        icon={FileSpreadsheet}
        maxWidthClass="max-w-5xl"
        disableBackdropClick={isBusy}
        isSubmitting={isBusy}
        footer={
          <div className="flex items-center justify-between w-full">
            <p className="text-xs text-[var(--text-muted)]">
              Full Mobile Store Import Parity with ADR-001 slot validation and rollback governance.
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
          {/* Floating Toast Notification */}
          {toastMessage && (
            <div className="p-3 rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-muted)] text-sm font-semibold text-[var(--foreground)] flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4 shrink-0 text-[var(--foreground)]" />
              <span>{toastMessage}</span>
            </div>
          )}

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

              {/* Scope selectors & Template Download */}
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs font-bold text-[var(--text-muted)] uppercase mb-1.5">
                    1. Target Group
                  </label>
                  <select
                    value={selectedGroupId}
                    onChange={(e) => handleGroupSelect(e.target.value)}
                    className="w-full h-10 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] px-3 text-sm font-medium text-[var(--foreground)] focus:outline-hidden"
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
                  <label className="block text-xs font-bold text-[var(--text-muted)] uppercase mb-1.5">
                    2. Target Account
                  </label>
                  <select
                    value={selectedAccountId}
                    onChange={(e) => setSelectedAccountId(e.target.value)}
                    disabled={!selectedGroupId || isLoadingAccounts}
                    className="w-full h-10 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] px-3 text-sm font-medium text-[var(--foreground)] focus:outline-hidden disabled:opacity-50"
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
                    type="button"
                    onClick={downloadPlantillaImportTemplate}
                    className="h-10 inline-flex items-center justify-center gap-2 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] hover:bg-[var(--surface-muted)] text-[var(--foreground)] text-sm font-semibold transition"
                  >
                    <Download className="h-4 w-4" />
                    Download Official Template
                  </button>
                </div>
              </div>

              {/* Upload Dropzone */}
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
                  {file ? file.name : "Click or drag & drop Plantilla XLSX or CSV file here"}
                </p>
                <p className="text-xs text-[var(--text-muted)] mt-1">
                  Supports Store Master & Baseline Plantilla with slot capacities and initial employee bindings.
                </p>
                {isParsing && (
                  <div className="flex items-center gap-2 mt-3 text-sm text-[var(--text-muted)]">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Parsing and validating columns...
                  </div>
                )}
              </div>

              {/* Parsed Preview Table */}
              {parsedRows.length > 0 && (
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="text-sm font-bold uppercase tracking-wider text-[var(--foreground)]">
                      File Preview ({parsedRows.length} total rows)
                    </h3>
                    <span className="text-sm text-[var(--foreground)] font-semibold flex items-center gap-1">
                      <CheckCircle2 className="h-4 w-4 text-[var(--text-muted)]" /> All required headers present
                    </span>
                  </div>

                  <div className="rounded-xl border border-[var(--border-subtle)] overflow-hidden max-h-60 overflow-y-auto">
                    <table className="w-full text-left text-sm">
                      <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)] sticky top-0 text-xs uppercase text-[var(--text-muted)] font-bold">
                        <tr>
                          <th className="py-2.5 px-3">#</th>
                          <th className="py-2.5 px-3">VCode</th>
                          <th className="py-2.5 px-3">Store Name</th>
                          <th className="py-2.5 px-3">Position</th>
                          <th className="py-2.5 px-3">Emp No</th>
                          <th className="py-2.5 px-3">Employee Name</th>
                          <th className="py-2.5 px-3">Date Hired</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-[var(--border-subtle)]">
                        {parsedRows.slice(0, 10).map((row, idx) => {
                          const isVacant = !row.EMPLOYEE_NO && !row.LAST_NAME && !row.FIRST_NAME;
                          return (
                            <tr key={idx} className="hover:bg-[var(--surface-muted)]/50">
                              <td className="py-2 px-3 text-[var(--text-muted)]">{idx + 1}</td>
                              <td className="py-2 px-3 font-semibold text-[var(--foreground)]">{row.VCODE || "—"}</td>
                              <td className="py-2 px-3 text-[var(--foreground)]">{row.STORE_NAME || "—"}</td>
                              <td className="py-2 px-3 text-[var(--text-muted)]">{row.POSITION || "—"}</td>
                              <td className="py-2 px-3 font-mono font-bold text-[var(--foreground)]">
                                {row.EMPLOYEE_NO ? (
                                  row.EMPLOYEE_NO
                                ) : (
                                  <span className="italic text-[var(--text-muted)] font-sans font-normal">(Vacant Slot)</span>
                                )}
                              </td>
                              <td className="py-2 px-3 font-medium text-[var(--foreground)]">
                                {[row.LAST_NAME, row.FIRST_NAME, row.MIDDLE_NAME].filter(Boolean).join(", ") || (
                                  isVacant ? <span className="italic text-[var(--text-muted)] font-normal">(Vacant Slot)</span> : "—"
                                )}
                              </td>
                              <td className="py-2 px-3 text-[var(--text-muted)]">{row.DATE_HIRED || "—"}</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                  {parsedRows.length > 10 && (
                    <p className="text-xs text-[var(--text-muted)] text-right">
                      Showing first 10 rows of {parsedRows.length}.
                    </p>
                  )}

                  <div className="flex justify-end pt-2">
                    <button
                      type="button"
                      onClick={handleSubmit}
                      disabled={isSubmitting || !selectedGroupId || !selectedAccountId}
                      className="inline-flex items-center gap-2 rounded-xl bg-[var(--primary)] hover:opacity-90 text-white font-semibold text-sm px-5 py-2.5 transition disabled:opacity-50"
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

          {/* Tab 2: Review Queue */}
          {activeTab === "review" && (
            <div className="space-y-4">
              {reviewNotice && (
                <div
                  className={`rounded-xl border p-3.5 flex items-start gap-3 ${
                    reviewNotice.type === "error"
                      ? "border-[var(--danger-border)] bg-[var(--danger-bg)] text-[var(--danger)]"
                      : "border-[var(--border-subtle)] bg-[var(--surface-muted)] text-[var(--foreground)]"
                  }`}
                >
                  {reviewNotice.type === "error" ? (
                    <AlertCircle className="h-5 w-5 text-[var(--danger)] shrink-0 mt-0.5" />
                  ) : (
                    <CheckCircle2 className="h-5 w-5 text-[var(--foreground)] shrink-0 mt-0.5" />
                  )}
                  <p className="text-sm font-medium">{reviewNotice.message}</p>
                </div>
              )}

              {actionError && (
                <div className="rounded-xl border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3.5 flex items-start gap-3">
                  <AlertCircle className="h-5 w-5 text-[var(--danger)] shrink-0 mt-0.5" />
                  <p className="text-sm font-medium text-[var(--danger)]">{actionError}</p>
                </div>
              )}

              <div className="flex items-center justify-between">
                <p className="text-sm text-[var(--text-muted)]">
                  Pending plantilla baseline batches awaiting administrative approval or validation error review.
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
                        className={`rounded-xl border bg-[var(--card)] p-4 transition ${
                          isSelected ? "border-[var(--border-bold)]" : "border-[var(--border-subtle)]"
                        }`}
                      >
                        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
                          <div className="space-y-1">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className="font-semibold text-sm text-[var(--foreground)]">{batch.fileName}</span>
                              <span
                                className={`rounded-md text-xs font-bold px-1.5 py-0.5 uppercase whitespace-nowrap leading-none ${
                                  isValidationFailed
                                    ? "bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)]"
                                    : "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                                }`}
                              >
                                {batch.status.replace("_", " ")}
                              </span>
                              {batch.blockedRows > 0 && (
                                <span className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] text-xs font-semibold px-1.5 py-0.5 border border-[var(--danger-border)] whitespace-nowrap leading-none">
                                  {batch.blockedRows} Blocked
                                </span>
                              )}
                              {batch.flaggedRows > 0 && (
                                <span className="rounded-md bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-semibold px-1.5 py-0.5 border border-[var(--border-subtle)] whitespace-nowrap leading-none">
                                  {batch.flaggedRows} Flagged
                                </span>
                              )}
                              {batch.validRows > 0 && (
                                <span className="rounded-md bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-semibold px-1.5 py-0.5 border border-[var(--border-subtle)] whitespace-nowrap leading-none">
                                  {batch.validRows} Valid
                                </span>
                              )}
                            </div>

                            <div className="text-xs text-[var(--text-muted)] flex flex-wrap gap-x-3 gap-y-1">
                              <span>Batch #{batch.id.slice(0, 8)}</span>
                              <span>Scope: {batch.groupName || "Group"} / {batch.accountName || "Account"}</span>
                              <span>Uploaded by: {batch.uploadedBy || "System"}</span>
                              <span>Rows: {batch.totalRows}</span>
                            </div>

                            {(() => {
                              const errorEntries = getActualErrorEntries(batch.errorSummary);
                              if (errorEntries.length === 0) return null;
                              return (
                                <div className="flex flex-wrap items-center gap-1.5 pt-1">
                                  <span className="text-xs text-[var(--danger)] font-bold uppercase">Errors:</span>
                                  {errorEntries.map(([f, cnt]) => (
                                    <span
                                      key={f}
                                      className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)] text-xs font-mono font-semibold px-2 py-0.5"
                                    >
                                      {f}: {cnt}
                                    </span>
                                  ))}
                                </div>
                              );
                            })()}
                          </div>

                          <div className="flex items-center gap-2 shrink-0">
                            <button
                              type="button"
                              onClick={() => setSelectedBatchId(isSelected ? null : batch.id)}
                              className={`h-9 px-3 rounded-lg border text-sm font-semibold transition ${
                                isSelected
                                  ? "bg-[var(--surface-muted)] text-[var(--foreground)] border-[var(--border-bold)]"
                                  : "border-[var(--border-subtle)] text-[var(--text-muted)] hover:text-[var(--foreground)] hover:bg-[var(--surface-muted)]"
                              }`}
                            >
                              {isSelected ? "Hide Rows" : "Inspect Rows"}
                            </button>

                            {canApprove && (
                              <>
                                <button
                                  type="button"
                                  onClick={() => handleApproveBatch(batch.id)}
                                  disabled={isActionPending || isValidationFailed}
                                  title={
                                    isValidationFailed
                                      ? `Cannot approve batch: ${batch.blockedRows} row(s) failed validation.`
                                      : "Approve & Apply batch"
                                  }
                                  className={`h-9 px-3 rounded-lg text-[var(--card)] text-sm font-semibold transition ${
                                    isValidationFailed
                                      ? "bg-[var(--text-subtle)] cursor-not-allowed opacity-50"
                                      : "bg-[var(--foreground)] hover:opacity-90 disabled:opacity-50"
                                  }`}
                                >
                                  Approve & Apply
                                </button>
                                <button
                                  type="button"
                                  onClick={() => openRejectModal(batch)}
                                  disabled={isActionPending}
                                  className="h-9 px-3 rounded-lg bg-[var(--danger-bg)] hover:opacity-90 text-[var(--danger)] border border-[var(--danger-border)] text-sm font-semibold transition disabled:opacity-50"
                                >
                                  {isValidationFailed ? "Dismiss / Reject" : "Reject"}
                                </button>
                              </>
                            )}
                          </div>
                        </div>

                        {/* Batch Row Inspection Drawer */}
                        {isSelected && (
                          <div className="mt-4 pt-4 border-t border-[var(--border-subtle)] bg-[var(--surface-muted)]/50 rounded-xl p-3.5 space-y-3">
                            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                              <h4 className="text-sm font-bold text-[var(--foreground)]">
                                Inspect Batch Rows (#{batch.id.slice(0, 8)})
                              </h4>

                              {/* Quick Filter Pills */}
                              <div className="flex items-center gap-1.5 flex-wrap">
                                <span className="text-xs font-semibold text-[var(--text-muted)] mr-1">Filter:</span>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("all")}
                                  className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                                    rowFilter === "all"
                                      ? "bg-[var(--foreground)] text-[var(--card)]"
                                      : "bg-[var(--card)] border border-[var(--border-subtle)] text-[var(--text-muted)] hover:text-[var(--foreground)]"
                                  }`}
                                >
                                  All ({previewRows.length})
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("blocked")}
                                  className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                                    rowFilter === "blocked"
                                      ? "bg-[var(--danger)] text-white"
                                      : "bg-[var(--danger-bg)] border border-[var(--danger-border)] text-[var(--danger)]"
                                  }`}
                                >
                                  Blocked ({previewRows.filter((r) => r.validationStatus === "blocked").length})
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("flagged")}
                                  className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                                    rowFilter === "flagged"
                                      ? "bg-[var(--foreground)] text-[var(--card)]"
                                      : "bg-[var(--surface-sunken)] border border-[var(--border-subtle)] text-[var(--foreground)]"
                                  }`}
                                >
                                  Flagged ({previewRows.filter((r) => r.validationStatus === "flagged").length})
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("valid")}
                                  className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                                    rowFilter === "valid"
                                      ? "bg-[var(--foreground)] text-[var(--card)]"
                                      : "bg-[var(--surface-sunken)] border border-[var(--border-subtle)] text-[var(--foreground)]"
                                  }`}
                                >
                                  Valid ({previewRows.filter((r) => r.validationStatus === "valid").length})
                                </button>
                                <button
                                  type="button"
                                  onClick={() => setRowFilter("skipped")}
                                  className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                                    rowFilter === "skipped"
                                      ? "bg-[var(--foreground)] text-[var(--card)]"
                                      : "bg-[var(--card)] border border-[var(--border-subtle)] text-[var(--text-muted)]"
                                  }`}
                                >
                                  Skipped ({previewRows.filter((r) => r.validationStatus === "skipped").length})
                                </button>
                              </div>
                            </div>

                            {isLoadingPreviewRows ? (
                              <div className="flex justify-center p-6 text-sm text-[var(--text-muted)]">
                                <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rows...
                              </div>
                            ) : filteredPreviewRows.length === 0 ? (
                              <div className="rounded-lg border border-dashed border-[var(--border-subtle)] p-6 text-center text-sm text-[var(--text-muted)]">
                                No rows match the selected filter ({rowFilter}).
                              </div>
                            ) : (
                              <div className="rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] overflow-x-auto max-h-72">
                                <table className="w-full text-left text-sm">
                                  <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)] sticky top-0">
                                    <tr>
                                      <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-10">#</th>
                                      <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-24">Status</th>
                                      <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-28">VCode</th>
                                      <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)]">Store & Mother</th>
                                      <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)]">Employee</th>
                                      <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)]">Position / HC</th>
                                      <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)]">Validation Issues & Guidance</th>
                                    </tr>
                                  </thead>
                                  <tbody className="divide-y divide-[var(--border-subtle)]">
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
                                              ? "bg-[var(--danger-bg)]/40 hover:bg-[var(--danger-bg)]/60"
                                              : isRowFlagged
                                              ? "bg-[var(--surface-sunken)]/40 hover:bg-[var(--surface-sunken)]/60"
                                              : isRowSkipped
                                              ? "bg-[var(--surface-muted)]/40 hover:bg-[var(--surface-muted)]/60 text-[var(--text-muted)]"
                                              : "hover:bg-[var(--surface-muted)]/50"
                                          }`}
                                        >
                                          <td className="px-2.5 py-1.5 align-middle font-mono text-sm text-[var(--text-muted)]">{r.rowNumber}</td>
                                          <td className="px-2.5 py-1.5 align-middle whitespace-nowrap">
                                            <span
                                              className={`inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium uppercase whitespace-nowrap leading-none ${
                                                isRowBlocked
                                                  ? "bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)]"
                                                  : isRowFlagged
                                                  ? "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                                                  : isRowValid
                                                  ? "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                                                  : isRowSkipped
                                                  ? "bg-[var(--surface-muted)] text-[var(--text-muted)] border border-[var(--border-subtle)]"
                                                  : "bg-[var(--surface-muted)] text-[var(--foreground)]"
                                              }`}
                                            >
                                              {r.validationStatus}
                                            </span>
                                          </td>
                                          <td className="px-2.5 py-1.5 align-middle font-medium font-mono text-[var(--foreground)] text-sm whitespace-nowrap leading-tight">
                                            {r.vcode || "—"}
                                          </td>
                                          <td className="px-2.5 py-1.5 align-middle">
                                            <div className="font-medium text-[var(--foreground)] text-sm leading-tight">{r.storeName || "—"}</div>
                                            {r.motherAccount && (
                                              <div className="text-xs text-[var(--text-muted)] font-mono leading-tight mt-0.5">
                                                Mother: {r.motherAccount}
                                              </div>
                                            )}
                                          </td>
                                          <td className="px-2.5 py-1.5 align-middle">
                                            {r.employeeNo || r.employeeName ? (
                                              <div className="space-y-0.5">
                                                <div className="font-medium text-[var(--foreground)] text-sm leading-tight">{r.employeeName || "—"}</div>
                                                <div className="flex items-center gap-1.5 flex-wrap leading-tight">
                                                  {r.employeeNo && (
                                                    <span className="text-xs font-mono text-[var(--text-muted)] leading-tight">ID: {r.employeeNo}</span>
                                                  )}
                                                  {r.needsHrco && !accountHasAssignedHrco && !r.resolvedHrcoUserId && (!r.hrcoEmail || !r.hrcoEmail.trim()) && (
                                                    <span className="rounded bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-medium px-1.5 py-0.5 whitespace-nowrap leading-none border border-[var(--border-subtle)]">
                                                      NEEDS HRCO
                                                    </span>
                                                  )}
                                                </div>
                                              </div>
                                            ) : (
                                              <span className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)] whitespace-nowrap leading-none">
                                                (Vacant Baseline Slot)
                                              </span>
                                            )}
                                          </td>
                                          <td className="px-2.5 py-1.5 align-middle text-[var(--text-muted)]">
                                            <div className="font-medium text-[var(--foreground)] text-sm leading-tight">{r.position || "—"}</div>
                                            <div className="text-xs text-[var(--text-muted)] flex items-center gap-1.5 flex-wrap mt-0.5 leading-tight">
                                              {r.employmentType && (
                                                <span className="rounded px-1.5 py-0.5 text-xs font-medium uppercase whitespace-nowrap leading-none bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]">
                                                  {r.employmentType}
                                                </span>
                                              )}
                                              {r.requiredHc !== undefined && <span>{r.requiredHc} HC</span>}
                                            </div>
                                            {(r.scheduleDays || r.scheduleTime || r.dayoff) && (
                                              <div
                                                className="text-xs text-[var(--text-muted)] truncate mt-0.5 leading-tight"
                                                title={[r.scheduleDays, r.scheduleTime, r.dayoff ? `Off: ${r.dayoff}` : null].filter(Boolean).join(" • ")}
                                              >
                                                {[r.scheduleDays, r.scheduleTime, r.dayoff ? `Off: ${r.dayoff}` : null].filter(Boolean).join(" • ")}
                                              </div>
                                            )}
                                          </td>
                                          <td className="px-2.5 py-1.5 align-middle">
                                            {isRowBlocked && (
                                              <div className="space-y-0.5 text-xs leading-snug">
                                                {r.validationErrors && r.validationErrors.length > 0 ? (
                                                  r.validationErrors.map((err, errIdx) => (
                                                    <div
                                                      key={errIdx}
                                                      className="flex items-start gap-1 text-[var(--danger)] leading-snug"
                                                    >
                                                      {err.conflictType && (
                                                        <span className="rounded bg-[var(--danger-bg)] text-[var(--danger)] px-1.5 py-0.5 text-xs font-mono font-medium shrink-0 leading-none border border-[var(--danger-border)]">
                                                          {err.conflictType}
                                                        </span>
                                                      )}
                                                      {!err.conflictType && err.field && (
                                                        <span className="rounded bg-[var(--danger-bg)] text-[var(--danger)] px-1.5 py-0.5 text-xs font-mono font-medium shrink-0 leading-none border border-[var(--danger-border)]">
                                                          {err.field}
                                                        </span>
                                                      )}
                                                      <span className="font-normal break-words">{err.msg}</span>
                                                    </div>
                                                  ))
                                                ) : (
                                                  r.validationMessages.map((msg, mIdx) => (
                                                    <div key={mIdx} className="text-[var(--danger)] font-normal break-words">
                                                      • {msg}
                                                    </div>
                                                  ))
                                                )}
                                              </div>
                                            )}
                                            {isRowFlagged && (
                                              <div className="space-y-0.5 text-xs leading-snug">
                                                {r.validationFlags && r.validationFlags.length > 0 ? (
                                                  r.validationFlags.map((flag, fIdx) => (
                                                    <div
                                                      key={fIdx}
                                                      className="flex items-start gap-1 text-[var(--foreground)] leading-snug"
                                                    >
                                                      {flag.flag && (
                                                        <span className="rounded bg-[var(--surface-sunken)] text-[var(--foreground)] px-1.5 py-0.5 text-xs font-mono font-medium shrink-0 leading-none border border-[var(--border-subtle)]">
                                                          {flag.flag}
                                                        </span>
                                                      )}
                                                      <span className="font-normal break-words">{flag.msg}</span>
                                                    </div>
                                                  ))
                                                ) : (
                                                  r.validationMessages.map((msg, mIdx) => (
                                                    <div key={mIdx} className="text-[var(--foreground)] font-normal break-words">
                                                      • {msg}
                                                    </div>
                                                  ))
                                                )}
                                              </div>
                                            )}
                                            {isRowValid && (
                                              <span className="inline-flex items-center gap-1 text-[var(--foreground)] text-xs font-medium leading-tight">
                                                <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-[var(--text-muted)]" /> Ready for import
                                              </span>
                                            )}
                                            {isRowSkipped && (
                                              <span className="inline-flex items-center gap-1 text-[var(--text-muted)] text-xs font-medium leading-tight">
                                                Existing VCODE skipped (vacant row)
                                              </span>
                                            )}
                                            {!isRowBlocked && !isRowFlagged && !isRowValid && !isRowSkipped && (
                                              <span className="text-[var(--text-subtle)] text-xs leading-tight">Pending</span>
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
                              <div className="pt-2 flex justify-end">
                                <button
                                  type="button"
                                  onClick={() => openRejectModal(batch)}
                                  disabled={isActionPending}
                                  className="h-9 px-3 rounded-lg bg-[var(--danger-bg)] hover:opacity-90 text-[var(--danger)] border border-[var(--danger-border)] text-sm font-semibold transition disabled:opacity-50 shrink-0"
                                >
                                  {isValidationFailed ? "Dismiss / Reject Batch" : "Reject Batch"}
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

          {/* Tab 3: History */}
          {activeTab === "history" && (
            <div className="space-y-4">
              {historyBatches.length === 0 ? (
                <div className="rounded-xl border border-dashed border-[var(--border-subtle)] p-8 text-center text-sm text-[var(--text-muted)]">
                  No historical import logs recorded yet.
                </div>
              ) : (
                <div className="rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] overflow-x-auto">
                  <table className="w-full min-w-[920px] table-fixed text-left text-sm">
                    <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)]">
                      <tr>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-20">Batch #</th>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-44">File Name</th>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-28">Status</th>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-20">Stores / HC</th>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-44">Rollback State & Window</th>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-36">Scope</th>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-32">Uploaded By</th>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-36">Approved / Rejected By</th>
                        <th className="text-xs font-semibold uppercase tracking-wider px-2.5 py-1.5 text-[var(--text-muted)] w-24">Date</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--border-subtle)]">
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
                              isSelected ? "bg-[var(--surface-muted)]" : "hover:bg-[var(--surface-muted)]/50"
                            }`}
                          >
                            <td className="px-2.5 py-1.5 align-middle font-mono text-sm font-semibold text-[var(--foreground)] whitespace-nowrap leading-tight">
                              #{b.id.slice(0, 8)}
                            </td>
                            <td className="px-2.5 py-1.5 align-middle font-medium text-[var(--foreground)] text-sm leading-tight">
                              <div className="flex items-center gap-1.5 min-w-0" title={b.fileName}>
                                <span className="truncate">{b.fileName}</span>
                                {isSelected && (
                                  <span className="rounded-full bg-[var(--surface-sunken)] text-[var(--foreground)] text-xs font-bold px-1.5 py-0.5 whitespace-nowrap shrink-0 border border-[var(--border-subtle)]">
                                    Selected
                                  </span>
                                )}
                              </div>
                            </td>
                            <td className="px-2.5 py-1.5 align-middle whitespace-nowrap leading-tight">
                              <span
                                className={`inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium uppercase whitespace-nowrap leading-none ${
                                  b.status.includes("rolled_back") || b.status.includes("reject")
                                    ? "bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)]"
                                    : isApproved
                                    ? "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                                    : "bg-[var(--surface-muted)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                                }`}
                              >
                                {b.status.replace("_", " ")}
                              </span>
                            </td>
                            <td className="px-2.5 py-1.5 align-middle font-mono text-sm font-medium text-[var(--foreground)] whitespace-nowrap leading-tight">
                              {b.committedStores ?? b.totalRows} / {b.committedEmployees ?? b.validRows}
                            </td>
                            <td className="px-2.5 py-1.5 align-middle whitespace-nowrap leading-tight">
                              {b.rollbackStatus === "requested" ? (
                                <span className="inline-flex items-center gap-1 rounded bg-[var(--surface-sunken)] text-[var(--foreground)] px-1.5 py-0.5 text-xs font-medium uppercase whitespace-nowrap leading-none border border-[var(--border-subtle)]">
                                  <Clock className="h-3 w-3 shrink-0" /> Rollback Requested
                                </span>
                              ) : b.rollbackStatus === "completed" || b.status === "rolled_back" ? (
                                <span className="inline-flex items-center gap-1 rounded bg-[var(--danger-bg)] text-[var(--danger)] px-1.5 py-0.5 text-xs font-medium uppercase whitespace-nowrap leading-none border border-[var(--danger-border)]">
                                  <RotateCcw className="h-3 w-3 shrink-0" /> Rolled Back
                                </span>
                              ) : b.rollbackStatus === "failed" ? (
                                <span className="inline-flex items-center gap-1 rounded bg-[var(--danger-bg)] text-[var(--danger)] px-1.5 py-0.5 text-xs font-medium uppercase whitespace-nowrap leading-none border border-[var(--danger-border)]">
                                  <AlertCircle className="h-3 w-3 shrink-0" /> Rollback Failed
                                </span>
                              ) : isApproved ? (
                                b.rollbackAllowed ? (
                                  <span className="inline-flex items-center gap-1 rounded bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)] px-1.5 py-0.5 text-xs font-medium whitespace-nowrap leading-none">
                                    <Clock className="h-3 w-3 text-[var(--text-muted)] shrink-0" />
                                    Expires: {formatRollbackRemaining(b.rollbackRemainingSeconds)}
                                  </span>
                                ) : (
                                  <span className="rounded bg-[var(--surface-muted)] text-[var(--text-muted)] px-1.5 py-0.5 text-xs font-medium whitespace-nowrap leading-none">
                                    Window Expired
                                  </span>
                                )
                              ) : (
                                <span className="text-[var(--text-subtle)] text-sm">—</span>
                              )}
                            </td>
                            <td
                              className="px-2.5 py-1.5 align-middle text-[var(--text-muted)] text-sm leading-tight"
                              title={`${b.groupName ?? "—"} / ${b.accountName ?? "—"}`}
                            >
                              <span className="truncate block max-w-full">
                                {b.groupName ?? "—"} / {b.accountName ?? "—"}
                              </span>
                            </td>
                            <td
                              className="px-2.5 py-1.5 align-middle text-[var(--text-muted)] text-sm leading-tight"
                              title={formatActor(b.uploadedBy)}
                            >
                              <span className="truncate block max-w-full">
                                {formatActor(b.uploadedBy)}
                              </span>
                            </td>
                            <td
                              className="px-2.5 py-1.5 align-middle text-[var(--text-muted)] text-sm leading-tight"
                              title={rawActor ? (isRejection ? `[Rej] ${actorDisplay}` : actorDisplay) : "—"}
                            >
                              <span className="truncate block max-w-full">
                                {isRejection && rawActor ? `[Rej] ${actorDisplay}` : actorDisplay}
                              </span>
                            </td>
                            <td
                              className="px-2.5 py-1.5 align-middle text-[var(--text-subtle)] text-sm leading-tight whitespace-nowrap"
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
                  <div className="rounded-xl border border-[var(--danger-border)] bg-[var(--danger-bg)]/20 p-4 space-y-4">
                    <div className="flex items-center justify-between border-b border-[var(--border-subtle)] pb-3">
                      <div className="flex items-center gap-2">
                        <AlertCircle className="h-4 w-4 text-[var(--danger)]" />
                        <h4 className="text-sm font-bold text-[var(--foreground)]">
                          Import Failure Audit & Error Log — #{historySelectedBatch.id.slice(0, 8)} (
                          {historySelectedBatch.fileName})
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
                        <span className="font-bold text-[var(--danger)] uppercase mt-0.5 block">
                          {historySelectedBatch.status.replace("_", " ")}
                        </span>
                      </div>
                      <div className="p-2.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                        <span className="text-[var(--text-muted)] block">Scope</span>
                        <span className="font-bold text-[var(--foreground)] mt-0.5 block truncate">
                          {historySelectedBatch.groupName || "—"} / {historySelectedBatch.accountName || "—"}
                        </span>
                      </div>
                      <div className="p-2.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                        <span className="text-[var(--text-muted)] block">Failed / Blocked Rows</span>
                        <span className="font-bold text-[var(--danger)] mt-0.5 block">
                          {historySelectedBatch.blockedRows} / {historySelectedBatch.totalRows} rows
                        </span>
                      </div>
                      <div className="p-2.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                        <span className="text-[var(--text-muted)] block">Valid Rows</span>
                        <span className="font-bold text-[var(--foreground)] mt-0.5 block">
                          {historySelectedBatch.validRows} rows
                        </span>
                      </div>
                    </div>

                    {(historySelectedBatch.rejectionReasonNote ||
                      historySelectedBatch.rejectionReason) && (
                      <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-sm text-[var(--danger)] space-y-1">
                        <div className="font-bold uppercase text-xs">Rejection Reason / Note:</div>
                        <div>
                          {historySelectedBatch.rejectionReasonNote ||
                            historySelectedBatch.rejectionReason}
                        </div>
                      </div>
                    )}

                    {(() => {
                      const errorEntries = getActualErrorEntries(historySelectedBatch.errorSummary);
                      if (errorEntries.length === 0) return null;
                      return (
                        <div className="flex flex-wrap items-center gap-1.5 p-2 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                          <span className="text-xs text-[var(--danger)] font-bold uppercase">
                            Field error breakdown:
                          </span>
                          {errorEntries.map(([f, cnt]) => (
                            <span
                              key={f}
                              className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)] text-xs font-mono font-semibold px-2 py-0.5"
                            >
                              {f}: {cnt}
                            </span>
                          ))}
                        </div>
                      );
                    })()}

                    {/* Row Inspection in History */}
                    <div className="space-y-3 pt-2">
                      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                        <h5 className="text-sm font-bold text-[var(--foreground)]">
                          Row Error Breakdown ({historyRows.length} total rows)
                        </h5>

                        {/* Quick Filter Pills */}
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="text-xs font-semibold text-[var(--text-muted)] mr-1">Filter:</span>
                          <button
                            type="button"
                            onClick={() => setHistoryRowFilter("all")}
                            className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                              historyRowFilter === "all"
                                ? "bg-[var(--foreground)] text-[var(--card)]"
                                : "bg-[var(--card)] border border-[var(--border-subtle)] text-[var(--text-muted)] hover:text-[var(--foreground)]"
                            }`}
                          >
                            All ({historyRows.length})
                          </button>
                          <button
                            type="button"
                            onClick={() => setHistoryRowFilter("blocked")}
                            className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                              historyRowFilter === "blocked"
                                ? "bg-[var(--danger)] text-white"
                                : "bg-[var(--danger-bg)] border border-[var(--danger-border)] text-[var(--danger)]"
                            }`}
                          >
                            Blocked ({historyRows.filter((r) => r.validationStatus === "blocked").length})
                          </button>
                          <button
                            type="button"
                            onClick={() => setHistoryRowFilter("flagged")}
                            className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                              historyRowFilter === "flagged"
                                ? "bg-[var(--foreground)] text-[var(--card)]"
                                : "bg-[var(--surface-sunken)] border border-[var(--border-subtle)] text-[var(--foreground)]"
                            }`}
                          >
                            Flagged ({historyRows.filter((r) => r.validationStatus === "flagged").length})
                          </button>
                          <button
                            type="button"
                            onClick={() => setHistoryRowFilter("valid")}
                            className={`px-2 py-0.5 rounded-md text-xs font-semibold transition ${
                              historyRowFilter === "valid"
                                ? "bg-[var(--foreground)] text-[var(--card)]"
                                : "bg-[var(--surface-sunken)] border border-[var(--border-subtle)] text-[var(--foreground)]"
                            }`}
                          >
                            Valid ({historyRows.filter((r) => r.validationStatus === "valid").length})
                          </button>
                        </div>
                      </div>

                      {isLoadingHistoryRows ? (
                        <div className="flex justify-center p-6 text-sm text-[var(--text-muted)]">
                          <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rows...
                        </div>
                      ) : filteredHistoryRows.length === 0 ? (
                        <div className="rounded-lg border border-dashed border-[var(--border-subtle)] p-6 text-center text-sm text-[var(--text-muted)]">
                          No rows match the selected filter ({historyRowFilter}).
                        </div>
                      ) : (
                        <div className="rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] overflow-x-auto max-h-72">
                          <table className="w-full text-left text-sm">
                            <thead className="bg-[var(--surface-muted)] border-b border-[var(--border-subtle)] sticky top-0 text-xs uppercase text-[var(--text-muted)] font-bold">
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
                            <tbody className="divide-y divide-[var(--border-subtle)]">
                              {filteredHistoryRows.map((r) => {
                                const isRowBlocked = r.validationStatus === "blocked";
                                const isRowFlagged = r.validationStatus === "flagged";
                                const isRowValid = r.validationStatus === "valid";

                                return (
                                  <tr
                                    key={r.rowNumber}
                                    className={`${
                                      isRowBlocked
                                        ? "bg-[var(--danger-bg)]/40 hover:bg-[var(--danger-bg)]/60"
                                        : isRowFlagged
                                        ? "bg-[var(--surface-sunken)]/40 hover:bg-[var(--surface-sunken)]/60"
                                        : "hover:bg-[var(--surface-muted)]/50"
                                    }`}
                                  >
                                    <td className="py-2 px-2.5 font-mono text-sm text-[var(--text-muted)]">{r.rowNumber}</td>
                                    <td className="py-2 px-2.5 whitespace-nowrap">
                                      <span
                                        className={`inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-bold uppercase whitespace-nowrap leading-none ${
                                          isRowBlocked
                                            ? "bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)]"
                                            : isRowFlagged
                                            ? "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                                            : isRowValid
                                            ? "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                                            : "bg-[var(--surface-muted)] text-[var(--foreground)]"
                                        }`}
                                      >
                                        {r.validationStatus}
                                      </span>
                                    </td>
                                    <td className="py-2 px-2.5 font-bold font-mono text-[var(--foreground)] text-sm whitespace-nowrap">
                                      {r.vcode || "—"}
                                    </td>
                                    <td className="py-2 px-2.5">
                                      <div className="font-semibold text-[var(--foreground)] text-sm leading-tight">{r.storeName || "—"}</div>
                                    </td>
                                    <td className="py-2 px-2.5">
                                      {r.employeeNo || r.employeeName ? (
                                        <div className="space-y-0.5">
                                          <div className="font-medium text-[var(--foreground)] text-sm leading-tight">{r.employeeName || "—"}</div>
                                          {r.employeeNo && (
                                            <div className="text-xs font-mono text-[var(--text-muted)] leading-tight">
                                              ID: {r.employeeNo}
                                            </div>
                                          )}
                                        </div>
                                      ) : (
                                        <span className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-semibold bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)] whitespace-nowrap leading-none">
                                          (Vacant Slot)
                                        </span>
                                      )}
                                    </td>
                                    <td className="py-2 px-2.5 text-[var(--text-muted)]">
                                      <div className="font-medium text-[var(--foreground)] text-sm leading-tight">{r.position || "—"}</div>
                                      {r.employmentType && (
                                        <div className="mt-0.5 leading-tight">
                                          <span className="rounded px-1.5 py-0.5 text-xs font-bold uppercase whitespace-nowrap leading-none bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]">
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
                                                className="flex items-start gap-1.5 text-[var(--danger)] text-sm leading-tight"
                                              >
                                                {err.conflictType && (
                                                  <span className="rounded bg-[var(--danger-bg)] text-[var(--danger)] px-1.5 py-0.5 text-xs font-mono font-bold shrink-0 leading-none border border-[var(--danger-border)]">
                                                    {err.conflictType}
                                                  </span>
                                                )}
                                                {!err.conflictType && err.field && (
                                                  <span className="rounded bg-[var(--danger-bg)] text-[var(--danger)] px-1.5 py-0.5 text-xs font-mono font-bold shrink-0 leading-none border border-[var(--danger-border)]">
                                                    {err.field}
                                                  </span>
                                                )}
                                                <span className="font-medium break-words leading-tight">{err.msg}</span>
                                              </div>
                                            ))
                                          ) : (
                                            r.validationMessages.map((msg, mIdx) => (
                                              <div key={mIdx} className="text-[var(--danger)] text-sm font-medium break-words leading-tight">
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
                                                className="flex items-start gap-1.5 text-[var(--foreground)] text-sm leading-tight"
                                              >
                                                {flag.flag && (
                                                  <span className="rounded bg-[var(--surface-sunken)] text-[var(--foreground)] px-1.5 py-0.5 text-xs font-mono font-bold shrink-0 leading-none border border-[var(--border-subtle)]">
                                                    {flag.flag}
                                                  </span>
                                                )}
                                                <span className="font-medium break-words leading-tight">{flag.msg}</span>
                                              </div>
                                            ))
                                          ) : (
                                            r.validationMessages.map((msg, mIdx) => (
                                              <div key={mIdx} className="text-[var(--foreground)] text-sm font-medium break-words leading-tight">
                                                • {msg}
                                              </div>
                                            ))
                                          )}
                                        </div>
                                      )}
                                      {isRowValid && (
                                        <span className="inline-flex items-center gap-1 text-[var(--foreground)] text-sm font-semibold leading-tight">
                                          <CheckCircle2 className="h-4 w-4 shrink-0 text-[var(--text-muted)]" /> Valid slot
                                        </span>
                                      )}
                                      {!isRowBlocked && !isRowFlagged && !isRowValid && (
                                        <span className="text-[var(--text-muted)] text-sm leading-tight">Skipped</span>
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
                  <div className="rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-muted)]/40 p-4 space-y-4">
                    <div className="flex items-center justify-between border-b border-[var(--border-subtle)] pb-3">
                      <div className="flex items-center gap-2">
                        <RotateCcw className="h-4 w-4 text-[var(--foreground)]" />
                        <h4 className="text-sm font-bold text-[var(--foreground)]">
                          Rollback Governance — #{historySelectedBatch.id.slice(0, 8)} (
                          {historySelectedBatch.fileName})
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
                        <span className="font-bold text-[var(--foreground)] uppercase mt-0.5 block">
                          {historySelectedBatch.status}
                        </span>
                      </div>
                      <div className="p-2.5 rounded-lg bg-[var(--card)] border border-[var(--border-subtle)]">
                        <span className="text-[var(--text-muted)] block">Rollback Status</span>
                        <span className="font-bold text-[var(--foreground)] uppercase mt-0.5 block">
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
                        <span className="text-[var(--text-muted)] block">Total Headcount Rows</span>
                        <span className="font-bold text-[var(--foreground)] mt-0.5 block">
                          {historySelectedBatch.totalRows} rows
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
                          Rollback attempt failed:{" "}
                          {humanizeRollbackError(historySelectedBatch.rollbackErrorDetail)}
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

                      {/* Step 1: Request Rollback Button */}
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

                      {/* Step 2: Approve & Execute Rollback Button (Head Admin or Super Admin) */}
                      {canApprove &&
                        historySelectedBatch.status.toLowerCase().includes("approved") &&
                        historySelectedBatch.rollbackStatus === "requested" && (
                          <>
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

                            <button
                              type="button"
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
                              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] text-sm font-semibold text-[var(--foreground)] hover:bg-[var(--surface-muted)] transition"
                            >
                              <X className="h-4 w-4 text-[var(--text-muted)]" />
                              Reject Rollback Request
                            </button>
                          </>
                        )}

                      {/* Emergency Rollback Override (Super Admin Only) */}
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

      {/* REJECTION REASON MODAL */}
      {isRejectModalOpen && rejectTargetBatch && (
        <Modal
          isOpen={isRejectModalOpen}
          onClose={closeRejectModal}
          title={
            <span className="flex items-center gap-2">
              <span>Reject Plantilla Batch</span>
              <span className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] text-xs font-bold px-2 py-0.5 border border-[var(--danger-border)]">
                REJECTION
              </span>
            </span>
          }
          subtitle={`Batch #${rejectTargetBatch.id.slice(0, 8)} ${rejectTargetBatch.fileName ? `(${rejectTargetBatch.fileName})` : ""}`}
          icon={AlertCircle}
          maxWidthClass="max-w-md"
          disableBackdropClick={isActionPending}
          isSubmitting={isActionPending}
          isDirty={Boolean(rejectionNote.trim())}
        >
          <div className="space-y-4">
            {(rejectTargetBatch.groupName || rejectTargetBatch.accountName) && (
              <div className="text-xs text-[var(--text-muted)] bg-[var(--surface-muted)] p-3 rounded-xl border border-[var(--border-subtle)]">
                <span className="font-semibold text-[var(--foreground)]">Scope:</span> {rejectTargetBatch.groupName || "—"} /{" "}
                {rejectTargetBatch.accountName || "—"}
              </div>
            )}

            <div className="space-y-1.5">
              <label className="text-sm font-semibold text-[var(--foreground)] block">
                Rejection Reason / Audit Remarks <span className="text-[var(--danger)]">*</span>
              </label>
              <textarea
                value={rejectionNote}
                onChange={(e) => {
                  setRejectionNote(e.target.value);
                  if (rejectionNoteError) setRejectionNoteError(null);
                }}
                disabled={isActionPending}
                placeholder="Please provide an audited reason note for rejection..."
                rows={3}
                className="w-full rounded-xl border border-[var(--border-subtle)] bg-[var(--card)] p-3 text-sm text-[var(--foreground)] placeholder:text-[var(--text-muted)] focus:outline-hidden focus:ring-2 focus:ring-[var(--danger)] resize-none"
              />
              {rejectionNoteError && (
                <div className="text-xs text-[var(--danger)] font-medium flex items-center gap-1.5 pt-1">
                  <AlertCircle className="h-3.5 w-3.5 shrink-0" />
                  <span>{rejectionNoteError}</span>
                </div>
              )}
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border-subtle)]">
              <button
                type="button"
                onClick={closeRejectModal}
                disabled={isActionPending}
                className="px-3.5 py-2 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] text-sm font-semibold text-[var(--text-muted)] hover:bg-[var(--surface-muted)] transition disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmRejection}
                disabled={isActionPending}
                className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg bg-[var(--danger)] hover:opacity-90 text-white text-sm font-semibold transition disabled:opacity-50"
              >
                {isActionPending ? (
                  <>
                    <Loader2 className="h-3.5 w-3.5 animate-spin" /> Rejecting...
                  </>
                ) : (
                  "Confirm Rejection"
                )}
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* SUB-MODAL 1: Request Rollback Modal */}
      {isRequestRollbackOpen && historySelectedBatch && (
        <Modal
          isOpen={isRequestRollbackOpen}
          onClose={() => setIsRequestRollbackOpen(false)}
          title={
            <span className="flex items-center gap-2">
              <span>Request Import Rollback</span>
              <span className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] text-xs font-bold px-2 py-0.5 border border-[var(--danger-border)]">
                DESTRUCTIVE
              </span>
            </span>
          }
          subtitle={`Batch #${historySelectedBatch.id.slice(0, 8)} (${historySelectedBatch.fileName})`}
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
                <label className="text-sm font-semibold text-[var(--foreground)] block mb-1">Rollback Reason (Required)</label>
                <select
                  value={selectedRollbackReason}
                  onChange={(e) => setSelectedRollbackReason(e.target.value)}
                  className="w-full h-10 rounded-lg border border-[var(--border-subtle)] bg-[var(--card)] px-3 text-sm text-[var(--foreground)] focus:outline-hidden"
                >
                  {IMPORT_ROLLBACK_REASONS.map((r) => (
                    <option key={r.code} value={r.code}>
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
                  placeholder="Provide detailed audited reason for requesting this rollback..."
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
              <span>Approve & Execute Rollback?</span>
              <span className="rounded-md bg-[var(--danger-bg)] text-[var(--danger)] text-xs font-bold px-2 py-0.5 border border-[var(--danger-border)]">
                DESTRUCTIVE
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
              WARNING: This will immediately deactivate plantilla rows and store allocations mutated by this batch and
              restore pre-commit snapshots. Rollback safety rules are still enforced server-side (newer approved imports
              for the same Group/Account will block this).
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
                Approve & Execute
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
              <span className="rounded-md bg-surface-muted text-text-primary text-xs font-bold px-2 py-0.5 border border-border-default">
                EMERGENCY OVERRIDE
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
      <PlantillaRollbackHistoryModal
        isOpen={isRollbackHistoryOpen}
        onClose={() => setIsRollbackHistoryOpen(false)}
        batchId={historySelectedBatch?.id ?? null}
      />
    </>
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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Rollback Audit History"
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
        ) : !history || !history.rollbackStatus ? (
          <div className="py-8 text-center text-sm text-[var(--text-muted)]">
            No rollback request has been submitted for this batch.
          </div>
        ) : (
          <div className="space-y-3 text-sm">
            <div className="flex items-center justify-between p-3 rounded-xl bg-[var(--surface-muted)] border border-[var(--border-subtle)]">
              <span className="font-semibold text-[var(--foreground)]">Current Status</span>
              <span
                className={`rounded-md px-2 py-0.5 text-xs font-bold uppercase ${
                  history.rollbackStatus === "completed"
                    ? "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                    : history.rollbackStatus === "requested"
                    ? "bg-[var(--surface-sunken)] text-[var(--foreground)] border border-[var(--border-subtle)]"
                    : "bg-[var(--danger-bg)] text-[var(--danger)] border border-[var(--danger-border)]"
                }`}
              >
                {history.rollbackStatus}
              </span>
            </div>

            <div className="space-y-2 p-3 rounded-xl border border-[var(--border-subtle)] bg-[var(--card)]">
              <div className="flex justify-between text-xs">
                <span className="text-[var(--text-muted)]">Requested By:</span>
                <span className="font-medium text-[var(--foreground)]">
                  {history.rollbackRequestedByName || history.rollbackRequestedBy || "—"}
                </span>
              </div>
              <div className="flex justify-between text-xs">
                <span className="text-[var(--text-muted)]">Requested At:</span>
                <span className="font-medium text-[var(--foreground)]">
                  {history.rollbackRequestedAt ? new Date(history.rollbackRequestedAt).toLocaleString() : "—"}
                </span>
              </div>
              <div className="pt-2 border-t border-[var(--border-subtle)]">
                <span className="text-xs text-[var(--text-muted)] block">Reason:</span>
                <span className="font-semibold text-[var(--foreground)] block mt-0.5">
                  {IMPORT_ROLLBACK_REASONS.find((r) => r.code === history.rollbackReasonCode)?.label ||
                    history.rollbackReason ||
                    "—"}
                </span>
              </div>
              {history.rollbackReasonNote && (
                <div className="pt-1">
                  <span className="text-xs text-[var(--text-muted)] block">Remarks:</span>
                  <span className="text-[var(--text-muted)] block mt-0.5 bg-[var(--surface-muted)] p-2 rounded-lg border border-[var(--border-subtle)]">
                    {history.rollbackReasonNote}
                  </span>
                </div>
              )}
            </div>

            {history.rollbackApprovedAt && (
              <div className="space-y-2 p-3 rounded-xl border border-[var(--border-subtle)] bg-[var(--card)]">
                <div className="flex justify-between text-xs">
                  <span className="text-[var(--text-muted)]">Approved By:</span>
                  <span className="font-medium text-[var(--foreground)]">
                    {history.rollbackApprovedByName || history.rollbackApprovedBy || "—"}
                  </span>
                </div>
                <div className="flex justify-between text-xs">
                  <span className="text-[var(--text-muted)]">Approved At:</span>
                  <span className="font-medium text-[var(--foreground)]">
                    {new Date(history.rollbackApprovedAt).toLocaleString()}
                  </span>
                </div>
                {history.rollbackCompletedAt && (
                  <div className="flex justify-between text-xs">
                    <span className="text-[var(--text-muted)]">Completed At:</span>
                    <span className="font-medium text-[var(--foreground)]">
                      {new Date(history.rollbackCompletedAt).toLocaleString()}
                    </span>
                  </div>
                )}
                {history.rollbackErrorDetail && (
                  <div className="pt-2 border-t border-[var(--border-subtle)] text-[var(--danger)] text-xs font-semibold">
                    Error: {humanizeRollbackError(history.rollbackErrorDetail)}
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
