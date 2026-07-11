// components/vacancy/VacancyDetailDrawer.tsx
"use client";

import { useQuery } from "@tanstack/react-query";
import {
  AlertCircle,
  Calendar,
  History,
  Lock,
  MapPin,
  RefreshCw,
  ShieldAlert,
  User,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  getVacancyDetail,
  VacancyDataError,
} from "@/lib/queries/vacancy";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { CapabilityActionBar } from "@/components/shared/CapabilityActionBar";
import { StatusBadge } from "@/components/ui/StatusBadge";

type VacancyDetailDrawerProps = {
  vacancyId: string | null;
  onClose: () => void;
  isFreezeModeActive?: boolean;
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

export function VacancyDetailDrawer({ vacancyId, onClose, isFreezeModeActive = false }: VacancyDetailDrawerProps) {
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

  return (
    <DetailDrawer
      isOpen={!!vacancyId}
      onClose={onClose}
      badge={
        isLoading ? (
          <div className="h-5 w-24 animate-pulse rounded bg-gray-200" />
        ) : detail ? (
          <Badge className="font-mono text-xs font-semibold bg-gray-900 text-white border-none py-1 px-2.5">
            {detail.vcode}
          </Badge>
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
              {[detail.accountName, detail.groupName, detail.storeName]
                .filter(Boolean)
                .join(" / ") || "Global Account"}
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
            <ErrorState errorMsg={error instanceof Error ? error.message : "RPC fetch failure"} onRetry={refetch} />
          ) : !detail ? (
            <NotFoundState />
          ) : (
            <>
              {/* Status & Urgency Badges */}
              <div className="grid grid-cols-2 gap-3">
                <div className="rounded-md border border-gray-100 bg-gray-50 p-2.5">
                  <div className="text-[10px] font-medium uppercase text-gray-400">Queue Status</div>
                  <div className="mt-1 flex items-center gap-1.5">
                    <Badge
                      className={
                        detail.derivedStatus === "Open" || detail.derivedStatus === "open"
                          ? "border-blue-200 bg-blue-50 text-blue-700"
                          : detail.derivedStatus === "pipeline" || detail.derivedStatus === "Pipeline"
                          ? "border-purple-200 bg-purple-50 text-purple-700"
                          : "border-gray-200 bg-gray-50 text-gray-700"
                      }
                    >
                      {detail.derivedStatus ?? detail.vacancyStatus ?? "--"}
                    </Badge>
                  </div>
                </div>

                <div className="rounded-md border border-gray-100 bg-gray-50 p-2.5">
                  <div className="text-[10px] font-medium uppercase text-gray-400">Urgency Level</div>
                  <div className="mt-1">
                    <StatusBadge
                      variant={
                        detail.urgencyLevel === "High"
                          ? "danger"
                          : detail.urgencyLevel === "Medium"
                          ? "warning"
                          : "neutral"
                      }
                      className="font-semibold"
                    >
                      {detail.urgencyLevel ?? "Normal"}
                    </StatusBadge>
                  </div>
                </div>
              </div>

              {/* Operational Metadata */}
              <div className="rounded-md border border-gray-100 p-4 space-y-3">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                  Operational Parameters
                </h3>
                <div className="grid grid-cols-2 gap-y-3 text-sm">
                  <div>
                    <div className="text-xs text-gray-400">Employment Type</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {detail.employmentType ?? "--"}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Business Department</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {detail.department ?? "--"}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">HRCO Assignee</div>
                    <div className="mt-0.5 font-medium text-gray-800 flex items-center gap-1">
                      <User className="h-3.5 w-3.5 text-gray-400" />
                      <span>{detail.hrcoName ?? "Unassigned"}</span>
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Target Fill Date</div>
                    <div className="mt-0.5 font-medium text-gray-800 flex items-center gap-1">
                      <Calendar className="h-3.5 w-3.5 text-gray-400" />
                      <span>{formatDate(detail.targetFillDate)}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* SLA / Aging Section */}
              <div className="rounded-md border border-gray-100 p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                    SLA & Aging Performance
                  </h3>
                  {detail.agingDays !== null && detail.agingDays > 60 && (
                    <StatusBadge variant="danger" className="font-semibold text-[10px]">
                      SLA Warning
                    </StatusBadge>
                  )}
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="text-sm">
                    <div className="text-xs text-gray-400">Slot Age</div>
                    <div className="mt-0.5 text-lg font-bold text-gray-900">
                      {detail.agingDays !== null ? `${detail.agingDays} Days` : "--"}
                    </div>
                  </div>
                  <div className="text-sm">
                    <div className="text-xs text-gray-400">CENCOM Aging Bucket</div>
                    <div className="mt-0.5">
                      <Badge className="border-blue-100 bg-blue-50 text-blue-800 uppercase font-mono text-[10px]">
                        {detail.agingBucket ?? "--"}
                      </Badge>
                    </div>
                  </div>
                </div>
                {detail.agingDays !== null && detail.agingDays > 60 && (
                  <div className="rounded border border-red-100 bg-red-50/50 p-2.5 text-xs text-red-700 flex items-start gap-2">
                    <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
                    <div>
                      <span className="font-semibold">High SLA Breach Risk:</span> This vacancy has been open for more than 60 days. Prioritize applicant onboarding to minimize operational penalty exposure.
                    </div>
                  </div>
                )}
              </div>

              {/* Pipeline / Candidate Summary */}
              <div className="rounded-md border border-gray-100 p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                    Pipeline Candidates
                  </h3>
                  <div className="flex items-center gap-1.5 text-xs text-gray-500 font-medium">
                    <span>{detail.activeApplicantCount} Active</span>
                    <span>&bull;</span>
                    <span>{detail.confirmedOnboardCount} Onboarded</span>
                  </div>
                </div>

                {/* Active Candidate cards */}
                <div className="space-y-2">
                  {detail.activeApplicantsList && detail.activeApplicantsList.length > 0 ? (
                    detail.activeApplicantsList.map((candidate, index) => (
                      <div
                        key={candidate.applicantId || `candidate-${index}`}
                        className="flex items-center justify-between rounded-md border border-gray-100 bg-gray-50/50 p-2 text-xs hover:bg-gray-50 transition"
                      >
                        <div className="flex items-center gap-2">
                          <div className="flex h-6 w-6 items-center justify-center rounded-full bg-blue-100 text-blue-700 font-bold uppercase text-[10px]">
                            {candidate.displayName.charAt(0)}
                          </div>
                          <div>
                            <div className="font-semibold text-gray-800">
                              {candidate.displayName}
                            </div>
                            <div className="text-[10px] text-gray-400">
                              Updated {formatDate(candidate.updatedAt)}
                            </div>
                          </div>
                        </div>
                        <Badge className="border-purple-200 bg-purple-50 text-purple-700 text-[10px] py-0">
                          {candidate.statusLabel}
                        </Badge>
                      </div>
                    ))
                  ) : (
                    <div className="text-center py-4 border border-dashed border-gray-200 rounded-md text-xs text-gray-400">
                      No active applicants in pipeline.
                    </div>
                  )}
                </div>
                <div className="text-[10px] text-gray-400 flex items-start gap-1">
                  <Lock className="h-3 w-3 shrink-0 mt-0.5 text-gray-300" />
                  <span>PII Guard active: Candidate email addresses and contact numbers are shielded.</span>
                </div>
              </div>

              {/* Headcount Origin & Approvals Context */}
              <div className="rounded-md border border-gray-100 p-4 space-y-3 text-sm">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                  Headcount & Approvals Context
                </h3>
                <div className="space-y-2">
                  <div className="flex justify-between border-b border-gray-50 pb-1.5">
                    <span className="text-xs text-gray-400">Headcount Request ID</span>
                    <span className="font-mono text-xs text-gray-700 truncate max-w-[200px]">
                      {detail.headcountRequestId ?? "--"}
                    </span>
                  </div>
                  <div className="flex justify-between border-b border-gray-50 pb-1.5">
                    <span className="text-xs text-gray-400">Vacancy Stated Reason</span>
                    <span className="text-xs text-gray-800 font-medium">
                      {detail.vacancyReason ?? "--"}
                    </span>
                  </div>
                  {detail.approvedByName && (
                    <div className="flex justify-between border-b border-gray-50 pb-1.5">
                      <span className="text-xs text-gray-400">Approved By</span>
                      <span className="text-xs text-gray-800 font-medium">
                        {detail.approvedByName}
                      </span>
                    </div>
                  )}
                  {detail.approvedAt && (
                    <div className="flex justify-between border-b border-gray-50 pb-1.5">
                      <span className="text-xs text-gray-400">Approval Date</span>
                      <span className="text-xs text-gray-800">
                        {formatDate(detail.approvedAt)}
                      </span>
                    </div>
                  )}
                </div>
                {detail.jobDescription && (
                  <div className="mt-3">
                    <div className="text-xs text-gray-400">Job Description & Qualifications</div>
                    <p className="mt-1 text-xs text-gray-600 leading-relaxed bg-gray-50 p-2.5 rounded border border-gray-100">
                      {detail.jobDescription}
                    </p>
                  </div>
                )}
              </div>

              {/* Audit Activity Timeline */}
              <div className="rounded-md border border-gray-100 p-4 space-y-3">
                <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-gray-400">
                  <History className="h-4 w-4 text-gray-400" />
                  <span>Activity History</span>
                </div>
                <div className="relative pl-4 space-y-4 border-l-2 border-gray-100 ml-1.5 mt-2">
                  {detail.activityHistory && detail.activityHistory.length > 0 ? (
                    detail.activityHistory.map((item, index) => (
                      <div key={item.eventId || `activity-${index}`} className="relative text-xs">
                        {/* Timeline dot */}
                        <div className="absolute -left-[21px] top-0.5 h-2.5 w-2.5 rounded-full border-2 border-white bg-blue-500" />
                        <div className="flex justify-between">
                          <span className="font-semibold text-gray-800">{item.eventLabel}</span>
                          <span className="text-[10px] text-gray-400">
                            {formatDate(item.createdAt)}
                          </span>
                        </div>
                        {item.eventDescription && (
                          <p className="mt-0.5 text-gray-500">{item.eventDescription}</p>
                        )}
                        {item.profileName && (
                          <div className="mt-0.5 text-[10px] text-gray-400">
                            By {item.profileName}
                          </div>
                        )}
                      </div>
                    ))
                  ) : (
                    // Default baseline placeholder timeline
                    <div className="relative text-xs">
                      <div className="absolute -left-[21px] top-0.5 h-2.5 w-2.5 rounded-full border-2 border-white bg-blue-500" />
                      <div className="flex justify-between">
                        <span className="font-semibold text-gray-800">Vacancy Created</span>
                        <span className="text-[10px] text-gray-400">
                          {formatDate(detail.vacantDate)}
                        </span>
                      </div>
                      <p className="mt-0.5 text-gray-500">Record initialized on the vacancy list.</p>
                    </div>
                  )}
                </div>
              </div>

              {/* Capability-Aware Action Area */}
              <CapabilityActionBar
                isReadOnlyEmergencyActive={isFreezeModeActive}
                actions={[
                  {
                    label: "Approve Vacancy",
                    isAvailable: detail.rowCapabilities?.canApprove === true,
                  },
                  {
                    label: "Add Applicant",
                    isAvailable: detail.rowCapabilities?.canUpdateApplicantStatus === true,
                  },
                  {
                    label: "Update Applicant Status",
                    isAvailable: detail.rowCapabilities?.canUpdateApplicantStatus === true,
                  },
                  {
                    label: "Request Closure",
                    isAvailable: detail.rowCapabilities?.canRequestClosure === true,
                  },
                ]}
              />
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
        Supabase RLS policies blocked this detail read. You are not authorized to view vacancies outside your scoped account/group boundary.
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
      <h4 className="mt-4 text-sm font-bold text-gray-900">Fetch Failed</h4>
      <p className="mt-1 text-xs text-gray-500 max-w-xs">
        {errorMsg}
      </p>
      <button
        className="mt-4 inline-flex items-center gap-1.5 rounded-md border border-gray-200 bg-white px-3 py-1.5 text-xs font-semibold text-gray-700 shadow-sm hover:bg-gray-50 transition"
        onClick={onRetry}
        type="button"
      >
        <RefreshCw className="h-3 w-3" />
        Retry Query
      </button>
    </div>
  );
}
