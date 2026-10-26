"use client";

import { useMemo } from "react";
import {
  Clock,
  User,
  UsersRound,
  Building2,
  Layers,
  ArrowRight,
  ShieldCheck,
  AlertCircle,
  Mail,
  Phone,
} from "lucide-react";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import { Badge } from "@/components/ui/badge";
import {
  usePlantillaSlotDetail,
  useSlotHistory,
} from "@/lib/queries/plantilla";

export interface SlotDetailDrawerProps {
  slotId: string | null;
  onClose: () => void;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function slotStatusBadgeVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase().trim()) {
    case "occupied":
    case "filled":
      return "success";
    case "pipeline":
      return "info";
    case "hr_processing":
    case "hr processing":
      return "warning";
    case "open":
    case "vacancy":
      return "neutral";
    case "closed":
      return "danger";
    default:
      return "neutral";
  }
}

function slotStatusLabel(status: string | null | undefined): string {
  switch ((status ?? "").toLowerCase().trim()) {
    case "occupied":
    case "filled":
      return "Occupied";
    case "pipeline":
      return "Pipeline";
    case "hr_processing":
    case "hr processing":
      return "HR Processing";
    case "open":
      return "Open";
    case "closed":
      return "Closed";
    default:
      return status ?? "Unknown";
  }
}

function formatDate(isoStr: string | null | undefined): string {
  if (!isoStr) return "—";
  try {
    return new Intl.DateTimeFormat("en-PH", {
      dateStyle: "medium",
    }).format(new Date(isoStr));
  } catch {
    return isoStr;
  }
}

function formatTimelineDate(isoStr: string | null | undefined): string {
  if (!isoStr) return "—";
  try {
    return new Intl.DateTimeFormat("en-PH", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(isoStr));
  } catch {
    return isoStr;
  }
}

