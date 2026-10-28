// components/hr-emploc/HrEmplocTable.tsx
"use client";

import {
  LockKeyhole,
  AlertTriangle,
  UserCheck,
  AlertCircle,
  Upload,
  Send,
  CheckCircle2,
  RotateCcw,
  Download,
  ArrowRight,
  Edit3,
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
  isBenefitsOnlyCorrection,
  type HrEmplocDataErrorKind,
  type HrEmplocListItem,
  type HrEmplocQueue,
} from "@/lib/queries/hr_emploc";
import { useCurrentUser } from "@/lib/auth";
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
  onAssignEmployeeNo?: (row: HrEmplocListItem) => void;
  onMoveToPlantilla?: (row: HrEmplocListItem) => void;
  onUploadAttachment?: (row: HrEmplocListItem) => void;
  onSubmitCorrection?: (row: HrEmplocListItem) => void;
  onApproveReview?: (row: HrEmplocListItem) => void;
  onRevertReview?: (row: HrEmplocListItem) => void;
  onDownloadAttachment?: (row: HrEmplocListItem) => void;
  onEditEmploc?: (row: HrEmplocListItem) => void;
};

function getTableColumns(queue: HrEmplocQueue): string[] {
  switch (queue) {
    case "correction":
      return [
        "Group",
        "Account",
        "Applicant",
        "Position",
        "HRCO",
        "SLA",
        "Reason",
        "Actions",
      ];
    case "review":
      return [
        "Group",
        "Account",
        "Applicant",
        "Position",
        "HRCO",
        "SLA",
        "Reason",
        "Remarks",
        "Attachment",
        "Actions",
      ];
    case "deployed":
    case "ready":
      return [
        "Group",
        "Account",
        "Emploc ID / Applicant",
        "Position",
        "HRCO",
        "SLA",
        "Actions",
      ];
    case "pending":
    default:
      return [
        "Group",
        "Account",
        "Applicant",
        "Position",
        "HRCO",
        "SLA",
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
  onAssignEmployeeNo,
  onMoveToPlantilla,
  onUploadAttachment,
  onSubmitCorrection,
  onApproveReview,
  onRevertReview,
  onDownloadAttachment,
  onEditEmploc,
}: HrEmplocTableProps) {
  const columns = getTableColumns(queue);
  const handleAddEmploc = onAddEmploc || onAssignEmployeeNo;
  const currentUser = useCurrentUser();
  const { getHrcosForRecord } = useInheritedHrcoMap();

  const roleName = (currentUser?.roleName ?? currentUser?.roleKey ?? "").toLowerCase().trim();
  const isSuperAdmin =
    roleName.includes("super_admin") ||
    roleName.includes("super admin") ||
    roleName.includes("developer");
  const isDataTeam =
    roleName.includes("encoder") ||
    roleName.includes("data") ||
    roleName.includes("head_admin") ||
    roleName.includes("head admin");
  const isHrPersonnelOrOps =
    roleName.includes("hr") ||
    roleName.includes("om") ||
    roleName.includes("hrco") ||
    roleName.includes("atl") ||
    roleName.includes("tl");

  // Allowed Roles:
  // + Add Emploc: Super Admin, Data Team, and HR Personnel (including OM / HRCO)
  const canAddEmploc = isSuperAdmin || isDataTeam || isHrPersonnelOrOps;
  // ! For Correction: Super Admin and HR Personnel (OM / HRCO only). Hidden from Data Team!
  const canForCorrection = (isSuperAdmin || isHrPersonnelOrOps) && !isDataTeam;

  const getErrorTitle = () => {
    return errorKind === "access_denied"
      ? "HR Emploc Access Blocked"
      : "Compliance Queue Data Unavailable";
  };

  const getErrorDescription = () => {
    return errorKind === "access_denied"
      ? "Supabase denied this compliance read request due to active RLS boundary checks. Partial or unscoped listings are blocked."
      : "The compliance RPC request failed on the server. You can retry the query directly.";
  };

  return (
    <section className="flex min-h-[520px] flex-col rounded-md border border-table-rule-section bg-table-row shadow-2xs">
      {/* Main Table Container (Without redundant inner card header bar) */}
      <div className="min-h-0 flex-1 overflow-auto">
        <table className="w-full min-w-[1080px] border-separate border-spacing-0 text-left text-[0.9375rem]">
          <thead className="sticky top-0 z-10 bg-table-header text-sm font-semibold text-text-secondary">
            <tr>
              {columns.map((column) => (
                <th
                  className={`border-b border-table-rule-section px-4 py-3 whitespace-nowrap ${
                    column === "Actions" ? "text-right" : ""
                  }`}
                  key={column}
                  scope="col"
                >
                  {column}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={columns.length}>
                  <DataState
                    kind="loading"
                    title="Loading compliance roster"
                    description="Executing list_web_hr_emplocs query on the Supabase cluster."
                  />
                </td>
              </tr>
            ) : errorKind ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={columns.length}>
                  <DataState
                    kind={errorKind === "access_denied" ? "access_denied" : "error"}
                    title={getErrorTitle()}
                    description={getErrorDescription()}
                    onRetry={onRetry}
                  />
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td className="px-3 py-12 text-center" colSpan={columns.length}>
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
                  row.hrStatus.toLowerCase().trim() === "pending deletion" ||
                  row.hrStatus.toLowerCase().trim() === "pending_deletion";

                // Conditional Upload Button Rule:
                // Hide Upload button ONLY when deficiency reason(s) consist exclusively of Invalid SSS, PhilHealth (PH), and/or Pag-IBIG.
                const isBenefitsOnly = isBenefitsOnlyCorrection(
                  row.correctionReason,
                  row.deficiencyIssues
                );
                const showUploadButton = !isBenefitsOnly;

                return (
                  <tr
                    className={`border-b border-table-rule transition-colors ${
                      row.rowCapabilities.canViewDetail ? "cursor-pointer" : "cursor-not-allowed"
                    } ${
                      selectedId === row.id
                        ? "bg-table-row-selected"
                        : isPendingDeletion
                        ? "bg-table-row-danger hover:bg-table-row-danger-hover"
                        : "hover:bg-table-row-hover"
                    }`}
                    key={row.id}
                    onClick={() => {
                      if (row.rowCapabilities.canViewDetail) {
                        onSelect(row);
                      }
                    }}
                  >
                    {/* 1. Group */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text font-medium truncate max-w-[140px]">
                      {row.groupName ? formatDisplayText(row.groupName) : "--"}
                    </td>

                    {/* 2. Account */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text truncate max-w-[160px]">
                      {row.accountName ? formatAccountName(row.accountName) : "--"}
                    </td>

                    {/* 3. Applicant / Emploc ID */}
                    <td className="border-b border-table-rule px-4 py-2.5">
                      {queue === "deployed" || queue === "ready" ? (
                        <div className="flex flex-col">
                          <div className="flex items-center gap-1.5 font-mono text-xs font-bold text-text-primary">
                            {isPendingDeletion && (
                              <span className="inline-flex items-center gap-1 rounded bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)] px-1.5 py-0.5 text-[10px] font-bold font-sans">
                                <AlertTriangle className="h-3 w-3 shrink-0" aria-hidden="true" />
                                <span>For Deletion</span>
                              </span>
                            )}
                            <span className={isPendingDeletion ? "text-table-text-muted line-through" : ""}>
                              {row.employeeNo || "—"}
                            </span>
                          </div>
                          <div
                            className={`text-xs text-text-secondary truncate max-w-[200px] font-medium ${
                              isPendingDeletion ? "line-through text-table-text-muted" : ""
                            }`}
                            title={row.applicantName || undefined}
                          >
                            {row.applicantName ? formatPersonName(row.applicantName) : "—"}
                          </div>
                        </div>
                      ) : (
                        <div className="font-semibold text-table-text flex items-center gap-1.5 flex-wrap">
                          {isPendingDeletion && (
                            <span className="inline-flex items-center gap-1 rounded bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)] px-1.5 py-0.5 text-[10px] font-bold">
                              <AlertTriangle className="h-3 w-3 shrink-0" aria-hidden="true" />
                              <span>For Deletion</span>
                            </span>
                          )}
                          <span className={isPendingDeletion ? "text-table-text-muted line-through" : ""}>
                            {row.applicantName ? formatPersonName(row.applicantName) : "--"}
                          </span>
                        </div>
                      )}
                    </td>

                    {/* 4. Position */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text truncate max-w-[160px]">
                      {row.positionTitle ? formatPosition(row.positionTitle) : "--"}
                    </td>

                    {/* 5. HRCO (Inherited from User Management) */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-table-text-sub truncate max-w-[140px]">
                      <InheritedHrcoBadge
                        hrcos={getHrcosForRecord({ accountId: row.accountId, groupId: row.groupId })}
                        fallbackName={row.hrcoName}
                      />
                    </td>

                    {/* 6. SLA (Aging - Frozen once Deployed) */}
                    <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                      <span
                        className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs ${SLA_BADGE_CLASS}`}
                      >
                        {queue === "deployed" || row.deploymentStatus === "Moved to Plantilla"
                          ? `Completed in ${row.slaElapsedDays} ${row.slaElapsedDays === 1 ? "day" : "days"}`
                          : `${row.slaElapsedDays} ${row.slaElapsedDays === 1 ? "day" : "days"}`}
                      </span>
                    </td>

                    {/* 7. Reason (Correction & Review Tabs) */}
                    {(queue === "correction" || queue === "review") && (
                      <td className="border-b border-table-rule px-4 py-2.5 max-w-[200px]">
                        {row.deficiencySummary ? (
                          <span
                            className="inline-block truncate max-w-[190px] rounded bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary border border-border-default"
                            title={row.deficiencySummary}
                          >
                            {row.deficiencySummary}
                          </span>
                        ) : (
                          <span className="text-table-text-muted text-xs">--</span>
                        )}
                      </td>
                    )}

                    {/* 8. Remarks (Review Tab) */}
                    {queue === "review" && (
                      <td className="border-b border-table-rule px-4 py-2.5 text-table-text max-w-[200px]">
                        {row.remarks ? (
                          <span
                            className="inline-block truncate max-w-[190px] text-xs text-text-secondary italic"
                            title={row.remarks}
                          >
                            &ldquo;{row.remarks}&rdquo;
                          </span>
                        ) : null}
                      </td>
                    )}

                    {/* 9. Attachment (Review Tab) */}
                    {queue === "review" && (
                      <td className="border-b border-table-rule px-4 py-2.5 whitespace-nowrap">
                        {row.attachmentUrl ? (
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              onDownloadAttachment?.(row);
                            }}
                            className="inline-flex items-center justify-center rounded-md p-1.5 text-brand-600 bg-brand-50 hover:bg-brand-100 hover:text-brand-800 border border-brand-200 transition-colors cursor-pointer shadow-2xs"
                            title={`Download ${row.attachmentFileName || "attachment"}`}
                            aria-label={`Download ${row.attachmentFileName || "attachment"}`}
                          >
                            <Download className="h-4 w-4 shrink-0" />
                          </button>
                        ) : null}
                      </td>
                    )}

                    {/* Tab-Specific Actions */}
                    <td className="border-b border-table-rule px-4 py-2.5 text-right whitespace-nowrap">
                      <div className="flex items-center justify-end gap-1.5">
                        {/* ── Pending Queue Actions ──────────────── */}
                        {queue === "pending" && (
                          <>
                            {canAddEmploc && handleAddEmploc && (
                              <button
                                type="button"
                                disabled={isPendingDeletion}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handleAddEmploc(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md bg-brand-500 hover:bg-brand-600 px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                                aria-label={`Add Emploc for ${row.applicantName}`}
                              >
                                <UserCheck className="h-3.5 w-3.5" />
                                <span>+ Add Emploc</span>
                              </button>
                            )}

                            {canForCorrection && onForCorrection && (
                              <button
                                type="button"
                                disabled={isPendingDeletion}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onForCorrection(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface px-2.5 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                                aria-label={`Return for correction for ${row.applicantName}`}
                              >
                                <AlertCircle className="h-3.5 w-3.5" />
                                <span>! For Correction</span>
                              </button>
                            )}
                          </>
                        )}

                        {/* ── Correction Queue Actions ───────────── */}
                        {queue === "correction" && (
                          <>
                            {row.rowCapabilities.canSubmitCorrection && showUploadButton && onUploadAttachment && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onUploadAttachment(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface px-2 py-1 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover transition-colors cursor-pointer"
                                aria-label={`Upload document for ${row.applicantName}`}
                                title="Upload supporting document"
                              >
                                <Upload className="h-3.5 w-3.5" />
                                <span>Upload</span>
                              </button>
                            )}

                            {row.rowCapabilities.canSubmitCorrection && onSubmitCorrection && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onSubmitCorrection(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md bg-brand-500 hover:bg-brand-600 px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition-colors cursor-pointer"
                                aria-label={`Submit correction for ${row.applicantName}`}
                                title="Submit correction with notes to Review"
                              >
                                <Send className="h-3.5 w-3.5" />
                                <span>Submit Correction</span>
                              </button>
                            )}
                          </>
                        )}

                        {/* ── Review Queue Actions ───────────────── */}
                        {queue === "review" && (
                          <>
                            {(row.rowCapabilities.canReviewCorrection || row.rowCapabilities.canApproveCorrection) && onApproveReview && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onApproveReview(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md bg-brand-500 hover:bg-brand-600 px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition-colors cursor-pointer"
                                aria-label={`Approve correction review for ${row.applicantName}`}
                                title="Approve correction"
                              >
                                <CheckCircle2 className="h-3.5 w-3.5" />
                                <span>Approve</span>
                              </button>
                            )}

                            {(row.rowCapabilities.canReviewCorrection || row.rowCapabilities.canRevertCorrection) && onRevertReview && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onRevertReview(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md border border-danger-border bg-surface px-2.5 py-1 text-xs font-semibold text-danger-text shadow-2xs hover:bg-danger-bg transition-colors cursor-pointer"
                                aria-label={`Revert review for ${row.applicantName}`}
                                title="Revert back to Correction"
                              >
                                <RotateCcw className="h-3.5 w-3.5" />
                                <span>Revert</span>
                              </button>
                            )}
                          </>
                        )}

                        {/* ── Deployed / Ready Queue Actions ────────────────── */}
                        {(queue === "deployed" || queue === "ready") && (
                          <>
                            {onEditEmploc && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onEditEmploc(row);
                                }}
                                className="inline-flex items-center justify-center rounded-md border border-border-default bg-surface hover:bg-surface-hover p-1.5 text-text-primary shadow-2xs transition-colors cursor-pointer hover:border-border-strong"
                                aria-label={`Edit Emploc for ${row.applicantName}`}
                                title="Edit Emploc ID or Revert to Pending"
                              >
                                <Edit3 className="h-3.5 w-3.5" />
                              </button>
                            )}

                            {row.rowCapabilities.canMoveToPlantilla && onMoveToPlantilla && !row.employeeNo && (
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onMoveToPlantilla(row);
                                }}
                                className="inline-flex items-center gap-1 rounded-md bg-brand-500 hover:bg-brand-600 px-2.5 py-1 text-xs font-semibold text-white shadow-2xs transition-colors cursor-pointer"
                                aria-label={`Move ${row.applicantName} to Plantilla`}
                                title="Deploy candidate to Plantilla"
                              >
                                <ArrowRight className="h-3.5 w-3.5" />
                                <span>Move to Plantilla</span>
                              </button>
                            )}
                          </>
                        )}

                        {/* Status / capability indicators */}
                        {isPendingDeletion && (
                          <span title="Record Locked: Pending Deletion">
                            <LockKeyhole className="h-3.5 w-3.5 text-status-danger-text" />
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

      {/* Pagination Footer (Default 10 with Selector) */}
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
