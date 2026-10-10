// components/vacancy/VacancyDetailDrawer.tsx
"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  AlertCircle,
  AlertTriangle,
  Calendar,
  History,
  Lock,
  MapPin,
  Phone,
  RefreshCw,
  ShieldAlert,
  User,
  UserCheck,
  Users,
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
  const [isReviseQuotaModalOpen, setIsReviseQuotaModalOpen] = useState(false);
  const [isRequestAdjustmentModalOpen, setIsRequestAdjustmentModalOpen] = useState(false);
  const [isAddApplicantModalOpen, setIsAddApplicantModalOpen] = useState(false);

  const currentUser = useCurrentUser();
  const userRole = currentUser?.roleKey ?? currentUser?.roleName;
  const canReviseQuota = isQuotaOverrideRole(userRole);
  const canRequestAdjustment = isOpsAmendmentRole(userRole);

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
              {[detail.accountName, detail.groupName || "General / Direct", detail.storeName]
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
            <ErrorState errorMsg={error instanceof Error ? error.message : "Unable to load vacancy details"} onRetry={refetch} />
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

              {/* Penalty Exposure Banner */}
              <div className="rounded-md border border-gray-100 p-3 bg-gray-50/50">
                <div className="flex items-center justify-between">
                  <span className="text-[10px] font-semibold uppercase tracking-wider text-gray-400">Penalty Status</span>
                  {detail.hasPenalty || (detail.penaltyAmount !== null && detail.penaltyAmount > 0) || detail.penaltyExposure > 0 ? (
                    <span className="inline-flex items-center gap-1 rounded-md border border-rose-200 bg-rose-50 px-2 py-0.5 text-xs font-bold text-rose-700">
                      <AlertTriangle className="h-3 w-3" />
                      Penalty Active
                    </span>
                  ) : (
                    <span className="inline-flex items-center rounded-md border border-gray-200 bg-white px-2 py-0.5 text-xs font-medium text-gray-600">
                      No Penalty
                    </span>
                  )}
                </div>
                {(detail.hasPenalty || (detail.penaltyAmount !== null && detail.penaltyAmount > 0) || detail.penaltyExposure > 0) && (
                  <div className="mt-2 text-xs text-rose-700 flex items-center justify-between border-t border-rose-100 pt-2">
                    <span className="font-medium">Calculated Penalty Exposure:</span>
                    <span className="text-sm font-bold">
                      {detail.penaltyAmount !== null && detail.penaltyAmount > 0
                        ? `₱${detail.penaltyAmount.toLocaleString()}`
                        : detail.penaltyExposure > 0
                        ? `₱${detail.penaltyExposure.toLocaleString()}`
                        : "Active Rate"}
                    </span>
                  </div>
                )}
              </div>

              {/* Timeline & Operational Dates */}
              <div className="rounded-md border border-gray-100 p-4 space-y-3">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400 flex items-center gap-1.5">
                  <Calendar className="h-3.5 w-3.5" />
                  Timeline & SLA Dates
                </h3>
                <div className="grid grid-cols-2 gap-y-3 text-sm">
                  <div>
                    <div className="text-xs text-gray-400">Vacant Date</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {formatDate(detail.vacantDate)}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Onboard Date</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {formatDate(detail.onboardDate ?? detail.targetFillDate)}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Slot Age (Aging)</div>
                    <div className="mt-0.5">
                      {detail.agingDays !== null ? (
                        <span
                          className={`inline-flex items-center rounded-md px-2 py-0.5 text-xs ${
                            detail.agingDays <= 15
                              ? "border border-emerald-200/80 bg-emerald-50 font-medium text-emerald-700"
                              : detail.agingDays <= 30
                              ? "border border-amber-200/80 bg-amber-50 font-medium text-amber-700"
                              : "border border-rose-200/80 bg-rose-50 font-semibold text-rose-700"
                          }`}
                        >
                          {detail.agingDays} {detail.agingDays === 1 ? "Day" : "Days"}
                        </span>
                      ) : (
                        <span className="text-sm font-medium text-gray-800">--</span>
                      )}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Aging Bucket</div>
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
                      <span className="font-semibold">High SLA Breach Risk:</span> This vacancy has been open for more than 60 days. Prioritize candidate onboarding to minimize operational penalty exposure.
                    </div>
                  </div>
                )}
              </div>

              {/* Store & Operational Scope */}
              <div className="rounded-md border border-gray-100 p-4 space-y-3">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                  Store & Operational Scope
                </h3>
                <div className="grid grid-cols-2 gap-y-3 text-sm">
                  <div>
                    <div className="text-xs text-gray-400">Outlet / Store</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {detail.storeName ?? "--"}
                    </div>
                    {detail.storeLocation && (
                      <div className="text-xs text-gray-500">
                        {detail.storeLocation}
                      </div>
                    )}
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Account / Group</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {[detail.accountName, detail.groupName || "General / Direct"].filter(Boolean).join(" / ") || "--"}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Employment Type</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {detail.employmentType || "Stationary"}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Business Department</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {detail.department ?? "--"}
                    </div>
                  </div>
                  <div className="col-span-2">
                    <div className="text-xs text-gray-400">Reliever on Duty</div>
                    <div className="mt-0.5 flex items-center gap-1.5 font-medium text-gray-800">
                      {detail.hasReliever || detail.relieverOnDuty ? (
                        <span className="inline-flex items-center gap-1 rounded bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-800 border border-amber-200">
                          <UserCheck className="h-3 w-3 text-amber-600" />
                          {detail.relieverOnDuty ?? "Reliever Assigned"}
                        </span>
                      ) : (
                        <span className="text-xs text-gray-500">None Assigned</span>
                      )}
                    </div>
                  </div>
                </div>
              </div>

              {/* HR & Deployment Team */}
              <div className="rounded-md border border-gray-100 p-4 space-y-3">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                  HR & Deployment Assignment
                </h3>
                <div className="grid grid-cols-2 gap-y-3 text-sm">
                  <div>
                    <div className="text-xs text-gray-400">HRCO Assignee</div>
                    <div className="mt-0.5 font-medium text-gray-800 flex items-center gap-1.5">
                      <User className="h-3.5 w-3.5 text-gray-400" />
                      <span>{detail.hrcoName ?? "Unassigned"}</span>
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Recruiter</div>
                    <div className="mt-0.5 font-medium text-gray-800 flex items-center gap-1.5">
                      <User className="h-3.5 w-3.5 text-gray-400" />
                      <span>{detail.recruiterName ?? "Unassigned"}</span>
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Deployed By</div>
                    <div className="mt-0.5 font-medium text-gray-800">
                      {detail.deployedByName ?? "--"}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-400">Contact Number</div>
                    <div className="mt-0.5 font-medium text-gray-800 flex items-center gap-1.5">
                      <Phone className="h-3.5 w-3.5 text-gray-400" />
                      <span>{detail.contactNumber ?? "--"}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* HRCO Remarks */}
              <div className="rounded-md border border-gray-100 p-4 space-y-2">
                <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                  HRCO Remarks
                </h3>
                {detail.hrcoRemarks ? (
                  <p className="text-xs text-gray-700 bg-gray-50 p-2.5 rounded border border-gray-100 leading-relaxed whitespace-pre-line">
                    {detail.hrcoRemarks}
                  </p>
                ) : (
                  <div className="text-xs text-gray-400 italic bg-gray-50/50 p-2.5 rounded border border-dashed border-gray-200">
                    No HRCO operational remarks recorded.
                  </div>
                )}
              </div>

              {/* Pipeline / Candidate Summary */}
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
                    label: "Adjust Quota",
                    isAvailable: canReviseQuota,
                    onClick: () => setIsReviseQuotaModalOpen(true),
                  },
                  {
                    label: "Request HC Adjustment",
                    isAvailable: canRequestAdjustment,
                    onClick: () => setIsRequestAdjustmentModalOpen(true),
                  },
                  {
                    label: "Approve Vacancy",
                    isAvailable: detail.rowCapabilities?.canApprove === true,
                  },
                  {
                    label: "Add Applicant",
                    isAvailable: detail.rowCapabilities?.canUpdateApplicantStatus === true,
                    onClick: () => setIsAddApplicantModalOpen(true),
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

              {/* Headcount Quota Modals */}
              {isReviseQuotaModalOpen && (
                <ReviseHeadcountQuotaModal
                  isOpen={isReviseQuotaModalOpen}
                  onClose={() => setIsReviseQuotaModalOpen(false)}
                  vcode={detail.vcode}
                  storeName={detail.storeName}
                  positionTitle={detail.position_title}
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
