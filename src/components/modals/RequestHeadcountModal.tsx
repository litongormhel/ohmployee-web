"use client";

import { useState, useMemo } from "react";
import {
  AlertCircle,
  AlertTriangle,
  Building2,
  CheckCircle2,
  Clock,
  Globe2,
  Layers,
  MapPin,
  Minus,
  Plus,
  ShieldAlert,
  Sparkles,
  UsersRound,
  X,
  ArrowRight,
  ArrowLeft,
  Search,
} from "lucide-react";
import {
  useSubmitHeadcountRequest,
  useAvailableHeadcountAccounts,
  useHeadcountModalMasterData,
  type SubmitHeadcountRequestInput,
  type SubmitHeadcountRequestResult,
} from "@/lib/queries/requests";
import { useRefCities } from "@/lib/queries/locations";
import { Modal } from "@/components/shared/Modal";
import { RequiredAsterisk } from "@/components/shared/RequiredAsterisk";
import type { ActionModalProps } from "@/types/modal";

export interface RequestHeadcountModalProps extends ActionModalProps<SubmitHeadcountRequestResult | undefined> {
  accountId?: string | null;
  accountName?: string | null;
  initialStoreId?: string | null;
  initialStoreName?: string | null;
  initialProvince?: string | null;
  initialCity?: string | null;
  lockedWorkforceType?: WorkforceType | null;
  lockedStore?: boolean;
}

export type WorkforceType = "stationary" | "roving" | "floating";
export type RequestType =
  | "Additional Headcount"
  | "Replacement"
  | "Reliever"
  | "Commando"
  | "HC Reduction";
export type UrgencyTier = "Low" | "Medium" | "High" | "Critical";

interface StoreItem {
  id: string;
  store_name: string;
  area_city?: string | null;
  area_province?: string | null;
  province?: string | null;
  island_group?: string | null;
  account_id?: string | null;
  is_active?: boolean;
  is_new_store?: boolean;
}

function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function addDays(dateStr: string, days: number): string {
  try {
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return dateStr;
    d.setDate(d.getDate() + days);
    return formatDate(d);
  } catch {
    return dateStr;
  }
}

function getUrgencyDays(tier: UrgencyTier): number {
  switch (tier) {
    case "Critical":
      return 3;
    case "High":
      return 7;
    case "Medium":
      return 14;
    case "Low":
      return 30;
    default:
      return 14;
  }
}

export function RequestHeadcountModal({
  isOpen,
  onClose,
  accountId: propAccountId,
  accountName: propAccountName,
  initialStoreId,
  initialStoreName,
  initialProvince,
  initialCity,
  lockedWorkforceType,
  lockedStore = false,
  onSuccess,
}: RequestHeadcountModalProps) {
  if (!isOpen) return null;

  return (
    <RequestHeadcountModalDialog
      onClose={onClose}
      propAccountId={propAccountId}
      propAccountName={propAccountName}
      initialStoreId={initialStoreId}
      initialStoreName={initialStoreName}
      initialProvince={initialProvince}
      initialCity={initialCity}
      lockedWorkforceType={lockedWorkforceType}
      lockedStore={lockedStore}
      onSuccess={onSuccess}
    />
  );
}

interface RequestHeadcountModalDialogProps {
  onClose: () => void;
  propAccountId?: string | null;
  propAccountName?: string | null;
  initialStoreId?: string | null;
  initialStoreName?: string | null;
  initialProvince?: string | null;
  initialCity?: string | null;
  lockedWorkforceType?: WorkforceType | null;
  lockedStore?: boolean;
  onSuccess?: (result?: SubmitHeadcountRequestResult) => void;
}

