"use client";

import type { ReactNode } from "react";
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
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { CapabilityActionBar } from "@/components/shared/CapabilityActionBar";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { BadgeVariant } from "@/components/ui/StatusBadge";

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
      {data.plantillaType && (
        <span
          className={`inline-flex items-center rounded border px-1.5 py-0.5 text-xs font-semibold ${
            data.plantillaType === "AH"
              ? "border-status-warning-border bg-amber-50 text-status-warning-text"
              : "border-border-default bg-surface-muted text-text-secondary"
          }`}
        >
          {data.plantillaType}
        </span>
      )}
    </div>
  ) : undefined;

  const subtitle: ReactNode = data ? (
    <span className="truncate text-[11px] text-text-secondary">
      {[data.accountName, data.primaryStoreName].filter(Boolean).join(" / ")}
    </span>
  ) : undefined;

  return (
    <DetailDrawer
      isOpen={isOpen}
      onClose={onClose}
      title={data ? displayName : "Loading employee record…"}
      subtitle={subtitle}
      badge={headerBadge}
      widthClass="w-[var(--drawer-width-lg)] max-w-full"
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
      />
    </DetailDrawer>
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

      {/* Assignment Coverage */}
      <SectionCard title="Assignment Coverage">
        <AssignmentCoverageSection data={data} />
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

      {/* Capability-Aware Action Bar */}
      <CapabilityActionBar
        title="Capability-Aware Actions"
        helperText="Actions remain read-only. Availability reflects current RBAC permissions. Supabase final verification remains authoritative."
        actions={buildActionItems(data.rowCapabilities)}
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
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <div className="rounded-md border border-border-default bg-surface-base">
      <div className="border-b border-border-subtle px-4 py-2.5">
        <h3 className="text-xs font-semibold uppercase tracking-wider text-text-muted">
          {title}
        </h3>
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Employment grid
// ---------------------------------------------------------------------------

function EmploymentGrid({ data }: { data: PlantillaDetailItem }) {
  const fields = [
    { label: "Date Deployed", value: formatDate(data.dateDeployed) },
    { label: "Position", value: data.positionTitle ?? "—" },
    { label: "Account", value: data.accountName ?? "—" },
    { label: "Primary Store", value: data.primaryStoreName ?? "—" },
    { label: "Base Rate", value: data.maskedFields.baseRateMasked ?? "—" },
    { label: "Tenure", value: data.tenureDescription ?? "—" },
    { label: "Assignment", value: data.assignmentType ?? "—" },
    { label: "Plantilla Type", value: data.plantillaType ?? "—" },
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
        {data.primaryStoreName ?? "Primary store unavailable"}
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

// ---------------------------------------------------------------------------
// Capability action items
// ---------------------------------------------------------------------------

function buildActionItems(caps: PlantillaRowCapabilities) {
  return [
    { label: "Request Deactivation", isAvailable: caps.canRequestDeactivation },
    { label: "Review Deactivation", isAvailable: caps.canReviewDeactivation },
    { label: "Request Deletion", isAvailable: caps.canRequestDeletion },
    { label: "Review Deletion", isAvailable: caps.canReviewDeletion },
    { label: "Transfer Employee", isAvailable: caps.canTransferEmployee },
  ];
}
