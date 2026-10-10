"use client";

import { useState, useId } from "react";
import { AlertCircle, CheckCircle, Loader2, UserPlus, X } from "lucide-react";
import { useEndorseApplicant } from "@/lib/queries/vacancy";
import { useCurrentUser } from "@/lib/auth";

export interface VacancyContextSummary {
  vcode: string;
  positionTitle?: string | null;
  storeName?: string | null;
  accountName?: string | null;
  groupName?: string | null;
  hrcoName?: string | null;
}

export interface AddApplicantModalProps {
  isOpen: boolean;
  onClose: () => void;
  vacancy: VacancyContextSummary | null;
  onSuccess?: (candidateName: string) => void;
}

export function AddApplicantModal({
  isOpen,
  onClose,
  vacancy,
  onSuccess,
}: AddApplicantModalProps) {
  if (!isOpen || !vacancy) return null;

  return (
    <AddApplicantModalContent
      vacancy={vacancy}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function AddApplicantModalContent({
  vacancy,
  onClose,
  onSuccess,
}: {
  vacancy: VacancyContextSummary;
  onClose: () => void;
  onSuccess?: (candidateName: string) => void;
}) {
  const firstNameId = useId();
  const middleNameId = useId();
  const lastNameId = useId();
  const contactNumberId = useId();
  const targetOnboardDateId = useId();
  const recruiterNameId = useId();
  const hrcoRemarksId = useId();

  const currentUser = useCurrentUser();
  const endorseMutation = useEndorseApplicant();

  // Form State initialized fresh on mount
  const [firstName, setFirstName] = useState("");
  const [middleName, setMiddleName] = useState("");
  const [lastName, setLastName] = useState("");
  const [contactNumber, setContactNumber] = useState("");
  const [targetOnboardDate, setTargetOnboardDate] = useState("");
  const [recruiterName, setRecruiterName] = useState(() => currentUser?.displayName ?? "");
  const [hrcoRemarks, setHrcoRemarks] = useState("");

  const [formError, setFormError] = useState<string | null>(null);

  // Validation
  const trimmedFirstName = firstName.trim();
  const trimmedLastName = lastName.trim();
  const digitsOnlyContact = contactNumber.replace(/[^0-9]/g, "");

  // Normalize for validation check: must either be 10 digits starting with 9 or 11 digits starting with 09
  const normalizedContact =
    digitsOnlyContact.length === 10 && digitsOnlyContact.startsWith("9")
      ? `0${digitsOnlyContact}`
      : digitsOnlyContact;

  const isContactValid =
    normalizedContact.length === 11 && normalizedContact.startsWith("09");

  const isFormValid =
    trimmedFirstName.length > 0 &&
    trimmedLastName.length > 0 &&
    isContactValid &&
    !endorseMutation.isPending;

  const handleContactChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    // Keep numeric characters only
    const val = e.target.value.replace(/[^0-9]/g, "");
    if (val.length <= 11) {
      setContactNumber(val);
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);

    if (!trimmedFirstName) {
      setFormError("First name is required.");
      return;
    }
    if (!trimmedLastName) {
      setFormError("Last name is required.");
      return;
    }
    if (!isContactValid) {
      setFormError("Contact number must be an 11-digit mobile number starting with 09 (e.g., 09171234567).");
      return;
    }

    endorseMutation.mutate(
      {
        vcode: vacancy.vcode,
        firstName: trimmedFirstName,
        lastName: trimmedLastName,
        middleName: middleName.trim() || null,
        contactNumber: normalizedContact,
        targetOnboardDate: targetOnboardDate || null,
        recruiterName: recruiterName.trim() || currentUser?.displayName || null,
        recruiterId: currentUser?.profileId || null,
        hrcoRemarks: hrcoRemarks.trim() || null,
      },
      {
        onSuccess: (result) => {
          onSuccess?.(result.fullName);
          onClose();
        },
        onError: (err) => {
          setFormError(err.message || "Failed to endorse candidate into vacancy.");
        },
      },
    );
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-applicant-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-xl rounded-xl border border-gray-200 bg-white shadow-2xl transition-all overflow-hidden flex flex-col max-h-[92vh]">
        {/* Modal Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-gray-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-50 text-blue-600 border border-blue-100 shadow-2xs">
              <UserPlus className="h-4.5 w-4.5" />
            </div>
            <div>
              <h2
                id="add-applicant-modal-title"
                className="text-base font-semibold text-gray-900"
              >
                Add / Endorse Applicant
              </h2>
              <p className="text-xs text-gray-500">
                Endorse candidate into active requisition and transition to Pipeline
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={endorseMutation.isPending}
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors disabled:opacity-50"
            aria-label="Close modal"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Modal Body */}
        <form onSubmit={handleSubmit} className="flex flex-col flex-1 overflow-y-auto p-6 space-y-5">
          {/* Target Requisition Context Card */}
          <div className="rounded-lg border border-blue-100 bg-blue-50/40 p-4 space-y-2.5">
            <div className="flex items-center justify-between">
              <span className="text-[11px] font-semibold uppercase tracking-wider text-blue-700">
                Target Requisition Context
              </span>
              <span className="font-mono text-xs font-bold text-gray-900 bg-white border border-blue-200 px-2 py-0.5 rounded shadow-2xs">
                {vacancy.vcode}
              </span>
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <div>
                <span className="text-gray-500">Position Title:</span>{" "}
                <span className="font-semibold text-gray-800">
                  {vacancy.positionTitle || "General Staff"}
                </span>
              </div>
              <div>
                <span className="text-gray-500">Outlet / Store:</span>{" "}
                <span className="font-semibold text-gray-800">
                  {vacancy.storeName || "—"}
                </span>
              </div>
              <div>
                <span className="text-gray-500">Account:</span>{" "}
                <span className="font-medium text-gray-700">
                  {vacancy.accountName || "—"}
                </span>
              </div>
              <div>
                <span className="text-gray-500">Group:</span>{" "}
                <span className="font-medium text-gray-700">
                  {vacancy.groupName || "General / Direct"}
                </span>
              </div>
            </div>
          </div>

          {/* Candidate Form Fields */}
          <div className="space-y-4">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-400">
              Candidate Information
            </h3>

            {/* Name Fields: First, Middle, Last */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div>
                <label
                  htmlFor={firstNameId}
                  className="block text-xs font-medium text-gray-700 mb-1"
                >
                  First Name <span className="text-red-500">*</span>
                </label>
                <input
                  id={firstNameId}
                  type="text"
                  required
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  placeholder="e.g. Juan"
                  className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 outline-none placeholder:text-gray-400 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
                />
              </div>

              <div>
                <label
                  htmlFor={middleNameId}
                  className="block text-xs font-medium text-gray-700 mb-1"
                >
                  Middle Name <span className="text-gray-400 font-normal">(optional)</span>
                </label>
                <input
                  id={middleNameId}
                  type="text"
                  value={middleName}
                  onChange={(e) => setMiddleName(e.target.value)}
                  placeholder="e.g. Santos"
                  className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 outline-none placeholder:text-gray-400 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
                />
              </div>

              <div>
                <label
                  htmlFor={lastNameId}
                  className="block text-xs font-medium text-gray-700 mb-1"
                >
                  Last Name <span className="text-red-500">*</span>
                </label>
                <input
                  id={lastNameId}
                  type="text"
                  required
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  placeholder="e.g. Dela Cruz"
                  className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 outline-none placeholder:text-gray-400 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
                />
              </div>
            </div>

            {/* Contact Number & Target Onboard Date */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <div className="flex items-center justify-between mb-1">
                  <label
                    htmlFor={contactNumberId}
                    className="block text-xs font-medium text-gray-700"
                  >
                    11-Digit Contact Number <span className="text-red-500">*</span>
                  </label>
                  <span
                    className={`text-[10px] font-mono ${
                      isContactValid ? "text-emerald-600 font-semibold" : "text-gray-400"
                    }`}
                  >
                    {digitsOnlyContact.length}/11 digits
                  </span>
                </div>
                <input
                  id={contactNumberId}
                  type="tel"
                  required
                  value={contactNumber}
                  onChange={handleContactChange}
                  placeholder="09XXXXXXXXX"
                  className={`w-full rounded-md border px-3 py-2 text-xs font-mono outline-none placeholder:text-gray-400 transition-colors ${
                    contactNumber && !isContactValid
                      ? "border-amber-400 bg-amber-50/20 text-gray-900 focus:border-amber-500 focus:ring-1 focus:ring-amber-500"
                      : "border-gray-300 bg-white text-gray-900 focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                  }`}
                />
                {contactNumber && !isContactValid && (
                  <p className="mt-1 text-[11px] text-amber-600">
                    Must be 11 digits starting with 09
                  </p>
                )}
              </div>

              <div>
                <label
                  htmlFor={targetOnboardDateId}
                  className="block text-xs font-medium text-gray-700 mb-1"
                >
                  Target Onboard Date
                </label>
                <input
                  id={targetOnboardDateId}
                  type="date"
                  value={targetOnboardDate}
                  onChange={(e) => setTargetOnboardDate(e.target.value)}
                  className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
                />
              </div>
            </div>

            {/* Recruiter / Endorsed By */}
            <div>
              <label
                htmlFor={recruiterNameId}
                className="block text-xs font-medium text-gray-700 mb-1"
              >
                Recruiter / Endorsed By
              </label>
              <input
                id={recruiterNameId}
                type="text"
                value={recruiterName}
                onChange={(e) => setRecruiterName(e.target.value)}
                placeholder="Current User Profile"
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-xs text-gray-900 outline-none placeholder:text-gray-400 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
              />
              <p className="mt-1 text-[11px] text-gray-400">
                Defaults to your authenticated account name.
              </p>
            </div>

            {/* HRCO Remarks / Notes */}
            <div>
              <label
                htmlFor={hrcoRemarksId}
                className="block text-xs font-medium text-gray-700 mb-1"
              >
                HRCO Remarks / Notes <span className="text-gray-400 font-normal">(optional)</span>
              </label>
              <textarea
                id={hrcoRemarksId}
                rows={2}
                value={hrcoRemarks}
                onChange={(e) => setHrcoRemarks(e.target.value)}
                placeholder="Candidate background, endorsements, interview findings, or operational notes..."
                className="w-full rounded-md border border-gray-300 bg-white p-2.5 text-xs text-gray-900 outline-none placeholder:text-gray-400 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 transition-colors"
              />
            </div>
          </div>

          {/* Form Error Message */}
          {formError && (
            <div className="flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700">
              <AlertCircle className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
              <span>{formError}</span>
            </div>
          )}

          {/* Modal Footer Actions */}
          <div className="flex items-center justify-end gap-3 border-t border-gray-100 pt-4 mt-auto">
            <button
              type="button"
              onClick={onClose}
              disabled={endorseMutation.isPending}
              className="rounded-md border border-gray-300 bg-white px-4 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50 transition-colors disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!isFormValid}
              className="inline-flex items-center gap-1.5 rounded-md bg-blue-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-blue-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              {endorseMutation.isPending ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Endorsing...</span>
                </>
              ) : (
                <>
                  <CheckCircle className="h-3.5 w-3.5" />
                  <span>Endorse Candidate</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
