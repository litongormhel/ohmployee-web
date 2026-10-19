"use client";

import React, { useMemo, useRef, useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  Download,
  FileSpreadsheet,
  Loader2,
  Send,
  UploadCloud,
  X,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import {
  downloadPayrollCheckTemplate,
  parseSpreadsheetToRows,
} from "@/lib/utils/data_control_xlsx";
import {
  createPayrollReviewSession,
  fetchAllScopedAccounts,
  fetchGlobalPlantillaForPayrollCheck,
  PayrollCheckResult,
  reconcilePayroll,
} from "@/lib/queries/dataControl";

export interface PayrollImportModalProps {
  isOpen: boolean;
  onClose: () => void;
  onOpenReviewCenter?: () => void;
}

type TabType =
  | "missingInPayroll"
  | "missingInPlantilla"
  | "paidInactive"
  | "mismatch"
  | "duplicates"
  | "clean";

export function PayrollImportModal({
  isOpen,
  onClose,
  onOpenReviewCenter,
}: PayrollImportModalProps) {
  const currentUser = useCurrentUser();

  const [file, setFile] = useState<File | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [result, setResult] = useState<PayrollCheckResult | null>(null);
  const [activeTab, setActiveTab] = useState<TabType>("missingInPayroll");

  // Send to Ops State
  const [isSendingToOps, setIsSendingToOps] = useState(false);
  const [sendSuccess, setSendSuccess] = useState<string | null>(null);
  const [sessionNotes, setSessionNotes] = useState("");
  const [isSubmittingSession, setIsSubmittingSession] = useState(false);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const canManage = useMemo(() => {
    const role = (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
    return (
      role.includes("super_admin") ||
      role.includes("head_admin") ||
      role === "sa" ||
      role === "ha" ||
      role.includes("encoder")
    );
  }, [currentUser]);

  if (!isOpen) return null;

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const picked = e.target.files?.[0];
    if (!picked) return;
    setFile(picked);
    setErrorMessage(null);
    setSendSuccess(null);
    setIsProcessing(true);

    try {
      const { headers, rows } = await parseSpreadsheetToRows(picked);
      const upperHeaders = new Set(headers.map((h) => h.toUpperCase()));

      const hasEmpNo =
        upperHeaders.has("EMPLOYEE_NUMBER") ||
        upperHeaders.has("EMPLOYEE NUMBER") ||
        upperHeaders.has("EMPLOYEE NO.") ||
        upperHeaders.has("EMPLOYEE NO");
      const hasName =
        upperHeaders.has("FULL_NAME") ||
        upperHeaders.has("FULLNAME") ||
        upperHeaders.has("FULL NAME");
      const hasAccount =
        upperHeaders.has("ACCOUNT_GROUP") ||
        upperHeaders.has("ACCOUNT GROUP") ||
        upperHeaders.has("ACCOUNT");

      if (!hasEmpNo || !hasName || !hasAccount) {
        throw new Error(
          `Missing required headers: EMPLOYEE_NUMBER, FULL_NAME, ACCOUNT_GROUP.`
        );
      }

      // Convert rows
      const payrollRows = rows.map((r, i) => ({
        rowNumber: i + 1,
        employeeNumber:
          r["EMPLOYEE_NUMBER"] ||
          r["EMPLOYEE NUMBER"] ||
          r["EMPLOYEE NO."] ||
          r["EMPLOYEE NO"] ||
          "",
        fullName: r["FULL_NAME"] || r["FULLNAME"] || r["FULL NAME"] || "",
        accountGroup:
          r["ACCOUNT_GROUP"] || r["ACCOUNT GROUP"] || r["ACCOUNT"] || "",
      }));

      // Fetch global plantilla & reconcile
      const plantillaRows = await fetchGlobalPlantillaForPayrollCheck();
      const checkResult = reconcilePayroll(payrollRows, plantillaRows);

      setResult(checkResult);
      setActiveTab(
        checkResult.missingInPayroll.length > 0
          ? "missingInPayroll"
          : checkResult.missingInPlantilla.length > 0
          ? "missingInPlantilla"
          : checkResult.mismatch.length > 0
          ? "mismatch"
          : "clean"
      );
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : "Failed to reconcile payroll file."
      );
      setResult(null);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleCreateReviewSession = async () => {
    if (!result || !file) return;
    setIsSubmittingSession(true);
    setErrorMessage(null);

    try {
      const scopedAccounts = await fetchAllScopedAccounts();
      const defaultAccountId =
        scopedAccounts.length > 0 ? scopedAccounts[0].id : "";

      const findingsToPublish = [
        ...result.missingInPayroll,
        ...result.missingInPlantilla,
        ...result.paidInactive,
        ...result.mismatch,
        ...result.duplicates,
      ];

      const items = findingsToPublish.map((f) => {
        // Find matching account id if possible
        const combined = f.plantillaAccountGroup || f.payrollAccountGroup || "";
        const acctName = combined.split(" / ")[0]?.trim().toUpperCase();
        const matched = scopedAccounts.find(
          (a) => a.name.toUpperCase() === acctName
        );
        const targetAccountId = matched ? matched.id : defaultAccountId;

        const parts = combined.split(" / ");
        const acct = parts[0]?.trim() || "";
        const grp = parts.slice(1).join(" / ").trim() || "";

        return {
          findingType: f.findingType,
          employeeNumber: f.employeeNumber,
          payrollFullName: f.payrollFullName,
          plantillaFullName: f.plantillaFullName,
          payrollAccount: acct,
          payrollGroup: grp,
          plantillaAccount: acct,
          plantillaGroup: grp,
          assignedAccountId: targetAccountId,
          assignedGroupId: matched?.groupId,
        };
      });

      const sessionId = await createPayrollReviewSession({
        payrollFileName: file.name,
        notes: sessionNotes.trim() || undefined,
        items,
      });

      setSendSuccess(
        `Created Payroll Review Session #${sessionId.slice(0, 8)} with ${
          items.length
        } discrepancy findings for Ops review.`
      );
      setIsSendingToOps(false);
    } catch (err) {
      setErrorMessage(
        err instanceof Error
          ? err.message
          : "Failed to publish review session."
      );
    } finally {
      setIsSubmittingSession(false);
    }
  };

  const currentFindings = result ? result[activeTab] : [];

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
                <h2 className="text-base font-bold text-text-primary">
                  Import Payroll
                </h2>
                <span className="rounded-md bg-purple-100 text-purple-800 px-2 py-0.5 text-3xs font-bold uppercase tracking-wider">
                  PAYROLL CHECKER
                </span>
              </div>
              <p className="text-xs text-text-secondary">
                Upload wage and payroll sheets to compare against active Plantilla slots. Pure read-only checker without data mutations.
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

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {errorMessage && (
            <div className="rounded-xl border border-rose-200 bg-rose-50/80 p-3.5 flex items-start gap-3">
              <AlertCircle className="h-5 w-5 text-rose-600 shrink-0 mt-0.5" />
              <p className="text-xs font-medium text-rose-800">{errorMessage}</p>
            </div>
          )}

          {sendSuccess && (
            <div className="rounded-xl border border-emerald-200 bg-emerald-50/80 p-3.5 flex items-start gap-3">
              <CheckCircle2 className="h-5 w-5 text-emerald-600 shrink-0 mt-0.5" />
              <div className="space-y-1">
                <p className="text-xs font-medium text-emerald-800">{sendSuccess}</p>
                {onOpenReviewCenter && (
                  <button
                    onClick={() => {
                      onClose();
                      onOpenReviewCenter();
                    }}
                    className="text-xs font-bold text-purple-700 hover:underline"
                  >
                    Open Payroll Review Center →
                  </button>
                )}
              </div>
            </div>
          )}

          {/* Template Download & Upload Dropzone */}
          {!result && (
            <div className="space-y-4">
              <div className="flex justify-end">
                <button
                  onClick={downloadPayrollCheckTemplate}
                  className="h-9 inline-flex items-center justify-center gap-2 rounded-lg border border-border-subtle bg-surface hover:bg-surface-hover text-text-primary text-xs font-semibold px-4 transition"
                >
                  <Download className="h-4 w-4 text-purple-600" />
                  Download 3-Column Payroll Template
                </button>
              </div>

              <div
                onClick={() => fileInputRef.current?.click()}
                className="border-2 border-dashed border-border-subtle hover:border-purple-400 bg-surface-subtle hover:bg-purple-50/20 rounded-2xl p-10 flex flex-col items-center justify-center cursor-pointer transition text-center"
              >
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".xlsx"
                  onChange={handleFileChange}
                  className="hidden"
                />
                <div className="h-12 w-12 rounded-xl bg-purple-100 flex items-center justify-center text-purple-700 mb-3">
                  <UploadCloud className="h-6 w-6" />
                </div>
                <p className="text-sm font-semibold text-text-primary">
                  {file ? file.name : "Click or drag & drop Payroll XLSX file here"}
                </p>
                <p className="text-xs text-text-muted mt-1">
                  Requires columns: EMPLOYEE_NUMBER, FULL_NAME, ACCOUNT_GROUP.
                </p>
                {isProcessing && (
                  <div className="flex items-center gap-2 mt-3 text-xs text-purple-700">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    Loading global plantilla & reconciling payroll findings...
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Reconciliation Findings Display */}
          {result && (
            <div className="space-y-4">
              <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 bg-surface-subtle border border-border-subtle rounded-xl p-3">
                <div className="flex items-center gap-3">
                  <div className="rounded-lg bg-purple-100 text-purple-700 p-2 font-mono text-xs font-bold">
                    {file?.name}
                  </div>
                  <div className="text-xs text-text-secondary">
                    <span>{result.payrollRows} payroll rows</span>
                    <span className="mx-2">·</span>
                    <span>{result.activePlantillaCount} active plantilla slots</span>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={() => {
                      setResult(null);
                      setFile(null);
                      if (fileInputRef.current) fileInputRef.current.value = "";
                    }}
                    className="h-8 px-3 rounded-lg border border-border-subtle bg-surface text-xs font-semibold text-text-secondary hover:text-text-primary transition"
                  >
                    Upload Another File
                  </button>
                  {canManage && (
                    <button
                      onClick={() => setIsSendingToOps(!isSendingToOps)}
                      className="h-8 px-3 rounded-lg bg-purple-600 hover:bg-purple-700 text-white text-xs font-semibold flex items-center gap-1.5 transition"
                    >
                      <Send className="h-3.5 w-3.5" />
                      Send to Ops Review
                    </button>
                  )}
                </div>
              </div>

              {/* Publish to Ops Drawer */}
              {isSendingToOps && (
                <div className="rounded-xl border border-purple-200 bg-purple-50/40 p-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <h4 className="text-xs font-bold text-text-primary">
                      Publish Findings to Ops Payroll Review Center
                    </h4>
                    <span className="text-2xs text-text-muted">
                      {result.missingInPayroll.length +
                        result.missingInPlantilla.length +
                        result.paidInactive.length +
                        result.mismatch.length +
                        result.duplicates.length}{" "}
                      total discrepancy items
                    </span>
                  </div>
                  <input
                    type="text"
                    placeholder="Review session notes or instructions for Ops Coordinators..."
                    value={sessionNotes}
                    onChange={(e) => setSessionNotes(e.target.value)}
                    className="w-full h-9 rounded-lg border border-border-subtle bg-surface px-3 text-xs text-text-primary focus:outline-hidden"
                  />
                  <div className="flex justify-end gap-2">
                    <button
                      onClick={() => setIsSendingToOps(false)}
                      className="px-3 py-1.5 rounded-lg border border-border-subtle bg-surface text-xs font-medium text-text-secondary"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleCreateReviewSession}
                      disabled={isSubmittingSession}
                      className="px-4 py-1.5 rounded-lg bg-purple-600 hover:bg-purple-700 text-white text-xs font-semibold flex items-center gap-1.5 disabled:opacity-50"
                    >
                      {isSubmittingSession ? (
                        <>
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                          Publishing...
                        </>
                      ) : (
                        "Create Review Session"
                      )}
                    </button>
                  </div>
                </div>
              )}

              {/* Finding Tabs */}
              <div className="flex items-center gap-1 overflow-x-auto border-b border-border-subtle pb-2 no-scrollbar">
                {(
                  [
                    { key: "missingInPayroll", label: "Missing in Payroll", count: result.missingInPayroll.length, color: "text-amber-700" },
                    { key: "missingInPlantilla", label: "Missing in Plantilla", count: result.missingInPlantilla.length, color: "text-rose-700" },
                    { key: "paidInactive", label: "Paid Inactive", count: result.paidInactive.length, color: "text-rose-700" },
                    { key: "mismatch", label: "Mismatch", count: result.mismatch.length, color: "text-amber-700" },
                    { key: "duplicates", label: "Duplicates", count: result.duplicates.length, color: "text-rose-700" },
                    { key: "clean", label: "Clean Verified", count: result.clean.length, color: "text-emerald-700" },
                  ] as const
                ).map((tab) => (
                  <button
                    key={tab.key}
                    onClick={() => setActiveTab(tab.key)}
                    className={`flex items-center gap-1.5 py-1.5 px-3 rounded-lg text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                      activeTab === tab.key
                        ? "bg-purple-100 text-purple-900 border border-purple-200"
                        : "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
                    }`}
                  >
                    <span>{tab.label}</span>
                    <span
                      className={`font-mono text-3xs font-bold rounded-full px-1.5 py-0.2 ${
                        tab.count > 0 ? "bg-white/80 " + tab.color : "bg-slate-100 text-slate-500"
                      }`}
                    >
                      {tab.count}
                    </span>
                  </button>
                ))}
              </div>

              {/* Findings Table */}
              <div className="rounded-xl border border-border-subtle overflow-hidden max-h-72 overflow-y-auto">
                {currentFindings.length === 0 ? (
                  <div className="p-8 text-center text-xs text-text-muted">
                    No records found in this reconciliation category.
                  </div>
                ) : (
                  <table className="w-full text-left text-xs">
                    <thead className="bg-surface-subtle border-b border-border-subtle sticky top-0 text-2xs uppercase text-text-muted font-bold">
                      <tr>
                        <th className="py-2 px-3">Emp No</th>
                        <th className="py-2 px-3">Payroll Name</th>
                        <th className="py-2 px-3">Plantilla Name</th>
                        <th className="py-2 px-3">Payroll Scope</th>
                        <th className="py-2 px-3">Plantilla Scope</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {currentFindings.map((f, i) => (
                        <tr key={i} className="hover:bg-surface-hover/50">
                          <td className="py-2 px-3 font-mono font-semibold text-purple-700">
                            {f.employeeNumber}
                          </td>
                          <td className="py-2 px-3 font-medium text-text-primary">
                            {f.payrollFullName || "—"}
                          </td>
                          <td className="py-2 px-3 font-medium text-text-primary">
                            {f.plantillaFullName || "—"}
                          </td>
                          <td className="py-2 px-3 text-text-secondary">
                            {f.payrollAccountGroup || "—"}
                          </td>
                          <td className="py-2 px-3 text-text-secondary">
                            {f.plantillaAccountGroup || "—"}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border-subtle px-6 py-3 bg-surface-subtle">
          <p className="text-2xs text-text-muted">
            OHM2026_0071 Parity: Pure read-only payroll checker with automated variance detection.
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
