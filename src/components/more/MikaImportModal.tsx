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
  downloadMikaImportTemplate,
  parseSpreadsheetToRows,
} from "@/lib/utils/data_control_xlsx";
import {
  approveMikaImport,
  MikaEmployeeRow,
  rejectMikaImport,
  submitMikaImport,
  useMikaImportLogs,
  useMikaImportRowsQuery,
} from "@/lib/queries/dataControl";
import { createClient } from "@/lib/supabase/client";

export interface MikaImportModalProps {
  isOpen: boolean;
  onClose: () => void;
}

type TabType = "upload" | "review" | "history";

export function MikaImportModal({ isOpen, onClose }: MikaImportModalProps) {
  const currentUser = useCurrentUser();
  const [activeTab, setActiveTab] = useState<TabType>("upload");

  // Selection & staging
  const [file, setFile] = useState<File | null>(null);
  const [stagedRows, setStagedRows] = useState<MikaEmployeeRow[]>([]);
  const [parseError, setParseError] = useState<string | null>(null);
  const [isParsing, setIsParsing] = useState(false);
  const [isCrossChecking, setIsCrossChecking] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitSuccess, setSubmitSuccess] = useState<string | null>(null);

  // Review detail & action
  const [selectedLogId, setSelectedLogId] = useState<string | null>(null);
  const [actionRemarks, setActionRemarks] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [isActionPending, setIsActionPending] = useState(false);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const { data: pendingLogs = [], refetch: refetchPending, isLoading: isLoadingPending } = useMikaImportLogs("pending");
  const { data: historyLogs = [], isLoading: isLoadingHistory } = useMikaImportLogs("history");
  const { data: inspectRows = [], isLoading: isLoadingInspectRows } = useMikaImportRowsQuery(selectedLogId);

  const canApprove = useMemo(() => {
    const role = (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
    return role.includes("super_admin") || role.includes("head_admin") || role === "sa" || role === "ha";
  }, [currentUser]);

  if (!isOpen) return null;

  // Split Name Helper
  const splitFullName = (fullName: string) => {
    const clean = fullName.trim();
    const parts = clean.split(",");
    if (parts.length >= 2) {
      return {
        lastName: parts[0].trim(),
        firstName: parts[1].trim(),
        middleName: parts.length > 2 ? parts.slice(2).join(",").trim() : "",
      };
    }
    const spaceParts = clean.split(" ");
    if (spaceParts.length >= 2) {
      return {
        lastName: spaceParts[spaceParts.length - 1].trim(),
        firstName: spaceParts.slice(0, spaceParts.length - 1).join(" ").trim(),
        middleName: "",
      };
    }
    return { lastName: clean, firstName: "", middleName: "" };
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

      // Check required columns
      const hasEmpNo =
        upperHeaders.has("EMPLOYEE NO.") ||
        upperHeaders.has("EMPLOYEE NO") ||
        upperHeaders.has("EMPLOYEE_NO") ||
        upperHeaders.has("EMPLOYEE NUMBER") ||
        upperHeaders.has("EMPLOYEE ID");
      const hasFullName = upperHeaders.has("FULLNAME") || upperHeaders.has("FULL_NAME") || upperHeaders.has("FULL NAME");
      const hasSplitName = upperHeaders.has("LAST_NAME") && upperHeaders.has("FIRST_NAME");
      const hasAccount = upperHeaders.has("ACCOUNT") || upperHeaders.has("ACCOUNT_NAME");

      if (!hasEmpNo || (!hasFullName && !hasSplitName) || !hasAccount) {
        throw new Error("Missing required columns: Employee No., Fullname (or Last/First), and Account.");
      }

      // Convert rows
      const converted: MikaEmployeeRow[] = rows.map((r) => {
        const empNo = r["Employee No."] || r["EMPLOYEE NO."] || r["EMPLOYEE_NO"] || r["Employee Number"] || r["Employee ID"] || "";
        const rawName = r["Fullname"] || r["FULLNAME"] || r["Full Name"] || "";
        const nameParts = rawName ? splitFullName(rawName) : { lastName: r["Last Name"] || r["LAST_NAME"] || "", firstName: r["First Name"] || r["FIRST_NAME"] || "", middleName: r["Middle Name"] || r["MIDDLE_NAME"] || "" };
        const acct = r["Account"] || r["ACCOUNT"] || r["ACCOUNT_NAME"] || "";

        return {
          employeeNo: empNo.trim(),
          account: acct.trim(),
          lastName: nameParts.lastName,
          firstName: nameParts.firstName,
          middleName: nameParts.middleName || undefined,
          position: r["Position"] || r["POSITION"] || undefined,
          contactNumber: r["Contact No."] || r["CONTACT_NO"] || r["CONTACT"] || undefined,
          address: r["Address"] || r["ADDRESS"] || undefined,
          sssNo: r["SSS"] || r["SSS_NO"] || undefined,
          philhealthNo: r["PhilHealth"] || r["PHILHEALTH"] || undefined,
          pagibigNo: r["Pag-IBIG"] || r["PAGIBIG"] || undefined,
          tinNo: r["TIN"] || r["TIN_NO"] || undefined,
          atmNo: r["ATM No."] || r["ATM_NO"] || undefined,
          birthdate: r["Birth Date"] || r["BIRTHDATE"] || undefined,
          civilStatus: r["Civil Status"] || r["CIVIL_STATUS"] || undefined,
          dateHired: r["Date Hired"] || r["DATE_HIRED"] || undefined,
          flagType: "clean",
        };
      });

      setStagedRows(converted);
      setIsParsing(false);

      // Perform cross-check with active plantilla
      setIsCrossChecking(true);
      const supabase = createClient();
      const empNos = converted.map((r) => r.employeeNo).filter(Boolean);
      const { data: plantilla } = await supabase
        .from("plantilla")
        .select("employee_no, account, is_active")
        .in("employee_no", empNos.slice(0, 500));

      const plantillaMap = new Map<string, { account: string; is_active: boolean }>();
      (plantilla ?? []).forEach((p) => {
        if (p.employee_no) {
          plantillaMap.set(String(p.employee_no).trim().toUpperCase(), {
            account: String(p.account ?? "").trim().toUpperCase(),
            is_active: p.is_active === true,
          });
        }
      });

      const evaluated = converted.map((row) => {
        const key = row.employeeNo.trim().toUpperCase();
        const match = plantillaMap.get(key);
        if (!match) {
          return { ...row, flagType: "ghost" as const, flagReason: "Possible Ghost Employee (No Plantilla match)" };
        }
        if (row.account.toUpperCase() !== match.account) {
          return {
            ...row,
            flagType: "blocked" as const,
            flagReason: `Account mismatch: MIKA has "${row.account}", Plantilla has "${match.account}"`,
          };
        }
        return { ...row, flagType: "matched" as const };
      });

      setStagedRows(evaluated);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : "Failed to parse MIKA spreadsheet.");
      setStagedRows([]);
    } finally {
      setIsParsing(false);
      setIsCrossChecking(false);
    }
  };

  const handleSubmit = async () => {
    if (stagedRows.length === 0 || !file) {
      setParseError("Please select a valid MIKA spreadsheet.");
      return;
    }

    setIsSubmitting(true);
    setParseError(null);
    try {
      const logId = await submitMikaImport({
        uploadedBy: currentUser?.displayName || currentUser?.email || "Super Admin",
        uploadedByRole: currentUser?.roleKey || "super_admin",
        fileName: file.name,
        rows: stagedRows,
      });

      setSubmitSuccess(`MIKA import log #${logId.slice(0, 8)} submitted for approval.`);
      setFile(null);
      setStagedRows([]);
      if (fileInputRef.current) fileInputRef.current.value = "";
      refetchPending();
      setActiveTab("review");
      setSelectedLogId(logId);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : "Failed to submit MIKA import log.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleApproveLog = async (logId: string, cleanCount: number) => {
    setIsActionPending(true);
    setActionError(null);
    try {
      await approveMikaImport({
        importLogId: logId,
        approvedBy: currentUser?.displayName || currentUser?.email || "Super Admin",
        remarks: actionRemarks.trim() || undefined,
        cleanRowsCount: cleanCount,
      });
      refetchPending();
      setSelectedLogId(null);
      setActionRemarks("");
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to approve MIKA import log.");
    } finally {
      setIsActionPending(false);
    }
  };

  const handleRejectLog = async (logId: string) => {
    setIsActionPending(true);
    setActionError(null);
    try {
      await rejectMikaImport({
        importLogId: logId,
        rejectedBy: currentUser?.displayName || currentUser?.email || "Super Admin",
        remarks: actionRemarks.trim() || undefined,
      });
      refetchPending();
      setSelectedLogId(null);
      setActionRemarks("");
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Failed to reject MIKA import log.");
    } finally {
      setIsActionPending(false);
    }
  };

  const ghostCount = stagedRows.filter((r) => r.flagType === "ghost").length;
  const blockedCount = stagedRows.filter((r) => r.flagType === "blocked").length;
  const matchedCount = stagedRows.filter((r) => r.flagType === "matched").length;

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
                <h2 className="text-base font-bold text-text-primary">Import MIKA</h2>
                <span className="rounded-md bg-purple-100 text-purple-800 px-2 py-0.5 text-3xs font-bold uppercase tracking-wider">
                  BIOMETRIC & ATTENDANCE
                </span>
              </div>
              <p className="text-xs text-text-secondary">
                Upload MIKA biometric and store activity sheets with ghost employee cross-check detection.
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
            {pendingLogs.length > 0 && (
              <span className="rounded-full bg-purple-100 text-purple-700 font-bold px-1.5 py-0.2 text-3xs">
                {pendingLogs.length}
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

              <div className="flex justify-end">
                <button
                  onClick={downloadMikaImportTemplate}
                  className="h-9 inline-flex items-center justify-center gap-2 rounded-lg border border-border-subtle bg-surface hover:bg-surface-hover text-text-primary text-xs font-semibold px-4 transition"
                >
                  <Download className="h-4 w-4 text-purple-600" />
                  Download MIKA Template
                </button>
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
                  {file ? file.name : "Click or drag & drop MIKA Attendance XLSX or CSV file here"}
                </p>
                <p className="text-xs text-text-muted mt-1">
                  Automatic cross-check against active Plantilla slots flags potential ghost employees.
                </p>
                {(isParsing || isCrossChecking) && (
                  <div className="flex items-center gap-2 mt-3 text-xs text-purple-700">
                    <Loader2 className="h-4 w-4 animate-spin" />
                    {isParsing ? "Reading spreadsheet..." : "Cross-checking against active Plantilla..."}
                  </div>
                )}
              </div>

              {/* Staged Summary Badges */}
              {stagedRows.length > 0 && (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                    <div className="rounded-xl border border-border-subtle bg-surface p-3 text-center">
                      <p className="text-2xs uppercase font-bold text-text-muted">Total Rows</p>
                      <p className="text-lg font-bold text-text-primary">{stagedRows.length}</p>
                    </div>
                    <div className="rounded-xl border border-emerald-200 bg-emerald-50/50 p-3 text-center">
                      <p className="text-2xs uppercase font-bold text-emerald-700">Matched Clean</p>
                      <p className="text-lg font-bold text-emerald-800">{matchedCount}</p>
                    </div>
                    <div className="rounded-xl border border-amber-200 bg-amber-50/50 p-3 text-center">
                      <p className="text-2xs uppercase font-bold text-amber-700">Possible Ghost</p>
                      <p className="text-lg font-bold text-amber-800">{ghostCount}</p>
                    </div>
                    <div className="rounded-xl border border-rose-200 bg-rose-50/50 p-3 text-center">
                      <p className="text-2xs uppercase font-bold text-rose-700">Blocked (Mismatch)</p>
                      <p className="text-lg font-bold text-rose-800">{blockedCount}</p>
                    </div>
                  </div>

                  <div className="rounded-xl border border-border-subtle overflow-hidden max-h-60 overflow-y-auto">
                    <table className="w-full text-left text-xs">
                      <thead className="bg-surface-subtle border-b border-border-subtle sticky top-0 text-2xs uppercase text-text-muted font-bold">
                        <tr>
                          <th className="py-2 px-3">#</th>
                          <th className="py-2 px-3">Flag</th>
                          <th className="py-2 px-3">Emp No</th>
                          <th className="py-2 px-3">Fullname</th>
                          <th className="py-2 px-3">Account</th>
                          <th className="py-2 px-3">Reason / Details</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-border-subtle">
                        {stagedRows.slice(0, 10).map((row, idx) => (
                          <tr key={idx} className="hover:bg-surface-hover/50">
                            <td className="py-2 px-3 text-text-muted">{idx + 1}</td>
                            <td className="py-2 px-3">
                              <span
                                className={`rounded-md px-1.5 py-0.5 text-3xs font-bold uppercase ${
                                  row.flagType === "matched"
                                    ? "bg-emerald-100 text-emerald-800"
                                    : row.flagType === "ghost"
                                    ? "bg-amber-100 text-amber-800"
                                    : "bg-rose-100 text-rose-800"
                                }`}
                              >
                                {row.flagType}
                              </span>
                            </td>
                            <td className="py-2 px-3 font-mono text-purple-700 font-semibold">{row.employeeNo}</td>
                            <td className="py-2 px-3 font-medium text-text-primary">
                              {[row.lastName, row.firstName, row.middleName].filter(Boolean).join(", ")}
                            </td>
                            <td className="py-2 px-3 text-text-secondary">{row.account}</td>
                            <td className="py-2 px-3 text-text-secondary">{row.flagReason || "Verified match"}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>

                  <div className="flex justify-end pt-2">
                    <button
                      onClick={handleSubmit}
                      disabled={isSubmitting}
                      className="inline-flex items-center gap-2 rounded-xl bg-purple-600 hover:bg-purple-700 text-white font-semibold text-xs px-5 py-2.5 transition disabled:opacity-50"
                    >
                      {isSubmitting ? (
                        <>
                          <Loader2 className="h-4 w-4 animate-spin" />
                          Submitting MIKA Import...
                        </>
                      ) : (
                        <>
                          <Send className="h-4 w-4" />
                          Submit Import Log for Approval
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
                  Pending MIKA attendance batches awaiting administrative sign-off.
                </p>
                <button
                  onClick={() => refetchPending()}
                  className="inline-flex items-center gap-1.5 text-xs text-text-muted hover:text-text-primary transition"
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                  Refresh
                </button>
              </div>

              {isLoadingPending ? (
                <div className="flex justify-center p-8 text-xs text-text-muted">
                  <Loader2 className="h-5 w-5 animate-spin mr-2" /> Loading pending logs...
                </div>
              ) : pendingLogs.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border-subtle p-8 text-center text-xs text-text-muted">
                  No pending MIKA imports waiting for review.
                </div>
              ) : (
                <div className="space-y-3">
                  {pendingLogs.map((log) => (
                    <div
                      key={log.id}
                      className="rounded-xl border border-border-subtle bg-surface p-4 flex flex-col md:flex-row items-start md:items-center justify-between gap-4"
                    >
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-xs text-text-primary">{log.fileName}</span>
                          <span className="rounded-md bg-amber-100 text-amber-800 text-3xs font-bold px-2 py-0.5">
                            PENDING
                          </span>
                        </div>
                        <div className="text-2xs text-text-muted flex flex-wrap gap-x-3 gap-y-1">
                          <span>Log #{log.id.slice(0, 8)}</span>
                          <span>Uploaded by: {log.uploadedBy}</span>
                          <span>Total: {log.totalRows}</span>
                          <span className="text-emerald-700 font-semibold">Matched: {log.matchedCount}</span>
                          {log.ghostCount > 0 && (
                            <span className="text-amber-700 font-semibold">Ghost: {log.ghostCount}</span>
                          )}
                        </div>
                      </div>

                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => setSelectedLogId(selectedLogId === log.id ? null : log.id)}
                          className="h-8 px-3 rounded-lg border border-border-subtle text-xs font-semibold text-text-secondary hover:text-text-primary hover:bg-surface-hover transition"
                        >
                          {selectedLogId === log.id ? "Hide Rows" : "Inspect Rows"}
                        </button>

                        {canApprove && (
                          <div className="flex items-center gap-2">
                            <button
                              onClick={() => handleApproveLog(log.id, log.cleanRows)}
                              disabled={isActionPending}
                              className="h-8 px-3 rounded-lg bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold transition disabled:opacity-50"
                            >
                              Approve
                            </button>
                            <button
                              onClick={() => handleRejectLog(log.id)}
                              disabled={isActionPending}
                              className="h-8 px-3 rounded-lg bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 text-xs font-semibold transition disabled:opacity-50"
                            >
                              Reject
                            </button>
                          </div>
                        )}
                      </div>
                    </div>
                  ))}

                  {/* Rows Drawer */}
                  {selectedLogId && (
                    <div className="rounded-xl border border-purple-200 bg-purple-50/20 p-4 space-y-3">
                      <div className="flex items-center justify-between">
                        <h4 className="text-xs font-bold text-text-primary">
                          Inspect MIKA Import Rows (#{selectedLogId.slice(0, 8)})
                        </h4>
                        <span className="text-2xs text-text-muted">{inspectRows.length} rows</span>
                      </div>

                      {isLoadingInspectRows ? (
                        <div className="flex justify-center p-6 text-xs text-text-muted">
                          <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading rows...
                        </div>
                      ) : (
                        <div className="rounded-lg border border-border-subtle bg-surface overflow-x-auto max-h-56">
                          <table className="w-full text-left text-xs">
                            <thead className="bg-surface-subtle border-b border-border-subtle sticky top-0 text-2xs uppercase text-text-muted font-bold">
                              <tr>
                                <th className="py-2 px-3">Emp No</th>
                                <th className="py-2 px-3">Name</th>
                                <th className="py-2 px-3">Account</th>
                                <th className="py-2 px-3">Status</th>
                                <th className="py-2 px-3">Remarks</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-border-subtle">
                              {inspectRows.map((r, i) => (
                                <tr key={i}>
                                  <td className="py-1.5 px-3 font-mono font-semibold">{r.employeeNo}</td>
                                  <td className="py-1.5 px-3">{[r.lastName, r.firstName].filter(Boolean).join(", ")}</td>
                                  <td className="py-1.5 px-3 text-text-secondary">{r.account}</td>
                                  <td className="py-1.5 px-3">
                                    <span className="rounded-md bg-slate-100 text-slate-800 text-3xs font-bold px-1.5 py-0.5 uppercase">
                                      {r.flagType}
                                    </span>
                                  </td>
                                  <td className="py-1.5 px-3 text-text-muted">{r.flagReason || "—"}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
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
              {isLoadingHistory ? (
                <div className="flex justify-center p-8 text-xs text-text-muted">
                  <Loader2 className="h-5 w-5 animate-spin mr-2" /> Loading history...
                </div>
              ) : historyLogs.length === 0 ? (
                <div className="rounded-xl border border-dashed border-border-subtle p-8 text-center text-xs text-text-muted">
                  No historical MIKA import logs recorded.
                </div>
              ) : (
                <div className="rounded-xl border border-border-subtle bg-surface overflow-hidden">
                  <table className="w-full text-left text-xs">
                    <thead className="bg-surface-subtle border-b border-border-subtle text-2xs uppercase text-text-muted font-bold">
                      <tr>
                        <th className="py-2.5 px-4">File Name</th>
                        <th className="py-2.5 px-4">Status</th>
                        <th className="py-2.5 px-4">Uploaded By</th>
                        <th className="py-2.5 px-4">Approved By</th>
                        <th className="py-2.5 px-4">Date</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border-subtle">
                      {historyLogs.map((l) => (
                        <tr key={l.id} className="hover:bg-surface-hover/50">
                          <td className="py-2.5 px-4 font-semibold text-text-primary">{l.fileName}</td>
                          <td className="py-2.5 px-4">
                            <span
                              className={`rounded-md px-2 py-0.5 text-3xs font-bold uppercase ${
                                l.status.toLowerCase() === "rejected"
                                  ? "bg-rose-100 text-rose-800 border border-rose-200"
                                  : l.status.toLowerCase() === "approved"
                                  ? "bg-emerald-100 text-emerald-800"
                                  : "bg-amber-100 text-amber-800"
                              }`}
                            >
                              {l.status}
                            </span>
                          </td>
                          <td className="py-2.5 px-4 text-text-secondary">{l.uploadedBy}</td>
                          <td className="py-2.5 px-4 text-text-secondary">{l.approvedBy || "—"}</td>
                          <td className="py-2.5 px-4 text-text-muted">
                            {new Date(l.submittedAt).toLocaleDateString()}
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
            Full Mobile MIKA Biometric Parity with Ghost Case Isolation and Checker Security.
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
