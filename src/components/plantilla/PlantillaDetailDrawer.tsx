"use client";

import { useState } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import {
  AlertTriangle,
  ArrowRightLeft,
  Briefcase,
  Calendar,
  ChevronDown,
  ChevronUp,
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
} from "lucide-react";
import {
  getWebPlantillaDetail,
  syncPlantillaMika,
  deriveDeactivationOverlay,
  deriveTransferOverlay,
  PlantillaDataError,
} from "@/lib/queries/plantilla";
import { useCurrentUser, isPlantillaLifecycleRole } from "@/lib/auth";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { BadgeVariant } from "@/components/ui/StatusBadge";
import { InitiateSeparationModal } from "@/components/plantilla/InitiateSeparationModal";
import { UpdateEmploymentStatusModal } from "@/components/plantilla/UpdateEmploymentStatusModal";
import { RequestDeactivationModal } from "@/components/plantilla/RequestDeactivationModal";
import { TransferPersonnelModal } from "@/components/plantilla/TransferPersonnelModal";
import { UpdateScheduleModal } from "@/components/plantilla/UpdateScheduleModal";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function statusVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase()) {
    case "active":
      return "success";
    case "pending transfer":
    case "pending_transfer":
      return "info";
    case "pending separation":
    case "pending_separation":
      return "danger";
    case "suspended":
      return "warning";
    case "inactive":
    case "terminated":
      return "neutral";
    default:
      return "neutral";
  }
}

function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return "—";
  try {
    return new Intl.DateTimeFormat("en-PH", { dateStyle: "medium" }).format(
      new Date(dateStr),
    );
  } catch {
    return dateStr;
  }
}

