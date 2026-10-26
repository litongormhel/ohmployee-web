"use client";

import { useState } from "react";
import { Loader2, UserCheck } from "lucide-react";
import { useConfirmApplicantOnboard } from "@/lib/queries/vacancy";
import { useCurrentUser } from "@/lib/auth";
import { formatPersonName, parseCandidateFullName } from "@/lib/utils/formatName";
import { Modal } from "@/components/shared/Modal";

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

  // Name binding and fallback parsing
  const initialNames = parseCandidateFullName(applicant.fullName, {
    firstName: applicant.firstName,
    lastName: applicant.lastName,
    middleName: applicant.middleName,
  });

  const [lastName, setLastName] = useState(initialNames.lastName);
  const [firstName, setFirstName] = useState(initialNames.firstName);
  const [middleName, setMiddleName] = useState(initialNames.middleName);
  const [contactNumber, setContactNumber] = useState(
    applicant.contactNumber || "",
  );
  const [hiredDate, setHiredDate] = useState(
    new Date().toISOString().substring(0, 10),
  );
  const [endorsedByName, setEndorsedByName] = useState(
    currentUser?.displayName || "",
  );
  const [remarks, setRemarks] = useState("");
  const [requirementsChecked, setRequirementsChecked] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

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

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Last Name *
            </label>
            <input
              type="text"
              required
              value={lastName}
              onChange={(e) => setLastName(e.target.value)}
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              First Name *
            </label>
            <input
              type="text"
              required
              value={firstName}
              onChange={(e) => setFirstName(e.target.value)}
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Middle Name
            </label>
            <input
              type="text"
              value={middleName}
              onChange={(e) => setMiddleName(e.target.value)}
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Contact Number *
            </label>
            <input
              type="tel"
              required
              value={contactNumber}
              onChange={(e) => setContactNumber(e.target.value)}
              placeholder="09171234567"
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Hired / Deployment Date *
            </label>
            <input
              type="date"
              required
              value={hiredDate}
              onChange={(e) => setHiredDate(e.target.value)}
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Endorsed By Deployer
            </label>
            <input
              type="text"
              value={endorsedByName}
              onChange={(e) => setEndorsedByName(e.target.value)}
              placeholder="Deployer or Recruiter Name"
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
            />
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
            className="rounded-lg border border-border-default px-4 py-2 text-sm font-medium text-text-secondary hover:bg-surface-hover"
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
