"use client";

import { useState } from "react";
import {
  Loader2,
  UserCheck,
  X,
} from "lucide-react";
import { useConfirmApplicantOnboard } from "@/lib/queries/vacancy";
import { useCurrentUser } from "@/lib/auth";

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
      applicant={applicant}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function MarkHiredModalContent({
  applicant,
  onClose,
  onSuccess,
}: {
  applicant: NonNullable<MarkHiredModalProps["applicant"]>;
  onClose: () => void;
  onSuccess?: (workerName: string) => void;
}) {
  const currentUser = useCurrentUser();
  const confirmOnboardMutation = useConfirmApplicantOnboard();

  // Name splitting
  const rawParts = applicant.fullName.split(/,\s*|\s+/);
  const defaultLastName =
    applicant.lastName || (rawParts.length > 1 ? rawParts[0] : applicant.fullName);
  const defaultFirstName =
    applicant.firstName || (rawParts.length > 1 ? rawParts[1] : "");

  const [lastName, setLastName] = useState(defaultLastName);
  const [firstName, setFirstName] = useState(defaultFirstName);
  const [middleName, setMiddleName] = useState(applicant.middleName || "");
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

    confirmOnboardMutation.mutate(
      {
        applicantId: applicant.id,
        lastName: lastName.trim(),
        firstName: firstName.trim(),
        middleName: middleName.trim() || null,
        fullName: `${lastName.trim()}, ${firstName.trim()}`,
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
          onSuccess?.(`${lastName.trim()}, ${firstName.trim()}`);
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to confirm onboarding.");
        },
      },
    );
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-xl rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-emerald-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700 border border-emerald-200">
              <UserCheck className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">
                Confirm Onboarding / Mark Hired
              </h2>
              <p className="text-xs text-gray-500 font-mono">
                {applicant.vcode} &bull; {applicant.fullName}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-4">
          {errorMessage && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700">
              {errorMessage}
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                Last Name *
              </label>
              <input
                type="text"
                required
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                First Name *
              </label>
              <input
                type="text"
                required
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                Middle Name
              </label>
              <input
                type="text"
                value={middleName}
                onChange={(e) => setMiddleName(e.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                Contact Number *
              </label>
              <input
                type="tel"
                required
                value={contactNumber}
                onChange={(e) => setContactNumber(e.target.value)}
                placeholder="09171234567"
                className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                Hired / Deployment Date *
              </label>
              <input
                type="date"
                required
                value={hiredDate}
                onChange={(e) => setHiredDate(e.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                Endorsed By Deployer
              </label>
              <input
                type="text"
                value={endorsedByName}
                onChange={(e) => setEndorsedByName(e.target.value)}
                placeholder="Deployer or Recruiter Name"
                className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              Onboarding Remarks
            </label>
            <textarea
              rows={2}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="e.g. Cleared medical exam, complete 201 file submitted..."
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
            />
          </div>

          {/* Verification checklist matching mobile */}
          <div className="rounded-lg border border-emerald-100 bg-emerald-50/50 p-3">
            <label className="flex items-start gap-2.5 cursor-pointer">
              <input
                type="checkbox"
                checked={requirementsChecked}
                onChange={(e) => setRequirementsChecked(e.target.checked)}
                className="mt-0.5 h-4 w-4 rounded border-gray-300 text-emerald-600 focus:ring-emerald-500"
              />
              <span className="text-xs text-emerald-900 leading-relaxed font-medium">
                I verify that this applicant has passed all pre-employment screenings, is assigned to this slot, and should be moved directly to HR Emploc for deployment.
              </span>
            </label>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-gray-100">
            <button
              type="button"
              onClick={onClose}
              disabled={confirmOnboardMutation.isPending}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={confirmOnboardMutation.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50"
            >
              {confirmOnboardMutation.isPending && (
                <Loader2 className="h-4 w-4 animate-spin" />
              )}
              Confirm Onboard
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
