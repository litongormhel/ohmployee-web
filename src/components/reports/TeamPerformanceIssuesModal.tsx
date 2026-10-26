"use client";

import { useState } from "react";
import { AlertCircle, Download, FileSpreadsheet, Loader2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useTeamPerformanceDetail } from "@/lib/queries/reports";
import { exportToCsv, exportToXlsx } from "@/lib/utils/reports_export";

interface TeamPerformanceIssuesModalProps {
  accountId: string;
  accountName: string;
  groupName: string;
  onClose: () => void;
}

export function TeamPerformanceIssuesModal({
  accountId,
  accountName,
  groupName,
  onClose,
}: TeamPerformanceIssuesModalProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("all");

  const { data: issues = [], isLoading, error } = useTeamPerformanceDetail(
    null,
    accountId
  );

  const categories = Array.from(new Set(issues.map((i) => i.issueCategory).filter(Boolean)));

  const filteredIssues = issues.filter((i) => {
    if (categoryFilter !== "all" && i.issueCategory !== categoryFilter) return false;
    if (!searchQuery) return true;
    const q = searchQuery.toLowerCase();
    return (
      i.issueLabel.toLowerCase().includes(q) ||
      i.issueDetail.toLowerCase().includes(q) ||
      (i.storeName && i.storeName.toLowerCase().includes(q)) ||
      (i.employeeName && i.employeeName.toLowerCase().includes(q)) ||
      (i.vcode && i.vcode.toLowerCase().includes(q))
    );
  });

  const handleExportXlsx = () => {
    exportToXlsx(
      issues.map((i) => ({
        Account: i.accountName,
        Group: i.groupName,
        Category: i.issueCategory,
        Label: i.issueLabel,
        Detail: i.issueDetail,
        "Days Impacted": i.daysImpacted ?? "—",
        Store: i.storeName ?? "—",
        Employee: i.employeeName ?? "—",
        VCode: i.vcode ?? "—",
      })),
      `Team_Performance_Issues_${accountName.replace(/\s+/g, "_")}`
    );
  };

  const handleExportCsv = () => {
    exportToCsv(
      issues.map((i) => ({
        Account: i.accountName,
        Group: i.groupName,
        Category: i.issueCategory,
        Label: i.issueLabel,
        Detail: i.issueDetail,
        "Days Impacted": i.daysImpacted ?? "—",
        Store: i.storeName ?? "—",
        Employee: i.employeeName ?? "—",
        VCode: i.vcode ?? "—",
      })),
      `Team_Performance_Issues_${accountName.replace(/\s+/g, "_")}`
    );
  };

  return (
    <Modal
      isOpen={true}
      onClose={onClose}
      title={`${accountName} — Operational Issues & SLA Breaches`}
      subtitle={
        <div className="flex items-center gap-2 pt-0.5">
          <span className="text-[10px] font-bold text-text-primary bg-surface-subtle px-2 py-0.5 rounded border border-border-default">
            Operational Discipline Audit
          </span>
          <span className="text-xs text-text-muted">{groupName}</span>
        </div>
      }
      maxWidthClass="max-w-4xl"
      footer={
        <div className="flex items-center justify-between w-full text-xs text-text-muted">
          <span>Total: {issues.length} operational issues recorded</span>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-1.5 text-xs font-semibold text-text-primary bg-surface hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer shadow-2xs"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        {/* Toolbar */}
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle pb-3">
          <div className="flex items-center gap-2 flex-wrap">
            <button
              type="button"
              onClick={() => setCategoryFilter("all")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition cursor-pointer ${
                categoryFilter === "all"
                  ? "bg-brand-50 text-brand-700 border border-brand-200 shadow-2xs"
                  : "text-text-secondary hover:bg-surface-hover border border-transparent"
              }`}
            >
              All Categories ({issues.length})
            </button>
            {categories.map((cat) => (
              <button
                key={cat}
                type="button"
                onClick={() => setCategoryFilter(cat)}
                className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition cursor-pointer ${
                  categoryFilter === cat
                    ? "bg-brand-50 text-brand-700 border border-brand-200 shadow-2xs"
                    : "text-text-secondary hover:bg-surface-hover border border-transparent"
                }`}
              >
                {cat}
              </button>
            ))}
          </div>

          <div className="flex items-center gap-2 ml-auto">
            <input
              type="text"
              placeholder="Search issues, store, employee..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="h-8 px-3 text-xs bg-surface border border-border-default rounded-md focus:outline-hidden focus:border-brand-500 w-48 sm:w-60"
            />
            <button
              type="button"
              onClick={handleExportXlsx}
              disabled={isLoading || !issues.length}
              className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-medium text-text-primary bg-surface hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer disabled:opacity-50"
              title="Export to XLSX"
            >
              <FileSpreadsheet className="w-3.5 h-3.5" />
              XLSX
            </button>
            <button
              type="button"
              onClick={handleExportCsv}
              disabled={isLoading || !issues.length}
              className="flex items-center gap-1.5 h-8 px-2.5 text-xs font-medium text-text-secondary bg-surface hover:bg-surface-hover border border-border-default rounded-md transition cursor-pointer disabled:opacity-50"
              title="Export to CSV"
            >
              <Download className="w-3.5 h-3.5" />
              CSV
            </button>
          </div>
        </div>

        {/* Content Body */}
        <div className="max-h-[60vh] overflow-y-auto">
          {isLoading ? (
            <div className="flex flex-col items-center justify-center py-20 text-text-muted">
              <Loader2 className="w-8 h-8 animate-spin text-brand-600 mb-2" />
              <p className="text-xs font-medium">Loading operational issues...</p>
            </div>
          ) : error ? (
            <div className="p-4 rounded-lg bg-danger-subtle border border-danger-border text-danger-text text-sm">
              Failed to load team performance issues. {String(error)}
            </div>
          ) : filteredIssues.length === 0 ? (
            <div className="text-center py-16 text-text-muted text-xs flex flex-col items-center gap-2">
              <AlertCircle className="w-8 h-8 text-pct-high" />
              <p className="font-semibold text-text-primary">No Operational Issues Recorded</p>
              <p>This account currently maintains full SLA compliance and operational discipline.</p>
            </div>
          ) : (
            <div className="overflow-x-auto border border-border-subtle rounded-lg">
              <table className="w-full text-left text-sm">
                <thead className="bg-surface-muted border-b border-border-subtle text-text-secondary text-sm font-semibold">
                  <tr>
                    <th className="py-2.5 px-3">Issue Category</th>
                    <th className="py-2.5 px-3">Label</th>
                    <th className="py-2.5 px-3">Detail &amp; Scope</th>
                    <th className="py-2.5 px-3">Store Branch</th>
                    <th className="py-2.5 px-3">Entity</th>
                    <th className="py-2.5 px-3 text-right">Impact</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle font-medium">
                  {filteredIssues.map((issue, idx) => (
                    <tr key={idx} className="hover:bg-surface-hover/50 transition">
                      <td className="py-2.5 px-3">
                        <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-semibold bg-surface-subtle text-text-secondary border border-border-default">
                          {issue.issueCategory}
                        </span>
                      </td>
                      <td className="py-2.5 px-3 font-semibold text-text-primary">
                        {issue.issueLabel}
                      </td>
                      <td className="py-2.5 px-3 text-text-secondary max-w-sm" title={issue.issueDetail}>
                        {issue.issueDetail}
                      </td>
                      <td className="py-2.5 px-3 text-text-secondary">
                        {issue.storeName || "—"}
                      </td>
                      <td className="py-2.5 px-3 text-text-secondary">
                        {issue.employeeName ? (
                          <span className="text-text-primary font-medium">{issue.employeeName}</span>
                        ) : issue.vcode ? (
                          <span className="font-mono text-[11px] text-brand-700 bg-brand-50 px-1.5 py-0.5 rounded border border-brand-200">
                            {issue.vcode}
                          </span>
                        ) : (
                          "—"
                        )}
                      </td>
                      <td className="py-2.5 px-3 text-right">
                        {issue.daysImpacted != null ? (
                          <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold bg-danger-subtle text-danger-text border border-danger-border">
                            {issue.daysImpacted}d delayed
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
      </div>
    </Modal>
  );
}
