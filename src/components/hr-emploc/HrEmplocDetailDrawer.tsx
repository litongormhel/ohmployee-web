// components/hr-emploc/HrEmplocDetailDrawer.tsx
"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  AlertCircle,
  AlertTriangle,
  Calendar,
  CheckCircle2,
  FileDown,
  FileText,
  History,
  Loader2,
  Lock,
  MapPin,
  RefreshCw,
  ShieldAlert,
  Trash2,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { InheritedHrcoBadge } from "@/components/hr-emploc/useInheritedHrco";
import {
  getWebHrEmplocDetail,
  useWithdrawEmplocDeletion,
  useRequestEmplocDeletion,
  getCorrectionAttachmentSignedUrl,
  HrEmplocDataError,
  type HrEmplocDetailItem,
  type HrEmplocAuditLogItem,
} from "@/lib/queries/hr_emploc";
import { useCurrentUser } from "@/lib/auth";
import { normalizeRole, AppRole, hasFullAccess } from "@/lib/rbac";

export type HrEmplocDetailDrawerProps = {
  hrEmplocId: string | null;
  onClose: () => void;
};

function formatDate(value: string | null) {
  if (!value) return "--";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "2-digit",
    year: "numeric",
  }).format(date);
}

function formatDateTime(value: string | null) {
  if (!value) return "--";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function formatBytes(bytes?: number) {
  if (bytes === undefined) return "";
  if (bytes === 0) return "0 Bytes";
  const k = 1024;
  const sizes = ["Bytes", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
}

function getErrorKind(error: unknown) {
  return error instanceof HrEmplocDataError ? error.kind : "retryable";
}

/**
 * Formats timeline log items into specific, human-readable events detailing
 * what happened, where, why, and by whom.
 */
function formatTimelineItem(item: HrEmplocAuditLogItem, detail: HrEmplocDetailItem) {
  const label = (item.eventLabel || "").toLowerCase();
  const desc = item.eventDescription || "";
  const actor = item.profileName || "System Operator";

  // If already detailed from RPC or custom log, retain it
  if (
    desc.includes("Added to HR Emploc Queue") ||
    desc.includes("Assigned HRCO") ||
    desc.includes("Flagged for Correction") ||
    desc.includes("Assigned Employee ID") ||
    desc.includes("Updated Employee ID") ||
    desc.includes("Reverted from Deployed") ||
    desc.includes("Requested Deletion") ||
    desc.includes("Withdrew Deletion Request")
  ) {
    return {
      title: item.eventLabel,
      description: desc,
    };
  }

  // Creation / Endorsement
  if (
    label.includes("created") ||
    label.includes("record created") ||
    label.includes("endorsed") ||
    label.includes("placement confirmed")
  ) {
    return {
      title: "Queue Endorsement",
      description: `Added to HR Emploc Queue (${detail.positionTitle || "Position"} – ${detail.storeName || "Store"}) from Vacancy ${detail.vcode} by ${actor}`,
    };
  }

  // HRCO Assignment
  if (label.includes("hrco") || desc.toLowerCase().includes("assigned hrco")) {
    return {
      title: "HRCO Assignment",
      description: `Assigned HRCO ${detail.hrcoName || "Coordinator"} via ${detail.groupName || "Group"} (${detail.accountName || "Account"}) matrix`,
    };
  }

  // Flagged for Correction
  if (label.includes("correction") || label.includes("deficiency")) {
    const reasonText = detail.hrRemarks || desc || "Compliance Deficiency";
    return {
      title: "Flagged for Correction",
      description: `Flagged for Correction (${reasonText}) — Moved to Correction by ${actor}`,
    };
  }

  // Emploc & Deployment
  if (
    label.includes("deployed") ||
    label.includes("plantilla") ||
    label.includes("employee no") ||
    label.includes("employee id")
  ) {
    return {
      title: "Emploc & Deployment",
      description: `Assigned Employee ID ${detail.employeeNo || "--"} and deployed to Plantilla (${detail.storeName || "Store"}) by ${actor}`,
    };
  }

  // Edit Employee ID
  if (label.includes("edit") || desc.toLowerCase().includes("updated employee id")) {
    return {
      title: "Employee ID Updated",
      description: desc || `Updated Employee ID by ${actor}`,
    };
  }

  // Revert to Pending
  if (label.includes("revert") || desc.toLowerCase().includes("reverted from deployed")) {
    return {
      title: "Reverted to Pending",
      description: desc || `Reverted from Deployed to Pending and removed from Plantilla by ${actor}`,
    };
  }

  // Deletion Request
  if (label.includes("deletion request") || label.includes("requested deletion")) {
    return {
      title: "Deletion Requested",
      description:
        desc ||
        `Requested Deletion (Reason: ${detail.activeDeletionRequest?.reason || "Separation"}) by ${actor}`,
    };
  }

  // Withdrawal
  if (label.includes("withdraw")) {
    return {
      title: "Deletion Request Withdrawn",
      description:
        desc || `Withdrew Deletion Request and restored to Pending Emploc by ${actor}`,
    };
  }

  return {
    title: item.eventLabel,
    description: desc || `Action recorded by ${actor}`,
  };
}

export function HrEmplocDetailDrawer({
  hrEmplocId,
  onClose,
}: HrEmplocDetailDrawerProps) {
  const queryClient = useQueryClient();
  const currentUser = useCurrentUser();

  // Inline deletion form state (Available Actions)
  const [isRequestingDeletion, setIsRequestingDeletion] = useState(false);
  const [deletionReasonOption, setDeletionReasonOption] = useState<string>("Applicant Backed Out");
  const [deletionRemarks, setDeletionRemarks] = useState("");
  const [originalRecordUuid, setOriginalRecordUuid] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);

  const withdrawMutation = useWithdrawEmplocDeletion();
  const requestDeletionMutation = useRequestEmplocDeletion();

  const {
    data: detail,
    isLoading,
    isError,
    error,
    refetch,
  } = useQuery({
    queryKey: ["hr-emploc-detail", hrEmplocId],
    queryFn: () => getWebHrEmplocDetail(hrEmplocId!),
    enabled: !!hrEmplocId,
    retry: false,
  });

  if (!hrEmplocId) return null;

  const errorKind = isError ? getErrorKind(error) : null;

  const isPendingDeletion = Boolean(
    detail &&
      (detail.hrStatus.toLowerCase().trim() === "pending deletion" ||
        detail.hrStatus.toLowerCase().trim() === "pending_deletion" ||
        detail.deploymentStatus.toLowerCase().includes("deletion") ||
        detail.activeDeletionRequest)
  );

  const isDeployed = Boolean(
    detail &&
      (detail.deploymentStatus.toLowerCase().includes("deployed") ||
        detail.hrStatus.toLowerCase() === "transferred" ||
        detail.hrStatus.toLowerCase() === "moved to plantilla" ||
        Boolean(detail.employeeNo))
  );

  // RBAC for Available Actions: Only Ops (OM - HRCO) and Super Admin
  const userRole = normalizeRole(currentUser?.roleName || currentUser?.roleKey);
  const isSuperAdmin =
    hasFullAccess(currentUser) ||
    userRole === AppRole.SUPER_ADMIN ||
    userRole === AppRole.HEAD_ADMIN;
  const isOpsRole = userRole === AppRole.OM || userRole === AppRole.HRCO;
  const canManageDeletion = isSuperAdmin || isOpsRole;

  const handleOpenAttachment = async (pathOrUrl: string) => {
    try {
      const url = await getCorrectionAttachmentSignedUrl(pathOrUrl);
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (err) {
      console.error("Failed to open attachment:", err);
      window.open(pathOrUrl, "_blank", "noopener,noreferrer");
    }
  };

  const handleConfirmDeletionRequest = async () => {
    if (!detail) return;
    setActionError(null);

    const trimmedRemarks = deletionRemarks.trim();
    if (!trimmedRemarks) {
      setActionError("Please provide specific remarks or justification for the deletion request.");
      return;
    }

    const isDuplicate = deletionReasonOption.toLowerCase().includes("duplicate");
    if (isDuplicate && !originalRecordUuid.trim()) {
      setActionError("Please provide the original/master record UUID for duplicate separation.");
      return;
    }

    const fullReason = `${deletionReasonOption}: ${trimmedRemarks}`;
    const deletionType = isDuplicate ? "duplicate" : "backout";

    requestDeletionMutation.mutate(
      {
        hrEmplocId: detail.id,
        reason: fullReason,
        deletionType,
        originalEmplocId: isDuplicate ? originalRecordUuid.trim() : null,
      },
      {
        onSuccess: () => {
          setIsRequestingDeletion(false);
          setDeletionRemarks("");
          setOriginalRecordUuid("");
          queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", hrEmplocId] });
          queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
          queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
          refetch();
        },
        onError: (err) => {
          setActionError(err instanceof Error ? err.message : "Failed to submit deletion request.");
        },
      }
    );
  };

  const handleWithdrawDeletionRequest = async () => {
    if (!detail?.activeDeletionRequest?.requestId) return;
    if (!window.confirm("Withdraw deletion request and restore record to Pending Emploc?")) {
      return;
    }
    setActionError(null);

    withdrawMutation.mutate(
      {
        requestId: detail.activeDeletionRequest.requestId,
        reason: "Withdrawn by operator from Available Actions drawer",
      },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", hrEmplocId] });
          queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
          queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
          refetch();
        },
        onError: (err) => {
          setActionError(err instanceof Error ? err.message : "Failed to withdraw request.");
        },
      }
    );
  };

  return (
    <DetailDrawer
      isOpen={!!hrEmplocId}
      onClose={onClose}
      widthClass="w-[var(--drawer-width-lg)] max-w-full"
      /* Section 1: Drawer Header (VCode badge, Applicant Full Name, 📍 Account / Store) */
      badge={
        isLoading ? (
          <div className="h-5 w-24 animate-pulse rounded bg-surface-muted" />
        ) : detail ? (
          <Badge className="font-mono text-xs font-semibold bg-surface border border-border-default text-text-primary py-1 px-2.5">
            {detail.vcode}
          </Badge>
        ) : (
          <Badge className="bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)]">
            Error
          </Badge>
        )
      }
      title={
        isLoading ? (
          <div className="h-6 w-48 animate-pulse rounded bg-surface-muted mt-1" />
        ) : detail ? (
          <span className={isPendingDeletion ? "text-text-muted line-through" : ""}>
            {detail.applicantName}
          </span>
        ) : (
          "Compliance Placement Detail"
        )
      }
      subtitle={
        !isLoading && detail && (
          <>
            <MapPin className="h-3 w-3 shrink-0 text-text-muted" />
            <span className="truncate">
              {[detail.accountName, detail.storeName].filter(Boolean).join(" / ") ||
                "Global Account"}
            </span>
          </>
        )
      }
    >
      {isLoading ? (
        <LoadingSkeleton />
      ) : errorKind === "access_denied" ? (
        <AccessDeniedState />
      ) : isError ? (
        <ErrorState
          errorMsg={error instanceof Error ? error.message : "RPC fetch failure"}
          onRetry={refetch}
        />
      ) : !detail ? (
        <NotFoundState />
      ) : (
        <div className="space-y-4">
          {/* Section 2: Status Summary Cards (2-Column Grid) */}
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-md border border-border-subtle bg-surface-muted p-2.5">
              <div className="text-xs font-medium text-text-muted">Deployment status</div>
              <div className="mt-1 flex items-center gap-1.5">
                <span className="text-xs font-semibold text-text-primary bg-surface border border-border-default rounded px-2 py-0.5">
                  {isPendingDeletion
                    ? "Deletion Requested"
                    : isDeployed
                    ? "Deployed to Plantilla"
                    : detail.deploymentStatus || "Pending Emploc"}
                </span>
              </div>
            </div>

            <div className="rounded-md border border-border-subtle bg-surface-muted p-2.5">
              <div className="text-xs font-medium text-text-muted">HR status</div>
              <div className="mt-1">
                <StatusBadge
                  variant={
                    isDeployed || detail.hrStatus.toLowerCase().includes("complete")
                      ? "success"
                      : detail.hrStatus.toLowerCase().includes("correction")
                      ? "warning"
                      : isPendingDeletion
                      ? "danger"
                      : "info"
                  }
                  className="font-semibold"
                >
                  {isDeployed ? "Deployed" : detail.hrStatus}
                </StatusBadge>
              </div>
            </div>
          </div>

          {/* Section 3: Placement Parameters Card */}
          <div className="rounded-md border border-border-subtle p-4 space-y-3 bg-surface">
            <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider">
              Placement Parameters
            </h3>
            <div className="grid grid-cols-2 gap-y-3 text-sm">
              <div>
                <div className="text-xs text-text-muted">Vacancy Code (VCode)</div>
                <div className="mt-0.5 font-mono font-medium text-text-primary">
                  {detail.vcode || "--"}
                </div>
              </div>
              <div>
                <div className="text-xs text-text-muted">Account</div>
                <div className="mt-0.5 font-medium text-text-primary">
                  {detail.accountName || "--"}
                </div>
              </div>
              <div>
                <div className="text-xs text-text-muted">Store / Location</div>
                <div className="mt-0.5 font-medium text-text-primary">
                  {detail.storeName || "--"}
                </div>
              </div>
              <div>
                <div className="text-xs text-text-muted">Assignment Type</div>
                <div className="mt-0.5 font-medium text-text-primary">
                  {detail.assignmentType ?? "Stationary"}
                </div>
              </div>
              <div>
                <div className="text-xs text-text-muted">Position Title</div>
                <div className="mt-0.5 font-medium text-text-primary">
                  {detail.positionTitle ?? "--"}
                </div>
              </div>
              <div>
                <div className="text-xs text-text-muted">HRCO Coordinator</div>
                <div className="mt-0.5">
                  <InheritedHrcoBadge
                    accountId={detail.accountId}
                    groupId={detail.groupId}
                    fallbackName={detail.hrcoName}
                  />
                </div>
              </div>
              <div>
                <div className="text-xs text-text-muted">Hired Date</div>
                <div className="mt-0.5 font-medium text-text-primary flex items-center gap-1">
                  <Calendar className="h-3.5 w-3.5 text-text-muted" />
                  <span>{formatDate(detail.hiredDate)}</span>
                </div>
              </div>
              {detail.employeeNo && (
                <div>
                  <div className="text-xs text-text-muted">Employee ID</div>
                  <div className="mt-0.5">
                    <Badge className="font-mono text-xs bg-surface border border-border-default text-text-primary font-bold">
                      {detail.employeeNo}
                    </Badge>
                  </div>
                </div>
              )}
            </div>

            {/* Roving Covered Stores list */}
            {detail.assignmentType === "Roving" &&
              detail.coveredStores &&
              detail.coveredStores.length > 0 && (
                <div className="mt-3 border-t border-border-subtle pt-3">
                  <div className="text-xs text-text-muted mb-1.5">Roving Covered Stores</div>
                  <div className="grid gap-1.5">
                    {detail.coveredStores.map((store, storeIdx) => (
                      <div
                        key={store.storeId || `store-${storeIdx}`}
                        className="text-xs bg-surface-muted border border-border-subtle rounded p-2 flex items-start gap-2"
                      >
                        <MapPin className="h-3.5 w-3.5 text-brand-primary shrink-0 mt-0.5" />
                        <div>
                          <div className="font-semibold text-text-primary">{store.storeName}</div>
                          {store.address && (
                            <div className="text-[10px] text-text-muted">{store.address}</div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
          </div>

          {/* Section 4: SLA & Aging Performance Card */}
          <div className="rounded-md border border-border-subtle p-4 space-y-3 bg-surface">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider">
                SLA & Aging Performance
              </h3>
              {isDeployed ? (
                <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
                  <CheckCircle2 className="h-3 w-3" />
                  SLA Closed
                </span>
              ) : detail.slaBreached ? (
                <StatusBadge variant="neutral" className="font-semibold text-[10px]">
                  SLA Breached
                </StatusBadge>
              ) : null}
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="text-sm">
                <div className="text-xs text-text-muted">Elapsed Compliance Time</div>
                <div className="mt-0.5 text-base font-bold text-text-primary">
                  {isDeployed
                    ? `Completed in ${detail.slaElapsedDays} days`
                    : `${detail.slaElapsedDays} Days`}
                </div>
              </div>
              <div className="text-sm">
                <div className="text-xs text-text-muted">Baseline Request Date</div>
                <div className="mt-0.5 font-medium text-text-primary">
                  {formatDate(detail.dateRequested)}
                </div>
              </div>
            </div>

            {/* SLA Escalation Levels Alerts (Only active while in progress) */}
            {!isDeployed && (
              <>
                {detail.slaElapsedDays >= 5 ? (
                  <div className="rounded border border-border-default bg-surface-muted p-3 text-xs text-text-primary flex items-start gap-2">
                    <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-text-muted" />
                    <div>
                      <span className="font-bold">SLA Escalation Tier 2:</span> This record has
                      languished for <span className="font-bold">{detail.slaElapsedDays} days</span>.
                      Escalated to the <span className="font-semibold">Super Admin</span>.
                    </div>
                  </div>
                ) : detail.slaElapsedDays >= 3 ? (
                  <div className="rounded border border-border-default bg-surface-muted p-3 text-xs text-text-primary flex items-start gap-2">
                    <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-text-muted" />
                    <div>
                      <span className="font-bold">SLA Escalation Tier 1:</span> Compliance audit is
                      pending past the <span className="font-bold">3-day SLA threshold</span>.
                    </div>
                  </div>
                ) : null}
              </>
            )}
          </div>

          {/* Section 6: Correction Submissions & Attachments Card (Section 5 removed) */}
          <div className="rounded-md border border-border-subtle p-4 space-y-3 bg-surface">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider">
                Correction Submissions & Attachments
              </h3>
              <Badge className="bg-surface-muted text-text-muted border border-border-subtle text-[10px]">
                {detail.uploadedAttachments.length} Files
              </Badge>
            </div>

            {/* Remarks if any */}
            {(detail.hrRemarks || detail.opsRemarks) && (
              <div className="space-y-2 border-b border-border-subtle pb-3">
                {detail.hrRemarks && (
                  <div>
                    <div className="text-[10px] font-semibold text-text-muted">
                      HR Compliance Remarks
                    </div>
                    <p className="mt-1 text-xs text-text-primary leading-relaxed bg-surface-muted p-2 rounded border border-border-subtle italic">
                      &quot;{detail.hrRemarks}&quot;
                    </p>
                  </div>
                )}
                {detail.opsRemarks && (
                  <div>
                    <div className="text-[10px] font-semibold text-text-muted">
                      Ops Coordinator Remarks
                    </div>
                    <p className="mt-1 text-xs text-text-primary leading-relaxed bg-surface-muted p-2 rounded border border-border-subtle italic">
                      &quot;{detail.opsRemarks}&quot;
                    </p>
                  </div>
                )}
              </div>
            )}

            {detail.uploadedAttachments.length > 0 ? (
              <div className="space-y-2">
                {detail.uploadedAttachments.map((file, fileIdx) => (
                  <div
                    key={file.attachmentId || `attachment-${fileIdx}`}
                    className="flex items-center justify-between rounded-md border border-border-subtle bg-surface-muted p-2.5 hover:bg-surface transition"
                  >
                    <div className="flex items-center gap-2.5 min-w-0">
                      <div className="p-1.5 bg-surface rounded border border-border-subtle text-brand-primary">
                        <FileText className="h-4 w-4" />
                      </div>
                      <div className="min-w-0">
                        <button
                          type="button"
                          className="text-xs font-semibold text-brand-primary hover:underline truncate block text-left cursor-pointer"
                          onClick={() => handleOpenAttachment(file.fileUrl)}
                        >
                          {file.fileName}
                        </button>
                        <div className="text-[10px] text-text-muted flex flex-wrap gap-x-2">
                          <span>By: {file.uploadedBy}</span>
                          <span>•</span>
                          <span>{formatDate(file.uploadedAt)}</span>
                          {file.fileSize && (
                            <>
                              <span>•</span>
                              <span>{formatBytes(file.fileSize)}</span>
                            </>
                          )}
                        </div>
                      </div>
                    </div>
                    <button
                      type="button"
                      aria-label={`Download file ${file.fileName}`}
                      className="inline-flex h-7 w-7 items-center justify-center rounded border border-border-default bg-surface text-text-muted hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
                      onClick={() => handleOpenAttachment(file.fileUrl)}
                    >
                      <FileDown className="h-4 w-4" />
                    </button>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-center py-4 border border-dashed border-border-subtle rounded-md text-xs text-text-muted">
                No correction compliance files uploaded.
              </div>
            )}
          </div>

          {/* Section 7: Specific Activity History Trail Card */}
          <div className="rounded-md border border-border-subtle p-4 space-y-3 bg-surface">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-text-muted uppercase tracking-wider">
              <History className="h-4 w-4 text-text-muted" />
              <span>Activity History Trail</span>
            </div>
            <div className="relative pl-4 space-y-4 border-l-2 border-border-subtle ml-1.5 mt-2">
              {detail.auditLogsTimeline && detail.auditLogsTimeline.length > 0 ? (
                detail.auditLogsTimeline.map((item, timelineIdx) => {
                  const formatted = formatTimelineItem(item, detail);
                  return (
                    <div
                      key={item.eventId || `timeline-${timelineIdx}`}
                      className="relative text-xs"
                    >
                      <div className="absolute -left-[21px] top-0.5 h-2.5 w-2.5 rounded-full border-2 border-surface bg-brand-primary" />
                      <div className="flex justify-between items-baseline">
                        <span className="font-semibold text-text-primary">
                          {formatted.title}
                        </span>
                        <span className="text-[10px] text-text-muted font-mono">
                          {formatDateTime(item.createdAt)}
                        </span>
                      </div>
                      <p className="mt-0.5 text-text-secondary leading-relaxed">
                        {formatted.description}
                      </p>
                    </div>
                  );
                })
              ) : (
                <div className="relative text-xs">
                  <div className="absolute -left-[21px] top-0.5 h-2.5 w-2.5 rounded-full border-2 border-surface bg-brand-primary" />
                  <div className="flex justify-between">
                    <span className="font-semibold text-text-primary">Queue Endorsement</span>
                    <span className="text-[10px] text-text-muted">
                      {formatDate(detail.dateRequested)}
                    </span>
                  </div>
                  <p className="mt-0.5 text-text-secondary">
                    Added to HR Emploc Queue ({detail.positionTitle || "Position"} –{" "}
                    {detail.storeName || "Store"}) from Vacancy {detail.vcode}
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Section 8: Available Actions Card (Human-Readable & Scoped to Deletion Flow) */}
          <div className="rounded-md border border-border-subtle p-4 space-y-3 bg-surface">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-semibold text-text-primary uppercase tracking-wider">
                Available Actions
              </h3>
            </div>

            {/* Error banner */}
            {actionError && (
              <div className="rounded border border-danger-border bg-danger-bg p-2.5 text-xs text-danger-text flex items-start gap-2">
                <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
                <span>{actionError}</span>
              </div>
            )}

            {/* 1. Role Restriction Check: Restricted to Ops (OM - HRCO) and Super Admin */}
            {!canManageDeletion ? (
              <div className="rounded-md border border-border-default bg-surface-muted p-3 text-xs text-text-muted flex items-center gap-2">
                <Lock className="h-4 w-4 shrink-0 text-text-muted" />
                <span>Restricted to Ops (OM - HRCO) personnel.</span>
              </div>
            ) : isDeployed ? (
              /* 2. Guardrail: If record is in Deployed tab, lock Request Deletion */
              <div className="rounded-md border border-border-default bg-surface-muted p-3 text-xs text-text-muted flex items-start gap-2">
                <Lock className="h-4 w-4 shrink-0 mt-0.5 text-text-muted" />
                <div>
                  <span className="font-semibold text-text-primary">Record is Deployed</span>
                  <p className="mt-0.5 text-[11px] text-text-muted leading-relaxed">
                    Deletion request is locked while candidate is deployed. To request deletion,
                    first revert the record to Pending using <strong>Edit Emploc &gt; Revert to Pending</strong> in the Deployed tab.
                  </p>
                </div>
              </div>
            ) : isPendingDeletion ? (
              /* 3. State B: Pending Deletion Request exists -> Show banner & Withdraw button */
              <div className="rounded-md border border-amber-300 bg-amber-50 dark:border-amber-900/50 dark:bg-amber-950/20 p-3.5 space-y-3 text-xs text-amber-900 dark:text-amber-200">
                <div className="flex items-start gap-2.5">
                  <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5 text-amber-600 dark:text-amber-400" />
                  <div className="space-y-1">
                    <span className="font-semibold block text-xs">
                      Active Deletion Request: {detail.activeDeletionRequest?.reason || "Placement separation requested"}
                    </span>
                    <span className="text-[11px] block text-amber-800 dark:text-amber-300">
                      Submitted by {detail.activeDeletionRequest?.requestedBy || "Operations"} on{" "}
                      {formatDate(detail.activeDeletionRequest?.requestedAt || null)}
                    </span>
                  </div>
                </div>

                <div className="pt-1">
                  <button
                    type="button"
                    disabled={withdrawMutation.isPending}
                    onClick={handleWithdrawDeletionRequest}
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-surface border border-border-default rounded-md text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer shadow-2xs disabled:opacity-50"
                  >
                    {withdrawMutation.isPending && (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    )}
                    <span>
                      {withdrawMutation.isPending ? "Withdrawing..." : "Withdraw Request"}
                    </span>
                  </button>
                </div>
              </div>
            ) : !isRequestingDeletion ? (
              /* 4. State A: No active request, not requesting -> Request Deletion Button */
              <div>
                <button
                  type="button"
                  onClick={() => {
                    setActionError(null);
                    setIsRequestingDeletion(true);
                  }}
                  className="inline-flex items-center gap-1.5 rounded-md border border-danger-border bg-surface px-3 py-1.5 text-xs font-semibold text-danger-text hover:bg-danger-bg transition cursor-pointer shadow-2xs"
                >
                  <Trash2 className="h-3.5 w-3.5 text-danger-text" />
                  <span>Request Deletion</span>
                </button>
              </div>
            ) : (
              /* 5. State A (Expanded): Inline deletion request form */
              <div className="rounded-md border border-border-default bg-surface-muted p-3.5 space-y-3 text-xs">
                <div className="flex items-center justify-between border-b border-border-subtle pb-2">
                  <span className="font-semibold text-text-primary">
                    Request Placement Deletion
                  </span>
                  <button
                    type="button"
                    onClick={() => {
                      setIsRequestingDeletion(false);
                      setActionError(null);
                    }}
                    className="text-text-muted hover:text-text-primary text-xs cursor-pointer"
                  >
                    Cancel
                  </button>
                </div>

                {/* Reason Dropdown */}
                <div className="space-y-1">
                  <label className="block text-[11px] font-semibold text-text-muted">
                    Reason for Deletion <span className="text-danger-text">*</span>
                  </label>
                  <select
                    className="w-full h-8 rounded-md border border-border-default bg-surface px-2.5 text-xs text-text-primary outline-none focus:border-brand-500 cursor-pointer"
                    value={deletionReasonOption}
                    onChange={(e) => setDeletionReasonOption(e.target.value)}
                    disabled={requestDeletionMutation.isPending}
                  >
                    <option value="Applicant Backed Out">Applicant Backed Out</option>
                    <option value="Duplicate / Wrong Endorsement">
                      Duplicate / Wrong Endorsement
                    </option>
                    <option value="Failed Store Deployment">Failed Store Deployment</option>
                  </select>
                </div>

                {/* Optional Original Record UUID for Duplicate */}
                {deletionReasonOption.includes("Duplicate") && (
                  <div className="space-y-1">
                    <label className="block text-[11px] font-semibold text-text-muted">
                      Original / Master Record ID <span className="text-danger-text">*</span>
                    </label>
                    <input
                      type="text"
                      className="w-full h-8 rounded-md border border-border-default bg-surface px-2.5 text-xs font-mono text-text-primary outline-none focus:border-brand-500 placeholder:text-text-muted"
                      placeholder="e.g. 550e8400-e29b-41d4-a716-446655440000"
                      value={originalRecordUuid}
                      onChange={(e) => setOriginalRecordUuid(e.target.value)}
                      disabled={requestDeletionMutation.isPending}
                    />
                  </div>
                )}

                {/* Specific Remarks / Justification */}
                <div className="space-y-1">
                  <label className="block text-[11px] font-semibold text-text-muted">
                    Specific Remarks / Justification <span className="text-danger-text">*</span>
                  </label>
                  <textarea
                    rows={2}
                    className="w-full rounded-md border border-border-default bg-surface px-2.5 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500 resize-none placeholder:text-text-muted"
                    placeholder="Provide specific operational reason for separation..."
                    value={deletionRemarks}
                    onChange={(e) => setDeletionRemarks(e.target.value)}
                    disabled={requestDeletionMutation.isPending}
                  />
                </div>

                {/* Actions */}
                <div className="flex items-center justify-end gap-2 pt-1 border-t border-border-subtle">
                  <button
                    type="button"
                    onClick={() => {
                      setIsRequestingDeletion(false);
                      setActionError(null);
                    }}
                    disabled={requestDeletionMutation.isPending}
                    className="px-3 py-1.5 rounded-md border border-border-default bg-surface text-xs font-medium text-text-primary hover:bg-surface-hover transition cursor-pointer"
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    onClick={handleConfirmDeletionRequest}
                    disabled={requestDeletionMutation.isPending}
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-danger-text text-white text-xs font-semibold hover:opacity-90 transition cursor-pointer disabled:opacity-50 shadow-2xs"
                  >
                    {requestDeletionMutation.isPending && (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    )}
                    <span>
                      {requestDeletionMutation.isPending
                        ? "Submitting..."
                        : "Confirm & Submit Request"}
                    </span>
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </DetailDrawer>
  );
}

// ─── State sub-components ─────────────────────────────────────────────────────

function LoadingSkeleton() {
  return (
    <div className="space-y-4 animate-pulse">
      <div className="grid grid-cols-2 gap-3">
        <div className="h-14 rounded-md bg-surface-muted" />
        <div className="h-14 rounded-md bg-surface-muted" />
      </div>
      <div className="h-28 rounded-md bg-surface-muted" />
      <div className="h-20 rounded-md bg-surface-muted" />
      <div className="h-32 rounded-md bg-surface-muted" />
      <div className="h-32 rounded-md bg-surface-muted" />
    </div>
  );
}

function AccessDeniedState() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <div className="rounded-full bg-[var(--danger-bg)] p-3 text-[var(--danger-text)] border border-[var(--danger-border)] shadow-xs">
        <ShieldAlert className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-bold text-text-primary">Compliance Access Denied</h4>
      <p className="mt-1 text-xs text-text-muted max-w-xs leading-relaxed">
        Supabase RLS policies blocked this specific detail read. You are not authorized to view
        candidates outside your assigned scopes.
      </p>
    </div>
  );
}

function NotFoundState() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <div className="rounded-full bg-surface-muted p-3 text-text-muted border border-border-default shadow-xs">
        <AlertCircle className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-bold text-text-primary">Record Not Found</h4>
      <p className="mt-1 text-xs text-text-muted max-w-xs leading-relaxed">
        The selected allocation could not be found. It may have been archived, rejected, or moved.
      </p>
    </div>
  );
}

type ErrorStateProps = {
  errorMsg: string;
  onRetry: () => void;
};

function ErrorState({ errorMsg, onRetry }: ErrorStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <div className="rounded-full bg-[var(--danger-bg)] p-3 text-[var(--danger-text)] border border-[var(--danger-border)] shadow-xs">
        <AlertCircle className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-bold text-text-primary">Fetch Failed</h4>
      <p className="mt-1 text-xs text-text-muted max-w-xs leading-relaxed">{errorMsg}</p>
      <button
        className="mt-4 inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-primary shadow-xs hover:bg-surface-hover transition cursor-pointer"
        onClick={onRetry}
        type="button"
      >
        <RefreshCw className="h-3 w-3" />
        Retry Query
      </button>
    </div>
  );
}
