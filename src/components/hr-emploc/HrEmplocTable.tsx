// components/hr-emploc/HrEmplocTable.tsx
"use client";

import { useState } from "react";
import {
  LockKeyhole,
  AlertTriangle,
  UserCheck,
  AlertCircle,
  Upload,
  CheckCircle2,
  RotateCcw,
  Edit3,
  Eye,
  MoreVertical,
} from "lucide-react";
import { DataState } from "@/components/shared/DataState";
import { TablePagination } from "@/components/shared/TablePagination";
import {
  formatPersonName,
  formatPosition,
  formatAccountName,
  formatDisplayText,
} from "@/lib/utils/displayText";
import {
  type HrEmplocDataErrorKind,
  type HrEmplocListItem,
  type HrEmplocQueue,
} from "@/lib/queries/hr_emploc";
import {
  useInheritedHrcoMap,
  InheritedHrcoBadge,
} from "@/components/hr-emploc/useInheritedHrco";

export type { HrEmplocQueue } from "@/lib/queries/hr_emploc";

type HrEmplocTableProps = {
  queue: HrEmplocQueue;
  queueLabel?: string;
  rows: HrEmplocListItem[];
  selectedId: string | null;
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  errorKind: HrEmplocDataErrorKind | null;
  onSelect: (row: HrEmplocListItem) => void;
  onRetry: () => void;
  onPageChange: (page: number) => void;
  onPageSizeChange?: (pageSize: number) => void;
  onAddEmploc?: (row: HrEmplocListItem) => void;
  onForCorrection?: (row: HrEmplocListItem) => void;
  onUploadDocs?: (row: HrEmplocListItem) => void;
  onApproveReview?: (row: HrEmplocListItem) => void;
  onRevertReview?: (row: HrEmplocListItem) => void;
  onRevertToPending?: (row: HrEmplocListItem) => void;
  onViewDocs?: (row: HrEmplocListItem) => void;
  onEditEmploc?: (row: HrEmplocListItem) => void;
};

function getTableColumns(queue: HrEmplocQueue): string[] {
  switch (queue) {
    case "pending":
      return [
        "Applicant",
        "Account / Store",
        "Position",
        "HRCO",
        "SLA",
        "Docs",
        "Actions",
      ];
    case "for_emploc":
      return [
        "Group",
        "Account",
        "Applicant",
        "Position",
        "HRCO",
        "SLA",
        "Docs",
        "Actions",
      ];
    case "correction":
      return [
        "Group",
        "Account",
        "Applicant",
        "SLA",
        "Reason",
        "Remarks",
        "Docs",
        "Actions",
      ];
    case "review":
      return [
        "Group",
        "Account",
        "Applicant",
        "SLA",
        "Reason",
        "Remarks",
        "Attachment",
        "Actions",
      ];
    case "deployed":
    case "ready":
      return [
        "Employee #",
        "Applicant",
        "Store / Position",
        "HRCO",
        "Deployed Date",
        "Actions",
      ];
    default:
      return [
        "Group",
        "Account",
        "Applicant",
        "Position",
        "HRCO",
        "SLA",
        "Docs",
        "Actions",
      ];
  }
}

const SLA_BADGE_CLASS =
  "border border-border-default bg-surface-muted font-mono font-medium text-text-secondary";

