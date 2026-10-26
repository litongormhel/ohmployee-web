"use client";

import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  AlertTriangle,
  ArrowRightLeft,
  Building,
  Calendar,
  CheckCircle2,
  Compass,
  Loader2,
  MapPin,
  Search,
  Store,
  X,
} from "lucide-react";
import {
  fetchDestinationStores,
  useTransferPersonnel,
  deriveIslandGroup,
  type DestinationStoreItem,
  type TransferReasonType,
} from "@/lib/queries/plantilla";
import { Modal } from "@/components/shared/Modal";

export interface TransferPersonnelModalProps {
  isOpen: boolean;
  onClose: () => void;
  plantillaId: string;
  employeeName: string;
  employeeNo: string;
  positionTitle?: string | null;
  accountId?: string | null;
  accountName?: string | null;
  currentStoreId?: string | null;
  currentStoreName?: string | null;
  currentProvince?: string | null;
  currentIslandGroup?: string | null;
  onSuccess?: () => void;
}

const TRANSFER_REASONS: { value: TransferReasonType; label: string; description: string }[] = [
  { value: "Store Initiated", label: "Store Initiated", description: "Operational transfer initiated by management / store leadership" },
  { value: "Employee Requested", label: "Employee Requested", description: "Reassignment requested by the employee for personal / relocation reasons" },
  { value: "Operational Need", label: "Operational Need", description: "Critical staffing balance or capacity realignment" },
  { value: "Annual Inventory", label: "Annual Inventory", description: "Temporary or scheduled inventory rotation" },
  { value: "Store Closed Temporarily", label: "Store Closed Temporarily", description: "Store renovation, closure, or maintenance relocation" },
];

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
  currentProvince,
  currentIslandGroup,
  onSuccess,
}: TransferPersonnelModalProps) {
  const [selectedStore, setSelectedStore] = useState<DestinationStoreItem | null>(null);
  const [reason, setReason] = useState<TransferReasonType>("Operational Need");
  const [customRemarks, setCustomRemarks] = useState<string>("");
  const [effectiveDate, setEffectiveDate] = useState<string>(
    () => new Date().toISOString().substring(0, 10),
  );
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useTransferPersonnel();

  const isDirty = selectedStore !== null || customRemarks.trim() !== "" || reason !== "Operational Need";

  // Fetch active eligible destination stores
  const storesQuery = useQuery({
    queryKey: ["plantilla", "destination-stores", accountId],
    queryFn: () => fetchDestinationStores(accountId ?? undefined),
    enabled: isOpen,
    staleTime: 60_000,
  });

  // Filter out the source store and apply client search
  const eligibleStores = useMemo(() => {
    const list = storesQuery.data ?? [];
    return list.filter((s) => s.id !== currentStoreId);
  }, [storesQuery.data, currentStoreId]);

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

  // Derive source vs target island groups
  const sourceIslandGroup = useMemo(() => {
    if (currentIslandGroup) return currentIslandGroup;
    return deriveIslandGroup(currentProvince);
  }, [currentIslandGroup, currentProvince]);

  const destinationIslandGroup = useMemo(() => {
    if (!selectedStore) return null;
    if (selectedStore.islandGroup) return selectedStore.islandGroup;
    return deriveIslandGroup(selectedStore.province ?? selectedStore.areaProvince);
  }, [selectedStore]);

  const isCrossIslandTransfer = Boolean(
    sourceIslandGroup &&
      destinationIslandGroup &&
      sourceIslandGroup !== destinationIslandGroup,
  );

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!selectedStore) {
      setErrorMessage("Please select a target destination store.");
      return;
    }

    if (!effectiveDate) {
      setErrorMessage("Please specify an effective transfer date.");
      return;
    }

    const fullRemarks = customRemarks.trim()
      ? `${reason}: ${customRemarks.trim()}`
      : reason;

    mutation.mutate(
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
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Transfer Personnel Store Assignment"
      subtitle={
        <span className="font-mono text-text-secondary text-xs">
          {employeeNo} • {employeeName}
        </span>
      }
      icon={ArrowRightLeft}
      isSubmitting={mutation.isPending}
      isDirty={isDirty}
      maxWidthClass="max-w-2xl"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg p-3.5 flex items-start gap-2.5 text-xs text-danger-text">
            <AlertTriangle className="h-4 w-4 shrink-0 text-danger-text mt-0.5" />
            <div className="flex-1 font-medium">{errorMessage}</div>
          </div>
        )}

        {/* Current Source Store Card vs Selected Destination Store Card */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3.5">
          {/* Source Store */}
          <div className="rounded-lg border border-border-default bg-surface-muted p-3.5 space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
                <Store className="h-3.5 w-3.5 text-text-muted" />
                Source Store (Current)
              </span>
              <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-surface text-text-secondary border border-border-default">
                Origin
              </span>
            </div>
            <div>
              <p className="text-sm font-semibold text-text-primary">
                {currentStoreName ?? "Current Store"}
              </p>
              <p className="text-xs text-text-secondary mt-0.5">
                {[accountName, positionTitle].filter(Boolean).join(" • ")}
              </p>
            </div>
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

          {/* Destination Store */}
          <div
            className={`rounded-lg border p-3.5 space-y-2 transition-colors ${
              selectedStore
                ? "border-brand-primary bg-surface"
                : "border-dashed border-border-default bg-surface-muted/40"
            }`}
          >
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-bold uppercase tracking-wider text-brand-primary flex items-center gap-1.5">
                <Store className="h-3.5 w-3.5 text-brand-primary" />
                Destination Store (Target)
              </span>
              {selectedStore ? (
                <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-surface-muted text-brand-primary border border-border-default">
                  Selected
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
                  <div className="flex items-center gap-1.5">
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
                Select a destination store from the search list below
              </div>
            )}
          </div>
        </div>

        {/* Cross-Island Group Warning Banner */}
        {isCrossIslandTransfer && (
          <div className="rounded-lg border border-pct-warn-border bg-pct-warn-bg p-3.5 flex items-start gap-2.5 text-xs text-pct-warn-text">
            <Compass className="h-4 w-4 shrink-0 text-pct-warn-text mt-0.5" />
            <div className="space-y-1">
              <p className="font-semibold text-pct-warn-text">
                Cross-Island Group Transfer Detected
              </p>
              <p className="leading-relaxed text-pct-warn-text">
                Moving this personnel across island groups (<strong>{sourceIslandGroup}</strong> &rarr;{" "}
                <strong>{destinationIslandGroup}</strong>) requires inter-regional logistics coordination.
                Ensure regional operations heads are notified.
              </p>
            </div>
          </div>
        )}

        {/* Destination Store Picker with Search Filter */}
        <div className="space-y-2">
          <label htmlFor="store-search-input" className="block text-xs font-semibold text-text-secondary uppercase tracking-wider">
            Search &amp; Select Destination Store <span className="text-danger-text">*</span>
          </label>
          <div className="relative">
            <Search className="absolute left-3 top-2.5 h-4 w-4 text-text-muted pointer-events-none" />
            <input
              id="store-search-input"
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search store name, vcode, city, province, or CENCOM group…"
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

          {/* Store List Box */}
          <div className="rounded-lg border border-border-default bg-surface overflow-hidden">
            {storesQuery.isLoading ? (
              <div className="py-8 text-center text-xs text-text-secondary flex items-center justify-center gap-2">
                <Loader2 className="h-4 w-4 animate-spin text-brand-primary" />
                Loading destination stores…
              </div>
            ) : storesQuery.isError ? (
              <div className="py-6 text-center text-xs text-danger-text px-4">
                Failed to load destination stores. Please close and retry.
              </div>
            ) : filteredStores.length === 0 ? (
              <div className="py-8 text-center text-xs text-text-secondary px-4">
                {eligibleStores.length === 0
                  ? "No other eligible stores found within this account scope."
                  : "No stores match your search query."}
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
                          <div className="flex items-center gap-2">
                            <span className="font-semibold truncate">{store.storeName}</span>
                            {store.vcode && (
                              <span className="font-mono text-[10px] text-text-secondary bg-surface-muted border border-border-default px-1 py-0.2 rounded shrink-0">
                                {store.vcode}
                              </span>
                            )}
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
            )}
          </div>
        </div>

        {/* Transfer Reason & Effective Date */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label htmlFor="transfer-reason" className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1.5">
              Transfer Reason <span className="text-danger-text">*</span>
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
            <label htmlFor="transfer-effective-date" className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1.5">
              Effective Transfer Date <span className="text-danger-text">*</span>
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
          <label htmlFor="transfer-remarks" className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1.5">
            Transfer Justification / Operational Remarks
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

        {/* ADR-001 Slot Vacancy Notice */}
        <div className="rounded-lg border border-border-default bg-surface-muted p-3 flex items-start gap-2.5 text-xs text-text-primary">
          <Building className="h-4 w-4 shrink-0 text-brand-primary mt-0.5" />
          <div className="leading-relaxed">
            <span className="font-semibold text-text-primary">ADR-001 Slot Vacancy Effect:</span> Executing this transfer vacates the
            slot at <strong className="text-text-primary">{currentStoreName ?? "the source store"}</strong>. In accordance with slot authority,
            the source slot will remain open for recruitment / backfill unless quota is formally amended.
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-border-default pt-4">
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="rounded-lg border border-border-default bg-surface px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={!selectedStore || mutation.isPending}
            className="inline-flex items-center gap-1.5 rounded-lg bg-brand-primary px-4 py-2 text-xs font-semibold text-white hover:bg-brand-secondary disabled:opacity-50 disabled:cursor-not-allowed transition-colors shadow-xs cursor-pointer"
          >
            {mutation.isPending ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                Executing Transfer…
              </>
            ) : (
              <>
                <ArrowRightLeft className="h-3.5 w-3.5" />
                Confirm Store Transfer
              </>
            )}
          </button>
        </div>
      </form>
    </Modal>
  );
}
