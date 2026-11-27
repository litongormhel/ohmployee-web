"use client";

import { useState, useMemo } from "react";
import Link from "next/link";
import {
  AlertCircle,
  AlertTriangle,
  Building2,
  CheckCircle2,
  ExternalLink,
  Layers,
  MapPin,
  Minus,
  Plus,
  Search,
  ShieldAlert,
  Sparkles,
  Store,
  X,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { RequiredAsterisk } from "@/components/shared/RequiredAsterisk";
import { useRefProvinces, useRefCities, useRefLocations } from "@/lib/queries/locations";
import { deriveIslandGroup } from "@/lib/queries/plantilla";
import {
  useAvailableHeadcountAccounts,
  useHeadcountModalMasterData,
  useSubmitHeadcountRequest,
  useSubmitNewStoreRequest,
  useAccountGroupId,
} from "@/lib/queries/requests";
import type { ActionModalProps } from "@/types/modal";

export type NewStoreMode = "stationary" | "roving";
export type UrgencyTier = "Low" | "Medium" | "High" | "Critical";

interface DoorItem {
  id: string;
  store_name: string;
  area_city: string;
  area_province: string;
  island_group: string | null;
  is_new_store: boolean;
}

export interface NewStoreRequestSuccessPayload {
  mode: NewStoreMode;
  requestId: string;
  storeName: string;
  storeCount: number;
  province: string;
  city: string;
  accountName: string;
  accountId: string;
}

export interface NewStoreRequestModalProps
  extends ActionModalProps<NewStoreRequestSuccessPayload> {
  initialAccountId?: string | null;
  initialAccountName?: string | null;
  initialGroupId?: string | null;
  initialStoreName?: string | null;
  initialProvince?: string | null;
  initialCity?: string | null;
  initialPosition?: string | null;
  initialRequestedHc?: number | null;
  provinces?: string[];
  cities?: string[];
  existingStores?: {
    store_name: string;
    area_city?: string | null;
    province?: string | null;
    area_province?: string | null;
  }[];
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
    case "Low":
      return 30;
    default:
      return 14;
  }
}

export function NewStoreRequestModal(props: NewStoreRequestModalProps) {
  if (!props.isOpen) return null;

  return <NewStoreRequestModalDialog {...props} />;
}

