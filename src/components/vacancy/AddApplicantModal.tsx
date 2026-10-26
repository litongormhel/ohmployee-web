"use client";

import { useState, useId } from "react";
import { AlertCircle, CheckCircle, Loader2, UserPlus } from "lucide-react";
import { useEndorseApplicant } from "@/lib/queries/vacancy";
import { useCurrentUser } from "@/lib/auth";
import { Modal } from "@/components/shared/Modal";

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
      isOpen={isOpen}
      vacancy={vacancy}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

export const EndorseApplicantModal = AddApplicantModal;
export type EndorseApplicantModalProps = AddApplicantModalProps;

function AddApplicantModalContent({
  isOpen,
  vacancy,
  onClose,
  onSuccess,
}: {
  isOpen: boolean;
  vacancy: VacancyContextSummary;
  onClose: () => void;
  onSuccess?: (candidateName: string) => void;
}) {
  const firstNameId = useId();
  const middleNameId = useId();
  const lastNameId = useId();
  const contactNumberId = useId();
  const targetOnboardDateId = useId();
  const hrcoRemarksId = useId();

  const currentUser = useCurrentUser();
  const endorseMutation = useEndorseApplicant();

  // Form State initialized fresh on mount
  const [firstName, setFirstName] = useState("");
  const [middleName, setMiddleName] = useState("");
  const [lastName, setLastName] = useState("");
  const [contactNumber, setContactNumber] = useState("");
  const [targetOnboardDate, setTargetOnboardDate] = useState("");
  const [hrcoRemarks, setHrcoRemarks] = useState("");

  const [formError, setFormError] = useState<string | null>(null);
  const [submitted, setSubmitted] = useState(false);
  const [touched, setTouched] = useState<{
    firstName?: boolean;
    middleName?: boolean;
    lastName?: boolean;
    contactNumber?: boolean;
  }>({});

  // Validation
  const trimmedFirstName = firstName.trim();
  const trimmedMiddleName = middleName.trim();
  const trimmedLastName = lastName.trim();
  const digitsOnlyContact = contactNumber.replace(/[^0-9]/g, "");

  // Normalize for validation check: must either be 10 digits starting with 9 or 11 digits starting with 09
  const normalizedContact =
    digitsOnlyContact.length === 10 && digitsOnlyContact.startsWith("9")
      ? `0${digitsOnlyContact}`
      : digitsOnlyContact;

  const isContactValid =
    normalizedContact.length === 11 && normalizedContact.startsWith("09");

  const isFirstNameValid = trimmedFirstName.length > 0;
  const isMiddleNameValid = trimmedMiddleName.length > 0;
  const isLastNameValid = trimmedLastName.length > 0;

  const isFormValid =
    isFirstNameValid &&
    isMiddleNameValid &&
    isLastNameValid &&
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
    setSubmitted(true);
    setFormError(null);

    if (!trimmedFirstName) {
      setFormError("First name is required.");
      return;
    }
    if (!trimmedMiddleName) {
      setFormError("Middle name is required.");
      return;
    }
    if (!trimmedLastName) {
      setFormError("Last name is required.");
      return;
    }
    if (!isContactValid) {
      setFormError(
        "Contact number must be an 11-digit mobile number starting with 09 (e.g., 09171234567)."
      );
      return;
    }

    endorseMutation.mutate(
      {
        vcode: vacancy.vcode,
        firstName: trimmedFirstName,
        middleName: trimmedMiddleName,
        lastName: trimmedLastName,
        contactNumber: normalizedContact,
        targetOnboardDate: targetOnboardDate || null,
        recruiterName: currentUser?.displayName || null,
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
      }
    );
  };

  const accountGroupText =
    vacancy.accountName && vacancy.groupName
      ? `${vacancy.accountName} (${vacancy.groupName})`
      : vacancy.accountName ||
        (vacancy.groupName ? `(${vacancy.groupName})` : "—");

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Add / Endorse Applicant"
      subtitle="Endorse candidate into active requisition and transition to Pipeline"
      icon={UserPlus}
      maxWidthClass="max-w-xl"
      disableBackdropClick={true}
      isSubmitting={endorseMutation.isPending}
      isDirty={Boolean(firstName || middleName || lastName || contactNumber || targetOnboardDate || hrcoRemarks)}
    >
      <form
        onSubmit={handleSubmit}
        className="flex flex-col space-y-4 text-xs"
      >
          {/* Target Requisition Context Header Strip */}
          <div className="flex flex-wrap items-center gap-2 p-2.5 rounded-lg border border-border-subtle bg-surface-subtle text-xs">
            <span className="font-mono font-bold text-text-primary bg-surface-base px-2 py-0.5 rounded border border-border-subtle shadow-2xs">
              {vacancy.vcode}
            </span>
            <div className="flex flex-wrap items-center gap-1.5 text-text-secondary">
              <span className="font-semibold text-text-primary">
                {vacancy.positionTitle || "General Staff"}
              </span>
              <span className="text-text-muted">•</span>
              <span>{vacancy.storeName || "—"}</span>
              <span className="text-text-muted">•</span>
              <span>{accountGroupText}</span>
            </div>
          </div>

          {/* Candidate Form Fields */}
          <div className="space-y-3.5">
            <h3 className="text-xs font-semibold text-text-muted">
              Candidate information
            </h3>

            {/* 3-Column Name Row: First Name *, Middle Name *, Last Name * */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div>
                <label
                  htmlFor={firstNameId}
                  className="block text-xs font-medium text-text-primary mb-1"
                >
                  First Name <span className="text-text-muted">*</span>
                </label>
                <input
                  id={firstNameId}
                  type="text"
                  required
                  value={firstName}
                  onBlur={() =>
                    setTouched((prev) => ({ ...prev, firstName: true }))
                  }
                  onChange={(e) => setFirstName(e.target.value)}
                  placeholder="e.g. Juan"
                  className={`w-full h-9 rounded-md border bg-surface-base px-3 text-xs text-text-primary outline-none placeholder:text-text-muted focus:border-brand-500 focus:ring-1 focus:ring-brand-500 transition-colors ${
                    (submitted || touched.firstName) && !trimmedFirstName
                      ? "border-border-strong focus:border-brand-500"
                      : "border-border-subtle"
                  }`}
                />
                {(submitted || touched.firstName) && !trimmedFirstName && (
                  <p className="mt-1 text-[11px] text-danger-text">
                    First name is required.
                  </p>
                )}
              </div>

              <div>
                <label
                  htmlFor={middleNameId}
                  className="block text-xs font-medium text-text-primary mb-1"
                >
                  Middle Name <span className="text-text-muted">*</span>
                </label>
                <input
                  id={middleNameId}
                  type="text"
                  required
                  value={middleName}
                  onBlur={() =>
                    setTouched((prev) => ({ ...prev, middleName: true }))
                  }
                  onChange={(e) => setMiddleName(e.target.value)}
                  placeholder="e.g. Santos"
                  className={`w-full h-9 rounded-md border bg-surface-base px-3 text-xs text-text-primary outline-none placeholder:text-text-muted focus:border-brand-500 focus:ring-1 focus:ring-brand-500 transition-colors ${
                    (submitted || touched.middleName) && !trimmedMiddleName
                      ? "border-danger-border focus:border-danger-text"
                      : "border-border-subtle"
                  }`}
                />
                {(submitted || touched.middleName) && !trimmedMiddleName && (
                  <p className="mt-1 text-[11px] text-danger-text">
                    Middle name is required.
                  </p>
                )}
              </div>

              <div>
                <label
                  htmlFor={lastNameId}
                  className="block text-xs font-medium text-text-primary mb-1"
                >
                  Last Name <span className="text-text-muted">*</span>
                </label>
                <input
                  id={lastNameId}
                  type="text"
                  required
                  value={lastName}
                  onBlur={() =>
                    setTouched((prev) => ({ ...prev, lastName: true }))
                  }
                  onChange={(e) => setLastName(e.target.value)}
                  placeholder="e.g. Dela Cruz"
                  className={`w-full h-9 rounded-md border bg-surface-base px-3 text-xs text-text-primary outline-none placeholder:text-text-muted focus:border-brand-500 focus:ring-1 focus:ring-brand-500 transition-colors ${
                    (submitted || touched.lastName) && !trimmedLastName
                      ? "border-danger-border focus:border-danger-text"
                      : "border-border-subtle"
                  }`}
                />
                {(submitted || touched.lastName) && !trimmedLastName && (
                  <p className="mt-1 text-[11px] text-danger-text">
                    Last name is required.
                  </p>
                )}
              </div>
            </div>

            {/* Contact & Onboard Row */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <div className="flex items-center justify-between mb-1">
                  <label
                    htmlFor={contactNumberId}
                    className="block text-xs font-medium text-text-primary"
                  >
                    11-Digit Contact Number <span className="text-text-muted">*</span>
                  </label>
                  <span
                    className={`text-[10px] font-mono ${
                      isContactValid
                        ? "text-text-primary font-semibold"
                        : "text-text-muted"
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
                  onBlur={() =>
                    setTouched((prev) => ({ ...prev, contactNumber: true }))
                  }
                  onChange={handleContactChange}
                  placeholder="09XXXXXXXXX"
                  className={`w-full h-9 rounded-md border bg-surface-base px-3 text-xs font-mono outline-none placeholder:text-text-muted transition-colors ${
                    (submitted ||
                      touched.contactNumber ||
                      contactNumber.length > 0) &&
                    !isContactValid
                      ? "border-border-strong bg-surface-muted/30 text-text-primary focus:border-brand-500 focus:ring-1 focus:ring-brand-500"
                      : "border-border-subtle text-text-primary focus:border-brand-500 focus:ring-1 focus:ring-brand-500"
                  }`}
                />
                {(submitted ||
                  touched.contactNumber ||
                  contactNumber.length > 0) &&
                  !isContactValid && (
                    <p className="mt-1 text-[11px] text-danger-text">
                      Must be 11 digits starting with 09 (e.g. 09171234567)
                    </p>
                  )}
              </div>

              <div>
                <label
                  htmlFor={targetOnboardDateId}
                  className="block text-xs font-medium text-text-primary mb-1"
                >
                  Target Onboard Date
                </label>
                <input
                  id={targetOnboardDateId}
                  type="date"
                  value={targetOnboardDate}
                  onChange={(e) => setTargetOnboardDate(e.target.value)}
                  className="w-full h-9 rounded-md border border-border-subtle bg-surface-base px-3 text-xs text-text-primary outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 transition-colors"
                />
              </div>
            </div>

            {/* HRCO Remarks / Notes */}
            <div>
              <label
                htmlFor={hrcoRemarksId}
                className="block text-xs font-medium text-text-primary mb-1"
              >
                HRCO Remarks / Notes{" "}
                <span className="text-text-muted font-normal">(optional)</span>
              </label>
              <textarea
                id={hrcoRemarksId}
                rows={2}
                value={hrcoRemarks}
                onChange={(e) => setHrcoRemarks(e.target.value)}
                placeholder="Candidate background, endorsements, interview findings, or operational notes..."
                className="w-full rounded-md border border-border-subtle bg-surface-base p-2.5 text-xs text-text-primary outline-none placeholder:text-text-muted focus:border-brand-500 focus:ring-1 focus:ring-brand-500 transition-colors"
              />
            </div>
          </div>

          {/* Form Error Message */}
          {formError && (
            <div className="flex items-start gap-2 rounded-lg border border-danger-border bg-danger-bg p-2.5 text-xs text-danger-text">
              <AlertCircle className="h-4 w-4 shrink-0 text-danger-text mt-0.5" />
              <span>{formError}</span>
            </div>
          )}

          {/* Modal Footer Actions */}
          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border-subtle pt-4 mt-auto">
            {/* Endorser Metadata Indicator */}
            <div className="flex items-center gap-1.5 text-xs text-text-secondary">
              <span className="text-text-muted">Endorsed by:</span>
              <span className="inline-flex items-center gap-1 rounded bg-surface-muted px-2 py-0.5 text-xs font-medium text-text-primary border border-border-subtle">
                {currentUser?.displayName || "Current User"}
              </span>
            </div>

            {/* Actions */}
            <div className="flex items-center gap-2.5">
              <button
                type="button"
                onClick={onClose}
                disabled={endorseMutation.isPending}
                className="h-9 rounded-md border border-border-subtle bg-surface-base px-3.5 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors disabled:opacity-50 cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={!isFormValid}
                className="inline-flex h-9 items-center gap-1.5 rounded-md bg-brand-500 px-4 text-xs font-semibold text-white shadow-xs hover:bg-brand-600 disabled:bg-surface-muted disabled:text-text-secondary disabled:border disabled:border-border-default disabled:shadow-none disabled:cursor-not-allowed transition-colors cursor-pointer"
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
          </div>
        </form>
    </Modal>
  );
}
