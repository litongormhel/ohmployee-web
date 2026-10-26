"use client";

import React, { useRef, useState } from "react";
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  Download,
  FileSpreadsheet,
  Info,
  Loader2,
  Send,
  UploadCloud,
  X,
} from "lucide-react";
import {
  type HrEmplocImportGroup,
  useImportGroups,
  useSubmitImportBatch,
} from "@/lib/queries/hr_emploc_import";
import {
  buildParsePreview,
  downloadHrEmplocTemplate,
  type HrEmplocParsePreview,
  xlsxToHrEmplocRows,
} from "@/lib/utils/hr_emploc_xlsx";

interface UploadTabProps {
  onSuccess: () => void;
}

export function UploadTab({ onSuccess }: UploadTabProps) {
  const [selectedGroup, setSelectedGroup] = useState<HrEmplocImportGroup | null>(
    null,
  );
  const [fileName, setFileName] = useState<string | null>(null);
  const [rawRows, setRawRows] = useState<Record<string, string>[]>([]);
  const [parseError, setParseError] = useState<string | null>(null);
  const [preview, setPreview] = useState<HrEmplocParsePreview | null>(null);
  const [isDragOver, setIsDragOver] = useState(false);
  const [search, setSearch] = useState("");
  const [filterMode, setFilterMode] = useState<"all" | "valid" | "blocked">("all");
  const [submissionError, setSubmissionError] = useState<string | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const { data: groups = [], isLoading: isLoadingGroups, error: groupsError } =
    useImportGroups();
  const submitMutation = useSubmitImportBatch();

  function handleGroupChange(groupId: string) {
    const found = groups.find((g) => g.id === groupId) || null;
    setSelectedGroup(found);
    if (rawRows.length > 0 && found) {
      setPreview(buildParsePreview(rawRows, found.groupName));
    }
  }

  async function processFile(file: File) {
    if (!file.name.endsWith(".xlsx")) {
      setParseError("Only .xlsx Excel files are supported. Please download and use the official template.");
      return;
    }

    setParseError(null);
    setSubmissionError(null);

    try {
      const buffer = await file.arrayBuffer();
      const parsed = xlsxToHrEmplocRows(buffer);

      if (parsed.length === 0) {
        setParseError(
          "Could not parse any rows from this file. Ensure it contains the 'IMPORT_TEMPLATE' sheet or standard columns.",
        );
        setRawRows([]);
        setPreview(null);
        setFileName(file.name);
        return;
      }

      setFileName(file.name);
      setRawRows(parsed);

      if (selectedGroup) {
        setPreview(buildParsePreview(parsed, selectedGroup.groupName));
      }
    } catch (err: unknown) {
      setParseError(
        err instanceof Error ? err.message : "Failed to read the XLSX file",
      );
    }
  }

  function handleFileDrop(e: React.DragEvent) {
    e.preventDefault();
    setIsDragOver(false);
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      void processFile(e.dataTransfer.files[0]);
    }
  }

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    if (e.target.files && e.target.files.length > 0) {
      void processFile(e.target.files[0]);
    }
  }

  function resetFile() {
    setFileName(null);
    setRawRows([]);
    setPreview(null);
    setParseError(null);
    setSubmissionError(null);
    if (fileInputRef.current) {
      fileInputRef.current.value = "";
    }
  }

  async function handleSubmit() {
    if (!selectedGroup || !fileName || !preview || !preview.hasSubmittableRows) {
      return;
    }

    setSubmissionError(null);

    try {
      await submitMutation.mutateAsync({
        groupId: selectedGroup.id,
        filename: fileName,
        rows: preview.submittableRows,
      });

      resetFile();
      onSuccess();
    } catch (err: unknown) {
      setSubmissionError(
        err instanceof Error ? err.message : "Failed to submit import batch",
      );
    }
  }

  const canSubmit =
    Boolean(selectedGroup) &&
    Boolean(fileName) &&
    Boolean(preview?.hasSubmittableRows) &&
    !submitMutation.isPending;

  const displayedRows = (preview?.previews || []).filter((p) => {
    if (filterMode === "valid" && !p.passedBasicCheck) return false;
    if (filterMode === "blocked" && p.passedBasicCheck) return false;
    if (search.trim()) {
      const q = search.toLowerCase();
      const matchName =
        p.firstName.toLowerCase().includes(q) ||
        p.lastName.toLowerCase().includes(q);
      const matchVcode = p.vcode.toLowerCase().includes(q);
      const matchAccount = p.accountName.toLowerCase().includes(q);
      return matchName || matchVcode || matchAccount;
    }
    return true;
  });

  return (
    <div className="space-y-6 text-xs">
      {/* Information Guideline Banner */}
      <div className="rounded-xl border border-border-default bg-surface-muted/50 p-4.5">
        <div className="flex items-start gap-3">
          <Info className="h-5 w-5 text-brand-primary mt-0.5 shrink-0" />
          <div className="space-y-1 text-xs text-text-primary leading-relaxed">
            <h3 className="font-bold text-sm text-text-primary">
              Bulk HR Emploc Import & Slot Reconciliation
            </h3>
            <p className="text-text-muted">
              Download the official template, fill in employee placement rows, select the target operational group, and upload.
              Under <strong className="font-semibold text-text-primary">ADR-001 (Slot-First Architecture)</strong>, store, position, and employment type are derived directly from the authoritative Plantilla slot identified by the VCode.
            </p>
            <p className="text-text-muted">
              • For employees without a middle name, use <code className="bg-surface px-1 py-0.5 rounded border border-border-subtle font-mono font-bold text-text-primary">NA</code> (not &apos;N/A&apos; or initials).
              <br />
              • All rows in a single file must belong to one operational group.
              <br />
              • Valid rows reserve slots in <code className="bg-surface px-1 py-0.5 rounded border border-border-subtle font-mono font-bold text-text-primary">hr_processing</code> status pending Head Admin or Super Admin review.
            </p>
          </div>
        </div>
      </div>

      {/* Submission error banner */}
      {submissionError && (
        <div className="rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-4 text-xs text-[var(--danger-text)] flex items-start gap-2.5">
          <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="font-semibold">Import Submission Blocked</p>
            <p className="mt-0.5">{submissionError}</p>
          </div>
        </div>
      )}

      {/* Control Card: Group Selection & Template Download CTA */}
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        {/* Step 1: Target Operational Group */}
        <div className="rounded-xl border border-border-default bg-surface p-5 shadow-xs">
          <label className="block text-xs font-bold text-text-primary mb-1.5">
            1. Select Target CENCOM Group *
          </label>
          <p className="text-xs text-text-muted mb-3">
            Choose the operational group to reconcile slots and accounts against.
          </p>

          {isLoadingGroups ? (
            <div className="flex h-10 items-center gap-2 text-xs text-text-muted">
              <Loader2 className="h-4 w-4 animate-spin text-brand-primary" />
              <span>Loading operational groups...</span>
            </div>
          ) : groupsError ? (
            <div className="rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] p-2.5 text-xs text-[var(--danger-text)]">
              {(groupsError as Error).message}
            </div>
          ) : (
            <select
              className="w-full rounded-lg border border-border-default bg-surface px-3 py-2 text-xs font-semibold text-text-primary shadow-2xs focus:border-brand-primary focus:outline-hidden focus:ring-1 focus:ring-brand-primary"
              onChange={(e) => handleGroupChange(e.target.value)}
              value={selectedGroup?.id ?? ""}
            >
              <option value="">— Select an Operational Group —</option>
              {groups.map((group) => (
                <option key={group.id} value={group.id}>
                  {group.groupName}
                </option>
              ))}
            </select>
          )}

          {selectedGroup && (
            <div className="mt-2.5 flex items-center gap-1.5 text-xs text-text-primary font-medium">
              <CheckCircle2 className="h-3.5 w-3.5 text-text-muted" />
              <span>Active scope: {selectedGroup.groupName}</span>
            </div>
          )}
        </div>

        {/* Step 2: Download Official Template */}
        <div className="rounded-xl border border-border-default bg-surface p-5 shadow-xs flex flex-col justify-between">
          <div>
            <label className="block text-xs font-bold text-text-primary mb-1.5">
              2. Download Standard Template
            </label>
            <p className="text-xs text-text-muted mb-3">
              Generate the pre-formatted Excel template with required columns and validation rules.
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-2 pt-2">
            <button
              className="inline-flex items-center gap-2 rounded-lg border border-border-default bg-surface px-3.5 py-2 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
              onClick={() => downloadHrEmplocTemplate("v3")}
              type="button"
            >
              <Download className="h-4 w-4 text-text-muted" />
              Download XLSX Template (v3 ADR-001)
            </button>
            <button
              className="inline-flex items-center gap-2 rounded-lg border border-border-subtle bg-surface-muted px-3 py-2 text-xs font-medium text-text-muted hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
              onClick={() => downloadHrEmplocTemplate("standard")}
              title="Download template with Store / Position / Employee No columns"
              type="button"
            >
              Standard 7-Col
            </button>
          </div>
        </div>
      </div>

      {/* Step 3: Drag & Drop Dropzone */}
      <div className="rounded-xl border border-border-default bg-surface p-5 shadow-xs">
        <label className="block text-xs font-bold text-text-primary mb-1.5">
          3. Upload XLSX File *
        </label>
        <p className="text-xs text-text-muted mb-3">
          Drag and drop your populated spreadsheet here, or click to browse.
        </p>

        {!selectedGroup && (
          <div className="mb-3 rounded-lg border border-border-default bg-surface-muted p-3 text-xs text-text-primary flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 shrink-0 text-text-muted" />
            <span>Please select a Target Group above before parsing your file.</span>
          </div>
        )}

        <div
          className={`relative flex flex-col items-center justify-center rounded-xl border-2 border-dashed p-8 transition cursor-pointer ${
            !selectedGroup
              ? "border-border-default bg-surface-muted/50 cursor-not-allowed opacity-60"
              : isDragOver
              ? "border-brand-primary bg-surface-muted"
              : "border-border-default hover:border-border-strong bg-surface"
          }`}
          onClick={() => {
            if (selectedGroup) fileInputRef.current?.click();
          }}
          onDragLeave={() => setIsDragOver(false)}
          onDragOver={(e) => {
            e.preventDefault();
            if (selectedGroup) setIsDragOver(true);
          }}
          onDrop={selectedGroup ? handleFileDrop : undefined}
        >
          <input
            ref={fileInputRef}
            accept=".xlsx"
            className="hidden"
            disabled={!selectedGroup}
            onChange={handleFileSelect}
            type="file"
          />

          <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-muted text-brand-primary mb-3 border border-border-subtle">
            <UploadCloud className="h-6 w-6" />
          </div>

          <p className="text-sm font-semibold text-text-primary">
            {isDragOver ? "Drop file to upload" : "Click to browse or drag file here"}
          </p>
          <p className="mt-1 text-xs text-text-muted">
            Supports Microsoft Excel (.xlsx) files up to 10 MB
          </p>
        </div>

        {parseError && (
          <div className="mt-3 rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] flex items-center justify-between">
            <span>{parseError}</span>
            <button
              className="text-[var(--danger-text)] hover:opacity-80 cursor-pointer"
              onClick={() => setParseError(null)}
              type="button"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        )}
      </div>

      {/* Step 4: Parsed Preview & Client Validation Table */}
      {preview && fileName && (
        <div className="rounded-xl border border-border-default bg-surface p-5 shadow-xs space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between border-b border-border-subtle pb-4">
            <div className="flex items-center gap-3">
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-surface-muted text-brand-primary border border-border-subtle">
                <FileSpreadsheet className="h-5 w-5" />
              </div>
              <div>
                <h4 className="text-sm font-bold text-text-primary">{fileName}</h4>
                <p className="text-xs text-text-muted">
                  Target Group: <span className="font-semibold text-text-primary">{selectedGroup?.groupName}</span>
                </p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <span className="inline-flex items-center rounded-full bg-surface-muted border border-border-subtle px-2.5 py-1 text-xs font-semibold text-text-primary">
                {preview.totalRows} Total Rows
              </span>
              <span className="inline-flex items-center rounded-full bg-surface-muted border border-border-subtle px-2.5 py-1 text-xs font-semibold text-text-primary">
                {preview.clientValidRows} Ready
              </span>
              {preview.clientInvalidRows > 0 && (
                <span className="inline-flex items-center rounded-full bg-surface-muted border border-border-subtle px-2.5 py-1 text-xs font-semibold text-text-primary">
                  {preview.clientInvalidRows} Flagged
                </span>
              )}
              <button
                className="ml-2 text-xs font-semibold text-text-muted hover:text-text-primary cursor-pointer"
                onClick={resetFile}
                type="button"
              >
                Clear File
              </button>
            </div>
          </div>

          {/* Validation Notice */}
          {preview.clientInvalidRows > 0 && (
            <div className="rounded-lg border border-border-default bg-surface-muted p-3 text-xs text-text-primary">
              <p className="font-semibold">
                {preview.clientInvalidRows} row(s) contain validation errors.
              </p>
              <p className="mt-0.5 text-text-muted">
                You may still submit: only the {preview.clientValidRows} valid row(s) will be staged for review. Blocked rows will be automatically excluded.
              </p>
            </div>
          )}

          {/* Table Filters */}
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between pt-1">
            <div className="inline-flex rounded-lg border border-border-default bg-surface-muted p-0.5">
              <button
                className={`rounded-md px-3 py-1 text-xs font-semibold transition cursor-pointer ${
                  filterMode === "all"
                    ? "bg-surface text-text-primary shadow-2xs"
                    : "text-text-muted hover:text-text-primary"
                }`}
                onClick={() => setFilterMode("all")}
                type="button"
              >
                All ({preview.totalRows})
              </button>
              <button
                className={`rounded-md px-3 py-1 text-xs font-semibold transition cursor-pointer ${
                  filterMode === "valid"
                    ? "bg-surface text-text-primary shadow-2xs"
                    : "text-text-muted hover:text-text-primary"
                }`}
                onClick={() => setFilterMode("valid")}
                type="button"
              >
                Valid Only ({preview.clientValidRows})
              </button>
              <button
                className={`rounded-md px-3 py-1 text-xs font-semibold transition cursor-pointer ${
                  filterMode === "blocked"
                    ? "bg-surface text-text-primary shadow-2xs"
                    : "text-text-muted hover:text-text-primary"
                }`}
                onClick={() => setFilterMode("blocked")}
                type="button"
              >
                Flagged ({preview.clientInvalidRows})
              </button>
            </div>

            <input
              className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden"
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search parsed preview..."
              type="text"
              value={search}
            />
          </div>

          {/* Preview Table: 14px text floor */}
          <div className="max-h-72 overflow-y-auto rounded-lg border border-border-default shadow-2xs">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="sticky top-0 bg-surface-muted text-text-muted border-b border-border-default font-semibold text-xs z-10">
                <tr>
                  <th className="py-2.5 px-3">#</th>
                  <th className="py-2.5 px-3">Status</th>
                  <th className="py-2.5 px-3">Candidate Name</th>
                  <th className="py-2.5 px-3">VCode / Emp No</th>
                  <th className="py-2.5 px-3">Account</th>
                  <th className="py-2.5 px-3">Middle Name</th>
                  <th className="py-2.5 px-3">Date Hired</th>
                  <th className="py-2.5 px-3">Client Validation</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle bg-surface">
                {displayedRows.map((p) => {
                  const isValid = p.passedBasicCheck;
                  return (
                    <tr
                      key={p.rowNum}
                      className={isValid ? "hover:bg-surface-hover" : "bg-[var(--danger-bg)]/20 hover:bg-[var(--danger-bg)]/30"}
                    >
                      <td className="py-2 px-3 font-mono text-sm text-text-muted">{p.rowNum}</td>
                      <td className="py-2 px-3">
                        <span
                          className="inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-semibold border border-border-default bg-surface text-text-primary"
                        >
                          {isValid ? "READY" : "ERROR"}
                        </span>
                      </td>
                      <td className="py-2 px-3 font-semibold text-text-primary">
                        {p.firstName} {p.middleName !== "NA" ? p.middleName : ""} {p.lastName}
                      </td>
                      <td className="py-2 px-3 font-mono text-text-primary">{p.vcode || "—"}</td>
                      <td className="py-2 px-3 text-text-muted">{p.accountName || "—"}</td>
                      <td className="py-2 px-3 font-mono text-text-muted">{p.middleName}</td>
                      <td className="py-2 px-3 text-text-muted">{p.dateHired}</td>
                      <td className="py-2 px-3 max-w-xs text-sm">
                        {isValid ? (
                          <span className="text-text-muted">Passed basic checks</span>
                        ) : (
                          <div className="space-y-0.5">
                            {p.clientErrors.map((err, idx) => (
                              <p key={idx} className="text-[11px] text-[var(--danger-text)]">
                                • {err}
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

          {/* Submission CTA */}
          <div className="flex items-center justify-between pt-2 border-t border-border-subtle">
            <p className="text-xs text-text-muted">
              {preview.clientValidRows} out of {preview.totalRows} rows will be submitted for review.
            </p>

            <button
              className="inline-flex items-center gap-2 rounded-lg bg-brand-button px-5 py-2.5 text-xs font-semibold text-white shadow-xs hover:bg-brand-primary-hover transition disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
              disabled={!canSubmit}
              onClick={handleSubmit}
              type="button"
            >
              {submitMutation.isPending ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  <span>Submitting to Database...</span>
                </>
              ) : (
                <>
                  <Send className="h-4 w-4" />
                  <span>Submit {preview.clientValidRows} Valid Row(s) for Review</span>
                </>
              )}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
