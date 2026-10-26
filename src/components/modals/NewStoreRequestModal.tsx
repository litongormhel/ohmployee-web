"use client";

import { useState, useEffect, useMemo } from "react";
import Link from "next/link";
import {
  AlertCircle,
  AlertTriangle,
  Building2,
  CheckCircle2,
  ExternalLink,
  Sparkles,
  Store,
  X,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import {
  useSubmitNewStoreRequest,
  type SubmitNewStoreRequestResult,
} from "@/lib/queries/requests";

export interface NewStoreRequestModalProps {
  isOpen: boolean;
  onClose: () => void;
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
  onSuccess?: (result: {
    requestId: string;
    storeName: string;
    province: string;
    city: string;
    accountName: string;
    accountId: string;
  }) => void;
}

export function NewStoreRequestModal(props: NewStoreRequestModalProps) {
  if (!props.isOpen) return null;

  return <NewStoreRequestModalDialog {...props} />;
}

function NewStoreRequestModalDialog({
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
  existingStores = [],
  onSuccess,
}: NewStoreRequestModalProps) {
  const submitMutation = useSubmitNewStoreRequest();

  const [storeName, setStoreName] = useState(initialStoreName || "");
  const [province, setProvince] = useState(initialProvince || "");
  const [city, setCity] = useState(initialCity || "");
  const [reason, setReason] = useState("");
  const [fetchedGroupId, setFetchedGroupId] = useState<string | null>(null);
  const resolvedGroupId = initialGroupId || fetchedGroupId;
  const [fetchedProvinces, setFetchedProvinces] = useState<string[]>([]);
  const [fetchedCities, setFetchedCities] = useState<string[]>([]);
  const [formError, setFormError] = useState<string | null>(null);
  const [submittedResult, setSubmittedResult] =
    useState<SubmitNewStoreRequestResult | null>(null);

  // Look up account group_id if not provided
  useEffect(() => {
    if (initialGroupId || !initialAccountId) return;
    const supabase = createClient();
    let isMounted = true;
    async function loadAccountGroup() {
      try {
        const { data } = await supabase
          .from("accounts")
          .select("group_id")
          .eq("id", initialAccountId)
          .maybeSingle();
        if (isMounted && data?.group_id) {
          setFetchedGroupId(data.group_id);
        }
      } catch {
        // Fallback
      }
    }
    loadAccountGroup();
    return () => {
      isMounted = false;
    };
  }, [initialAccountId, initialGroupId]);

  // Available provinces
  const availableProvinces = useMemo(() => {
    if (propProvinces && propProvinces.length > 0) return propProvinces;
    return fetchedProvinces;
  }, [propProvinces, fetchedProvinces]);

  // Load provinces if not provided
  useEffect(() => {
    if (propProvinces && propProvinces.length > 0) return;
    const supabase = createClient();
    let isMounted = true;
    async function loadProvinces() {
      try {
        const { data } = await supabase
          .from("ref_locations")
          .select("province")
          .eq("is_active", true)
          .order("province");
        if (isMounted && data) {
          const unique = Array.from(
            new Set(
              data
                .map((r: { province: string | null }) => r.province?.trim() || "")
                .filter(Boolean)
            )
          ).sort();
          setFetchedProvinces(unique);
        }
      } catch {
        // Fallback
      }
    }
    loadProvinces();
    return () => {
      isMounted = false;
    };
  }, [propProvinces]);

  // Available cities
  const availableCities = useMemo(() => {
    if (fetchedCities.length > 0) return fetchedCities;
    if (propCities && propCities.length > 0 && province === initialProvince) {
      return propCities;
    }
    return [];
  }, [fetchedCities, propCities, province, initialProvince]);

  // Load cities when province changes
  useEffect(() => {
    if (!province) return;
    const supabase = createClient();
    let isMounted = true;
    async function loadCities() {
      try {
        const { data } = await supabase
          .from("ref_locations")
          .select("city")
          .eq("province", province)
          .eq("is_active", true)
          .order("city");
        if (isMounted && data) {
          const unique = Array.from(
            new Set(
              data
                .map((r: { city: string | null }) => r.city?.trim() || "")
                .filter(Boolean)
            )
          ).sort();
          setFetchedCities(unique);
        }
      } catch {
        if (isMounted) setFetchedCities([]);
      }
    }
    loadCities();
    return () => {
      isMounted = false;
    };
  }, [province]);

  // Client duplicate warning check
  const duplicateWarning = (() => {
    if (!storeName.trim() || !province.trim()) return null;
    const nameLower = storeName.trim().toLowerCase();
    const provLower = province.trim().toLowerCase();
    const cityLower = city.trim().toLowerCase();

    const match = existingStores.find((s) => {
      const sName = s.store_name.trim().toLowerCase();
      const sProv = (s.province || s.area_province || "").trim().toLowerCase();
      const sCity = (s.area_city || "").trim().toLowerCase();
      if (sName !== nameLower) return false;
      if (sProv && sProv !== provLower) return false;
      if (cityLower && sCity && sCity !== cityLower) return false;
      return true;
    });

    if (match) {
      return `A store named "${match.store_name}" already exists under this account (${match.area_city || ""}, ${match.province || match.area_province || ""}).`;
    }
    return null;
  })();

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);

    const trimmedStore = storeName.trim();
    const trimmedProv = province.trim();
    const trimmedCity = city.trim();
    const trimmedReason = reason.trim();

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
    if (!initialAccountId) {
      setFormError("Operational account is required.");
      return;
    }
    if (!trimmedReason) {
      setFormError("Reason for requesting new store is required.");
      return;
    }

    submitMutation.mutate(
      {
        store_name: trimmedStore,
        province: trimmedProv,
        city: trimmedCity,
        account_id: initialAccountId,
        account_name: initialAccountName || "Scoped Account",
        group_id: resolvedGroupId || null,
        reason: trimmedReason,
        position: initialPosition || null,
        requested_hc: initialRequestedHc || null,
      },
      {
        onSuccess: (res) => {
          setSubmittedResult(res);
        },
        onError: (err) => {
          setFormError(
            err.message || "Failed to submit new store request. Please try again."
          );
        },
      }
    );
  };

  const handleLinkToRequisition = () => {
    if (!submittedResult) return;
    onSuccess?.({
      requestId: submittedResult.request_id,
      storeName: storeName.trim(),
      province: province.trim(),
      city: city.trim(),
      accountName: initialAccountName || "Scoped Account",
      accountId: initialAccountId || "",
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/60 backdrop-blur-xs transition-opacity"
        onClick={submitMutation.isPending ? undefined : onClose}
        aria-hidden="true"
      />

      {/* Modal Dialog Card */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="new-store-modal-title"
        className="relative z-10 w-full max-w-lg rounded-xl border border-border-default bg-surface-base shadow-2xl transition-all my-8 flex flex-col overflow-hidden"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-default px-6 py-4 shrink-0 bg-surface-base">
          <div className="flex items-center gap-3">
            <div className="rounded-lg bg-[var(--surface-sunken)] p-2 text-[var(--foreground)] border border-[var(--border-subtle)]">
              <Store className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="rounded bg-[var(--surface-sunken)] px-2 py-0.5 text-xs font-bold uppercase tracking-wider text-[var(--foreground)] border border-[var(--border-subtle)]">
                  New Store Request (NSR)
                </span>
              </div>
              <h2
                id="new-store-modal-title"
                className="text-base font-bold text-text-primary"
              >
                Request Store Addition
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

        {/* Content Body */}
        <div className="p-6 space-y-5 overflow-y-auto max-h-[75vh]">
          {submittedResult ? (
            /* Success State */
            <div className="space-y-5 text-center py-2">
              <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-[var(--surface-muted)] text-[var(--foreground)] border border-[var(--border-subtle)]">
                <CheckCircle2 className="h-7 w-7" />
              </div>
              <div className="space-y-1.5">
                <h3 className="text-base font-bold text-text-primary">
                  New Store Request Submitted!
                </h3>
                <p className="text-xs text-text-muted max-w-sm mx-auto">
                  Your request to register{" "}
                  <strong className="text-text-primary font-semibold">
                    {storeName}
                  </strong>{" "}
                  under{" "}
                  <strong className="text-text-primary font-semibold">
                    {initialAccountName || "Scoped Account"}
                  </strong>{" "}
                  has been submitted for Head Admin / Super Admin review.
                </p>
              </div>

              <div className="rounded-lg border border-border-default bg-surface-muted p-3 text-left text-xs space-y-1.5">
                <div className="flex justify-between">
                  <span className="text-text-muted font-medium">Request Status:</span>
                  <span className="rounded bg-[var(--surface-sunken)] px-2 py-0.5 text-xs font-bold text-[var(--foreground)] uppercase border border-[var(--border-subtle)]">
                    Pending Review
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-muted font-medium">Location:</span>
                  <span className="font-semibold text-text-primary">
                    {[city, province].filter(Boolean).join(", ")}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-muted font-medium">Request Reference:</span>
                  <span className="font-mono text-[11px] text-text-secondary">
                    {submittedResult.request_id}
                  </span>
                </div>
              </div>

              <div className="flex flex-col gap-2.5 pt-2">
                <button
                  type="button"
                  onClick={handleLinkToRequisition}
                  className="w-full inline-flex items-center justify-center gap-1.5 rounded-lg bg-brand-600 px-4 py-2.5 text-xs font-semibold text-white shadow-xs hover:bg-brand-700 transition-colors"
                >
                  <Sparkles className="h-3.5 w-3.5" />
                  <span>Link to Headcount Requisition</span>
                </button>
                <Link
                  href="/approvals"
                  onClick={onClose}
                  className="w-full inline-flex items-center justify-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-medium text-text-secondary hover:bg-surface-hover transition-colors"
                >
                  <ExternalLink className="h-3.5 w-3.5 text-text-muted" />
                  <span>View in Request Center (/approvals)</span>
                </Link>
              </div>
            </div>
          ) : (
            /* Form View */
            <form onSubmit={handleSubmit} className="space-y-4">
              {/* Account Scope Badge */}
              <div className="rounded-lg border border-border-default bg-surface-muted p-3 flex items-center justify-between">
                <span className="text-xs font-semibold uppercase tracking-wider text-text-secondary flex items-center gap-1.5">
                  <Building2 className="h-4 w-4 text-text-muted" />
                  Target Account
                </span>
                <span className="inline-flex items-center rounded-md bg-brand-50 px-2.5 py-1 text-xs font-semibold text-brand-700 ring-1 ring-inset ring-brand-700/10">
                  {initialAccountName || "Scoped Account"}
                </span>
              </div>

              {/* Form Errors */}
              {formError && (
                <div className="flex items-start gap-2.5 rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger)]">
                  <AlertCircle className="h-4 w-4 shrink-0 text-[var(--danger)] mt-0.5" />
                  <span>{formError}</span>
                </div>
              )}

              {/* Duplicate Warning */}
              {duplicateWarning && (
                <div className="flex items-start gap-2.5 rounded-lg border border-[var(--border-subtle)] bg-[var(--surface-muted)] p-3 text-xs text-[var(--foreground)]">
                  <AlertTriangle className="h-4 w-4 shrink-0 text-[var(--text-muted)] mt-0.5" />
                  <span>{duplicateWarning}</span>
                </div>
              )}

              {/* Store Name */}
              <div className="space-y-1">
                <label
                  htmlFor="nsr-store-name"
                  className="text-xs font-semibold text-text-primary block"
                >
                  Store Name <span className="text-[var(--danger)]">*</span>
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

              {/* Province & City Selection */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="space-y-1">
                  <label
                    htmlFor="nsr-province"
                    className="text-xs font-semibold text-text-primary block"
                  >
                    Province <span className="text-[var(--danger)]">*</span>
                  </label>
                  <select
                    id="nsr-province"
                    value={province}
                    onChange={(e) => {
                      setProvince(e.target.value);
                      setCity("");
                      setFetchedCities([]);
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
                    City / Municipality <span className="text-[var(--danger)]">*</span>
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

              {/* Optional Requisition Context */}
              {(initialPosition || initialRequestedHc) && (
                <div className="rounded-lg border border-border-default bg-surface-muted/60 p-3 text-xs space-y-1 text-text-secondary">
                  <span className="font-semibold text-text-primary block">
                    Requisition Context
                  </span>
                  {initialPosition && (
                    <div>Position Target: {initialPosition}</div>
                  )}
                  {initialRequestedHc && (
                    <div>Requested Headcount Quota: {initialRequestedHc} slot(s)</div>
                  )}
                </div>
              )}

              {/* Reason / Justification */}
              <div className="space-y-1">
                <label
                  htmlFor="nsr-reason"
                  className="text-xs font-semibold text-text-primary block"
                >
                  Justification / Operational Reason <span className="text-[var(--danger)]">*</span>
                </label>
                <textarea
                  id="nsr-reason"
                  rows={3}
                  placeholder="State the reason for this store addition (e.g., upcoming branch grand opening, contract expansion)..."
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary outline-none focus:border-brand-500"
                  required
                />
              </div>

              {/* Form Action Buttons */}
              <div className="flex items-center justify-between pt-3 border-t border-border-default">
                <button
                  type="button"
                  onClick={onClose}
                  disabled={submitMutation.isPending}
                  className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors"
                >
                  Cancel / Back to Search
                </button>
                <button
                  type="submit"
                  disabled={submitMutation.isPending}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-[var(--foreground)] px-4 py-2 text-xs font-semibold text-[var(--card)] shadow-xs hover:opacity-90 transition-opacity disabled:opacity-50"
                >
                  {submitMutation.isPending ? (
                    <span>Submitting NSR...</span>
                  ) : (
                    <>
                      <Store className="h-3.5 w-3.5" />
                      <span>Submit New Store Request</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
