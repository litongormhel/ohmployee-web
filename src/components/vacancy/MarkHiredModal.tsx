"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Check, ChevronDown, Loader2, Search, UserCheck, X } from "lucide-react";
import { useConfirmApplicantOnboard } from "@/lib/queries/vacancy";
import { useUsersList } from "@/lib/queries/users";
import { useCurrentUser } from "@/lib/auth";
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
        vacancyRequirementId: applicant.vacancyRequirementId || null,
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