function NewStoreRequestModalDialog({
  isOpen = true,
  onClose,
  initialAccountId,
  initialAccountName,
  initialGroupId,
  initialStoreName = "",
  initialProvince = "",
  initialCity = "",
  initialPosition,
  initialRequestedHc,
  provinces: propProvinces,
  cities: propCities,
  existingStores: propExistingStores = [],
  onSuccess,
}: NewStoreRequestModalProps) {
  const submitStationaryMutation = useSubmitNewStoreRequest();
  const submitRovingMutation = useSubmitHeadcountRequest();

  const [mode, setMode] = useState<NewStoreMode>("stationary");
  const [customAccountId, setCustomAccountId] = useState("");
  const [customAccountName, setCustomAccountName] = useState("");

  const { data: accountsData = [] } = useAvailableHeadcountAccounts({
    enabled: !initialAccountId,
  });

  const resolvedAccountId =
    initialAccountId ||
    customAccountId ||
    (accountsData.length > 0 ? accountsData[0].id : "");

  const resolvedAccountName =
    initialAccountName ||
    customAccountName ||
    (accountsData.find((a) => a.id === resolvedAccountId)?.name ?? "Scoped Account");

  const { data: fetchedAccountGroupId } = useAccountGroupId(resolvedAccountId, {
    enabled: !initialGroupId && Boolean(resolvedAccountId),
  });
  const resolvedGroupId = initialGroupId || fetchedAccountGroupId || null;

  const { data: masterData } = useHeadcountModalMasterData(resolvedAccountId, {
    enabled: Boolean(resolvedAccountId),
  });

  const masterStores = useMemo(() => masterData?.stores ?? [], [masterData?.stores]);
  const positions = useMemo(() => masterData?.positions ?? [], [masterData?.positions]);
  const isRecruitmentFreezeActive = masterData?.isRecruitmentFreezeActive ?? false;

  const existingStoresForDuplicateCheck = useMemo(() => {
    if (masterStores.length > 0) return masterStores;
    return propExistingStores;
  }, [masterStores, propExistingStores]);

  // Shared Position, HC, Reason
  const [customPositionId, setCustomPositionId] = useState("");
  const defaultPositionId = useMemo(() => {
    if (initialPosition && positions.length > 0) {
      const matched = positions.find(
        (p) => p.position_name.toLowerCase() === initialPosition.toLowerCase()
      );
      if (matched) return matched.id;
    }
    return positions.length > 0 ? positions[0].id : "";
  }, [initialPosition, positions]);

  const selectedPositionId = customPositionId || defaultPositionId;
  const selectedPosition = useMemo(
    () => positions.find((p) => p.id === selectedPositionId) ?? null,
    [positions, selectedPositionId]
  );

  const [requestedHc, setRequestedHc] = useState<number>(
    Math.max(1, initialRequestedHc ?? 1)
  );
  const [reason, setReason] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [submittedInfo, setSubmittedInfo] = useState<NewStoreRequestSuccessPayload | null>(
    null
  );

  // Stationary Mode Fields
  const [storeName, setStoreName] = useState(initialStoreName || "");
  const [province, setProvince] = useState(initialProvince || "");
  const [city, setCity] = useState(initialCity || "");

  // Roving Mode Fields (ADR-003 Multi-Door)
  const [rovingDoors, setRovingDoors] = useState<DoorItem[]>([]);
  const [doorSearch, setDoorSearch] = useState("");
  const [newDoorName, setNewDoorName] = useState("");
  const [newDoorProvince, setNewDoorProvince] = useState("");
  const [newDoorCity, setNewDoorCity] = useState("");
  const [newDoorError, setNewDoorError] = useState<string | null>(null);
  const [urgency, setUrgency] = useState<UrgencyTier>("Medium");
  const todayStr = useMemo(() => formatDate(new Date()), []);
  const [vacantDate, setVacantDate] = useState(todayStr);

  // Reference Locations
  const { data: dbProvinces = [] } = useRefProvinces({
    enabled: !propProvinces || propProvinces.length === 0 || mode === "roving",
  });
  const availableProvinces = useMemo(() => {
    if (propProvinces && propProvinces.length > 0 && mode === "stationary") {
      return propProvinces;
    }
    return dbProvinces;
  }, [propProvinces, dbProvinces, mode]);

  const { data: dbCities = [] } = useRefCities(province, {
    enabled: mode === "stationary" && Boolean(province),
  });
  const availableCities = useMemo(() => {
    if (dbCities.length > 0) return dbCities;
    if (propCities && propCities.length > 0 && province === initialProvince) {
      return propCities;
    }
    return [];
  }, [dbCities, propCities, province, initialProvince]);

  const { data: rovingDoorCities = [] } = useRefCities(newDoorProvince, {
    enabled: mode === "roving" && Boolean(newDoorProvince),
  });
  const { data: allRefLocations = [] } = useRefLocations({
    enabled: mode === "roving",
  });

  const resolveIslandGroup = (prov: string, cty?: string | null): string | null => {
    if (!prov) return null;
    const direct = deriveIslandGroup(prov);
    if (direct) return direct;
    if (cty) {
      const cityMatch = allRefLocations.find(
        (l) =>
          l.province.toLowerCase() === prov.toLowerCase() &&
          l.city.toLowerCase() === cty.toLowerCase()
      );
      if (cityMatch?.island_group) return cityMatch.island_group;
    }
    const provMatch = allRefLocations.find(
      (l) => l.province.toLowerCase() === prov.toLowerCase()
    );
    return provMatch?.island_group || null;
  };

  const stationaryIslandGroup = useMemo(
    () => (province ? deriveIslandGroup(province) : null),
    [province]
  );

  const newDoorIslandGroup = useMemo(
    () => resolveIslandGroup(newDoorProvince, newDoorCity),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [newDoorProvince, newDoorCity, allRefLocations]
  );

  const rovingIslandGroups = useMemo(() => {
    const set = new Set<string>();
    rovingDoors.forEach((d) => {
      if (d.island_group) set.add(d.island_group);
    });
    return Array.from(set);
  }, [rovingDoors]);

  const rovingIslandGroupError = useMemo(() => {
    if (mode !== "roving") return null;
    if (rovingIslandGroups.length > 1) {
      return `Coverage Group cannot span multiple island groups (${rovingIslandGroups.join(
        " + "
      )}). Create separate New Store Requests per island group.`;
    }
    return null;
  }, [mode, rovingIslandGroups]);

  // Stationary duplicate warning
  const duplicateWarning = useMemo(() => {
    if (mode !== "stationary" || !storeName.trim() || !province.trim()) return null;
    const nameLower = storeName.trim().toLowerCase();
    const provLower = province.trim().toLowerCase();
    const cityLower = city.trim().toLowerCase();

    const match = existingStoresForDuplicateCheck.find((s) => {
      const sName = s.store_name.trim().toLowerCase();
      const sProv = (s.province || s.area_province || "").trim().toLowerCase();
      const sCity = (s.area_city || "").trim().toLowerCase();
      if (sName !== nameLower) return false;
      if (sProv && sProv !== provLower) return false;
      if (cityLower && sCity && sCity !== cityLower) return false;
      return true;
    });

    if (match) {
      return `A store named "${match.store_name}" already exists under this account (${
        match.area_city || ""
      }, ${match.province || match.area_province || ""}). Use Store View -> Request HC for existing stores.`;
    }
    return null;
  }, [mode, storeName, province, city, existingStoresForDuplicateCheck]);

  const filteredExistingStores = useMemo(() => {
    const q = doorSearch.trim().toLowerCase();
    return masterStores.filter((s) => {
      if (!q) return true;
      return (
        s.store_name.toLowerCase().includes(q) ||
        (s.area_city || "").toLowerCase().includes(q) ||
        (s.province || s.area_province || "").toLowerCase().includes(q)
      );
    });
  }, [masterStores, doorSearch]);

  const handleAddNewDoor = () => {
    setNewDoorError(null);
    const cleanName = newDoorName.trim();
    if (!cleanName) {
      setNewDoorError("Store name is required.");
      return;
    }
    if (!newDoorProvince) {
      setNewDoorError("Province is required.");
      return;
    }
    if (!newDoorCity) {
      setNewDoorError("City / Municipality is required.");
      return;
    }
    if (rovingDoors.some((d) => d.store_name.toLowerCase() === cleanName.toLowerCase())) {
      setNewDoorError(`"${cleanName}" is already in this multi-door list.`);
      return;
    }
    if (masterStores.some((s) => s.store_name.toLowerCase() === cleanName.toLowerCase())) {
      setNewDoorError(
        `"${cleanName}" already exists under this account. Select it from the existing stores list below.`
      );
      return;
    }
    if (
      newDoorIslandGroup &&
      rovingIslandGroups.length > 0 &&
      !rovingIslandGroups.includes(newDoorIslandGroup)
    ) {
      setNewDoorError(
        `Cannot add store in ${newDoorIslandGroup}. Current cluster belongs to ${rovingIslandGroups.join(
          " + "
        )}.`
      );
      return;
    }
    if (rovingDoors.length >= 20) {
      setNewDoorError("Maximum 20 stores per roving cluster.");
      return;
    }

    setRovingDoors((prev) => [
      ...prev,
      {
        id: `new-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
        store_name: cleanName,
        area_province: newDoorProvince,
        area_city: newDoorCity,
        island_group: newDoorIslandGroup,
        is_new_store: true,
      },
    ]);
    setNewDoorName("");
    setNewDoorProvince("");
    setNewDoorCity("");
  };

  const isPending =
    submitStationaryMutation.isPending || submitRovingMutation.isPending;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);

    if (!resolvedAccountId) {
      setFormError("Operational account is required.");
      return;
    }

    const cleanReason = reason.trim();
    if (cleanReason.length < 20) {
      setFormError("Operational justification is mandatory (minimum 20 characters).");
      return;
    }

    if (!selectedPosition) {
      setFormError("Target position is required so approved stores receive an initial vacancy.");
      return;
    }

    if (requestedHc < 1 || requestedHc > 20) {
      setFormError("Initial headcount must be between 1 and 20.");
      return;
    }

    if (mode === "stationary") {
      const trimmedStore = storeName.trim();
      const trimmedProv = province.trim();
      const trimmedCity = city.trim();

      if (!trimmedStore) {
        setFormError("Store name is required.");
        return;
      }
      if (!trimmedProv) {
        setFormError("Province is required.");
        return;
      }
      if (!trimmedCity) {
        setFormError("City / Municipality is required.");
        return;
      }

      submitStationaryMutation.mutate(
        {
          store_name: trimmedStore,
          province: trimmedProv,
          city: trimmedCity,
          account_id: resolvedAccountId,
          account_name: resolvedAccountName,
          group_id: resolvedGroupId,
          reason: cleanReason,
          position: selectedPosition.position_name,
          requested_hc: requestedHc,
        },
        {
          onSuccess: (res) => {
            const payload: NewStoreRequestSuccessPayload = {
              mode: "stationary",
              requestId: res.request_id,
              storeName: trimmedStore,
              storeCount: 1,
              province: trimmedProv,
              city: trimmedCity,
              accountName: resolvedAccountName,
              accountId: resolvedAccountId,
            };
            setSubmittedInfo(payload);
            onSuccess?.(payload);
          },
          onError: (err) => {
            setFormError(
              err.message || "Failed to submit new store request. Please try again."
            );
          },
        }
      );
      return;
    }

    // Roving Mode (ADR-003)
    if (isRecruitmentFreezeActive) {
      setFormError("Recruitment freeze is active. Roving new-store submissions are paused.");
      return;
    }
    if (rovingDoors.length < 2) {
      setFormError("Roving New Store openings require at least 2 stores in the cluster.");
      return;
    }
    if (rovingDoors.length > 20) {
      setFormError("Maximum 20 stores per roving cluster.");
      return;
    }
    if (!rovingDoors.some((d) => d.is_new_store)) {
      setFormError(
        "Include at least 1 new opening store. For existing stores only, use '+ Request Roving HC'."
      );
      return;
    }
    if (rovingIslandGroupError) {
      setFormError(rovingIslandGroupError);
      return;
    }

    submitRovingMutation.mutate(
      {
        account_id: resolvedAccountId,
        account_name: resolvedAccountName,
        position_id: selectedPosition.id,
        position_name: selectedPosition.position_name,
        workforce_type: "roving",
        employment_type: "Roving",
        request_type: "Additional Headcount",
        headcount_needed: requestedHc,
        vacant_date: vacantDate,
        target_fill_date: addDays(vacantDate, getUrgencyDays(urgency)),
        urgency,
        reason: cleanReason,
        stores: rovingDoors.map((d) =>
          d.is_new_store
            ? {
                is_new_store: true,
                store_name: d.store_name,
                area_province: d.area_province,
                area_city: d.area_city,
                island_group: d.island_group || undefined,
              }
            : {
                is_new_store: false,
                store_id: d.id,
                store_name: d.store_name,
                area_province: d.area_province,
                area_city: d.area_city,
                island_group: d.island_group || undefined,
              }
        ),
        store_ids: rovingDoors.filter((d) => !d.is_new_store).map((d) => d.id),
      },
      {
        onSuccess: (res) => {
          const firstDoor = rovingDoors[0];
          const newCount = rovingDoors.filter((d) => d.is_new_store).length;
          const payload: NewStoreRequestSuccessPayload = {
            mode: "roving",
            requestId: res.request_id,
            storeName: rovingDoors.map((d) => d.store_name).join(", "),
            storeCount: newCount,
            province: firstDoor?.area_province || "",
            city: firstDoor?.area_city || "",
            accountName: resolvedAccountName,
            accountId: resolvedAccountId,
          };
          setSubmittedInfo(payload);
          onSuccess?.(payload);
        },
        onError: (err) => {
          setFormError(
            err.message || "Failed to submit roving new store request. Please try again."
          );
        },
      }
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={
        <span className="flex items-center gap-2">
          <span>Request New Store</span>
          <span className="rounded bg-[var(--surface-sunken)] px-2 py-0.5 text-xs font-bold text-[var(--foreground)] border border-[var(--border-subtle)]">
            Store Opening
          </span>
        </span>
      }
      subtitle="Register unlisted opening store(s) with initial staffing demand"
      icon={Store}
      maxWidthClass="max-w-2xl"
      disableBackdropClick={isPending}
      isSubmitting={isPending}
      isDirty={Boolean(
        !submittedInfo &&
          (storeName.trim() || reason.trim() || rovingDoors.length > 0 || newDoorName.trim())
      )}
    >
      <div className="p-6 space-y-5 overflow-y-auto max-h-[78vh]">
        {submittedInfo ? (
          <div className="space-y-5 text-center py-2">
            <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-[var(--surface-muted)] text-emerald-600 border border-[var(--border-subtle)]">
              <CheckCircle2 className="h-7 w-7" />
            </div>
            <div className="space-y-1.5">
              <h3 className="text-base font-bold text-text-primary">
                New Store Request Submitted!
              </h3>
              <p className="text-xs text-text-muted max-w-md mx-auto">
                Your{" "}
                <strong className="text-text-primary">
                  {submittedInfo.mode === "roving"
                    ? `Roving Multi-Door (${submittedInfo.storeCount} new door${
                        submittedInfo.storeCount === 1 ? "" : "s"
                      })`
                    : "Stationary New Store"}
                </strong>{" "}
                opening request for{" "}
                <strong className="text-text-primary">{submittedInfo.storeName}</strong> under{" "}
                <strong className="text-text-primary">{submittedInfo.accountName}</strong> is now
                pending review in the New Stores queue.
              </p>
            </div>

            <div className="rounded-lg border border-border-default bg-surface-muted p-3.5 text-left text-xs space-y-1.5">
              <div className="flex justify-between">
                <span className="text-text-muted font-medium">Status:</span>
                <span className="rounded bg-[var(--surface-sunken)] px-2 py-0.5 text-xs font-bold text-[var(--foreground)] border border-[var(--border-subtle)]">
                  Pending Review (New Stores)
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted font-medium">Initial Vacancy Provision:</span>
                <span className="font-semibold text-text-primary">
                  {requestedHc} × {selectedPosition?.position_name ?? "Staff"} ({mode})
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted font-medium">Request Reference:</span>
                <span
                  className="font-mono text-[11px] font-semibold text-text-secondary tracking-wider"
                  title={submittedInfo.requestId}
                >
                  {submittedInfo.requestId.replace(/-/g, "").slice(0, 8).toUpperCase()}
                </span>
              </div>
            </div>

            <div className="flex flex-col sm:flex-row gap-2.5 pt-2">
              <Link
                href="/my-requests"
                onClick={onClose}
                className="flex-1 inline-flex items-center justify-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-primary hover:bg-surface-hover transition-colors"
              >
                <ExternalLink className="h-3.5 w-3.5 text-text-muted" />
                <span>Track in My Requests</span>
              </Link>
              <Link
                href="/approvals?tab=new_stores"
                onClick={onClose}
                className="flex-1 inline-flex items-center justify-center gap-1.5 rounded-lg bg-brand-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-700 transition-colors"
              >
                <ExternalLink className="h-3.5 w-3.5" />
                <span>View in Approvals</span>
              </Link>
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors"
              >
                Done
              </button>
            </div>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-5">
            {/* Account Scope Badge or Selector */}
            <div className="rounded-lg border border-border-default bg-surface-muted p-3 flex items-center justify-between gap-3">
              <span className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                <Building2 className="h-4 w-4 text-text-muted" />
                Target Account
              </span>
              {initialAccountId ? (
                <span className="inline-flex items-center rounded-md bg-brand-50 px-2.5 py-1 text-xs font-semibold text-brand-700 ring-1 ring-inset ring-brand-700/10">
                  {resolvedAccountName}
                </span>
              ) : (
                <select
                  value={resolvedAccountId}
                  onChange={(e) => {
                    const id = e.target.value;
                    setCustomAccountId(id);
                    const acct = accountsData.find((a) => a.id === id);
                    setCustomAccountName(acct?.name || "");
                    setRovingDoors([]);
                  }}
                  className="rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-semibold text-text-primary outline-none focus:border-brand-500"
                >
                  {accountsData.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
                </select>
              )}
            </div>

            {/* Deployment Mode Toggle */}
            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-text-secondary block">
                Store Opening Type
              </label>
              <div className="grid grid-cols-2 gap-3">
                <button
                  type="button"
                  onClick={() => {
                    setMode("stationary");
                    setFormError(null);
                  }}
                  className={`flex flex-col items-start gap-1 rounded-lg border p-3 text-left transition-all cursor-pointer ${
                    mode === "stationary"
                      ? "border-brand-primary bg-surface-selected text-text-primary shadow-xs ring-1 ring-brand-primary"
                      : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
                  }`}
                >
                  <div className="flex items-center gap-1.5 text-xs font-bold">
                    <MapPin className="h-3.5 w-3.5 text-brand-primary" />
                    <span>Stationary (1 New Store)</span>
                  </div>
                  <p className="text-[11px] text-text-muted">
                    Registers 1 opening branch + initial open vacancy
                  </p>
                </button>

                <button
                  type="button"
                  onClick={() => {
                    setMode("roving");
                    setFormError(null);
                  }}
                  className={`flex flex-col items-start gap-1 rounded-lg border p-3 text-left transition-all cursor-pointer ${
                    mode === "roving"
                      ? "border-brand-primary bg-surface-selected text-text-primary shadow-xs ring-1 ring-brand-primary"
                      : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover"
                  }`}
                >
                  <div className="flex items-center gap-1.5 text-xs font-bold">
                    <Layers className="h-3.5 w-3.5 text-brand-primary" />
                    <span>Roving (Multi-Door Opening)</span>
                  </div>
                  <p className="text-[11px] text-text-muted">
                    2–20 new or mixed doors sharing 1 roving Coverage Group (ADR-003)
                  </p>
                </button>
              </div>
            </div>

            {formError && (
              <div className="flex items-start gap-2.5 rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger)]">
                <AlertCircle className="h-4 w-4 shrink-0 text-[var(--danger)] mt-0.5" />
                <span>{formError}</span>
              </div>
            )}

            {mode === "stationary" ? (
              <div className="space-y-4 rounded-lg border border-border-default bg-surface-base p-4">
                {duplicateWarning && (
                  <div className="flex items-start gap-2.5 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-800 dark:text-amber-200">
                    <AlertTriangle className="h-4 w-4 shrink-0 text-amber-600 mt-0.5" />
                    <span>{duplicateWarning}</span>
                  </div>
                )}

                <div className="space-y-1">
                  <label
                    htmlFor="nsr-store-name"
                    className="text-xs font-semibold text-text-primary block"
                  >
                    New Store Name <RequiredAsterisk />
                  </label>
                  <input
                    id="nsr-store-name"
                    type="text"
                    placeholder="e.g., Puregold Jr. San Pedro"
                    value={storeName}
                    onChange={(e) => setStoreName(e.target.value)}
                    className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                    required
                  />
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <div className="flex items-center justify-between">
                      <label
                        htmlFor="nsr-province"
                        className="text-xs font-semibold text-text-primary block"
                      >
                        Province <RequiredAsterisk />
                      </label>
                      {stationaryIslandGroup && (
                        <span className="rounded bg-surface-muted px-1.5 py-0.5 font-mono text-[10px] font-semibold text-text-secondary border border-border-subtle">
                          {stationaryIslandGroup}
                        </span>
                      )}
                    </div>
                    <select
                      id="nsr-province"
                      value={province}
                      onChange={(e) => {
                        setProvince(e.target.value);
                        setCity("");
                      }}
                      className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                      required
                    >
                      <option value="">Select Province</option>
                      {availableProvinces.map((prov) => (
                        <option key={prov} value={prov}>
                          {prov}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="space-y-1">
                    <label
                      htmlFor="nsr-city"
                      className="text-xs font-semibold text-text-primary block"
                    >
                      City / Municipality <RequiredAsterisk />
                    </label>
                    {availableCities.length > 0 ? (
                      <select
                        id="nsr-city"
                        value={city}
                        onChange={(e) => setCity(e.target.value)}
                        className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                        required
                      >
                        <option value="">Select City</option>
                        {availableCities.map((c) => (
                          <option key={c} value={c}>
                            {c}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <input
                        id="nsr-city"
                        type="text"
                        placeholder="e.g., San Pedro City"
                        value={city}
                        onChange={(e) => setCity(e.target.value)}
                        className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                        required
                      />
                    )}
                  </div>
                </div>
              </div>
            ) : (
              /* Roving Mode: Multi-Door Cluster (ADR-003) */
              <div className="space-y-3 rounded-lg border border-border-default bg-surface-base p-4">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                    <Layers className="h-4 w-4 text-brand-600" />
                    Roving Door Cluster ({rovingDoors.length}/20)
                  </span>
                  <span className="text-[11px] text-text-muted">
                    Min 2 doors · At least 1 New Store
                  </span>
                </div>

                {rovingIslandGroupError && (
                  <div className="flex items-start gap-2 rounded-lg border border-[var(--danger)]/30 bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger)]">
                    <ShieldAlert className="h-4 w-4 shrink-0 mt-0.5" />
                    <span>{rovingIslandGroupError}</span>
                  </div>
                )}

                {rovingDoors.length > 0 && (
                  <div className="flex flex-wrap gap-2 rounded-md border border-border-default bg-surface-muted p-2">
                    {rovingDoors.map((d) => (
                      <span
                        key={d.id}
                        className={`inline-flex items-center gap-1.5 rounded-md border pl-2.5 pr-1.5 py-1 text-xs font-medium shadow-2xs ${
                          d.is_new_store
                            ? "bg-amber-500/10 border-amber-500/30 text-amber-800 dark:text-amber-200"
                            : "bg-surface-base border-border-default text-text-primary"
                        }`}
                      >
                        {d.is_new_store && (
                          <Sparkles className="h-3 w-3 text-amber-500 shrink-0" />
                        )}
                        <span>{d.store_name}</span>
                        {d.is_new_store && (
                          <span className="rounded bg-amber-500/20 px-1 text-[9px] font-semibold">
                            New Store
                          </span>
                        )}
                        <span className="text-[10px] font-mono text-text-muted">
                          {[d.area_city, d.island_group].filter(Boolean).join(" • ")}
                        </span>
                        <button
                          type="button"
                          onClick={() =>
                            setRovingDoors((prev) => prev.filter((item) => item.id !== d.id))
                          }
                          className="rounded-full p-0.5 text-text-muted hover:bg-surface-hover hover:text-text-primary"
                          aria-label={`Remove ${d.store_name}`}
                        >
                          <X className="h-3 w-3" />
                        </button>
                      </span>
                    ))}
                  </div>
                )}

                {/* Add New Opening Door Sub-Form */}
                <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 space-y-2.5">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-amber-800 dark:text-amber-200 flex items-center gap-1.5">
                      <Sparkles className="h-3.5 w-3.5 text-amber-500" />
                      Add New Opening Store Door
                    </span>
                    {newDoorIslandGroup && (
                      <span className="rounded bg-surface-base px-2 py-0.5 border border-border-default font-mono text-[10px] text-text-secondary">
                        {newDoorIslandGroup}
                      </span>
                    )}
                  </div>

                  {newDoorError && (
                    <div className="rounded border border-[var(--danger-border)] bg-[var(--danger-bg)] p-2 text-xs text-[var(--danger)] flex items-start gap-1.5">
                      <AlertTriangle className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                      <span>{newDoorError}</span>
                    </div>
                  )}

                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                    <input
                      type="text"
                      placeholder="New Store Name *"
                      value={newDoorName}
                      onChange={(e) => setNewDoorName(e.target.value)}
                      className="rounded border border-border-default bg-surface-base px-2.5 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500"
                    />
                    <select
                      value={newDoorProvince}
                      onChange={(e) => {
                        setNewDoorProvince(e.target.value);
                        setNewDoorCity("");
                      }}
                      className="rounded border border-border-default bg-surface-base px-2.5 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500"
                    >
                      <option value="">Province *</option>
                      {availableProvinces.map((prov) => (
                        <option key={prov} value={prov}>
                          {prov}
                        </option>
                      ))}
                    </select>
                    <select
                      value={newDoorCity}
                      disabled={!newDoorProvince}
                      onChange={(e) => setNewDoorCity(e.target.value)}
                      className="rounded border border-border-default bg-surface-base px-2.5 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500 disabled:opacity-50"
                    >
                      <option value="">
                        {!newDoorProvince ? "Select Province..." : "City / Municipality *"}
                      </option>
                      {rovingDoorCities.map((c) => (
                        <option key={c} value={c}>
                          {c}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="flex justify-end">
                    <button
                      type="button"
                      onClick={handleAddNewDoor}
                      className="inline-flex items-center gap-1 rounded bg-brand-600 hover:bg-brand-700 text-white px-3 py-1.5 text-xs font-semibold transition cursor-pointer"
                    >
                      <Plus className="h-3.5 w-3.5" />
                      <span>Add New Door</span>
                    </button>
                  </div>
                </div>

                {/* Optional Existing Store Picker */}
                {masterStores.length > 0 && (
                  <div className="space-y-1.5 pt-1">
                    <div className="relative">
                      <Search className="absolute left-3 top-2 h-3.5 w-3.5 text-text-muted" />
                      <input
                        type="text"
                        placeholder="Optional: include existing registered stores in this cluster..."
                        value={doorSearch}
                        onChange={(e) => setDoorSearch(e.target.value)}
                        className="w-full rounded-md border border-border-default bg-surface-muted pl-8 pr-3 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500"
                      />
                    </div>
                    <div className="max-h-32 overflow-y-auto rounded-md border border-border-default divide-y divide-border-subtle">
                      {filteredExistingStores.slice(0, 30).map((s) => {
                        const isSelected = rovingDoors.some((d) => d.id === s.id);
                        return (
                          <div
                            key={s.id}
                            className="flex items-center justify-between px-3 py-1.5 text-xs hover:bg-surface-hover"
                          >
                            <div>
                              <span className="font-semibold text-text-primary">
                                {s.store_name}
                              </span>
                              <span className="ml-2 text-[11px] text-text-muted">
                                {[s.area_city, s.province || s.area_province, s.island_group]
                                  .filter(Boolean)
                                  .join(" • ")}
                              </span>
                            </div>
                            <button
                              type="button"
                              onClick={() => {
                                if (isSelected) {
                                  setRovingDoors((prev) => prev.filter((d) => d.id !== s.id));
                                } else if (rovingDoors.length < 20) {
                                  setRovingDoors((prev) => [
                                    ...prev,
                                    {
                                      id: s.id,
                                      store_name: s.store_name,
                                      area_city: s.area_city || "",
                                      area_province: s.province || s.area_province || "",
                                      island_group: s.island_group || null,
                                      is_new_store: false,
                                    },
                                  ]);
                                }
                              }}
                              className={`rounded px-2 py-0.5 text-[11px] font-semibold ${
                                isSelected
                                  ? "bg-[var(--danger-bg)] text-[var(--danger)]"
                                  : "bg-brand-600 text-white hover:bg-brand-700"
                              }`}
                            >
                              {isSelected ? "Remove" : "Include"}
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Initial Staffing Demand (ensures approved stores immediately get Open Vacancy for Store View) */}
            <div className="space-y-3 rounded-lg border border-border-default bg-surface-base p-4">
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                  <Sparkles className="h-4 w-4 text-brand-600" />
                  Initial Staffing Requirement
                </span>
                <span className="text-[11px] text-text-muted">
                  Auto-creates open vacancy on approval
                </span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-medium text-text-secondary mb-1 block">
                    Position Title <RequiredAsterisk />
                  </label>
                  <select
                    value={selectedPositionId}
                    onChange={(e) => setCustomPositionId(e.target.value)}
                    className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                    required
                  >
                    {positions.length === 0 ? (
                      <option value="">Loading positions...</option>
                    ) : (
                      positions.map((pos) => (
                        <option key={pos.id} value={pos.id}>
                          {pos.position_name}
                        </option>
                      ))
                    )}
                  </select>
                </div>

                <div>
                  <label className="text-xs font-medium text-text-secondary mb-1 block">
                    Initial Headcount <RequiredAsterisk />
                  </label>
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      disabled={requestedHc <= 1}
                      onClick={() => setRequestedHc((prev) => Math.max(1, prev - 1))}
                      className="flex h-9 w-9 items-center justify-center rounded-md border border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover disabled:opacity-40"
                      aria-label="Decrease initial headcount"
                    >
                      <Minus className="h-4 w-4" />
                    </button>
                    <input
                      type="number"
                      min={1}
                      max={20}
                      value={requestedHc}
                      onChange={(e) => {
                        const val = parseInt(e.target.value, 10);
                        if (!isNaN(val) && val >= 1 && val <= 20) {
                          setRequestedHc(val);
                        }
                      }}
                      className="h-9 w-16 rounded-md border border-border-default bg-surface-muted text-center font-mono text-sm font-bold text-text-primary outline-none focus:border-brand-500"
                    />
                    <button
                      type="button"
                      disabled={requestedHc >= 20}
                      onClick={() => setRequestedHc((prev) => Math.min(20, prev + 1))}
                      className="flex h-9 w-9 items-center justify-center rounded-md border border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover disabled:opacity-40"
                      aria-label="Increase initial headcount"
                    >
                      <Plus className="h-4 w-4" />
                    </button>
                  </div>
                </div>
              </div>

              {mode === "roving" && (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
                  <div>
                    <label className="text-xs font-medium text-text-secondary mb-1 block">
                      Target Start / Vacant Date <RequiredAsterisk />
                    </label>
                    <input
                      type="date"
                      value={vacantDate}
                      onChange={(e) => setVacantDate(e.target.value)}
                      className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-1.5 text-sm text-text-primary outline-none focus:border-brand-500"
                    />
                  </div>
                  <div>
                    <label className="text-xs font-medium text-text-secondary mb-1 block">
                      Urgency Tier <RequiredAsterisk />
                    </label>
                    <select
                      value={urgency}
                      onChange={(e) => setUrgency(e.target.value as UrgencyTier)}
                      className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-1.5 text-sm text-text-primary outline-none focus:border-brand-500"
                    >
                      <option value="Critical">Critical (3 days)</option>
                      <option value="High">High (7 days)</option>
                      <option value="Medium">Medium (14 days)</option>
                      <option value="Low">Low (30 days)</option>
                    </select>
                  </div>
                </div>
              )}
            </div>

            {/* Operational Justification (>= 20 chars) */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between">
                <label
                  htmlFor="nsr-reason"
                  className="text-xs font-semibold text-text-primary block"
                >
                  Operational Justification <RequiredAsterisk />
                </label>
                <span className="text-xs text-text-muted">
                  <span
                    className={
                      reason.trim().length >= 20
                        ? "text-text-success font-semibold"
                        : "text-text-danger font-semibold"
                    }
                  >
                    {reason.trim().length}/20 chars min
                  </span>
                </span>
              </div>
              <textarea
                id="nsr-reason"
                rows={3}
                maxLength={500}
                placeholder="State the store opening / expansion rationale (minimum 20 characters required)..."
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                className="w-full rounded-md border border-border-default bg-surface-base p-3 text-sm text-text-primary outline-none focus:border-brand-500 resize-none"
                required
              />
            </div>

            <div className="flex items-center justify-between pt-3 border-t border-border-default">
              <button
                type="button"
                onClick={onClose}
                disabled={isPending}
                className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isPending}
                className="inline-flex items-center gap-1.5 rounded-lg bg-brand-button hover:bg-brand-button-hover px-4 py-2 text-xs font-semibold text-white shadow-xs transition-colors disabled:opacity-50"
              >
                <Store className="h-3.5 w-3.5" />
                <span>
                  {isPending
                    ? "Submitting Request..."
                    : mode === "roving"
                    ? "Submit Roving New Store Request"
                    : "Submit New Store Request"}
                </span>
              </button>
            </div>
          </form>
        )}
      </div>
    </Modal>
  );
}
