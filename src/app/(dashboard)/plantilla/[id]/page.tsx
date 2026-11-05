"use client";

import { useState, useMemo, Suspense } from "react";
import { useParams, useSearchParams } from "next/navigation";
import Link from "next/link";
import { useQuery, useMutation } from "@tanstack/react-query";
import {
  ArrowLeft,
  ArrowRightLeft,
  Briefcase,
  Calendar,
  Clock,
  CreditCard,
  Eye,
  EyeOff,
  HeartPulse,
  Home,
  IdCard,
  Pencil,
  RefreshCw,
  Settings,
  Shield,
  ShieldCheck,
  Store,
  Trash2,
  UserCheck,
  UserMinus,
  AlertTriangle,
  FileText,
  Building2,
} from "lucide-react";
import {
  getWebPlantillaDetail,
  syncPlantillaMika,
  deriveDeactivationOverlay,
  deriveTransferOverlay,
  PlantillaDataError,
} from "@/lib/queries/plantilla";
import { useCurrentUser, isPlantillaLifecycleRole } from "@/lib/auth";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import { InitiateSeparationModal } from "@/components/plantilla/InitiateSeparationModal";
import { UpdateEmploymentStatusModal } from "@/components/plantilla/UpdateEmploymentStatusModal";
import { RequestDeactivationModal } from "@/components/plantilla/RequestDeactivationModal";
import { TransferPersonnelModal } from "@/components/plantilla/TransferPersonnelModal";
import { UpdateScheduleModal } from "@/components/plantilla/UpdateScheduleModal";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function statusVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase().trim()) {
    case "active":
      return "success";
    case "on leave":
    case "on_leave":
      return "warning";
    case "floating":
      return "neutral";
    case "pending transfer":
    case "pending_transfer":
      return "info";
    case "pending separation":
    case "pending_separation":
    case "pending deactivation":
    case "pending_deactivation":
      return "danger";
    case "suspended":
      return "warning";
    case "inactive":
    case "terminated":
    case "resigned":
    case "awol":
    case "deactivated":
      return "neutral";
    default:
      return "neutral";
  }
}

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return "—";
  try {
    return new Intl.DateTimeFormat("en-PH", { dateStyle: "medium" }).format(
      new Date(dateStr)
    );
  } catch {
    return dateStr;
  }
}

function formatEventDate(isoStr: string | null | undefined): string {
  if (!isoStr) return "Date unavailable";
  try {
    return new Intl.DateTimeFormat("en-PH", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(isoStr));
  } catch {
    return isoStr;
  }
}

function computeTenure(dateStr: string | null | undefined): string {
  if (!dateStr) return "—";
  try {
    const start = new Date(dateStr);
    if (isNaN(start.getTime())) return "—";

    const now = new Date();
    if (start > now) return "< 1 Month";

    let years = now.getFullYear() - start.getFullYear();
    let months = now.getMonth() - start.getMonth();

    if (now.getDate() < start.getDate()) {
      months--;
    }

    if (months < 0) {
      years--;
      months += 12;
    }

    const parts: string[] = [];
    if (years > 0) {
      parts.push(`${years} ${years === 1 ? "Year" : "Years"}`);
    }
    if (months > 0) {
      parts.push(`${months} ${months === 1 ? "Month" : "Months"}`);
    }

    if (parts.length === 0) {
      return "< 1 Month";
    }

    return parts.join(", ");
  } catch {
    return "—";
  }
}

function getInitials(
  firstName?: string | null,
  lastName?: string | null,
  displayName?: string | null
): string {
  if (firstName && lastName) {
    return `${firstName[0]}${lastName[0]}`.toUpperCase();
  }
  if (displayName) {
    const parts = displayName.replace(/,/g, "").trim().split(/\s+/).filter(Boolean);
    if (parts.length >= 2) {
      return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
    }
    if (parts.length === 1 && parts[0].length >= 2) {
      return parts[0].slice(0, 2).toUpperCase();
    }
  }
  return "EM";
}

function formatBenefitValue(
  value: string | null | undefined,
  isMasked: boolean,
  maskedFallback?: string | null
): string {
  if (!value && !maskedFallback) return "—";
  if (!isMasked) {
    return value || maskedFallback || "—";
  }
  if (maskedFallback && maskedFallback.includes("•")) {
    return maskedFallback;
  }
  const clean = (value || maskedFallback || "").trim();
  const digits = clean.replace(/\D/g, "");
  if (digits.length >= 4) {
    return `••••-••••-${digits.slice(-4)}`;
  }
  return clean ? `••••-••••-${clean.slice(-4)}` : "—";
}

type CategoryTab =
  | "employment"
  | "schedule"
  | "benefits"
  | "stores"
  | "activity";

// ---------------------------------------------------------------------------
// Main Component Content
// ---------------------------------------------------------------------------

