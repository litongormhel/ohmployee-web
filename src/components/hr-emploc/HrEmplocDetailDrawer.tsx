// components/hr-emploc/HrEmplocDetailDrawer.tsx
"use client";

import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  AlertCircle,
  AlertTriangle,
  Calendar,
  CheckCircle2,
  FileDown,
  FileText,
  History,
  Loader2,
  MapPin,
  RefreshCw,
  ShieldAlert,
  User,
  X,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { CapabilityActionBar } from "@/components/shared/CapabilityActionBar";
import {
  getWebHrEmplocDetail,
  tagWebHrEmplocDeficiency,
  reviewWebHrEmplocCorrection,
  HrEmplocDataError,
  type TagDeficiencyParams,
  type ReviewCorrectionParams,
} from "@/lib/queries/hr_emploc";

type HrEmplocDetailDrawerProps = {
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

const canonicalRequirements = [
  { key: "sss_card", label: "SSS Card / ID Document" },
  { key: "pagibig_id", label: "PagIBIG Member ID" },
  { key: "philhealth_id", label: "PhilHealth ID / MDF" },
  { key: "nbi_clearance", label: "NBI Clearance Certificate" },
  { key: "birth_certificate", label: "PSA Birth Certificate" },
];

export function HrEmplocDetailDrawer({
  hrEmplocId,
  onClose,
}: HrEmplocDetailDrawerProps) {
  const [isTagModalOpen, setIsTagModalOpen] = useState(false);
  const [isReviewModalOpen, setIsReviewModalOpen] = useState(false);

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
  const isPendingDeletion = detail
    ? detail.hrStatus.toLowerCase().trim() === "pending deletion" ||
      detail.hrStatus.toLowerCase().trim() === "pending_deletion"
    : false;

  // Function to check if a requirement is flagged as deficient
  const isRequirementDeficient = (reqKey: string): boolean => {
    if (!detail?.correctionReason) return false;
    const normKey = reqKey.toLowerCase().replace(/_/g, "");
    return Object.keys(detail.correctionReason).some((k) => {
      const normK = k.toLowerCase().replace(/_/g, "");
      return normK.includes(normKey) || normKey.includes(normK);
    });
  };

  const getDeficiencyComment = (reqKey: string): string | null => {
    if (!detail?.correctionReason) return null;
    const normKey = reqKey.toLowerCase().replace(/_/g, "");
    const matchingKey = Object.keys(detail.correctionReason).find((k) => {
      const normK = k.toLowerCase().replace(/_/g, "");
      return normK.includes(normKey) || normKey.includes(normK);
    });
    if (!matchingKey) return null;
    const val = detail.correctionReason[matchingKey];
    return typeof val === "string" ? val : JSON.stringify(val);
  };

  return (
    <DetailDrawer
      isOpen={!!hrEmplocId}
      onClose={onClose}
      widthClass="w-[var(--drawer-width-lg)] max-w-full"
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
          <span className={isPendingDeletion ? "text-gray-500 line-through" : ""}>
            {detail.applicantName}
          </span>
        ) : (
          "Compliance Placement Detail"
        )
      }
      subtitle={
        !isLoading && detail && (
          <>
            <MapPin className="h-3 w-3 shrink-0 text-gray-400" />
            <span className="truncate">
              {[detail.accountName, detail.storeName]
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
        <ErrorState
          errorMsg={error instanceof Error ? error.message : "RPC fetch failure"}
          onRetry={refetch}
        />
      ) : !detail ? (
        <NotFoundState />
      ) : (
        <>
          {/* Active Deletion Overlay / Locking Banner */}
          {isPendingDeletion && (
            <div className="rounded-md border border-red-200 bg-red-50 p-4 space-y-2">
              <div className="flex items-start gap-2.5">
                <AlertTriangle className="h-5 w-5 text-red-600 shrink-0 mt-0.5" />
                <div className="space-y-1">
                  <h4 className="text-xs font-bold text-red-800 uppercase tracking-wide">
                    Record Locked: Pending Deletion
                  </h4>
                  <p className="text-xs text-red-700 leading-relaxed">
                    This allocation is currently subject to a separation or duplicate record separation request. All audits, corrections, employee ID assignments, and deployment triggers are strictly locked.
                  </p>
                </div>
              </div>
              {detail.activeDeletionRequest && (
                <div className="mt-3 border-t border-red-100 pt-2.5 text-xs text-red-800 space-y-1.5 bg-red-100/30 p-2.5 rounded-sm">
                  <div className="grid grid-cols-2 gap-y-1">
                    <div>
                      <span className="font-semibold">Request Type:</span>{" "}
                      <span className="capitalize">{detail.activeDeletionRequest.deletionType}</span>
                    </div>
                    <div>
                      <span className="font-semibold">Requested By:</span>{" "}
                      {detail.activeDeletionRequest.requestedBy}
                    </div>
                    <div>
                      <span className="font-semibold">Requested At:</span>{" "}
                      {formatDate(detail.activeDeletionRequest.requestedAt)}
                    </div>
                    {detail.activeDeletionRequest.originalEmplocId && (
                      <div className="col-span-2">
                        <span className="font-semibold">Original Record ID:</span>{" "}
                        <span className="font-mono text-[10px] bg-red-100 p-0.5 rounded">
                          {detail.activeDeletionRequest.originalEmplocId}
                        </span>
                      </div>
                    )}
                  </div>
                  <div className="border-t border-red-200/50 pt-1.5">
                    <span className="font-semibold">Reason:</span>{" "}
                    <span className="italic">&quot;{detail.activeDeletionRequest.reason}&quot;</span>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Status & SLA Metrics Row */}
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-md border border-gray-100 bg-gray-50 p-2.5">
              <div className="text-[10px] font-medium uppercase text-gray-400">
                Deployment Status
              </div>
              <div className="mt-1 flex items-center gap-1.5">
                <span className="text-xs font-semibold text-gray-700 bg-white border border-gray-200 rounded px-2 py-0.5">
                  {detail.deploymentStatus}
                </span>
              </div>
            </div>

            <div className="rounded-md border border-gray-100 bg-gray-50 p-2.5">
              <div className="text-[10px] font-medium uppercase text-gray-400">
                HR Status
              </div>
              <div className="mt-1">
                <StatusBadge
                  variant={
                    detail.hrStatus.toLowerCase().includes("complete")
                      ? "success"
                      : detail.hrStatus.toLowerCase().includes("correction")
                      ? "warning"
                      : detail.hrStatus.toLowerCase().includes("deletion")
                      ? "danger"
                      : "info"
                  }
                  className="font-semibold"
                >
                  {detail.hrStatus}
                </StatusBadge>
              </div>
            </div>
          </div>

          {/* Operational Metadata Grid */}
          <div className="rounded-md border border-gray-100 p-4 space-y-3 bg-white">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
              Placement Parameters
            </h3>
            <div className="grid grid-cols-2 gap-y-3 text-sm">
              <div>
                <div className="text-xs text-gray-400">Assignment Type</div>
                <div className="mt-0.5 font-medium text-gray-800">
                  {detail.assignmentType ?? "Stationary"}
                </div>
              </div>
              <div>
                <div className="text-xs text-gray-400">Position Title</div>
                <div className="mt-0.5 font-medium text-gray-800">
                  {detail.positionTitle ?? "--"}
                </div>
              </div>
              <div>
                <div className="text-xs text-gray-400">HRCO Coordinator</div>
                <div className="mt-0.5 font-medium text-gray-800 flex items-center gap-1">
                  <User className="h-3.5 w-3.5 text-gray-400" />
                  <span>{detail.hrcoName ?? "Unassigned"}</span>
                </div>
              </div>
              <div>
                <div className="text-xs text-gray-400">Hired Date</div>
                <div className="mt-0.5 font-medium text-gray-800 flex items-center gap-1">
                  <Calendar className="h-3.5 w-3.5 text-gray-400" />
                  <span>{formatDate(detail.hiredDate)}</span>
                </div>
              </div>
              {detail.employeeNo && (
                <div>
                  <div className="text-xs text-gray-400">Employee Number</div>
                  <div className="mt-0.5">
                    <Badge className="font-mono text-xs bg-emerald-50 text-emerald-700 border-emerald-200">
                      {detail.employeeNo}
                    </Badge>
                  </div>
                </div>
              )}
            </div>

            {/* Roving Covered Stores list */}
            {detail.assignmentType === "Roving" && detail.coveredStores && detail.coveredStores.length > 0 && (
              <div className="mt-3 border-t border-gray-100 pt-3">
                <div className="text-xs text-gray-400 mb-1.5">Roving Covered Stores</div>
                <div className="grid gap-1.5">
                  {detail.coveredStores.map((store) => (
                    <div
                      key={store.storeId}
                      className="text-xs bg-gray-50 border border-gray-100 rounded p-2 flex items-start gap-2"
                    >
                      <MapPin className="h-3.5 w-3.5 text-purple-500 shrink-0 mt-0.5" />
                      <div>
                        <div className="font-semibold text-gray-800">{store.storeName}</div>
                        {store.address && <div className="text-[10px] text-gray-400">{store.address}</div>}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* SLA Performance Section */}
          <div className="rounded-md border border-gray-100 p-4 space-y-3 bg-white">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                SLA & Aging Performance
              </h3>
              {detail.slaBreached && (
                <StatusBadge variant="danger" className="font-semibold text-[10px]">
                  SLA Breached
                </StatusBadge>
              )}
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="text-sm">
                <div className="text-xs text-gray-400">Elapsed Compliance Time</div>
                <div className="mt-0.5 text-lg font-bold text-gray-900">
                  {detail.slaElapsedDays} Days
                </div>
              </div>
              <div className="text-sm">
                <div className="text-xs text-gray-400">Baseline Request Date</div>
                <div className="mt-0.5 font-medium text-gray-800">
                  {formatDate(detail.dateRequested)}
                </div>
              </div>
            </div>

            {/* SLA Escalation Levels Alerts */}
            {detail.slaElapsedDays >= 5 ? (
              <div className="rounded border border-red-200 bg-red-50 p-3 text-xs text-red-800 flex items-start gap-2">
                <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
                <div>
                  <span className="font-bold">SLA Escalation Tier 2:</span> This record has languished for <span className="font-bold">{detail.slaElapsedDays} days</span>. A critical alert has been escalated to the <span className="font-semibold text-red-900">Super Admin</span>. Document verification must be finalized immediately.
                </div>
              </div>
            ) : detail.slaElapsedDays >= 3 ? (
              <div className="rounded border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 flex items-start gap-2">
                <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-amber-600" />
                <div>
                  <span className="font-bold">SLA Escalation Tier 1:</span> Compliance audit is pending past the <span className="font-bold">3-day SLA threshold</span>. An operational notice has been sent to the <span className="font-semibold text-amber-900">Head Admin</span>.
                </div>
              </div>
            ) : null}
          </div>

          {/* Requirements Compliance Checklist & Deficiencies */}
          <div className="rounded-md border border-gray-100 p-4 space-y-3 bg-white">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
              Onboarding Requirements Compliance
            </h3>
            <div className="grid gap-2">
              {canonicalRequirements.map((req) => {
                const isDeficient = isRequirementDeficient(req.key);
                const comment = getDeficiencyComment(req.key);

                return (
                  <div
                    key={req.key}
                    className={`rounded-md border p-2.5 text-xs transition-colors ${
                      isDeficient
                        ? "border-amber-200 bg-amber-50/30"
                        : "border-gray-100 bg-gray-50/30"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        {isDeficient ? (
                          <AlertTriangle className="h-4 w-4 text-amber-600 shrink-0" />
                        ) : (
                          <CheckCircle2 className="h-4 w-4 text-emerald-600 shrink-0" />
                        )}
                        <span className={`font-semibold ${isDeficient ? "text-amber-800" : "text-gray-800"}`}>
                          {req.label}
                        </span>
                      </div>
                      <Badge
                        className={`text-[9px] py-0 border ${
                          isDeficient
                            ? "border-amber-200 bg-amber-50 text-amber-700 hover:bg-amber-50"
                            : "border-emerald-200 bg-emerald-50 text-emerald-700 hover:bg-emerald-50"
                        }`}
                      >
                        {isDeficient ? "deficient" : "compliant"}
                      </Badge>
                    </div>
                    {isDeficient && comment && (
                      <div className="mt-1.5 pl-6 border-l border-amber-200/50 py-0.5 text-amber-800 text-[11px] leading-relaxed">
                        <span className="font-bold">Tag Note:</span> {comment}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* Custom Remarks Section */}
            {(detail.hrRemarks || detail.opsRemarks) && (
              <div className="mt-3 pt-3 border-t border-gray-100 space-y-2">
                {detail.hrRemarks && (
                  <div>
                    <div className="text-[10px] font-semibold uppercase text-gray-400">
                      HR Compliance Remarks
                    </div>
                    <p className="mt-1 text-xs text-gray-700 leading-relaxed bg-slate-50 p-2.5 rounded border border-slate-100 italic">
                      &quot;{detail.hrRemarks}&quot;
                    </p>
                  </div>
                )}
                {detail.opsRemarks && (
                  <div>
                    <div className="text-[10px] font-semibold uppercase text-gray-400">
                      Ops Coordinator Remarks
                    </div>
                    <p className="mt-1 text-xs text-gray-700 leading-relaxed bg-slate-50 p-2.5 rounded border border-slate-100 italic">
                      &quot;{detail.opsRemarks}&quot;
                    </p>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Corrected File Attachments viewer */}
          <div className="rounded-md border border-gray-100 p-4 space-y-3 bg-white">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
                Correction Submissions & Attachments
              </h3>
              <Badge className="bg-gray-100 text-gray-600 hover:bg-gray-100 border-none text-[10px]">
                {detail.uploadedAttachments.length} Files
              </Badge>
            </div>

            {detail.uploadedAttachments.length > 0 ? (
              <div className="space-y-2">
                {detail.uploadedAttachments.map((file) => (
                  <div
                    key={file.attachmentId}
                    className="flex items-center justify-between rounded-md border border-gray-100 bg-gray-50/50 p-2.5 hover:bg-gray-50 transition"
                  >
                    <div className="flex items-center gap-2.5 min-w-0">
                      <div className="p-1.5 bg-blue-50 rounded border border-blue-100 text-blue-600">
                        <FileText className="h-4 w-4" />
                      </div>
                      <div className="min-w-0">
                        <a
                          className="text-xs font-semibold text-blue-600 hover:underline truncate block"
                          href={file.fileUrl}
                          rel="noreferrer"
                          target="_blank"
                        >
                          {file.fileName}
                        </a>
                        <div className="text-[10px] text-gray-400 flex flex-wrap gap-x-2">
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
                    <a
                      aria-label={`Download file ${file.fileName}`}
                      className="inline-flex h-7 w-7 items-center justify-center rounded border border-gray-200 bg-white text-gray-500 hover:bg-gray-100 hover:text-gray-700 transition"
                      download
                      href={file.fileUrl}
                      rel="noreferrer"
                      target="_blank"
                    >
                      <FileDown className="h-4 w-4" />
                    </a>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-center py-5 border border-dashed border-gray-100 rounded-md text-xs text-gray-400">
                No corrected compliance files uploaded yet.
              </div>
            )}
          </div>

          {/* Audit Timeline Section */}
          <div className="rounded-md border border-gray-100 p-4 space-y-3 bg-white">
            <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-gray-400">
              <History className="h-4 w-4 text-gray-400" />
              <span>Activity History Trail</span>
            </div>
            <div className="relative pl-4 space-y-4 border-l-2 border-gray-100 ml-1.5 mt-2">
              {detail.auditLogsTimeline && detail.auditLogsTimeline.length > 0 ? (
                detail.auditLogsTimeline.map((item) => (
                  <div key={item.eventId} className="relative text-xs">
                    {/* Timeline dot */}
                    <div className="absolute -left-[21px] top-0.5 h-2.5 w-2.5 rounded-full border-2 border-white bg-blue-500" />
                    <div className="flex justify-between">
                      <span className="font-semibold text-gray-800">{item.eventLabel}</span>
                      <span className="text-[10px] text-gray-400">
                        {formatDateTime(item.createdAt)}
                      </span>
                    </div>
                    {item.eventDescription && (
                      <p className="mt-0.5 text-gray-500 leading-relaxed">
                        {item.eventDescription}
                      </p>
                    )}
                    {item.profileName && (
                      <div className="mt-0.5 text-[9px] text-gray-400">
                        Triggered by: {item.profileName}
                      </div>
                    )}
                  </div>
                ))
              ) : (
                <div className="relative text-xs">
                  <div className="absolute -left-[21px] top-0.5 h-2.5 w-2.5 rounded-full border-2 border-white bg-blue-500" />
                  <div className="flex justify-between">
                    <span className="font-semibold text-gray-800">Placement Confirmed</span>
                    <span className="text-[10px] text-gray-400">
                      {formatDate(detail.dateRequested)}
                    </span>
                  </div>
                  <p className="mt-0.5 text-gray-500">Record initialized on the compliance queue.</p>
                </div>
              )}
            </div>
          </div>

          {/* Capability-Aware Action Area */}
          {(() => {
            const canTag =
              detail.rowCapabilities?.canTagDeficiency === true &&
              !isPendingDeletion;
            const isForReview =
              detail.hrStatus.toLowerCase().trim() === "for review";
            const canReviewCorrection =
              detail.rowCapabilities?.canReviewCorrection === true &&
              isForReview &&
              !isPendingDeletion;
            return (
              <CapabilityActionBar
                actions={[
                  {
                    label: "Tag Deficiency (HR Compliance)",
                    isAvailable: canTag,
                    onClick: canTag ? () => setIsTagModalOpen(true) : undefined,
                  },
                  {
                    label: "Review Correction Resubmission (HR Compliance)",
                    isAvailable: canReviewCorrection,
                    onClick: canReviewCorrection ? () => setIsReviewModalOpen(true) : undefined,
                  },
                  {
                    label: "Assign Employee ID (Data Encoder Only)",
                    isAvailable:
                      detail.rowCapabilities?.canAssignEmployeeNo === true &&
                      !isPendingDeletion,
                  },
                  {
                    label: "Deploy to Plantilla Directory",
                    isAvailable:
                      detail.rowCapabilities?.canMoveToPlantilla === true &&
                      !isPendingDeletion,
                  },
                  {
                    label: "Request Placement Separation / Deletion",
                    isAvailable:
                      detail.rowCapabilities?.canRequestDeletion === true &&
                      !isPendingDeletion,
                  },
                  {
                    label: "Review Deletion Request",
                    isAvailable:
                      detail.rowCapabilities?.canReviewDeletion === true &&
                      isPendingDeletion,
                  },
                ]}
              />
            );
          })()}

          {/* Tag Deficiency Confirmation Modal */}
          {isTagModalOpen && hrEmplocId && (
            <TagDeficiencyModal
              hrEmplocId={hrEmplocId}
              onClose={() => setIsTagModalOpen(false)}
              onSubmitted={() => setIsTagModalOpen(false)}
            />
          )}

          {/* Review Correction Modal */}
          {isReviewModalOpen && hrEmplocId && detail && (
            <ReviewCorrectionModal
              correctionReason={detail.correctionReason ?? {}}
              hrEmplocId={hrEmplocId}
              onClose={() => setIsReviewModalOpen(false)}
              onSubmitted={() => setIsReviewModalOpen(false)}
            />
          )}
        </>
      )}
    </DetailDrawer>
  );
}

// ─── Tag Deficiency Modal ────────────────────────────────────────────────────

type TagDeficiencyModalProps = {
  hrEmplocId: string;
  onClose: () => void;
  onSubmitted: () => void;
};

function TagDeficiencyModal({
  hrEmplocId,
  onClose,
  onSubmitted,
}: TagDeficiencyModalProps) {
  const queryClient = useQueryClient();
  const [selectedIssues, setSelectedIssues] = useState<Record<string, boolean>>({});
  const [issueNotes, setIssueNotes] = useState<Record<string, string>>({});
  const [remarks, setRemarks] = useState("");
  const [submitError, setSubmitError] = useState<string | null>(null);

  const hasSelected = canonicalRequirements.some((r) => selectedIssues[r.key]);

  const { mutate, isPending } = useMutation({
    mutationFn: (params: TagDeficiencyParams) => tagWebHrEmplocDeficiency(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      onSubmitted();
    },
    onError: (err) => {
      if (err instanceof HrEmplocDataError) {
        if (err.kind === "access_denied") {
          setSubmitError("You are not authorized to tag deficiencies on this record. Your session may have expired.");
        } else if (err.kind === "invalid_state") {
          setSubmitError(err.message);
        } else {
          setSubmitError("A network error occurred. Please check your connection and try again.");
        }
      } else {
        setSubmitError("An unexpected error occurred. Please try again.");
      }
    },
  });

  function handleSubmit() {
    setSubmitError(null);
    const deficiencies: Record<string, string> = {};
    for (const req of canonicalRequirements) {
      if (selectedIssues[req.key]) {
        deficiencies[req.key] = issueNotes[req.key]?.trim() ?? "";
      }
    }
    mutate({
      hrEmplocId,
      deficiencies,
      remarks: remarks.trim() || null,
    });
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40"
        onClick={isPending ? undefined : onClose}
      />
      {/* Modal panel */}
      <div className="relative z-10 w-full max-w-lg mx-4 bg-white rounded-lg border border-gray-200 shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-5 py-3.5">
          <div>
            <h2 className="text-sm font-semibold text-gray-900">Tag Compliance Deficiency</h2>
            <p className="text-[11px] text-gray-500 mt-0.5">
              Select the requirements that require correction and confirm to notify the coordinator.
            </p>
          </div>
          <button
            aria-label="Close"
            className="inline-flex h-7 w-7 items-center justify-center rounded border border-gray-200 text-gray-400 hover:bg-gray-50 hover:text-gray-600 transition disabled:opacity-40"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Scrollable body */}
        <div className="px-5 py-4 space-y-3 max-h-[60vh] overflow-y-auto">
          <div className="text-[10px] font-semibold uppercase text-gray-400">
            Deficient Requirements (select at least one)
          </div>
          <div className="space-y-2">
            {canonicalRequirements.map((req) => (
              <div
                key={req.key}
                className={`rounded-md border p-3 space-y-2 transition-colors ${
                  selectedIssues[req.key]
                    ? "border-amber-200 bg-amber-50/40"
                    : "border-gray-100 bg-gray-50/30"
                }`}
              >
                <label className="flex items-center gap-2.5 cursor-pointer select-none">
                  <input
                    checked={selectedIssues[req.key] ?? false}
                    className="h-4 w-4 rounded border-gray-300 accent-amber-600"
                    disabled={isPending}
                    onChange={(e) => {
                      setSelectedIssues((prev) => ({
                        ...prev,
                        [req.key]: e.target.checked,
                      }));
                      if (!e.target.checked) {
                        setIssueNotes((prev) => ({ ...prev, [req.key]: "" }));
                      }
                    }}
                    type="checkbox"
                  />
                  <span
                    className={`text-xs font-medium ${
                      selectedIssues[req.key] ? "text-amber-800" : "text-gray-700"
                    }`}
                  >
                    {req.label}
                  </span>
                </label>
                {selectedIssues[req.key] && (
                  <div className="pl-6">
                    <input
                      className="w-full rounded border border-amber-200 bg-white px-2.5 py-1.5 text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-amber-300"
                      disabled={isPending}
                      maxLength={500}
                      onChange={(e) =>
                        setIssueNotes((prev) => ({
                          ...prev,
                          [req.key]: e.target.value,
                        }))
                      }
                      placeholder="Brief deficiency note (optional)"
                      type="text"
                      value={issueNotes[req.key] ?? ""}
                    />
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* Remarks */}
          <div className="pt-1 space-y-1.5">
            <div className="text-[10px] font-semibold uppercase text-gray-400">
              HR Compliance Remarks (Optional)
            </div>
            <textarea
              className="w-full rounded border border-gray-200 px-2.5 py-2 text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-blue-300 resize-none"
              disabled={isPending}
              maxLength={1000}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Add overall remarks for the field coordinator…"
              rows={3}
              value={remarks}
            />
          </div>

          {/* Inline error */}
          {submitError && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-xs text-red-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
              <span>{submitError}</span>
            </div>
          )}
        </div>

        {/* Footer actions */}
        <div className="flex items-center justify-end gap-2.5 border-t border-gray-100 px-5 py-3">
          <button
            className="rounded-md border border-gray-200 bg-white px-4 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 transition disabled:opacity-50"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className="inline-flex items-center gap-1.5 rounded-md bg-amber-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-amber-700 transition disabled:opacity-50 disabled:cursor-not-allowed"
            disabled={!hasSelected || isPending}
            onClick={handleSubmit}
            type="button"
          >
            {isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            {isPending ? "Submitting…" : "Confirm Tag Deficiency"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Review Correction Modal ─────────────────────────────────────────────────

type ReviewCorrectionModalProps = {
  hrEmplocId: string;
  correctionReason: Record<string, unknown>;
  onClose: () => void;
  onSubmitted: () => void;
};

function ReviewCorrectionModal({
  hrEmplocId,
  correctionReason,
  onClose,
  onSubmitted,
}: ReviewCorrectionModalProps) {
  const queryClient = useQueryClient();
  const deficiencyKeys = Object.keys(correctionReason);

  const [resolved, setResolved] = useState<Record<string, boolean>>(() =>
    Object.fromEntries(deficiencyKeys.map((k) => [k, false])),
  );
  const [remarks, setRemarks] = useState("");
  const [submitError, setSubmitError] = useState<string | null>(null);

  const resolvedKeys = deficiencyKeys.filter((k) => resolved[k]);
  const allResolved =
    deficiencyKeys.length === 0 || deficiencyKeys.every((k) => resolved[k]);
  const decision: "approve" | "return" = allResolved ? "approve" : "return";
  const residualCount = deficiencyKeys.length - resolvedKeys.length;

  const { mutate, isPending } = useMutation({
    mutationFn: (params: ReviewCorrectionParams) =>
      reviewWebHrEmplocCorrection(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      onSubmitted();
    },
    onError: (err) => {
      if (err instanceof HrEmplocDataError) {
        if (err.kind === "access_denied") {
          setSubmitError(
            "You are not authorized to review this correction. Your session may have expired.",
          );
        } else if (err.kind === "invalid_state") {
          setSubmitError(err.message);
        } else {
          setSubmitError(
            "A network error occurred. Please check your connection and try again.",
          );
        }
      } else {
        setSubmitError("An unexpected error occurred. Please try again.");
      }
    },
  });

  function getDeficiencyLabel(key: string): string {
    return (
      canonicalRequirements.find((r) => r.key === key)?.label ??
      key.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase())
    );
  }

  function getDeficiencyNote(key: string): string | null {
    const val = correctionReason[key];
    return typeof val === "string" && val.trim() ? val : null;
  }

  function handleSubmit() {
    setSubmitError(null);
    mutate({
      hrEmplocId,
      decision,
      resolvedKeys: resolvedKeys.length > 0 ? resolvedKeys : null,
      remarks: remarks.trim() || null,
    });
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40"
        onClick={isPending ? undefined : onClose}
      />
      {/* Modal panel */}
      <div className="relative z-10 w-full max-w-lg mx-4 bg-white rounded-lg border border-gray-200 shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-5 py-3.5">
          <div>
            <h2 className="text-sm font-semibold text-gray-900">
              Review Correction Resubmission
            </h2>
            <p className="text-[11px] text-gray-500 mt-0.5">
              Mark each tagged deficiency as resolved or still deficient to determine the review outcome.
            </p>
          </div>
          <button
            aria-label="Close"
            className="inline-flex h-7 w-7 items-center justify-center rounded border border-gray-200 text-gray-400 hover:bg-gray-50 hover:text-gray-600 transition disabled:opacity-40"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Scrollable body */}
        <div className="px-5 py-4 space-y-3 max-h-[60vh] overflow-y-auto">
          {deficiencyKeys.length === 0 ? (
            <div className="text-center py-5 border border-dashed border-gray-100 rounded-md text-xs text-gray-400">
              No deficiency keys are tagged on this record.
            </div>
          ) : (
            <>
              <div className="text-[10px] font-semibold uppercase text-gray-400">
                Tagged Deficiencies — mark each as resolved or still deficient
              </div>
              <div className="space-y-2">
                {deficiencyKeys.map((key) => {
                  const isResolved = resolved[key] ?? false;
                  const note = getDeficiencyNote(key);
                  return (
                    <div
                      key={key}
                      className={`rounded-md border p-3 space-y-1.5 transition-colors ${
                        isResolved
                          ? "border-emerald-200 bg-emerald-50/40"
                          : "border-amber-200 bg-amber-50/30"
                      }`}
                    >
                      <label className="flex items-center gap-2.5 cursor-pointer select-none">
                        <input
                          checked={isResolved}
                          className="h-4 w-4 rounded border-gray-300 accent-emerald-600"
                          disabled={isPending}
                          onChange={(e) =>
                            setResolved((prev) => ({
                              ...prev,
                              [key]: e.target.checked,
                            }))
                          }
                          type="checkbox"
                        />
                        <span
                          className={`text-xs font-medium flex-1 ${
                            isResolved ? "text-emerald-800" : "text-amber-800"
                          }`}
                        >
                          {getDeficiencyLabel(key)}
                        </span>
                        <span
                          className={`inline-flex rounded-full px-2 py-0.5 text-[9px] font-semibold border ${
                            isResolved
                              ? "border-emerald-200 bg-emerald-50 text-emerald-700"
                              : "border-amber-200 bg-amber-50 text-amber-700"
                          }`}
                        >
                          {isResolved ? "Resolved" : "Still Deficient"}
                        </span>
                      </label>
                      {note && (
                        <div className="pl-6 text-[11px] text-gray-500 leading-relaxed border-l border-amber-200/50 py-0.5">
                          <span className="font-semibold">Tagged Note:</span> {note}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </>
          )}

          {/* Decision preview */}
          <div
            className={`rounded-md border p-3 text-xs ${
              allResolved
                ? "border-emerald-200 bg-emerald-50 text-emerald-800"
                : "border-amber-200 bg-amber-50 text-amber-800"
            }`}
          >
            {allResolved ? (
              <>
                <span className="font-bold">Decision: Approve &amp; Complete</span>
                <span className="block mt-0.5 text-[11px]">
                  All deficiencies affirmed resolved. This record will move to{" "}
                  <span className="font-bold">Complete</span> and become eligible for employee number assignment.
                </span>
              </>
            ) : (
              <>
                <span className="font-bold">Decision: Return for Correction</span>
                <span className="block mt-0.5 text-[11px]">
                  {residualCount} remaining deficiency item{residualCount !== 1 ? "s" : ""} will be sent back to the coordinator.
                </span>
              </>
            )}
          </div>

          {/* Remarks */}
          <div className="pt-1 space-y-1.5">
            <div className="text-[10px] font-semibold uppercase text-gray-400">
              Reviewer Remarks (Optional)
            </div>
            <textarea
              className="w-full rounded border border-gray-200 px-2.5 py-2 text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-blue-300 resize-none"
              disabled={isPending}
              maxLength={1000}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Add reviewer notes for the coordinator…"
              rows={3}
              value={remarks}
            />
          </div>

          {/* Inline error */}
          {submitError && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-xs text-red-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
              <span>{submitError}</span>
            </div>
          )}
        </div>

        {/* Footer actions */}
        <div className="flex items-center justify-end gap-2.5 border-t border-gray-100 px-5 py-3">
          <button
            className="rounded-md border border-gray-200 bg-white px-4 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 transition disabled:opacity-50"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className={`inline-flex items-center gap-1.5 rounded-md px-4 py-1.5 text-xs font-semibold text-white transition disabled:opacity-50 disabled:cursor-not-allowed ${
              allResolved
                ? "bg-emerald-600 hover:bg-emerald-700"
                : "bg-amber-600 hover:bg-amber-700"
            }`}
            disabled={isPending}
            onClick={handleSubmit}
            type="button"
          >
            {isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            {isPending
              ? "Submitting…"
              : allResolved
              ? "Approve & Complete"
              : "Return for Correction"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── State sub-components ─────────────────────────────────────────────────────

// Sub-components for states
function LoadingSkeleton() {
  return (
    <div className="space-y-5 animate-pulse">
      <div className="grid grid-cols-2 gap-3">
        <div className="h-16 rounded-md bg-gray-100" />
        <div className="h-16 rounded-md bg-gray-100" />
      </div>
      <div className="h-32 rounded-md bg-gray-100" />
      <div className="h-28 rounded-md bg-gray-100" />
      <div className="h-44 rounded-md bg-gray-100" />
      <div className="h-36 rounded-md bg-gray-100" />
    </div>
  );
}

function AccessDeniedState() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <div className="rounded-full bg-red-50 p-3 text-red-600 shadow-xs border border-red-100">
        <ShieldAlert className="h-8 w-8" />
      </div>
      <h4 className="mt-4 text-sm font-bold text-gray-900">Compliance Access Denied</h4>
      <p className="mt-1 text-xs text-gray-500 max-w-xs leading-relaxed">
        Supabase RLS policies blocked this specific detail read. You are not authorized to view candidates outside your assigned store scopes.
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
      <p className="mt-1 text-xs text-gray-500 max-w-xs leading-relaxed">
        The selected allocation could not be found. It may have been archived, rejected, or moved to Plantilla.
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
      <p className="mt-1 text-xs text-gray-500 max-w-xs leading-relaxed">
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
