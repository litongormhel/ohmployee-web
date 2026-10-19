"use client";

import React, { useMemo, useRef, useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  Download,
  FileSpreadsheet,
  History,
  Layers,
  Loader2,
  RefreshCw,
  Send,
  UploadCloud,
  X,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import {
  downloadVacancyImportTemplate,
  parseSpreadsheetToRows,
  VACANCY_REQUIRED_HEADERS,
} from "@/lib/utils/data_control_xlsx";
import {
  approveVacancyImportBatch,
  rejectVacancyImportBatch,
  submitVacancyImport,
  useDataControlAccounts,
  useDataControlGroups,
  useVacancyImportBatches,
  useVacancyImportRows,
} from "@/lib/queries/dataControl";

export interface VacancyImportModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type TabType = "upload" | "review" | "history";

export function VacancyImportModal({ isOpen, onClose }: VacancyImportModalProps) {
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

  const fileInputRef = useRef<HTMLInputElement>(null);

  const { data: groups = [] } = useDataControlGroups();
  const { data: accounts = [], isLoading: isLoadingAccounts } = useDataControlAccounts(selectedGroupId || null);
  const { data: batches = [], refetch: refetchBatches, isLoading: isLoadingBatches } = useVacancyImportBatches();
  const { data: previewRows = [], isLoading: isLoadingPreviewRows } = useVacancyImportRows(selectedBatchId);

  const canApprove = useMemo(() => {
    const role = (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
    return role.includes("super_admin") || role.includes("head_admin") || role === "sa" || role === "ha";
  }, [currentUser]);

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
            <div className="space-y-3">
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
                        <th className="py-2.5 px-4">Scope</th>
                        <th className="py-2.5 px-4">Uploaded By</th>
                        <th className="py-2.5 px-4">Date</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {historyBatches.map((b) => (
                        <tr key={b.id} className="hover:bg-surface-hover/50">
                          <td className="py-2.5 px-4 font-semibold text-text-primary">{b.fileName}</td>
                          <td className="py-2.5 px-4">
                            <span
                              className={`rounded-md px-2 py-0.5 text-3xs font-bold uppercase ${
                                b.status.toLowerCase().includes("approved")
                                  ? "bg-emerald-100 text-emerald-800"
                                  : "bg-rose-100 text-rose-800"
                              }`}
                            >
                              {b.status}
                            </span>
                          </td>
                          <td className="py-2.5 px-4 text-text-secondary">
                            {b.groupName} / {b.accountName}
                          </td>
                          <td className="py-2.5 px-4 text-text-secondary">{b.uploadedBy || "—"}</td>
                          <td className="py-2.5 px-4 text-text-muted">
                            {b.createdAt ? new Date(b.createdAt).toLocaleDateString() : "—"}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
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
    </div>
  );
}
