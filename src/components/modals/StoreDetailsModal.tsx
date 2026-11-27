"use client";

import { useMemo, useState } from "react";
import {
  Building2,
  MapPin,
  Users,
  Clock,
  Layers,
  ChevronRight,
  User,
  RotateCw,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import type { StoreCapacityRow } from "@/components/plantilla/directory/types";
import {
  type PlantillaEmployeeListItem,
  type PlantillaStoreAllocationRow,
  useStorePlantillaSlots,
  useStoreHistory,
} from "@/lib/queries/plantilla";
import {
  formatPersonName,
  formatPosition,
  formatStoreName,
} from "@/lib/utils/displayText";
import { getInitials } from "@/components/plantilla/directory/types";

export interface StoreDetailsModalProps {
  isOpen: boolean;
  onClose: () => void;
  store: StoreCapacityRow | null;
  accountName?: string | null;
  allEmployees?: PlantillaEmployeeListItem[];
  allocations?: PlantillaStoreAllocationRow[];
  onInspectSlot?: (slotId: string) => void;
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
      return { label: "Slot Filled", variant: "success" };
    case "deployed":
    case "employee_deployed":
      return { label: "Personnel Deployed", variant: "success" };
    case "hr_processing":
      return { label: "HR Processing", variant: "warning" };
    case "pipeline":
      return { label: "Candidate Endorsed", variant: "info" };
    case "confirmed onboard":
    case "confirmed_onboard":
      return { label: "Confirmed Onboard", variant: "success" };
    case "created":
    case "slot_created":
      return { label: "Slot Created", variant: "neutral" };
    case "deactivated":
    case "deactivation":
      return { label: "Slot Deactivated", variant: "danger" };
    case "separated":
      return { label: "Personnel Separated", variant: "danger" };
    case "quota_revised":
      return { label: "Quota Updated", variant: "info" };
    case "transfer":
      return { label: "Transferred", variant: "info" };
    default:
      return {
        label: action.replace(/[_-]/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()),
        variant: "neutral",
      };
  }
}

