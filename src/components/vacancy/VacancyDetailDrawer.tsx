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
  UserMinus,
  UserPlus,
  Users,
  XCircle,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  getVacancyDetail,
  VacancyDataError,
} from "@/lib/queries/vacancy";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { CapabilityActionBar } from "@/components/shared/CapabilityActionBar";
import { StatusBadge } from "@/components/ui/StatusBadge";
import {
  isOpsAmendmentRole,
  isQuotaOverrideRole,
  useCurrentUser,
} from "@/lib/auth";
import {
  canAddApplicant,
  canManageApplicantPipeline,
  canReviewVacancyClosures,
  canRequestVacancyClosure,
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
      <div className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-text-secondary">
        <Icon className="h-3.5 w-3.5 text-brand-600 shrink-0" />
        <span>{title}</span>
      </div>
      {children}
    </div>
  );
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
  const canReviseQuota = Boolean(userRole && isQuotaOverrideRole(userRole));
  const canRequestAdjustment = Boolean(userRole && isOpsAmendmentRole(userRole));
  const userCanAddApplicant = canAddApplicant(currentUser);
  const userCanManagePipeline = canManageApplicantPipeline(currentUser);
  const userCanReviewClosures = canReviewVacancyClosures(currentUser);
  const userCanRequestClosure = canRequestVacancyClosure(currentUser);

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

  const isHired = Boolean(
    status === "hired" ||
    detail?.derivedStatus?.toLowerCase() === "hired" ||
    detail?.pipelineStatus?.toLowerCase() === "hired" ||
    detail?.vacancyStatus?.toLowerCase() === "filled" ||
    (detail?.confirmedOnboardCount ?? 0) > 0
  );

  const statusLabel = isPendingClosure
    ? "Pending Clearance"
    : detail?.derivedStatus ?? detail?.vacancyStatus ?? "--";

  const statusBadgeStyle = isPendingClosure
    ? "border-amber-300 bg-amber-50 text-amber-800"
    : detail?.derivedStatus?.toLowerCase() === "open"
    ? "border-blue-200 bg-blue-50 text-blue-700"
    : detail?.derivedStatus?.toLowerCase() === "pipeline"
    ? "border-purple-200 bg-purple-50 text-purple-700"
    : detail?.derivedStatus?.toLowerCase() === "hired"
    ? "border-emerald-200 bg-emerald-50 text-emerald-700"
    : "border-gray-200 bg-gray-50 text-gray-700";

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
          <div className="h-5 w-24 animate-pulse rounded bg-gray-200" />
        ) : detail ? (
          <div className="flex items-center gap-1.5 flex-wrap">
            <Badge className="font-mono text-xs font-semibold bg-gray-900 text-white border-none py-0.5 px-2">
              {detail.vcode}
            </Badge>
            <Badge className={`text-[11px] py-0 px-2 font-medium ${statusBadgeStyle}`}>
              {statusLabel}
            </Badge>
          </div>
        ) : (
          <Badge className="bg-red-50 text-red-700">Error</Badge>
        )
      }
      title={
        isLoading ? (
          <div className="h-6 w-48 animate-pulse rounded bg-gray-200 mt-1" />
        ) : detail ? (
          detail.position_title ?? "Position Title"
        ) : (
          "Vacancy Detail"
        )
      }
      subtitle={
        !isLoading && detail && (
          <>
            <MapPin className="h-3 w-3 shrink-0 text-gray-400" />
            <span className="truncate">
              {[detail.accountName, detail.groupName || "General / Direct", detail.storeName]
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
                label: "Update Stage",
                isAvailable:
                  userCanManagePipeline &&
                  !isPendingClosure &&
                  Boolean(detail.activeApplicantsList?.[0] || detail.applicantName) &&
                  detail.derivedStatus?.toLowerCase() !== "hired" &&
                  detail.derivedStatus?.toLowerCase() !== "closed",
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
                    });
                  }
                  setIsAdvancePipelineModalOpen(true);
                },
                icon: ArrowRightCircle,
                variant: "primary",
              },
              {
                label: "Mark Hired",
                isAvailable:
                  userCanManagePipeline &&
                  !isPendingClosure &&
                  Boolean(detail.activeApplicantsList?.[0] || detail.applicantName) &&
                  detail.derivedStatus?.toLowerCase() !== "hired" &&
                  detail.derivedStatus?.toLowerCase() !== "closed",
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
                    });
                  }
                  setIsMarkHiredModalOpen(true);
                },
                icon: CheckCircle2,
                variant: "success",
              },
              {
                label: "Reopen Slot",
                isAvailable:
                  userCanManagePipeline &&
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
                label: "Adjust Quota",
                isAvailable: canReviseQuota,
                onClick: () => setIsReviseQuotaModalOpen(true),
                icon: SlidersHorizontal,
                variant: "secondary",
              },
              {
                label: "Request HC Adjustment",
                isAvailable: canRequestAdjustment,
                onClick: () => setIsRequestAdjustmentModalOpen(true),
                icon: FileText,
                variant: "secondary",
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
                  userCanManagePipeline &&
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
              {
                label: "Drop / Backout",
                isAvailable:
                  userCanManagePipeline &&
                  !isPendingClosure &&
                  Boolean(detail.activeApplicantsList?.[0] || detail.applicantName) &&
                  detail.derivedStatus?.toLowerCase() !== "hired" &&
                  detail.derivedStatus?.toLowerCase() !== "closed",
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
                    });
                  }
                  setIsFailBackoutModalOpen(true);
                },
                icon: UserMinus,
                variant: "danger",
              },
              {
                label: "Request Closure",
                isAvailable:
                  userCanRequestClosure &&
                  !isPendingClosure &&
                  detail.derivedStatus?.toLowerCase() !== "closed",
                onClick: () => setIsRequestClosureModalOpen(true),
                icon: XCircle,
                variant: "warning",
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
                <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-amber-900 flex items-start gap-2.5">
                  <Clock3 className="h-4 w-4 shrink-0 mt-0.5 text-amber-600" />
                  <div className="text-xs space-y-1">
                    <div className="font-semibold flex items-center gap-1.5">
                      <span>Closure Clearance In-Flight</span>
                      {detail.closureRequestStatus && (
                        <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] text-amber-800 border border-amber-300">
                          {detail.closureRequestStatus}
                        </span>
                      )}
                    </div>
                    <div className="text-amber-800/90 leading-relaxed">
                      This vacancy slot has an active Store / Vacancy Closure request under review. Sourcing and pipeline transitions are paused pending management clearance.
                    </div>
                    {detail.closureReason && (
                      <div className="mt-1 font-medium text-amber-950">
                        Reason: {detail.closureReason}
                      </div>
                    )}
                    {detail.closureRequestedBy && (
                      <div className="text-[11px] text-amber-700">
                        Requested by {detail.closureRequestedBy}
                        {detail.closureRequestedAt && ` • ${new Date(detail.closureRequestedAt).toLocaleDateString()}`}
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
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">VCode</span>
                          <span className="font-mono text-xs font-semibold text-text-primary block truncate">{detail.vcode}</span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Urgency Level</span>
                          <div className="mt-0.5">
                            <StatusBadge variant={urgencyVariant} className="text-[11px] py-0 px-2 font-semibold">
                              {detail.urgencyLevel ?? "Normal"}
                            </StatusBadge>
                          </div>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Source</span>
                          <span className="font-semibold text-text-primary block truncate">
                            {detail.source || (detail.vcode.startsWith("CG-") ? "Coverage Group" : "Plantilla")}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Vacancy Type</span>
                          <span className="font-semibold text-text-primary block truncate">
                            {detail.vacancyType || (detail.source === "Plantilla" ? "Replacement" : "New Demand")}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Group</span>
                          <span className="font-semibold text-text-primary block truncate" title={detail.groupName || "General / Direct"}>
                            {detail.groupName || "General / Direct"}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Account</span>
                          <span className="font-semibold text-text-primary block truncate" title={detail.accountName || "--"}>
                            {detail.accountName || "--"}
                          </span>
                        </div>
                        <div className={storesList.length > 1 ? "col-span-2" : ""}>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">
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
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Province / City</span>
                          <span className="font-semibold text-text-primary block truncate">
                            {[detail.areaProvince, detail.areaCity].filter(Boolean).join(" / ") || detail.storeLocation || "--"}
                          </span>
                        </div>
                        {detail.employmentType && (
                          <div className="col-span-2">
                            <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Employment Type</span>
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
                      <div className="grid grid-cols-3 gap-2 text-xs py-0.5">
                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Vacant Since</span>
                          <span className="mt-0.5 text-xs font-bold text-text-primary block truncate">
                            {formatDate(detail.vacantDate)}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Target Fill Date</span>
                          <span className="mt-0.5 text-xs font-bold text-text-primary block truncate">
                            {detail.source === "Plantilla" ? "-" : formatDate(detail.targetFillDate)}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Date Created</span>
                          <span className="mt-0.5 text-xs font-bold text-text-primary block truncate">
                            {formatDate(detail.createdAt || detail.vacantDate)}
                          </span>
                        </div>
                      </div>

                      {(detail.agingDays !== null || hasPenalty) && (
                        <div className="flex flex-wrap items-center justify-between gap-1.5 rounded-md bg-surface-muted/70 px-2.5 py-1.5 text-xs border border-border-subtle">
                          <div className="flex items-center gap-1.5 flex-wrap">
                            <span className="text-[10px] uppercase font-semibold text-text-muted">Aging:</span>
                            {detail.agingDays !== null ? (
                              <span
                                className={`inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-bold ${
                                  detail.agingDays <= 15
                                    ? "border border-emerald-200 bg-emerald-50 text-emerald-700"
                                    : detail.agingDays <= 30
                                    ? "border border-amber-200 bg-amber-50 text-amber-700"
                                    : "border border-rose-200 bg-rose-50 text-rose-700"
                                }`}
                              >
                                {detail.agingDays} {detail.agingDays === 1 ? "Day" : "Days"}
                              </span>
                            ) : (
                              <span className="font-semibold text-text-primary">--</span>
                            )}
                            {detail.agingBucket && (
                              <Badge className="border-blue-100 bg-blue-50 text-blue-800 uppercase font-mono text-[9px] py-0 px-1.5">
                                {detail.agingBucket}
                              </Badge>
                            )}
                          </div>
                          <div>
                            {hasPenalty ? (
                              <span className="inline-flex items-center gap-1 rounded border border-rose-200 bg-rose-50 px-1.5 py-0.5 text-[11px] font-bold text-rose-700">
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
                        <div className="flex items-center gap-2 rounded-md border border-rose-200 bg-rose-50/60 px-2.5 py-1.5 text-xs text-rose-800">
                          <AlertCircle className="h-3.5 w-3.5 shrink-0 text-rose-600" />
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
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">HRCO Assignee</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{detail.hrcoName ?? "Unassigned"}</span>
                          </div>
                        </div>

                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Recruiter</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{detail.recruiterName ?? "Unassigned"}</span>
                          </div>
                        </div>

                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">OM</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{leadership.om}</span>
                          </div>
                        </div>

                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">TL</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{leadership.tl}</span>
                          </div>
                        </div>

                        <div>
                          <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">ATL</span>
                          <div className="mt-0.5 font-semibold text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3 w-3 shrink-0 text-text-muted" />
                            <span className="truncate">{leadership.atl}</span>
                          </div>
                        </div>

                        {isHiredTab ? (
                          <div>
                            <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Deployed By</span>
                            <div className="mt-0.5 font-semibold text-text-primary truncate">
                              {detail.deployedByName ?? "--"}
                            </div>
                          </div>
                        ) : detail.triggeredByName ? (
                          <div>
                            <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Triggered By</span>
                            <div className="mt-0.5 font-semibold text-text-primary truncate">
                              {detail.triggeredByName}
                            </div>
                          </div>
                        ) : (
                          <div>
                            <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted block">Triggered By</span>
                            <div className="mt-0.5 font-semibold text-text-primary truncate">
                              --
                            </div>
                          </div>
                        )}

                        {(detail.hasReliever || detail.relieverOnDuty) && (
                          <div className="col-span-2 pt-1.5 border-t border-border-subtle/50 flex items-center justify-between text-xs">
                            <span className="text-[10px] font-medium uppercase tracking-wider text-text-muted">Reliever on Duty</span>
                            <span className="inline-flex items-center gap-1 rounded bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-800 border border-amber-200">
                              <UserCheck className="h-3 w-3 text-amber-600" />
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
                  <h3 className="text-xs font-semibold uppercase tracking-wider text-text-muted">
                    HRCO Remarks
                  </h3>
                  <p className="text-xs text-text-primary bg-surface-base p-2.5 rounded border border-border-subtle leading-relaxed whitespace-pre-line">
                    {detail.hrcoRemarks.trim()}
                  </p>
                </div>
              )}

              {/* Pipeline / Candidate Summary (omitted for Open vacancies) */}
              {!(status === "open" || detail.derivedStatus?.toLowerCase() === "open" || detail.vacancyStatus?.toLowerCase() === "open") && (
                <div className="rounded-lg border border-border-subtle bg-surface-base p-3 space-y-2">
                  <div className="flex items-center justify-between">
                    <h3 className="text-[11px] font-bold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
                      <Users className="h-3.5 w-3.5 text-brand-600 shrink-0" />
                      <span>Applicant & Pipeline</span>
                    </h3>
                    <div className="flex items-center gap-1.5 text-[11px] text-text-secondary font-medium">
                      <span>{detail.activeApplicantCount} Active</span>
                      <span>&bull;</span>
                      <span>{detail.confirmedOnboardCount} Onboarded</span>
                    </div>
                  </div>

                {/* Active Candidate cards */}
                <div className="space-y-2">
                  {detail.activeApplicantsList && detail.activeApplicantsList.length > 0 ? (
                    detail.activeApplicantsList.map((candidate, index) => {
                      const isCandidateHired =
                        isHired ||
                        candidate.statusLabel.toLowerCase().includes("hired") ||
                        candidate.statusLabel.toLowerCase().includes("confirm");

                      return (
                        <div
                          key={candidate.applicantId || `candidate-${index}`}
                          className="rounded-md border border-border-subtle bg-surface-muted/40 p-2 text-xs hover:bg-surface-muted/70 transition space-y-1.5"
                        >
                          <div className="flex items-center justify-between">
                            <div className="flex items-center gap-2">
                              <div className="flex h-5 w-5 items-center justify-center rounded-full bg-blue-100 text-blue-700 font-bold uppercase text-[9px]">
                                {candidate.displayName.charAt(0)}
                              </div>
                              <div className="font-semibold text-text-primary">
                                {candidate.displayName}
                              </div>
                            </div>
                            <Badge
                              className={`text-[10px] py-0 ${
                                isCandidateHired
                                  ? "border-emerald-200 bg-emerald-50 text-emerald-700"
                                  : "border-purple-200 bg-purple-50 text-purple-700"
                              }`}
                            >
                              {candidate.statusLabel}
                            </Badge>
                          </div>

                          <div className="grid grid-cols-2 gap-1 text-[11px] text-text-secondary pt-1 border-t border-border-subtle/50">
                            {candidate.contactNumber && (
                              <div className="flex items-center gap-1">
                                <Phone className="h-3 w-3 text-text-muted" />
                                <span>{candidate.contactNumber}</span>
                              </div>
                            )}
                            {candidate.onboardDate && (
                              <div className="flex items-center gap-1">
                                <Calendar className="h-3 w-3 text-text-muted" />
                                <span>Onboard: {formatDate(candidate.onboardDate)}</span>
                              </div>
                            )}
                          </div>

                          {/* Quick action buttons for this candidate (Only for active pipeline, not hired) */}
                          {!isCandidateHired && userCanManagePipeline && (
                            <div className="flex items-center justify-end gap-1.5 pt-1.5 border-t border-border-subtle/50">
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
                                className="inline-flex items-center gap-1 rounded bg-purple-50 px-2 py-0.5 text-[11px] font-semibold text-purple-700 border border-purple-200 hover:bg-purple-100 transition"
                              >
                                Update Stage
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
                                className="inline-flex items-center gap-1 rounded bg-emerald-50 px-2 py-0.5 text-[11px] font-semibold text-emerald-700 border border-emerald-200 hover:bg-emerald-100 transition"
                              >
                                Mark Hired
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
                                  setIsFailBackoutModalOpen(true);
                                }}
                                className="inline-flex items-center gap-1 rounded bg-rose-50 px-2 py-0.5 text-[11px] font-semibold text-rose-700 border border-rose-200 hover:bg-rose-100 transition"
                              >
                                Drop / Backout
                              </button>
                            </div>
                          )}
                        </div>
                      );
                    })
                  ) : detail.applicantName ? (
                    <div className="rounded-md border border-border-subtle bg-surface-muted/40 p-2 text-xs">
                      <div className="font-semibold text-text-primary">{detail.applicantName}</div>
                      {detail.contactNumber && (
                        <div className="mt-1 flex items-center gap-1 text-[11px] text-text-secondary">
                          <Phone className="h-3 w-3 text-text-muted" />
                          <span>{detail.contactNumber}</span>
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="text-center py-3 border border-dashed border-border-subtle rounded-md text-xs text-text-muted">
                      No active applicants in pipeline.
                    </div>
                  )}
                </div>
                <div className="text-[10px] text-text-muted flex items-start gap-1">
                  <Lock className="h-3 w-3 shrink-0 mt-0.5 text-text-muted" />
                  <span>PII Guard active: Candidate personal contact details subject to operational scope.</span>
                </div>
              </div>
            )}

              {/* Headcount Origin & Approvals Context - Hidden if completely empty */}
              {hasHeadcountContext && (
                <div className="rounded-lg border border-border-subtle p-3 space-y-2 text-xs bg-surface-base">
                  <h3 className="text-[11px] font-bold uppercase tracking-wider text-text-secondary">
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
                  <div className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-text-secondary">
                    <History className="h-3.5 w-3.5 text-brand-600 shrink-0" />
                    <span>Activity History</span>
                  </div>
                  <div className="relative pl-4 space-y-2.5 border-l-2 border-border-subtle ml-1.5 mt-2">
                    {detail.activityHistory!.map((item, index) => (
                      <div key={item.eventId || `activity-${index}`} className="relative text-xs">
                        {/* Timeline dot */}
                        <div className="absolute -left-[21px] top-0.5 h-2 w-2 rounded-full border-2 border-surface-base bg-brand-500" />
                        <div className="flex justify-between">
                          <span className="font-semibold text-text-primary">{item.eventLabel}</span>
                          <span className="text-[10px] text-text-muted">
                            {formatDate(item.createdAt)}
                          </span>
                        </div>
                        {item.eventDescription && (
                          <p className="mt-0.5 text-text-secondary">{item.eventDescription}</p>
                        )}
                        {item.profileName && (
                          <div className="mt-0.5 text-[10px] text-text-muted">
                            By {item.profileName}
                          </div>
                        )}
                      </div>
                    ))}
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
                      status: detail.pipelineStatus || "pipeline",
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
                      id: detail.vacancyId,
                      fullName: detail.applicantName || "Candidate",
                      status: detail.pipelineStatus || "pipeline",
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
        <div className="h-16 rounded-md bg-gray-100" />
        <div className="h-16 rounded-md bg-gray-100" />
      </div>
      <div className="h-32 rounded-md bg-gray-100" />
      <div className="h-24 rounded-md bg-gray-100" />
      <div className="h-36 rounded-md bg-gray-100" />
      <div className="h-28 rounded-md bg-gray-100" />
    </div>
  );
}

function AccessDeniedState() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <div className="rounded-full bg-red-50 p-3 text-red-600 shadow-xs border border-red-100">
        <ShieldAlert className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-bold text-gray-900">Access Denied</h4>
      <p className="mt-1 text-xs text-gray-500 max-w-xs">
        You do not have permission to view this vacancy record. Access is restricted to your assigned scope.
      </p>
    </div>
  );
}

function NotFoundState() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <div className="rounded-full bg-gray-50 p-3 text-gray-400 border border-gray-100 shadow-xs">
        <AlertCircle className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-bold text-gray-900">Record Not Found</h4>
      <p className="mt-1 text-xs text-gray-500 max-w-xs">
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
      <div className="rounded-full bg-amber-50 p-3 text-amber-600 border border-amber-100 shadow-xs">
        <AlertCircle className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-bold text-gray-900">Unable to Load Details</h4>
      <p className="mt-1 text-xs text-gray-500 max-w-xs">
        {errorMsg}
      </p>
      <button
        className="mt-4 inline-flex items-center gap-1.5 rounded-md border border-gray-200 bg-white px-3 py-1.5 text-xs font-semibold text-gray-700 shadow-sm hover:bg-gray-50 transition"
        onClick={onRetry}
        type="button"
      >
        <RefreshCw className="h-3 w-3" />
        Retry
      </button>
    </div>
  );
}
