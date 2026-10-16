// components/vacancy/VacancyDetailDrawer.tsx
"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
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
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "2-digit",
    year: "numeric",
  }).format(date);
}

function getErrorKind(error: unknown) {
  return error instanceof VacancyDataError ? error.kind : "retryable";
}

function OverviewCard({
  icon: Icon,
  title,
  children,
  headerAction,
}: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  children: React.ReactNode;
  headerAction?: React.ReactNode;
}) {
  return (
    <div className="rounded-xl border border-border-default/80 bg-surface-base p-4 shadow-2xs space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-text-secondary">
          <Icon className="h-4 w-4 text-brand-600 shrink-0" />
          <span>{title}</span>
        </div>
        {headerAction}
      </div>
      {children}
    </div>
  );
}

function OverviewRow({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-start justify-between py-2 border-b border-border-subtle/60 last:border-b-0 text-xs gap-3">
      <span className="text-text-muted font-medium shrink-0 pt-0.5">{label}</span>
      <div className="text-right text-text-primary">{children}</div>
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
  const canReviseQuota = !userRole || isQuotaOverrideRole(userRole);
  const canRequestAdjustment = !userRole || isOpsAmendmentRole(userRole);

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

  if (!vacancyId) return null;

  const errorKind = isError ? getErrorKind(error) : null;

  const isPendingClosure = Boolean(
    detail?.hasPendingClosure ||
    detail?.closureRequestStatus?.toLowerCase() === "pending" ||
    detail?.derivedStatus === "For Closure"
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
        detail ? (
          <CapabilityActionBar
            variant="toolbar"
            isReadOnlyEmergencyActive={isFreezeModeActive}
            actions={[
              {
                label: "Add Applicant",
                isAvailable:
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
                isAvailable: !isPendingClosure && detail.rowCapabilities?.canApprove === true,
                icon: CheckCheck,
                variant: "success",
              },
              {
                label: "Edit Hired Date",
                isAvailable:
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
                    {/* 1. Vacancy Summary Card */}
                    <OverviewCard icon={FileText} title="Vacancy Summary">
                      <OverviewRow label="VCode">
                        <span className="font-mono text-xs font-semibold bg-gray-900 text-white py-0.5 px-2 rounded">
                          {detail.vcode}
                        </span>
                      </OverviewRow>
                      <OverviewRow label="Source">
                        <span className="font-semibold">
                          {detail.source || (detail.vcode.startsWith("CG-") ? "Coverage Group" : "Plantilla")}
                        </span>
                      </OverviewRow>
                      <OverviewRow label="Vacancy Type">
                        <span className="font-semibold">
                          {detail.vacancyType || (detail.source === "Plantilla" ? "Replacement" : "New Demand")}
                        </span>
                      </OverviewRow>
                      <OverviewRow label="Urgency Level">
                        <StatusBadge variant={urgencyVariant} className="text-xs py-0.5 px-2 font-semibold">
                          {detail.urgencyLevel ?? "Normal"}
                        </StatusBadge>
                      </OverviewRow>
                    </OverviewCard>

                    {/* 2. Assignment Card */}
                    <OverviewCard icon={Building2} title="Assignment">
                      <OverviewRow label="Group">
                        <span className="font-semibold">
                          {detail.groupName || "General / Direct"}
                        </span>
                      </OverviewRow>
                      <OverviewRow label="Account">
                        <span className="font-semibold">
                          {detail.accountName || "--"}
                        </span>
                      </OverviewRow>
                      <OverviewRow label={storesList.length > 1 ? "Store Names" : "Store Name"}>
                        {storesList.length > 1 ? (
                          <div className="flex flex-col items-end gap-1 text-right">
                            {storesList.map((st, i) => (
                              <span key={i} className="font-semibold text-text-primary text-xs">
                                {st}
                              </span>
                            ))}
                          </div>
                        ) : (
                          <span className="font-semibold text-text-primary">
                            {storesList[0] || "--"}
                          </span>
                        )}
                      </OverviewRow>
                      <OverviewRow label="Province / City">
                        <span className="font-semibold">
                          {[detail.areaProvince, detail.areaCity].filter(Boolean).join(" / ") || detail.storeLocation || "--"}
                        </span>
                      </OverviewRow>
                      {detail.employmentType && (
                        <OverviewRow label="Employment Type">
                          <span className="font-semibold">
                            {detail.employmentType}
                          </span>
                        </OverviewRow>
                      )}
                    </OverviewCard>

                    {/* 3. Requirements Card */}
                    <OverviewCard
                      icon={ClipboardList}
                      title="Requirements"
                      headerAction={
                        <div className="flex items-center gap-1.5">
                          {canReviseQuota && (
                            <button
                              type="button"
                              onClick={() => setIsReviseQuotaModalOpen(true)}
                              className="inline-flex items-center gap-1 text-[11px] font-semibold text-brand-700 hover:text-brand-800 bg-brand-50 hover:bg-brand-100 border border-brand-200/80 px-2 py-0.5 rounded transition shadow-2xs"
                            >
                              <SlidersHorizontal className="h-3 w-3" />
                              Adjust Quota
                            </button>
                          )}
                          {canRequestAdjustment && (
                            <button
                              type="button"
                              onClick={() => setIsRequestAdjustmentModalOpen(true)}
                              className="inline-flex items-center gap-1 text-[11px] font-semibold text-text-secondary hover:text-text-primary bg-surface-muted hover:bg-surface-hover border border-border-default px-2 py-0.5 rounded transition shadow-2xs"
                            >
                              <FileText className="h-3 w-3" />
                              Request HC Adjustment
                            </button>
                          )}
                        </div>
                      }
                    >
                      {detail.requirements && detail.requirements.length > 0 ? (
                        <div className="space-y-2">
                          {detail.requirements.map((req, idx) => {
                            const avail = Math.max(0, req.hcNeeded - req.hcFilled);
                            return (
                              <div
                                key={req.id || `req-${idx}`}
                                className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 py-1.5 border-b border-border-subtle/60 last:border-b-0 text-xs"
                              >
                                <div className="font-semibold text-text-primary">{req.positionName}</div>
                                <div className="text-text-secondary font-medium shrink-0">
                                  Hired: <span className="font-bold text-text-primary">{req.hcFilled}/{req.hcNeeded}</span> • Pipeline: <span className="font-bold text-text-primary">{req.pipelineCount}</span> • Available: <span className="font-bold text-text-primary">{avail}</span>
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      ) : (
                        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1 py-1 text-xs">
                          <div className="font-semibold text-text-primary text-sm">
                            {detail.position_title ?? "Position Title"}
                          </div>
                          <div className="text-text-secondary font-medium shrink-0 text-xs">
                            Hired: <span className="font-bold text-text-primary">{hiredCount}/{totalHc}</span> • Pipeline: <span className="font-bold text-text-primary">{pipelineCount}</span> • Available: <span className="font-bold text-text-primary">{availableSlots}</span>
                          </div>
                        </div>
                      )}
                    </OverviewCard>

                    {/* 4. Timeline Card */}
                    <OverviewCard icon={Calendar} title="Timeline">
                      <div className="grid grid-cols-3 gap-3">
                        <div>
                          <div className="text-[11px] text-text-muted font-medium">Vacant Since</div>
                          <div className="mt-1 text-xs sm:text-sm font-bold text-text-primary">
                            {formatDate(detail.vacantDate)}
                          </div>
                        </div>
                        <div>
                          <div className="text-[11px] text-text-muted font-medium">Target Fill Date</div>
                          <div className="mt-1 text-xs sm:text-sm font-bold text-text-primary">
                            {detail.source === "Plantilla" ? "-" : formatDate(detail.targetFillDate)}
                          </div>
                        </div>
                        <div>
                          <div className="text-[11px] text-text-muted font-medium">Date Created</div>
                          <div className="mt-1 text-xs sm:text-sm font-bold text-text-primary">
                            {formatDate(detail.createdAt || detail.vacantDate)}
                          </div>
                        </div>
                      </div>

                      {(detail.agingDays !== null || hasPenalty) && (
                        <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-border-subtle/60 text-xs">
                          <div className="flex items-center gap-2">
                            <span className="text-[11px] text-text-muted">Slot Aging:</span>
                            {detail.agingDays !== null ? (
                              <span
                                className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs font-semibold ${
                                  detail.agingDays <= 15
                                    ? "border border-emerald-200/80 bg-emerald-50 text-emerald-700"
                                    : detail.agingDays <= 30
                                    ? "border border-amber-200/80 bg-amber-50 text-amber-700"
                                    : "border border-rose-200/80 bg-rose-50 text-rose-700"
                                }`}
                              >
                                {detail.agingDays} {detail.agingDays === 1 ? "Day" : "Days"}
                              </span>
                            ) : (
                              <span className="font-medium text-text-primary">--</span>
                            )}
                            {detail.agingBucket && (
                              <Badge className="border-blue-100 bg-blue-50 text-blue-800 uppercase font-mono text-[10px] py-0 px-1.5">
                                {detail.agingBucket}
                              </Badge>
                            )}
                          </div>
                          <div>
                            {hasPenalty ? (
                              <span className="inline-flex items-center gap-1 rounded-md border border-rose-200 bg-rose-50 px-2 py-0.5 text-xs font-bold text-rose-700">
                                <AlertTriangle className="h-3 w-3" />
                                Penalty Active {penaltyFormatted ? `(${penaltyFormatted})` : ""}
                              </span>
                            ) : (
                              <span className="text-[11px] text-text-muted">No Penalty</span>
                            )}
                          </div>
                        </div>
                      )}
                      {detail.agingDays !== null && detail.agingDays > 60 && (
                        <div className="rounded border border-red-100 bg-red-50/50 p-2 text-xs text-red-700 flex items-start gap-2 mt-1">
                          <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
                          <div>
                            <span className="font-semibold">High SLA Breach Risk:</span> This vacancy has been open for more than 60 days. Prioritize candidate onboarding to minimize operational penalty exposure.
                          </div>
                        </div>
                      )}
                    </OverviewCard>

                    {/* 5. Ownership & Operational Scope Card */}
                    <OverviewCard icon={User} title="Ownership & Assigned Team">
                      <div className="grid grid-cols-2 gap-x-4 gap-y-3 text-xs">
                        <div>
                          <div className="text-[11px] text-text-muted">HRCO Assignee</div>
                          <div className="mt-0.5 font-medium text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3.5 w-3.5 shrink-0 text-text-muted" />
                            <span className="truncate">{detail.hrcoName ?? "Unassigned"}</span>
                          </div>
                        </div>

                        <div>
                          <div className="text-[11px] text-text-muted">Recruiter</div>
                          <div className="mt-0.5 font-medium text-text-primary flex items-center gap-1.5 truncate">
                            <User className="h-3.5 w-3.5 shrink-0 text-text-muted" />
                            <span className="truncate">{detail.recruiterName ?? "Unassigned"}</span>
                          </div>
                        </div>

                        {isHiredTab ? (
                          <div>
                            <div className="text-[11px] text-text-muted">Deployed By</div>
                            <div className="mt-0.5 font-medium text-text-primary truncate">
                              {detail.deployedByName ?? "--"}
                            </div>
                            {detail.contactNumber && (
                              <div className="mt-0.5 flex items-center gap-1 text-[10px] text-text-secondary truncate">
                                <Phone className="h-3 w-3 shrink-0 text-text-muted" />
                                <span>{detail.contactNumber}</span>
                              </div>
                            )}
                          </div>
                        ) : detail.triggeredByName ? (
                          <div>
                            <div className="text-[11px] text-text-muted">Triggered By</div>
                            <div className="mt-0.5 font-medium text-text-primary truncate">
                              {detail.triggeredByName}
                            </div>
                          </div>
                        ) : null}

                        <div>
                          <div className="text-[11px] text-text-muted">Department</div>
                          <div className="mt-0.5 font-medium text-text-primary truncate">
                            {detail.department || "Operations"}
                          </div>
                        </div>

                        {(detail.hasReliever || detail.relieverOnDuty) && (
                          <div className="col-span-2 pt-2 border-t border-border-subtle/60 flex items-center justify-between">
                            <span className="text-[11px] text-text-muted">Reliever on Duty</span>
                            <span className="inline-flex items-center gap-1 rounded bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-800 border border-amber-200">
                              <UserCheck className="h-3 w-3 text-amber-600" />
                              {detail.relieverOnDuty ?? "Reliever Assigned"}
                            </span>
                          </div>
                        )}
                      </div>
                    </OverviewCard>
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
                <div className="rounded-md border border-gray-100 p-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400 flex items-center gap-1.5">
                      <Users className="h-3.5 w-3.5" />
                      Applicant & Pipeline Information
                    </h3>
                    <div className="flex items-center gap-1.5 text-xs text-gray-500 font-medium">
                      <span>{detail.activeApplicantCount} Active</span>
                      <span>&bull;</span>
                      <span>{detail.confirmedOnboardCount} Onboarded</span>
                    </div>
                  </div>

                {/* Active Candidate cards */}
                <div className="space-y-2.5">
                  {detail.activeApplicantsList && detail.activeApplicantsList.length > 0 ? (
                    detail.activeApplicantsList.map((candidate, index) => (
                      <div
                        key={candidate.applicantId || `candidate-${index}`}
                        className="rounded-md border border-gray-100 bg-gray-50/50 p-2.5 text-xs hover:bg-gray-50 transition space-y-1.5"
                      >
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2">
                            <div className="flex h-6 w-6 items-center justify-center rounded-full bg-blue-100 text-blue-700 font-bold uppercase text-[10px]">
                              {candidate.displayName.charAt(0)}
                            </div>
                            <div>
                              <div className="font-semibold text-gray-800">
                                {candidate.displayName}
                              </div>
                              {candidate.lastName && candidate.firstName && (
                                <div className="text-[11px] text-gray-500">
                                  {candidate.lastName}, {candidate.firstName}
                                </div>
                              )}
                            </div>
                          </div>
                          <Badge className="border-purple-200 bg-purple-50 text-purple-700 text-[10px] py-0">
                            {candidate.statusLabel}
                          </Badge>
                        </div>

                        <div className="grid grid-cols-2 gap-1 text-[11px] text-gray-500 pt-1 border-t border-gray-100">
                          {candidate.contactNumber && (
                            <div className="flex items-center gap-1">
                              <Phone className="h-3 w-3 text-gray-400" />
                              <span>{candidate.contactNumber}</span>
                            </div>
                          )}
                          {candidate.onboardDate && (
                            <div className="flex items-center gap-1">
                              <Calendar className="h-3 w-3 text-gray-400" />
                              <span>Onboard: {formatDate(candidate.onboardDate)}</span>
                            </div>
                          )}
                          <div className="text-[10px] text-gray-400 col-span-2">
                            Updated {formatDate(candidate.updatedAt)}
                          </div>
                        </div>

                        {/* Quick action buttons for this candidate */}
                        <div className="flex items-center justify-end gap-1.5 pt-1.5 border-t border-gray-100">
                          {candidate.statusLabel.toLowerCase() !== "hired" && candidate.statusLabel.toLowerCase() !== "confirmed" ? (
                            <>
                              <button
                                type="button"
                                onClick={() => {
                                  setSelectedCandidate({
                                    id: candidate.applicantId,
                                    fullName: candidate.displayName,
                                    lastName: candidate.lastName,
                                    firstName: candidate.firstName,
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
                            </>
                          ) : (
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedCandidate({
                                  id: candidate.applicantId,
                                  fullName: candidate.displayName,
                                  lastName: candidate.lastName,
                                  firstName: candidate.firstName,
                                  contactNumber: candidate.contactNumber,
                                  status: candidate.statusLabel,
                                  vcode: detail.vcode,
                                  positionTitle: detail.position_title,
                                  hiredDate: candidate.onboardDate,
                                });
                                setIsEditHiredDateModalOpen(true);
                              }}
                              className="inline-flex items-center gap-1 rounded bg-blue-50 px-2 py-0.5 text-[11px] font-semibold text-blue-700 border border-blue-200 hover:bg-blue-100 transition"
                            >
                              Edit Hired Date
                            </button>
                          )}
                        </div>
                      </div>
                    ))
                  ) : detail.applicantName ? (
                    <div className="rounded-md border border-gray-100 bg-gray-50/50 p-2.5 text-xs">
                      <div className="font-semibold text-gray-800">{detail.applicantName}</div>
                      {detail.contactNumber && (
                        <div className="mt-1 flex items-center gap-1 text-[11px] text-gray-500">
                          <Phone className="h-3 w-3 text-gray-400" />
                          <span>{detail.contactNumber}</span>
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="text-center py-4 border border-dashed border-gray-200 rounded-md text-xs text-gray-400">
                      No active applicants in pipeline.
                    </div>
                  )}
                </div>
                <div className="text-[10px] text-gray-400 flex items-start gap-1">
                  <Lock className="h-3 w-3 shrink-0 mt-0.5 text-gray-300" />
                  <span>PII Guard active: Candidate personal contact details subject to operational scope.</span>
                </div>
              </div>
            )}

              {/* Headcount Origin & Approvals Context - Hidden if completely empty */}
              {hasHeadcountContext && (
                <div className="rounded-lg border border-border-subtle p-3.5 space-y-2.5 text-xs bg-surface-base">
                  <h3 className="text-xs font-semibold uppercase tracking-wider text-text-muted">
                    Headcount & Approvals Context
                  </h3>
                  <div className="space-y-2">
                    {detail.headcountRequestId && (
                      <div className="flex justify-between border-b border-border-subtle/50 pb-1.5">
                        <span className="text-[11px] text-text-muted">Headcount Request ID</span>
                        <span className="font-mono text-xs text-text-primary truncate max-w-[200px]">
                          {detail.headcountRequestId}
                        </span>
                      </div>
                    )}
                    {detail.vacancyReason && (
                      <div className="flex justify-between border-b border-border-subtle/50 pb-1.5">
                        <span className="text-[11px] text-text-muted">Vacancy Stated Reason</span>
                        <span className="text-xs text-text-primary font-medium">
                          {detail.vacancyReason}
                        </span>
                      </div>
                    )}
                    {detail.approvedByName && (
                      <div className="flex justify-between border-b border-border-subtle/50 pb-1.5">
                        <span className="text-[11px] text-text-muted">Approved By</span>
                        <span className="text-xs text-text-primary font-medium">
                          {detail.approvedByName}
                        </span>
                      </div>
                    )}
                    {detail.approvedAt && (
                      <div className="flex justify-between border-b border-border-subtle/50 pb-1.5">
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
                      <p className="text-xs text-text-secondary leading-relaxed bg-surface-muted/50 p-2.5 rounded border border-border-subtle whitespace-pre-line">
                        {detail.jobDescription}
                      </p>
                    </div>
                  )}
                </div>
              )}

              {/* Audit Activity Timeline - Hidden when no real audit logs exist */}
              {hasActivityLogs && (
                <div className="rounded-lg border border-border-subtle p-3.5 space-y-3 bg-surface-base">
                  <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-text-muted">
                    <History className="h-3.5 w-3.5 text-text-muted" />
                    <span>Activity History</span>
                  </div>
                  <div className="relative pl-4 space-y-3 border-l-2 border-border-subtle ml-1.5 mt-2">
                    {detail.activityHistory!.map((item, index) => (
                      <div key={item.eventId || `activity-${index}`} className="relative text-xs">
                        {/* Timeline dot */}
                        <div className="absolute -left-[21px] top-0.5 h-2.5 w-2.5 rounded-full border-2 border-surface-base bg-brand-500" />
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