export function HrEmplocTable({
  queue,
  rows,
  selectedId,
  totalCount,
  page,
  pageSize,
  isLoading,
  errorKind,
  onSelect,
  onRetry,
  onPageChange,
  onPageSizeChange,
  onAddEmploc,
  onForCorrection,
  onUploadDocs,
  onApproveReview,
  onRevertReview,
  onRevertToPending,
  onViewDocs,
  onEditEmploc,
}: HrEmplocTableProps) {
  const columns = getTableColumns(queue);
  const { getHrcosForRecord } = useInheritedHrcoMap();
  const [openOverflowId, setOpenOverflowId] = useState<string | null>(null);

  const getErrorTitle = () => {
    return errorKind === "access_denied"
      ? "HR Emploc Access Blocked"
      : "Compliance Queue Data Unavailable";
  };

  const getErrorDescription = () => {
    return errorKind === "access_denied"
      ? "Access denied due to active security boundary checks. Partial or unscoped listings are blocked."
      : "The compliance request failed on the server. You can retry the query directly.";
  };

  return (
    <section className="flex min-h-[520px] flex-col rounded-md border border-table-rule-section bg-table-row shadow-2xs">
      {/* Main Table Container with sticky header & sticky right actions column */}
      <div className="relative min-h-0 flex-1 overflow-x-auto overflow-y-auto">
        <table className="w-full min-w-[960px] border-separate border-spacing-0 text-left text-[0.875rem]">
          <thead className="sticky top-0 z-20 bg-table-header text-xs font-semibold text-text-secondary shadow-xs">
            <tr>
              {columns.map((column) => {
                const isActions = column === "Actions";
                return (
                  <th
                    key={column}
                    scope="col"
                    className={`border-b border-table-rule-section px-4 py-3 whitespace-nowrap bg-table-header ${
                      isActions
                        ? "sticky right-0 z-30 text-right shadow-[-4px_0_6px_-2px_rgba(0,0,0,0.06)]"
                        : ""
                    }`}
                  >
                    {column}
                  </th>
                );
              })}
            </tr>
          </thead>

          <tbody>
            {isLoading ? (
              <tr>
                <td className="px-6 py-12 text-center" colSpan={columns.length}>
                  <DataState
                    kind="loading"
                    title="Loading recruits"
                    description="Fetching compliance queue records from database..."
                  />
                </td>
              </tr>
            ) : errorKind ? (
              <tr>
                <td className="px-6 py-12 text-center" colSpan={columns.length}>
                  <DataState
                    kind="error"
                    title={getErrorTitle()}
                    description={getErrorDescription()}
                    onRetry={onRetry}
                  />
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td className="px-6 py-12 text-center" colSpan={columns.length}>
                  <DataState
                    kind="empty"
                    title="No recruits found"
                    description="No employee allocation records found matching active queue or filter criteria."
                  />
                </td>
              </tr>
            ) : (
              rows.map((row) => {
                const isPendingDeletion =
                  row.isPendingDeletion ||
                  row.hrStatus.toLowerCase().trim() === "pending deletion" ||
                  row.hrStatus.toLowerCase().trim() === "pending_deletion";

                const caps = row.rowCapabilities;

                return (
                  <tr
                    key={row.id}
                    onClick={() => {
                      if (caps.canViewDetail) {
                        onSelect(row);
                      }
                    }}
                    className={`group border-b border-table-rule transition-colors ${
                      caps.canViewDetail ? "cursor-pointer" : "cursor-not-allowed"
                    } ${
                      selectedId === row.id
                        ? "bg-table-row-selected"
                        : isPendingDeletion
                        ? "bg-table-row-danger hover:bg-table-row-danger-hover"
                        : "hover:bg-table-row-hover"
                    }`}
                  >
                    {/* ── Pending Tab Columns ────────────────────────── */}
                    {queue === "pending" && (
                      <>
                        {/* 1. Applicant */}
                        <td className="border-b border-table-rule px-4 py-2.5 font-medium text-table-text">
                          <div className="flex items-center gap-1.5 flex-wrap">
                            {isPendingDeletion && (
                              <span className="inline-flex items-center gap-1 rounded bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)] px-1.5 py-0.5 text-3xs font-bold">
                                <AlertTriangle className="h-3 w-3 shrink-0" />
                                <span>For Deletion</span>
                              </span>
                            )}
                            <span className={isPendingDeletion ? "text-table-text-muted line-through" : ""}>
                              {row.applicantName ? formatPersonName(row.applicantName) : "--"}
                            </span>
                          </div>
                        </td>

                        {/* 2. Account / Store */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text max-w-[200px]">
                          <p className="truncate font-medium">{row.accountName ? formatAccountName(row.accountName) : "--"}</p>
                          <p className="truncate text-2xs text-text-muted">{row.storeName || "Unassigned Store"}</p>
                        </td>

                        {/* 3. Position */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text truncate max-w-[160px]">
                          {row.positionTitle ? formatPosition(row.positionTitle) : "--"}
                        </td>

                        {/* 4. HRCO */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub truncate max-w-[140px]">
                          <InheritedHrcoBadge
                            hrcos={getHrcosForRecord({ accountId: row.accountId, groupId: row.groupId })}
                            fallbackName={row.hrcoName}
                          />
                        </td>

                        {/* 5. SLA */}
                        <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                          <span className={`inline-flex items-center rounded-md px-2 py-0.5 text-2xs ${SLA_BADGE_CLASS}`}>
                            {row.slaElapsedDays} {row.slaElapsedDays === 1 ? "day" : "days"}
                          </span>
                        </td>

                        {/* 6. Docs */}
                        <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                          {row.docCount > 0 ? (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                onViewDocs?.(row);
                              }}
                              className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-subtle px-2 py-1 text-2xs font-medium text-text-primary hover:bg-surface-hover hover:border-accent-primary cursor-pointer transition"
                            >
                              <Eye className="h-3 w-3 text-accent-primary" />
                              <span>{row.docCount > 1 ? `View (${row.docCount})` : "View"}</span>
                            </button>
                          ) : (
                            <span className="text-3xs text-text-muted italic">0 docs</span>
                          )}
                        </td>
                      </>
                    )}

                    {/* ── For Emploc Tab Columns ─────────────────────── */}
                    {queue === "for_emploc" && (
                      <>
                        {/* 1. Group */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text font-medium truncate max-w-[140px]">
                          {row.groupName ? formatDisplayText(row.groupName) : "--"}
                        </td>

                        {/* 2. Account */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text truncate max-w-[160px]">
                          {row.accountName ? formatAccountName(row.accountName) : "--"}
                        </td>

                        {/* 3. Applicant */}
                        <td className="border-b border-table-rule px-4 py-2.5 font-medium text-table-text">
                          <div className="flex items-center gap-1.5 flex-wrap">
                            {isPendingDeletion && (
                              <span className="inline-flex items-center gap-1 rounded bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)] px-1.5 py-0.5 text-3xs font-bold">
                                <AlertTriangle className="h-3 w-3 shrink-0" />
                                <span>For Deletion</span>
                              </span>
                            )}
                            <span className={isPendingDeletion ? "text-table-text-muted line-through" : ""}>
                              {row.applicantName ? formatPersonName(row.applicantName) : "--"}
                            </span>
                          </div>
                        </td>

                        {/* 4. Position */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text truncate max-w-[160px]">
                          {row.positionTitle ? formatPosition(row.positionTitle) : "--"}
                        </td>

                        {/* 5. HRCO */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub truncate max-w-[140px]">
                          <InheritedHrcoBadge
                            hrcos={getHrcosForRecord({ accountId: row.accountId, groupId: row.groupId })}
                            fallbackName={row.hrcoName}
                          />
                        </td>

                        {/* 6. SLA */}
                        <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                          <span className={`inline-flex items-center rounded-md px-2 py-0.5 text-2xs ${SLA_BADGE_CLASS}`}>
                            {row.slaElapsedDays} {row.slaElapsedDays === 1 ? "day" : "days"}
                          </span>
                        </td>

                        {/* 7. Docs */}
                        <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                          {row.docCount > 0 ? (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                onViewDocs?.(row);
                              }}
                              className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-subtle px-2 py-1 text-2xs font-medium text-text-primary hover:bg-surface-hover hover:border-accent-primary cursor-pointer transition"
                            >
                              <Eye className="h-3 w-3 text-accent-primary" />
                              <span>{row.docCount > 1 ? `View (${row.docCount})` : "View"}</span>
                            </button>
                          ) : (
                            <span className="text-3xs text-text-muted italic">0 docs</span>
                          )}
                        </td>
                      </>
                    )}

                    {/* ── Correction & Review Tabs Columns (No Position/HRCO) ── */}
                    {(queue === "correction" || queue === "review") && (
                      <>
                        {/* 1. Group */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text font-medium truncate max-w-[140px]">
                          {row.groupName ? formatDisplayText(row.groupName) : "--"}
                        </td>

                        {/* 2. Account */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text truncate max-w-[160px]">
                          {row.accountName ? formatAccountName(row.accountName) : "--"}
                        </td>

                        {/* 3. Applicant */}
                        <td className="border-b border-table-rule px-4 py-2.5 font-medium text-table-text">
                          <div className="flex items-center gap-1.5 flex-wrap">
                            {isPendingDeletion && (
                              <span className="inline-flex items-center gap-1 rounded bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)] px-1.5 py-0.5 text-3xs font-bold">
                                <AlertTriangle className="h-3 w-3 shrink-0" />
                                <span>For Deletion</span>
                              </span>
                            )}
                            <span className={isPendingDeletion ? "text-table-text-muted line-through" : ""}>
                              {row.applicantName ? formatPersonName(row.applicantName) : "--"}
                            </span>
                          </div>
                        </td>

                        {/* 4. SLA */}
                        <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                          <span className={`inline-flex items-center rounded-md px-2 py-0.5 text-2xs ${SLA_BADGE_CLASS}`}>
                            {row.slaElapsedDays} {row.slaElapsedDays === 1 ? "day" : "days"}
                          </span>
                        </td>

                        {/* 5. Reason (Badges with flex-wrap, no truncate/narrow width) */}
                        <td className="border-b border-table-rule px-4 py-2.5">
                          <div className="flex flex-wrap gap-1.5 items-center">
                            {row.deficiencyIssues && row.deficiencyIssues.length > 0 ? (
                              row.deficiencyIssues.map((issue) => (
                                <span
                                  key={issue.code}
                                  className="rounded border border-status-warning/40 bg-status-warning/10 px-2 py-0.5 text-3xs font-medium text-status-warning whitespace-nowrap"
                                  title={issue.comment || issue.label}
                                >
                                  {issue.label || issue.code}
                                </span>
                              ))
                            ) : row.deficiencySummary ? (
                              <span className="rounded border border-status-warning/40 bg-status-warning/10 px-2 py-0.5 text-3xs font-medium text-status-warning">
                                {row.deficiencySummary}
                              </span>
                            ) : (
                              <span className="text-table-text-muted text-xs">--</span>
                            )}
                          </div>
                        </td>

                        {/* 6. Remarks (Ops Remark) */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text max-w-[220px]">
                          {row.remarks ? (
                            <span className="text-2xs text-text-secondary italic line-clamp-2" title={row.remarks}>
                              &ldquo;{row.remarks}&rdquo;
                            </span>
                          ) : (
                            <span className="text-table-text-muted text-xs">--</span>
                          )}
                        </td>

                        {/* 7. Docs / Attachment */}
                        <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                          {row.docCount > 0 ? (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                onViewDocs?.(row);
                              }}
                              className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-subtle px-2 py-1 text-2xs font-medium text-text-primary hover:bg-surface-hover hover:border-accent-primary cursor-pointer transition"
                            >
                              <Eye className="h-3 w-3 text-accent-primary" />
                              <span>{row.docCount > 1 ? `View (${row.docCount})` : "View"}</span>
                            </button>
                          ) : (
                            <span className="text-3xs text-text-muted italic">0 docs</span>
                          )}
                        </td>
                      </>
                    )}

                    {/* ── Deployed / Ready Tab Columns ───────────────── */}
                    {(queue === "deployed" || queue === "ready") && (
                      <>
                        {/* 1. Employee # */}
                        <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                          <span className="font-mono text-xs font-bold text-text-primary">
                            {row.employeeNo || "—"}
                          </span>
                        </td>

                        {/* 2. Applicant */}
                        <td className="border-b border-table-rule px-4 py-2.5 font-medium text-table-text">
                          <div className="flex items-center gap-1.5 flex-wrap">
                            {isPendingDeletion && (
                              <span className="inline-flex items-center gap-1 rounded bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)] px-1.5 py-0.5 text-3xs font-bold">
                                <AlertTriangle className="h-3 w-3 shrink-0" />
                                <span>For Deletion</span>
                              </span>
                            )}
                            <span className={isPendingDeletion ? "text-table-text-muted line-through" : ""}>
                              {row.applicantName ? formatPersonName(row.applicantName) : "--"}
                            </span>
                          </div>
                        </td>

                        {/* 3. Store / Position */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text max-w-[200px]">
                          <p className="truncate font-medium">{row.storeName || "Unassigned Store"}</p>
                          <p className="truncate text-2xs text-text-muted">{row.positionTitle || "--"}</p>
                        </td>

                        {/* 4. HRCO */}
                        <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub truncate max-w-[140px]">
                          <InheritedHrcoBadge
                            hrcos={getHrcosForRecord({ accountId: row.accountId, groupId: row.groupId })}
                            fallbackName={row.hrcoName}
                          />
                        </td>

                        {/* 5. Deployed Date */}
                        <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap text-2xs text-text-secondary">
                          {row.hiredDate || "--"}
                        </td>
                      </>
                    )}

                    {/* ── Sticky Right Actions Column ─────────────────── */}
                    <td className="sticky right-0 z-10 border-b border-table-rule bg-table-row group-hover:bg-table-row-hover px-4 py-2.5 text-right whitespace-nowrap shadow-[-4px_0_6px_-2px_rgba(0,0,0,0.06)]">
                      <div className="flex items-center justify-end gap-1.5">
                        {/* Pending Tab Primary Action: Upload Docs */}
                        {queue === "pending" && (
                          <>
                            {caps.can_upload_docs && onUploadDocs && (
                              <button
                                type="button"
                                disabled={isPendingDeletion}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onUploadDocs(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md bg-brand-button hover:bg-brand-button-hover px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                                title="Upload Requirements & Move to For Emploc"
                              >
                                <Upload className="h-3.5 w-3.5" />
                                <span>Upload Docs</span>
                              </button>
                            )}

                            {/* SA Override Add Emploc from Pending */}
                            {caps.can_assign_employee_no && onAddEmploc && (
                              <div className="relative">
                                <button
                                  type="button"
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    setOpenOverflowId(openOverflowId === row.id ? null : row.id);
                                  }}
                                  className="rounded p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary"
                                  title="Admin actions"
                                >
                                  <MoreVertical className="h-3.5 w-3.5" />
                                </button>
                                {openOverflowId === row.id && (
                                  <div
                                    className="absolute right-0 top-full mt-1 z-30 w-44 rounded-lg border border-border-default bg-surface-base p-1 shadow-lg text-left"
                                    onClick={(e) => e.stopPropagation()}
                                  >
                                    <button
                                      type="button"
                                      onClick={() => {
                                        setOpenOverflowId(null);
                                        onAddEmploc(row);
                                      }}
                                      className="flex w-full items-center gap-2 rounded px-2.5 py-1.5 text-xs text-text-primary hover:bg-surface-hover"
                                    >
                                      <UserCheck className="h-3.5 w-3.5 text-accent-primary" />
                                      <span>Add Emploc (SA)</span>
                                    </button>
                                  </div>
                                )}
                              </div>
                            )}
                          </>
                        )}

                        {/* For Emploc Tab Actions: + Add Emploc & ! For Correction */}
                        {queue === "for_emploc" && (
                          <>
                            {caps.can_assign_employee_no && onAddEmploc && (
                              <button
                                type="button"
                                disabled={isPendingDeletion}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onAddEmploc(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md bg-brand-button hover:bg-brand-button-hover px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                                title="Assign Emploc Number & Deploy to Plantilla"
                              >
                                <UserCheck className="h-3.5 w-3.5" />
                                <span>+ Add Emploc</span>
                              </button>
                            )}

                            {caps.can_tag_deficiency && onForCorrection && (
                              <button
                                type="button"
                                disabled={isPendingDeletion}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onForCorrection(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                                title="Tag deficiencies and send to For Correction"
                              >
                                <AlertCircle className="h-3.5 w-3.5 text-status-warning" />
                                <span>! For Correction</span>
                              </button>
                            )}
                          </>
                        )}

                        {/* Correction Tab Actions: Upload Docs / Submit Correction */}
                        {queue === "correction" && (
                          <>
                            {(caps.can_upload_docs || caps.can_submit_correction) && onUploadDocs && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onUploadDocs(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md bg-brand-button hover:bg-brand-button-hover px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition-colors cursor-pointer"
                                title="Upload correction documents and submit"
                              >
                                <Upload className="h-3.5 w-3.5" />
                                <span>Upload Docs</span>
                              </button>
                            )}
                          </>
                        )}

                        {/* Review Tab Actions: Approve & Revert */}
                        {queue === "review" && (
                          <>
                            {caps.can_review_approve && onApproveReview && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onApproveReview(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md bg-brand-button hover:bg-brand-button-hover px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition-colors cursor-pointer"
                                title="Approve review and deploy candidate"
                              >
                                <CheckCircle2 className="h-3.5 w-3.5" />
                                <span>Approve</span>
                              </button>
                            )}

                            {caps.can_review_return && onRevertReview && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onRevertReview(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md border border-status-danger/30 bg-surface px-2.5 py-1 text-xs font-semibold text-status-danger shadow-2xs hover:bg-status-danger/10 transition-colors cursor-pointer"
                                title="Return back to Correction"
                              >
                                <RotateCcw className="h-3.5 w-3.5" />
                                <span>Revert</span>
                              </button>
                            )}
                          </>
                        )}

                        {/* Deployed Tab Actions: Edit Emploc # & Revert to Pending */}
                        {(queue === "deployed" || queue === "ready") && (
                          <>
                            {caps.can_edit_emploc_no && onEditEmploc && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onEditEmploc(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface hover:bg-surface-hover px-2 py-1 text-xs font-semibold text-text-primary shadow-2xs transition-colors cursor-pointer"
                                title="Edit Emploc Number"
                              >
                                <Edit3 className="h-3.5 w-3.5" />
                                <span>Edit Emploc #</span>
                              </button>
                            )}

                            {caps.can_revert_to_pending && onRevertToPending && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onRevertToPending(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md border border-status-danger/30 bg-surface hover:bg-status-danger/10 px-2 py-1 text-xs font-semibold text-status-danger shadow-2xs transition-colors cursor-pointer"
                                title="Revert Deployed record to Pending (within 3-day window)"
                              >
                                <RotateCcw className="h-3.5 w-3.5" />
                                <span>Revert</span>
                              </button>
                            )}
                          </>
                        )}

                        {/* Status indicators */}
                        {isPendingDeletion && (
                          <span title="Record Locked: Pending Deletion">
                            <LockKeyhole className="h-3.5 w-3.5 text-status-danger" />
                          </span>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination Footer */}
      <TablePagination
        page={page}
        pageSize={pageSize}
        totalCount={totalCount}
        pageSizeOptions={[10, 25, 50]}
        onPageChange={onPageChange}
        onPageSizeChange={onPageSizeChange}
        isLoading={isLoading}
      />
    </section>
  );
}