export function computeTenure(dateStr: string | null | undefined): string {
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

function getInitials(
  firstName?: string | null,
  lastName?: string | null,
  displayName?: string | null,
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
  return "AA";
}

function formatBenefitValue(
  value: string | null | undefined,
  isMasked: boolean,
  maskedFallback?: string | null,
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

type TabKey = "profile" | "benefits" | "stores" | "activity";

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

export interface PlantillaDetailDrawerProps {
  plantillaId: string | null;
  onClose: () => void;
}

// ---------------------------------------------------------------------------
// Main drawer
// ---------------------------------------------------------------------------

export function PlantillaDetailDrawer({
  plantillaId,
  onClose,
}: PlantillaDetailDrawerProps) {
  const isOpen = Boolean(plantillaId);
  const [activeTab, setActiveTab] = useState<TabKey>("profile");
  const [isMasked, setIsMasked] = useState(true);
  const [isSystemInfoOpen, setIsSystemInfoOpen] = useState(false);
  const [actionFeedback, setActionFeedback] = useState<{
    type: "info" | "success" | "error";
    message: string;
  } | null>(null);

  // Modal open states
  const [isSeparationModalOpen, setIsSeparationModalOpen] = useState(false);
  const [isStatusModalOpen, setIsStatusModalOpen] = useState(false);
  const [isDeactivationModalOpen, setIsDeactivationModalOpen] = useState(false);
  const [isTransferModalOpen, setIsTransferModalOpen] = useState(false);
  const [isScheduleModalOpen, setIsScheduleModalOpen] = useState(false);

  const detailQuery = useQuery({
    queryKey: ["plantilla", "detail", plantillaId],
    queryFn: () => getWebPlantillaDetail(plantillaId!),
    enabled: Boolean(plantillaId),
    retry: false,
  });

  const syncMutation = useMutation({
    mutationFn: () => syncPlantillaMika(plantillaId!),
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
      : (data?.lastName ?? data?.firstName ?? "Loading employee record…");

  const initials = getInitials(data?.firstName, data?.lastName, displayName);

  const currentUser = useCurrentUser();
  const isAuthorized = isPlantillaLifecycleRole(currentUser?.roleKey);

  const status = (data?.plantillaStatus ?? "").trim().toLowerCase();
  const isInactive =
    status === "inactive" || status === "terminated" || status === "deactivated";
  const isPendingDeactivation =
    status === "pending deactivation" || status === "pending_deactivation";

  if (!isOpen) return null;

  return (
    <>
      <DetailDrawer
        isOpen={isOpen}
        onClose={onClose}
        widthClass="w-full sm:max-w-2xl max-w-full"
        title={displayName}
        subtitle={
          <div className="flex items-center flex-wrap gap-2 text-xs text-text-secondary mt-1">
            <span className="flex items-center gap-1 font-mono">
              <IdCard className="w-3.5 h-3.5" /> ID: {data?.employeeNo ?? "—"}
            </span>
            <span>•</span>
            <span className="flex items-center gap-1">
              <Calendar className="w-3.5 h-3.5" /> Deployed: {formatDate(data?.dateDeployed ?? data?.dateHired)}
            </span>
          </div>
        }
        badge={
          data?.plantillaStatus ? (
            <StatusBadge
              variant={statusVariant(data.plantillaStatus)}
              text={data.plantillaStatus}
            />
          ) : null
        }
        contentClassName="p-0 flex flex-col flex-1 overflow-hidden"
      >
        {/* Navigation Tabs */}
        <div className="flex border-b border-border-default px-5 bg-surface-base text-sm font-medium gap-1 shrink-0">
          <button
            type="button"
            onClick={() => setActiveTab("profile")}
            className={`px-4 py-2.5 border-b-2 font-medium transition cursor-pointer text-xs uppercase tracking-wider ${
              activeTab === "profile"
                ? "border-brand-primary text-brand-primary font-bold"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            Profile
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("benefits")}
            className={`px-4 py-2.5 border-b-2 font-medium transition cursor-pointer text-xs uppercase tracking-wider ${
              activeTab === "benefits"
                ? "border-brand-primary text-brand-primary font-bold"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            Benefits
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("stores")}
            className={`px-4 py-2.5 border-b-2 font-medium transition cursor-pointer text-xs uppercase tracking-wider ${
              activeTab === "stores"
                ? "border-brand-primary text-brand-primary font-bold"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            Stores
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("activity")}
            className={`px-4 py-2.5 border-b-2 font-medium transition cursor-pointer text-xs uppercase tracking-wider ${
              activeTab === "activity"
                ? "border-brand-primary text-brand-primary font-bold"
                : "border-transparent text-text-secondary hover:text-text-primary"
            }`}
          >
            Activity
          </button>
        </div>

        {/* Scrollable Body */}
        <div className="p-5 overflow-y-auto space-y-5 flex-1 bg-surface-muted/30">
          {detailQuery.isLoading && (
            <DataState
              kind="loading"
              title="Loading employee record"
              description="Fetching plantilla detail through Supabase RPC."
            />
          )}

          {isAccessDenied && (
            <DataState
              kind="access_denied"
              title="Access Restricted"
              description="Supabase RLS policies blocked this read. You are not authorized to view this employee's plantilla record."
            />
          )}

          {isNotFound && (
            <DataState
              kind="empty"
              title="Record Not Found"
              description="No plantilla detail record was returned for this selection."
            />
          )}

          {isRetryable && (
            <DataState
              kind="error"
              title="Fetch Failed"
              description={
                queryError?.message ??
                "The plantilla detail query failed. You can retry."
              }
              onRetry={() => detailQuery.refetch()}
            />
          )}

          {data && (
            <>
              {/* Feedback toast banner */}
              {actionFeedback && (
                <div
                  className={`rounded-lg p-3 text-xs flex items-center justify-between ${
                    actionFeedback.type === "error"
                      ? "bg-danger-bg text-danger-text border border-danger-border"
                      : "bg-surface-muted text-text-primary border border-border-default"
                  }`}
                >
                  <span>{actionFeedback.message}</span>
                  <button
                    type="button"
                    onClick={() => setActionFeedback(null)}
                    className="ml-2 font-bold cursor-pointer"
                  >
                    ×
                  </button>
                </div>
              )}

              {/* Employee Summary Card */}
              <div className="flex items-center gap-4 p-4 rounded-xl border border-border-default bg-surface shadow-xs">
                <div className="w-12 h-12 rounded-full bg-surface-muted border border-border-default flex items-center justify-center text-base font-bold text-text-primary tracking-wider shrink-0">
                  {initials}
                </div>
                <div className="min-w-0 flex-1">
                  <h2 className="text-base font-bold text-text-primary truncate">
                    {displayName}
                  </h2>
                  <p className="text-xs text-text-secondary font-mono mt-0.5">
                    {data.positionTitle || "Position unassigned"} • {data.primaryStoreName || data.vcode || "Store unassigned"}
                  </p>
                </div>
              </div>

              {/* PROFILE TAB CONTENT */}
              {activeTab === "profile" && (
                <div className="space-y-5">
                  {/* Deactivation & Transfer Banners */}
                  {deactivation?.showSeparationBanner && (
                    <div className="rounded-lg border border-border-default bg-surface-muted p-3 flex items-start gap-2 text-text-primary">
                      <AlertTriangle className="h-4 w-4 shrink-0 text-text-secondary mt-0.5" />
                      <p className="text-xs leading-relaxed text-text-secondary">
                        This employee has an active separation request pending clearance approval.
                      </p>
                    </div>
                  )}

                  {deactivation?.showDeactivatedBanner && (
                    <div className="rounded-lg border border-border-default bg-surface-muted p-3 flex items-start gap-2 text-text-secondary">
                      <AlertTriangle className="h-4 w-4 shrink-0 text-text-secondary mt-0.5" />
                      <p className="text-xs leading-relaxed">
                        This profile is INACTIVE. This record is locked and archived.
                      </p>
                    </div>
                  )}

                  {transferOverlay?.hasActiveTransfer && (
                    <div className="rounded-lg border border-border-default bg-surface-muted p-3 flex items-start gap-2 text-text-primary">
                      <ArrowRightLeft className="h-4 w-4 shrink-0 mt-0.5 text-text-secondary" />
                      <p className="text-xs leading-relaxed">
                        <span className="font-semibold text-text-primary">
                          {transferOverlay.transferType ?? "Transfer"} in progress
                        </span>
                        {transferOverlay.targetStoreName && (
                          <span className="text-text-secondary"> → {transferOverlay.targetStoreName}</span>
                        )}
                        {transferOverlay.slaBreached && (
                          <span className="ml-1 font-semibold text-text-primary">[SLA Breached]</span>
                        )}
                      </p>
                    </div>
                  )}

                  {/* Employment & Allocation Grid */}
                  <div className="bg-surface rounded-xl p-5 shadow-xs border border-border-default">
                    <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary mb-3 flex items-center gap-2">
                      <Briefcase className="w-3.5 h-3.5 text-brand-primary" /> Employment & Allocation
                    </h3>
                    <div className="grid grid-cols-2 gap-x-6 gap-y-4 text-xs">
                      <div>
                        <span className="text-text-secondary">VCODE</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5 font-mono">
                          {data.vcode || "—"}
                        </p>
                      </div>
                      <div>
                        <span className="text-text-secondary">Position</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.positionTitle || "—"}
                        </p>
                      </div>
                      <div>
                        <span className="text-text-secondary">Store</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.primaryStoreName || data.vcode || "—"}
                        </p>
                      </div>
                      <div>
                        <span className="text-text-secondary">Employment Type</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.employmentType || data.assignmentType || "—"}
                        </p>
                      </div>
                      <div>
                        <span className="text-text-secondary">Date Hired</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {formatDate(data.dateHired || data.dateDeployed)}
                        </p>
                      </div>
                      <div>
                        <span className="text-text-secondary">Tenure</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.tenureDescription || computeTenure(data.dateDeployed || data.dateHired)}
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Work Schedule & Rate Card */}
                  <div className="bg-surface rounded-xl p-5 shadow-xs border border-border-default">
                    <div className="flex items-center justify-between mb-3">
                      <h3 className="text-xs font-bold uppercase tracking-wider text-brand-primary flex items-center gap-2">
                        <Clock className="w-3.5 h-3.5" /> Work Schedule & Rate
                      </h3>
                      {isAuthorized && (
                        <button
                          type="button"
                          onClick={() => setIsScheduleModalOpen(true)}
                          className="text-text-secondary hover:text-brand-primary transition text-xs font-medium flex items-center gap-1 bg-surface-muted hover:bg-surface-base px-2.5 py-1 rounded-md border border-border-default cursor-pointer"
                        >
                          <Pencil className="w-3 h-3" /> Edit Schedule
                        </button>
                      )}
                    </div>
                    <div className="grid grid-cols-2 gap-x-6 gap-y-4 text-xs">
                      <div>
                        <span className="text-text-secondary">Schedule Days</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.scheduleDays || "Mon - Sat"}
                        </p>
                      </div>
                      <div>
                        <span className="text-text-secondary">Schedule Time</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.scheduleTime || "08:00 AM - 05:00 PM"}
                        </p>
                      </div>
                      <div>
                        <span className="text-text-secondary">Day Off</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.dayoff || "Sun"}
                        </p>
                      </div>
                      <div>
                        <span className="text-text-secondary">Daily Rate</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.dailyRate || data.maskedFields.baseRateMasked || "—"}
                        </p>
                      </div>
                      <div className="col-span-2">
                        <span className="text-text-secondary">Coordinator</span>
                        <p className="font-semibold text-text-primary text-sm mt-0.5">
                          {data.coordinator || data.hrcoName || "—"}
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* System Information Accordion */}
                  <div className="bg-surface rounded-xl shadow-xs border border-border-default overflow-hidden">
                    <button
                      type="button"
                      onClick={() => setIsSystemInfoOpen(!isSystemInfoOpen)}
                      className="w-full p-4 flex items-center justify-between text-left text-xs font-bold uppercase tracking-wider text-text-secondary bg-surface-muted hover:bg-surface-base transition cursor-pointer"
                    >
                      <span className="flex items-center gap-2 text-text-primary">
                        <Settings className="w-3.5 h-3.5 text-brand-primary" /> System Information
                      </span>
                      {isSystemInfoOpen ? (
                        <ChevronUp className="w-3.5 h-3.5" />
                      ) : (
                        <ChevronDown className="w-3.5 h-3.5" />
                      )}
                    </button>
                    {isSystemInfoOpen && (
                      <div className="p-4 border-t border-border-subtle bg-surface grid grid-cols-2 gap-x-6 gap-y-3 text-xs">
                        <div>
                          <span className="text-text-secondary">Plantilla ID</span>
                          <p className="font-mono text-text-primary text-xs mt-0.5 truncate">{data.id}</p>
                        </div>
                        <div>
                          <span className="text-text-secondary">Account Name</span>
                          <p className="font-semibold text-text-primary text-xs mt-0.5">{data.accountName || "—"}</p>
                        </div>
                        <div>
                          <span className="text-text-secondary">Status</span>
                          <p className="font-semibold text-text-primary text-xs mt-0.5">{data.plantillaStatus || "Active"}</p>
                        </div>
                        <div>
                          <span className="text-text-secondary">Province / Area</span>
                          <p className="font-semibold text-text-primary text-xs mt-0.5">{data.province || data.area || "—"}</p>
                        </div>
                        <div>
                          <span className="text-text-secondary">Island Group</span>
                          <p className="font-semibold text-text-primary text-xs mt-0.5">{data.islandGroup || "—"}</p>
                        </div>
                        <div>
                          <span className="text-text-secondary">Assignment Type</span>
                          <p className="font-semibold text-text-primary text-xs mt-0.5">{data.assignmentType || "Stationary"}</p>
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Capability-Aware Personnel Actions */}
                  <div className="bg-surface rounded-xl p-4 shadow-xs border border-border-default">
                    <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary mb-3">
                      Capability-Aware Personnel Actions
                    </h3>
                    <div className="grid grid-cols-2 gap-3">
                      <button
                        type="button"
                        onClick={() => setIsTransferModalOpen(true)}
                        disabled={!isAuthorized || isInactive}
                        className="bg-surface-muted hover:bg-surface-base border border-border-default text-text-primary disabled:opacity-50 disabled:cursor-not-allowed rounded-lg p-2.5 text-xs font-semibold flex items-center justify-center gap-2 transition cursor-pointer"
                      >
                        <ArrowRightLeft className="w-3.5 h-3.5 text-brand-primary" /> Transfer Employee
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setActionFeedback({
                            type: "info",
                            message: "HR Coordinator assignment request submitted for review.",
                          });
                        }}
                        disabled={!isAuthorized || isInactive}
                        className="bg-surface-muted hover:bg-surface-base border border-border-default text-text-primary disabled:opacity-50 disabled:cursor-not-allowed rounded-lg p-2.5 text-xs font-semibold flex items-center justify-center gap-2 transition cursor-pointer"
                      >
                        <ShieldCheck className="w-3.5 h-3.5 text-brand-primary" /> Reassign HRCO
                      </button>
                      <button
                        type="button"
                        onClick={() => setIsDeactivationModalOpen(true)}
                        disabled={!isAuthorized || isPendingDeactivation}
                        className="bg-surface-muted hover:bg-surface-base border border-border-default text-text-primary disabled:opacity-50 disabled:cursor-not-allowed rounded-lg p-2.5 text-xs font-semibold flex items-center justify-center gap-2 transition cursor-pointer"
                      >
                        <UserMinus className="w-3.5 h-3.5 text-text-secondary" /> Request Deactivation
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setActionFeedback({
                            type: "info",
                            message: "Deletion request logged and routed to operations queue.",
                          });
                        }}
                        disabled={!isAuthorized}
                        className="bg-danger-bg/40 hover:bg-danger-bg text-danger-text border border-danger-border disabled:opacity-50 disabled:cursor-not-allowed rounded-lg p-2.5 text-xs font-semibold flex items-center justify-center gap-2 transition cursor-pointer"
                      >
                        <Trash2 className="w-3.5 h-3.5 text-danger-text" /> Request Deletion
                      </button>
                      <button
                        type="button"
                        onClick={() => setIsStatusModalOpen(true)}
                        disabled={!isAuthorized || isInactive}
                        className="col-span-2 bg-brand-primary hover:bg-brand-secondary text-white disabled:opacity-50 disabled:cursor-not-allowed rounded-lg p-2.5 text-xs font-bold flex items-center justify-center gap-2 transition cursor-pointer"
                      >
                        <UserCheck className="w-3.5 h-3.5" /> Update Employment Status
                      </button>
                    </div>
                  </div>
                </div>
              )}

              {/* BENEFITS TAB CONTENT */}
              {activeTab === "benefits" && (
                <div className="space-y-4">
                  <div className="bg-surface rounded-xl p-5 shadow-xs border border-border-default space-y-4">
                    <div className="flex justify-between items-center border-b border-border-subtle pb-3">
                      <h3 className="text-xs font-bold uppercase tracking-wider text-text-secondary">
                        Benefit Numbers
                      </h3>
                      <button
                        type="button"
                        onClick={() => setIsMasked(!isMasked)}
                        className="text-text-secondary hover:text-brand-primary transition text-sm p-1 cursor-pointer"
                        title={isMasked ? "Reveal benefit numbers" : "Mask benefit numbers"}
                      >
                        {isMasked ? <Eye className="w-4 h-4" /> : <EyeOff className="w-4 h-4" />}
                      </button>
                    </div>

                    <div className="flex justify-between items-center border-b border-border-subtle pb-3">
                      <span className="text-xs font-semibold text-text-secondary flex items-center gap-2">
                        <Shield className="w-3.5 h-3.5 text-brand-primary" /> SSS
                      </span>
                      <span className="text-sm font-medium text-text-primary font-mono">
                        {formatBenefitValue(data.maskedFields.governmentIds.sss, isMasked)}
                      </span>
                    </div>

                    <div className="flex justify-between items-center border-b border-border-subtle pb-3">
                      <span className="text-xs font-semibold text-text-secondary flex items-center gap-2">
                        <HeartPulse className="w-3.5 h-3.5 text-pct-good-text" /> PhilHealth
                      </span>
                      <span className="text-sm font-medium text-text-primary font-mono">
                        {formatBenefitValue(data.maskedFields.governmentIds.philhealth, isMasked)}
                      </span>
                    </div>

                    <div className="flex justify-between items-center border-b border-border-subtle pb-3">
                      <span className="text-xs font-semibold text-text-secondary flex items-center gap-2">
                        <Home className="w-3.5 h-3.5 text-pct-warn-text" /> Pag-IBIG
                      </span>
                      <span className="text-sm font-medium text-text-primary font-mono">
                        {formatBenefitValue(data.maskedFields.governmentIds.pagibig, isMasked)}
                      </span>
                    </div>

                    <div className="flex justify-between items-center pb-1">
                      <span className="text-xs font-semibold text-text-secondary flex items-center gap-2">
                        <CreditCard className="w-3.5 h-3.5 text-brand-primary" /> ATM Number
                      </span>
                      <span className="text-sm font-medium text-text-primary font-mono">
                        {formatBenefitValue(
                          data.maskedFields.governmentIds.atmNumber ||
                            data.maskedFields.governmentIds.atmNumberMasked,
                          isMasked,
                          data.maskedFields.governmentIds.atmNumberMasked,
                        )}
                      </span>
                    </div>
                  </div>

                  {/* Sync MIKA Card */}
                  <div className="bg-surface rounded-xl p-4 shadow-xs border border-border-default flex items-center justify-between">
                    <div>
                      <p className="text-xs font-bold text-text-primary flex items-center gap-1.5">
                        <RefreshCw className="w-3.5 h-3.5 text-brand-primary" /> Last synced from MIKA
                      </p>
                      <p className="text-[11px] text-text-secondary mt-0.5">
                        {data.lastMikaSyncedAt
                          ? `${formatEventDate(data.lastMikaSyncedAt)} / Synced`
                          : "Never synced / Sync by: —"}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => syncMutation.mutate()}
                      disabled={syncMutation.isPending}
                      className="bg-surface hover:bg-surface-muted border border-border-default text-brand-primary px-4 py-2 rounded-lg text-xs font-bold flex items-center gap-2 transition shadow-xs cursor-pointer disabled:opacity-50"
                    >
                      <RefreshCw
                        className={`w-3.5 h-3.5 ${syncMutation.isPending ? "animate-spin" : ""}`}
                      />
                      {syncMutation.isPending ? "Syncing…" : "Sync MIKA"}
                    </button>
                  </div>
                </div>
              )}

              {/* STORES TAB CONTENT */}
              {activeTab === "stores" && (
                <div className="space-y-4">
                  <div className="bg-surface rounded-xl p-5 shadow-xs border border-border-default flex justify-around text-center">
                    <div>
                      <p className="text-xl font-bold text-pct-good-text">
                        {data.coveredStores && data.coveredStores.length > 0
                          ? data.coveredStores.length
                          : 1}
                      </p>
                      <p className="text-xs text-text-secondary uppercase tracking-wider mt-0.5">
                        Current Stores
                      </p>
                    </div>
                    <div className="border-r border-border-default" />
                    <div>
                      <p className="text-xl font-bold text-text-secondary">0</p>
                      <p className="text-xs text-text-secondary uppercase tracking-wider mt-0.5">
                        Past Stores
                      </p>
                    </div>
                  </div>

                  {data.coveredStores && data.coveredStores.length > 0 ? (
                    data.coveredStores.map((store) => (
                      <div
                        key={store.stableKey}
                        className="bg-surface rounded-xl p-4 shadow-xs border border-border-default"
                      >
                        <div className="flex items-start gap-3">
                          <div className="w-3 h-3 rounded-full bg-pct-good-text mt-1.5 shrink-0" />
                          <div>
                            <h3 className="font-bold text-text-primary text-sm">
                              {store.storeName}
                            </h3>
                            <p className="text-xs text-brand-primary font-mono mt-0.5">
                              {data.vcode || "—"}
                            </p>
                            <p className="text-xs text-text-secondary mt-1">
                              Area: {data.area || data.province || "—"}
                            </p>
                            <p className="text-xs text-text-secondary mt-0.5">
                              HC Share:{" "}
                              {store.allocationPercent != null
                                ? (store.allocationPercent / 100).toFixed(2)
                                : "1.00"}
                            </p>
                          </div>
                        </div>
                      </div>
                    ))
                  ) : (
                    <div className="bg-surface rounded-xl p-4 shadow-xs border border-border-default">
                      <div className="flex items-start gap-3">
                        <div className="w-3 h-3 rounded-full bg-pct-good-text mt-1.5 shrink-0" />
                        <div>
                          <h3 className="font-bold text-text-primary text-sm">
                            {data.primaryStoreName || "Primary Store"}
                          </h3>
                          <p className="text-xs text-brand-primary font-mono mt-0.5">
                            {data.vcode || "—"}
                          </p>
                          <p className="text-xs text-text-secondary mt-1">
                            Area: {data.area || data.province || "—"}
                          </p>
                          <p className="text-xs text-text-secondary mt-0.5">HC Share: 1.00</p>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              )}

              {/* ACTIVITY TAB CONTENT */}
              {activeTab === "activity" && (
                <div className="space-y-4">
                  {data.auditTimeline && data.auditTimeline.length > 0 ? (
                    data.auditTimeline.map((item) => (
                      <div
                        key={item.stableKey}
                        className="bg-surface rounded-xl p-4 shadow-xs border border-border-default"
                      >
                        <div className="flex gap-3">
                          <div className="w-8 h-8 rounded-lg bg-surface-muted text-brand-primary flex items-center justify-center shrink-0">
                            <Store className="w-4 h-4" />
                          </div>
                          <div>
                            <p className="text-xs font-semibold text-text-primary">
                              {item.eventLabel}
                            </p>
                            {item.eventDescription && (
                              <p className="text-xs text-text-secondary mt-0.5">
                                {item.eventDescription}
                              </p>
                            )}
                            <p className="text-[10px] text-text-secondary mt-0.5">
                              {formatEventDate(item.createdAt)}
                              {item.profileName && ` · ${item.profileName}`}
                            </p>
                            {data.vcode && (
                              <p className="text-[11px] font-mono text-brand-primary mt-1">
                                {data.vcode}
                              </p>
                            )}
                          </div>
                        </div>
                      </div>
                    ))
                  ) : (
                    <div className="bg-surface rounded-xl p-4 shadow-xs border border-border-default">
                      <div className="flex gap-3">
                        <div className="w-8 h-8 rounded-lg bg-surface-muted text-brand-primary flex items-center justify-center shrink-0">
                          <Store className="w-4 h-4" />
                        </div>
                        <div>
                          <p className="text-xs font-semibold text-text-primary">
                            Employee deployed to Plantilla - {data.primaryStoreName || data.vcode || "Store"}
                          </p>
                          <p className="text-[10px] text-text-secondary mt-0.5">
                            {formatEventDate(data.dateDeployed || data.dateHired)}
                          </p>
                          {data.vcode && (
                            <p className="text-[11px] font-mono text-brand-primary mt-1">
                              {data.vcode}
                            </p>
                          )}
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </>
          )}
        </div>
      </DetailDrawer>

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
    </>
  );
}
