// components/vacancy/VacancyDetailDrawer.tsx
"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { fetchTeamDirectory } from "@/lib/queries/team_directory";
import {
  AlertCircle,
  AlertTriangle,
  ArrowRightCircle,
  Building2,
  Calendar,
  CheckCheck,
  CheckCircle2,
  ClipboardList,
  Clock3,
  Edit3,
  FileText,
  History,
  Lock,
  MapPin,
  Phone,
  RefreshCw,
  RotateCcw,
  ShieldAlert,
  SlidersHorizontal,
  User,
  UserCheck,
  UserPlus,
  Users,
  XCircle,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  formatGroupName,
  getVacancyDetail,
  useUpdateEffectiveVacancyDate,
  useWithdrawVacancyClosureRequest,
  VacancyDataError,
} from "@/lib/queries/vacancy";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { CapabilityActionBar } from "@/components/shared/CapabilityActionBar";
import { StatusBadge } from "@/components/ui/StatusBadge";
import {
  formatPersonName,
  formatPosition,
  formatAccountName,
  formatStoreName,
  formatAgingBucket,
  formatVacancySource,
} from "@/lib/utils/displayText";
import { useCurrentUser } from "@/lib/auth";
import {
  AppRole,
  canAddApplicant,
  canEditApplicantProfile,
  canEditHiredDate,
  canReopenVacancySlot,
  canManageApplicantPipeline,
  canReviewVacancyClosures,
  canRequestVacancyClosure,
  canRequestHeadcountAdjustment,
  canReviseHeadcountQuota,
  hasFullAccess,
  isOpsTeam,
  normalizeRole,
} from "@/lib/rbac";
import { ReviseHeadcountQuotaModal } from "@/components/modals/ReviseHeadcountQuotaModal";
import { RequestHeadcountAdjustmentModal } from "@/components/modals/RequestHeadcountAdjustmentModal";
import { AddApplicantModal } from "@/components/vacancy/AddApplicantModal";
import { AdvancePipelineModal } from "@/components/vacancy/AdvancePipelineModal";
import { MarkHiredModal } from "@/components/vacancy/MarkHiredModal";
import { FailBackoutModal } from "@/components/vacancy/FailBackoutModal";
import { ReopenVacancyModal } from "@/components/vacancy/ReopenVacancyModal";
import { RequestVacancyClosureModal } from "@/components/vacancy/RequestVacancyClosureModal";
import { EditHiredDateModal } from "@/components/vacancy/EditHiredDateModal";
import {
  EditApplicantModal,
  type EditApplicantTarget,
} from "@/components/vacancy/EditApplicantModal";

type VacancyDetailDrawerProps = {
  vacancyId: string | null;
  onClose: () => void;
  isFreezeModeActive?: boolean;
  status?: string;
};

function formatDate(value: string | null) {
  if (!value) return "--";
  const parts = value.split("-");
  if (parts.length === 3 && parts[0].length === 4) {
    const year = parseInt(parts[0], 10);
    const monthIndex = parseInt(parts[1], 10) - 1;
    const day = parseInt(parts[2], 10);
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    if (monthIndex >= 0 && monthIndex < 12 && !Number.isNaN(day) && !Number.isNaN(year)) {
      return `${months[monthIndex]} ${day}, ${year}`;
    }
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(date);
}

function getErrorKind(error: unknown) {
  return error instanceof VacancyDataError ? error.kind : "retryable";
}

function CompactSection({
  icon: Icon,
  title,
  children,
}: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-lg border border-border-subtle bg-surface-base p-3 space-y-2">
      <div className="flex items-center gap-1.5 text-[11px] font-bold text-text-secondary">
        <Icon className="h-3.5 w-3.5 text-brand-600 shrink-0" />
        <span>{title}</span>
      </div>
      {children}
    </div>
  );
}

function formatActivityHistorySummary(item: {
  eventLabel?: string | null;
  eventDescription?: string | null;
  profileName?: string | null;
}): { title: string } {
  const action = (item.eventLabel || "").toUpperCase().trim();
  const rawModule = (item.eventDescription || "").toLowerCase().trim();

  // 1. Specific domain events
  if (action.includes("CLOSURE")) {
    if (action.includes("WITHDRAW")) {
      return { title: "Closure request withdrawn" };
    }
    if (action.includes("APPROV")) {
      return { title: "Vacancy closure approved" };
    }
    if (action.includes("REJECT")) {
      return { title: "Vacancy closure rejected" };
    }
    return { title: "Vacancy closure requested" };
  }

  if (action.includes("HEADCOUNT") || action.includes("QUOTA")) {
    if (action.includes("REVISE") || action.includes("OVERRIDE") || action.includes("UPDATE")) {
      return { title: "Headcount quota revised" };
    }
    if (action.includes("REQUEST")) {
      return { title: "Headcount adjustment requested" };
    }
    return { title: "Headcount allocation updated" };
  }

  // 2. Applicants & pipeline events
  if (rawModule.includes("applicant") || rawModule.includes("pipeline")) {
    if (action === "INSERT") {
      return { title: "Applicant added to recruitment pipeline" };
    }
    if (action === "UPDATE") {
      return { title: "Applicant pipeline stage updated" };
    }
    if (action === "DELETE") {
      return { title: "Applicant removed from pipeline" };
    }
    if (action.includes("HIRED") || action.includes("ONBOARD")) {
      return { title: "Candidate confirmed onboard and hired" };
    }
    if (action.includes("BACKOUT") || action.includes("FAILED") || action.includes("DROPOUT")) {
      return { title: "Candidate backout / dropout recorded" };
    }
  }

  // 3. Vacancy module events
  if (rawModule.includes("vacanc") || rawModule === "plantilla") {
    if (action === "INSERT") {
      return { title: "Vacancy created and opened for sourcing" };
    }
    if (action === "UPDATE") {
      return { title: "Vacancy requisition details updated" };
    }
    if (action === "DELETE") {
      return { title: "Vacancy requisition archived / removed" };
    }
    if (action === "APPROVAL" || action === "APPROVE") {
      return { title: "Vacancy requisition approved" };
    }
    if (action === "REJECT") {
      return { title: "Vacancy requisition rejected" };
    }
  }

  // 4. Canonical database action fallbacks
  switch (action) {
    case "INSERT":
      return { title: rawModule ? `New ${rawModule.replace(/[_-]/g, " ")} record created` : "Record created" };
    case "UPDATE":
      return { title: rawModule ? `${rawModule.replace(/[_-]/g, " ")} details updated` : "Details updated" };
    case "DELETE":
      return { title: rawModule ? `${rawModule.replace(/[_-]/g, " ")} record removed` : "Record removed" };
    case "APPROVAL":
    case "APPROVE":
      return { title: "Requisition approved" };
    case "REJECT":
    case "REJECTION":
      return { title: "Request rejected" };
    default:
      return {
        title: action ? action.replace(/_/g, " ").toLowerCase().replace(/^\w/, (c) => c.toUpperCase()) : "Activity logged",
      };
  }
}

