"use client";

import { useMemo, useState } from "react";
import {
  AlertCircle,
  AlertTriangle,
  Building2,
  CheckCircle2,
  Clock,
  GitMerge,
  Info,
  Loader2,
  MapPin,
  MinusCircle,
  Plus,
  PlusCircle,
  Search,
  ShieldCheck,
  Trash2,
  Users2,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useCurrentUser, isHeadOrSuperAdmin } from "@/lib/auth";
import {
  useCoverageGroupEligibleStores,
  useCoverageGroups,
  useCoverageGroupDetail,
  useCoverageGroupEmployees,
  useCoverageOperation,
  useScopeAccounts,
} from "@/lib/queries/more";

export type CoverageTabType = "create" | "add_store" | "remove_store" | "merge" | "dissolve";

export interface CreateCoverageGroupModalProps {
  isOpen: boolean;
  onClose: () => void;
  defaultAccountId?: string;
  defaultAccountName?: string;
  initialTab?: CoverageTabType;
  onSuccess?: (result: { coverageGroupId?: string; coverageCode?: string }) => void;
}

export function CreateCoverageGroupModal({
  isOpen,
  onClose,
  defaultAccountId,
  defaultAccountName,
  initialTab = "create",
  onSuccess,
}: CreateCoverageGroupModalProps) {
  // Current user & execution authorization
  const currentUser = useCurrentUser();
  const userRole = currentUser?.roleKey ?? currentUser?.roleName;
  const isDirect = isHeadOrSuperAdmin(userRole);

  // Tab State
  const [activeTab, setActiveTab] = useState<CoverageTabType>(initialTab);

  // Shared Account State with sync to defaultAccountId
  const [prevDefaultAccountId, setPrevDefaultAccountId] = useState(defaultAccountId);
  const [selectedAccountId, setSelectedAccountId] = useState<string>(defaultAccountId || "");
  if (defaultAccountId && defaultAccountId !== prevDefaultAccountId) {
    setPrevDefaultAccountId(defaultAccountId);
    setSelectedAccountId(defaultAccountId);
  }

  // Tab 1: Create State
  const [areaName, setAreaName] = useState<string>("");
  const [selectedStoreIds, setSelectedStoreIds] = useState<Set<string>>(new Set());
  const [anchorStoreId, setAnchorStoreId] = useState<string | null>(null);

  // Tab 2: Add Store State
  const [addStoreTargetGroupId, setAddStoreTargetGroupId] = useState<string>("");
  const [selectedStoresToAdd, setSelectedStoresToAdd] = useState<Set<string>>(new Set());

  // Tab 3: Remove Store State
  const [removeStoreTargetGroupId, setRemoveStoreTargetGroupId] = useState<string>("");
  const [selectedStoresToRemove, setSelectedStoresToRemove] = useState<Set<string>>(new Set());

  // Tab 4: Merge State
  const [sourceGroupId, setSourceGroupId] = useState<string>("");
  const [destinationGroupId, setDestinationGroupId] = useState<string>("");

  // Tab 5: Dissolve State
  const [dissolveTargetGroupId, setDissolveTargetGroupId] = useState<string>("");
  const [employeeHomeStores, setEmployeeHomeStores] = useState<Record<string, string>>({});

  // Common UI State
  const [notes, setNotes] = useState<string>("");
  const [storeSearch, setStoreSearch] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successInfo, setSuccessInfo] = useState<{
    tab: CoverageTabType;
    message: string;
    coverageCode?: string;
    requestId?: string;
    isDirect: boolean;
  } | null>(null);

  // Queries
  const { data: accounts = [], isLoading: isLoadingAccounts } = useScopeAccounts();
  const {
    data: stores = [],
    isLoading: isLoadingStores,
  } = useCoverageGroupEligibleStores(selectedAccountId);

  const { data: coverageGroups = [], isLoading: isLoadingCoverageGroups } = useCoverageGroups(
    selectedAccountId || undefined
  );

  const activeCoverageGroups = useMemo(() => {
    return coverageGroups.filter((g) => g.groupStatus === "Active" || !g.groupStatus);
  }, [coverageGroups]);

  // Target group details for Add, Remove, and Dissolve
  const activeRemoveDetailId = activeTab === "remove_store" ? removeStoreTargetGroupId : null;
  const { data: removeTargetDetail, isLoading: isLoadingRemoveTarget } = useCoverageGroupDetail(activeRemoveDetailId);

  const activeAddDetailId = activeTab === "add_store" ? addStoreTargetGroupId : null;
  const { data: addTargetDetail } = useCoverageGroupDetail(activeAddDetailId);

  const activeDissolveDetailId = activeTab === "dissolve" ? dissolveTargetGroupId : null;
  const { data: dissolveTargetDetail, isLoading: isLoadingDissolveTarget } = useCoverageGroupDetail(activeDissolveDetailId);
  const { data: dissolveEmployees = [], isLoading: isLoadingDissolveEmployees } = useCoverageGroupEmployees(activeDissolveDetailId);

  // Source & Destination group details for Merge
  const { data: sourceDetail } = useCoverageGroupDetail(sourceGroupId || null);
  const { data: destDetail } = useCoverageGroupDetail(destinationGroupId || null);

  // Derived default store ID for dissolve home assignments (GAP-02 parity)
  const defaultDissolveHomeStoreId = useMemo(() => {
    return (
      dissolveTargetDetail?.stores?.find((s) => s.isAnchor)?.storeId ||
      dissolveTargetDetail?.stores?.[0]?.storeId ||
      ""
    );
  }, [dissolveTargetDetail]);

  const operationMutation = useCoverageOperation();

  // Free stationary stores (not currently in an active coverage group)
  const freeStores = useMemo(() => {
    return stores.filter((s) => !s.alreadyGroupedCode);
  }, [stores]);

  // All stores filtered by search term (for Create Group footprint)
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

  // Free stores filtered by search term (for Add Store footprint)
  const filteredFreeStores = useMemo(() => {
    if (!storeSearch.trim()) return freeStores;
    const q = storeSearch.toLowerCase();
    return freeStores.filter(
      (s) =>
        s.storeName.toLowerCase().includes(q) ||
        s.areaCity.toLowerCase().includes(q) ||
        s.areaProvince.toLowerCase().includes(q)
    );
  }, [freeStores, storeSearch]);

  // Tab switching handler
  const handleTabChange = (newTab: CoverageTabType) => {
    setActiveTab(newTab);
    setErrorMessage(null);
    setStoreSearch("");
  };

  // Reset & Close
  const handleResetAndClose = () => {
    if (operationMutation.isPending) return;
    if (!defaultAccountId) {
      setSelectedAccountId("");
    }
    setAreaName("");
    setSelectedStoreIds(new Set());
    setAnchorStoreId(null);
    setAddStoreTargetGroupId("");
    setSelectedStoresToAdd(new Set());
    setRemoveStoreTargetGroupId("");
    setSelectedStoresToRemove(new Set());
    setSourceGroupId("");
    setDestinationGroupId("");
    setDissolveTargetGroupId("");
    setEmployeeHomeStores({});
    setNotes("");
    setStoreSearch("");
    setErrorMessage(null);
    setSuccessInfo(null);
    onClose();
  };

  // Helper toggle functions
  const toggleCreateStore = (storeId: string) => {
    const next = new Set(selectedStoreIds);
    if (next.has(storeId)) {
      next.delete(storeId);
      if (anchorStoreId === storeId) {
        setAnchorStoreId(null);
      }
    } else {
      next.add(storeId);
      if (!anchorStoreId) {
        setAnchorStoreId(storeId);
      }
    }
    setSelectedStoreIds(next);
  };

  const toggleAddStore = (storeId: string) => {
    const next = new Set(selectedStoresToAdd);
    if (next.has(storeId)) {
      next.delete(storeId);
    } else {
      next.add(storeId);
    }
    setSelectedStoresToAdd(next);
  };

  const toggleRemoveStore = (storeId: string) => {
    const next = new Set(selectedStoresToRemove);
    if (next.has(storeId)) {
      next.delete(storeId);
    } else {
      next.add(storeId);
    }
    setSelectedStoresToRemove(next);
  };

  // Validation Logic per Tab
  const isSubmitDisabled = useMemo(() => {
    if (!selectedAccountId || operationMutation.isPending) return true;

    if (activeTab === "create") {
      return selectedStoreIds.size < 2 || !anchorStoreId;
    }

    if (activeTab === "add_store") {
      return !addStoreTargetGroupId || selectedStoresToAdd.size === 0;
    }

    if (activeTab === "remove_store") {
      if (!removeStoreTargetGroupId || selectedStoresToRemove.size === 0) return true;
      const totalStores = removeTargetDetail?.stores?.length ?? 0;
      return totalStores - selectedStoresToRemove.size < 2;
    }

    if (activeTab === "merge") {
      return !sourceGroupId || !destinationGroupId || sourceGroupId === destinationGroupId;
    }

    if (activeTab === "dissolve") {
      if (!dissolveTargetGroupId) return true;
      if (dissolveEmployees.length > 0) {
        // Every employee must resolve to a valid home store
        return dissolveEmployees.some(
          (emp) => !(employeeHomeStores[emp.id] || defaultDissolveHomeStoreId)
        );
      }
      return false;
    }

    return true;
  }, [
    selectedAccountId,
    operationMutation.isPending,
    activeTab,
    selectedStoreIds.size,
    anchorStoreId,
    addStoreTargetGroupId,
    selectedStoresToAdd.size,
    removeStoreTargetGroupId,
    selectedStoresToRemove.size,
    removeTargetDetail?.stores?.length,
    sourceGroupId,
    destinationGroupId,
    dissolveTargetGroupId,
    dissolveEmployees,
    employeeHomeStores,
    defaultDissolveHomeStoreId,
  ]);

  // Submit Handler
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!selectedAccountId) {
      setErrorMessage("Please select a billing account.");
      return;
    }

    try {
      if (activeTab === "create") {
        if (selectedStoreIds.size < 2) {
          setErrorMessage("Coverage groups require at least 2 member stores.");
          return;
        }
        if (!anchorStoreId) {
          setErrorMessage("Please designate an anchor store.");
          return;
        }

        const res = await operationMutation.mutateAsync({
          operationType: "create_coverage_group",
          accountId: selectedAccountId,
          positionId: undefined,
          employmentType: "Regular",
          areaName: areaName.trim() || undefined,
          storeIds: Array.from(selectedStoreIds),
          anchorStoreId,
          notes: notes.trim() || undefined,
          autoApprove: isDirect,
        });

        setSuccessInfo({
          tab: "create",
          isDirect,
          coverageCode: res.coverageCode,
          requestId: res.requestId,
          message: isDirect
            ? `Coverage Group ${res.coverageCode || ""} created successfully.`
            : "Coverage Group creation request submitted to Approval Center.",
        });
        onSuccess?.({ coverageGroupId: res.coverageGroupId, coverageCode: res.coverageCode });
      } else if (activeTab === "add_store") {
        if (!addStoreTargetGroupId) {
          setErrorMessage("Please select a target coverage group.");
          return;
        }
        if (selectedStoresToAdd.size === 0) {
          setErrorMessage("Please select at least 1 stationary store to add.");
          return;
        }

        const res = await operationMutation.mutateAsync({
          operationType: "add_store",
          accountId: selectedAccountId,
          targetCoverageGroupId: addStoreTargetGroupId,
          storeIds: Array.from(selectedStoresToAdd),
          notes: notes.trim() || undefined,
          autoApprove: isDirect,
        });

        setSuccessInfo({
          tab: "add_store",
          isDirect,
          requestId: res.requestId,
          message: isDirect
            ? `Successfully added ${selectedStoresToAdd.size} store(s) to coverage group.`
            : "Add Store request submitted to Approval Center.",
        });
        onSuccess?.({ coverageGroupId: addStoreTargetGroupId });
      } else if (activeTab === "remove_store") {
        if (!removeStoreTargetGroupId) {
          setErrorMessage("Please select a target coverage group.");
          return;
        }
        if (selectedStoresToRemove.size === 0) {
          setErrorMessage("Please select at least 1 store to remove.");
          return;
        }
        const totalStores = removeTargetDetail?.stores?.length ?? 0;
        if (totalStores - selectedStoresToRemove.size < 2) {
          setErrorMessage("Coverage groups must retain at least 2 stores. To disband the group, use Dissolve.");
          return;
        }

        const res = await operationMutation.mutateAsync({
          operationType: "remove_store",
          accountId: selectedAccountId,
          targetCoverageGroupId: removeStoreTargetGroupId,
          storeIds: Array.from(selectedStoresToRemove),
          notes: notes.trim() || undefined,
          autoApprove: isDirect,
        });

        setSuccessInfo({
          tab: "remove_store",
          isDirect,
          requestId: res.requestId,
          message: isDirect
            ? `Successfully removed ${selectedStoresToRemove.size} store(s) from coverage group.`
            : "Remove Store request submitted to Approval Center.",
        });
        onSuccess?.({ coverageGroupId: removeStoreTargetGroupId });
      } else if (activeTab === "merge") {
        if (!sourceGroupId || !destinationGroupId) {
          setErrorMessage("Please select both source and destination coverage groups.");
          return;
        }
        if (sourceGroupId === destinationGroupId) {
          setErrorMessage("Source and destination coverage groups must be different.");
          return;
        }

        const res = await operationMutation.mutateAsync({
          operationType: "merge_coverage_groups",
          accountId: selectedAccountId,
          sourceCoverageGroupId: sourceGroupId,
          destinationCoverageGroupId: destinationGroupId,
          notes: notes.trim() || undefined,
          autoApprove: isDirect,
        });

        setSuccessInfo({
          tab: "merge",
          isDirect,
          requestId: res.requestId,
          message: isDirect
            ? "Coverage groups merged successfully. Source group absorbed into destination."
            : "Merge Coverage Groups request submitted to Approval Center.",
        });
        onSuccess?.({ coverageGroupId: destinationGroupId });
      } else if (activeTab === "dissolve") {
        if (!dissolveTargetGroupId) {
          setErrorMessage("Please select a coverage group to dissolve.");
          return;
        }

        const finalHomeStores: Record<string, string> = {};
        if (dissolveEmployees.length > 0) {
          for (const emp of dissolveEmployees) {
            const targetStore = employeeHomeStores[emp.id] || defaultDissolveHomeStoreId;
            if (!targetStore) {
              setErrorMessage(`Please designate a home store for ${emp.fullName}.`);
              return;
            }
            finalHomeStores[emp.id] = targetStore;
          }
        }

        const res = await operationMutation.mutateAsync({
          operationType: "dissolve_coverage_group",
          accountId: selectedAccountId,
          targetCoverageGroupId: dissolveTargetGroupId,
          employeeHomeStores: dissolveEmployees.length > 0 ? finalHomeStores : undefined,
          notes: notes.trim() || undefined,
          autoApprove: isDirect,
        });

        setSuccessInfo({
          tab: "dissolve",
          isDirect,
          requestId: res.requestId,
          message: isDirect
            ? "Coverage group successfully dissolved. All member stores reverted to stationary."
            : "Dissolve Coverage Group request submitted to Approval Center.",
        });
        onSuccess?.({ coverageGroupId: dissolveTargetGroupId });
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Coverage operation failed.";
      setErrorMessage(msg);
    }
  };

  const isLockedAccount = Boolean(defaultAccountId && defaultAccountName);

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleResetAndClose}
      title="Coverage Group Management"
      subtitle="Establish multi-store reliever pools, adjust member stores, merge groups, or dissolve roving assignments."
      icon={Users2}
      maxWidthClass="max-w-3xl"
      isSubmitting={operationMutation.isPending}
    >
      {/* Success View */}
      {successInfo ? (
        <div className="py-8 text-center space-y-4">
          <div className="inline-flex h-14 w-14 items-center justify-center rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400">
            <CheckCircle2 className="h-8 w-8" />
          </div>
          <div className="space-y-1">
            <h3 className="text-lg font-bold text-text-primary">
              {successInfo.isDirect ? "Operation Applied" : "Request Submitted"}
            </h3>
            <p className="text-sm text-text-secondary max-w-md mx-auto">{successInfo.message}</p>
            {successInfo.requestId && (
              <p className="text-xs text-text-muted font-mono pt-1">
                Reference ID: <span className="font-bold text-text-primary">#{successInfo.requestId.slice(0, 8)}</span>
              </p>
            )}
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
        <div className="space-y-4">
          {/* Top Mode Tabs */}
          <div className="flex border-b border-border-subtle bg-surface-subtle/50 px-2 pt-2 gap-1 overflow-x-auto rounded-t-lg">
            <button
              type="button"
              onClick={() => handleTabChange("create")}
              className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold border-b-2 transition-colors whitespace-nowrap cursor-pointer ${
                activeTab === "create"
                  ? "border-brand-600 text-brand-600 dark:border-brand-400 dark:text-brand-400 bg-surface-base rounded-t-lg shadow-2xs"
                  : "border-transparent text-text-secondary hover:text-text-primary"
              }`}
            >
              <Plus className="h-3.5 w-3.5" />
              <span>Create Group</span>
            </button>
            <button
              type="button"
              onClick={() => handleTabChange("add_store")}
              className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold border-b-2 transition-colors whitespace-nowrap cursor-pointer ${
                activeTab === "add_store"
                  ? "border-brand-600 text-brand-600 dark:border-brand-400 dark:text-brand-400 bg-surface-base rounded-t-lg shadow-2xs"
                  : "border-transparent text-text-secondary hover:text-text-primary"
              }`}
            >
              <PlusCircle className="h-3.5 w-3.5" />
              <span>Add Store</span>
            </button>
            <button
              type="button"
              onClick={() => handleTabChange("remove_store")}
              className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold border-b-2 transition-colors whitespace-nowrap cursor-pointer ${
                activeTab === "remove_store"
                  ? "border-brand-600 text-brand-600 dark:border-brand-400 dark:text-brand-400 bg-surface-base rounded-t-lg shadow-2xs"
                  : "border-transparent text-text-secondary hover:text-text-primary"
              }`}
            >
              <MinusCircle className="h-3.5 w-3.5" />
              <span>Remove Store</span>
            </button>
            <button
              type="button"
              onClick={() => handleTabChange("merge")}
              className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold border-b-2 transition-colors whitespace-nowrap cursor-pointer ${
                activeTab === "merge"
                  ? "border-brand-600 text-brand-600 dark:border-brand-400 dark:text-brand-400 bg-surface-base rounded-t-lg shadow-2xs"
                  : "border-transparent text-text-secondary hover:text-text-primary"
              }`}
            >
              <GitMerge className="h-3.5 w-3.5" />
              <span>Merge Groups</span>
            </button>
            <button
              type="button"
              onClick={() => handleTabChange("dissolve")}
              className={`flex items-center gap-1.5 px-3 py-2 text-xs font-semibold border-b-2 transition-colors whitespace-nowrap cursor-pointer ${
                activeTab === "dissolve"
                  ? "border-red-600 text-red-600 dark:border-red-400 dark:text-red-400 bg-surface-base rounded-t-lg shadow-2xs"
                  : "border-transparent text-text-secondary hover:text-text-primary"
              }`}
            >
              <Trash2 className="h-3.5 w-3.5" />
              <span>Dissolve Group</span>
            </button>
          </div>

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
                  onChange={(e) => {
                    setSelectedAccountId(e.target.value);
                    setSelectedStoreIds(new Set());
                    setAnchorStoreId(null);
                    setAddStoreTargetGroupId("");
                    setSelectedStoresToAdd(new Set());
                    setRemoveStoreTargetGroupId("");
                    setSelectedStoresToRemove(new Set());
                    setSourceGroupId("");
                    setDestinationGroupId("");
                    setDissolveTargetGroupId("");
                    setErrorMessage(null);
                  }}
                  disabled={isLoadingAccounts || operationMutation.isPending}
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

            {/* TAB 1: CREATE COVERAGE GROUP */}
            {activeTab === "create" && (
              <div className="space-y-4">
                <div className="rounded-lg bg-brand-50/50 dark:bg-brand-950/20 border border-brand-200/60 p-2.5 text-[11px] text-brand-900 dark:text-brand-300 flex items-start gap-2">
                  <Info className="h-4 w-4 shrink-0 text-brand-600 mt-0.5" />
                  <span>
                    Assemble multiple stationary stores into a roving cluster. Select at least 2 unassigned stores and designate 1 anchor home store.
                  </span>
                </div>

                {/* Area Name */}
                <div className="space-y-1.5">
                  <label className="block text-xs font-semibold text-text-primary">
                    Cluster / Area Name <span className="text-text-muted font-normal">(Optional)</span>
                  </label>
                  <input
                    type="text"
                    value={areaName}
                    onChange={(e) => setAreaName(e.target.value)}
                    placeholder="e.g. Cebu South Cluster, NCR West Roving Pool"
                    disabled={operationMutation.isPending}
                    className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                  />
                </div>

                {/* Store Footprint Picker */}
                <div className="space-y-2 pt-2 border-t border-border-subtle">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <label className="block text-xs font-bold text-text-primary">
                        Stationary Stores Footprint ({selectedStoreIds.size} Selected){" "}
                        <span className="text-red-500">*</span>
                      </label>
                      <p className="text-[11px] text-text-muted">
                        All stationary stores under this account. Stores already in an active coverage group are locked.
                      </p>
                    </div>
                    {freeStores.length > 0 && (
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => {
                            const next = new Set(freeStores.map((s) => s.storeId));
                            setSelectedStoreIds(next);
                            if (!anchorStoreId && next.size > 0) {
                              setAnchorStoreId(freeStores[0].storeId);
                            }
                          }}
                          disabled={operationMutation.isPending}
                          className="text-[11px] font-semibold text-brand-600 hover:text-brand-700 cursor-pointer disabled:opacity-50"
                        >
                          Select All ({freeStores.length})
                        </button>
                        <span className="text-text-muted/50">•</span>
                        <button
                          type="button"
                          onClick={() => {
                            setSelectedStoreIds(new Set());
                            setAnchorStoreId(null);
                          }}
                          disabled={operationMutation.isPending || selectedStoreIds.size === 0}
                          className="text-[11px] font-semibold text-text-muted hover:text-text-primary cursor-pointer disabled:opacity-50"
                        >
                          Clear
                        </button>
                      </div>
                    )}
                  </div>

                  {/* Anchor callout */}
                  {anchorStoreId && (
                    <div className="flex items-center gap-2 rounded-lg border border-brand-200/80 bg-brand-50/60 dark:bg-brand-950/20 px-3 py-1.5 text-xs text-brand-900 dark:text-brand-300">
                      <MapPin className="h-3.5 w-3.5 shrink-0 text-brand-600 dark:text-brand-400" />
                      <span>
                        Designated Anchor Store:{" "}
                        <strong>{stores.find((s) => s.storeId === anchorStoreId)?.storeName || "Unknown"}</strong>
                      </span>
                    </div>
                  )}

                  {/* Store Search */}
                  {selectedAccountId && (
                    <div className="relative">
                      <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
                      <input
                        type="text"
                        value={storeSearch}
                        onChange={(e) => setStoreSearch(e.target.value)}
                        placeholder="Filter stores by name, city, province, or group..."
                        className="w-full h-8 pl-8 pr-3 rounded-lg border border-border-default bg-surface-base text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                      />
                    </div>
                  )}

                  {/* Store list */}
                  <div className="max-h-52 overflow-y-auto rounded-lg border border-border-default bg-surface-subtle/40 p-2 space-y-1.5">
                    {!selectedAccountId ? (
                      <div className="p-6 text-center text-xs text-text-muted">
                        Select a billing account to view stationary stores.
                      </div>
                    ) : isLoadingStores ? (
                      <div className="p-6 flex flex-col items-center justify-center gap-2 text-xs text-text-muted">
                        <Loader2 className="h-4 w-4 animate-spin text-brand-primary" />
                        <span>Loading stores...</span>
                      </div>
                    ) : stores.length === 0 ? (
                      <div className="p-6 text-center text-xs text-text-muted">
                        No stationary stores found for this account.
                      </div>
                    ) : filteredStores.length === 0 ? (
                      <div className="p-6 text-center text-xs text-text-muted">
                        No stores match &quot;{storeSearch}&quot;.
                      </div>
                    ) : (
                      filteredStores.map((store) => {
                        const isGrouped = !!store.alreadyGroupedCode;
                        const isSelected = selectedStoreIds.has(store.storeId);
                        const isAnchor = anchorStoreId === store.storeId;

                        if (isGrouped) {
                          return (
                            <div
                              key={store.storeId}
                              className="flex items-center justify-between p-2 rounded-lg border border-border-default/60 bg-surface-subtle/40 opacity-70"
                            >
                              <div className="flex items-center gap-2.5 flex-1 min-w-0">
                                <input
                                  type="checkbox"
                                  checked={false}
                                  disabled={true}
                                  className="h-4 w-4 rounded border-border-default text-text-muted cursor-not-allowed opacity-50"
                                />
                                <div className="truncate">
                                  <span className="text-xs font-semibold text-text-secondary truncate block">
                                    {store.storeName}
                                  </span>
                                  {(store.areaCity || store.areaProvince) && (
                                    <span className="text-[11px] text-text-muted block truncate">
                                      {[store.areaCity, store.areaProvince].filter(Boolean).join(", ")}
                                    </span>
                                  )}
                                </div>
                              </div>
                              <div className="shrink-0 ml-2">
                                <span className="inline-flex items-center gap-1 rounded bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-800 px-2 py-0.5 text-[10px] font-medium text-amber-700 dark:text-amber-400">
                                  Already in {store.alreadyGroupedCode}
                                </span>
                              </div>
                            </div>
                          );
                        }

                        return (
                          <div
                            key={store.storeId}
                            className={`flex items-center justify-between p-2 rounded-lg border transition-colors ${
                              isSelected
                                ? "border-brand-300 dark:border-brand-800 bg-brand-50/40 dark:bg-brand-950/20"
                                : "border-border-default bg-surface-base hover:bg-surface-hover"
                            }`}
                          >
                            <label className="flex items-center gap-2.5 flex-1 min-w-0 cursor-pointer">
                              <input
                                type="checkbox"
                                checked={isSelected}
                                disabled={operationMutation.isPending}
                                onChange={() => toggleCreateStore(store.storeId)}
                                className="h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500"
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

                            {isSelected && (
                              <div className="shrink-0 ml-2">
                                {isAnchor ? (
                                  <span className="inline-flex items-center gap-1 rounded-full bg-brand-600 px-2 py-0.5 text-[10px] font-bold text-white shadow-2xs">
                                    <MapPin className="h-3 w-3" />
                                    <span>Anchor</span>
                                  </span>
                                ) : (
                                  <button
                                    type="button"
                                    onClick={() => setAnchorStoreId(store.storeId)}
                                    className="rounded border border-border-default bg-surface-base px-2 py-0.5 text-[10px] font-semibold text-text-secondary hover:bg-surface-muted transition cursor-pointer"
                                  >
                                    Set Anchor
                                  </button>
                                )}
                              </div>
                            )}
                          </div>
                        );
                      })
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* TAB 2: ADD STORE */}
            {activeTab === "add_store" && (
              <div className="space-y-4">
                <div className="rounded-lg bg-blue-50/50 dark:bg-blue-950/20 border border-blue-200/60 p-2.5 text-[11px] text-blue-900 dark:text-blue-300 flex items-start gap-2">
                  <Info className="h-4 w-4 shrink-0 text-blue-600 mt-0.5" />
                  <span>
                    Select an active coverage group and add stationary stores to expand its roving footprint.
                  </span>
                </div>

                {/* Target Coverage Group Selector */}
                <div className="space-y-1.5">
                  <label className="block text-xs font-semibold text-text-primary">
                    Target Coverage Group <span className="text-red-500">*</span>
                  </label>
                  <select
                    value={addStoreTargetGroupId}
                    onChange={(e) => {
                      setAddStoreTargetGroupId(e.target.value);
                      setSelectedStoresToAdd(new Set());
                    }}
                    disabled={!selectedAccountId || isLoadingCoverageGroups || operationMutation.isPending}
                    className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
                  >
                    <option value="">
                      {!selectedAccountId
                        ? "-- Select Account First --"
                        : isLoadingCoverageGroups
                        ? "Loading coverage groups..."
                        : activeCoverageGroups.length === 0
                        ? "-- No Active Coverage Groups Found --"
                        : "-- Select Coverage Group --"}
                    </option>
                    {activeCoverageGroups.map((cg) => (
                      <option key={cg.coverageGroupId} value={cg.coverageGroupId}>
                        {cg.coverageCode} — {cg.positionName} ({cg.activeStoreCount} stores)
                        {cg.areaName ? ` • ${cg.areaName}` : ""}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Show current member stores preview */}
                {addTargetDetail && addTargetDetail.stores && addTargetDetail.stores.length > 0 && (
                  <div className="rounded-lg border border-border-subtle bg-surface-subtle/30 p-2.5 space-y-1.5">
                    <span className="text-[11px] font-bold text-text-muted uppercase tracking-wider">
                      Current Member Stores ({addTargetDetail.stores.length})
                    </span>
                    <div className="flex flex-wrap gap-1.5">
                      {addTargetDetail.stores.map((s) => (
                        <span
                          key={s.storeId}
                          className="inline-flex items-center gap-1 rounded bg-surface-base border border-border-default px-2 py-0.5 text-[11px] text-text-secondary"
                        >
                          <Building2 className="h-3 w-3 text-text-muted" />
                          <span>{s.storeName}</span>
                          {s.isAnchor && <span className="text-[10px] font-bold text-brand-600">(Anchor)</span>}
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {/* Available Stationary Stores to Add */}
                <div className="space-y-2 pt-2 border-t border-border-subtle">
                  <div className="flex items-center justify-between">
                    <label className="block text-xs font-bold text-text-primary">
                      Available Stationary Stores to Add ({selectedStoresToAdd.size} Selected){" "}
                      <span className="text-red-500">*</span>
                    </label>
                  </div>

                  {/* Search */}
                  {selectedAccountId && (
                    <div className="relative">
                      <Search className="pointer-events-none absolute left-2.5 top-2.5 h-3.5 w-3.5 text-text-muted" />
                      <input
                        type="text"
                        value={storeSearch}
                        onChange={(e) => setStoreSearch(e.target.value)}
                        placeholder="Search stationary stores to add..."
                        className="w-full h-8 pl-8 pr-3 rounded-lg border border-border-default bg-surface-base text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                      />
                    </div>
                  )}

                  <div className="max-h-52 overflow-y-auto rounded-lg border border-border-default bg-surface-subtle/40 p-2 space-y-1.5">
                    {!addStoreTargetGroupId ? (
                      <div className="p-6 text-center text-xs text-text-muted">
                        Select a target coverage group above to view available stores.
                      </div>
                    ) : freeStores.length === 0 ? (
                      <div className="p-6 text-center text-xs text-text-muted">
                        No unassigned stationary stores available to add.
                      </div>
                    ) : filteredFreeStores.length === 0 ? (
                      <div className="p-6 text-center text-xs text-text-muted">
                        No stores match &quot;{storeSearch}&quot;.
                      </div>
                    ) : (
                      filteredFreeStores.map((store) => {
                        const isSelected = selectedStoresToAdd.has(store.storeId);
                        return (
                          <label
                            key={store.storeId}
                            className={`flex items-center justify-between p-2 rounded-lg border transition-colors cursor-pointer ${
                              isSelected
                                ? "border-brand-300 dark:border-brand-800 bg-brand-50/40 dark:bg-brand-950/20"
                                : "border-border-default bg-surface-base hover:bg-surface-hover"
                            }`}
                          >
                            <div className="flex items-center gap-2.5 flex-1 min-w-0">
                              <input
                                type="checkbox"
                                checked={isSelected}
                                disabled={operationMutation.isPending}
                                onChange={() => toggleAddStore(store.storeId)}
                                className="h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500"
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
                            </div>
                          </label>
                        );
                      })
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* TAB 3: REMOVE STORE */}
            {activeTab === "remove_store" && (
              <div className="space-y-4">
                <div className="rounded-lg bg-amber-50/50 dark:bg-amber-950/20 border border-amber-200/60 p-2.5 text-[11px] text-amber-900 dark:text-amber-300 flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 shrink-0 text-amber-600 mt-0.5" />
                  <span>
                    Remove member stores from a coverage group. Removed stores revert to stationary. The group must retain at least 2 member stores.
                  </span>
                </div>

                {/* Target Coverage Group Selector */}
                <div className="space-y-1.5">
                  <label className="block text-xs font-semibold text-text-primary">
                    Target Coverage Group <span className="text-red-500">*</span>
                  </label>
                  <select
                    value={removeStoreTargetGroupId}
                    onChange={(e) => {
                      setRemoveStoreTargetGroupId(e.target.value);
                      setSelectedStoresToRemove(new Set());
                    }}
                    disabled={!selectedAccountId || isLoadingCoverageGroups || operationMutation.isPending}
                    className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
                  >
                    <option value="">
                      {!selectedAccountId
                        ? "-- Select Account First --"
                        : isLoadingCoverageGroups
                        ? "Loading coverage groups..."
                        : activeCoverageGroups.length === 0
                        ? "-- No Active Coverage Groups Found --"
                        : "-- Select Coverage Group --"}
                    </option>
                    {activeCoverageGroups.map((cg) => (
                      <option key={cg.coverageGroupId} value={cg.coverageGroupId}>
                        {cg.coverageCode} — {cg.positionName} ({cg.activeStoreCount} stores)
                        {cg.areaName ? ` • ${cg.areaName}` : ""}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Member Stores of this group */}
                {removeStoreTargetGroupId && (
                  <div className="space-y-2 pt-2 border-t border-border-subtle">
                    <div className="flex items-center justify-between">
                      <label className="block text-xs font-bold text-text-primary">
                        Select Member Store(s) to Remove ({selectedStoresToRemove.size} Selected){" "}
                        <span className="text-red-500">*</span>
                      </label>
                    </div>

                    {isLoadingRemoveTarget ? (
                      <div className="p-6 flex flex-col items-center justify-center gap-2 text-xs text-text-muted">
                        <Loader2 className="h-4 w-4 animate-spin text-brand-primary" />
                        <span>Loading member stores...</span>
                      </div>
                    ) : !removeTargetDetail || !removeTargetDetail.stores || removeTargetDetail.stores.length === 0 ? (
                      <div className="p-6 text-center text-xs text-text-muted">
                        No member stores found in this coverage group.
                      </div>
                    ) : removeTargetDetail.stores.length <= 2 ? (
                      <div className="rounded-lg border border-amber-200 dark:border-amber-900/40 bg-amber-50 dark:bg-amber-950/30 p-3 text-xs text-amber-800 dark:text-amber-300">
                        This coverage group only has {removeTargetDetail.stores.length} member stores. A coverage group requires at least 2 member stores to remain active. To disband this group completely, please switch to the <strong>Dissolve Group</strong> tab.
                      </div>
                    ) : (
                      <>
                        {removeTargetDetail.stores.length - selectedStoresToRemove.size < 2 && (
                          <div className="rounded-lg border border-red-200 dark:border-red-900/40 bg-red-50 dark:bg-red-950/30 p-2.5 text-xs text-red-700 dark:text-red-400">
                            Warning: Removing {selectedStoresToRemove.size} stores will leave fewer than 2 stores. Please keep at least 2 stores or use Dissolve Group instead.
                          </div>
                        )}

                        <div className="max-h-52 overflow-y-auto rounded-lg border border-border-default bg-surface-subtle/40 p-2 space-y-1.5">
                          {removeTargetDetail.stores.map((store) => {
                            const isSelected = selectedStoresToRemove.has(store.storeId);
                            return (
                              <label
                                key={store.storeId}
                                className={`flex items-center justify-between p-2 rounded-lg border transition-colors cursor-pointer ${
                                  isSelected
                                    ? "border-red-300 dark:border-red-800 bg-red-50/40 dark:bg-red-950/20"
                                    : "border-border-default bg-surface-base hover:bg-surface-hover"
                                }`}
                              >
                                <div className="flex items-center gap-2.5 flex-1 min-w-0">
                                  <input
                                    type="checkbox"
                                    checked={isSelected}
                                    disabled={operationMutation.isPending}
                                    onChange={() => toggleRemoveStore(store.storeId)}
                                    className="h-4 w-4 rounded border-border-default text-red-600 focus:ring-red-500"
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
                                </div>

                                {store.isAnchor && (
                                  <span className="shrink-0 ml-2 rounded-full bg-amber-500/10 border border-amber-500/30 px-2 py-0.5 text-[10px] font-bold text-amber-700 dark:text-amber-300">
                                    Current Anchor
                                  </span>
                                )}
                              </label>
                            );
                          })}
                        </div>
                      </>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* TAB 4: MERGE GROUPS */}
            {activeTab === "merge" && (
              <div className="space-y-4">
                <div className="rounded-lg bg-indigo-50/50 dark:bg-indigo-950/20 border border-indigo-200/60 p-2.5 text-[11px] text-indigo-900 dark:text-indigo-300 flex items-start gap-2">
                  <GitMerge className="h-4 w-4 shrink-0 text-indigo-600 mt-0.5" />
                  <span>
                    Merge 2 coverage groups into one. All stores and vacancies from the Source group are absorbed into Destination, and Source group is dissolved.
                  </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  {/* Source Group */}
                  <div className="space-y-1.5">
                    <label className="block text-xs font-semibold text-text-primary">
                      Source Coverage Group (Absorbed) <span className="text-red-500">*</span>
                    </label>
                    <select
                      value={sourceGroupId}
                      onChange={(e) => setSourceGroupId(e.target.value)}
                      disabled={!selectedAccountId || isLoadingCoverageGroups || operationMutation.isPending}
                      className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
                    >
                      <option value="">-- Select Source Group --</option>
                      {activeCoverageGroups.map((cg) => (
                        <option
                          key={cg.coverageGroupId}
                          value={cg.coverageGroupId}
                          disabled={cg.coverageGroupId === destinationGroupId}
                        >
                          {cg.coverageCode} — {cg.positionName} ({cg.activeStoreCount} stores)
                        </option>
                      ))}
                    </select>
                  </div>

                  {/* Destination Group */}
                  <div className="space-y-1.5">
                    <label className="block text-xs font-semibold text-text-primary">
                      Destination Coverage Group (Retained) <span className="text-red-500">*</span>
                    </label>
                    <select
                      value={destinationGroupId}
                      onChange={(e) => setDestinationGroupId(e.target.value)}
                      disabled={!selectedAccountId || isLoadingCoverageGroups || operationMutation.isPending}
                      className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
                    >
                      <option value="">-- Select Destination Group --</option>
                      {activeCoverageGroups.map((cg) => (
                        <option
                          key={cg.coverageGroupId}
                          value={cg.coverageGroupId}
                          disabled={cg.coverageGroupId === sourceGroupId}
                        >
                          {cg.coverageCode} — {cg.positionName} ({cg.activeStoreCount} stores)
                        </option>
                      ))}
                    </select>
                  </div>
                </div>

                {/* Comparison Card */}
                {sourceDetail && destDetail && (
                  <div className="rounded-lg border border-indigo-200 dark:border-indigo-900/40 bg-indigo-50/30 dark:bg-indigo-950/20 p-3 space-y-2">
                    <div className="flex items-center justify-between text-xs font-bold text-text-primary">
                      <span>{sourceDetail.coverageCode} (Source)</span>
                      <GitMerge className="h-4 w-4 text-indigo-600" />
                      <span>{destDetail.coverageCode} (Destination)</span>
                    </div>
                    <div className="grid grid-cols-2 gap-3 text-[11px] text-text-secondary border-t border-indigo-100 dark:border-indigo-900/30 pt-2">
                      <div>
                        <span className="font-semibold block">{sourceDetail.stores?.length || 0} Stores absorbed:</span>
                        <span className="truncate block text-text-muted">
                          {sourceDetail.stores?.map((s) => s.storeName).join(", ") || "None"}
                        </span>
                      </div>
                      <div>
                        <span className="font-semibold block">{destDetail.stores?.length || 0} Existing Stores:</span>
                        <span className="truncate block text-text-muted">
                          {destDetail.stores?.map((s) => s.storeName).join(", ") || "None"}
                        </span>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* TAB 5: DISSOLVE GROUP */}
            {activeTab === "dissolve" && (
              <div className="space-y-4">
                <div className="rounded-lg bg-red-50/50 dark:bg-red-950/20 border border-red-200/60 p-2.5 text-[11px] text-red-900 dark:text-red-300 flex items-start gap-2">
                  <Trash2 className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
                  <span>
                    Dissolve this coverage group. All member stores will revert to stationary status. If active personnel exist in the group, assign each employee to a member home store.
                  </span>
                </div>

                {/* Target Coverage Group Selector */}
                <div className="space-y-1.5">
                  <label className="block text-xs font-semibold text-text-primary">
                    Coverage Group to Dissolve <span className="text-red-500">*</span>
                  </label>
                  <select
                    value={dissolveTargetGroupId}
                    onChange={(e) => {
                      setDissolveTargetGroupId(e.target.value);
                      setEmployeeHomeStores({});
                    }}
                    disabled={!selectedAccountId || isLoadingCoverageGroups || operationMutation.isPending}
                    className="w-full h-9 rounded-lg border border-border-default bg-surface-base px-3 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
                  >
                    <option value="">
                      {!selectedAccountId
                        ? "-- Select Account First --"
                        : isLoadingCoverageGroups
                        ? "Loading coverage groups..."
                        : activeCoverageGroups.length === 0
                        ? "-- No Active Coverage Groups Found --"
                        : "-- Select Coverage Group --"}
                    </option>
                    {activeCoverageGroups.map((cg) => (
                      <option key={cg.coverageGroupId} value={cg.coverageGroupId}>
                        {cg.coverageCode} — {cg.positionName} ({cg.activeStoreCount} stores)
                        {cg.areaName ? ` • ${cg.areaName}` : ""}
                      </option>
                    ))}
                  </select>
                </div>

                {/* Detail Summary & Employee Home Store Designation */}
                {dissolveTargetGroupId && (
                  <div className="space-y-3 pt-2 border-t border-border-subtle">
                    {isLoadingDissolveTarget || isLoadingDissolveEmployees ? (
                      <div className="p-6 flex flex-col items-center justify-center gap-2 text-xs text-text-muted">
                        <Loader2 className="h-4 w-4 animate-spin text-brand-primary" />
                        <span>Loading coverage group personnel and footprint...</span>
                      </div>
                    ) : (
                      <>
                        {/* Member stores preview */}
                        <div className="rounded-lg border border-border-default bg-surface-subtle/30 p-2.5">
                          <span className="text-[11px] font-bold text-text-muted uppercase tracking-wider block mb-1">
                            Reverting {dissolveTargetDetail?.stores?.length ?? 0} Stores to Stationary:
                          </span>
                          <span className="text-xs text-text-secondary">
                            {dissolveTargetDetail?.stores?.map((s) => s.storeName).join(", ") || "None"}
                          </span>
                        </div>

                        {/* Active Employees Home Store Mapping (GAP-02 parity) */}
                        <div className="space-y-2">
                          <div className="flex items-center justify-between">
                            <label className="block text-xs font-bold text-text-primary">
                              Home Store Assignment for Active Personnel ({dissolveEmployees.length})
                            </label>
                          </div>

                          {dissolveEmployees.length === 0 ? (
                            <div className="rounded-lg border border-border-default bg-surface-base p-3 text-xs text-text-muted">
                              No active personnel assigned to this coverage group. Stores will safely revert to stationary with no employee reassignments required.
                            </div>
                          ) : (
                            <div className="space-y-2 max-h-52 overflow-y-auto rounded-lg border border-border-default bg-surface-subtle/40 p-2">
                              {dissolveEmployees.map((emp) => (
                                <div
                                  key={emp.id}
                                  className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 p-2 rounded-lg border border-border-default bg-surface-base"
                                >
                                  <div>
                                    <span className="text-xs font-semibold text-text-primary block">
                                      {emp.fullName}
                                    </span>
                                    <span className="text-[11px] text-text-muted">
                                      {emp.employeeNo ? `#${emp.employeeNo} • ` : ""}
                                      {emp.position || "Employee"}
                                    </span>
                                  </div>

                                  <div className="sm:w-60">
                                    <select
                                      value={employeeHomeStores[emp.id] || defaultDissolveHomeStoreId}
                                      onChange={(e) =>
                                        setEmployeeHomeStores((prev) => ({
                                          ...prev,
                                          [emp.id]: e.target.value,
                                        }))
                                      }
                                      className="w-full h-8 rounded-lg border border-border-default bg-surface-base px-2 text-xs text-text-primary focus:border-brand-500 focus:outline-none"
                                    >
                                      <option value="">-- Assign Home Store --</option>
                                      {dissolveTargetDetail?.stores?.map((s) => (
                                        <option key={s.storeId} value={s.storeId}>
                                          {s.storeName} {s.isAnchor ? "(Anchor)" : ""}
                                        </option>
                                      ))}
                                    </select>
                                  </div>
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      </>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* Optional Notes / Justification (Applicable to all tabs) */}
            <div className="space-y-1.5 pt-2 border-t border-border-subtle">
              <label className="block text-xs font-semibold text-text-primary">
                Remarks / Justification <span className="text-text-muted font-normal">(Optional)</span>
              </label>
              <textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Reason or operational context for this coverage adjustment..."
                rows={2}
                disabled={operationMutation.isPending}
                className="w-full rounded-lg border border-border-default bg-surface-base p-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              />
            </div>

            {/* Bottom Actions Bar */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pt-3 border-t border-border-subtle">
              <div className="text-[11px]">
                {isDirect ? (
                  <div className="flex items-center gap-1.5 text-emerald-700 dark:text-emerald-400 font-medium">
                    <ShieldCheck className="h-4 w-4 shrink-0" />
                    <span>Administrator Mode: Changes apply directly to live operations.</span>
                  </div>
                ) : (
                  <div className="flex items-center gap-1.5 text-amber-700 dark:text-amber-400 font-medium">
                    <Clock className="h-4 w-4 shrink-0" />
                    <span>Request Mode: Submits request to Approval Center for review.</span>
                  </div>
                )}
              </div>

              <div className="flex items-center gap-2 justify-end">
                <button
                  type="button"
                  onClick={handleResetAndClose}
                  disabled={operationMutation.isPending}
                  className="h-9 rounded-lg border border-border-default bg-surface-base px-3.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
                >
                  Cancel
                </button>

                <button
                  type="submit"
                  disabled={isSubmitDisabled || operationMutation.isPending}
                  className={`inline-flex h-9 items-center gap-1.5 rounded-lg px-4 text-xs font-semibold shadow-xs transition cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed ${
                    isDirect
                      ? "bg-emerald-600 hover:bg-emerald-700 text-white"
                      : "bg-brand-button hover:bg-brand-button-hover text-white"
                  }`}
                >
                  {operationMutation.isPending ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      <span>{isDirect ? "Applying..." : "Submitting..."}</span>
                    </>
                  ) : isDirect ? (
                    <>
                      <ShieldCheck className="h-3.5 w-3.5" />
                      <span>
                        {activeTab === "create"
                          ? "Create Directly"
                          : activeTab === "dissolve"
                          ? "Dissolve Directly"
                          : "Apply Directly"}
                      </span>
                    </>
                  ) : (
                    <>
                      <Clock className="h-3.5 w-3.5" />
                      <span>Submit for Approval</span>
                    </>
                  )}
                </button>
              </div>
            </div>
          </form>
        </div>
      )}
    </Modal>
  );
}
