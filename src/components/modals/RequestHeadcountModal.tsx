"use client";

import { useState, useEffect, useMemo } from "react";
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
import { createClient } from "@/lib/supabase/client";
import {
  useSubmitHeadcountRequest,
  type SubmitHeadcountRequestInput,
  type SubmitHeadcountRequestResult,
} from "@/lib/queries/requests";

export interface RequestHeadcountModalProps {
  isOpen: boolean;
  onClose: () => void;
  accountId?: string | null;
  accountName?: string | null;
  initialStoreId?: string | null;
  initialStoreName?: string | null;
  initialProvince?: string | null;
  initialCity?: string | null;
  onSuccess?: (result?: SubmitHeadcountRequestResult) => void;
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
}

interface PositionItem {
  id: string;
  position_name: string;
  position_code?: string | null;
}

interface RecentRequestItem {
  id: string;
  store_id?: string | null;
  store_name_snapshot?: string | null;
  position_id?: string | null;
  position_name_snapshot?: string | null;
  headcount_needed?: number;
  employment_type?: string | null;
  vacant_date?: string | null;
  status?: string | null;
  request_type?: string | null;
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
  onSuccess,
}: RequestHeadcountModalDialogProps) {
  const submitMutation = useSubmitHeadcountRequest();

  // Step state: "form" | "review"
  const [currentStep, setCurrentStep] = useState<"form" | "review">("form");

  // Account State
  const [selectedAccountId, setSelectedAccountId] = useState<string>(propAccountId || "");
  const [selectedAccountName, setSelectedAccountName] = useState<string>(propAccountName || "");
  const [availableAccounts, setAvailableAccounts] = useState<{ id: string; name: string }[]>([]);

  // Workforce Type
  const [workforceType, setWorkforceType] = useState<WorkforceType>("stationary");

  // Master Data & Options
  const [isLoadingMasterData, setIsLoadingMasterData] = useState(false);
  const [stores, setStores] = useState<StoreItem[]>([]);
  const [positions, setPositions] = useState<PositionItem[]>([]);
  const [provinces, setProvinces] = useState<string[]>([]);
  const [cities, setCities] = useState<string[]>([]);
  const [recentRequests, setRecentRequests] = useState<RecentRequestItem[]>([]);
  const [isRecruitmentFreezeActive, setIsRecruitmentFreezeActive] = useState(false);

  // Form Fields - Stationary
  const [selectedProvince, setSelectedProvince] = useState<string>(initialProvince || "");
  const [selectedCity, setSelectedCity] = useState<string>(initialCity || "");
  const [selectedStore, setSelectedStore] = useState<StoreItem | null>(() => {
    if (initialStoreId) {
      return {
        id: initialStoreId,
        store_name: initialStoreName || "Preselected Store",
        province: initialProvince || null,
        area_city: initialCity || null,
      };
    }
    return null;
  });
  const [storeSearch, setStoreSearch] = useState<string>("");

  // Form Fields - Roving
  const [selectedRovingStores, setSelectedRovingStores] = useState<StoreItem[]>([]);
  const [rovingSearch, setRovingSearch] = useState<string>("");

  // Form Fields - Position & Quota
  const [selectedPositionId, setSelectedPositionId] = useState<string>("");
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

  // Load available accounts if accountId is not provided
  useEffect(() => {
    if (propAccountId) return;
    const supabase = createClient();
    async function loadAccounts() {
      try {
        const { data, error } = await supabase
          .from("accounts")
          .select("id, account_name")
          .eq("is_active", true)
          .order("account_name");
        if (!error && data) {
          const mapped = data.map((d) => ({ id: d.id, name: d.account_name }));
          setAvailableAccounts(mapped);
          if (mapped.length > 0) {
            setSelectedAccountId((curr) => curr || mapped[0].id);
            setSelectedAccountName((curr) => curr || mapped[0].name);
          }
        }
      } catch {
        // Safe fallback
      }
    }
    loadAccounts();
  }, [propAccountId]);

  // Load Master Data (stores, positions, locations, freeze, recent requests) for account
  useEffect(() => {
    if (!selectedAccountId) return;
    const supabase = createClient();
    let isMounted = true;

    async function loadAccountData() {
      setIsLoadingMasterData(true);
      try {
        // 1. Fetch stores
        const storesQuery = supabase
          .from("stores")
          .select("id, store_name, area_city, area_province, province, island_group, is_active, account_id")
          .eq("account_id", selectedAccountId)
          .eq("is_active", true)
          .order("store_name");

        // 2. Fetch positions
        const positionsRpc = supabase.rpc("get_positions_by_account", {
          p_account_id: selectedAccountId,
        });

        // 3. Fetch provinces
        const provincesQuery = supabase
          .from("ref_locations")
          .select("province")
          .eq("is_active", true)
          .order("province", { ascending: true });

        // 4. Check recruitment freeze
        const freezeRpc = supabase.rpc("fn_check_freeze_active", {
          p_freeze_key: "recruitment_freeze",
        });

        // 5. Fetch recent requests for duplicate warning
        const recentRequestsQuery = supabase
          .from("headcount_requests")
          .select("id, store_id, store_name_snapshot, position_id, position_name_snapshot, headcount_needed, employment_type, vacant_date, status, request_type")
          .eq("account_id", selectedAccountId)
          .order("created_at", { ascending: false })
          .limit(30);

        const [storesRes, positionsRes, provincesRes, freezeRes, recentRes] =
          await Promise.allSettled([
            storesQuery,
            positionsRpc,
            provincesQuery,
            freezeRpc,
            recentRequestsQuery,
          ]);

        if (!isMounted) return;

        // Process Stores
        let loadedStores: StoreItem[] = [];
        if (storesRes.status === "fulfilled" && !storesRes.value.error && storesRes.value.data) {
          loadedStores = storesRes.value.data as StoreItem[];
          setStores(loadedStores);

          if (initialStoreId) {
            const found = loadedStores.find((s) => s.id === initialStoreId);
            if (found) {
              setSelectedStore(found);
              const prov = found.province || found.area_province || "";
              const city = found.area_city || "";
              if (prov) setSelectedProvince(prov);
              if (city) setSelectedCity(city);
            }
          }
        }

        // Process Positions
        if (positionsRes.status === "fulfilled" && !positionsRes.value.error && positionsRes.value.data) {
          const rows = positionsRes.value.data as {
            position_id: string;
            position_name: string;
            position_code?: string;
          }[];
          const posList = rows.map((r) => ({
            id: r.position_id,
            position_name: r.position_name,
            position_code: r.position_code,
          }));
          setPositions(posList);
          setSelectedPositionId((curr) => curr || (posList.length > 0 ? posList[0].id : ""));
        } else {
          // Fallback to table query if RPC is empty or fails
          const { data: posData } = await supabase
            .from("positions")
            .select("id, position_name")
            .eq("is_active", true)
            .order("position_name");
          if (posData && posData.length > 0) {
            const posList = posData.map((p) => ({
              id: p.id,
              position_name: p.position_name,
            }));
            setPositions(posList);
            setSelectedPositionId((curr) => curr || posList[0].id);
          }
        }

        // Process Provinces
        if (provincesRes.status === "fulfilled" && !provincesRes.value.error && provincesRes.value.data) {
          const rawProvinces = provincesRes.value.data.map(
            (p: { province: string | null }) => p.province?.trim() || ""
          );
          const uniqueProvinces = Array.from(new Set(rawProvinces.filter(Boolean))).sort();
          const mmIndex = uniqueProvinces.findIndex(
            (p) => p.toLowerCase() === "metro manila"
          );
          if (mmIndex > 0) {
            const mm = uniqueProvinces.splice(mmIndex, 1)[0];
            uniqueProvinces.unshift(mm);
          }
          setProvinces(uniqueProvinces);
        } else {
          const storeProvinces = Array.from(
            new Set(
              loadedStores
                .map((s) => s.province || s.area_province || "")
                .filter(Boolean)
            )
          ).sort();
          setProvinces(storeProvinces);
        }

        // Process Freeze
        if (freezeRes.status === "fulfilled" && !freezeRes.value.error) {
          setIsRecruitmentFreezeActive(freezeRes.value.data === true);
        }

        // Process Recent Requests
        if (recentRes.status === "fulfilled" && !recentRes.value.error && recentRes.value.data) {
          setRecentRequests(recentRes.value.data as RecentRequestItem[]);
        }
      } catch {
        // Non-blocking catch
      } finally {
        if (isMounted) setIsLoadingMasterData(false);
      }
    }

    loadAccountData();

    return () => {
      isMounted = false;
    };
  }, [selectedAccountId, initialStoreId]);

  // Load Cities when Province changes
  useEffect(() => {
    if (!selectedProvince) {
      return;
    }
    const supabase = createClient();
    let isMounted = true;

    async function loadCities() {
      try {
        const { data, error } = await supabase
          .from("ref_locations")
          .select("city")
          .eq("province", selectedProvince)
          .eq("is_active", true)
          .order("city", { ascending: true });

        if (!isMounted) return;

        if (!error && data && data.length > 0) {
          const rawCities = data.map((c: { city: string | null }) => c.city?.trim() || "");
          const uniqueCities = Array.from(new Set(rawCities.filter(Boolean))).sort();
          setCities(uniqueCities);
        } else {
          const storeCities = Array.from(
            new Set(
              stores
                .filter(
                  (s) =>
                    (s.province || s.area_province || "").toLowerCase() ===
                    selectedProvince.toLowerCase()
                )
                .map((s) => s.area_city || "")
                .filter(Boolean)
            )
          ).sort();
          setCities(storeCities);
        }
      } catch {
        if (isMounted) setCities([]);
      }
    }

    loadCities();

    return () => {
      isMounted = false;
    };
  }, [selectedProvince, stores]);

  const handleProvinceChange = (province: string) => {
    setSelectedProvince(province);
    setSelectedCity("");
    if (!province) {
      setCities([]);
    }
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
    } else {
      if (reason.trim().length < 20) {
        setValidationError("Business justification is mandatory for HC Reduction requests (minimum 20 characters).");
        return;
      }
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

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/50 backdrop-blur-xs transition-opacity"
        onClick={submitMutation.isPending ? undefined : onClose}
        aria-hidden="true"
      />

      {/* Modal Dialog Card */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="headcount-modal-title"
        className="relative z-10 w-full max-w-3xl rounded-xl border border-border-default bg-surface-base shadow-2xl transition-all my-8 max-h-[90vh] flex flex-col overflow-hidden"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-default px-6 py-4 shrink-0 bg-surface-base">
          <div className="flex items-center gap-3">
            <div className="rounded-lg bg-brand-50 p-2 text-brand-600 border border-brand-200">
              <UsersRound className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="inline-flex items-center rounded bg-brand-100 px-2 py-0.5 text-[11px] font-semibold text-brand-800">
                  New Requisition
                </span>
                <span className="text-xs text-text-muted">
                  {currentStep === "form" ? "Step 1 of 2: Requisition Details" : "Step 2 of 2: Review & Submit"}
                </span>
              </div>
              <h2 id="headcount-modal-title" className="text-lg font-bold text-text-primary">
                Request Headcount
              </h2>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={submitMutation.isPending}
            className="rounded-md p-1.5 text-text-muted hover:bg-surface-hover hover:text-text-primary transition-colors disabled:opacity-40"
            aria-label="Close dialog"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Modal Body - Scrollable */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {/* Recruitment Freeze Banner */}
          {isRecruitmentFreezeActive && (
            <div className="flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 p-4 text-xs text-red-800">
              <ShieldAlert className="h-5 w-5 shrink-0 text-red-600 mt-0.5" />
              <div>
                <p className="font-semibold text-sm">Recruitment Freeze Active</p>
                <p className="mt-0.5 text-red-700">
                  System governance has locked headcount requisitions under a global freeze. You can explore the options, but submission is blocked.
                </p>
              </div>
            </div>
          )}

          {/* Validation & Error Alert */}
          {validationError && (
            <div className="flex items-start gap-3 rounded-lg border border-amber-200 bg-amber-50 p-3.5 text-xs text-amber-800">
              <AlertTriangle className="h-4 w-4 shrink-0 text-amber-600 mt-0.5" />
              <span>{validationError}</span>
            </div>
          )}

          {submissionError && (
            <div className="flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 p-3.5 text-xs text-red-800">
              <AlertCircle className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
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
                  <span className="text-xs font-semibold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
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
                    <span className="font-mono text-xs text-text-muted">({selectedAccountId})</span>
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

              {/* SECTION 1: WORKFORCE TYPE TOGGLE */}
              <div className="space-y-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-text-secondary">
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
                        ? "border-brand-600 bg-brand-50/50 text-brand-900 shadow-xs ring-1 ring-brand-500"
                        : "border-border-default bg-surface-base text-text-secondary hover:border-border-subtle hover:bg-surface-hover"
                    }`}
                  >
                    <div className="flex items-center gap-1.5 font-semibold text-sm">
                      <MapPin className="h-4 w-4 text-brand-600" />
                      <span>Stationary</span>
                    </div>
                    <p className="text-xs text-text-muted">Single dedicated store assignment</p>
                  </button>

                  <button
                    type="button"
                    onClick={() => {
                      setWorkforceType("roving");
                      setValidationError(null);
                    }}
                    className={`flex flex-col items-start gap-1 rounded-lg border p-3.5 text-left transition-all ${
                      workforceType === "roving"
                        ? "border-brand-600 bg-brand-50/50 text-brand-900 shadow-xs ring-1 ring-brand-500"
                        : "border-border-default bg-surface-base text-text-secondary hover:border-border-subtle hover:bg-surface-hover"
                    }`}
                  >
                    <div className="flex items-center gap-1.5 font-semibold text-sm">
                      <Layers className="h-4 w-4 text-brand-600" />
                      <span>Roving</span>
                    </div>
                    <p className="text-xs text-text-muted">Multi-store coverage cluster (2–20)</p>
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

              {/* SECTION 2: STORE SELECTION */}
              {workforceType === "stationary" ? (
                /* Stationary: Province -> City -> Store */
                <div className="space-y-3 rounded-lg border border-border-default bg-surface-base p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
                      <MapPin className="h-4 w-4 text-brand-600" />
                      Target Store & Area
                    </span>
                    {selectedStore && (
                      <button
                        type="button"
                        onClick={() => setSelectedStore(null)}
                        className="text-xs font-semibold text-brand-600 hover:text-brand-700"
                      >
                        Change Store
                      </button>
                    )}
                  </div>

                  {selectedStore ? (
                    /* Store Verification Card */
                    <div className="flex items-start justify-between rounded-lg border border-emerald-200 bg-emerald-50/50 p-4">
                      <div className="space-y-1">
                        <div className="flex items-center gap-2">
                          <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                          <h4 className="font-semibold text-sm text-emerald-950">
                            {selectedStore.store_name}
                          </h4>
                          {selectedStore.island_group && (
                            <span className="rounded bg-emerald-100 px-1.5 py-0.5 text-[10px] font-semibold font-mono text-emerald-800 uppercase">
                              {selectedStore.island_group}
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-emerald-800">
                          {[selectedStore.area_city, selectedStore.province || selectedStore.area_province]
                            .filter(Boolean)
                            .join(", ") || "Active Store"}
                        </p>
                      </div>
                      <span className="rounded-full bg-emerald-100 px-2.5 py-1 text-[11px] font-semibold text-emerald-800">
                        Verified Store
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

                        <div className="max-h-48 overflow-y-auto rounded-md border border-border-default bg-surface-base divide-y divide-border-subtle">
                          {filteredStationaryStores.length === 0 ? (
                            <div className="p-4 text-center text-xs text-text-muted">
                              {isLoadingMasterData
                                ? "Loading stores..."
                                : "No stores matching current filters."}
                            </div>
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
                                  <span className="rounded bg-gray-100 px-1.5 py-0.5 text-[10px] font-mono font-medium text-gray-700">
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
                    <div className="flex items-start gap-2.5 rounded-lg border border-amber-300 bg-amber-50 p-3 text-xs text-amber-900">
                      <AlertTriangle className="h-4 w-4 shrink-0 text-amber-600 mt-0.5" />
                      <div>
                        <span className="font-semibold">Pending Requests Notice: </span>
                        {storePendingRequests.length} pending request(s) already submitted for{" "}
                        <strong>{selectedStore.store_name}</strong>.
                      </div>
                    </div>
                  )}

                  {/* Warning: Exact Duplicate Candidate */}
                  {duplicateCandidate && (
                    <div className="flex items-start gap-2.5 rounded-lg border border-orange-300 bg-orange-50 p-3 text-xs text-orange-900">
                      <AlertTriangle className="h-4 w-4 shrink-0 text-orange-600 mt-0.5" />
                      <div>
                        <span className="font-semibold">Potential Duplicate Warning: </span>
                        A similar recent request exists for this store, position,{" "}
                        {headcountNeeded} headcount, and vacant date.
                      </div>
                    </div>
                  )}
                </div>
              ) : (
                /* Roving: Multi-Store Chip Picker */
                <div className="space-y-3 rounded-lg border border-border-default bg-surface-base p-4">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
                      <Layers className="h-4 w-4 text-brand-600" />
                      Selected Roving Stores ({selectedRovingStores.length}/20)
                    </span>
                    <span className="text-xs text-text-muted">Min: 2 stores</span>
                  </div>

                  {/* Island Group Violation Alert */}
                  {rovingIslandGroupError && (
                    <div className="flex items-start gap-2.5 rounded-lg border border-red-300 bg-red-50 p-3 text-xs text-red-900">
                      <ShieldAlert className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
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
                          className="inline-flex items-center gap-1.5 rounded-md bg-surface-base border border-border-default pl-2.5 pr-1.5 py-1 text-xs font-medium text-text-primary shadow-xs"
                        >
                          <span>{s.store_name}</span>
                          {s.island_group && (
                            <span className="text-[10px] font-mono text-text-muted">
                              ({s.island_group})
                            </span>
                          )}
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
                      No stores added yet. Select between 2 and 20 stores below sharing the same island group.
                    </div>
                  )}

                  {/* Store Multi-picker list */}
                  <div className="space-y-2 pt-2">
                    <div className="relative">
                      <Search className="absolute left-3 top-2.5 h-4 w-4 text-text-muted" />
                      <input
                        type="text"
                        placeholder="Search stores to add to roving cluster..."
                        value={rovingSearch}
                        onChange={(e) => setRovingSearch(e.target.value)}
                        className="w-full rounded-md border border-border-default bg-surface-muted pl-9 pr-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                      />
                    </div>

                    <div className="max-h-40 overflow-y-auto rounded-md border border-border-default bg-surface-base divide-y divide-border-subtle">
                      {stores
                        .filter((s) => {
                          if (!rovingSearch.trim()) return true;
                          const q = rovingSearch.toLowerCase();
                          return (
                            s.store_name.toLowerCase().includes(q) ||
                            (s.area_city || "").toLowerCase().includes(q)
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
                                  {[s.area_city, s.island_group].filter(Boolean).join(" • ")}
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
                                    ? "bg-red-50 text-red-700 hover:bg-red-100"
                                    : "bg-brand-600 text-white hover:bg-brand-700"
                                }`}
                              >
                                {isSelected ? "Remove" : "Select"}
                              </button>
                            </div>
                          );
                        })}
                    </div>
                  </div>
                </div>
              )}

              {/* SECTION 3: POSITION & DEMAND DETAILS */}
              <div className="space-y-4 rounded-lg border border-border-default bg-surface-base p-4">
                <span className="text-xs font-semibold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
                  <Sparkles className="h-4 w-4 text-brand-600" />
                  Position & Headcount
                </span>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label className="text-xs font-medium text-text-secondary mb-1 block">
                      Position Title *
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
                      Request Type *
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
                      {requestType === "HC Reduction" ? "Headcount to Reduce" : "Headcount Needed"} *
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
                  <span className="text-xs font-semibold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
                    <Clock className="h-4 w-4 text-brand-600" />
                    Timeline & Fulfillment Urgency
                  </span>

                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div>
                      <label className="text-xs font-medium text-text-secondary mb-1 block">
                        Vacant Date *
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
                        Urgency Tier *
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
                          Target Fill Date *
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
                          isDateOrderInvalid ? "border-red-400" : "border-border-default"
                        }`}
                      />
                      {isDateOrderInvalid && (
                        <p className="mt-1 text-[11px] text-red-600">
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
                  <span className="text-xs font-semibold uppercase tracking-wider text-text-secondary">
                    Operational Justification {requestType === "HC Reduction" ? "(Mandatory)" : "(Optional)"}
                  </span>
                  <span className="text-xs text-text-muted">
                    {reason.length}/500 chars{" "}
                    {requestType === "HC Reduction" && (
                      <span className={reason.trim().length >= 20 ? "text-emerald-600 font-semibold" : "text-amber-600 font-semibold"}>
                        (Min 20 required)
                      </span>
                    )}
                  </span>
                </div>
                <textarea
                  rows={3}
                  maxLength={500}
                  placeholder={
                    requestType === "HC Reduction"
                      ? "Detail the business or operational rationale for this quota reduction (minimum 20 characters required)..."
                      : "Provide operational context, seasonal demands, or store expansion justification..."
                  }
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
              <div className="rounded-lg border border-brand-200 bg-brand-50/40 p-4 text-xs text-brand-900">
                <h4 className="font-semibold text-sm flex items-center gap-2">
                  <Sparkles className="h-4 w-4 text-brand-600" />
                  Review Headcount Requisition
                </h4>
                <p className="mt-0.5 text-brand-800">
                  Please confirm the requisition parameters before submitting to the approval pipeline.
                </p>
              </div>

              {/* Requisition Summary Card */}
              <div className="rounded-xl border border-border-default bg-surface-base overflow-hidden divide-y divide-border-subtle shadow-xs">
                <div className="p-4 grid grid-cols-2 gap-4">
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted uppercase">Operational Account</span>
                    <div className="text-sm font-bold text-text-primary mt-0.5">{selectedAccountName}</div>
                  </div>
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted uppercase">Deployment Mode</span>
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
                  <span className="text-[11px] font-semibold text-text-muted uppercase">
                    {workforceType === "stationary" ? "Assigned Store" : `Roving Cluster (${selectedRovingStores.length} stores)`}
                  </span>
                  {workforceType === "stationary" ? (
                    <div className="mt-1 flex items-center justify-between">
                      <div className="font-bold text-sm text-text-primary">
                        {selectedStore?.store_name}
                      </div>
                      <span className="text-xs text-text-muted">
                        {[selectedStore?.area_city, selectedStore?.province || selectedStore?.area_province]
                          .filter(Boolean)
                          .join(", ")}
                      </span>
                    </div>
                  ) : (
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      {selectedRovingStores.map((s) => (
                        <span
                          key={s.id}
                          className="rounded bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-secondary border border-border-default"
                        >
                          {s.store_name}
                        </span>
                      ))}
                    </div>
                  )}
                </div>

                <div className="p-4 grid grid-cols-3 gap-4">
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted uppercase">Position</span>
                    <div className="text-sm font-bold text-text-primary mt-0.5">
                      {selectedPosition?.position_name}
                    </div>
                  </div>
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted uppercase">Request Type</span>
                    <div className="text-sm font-semibold text-text-primary mt-0.5">
                      {requestType}
                    </div>
                  </div>
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted uppercase">Headcount</span>
                    <div className="text-sm font-mono font-bold text-brand-700 mt-0.5">
                      {headcountNeeded} {headcountNeeded === 1 ? "Slot" : "Slots"}
                    </div>
                  </div>
                </div>

                {requestType !== "HC Reduction" && (
                  <div className="p-4 grid grid-cols-3 gap-4">
                    <div>
                      <span className="text-[11px] font-semibold text-text-muted uppercase">Vacant Date</span>
                      <div className="text-sm font-medium text-text-primary mt-0.5">{vacantDate}</div>
                    </div>
                    <div>
                      <span className="text-[11px] font-semibold text-text-muted uppercase">Urgency Tier</span>
                      <div className="text-sm font-semibold text-text-primary mt-0.5">{urgency}</div>
                    </div>
                    <div>
                      <span className="text-[11px] font-semibold text-text-muted uppercase">Target Fill Date</span>
                      <div className="text-sm font-bold text-text-primary mt-0.5">{targetFillDate}</div>
                    </div>
                  </div>
                )}

                <div className="p-4">
                  <span className="text-[11px] font-semibold text-text-muted uppercase">Operational Justification</span>
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
      </div>
    </div>
  );
}
