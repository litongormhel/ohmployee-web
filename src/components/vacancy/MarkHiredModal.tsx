"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Check, ChevronDown, Loader2, Search, Store, UserCheck, X } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import {
  type AssignedStoreDetail,
  useConfirmApplicantOnboard,
  useVacancyRequirements,
} from "@/lib/queries/vacancy";
import { useUsersList } from "@/lib/queries/users";
import { useCurrentUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/client";
import { formatPersonName, parseCandidateFullName } from "@/lib/utils/formatName";
import { Modal } from "@/components/shared/Modal";
import { RequiredAsterisk } from "@/components/shared/RequiredAsterisk";

export interface MarkHiredModalProps {
  isOpen: boolean;
  onClose: () => void;
  applicant: {
    id: string;
    fullName: string;
    lastName?: string | null;
    firstName?: string | null;
    middleName?: string | null;
    contactNumber?: string | null;
    vcode: string;
    cgCode?: string | null;
    assignedStoreDetails?: AssignedStoreDetail[] | null;
    positionTitle?: string | null;
    vacancyRequirementId?: string | null;
    groupId?: string | null;
    accountId?: string | null;
    endorsedByName?: string | null;
    recruiterName?: string | null;
  } | null;
  onSuccess?: (workerName: string) => void;
}

export function MarkHiredModal({
  isOpen,
  onClose,
  applicant,
  onSuccess,
}: MarkHiredModalProps) {
  if (!isOpen || !applicant) return null;

  return (
    <MarkHiredModalContent
      isOpen={isOpen}
      applicant={applicant}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function MarkHiredModalContent({
  isOpen,
  applicant,
  onClose,
  onSuccess,
}: {
  isOpen: boolean;
  applicant: NonNullable<MarkHiredModalProps["applicant"]>;
  onClose: () => void;
  onSuccess?: (workerName: string) => void;
}) {
  const currentUser = useCurrentUser();
  const confirmOnboardMutation = useConfirmApplicantOnboard();
  const { data: allUsers = [], isLoading: isLoadingUsers } = useUsersList();

  // Name binding and fallback parsing
  const initialNames = parseCandidateFullName(applicant.fullName, {
    firstName: applicant.firstName,
    lastName: applicant.lastName,
    middleName: applicant.middleName,
  });

  const lastName = initialNames.lastName || "";
  const firstName = initialNames.firstName || "";
  const middleName = initialNames.middleName || "";
  const contactNumber = applicant.contactNumber || "";

  const [hiredDate, setHiredDate] = useState(
    new Date().toISOString().substring(0, 10),
  );

  // Deployer endorsement selection
  const initialEndorser =
    applicant.endorsedByName?.trim() ||
    applicant.recruiterName?.trim() ||
    currentUser?.displayName?.trim() ||
    "";

  const [endorsedByName, setEndorsedByName] = useState(initialEndorser);
  const [selectedDeployerId, setSelectedDeployerId] = useState<string | null>(null);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState("");
  const dropdownRef = useRef<HTMLDivElement>(null);

  const [remarks, setRemarks] = useState("");
  const [requirementsChecked, setRequirementsChecked] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Coverage Group Store Footprint resolution (Web parity with Mobile _CoverageOnboardingStoreSelectionSheet)
  const { data: coverageFootprintData, isLoading: isLoadingFootprint } = useQuery({
    queryKey: ["vacancy", "cg-onboarding-footprint", applicant.id, applicant.vcode, applicant.cgCode],
    queryFn: async () => {
      const supabase = createClient();
      let targetCgId: string | null = null;
      let targetCgCode: string | null = applicant.cgCode || (applicant.vcode.startsWith("CG-") ? applicant.vcode : null);

      // 1. Check applicant row for coverage_group_id or vacancy_vcode
      const { data: appRow, error: appErr } = await supabase
        .from("applicants")
        .select("id, coverage_group_id, vacancy_vcode, full_name")
        .eq("id", applicant.id)
        .maybeSingle();
      if (appErr) {
        console.error("[PostgREST Schema Error] MarkHiredModal applicant lookup:", appErr);
      }
      if (appRow?.coverage_group_id) {
        targetCgId = String(appRow.coverage_group_id);
      }

      // 2. Fallback: Resolve coverage_group_id from cgCode or store VCode
      if (!targetCgId && targetCgCode) {
        const { data: cgRow, error: cgErr } = await supabase
          .from("coverage_groups")
          .select("id, coverage_code")
          .eq("coverage_code", targetCgCode)
          .is("archived_at", null)
          .maybeSingle();
        if (cgErr) {
          console.error("[PostgREST Schema Error] MarkHiredModal coverage_groups lookup:", cgErr);
        }
        if (cgRow?.id) {
          targetCgId = String(cgRow.id);
          targetCgCode = String(cgRow.coverage_code || targetCgCode);
        }
      }

      const rawVk = (appRow?.vacancy_vcode || applicant.vcode || "").trim();
      if (!targetCgId && rawVk && !rawVk.startsWith("CG-")) {
        const { data: storeRow, error: storeErr } = await supabase
          .from("stores")
          .select("id")
          .eq("vcode", rawVk)
          .maybeSingle();
        if (storeErr) {
          console.error("[PostgREST Schema Error] MarkHiredModal stores lookup:", storeErr);
        }
        if (storeRow?.id) {
          const { data: cgsMatch, error: cgsErr } = await supabase
            .from("coverage_group_stores")
            .select("coverage_group_id, coverage_groups(id, coverage_code, archived_at)")
            .eq("store_id", storeRow.id)
            .is("archived_at", null)
            .maybeSingle();
          if (cgsErr) {
            console.error("[PostgREST Schema Error] MarkHiredModal coverage_group_stores lookup:", cgsErr);
          }
          if (cgsMatch?.coverage_group_id) {
            const cgObjRaw = cgsMatch.coverage_groups as unknown;
            const cgObj = Array.isArray(cgObjRaw)
              ? (cgObjRaw[0] as Record<string, unknown> | undefined)
              : (cgObjRaw as Record<string, unknown> | null);
            if (!cgObj?.archived_at) {
              targetCgId = String(cgsMatch.coverage_group_id);
              if (cgObj?.coverage_code) targetCgCode = String(cgObj.coverage_code);
            }
          }
        }
      }

      if (!targetCgId) {
        return { cgId: null, cgCode: null, stores: [], isCandidateAlreadyActiveInPlantilla: false };
      }

      const [cgsRes, hslRes, pslRes, activePlRes] = await Promise.all([
        supabase
          .from("coverage_group_stores")
          .select("store_id, is_anchor, hc_share, stores(id, store_name, vcode), coverage_groups(coverage_code)")
          .eq("coverage_group_id", targetCgId)
          .is("archived_at", null),
        supabase
          .from("hr_emploc_store_links")
          .select("store_id, vcode, status")
          .eq("coverage_group_id", targetCgId)
          .eq("status", "Confirmed")
          .is("deleted_at", null),
        supabase
          .from("plantilla_store_links")
          .select("vcode, status")
          .eq("coverage_group_id", targetCgId)
          .eq("status", "Active")
          .is("deleted_at", null),
        supabase
          .from("plantilla")
          .select("id, employee_no, vcode, store_name")
          .eq("coverage_group_id", targetCgId)
          .in("status", ["Active", "On Leave"])
          .or("is_deleted.is.null,is_deleted.eq.false"),
      ]);

      if (cgsRes.error) {
        console.error("[PostgREST Schema Error] MarkHiredModal group stores:", cgsRes.error);
      }

      const confirmedStoreIds = new Set<string>();
      const confirmedVcodes = new Set<string>();
      for (const h of hslRes.data ?? []) {
        if (h.store_id) confirmedStoreIds.add(String(h.store_id));
        if (h.vcode) confirmedVcodes.add(String(h.vcode).toUpperCase());
      }
      for (const p of pslRes.data ?? []) {
        if (p.vcode) confirmedVcodes.add(String(p.vcode).toUpperCase());
      }

      const items = (cgsRes.data ?? []) as Array<Record<string, unknown>>;
      const count = items.length || 1;
      const defaultFraction = `1/${count}`;

      const stores = items
        .map((item) => {
          const sObj = (item.stores as unknown) as Record<string, unknown> | null;
          const storeId = String(item.store_id || sObj?.id || "");
          const storeName = String(sObj?.store_name || "Store");
          const vcode = sObj?.vcode ? String(sObj.vcode) : null;
          const isAnchor = Boolean(item.is_anchor);
          const hcShare = typeof item.hc_share === "number" ? item.hc_share : Number(item.hc_share || 0);
          const slotFraction = hcShare === 0.5 ? "1/2" : hcShare >= 0.33 && hcShare <= 0.34 ? "1/3" : defaultFraction;
          const cgObj = (item.coverage_groups as unknown) as Record<string, unknown> | null;
          if (!targetCgCode && cgObj?.coverage_code) {
            targetCgCode = String(cgObj.coverage_code);
          }

          const alreadyOnboarded =
            (storeId && confirmedStoreIds.has(storeId)) ||
            Boolean(vcode && confirmedVcodes.has(vcode.toUpperCase()));

          return {
            storeId,
            storeName,
            vcode,
            isAnchor,
            slotFraction,
            alreadyOnboarded,
          };
        })
        .filter((s) => Boolean(s.storeId));

      stores.sort((a, b) => (a.isAnchor === b.isAnchor ? a.storeName.localeCompare(b.storeName) : a.isAnchor ? -1 : 1));

      return {
        cgId: targetCgId,
        cgCode: targetCgCode,
        stores,
        isCandidateAlreadyActiveInPlantilla: (activePlRes.data ?? []).length > 0,
      };
    },
    enabled: isOpen,
    staleTime: 10_000,
  });

  const footprintStores = useMemo(
    () => coverageFootprintData?.stores ?? [],
    [coverageFootprintData?.stores],
  );
  const isCoverageGroupOnboarding = footprintStores.length > 1;
  const actionableFootprintStores = useMemo(
    () => footprintStores.filter((s) => !s.alreadyOnboarded),
    [footprintStores],
  );

  // Track user-unchecked store IDs so all actionable stores default to checked without an effect
  const [uncheckedStoreIds, setUncheckedStoreIds] = useState<string[]>([]);

  const selectedStoreIds = useMemo(() => {
    if (!isCoverageGroupOnboarding) return [];
    return actionableFootprintStores
      .filter((s) => !uncheckedStoreIds.includes(s.storeId))
      .map((s) => s.storeId);
  }, [isCoverageGroupOnboarding, actionableFootprintStores, uncheckedStoreIds]);

  const toggleStoreSelection = (storeId: string) => {
    setErrorMessage(null);
    setUncheckedStoreIds((prev) =>
      prev.includes(storeId) ? prev.filter((id) => id !== storeId) : [...prev, storeId],
    );
  };

  // Position requirements disambiguation (ADR-001/002) for legacy candidates without intake requirement tag
  const { data: requirements = [] } = useVacancyRequirements(
    applicant.vacancyRequirementId ? null : applicant.vcode,
    isOpen,
  );

  const [userSelectedRequirementId, setUserSelectedRequirementId] = useState<string | null>(null);

  // Derive effective requirement without triggering setState inside useEffect
  const effectiveRequirementId = useMemo(() => {
    if (applicant.vacancyRequirementId) return applicant.vacancyRequirementId;
    if (userSelectedRequirementId) return userSelectedRequirementId;
    if (requirements.length === 1) return requirements[0].id;
    if (requirements.length > 1) {
      const nonFull = requirements.filter((r) => r.hcFilled < r.hcNeeded);
      if (nonFull.length === 1) return nonFull[0].id;
    }
    return null;
  }, [applicant.vacancyRequirementId, userSelectedRequirementId, requirements]);

  // Filter users eligible to endorse: Deployers, HRCOs, Recruitment, OM, Ops, Admins
  // scoped to the vacancy's group or account, or users with global visibility
  const eligibleUsers = useMemo(() => {
    const targetGroupId = applicant.groupId;
    const targetAccountId = applicant.accountId;

    const filtered = allUsers.filter((u) => {
      if (!u.isActive || u.isArchived) return false;

      const role = (u.roleName || "").toLowerCase();
      const isEligibleRole =
        role.includes("deployer") ||
        role.includes("hrco") ||
        role.includes("recruitment") ||
        role.includes("om") ||
        role.includes("operations") ||
        role.includes("admin");

      if (!isEligibleRole) return false;

      // Global visibility / Super Admins / Head Admins bypass scope check
      if (
        u.hrcoGlobalVisibility ||
        role.includes("super admin") ||
        role.includes("head admin")
      ) {
        return true;
      }

      // Check group / account assignment
      const matchesGroup = targetGroupId ? u.scopedGroupIds?.includes(targetGroupId) : false;
      const matchesAccount = targetAccountId
        ? u.scopes?.some((s) => s.accountId === targetAccountId)
        : false;

      return matchesGroup || matchesAccount;
    });

    filtered.sort((a, b) => a.fullName.localeCompare(b.fullName));
    return filtered;
  }, [allUsers, applicant.groupId, applicant.accountId]);

  // Dynamically resolve deployer user ID without triggering cascading renders in effects
  const resolvedDeployerId = useMemo(() => {
    if (!endorsedByName) return null;
    if (selectedDeployerId) return selectedDeployerId;
    const matched = allUsers.find(
      (u) => u.fullName.toLowerCase().trim() === endorsedByName.toLowerCase().trim(),
    );
    return matched?.id || null;
  }, [endorsedByName, selectedDeployerId, allUsers]);

  // Close dropdown on outside click
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsDropdownOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Filtered dropdown options based on local search term
  const displayedOptions = useMemo(() => {
    const term = searchTerm.toLowerCase().trim();
    if (!term) return eligibleUsers;
    return eligibleUsers.filter(
      (u) =>
        u.fullName.toLowerCase().includes(term) ||
        (u.roleName && u.roleName.toLowerCase().includes(term)) ||
        (u.email && u.email.toLowerCase().includes(term)),
    );
  }, [eligibleUsers, searchTerm]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!currentUser?.profileId) {
      setErrorMessage("Authenticated user profile is required.");
      return;
    }

    if (!requirementsChecked) {
      setErrorMessage("Please verify that all onboarding requirements are met.");
      return;
    }

    const targetRequirementId = effectiveRequirementId || null;
    if (requirements.length > 1 && !targetRequirementId && !isCoverageGroupOnboarding) {
      setErrorMessage("Please select which position requirement this candidate is filling.");
      return;
    }

    if (isCoverageGroupOnboarding && selectedStoreIds.length === 0) {
      setErrorMessage("Please select at least one store from the Coverage Group footprint to onboard now.");
      return;
    }

    const cleanContact = contactNumber.replace(/[^0-9]/g, "");
    const normalizedContact =
      cleanContact.length === 10 && cleanContact.startsWith("9")
        ? `0${cleanContact}`
        : cleanContact;

    const trimmedLast = lastName.trim();
    const trimmedFirst = firstName.trim();
    const trimmedMiddle = middleName.trim() || null;
    const computedFullName = formatPersonName(trimmedFirst, trimmedLast, trimmedMiddle);

    confirmOnboardMutation.mutate(
      {
        applicantId: applicant.id,
        lastName: trimmedLast,
        firstName: trimmedFirst,
        middleName: trimmedMiddle,
        fullName: computedFullName || `${trimmedLast}, ${trimmedFirst}`,
        contactNumber: normalizedContact,
        hiredByUserId: currentUser?.profileId ?? null,
        hiredDate,
        endorsedByDeployerId: resolvedDeployerId || null,
        endorsedByName: endorsedByName.trim() || null,
        remarks: remarks.trim() || null,
        vacancyRequirementId: targetRequirementId || null,
        selectedStoreIds: isCoverageGroupOnboarding ? selectedStoreIds : null,
        cgCode: coverageFootprintData?.cgCode || applicant.cgCode || null,
        vcode: applicant.vcode,
      },
      {
        onSuccess: () => {
          onSuccess?.(computedFullName || `${trimmedLast}, ${trimmedFirst}`);
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to confirm onboarding.");
        },
      },
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Confirm Onboarding / Mark Hired"
      subtitle={`${applicant.vcode} • ${applicant.fullName}`}
      icon={UserCheck}
      maxWidthClass="max-w-xl"
      disableBackdropClick={true}
      isSubmitting={confirmOnboardMutation.isPending}
      isDirty={Boolean(remarks || hiredDate)}
    >
      <form onSubmit={handleSubmit} className="space-y-4 text-xs">
        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text font-medium">
            {errorMessage}
          </div>
        )}

        {/* Read-Only Candidate Name Row */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Last Name <RequiredAsterisk />
            </label>
            <input
              type="text"
              readOnly
              disabled
              value={lastName}
              title="Candidate identity fields are read-only at onboarding. Edit via candidate profile if corrections are needed."
              className="w-full rounded-lg border border-border-default bg-gray-100 dark:bg-surface-muted px-3 py-2 text-sm text-text-secondary cursor-not-allowed select-none opacity-90 shadow-none focus:outline-none"
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              First Name <RequiredAsterisk />
            </label>
            <input
              type="text"
              readOnly
              disabled
              value={firstName}
              title="Candidate identity fields are read-only at onboarding. Edit via candidate profile if corrections are needed."
              className="w-full rounded-lg border border-border-default bg-gray-100 dark:bg-surface-muted px-3 py-2 text-sm text-text-secondary cursor-not-allowed select-none opacity-90 shadow-none focus:outline-none"
            />
          </div>
        </div>

        {/* Read-Only Middle Name & Contact Number Row */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Middle Name
            </label>
            <input
              type="text"
              readOnly
              disabled
              value={middleName}
              title="Candidate identity fields are read-only at onboarding. Edit via candidate profile if corrections are needed."
              className="w-full rounded-lg border border-border-default bg-gray-100 dark:bg-surface-muted px-3 py-2 text-sm text-text-secondary cursor-not-allowed select-none opacity-90 shadow-none focus:outline-none"
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Contact Number <RequiredAsterisk />
            </label>
            <input
              type="tel"
              readOnly
              disabled
              value={contactNumber}
              title="Candidate identity fields are read-only at onboarding. Edit via candidate profile if corrections are needed."
              className="w-full rounded-lg border border-border-default bg-gray-100 dark:bg-surface-muted px-3 py-2 text-sm text-text-secondary cursor-not-allowed select-none opacity-90 shadow-none focus:outline-none font-mono"
            />
          </div>
        </div>

        {/* Roving Coverage Group Store Footprint Selection (Mobile Parity) */}
        {isLoadingFootprint ? (
          <div className="flex items-center gap-2 rounded-lg border border-border-subtle bg-surface-muted/40 p-3 text-xs text-text-muted">
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
            <span>Checking roving coverage group store footprint...</span>
          </div>
        ) : isCoverageGroupOnboarding ? (
          <div className="space-y-2.5 rounded-lg border border-brand-200 dark:border-brand-800/70 bg-brand-50/40 dark:bg-brand-950/20 p-3">
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div className="flex items-center gap-1.5">
                <Store className="h-3.5 w-3.5 text-brand-600 dark:text-brand-400" />
                <span className="text-xs font-bold text-text-primary">
                  Approve Onboarding Store Footprint
                </span>
                <RequiredAsterisk />
                {coverageFootprintData?.cgCode && (
                  <span className="rounded bg-brand-100 dark:bg-brand-900/60 px-1.5 py-0.5 text-[10px] font-mono font-bold text-brand-700 dark:text-brand-300">
                    {coverageFootprintData.cgCode}
                  </span>
                )}
              </div>
              <span className="text-[11px] font-semibold text-text-secondary">
                {selectedStoreIds.length + (footprintStores.length - actionableFootprintStores.length)}/{footprintStores.length} Stores Onboarding
              </span>
            </div>

            <p className="text-[11px] text-text-secondary leading-relaxed">
              Select the store(s) where this roving merchandiser is ready to onboard now. Any unchecked store will remain in the{" "}
              <span className="font-semibold text-text-primary">Pipeline (For Requirements)</span> until its requirements are completed.
            </p>

            <div className="space-y-1.5 pt-1">
              {footprintStores.map((st) => {
                const isAlreadyDone = st.alreadyOnboarded;
                const isChecked = isAlreadyDone || selectedStoreIds.includes(st.storeId);
                return (
                  <label
                    key={st.storeId}
                    className={`flex items-center justify-between gap-2 rounded-md border px-3 py-2 transition ${
                      isAlreadyDone
                        ? "border-emerald-200 bg-emerald-50/60 dark:border-emerald-800/60 dark:bg-emerald-950/30 cursor-default"
                        : isChecked
                        ? "border-brand-400 bg-surface-base dark:border-brand-700 cursor-pointer shadow-2xs"
                        : "border-border-default bg-surface-muted/40 hover:bg-surface-hover cursor-pointer"
                    }`}
                  >
                    <div className="flex items-center gap-2.5 min-w-0">
                      <input
                        type="checkbox"
                        checked={isChecked}
                        disabled={isAlreadyDone}
                        onChange={() => {
                          if (!isAlreadyDone) toggleStoreSelection(st.storeId);
                        }}
                        className="h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500 disabled:opacity-70"
                      />
                      <div className="min-w-0">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="text-xs font-bold text-text-primary truncate">
                            {st.storeName}
                          </span>
                          {st.vcode && (
                            <span className="text-[10px] font-mono text-text-muted">
                              ({st.vcode})
                            </span>
                          )}
                          <span className="rounded bg-surface-muted px-1.5 py-0.5 text-[10px] font-medium text-text-secondary border border-border-subtle">
                            {st.isAnchor ? "Anchor" : "Secondary"} • {st.slotFraction || "1/2"} HC
                          </span>
                        </div>
                      </div>
                    </div>

                    <div className="shrink-0">
                      {isAlreadyDone ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 dark:bg-emerald-900/60 px-2 py-0.5 text-[10px] font-bold text-emerald-800 dark:text-emerald-300 border border-emerald-300 dark:border-emerald-700">
                          <Check className="h-3 w-3" />
                          Already Onboarded
                        </span>
                      ) : isChecked ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-brand-100 dark:bg-brand-900/60 px-2 py-0.5 text-[10px] font-bold text-brand-700 dark:text-brand-300 border border-brand-300 dark:border-brand-700">
                          {coverageFootprintData?.isCandidateAlreadyActiveInPlantilla
                            ? "Fast-Track → Active Plantilla"
                            : "Onboard Now → HR Emploc"}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 dark:bg-amber-950/70 px-2 py-0.5 text-[10px] font-semibold text-amber-800 dark:text-amber-300 border border-amber-300 dark:border-amber-800">
                          Keep in Pipeline (For Requirements)
                        </span>
                      )}
                    </div>
                  </label>
                );
              })}
            </div>
          </div>
        ) : null}

        {/* Multi-Position Disambiguation Selector if not pre-tagged at intake */}
        {requirements.length > 1 && !applicant.vacancyRequirementId && (
          <div className="space-y-2 p-3 rounded-lg border border-border-default bg-surface-subtle">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-text-primary flex items-center gap-1.5">
                <span>Select Position Requirement</span>
                <RequiredAsterisk />
              </span>
              <span className="text-[11px] text-text-muted">
                Choose which position this applicant fills
              </span>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {requirements.map((req) => {
                const isFull = req.hcFilled >= req.hcNeeded;
                const isSelected = effectiveRequirementId === req.id;
                const available = Math.max(0, req.hcNeeded - req.hcFilled);
                return (
                  <button
                    key={req.id}
                    type="button"
                    disabled={isFull}
                    onClick={() => {
                      setUserSelectedRequirementId(req.id);
                      setErrorMessage(null);
                    }}
                    className={`flex flex-col p-2.5 rounded-md border text-left transition-all ${
                      isSelected
                        ? "border-brand-500 bg-brand-50/70 dark:bg-brand-950/40 ring-1 ring-brand-500 shadow-2xs"
                        : isFull
                        ? "opacity-60 bg-surface-muted border-border-subtle cursor-not-allowed"
                        : "border-border-subtle bg-surface-base hover:border-border-default"
                    }`}
                  >
                    <div className="flex items-center justify-between w-full">
                      <span
                        className={`text-xs font-bold truncate ${
                          isSelected
                            ? "text-brand-700 dark:text-brand-300"
                            : isFull
                            ? "text-text-muted line-through"
                            : "text-text-primary"
                        }`}
                      >
                        {req.positionName}
                      </span>
                      {isFull ? (
                        <span className="text-[10px] font-semibold text-danger-text bg-danger-bg px-1.5 py-0.5 rounded border border-danger-border shrink-0">
                          Full
                        </span>
                      ) : (
                        <span className="text-[10px] font-semibold text-brand-700 bg-brand-50 border border-brand-200 dark:bg-zinc-800 dark:text-zinc-300 dark:border-zinc-700 px-1.5 py-0.5 rounded shrink-0">
                          {available} Open
                        </span>
                      )}
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {/* Hired Date & Endorsed By Deployer */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Hired / Deployment Date <RequiredAsterisk />
            </label>
            <input
              type="date"
              required
              value={hiredDate}
              onChange={(e) => setHiredDate(e.target.value)}
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>

          {/* Searchable Select for Endorsed By Deployer */}
          <div className="relative" ref={dropdownRef}>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Endorsed By Deployer
            </label>
            <div
              onClick={() => {
                setIsDropdownOpen((prev) => !prev);
                setSearchTerm("");
              }}
              className="w-full flex items-center justify-between rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary cursor-pointer hover:border-brand-500 transition focus-within:border-brand-500 focus-within:ring-1 focus-within:ring-brand-500"
            >
              <span className={`truncate ${endorsedByName ? "text-text-primary font-medium" : "text-text-muted"}`}>
                {endorsedByName || "Select active deployer / HRCO..."}
              </span>
              <div className="flex items-center gap-1 text-text-muted shrink-0">
                {endorsedByName && (
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      setEndorsedByName("");
                      setSelectedDeployerId(null);
                    }}
                    className="p-0.5 hover:text-text-primary cursor-pointer"
                    title="Clear selection"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                )}
                <ChevronDown className="h-4 w-4" />
              </div>
            </div>

            {/* Dropdown Menu */}
            {isDropdownOpen && (
              <div className="absolute left-0 right-0 top-full mt-1 z-50 rounded-lg border border-border-default bg-surface-base shadow-lg overflow-hidden flex flex-col max-h-60">
                <div className="p-2 border-b border-border-subtle bg-surface-muted/30">
                  <div className="relative">
                    <Search className="h-3.5 w-3.5 absolute left-2.5 top-2.5 text-text-muted pointer-events-none" />
                    <input
                      type="text"
                      autoFocus
                      placeholder="Search active deployer or HRCO..."
                      value={searchTerm}
                      onChange={(e) => setSearchTerm(e.target.value)}
                      className="w-full rounded-md border border-border-default bg-surface-base pl-8 pr-3 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500"
                    />
                  </div>
                </div>

                <div className="overflow-y-auto divide-y divide-border-subtle/50">
                  {/* Graceful preservation of current endorser if not in filtered list */}
                  {endorsedByName &&
                    !eligibleUsers.some(
                      (u) => u.fullName.toLowerCase().trim() === endorsedByName.toLowerCase().trim(),
                    ) && (
                      <button
                        type="button"
                        onClick={() => setIsDropdownOpen(false)}
                        className="w-full text-left px-3 py-2 text-xs flex items-center justify-between bg-surface-selected hover:bg-surface-hover transition cursor-pointer"
                      >
                        <div className="truncate">
                          <div className="font-semibold text-text-primary truncate">
                            {endorsedByName}
                          </div>
                          <div className="text-[10px] text-text-muted">
                            Original Candidate Endorsement
                          </div>
                        </div>
                        <Check className="h-4 w-4 text-brand-600 shrink-0 ml-2" />
                      </button>
                    )}

                  {isLoadingUsers ? (
                    <div className="p-4 text-center text-xs text-text-muted flex items-center justify-center gap-1.5">
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      Loading assigned users...
                    </div>
                  ) : displayedOptions.length === 0 ? (
                    <div className="p-4 text-center text-xs text-text-muted">
                      No matching deployers found.
                    </div>
                  ) : (
                    displayedOptions.map((user) => {
                      const isSelected =
                        endorsedByName.toLowerCase().trim() === user.fullName.toLowerCase().trim();
                      return (
                        <button
                          key={user.id}
                          type="button"
                          onClick={() => {
                            setEndorsedByName(user.fullName);
                            setSelectedDeployerId(user.id);
                            setIsDropdownOpen(false);
                          }}
                          className={`w-full text-left px-3 py-2 text-xs flex items-center justify-between hover:bg-surface-hover transition cursor-pointer ${
                            isSelected ? "bg-surface-selected" : ""
                          }`}
                        >
                          <div className="truncate">
                            <div className="font-medium text-text-primary truncate">
                              {user.fullName}
                            </div>
                            <div className="text-[10px] text-text-muted flex items-center gap-1 mt-0.5">
                              <span className="font-semibold">{user.roleName || "User"}</span>
                              {user.scopeLabel && (
                                <span className="truncate">• {user.scopeLabel}</span>
                              )}
                            </div>
                          </div>
                          {isSelected && (
                            <Check className="h-4 w-4 text-brand-600 shrink-0 ml-2" />
                          )}
                        </button>
                      );
                    })
                  )}
                </div>
              </div>
            )}
          </div>
        </div>

        <div>
          <label className="block text-xs font-semibold text-text-secondary mb-1">
            Onboarding Remarks
          </label>
          <textarea
            rows={2}
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            placeholder="e.g. Cleared medical exam, complete 201 file submitted..."
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>

        {/* Verification checklist matching mobile */}
        <div className="rounded-lg border border-border-default bg-surface-muted/50 p-3">
          <label className="flex items-start gap-2.5 cursor-pointer">
            <input
              type="checkbox"
              checked={requirementsChecked}
              onChange={(e) => setRequirementsChecked(e.target.checked)}
              className="mt-0.5 h-4 w-4 rounded border-border-default text-brand-600 focus:ring-brand-500"
            />
            <span className="text-xs text-text-secondary leading-relaxed font-medium">
              I verify that this applicant has passed all pre-employment screenings, is assigned to this slot, and should be moved directly to HR Emploc for deployment.
            </span>
          </label>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 pt-4 border-t border-border-subtle">
          <button
            type="button"
            onClick={onClose}
            disabled={confirmOnboardMutation.isPending}
            className="rounded-lg border border-border-default px-4 py-2 text-sm font-medium text-text-secondary hover:bg-surface-hover cursor-pointer"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={confirmOnboardMutation.isPending}
            className="inline-flex items-center gap-2 rounded-lg bg-brand-500 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-600 disabled:bg-surface-muted disabled:text-text-secondary disabled:border disabled:border-border-default disabled:shadow-none disabled:cursor-not-allowed cursor-pointer"
          >
            {confirmOnboardMutation.isPending && (
              <Loader2 className="h-4 w-4 animate-spin" />
            )}
            Confirm Onboard
          </button>
        </div>
      </form>
    </Modal>
  );
}
