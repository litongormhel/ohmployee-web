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
  | "schedule_stores"
  | "benefits"
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

  const coveredStores = data?.coveredStores ?? [];
  const hasMultiStores = coveredStores.length > 1;
  const isRoving =
    (data?.assignmentType ?? "").toLowerCase() === "roving" ||
    (data?.employmentType ?? "").toLowerCase() === "roving" ||
    hasMultiStores;

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
                      <h1 className="text-xl font-bold text-text-primary tracking-tight truncate flex items-center gap-2">
                        <span>{displayName}</span>
                        {status === "active" && (
                          <span
                            className="inline-block w-2.5 h-2.5 rounded-full bg-emerald-500 ring-2 ring-emerald-500/20 shrink-0"
                            title="Active Employee"
                          />
                        )}
                      </h1>
                      {status !== "active" && data.plantillaStatus && (
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
                onClick={() => setActiveTab("schedule_stores")}
                role="tab"
                aria-selected={activeTab === "schedule_stores"}
                className={`flex items-center gap-2 px-4 py-3 text-xs font-bold border-b-2 transition whitespace-nowrap cursor-pointer ${
                  activeTab === "schedule_stores"
                    ? "border-brand-primary text-brand-primary"
                    : "border-transparent text-text-secondary hover:text-text-primary"
                }`}
              >
                <Clock className="w-4 h-4" />
                <span>Schedule & Store Coverage</span>
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
                    <div className="p-3.5 rounded-xl bg-surface-muted/50 border border-border-subtle flex flex-col justify-between">
                      <div>
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-text-secondary font-medium">
                            {hasMultiStores ? "Assigned Store Allocations" : "Assigned Primary Store"}
                          </span>
                          {isRoving && (
                            <span className="text-[10px] uppercase font-bold tracking-wider px-1.5 py-0.5 rounded bg-brand-50 text-brand-700 dark:bg-brand-950/40 dark:text-brand-300 border border-brand-200 dark:border-brand-800 shrink-0">
                              Roving{hasMultiStores ? ` • ${coveredStores.length} Stores` : ""}
                            </span>
                          )}
                        </div>

                        {hasMultiStores ? (
                          <div className="mt-2 space-y-1.5">
                            {coveredStores.map((store, idx) => {
                              const isPrimary = Boolean(store.isPrimary || idx === 0);
                              const hcShare =
                                store.allocationPercent != null
                                  ? (store.allocationPercent / 100).toFixed(2)
                                  : (1 / coveredStores.length).toFixed(2);
                              return (
                                <div
                                  key={store.stableKey || `store-alloc-${idx}`}
                                  className="flex items-center justify-between gap-2 p-2 rounded-lg bg-surface border border-border-default/70 shadow-2xs"
                                >
                                  <div className="min-w-0 flex items-center gap-2">
                                    <span
                                      className={`w-2 h-2 rounded-full shrink-0 ${
                                        isPrimary ? "bg-emerald-500" : "bg-text-muted"
                                      }`}
                                    />
                                    <div className="min-w-0">
                                      <div className="flex items-center gap-1.5 flex-wrap">
                                        <span
                                          className="font-bold text-text-primary text-xs truncate"
                                          title={store.storeName}
                                        >
                                          {store.storeName}
                                        </span>
                                        {isPrimary && (
                                          <span className="text-[9px] font-bold uppercase tracking-wider px-1 py-0.2 rounded bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300 border border-emerald-200 dark:border-emerald-800 shrink-0">
                                            Primary
                                          </span>
                                        )}
                                      </div>
                                      {store.vcode && (
                                        <span className="font-mono text-[10px] text-text-muted block mt-0.5">
                                          {store.vcode}
                                        </span>
                                      )}
                                    </div>
                                  </div>
                                  <span className="font-mono font-bold text-xs text-brand-primary bg-brand-50 dark:bg-brand-950/40 px-2 py-0.5 rounded border border-brand-200 dark:border-brand-800 shrink-0">
                                    {hcShare} HC
                                  </span>
                                </div>
                              );
                            })}
                          </div>
                        ) : (
                          <p className="font-bold text-text-primary text-sm mt-1">
                            {data.primaryStoreName || data.vcode || "—"}
                          </p>
                        )}
                      </div>
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
                        {isRoving ? "Roving" : (data.employmentType || data.assignmentType || "Stationary")}
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

            {/* TAB 2: SCHEDULE & STORE COVERAGE */}
            {activeTab === "schedule_stores" && (
              <div className="space-y-6">
                {/* Top Summary Bar: Global Employee Terms */}
                <div className="bg-surface rounded-2xl border border-border-default p-5 shadow-xs">
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-4 pb-4 border-b border-border-subtle">
                    <div>
                      <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                        <Clock className="w-4 h-4 text-brand-primary" />
                        <span>Global Work Terms & Rate</span>
                      </h3>
                      <p className="text-xs text-text-secondary mt-0.5">
                        Base remuneration rate, designated mandatory weekly rest day, and HR management assignment.
                      </p>
                    </div>
                    {isAuthorized && (
                      <button
                        type="button"
                        onClick={() => setIsScheduleModalOpen(true)}
                        className="inline-flex items-center gap-1.5 px-3.5 py-2 text-xs font-bold rounded-lg bg-brand-primary hover:bg-brand-secondary text-white transition shadow-xs cursor-pointer shrink-0"
                      >
                        <Pencil className="w-3.5 h-3.5" />
                        <span>Edit Schedule & Allocations</span>
                      </button>
                    )}
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 text-xs">
                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Daily Wage / Base Rate</span>
                      <p className="font-bold text-text-primary text-base mt-1 font-mono">
                        {data.dailyRate || data.maskedFields?.baseRateMasked || "—"}
                      </p>
                      <span className="text-[11px] text-text-muted mt-1 block">Standard daily statutory rate</span>
                    </div>

                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Designated Rest Days</span>
                      <p className="font-bold text-text-primary text-base mt-1 flex flex-wrap items-center gap-2">
                        <span>{data.dayoff || "Sunday"}</span>
                        <span className="text-[10px] uppercase font-bold tracking-wider px-1.5 py-0.5 rounded bg-surface border border-border-default text-text-secondary">
                          {(data.dayoff || "").includes(",")
                            ? `${(data.dayoff || "").split(",").length} Rest Days / Wk`
                            : "1 Rest Day / Wk"}
                        </span>
                      </p>
                      <span className="text-[11px] text-text-muted mt-1 block">Designated weekly rest schedule</span>
                    </div>

                    <div className="p-4 rounded-xl bg-surface-muted/50 border border-border-subtle">
                      <span className="text-text-secondary font-medium">Assigned HR Coordinator</span>
                      <p className="font-bold text-text-primary text-base mt-1 truncate">
                        {data.coordinator || data.hrcoName || "Unassigned Coordinator"}
                      </p>
                      <span className="text-[11px] text-text-muted mt-1 block">Operations Supervisor</span>
                    </div>
                  </div>
                </div>

                {/* Store Schedule & Headcount Allocation Matrix */}
                <div className="bg-surface rounded-2xl border border-border-default p-6 shadow-xs space-y-4">
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                    <div>
                      <h3 className="text-sm font-bold text-text-primary flex items-center gap-2">
                        <Building2 className="w-4 h-4 text-brand-primary" />
                        <span>Store Schedule & Headcount Allocation Matrix</span>
                      </h3>
                      <p className="text-xs text-text-secondary mt-0.5">
                        Breakdown of per-store duty days, shift times, and headcount (HC) share distribution.
                      </p>
                    </div>

                    {/* Total HC Meter */}
                    <div className="flex items-center gap-2 bg-surface-muted px-3 py-1.5 rounded-lg border border-border-default self-start sm:self-auto shrink-0">
                      <span className="text-xs text-text-secondary font-medium">Total Allocation:</span>
                      <span className="font-mono font-bold text-xs text-brand-primary">
                        {(
                          (data.coveredStores && data.coveredStores.length > 0
                            ? data.coveredStores.reduce((sum, s) => sum + (s.allocationPercent ?? 0), 0)
                            : 100) / 100
                        ).toFixed(2)}{" "}
                        / 1.00 HC
                      </span>
                    </div>
                  </div>

                  {/* Store Allocation Cards / Table */}
                  <div className="divide-y divide-border-subtle border border-border-default rounded-xl overflow-hidden bg-surface">
                    {(data.coveredStores && data.coveredStores.length > 0
                      ? data.coveredStores
                      : [
                          {
                            storeId: data.storeId || "primary",
                            storeName: data.primaryStoreName || "Primary Store Assignment",
                            vcode: data.vcode || "—",
                            scheduleDays: data.scheduleDays || "Mon - Sat",
                            scheduleTime: data.scheduleTime || "08:00 AM - 05:00 PM",
                            allocationPercent: 100,
                            area: data.area,
                            province: data.province,
                            stableKey: "fallback-primary",
                          },
                        ]
                    ).map((store) => {
                      const hcShare =
                        store.allocationPercent != null
                          ? (store.allocationPercent / 100).toFixed(2)
                          : "1.00";
                      const storeDays = store.scheduleDays || data.scheduleDays || "Mon - Sat";
                      const storeTime =
                        store.scheduleTime || data.scheduleTime || "08:00 AM - 05:00 PM";
                      const locationStr = [
                        store.area || data.area,
                        store.province || data.province,
                      ]
                        .filter(Boolean)
                        .join(" • ");

                      return (
                        <div
                          key={store.stableKey}
                          className="p-4 sm:p-5 flex flex-col md:flex-row md:items-center justify-between gap-4 hover:bg-surface-muted/30 transition"
                        >
                          {/* Store Details */}
                          <div className="min-w-0 flex-1 space-y-1">
                            <div className="flex flex-wrap items-center gap-2.5">
                              <span className="w-2.5 h-2.5 rounded-full bg-emerald-500 shrink-0" />
                              <h4 className="font-bold text-text-primary text-sm truncate">
                                {store.storeName}
                              </h4>
                              {store.vcode && (
                                <span className="font-mono text-xs font-bold text-brand-primary bg-brand-50 dark:bg-brand-950/40 border border-brand-200 dark:border-brand-800 px-2 py-0.5 rounded">
                                  {store.vcode}
                                </span>
                              )}
                              {/* External visibility presence badge */}
                              <span className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-surface-muted border border-border-default text-text-secondary">
                                <Clock className="w-3 h-3 text-text-muted" />
                                <span>
                                  {storeDays} • {hcShare} HC
                                </span>
                              </span>
                            </div>
                            {locationStr && (
                              <p className="text-xs text-text-secondary pl-5">
                                {locationStr}
                              </p>
                            )}
                          </div>

                          {/* Schedule & HC Details */}
                          <div className="flex flex-wrap items-center gap-4 sm:gap-6 pt-2 md:pt-0 border-t md:border-t-0 border-border-subtle shrink-0 text-xs">
                            <div className="space-y-0.5">
                              <span className="text-[11px] font-medium text-text-muted block">
                                Duty Days
                              </span>
                              <span className="font-semibold text-text-primary">
                                {storeDays}
                              </span>
                            </div>
                            <div className="space-y-0.5">
                              <span className="text-[11px] font-medium text-text-muted block">
                                Shift Window
                              </span>
                              <span className="font-mono font-semibold text-text-primary">
                                {storeTime}
                              </span>
                            </div>
                            <div className="text-right pl-3 border-l border-border-subtle">
                              <span className="text-[11px] font-semibold text-text-muted block">
                                HC Share
                              </span>
                              <p className="font-mono font-extrabold text-brand-primary text-base leading-none mt-0.5">
                                {hcShare}
                              </p>
                            </div>
                          </div>
                        </div>
                      );
                    })}
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

            {/* TAB 4: ACTIVITY & SYSTEM INFO */}
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
          initialStoreAllocations={
            data.coveredStores && data.coveredStores.length > 0
              ? data.coveredStores.map((st) => ({
                  storeId: st.storeId,
                  storeName: st.storeName,
                  vcode: st.vcode || data.vcode || "",
                  scheduleDays: st.scheduleDays || data.scheduleDays || "MON-SAT",
                  scheduleTime: st.scheduleTime || data.scheduleTime || "08:00 AM - 05:00 PM",
                  allocationPercent:
                    st.allocationPercent ??
                    (data.coveredStores.length > 1
                      ? Math.round(100 / data.coveredStores.length)
                      : 100),
                }))
              : [
                  {
                    storeId: data.storeId || "primary",
                    storeName: data.primaryStoreName || "Primary Store Assignment",
                    vcode: data.vcode || "",
                    scheduleDays: data.scheduleDays || "MON-SAT",
                    scheduleTime: data.scheduleTime || "08:00 AM - 05:00 PM",
                    allocationPercent: 100,
                  },
                ]
          }
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
