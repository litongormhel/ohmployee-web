"use client";

import { useState } from "react";
import { Download, FileSpreadsheet, Loader2, ShieldAlert, X } from "lucide-react";
import { useDataIntegrityDetail } from "@/lib/queries/reports";
import { exportToCsv, exportToXlsx } from "@/lib/utils/reports_export";

interface DataIntegrityDetailModalProps {
  sectionKey: "late_hr" | "vacancy_delay" | "ghost_occupancy" | "pipeline_no_vacancy";
  sectionTitle: string;
  groupId?: string | null;
  accountId?: string | null;
  onClose: () => void;
}

export function DataIntegrityDetailModal({
  sectionKey,
  sectionTitle,
  groupId,
  accountId,
  onClose,
}: DataIntegrityDetailModalProps) {
  const [searchQuery, setSearchQuery] = useState("");

  const { data: rows = [], isLoading, error } = useDataIntegrityDetail(
    sectionKey,
    { groupId, accountId, slaDays: 7 }
  );

  const filteredRows = rows.filter((r) => {
    if (!searchQuery) return true;
    const q = searchQuery.toLowerCase();
    return (
      r.storeName.toLowerCase().includes(q) ||
      r.accountName.toLowerCase().includes(q) ||
      r.groupName.toLowerCase().includes(q) ||
      r.issueType.toLowerCase().includes(q) ||
      (r.employeeName && r.employeeName.toLowerCase().includes(q)) ||
      (r.applicantName && r.applicantName.toLowerCase().includes(q)) ||
      (r.position && r.position.toLowerCase().includes(q)) ||
      (r.vcode && r.vcode.toLowerCase().includes(q))
    );
  });

  const handleExportXlsx = () => {
    exportToXlsx(
      rows.map((r) => ({
        "Store Branch": r.storeName,
        Account: r.accountName,
        Group: r.groupName,
        "Issue Type": r.issueType,
        "Employee / Applicant": r.employeeName || r.applicantName || "—",
        Position: r.position || "—",
        VCode: r.vcode || "—",
        "Effective Date": r.effectiveDate ? r.effectiveDate.substring(0, 10) : "—",
        "Recorded / Detected Date": (r.recordedDate || r.detectedDate || "—").substring(0, 10),
        "Delay (Days)": r.daysImpacted ?? "—",
      })),
      `Data_Integrity_${sectionKey}`
    );
  };

  const handleExportCsv = () => {
    exportToCsv(
      rows.map((r) => ({
        "Store Branch": r.storeName,
        Account: r.accountName,
        Group: r.groupName,
        "Issue Type": r.issueType,
        "Employee / Applicant": r.employeeName || r.applicantName || "—",
        Position: r.position || "—",
        VCode: r.vcode || "—",
        "Effective Date": r.effectiveDate ? r.effectiveDate.substring(0, 10) : "—",
        "Recorded / Detected Date": (r.recordedDate || r.detectedDate || "—").substring(0, 10),
        "Delay (Days)": r.daysImpacted ?? "—",
      })),
      `Data_Integrity_${sectionKey}`
    );
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 backdrop-blur-xs p-4 animate-in fade-in duration-150">
      <div className="relative flex flex-col w-full max-w-4xl max-h-[90vh] bg-surface-base rounded-xl border border-border-default shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-border-subtle bg-surface-muted/40">
          <div>
            <div className="flex items-center gap-2">
              <span className="text-[10px] font-bold uppercase tracking-wider text-rose-700 bg-rose-50 px-2 py-0.5 rounded border border-rose-200">
                Workforce Data Audit
              </span>
            </div>
            <h2 className="text-lg font-bold text-text-primary mt-1 flex items-center gap-2">
              <ShieldAlert className="w-5 h-5 text-rose-600" />
              {sectionTitle} — Finding Details
            </h2>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-text-muted hover:text-text-primary hover:bg-surface-hover transition cursor-pointer"
            aria-label="Close modal"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Toolbar */}
        <div className="flex flex-wrap items-center justify-between gap-3 px-6 py-3 border-b border-border-subtle bg-surface-base">
          <span className="text-xs text-text-secondary font-medium">
            Showing {filteredRows.length} of {rows.length} anomaly findings
          </span>

          <div className="flex items-center gap-2 ml-auto">
            <input
              type="text"
              placeholder="Filter findings by store, employee, account..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="h-8 px-3 text-xs bg-surface-base border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 w-52 sm:w-72"
            />
            <button
              onClick={handleExportXlsx}
              disabled={isLoading || !rows.length}
              className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-medium text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 rounded-md transition cursor-pointer disabled:opacity-50"
              title="Export findings to XLSX"
            >
              <FileSpreadsheet className="w-3.5 h-3.5" />
              XLSX
            </button>
            <button
              onClick={handleExportCsv}
              disabled={isLoading || !rows.length}
              className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-medium text-text-secondary bg-surface-base hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer disabled:opacity-50"
              title="Export findings to CSV"
            >
              <Download className="w-3.5 h-3.5" />
              CSV
            </button>
          </div>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-6">
          {isLoading ? (
            <div className="flex flex-col items-center justify-center py-20 text-text-muted">
              <Loader2 className="w-8 h-8 animate-spin text-brand-600 mb-2" />
              <p className="text-xs font-medium">Auditing data integrity findings...</p>
            </div>
          ) : error ? (
            <div className="p-4 rounded-lg bg-rose-50 border border-rose-200 text-rose-800 text-sm">
              Failed to load data integrity findings. {String(error)}
            </div>
          ) : filteredRows.length === 0 ? (
            <div className="text-center py-16 text-text-muted text-xs">
              No anomalies found matching your search criteria.
            </div>
          ) : (
            <div className="overflow-x-auto border border-border-subtle rounded-lg">
              <table className="w-full text-left text-xs">
                <thead className="bg-surface-muted border-b border-border-subtle text-text-secondary uppercase text-[10px] tracking-wider font-semibold">
                  <tr>
                    <th className="py-2.5 px-3">Store Branch</th>
                    <th className="py-2.5 px-3">Account & Group</th>
                    <th className="py-2.5 px-3">Subject / Entity</th>
                    <th className="py-2.5 px-3">Issue Type</th>
                    <th className="py-2.5 px-3">Effective Date</th>
                    <th className="py-2.5 px-3 text-right">Delay / Impact</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle font-medium">
                  {filteredRows.map((r, idx) => (
                    <tr key={idx} className="hover:bg-surface-hover/50 transition">
                      <td className="py-2.5 px-3 font-semibold text-text-primary">
                        {r.storeName}
                      </td>
                      <td className="py-2.5 px-3">
                        <div className="text-text-primary font-medium">{r.accountName}</div>
                        <div className="text-[10px] text-text-muted">{r.groupName}</div>
                      </td>
                      <td className="py-2.5 px-3">
                        <div className="text-text-primary font-semibold">
                          {r.employeeName || r.applicantName || "—"}
                        </div>
                        {r.position && (
                          <div className="text-[10px] text-text-secondary">{r.position}</div>
                        )}
                        {r.vcode && (
                          <div className="text-[10px] font-mono text-brand-600">{r.vcode}</div>
                        )}
                      </td>
                      <td className="py-2.5 px-3">
                        <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-semibold bg-rose-50 text-rose-700 border border-rose-200">
                          {r.issueType}
                        </span>
                      </td>
                      <td className="py-2.5 px-3 font-mono text-[11px] text-text-secondary">
                        {r.effectiveDate ? r.effectiveDate.substring(0, 10) : r.detectedDate ? r.detectedDate.substring(0, 10) : "—"}
                      </td>
                      <td className="py-2.5 px-3 text-right">
                        {r.daysImpacted != null ? (
                          <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold bg-amber-50 text-amber-800 border border-amber-200">
                            {r.daysImpacted} days
                          </span>
                        ) : (
                          <span className="text-text-muted">—</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-3 border-t border-border-subtle bg-surface-muted/30 text-xs text-text-muted">
          <span>Total: {rows.length} data integrity findings detected</span>
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-xs font-semibold text-text-primary bg-surface-base hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer shadow-2xs"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
