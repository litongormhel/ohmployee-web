"use client";

import { useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, ArrowRightLeft, Clock } from "lucide-react";
import {
  getWebPlantillaDetail,
  deriveDeactivationOverlay,
  deriveTransferOverlay,
  PlantillaDataError,
  type PlantillaDetailItem,
  type PlantillaRowCapabilities,
} from "@/lib/queries/plantilla";
import { useCurrentUser, isPlantillaLifecycleRole } from "@/lib/auth";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { CapabilityActionBar, type ActionItem } from "@/components/shared/CapabilityActionBar";
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

  const detailQuery = useQuery({
    queryKey: ["plantilla", "detail", plantillaId],
    queryFn: () => getWebPlantillaDetail(plantillaId!),
    enabled: Boolean(plantillaId),
    retry: false,
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
      : (data?.lastName ?? data?.firstName ?? "—");

  const headerBadge: ReactNode = data ? (
    <div className="flex items-center gap-1.5 flex-wrap">
      <StatusBadge
        variant={statusVariant(data.plantillaStatus)}
        text={data.plantillaStatus ?? "Unknown"}
      />
    </div>
  ) : undefined;

  const subtitle: ReactNode = data ? (
    <span className="truncate text-[11px] text-text-secondary">
      {[data.accountName, data.primaryStoreName || data.vcode].filter(Boolean).join(" / ")}
    </span>
  ) : undefined;

  const currentUser = useCurrentUser();
  const isAuthorized = isPlantillaLifecycleRole(currentUser?.roleKey);

  // Modal open states
  const [isSeparationModalOpen, setIsSeparationModalOpen] = useState(false);
  const [isStatusModalOpen, setIsStatusModalOpen] = useState(false);
  const [isDeactivationModalOpen, setIsDeactivationModalOpen] = useState(false);
  const [isTransferModalOpen, setIsTransferModalOpen] = useState(false);
  const [isScheduleModalOpen, setIsScheduleModalOpen] = useState(false);

  return (
    <>
      <DetailDrawer
        isOpen={isOpen}
        onClose={onClose}
        title={data ? displayName : "Loading employee record…"}
        subtitle={subtitle}
        badge={headerBadge}
        widthClass="w-[var(--drawer-width-lg)] max-w-full"
        contentClassName="p-4 space-y-3"
      >
        <DrawerBody
          isLoading={detailQuery.isLoading}
          isAccessDenied={isAccessDenied}
          isNotFound={isNotFound}
          isRetryable={isRetryable}
          data={data}
          queryError={queryError}
          onRetry={() => detailQuery.refetch()}
          deactivation={deactivation}
          transferOverlay={transferOverlay}
          isAuthorized={isAuthorized}
          onMarkSeparation={() => setIsSeparationModalOpen(true)}
          onUpdateStatus={() => setIsStatusModalOpen(true)}
          onRequestDeactivation={() => setIsDeactivationModalOpen(true)}
          onTransferEmployee={() => setIsTransferModalOpen(true)}
          onEditSchedule={() => setIsScheduleModalOpen(true)}
        />
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

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

type DeactivationOverlay = ReturnType<typeof deriveDeactivationOverlay>;
type TransferOverlay = ReturnType<typeof deriveTransferOverlay>;

function DrawerBody({
  isLoading,
  isAccessDenied,
  isNotFound,
  isRetryable,
  data,
  queryError,
  onRetry,
  deactivation,
  transferOverlay,
  isAuthorized,
  onMarkSeparation,
  onUpdateStatus,
  onRequestDeactivation,
  onTransferEmployee,
  onEditSchedule,
}: {
  isLoading: boolean;
  isAccessDenied: boolean;
  isNotFound: boolean;
  isRetryable: boolean;
  data: PlantillaDetailItem | undefined;
  queryError: PlantillaDataError | null;
  onRetry: () => void;
  deactivation: DeactivationOverlay | null;
  transferOverlay: TransferOverlay | null;
  isAuthorized: boolean;
  onMarkSeparation: () => void;
  onUpdateStatus: () => void;
  onRequestDeactivation: () => void;
  onTransferEmployee: () => void;
  onEditSchedule: () => void;
}) {
  if (isLoading) {
    return (
      <DataState
        kind="loading"
        title="Loading employee record"
        description="Fetching plantilla detail through Supabase RPC."
      />
    );
  }

  if (isAccessDenied) {
    return (
      <DataState
        kind="access_denied"
        title="Access Restricted"
        description="Supabase RLS policies blocked this read. You are not authorized to view this employee's plantilla record."
      />
    );
  }

  if (isNotFound) {
    return (
      <DataState
        kind="empty"
        title="Record Not Found"
        description="No plantilla detail record was returned for this selection."
      />
    );
  }

  if (isRetryable) {
    return (
      <DataState
        kind="error"
        title="Fetch Failed"
        description={
          queryError?.message ?? "The plantilla detail query failed. You can retry."
        }
        onRetry={onRetry}
      />
    );
  }

  if (!data) return null;

  return (
    <>
      {/* Deactivation banners */}
      {deactivation?.showSeparationBanner && (
        <div className="rounded-md border border-status-danger-border bg-status-danger-bg p-3 flex items-start gap-2">
          <AlertTriangle
            className="h-4 w-4 shrink-0 text-status-danger-text mt-0.5"
            aria-hidden="true"
          />
          <p className="text-xs leading-relaxed text-status-danger-text">
            This employee has an active separation request pending clearance
            approval. Roster details are currently locked.
          </p>
        </div>
      )}

      {deactivation?.showDeactivatedBanner && (
        <div className="rounded-md border border-status-neutral-border bg-status-neutral-bg p-3 flex items-start gap-2">
          <AlertTriangle
            className="h-4 w-4 shrink-0 text-status-neutral-text mt-0.5"
            aria-hidden="true"
          />
          <p className="text-xs leading-relaxed text-status-neutral-text">
            This profile is INACTIVE. This record is locked and archived.
          </p>
        </div>
      )}

      {/* Transfer overlay banner */}
      {transferOverlay?.hasActiveTransfer && (
        <div
          className={`rounded-md border p-3 flex items-start gap-2 ${
            transferOverlay.slaBreached
              ? "border-status-danger-border bg-status-danger-bg"
              : "border-status-info-border bg-status-info-bg"
          }`}
        >
          <ArrowRightLeft
            className={`h-4 w-4 shrink-0 mt-0.5 ${
              transferOverlay.slaBreached
                ? "text-status-danger-text"
                : "text-status-info-text"
            }`}
            aria-hidden="true"
          />
          <p
            className={`text-xs leading-relaxed ${
              transferOverlay.slaBreached
                ? "text-status-danger-text"
                : "text-status-info-text"
            }`}
          >
            <span className="font-semibold">
              {transferOverlay.transferType ?? "Transfer"} in progress
            </span>
            {transferOverlay.targetStoreName && (
              <span> → {transferOverlay.targetStoreName}</span>
            )}
            {transferOverlay.slaBreached && (
              <span className="ml-1 font-semibold">[SLA Breached]</span>
            )}
          </p>
        </div>
      )}

      {/* Employee ID badge */}
      <div className="flex items-center gap-2">
        <span className="font-mono text-xs bg-mono-pill-surface border border-mono-pill-ring rounded px-1.5 py-0.5 text-table-text">
          {data.employeeNo}
        </span>
      </div>

      {/* Employment & Allocation */}
      <SectionCard title="Employment & Allocation">
        <EmploymentGrid data={data} />
      </SectionCard>

      {/* Assignment Coverage - Only rendered for roving multi-store assignments to avoid redundancy */}
      {(data.assignmentType ?? "").toLowerCase() === "roving" && (
        <SectionCard title="Roving Store Coverage">
          <AssignmentCoverageSection data={data} />
        </SectionCard>
      )}

      {/* Ops Schedule & Dayoff Audit (ADR-002 Invariant 8) */}
      <SectionCard
        title="Schedule & Store Visit Audit"
        action={
          isAuthorized ? (
            <button
              onClick={onEditSchedule}
              className="text-3xs font-semibold text-purple-700 hover:text-purple-900 border border-purple-200 bg-purple-50 hover:bg-purple-100 rounded px-2 py-0.5 transition cursor-pointer"
            >
              Edit Schedule
            </button>
          ) : undefined
        }
      >
        <ScheduleAuditSection data={data} />
      </SectionCard>

      {/* AH slot notice */}
      {data.plantillaType === "AH" && (
        <div className="rounded-md border border-status-warning-border bg-amber-50 p-3 flex items-start gap-2">
          <Clock
            className="h-4 w-4 shrink-0 text-status-warning-text mt-0.5"
            aria-hidden="true"
          />
          <p className="text-xs leading-relaxed text-status-warning-text">
            This employee occupies a temporary Additional Headcount (AH) slot.
          </p>
        </div>
      )}

      {/* Clearance Panel: pending separation only, read-only */}
      {deactivation?.isPendingSeparation && data.clearanceChecklist.length > 0 && (
        <SectionCard title="Clearance & Offboarding Audit">
          <ClearancePanel
            status={data.clearanceStatus}
            checklist={data.clearanceChecklist}
            documents={data.clearanceDocuments}
          />
        </SectionCard>
      )}

      {/* SLA Warning */}
      {data.slaBreached && (
        <SectionCard title="SLA & Transition Performance">
          <SlaWarningBlock
            elapsedHours={data.slaElapsedHours}
            breached={data.slaBreached}
          />
        </SectionCard>
      )}

      {/* Contact & Masked PII */}
      <SectionCard title="Contact & Personal Details">
        <MaskedFieldsSection maskedFields={data.maskedFields} />
      </SectionCard>

      {/* Audit Timeline */}
      {data.auditTimeline.length > 0 && (
        <SectionCard title="Roster Audit History">
          <AuditTimeline events={data.auditTimeline} />
        </SectionCard>
      )}

      {/* Actions */}
      <CapabilityActionBar
        title="Actions"
        variant="toolbar"
        actions={buildActionItems(
          data.rowCapabilities,
          data.plantillaStatus,
          isAuthorized,
          {
            onMarkSeparation,
            onUpdateStatus,
            onRequestDeactivation,
            onTransferEmployee,
          },
        )}
      />
    </>
  );
}

// ---------------------------------------------------------------------------
// Section container
// ---------------------------------------------------------------------------

function SectionCard({
  title,
  children,
  action,
}: {
  title: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="rounded-lg border border-border-default bg-surface-base shadow-2xs">
      <div className="border-b border-border-subtle px-3.5 py-2 flex items-center justify-between">
        <h3 className="text-[11px] font-bold uppercase tracking-wider text-text-muted">
          {title}
        </h3>
        {action}
      </div>
      <div className="p-3.5">{children}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Schedule Audit Section (ADR-002 Invariant 8)
// ---------------------------------------------------------------------------

function ScheduleAuditSection({ data }: { data: PlantillaDetailItem }) {
  return (
    <div className="space-y-1.5 text-xs">
      <div className="grid grid-cols-3 gap-2">
        <div className="p-2 rounded-lg bg-surface-subtle border border-border-subtle">
          <span className="text-[10px] font-semibold uppercase tracking-wider text-text-muted block">
            Schedule Days
          </span>
          <span className="font-semibold text-text-primary mt-0.5 block truncate">
            {data.scheduleDays || "MON-SAT"}
          </span>
        </div>
        <div className="p-2 rounded-lg bg-surface-subtle border border-border-subtle">
          <span className="text-[10px] font-semibold uppercase tracking-wider text-text-muted block">
            Schedule Time
          </span>
          <span className="font-semibold text-text-primary mt-0.5 block truncate">
            {data.scheduleTime || "08:00 AM - 05:00 PM"}
          </span>
        </div>
        <div className="p-2 rounded-lg bg-surface-subtle border border-border-subtle">
          <span className="text-[10px] font-semibold uppercase tracking-wider text-text-muted block">
            Dayoff
          </span>
          <span className="font-semibold text-text-primary mt-0.5 block truncate">
            {data.dayoff || "SUN"}
          </span>
        </div>
      </div>
      <p className="text-[10px] text-text-muted">
        Shift and flexible visit windows recorded for operational store visit audits.
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employment grid
// ---------------------------------------------------------------------------

function EmploymentGrid({ data }: { data: PlantillaDetailItem }) {
  const primaryStoreDisplay = data.primaryStoreName || data.vcode || "—";
  const tenureDisplay = data.tenureDescription || computeTenure(data.dateDeployed);
  const fields = [
    { label: "Date Deployed", value: formatDate(data.dateDeployed) },
    { label: "Position", value: data.positionTitle ?? "—" },
    { label: "Account", value: data.accountName ?? "—" },
    { label: "Primary Store", value: primaryStoreDisplay },
    { label: "Base Rate", value: data.maskedFields.baseRateMasked ?? "—" },
    { label: "Tenure", value: tenureDisplay },
    { label: "Assignment", value: data.assignmentType ?? "—" },
  ];

  return (
    <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
      {fields.map(({ label, value }) => (
        <div key={label}>
          <dt className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
            {label}
          </dt>
          <dd className="mt-0.5 text-xs text-text-primary">{value}</dd>
        </div>
      ))}
    </dl>
  );
}

// ---------------------------------------------------------------------------
// Assignment coverage
// ---------------------------------------------------------------------------

function AssignmentCoverageSection({ data }: { data: PlantillaDetailItem }) {
  const isRoving = (data.assignmentType ?? "").toLowerCase() === "roving";

  if (isRoving) {
    if (data.coveredStores.length === 0) {
      return (
        <p className="text-xs text-text-muted">
          Roving assignment returned without covered store rows.
        </p>
      );
    }

    return <RovingCoverageSection stores={data.coveredStores} />;
  }

  return (
    <div className="flex items-center justify-between text-xs">
      <span className="text-text-primary">
        {data.primaryStoreName || data.vcode || "Primary store unavailable"}
      </span>
      <span className="text-text-muted">{data.assignmentType ?? "Stationary"}</span>
    </div>
  );
}

function RovingCoverageSection({
  stores,
}: {
  stores: PlantillaDetailItem["coveredStores"];
}) {
  return (
    <ul className="space-y-1.5">
      {stores.map((store) => (
        <li
          key={store.stableKey}
          className="flex items-center justify-between text-xs"
        >
          <span className="text-text-primary">
            {store.storeName}
            {store.isPrimary && (
              <span className="ml-1.5 text-[10px] font-semibold uppercase text-text-muted">
                (Primary)
              </span>
            )}
          </span>
          {store.allocationPercent !== null && (
            <span className="text-text-muted">{store.allocationPercent}%</span>
          )}
        </li>
      ))}
    </ul>
  );
}

// ---------------------------------------------------------------------------
// Clearance panel
// ---------------------------------------------------------------------------

function ClearancePanel({
  status,
  checklist,
  documents,
}: {
  status: string | null;
  checklist: PlantillaDetailItem["clearanceChecklist"];
  documents: PlantillaDetailItem["clearanceDocuments"];
}) {
  return (
    <div className="space-y-3">
      {status && (
        <p className="text-xs">
          <span className="font-semibold text-[10px] uppercase tracking-wider text-text-muted">
            Clearance Status:{" "}
          </span>
          <span className="text-text-primary">{status}</span>
        </p>
      )}

      <ul className="space-y-1.5">
        {checklist.map((item) => (
          <li key={item.stableKey} className="flex items-center gap-2 text-xs">
            <span
              className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border text-[10px] font-bold ${
                item.completed
                  ? "border-status-success-border bg-status-success-bg text-status-success-text"
                  : "border-border-default bg-surface-muted text-text-muted"
              }`}
              aria-label={item.completed ? "Completed" : "Pending"}
            >
              {item.completed ? "✓" : ""}
            </span>
            <span className="text-text-primary">{item.label}</span>
          </li>
        ))}
      </ul>

      {documents.length > 0 && (
        <div className="space-y-1">
          <p className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
            Uploaded Documents
          </p>
          <ul className="space-y-1">
            {documents.map((doc) => (
              <li key={doc.stableKey} className="text-xs text-text-secondary">
                {doc.fileName}
                <span className="ml-2 text-text-muted">
                  {formatDate(doc.uploadedAt)}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// SLA warning
// ---------------------------------------------------------------------------

function SlaWarningBlock({
  elapsedHours,
  breached,
}: {
  elapsedHours: number;
  breached: boolean;
}) {
  return (
    <div
      className={`rounded-md border p-3 ${
        breached
          ? "border-status-danger-border bg-status-danger-bg"
          : "border-border-default bg-surface-muted"
      }`}
    >
      <p
        className={`text-xs font-semibold ${
          breached ? "text-status-danger-text" : "text-text-primary"
        }`}
      >
        {breached ? "⚠ SLA Breach Detected" : "SLA Monitoring"}
      </p>
      <p
        className={`mt-0.5 text-xs ${
          breached ? "text-status-danger-text" : "text-text-secondary"
        }`}
      >
        Elapsed time: {elapsedHours} hour{elapsedHours !== 1 ? "s" : ""}.
        {breached &&
          " Clearance or transfer approval has exceeded the SLA window."}
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Masked PII fields
// ---------------------------------------------------------------------------

function MaskedFieldsSection({
  maskedFields,
}: {
  maskedFields: PlantillaDetailItem["maskedFields"];
}) {
  const { contactNumber, emailAddress, residentialAddress, governmentIds } =
    maskedFields;

  const govIds = [
    { label: "SSS", value: governmentIds.sss },
    { label: "PhilHealth", value: governmentIds.philhealth },
    { label: "Pag-IBIG", value: governmentIds.pagibig },
    { label: "TIN", value: governmentIds.tin },
  ];

  return (
    <div className="space-y-3">
      <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
        <div>
          <dt className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
            Contact Number
          </dt>
          <dd className="mt-0.5 font-mono text-xs text-text-primary">
            {contactNumber ?? "—"}
          </dd>
        </div>
        <div>
          <dt className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
            Email Address
          </dt>
          <dd className="mt-0.5 font-mono text-xs text-text-primary">
            {emailAddress ?? "—"}
          </dd>
        </div>
        <div className="col-span-2">
          <dt className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
            Residential Address
          </dt>
          <dd className="mt-0.5 text-xs text-text-primary">
            {residentialAddress ?? "—"}
          </dd>
        </div>
      </dl>

      <div>
        <p className="mb-2 text-[10px] font-semibold uppercase tracking-wider text-text-muted">
          Government IDs
        </p>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
          {govIds.map(({ label, value }) => (
            <div key={label}>
              <dt className="text-[10px] text-text-muted">{label}</dt>
              <dd className="mt-0.5 font-mono text-xs text-text-primary">
                {value ?? "—"}
              </dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Audit timeline
// ---------------------------------------------------------------------------

function AuditTimeline({
  events,
}: {
  events: PlantillaDetailItem["auditTimeline"];
}) {
  return (
    <ol className="space-y-3">
      {events.map((event) => (
        <li key={event.stableKey} className="flex gap-3 text-xs">
          <span
            className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-brand-500"
            aria-hidden="true"
          />
          <div className="min-w-0">
            <p className="font-semibold text-text-primary">{event.eventLabel}</p>
            {event.eventDescription && (
              <p className="mt-0.5 text-text-secondary">
                {event.eventDescription}
              </p>
            )}
            <p className="mt-0.5 text-text-muted">
              {formatEventDate(event.createdAt)}
              {event.profileName && ` · ${event.profileName}`}
            </p>
          </div>
        </li>
      ))}
    </ol>
  );
}

interface ActionHandlers {
  onMarkSeparation: () => void;
  onUpdateStatus: () => void;
  onRequestDeactivation: () => void;
  onTransferEmployee: () => void;
}

function buildActionItems(
  caps: PlantillaRowCapabilities,
  plantillaStatus: string | null | undefined,
  isAuthorized: boolean,
  handlers: ActionHandlers,
): ActionItem[] {
  const status = (plantillaStatus ?? "").trim().toLowerCase();
  const isInactive = status === "inactive" || status === "terminated" || status === "deactivated";
  const isPendingDeactivation = status === "pending deactivation" || status === "pending_deactivation";

  // Mark Separation: Available for Active / On Leave employees for authorized roles
  const canSeparate =
    isAuthorized && !isInactive && (caps.canSeparate !== false);

  // Update Status: Available for Active / On Leave / Floating employees
  const canUpdateStatus =
    isAuthorized && !isInactive;

  // Request Deactivation: Available for Inactive / Floating / Pending Separation employees or caps.canRequestDeactivation
  const canRequestDeact =
    isAuthorized && (caps.canRequestDeactivation || isInactive || status === "floating" || status === "rejected deactivation") && !isPendingDeactivation;

  // Transfer Employee: Available for active/deployable employees for authorized roles (caps.canTransferEmployee defaults or authorized)
  const canTransfer =
    isAuthorized && !isInactive && (caps.canTransferEmployee !== false);

  const actions: ActionItem[] = [];

  if (canUpdateStatus) {
    actions.push({
      label: "Update Status",
      isAvailable: true,
      onClick: handlers.onUpdateStatus,
      variant: "secondary",
    });
  }

  if (canTransfer) {
    actions.push({
      label: "Transfer Store",
      isAvailable: true,
      onClick: handlers.onTransferEmployee,
      variant: "secondary",
    });
  }

  if (canSeparate) {
    actions.push({
      label: "Mark Separation",
      isAvailable: true,
      onClick: handlers.onMarkSeparation,
      variant: "warning",
    });
  }

  if (canRequestDeact) {
    actions.push({
      label: "Request Deactivation",
      isAvailable: true,
      onClick: handlers.onRequestDeactivation,
      variant: "danger",
    });
  }

  return actions;
}
