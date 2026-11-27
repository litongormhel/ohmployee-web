"use client";

import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  AlertTriangle,
  ArrowLeftRight,
  ArrowRightLeft,
  Building,
  Calendar,
  CheckCircle2,
  Clock,
  Compass,
  Loader2,
  MapPin,
  Search,
  Store,
  Users,
  X,
} from "lucide-react";
import {
  fetchDestinationStores,
  fetchSwapCandidates,
  useTransferPersonnel,
  useSwapPersonnel,
  deriveIslandGroup,
  type DestinationStoreItem,
  type SwapCandidateItem,
  type TransferReasonType,
} from "@/lib/queries/plantilla";
import { Modal } from "@/components/shared/Modal";
import type { ActionModalProps } from "@/types/modal";

export interface TransferPersonnelModalProps extends ActionModalProps {
  plantillaId: string;
  employeeName: string;
  employeeNo: string;
  positionTitle?: string | null;
  accountId?: string | null;
  accountName?: string | null;
  currentStoreId?: string | null;
  currentStoreName?: string | null;
  currentVcode?: string | null;
  currentProvince?: string | null;
  currentIslandGroup?: string | null;
  deploymentType?: string | null;
  currentScheduleDays?: string | null;
  currentScheduleTime?: string | null;
  currentDayoff?: string | null;
}

type MovementMode = "transfer" | "swap";

const TRANSFER_REASONS: { value: TransferReasonType; label: string; description: string }[] = [
  { value: "Store Initiated", label: "Store Initiated", description: "Operational transfer initiated by management / store leadership" },
  { value: "Employee Requested", label: "Employee Requested", description: "Reassignment requested by the employee for personal / relocation reasons" },
  { value: "Operational Need", label: "Operational Need", description: "Critical staffing balance or capacity realignment" },
  { value: "Annual Inventory", label: "Annual Inventory", description: "Temporary or scheduled inventory rotation" },
  { value: "Store Closed Temporarily", label: "Store Closed Temporarily", description: "Store renovation, closure, or maintenance relocation" },
];

function formatScheduleSummary(
  days?: string | null,
  time?: string | null,
  dayoff?: string | null,
): string {
  const parts = [
    days?.trim() || null,
    time?.trim() || null,
    dayoff?.trim() ? `Off: ${dayoff.trim()}` : null,
  ].filter(Boolean);
  return parts.length > 0 ? parts.join(" • ") : "No schedule set";
}

