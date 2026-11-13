"use client";

import { useMemo, useState } from "react";
import {
  AlertCircle,
  Check,
  CheckCircle2,
  Info,
  Loader2,
  MapPin,
  Plus,
  Search,
  Users2,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  useAccountPositionOptions,
  useCoverageGroupEligibleStores,
  useCreateDirectCoverageGroup,
  useScopeAccounts,
  type EligibleCoverageStoreItem,
} from "@/lib/queries/more";

export interface CreateCoverageGroupModalProps {
  isOpen: boolean;
  onClose: () => void;
  defaultAccountId?: string;
  defaultAccountName?: string;
  onSuccess?: (created: { coverageGroupId: string; coverageCode: string }) => void;
}

const EMPLOYMENT_TYPES = ["Regular", "Probationary", "Seasonal", "Agency"] as const;

export function CreateCoverageGroupModal({
  isOpen,
  onClose,
  defaultAccountId,
  defaultAccountName,
  onSuccess,
}: CreateCoverageGroupModalProps) {
  // Form State
  const [selectedAccountId, setSelectedAccountId] = useState<string>(defaultAccountId || "");
  const [selectedPositionId, setSelectedPositionId] = useState<string>("");
  const [selectedEmploymentType, setSelectedEmploymentType] = useState<string>("Regular");
  const [areaName, setAreaName] = useState<string>("");
  const [selectedStoreIds, setSelectedStoreIds] = useState<Set<string>>(new Set());
  const [anchorStoreId, setAnchorStoreId] = useState<string | null>(null);
  const [storeSearch, setStoreSearch] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successInfo, setSuccessInfo] = useState<{ coverageGroupId: string; coverageCode: string } | null>(null);

  // Reset dependent selections when account changes
  const handleAccountChange = (newAccountId: string) => {
    setSelectedAccountId(newAccountId);
    setSelectedPositionId("");
    setSelectedStoreIds(new Set());
    setAnchorStoreId(null);
    setErrorMessage(null);
  };

  // Queries
  const { data: accounts = [], isLoading: isLoadingAccounts } = useScopeAccounts();
  const { data: positions = [], isLoading: isLoadingPositions } = useAccountPositionOptions(selectedAccountId);
  const {
    data: stores = [],
    isLoading: isLoadingStores,
    error: storesError,
  } = useCoverageGroupEligibleStores(selectedAccountId);

  const createMutation = useCreateDirectCoverageGroup();

  // Eligible & Free Stores derivation
  const freeStoreIds = useMemo(() => {
    return new Set(
      stores.filter((s) => !s.alreadyGroupedCode).map((s) => s.storeId)
    );
  }, [stores]);

  const filteredStores = useMemo(() => {
    if (!storeSearch.trim()) return stores;
    const q = storeSearch.toLowerCase();
    return stores.filter(
      (s) =>
        s.storeName.toLowerCase().includes(q) ||
        s.areaCity.toLowerCase().includes(q) ||
        s.areaProvince.toLowerCase().includes(q) ||
        (s.alreadyGroupedCode && s.alreadyGroupedCode.toLowerCase().includes(q))
    );
  }, [stores, storeSearch]);

  const toggleStoreSelection = (store: EligibleCoverageStoreItem) => {
    if (store.alreadyGroupedCode) return; // Cannot select stores already belonging to another group

    const next = new Set(selectedStoreIds);
    if (next.has(store.storeId)) {
      next.delete(store.storeId);
      // If we deselected the current anchor store, clear anchor
      if (anchorStoreId === store.storeId) {
        setAnchorStoreId(null);
      }
    } else {
      next.add(store.storeId);
      // Auto-designate first selected store as anchor if none chosen yet
      if (!anchorStoreId) {
        setAnchorStoreId(store.storeId);
      }
    }
    setSelectedStoreIds(next);
  };

  const setAnchor = (storeId: string) => {
    if (selectedStoreIds.has(storeId)) {
      setAnchorStoreId(storeId);
    }
  };

  const handleSelectAllFreeStores = () => {
    const next = new Set<string>();
    for (const s of stores) {
      if (!s.alreadyGroupedCode) {
        next.add(s.storeId);
      }
    }
    setSelectedStoreIds(next);
    if (!anchorStoreId && next.size > 0) {
      setAnchorStoreId(Array.from(next)[0]);
    }
  };

  const handleClearStoreSelection = () => {
    setSelectedStoreIds(new Set());
    setAnchorStoreId(null);
  };

  const handleResetAndClose = () => {
    if (createMutation.isPending) return;
    if (!defaultAccountId) {
      setSelectedAccountId("");
    }
    setSelectedPositionId("");
    setSelectedEmploymentType("Regular");
    setAreaName("");
    setSelectedStoreIds(new Set());
    setAnchorStoreId(null);
    setStoreSearch("");
    setErrorMessage(null);
    setSuccessInfo(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!selectedAccountId) {
      setErrorMessage("Please select a billing account.");
      return;
    }
    if (!selectedPositionId) {
      setErrorMessage("Please select a target position for this coverage group.");
      return;
    }
    if (selectedStoreIds.size < 2) {
      setErrorMessage("Coverage Groups require at least 2 stores to be selected.");
      return;
    }
    if (!anchorStoreId || !selectedStoreIds.has(anchorStoreId)) {
      setErrorMessage("Please designate an anchor store from your selected stores.");
      return;
    }

    try {
      const result = await createMutation.mutateAsync({
        accountId: selectedAccountId,
        positionId: selectedPositionId,
        employmentType: selectedEmploymentType,
        areaName: areaName.trim() || undefined,
        storeIds: Array.from(selectedStoreIds),
        anchorStoreId,
      });

      setSuccessInfo({
        coverageGroupId: result.coverage_group_id,
        coverageCode: result.coverage_code,
      });

      if (onSuccess) {
        onSuccess({
          coverageGroupId: result.coverage_group_id,
          coverageCode: result.coverage_code,
        });
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Failed to create coverage group.";
      setErrorMessage(msg);
    }
  };

  const isLockedAccount = Boolean(defaultAccountId && defaultAccountName);
  const selectedAnchorStore = stores.find((s) => s.storeId === anchorStoreId);

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleResetAndClose}
      title="Create Roving Coverage Group"
      subtitle="Establish multi-store reliever assignment clusters, roaming headcount pools, and designate anchor home stores."
      icon={Users2}
      maxWidthClass="max-w-2xl"
      isSubmitting={createMutation.isPending}
    >
      {successInfo ? (
        <div className="py-6 text-center space-y-4">
          <div className="inline-flex h-14 w-14 items-center justify-center rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400">
            <CheckCircle2 className="h-8 w-8" />
          </div>
          <div className="space-y-1">
            <h3 className="text-lg font-bold text-text-primary">Coverage Group Created</h3>
            <p className="text-sm text-text-secondary">
              Coverage group{" "}
              <span className="font-mono font-bold text-brand-600 dark:text-brand-400">
                {successInfo.coverageCode}
              </span>{" "}
              has been successfully established with {selectedStoreIds.size} stores.
            </p>
          </div>
          <div className="pt-4">
            <button
              type="button"
              onClick={handleResetAndClose}
              className="inline-flex h-9 items-center justify-center rounded-lg bg-brand-button px-5 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover transition cursor-pointer"
            >
              Done
            </button>
          </div>
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-4">
          {errorMessage && (
            <div className="rounded-lg border border-red-200 dark:border-red-900/40 bg-red-50 dark:bg-red-950/30 p-3 text-xs text-red-700 dark:text-red-400 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
              <span>{errorMessage}</span>
            </div>
          )}

          {/* Account Selection */}
          <div className="space-y-1.5">
            <label className="block text-xs font-semibold text-text-primary">
              Billing Account <span className="text-red-500">*</span>
            </label>
            {isLockedAccount ? (
              <div className="flex h-9 items-center justify-between rounded-lg border border-border-default bg-surface-muted px-3 text-xs text-text-primary">
                <span className="font-semibold">{defaultAccountName}</span>
                <span className="rounded bg-surface-subtle px-2 py-0.5 text-[10px] font-semibold text-text-muted uppercase tracking-wider">
                  Locked to View
                </span>
              </div>
            ) : (
              <select
                value={selectedAccountId}
                onChange={(e) => handleAccountChange(e.target.value)}
                disabled={isLoadingAccounts || createMutation.isPending}
                className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
              >
                <option value="">-- Select Billing Account --</option>
                {accounts.map((acc) => (
                  <option key={acc.id} value={acc.id}>
                    {acc.accountName} {acc.accountCode ? `(${acc.accountCode})` : ""}
                  </option>
                ))}
              </select>
            )}
          </div>

          {/* Position & Employment Type Grid */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Target Position <span className="text-red-500">*</span>
              </label>
              <select
                value={selectedPositionId}
                onChange={(e) => setSelectedPositionId(e.target.value)}
                disabled={!selectedAccountId || isLoadingPositions || createMutation.isPending}
                className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
              >
                <option value="">
                  {!selectedAccountId
                    ? "-- Select Account First --"
                    : isLoadingPositions
                    ? "Loading positions..."
                    : positions.length === 0
                    ? "-- No Positions Configured --"
                    : "-- Select Position --"}
                </option>
                {positions.map((p) => (
                  <option key={p.positionId} value={p.positionId}>
                    {p.positionName} {p.positionCode ? `(${p.positionCode})` : ""}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1.5">
              <label className="block text-xs font-semibold text-text-primary">
                Employment Type <span className="text-red-500">*</span>
              </label>
              <select
                value={selectedEmploymentType}
                onChange={(e) => setSelectedEmploymentType(e.target.value)}
                disabled={createMutation.isPending}
                className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              >
                {EMPLOYMENT_TYPES.map((type) => (
                  <option key={type} value={type}>
                    {type}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Area / Cluster Name */}
          <div className="space-y-1.5">
            <label className="block text-xs font-semibold text-text-primary">
              Cluster / Area Name <span className="text-text-muted font-normal">(Optional)</span>
            </label>
            <input
              type="text"
              value={areaName}
              onChange={(e) => setAreaName(e.target.value)}
              placeholder="e.g. Cebu South Cluster, NCR West Roving Pool"
              disabled={createMutation.isPending}
              className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>

          {/* Store Selection & Anchor Designation */}
          <div className="space-y-2 pt-1 border-t border-border-subtle">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <label className="block text-xs font-bold text-text-primary">
                  Store Footprint ({selectedStoreIds.size} Selected) <span className="text-red-500">*</span>
                </label>
                <p className="text-[11px] text-text-muted">
                  Select at least 2 stores and designate 1 home anchor store.
                </p>
              </div>
              {selectedAccountId && stores.length > 0 && (
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={handleSelectAllFreeStores}
                    disabled={createMutation.isPending || freeStoreIds.size === 0}
                    className="text-[11px] font-semibold text-brand-600 hover:text-brand-700 cursor-pointer disabled:opacity-50"
                  >
                    Select All ({freeStoreIds.size} free)
                  </button>
                  <span className="text-text-muted/50">•</span>
                  <button
                    type="button"
                    onClick={handleClearStoreSelection}
                    disabled={createMutation.isPending || selectedStoreIds.size === 0}
                    className="text-[11px] font-semibold text-text-muted hover:text-text-primary cursor-pointer disabled:opacity-50"
                  >
                    Clear
                  </button>
                </div>
              )}
            </div>

            {/* Anchor Store Callout */}
            {selectedAnchorStore && (
              <div className="flex items-center gap-2 rounded-lg border border-brand-200/80 bg-brand-50/60 dark:bg-brand-950/20 px-3 py-1.5 text-xs text-brand-900 dark:text-brand-300">
                <MapPin className="h-3.5 w-3.5 shrink-0 text-brand-600 dark:text-brand-400" />
                <span>
                  Designated Anchor: <strong>{selectedAnchorStore.storeName}</strong>
                </span>
              </div>
            )}

            {/* Search Filter for stores */}
            {selectedAccountId && (
              <div className="relative">
                <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
                <input
                  type="text"
                  value={storeSearch}
                  onChange={(e) => setStoreSearch(e.target.value)}
                  placeholder="Filter stores by name or city..."
                  className="w-full h-8 pl-8 pr-3 rounded-lg border border-border-default bg-surface-base text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                />
              </div>
            )}

            {/* Stores List Container */}
            <div className="max-h-56 overflow-y-auto rounded-lg border border-border-default bg-surface-subtle/40 p-2 space-y-1.5">
              {!selectedAccountId ? (
                <div className="p-6 text-center text-xs text-text-muted">
                  Please select a billing account above to load eligible stores.
                </div>
              ) : isLoadingStores ? (
                <div className="p-6 flex flex-col items-center justify-center gap-2 text-xs text-text-muted">
                  <Loader2 className="h-4 w-4 animate-spin text-brand-primary" />
                  <span>Loading eligible stores...</span>
                </div>
              ) : storesError ? (
                <div className="p-4 text-center text-xs text-red-600">
                  Failed to load stores. Please ensure you have permission to view this account.
                </div>
              ) : stores.length === 0 ? (
                <div className="p-6 text-center text-xs text-text-muted">
                  No operational stores with active plantilla footprint found for this account.
                </div>
              ) : filteredStores.length === 0 ? (
                <div className="p-6 text-center text-xs text-text-muted">
                  No stores match &quot;{storeSearch}&quot;.
                </div>
              ) : (
                filteredStores.map((store) => {
                  const isSelected = selectedStoreIds.has(store.storeId);
                  const isAnchor = anchorStoreId === store.storeId;
                  const isUnavailable = Boolean(store.alreadyGroupedCode);

                  return (
                    <div
                      key={store.storeId}
                      className={`flex items-center justify-between p-2 rounded-lg border transition-colors ${
                        isUnavailable
                          ? "border-border-subtle bg-surface-muted/40 opacity-60 cursor-not-allowed"
                          : isSelected
                          ? "border-brand-300 dark:border-brand-800 bg-brand-50/40 dark:bg-brand-950/20"
                          : "border-border-default bg-surface-base hover:bg-surface-hover"
                      }`}
                    >
                      <label
                        className={`flex items-center gap-2.5 flex-1 min-w-0 ${
                          isUnavailable ? "cursor-not-allowed" : "cursor-pointer"
                        }`}
                      >
                        <input
                          type="checkbox"
                          checked={isSelected}
                          disabled={isUnavailable || createMutation.isPending}
                          onChange={() => toggleStoreSelection(store)}
                          className="h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500 disabled:cursor-not-allowed"
                        />
                        <div className="truncate">
                          <span className="text-xs font-semibold text-text-primary truncate block">
                            {store.storeName}
                          </span>
                          {(store.areaCity || store.areaProvince) && (
                            <span className="text-[11px] text-text-muted block truncate">
                              {[store.areaCity, store.areaProvince].filter(Boolean).join(", ")}
                            </span>
                          )}
                        </div>
                      </label>

                      <div className="flex items-center gap-1.5 shrink-0 ml-2">
                        {isUnavailable ? (
                          <span className="rounded bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-900/40 px-2 py-0.5 text-[10px] font-bold text-amber-700 dark:text-amber-400">
                            {store.alreadyGroupedCode} (Assigned)
                          </span>
                        ) : isSelected ? (
                          isAnchor ? (
                            <span className="inline-flex items-center gap-1 rounded-full bg-brand-600 px-2 py-0.5 text-[10px] font-bold text-white shadow-2xs">
                              <MapPin className="h-3 w-3" />
                              <span>Anchor</span>
                            </span>
                          ) : (
                            <button
                              type="button"
                              onClick={() => setAnchor(store.storeId)}
                              disabled={createMutation.isPending}
                              className="rounded border border-border-default bg-surface-base px-2 py-0.5 text-[10px] font-semibold text-text-secondary hover:bg-surface-muted hover:text-text-primary transition cursor-pointer"
                            >
                              Set Anchor
                            </button>
                          )
                        ) : null}
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>

          {/* Modal Actions */}
          <div className="flex items-center justify-between pt-3 border-t border-border-subtle">
            <div className="text-[11px] text-text-muted">
              {selectedStoreIds.size < 2 ? (
                <span className="text-amber-600 dark:text-amber-400 font-medium flex items-center gap-1">
                  <Info className="h-3 w-3" />
                  Select at least {2 - selectedStoreIds.size} more store
                </span>
              ) : !anchorStoreId ? (
                <span className="text-amber-600 dark:text-amber-400 font-medium flex items-center gap-1">
                  <Info className="h-3 w-3" />
                  Pick 1 store as Anchor
                </span>
              ) : (
                <span className="text-emerald-600 dark:text-emerald-400 font-medium flex items-center gap-1">
                  <Check className="h-3 w-3" />
                  Ready to create ({selectedStoreIds.size} stores)
                </span>
              )}
            </div>

            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={handleResetAndClose}
                disabled={createMutation.isPending}
                className="h-9 rounded-lg border border-border-default bg-surface-base px-3.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={
                  !selectedAccountId ||
                  !selectedPositionId ||
                  selectedStoreIds.size < 2 ||
                  !anchorStoreId ||
                  createMutation.isPending
                }
                className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-brand-button px-4 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover transition cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {createMutation.isPending ? (
                  <>
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    <span>Creating...</span>
                  </>
                ) : (
                  <>
                    <Plus className="h-3.5 w-3.5" />
                    <span>Create Coverage Group</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </form>
      )}
    </Modal>
  );
}