function RequestHeadcountModalDialog({
  onClose,
  propAccountId,
  propAccountName,
  initialStoreId,
  initialStoreName,
  initialProvince,
  initialCity,
  lockedWorkforceType,
  lockedStore = false,
  onSuccess,
}: RequestHeadcountModalDialogProps) {
  const submitMutation = useSubmitHeadcountRequest();

  // Step state: "form" | "review"
  const [currentStep, setCurrentStep] = useState<"form" | "review">("form");

  // Account State
  const { data: accountsData = [] } = useAvailableHeadcountAccounts({
    enabled: !propAccountId,
  });

  const availableAccounts = useMemo(() => {
    if (propAccountId) return [];
    return accountsData;
  }, [propAccountId, accountsData]);

  const [customAccountId, setCustomAccountId] = useState<string>("");
  const [customAccountName, setCustomAccountName] = useState<string>("");

  const selectedAccountId =
    propAccountId ||
    customAccountId ||
    (availableAccounts.length > 0 ? availableAccounts[0].id : "");

  const selectedAccountName =
    propAccountName ||
    customAccountName ||
    (availableAccounts.find((a) => a.id === selectedAccountId)?.name ?? "");

  const setSelectedAccountId = setCustomAccountId;
  const setSelectedAccountName = setCustomAccountName;

  // Workforce Type
  const [workforceType, setWorkforceType] = useState<WorkforceType>(
    lockedWorkforceType ?? "stationary"
  );

  // Master Data & Options (Derived from React Query)
  const {
    data: masterData,
    isLoading: isLoadingMasterData,
  } = useHeadcountModalMasterData(selectedAccountId, {
    enabled: Boolean(selectedAccountId),
  });

  const stores = useMemo(() => masterData?.stores ?? [], [masterData?.stores]);
  const positions = useMemo(() => masterData?.positions ?? [], [masterData?.positions]);
  const provinces = useMemo(() => masterData?.provinces ?? [], [masterData?.provinces]);
  const recentRequests = useMemo(() => masterData?.recentRequests ?? [], [masterData?.recentRequests]);
  const isRecruitmentFreezeActive = masterData?.isRecruitmentFreezeActive ?? false;

  // Form Fields - Stationary
  const [selectedProvince, setSelectedProvince] = useState<string>(initialProvince || "");
  const [selectedCity, setSelectedCity] = useState<string>(initialCity || "");
  const [userSelectedStore, setUserSelectedStore] = useState<StoreItem | null>(null);
  const selectedStore = useMemo<StoreItem | null>(() => {
    if (userSelectedStore) return userSelectedStore;
    if (!initialStoreId && !initialStoreName) return null;
    const matchById = initialStoreId
      ? stores.find((s) => s.id === initialStoreId)
      : undefined;
    if (matchById) return matchById;
    const matchByName = initialStoreName
      ? stores.find(
          (s) => s.store_name.trim().toLowerCase() === initialStoreName.trim().toLowerCase()
        )
      : undefined;
    if (matchByName) return matchByName;
    if (initialStoreId && /^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(initialStoreId)) {
      return {
        id: initialStoreId,
        store_name: initialStoreName || "Preselected Store",
        province: initialProvince || null,
        area_city: initialCity || null,
      };
    }
    return null;
  }, [userSelectedStore, initialStoreId, initialStoreName, initialProvince, initialCity, stores]);
  const setSelectedStore = setUserSelectedStore;
  const [storeSearch, setStoreSearch] = useState<string>("");

  // Form Fields - Roving
  const [selectedRovingStores, setSelectedRovingStores] = useState<StoreItem[]>([]);
  const [rovingSearch, setRovingSearch] = useState<string>("");

  // Form Fields - Position & Quota
  const [customPositionId, setCustomPositionId] = useState<string>("");
  const selectedPositionId =
    customPositionId || (positions.length > 0 ? positions[0].id : "");
  const setSelectedPositionId = setCustomPositionId;

  const [requestType, setRequestType] = useState<RequestType>("Additional Headcount");
  const [headcountNeeded, setHeadcountNeeded] = useState<number>(1);

  // Form Fields - Timeline & Urgency
  const todayStr = useMemo(() => formatDate(new Date()), []);
  const [vacantDate, setVacantDate] = useState<string>(todayStr);
  const [urgency, setUrgency] = useState<UrgencyTier>("Medium");
  const [targetFillDate, setTargetFillDate] = useState<string>(addDays(todayStr, 14));
  const [isTargetDateUserOverridden, setIsTargetDateUserOverridden] = useState(false);

  // Form Fields - Justification & Error state
  const [reason, setReason] = useState<string>("");
  const [validationError, setValidationError] = useState<string | null>(null);
  const [submissionError, setSubmissionError] = useState<string | null>(null);

  // Cities (Derived from React Query and loaded stores)
  const { data: dbCities = [] } = useRefCities(selectedProvince, {
    enabled: Boolean(selectedProvince),
  });

  const cities = useMemo(() => {
    if (!selectedProvince) return [];
    if (dbCities.length > 0) return dbCities;
    const storeCitiesMap = new Map<string, string>();
    stores
      .filter(
        (s) =>
          (s.province || s.area_province || "").toLowerCase() ===
          selectedProvince.toLowerCase()
      )
      .map((s) => (s.area_city || "").trim())
      .filter(Boolean)
      .forEach((c: string) => {
        const key = c.toLowerCase();
        if (!storeCitiesMap.has(key)) {
          storeCitiesMap.set(key, c);
        }
      });
    return Array.from(storeCitiesMap.values()).sort((a, b) => a.localeCompare(b));
  }, [selectedProvince, dbCities, stores]);

  const handleProvinceChange = (province: string) => {
    setSelectedProvince(province);
    setSelectedCity("");
  };

  const handleVacantDateChange = (date: string) => {
    setVacantDate(date);
    if (!isTargetDateUserOverridden) {
      setTargetFillDate(addDays(date, getUrgencyDays(urgency)));
    }
  };

  const handleUrgencyChange = (newUrgency: UrgencyTier) => {
    setUrgency(newUrgency);
    if (!isTargetDateUserOverridden) {
      setTargetFillDate(addDays(vacantDate, getUrgencyDays(newUrgency)));
    }
  };

  // Filtered stores for stationary selection
  const filteredStationaryStores = useMemo(() => {
    return stores.filter((s) => {
      if (selectedProvince) {
        const prov = (s.province || s.area_province || "").toLowerCase();
        if (prov !== selectedProvince.toLowerCase()) return false;
      }
      if (selectedCity) {
        const city = (s.area_city || "").toLowerCase();
        if (city !== selectedCity.toLowerCase()) return false;
      }
      if (storeSearch.trim()) {
        const q = storeSearch.toLowerCase();
        const matchesName = s.store_name.toLowerCase().includes(q);
        const matchesCity = (s.area_city || "").toLowerCase().includes(q);
        return matchesName || matchesCity;
      }
      return true;
    });
  }, [stores, selectedProvince, selectedCity, storeSearch]);

  // Roving Island Group Validation
  const rovingIslandGroups = useMemo(() => {
    const set = new Set<string>();
    selectedRovingStores.forEach((s) => {
      if (s.island_group) set.add(s.island_group);
    });
    return Array.from(set);
  }, [selectedRovingStores]);

  const rovingIslandGroupError = useMemo(() => {
    if (workforceType !== "roving") return null;
    if (rovingIslandGroups.length > 1) {
      return `Coverage Group cannot span multiple island groups (${rovingIslandGroups.join(
        " + "
      )}). Create separate HC Requests per island group.`;
    }
    return null;
  }, [workforceType, rovingIslandGroups]);

  // In-flight pending request checks for selected store
  const storePendingRequests = useMemo(() => {
    if (!selectedStore) return [];
    const targetName = selectedStore.store_name.trim().toLowerCase();
    const targetId = selectedStore.id;
    return recentRequests.filter((r) => {
      const matchStore =
        r.store_id === targetId ||
        (r.store_name_snapshot || "").trim().toLowerCase() === targetName;
      if (!matchStore) return false;
      const st = (r.status || "").toLowerCase();
      return (
        st === "pending" ||
        st === "pending_approval" ||
        st === "pending_om_approval" ||
        st === "under_review" ||
        st === "pending_head_admin_approval"
      );
    });
  }, [selectedStore, recentRequests]);

  // Exact duplicate candidate check
  const duplicateCandidate = useMemo(() => {
    if (workforceType !== "stationary" || !selectedStore || !selectedPositionId) {
      return null;
    }
    const targetName = selectedStore.store_name.trim().toLowerCase();
    return recentRequests.find((r) => {
      const sameStore =
        r.store_id === selectedStore.id ||
        (r.store_name_snapshot || "").trim().toLowerCase() === targetName;
      const samePos = r.position_id === selectedPositionId;
      const sameHc = Number(r.headcount_needed) === headcountNeeded;
      const sameEmp =
        (r.employment_type || "").toLowerCase() === workforceType.toLowerCase();
      const sameDate = r.vacant_date === vacantDate;
      return sameStore && samePos && sameHc && sameEmp && sameDate;
    });
  }, [
    workforceType,
    selectedStore,
    selectedPositionId,
    headcountNeeded,
    vacantDate,
    recentRequests,
  ]);

  // Target Date before Vacant Date validation
  const isDateOrderInvalid = useMemo(() => {
    if (requestType === "HC Reduction") return false;
    if (!vacantDate || !targetFillDate) return false;
    return targetFillDate < vacantDate;
  }, [requestType, vacantDate, targetFillDate]);

  // Selected position details
  const selectedPosition = useMemo(() => {
    return positions.find((p) => p.id === selectedPositionId);
  }, [positions, selectedPositionId]);

  // Validation logic before moving to Review
  const handleProceedToReview = () => {
    setValidationError(null);

    if (isRecruitmentFreezeActive) {
      setValidationError("Recruitment freeze is active. Submissions are temporarily blocked.");
      return;
    }

    if (!selectedAccountId) {
      setValidationError("Please select an operational account.");
      return;
    }

    if (workforceType === "stationary") {
      if (!selectedStore) {
        setValidationError("Please select an active target store for stationary deployment.");
        return;
      }
    } else if (workforceType === "roving") {
      if (selectedRovingStores.length < 2) {
        setValidationError("Roving workforce requires selecting at least 2 stores.");
        return;
      }
      if (selectedRovingStores.length > 20) {
        setValidationError("A maximum of 20 stores can be selected for roving deployment.");
        return;
      }
      if (rovingIslandGroupError) {
        setValidationError(rovingIslandGroupError);
        return;
      }
    } else {
      setValidationError("Floating workforce is reserved for a future phase.");
      return;
    }

    if (!selectedPositionId) {
      setValidationError("Please select a target position.");
      return;
    }

    if (headcountNeeded < 1) {
      setValidationError("Headcount needed must be at least 1.");
      return;
    }

    if (requestType !== "HC Reduction") {
      if (!vacantDate) {
        setValidationError("Vacant Date is required.");
        return;
      }
      if (!targetFillDate) {
        setValidationError("Target Fill Date is required.");
        return;
      }
      if (isDateOrderInvalid) {
        setValidationError("Target Fill Date cannot precede Vacant Date.");
        return;
      }
    }

    // Mandatory Operational Justification (ADR-003: minimum 20 characters for all requests)
    if (reason.trim().length < 20) {
      setValidationError("Operational justification is mandatory (minimum 20 characters).");
      return;
    }

    setCurrentStep("review");
  };

  // Submit Handler
  const handleFinalSubmit = () => {
    setSubmissionError(null);

    const employmentTypeFormatted =
      workforceType === "stationary"
        ? "Stationary"
        : workforceType === "roving"
        ? "Roving"
        : "Floating";

    const payload: SubmitHeadcountRequestInput = {
      account_id: selectedAccountId,
      account_name: selectedAccountName || undefined,
      position_id: selectedPositionId,
      position_name: selectedPosition?.position_name || undefined,
      workforce_type: workforceType,
      employment_type: employmentTypeFormatted,
      request_type: requestType,
      headcount_needed: headcountNeeded,
      reason: reason.trim(),
    };

    if (requestType !== "HC Reduction") {
      payload.vacant_date = vacantDate || null;
      payload.target_fill_date = targetFillDate || null;
      payload.urgency = urgency;
    }

    if (workforceType === "stationary" && selectedStore) {
      payload.store_id = selectedStore.id;
      payload.store_name = selectedStore.store_name;
      payload.area_province =
        selectedStore.province || selectedStore.area_province || selectedProvince || null;
      payload.area_city = selectedStore.area_city || selectedCity || null;
    } else if (workforceType === "roving") {
      payload.stores = selectedRovingStores.map((s) => ({
        is_new_store: false,
        store_id: s.id,
        store_name: s.store_name,
        area_province: s.area_province || s.province || "",
        area_city: s.area_city || "",
        island_group: s.island_group || undefined,
      }));
      payload.store_ids = selectedRovingStores.map((s) => s.id);
    }

    submitMutation.mutate(payload, {
      onSuccess: (data) => {
        onSuccess?.(data);
        onClose();
      },
      onError: (err) => {
        setSubmissionError(
          err.message || "Failed to submit headcount request. Please try again."
        );
      },
    });
  };

  const isFormDirty = Boolean(
    reason.trim() ||
      (!lockedStore && selectedStore) ||
      selectedRovingStores.length > 0 ||
      customPositionId ||
      headcountNeeded !== 1
  );

  return (
    <>
      <Modal
        isOpen={true}
        onClose={onClose}
        title={
          <span className="flex items-center gap-2">
            <span>
              {lockedWorkforceType === "roving" ? "Request Roving Headcount" : "Request Headcount"}
            </span>
            <span className="inline-flex items-center rounded bg-surface-muted px-2 py-0.5 text-[11px] font-semibold text-text-primary border border-border-default">
              {lockedWorkforceType === "roving"
                ? "Roving (Existing Stores)"
                : lockedStore
                ? "Stationary (Store Locked)"
                : "Requisition"}
            </span>
          </span>
        }
        subtitle={
          currentStep === "form"
            ? "Step 1 of 2: Requisition Details"
            : "Step 2 of 2: Review & Submit"
        }
        icon={UsersRound}
        maxWidthClass="max-w-3xl"
        disableBackdropClick={submitMutation.isPending}
        isSubmitting={submitMutation.isPending}
        isDirty={isFormDirty}
      >
        <div className="flex-1 overflow-y-auto p-6 space-y-6 max-h-[75vh]">
          {/* Recruitment Freeze Banner */}
          {isRecruitmentFreezeActive && (
            <div className="flex items-start gap-3 rounded-lg border border-border-default bg-surface-muted p-4 text-xs text-text-primary">
              <ShieldAlert className="h-5 w-5 shrink-0 text-text-secondary mt-0.5" />
              <div>
                <p className="font-semibold text-sm">Recruitment Freeze Active</p>
                <p className="mt-0.5 text-text-secondary">
                  System governance has locked headcount requisitions under a global freeze. You can explore the options, but submission is blocked.
                </p>
              </div>
            </div>
          )}

          {/* Validation & Error Alert */}
          {validationError && (
            <div className="flex items-start gap-3 rounded-lg border border-[var(--border-subtle)] bg-[var(--surface-sunken)] p-3.5 text-xs text-[var(--foreground)]">
              <AlertTriangle className="h-4 w-4 shrink-0 text-[var(--text-muted)] mt-0.5" />
              <span>{validationError}</span>
            </div>
          )}

          {submissionError && (
            <div className="flex items-start gap-3 rounded-lg border border-[var(--danger)]/30 bg-[var(--danger-bg)] p-3.5 text-xs text-[var(--danger)]">
              <AlertCircle className="h-4 w-4 shrink-0 text-[var(--danger)] mt-0.5" />
              <span>{submissionError}</span>
            </div>
          )}

          {/* ========================================================================= */}
          {/* STEP 1: FORM DETAILS */}
          {/* ========================================================================= */}
          {currentStep === "form" && (
            <div className="space-y-6">
              {/* Account Context */}
              <div className="rounded-lg border border-border-default bg-surface-muted p-4 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                    <Building2 className="h-4 w-4 text-text-muted" />
                    Target Operational Account
                  </span>
                  {selectedAccountName && (
                    <span className="text-xs font-semibold text-brand-600">
                      Active Plantilla Scope
                    </span>
                  )}
                </div>
                {propAccountId ? (
                  <div className="flex items-center gap-2 text-sm font-semibold text-text-primary">
                    <span>{selectedAccountName || propAccountName || "Scoped Account"}</span>
                    <span className="inline-flex items-center rounded-md bg-brand-50 px-2 py-0.5 text-xs font-semibold text-brand-700 ring-1 ring-inset ring-brand-700/10">
                      Scoped Account
                    </span>
                  </div>
                ) : (
                  <select
                    value={selectedAccountId}
                    onChange={(e) => {
                      const id = e.target.value;
                      setSelectedAccountId(id);
                      const acct = availableAccounts.find((a) => a.id === id);
                      setSelectedAccountName(acct?.name || "");
                      setSelectedStore(null);
                      setSelectedRovingStores([]);
                    }}
                    className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                  >
                    {availableAccounts.map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.name}
                      </option>
                    ))}
                  </select>
                )}
              </div>

              {/* SECTION 1: WORKFORCE TYPE TOGGLE (Hidden when locked by entry point) */}
              {!lockedWorkforceType && (
                <div className="space-y-2">
                  <label className="text-xs font-semibold text-text-secondary">
                    Workforce Deployment Type
                  </label>
                  <div className="grid grid-cols-3 gap-3">
                    <button
                      type="button"
                      onClick={() => {
                        setWorkforceType("stationary");
                        setValidationError(null);
                      }}
                      className={`flex flex-col items-start gap-1 rounded-lg border p-3.5 text-left transition-all ${
                        workforceType === "stationary"
                          ? "border-brand-primary bg-surface-selected text-text-primary shadow-xs ring-1 ring-brand-primary"
                          : "border-border-default bg-surface-base text-text-secondary hover:border-border-subtle hover:bg-surface-hover hover:text-text-primary"
                      }`}
                    >
                      <div className="flex items-center gap-1.5 font-semibold text-sm">
                        <MapPin className="h-4 w-4 text-brand-primary" />
                        <span>Stationary</span>
                      </div>
                      <p className="text-xs text-text-secondary">Single dedicated store assignment</p>
                    </button>

                    <button
                      type="button"
                      onClick={() => {
                        setWorkforceType("roving");
                        setValidationError(null);
                      }}
                      className={`flex flex-col items-start gap-1 rounded-lg border p-3.5 text-left transition-all ${
                        workforceType === "roving"
                          ? "border-brand-primary bg-surface-selected text-text-primary shadow-xs ring-1 ring-brand-primary"
                          : "border-border-default bg-surface-base text-text-secondary hover:border-border-subtle hover:bg-surface-hover hover:text-text-primary"
                      }`}
                    >
                      <div className="flex items-center gap-1.5 font-semibold text-sm">
                        <Layers className="h-4 w-4 text-brand-primary" />
                        <span>Roving</span>
                      </div>
                      <p className="text-xs text-text-secondary">Multi-store coverage cluster (2–20)</p>
                    </button>

                    <div
                      title="Floating workforce is reserved for a future phase"
                      className="flex flex-col items-start gap-1 rounded-lg border border-border-default bg-surface-muted/60 p-3.5 text-left opacity-50 cursor-not-allowed"
                    >
                      <div className="flex items-center gap-1.5 font-semibold text-sm text-text-muted">
                        <Globe2 className="h-4 w-4" />
                        <span>Floating</span>
                      </div>
                      <p className="text-[11px] text-text-muted italic">Phase 2 Reserved</p>
                    </div>
                  </div>
                </div>
              )}

              {/* SECTION 2: STORE SELECTION */}
              {workforceType === "stationary" ? (
                /* Stationary: Province -> City -> Store */
                <div className="space-y-3 rounded-lg border border-border-default bg-surface-base p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                      <MapPin className="h-4 w-4 text-brand-600" />
                      Target Store & Area
                    </span>
                    {selectedStore && !lockedStore && (
                      <button
                        type="button"
                        onClick={() => {
                          setSelectedStore(null);
                        }}
                        className="text-xs font-semibold text-brand-600 hover:text-brand-700"
                      >
                        Change Store
                      </button>
                    )}
                  </div>

                  {selectedStore ? (
                    /* Store Verification Card */
                    <div className="flex items-start justify-between rounded-lg border border-[var(--border-subtle)] bg-[var(--surface-sunken)] p-4">
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <CheckCircle2 className="h-4 w-4 text-[var(--foreground)]" />
                          <h4 className="font-semibold text-sm text-[var(--foreground)]">
                            {selectedStore.store_name}
                          </h4>
                          {selectedStore.island_group && (
                            <span className="rounded bg-[var(--surface-base)] px-1.5 py-0.5 text-[10px] font-semibold font-mono text-[var(--foreground)] border border-[var(--border-subtle)]">
                              {selectedStore.island_group}
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-[var(--text-muted)]">
                          {[selectedStore.area_city, selectedStore.province || selectedStore.area_province]
                            .filter(Boolean)
                            .join(", ") || "Active Store"}
                        </p>
                      </div>
                      <span className="rounded-full bg-[var(--surface-base)] px-2.5 py-1 text-[11px] font-semibold text-[var(--foreground)] border border-[var(--border-subtle)]">
                        {lockedStore ? "Store View Locked" : "Verified Store"}
                      </span>
                    </div>
                  ) : (
                    <div className="space-y-3">
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <div>
                          <label className="text-xs font-medium text-text-secondary mb-1 block">
                            Province Filter
                          </label>
                          <select
                            value={selectedProvince}
                            onChange={(e) => handleProvinceChange(e.target.value)}
                            className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                          >
                            <option value="">All Provinces</option>
                            {provinces.map((prov) => (
                              <option key={prov} value={prov}>
                                {prov}
                              </option>
                            ))}
                          </select>
                        </div>

                        <div>
                          <label className="text-xs font-medium text-text-secondary mb-1 block">
                            City / Municipality
                          </label>
                          <select
                            value={selectedCity}
                            onChange={(e) => setSelectedCity(e.target.value)}
                            disabled={!selectedProvince}
                            className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500 disabled:opacity-50"
                          >
                            <option value="">All Cities</option>
                            {cities.map((city) => (
                              <option key={city} value={city}>
                                {city}
                              </option>
                            ))}
                          </select>
                        </div>
                      </div>

                      {/* Store Search / Picker */}
                      <div>
                        <div className="relative mb-2">
                          <Search className="absolute left-3 top-2.5 h-4 w-4 text-text-muted" />
                          <input
                            type="text"
                            placeholder="Search store by name..."
                            value={storeSearch}
                            onChange={(e) => setStoreSearch(e.target.value)}
                            className="w-full rounded-md border border-border-default bg-surface-muted pl-9 pr-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                          />
                        </div>

                        <div className="max-h-56 overflow-y-auto rounded-md border border-border-default bg-surface-base divide-y divide-border-subtle">
                          {filteredStationaryStores.length === 0 ? (
                            isLoadingMasterData ? (
                              <div className="p-4 text-center text-xs text-text-muted">
                                Loading stores...
                              </div>
                            ) : (
                              <div className="p-4 bg-[var(--surface-sunken)] space-y-2.5 text-xs text-[var(--foreground)]">
                                <p className="text-[var(--text-muted)]">
                                  Store not found under this account. Use{" "}
                                  <strong className="text-[var(--foreground)]">+ Request New Store</strong>{" "}
                                  in the Plantilla header to register an opening store.
                                </p>
                                {(storeSearch || selectedProvince || selectedCity) && (
                                  <button
                                    type="button"
                                    onClick={() => {
                                      setStoreSearch("");
                                      setSelectedCity("");
                                      setSelectedProvince("");
                                    }}
                                    className="rounded-md border border-[var(--border-subtle)] bg-[var(--surface-base)] px-2.5 py-1.5 text-xs font-medium text-[var(--foreground)] hover:bg-[var(--surface-hover)] transition-colors"
                                  >
                                    Clear Filters
                                  </button>
                                )}
                              </div>
                            )
                          ) : (
                            filteredStationaryStores.map((s) => (
                              <button
                                key={s.id}
                                type="button"
                                onClick={() => setSelectedStore(s)}
                                className="w-full px-3.5 py-2.5 text-left text-xs hover:bg-surface-hover flex items-center justify-between transition-colors"
                              >
                                <div>
                                  <div className="font-semibold text-text-primary">
                                    {s.store_name}
                                  </div>
                                  <div className="text-[11px] text-text-muted">
                                    {[s.area_city, s.province || s.area_province]
                                      .filter(Boolean)
                                      .join(", ")}
                                  </div>
                                </div>
                                {s.island_group && (
                                  <span className="rounded bg-[var(--surface-sunken)] px-1.5 py-0.5 text-[10px] font-mono font-medium text-[var(--foreground)] border border-[var(--border-subtle)]">
                                    {s.island_group}
                                  </span>
                                )}
                              </button>
                            ))
                          )}
                        </div>
                      </div>
                    </div>
                  )}

                  {/* Warning: In-flight requests for this store */}
                  {selectedStore && storePendingRequests.length > 0 && (
                    <div className="flex items-start gap-2.5 rounded-lg border border-[var(--border-subtle)] bg-[var(--surface-sunken)] p-3 text-xs text-[var(--foreground)]">
                      <AlertTriangle className="h-4 w-4 shrink-0 text-[var(--text-muted)] mt-0.5" />
                      <div>
                        <span className="font-semibold">Pending Requests Notice: </span>
                        {storePendingRequests.length} pending request(s) already submitted for{" "}
                        <strong>{selectedStore.store_name}</strong>.
                      </div>
                    </div>
                  )}

                  {/* Warning: Exact Duplicate Candidate */}
                  {duplicateCandidate && (
                    <div className="flex items-start gap-2.5 rounded-lg border border-[var(--border-subtle)] bg-[var(--surface-sunken)] p-3 text-xs text-[var(--foreground)]">
                      <AlertTriangle className="h-4 w-4 shrink-0 text-[var(--text-muted)] mt-0.5" />
                      <div>
                        <span className="font-semibold">Potential Duplicate Warning: </span>
                        A similar recent request exists for this store, position,{" "}
                        {headcountNeeded} headcount, and vacant date.
                      </div>
                    </div>
                  )}
                </div>
              ) : (
                /* Roving: Existing Multi-Store Chip Picker */
                <div className="space-y-3 rounded-lg border border-border-default bg-surface-base p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                      <Layers className="h-4 w-4 text-brand-600" />
                      Selected Roving Stores ({selectedRovingStores.length}/20)
                    </span>
                    <span className="text-xs text-text-muted">Min: 2 existing stores</span>
                  </div>

                  {/* Island Group Violation Alert */}
                  {rovingIslandGroupError && (
                    <div className="flex items-start gap-2.5 rounded-lg border border-[var(--danger)]/30 bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger)]">
                      <ShieldAlert className="h-4 w-4 shrink-0 text-[var(--danger)] mt-0.5" />
                      <div>
                        <span className="font-semibold">Island Group Restriction (Hard Block): </span>
                        {rovingIslandGroupError}
                      </div>
                    </div>
                  )}

                  {/* Selected Chips */}
                  {selectedRovingStores.length > 0 ? (
                    <div className="flex flex-wrap gap-2 p-2 rounded-md bg-surface-muted border border-border-default">
                      {selectedRovingStores.map((s) => (
                        <span
                          key={s.id}
                          className="inline-flex items-center gap-1.5 rounded-md border bg-surface-base border-border-default pl-2.5 pr-1.5 py-1 text-xs font-medium text-text-primary shadow-xs"
                        >
                          <span>{s.store_name}</span>
                          <span className="text-[10px] font-mono text-text-muted">
                            {[s.area_city, s.island_group].filter(Boolean).join(" • ")}
                          </span>
                          <button
                            type="button"
                            onClick={() =>
                              setSelectedRovingStores((prev) =>
                                prev.filter((item) => item.id !== s.id)
                              )
                            }
                            className="rounded-full p-0.5 text-text-muted hover:bg-surface-hover hover:text-text-primary"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </span>
                      ))}
                    </div>
                  ) : (
                    <div className="rounded-md border border-dashed border-border-default p-4 text-center text-xs text-text-muted">
                      No stores selected yet. Pick between 2 and 20 existing stores below sharing the same island group. Need to open an unlisted store? Use <strong>+ Request New Store</strong> in the Plantilla header.
                    </div>
                  )}

                  {/* Store Multi-picker list */}
                  <div className="space-y-2 pt-2">
                    <div className="relative">
                      <Search className="absolute left-3 top-2.5 h-4 w-4 text-text-muted" />
                      <input
                        type="text"
                        placeholder="Search existing stores across all cities..."
                        value={rovingSearch}
                        onChange={(e) => setRovingSearch(e.target.value)}
                        className="w-full rounded-md border border-border-default bg-surface-muted pl-9 pr-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                      />
                    </div>

                    <div className="max-h-44 overflow-y-auto rounded-md border border-border-default bg-surface-base divide-y divide-border-subtle">
                      {stores
                        .filter((s) => {
                          if (!rovingSearch.trim()) return true;
                          const q = rovingSearch.toLowerCase();
                          return (
                            s.store_name.toLowerCase().includes(q) ||
                            (s.area_city || "").toLowerCase().includes(q) ||
                            (s.province || s.area_province || "").toLowerCase().includes(q)
                          );
                        })
                        .map((s) => {
                          const isSelected = selectedRovingStores.some(
                            (item) => item.id === s.id
                          );
                          return (
                            <div
                              key={s.id}
                              className={`flex items-center justify-between px-3.5 py-2 text-xs transition-colors ${
                                isSelected ? "bg-brand-50/40" : "hover:bg-surface-hover"
                              }`}
                            >
                              <div>
                                <span className="font-semibold text-text-primary">
                                  {s.store_name}
                                </span>
                                <span className="text-[11px] text-text-muted ml-2">
                                  {[s.area_city, s.province || s.area_province, s.island_group]
                                    .filter(Boolean)
                                    .join(" • ")}
                                </span>
                              </div>
                              <button
                                type="button"
                                onClick={() => {
                                  if (isSelected) {
                                    setSelectedRovingStores((prev) =>
                                      prev.filter((item) => item.id !== s.id)
                                    );
                                  } else {
                                    if (selectedRovingStores.length >= 20) return;
                                    setSelectedRovingStores((prev) => [...prev, s]);
                                  }
                                }}
                                className={`rounded px-2.5 py-1 text-xs font-semibold transition-colors ${
                                  isSelected
                                    ? "bg-[var(--danger-bg)] text-[var(--danger)] hover:opacity-90"
                                    : "bg-brand-600 text-white hover:bg-brand-700"
                                }`}
                              >
                                {isSelected ? "Remove" : "Select"}
                              </button>
                            </div>
                          );
                        })}

                      {stores.filter((s) => {
                        if (!rovingSearch.trim()) return true;
                        const q = rovingSearch.toLowerCase();
                        return (
                          s.store_name.toLowerCase().includes(q) ||
                          (s.area_city || "").toLowerCase().includes(q) ||
                          (s.province || s.area_province || "").toLowerCase().includes(q)
                        );
                      }).length === 0 && (
                        <div className="p-4 text-center text-xs text-text-muted space-y-2">
                          <p>
                            Store not found under this account. Use{" "}
                            <strong className="text-text-primary">+ Request New Store</strong> in the Plantilla header to register an opening store.
                          </p>
                          {rovingSearch.trim() && (
                            <button
                              type="button"
                              onClick={() => setRovingSearch("")}
                              className="rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-medium text-text-primary hover:bg-surface-hover transition"
                            >
                              Clear Filters
                            </button>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              )}

              {/* SECTION 3: POSITION & DEMAND DETAILS */}
              <div className="space-y-4 rounded-lg border border-border-default bg-surface-base p-4">
                <span className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                  <Sparkles className="h-4 w-4 text-brand-600" />
                  Position & Headcount
                </span>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label className="text-xs font-medium text-text-secondary mb-1 block">
                      Position Title <RequiredAsterisk />
                    </label>
                    <select
                      value={selectedPositionId}
                      onChange={(e) => setSelectedPositionId(e.target.value)}
                      className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                    >
                      {positions.map((pos) => (
                        <option key={pos.id} value={pos.id}>
                          {pos.position_name}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <label className="text-xs font-medium text-text-secondary mb-1 block">
                      Request Type <RequiredAsterisk />
                    </label>
                    <select
                      value={requestType}
                      onChange={(e) => setRequestType(e.target.value as RequestType)}
                      className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                    >
                      <option value="Additional Headcount">Additional Headcount</option>
                      <option value="Replacement">Replacement</option>
                      <option value="Reliever">Reliever</option>
                      <option value="Commando">Commando</option>
                      <option value="HC Reduction">HC Reduction</option>
                    </select>
                  </div>
                </div>

                {/* Stepper for Headcount */}
                <div className="flex items-center justify-between border-t border-border-subtle pt-3">
                  <div>
                    <div className="text-xs font-medium text-text-secondary">
                      {requestType === "HC Reduction" ? "Headcount to Reduce" : "Headcount Needed"} <RequiredAsterisk />
                    </div>
                    <div className="text-[11px] text-text-muted">
                      {requestType === "HC Reduction"
                        ? "Slots to reduce from active capacity"
                        : "Target capacity expansion for this requisition"}
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      disabled={headcountNeeded <= 1}
                      onClick={() => setHeadcountNeeded((prev) => Math.max(1, prev - 1))}
                      className="flex h-9 w-9 items-center justify-center rounded-md border border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover disabled:opacity-40 transition-colors shadow-xs"
                      aria-label="Decrease headcount"
                    >
                      <Minus className="h-4 w-4" />
                    </button>
                    <input
                      type="number"
                      min={1}
                      max={999}
                      value={headcountNeeded}
                      onChange={(e) => {
                        const val = parseInt(e.target.value, 10);
                        if (!isNaN(val) && val >= 1) {
                          setHeadcountNeeded(val);
                        }
                      }}
                      className="h-9 w-14 rounded-md border border-border-default bg-surface-muted text-center font-mono text-base font-bold text-text-primary outline-none focus:border-brand-500"
                    />
                    <button
                      type="button"
                      onClick={() => setHeadcountNeeded((prev) => prev + 1)}
                      className="flex h-9 w-9 items-center justify-center rounded-md border border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover transition-colors shadow-xs"
                      aria-label="Increase headcount"
                    >
                      <Plus className="h-4 w-4" />
                    </button>
                  </div>
                </div>
              </div>

              {/* SECTION 4: TIMELINE & URGENCY (Bypassed if HC Reduction) */}
              {requestType !== "HC Reduction" && (
                <div className="space-y-4 rounded-lg border border-border-default bg-surface-base p-4">
                  <span className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                    <Clock className="h-4 w-4 text-brand-600" />
                    Timeline & Fulfillment Urgency
                  </span>

                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div>
                      <label className="text-xs font-medium text-text-secondary mb-1 block">
                        Vacant Date <RequiredAsterisk />
                      </label>
                      <input
                        type="date"
                        value={vacantDate}
                        onChange={(e) => handleVacantDateChange(e.target.value)}
                        className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                      />
                    </div>

                    <div>
                      <label className="text-xs font-medium text-text-secondary mb-1 block">
                        Urgency Tier <RequiredAsterisk />
                      </label>
                      <select
                        value={urgency}
                        onChange={(e) => handleUrgencyChange(e.target.value as UrgencyTier)}
                        className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                      >
                        <option value="Critical">Critical (3 days)</option>
                        <option value="High">High (7 days)</option>
                        <option value="Medium">Medium (14 days)</option>
                        <option value="Low">Low (30 days)</option>
                      </select>
                    </div>

                    <div>
                      <div className="flex items-center justify-between mb-1">
                        <label className="text-xs font-medium text-text-secondary block">
                          Target Fill Date <RequiredAsterisk />
                        </label>
                        {isTargetDateUserOverridden && (
                          <button
                            type="button"
                            onClick={() => {
                              setIsTargetDateUserOverridden(false);
                              setTargetFillDate(addDays(vacantDate, getUrgencyDays(urgency)));
                            }}
                            className="text-[10px] text-brand-600 hover:text-brand-700"
                          >
                            Reset Auto
                          </button>
                        )}
                      </div>
                      <input
                        type="date"
                        value={targetFillDate}
                        onChange={(e) => {
                          setTargetFillDate(e.target.value);
                          setIsTargetDateUserOverridden(true);
                        }}
                        className={`w-full rounded-md border bg-surface-muted px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500 ${
                          isDateOrderInvalid ? "border-[var(--danger)]" : "border-border-default"
                        }`}
                      />
                      {isDateOrderInvalid && (
                        <p className="mt-1 text-[11px] text-[var(--danger)]">
                          Target date cannot precede vacant date
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              )}

              {/* SECTION 5: OPERATIONAL JUSTIFICATION */}
              <div className="space-y-2 rounded-lg border border-border-default bg-surface-base p-4">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-text-secondary flex items-center gap-1">
                    Operational Justification <RequiredAsterisk />
                  </span>
                  <span className="text-xs text-text-muted">
                    {reason.length}/500 chars{" "}
                    <span
                      className={
                        reason.trim().length >= 20
                          ? "text-text-success font-semibold"
                          : "text-text-danger font-semibold"
                      }
                    >
                      ({reason.trim().length}/20 chars min)
                    </span>
                  </span>
                </div>
                <textarea
                  rows={3}
                  maxLength={500}
                  placeholder="Detail the operational justification, store coverage, expansion rationale, or business demand (minimum 20 characters required)..."
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  className="w-full rounded-md border border-border-default bg-surface-muted p-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors resize-none"
                />
              </div>
            </div>
          )}

          {/* ========================================================================= */}
          {/* STEP 2: REVIEW CONFIRMATION STEP */}
          {/* ========================================================================= */}
          {currentStep === "review" && (
            <div className="space-y-6">
              <div className="rounded-lg border border-border-default bg-surface-selected p-4 text-xs text-text-primary">
                <h4 className="font-semibold text-sm flex items-center gap-2">
                  <Sparkles className="h-4 w-4 text-brand-primary" />
                  Review Headcount Requisition
                </h4>
                <p className="mt-0.5 text-text-secondary">
                  Please confirm the requisition parameters before submitting to the approval pipeline.
                </p>
              </div>

              {/* Requisition Summary Card */}
              <div className="rounded-xl border border-border-default bg-surface-base overflow-hidden divide-y divide-border-subtle shadow-xs">
                <div className="p-4 grid grid-cols-2 gap-4">
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted">Operational Account</span>
                    <div className="text-sm font-bold text-text-primary mt-0.5">{selectedAccountName}</div>
                  </div>
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted">Deployment Mode</span>
                    <div className="text-sm font-semibold text-text-primary mt-0.5 capitalize flex items-center gap-1.5">
                      {workforceType === "stationary" ? (
                        <MapPin className="h-3.5 w-3.5 text-brand-600" />
                      ) : (
                        <Layers className="h-3.5 w-3.5 text-brand-600" />
                      )}
                      <span>{workforceType} Deployment</span>
                    </div>
                  </div>
                </div>

                <div className="p-4">
                  <span className="text-[11px] font-semibold text-text-muted">
                    {workforceType === "stationary" ? "Assigned Store" : `Roving Cluster (${selectedRovingStores.length} stores)`}
                  </span>
                  {workforceType === "stationary" ? (
                    <div className="mt-1 flex items-center justify-between">
                      <span className="font-bold text-sm text-text-primary">
                        {selectedStore?.store_name}
                      </span>
                      <span className="text-xs text-text-muted">
                        {[selectedStore?.area_city, selectedStore?.province || selectedStore?.area_province]
                          .filter(Boolean)
                          .join(", ")}
                      </span>
                    </div>
                  ) : (
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {selectedRovingStores.map((s) => (
                        <span
                          key={s.id}
                          className="inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium border bg-surface-muted border-border-default text-text-secondary"
                        >
                          <span>{s.store_name}</span>
                          <span className="text-[10px] text-text-muted">
                            • {[s.area_city, s.area_province || s.province].filter(Boolean).join(", ")}
                          </span>
                        </span>
                      ))}
                    </div>
                  )}
                </div>

                <div className="p-4 grid grid-cols-3 gap-4">
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted">Position</span>
                    <div className="text-sm font-bold text-text-primary mt-0.5">
                      {selectedPosition?.position_name}
                    </div>
                  </div>
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted">Request Type</span>
                    <div className="text-sm font-semibold text-text-primary mt-0.5">
                      {requestType}
                    </div>
                  </div>
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted">Headcount</span>
                    <div className="text-sm font-mono font-bold text-brand-700 mt-0.5">
                      {headcountNeeded} {headcountNeeded === 1 ? "Slot" : "Slots"}
                    </div>
                  </div>
                </div>

                {requestType !== "HC Reduction" && (
                  <div className="p-4 grid grid-cols-3 gap-4">
                    <div>
                      <span className="text-[11px] font-semibold text-text-muted">Vacant Date</span>
                      <div className="text-sm font-medium text-text-primary mt-0.5">{vacantDate}</div>
                    </div>
                    <div>
                      <span className="text-[11px] font-semibold text-text-muted">Urgency Tier</span>
                      <div className="text-sm font-semibold text-text-primary mt-0.5">{urgency}</div>
                    </div>
                    <div>
                      <span className="text-[11px] font-semibold text-text-muted">Target Fill Date</span>
                      <div className="text-sm font-bold text-text-primary mt-0.5">{targetFillDate}</div>
                    </div>
                  </div>
                )}

                <div className="p-4">
                  <span className="text-[11px] font-semibold text-text-muted">Operational Justification</span>
                  <div className="text-xs text-text-secondary mt-1 italic whitespace-pre-wrap">
                    {reason.trim() || "No additional justification notes provided."}
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-between border-t border-border-default px-6 py-4 shrink-0 bg-surface-muted/40">
          {currentStep === "form" ? (
            <>
              <button
                type="button"
                onClick={onClose}
                disabled={submitMutation.isPending}
                className="rounded-md border border-border-default bg-surface-base px-4 py-2 text-sm font-medium text-text-secondary hover:bg-surface-hover transition-colors shadow-xs disabled:opacity-40"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleProceedToReview}
                disabled={isRecruitmentFreezeActive}
                className="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-700 transition-colors shadow-xs disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <span>Review Request</span>
                <ArrowRight className="h-4 w-4" />
              </button>
            </>
          ) : (
            <>
              <button
                type="button"
                onClick={() => setCurrentStep("form")}
                disabled={submitMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-4 py-2 text-sm font-medium text-text-secondary hover:bg-surface-hover transition-colors shadow-xs disabled:opacity-40"
              >
                <ArrowLeft className="h-4 w-4" />
                <span>Back to Edit</span>
              </button>
              <button
                type="button"
                onClick={handleFinalSubmit}
                disabled={submitMutation.isPending}
                className="inline-flex items-center gap-2 rounded-md bg-brand-600 px-5 py-2 text-sm font-semibold text-white hover:bg-brand-700 transition-colors shadow-xs disabled:opacity-50"
              >
                {submitMutation.isPending ? (
                  <>
                    <div className="h-4 w-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    <span>Submitting Request...</span>
                  </>
                ) : (
                  <span>Confirm & Submit Request</span>
                )}
              </button>
            </>
          )}
        </div>
      </Modal>
    </>
  );
}