export function TransferPersonnelModal({
  isOpen,
  onClose,
  plantillaId,
  employeeName,
  employeeNo,
  positionTitle,
  accountId,
  accountName,
  currentStoreId,
  currentStoreName,
  currentVcode,
  currentProvince,
  currentIslandGroup,
  deploymentType,
  currentScheduleDays,
  currentScheduleTime,
  currentDayoff,
  onSuccess,
}: TransferPersonnelModalProps) {
  const [mode, setMode] = useState<MovementMode>("transfer");
  const [selectedStore, setSelectedStore] = useState<DestinationStoreItem | null>(null);
  const [selectedPartner, setSelectedPartner] = useState<SwapCandidateItem | null>(null);
  const [reason, setReason] = useState<TransferReasonType>("Operational Need");
  const [customRemarks, setCustomRemarks] = useState<string>("");
  const [effectiveDate, setEffectiveDate] = useState<string>(
    () => new Date().toISOString().substring(0, 10),
  );
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const isRoving = (deploymentType ?? "").trim().toLowerCase() === "roving";

  const transferMutation = useTransferPersonnel();
  const swapMutation = useSwapPersonnel();
  const isSubmitting = transferMutation.isPending || swapMutation.isPending;

  const isDirty =
    selectedStore !== null ||
    selectedPartner !== null ||
    customRemarks.trim() !== "" ||
    reason !== "Operational Need";

  // Fetch ONLY eligible stationary stores with available open slots (Avail > 0)
  const storesQuery = useQuery({
    queryKey: ["plantilla", "transfer-eligible-stores", accountId, currentStoreId],
    queryFn: () => fetchDestinationStores(accountId ?? undefined, currentStoreId ?? undefined),
    enabled: isOpen && !isRoving && mode === "transfer",
    staleTime: 30_000,
  });

  // Fetch eligible active stationary employees in the same account for atomic Swap
  const swapCandidatesQuery = useQuery({
    queryKey: ["plantilla", "swap-eligible-employees", plantillaId],
    queryFn: () => fetchSwapCandidates(plantillaId),
    enabled: isOpen && !isRoving && mode === "swap",
    staleTime: 30_000,
  });

  const eligibleStores = useMemo(() => storesQuery.data ?? [], [storesQuery.data]);
  const eligiblePartners = useMemo(() => swapCandidatesQuery.data ?? [], [swapCandidatesQuery.data]);

  const filteredStores = useMemo(() => {
    if (!searchQuery.trim()) return eligibleStores;
    const q = searchQuery.toLowerCase().trim();
    return eligibleStores.filter(
      (s) =>
        s.storeName.toLowerCase().includes(q) ||
        (s.vcode && s.vcode.toLowerCase().includes(q)) ||
        (s.areaCity && s.areaCity.toLowerCase().includes(q)) ||
        (s.province && s.province.toLowerCase().includes(q)) ||
        (s.groupName && s.groupName.toLowerCase().includes(q)),
    );
  }, [eligibleStores, searchQuery]);

  const filteredPartners = useMemo(() => {
    if (!searchQuery.trim()) return eligiblePartners;
    const q = searchQuery.toLowerCase().trim();
    return eligiblePartners.filter(
      (p) =>
        p.employeeName.toLowerCase().includes(q) ||
        p.employeeNo.toLowerCase().includes(q) ||
        p.storeName.toLowerCase().includes(q) ||
        (p.vcode && p.vcode.toLowerCase().includes(q)) ||
        (p.position && p.position.toLowerCase().includes(q)),
    );
  }, [eligiblePartners, searchQuery]);

  // Derive source vs target island groups (Transfer mode)
  const sourceIslandGroup = useMemo(() => {
    if (currentIslandGroup) return currentIslandGroup;
    return deriveIslandGroup(currentProvince);
  }, [currentIslandGroup, currentProvince]);

  const destinationIslandGroup = useMemo(() => {
    if (mode === "transfer" && selectedStore) {
      return selectedStore.islandGroup ?? deriveIslandGroup(selectedStore.province ?? selectedStore.areaProvince);
    }
    if (mode === "swap" && selectedPartner) {
      return deriveIslandGroup(selectedPartner.province);
    }
    return null;
  }, [mode, selectedStore, selectedPartner]);

  const isCrossIslandTransfer = Boolean(
    sourceIslandGroup &&
      destinationIslandGroup &&
      sourceIslandGroup !== destinationIslandGroup,
  );

  const handleModeSwitch = (nextMode: MovementMode) => {
    if (nextMode === mode) return;
    setMode(nextMode);
    setSearchQuery("");
    setErrorMessage(null);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (isRoving) {
      setErrorMessage("Roving employees cannot be transferred or swapped individually. Use Coverage Group Management.");
      return;
    }

    if (!effectiveDate) {
      setErrorMessage("Please specify an effective date.");
      return;
    }

    const fullRemarks = customRemarks.trim()
      ? `${reason}: ${customRemarks.trim()}`
      : reason;

    if (mode === "transfer") {
      if (!selectedStore) {
        setErrorMessage("Please select a target destination store with an available open slot.");
        return;
      }

      transferMutation.mutate(
        {
          plantillaId,
          targetStoreId: selectedStore.id,
          reason: fullRemarks,
          effectiveDate,
        },
        {
          onSuccess: () => {
            onSuccess?.();
            onClose();
          },
          onError: (err) => {
            setErrorMessage(err.message || "Failed to execute personnel store transfer.");
          },
        },
      );
      return;
    }

    // Atomic Swap Mode
    if (!selectedPartner) {
      setErrorMessage("Please select an active stationary employee to swap stores with.");
      return;
    }

    swapMutation.mutate(
      {
        plantillaIdA: plantillaId,
        plantillaIdB: selectedPartner.plantillaId,
        reason: fullRemarks,
        effectiveDate,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to execute atomic employee swap.");
        },
      },
    );
  };

  const canSubmit =
    !isRoving &&
    !isSubmitting &&
    (mode === "transfer" ? selectedStore !== null : selectedPartner !== null);

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={mode === "transfer" ? "Transfer Personnel Store Assignment" : "Swap Personnel Store Assignments"}
      subtitle={
        <span className="font-mono text-text-secondary text-xs">
          {employeeNo} • {employeeName}
        </span>
      }
      icon={mode === "transfer" ? ArrowRightLeft : ArrowLeftRight}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
      maxWidthClass="max-w-2xl"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        {/* Mode Switcher: Transfer to Vacant Store vs Swap with Employee */}
        <div className="grid grid-cols-2 gap-1.5 rounded-lg border border-border-default bg-surface-muted p-1">
          <button
            type="button"
            onClick={() => handleModeSwitch("transfer")}
            disabled={isSubmitting}
            className={`flex items-center justify-center gap-1.5 rounded-md px-3 py-2 text-xs font-semibold transition-all cursor-pointer ${
              mode === "transfer"
                ? "bg-surface text-brand-primary shadow-2xs border border-border-default"
                : "text-text-secondary hover:text-text-primary"
            }`}
          >
            <ArrowRightLeft className="h-3.5 w-3.5" />
            <span>Transfer to Vacant Store</span>
          </button>
          <button
            type="button"
            onClick={() => handleModeSwitch("swap")}
            disabled={isSubmitting}
            className={`flex items-center justify-center gap-1.5 rounded-md px-3 py-2 text-xs font-semibold transition-all cursor-pointer ${
              mode === "swap"
                ? "bg-surface text-brand-primary shadow-2xs border border-border-default"
                : "text-text-secondary hover:text-text-primary"
            }`}
          >
            <Users className="h-3.5 w-3.5" />
            <span>Swap with Employee</span>
          </button>
        </div>

        {isRoving && (
          <div className="rounded-lg border border-pct-warn-border bg-pct-warn-bg p-3.5 flex items-start gap-2.5 text-xs text-pct-warn-text">
            <AlertTriangle className="h-4 w-4 shrink-0 text-pct-warn-text mt-0.5" />
            <div className="flex-1">
              <p className="font-semibold">Stationary Personnel Only</p>
              <p className="mt-0.5">
                Roving employees belong to a Coverage Group (CGCODE) and cannot use individual store transfer or swap.
                Manage roving store routes via <strong>Coverage Group Management</strong>.
              </p>
            </div>
          </div>
        )}

        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg p-3.5 flex items-start gap-2.5 text-xs text-danger-text">
            <AlertTriangle className="h-4 w-4 shrink-0 text-danger-text mt-0.5" />
            <div className="flex-1 font-medium">{errorMessage}</div>
          </div>
        )}

        {/* Side-by-Side Comparison Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3.5">
          {/* Source Store / Employee A */}
          <div className="rounded-lg border border-border-default bg-surface-muted p-3.5 space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold text-text-secondary flex items-center gap-1.5">
                <Store className="h-3.5 w-3.5 text-text-muted" />
                {mode === "transfer" ? "Source Store (Current)" : "Employee A (Current)"}
              </span>
              <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-surface text-text-secondary border border-border-default">
                Origin
              </span>
            </div>
            <div>
              {mode === "swap" && (
                <p className="text-xs font-semibold text-brand-primary mb-0.5">
                  {employeeName} <span className="font-mono text-[10px] text-text-secondary">({employeeNo})</span>
                </p>
              )}
              <div className="flex items-center gap-1.5 flex-wrap">
                <p className="text-sm font-semibold text-text-primary">
                  {currentStoreName ?? "Current Store"}
                </p>
                {currentVcode && (
                  <span className="font-mono text-[10px] bg-surface border border-border-default text-text-secondary px-1 py-0.2 rounded">
                    {currentVcode}
                  </span>
                )}
              </div>
              <p className="text-xs text-text-secondary mt-0.5">
                {[accountName, positionTitle].filter(Boolean).join(" • ")}
              </p>
            </div>
            {mode === "swap" && (
              <div className="pt-1.5 border-t border-border-subtle flex items-center gap-1.5 text-[11px] text-text-secondary">
                <Clock className="h-3 w-3 text-text-muted shrink-0" />
                <span className="truncate">
                  {formatScheduleSummary(currentScheduleDays, currentScheduleTime, currentDayoff)}
                </span>
              </div>
            )}
            <div className="pt-1.5 border-t border-border-subtle flex items-center justify-between text-[11px] text-text-secondary">
              <span className="flex items-center gap-1">
                <MapPin className="h-3 w-3 text-text-muted" />
                {currentProvince ?? "Province Unspecified"}
              </span>
              {sourceIslandGroup && (
                <span className="font-semibold text-text-primary bg-surface border border-border-default rounded px-1.5 py-0.5">
                  {sourceIslandGroup}
                </span>
              )}
            </div>
          </div>

          {/* Destination Store (Transfer) OR Partner Employee B (Swap) */}
          {mode === "transfer" ? (
            <div
              className={`rounded-lg border p-3.5 space-y-2 transition-colors ${
                selectedStore
                  ? "border-brand-primary bg-surface-selected"
                  : "border-dashed border-border-default bg-surface-muted/40"
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-bold text-brand-primary flex items-center gap-1.5">
                  <Store className="h-3.5 w-3.5 text-brand-primary" />
                  Destination Store (Target)
                </span>
                {selectedStore ? (
                  <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
                    {selectedStore.availSlotsCount} Open {selectedStore.availSlotsCount === 1 ? "Slot" : "Slots"}
                  </span>
                ) : (
                  <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-surface text-text-muted border border-border-default">
                    Pending Pick
                  </span>
                )}
              </div>

              {selectedStore ? (
                <>
                  <div>
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <p className="text-sm font-semibold text-text-primary">
                        {selectedStore.storeName}
                      </p>
                      {selectedStore.vcode && (
                        <span className="font-mono text-[10px] bg-surface border border-border-default text-brand-primary px-1 py-0.2 rounded">
                          {selectedStore.vcode}
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-text-secondary mt-0.5">
                      {[selectedStore.accountName ?? accountName, selectedStore.groupName].filter(Boolean).join(" • ")}
                    </p>
                  </div>
                  <div className="pt-1.5 border-t border-border-subtle flex items-center justify-between text-[11px] text-text-secondary">
                    <span className="flex items-center gap-1 truncate max-w-[170px]">
                      <MapPin className="h-3 w-3 text-text-muted shrink-0" />
                      <span className="truncate">{selectedStore.areaCity ?? selectedStore.province ?? "Location"}</span>
                    </span>
                    {destinationIslandGroup && (
                      <span className="font-semibold text-brand-primary bg-surface border border-border-default rounded px-1.5 py-0.5 shrink-0">
                        {destinationIslandGroup}
                      </span>
                    )}
                  </div>
                </>
              ) : (
                <div className="py-2 text-center text-xs text-text-muted">
                  Select a store with available open slots below
                </div>
              )}
            </div>
          ) : (
            <div
              className={`rounded-lg border p-3.5 space-y-2 transition-colors ${
                selectedPartner
                  ? "border-brand-primary bg-surface-selected"
                  : "border-dashed border-border-default bg-surface-muted/40"
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-bold text-brand-primary flex items-center gap-1.5">
                  <Users className="h-3.5 w-3.5 text-brand-primary" />
                  Employee B (Swap Partner)
                </span>
                {selectedPartner ? (
                  <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-surface-muted text-brand-primary border border-border-default">
                    Selected
                  </span>
                ) : (
                  <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-surface text-text-muted border border-border-default">
                    Pending Pick
                  </span>
                )}
              </div>

              {selectedPartner ? (
                <>
                  <div>
                    <p className="text-xs font-semibold text-brand-primary mb-0.5">
                      {selectedPartner.employeeName}{" "}
                      <span className="font-mono text-[10px] text-text-secondary">({selectedPartner.employeeNo})</span>
                    </p>
                    <div className="flex items-center gap-1.5 flex-wrap">
                      <p className="text-sm font-semibold text-text-primary">
                        {selectedPartner.storeName}
                      </p>
                      {selectedPartner.vcode && (
                        <span className="font-mono text-[10px] bg-surface border border-border-default text-brand-primary px-1 py-0.2 rounded">
                          {selectedPartner.vcode}
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-text-secondary mt-0.5">
                      {[accountName, selectedPartner.position].filter(Boolean).join(" • ")}
                    </p>
                  </div>
                  <div className="pt-1.5 border-t border-border-subtle flex items-center gap-1.5 text-[11px] text-text-secondary">
                    <Clock className="h-3 w-3 text-text-muted shrink-0" />
                    <span className="truncate">
                      {formatScheduleSummary(
                        selectedPartner.scheduleDays,
                        selectedPartner.scheduleTime,
                        selectedPartner.dayoff,
                      )}
                    </span>
                  </div>
                  <div className="pt-1.5 border-t border-border-subtle flex items-center justify-between text-[11px] text-text-secondary">
                    <span className="flex items-center gap-1 truncate max-w-[170px]">
                      <MapPin className="h-3 w-3 text-text-muted shrink-0" />
                      <span className="truncate">{selectedPartner.areaCity ?? selectedPartner.province ?? "Location"}</span>
                    </span>
                    {destinationIslandGroup && (
                      <span className="font-semibold text-brand-primary bg-surface border border-border-default rounded px-1.5 py-0.5 shrink-0">
                        {destinationIslandGroup}
                      </span>
                    )}
                  </div>
                </>
              ) : (
                <div className="py-2 text-center text-xs text-text-muted">
                  Select an active stationary employee below to swap stores
                </div>
              )}
            </div>
          )}
        </div>

        {/* Cross-Island Group Warning Banner */}
        {isCrossIslandTransfer && (
          <div className="rounded-lg border border-pct-warn-border bg-pct-warn-bg p-3.5 flex items-start gap-2.5 text-xs text-pct-warn-text">
            <Compass className="h-4 w-4 shrink-0 text-pct-warn-text mt-0.5" />
            <div className="space-y-1">
              <p className="font-semibold text-pct-warn-text">
                Cross-Island Group Movement Detected
              </p>
              <p className="leading-relaxed text-pct-warn-text">
                Moving personnel across island groups (<strong>{sourceIslandGroup}</strong> &rarr;{" "}
                <strong>{destinationIslandGroup}</strong>) requires inter-regional logistics coordination.
                Ensure regional operations heads are notified.
              </p>
            </div>
          </div>
        )}

        {/* Picker List (Stores with Open Slots OR Active Swap Partners) */}
        {!isRoving && (
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <label htmlFor="movement-search-input" className="block text-xs font-semibold text-text-secondary">
                {mode === "transfer" ? (
                  <>
                    Search &amp; Select Destination Store <span className="text-danger-text">*</span>
                  </>
                ) : (
                  <>
                    Search &amp; Select Employee to Swap With <span className="text-danger-text">*</span>
                  </>
                )}
              </label>
              <span className="text-[11px] text-text-muted">
                {mode === "transfer"
                  ? "Showing stores with available open slots only"
                  : "Active stationary employees in this account"}
              </span>
            </div>

            <div className="relative">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-text-muted pointer-events-none" />
              <input
                id="movement-search-input"
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder={
                  mode === "transfer"
                    ? "Search store name, vcode, city, province, or CENCOM group…"
                    : "Search employee name, ID, store name, vcode, or position…"
                }
                className="w-full rounded-lg border border-border-default bg-surface pl-9 pr-8 py-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden"
              />
              {searchQuery && (
                <button
                  type="button"
                  onClick={() => setSearchQuery("")}
                  className="absolute right-2.5 top-2 text-text-muted hover:text-text-primary cursor-pointer"
                >
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>

            <div className="rounded-lg border border-border-default bg-surface overflow-hidden">
              {mode === "transfer" ? (
                storesQuery.isLoading ? (
                  <div className="py-8 text-center text-xs text-text-secondary flex items-center justify-center gap-2">
                    <Loader2 className="h-4 w-4 animate-spin text-brand-primary" />
                    Loading stores with available open slots…
                  </div>
                ) : storesQuery.isError ? (
                  <div className="py-6 text-center text-xs text-danger-text px-4">
                    Failed to load eligible destination stores. Please close and retry.
                  </div>
                ) : filteredStores.length === 0 ? (
                  <div className="py-8 text-center text-xs text-text-secondary px-4 space-y-2">
                    <p>
                      {eligibleStores.length === 0
                        ? "No stationary stores with available open slots found in this account."
                        : "No open-slot stores match your search query."}
                    </p>
                    {eligibleStores.length === 0 && (
                      <button
                        type="button"
                        onClick={() => handleModeSwitch("swap")}
                        className="inline-flex items-center gap-1.5 text-brand-primary font-semibold hover:underline cursor-pointer"
                      >
                        <Users className="h-3.5 w-3.5" />
                        Switch to Swap with Employee instead
                      </button>
                    )}
                  </div>
                ) : (
                  <ul className="divide-y divide-border-subtle max-h-48 overflow-y-auto">
                    {filteredStores.map((store) => {
                      const isSelected = selectedStore?.id === store.id;
                      const ig = store.islandGroup ?? deriveIslandGroup(store.province ?? store.areaProvince);
                      const isCross = sourceIslandGroup && ig && sourceIslandGroup !== ig;

                      return (
                        <li key={store.id}>
                          <button
                            type="button"
                            onClick={() => setSelectedStore(store)}
                            className={`w-full text-left px-3.5 py-2.5 flex items-center justify-between text-xs transition-colors cursor-pointer ${
                              isSelected
                                ? "bg-surface-muted text-brand-primary font-semibold"
                                : "hover:bg-surface-hover text-text-primary"
                            }`}
                          >
                            <div className="min-w-0 pr-3">
                              <div className="flex items-center gap-2 flex-wrap">
                                <span className="font-semibold truncate">{store.storeName}</span>
                                {store.vcode && (
                                  <span className="font-mono text-[10px] text-text-secondary bg-surface-muted border border-border-default px-1 py-0.2 rounded shrink-0">
                                    {store.vcode}
                                  </span>
                                )}
                                <span className="text-[10px] font-semibold text-emerald-700 dark:text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 px-1.5 py-0.2 rounded shrink-0">
                                  {store.availSlotsCount} Open ({store.occupiedSlotsCount}/{store.totalSlotsCount})
                                </span>
                                {isCross && (
                                  <span className="text-[10px] font-semibold text-pct-warn-text bg-pct-warn-bg border border-pct-warn-border px-1.5 py-0.2 rounded shrink-0">
                                    Cross-Island
                                  </span>
                                )}
                              </div>
                              <div className="text-[11px] text-text-secondary mt-0.5 flex items-center gap-1.5 truncate">
                                <span>{store.groupName ?? "CENCOM"}</span>
                                <span>&bull;</span>
                                <span>{store.areaCity ?? store.province ?? "Metro"}</span>
                                {ig && (
                                  <>
                                    <span>&bull;</span>
                                    <span className="text-text-primary font-medium">{ig}</span>
                                  </>
                                )}
                              </div>
                            </div>
                            {isSelected && (
                              <CheckCircle2 className="h-4 w-4 text-brand-primary shrink-0" />
                            )}
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                )
              ) : swapCandidatesQuery.isLoading ? (
                <div className="py-8 text-center text-xs text-text-secondary flex items-center justify-center gap-2">
                  <Loader2 className="h-4 w-4 animate-spin text-brand-primary" />
                  Loading active stationary employees…
                </div>
              ) : swapCandidatesQuery.isError ? (
                <div className="py-6 text-center text-xs text-danger-text px-4">
                  Failed to load eligible swap employees. Please close and retry.
                </div>
              ) : filteredPartners.length === 0 ? (
                <div className="py-8 text-center text-xs text-text-secondary px-4">
                  {eligiblePartners.length === 0
                    ? "No other active stationary employees available to swap with in this account."
                    : "No employees match your search query."}
                </div>
              ) : (
                <ul className="divide-y divide-border-subtle max-h-48 overflow-y-auto">
                  {filteredPartners.map((partner) => {
                    const isSelected = selectedPartner?.plantillaId === partner.plantillaId;
                    return (
                      <li key={partner.plantillaId}>
                        <button
                          type="button"
                          onClick={() => setSelectedPartner(partner)}
                          className={`w-full text-left px-3.5 py-2.5 flex items-center justify-between text-xs transition-colors cursor-pointer ${
                            isSelected
                              ? "bg-surface-muted text-brand-primary font-semibold"
                              : "hover:bg-surface-hover text-text-primary"
                          }`}
                        >
                          <div className="min-w-0 pr-3">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className="font-semibold truncate">{partner.employeeName}</span>
                              <span className="font-mono text-[10px] text-text-secondary">
                                {partner.employeeNo}
                              </span>
                              {partner.position && (
                                <span className="text-[10px] text-text-secondary bg-surface-muted border border-border-default px-1.5 py-0.2 rounded shrink-0">
                                  {partner.position}
                                </span>
                              )}
                            </div>
                            <div className="text-[11px] text-text-secondary mt-0.5 flex items-center gap-1.5 truncate">
                              <span className="font-medium text-text-primary truncate">{partner.storeName}</span>
                              {partner.vcode && (
                                <>
                                  <span>&bull;</span>
                                  <span className="font-mono text-[10px]">{partner.vcode}</span>
                                </>
                              )}
                              {partner.scheduleDays && (
                                <>
                                  <span>&bull;</span>
                                  <span className="truncate">{partner.scheduleDays}</span>
                                </>
                              )}
                            </div>
                          </div>
                          {isSelected && (
                            <CheckCircle2 className="h-4 w-4 text-brand-primary shrink-0" />
                          )}
                        </button>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </div>
        )}

        {/* Reason & Effective Date */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label htmlFor="transfer-reason" className="block text-xs font-semibold text-text-secondary mb-1.5">
              {mode === "transfer" ? "Transfer Reason" : "Swap Reason"} <span className="text-danger-text">*</span>
            </label>
            <select
              id="transfer-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value as TransferReasonType)}
              className="w-full rounded-lg border border-border-default px-3 py-2 text-xs bg-surface text-text-primary focus:border-brand-primary focus:outline-hidden"
            >
              {TRANSFER_REASONS.map((r) => (
                <option key={r.value} value={r.value}>
                  {r.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label htmlFor="transfer-effective-date" className="block text-xs font-semibold text-text-secondary mb-1.5">
              Effective Date <span className="text-danger-text">*</span>
            </label>
            <div className="relative">
              <Calendar className="absolute left-3 top-2.5 h-4 w-4 text-text-muted pointer-events-none" />
              <input
                id="transfer-effective-date"
                type="date"
                value={effectiveDate}
                onChange={(e) => setEffectiveDate(e.target.value)}
                className="w-full rounded-lg border border-border-default pl-9 pr-3 py-2 text-xs bg-surface text-text-primary focus:border-brand-primary focus:outline-hidden"
              />
            </div>
          </div>
        </div>

        {/* Justification / Remarks */}
        <div>
          <label htmlFor="transfer-remarks" className="block text-xs font-semibold text-text-secondary mb-1.5">
            Justification / Operational Remarks
          </label>
          <textarea
            id="transfer-remarks"
            rows={2}
            value={customRemarks}
            onChange={(e) => setCustomRemarks(e.target.value)}
            placeholder="State any specific endorsement notes, turnover details, or OM approval references…"
            className="w-full rounded-lg border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden"
          />
        </div>

        {/* ADR Governance Notice */}
        <div className="rounded-lg border border-border-default bg-surface-muted p-3 flex items-start gap-2.5 text-xs text-text-primary">
          <Building className="h-4 w-4 shrink-0 text-brand-primary mt-0.5" />
          {mode === "transfer" ? (
            <div className="leading-relaxed">
              <span className="font-semibold text-text-primary">ADR Slot &amp; Vacancy Effect:</span> Transferring binds{" "}
              <strong>{employeeName}</strong> to the destination store&apos;s permanent VCode and open slot (position kept).{" "}
              <strong className="text-text-primary">{currentStoreName ?? "The source store"}</strong> will immediately move to{" "}
              <strong>Open Vacancy</strong> for replacement recruitment.
            </div>
          ) : (
            <div className="leading-relaxed">
              <span className="font-semibold text-text-primary">Atomic Store Swap Effect:</span> Both employees stay{" "}
              <strong>Active</strong>, retain their positions, and exchange Stores, VCodes, Slots, and{" "}
              <strong>Work Schedules</strong> (duty days, shift time, and rest day) in one transaction.{" "}
              <strong>Zero vacancies</strong> are opened.
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border-default pt-4">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="rounded-lg border border-border-default bg-surface px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={!canSubmit}
            className="inline-flex items-center gap-1.5 rounded-lg bg-brand-button px-4 py-2 text-xs font-semibold text-white hover:bg-brand-button-hover disabled:bg-surface-muted disabled:text-text-secondary disabled:border-border-default disabled:cursor-not-allowed disabled:shadow-none transition-colors shadow-xs cursor-pointer"
          >
            {isSubmitting ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                {mode === "transfer" ? "Executing Transfer…" : "Executing Swap…"}
              </>
            ) : mode === "transfer" ? (
              <>
                <ArrowRightLeft className="h-3.5 w-3.5" />
                Confirm Store Transfer
              </>
            ) : (
              <>
                <ArrowLeftRight className="h-3.5 w-3.5" />
                Confirm Atomic Swap
              </>
            )}
          </button>
        </div>
      </form>
    </Modal>
  );
}
