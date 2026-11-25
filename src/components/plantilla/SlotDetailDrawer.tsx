"use client";

import { useMemo, useState } from "react";
import {
  Clock,
  User,
  UsersRound,
  Building2,
  Layers,
  ShieldCheck,
  AlertCircle,
  Mail,
  Phone,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { DataState } from "@/components/shared/DataState";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import { Badge } from "@/components/ui/badge";
import {
  usePlantillaSlotDetail,
  useSlotHistory,
} from "@/lib/queries/plantilla";
import { formatStoreName } from "@/lib/utils/displayText";

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

function humanizeActionType(action: string): { label: string; variant: BadgeVariant } {
  const a = (action || "").toLowerCase().trim();
  switch (a) {
    case "occupied":
    case "slot_occupied":
      return { label: "Slot Filled / Deployed", variant: "success" };
    case "deployed":
    case "employee_deployed":
      return { label: "Personnel Deployed", variant: "success" };
    case "hr_processing":
    case "hr processing":
      return { label: "HR Processing", variant: "warning" };
    case "pipeline":
      return { label: "Applicant Sourced", variant: "info" };
    case "confirmed onboard":
    case "confirmed_onboard":
      return { label: "Confirmed Onboard", variant: "success" };
    case "created":
    case "slot_created":
      return { label: "Slot Created", variant: "neutral" };
    case "reopened":
    case "slot_reopened":
      return { label: "Slot Reopened", variant: "neutral" };
    case "resigned":
    case "occupant_resigned":
      return { label: "Occupant Resigned", variant: "warning" };
    case "deactivated":
    case "deactivation":
      return { label: "Slot Deactivated", variant: "danger" };
    case "separated":
      return { label: "Personnel Separated", variant: "danger" };
    case "transfer_out":
      return { label: "Occupant Transferred Out", variant: "info" };
    case "transfer_in":
      return { label: "Occupant Transferred In", variant: "info" };
    case "closed":
      return { label: "Slot Closed / Headcount Reduced", variant: "danger" };
    case "quota_revised":
      return { label: "Quota Updated", variant: "info" };
    case "status_change":
      return { label: "Status Transition", variant: "neutral" };
    default:
      return {
        label: action.replace(/[_-]/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()),
        variant: "neutral",
      };
  }
}

function humanizeStatus(status: string | null | undefined): string {
  if (!status) return "";
  const s = status.toLowerCase().trim();
  switch (s) {
    case "hr_processing":
    case "hr processing":
      return "HR Processing";
    case "occupied":
    case "filled":
      return "Occupied";
    case "pipeline":
      return "Pipeline";
    case "open":
    case "vacancy":
      return "Open";
    case "closed":
      return "Closed";
    case "none":
      return "None";
    default:
      return status.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

function humanizeRemarks(
  remarks: string | null | undefined,
  actionType?: string,
  reasonCode?: string | null
): string {
  if (!remarks) return "";
  let text = remarks.trim();

  // 1. Separation / Resignation / AWOL / Termination patterns
  if (
    /plantilla_update_separation/i.test(text) ||
    /reason=RESIGNED/i.test(text) ||
    actionType?.toLowerCase() === "resigned" ||
    reasonCode?.toUpperCase() === "RESIGNED"
  ) {
    const reasonMatch = text.match(/reason=([A-Z_]+)/i);
    const rawReason = reasonMatch ? reasonMatch[1].toUpperCase() : reasonCode?.toUpperCase() || "RESIGNED";
    const formattedReason =
      rawReason === "RESIGNED"
        ? "Resigned"
        : rawReason === "AWOL"
        ? "AWOL"
        : rawReason === "TERMINATED"
        ? "Terminated"
        : rawReason;
    return `Occupant separated (${formattedReason}). Workforce slot vacated and returned to open pool.`;
  }

  // 2. Deployment / Onboard patterns
  if (/auto_move_to_plantilla/i.test(text) || /slot occupied by plantilla/i.test(text)) {
    return "Slot occupied and assigned to deployed plantilla staff.";
  }

  if (/confirm_applicant_onboard/i.test(text)) {
    return "Applicant confirmed onboard and transitioned to HR Emploc for deployment.";
  }

  // 3. Clean out internal RPC signatures, parameter dumps, and UUIDs
  text = text.replace(/auto_move_to_plantilla:\s*/gi, "");
  text = text.replace(/Phase\s*[\d.]+\s*(\([^)]*\))?\s*\/?\s*/gi, "");
  text = text.replace(/confirm_applicant_onboard\s*\/?\s*/gi, "");
  text = text.replace(/\/?[a-z_]+_id=[0-9a-f-]+/gi, "");
  text = text.replace(/\/?[a-z_]+=[A-Z0-9_-]+/gi, "");
  text = text.replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, "");

  // Clean up internal syntax residues
  text = text.replace(/\s*\/\s*\/\s*/g, " / ").replace(/\s*\/\s*$/g, "").replace(/^\s*\/\s*/g, "");
  text = text.replace(/by plantilla\s*$/i, "by deployed personnel.");
  text = text.replace(/slot occupied by plantilla/i, "Slot occupied and assigned to plantilla staff.");
  text = text.replace(/applicant confirmed onboard and moved to hr emploc for/i, "Applicant confirmed onboard and transitioned to HR Emploc for");

  text = text.trim();
  if (!text || text.length < 3) {
    const a = (actionType || "").toLowerCase();
    if (a.includes("occupied")) return "Workforce slot successfully occupied by deployed staff.";
    if (a.includes("hr_processing")) return "Candidate transitioned to HR processing pipeline.";
    if (a.includes("pipeline")) return "Candidate assigned and undergoing applicant pipeline review.";
    if (a.includes("deployed")) return "Staff member successfully deployed to store branch.";
    if (a.includes("resigned") || a.includes("separated")) return "Occupant separated. Slot vacated and returned to open pool.";
    return "Event successfully processed and logged.";
  }

  return text.charAt(0).toUpperCase() + text.slice(1);
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function SlotDetailDrawer({ slotId, onClose }: SlotDetailDrawerProps) {
  const isOpen = Boolean(slotId);
  const [showAllHistory, setShowAllHistory] = useState(false);
  const [prevSlotId, setPrevSlotId] = useState<string | null>(null);

  if (slotId !== prevSlotId) {
    setPrevSlotId(slotId);
    setShowAllHistory(false);
  }

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

  const isRoving = Boolean(slot?.isRoving);
  const vcodeColorClass = slot?.legacyVcode
    ? isRoving
      ? "border-purple-300 bg-purple-50 text-purple-700 dark:border-purple-800 dark:bg-purple-950/60 dark:text-purple-300"
      : "border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-800 dark:bg-blue-950/60 dark:text-blue-300"
    : isRoving
    ? "border-dashed border-purple-300 bg-purple-50/50 text-purple-600 dark:border-purple-800/60 dark:bg-purple-950/30 dark:text-purple-400"
    : "border-dashed border-blue-300 bg-blue-50/50 text-blue-600 dark:border-blue-800/60 dark:bg-blue-950/30 dark:text-blue-400";

  const vcodeTooltip = slot?.legacyVcode
    ? `${isRoving ? "Roving" : "Stationary"} VCode: ${slot.legacyVcode}`
    : `${isRoving ? "Roving" : "Stationary"} Slot (No VCode assigned yet)`;

  const resolvedPositionType = (() => {
    if (!slot) return "Stationary";
    const raw = (slot.employmentType || "").trim();
    const rawLower = raw.toLowerCase();
    const rovingLabel = slot.isRoving ? "Roving" : "Stationary";
    if (!raw || rawLower === "stationary" || rawLower === "roving") {
      return rovingLabel;
    }
    return `${raw.charAt(0).toUpperCase() + raw.slice(1)} • ${rovingLabel}`;
  })();

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidthClass="max-w-2xl"
      title={
        <div className="flex items-center gap-2 flex-wrap">
          <span
            className={`inline-flex items-center rounded border px-2 py-0.5 font-mono text-xs font-semibold ${vcodeColorClass}`}
            title={vcodeTooltip}
          >
            {slot?.legacyVcode || "No VCode"}
          </span>
          {slot && (
            <Badge className="font-mono text-xs text-text-secondary bg-surface-muted border-border-default py-0.5 px-2">
              Slot #{slot.slotOrdinal}
            </Badge>
          )}
          <span className="text-base font-semibold text-text-primary truncate">
            {slot?.position ?? "Slot Inspector"}
          </span>
        </div>
      }
      subtitle={
        slot ? (
          <div className="flex items-center gap-1.5 truncate mt-0.5">
            <Building2 className="h-3.5 w-3.5 shrink-0 text-text-muted" />
            <span className="truncate">
              {[formatStoreName(slot.storeName || slot.storeCode), slot.accountName].filter(Boolean).join(" • ") ||
                "Store Staffing Slot"}
            </span>
          </div>
        ) : undefined
      }
      footer={
        <button
          type="button"
          onClick={onClose}
          className="rounded-lg border border-border-default bg-surface px-4 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition-colors cursor-pointer"
        >
          Close
        </button>
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
                  {resolvedPositionType}
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
                  Unoccupied / Open Required Slot
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
              <span>Capacity Context & Required Rules</span>
            </div>

            <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <div className="text-[10px] font-semibold text-text-muted">
                    Headcount Required (Target)
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

          {/* Slot History Timeline (Capped at 10) */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-1.5 text-xs font-semibold text-text-secondary">
                <Clock className="h-4 w-4 text-text-muted" />
                <span>Slot Audit Trail ({sortedHistory.length})</span>
              </div>
              {sortedHistory.length > 10 && (
                <span className="text-[11px] text-text-muted">
                  Showing {showAllHistory ? sortedHistory.length : 10} of {sortedHistory.length}
                </span>
              )}
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
              <>
                <ol className="relative border-l border-border-default ml-2.5 space-y-4 pt-1">
                  {(showAllHistory ? sortedHistory : sortedHistory.slice(0, 10)).map((event) => {
                    const actionMeta = humanizeActionType(event.actionType);
                    const cleanRemarks = humanizeRemarks(event.remarks, event.actionType, event.reasonCode);
                    const performer = event.performerName && !event.performerName.includes("-")
                      ? event.performerName
                      : "System Automated";

                    return (
                      <li key={event.id} className="ml-4">
                        <span className="absolute -left-1.5 mt-1.5 h-3 w-3 rounded-full border-2 border-surface-base bg-brand-600 shadow-xs" />
                        <div className="rounded-lg border border-border-subtle bg-surface-base p-3 space-y-1.5 shadow-xs">
                          <div className="flex items-center justify-between gap-2 flex-wrap">
                            <div className="flex items-center gap-1.5 flex-wrap">
                              <StatusBadge variant={actionMeta.variant} text={actionMeta.label} />
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
                            <div className="flex items-center gap-1.5 text-[10px] font-mono text-text-muted bg-surface-muted rounded px-2 py-0.5 w-fit">
                              {event.oldValue && <span className="line-through">{humanizeStatus(event.oldValue)}</span>}
                              {event.oldValue && event.newValue && <span>→</span>}
                              {event.newValue && <span className="text-text-primary font-semibold">{humanizeStatus(event.newValue)}</span>}
                            </div>
                          )}

                          {cleanRemarks && (
                            <p className="text-xs text-text-secondary leading-relaxed">
                              {cleanRemarks}
                            </p>
                          )}

                          <div className="text-[10px] text-text-muted flex items-center gap-1 pt-0.5">
                            <ShieldCheck className="h-3 w-3 text-brand-600" />
                            <span>Performed by {performer}</span>
                          </div>
                        </div>
                      </li>
                    );
                  })}
                </ol>
                {sortedHistory.length > 10 && (
                  <div className="pt-2 flex justify-center">
                    <button
                      type="button"
                      onClick={() => setShowAllHistory((prev) => !prev)}
                      className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-muted/60 px-3.5 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition-colors cursor-pointer"
                    >
                      {showAllHistory
                        ? "Show Latest 10 Only"
                        : `See All Activity History (${sortedHistory.length})`}
                    </button>
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      )}
    </Modal>
  );
}