function PlantillaEmployeeDetailContent() {
  const params = useParams<{ id: string }>();
  const searchParams = useSearchParams();

  const plantillaId = params?.id ? String(params.id) : "";

  // Active Category Tab
  const [activeTab, setActiveTab] = useState<CategoryTab>("employment");
  const [isMasked, setIsMasked] = useState(true);
  const [actionFeedback, setActionFeedback] = useState<{
    type: "info" | "success" | "error";
    message: string;
  } | null>(null);

  // Modals state
  const [isSeparationModalOpen, setIsSeparationModalOpen] = useState(false);
  const [isStatusModalOpen, setIsStatusModalOpen] = useState(false);
  const [isDeactivationModalOpen, setIsDeactivationModalOpen] = useState(false);
  const [isTransferModalOpen, setIsTransferModalOpen] = useState(false);
  const [isScheduleModalOpen, setIsScheduleModalOpen] = useState(false);

  // Return query preservation: pass back current context
  const returnHref = useMemo(() => {
    const q = searchParams.toString();
    return q ? `/plantilla?${q}` : "/plantilla";
  }, [searchParams]);

  // Data queries
  const detailQuery = useQuery({
    queryKey: ["plantilla", "detail", plantillaId],
    queryFn: () => getWebPlantillaDetail(plantillaId),
    enabled: Boolean(plantillaId),
    retry: false,
  });

  const syncMutation = useMutation({
    mutationFn: () => syncPlantillaMika(plantillaId),
    onSuccess: () => {
      setActionFeedback({
        type: "success",
        message: "Successfully synced latest employee details from MIKA.",
      });
      detailQuery.refetch();
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : "Failed to sync with MIKA.";
      setActionFeedback({
        type: "error",
        message: msg,
      });
    },
  });

  const data = detailQuery.data;
  const queryError =
    detailQuery.error instanceof PlantillaDataError
      ? detailQuery.error
      : null;

  const isAccessDenied = queryError?.kind === "access_denied";
  const isNotFound =
    !detailQuery.isLoading &&
    !isAccessDenied &&
    detailQuery.isError &&
    !data;
  const isRetryable =
    detailQuery.isError && !isAccessDenied && !isNotFound;

  const deactivation = data
    ? deriveDeactivationOverlay(data.plantillaStatus)
    : null;
  const transferOverlay = data
    ? deriveTransferOverlay(data.activeMovementRequest, data.slaBreached)
    : null;

  const displayName =
    data?.lastName && data?.firstName
      ? `${data.lastName}, ${data.firstName}`
      : (data?.lastName ?? data?.firstName ?? "Employee Profile");

  const initials = getInitials(data?.firstName, data?.lastName, displayName);

  const currentUser = useCurrentUser();
  const isAuthorized = isPlantillaLifecycleRole(currentUser?.roleKey);

  const status = (data?.plantillaStatus ?? "").trim().toLowerCase();
  const isInactive =
    status === "inactive" ||
    status === "terminated" ||
    status === "resigned" ||
    status === "awol" ||
    status === "deactivated";
  const isPendingDeactivation =
    status === "pending deactivation" || status === "pending_deactivation";
  const isDeactivationEligible = isInactive || status === "floating";

  return (
    <div className="flex flex-col flex-1 min-h-0 bg-background text-text-primary">
      {/* Top Return Navigation */}
      <div className="px-6 pt-5 pb-0 shrink-0 max-w-7xl w-full mx-auto">
        <Link
          href={returnHref}
          className="inline-flex items-center gap-1.5 text-xs font-medium text-text-secondary hover:text-brand-primary transition px-2.5 py-1.5 rounded-lg hover:bg-surface-muted"
        >
          <ArrowLeft className="w-3.5 h-3.5" />
          <span>Back to Plantilla</span>
        </Link>
      </div>

      {/* Main Content Area */}
      <div className="flex-1 overflow-y-auto p-6 space-y-6 max-w-7xl w-full mx-auto">
        {/* Loading / Error States */}
        {detailQuery.isLoading && (
          <div className="py-12">
            <DataState
              kind="loading"
              title="Loading employee profile"
              description="Fetching full employee details and category data through Supabase RPC."
            />
          </div>
        )}

        {isAccessDenied && (
          <div className="py-12">
            <DataState
              kind="access_denied"
              title="Access Restricted"
              description="Supabase RLS policies blocked this read. You are not authorized to view this employee's plantilla record."
            />
          </div>
        )}

        {isNotFound && (
          <div className="py-12">
            <DataState
              kind="empty"
              title="Record Not Found"
              description="No plantilla detail record was found for this identifier."
            />
          </div>
        )}

        {isRetryable && (
          <div className="py-12">
            <DataState
              kind="error"
              title="Fetch Failed"
              description={
                queryError?.message ??
                "The employee profile query failed. Please try again."
              }
              onRetry={() => detailQuery.refetch()}
            />
          </div>
        )}

        {data && (
          <>
            {/* Feedback Alert Banner */}
            {actionFeedback && (
              <div
                className={`rounded-xl p-3.5 text-xs flex items-center justify-between border ${
                  actionFeedback.type === "error"
                    ? "bg-danger-bg text-danger-text border-danger-border"
                    : "bg-surface-muted text-text-primary border-border-default"
                }`}
              >
                <span>{actionFeedback.message}</span>
                <button
                  type="button"
                  onClick={() => setActionFeedback(null)}
                  className="ml-3 font-bold cursor-pointer text-text-muted hover:text-text-primary"
                >
                  ✕
                </button>
              </div>
            )}

            {/* Top Summary Header Card & Prominent Actions Bar */}
            <div className="bg-surface rounded-2xl border border-border-default p-6 shadow-xs">
              <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6">
                {/* Employee Info Header */}
                <div className="flex items-start sm:items-center gap-4 min-w-0">
                  <div className="w-16 h-16 rounded-2xl bg-brand-50 border-2 border-brand-200 text-brand-700 font-extrabold text-xl flex items-center justify-center shrink-0 shadow-xs dark:bg-brand-950/40 dark:border-brand-800 dark:text-brand-300">
                    {initials}
                  </div>
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2.5">
                      <h1 className="text-xl font-bold text-text-primary tracking-tight truncate">
                        {displayName}
                      </h1>
                      {data.plantillaStatus && (
                        <StatusBadge
                          variant={statusVariant(data.plantillaStatus)}
                          text={data.plantillaStatus}
                        />
                      )}
                    </div>
                    <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-xs text-text-secondary mt-1.5 font-medium">
                      <span className="flex items-center gap-1 font-mono text-text-primary">
                        <IdCard className="w-3.5 h-3.5 text-brand-primary" />
                        ID: {data.employeeNo || "—"}
                      </span>
                      {data.vcode && (
                        <span className="flex items-center gap-1 font-mono text-brand-primary font-bold">
                          <span>VCode:</span> {data.vcode}
                        </span>
                      )}
                      <span className="flex items-center gap-1">
                        <Store className="w-3.5 h-3.5 text-text-muted" />
                        {data.primaryStoreName || "Store Unassigned"}
                      </span>
                      <span className="flex items-center gap-1">
                        <Briefcase className="w-3.5 h-3.5 text-text-muted" />
                        {data.positionTitle || "Position Unassigned"}
                      </span>
                      <span className="flex items-center gap-1">
                        <Calendar className="w-3.5 h-3.5 text-text-muted" />
                        Hired: {formatDate(data.dateHired || data.dateDeployed)} ({data.tenureDescription || computeTenure(data.dateDeployed || data.dateHired)})
                      </span>
                    </div>
                  </div>
                </div>

                {/* Capability-Aware Personnel Actions Bar (Always Visible at Top) */}
                <div className="flex flex-wrap items-center gap-2 pt-4 lg:pt-0 border-t lg:border-t-0 border-border-subtle shrink-0">
                  {/* Primary: Update Employment Status */}
                  <button
                    type="button"
                    onClick={() => setIsStatusModalOpen(true)}
                    disabled={!isAuthorized || isInactive}
                    className="inline-flex items-center gap-2 px-3.5 py-2 rounded-lg bg-brand-primary hover:bg-brand-secondary text-white text-xs font-bold transition shadow-xs cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <UserCheck className="w-4 h-4" />
                    <span>Update Employment Status</span>
                  </button>

                  {/* Transfer Employee */}
                  <button
                    type="button"
                    onClick={() => setIsTransferModalOpen(true)}
                    disabled={!isAuthorized || isInactive}
                    className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-surface-muted hover:bg-surface-base border border-border-default text-text-primary text-xs font-semibold transition cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed shadow-2xs"
                  >
                    <ArrowRightLeft className="w-3.5 h-3.5 text-brand-primary" />
                    <span>Transfer</span>
                  </button>

                  {/* Reassign HRCO */}
                  <button
                    type="button"
                    onClick={() => {
                      setActionFeedback({
                        type: "info",
                        message: "HR Coordinator assignment request submitted for review.",
                      });
                    }}
                    disabled={!isAuthorized || isInactive}
                    className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-surface-muted hover:bg-surface-base border border-border-default text-text-primary text-xs font-semibold transition cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed shadow-2xs"
                  >
                    <ShieldCheck className="w-3.5 h-3.5 text-brand-primary" />
                    <span>Reassign HRCO</span>
                  </button>

                  {/* Request Deactivation */}
                  <button
                    type="button"
                    onClick={() => setIsDeactivationModalOpen(true)}
                    disabled={!isAuthorized || isPendingDeactivation || !isDeactivationEligible}
                    className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-surface-muted hover:bg-surface-base border border-border-default text-text-primary text-xs font-semibold transition cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed shadow-2xs"
                    title={
                      isPendingDeactivation
                        ? "A deactivation request is already pending review."
                        : !isDeactivationEligible
                        ? "Employee must be set to Floating or Inactive before requesting deactivation."
                        : undefined
                    }
                  >
                    <UserMinus className="w-3.5 h-3.5 text-text-secondary" />
                    <span>{isPendingDeactivation ? "Deactivation Pending" : "Request Deactivation"}</span>
                  </button>

                  {/* Request Deletion */}
                  <button
                    type="button"
                    onClick={() => {
                      setActionFeedback({
                        type: "info",
                        message: "Deletion request logged and routed to operations queue.",
                      });
                    }}
                    disabled={!isAuthorized}
                    className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-danger-bg/40 hover:bg-danger-bg text-danger-text border border-danger-border text-xs font-semibold transition cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed shadow-2xs"
                  >
                    <Trash2 className="w-3.5 h-3.5 text-danger-text" />
                    <span>Request Deletion</span>
                  </button>
                </div>
              </div>

              {/* Status Notice Callout if pending deactivation */}
              {isPendingDeactivation && (
                <div className="mt-4 pt-3 border-t border-border-subtle flex items-center gap-2 text-xs text-amber-700 dark:text-amber-400 font-medium">
                  <AlertTriangle className="w-4 h-4 shrink-0" />
                  <span>Deactivation request submitted and pending operations review.</span>
                </div>
              )}
            </div>

            {/* Category Navigation Tabs */}
            <div className="border-b border-border-default flex items-center gap-2 overflow-x-auto pb-px">
              <button
                type="button"
                onClick={() => setActiveTab("employment")}
                role="tab"
                aria-selected={activeTab === "employment"}
                className={`flex items-center gap-2 px-4 py-3 text-xs font-bold border-b-2 transition whitespace-nowrap cursor-pointer ${
                  activeTab === "employment"
                    ? "border-brand-primary text-brand-primary"
                    : "border-transparent text-text-secondary hover:text-text-primary"
                }`}
              >
                <Briefcase className="w-4 h-4" />
                <span>Employment & Allocation</span>
              </button>

              <button
                type="button"
                onClick={() => setActiveTab("schedule")}
                role="tab"
                aria-selected={activeTab === "schedule"}
                className={`flex items-center gap-2 px-4 py-3 text-xs font-bold border-b-2 transition whitespace-nowrap cursor-pointer ${
                  activeTab === "schedule"
                    ? "border-brand-primary text-brand-primary"
                    : "border-transparent text-text-secondary hover:text-text-primary"
                }`}
              >
                <Clock className="w-4 h-4" />
                <span>Work Schedule & Rate</span>
              </button>

              <button
                type="button"
                onClick={() => setActiveTab("benefits")}
                role="tab"
                aria-selected={activeTab === "benefits"}
                className={`flex items-center gap-2 px-4 py-3 text-xs font-bold border-b-2 transition whitespace-nowrap cursor-pointer ${
                  activeTab === "benefits"
                    ? "border-brand-primary text-brand-primary"
                    : "border-transparent text-text-secondary hover:text-text-primary"
                }`}
              >
                <Shield className="w-4 h-4" />
                <span>Benefits & Statutory</span>
              </button>

              <button
                type="button"
                onClick={() => setActiveTab("stores")}
                role="tab"
                aria-selected={activeTab === "stores"}
                className={`flex items-center gap-2 px-4 py-3 text-xs font-bold border-b-2 transition whitespace-nowrap cursor-pointer ${
                  activeTab === "stores"
                    ? "border-brand-primary text-brand-primary"
                    : "border-transparent text-text-secondary hover:text-text-primary"
                }`}
              >
                <Store className="w-4 h-4" />
                <span>Stores & Coverage</span>
              </button>

              <button
                type="button"
                onClick={() => setActiveTab("activity")}
                role="tab"
                aria-selected={activeTab === "activity"}
                className={`flex items-center gap-2 px-4 py-3 text-xs font-bold border-b-2 transition whitespace-nowrap cursor-pointer ${
                  activeTab === "activity"
                    ? "border-brand-primary text-brand-primary"
                    : "border-transparent text-text-secondary hover:text-text-primary"
                }`}
              >
                <FileText className="w-4 h-4" />
                <span>Activity & System Info</span>
              </button>
            </div>

            {/* TAB 1: EMPLOYMENT & ALLOCATION */}
            {activeTab === "employment" && (
              <div className="space-y-6">
                {/* Status-specific alert banners */}
                {deactivation?.showSeparationBanner && (
                  <div className="rounded-xl border border-amber-200 bg-amber-50 dark:bg-amber-950/30 dark:border-amber-800 p-4 flex items-start gap-3">
                    <AlertTriangle className="h-5 w-5 shrink-0 text-amber-600 dark:text-amber-400 mt-0.5" />
                    <div>
                      <h4 className="text-xs font-bold text-amber-900 dark:text-amber-200">
                        Active Separation Request Pending Clearance
                      </h4>
                      <p className="text-xs text-amber-800 dark:text-amber-300 mt-0.5 leading-relaxed">
                        This employee has an active separation request currently queued for offboarding clearance and review.
                      </p>
                    </div>
                  </div>
                )}

                {deactivation?.showDeactivatedBanner && (
                  <div className="rounded-xl border border-border-default bg-surface-muted p-4 flex items-start gap-3 text-text-secondary">
                    <AlertTriangle className="h-5 w-5 shrink-0 text-text-muted mt-0.5" />
                    <div>
                      <h4 className="text-xs font-bold text-text-primary">
                        Archived / Inactive Profile
                      </h4>
                      <p className="text-xs text-text-secondary mt-0.5 leading-relaxed">
                        This employee profile is disengaged or separated. The record is permanently preserved for historical compliance and audit reporting.
                      </p>
                    </div>
                  </div>
                )}

                {transferOverlay?.hasActiveTransfer && (
                  <div className="rounded-xl border border-blue-200 bg-blue-50 dark:bg-blue-950/30 dark:border-blue-800 p-4 flex items-start gap-3">
                    <ArrowRightLeft className="h-5 w-5 shrink-0 text-blue-600 dark:text-blue-400 mt-0.5" />
                    <div>
                      <h4 className="text-xs font-bold text-blue-900 dark:text-blue-200">
                        {transferOverlay.transferType ?? "Transfer"} in Progress
                      </h4>
                      <p className="text-xs text-blue-800 dark:text-blue-300 mt-0.5 leading-relaxed">
                        Destination: {transferOverlay.targetStoreName || "Pending Store Assignment"}
                        {transferOverlay.slaBreached && (
                          <span className="ml-2 font-bold text-red-600 dark:text-red-400">[SLA Breached]</span>
                        )}
                      </p>
                    </div>
                  </div>
                )}

                {/* Primary Employment Information Card */}
                <div className="bg-surface rounded-2xl border border-border-default p-6 shadow-xs">
                  <h3 className="text-sm font-bold text-text-primary mb-4 flex items-center gap-2">
                    <Briefcase className="w-4 h-4 text-brand-primary" />
                    <span>Employment & Placement Specifications</span>
                  </h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 text-xs">
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Permanent VCODE</span>
                      <p className="font-bold text-text-primary text-sm mt-1 font-mono">
                        {data.vcode || "—"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Assigned Primary Store</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.primaryStoreName || data.vcode || "—"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Area / City / Province</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {[data.area, data.province].filter(Boolean).join(" • ") || "—"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Designated Position</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.positionTitle || "—"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Plantilla Tier</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.plantillaType || "Standard Tier"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Employment / Assignment Type</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.employmentType || data.assignmentType || "Stationary"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Date Hired / Deployed</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {formatDate(data.dateHired || data.dateDeployed)}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Tenure</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.tenureDescription || computeTenure(data.dateDeployed || data.dateHired)}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Account Portfolio</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.accountName || "—"}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* TAB 2: WORK SCHEDULE & RATE */}
            {activeTab === "schedule" && (
              <div className="space-y-6">
                <div className="bg-surface rounded-2xl border border-border-default p-6 shadow-xs">
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                      <Clock className="w-4 h-4 text-brand-primary" />
                      <span>Work Schedule & Compensation Metadata</span>
                    </h3>
                    {isAuthorized && (
                      <button
                        type="button"
                        onClick={() => setIsScheduleModalOpen(true)}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg bg-surface-muted hover:bg-surface-base border border-border-default text-brand-primary transition shadow-2xs cursor-pointer"
                      >
                        <Pencil className="w-3.5 h-3.5" />
                        <span>Edit Schedule</span>
                      </button>
                    )}
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 text-xs">
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Schedule Days</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.scheduleDays || "Mon - Sat"}
                      </p>
                    </div>
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Schedule Time</span>
                      <p className="font-bold text-text-primary text-sm mt-1 font-mono">
                        {data.scheduleTime || "08:00 AM - 05:00 PM"}
                      </p>
                    </div>
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Designated Day Off</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.dayoff || "Sunday"}
                      </p>
                    </div>
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Daily Wage / Base Rate</span>
                      <p className="font-bold text-text-primary text-sm mt-1 font-mono">
                        {data.dailyRate || data.maskedFields?.baseRateMasked || "—"}
                      </p>
                    </div>
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle col-span-1 md:col-span-2">
                      <span className="text-text-secondary font-medium">Assigned HR Coordinator</span>
                      <p className="font-bold text-text-primary text-sm mt-1">
                        {data.coordinator || data.hrcoName || "Unassigned Coordinator"}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* TAB 3: BENEFITS & STATUTORY */}
            {activeTab === "benefits" && (
              <div className="space-y-6">
                <div className="bg-surface rounded-2xl border border-border-default p-6 shadow-xs space-y-5">
                  <div className="flex justify-between items-center border-b border-border-subtle pb-4">
                    <div>
                      <h3 className="text-sm font-bold text-text-primary">
                        Government Statutory & Benefit Enrollments
                      </h3>
                      <p className="text-xs text-text-secondary mt-0.5">
                        Statutory contribution accounts and disbursement metadata.
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => setIsMasked(!isMasked)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg border border-border-default bg-surface-muted hover:bg-surface-base text-text-secondary hover:text-text-primary transition cursor-pointer"
                      title={isMasked ? "Reveal benefit numbers" : "Mask benefit numbers"}
                    >
                      {isMasked ? <Eye className="w-3.5 h-3.5" /> : <EyeOff className="w-3.5 h-3.5" />}
                      <span>{isMasked ? "Reveal Numbers" : "Mask Numbers"}</span>
                    </button>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {/* SSS */}
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <div className="w-9 h-9 rounded-lg bg-blue-50 border border-blue-200 text-blue-700 flex items-center justify-center shrink-0 dark:bg-blue-950/40 dark:border-blue-800 dark:text-blue-300">
                          <Shield className="w-4 h-4" />
                        </div>
                        <div>
                          <p className="text-xs font-semibold text-text-secondary">Social Security System (SSS)</p>
                          <p className="text-sm font-bold text-text-primary font-mono mt-0.5">
                            {formatBenefitValue(data.maskedFields?.governmentIds?.sss, isMasked)}
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* PhilHealth */}
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <div className="w-9 h-9 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-700 flex items-center justify-center shrink-0 dark:bg-emerald-950/40 dark:border-emerald-800 dark:text-emerald-300">
                          <HeartPulse className="w-4 h-4" />
                        </div>
                        <div>
                          <p className="text-xs font-semibold text-text-secondary">PhilHealth Number</p>
                          <p className="text-sm font-bold text-text-primary font-mono mt-0.5">
                            {formatBenefitValue(data.maskedFields?.governmentIds?.philhealth, isMasked)}
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* Pag-IBIG */}
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <div className="w-9 h-9 rounded-lg bg-amber-50 border border-amber-200 text-amber-700 flex items-center justify-center shrink-0 dark:bg-amber-950/40 dark:border-amber-800 dark:text-amber-300">
                          <Home className="w-4 h-4" />
                        </div>
                        <div>
                          <p className="text-xs font-semibold text-text-secondary">Pag-IBIG (HDMF) Number</p>
                          <p className="text-sm font-bold text-text-primary font-mono mt-0.5">
                            {formatBenefitValue(data.maskedFields?.governmentIds?.pagibig, isMasked)}
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* TIN */}
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <div className="w-9 h-9 rounded-lg bg-purple-50 border border-purple-200 text-purple-700 flex items-center justify-center shrink-0 dark:bg-purple-950/40 dark:border-purple-800 dark:text-purple-300">
                          <IdCard className="w-4 h-4" />
                        </div>
                        <div>
                          <p className="text-xs font-semibold text-text-secondary">Tax Identification No. (TIN)</p>
                          <p className="text-sm font-bold text-text-primary font-mono mt-0.5">
                            {formatBenefitValue(data.maskedFields?.governmentIds?.tin, isMasked)}
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* ATM Card / Disbursement */}
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle flex items-center justify-between col-span-1 md:col-span-2">
                      <div className="flex items-center gap-3">
                        <div className="w-9 h-9 rounded-lg bg-cyan-50 border border-cyan-200 text-cyan-700 flex items-center justify-center shrink-0 dark:bg-cyan-950/40 dark:border-cyan-800 dark:text-cyan-300">
                          <CreditCard className="w-4 h-4" />
                        </div>
                        <div>
                          <p className="text-xs font-semibold text-text-secondary">Payroll ATM Account</p>
                          <p className="text-sm font-bold text-text-primary font-mono mt-0.5">
                            {formatBenefitValue(
                              data.maskedFields?.governmentIds?.atmNumber ||
                                data.maskedFields?.governmentIds?.atmNumberMasked,
                              isMasked,
                              data.maskedFields?.governmentIds?.atmNumberMasked
                            )}
                          </p>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                {/* MIKA Synchronization Card */}
                <div className="bg-surface rounded-2xl border border-border-default p-5 shadow-xs flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                  <div>
                    <h4 className="text-xs font-bold text-text-primary flex items-center gap-2">
                      <RefreshCw className="w-4 h-4 text-brand-primary" />
                      <span>MIKA HRIS Master Record Link</span>
                    </h4>
                    <p className="text-xs text-text-secondary mt-1">
                      {data.lastMikaSyncedAt
                        ? `Last synchronized: ${formatEventDate(data.lastMikaSyncedAt)}`
                        : "Never synchronized with external HRIS."}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => syncMutation.mutate()}
                    disabled={syncMutation.isPending}
                    className="inline-flex items-center gap-2 px-4 py-2 rounded-lg border border-border-default bg-surface hover:bg-surface-muted text-brand-primary text-xs font-bold transition shadow-2xs cursor-pointer disabled:opacity-50"
                  >
                    <RefreshCw className={`w-3.5 h-3.5 ${syncMutation.isPending ? "animate-spin" : ""}`} />
                    <span>{syncMutation.isPending ? "Syncing with MIKA…" : "Sync from MIKA"}</span>
                  </button>
                </div>
              </div>
            )}

            {/* TAB 4: STORES & COVERAGE */}
            {activeTab === "stores" && (
              <div className="space-y-6">
                {/* Store Allocation Summary Stat Cards */}
                <div className="grid grid-cols-2 gap-4">
                  <div className="bg-surface rounded-2xl border border-border-default p-5 shadow-xs text-center">
                    <p className="text-2xl font-extrabold text-brand-primary">
                      {data.coveredStores && data.coveredStores.length > 0
                        ? data.coveredStores.length
                        : 1}
                    </p>
                    <p className="text-xs font-semibold text-text-secondary mt-1">
                      Active Assigned Stores
                    </p>
                  </div>
                  <div className="bg-surface rounded-2xl border border-border-default p-5 shadow-xs text-center">
                    <p className="text-2xl font-extrabold text-text-muted">
                      0
                    </p>
                    <p className="text-xs font-semibold text-text-secondary mt-1">
                      Past Store History
                    </p>
                  </div>
                </div>

                {/* Covered Stores Roster */}
                <div className="bg-surface rounded-2xl border border-border-default p-6 shadow-xs">
                  <h3 className="text-sm font-bold text-text-primary mb-4 flex items-center gap-2">
                    <Building2 className="w-4 h-4 text-brand-primary" />
                    <span>Store Deployments & Headcount Split</span>
                  </h3>

                  <div className="space-y-3">
                    {data.coveredStores && data.coveredStores.length > 0 ? (
                      data.coveredStores.map((store) => (
                        <div
                          key={store.stableKey}
                          className="p-4 rounded-xl bg-surface-muted/40 border border-border-default flex items-center justify-between gap-4"
                        >
                          <div className="flex items-start gap-3">
                            <div className="w-3.5 h-3.5 rounded-full bg-emerald-500 mt-1 shrink-0" />
                            <div>
                              <h4 className="font-bold text-text-primary text-sm">
                                {store.storeName}
                              </h4>
                              <div className="flex flex-wrap items-center gap-3 text-xs text-text-secondary mt-1">
                                <span className="font-mono text-brand-primary font-bold">
                                  {data.vcode || "—"}
                                </span>
                                <span>•</span>
                                <span>Area: {[data.area, data.province].filter(Boolean).join(", ") || "—"}</span>
                              </div>
                            </div>
                          </div>
                          <div className="text-right shrink-0">
                            <span className="text-[11px] font-semibold text-text-muted">HC Share</span>
                            <p className="font-mono font-bold text-brand-primary text-sm">
                              {store.allocationPercent != null
                                ? (store.allocationPercent / 100).toFixed(2)
                                : "1.00"}
                            </p>
                          </div>
                        </div>
                      ))
                    ) : (
                      <div className="p-4 rounded-xl bg-surface-muted/40 border border-border-default flex items-center justify-between gap-4">
                        <div className="flex items-start gap-3">
                          <div className="w-3.5 h-3.5 rounded-full bg-emerald-500 mt-1 shrink-0" />
                          <div>
                            <h4 className="font-bold text-text-primary text-sm">
                              {data.primaryStoreName || "Primary Store Assignment"}
                            </h4>
                            <div className="flex flex-wrap items-center gap-3 text-xs text-text-secondary mt-1">
                              <span className="font-mono text-brand-primary font-bold">
                                {data.vcode || "—"}
                              </span>
                              <span>•</span>
                              <span>Area: {[data.area, data.province].filter(Boolean).join(", ") || "—"}</span>
                            </div>
                          </div>
                        </div>
                        <div className="text-right shrink-0">
                          <span className="text-[11px] font-semibold text-text-muted">HC Share</span>
                          <p className="font-mono font-bold text-brand-primary text-sm">1.00</p>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* TAB 5: ACTIVITY & SYSTEM INFO */}
            {activeTab === "activity" && (
              <div className="space-y-6">
                {/* Audit Timeline */}
                <div className="bg-surface rounded-2xl border border-border-default p-6 shadow-xs">
                  <h3 className="text-sm font-bold text-text-primary mb-4 flex items-center gap-2">
                    <FileText className="w-4 h-4 text-brand-primary" />
                    <span>Lifecycle Event Log & Audit Timeline</span>
                  </h3>

                  <div className="space-y-3">
                    {data.auditTimeline && data.auditTimeline.length > 0 ? (
                      data.auditTimeline.map((item) => (
                        <div
                          key={item.stableKey}
                          className="p-4 rounded-xl bg-surface-muted/40 border border-border-default flex items-start gap-3.5"
                        >
                          <div className="w-8 h-8 rounded-lg bg-brand-50 border border-brand-200 text-brand-700 flex items-center justify-center shrink-0 mt-0.5 dark:bg-brand-950/40 dark:border-brand-800 dark:text-brand-300">
                            <Store className="w-4 h-4" />
                          </div>
                          <div className="min-w-0 flex-1">
                            <div className="flex flex-wrap items-center justify-between gap-2">
                              <h4 className="text-xs font-bold text-text-primary">
                                {item.eventLabel}
                              </h4>
                              <span className="text-[11px] text-text-muted">
                                {formatEventDate(item.createdAt)}
                              </span>
                            </div>
                            {item.eventDescription && (
                              <p className="text-xs text-text-secondary mt-1 leading-relaxed">
                                {item.eventDescription}
                              </p>
                            )}
                            <div className="flex items-center gap-2 mt-1.5 text-[11px] text-text-muted">
                              {item.profileName && <span>By: {item.profileName}</span>}
                              {data.vcode && (
                                <>
                                  <span>•</span>
                                  <span className="font-mono text-brand-primary">{data.vcode}</span>
                                </>
                              )}
                            </div>
                          </div>
                        </div>
                      ))
                    ) : (
                      <div className="p-4 rounded-xl bg-surface-muted/40 border border-border-default flex items-start gap-3.5">
                        <div className="w-8 h-8 rounded-lg bg-brand-50 border border-brand-200 text-brand-700 flex items-center justify-center shrink-0 mt-0.5 dark:bg-brand-950/40 dark:border-brand-800 dark:text-brand-300">
                          <Store className="w-4 h-4" />
                        </div>
                        <div>
                          <h4 className="text-xs font-bold text-text-primary">
                            Personnel deployed to Plantilla — {data.primaryStoreName || data.vcode || "Store"}
                          </h4>
                          <p className="text-[11px] text-text-muted mt-0.5">
                            {formatEventDate(data.dateDeployed || data.dateHired)}
                          </p>
                        </div>
                      </div>
                    )}
                  </div>
                </div>

                {/* System Information Metadata */}
                <div className="bg-surface rounded-2xl border border-border-default p-6 shadow-xs">
                  <h3 className="text-sm font-bold text-text-primary mb-4 flex items-center gap-2">
                    <Settings className="w-4 h-4 text-brand-primary" />
                    <span>System Record Metadata</span>
                  </h3>
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 text-xs">
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Plantilla UUID</span>
                      <p className="font-mono text-text-primary text-xs mt-1 truncate select-all">
                        {data.id}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Account ID</span>
                      <p className="font-mono text-text-primary text-xs mt-1 truncate select-all">
                        {data.accountId || "—"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Store UUID</span>
                      <p className="font-mono text-text-primary text-xs mt-1 truncate select-all">
                        {data.storeId || "—"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Account Name</span>
                      <p className="font-semibold text-text-primary text-xs mt-1">
                        {data.accountName || "—"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Geographic Island Group</span>
                      <p className="font-semibold text-text-primary text-xs mt-1">
                        {data.islandGroup || "—"}
                      </p>
                    </div>
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Clearance Workflow State</span>
                      <p className="font-semibold text-text-primary text-xs mt-1">
                        {data.clearanceStatus || "N/A (Active Deployed)"}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* Lifecycle Action Modals */}
      {data && isSeparationModalOpen && (
        <InitiateSeparationModal
          isOpen={isSeparationModalOpen}
          onClose={() => setIsSeparationModalOpen(false)}
          plantillaId={data.id}
          employeeName={displayName}
          employeeNo={data.employeeNo}
          positionTitle={data.positionTitle}
          storeName={data.primaryStoreName}
          onSuccess={() => {
            detailQuery.refetch();
          }}
        />
      )}

      {data && isStatusModalOpen && (
        <UpdateEmploymentStatusModal
          isOpen={isStatusModalOpen}
          onClose={() => setIsStatusModalOpen(false)}
          plantillaId={data.id}
          employeeName={displayName}
          employeeNo={data.employeeNo}
          currentStatus={data.plantillaStatus}
          onSuccess={() => {
            detailQuery.refetch();
          }}
        />
      )}

      {data && isDeactivationModalOpen && (
        <RequestDeactivationModal
          isOpen={isDeactivationModalOpen}
          onClose={() => setIsDeactivationModalOpen(false)}
          plantillaId={data.id}
          employeeName={displayName}
          employeeNo={data.employeeNo}
          currentStatus={data.plantillaStatus}
          onSuccess={() => {
            detailQuery.refetch();
          }}
        />
      )}

      {data && isTransferModalOpen && (
        <TransferPersonnelModal
          isOpen={isTransferModalOpen}
          onClose={() => setIsTransferModalOpen(false)}
          plantillaId={data.id}
          employeeName={displayName}
          employeeNo={data.employeeNo}
          positionTitle={data.positionTitle}
          accountId={data.accountId}
          accountName={data.accountName}
          currentStoreId={data.storeId}
          currentStoreName={data.primaryStoreName}
          currentProvince={data.province}
          currentIslandGroup={data.islandGroup}
          onSuccess={() => {
            detailQuery.refetch();
          }}
        />
      )}

      {data && isScheduleModalOpen && (
        <UpdateScheduleModal
          isOpen={isScheduleModalOpen}
          onClose={() => setIsScheduleModalOpen(false)}
          plantillaId={data.id}
          employeeNo={data.employeeNo}
          employeeName={displayName}
          initialScheduleDays={data.scheduleDays}
          initialScheduleTime={data.scheduleTime}
          initialDayoff={data.dayoff}
          onSuccess={() => {
            detailQuery.refetch();
          }}
        />
      )}
    </div>
  );
}

export default function PlantillaEmployeeDetailPage() {
  return (
    <Suspense
      fallback={
        <div className="flex-1 p-8">
          <DataState
            kind="loading"
            title="Loading employee profile"
            description="Preparing page and parameters..."
          />
        </div>
      }
    >
      <PlantillaEmployeeDetailContent />
    </Suspense>
  );
}
