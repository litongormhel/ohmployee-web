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
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedStore, setSelectedStore] = useState<DestinationStoreItem | null>(null);
  const [reason, setReason] = useState<TransferReasonType>("Store Initiated");
  const [effectiveDate, setEffectiveDate] = useState<string>(() =>
    new Date().toISOString().substring(0, 10),
  );
  const [customRemarks, setCustomRemarks] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Query eligible stores for this account
  const storesQuery = useQuery({
    queryKey: ["plantilla-destination-stores", accountId],
    queryFn: () => fetchDestinationStores(accountId),
    enabled: isOpen,
    staleTime: 60 * 1000,
  });

  const mutation = useTransferPersonnel();

  // Resolved source island group
  const sourceIslandGroup = useMemo(() => {
    return currentIslandGroup ?? deriveIslandGroup(currentProvince);
  }, [currentIslandGroup, currentProvince]);

  // Destination stores filtered: exclude current store and apply search
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

  // Island group cross-region check
  const destinationIslandGroup = useMemo(() => {
    if (!selectedStore) return null;
    return selectedStore.islandGroup ?? deriveIslandGroup(selectedStore.province ?? selectedStore.areaProvince);
  }, [selectedStore]);

  const isCrossIslandTransfer = Boolean(
    sourceIslandGroup &&
      destinationIslandGroup &&
      sourceIslandGroup !== destinationIslandGroup,
  );

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!selectedStore) {
      setErrorMessage("Please select a target destination store.");
      return;
    }

    if (!effectiveDate) {
      setErrorMessage("Please specify the effective date of the transfer.");
      return;
    }

    const fullRemarks = [
      reason,
      customRemarks.trim() ? `Justification: ${customRemarks.trim()}` : null,
      isCrossIslandTransfer
        ? `Cross-Island Group: ${sourceIslandGroup ?? "Unspecified"} → ${destinationIslandGroup ?? "Unspecified"}`
        : null,
    ]
      .filter(Boolean)
      .join(" | ");

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
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="transfer-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-2xl rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[94vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-blue-50/80">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-100 text-blue-700 border border-blue-200">
              <ArrowRightLeft className="h-5 w-5" />
            </div>
            <div>
              <h2 id="transfer-modal-title" className="text-base font-semibold text-gray-900">
                Transfer Personnel Store Assignment
              </h2>
              <p className="text-xs text-gray-500 font-mono">
                {employeeNo} &bull; {employeeName}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="rounded-lg p-1 text-gray-400 hover:bg-white hover:text-gray-600 transition-colors"
            aria-label="Close modal"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-5">
          {errorMessage && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3.5 flex items-start gap-2.5 text-xs text-red-700">
              <AlertTriangle className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
              <div className="flex-1 font-medium">{errorMessage}</div>
            </div>
          )}

          {/* Current Source Store Card vs Selected Destination Store Card */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3.5">
            {/* Source Store */}
            <div className="rounded-lg border border-gray-200 bg-gray-50/80 p-3.5 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-bold uppercase tracking-wider text-gray-500 flex items-center gap-1.5">
                  <Store className="h-3.5 w-3.5 text-gray-400" />
                  Source Store (Current)
                </span>
                <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-gray-200/80 text-gray-700">
                  Origin
                </span>
              </div>
              <div>
                <p className="text-sm font-semibold text-gray-900">
                  {currentStoreName ?? "Current Store"}
                </p>
                <p className="text-xs text-gray-500 mt-0.5">
                  {[accountName, positionTitle].filter(Boolean).join(" • ")}
                </p>
              </div>
              <div className="pt-1.5 border-t border-gray-200/60 flex items-center justify-between text-[11px] text-gray-600">
                <span className="flex items-center gap-1">
                  <MapPin className="h-3 w-3 text-gray-400" />
                  {currentProvince ?? "Province Unspecified"}
                </span>
                {sourceIslandGroup && (
                  <span className="font-semibold text-gray-700 bg-white border border-gray-200 rounded px-1.5 py-0.5">
                    {sourceIslandGroup}
                  </span>
                )}
              </div>
            </div>

            {/* Destination Store */}
            <div
              className={`rounded-lg border p-3.5 space-y-2 transition-colors ${
                selectedStore
                  ? "border-blue-200 bg-blue-50/50"
                  : "border-dashed border-gray-300 bg-gray-50/40"
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-bold uppercase tracking-wider text-blue-700 flex items-center gap-1.5">
                  <Store className="h-3.5 w-3.5 text-blue-600" />
                  Destination Store (Target)
                </span>
                {selectedStore ? (
                  <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-blue-100 text-blue-700">
                    Selected
                  </span>
                ) : (
                  <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-gray-100 text-gray-500">
                    Pending Pick
                  </span>
                )}
              </div>

              {selectedStore ? (
                <>
                  <div>
                    <div className="flex items-center gap-1.5">
                      <p className="text-sm font-semibold text-gray-900">
                        {selectedStore.storeName}
                      </p>
                      {selectedStore.vcode && (
                        <span className="font-mono text-[10px] bg-white border border-blue-200 text-blue-700 px-1 py-0.2 rounded">
                          {selectedStore.vcode}
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-gray-500 mt-0.5">
                      {[selectedStore.accountName ?? accountName, selectedStore.groupName].filter(Boolean).join(" • ")}
                    </p>
                  </div>
                  <div className="pt-1.5 border-t border-blue-100 flex items-center justify-between text-[11px] text-gray-600">
                    <span className="flex items-center gap-1 truncate max-w-[170px]">
                      <MapPin className="h-3 w-3 text-blue-400 shrink-0" />
                      <span className="truncate">{selectedStore.areaCity ?? selectedStore.province ?? "Location"}</span>
                    </span>
                    {destinationIslandGroup && (
                      <span className="font-semibold text-blue-800 bg-white border border-blue-200 rounded px-1.5 py-0.5 shrink-0">
                        {destinationIslandGroup}
                      </span>
                    )}
                  </div>
                </>
              ) : (
                <div className="py-2 text-center text-xs text-gray-400">
                  Select a destination store from the search list below
                </div>
              )}
            </div>
          </div>

          {/* Cross-Island Group Warning Banner */}
          {isCrossIslandTransfer && (
            <div className="rounded-lg border border-amber-200 bg-amber-50 p-3.5 flex items-start gap-2.5 text-xs text-amber-800">
              <Compass className="h-4 w-4 shrink-0 text-amber-600 mt-0.5" />
              <div className="space-y-1">
                <p className="font-semibold text-amber-900">
                  Cross-Island Group Transfer Detected
                </p>
                <p className="leading-relaxed">
                  Moving this personnel across island groups (<strong>{sourceIslandGroup}</strong> &rarr;{" "}
                  <strong>{destinationIslandGroup}</strong>) requires inter-regional logistics coordination.
                  Ensure regional operations heads are notified.
                </p>
              </div>
            </div>
          )}

          {/* Destination Store Picker with Search Filter */}
          <div className="space-y-2">
            <label htmlFor="store-search-input" className="block text-xs font-semibold text-gray-700 uppercase tracking-wider">
              Search & Select Destination Store <span className="text-red-500">*</span>
            </label>
            <div className="relative">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-gray-400 pointer-events-none" />
              <input
                id="store-search-input"
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search store name, vcode, city, province, or CENCOM group…"
                className="w-full rounded-lg border border-gray-300 pl-9 pr-8 py-2 text-xs focus:border-blue-500 focus:outline-hidden focus:ring-1 focus:ring-blue-500"
              />
              {searchQuery && (
                <button
                  type="button"
                  onClick={() => setSearchQuery("")}
                  className="absolute right-2.5 top-2 text-gray-400 hover:text-gray-600"
                >
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>

            {/* Store List Box */}
            <div className="rounded-lg border border-gray-200 bg-white overflow-hidden">
              {storesQuery.isLoading ? (
                <div className="py-8 text-center text-xs text-gray-500 flex items-center justify-center gap-2">
                  <Loader2 className="h-4 w-4 animate-spin text-blue-600" />
                  Loading destination stores…
                </div>
              ) : storesQuery.isError ? (
                <div className="py-6 text-center text-xs text-red-600 px-4">
                  Failed to load destination stores. Please close and retry.
                </div>
              ) : filteredStores.length === 0 ? (
                <div className="py-8 text-center text-xs text-gray-500 px-4">
                  {eligibleStores.length === 0
                    ? "No other eligible stores found within this account scope."
                    : "No stores match your search query."}
                </div>
              ) : (
                <ul className="divide-y divide-gray-100 max-h-48 overflow-y-auto">
                  {filteredStores.map((store) => {
                    const isSelected = selectedStore?.id === store.id;
                    const ig = store.islandGroup ?? deriveIslandGroup(store.province ?? store.areaProvince);
                    const isCross = sourceIslandGroup && ig && sourceIslandGroup !== ig;

                    return (
                      <li key={store.id}>
                        <button
                          type="button"
                          onClick={() => setSelectedStore(store)}
                          className={`w-full text-left px-3.5 py-2.5 flex items-center justify-between text-xs transition-colors ${
                            isSelected
                              ? "bg-blue-50 text-blue-900"
                              : "hover:bg-gray-50 text-gray-800"
                          }`}
                        >
                          <div className="min-w-0 pr-3">
                            <div className="flex items-center gap-2">
                              <span className="font-semibold truncate">{store.storeName}</span>
                              {store.vcode && (
                                <span className="font-mono text-[10px] text-gray-500 bg-gray-100 px-1 py-0.2 rounded shrink-0">
                                  {store.vcode}
                                </span>
                              )}
                              {isCross && (
                                <span className="text-[10px] font-semibold text-amber-700 bg-amber-100 px-1.5 py-0.2 rounded shrink-0">
                                  Cross-Island
                                </span>
                              )}
                            </div>
                            <div className="text-[11px] text-gray-500 mt-0.5 flex items-center gap-1.5 truncate">
                              <span>{store.groupName ?? "CENCOM"}</span>
                              <span>&bull;</span>
                              <span>{store.areaCity ?? store.province ?? "Metro"}</span>
                              {ig && (
                                <>
                                  <span>&bull;</span>
                                  <span className="text-gray-600 font-medium">{ig}</span>
                                </>
                              )}
                            </div>
                          </div>
                          {isSelected && (
                            <CheckCircle2 className="h-4 w-4 text-blue-600 shrink-0" />
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
              <label htmlFor="transfer-reason" className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1.5">
                Transfer Reason <span className="text-red-500">*</span>
              </label>
              <select
                id="transfer-reason"
                value={reason}
                onChange={(e) => setReason(e.target.value as TransferReasonType)}
                className="w-full rounded-lg border border-gray-300 px-3 py-2 text-xs bg-white focus:border-blue-500 focus:outline-hidden focus:ring-1 focus:ring-blue-500"
              >
                {TRANSFER_REASONS.map((r) => (
                  <option key={r.value} value={r.value}>
                    {r.label}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label htmlFor="transfer-effective-date" className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1.5">
                Effective Transfer Date <span className="text-red-500">*</span>
              </label>
              <div className="relative">
                <Calendar className="absolute left-3 top-2.5 h-4 w-4 text-gray-400 pointer-events-none" />
                <input
                  id="transfer-effective-date"
                  type="date"
                  value={effectiveDate}
                  onChange={(e) => setEffectiveDate(e.target.value)}
                  className="w-full rounded-lg border border-gray-300 pl-9 pr-3 py-2 text-xs focus:border-blue-500 focus:outline-hidden focus:ring-1 focus:ring-blue-500"
                />
              </div>
            </div>
          </div>

          {/* Justification / Remarks */}
          <div>
            <label htmlFor="transfer-remarks" className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1.5">
              Transfer Justification / Operational Remarks
            </label>
            <textarea
              id="transfer-remarks"
              rows={2}
              value={customRemarks}
              onChange={(e) => setCustomRemarks(e.target.value)}
              placeholder="State any specific endorsement notes, turnover details, or OM approval references…"
              className="w-full rounded-lg border border-gray-300 p-2.5 text-xs focus:border-blue-500 focus:outline-hidden focus:ring-1 focus:ring-blue-500"
            />
          </div>

          {/* ADR-001 Slot Vacancy Notice */}
          <div className="rounded-lg border border-blue-200/70 bg-blue-50/40 p-3 flex items-start gap-2.5 text-xs text-blue-900">
            <Building className="h-4 w-4 shrink-0 text-blue-600 mt-0.5" />
            <div className="leading-relaxed">
              <span className="font-semibold">ADR-001 Slot Vacancy Effect:</span> Executing this transfer vacates the
              slot at <strong>{currentStoreName ?? "the source store"}</strong>. In accordance with slot authority,
              the source slot will remain open for recruitment / backfill unless quota is formally amended.
            </div>
          </div>
        </form>

        {/* Footer */}
        <div className="flex items-center justify-between border-t border-gray-100 px-6 py-4 bg-gray-50/50">
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="rounded-lg border border-gray-300 bg-white px-4 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50 focus:outline-hidden transition-colors"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={!selectedStore || mutation.isPending}
            className="inline-flex items-center gap-1.5 rounded-lg bg-blue-600 px-4 py-2 text-xs font-semibold text-white hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed focus:outline-hidden transition-colors shadow-xs"
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
      </div>
    </div>
  );
}