function getActionLabel(action: string): string {
  switch (action.toLowerCase().trim()) {
    case "created":
      return "Slot Created";
    case "pipeline":
      return "Applicant Sourced";
    case "hr_processing":
      return "HR Onboarding Processing";
    case "occupied":
      return "Slot Filled / Deployed";
    case "reopened":
      return "Slot Reopened";
    case "resigned":
      return "Occupant Resigned";
    case "transfer_out":
      return "Occupant Transferred Out";
    case "transfer_in":
      return "Occupant Transferred In";
    case "closed":
      return "Slot Closed / Headcount Reduced";
    case "status_change":
      return "Status Transition";
    default:
      return action.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function SlotDetailDrawer({ slotId, onClose }: SlotDetailDrawerProps) {
  const isOpen = Boolean(slotId);

  const {
    data: slot,
    isLoading: isSlotLoading,
    isError: isSlotError,
    error: slotError,
    refetch: refetchSlot,
  } = usePlantillaSlotDetail(slotId);

  const {
    data: history,
    isLoading: isHistoryLoading,
    refetch: refetchHistory,
  } = useSlotHistory(slotId);

  const sortedHistory = useMemo(() => {
    if (!history) return [];
    return [...history].sort(
      (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    );
  }, [history]);

  if (!isOpen) return null;

  return (
    <DetailDrawer
      isOpen={isOpen}
      onClose={onClose}
      widthClass="w-[var(--drawer-width-lg)] max-w-full"
      badge={
        <div className="flex items-center gap-2 flex-wrap">
          <Badge className="font-mono text-xs font-semibold bg-surface border border-border-default text-text-primary py-1 px-2.5">
            {slot?.legacyVcode || "SLOT"}
          </Badge>
          {slot && (
            <Badge className="font-mono text-xs text-text-muted bg-surface-muted border-border-default">
              Slot #{slot.slotOrdinal}
            </Badge>
          )}
        </div>
      }
      title={slot?.position ?? "Slot Inspector"}
      subtitle={
        slot ? (
          <div className="flex items-center gap-1.5 truncate">
            <Building2 className="h-3.5 w-3.5 shrink-0 text-text-muted" />
            <span className="truncate">
              {[slot.storeName || slot.storeCode, slot.accountName].filter(Boolean).join(" • ") ||
                "Store Staffing Slot"}
            </span>
          </div>
        ) : undefined
      }
    >
      {isSlotLoading ? (
        <div className="py-12">
          <DataState
            kind="loading"
            title="Loading Slot Record"
            description="Querying plantilla_slots lifecycle state and associated entities..."
          />
        </div>
      ) : isSlotError ? (
        <div className="py-8">
          <DataState
            kind="error"
            title="Unable to Load Slot Details"
            description={slotError?.message || "An unexpected error occurred while querying the slot."}
            onRetry={() => {
              refetchSlot();
              refetchHistory();
            }}
          />
        </div>
      ) : !slot ? (
        <div className="py-8">
          <DataState
            kind="empty"
            title="Slot Not Found"
            description="No active or archived slot was found matching the provided identifier."
          />
        </div>
      ) : (
        <div className="space-y-6">
          {/* Header & Status Banner */}
          <div className="rounded-lg border border-border-default bg-surface-muted p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-text-secondary">
                Lifecycle State
              </span>
              <StatusBadge
                variant={slotStatusBadgeVariant(slot.slotStatus)}
                text={slotStatusLabel(slot.slotStatus)}
              />
            </div>

            <div className="grid grid-cols-2 gap-3 pt-1 border-t border-border-subtle">
              <div>
                <div className="text-[10px] font-semibold text-text-muted">
                  Slot ID
                </div>
                <div className="font-mono text-xs text-text-primary truncate" title={slot.id}>
                  {slot.id}
                </div>
              </div>
              <div>
                <div className="text-[10px] font-semibold text-text-muted">
                  Position Type
                </div>
                <div className="text-xs font-medium text-text-primary">
                  {slot.employmentType} {slot.isRoving ? "• Roving" : "• Stationary"}
                </div>
              </div>
              <div>
                <div className="text-[10px] font-semibold text-text-muted">
                  Created Date
                </div>
                <div className="text-xs text-text-primary">
                  {formatDate(slot.createdAt)}
                </div>
              </div>
              <div>
                <div className="text-[10px] font-semibold text-text-muted">
                  Last Updated
                </div>
                <div className="text-xs text-text-primary">
                  {formatDate(slot.updatedAt)}
                </div>
              </div>
            </div>

            {slot.closedAt && (
              <div className="rounded border border-danger-border bg-danger-bg p-2.5 text-xs text-danger-text flex items-start gap-2">
                <AlertCircle className="h-4 w-4 shrink-0 text-danger-text mt-0.5" />
                <div>
                  <div className="font-semibold">Slot Retired / Closed</div>
                  <div className="text-[11px] mt-0.5 text-danger-text opacity-90">
                    Closed on {formatDate(slot.closedAt)}
                    {slot.closureReasonCode ? ` (Reason: ${slot.closureReasonCode})` : ""}
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Occupant / Reservation Card */}
          <div className="space-y-3">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-text-secondary">
              <User className="h-4 w-4 text-text-muted" />
              <span>Personnel & Reservation Status</span>
            </div>

            {slot.slotStatus === "occupied" && slot.occupant ? (
              <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-3 shadow-xs">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="text-xs font-semibold text-text-primary flex items-center gap-1.5">
                      <span>{slot.occupant.employeeName || "Assigned Personnel"}</span>
                      {slot.occupant.status && (
                        <StatusBadge
                          variant={slot.occupant.status.toLowerCase() === "active" ? "success" : "neutral"}
                          text={slot.occupant.status}
                        />
                      )}
                    </div>
                    <div className="mt-1 flex items-center gap-2 text-xs text-text-muted">
                      <span className="font-mono">{slot.occupant.employeeNo || "No Employee #"}</span>
                      <span>•</span>
                      <span>{slot.occupant.position || slot.position}</span>
                    </div>
                  </div>
                  <Badge className="text-xs font-medium border-border-default bg-surface-muted text-text-primary">
                    Active Occupant
                  </Badge>
                </div>

                <div className="text-xs text-text-muted border-t border-border-subtle pt-2.5">
                  Deployment Mode: <span className="font-medium text-text-primary">{slot.occupant.deploymentType || "Budgeted Regular"}</span>
                </div>
              </div>
            ) : slot.slotStatus === "pipeline" || slot.slotStatus === "hr_processing" ? (
              <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-3 shadow-xs">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="text-xs font-semibold text-text-primary">
                      {slot.candidate?.name || "Pipeline Candidate"}
                    </div>
                    <div className="mt-1 text-xs text-text-muted">
                      Pipeline Stage:{" "}
                      <span className="font-medium text-text-secondary">
                        {slot.candidate?.status || (slot.slotStatus === "hr_processing" ? "HR Emploc Compliance" : "Candidate Sourced")}
                      </span>
                    </div>
                  </div>
                  <Badge
                    className="text-[11px] font-normal border-border-default text-text-secondary bg-surface-muted"
                  >
                    {slot.slotStatus === "hr_processing" ? "Reserved (HR Processing)" : "Reserved (In Pipeline)"}
                  </Badge>
                </div>

                {(slot.candidate?.contactNumber || slot.candidate?.email) && (
                  <div className="flex flex-wrap gap-4 text-xs text-text-muted border-t border-border-subtle pt-2.5">
                    {slot.candidate.contactNumber && (
                      <span className="flex items-center gap-1 font-mono">
                        <Phone className="h-3 w-3 text-text-muted" />
                        {slot.candidate.contactNumber}
                      </span>
                    )}
                    {slot.candidate.email && (
                      <span className="flex items-center gap-1">
                        <Mail className="h-3 w-3 text-text-muted" />
                        {slot.candidate.email}
                      </span>
                    )}
                  </div>
                )}
              </div>
            ) : (
              <div className="rounded-lg border border-dashed border-border-default bg-surface-muted p-4 text-center">
                <UsersRound className="mx-auto h-6 w-6 text-text-muted" />
                <div className="mt-1 text-xs font-medium text-text-primary">
                  Unoccupied / Open Quota Slot
                </div>
                <div className="mt-0.5 text-[11px] text-text-muted">
                  This position slot is currently open for applicant endorsement and recruitment.
                </div>
              </div>
            )}
          </div>

          {/* Capacity Context */}
          <div className="space-y-3">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-text-secondary">
              <Layers className="h-4 w-4 text-text-muted" />
              <span>Capacity Context & Quota Rules</span>
            </div>

            <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">
                    Headcount Quota (Target)
                  </div>
                  <div className="font-mono text-sm font-bold text-text-primary">
                    {slot.requiredHeadcountQuota != null ? `${slot.requiredHeadcountQuota} slot(s)` : "1 slot"}
                  </div>
                </div>
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">
                    Slot Sequence Index
                  </div>
                  <div className="font-mono text-sm font-bold text-text-primary">
                    Ordinal #{slot.slotOrdinal}
                  </div>
                </div>
              </div>

              <div className="border-t border-border-subtle pt-2.5 text-xs text-text-secondary leading-relaxed">
                Under <strong>ADR-001 (Slot-First Architecture)</strong>, individual positions persist as permanent assets. Headcount is strictly defined as the count of approved slots. If an occupant separates, this slot is vacated back to <code className="font-mono text-[11px] bg-surface-muted px-1 rounded">open</code> state without altering total required budget.
              </div>
            </div>
          </div>

          {/* Slot History Timeline */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-1.5 text-xs font-semibold text-text-secondary">
                <Clock className="h-4 w-4 text-text-muted" />
                <span>Slot Audit Trail ({sortedHistory.length})</span>
              </div>
            </div>

            {isHistoryLoading ? (
              <div className="space-y-2 animate-pulse">
                <div className="h-12 rounded bg-surface-muted" />
                <div className="h-12 rounded bg-surface-muted" />
              </div>
            ) : sortedHistory.length === 0 ? (
              <div className="rounded-lg border border-border-default bg-surface-muted p-4 text-center text-xs text-text-muted">
                No history events recorded yet for this slot.
              </div>
            ) : (
              <ol className="relative border-l border-border-default ml-2.5 space-y-4 pt-1">
                {sortedHistory.map((event) => (
                  <li key={event.id} className="ml-4">
                    <span className="absolute -left-1.5 mt-1.5 h-3 w-3 rounded-full border-2 border-surface-base bg-brand-600 shadow-xs" />
                    <div className="rounded-lg border border-border-subtle bg-surface-base p-3 space-y-1.5 shadow-xs">
                      <div className="flex items-center justify-between gap-2">
                        <div className="text-xs font-semibold text-text-primary flex items-center gap-1.5">
                          <span>{getActionLabel(event.actionType)}</span>
                          {event.reasonCode && (
                            <span className="font-mono text-[10px] px-1.5 py-0.5 rounded bg-surface-muted text-text-secondary border border-border-subtle">
                              {event.reasonCode}
                            </span>
                          )}
                        </div>
                        <span className="font-mono text-[10px] text-text-muted">
                          {formatTimelineDate(event.createdAt)}
                        </span>
                      </div>

                      {(event.oldValue || event.newValue) && (
                        <div className="flex items-center gap-1.5 text-[11px] text-text-muted font-mono">
                          <span>{event.oldValue || "none"}</span>
                          <ArrowRight className="h-3 w-3 shrink-0 text-text-muted" />
                          <span className="font-semibold text-text-primary">{event.newValue || "none"}</span>
                        </div>
                      )}

                      {event.remarks && (
                        <p className="text-xs text-text-secondary">
                          {event.remarks}
                        </p>
                      )}

                      {event.performerName && (
                        <div className="text-[10px] text-text-muted flex items-center gap-1">
                          <ShieldCheck className="h-3 w-3 text-brand-600" />
                          <span>Performed by {event.performerName}</span>
                        </div>
                      )}
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </div>
        </div>
      )}
    </DetailDrawer>
  );
}