function humanizeRemarks(
  remarks: string | null | undefined,
  actionType?: string,
  reasonCode?: string
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

function humanizeStatus(status: string | null | undefined): string {
  if (!status) return "";
  const s = status.toLowerCase().trim();
  switch (s) {
    case "hr_processing":
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
    default:
      return status.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

function slotStatusBadgeVariant(status: string | null | undefined): BadgeVariant {
  switch ((status ?? "").toLowerCase().trim()) {
    case "occupied":
    case "filled":
      return "success";
    case "pipeline":
      return "info";
    case "hr_processing":
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

export function StoreDetailsModal({
  isOpen,
  onClose,
  store,
  accountName,
  allEmployees = [],
  allocations = [],
  onInspectSlot,
}: StoreDetailsModalProps) {
  const [activeTab, setActiveTab] = useState<"deployed" | "history" | "slots">("deployed");

  const storeKey = (store?.storeBranch || "").toLowerCase().trim();

  // 1. Fetch slots and history
  const {
    data: slots,
    isLoading: isSlotsLoading,
  } = useStorePlantillaSlots(store?.id ?? null);

  const {
    data: historyEvents,
    isLoading: isHistoryLoading,
    refetch: refetchHistory,
  } = useStoreHistory(store?.id, store?.code);

  // 2. Resolve deployed employees for this store
  const deployedPersonnel = useMemo(() => {
    if (!storeKey) return [];

    const seenEmpIds = new Set<string>();
    const list: Array<{
      id: string;
      fullName: string;
      employeeNo: string;
      position: string;
      assignmentType: "Stationary" | "Roving";
      rovingShareText?: string;
      scheduleDays?: string | null;
      scheduleTime?: string | null;
      status: string;
      isOnLeave: boolean;
      initials: string;
    }> = [];

    // First: Match by allocations for precise schedule & roving allocation share
    allocations.forEach((alloc) => {
      if ((alloc.storeName || "").toLowerCase().trim() === storeKey) {
        const emp = allEmployees.find(
          (e) => (alloc.plantillaId && e.id === alloc.plantillaId) ||
                 (alloc.employeeNo && e.employeeNo === alloc.employeeNo)
        );

        const rawStatus = (emp?.plantillaStatus || "active").toLowerCase();
        // Skip inactive or deactivated personnel from active deployed roster
        if (rawStatus === "inactive" || rawStatus === "deactivated" || rawStatus === "separated") {
          return;
        }

        const empId = emp?.id || alloc.plantillaId || alloc.employeeNo || alloc.id;
        if (empId && seenEmpIds.has(empId)) return;
        if (empId) seenEmpIds.add(empId);

        const fullName = emp
          ? formatPersonName(emp.firstName, emp.lastName, null, emp.fullName)
          : alloc.employeeNo || "Unknown Employee";

        const isRoving = Boolean(
          (emp?.assignmentType || "").toLowerCase().includes("roving") ||
          (alloc.filledHc > 0 && alloc.filledHc < 1)
        );

        const isOnLeave = rawStatus === "on leave" || rawStatus === "on_leave";
        const displayStatus = isOnLeave
          ? "On Leave"
          : emp?.plantillaStatus
          ? emp.plantillaStatus.charAt(0).toUpperCase() + emp.plantillaStatus.slice(1).toLowerCase()
          : "Active";

        list.push({
          id: empId,
          fullName,
          employeeNo: emp?.employeeNo || alloc.employeeNo || "—",
          position: formatPosition(emp?.positionTitle || "Staff"),
          assignmentType: isRoving ? "Roving" : "Stationary",
          rovingShareText: isRoving && alloc.filledHc ? `${alloc.filledHc} HC` : undefined,
          scheduleDays: null,
          scheduleTime: null,
          status: displayStatus,
          isOnLeave,
          initials: getInitials(emp?.firstName ?? null, emp?.lastName ?? null),
        });
      }
    });

    // Second: Fallback to allEmployees matching primaryStoreName or rovingStores
    allEmployees.forEach((emp) => {
      if (emp.id && seenEmpIds.has(emp.id)) return;
      if (emp.employeeNo && seenEmpIds.has(emp.employeeNo)) return;

      const rawStatus = (emp.plantillaStatus || "active").toLowerCase();
      // Skip inactive or deactivated personnel from active deployed roster
      if (rawStatus === "inactive" || rawStatus === "deactivated" || rawStatus === "separated") {
        return;
      }

      const isPrimary = (emp.primaryStoreName || "").toLowerCase().trim() === storeKey;
      const isRovingCovered = Array.isArray(emp.assignedStores) &&
        emp.assignedStores.some((s) => (s || "").toLowerCase().trim() === storeKey);

      if (isPrimary || isRovingCovered) {
        const empId = emp.id || emp.employeeNo || `emp-${emp.fullName || "unnamed"}`;
        seenEmpIds.add(empId);

        const isOnLeave = rawStatus === "on leave" || rawStatus === "on_leave";
        const isRoving = Boolean((emp.assignmentType || "").toLowerCase().includes("roving") || isRovingCovered);
        const displayStatus = isOnLeave
          ? "On Leave"
          : emp.plantillaStatus
          ? emp.plantillaStatus.charAt(0).toUpperCase() + emp.plantillaStatus.slice(1).toLowerCase()
          : "Active";

        list.push({
          id: empId,
          fullName: formatPersonName(emp.firstName, emp.lastName, null, emp.fullName),
          employeeNo: emp.employeeNo || "—",
          position: formatPosition(emp.positionTitle || "Staff"),
          assignmentType: isRoving ? "Roving" : "Stationary",
          rovingShareText: isRoving && emp.coveredStoresCount > 1 ? `${(1 / emp.coveredStoresCount).toFixed(2)} HC (${emp.coveredStoresCount} stores)` : undefined,
          scheduleDays: null,
          scheduleTime: null,
          status: displayStatus,
          isOnLeave,
          initials: getInitials(emp.firstName, emp.lastName),
        });
      }
    });

    return list;
  }, [allEmployees, allocations, storeKey]);

  if (!isOpen || !store) return null;

  const isRovingStore = store.deploymentTypes.includes("Roving");
  const isStationaryStore = store.deploymentTypes.includes("Stationary");
  const isMixedStore = isRovingStore && isStationaryStore;

  const locationLabel = [store.city, store.province].filter(Boolean).join(", ");

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      maxWidthClass="max-w-3xl"
      title={
        <span className="flex items-center gap-2.5">
          <Building2 className="h-5 w-5 text-brand-600 shrink-0" />
          <span className="truncate">{formatStoreName(store.storeBranch)}</span>
        </span>
      }
      subtitle={
        <div className="flex items-center gap-2 flex-wrap text-xs text-text-secondary mt-0.5">
          {locationLabel && (
            <span className="inline-flex items-center gap-1">
              <MapPin className="h-3 w-3 text-text-muted" />
              <span>{locationLabel}</span>
            </span>
          )}
          {accountName && (
            <span className="text-text-muted">• {accountName}</span>
          )}
          {/* VCode Badge in dedicated color */}
          {store.code ? (
            <span
              className={`font-mono text-[10px] font-semibold px-2 py-0.5 rounded border ${
                isMixedStore
                  ? "border-indigo-300 bg-gradient-to-r from-blue-50 to-purple-50 text-indigo-800 dark:border-indigo-700 dark:from-blue-950/60 dark:to-purple-950/60 dark:text-indigo-200"
                  : isRovingStore
                  ? "border-purple-300 bg-purple-50 text-purple-700 dark:border-purple-800 dark:bg-purple-950/60 dark:text-purple-300"
                  : "border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-800 dark:bg-blue-950/60 dark:text-blue-300"
              }`}
              title={
                isMixedStore
                  ? "Mixed Stationary & Roving Store VCode"
                  : isRovingStore
                  ? "Roving Store VCode"
                  : "Stationary Store VCode"
              }
            >
              {store.code}
            </span>
          ) : (
            <span
              className={`font-mono text-[10px] font-medium px-2 py-0.5 rounded border border-dashed ${
                isMixedStore
                  ? "border-indigo-300 bg-indigo-50/50 text-indigo-600 dark:border-indigo-800/60 dark:bg-indigo-950/30 dark:text-indigo-400"
                  : isRovingStore
                  ? "border-purple-300 bg-purple-50/50 text-purple-600 dark:border-purple-800/60 dark:bg-purple-950/30 dark:text-purple-400"
                  : "border-blue-300 bg-blue-50/50 text-blue-600 dark:border-blue-800/60 dark:bg-blue-950/30 dark:text-blue-400"
              }`}
              title="No VCode assigned to this store yet"
            >
              No VCode
            </span>
          )}
        </div>
      }
    >
      <div className="space-y-4 pt-1">
        {/* Metric Summary Bar */}
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-2 text-center">
          <div className="rounded-lg border border-border-default bg-surface-muted p-2.5">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">Required</div>
            <div className="text-lg font-bold font-mono text-text-primary mt-0.5">{store.plantillaRequired}</div>
          </div>
          <div className="rounded-lg border border-border-default bg-surface-muted p-2.5">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-emerald-600 dark:text-emerald-400">Actual</div>
            <div className="text-lg font-bold font-mono text-emerald-600 dark:text-emerald-400 mt-0.5">{store.activeDeployed}</div>
          </div>
          <div className="rounded-lg border border-border-default bg-surface-muted p-2.5">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-blue-600 dark:text-blue-400">Pipeline</div>
            <div className={`text-lg font-bold font-mono mt-0.5 ${(store.pipelineCount ?? 0) > 0 ? "text-blue-600 dark:text-blue-400" : "text-text-muted"}`}>
              {store.pipelineCount ?? 0}
            </div>
          </div>
          <div className="rounded-lg border border-border-default bg-surface-muted p-2.5">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-amber-600 dark:text-amber-400">On-Leave</div>
            <div className="text-lg font-bold font-mono text-amber-600 dark:text-amber-400 mt-0.5">{store.onLeave}</div>
          </div>
          <div className="rounded-lg border border-border-default bg-surface-muted p-2.5">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">Vacancy</div>
            <div className={`text-lg font-bold font-mono mt-0.5 ${store.openVacancy > 0 ? "text-red-600 dark:text-red-400" : "text-text-muted"}`}>
              {store.openVacancy}
            </div>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="flex border-b border-border-default gap-2 text-xs font-semibold">
          <button
            type="button"
            onClick={() => setActiveTab("deployed")}
            className={`pb-2 px-3 border-b-2 transition-colors flex items-center gap-1.5 ${
              activeTab === "deployed"
                ? "border-brand-600 text-brand-600 dark:text-brand-400"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            <Users className="h-3.5 w-3.5" />
            <span>Deployed Personnel ({deployedPersonnel.length})</span>
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("history")}
            className={`pb-2 px-3 border-b-2 transition-colors flex items-center gap-1.5 ${
              activeTab === "history"
                ? "border-brand-600 text-brand-600 dark:text-brand-400"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            <Clock className="h-3.5 w-3.5" />
            <span>Store History ({historyEvents?.length ?? 0})</span>
          </button>
          <button
            type="button"
            onClick={() => setActiveTab("slots")}
            className={`pb-2 px-3 border-b-2 transition-colors flex items-center gap-1.5 ${
              activeTab === "slots"
                ? "border-brand-600 text-brand-600 dark:text-brand-400"
                : "border-transparent text-text-muted hover:text-text-primary"
            }`}
          >
            <Layers className="h-3.5 w-3.5" />
            <span>
              Plantilla Slots (
              {(slots ?? []).filter(
                (s) =>
                  s.slotStatus !== "closed" &&
                  s.slotStatus !== "hc_reduced" &&
                  !s.isRoving
              ).length}
              )
            </span>
          </button>
        </div>

        {/* Tab 1: Deployed Personnel */}
        {activeTab === "deployed" && (
          <div className="space-y-2.5 max-h-[380px] overflow-y-auto pr-1">
            {deployedPersonnel.length === 0 ? (
              <div className="rounded-lg border border-border-default bg-surface-muted p-8 text-center">
                <Users className="mx-auto h-8 w-8 text-text-muted" />
                <h4 className="mt-2 text-xs font-semibold text-text-primary">No Active Deployments</h4>
                <p className="mt-1 text-[11px] text-text-muted">
                  There are currently no employees deployed to {formatStoreName(store.storeBranch)}.
                </p>
              </div>
            ) : (
              deployedPersonnel.map((person) => (
                <div
                  key={person.id}
                  className="flex items-center justify-between p-3 rounded-lg border border-border-default bg-surface-base hover:bg-surface-muted transition-colors"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="h-8 w-8 rounded-full bg-surface-muted border border-border-default text-brand-primary font-bold text-xs flex items-center justify-center shrink-0 shadow-2xs">
                      {person.initials}
                    </div>
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-semibold text-xs text-text-primary truncate">{person.fullName}</span>
                        <span className="font-mono text-[11px] text-text-muted">({person.employeeNo})</span>
                      </div>
                      <div className="flex items-center gap-2 text-[11px] text-text-muted mt-0.5 flex-wrap">
                        <span>{person.position}</span>
                        {person.scheduleDays && (
                          <span className="text-text-secondary font-mono">• {person.scheduleDays}</span>
                        )}
                        {person.scheduleTime && (
                          <span className="text-text-secondary font-mono">• {person.scheduleTime}</span>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 shrink-0">
                    <span
                      className={`text-[10px] font-semibold px-2 py-0.5 rounded border ${
                        person.assignmentType === "Roving"
                          ? "border-purple-300 bg-purple-50 text-purple-700 dark:border-purple-800 dark:bg-purple-950/60 dark:text-purple-300"
                          : "border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-800 dark:bg-blue-950/60 dark:text-blue-300"
                      }`}
                    >
                      {person.assignmentType}
                      {person.rovingShareText ? ` • ${person.rovingShareText}` : ""}
                    </span>
                    <StatusBadge
                      variant={person.isOnLeave ? "warning" : "success"}
                      text={person.status}
                    />
                  </div>
                </div>
              ))
            )}
          </div>
        )}

        {/* Tab 2: Store History */}
        {activeTab === "history" && (
          <div className="space-y-3 max-h-[380px] overflow-y-auto pr-1">
            <div className="flex items-center justify-between text-xs text-text-muted pb-1">
              <span>Audit and activity history for this store</span>
              <button
                type="button"
                onClick={() => refetchHistory()}
                className="inline-flex items-center gap-1 text-[11px] hover:text-text-primary transition-colors"
              >
                <RotateCw className="h-3 w-3" />
                Refresh
              </button>
            </div>

            {isHistoryLoading ? (
              <div className="space-y-2 animate-pulse">
                <div className="h-14 rounded-md bg-surface-muted" />
                <div className="h-14 rounded-md bg-surface-muted" />
              </div>
            ) : (historyEvents ?? []).length === 0 ? (
              <div className="rounded-lg border border-border-default bg-surface-muted p-8 text-center">
                <Clock className="mx-auto h-8 w-8 text-text-muted" />
                <h4 className="mt-2 text-xs font-semibold text-text-primary">No Recorded Events</h4>
                <p className="mt-1 text-[11px] text-text-muted">
                  No automated history or slot modifications have been logged yet for this branch.
                </p>
              </div>
            ) : (
              <div className="relative pl-6 space-y-3 before:absolute before:left-2.5 before:top-2 before:bottom-2 before:w-0.5 before:bg-border-default">
                {(historyEvents ?? []).map((ev) => {
                  const actionMeta = humanizeActionType(ev.actionType);
                  const cleanRemarks = humanizeRemarks(ev.remarks, ev.actionType);
                  const performer = ev.performerName && !ev.performerName.includes("-")
                    ? ev.performerName
                    : "System Automated";

                  return (
                    <div key={ev.id} className="relative group">
                      <div className="absolute -left-6 top-1.5 h-2.5 w-2.5 rounded-full border-2 border-brand-500 bg-surface-base" />
                      <div className="rounded-md border border-border-default bg-surface-base p-2.5 text-xs shadow-2xs space-y-1.5">
                        <div className="flex items-center justify-between gap-2 flex-wrap">
                          <StatusBadge variant={actionMeta.variant} text={actionMeta.label} />
                          <span className="font-mono text-[10px] text-text-muted">{formatTimelineDate(ev.createdAt)}</span>
                        </div>
                        {cleanRemarks && (
                          <p className="text-[11px] text-text-secondary leading-relaxed">{cleanRemarks}</p>
                        )}
                        {(ev.oldValue || ev.newValue) && (
                          <div className="flex items-center gap-1.5 text-[10px] font-mono text-text-muted bg-surface-muted rounded px-2 py-0.5 w-fit">
                            {ev.oldValue && <span className="line-through">{humanizeStatus(ev.oldValue)}</span>}
                            {ev.oldValue && ev.newValue && <span>→</span>}
                            {ev.newValue && <span className="text-text-primary font-semibold">{humanizeStatus(ev.newValue)}</span>}
                          </div>
                        )}
                        <div className="text-[10px] text-text-muted pt-0.5">
                          Logged by: <span className="font-medium text-text-secondary">{performer}</span>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* Tab 3: Plantilla Slots */}
        {activeTab === "slots" && (
          <div className="space-y-2.5 max-h-[380px] overflow-y-auto pr-1">
            {isSlotsLoading ? (
              <div className="space-y-2 animate-pulse">
                <div className="h-16 rounded-md bg-surface-muted" />
                <div className="h-16 rounded-md bg-surface-muted" />
              </div>
            ) : (slots ?? []).filter(
                (s) =>
                  s.slotStatus !== "closed" &&
                  s.slotStatus !== "hc_reduced" &&
                  !s.isRoving
              ).length === 0 ? (
              <div className="rounded-lg border border-border-default bg-surface-muted p-8 text-center">
                <Layers className="mx-auto h-8 w-8 text-text-muted" />
                <h4 className="mt-2 text-xs font-semibold text-text-primary">No Active Slots Registered</h4>
                <p className="mt-1 text-[11px] text-text-muted">
                  No active ADR-001 plantilla slot records are currently open, occupied, or in pipeline for this store.
                </p>
              </div>
            ) : (
              (slots ?? [])
                .filter(
                  (s) =>
                    s.slotStatus !== "closed" &&
                    s.slotStatus !== "hc_reduced" &&
                    !s.isRoving &&
                    !(s.legacyVcode ?? "").startsWith("COM-")
                )
                .map((slot) => (
                <div
                  key={slot.id}
                  className="rounded-lg border border-border-default bg-surface-base p-3 space-y-2 hover:border-border-subtle transition-colors"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <span className="font-mono text-[10px] font-semibold bg-surface-muted border border-border-default rounded px-1.5 py-0.5">
                          {slot.legacyVcode || "NO VCODE"}
                        </span>
                        <span className="font-mono text-[11px] text-text-muted">#{slot.slotOrdinal}</span>
                        <span className="font-semibold text-xs text-text-primary">{slot.position}</span>
                      </div>
                      <div className="mt-1 text-xs text-text-secondary flex items-center gap-1.5">
                        <User className="h-3 w-3 text-text-muted" />
                        {slot.slotStatus === "occupied" && slot.occupant ? (
                          <span>
                            {slot.occupant.employeeName}{" "}
                            <span className="font-mono text-[10px] text-text-muted">({slot.occupant.employeeNo})</span>
                          </span>
                        ) : slot.candidate ? (
                          <span>{slot.candidate.name} (Candidate)</span>
                        ) : (
                          <span className="italic text-text-muted">Unoccupied Position</span>
                        )}
                      </div>
                    </div>

                    <div className="flex flex-col items-end gap-1 shrink-0">
                      <StatusBadge
                        variant={slotStatusBadgeVariant(slot.slotStatus)}
                        text={slot.slotStatus}
                      />
                      {onInspectSlot && (
                        <button
                          type="button"
                          onClick={() => {
                            onClose();
                            onInspectSlot(slot.id);
                          }}
                          className="inline-flex items-center gap-0.5 text-[11px] font-medium text-brand-600 hover:text-brand-700 transition-colors"
                        >
                          <span>Inspect</span>
                          <ChevronRight className="h-3 w-3" />
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </div>
    </Modal>
  );
}