export function VacancyDetailDrawer({ vacancyId, onClose, isFreezeModeActive = false, status }: VacancyDetailDrawerProps) {
  const [isReviseQuotaModalOpen, setIsReviseQuotaModalOpen] = useState(false);
  const [isRequestAdjustmentModalOpen, setIsRequestAdjustmentModalOpen] = useState(false);
  const [isAddApplicantModalOpen, setIsAddApplicantModalOpen] = useState(false);
  const [isAdvancePipelineModalOpen, setIsAdvancePipelineModalOpen] = useState(false);
  const [isMarkHiredModalOpen, setIsMarkHiredModalOpen] = useState(false);
  const [isFailBackoutModalOpen, setIsFailBackoutModalOpen] = useState(false);
  const [isReopenVacancyModalOpen, setIsReopenVacancyModalOpen] = useState(false);
  const [isRequestClosureModalOpen, setIsRequestClosureModalOpen] = useState(false);
  const [isEditHiredDateModalOpen, setIsEditHiredDateModalOpen] = useState(false);
  const [isEditApplicantModalOpen, setIsEditApplicantModalOpen] = useState(false);
  const [selectedCandidateForEdit, setSelectedCandidateForEdit] = useState<EditApplicantTarget | null>(null);
  const [selectedCandidate, setSelectedCandidate] = useState<{
    id: string;
    fullName: string;
    lastName?: string | null;
    firstName?: string | null;
    middleName?: string | null;
    contactNumber?: string | null;
    status: string;
    vcode: string;
    positionTitle?: string | null;
    hiredDate?: string | null;
  } | null>(null);

  const currentUser = useCurrentUser();
  const userRole = currentUser?.roleKey ?? currentUser?.roleName;
  const canReviseQuota = canReviseHeadcountQuota(currentUser);
  const canRequestAdjustment = canRequestHeadcountAdjustment(currentUser);
  const isUserFullAccess = hasFullAccess(currentUser);
  const userCanEditApplicant = canEditApplicantProfile(currentUser);
  const userIsOps = isOpsTeam(currentUser);
  const userCanAddApplicant = canAddApplicant(currentUser);
  const userCanManagePipeline = canManageApplicantPipeline(currentUser);
  const userCanReopenSlot = canReopenVacancySlot(currentUser);
  const userCanEditHiredDate = canEditHiredDate(currentUser);
  const userCanReviewClosures = canReviewVacancyClosures(currentUser);
  const userCanRequestClosure = canRequestVacancyClosure(currentUser);
  const isExemptFromClosureApplicantBlock = Boolean(
    isUserFullAccess ||
    userIsOps ||
    normalizeRole(userRole) === AppRole.RECRUITMENT
  );

  const withdrawClosureMutation = useWithdrawVacancyClosureRequest();
  const updateEffectiveVacancyDateMutation = useUpdateEffectiveVacancyDate();
  const [isEditingVacantDate, setIsEditingVacantDate] = useState(false);
  const [editedVacantDate, setEditedVacantDate] = useState("");
  const [editDateError, setEditDateError] = useState<string | null>(null);
  const canEditEffectiveVacancyDate = Boolean(
    isUserFullAccess || userIsOps || canReviseQuota || userCanManagePipeline
  );

  const {
    data: detail,
    isLoading,
    isError,
    error,
    refetch,
  } = useQuery({
    queryKey: ["vacancy-detail", vacancyId],
    queryFn: () => getVacancyDetail(vacancyId!),
    enabled: !!vacancyId,
    retry: false,
  });

  const { data: teamUsers } = useQuery({
    queryKey: ["vacancy-team-directory", detail?.accountId],
    queryFn: () => fetchTeamDirectory({ accountId: detail!.accountId! }),
    enabled: Boolean(detail?.accountId),
    staleTime: 60_000,
  });

  const leadership = useMemo(() => {
    const users = teamUsers ?? [];
    const om: string[] = [];
    const tl: string[] = [];
    const atl: string[] = [];

    for (const u of users) {
      const role = (u.roleName || "").toLowerCase().replace(/[^a-z0-9]/g, "");
      const name = u.displayName || (u.firstName && u.lastName ? `${u.firstName} ${u.lastName}` : null);
      if (!name) continue;

      if (role === "om" || role === "operationsmanager") {
        om.push(name);
      } else if (role === "tl" || role === "teamleader") {
        tl.push(name);
      } else if (role === "atl" || role === "assistantteamleader") {
        atl.push(name);
      }
    }

    const formatRoleNames = (list: string[], fallback?: string | null) => {
      const unique = Array.from(new Set(list));
      if (unique.length > 0) return unique.join(", ");
      return fallback || "Unassigned";
    };

    return {
      om: formatRoleNames(om, detail?.omName),
      tl: formatRoleNames(tl, detail?.tlName),
      atl: formatRoleNames(atl, detail?.atlName),
    };
  }, [teamUsers, detail?.omName, detail?.tlName, detail?.atlName]);

  if (!vacancyId) return null;

  const errorKind = isError ? getErrorKind(error) : null;

  const isPendingClosure = Boolean(
    detail?.hasPendingClosure ||
    detail?.closureRequestStatus?.toLowerCase() === "pending" ||
    detail?.derivedStatus === "For Closure"
  );

  const isHiredTab = Boolean(
    status === "hired" ||
    detail?.derivedStatus?.toLowerCase() === "hired" ||
    detail?.pipelineStatus?.toLowerCase() === "hired" ||
    detail?.vacancyStatus?.toLowerCase() === "filled"
  );

  const isHired = Boolean(
    isHiredTab ||
    (detail?.confirmedOnboardCount ?? 0) > 0
  );

  const hasActiveApplicants = Boolean(
    detail &&
    ((detail.activeApplicantCount ?? 0) > 0 ||
      (detail.activeApplicantsList && detail.activeApplicantsList.length > 0))
  );

  const isClosureBlockedByApplicants = hasActiveApplicants && !isExemptFromClosureApplicantBlock;

  const statusLabel = isPendingClosure
    ? "Pending Clearance"
    : detail?.derivedStatus ?? detail?.vacancyStatus ?? "--";

  const statusBadgeStyle = "border-border-default bg-surface-muted text-text-secondary";

  const urgencyVariant =
    detail?.urgencyLevel === "High"
      ? "danger"
      : detail?.urgencyLevel === "Medium"
      ? "warning"
      : "neutral";

  const hasPenalty = Boolean(
    detail &&
    (detail.hasPenalty ||
      (detail.penaltyAmount !== null && detail.penaltyAmount > 0) ||
      detail.penaltyExposure > 0)
  );

  const penaltyFormatted =
    detail && detail.penaltyAmount !== null && detail.penaltyAmount > 0
      ? `₱${detail.penaltyAmount.toLocaleString()}`
      : detail && detail.penaltyExposure > 0
      ? `₱${detail.penaltyExposure.toLocaleString()}`
      : null;

  const hasHeadcountContext = Boolean(
    detail &&
    (detail.headcountRequestId ||
      detail.vacancyReason ||
      detail.approvedByName ||
      detail.approvedAt ||
      detail.jobDescription)
  );

  const hasActivityLogs = Boolean(
    detail && detail.activityHistory && detail.activityHistory.length > 0
  );

  return (
    <DetailDrawer
      isOpen={!!vacancyId}
      onClose={onClose}
      contentClassName="p-3.5 space-y-2.5"
      footerClassName="px-4 py-2.5"
      badge={
        isLoading ? (
          <div className="h-5 w-24 animate-pulse rounded bg-surface-muted" />
        ) : detail ? (
          <div className="flex items-center gap-1.5 flex-wrap">
            <Badge className="font-mono text-xs font-semibold bg-surface-muted text-text-primary border border-border-default py-0.5 px-2">
              {detail.vcode}
            </Badge>
            <Badge className={`text-[11px] py-0 px-2 font-medium ${statusBadgeStyle}`}>
              {statusLabel}
            </Badge>
          </div>
        ) : (
          <Badge className="border border-border-default bg-surface-muted text-text-muted">Error</Badge>
        )
      }
      title={
        isLoading ? (
          <div className="h-6 w-48 animate-pulse rounded bg-surface-muted mt-1" />
        ) : detail ? (
          detail.position_title ? formatPosition(detail.position_title) : "Position Title"
        ) : (
          "Vacancy Detail"
        )
      }
      subtitle={
        !isLoading && detail && (
          <>
            <MapPin className="h-3 w-3 shrink-0 text-text-muted" />
            <span className="truncate">
              {[
                detail.accountName && detail.accountName !== "Unknown Account" ? formatAccountName(detail.accountName) : null,
                formatGroupName(detail.groupName, detail.accountName),
                detail.storeName ? formatStoreName(detail.storeName) : null,
              ]
                .filter(Boolean)
                .join(" / ") || "Global Account"}
            </span>
          </>
        )
      }
      footer={
        detail && !isHired ? (
          <CapabilityActionBar
            variant="toolbar"
            isReadOnlyEmergencyActive={isFreezeModeActive}
            actions={[
              {
                label: "Add Applicant",
                isAvailable:
                  userCanAddApplicant &&
                  !isPendingClosure &&
                  (detail.rowCapabilities?.canUpdateApplicantStatus === true ||
                    detail.derivedStatus?.toLowerCase() === "open" ||
                    detail.activeApplicantCount === 0),
                onClick: () => setIsAddApplicantModalOpen(true),
                icon: UserPlus,
                variant: "primary",
              },
              {
                label: "Reopen Slot",
                isAvailable:
                  userCanReopenSlot &&
                  !isPendingClosure &&
                  (detail.derivedStatus?.toLowerCase() === "failed_backout" ||
                    detail.derivedStatus?.toLowerCase() === "rejected" ||
                    detail.derivedStatus?.toLowerCase() === "backout" ||
                    detail.derivedStatus?.toLowerCase() === "closed"),
                onClick: () => setIsReopenVacancyModalOpen(true),
                icon: RotateCcw,
                variant: "primary",
              },
              {
                label: "Approve Vacancy",
                isAvailable:
                  userCanReviewClosures &&
                  !isPendingClosure &&
                  detail.rowCapabilities?.canApprove === true,
                icon: CheckCheck,
                variant: "success",
              },
              {
                label: "Edit Hired Date",
                isAvailable:
                  userCanEditHiredDate &&
                  !isPendingClosure &&
                  Boolean(detail.activeApplicantsList?.[0] || detail.applicantName) &&
                  (detail.derivedStatus?.toLowerCase() === "hired" || detail.confirmedOnboardCount > 0),
                onClick: () => {
                  if (detail.activeApplicantsList?.[0]) {
                    setSelectedCandidate({
                      id: detail.activeApplicantsList[0].applicantId,
                      fullName: detail.activeApplicantsList[0].displayName,
                      lastName: detail.activeApplicantsList[0].lastName,
                      firstName: detail.activeApplicantsList[0].firstName,
                      middleName: detail.activeApplicantsList[0].middleName,
                      contactNumber: detail.activeApplicantsList[0].contactNumber,
                      status: detail.activeApplicantsList[0].statusLabel,
                      vcode: detail.vcode,
                      positionTitle: detail.position_title,
                      hiredDate: detail.activeApplicantsList[0].onboardDate,
                    });
                  }
                  setIsEditHiredDateModalOpen(true);
                },
                icon: Calendar,
                variant: "secondary",
              },
            ]}
          />
        ) : undefined
      }
    >
          {isLoading ? (
            <LoadingSkeleton />
          ) : errorKind === "access_denied" ? (
            <AccessDeniedState />
          ) : isError ? (
            <ErrorState errorMsg={error instanceof Error ? error.message : "Unable to load vacancy details"} onRetry={refetch} />
          ) : !detail ? (
            <NotFoundState />
          ) : (
            <>
              {/* Pending Closure Clearance Notice */}
              {(detail.hasPendingClosure ||
                detail.closureRequestStatus?.toLowerCase() === "pending" ||
                detail.derivedStatus === "For Closure") && (
                <div className="rounded-md border border-border-default bg-surface-muted p-3 text-text-primary flex items-start gap-2.5">
                  <Clock3 className="h-4 w-4 shrink-0 mt-0.5 text-text-muted" />
                  <div className="text-xs space-y-1">
                    <div className="font-semibold flex items-center gap-1.5">
                      <span>Closure Clearance In-Flight</span>
                      {detail.closureRequestStatus && (
                        <span className="rounded-full bg-surface-base px-2 py-0.5 text-[10px] text-text-secondary border border-border-default">
                          {detail.closureRequestStatus}
                        </span>
                      )}
                    </div>
                    <div className="text-text-secondary leading-relaxed">
                      This vacancy slot has an active Store / Vacancy Closure request under review. Sourcing and pipeline transitions are paused pending management clearance.
                    </div>
                    {detail.closureReason && (
                      <div className="mt-1 font-medium text-text-primary">
                        Reason: {detail.closureReason}
                      </div>
                    )}
                    {detail.closureRequestedBy && (
                      <div className="text-[11px] text-text-muted">
                        Requested by {detail.closureRequestedBy}
                        {detail.closureRequestedAt && ` • ${new Date(detail.closureRequestedAt).toLocaleDateString()}`}
                      </div>
                    )}
                    {(isUserFullAccess || userIsOps || userCanRequestClosure) && (
                      <div className="pt-1.5">
                        <button
                          type="button"
                          disabled={withdrawClosureMutation.isPending}
                          onClick={async () => {
                            if (!detail?.vcode) return;
                            const confirmed = window.confirm(
                              `Are you sure you want to withdraw the pending closure request for ${detail.vcode}? This will restore normal sourcing and pipeline operations.`
                            );
                            if (!confirmed) return;
                            try {
                              await withdrawClosureMutation.mutateAsync({
                                vcode: detail.vcode,
                                userId: currentUser?.authUserId || currentUser?.profileId || null,
                              });
                              refetch();
                            } catch (err: unknown) {
                              alert(err instanceof Error ? err.message : "Failed to withdraw closure request");
                            }
                          }}
                          className="inline-flex items-center gap-1 rounded bg-surface-base hover:bg-surface-hover text-text-primary border border-border-default px-2 py-0.5 text-[11px] font-semibold transition cursor-pointer"
                        >
                          <RotateCcw className="h-3 w-3" />
                          <span>{withdrawClosureMutation.isPending ? "Withdrawing..." : "Withdraw Closure Request"}</span>
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Stores list resolution for single / stacked multi-store listing */}
              {(() => {
                const storesList: string[] = [];
                if (Array.isArray(detail.assignedStores) && detail.assignedStores.length > 0) {
                  for (const s of detail.assignedStores) {
                    const clean = s?.trim();
                    if (clean && !storesList.includes(clean)) {
                      storesList.push(clean);
                    }
                  }
                }
                if (detail.storeName) {
                  const parts = detail.storeName.includes(",")
                    ? detail.storeName.split(",").map((s) => s.trim()).filter(Boolean)
                    : [detail.storeName.trim()];
                  for (const p of parts) {
                    if (p && !storesList.includes(p)) {
                      storesList.push(p);
                    }
                  }
                }
                if (storesList.length === 0) {
                  const isPool =
                    detail.vcode?.includes("GHQ") ||
                    detail.accountName?.toLowerCase() === "moses hq" ||
                    detail.source === "pool";
                  if (isPool) {
                    storesList.push("Moses HQ");
                  }
                }

                const hiredCount = detail.confirmedOnboardCount ?? 0;
                const totalHc = detail.headcount ?? 1;
                const pipelineCount = detail.activeApplicantCount ?? 0;
                const availableSlots = Math.max(0, totalHc - hiredCount);
                const isHiredTab = status === "hired" || detail.derivedStatus?.toLowerCase() === "hired" || detail.vacancyStatus?.toLowerCase() === "filled";

                return (
                  <>
                    {/* 1. Combined Vacancy Summary & Assignment Section (2-Column Key-Value Grid) */}
                    <CompactSection icon={Building2} title="Vacancy & Assignment">
                      <div className="grid grid-cols-2 gap-x-3 gap-y-2 text-xs">
                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">VCode</span>
                          <span className="font-mono text-xs font-semibold text-text-primary block truncate">{detail.vcode}</span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">Urgency Level</span>
                          <div className="mt-0.5">
                            <StatusBadge variant={urgencyVariant} className="text-[11px] py-0 px-2 font-semibold">
                              {detail.urgencyLevel ?? "Normal"}
                            </StatusBadge>
                          </div>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">Source</span>
                          <span className="font-semibold text-text-primary block truncate">
                            {formatVacancySource(detail.source) || (detail.vcode.startsWith("CG-") ? "Coverage Group" : "Plantilla")}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">Vacancy Type</span>
                          <span className="font-semibold text-text-primary block truncate">
                            {detail.vacancyType || (detail.source === "Plantilla" ? "Replacement" : "New Demand")}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">Group</span>
                          <span className="font-semibold text-text-primary block truncate" title={formatGroupName(detail.groupName, detail.accountName) || "--"}>
                            {formatGroupName(detail.groupName, detail.accountName) || "--"}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">Account</span>
                          <span className="font-semibold text-text-primary block truncate" title={detail.accountName && detail.accountName !== "Unknown Account" ? formatAccountName(detail.accountName) : "--"}>
                            {detail.accountName && detail.accountName !== "Unknown Account" ? formatAccountName(detail.accountName) : "--"}
                          </span>
                        </div>
                        <div className={storesList.length > 1 ? "col-span-2" : ""}>
                          <span className="text-[10px] font-medium text-text-muted block">
                            {storesList.length > 1 ? `Assigned Stores (${storesList.length})` : "Store Name"}
                          </span>
                          {storesList.length > 1 ? (
                            <div className="mt-1 flex flex-wrap gap-1">
                              {storesList.map((st, i) => (
                                <span key={i} className="inline-flex rounded bg-surface-muted px-1.5 py-0.5 text-[11px] font-medium text-text-primary border border-border-subtle">
                                  {st}
                                </span>
                              ))}
                            </div>
                          ) : (
                            <span className="font-semibold text-text-primary block truncate" title={storesList[0] || "--"}>
                              {storesList[0] || "--"}
                            </span>
                          )}
                        </div>
                        <div className={storesList.length > 1 ? "col-span-2" : ""}>
                          <span className="text-[10px] font-medium text-text-muted block">Province / City</span>
                          <span className="font-semibold text-text-primary block truncate">
                            {[detail.areaProvince, detail.areaCity].filter(Boolean).join(" / ") || detail.storeLocation || "--"}
                          </span>
                        </div>
                        {detail.employmentType && (
                          <div className="col-span-2">
                            <span className="text-[10px] font-medium text-text-muted block">Employment Type</span>
                            <span className="font-semibold text-text-primary">
                              {detail.employmentType}
                            </span>
                          </div>
                        )}
                      </div>
                    </CompactSection>

                    {/* 2. Requirements & Headcount Section */}
                    <CompactSection icon={ClipboardList} title="Requirements & Headcount">
                      {detail.requirements && detail.requirements.length > 0 ? (
                        <div className="space-y-1.5">
                          {detail.requirements.map((req, idx) => {
                            const avail = Math.max(0, req.hcNeeded - req.hcFilled);
                            return (
                              <div
                                key={req.id || `req-${idx}`}
                                className="flex items-center justify-between gap-1 py-1 border-b border-border-subtle/50 last:border-b-0 text-xs"
                              >
                                <div className="font-semibold text-text-primary truncate">{req.positionName}</div>
                                <div className="text-text-secondary text-[11px] font-medium shrink-0">
                                  Hired: <span className="font-bold text-text-primary">{req.hcFilled}/{req.hcNeeded}</span> • Pipeline: <span className="font-bold text-text-primary">{req.pipelineCount}</span> • Avail: <span className="font-bold text-text-primary">{avail}</span>
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      ) : (
                        <div className="flex items-center justify-between gap-1 py-0.5 text-xs">
                          <div className="font-semibold text-text-primary text-xs truncate">
                            {detail.position_title ?? "Position Title"}
                          </div>
                          <div className="text-text-secondary text-[11px] font-medium shrink-0">
                            Hired: <span className="font-bold text-text-primary">{hiredCount}/{totalHc}</span> • Pipeline: <span className="font-bold text-text-primary">{pipelineCount}</span> • Avail: <span className="font-bold text-text-primary">{availableSlots}</span>
                          </div>
                        </div>
                      )}
                    </CompactSection>

                    {/* 3. Compact Timeline & SLA Block */}
                    <CompactSection icon={Calendar} title="Timeline & SLA Status">
                      {isEditingVacantDate ? (
                        <div className="rounded-lg border border-brand-200 bg-brand-50/50 dark:bg-brand-950/40 p-2 my-1">
                          <div className="flex flex-wrap items-center justify-between gap-2">
                            <div className="flex-1 min-w-[140px]">
                              <label className="text-[10px] font-semibold text-text-secondary block mb-1">
                                Effective Vacancy Date (Aging Override)
                              </label>
                              <input
                                type="date"
                                value={editedVacantDate}
                                onChange={(e) => setEditedVacantDate(e.target.value)}
                                className="h-7 w-full rounded border border-border-default bg-surface-base px-2 text-xs text-text-primary focus:border-brand-500 focus:outline-none"
                              />
                            </div>
                            <div className="flex items-center gap-1.5 self-end">
                              <button
                                type="button"
                                disabled={updateEffectiveVacancyDateMutation.isPending}
                                onClick={async () => {
                                  if (!editedVacantDate) return;
                                  try {
                                    setEditDateError(null);
                                    await updateEffectiveVacancyDateMutation.mutateAsync({
                                      vacancyId: vacancyId || undefined,
                                      vcode: detail.vcode,
                                      vacantDate: editedVacantDate,
                                    });
                                    setIsEditingVacantDate(false);
                                    refetch();
                                  } catch (err: unknown) {
                                    setEditDateError(err instanceof Error ? err.message : "Failed to update date");
                                  }
                                }}
                                className="h-7 px-2.5 rounded bg-brand-600 text-white text-xs font-semibold hover:bg-brand-700 transition disabled:opacity-50 cursor-pointer shadow-2xs"
                              >
                                {updateEffectiveVacancyDateMutation.isPending ? "Saving..." : "Save"}
                              </button>
                              <button
                                type="button"
                                onClick={() => {
                                  setIsEditingVacantDate(false);
                                  setEditDateError(null);
                                }}
                                className="h-7 px-2 rounded border border-border-default bg-surface-base text-text-secondary text-xs hover:bg-surface-hover transition cursor-pointer"
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                          {editDateError && (
                            <p className="mt-1 text-[11px] text-danger-text">{editDateError}</p>
                          )}
                        </div>
                      ) : (
                        <div className="grid grid-cols-3 gap-2 text-xs py-0.5">
                          <div>
                            <div className="flex items-center justify-between">
                              <span className="text-[10px] font-medium text-text-muted block">Vacant Since</span>
                              {canEditEffectiveVacancyDate && (
                                <button
                                  type="button"
                                  onClick={() => {
                                    setEditedVacantDate(detail.vacantDate ? detail.vacantDate.split("T")[0] : new Date().toISOString().split("T")[0]);
                                    setIsEditingVacantDate(true);
                                  }}
                                  className="text-[10px] text-brand-600 hover:text-brand-700 font-medium inline-flex items-center gap-0.5 cursor-pointer ml-1"
                                  title="Edit Effective Vacancy Date (Override Aging)"
                                >
                                  <Edit3 className="w-2.5 h-2.5" />
                                  <span>Edit</span>
                                </button>
                              )}
                            </div>
                            <span className="mt-0.5 text-xs font-bold text-text-primary block truncate">
                              {formatDate(detail.vacantDate)}
                            </span>
                          </div>
                          <div>
                            <span className="text-[10px] font-medium text-text-muted block">Target Fill Date</span>
                            <span className="mt-0.5 text-xs font-bold text-text-primary block truncate">
                              {detail.source === "Plantilla" ? "-" : formatDate(detail.targetFillDate)}
                            </span>
                          </div>
                          <div>
                            <span className="text-[10px] font-medium text-text-muted block">Date Created</span>
                            <span className="mt-0.5 text-xs font-bold text-text-primary block truncate">
                              {formatDate(detail.createdAt || detail.vacantDate)}
                            </span>
                          </div>
                        </div>
                      )}

                      {(detail.agingDays !== null || hasPenalty) && (
                        <div className="flex flex-wrap items-center justify-between gap-1.5 rounded-md bg-surface-muted/70 px-2.5 py-1.5 text-xs border border-border-subtle">
                          <div className="flex items-center gap-1.5 flex-wrap">
                            <span className="text-xs font-semibold text-text-muted">Aging:</span>
                            {detail.agingDays !== null ? (
                              <span className="inline-flex items-center rounded px-1.5 py-0.5 text-xs font-medium border border-border-default bg-surface-muted text-text-secondary tabular-nums">
                                {detail.agingDays} {detail.agingDays === 1 ? "Day" : "Days"}
                              </span>
                            ) : (
                              <span className="font-semibold text-text-primary">--</span>
                            )}
                            {detail.agingBucket && (
                              <Badge className="border-border-default bg-surface-muted text-text-secondary font-sans text-xs py-0.5 px-1.5">
                                {formatAgingBucket(detail.agingBucket)}
                              </Badge>
                            )}
                          </div>
                          <div>
                            {hasPenalty ? (
                              <span className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-muted px-1.5 py-0.5 text-[11px] font-medium text-text-secondary">
                                <AlertTriangle className="h-3 w-3 shrink-0" />
                                Penalty Active {penaltyFormatted ? `(${penaltyFormatted})` : ""}
                              </span>
                            ) : (
                              <span className="text-[11px] text-text-muted">No Penalty</span>
                            )}
                          </div>
                        </div>
                      )}

                      {detail.agingDays !== null && detail.agingDays > 60 && (
                        <div className="flex items-center gap-2 rounded-md border border-border-default bg-surface-muted px-2.5 py-1.5 text-xs text-text-primary">
                          <AlertCircle className="h-3.5 w-3.5 shrink-0 text-text-muted" />
                          <div className="leading-snug text-[11px]">
                            <strong className="font-semibold">High SLA Breach Risk:</strong> Open &gt; 60 days. Prioritize onboarding to minimize penalty exposure.
                          </div>
                        </div>
                      )}
                    </CompactSection>

                    {/* 4. Ownership & Team Section */}
                    <CompactSection icon={User} title="Ownership & Team">
                      <div className="grid grid-cols-2 gap-x-3 gap-y-2 text-xs">
                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">HRCO Assignee</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{detail.hrcoName ?? "Unassigned"}</span>
                          </div>
                        </div>

                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">Recruiter</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{detail.recruiterName ?? "Unassigned"}</span>
                          </div>
                        </div>

                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">OM</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{leadership.om}</span>
                          </div>
                        </div>

                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">TL</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{leadership.tl}</span>
                          </div>
                        </div>

                        <div>
                          <span className="text-[10px] font-medium text-text-muted block">ATL</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{leadership.atl}</span>
                          </div>
                        </div>

                        {isHiredTab ? (
                          <div>
                            <span className="text-[10px] font-medium text-text-muted block">Deployed By</span>
                            <div className="mt-0.5 font-semibold text-text-primary truncate">
                              {detail.deployedByName ?? "--"}
                            </div>
                          </div>
                        ) : detail.triggeredByName ? (
                          <div>
                            <span className="text-[10px] font-medium text-text-muted block">Triggered By</span>
                            <div className="mt-0.5 font-semibold text-text-primary truncate">
                              {detail.triggeredByName}
                            </div>
                          </div>
                        ) : (
                          <div>
                            <span className="text-[10px] font-medium text-text-muted block">Triggered By</span>
                            <div className="mt-0.5 font-semibold text-text-primary truncate">
                              --
                            </div>
                          </div>
                        )}

                        {(detail.hasReliever || detail.relieverOnDuty) && (
                          <div className="col-span-2 pt-1.5 border-t border-border-subtle/50 flex items-center justify-between text-xs">
                            <span className="text-[10px] font-medium text-text-muted">Reliever on Duty</span>
                            <span className="inline-flex items-center gap-1 rounded bg-surface-muted px-2 py-0.5 text-[11px] font-medium text-text-secondary border border-border-default">
                              <UserCheck className="h-3 w-3 text-text-muted" />
                              {detail.relieverOnDuty ?? "Reliever Assigned"}
                            </span>
                          </div>
                        )}
                      </div>
                    </CompactSection>
                  </>
                );
              })()}

              {/* HRCO Remarks - Only rendered when actual operational remarks are recorded */}
              {detail.hrcoRemarks && detail.hrcoRemarks.trim().length > 0 && (
                <div className="rounded-lg border border-border-subtle p-3 space-y-1.5 bg-surface-muted/30">
                  <h3 className="text-xs font-semibold text-text-muted">
                    HRCO Remarks
                  </h3>
                  <p className="text-xs text-text-primary bg-surface-base p-2.5 rounded border border-border-subtle leading-relaxed whitespace-pre-line">
                    {detail.hrcoRemarks.trim()}
                  </p>
                </div>
              )}

              {/* 5. Requisition & Quota Management Section - Suppressed in Hired tab or filled status (Bug 2) */}
              {!isHiredTab && (
                <div className="rounded-lg border border-border-subtle bg-surface-base p-3 space-y-2">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-1.5 text-[11px] font-bold text-text-secondary">
                      <SlidersHorizontal className="h-3.5 w-3.5 text-brand-600 shrink-0" />
                      <span>Requisition & Quota Controls</span>
                    </div>
                  </div>

                  <div className="flex flex-wrap items-center gap-2 pt-0.5">
                    {canReviseQuota && (
                      <button
                        type="button"
                        onClick={() => setIsReviseQuotaModalOpen(true)}
                        className="inline-flex items-center gap-1.5 rounded-md border border-border-subtle bg-surface-muted/70 px-2.5 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-muted hover:border-border transition shadow-xs cursor-pointer"
                        title="Directly revise headcount quota for this requisition slot"
                      >
                        <SlidersHorizontal className="h-3.5 w-3.5 text-brand-600" />
                        <span>Adjust Quota</span>
                      </button>
                    )}

                    {canRequestAdjustment && (
                      <button
                        type="button"
                        onClick={() => setIsRequestAdjustmentModalOpen(true)}
                        className="inline-flex items-center gap-1.5 rounded-md border border-border-subtle bg-surface-muted/70 px-2.5 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-muted hover:border-border transition shadow-xs cursor-pointer"
                        title="Submit a formal headcount quota adjustment request"
                      >
                        <FileText className="h-3.5 w-3.5 text-brand-600" />
                        <span>Request HC Adjustment</span>
                      </button>
                    )}

                    {userCanRequestClosure && !isPendingClosure && detail.derivedStatus?.toLowerCase() !== "closed" && (
                      <button
                        type="button"
                        disabled={isClosureBlockedByApplicants}
                        onClick={() => {
                          if (isClosureBlockedByApplicants) return;
                          setIsRequestClosureModalOpen(true);
                        }}
                        className={`inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-xs font-semibold transition shadow-xs ${
                          isClosureBlockedByApplicants
                            ? "border-border-default bg-surface-muted text-text-muted cursor-not-allowed opacity-60"
                            : "border-border-default bg-surface text-text-secondary hover:bg-surface-hover hover:text-text-primary cursor-pointer"
                        }`}
                        title={
                          isClosureBlockedByApplicants
                            ? "Cannot request closure while active applicants exist in pipeline. Process or drop candidates first."
                            : "Request store or vacancy closure clearance"
                        }
                      >
                        <XCircle className={`h-3.5 w-3.5 ${isClosureBlockedByApplicants ? "text-text-muted" : "text-brand-600"}`} />
                        <span>Request Closure</span>
                      </button>
                    )}

                    {isPendingClosure && (isUserFullAccess || userIsOps || userCanRequestClosure) && (
                      <button
                        type="button"
                        disabled={withdrawClosureMutation.isPending}
                        onClick={async () => {
                          if (!detail?.vcode) return;
                          const confirmed = window.confirm(
                            `Are you sure you want to withdraw the pending closure request for ${detail.vcode}? This will restore normal sourcing and pipeline operations.`
                          );
                          if (!confirmed) return;
                          try {
                            await withdrawClosureMutation.mutateAsync({
                              vcode: detail.vcode,
                              userId: currentUser?.authUserId || currentUser?.profileId || null,
                            });
                            refetch();
                          } catch (err: unknown) {
                            alert(err instanceof Error ? err.message : "Failed to withdraw closure request");
                          }
                        }}
                        className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-muted px-2.5 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition shadow-xs cursor-pointer"
                        title="Withdraw in-flight closure clearance request"
                      >
                        <RotateCcw className="h-3.5 w-3.5 text-text-muted" />
                        <span>{withdrawClosureMutation.isPending ? "Withdrawing..." : "Withdraw Closure"}</span>
                      </button>
                    )}
                  </div>
                </div>
              )}

              {/* 6. Applicant & Pipeline Section with Candidate Cards */}
              <div className="rounded-lg border border-border-subtle bg-surface-base p-3 space-y-2.5">
                <div className="flex items-center justify-between">
                  <h3 className="text-[11px] font-bold text-text-secondary flex items-center gap-1.5">
                    <Users className="h-3.5 w-3.5 text-brand-600 shrink-0" />
                    <span>Applicant & Pipeline</span>
                  </h3>
                  <div className="flex items-center gap-1.5 text-[11px] text-text-secondary font-medium">
                    <span>{detail.activeApplicantCount} Active</span>
                    <span>&bull;</span>
                    <span>{detail.confirmedOnboardCount} Onboarded</span>
                  </div>
                </div>

                {/* Candidate cards */}
                <div className="space-y-2.5">
                  {detail.activeApplicantsList && detail.activeApplicantsList.length > 0 ? (
                    detail.activeApplicantsList.map((candidate, index) => {
                      const isCandidateHired =
                        isHired ||
                        candidate.statusLabel.toLowerCase().includes("hired") ||
                        candidate.statusLabel.toLowerCase().includes("confirm");

                      // Candidate aging in current stage or requisition aging
                      const candidateAging = candidate.agingDays ?? detail.agingDays ?? null;

                      return (
                        <div
                          key={candidate.applicantId || `candidate-${index}`}
                          className="rounded-lg border border-border-subtle bg-surface-muted/30 p-3 text-xs hover:bg-surface-muted/60 transition space-y-2.5"
                        >
                          {/* Candidate Top Header */}
                          <div className="flex items-center justify-between gap-2 flex-wrap">
                            <div className="flex items-center gap-2">
                              <div className="flex h-6 w-6 items-center justify-center rounded-full bg-brand-50 text-brand-700 font-bold text-[10px]">
                                {candidate.displayName.charAt(0)}
                              </div>
                              <div className="font-bold text-text-primary text-xs">
                                {formatPersonName(candidate.displayName)}
                              </div>
                            </div>
                            <div className="flex items-center gap-1.5 flex-wrap">
                              <Badge
                                className="text-[10px] py-0.5 px-2 font-medium border border-border-default bg-surface-muted text-text-secondary"
                              >
                                {candidate.statusLabel}
                              </Badge>
                              {candidateAging !== null && (
                                <span
                                  className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-medium border border-border-default bg-surface-muted text-text-secondary"
                                  title="Candidate Aging in Stage"
                                >
                                  <Clock3 className="h-2.5 w-2.5" />
                                  <span>{candidateAging}d</span>
                                </span>
                              )}
                            </div>
                          </div>

                          {/* Candidate Metadata Row */}
                          <div className="grid grid-cols-2 gap-2 text-[11px] text-text-secondary pt-1 border-t border-border-subtle/50">
                            <div className="flex items-center gap-1 truncate">
                              <Phone className="h-3 w-3 text-text-muted shrink-0" />
                              <span className="truncate">{candidate.contactNumber || "No contact recorded"}</span>
                            </div>
                            {candidate.onboardDate ? (
                              <div className="flex items-center gap-1 truncate">
                                <Calendar className="h-3 w-3 text-text-muted shrink-0" />
                                <span className="truncate">Onboard: {formatDate(candidate.onboardDate)}</span>
                              </div>
                            ) : candidate.recruiterName ? (
                              <div className="flex items-center gap-1 truncate">
                                <User className="h-3 w-3 text-text-muted shrink-0" />
                                <span className="truncate">Recruiter: {candidate.recruiterName}</span>
                              </div>
                            ) : null}
                          </div>

                          {/* Consolidated Candidate Action Buttons */}
                          {!isCandidateHired && (userCanManagePipeline || userCanEditApplicant) && (
                            <div className="flex items-center justify-end gap-1.5 pt-2 border-t border-border-subtle/50 flex-wrap">
                              {userCanEditApplicant && (isUserFullAccess || (candidate.profileEditCount ?? 0) === 0) && (
                                <button
                                  type="button"
                                  onClick={() => {
                                    setSelectedCandidateForEdit({
                                      applicantId: candidate.applicantId,
                                      displayName: candidate.displayName,
                                      lastName: candidate.lastName,
                                      firstName: candidate.firstName,
                                      middleName: candidate.middleName,
                                      contactNumber: candidate.contactNumber,
                                      profileEditCount: candidate.profileEditCount,
                                      statusLabel: candidate.statusLabel,
                                      vcode: detail.vcode,
                                      positionTitle: detail.position_title,
                                    });
                                    setIsEditApplicantModalOpen(true);
                                  }}
                                  className="inline-flex items-center gap-1 rounded border border-border-default bg-surface px-2 py-1 text-[11px] font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition shadow-xs cursor-pointer"
                                  title="Edit applicant profile details"
                                >
                                  <Edit3 className="h-3 w-3" />
                                  <span>Edit Details</span>
                                </button>
                              )}

                              {userCanManagePipeline && (
                                <>
                                  <button
                                    type="button"
                                    onClick={() => {
                                      setSelectedCandidate({
                                        id: candidate.applicantId,
                                        fullName: candidate.displayName,
                                        lastName: candidate.lastName,
                                        firstName: candidate.firstName,
                                        middleName: candidate.middleName,
                                        contactNumber: candidate.contactNumber,
                                        status: candidate.statusLabel,
                                        vcode: detail.vcode,
                                        positionTitle: detail.position_title,
                                      });
                                      setIsAdvancePipelineModalOpen(true);
                                    }}
                                    className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-muted px-2 py-1 text-[11px] font-semibold text-text-primary hover:bg-surface-hover transition shadow-xs cursor-pointer"
                                    title="Advance stage or select terminal backout/dropout reason"
                                  >
                                    <ArrowRightCircle className="h-3 w-3" />
                                    <span>Update Stage / Backout</span>
                                  </button>

                                  <button
                                    type="button"
                                    onClick={() => {
                                      setSelectedCandidate({
                                        id: candidate.applicantId,
                                        fullName: candidate.displayName,
                                        lastName: candidate.lastName,
                                        firstName: candidate.firstName,
                                        middleName: candidate.middleName,
                                        contactNumber: candidate.contactNumber,
                                        status: candidate.statusLabel,
                                        vcode: detail.vcode,
                                        positionTitle: detail.position_title,
                                      });
                                      setIsMarkHiredModalOpen(true);
                                    }}
                                    className="inline-flex items-center gap-1 rounded border border-brand-200 bg-brand-50 px-2 py-1 text-[11px] font-semibold text-brand-700 hover:bg-brand-100 transition shadow-xs cursor-pointer"
                                    title="Approve and mark candidate as hired"
                                  >
                                    <CheckCircle2 className="h-3 w-3" />
                                    <span>Mark Hired</span>
                                  </button>
                                </>
                              )}
                            </div>
                          )}
                        </div>
                      );
                    })
                  ) : detail.applicantName ? (
                    /* Fallback Single Candidate Card */
                    <div className="rounded-lg border border-border-subtle bg-surface-muted/30 p-3 text-xs space-y-2.5">
                      <div className="flex items-center justify-between gap-2 flex-wrap">
                        <div className="flex items-center gap-2">
                          <div className="flex h-6 w-6 items-center justify-center rounded-full bg-brand-50 text-brand-700 font-bold text-[10px]">
                            {detail.applicantName.charAt(0)}
                          </div>
                          <div className="font-bold text-text-primary text-xs">
                            {detail.applicantName}
                          </div>
                        </div>
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <Badge
                            className="text-[10px] py-0.5 px-2 font-medium border border-border-default bg-surface-muted text-text-secondary"
                          >
                            {detail.pipelineStatus || "In Pipeline"}
                          </Badge>
                          {detail.agingDays !== null && (
                            <span
                              className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-medium border border-border-default bg-surface-muted text-text-secondary"
                              title="Aging in Pipeline"
                            >
                              <Clock3 className="h-2.5 w-2.5" />
                              <span>{detail.agingDays}d</span>
                            </span>
                          )}
                        </div>
                      </div>

                      <div className="grid grid-cols-2 gap-2 text-[11px] text-text-secondary pt-1 border-t border-border-subtle/50">
                        <div className="flex items-center gap-1 truncate">
                          <Phone className="h-3 w-3 text-text-muted shrink-0" />
                          <span className="truncate">{detail.contactNumber || "No contact recorded"}</span>
                        </div>
                        {detail.onboardDate && (
                          <div className="flex items-center gap-1 truncate">
                            <Calendar className="h-3 w-3 text-text-muted shrink-0" />
                            <span className="truncate">Onboard: {formatDate(detail.onboardDate)}</span>
                          </div>
                        )}
                      </div>

                      {!isHired && (userCanManagePipeline || userCanEditApplicant) && (
                        <div className="flex items-center justify-end gap-1.5 pt-2 border-t border-border-subtle/50 flex-wrap">
                          {userCanEditApplicant && detail.applicantId && (isUserFullAccess || (detail.profileEditCount ?? 0) === 0) && (
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedCandidateForEdit({
                                  applicantId: detail.applicantId!,
                                  displayName: detail.applicantName,
                                  firstName: detail.applicantFirstName,
                                  middleName: detail.applicantMiddleName,
                                  lastName: detail.applicantLastName,
                                  contactNumber: detail.contactNumber,
                                  profileEditCount: detail.profileEditCount,
                                  statusLabel: detail.pipelineStatus,
                                  vcode: detail.vcode,
                                  positionTitle: detail.position_title,
                                });
                                setIsEditApplicantModalOpen(true);
                              }}
                              className="inline-flex items-center gap-1 rounded border border-border-default bg-surface px-2 py-1 text-[11px] font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition shadow-xs cursor-pointer"
                              title="Edit applicant profile details"
                            >
                              <Edit3 className="h-3 w-3" />
                              <span>Edit Details</span>
                            </button>
                          )}

                          {userCanManagePipeline && (
                            <>
                              <button
                                type="button"
                                onClick={() => {
                                  setSelectedCandidate({
                                    id: detail.applicantId || detail.vacancyId,
                                    fullName: detail.applicantName || "Candidate",
                                    lastName: detail.applicantLastName,
                                    firstName: detail.applicantFirstName,
                                    middleName: detail.applicantMiddleName,
                                    contactNumber: detail.contactNumber,
                                    status: detail.pipelineStatus || "Pipeline",
                                    vcode: detail.vcode,
                                    positionTitle: detail.position_title,
                                  });
                                  setIsAdvancePipelineModalOpen(true);
                                }}
                                className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-muted px-2 py-1 text-[11px] font-semibold text-text-primary hover:bg-surface-hover transition shadow-xs cursor-pointer"
                                title="Advance stage or select terminal backout/dropout reason"
                              >
                                <ArrowRightCircle className="h-3 w-3" />
                                <span>Update Stage / Backout</span>
                              </button>

                              <button
                                type="button"
                                onClick={() => {
                                  setSelectedCandidate({
                                    id: detail.applicantId || detail.vacancyId,
                                    fullName: detail.applicantName || "Candidate",
                                    lastName: detail.applicantLastName,
                                    firstName: detail.applicantFirstName,
                                    middleName: detail.applicantMiddleName,
                                    contactNumber: detail.contactNumber,
                                    status: detail.pipelineStatus || "Pipeline",
                                    vcode: detail.vcode,
                                    positionTitle: detail.position_title,
                                  });
                                  setIsMarkHiredModalOpen(true);
                                }}
                                className="inline-flex items-center gap-1 rounded border border-brand-200 bg-brand-50 px-2 py-1 text-[11px] font-semibold text-brand-700 hover:bg-brand-100 transition shadow-xs cursor-pointer"
                                title="Approve and mark candidate as hired"
                              >
                                <CheckCircle2 className="h-3 w-3" />
                                <span>Mark Hired</span>
                              </button>
                            </>
                          )}
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="text-center py-4 border border-dashed border-border-subtle rounded-md text-xs text-text-muted">
                      No active applicants in pipeline.
                    </div>
                  )}
                </div>

                <div className="text-[10px] text-text-muted flex items-start gap-1 pt-1">
                  <Lock className="h-3 w-3 shrink-0 mt-0.5 text-text-muted" />
                  <span>PII Guard active: Candidate personal contact details subject to operational scope.</span>
                </div>
              </div>

              {/* Headcount Origin & Approvals Context - Hidden if completely empty */}
              {hasHeadcountContext && (
                <div className="rounded-lg border border-border-subtle p-3 space-y-2 text-xs bg-surface-base">
                  <h3 className="text-[11px] font-bold text-text-secondary">
                    Headcount & Approvals Context
                  </h3>
                  <div className="space-y-1.5">
                    {detail.headcountRequestId && (
                      <div className="flex justify-between border-b border-border-subtle/50 pb-1">
                        <span className="text-[11px] text-text-muted">Headcount Request ID</span>
                        <span className="font-mono text-xs text-text-primary truncate max-w-[200px]">
                          {detail.headcountRequestId}
                        </span>
                      </div>
                    )}
                    {detail.vacancyReason && (
                      <div className="flex justify-between border-b border-border-subtle/50 pb-1">
                        <span className="text-[11px] text-text-muted">Vacancy Stated Reason</span>
                        <span className="text-xs text-text-primary font-medium">
                          {detail.vacancyReason}
                        </span>
                      </div>
                    )}
                    {detail.approvedByName && (
                      <div className="flex justify-between border-b border-border-subtle/50 pb-1">
                        <span className="text-[11px] text-text-muted">Approved By</span>
                        <span className="text-xs text-text-primary font-medium">
                          {detail.approvedByName}
                        </span>
                      </div>
                    )}
                    {detail.approvedAt && (
                      <div className="flex justify-between border-b border-border-subtle/50 pb-1">
                        <span className="text-[11px] text-text-muted">Approval Date</span>
                        <span className="text-xs text-text-primary">
                          {formatDate(detail.approvedAt)}
                        </span>
                      </div>
                    )}
                  </div>
                  {detail.jobDescription && (
                    <div className="mt-2 pt-2 border-t border-border-subtle/50">
                      <div className="text-[11px] text-text-muted mb-1">Job Description & Qualifications</div>
                      <p className="text-xs text-text-secondary leading-relaxed bg-surface-muted/50 p-2 rounded border border-border-subtle whitespace-pre-line">
                        {detail.jobDescription}
                      </p>
                    </div>
                  )}
                </div>
              )}

              {/* Audit Activity Timeline - Hidden when no real audit logs exist */}
              {hasActivityLogs && (
                <div className="rounded-lg border border-border-subtle p-3 space-y-2 bg-surface-base">
                  <div className="flex items-center gap-1.5 text-[11px] font-bold text-text-secondary">
                    <History className="h-3.5 w-3.5 text-brand-600 shrink-0" />
                    <span>Activity History</span>
                  </div>
                  <div className="relative pl-4 space-y-2.5 border-l-2 border-border-subtle ml-1.5 mt-2">
                    {detail.activityHistory!.map((item, index) => {
                      const summary = formatActivityHistorySummary(item);
                      return (
                        <div key={item.eventId || `activity-${index}`} className="relative text-xs">
                          {/* Timeline dot */}
                          <div className="absolute -left-[21px] top-0.5 h-2 w-2 rounded-full border-2 border-surface-base bg-brand-500" />
                          <div className="flex justify-between items-baseline gap-2">
                            <span className="font-semibold text-text-primary leading-tight">{summary.title}</span>
                            <span className="text-[10px] text-text-muted shrink-0">
                              {formatDate(item.createdAt)}
                            </span>
                          </div>
                          {item.profileName && (
                            <div className="mt-0.5 text-[10px] text-text-muted">
                              By {item.profileName}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Add Applicant Modal */}
              {isAddApplicantModalOpen && (
                <AddApplicantModal
                  isOpen={isAddApplicantModalOpen}
                  onClose={() => setIsAddApplicantModalOpen(false)}
                  vacancy={{
                    vcode: detail.vcode,
                    positionTitle: detail.position_title,
                    storeName: detail.storeName,
                    accountName: detail.accountName,
                    groupName: detail.groupName,
                    hrcoName: detail.hrcoName,
                  }}
                  onSuccess={() => refetch()}
                />
              )}

              {/* Advance Pipeline Modal */}
              {isAdvancePipelineModalOpen && (
                <AdvancePipelineModal
                  isOpen={isAdvancePipelineModalOpen}
                  onClose={() => {
                    setIsAdvancePipelineModalOpen(false);
                    setSelectedCandidate(null);
                  }}
                  applicant={
                    selectedCandidate || {
                      id: detail.vacancyId,
                      fullName: detail.applicantName || "Candidate",
                      contactNumber: detail.contactNumber,
                      status: detail.pipelineStatus || "Pipeline",
                      vcode: detail.vcode,
                      positionTitle: detail.position_title,
                    }
                  }
                  onSuccess={() => {
                    setIsAdvancePipelineModalOpen(false);
                    setSelectedCandidate(null);
                    refetch();
                  }}
                />
              )}

              {/* Mark Hired Modal */}
              {isMarkHiredModalOpen && (
                <MarkHiredModal
                  isOpen={isMarkHiredModalOpen}
                  onClose={() => {
                    setIsMarkHiredModalOpen(false);
                    setSelectedCandidate(null);
                  }}
                  applicant={
                    selectedCandidate || {
                      id: detail.vacancyId,
                      fullName: detail.applicantName || "Candidate",
                      lastName: detail.applicantLastName,
                      firstName: detail.applicantFirstName,
                      middleName: detail.applicantMiddleName,
                      contactNumber: detail.contactNumber,
                      vcode: detail.vcode,
                      positionTitle: detail.position_title,
                    }
                  }
                  onSuccess={() => {
                    setIsMarkHiredModalOpen(false);
                    setSelectedCandidate(null);
                    refetch();
                  }}
                />
              )}

              {/* Fail / Backout Modal */}
              {isFailBackoutModalOpen && (
                <FailBackoutModal
                  isOpen={isFailBackoutModalOpen}
                  onClose={() => {
                    setIsFailBackoutModalOpen(false);
                    setSelectedCandidate(null);
                  }}
                  applicant={
                    selectedCandidate || {
                      id: detail.applicantId || detail.vacancyId,
                      fullName: detail.applicantName || "Candidate",
                      status: detail.pipelineStatus || "Pipeline",
                      vcode: detail.vcode,
                      positionTitle: detail.position_title,
                    }
                  }
                  onSuccess={() => {
                    setIsFailBackoutModalOpen(false);
                    setSelectedCandidate(null);
                    refetch();
                  }}
                />
              )}

              {/* Edit Hired Date Modal */}
              {isEditHiredDateModalOpen && (
                <EditHiredDateModal
                  isOpen={isEditHiredDateModalOpen}
                  onClose={() => {
                    setIsEditHiredDateModalOpen(false);
                    setSelectedCandidate(null);
                  }}
                  applicant={
                    selectedCandidate || {
                      id: detail.vacancyId,
                      fullName: detail.applicantName || "Candidate",
                      vcode: detail.vcode,
                      hiredDate: detail.onboardDate,
                    }
                  }
                  onSuccess={() => {
                    setIsEditHiredDateModalOpen(false);
                    setSelectedCandidate(null);
                    refetch();
                  }}
                />
              )}

              {/* Edit Applicant Profile Modal */}
              {isEditApplicantModalOpen && selectedCandidateForEdit && (
                <EditApplicantModal
                  isOpen={isEditApplicantModalOpen}
                  onClose={() => {
                    setIsEditApplicantModalOpen(false);
                    setSelectedCandidateForEdit(null);
                  }}
                  applicant={selectedCandidateForEdit}
                  onSuccess={() => {
                    setIsEditApplicantModalOpen(false);
                    setSelectedCandidateForEdit(null);
                    refetch();
                  }}
                />
              )}

              {/* Reopen Vacancy Modal */}
              {isReopenVacancyModalOpen && (
                <ReopenVacancyModal
                  isOpen={isReopenVacancyModalOpen}
                  onClose={() => setIsReopenVacancyModalOpen(false)}
                  vacancy={{
                    vcode: detail.vcode,
                    positionTitle: detail.position_title,
                    storeName: detail.storeName,
                    accountName: detail.accountName,
                  }}
                  onSuccess={() => {
                    setIsReopenVacancyModalOpen(false);
                    refetch();
                  }}
                />
              )}

              {/* Request Vacancy Closure Modal */}
              {isRequestClosureModalOpen && (
                <RequestVacancyClosureModal
                  isOpen={isRequestClosureModalOpen}
                  onClose={() => setIsRequestClosureModalOpen(false)}
                  vacancy={{
                    vcode: detail.vcode,
                    positionTitle: detail.position_title,
                    storeName: detail.storeName,
                  }}
                  onSuccess={() => {
                    setIsRequestClosureModalOpen(false);
                    refetch();
                  }}
                />
              )}

              {/* Headcount Quota Modals */}
              {isReviseQuotaModalOpen && (
                <ReviseHeadcountQuotaModal
                  isOpen={isReviseQuotaModalOpen}
                  onClose={() => setIsReviseQuotaModalOpen(false)}
                  vcode={detail.vcode}
                  storeName={detail.storeName}
                  positionTitle={detail.position_title}
                  initialQuota={detail.headcount}
                  onSuccess={() => refetch()}
                />
              )}

              {isRequestAdjustmentModalOpen && (
                <RequestHeadcountAdjustmentModal
                  isOpen={isRequestAdjustmentModalOpen}
                  onClose={() => setIsRequestAdjustmentModalOpen(false)}
                  vcode={detail.vcode}
                  storeName={detail.storeName}
                  positionTitle={detail.position_title}
                  initialQuota={detail.headcount}
                  accountId={detail.accountId}
                  storeId={detail.storeId}
                  onSuccess={() => refetch()}
                />
              )}
            </>
          )}
      </DetailDrawer>
  );
}

// Sub-components for states
function LoadingSkeleton() {
  return (
    <div className="space-y-5 animate-pulse">
      <div className="grid grid-cols-2 gap-3">
        <div className="h-16 rounded-md bg-surface-muted" />
        <div className="h-16 rounded-md bg-surface-muted" />
      </div>
      <div className="h-32 rounded-md bg-surface-muted" />
      <div className="h-24 rounded-md bg-surface-muted" />
      <div className="h-36 rounded-md bg-surface-muted" />
      <div className="h-28 rounded-md bg-surface-muted" />
    </div>
  );
}

function AccessDeniedState() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <div className="rounded-full bg-surface-muted p-3 text-text-muted shadow-xs border border-border-default">
        <ShieldAlert className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-semibold text-text-primary">Access Denied</h4>
      <p className="mt-1 text-xs text-text-muted max-w-xs">
        You do not have permission to view this vacancy record. Access is restricted to your assigned scope.
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
      <h4 className="mt-4 text-sm font-semibold text-text-primary">Record Not Found</h4>
      <p className="mt-1 text-xs text-text-muted max-w-xs">
        The selected vacancy could not be located on the server. It may have been recently removed or closed.
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
      <div className="rounded-full bg-surface-muted p-3 text-text-muted border border-border-default shadow-xs">
        <AlertCircle className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-semibold text-text-primary">Unable to Load Details</h4>
      <p className="mt-1 text-xs text-text-muted max-w-xs">
        {errorMsg}
      </p>
      <button
        className="mt-4 inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary shadow-xs hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
        onClick={onRetry}
        type="button"
      >
        <RefreshCw className="h-3 w-3" />
        Retry
      </button>
    </div>
  );
}
