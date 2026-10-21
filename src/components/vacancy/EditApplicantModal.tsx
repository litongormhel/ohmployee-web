"use client";

import { useState, useId } from "react";
import { AlertCircle, AlertTriangle, CheckCircle2, Edit3, Loader2, ShieldAlert, X } from "lucide-react";
import { useUpdateApplicantProfile } from "@/lib/queries/vacancy";
import { useCurrentUser } from "@/lib/auth";
import { hasFullAccess, canEditApplicantProfile } from "@/lib/rbac";

export interface EditApplicantTarget {
  applicantId: string;
  displayName?: string | null;
  firstName?: string | null;
  middleName?: string | null;
  lastName?: string | null;
  contactNumber?: string | null;
  profileEditCount?: number | null;
  statusLabel?: string | null;
  vcode?: string | null;
  positionTitle?: string | null;
}

export interface EditApplicantModalProps {
  isOpen: boolean;
  onClose: () => void;
  applicant: EditApplicantTarget | null;
  onSuccess?: (updatedName: string) => void;
}

export function EditApplicantModal({
  isOpen,
  onClose,
  applicant,
  onSuccess,
}: EditApplicantModalProps) {
  if (!isOpen || !applicant) return null;

  return (
    <EditApplicantModalContent
      key={applicant.applicantId}
      applicant={applicant}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function EditApplicantModalContent({
  applicant,
  onClose,
  onSuccess,
}: {
  applicant: EditApplicantTarget;
  onClose: () => void;
  onSuccess?: (updatedName: string) => void;
}) {
  const firstNameId = useId();
  const middleNameId = useId();
  const lastNameId = useId();
  const contactNumberId = useId();
  const reasonId = useId();

  const currentUser = useCurrentUser();
  const updateMutation = useUpdateApplicantProfile();

  const isUserFullAccess = hasFullAccess(currentUser);
  const isUserAuthorized = canEditApplicantProfile(currentUser);

  // Locked statuses from database RPC: confirmed_onboard, transferred, hired
  const statusNorm = (applicant.statusLabel || "").toLowerCase().replace(/[\s_-]+/g, "");
  const isLockedStatus =
    statusNorm === "confirmedonboard" ||
    statusNorm === "transferred" ||
    statusNorm === "hired";

  const editCount = applicant.profileEditCount ?? 0;
  const isOneTimeUsed = editCount >= 1;
  const isOverrideMode = isOneTimeUsed && isUserFullAccess;
  const isBlockedByEditLimit = isOneTimeUsed && !isUserFullAccess;

  // Form State
  const [firstName, setFirstName] = useState(applicant.firstName || "");
  const [middleName, setMiddleName] = useState(applicant.middleName || "");
  const [lastName, setLastName] = useState(applicant.lastName || "");
  const [contactNumber, setContactNumber] = useState(applicant.contactNumber || "");
  const [reason, setReason] = useState("");

  const [formError, setFormError] = useState<string | null>(null);
  const [isConfirming, setIsConfirming] = useState(false);
  const [touched, setTouched] = useState<{
    firstName?: boolean;
    middleName?: boolean;
    lastName?: boolean;
    contactNumber?: boolean;
    reason?: boolean;
  }>({});

  const trimmedFirstName = firstName.trim();
  const trimmedMiddleName = middleName.trim();
  const trimmedLastName = lastName.trim();
  const trimmedReason = reason.trim();
  const digitsOnlyContact = contactNumber.replace(/[^0-9]/g, "");

  const normalizedContact =
    digitsOnlyContact.length === 10 && digitsOnlyContact.startsWith("9")
      ? `0${digitsOnlyContact}`
      : digitsOnlyContact;

  const isContactValid =
    normalizedContact.length === 11 && normalizedContact.startsWith("09");

  const isFirstNameValid = trimmedFirstName.length > 0;
  const isMiddleNameValid = trimmedMiddleName.length > 0;
  const isLastNameValid = trimmedLastName.length > 0;
  const isReasonValid = trimmedReason.length > 0;

  // Check if any field differs from current
  const origFirst = (applicant.firstName || "").trim().toUpperCase();
  const origLast = (applicant.lastName || "").trim().toUpperCase();
  const origMiddle = (applicant.middleName || "").trim().toUpperCase();
  const origContact = (applicant.contactNumber || "").replace(/[^0-9]/g, "");
  const origNormalizedContact =
    origContact.length === 10 && origContact.startsWith("9")
      ? `0${origContact}`
      : origContact;

  const currentFirst = trimmedFirstName.toUpperCase();
  const currentLast = trimmedLastName.toUpperCase();
  const currentMiddle = trimmedMiddleName.toUpperCase();
  const currentContact = normalizedContact;

  const hasFieldChanges =
    currentFirst !== origFirst ||
    currentLast !== origLast ||
    currentMiddle !== origMiddle ||
    currentContact !== origNormalizedContact;

  const isFormValid =
    isFirstNameValid &&
    isMiddleNameValid &&
    isLastNameValid &&
    isContactValid &&
    isReasonValid &&
    hasFieldChanges &&
    !isBlockedByEditLimit &&
    !isLockedStatus &&
    isUserAuthorized &&
    !updateMutation.isPending;

  const handleContactChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value.replace(/[^0-9]/g, "");
    if (val.length <= 11) {
      setContactNumber(val);
    }
  };

  const handleInitialSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);

    if (isLockedStatus) {
      setFormError("Applicant profile is locked because candidate has progressed beyond the Vacancy pipeline.");
      return;
    }
    if (isBlockedByEditLimit) {
      setFormError("One-time profile edit already used for this applicant. Head Admin or Super Admin override required.");
      return;
    }
    if (!trimmedFirstName) {
      setFormError("First name is required.");
      return;
    }
    if (!trimmedMiddleName) {
      setFormError("Middle name is required. Enter NA if not applicable.");
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
    if (!trimmedReason) {
      setFormError("Reason / comments are required explaining this profile edit.");
      return;
    }
    if (!hasFieldChanges) {
      setFormError("No field changes detected. At least one detail (name or contact) must differ from current values.");
      return;
    }

    // Advance to confirmation modal dialog
    setIsConfirming(true);
  };

  const handleConfirmSave = () => {
    setFormError(null);

    updateMutation.mutate(
      {
        applicantId: applicant.applicantId,
        firstName: trimmedFirstName,
        middleName: trimmedMiddleName,
        lastName: trimmedLastName,
        contactNumber: normalizedContact,
        reason: trimmedReason,
        vcode: applicant.vcode || undefined,
      },
      {
        onSuccess: () => {
          const formattedFullName = `${trimmedLastName.toUpperCase()}, ${trimmedFirstName.toUpperCase()}${
            trimmedMiddleName && !["NA", "N/A", "NONE"].includes(trimmedMiddleName.toUpperCase())
              ? " " + trimmedMiddleName.toUpperCase()
              : ""
          }`;
          onSuccess?.(formattedFullName);
          onClose();
        },
        onError: (err) => {
          setIsConfirming(false);
          setFormError(err.message || "Failed to update applicant details.");
        },
      }
    );
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="edit-applicant-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl bg-surface border border-border shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-border bg-surface-muted/50">
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-lg bg-blue-50 text-blue-700 border border-blue-200">
              <Edit3 className="h-5 w-5" aria-hidden="true" />
            </div>
            <div>
              <h2 id="edit-applicant-title" className="text-base font-bold text-text-primary">
                Edit Applicant Details
              </h2>
              <p className="text-xs text-text-muted">
                {applicant.vcode ? `Requisition: ${applicant.vcode}` : "Candidate Identity Correction"}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-lg text-text-muted hover:text-text-primary hover:bg-surface-muted transition-colors cursor-pointer"
            aria-label="Close dialog"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Content Body */}
        <div className="p-6 overflow-y-auto space-y-4 text-xs">
          {/* Status Banners */}
          {isLockedStatus && (
            <div className="p-3 rounded-lg border border-red-200 bg-red-50 text-red-800 flex items-start gap-2">
              <ShieldAlert className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
              <div>
                <p className="font-semibold">Candidate Profile Locked</p>
                <p className="text-[11px] text-red-700 mt-0.5">
                  This applicant has progressed beyond the Vacancy pipeline ({applicant.statusLabel}). Profile changes must be requested through HR Emploc corrections.
                </p>
              </div>
            </div>
          )}

          {isBlockedByEditLimit && !isLockedStatus && (
            <div className="p-3 rounded-lg border border-amber-200 bg-amber-50 text-amber-800 flex items-start gap-2">
              <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5 text-amber-600" />
              <div>
                <p className="font-semibold">One-Time Edit Already Used</p>
                <p className="text-[11px] text-amber-700 mt-0.5">
                  Applicant details can be edited only once to protect downstream payroll and HR records. A Head Admin or Super Admin override is required to make further corrections.
                </p>
              </div>
            </div>
          )}

          {isOverrideMode && !isLockedStatus && (
            <div className="p-3 rounded-lg border border-purple-200 bg-purple-50 text-purple-800 flex items-start gap-2">
              <ShieldAlert className="h-4 w-4 shrink-0 mt-0.5 text-purple-600" />
              <div>
                <p className="font-semibold">Administrator Override Mode Active</p>
                <p className="text-[11px] text-purple-700 mt-0.5">
                  This applicant has already used their standard profile edit. As a full-access administrator, your update will be recorded as an audit override without resetting the caller limit.
                </p>
              </div>
            </div>
          )}

          {!isOneTimeUsed && !isLockedStatus && (
            <div className="p-3 rounded-lg border border-blue-200 bg-blue-50 text-blue-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-blue-600" />
              <div>
                <p className="font-semibold">One-Time Policy Warning</p>
                <p className="text-[11px] text-blue-700 mt-0.5">
                  Applicant details can only be edited once. Please ensure exact legal name spelling and correct phone digits to prevent downstream correction issues in HR Emploc.
                </p>
              </div>
            </div>
          )}

          {formError && (
            <div className="p-3 rounded-lg border border-red-200 bg-red-50 text-red-700 flex items-start gap-2 animate-in fade-in">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
              <span>{formError}</span>
            </div>
          )}

          {/* Form Fields */}
          <form id="edit-applicant-form" onSubmit={handleInitialSubmit} className="space-y-3.5">
            {/* Last Name */}
            <div>
              <label htmlFor={lastNameId} className="block font-semibold text-text-primary mb-1">
                Last Name <span className="text-red-600">*</span>
              </label>
              <input
                id={lastNameId}
                type="text"
                disabled={isLockedStatus || isBlockedByEditLimit || updateMutation.isPending}
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                onBlur={() => setTouched((p) => ({ ...p, lastName: true }))}
                placeholder="e.g. DELA CRUZ"
                className={`w-full rounded-lg border px-3 py-2 text-text-primary uppercase tracking-wide focus:outline-none focus:ring-2 focus:ring-blue-500/20 ${
                  touched.lastName && !isLastNameValid
                    ? "border-red-500 bg-red-50/20"
                    : "border-border bg-surface"
                }`}
              />
              {touched.lastName && !isLastNameValid && (
                <p className="mt-1 text-[11px] text-red-600">Last name is required.</p>
              )}
            </div>

            {/* First Name */}
            <div>
              <label htmlFor={firstNameId} className="block font-semibold text-text-primary mb-1">
                First Name <span className="text-red-600">*</span>
              </label>
              <input
                id={firstNameId}
                type="text"
                disabled={isLockedStatus || isBlockedByEditLimit || updateMutation.isPending}
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                onBlur={() => setTouched((p) => ({ ...p, firstName: true }))}
                placeholder="e.g. JUAN"
                className={`w-full rounded-lg border px-3 py-2 text-text-primary uppercase tracking-wide focus:outline-none focus:ring-2 focus:ring-blue-500/20 ${
                  touched.firstName && !isFirstNameValid
                    ? "border-red-500 bg-red-50/20"
                    : "border-border bg-surface"
                }`}
              />
              {touched.firstName && !isFirstNameValid && (
                <p className="mt-1 text-[11px] text-red-600">First name is required.</p>
              )}
            </div>

            {/* Middle Name */}
            <div>
              <label htmlFor={middleNameId} className="block font-semibold text-text-primary mb-1">
                Middle Name <span className="text-red-600">*</span>{" "}
                <span className="text-text-muted font-normal">(enter NA if not applicable)</span>
              </label>
              <input
                id={middleNameId}
                type="text"
                disabled={isLockedStatus || isBlockedByEditLimit || updateMutation.isPending}
                value={middleName}
                onChange={(e) => setMiddleName(e.target.value)}
                onBlur={() => setTouched((p) => ({ ...p, middleName: true }))}
                placeholder="e.g. SANTOS or NA"
                className={`w-full rounded-lg border px-3 py-2 text-text-primary uppercase tracking-wide focus:outline-none focus:ring-2 focus:ring-blue-500/20 ${
                  touched.middleName && !isMiddleNameValid
                    ? "border-red-500 bg-red-50/20"
                    : "border-border bg-surface"
                }`}
              />
              {touched.middleName && !isMiddleNameValid && (
                <p className="mt-1 text-[11px] text-red-600">Middle name or NA is required.</p>
              )}
            </div>

            {/* Contact Number */}
            <div>
              <label htmlFor={contactNumberId} className="block font-semibold text-text-primary mb-1">
                Contact Number (11-digit mobile) <span className="text-red-600">*</span>
              </label>
              <input
                id={contactNumberId}
                type="tel"
                disabled={isLockedStatus || isBlockedByEditLimit || updateMutation.isPending}
                value={contactNumber}
                onChange={handleContactChange}
                onBlur={() => setTouched((p) => ({ ...p, contactNumber: true }))}
                placeholder="09171234567"
                maxLength={11}
                className={`w-full rounded-lg border px-3 py-2 font-mono text-text-primary focus:outline-none focus:ring-2 focus:ring-blue-500/20 ${
                  touched.contactNumber && !isContactValid
                    ? "border-red-500 bg-red-50/20"
                    : "border-border bg-surface"
                }`}
              />
              {touched.contactNumber && !isContactValid && (
                <p className="mt-1 text-[11px] text-red-600">
                  Must be 11 digits starting with 09 (e.g., 09171234567).
                </p>
              )}
            </div>

            {/* Comments / Reason */}
            <div>
              <label htmlFor={reasonId} className="block font-semibold text-text-primary mb-1">
                Reason / Comments <span className="text-red-600">*</span>
              </label>
              <textarea
                id={reasonId}
                rows={2}
                disabled={isLockedStatus || isBlockedByEditLimit || updateMutation.isPending}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                onBlur={() => setTouched((p) => ({ ...p, reason: true }))}
                placeholder="Explain reason for editing candidate profile (e.g., Corrected misspelled middle name per valid ID)..."
                className={`w-full rounded-lg border px-3 py-2 text-text-primary focus:outline-none focus:ring-2 focus:ring-blue-500/20 ${
                  touched.reason && !isReasonValid
                    ? "border-red-500 bg-red-50/20"
                    : "border-border bg-surface"
                }`}
              />
              {touched.reason && !isReasonValid && (
                <p className="mt-1 text-[11px] text-red-600">Reason is required for audit history.</p>
              )}
            </div>
          </form>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-4 border-t border-border bg-surface-muted/30">
          <button
            type="button"
            onClick={onClose}
            disabled={updateMutation.isPending}
            className="px-4 py-2 rounded-lg border border-border text-xs font-semibold text-text-secondary hover:bg-surface-muted transition-colors cursor-pointer"
          >
            Cancel
          </button>

          <button
            type="submit"
            form="edit-applicant-form"
            disabled={!isFormValid}
            className={`inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold text-white shadow-xs transition-colors ${
              !isFormValid
                ? "bg-blue-300 cursor-not-allowed"
                : "bg-blue-600 hover:bg-blue-700 cursor-pointer"
            }`}
          >
            <CheckCircle2 className="h-4 w-4" />
            <span>Review & Save</span>
          </button>
        </div>

        {/* Confirmation Modal Overlay */}
        {isConfirming && (
          <div className="absolute inset-0 z-20 flex items-center justify-center p-6 bg-black/60 backdrop-blur-xs animate-in fade-in duration-150">
            <div className="w-full max-w-md rounded-xl bg-surface border border-border p-5 shadow-2xl space-y-4">
              <div className="flex items-center gap-2.5 text-amber-700">
                <AlertTriangle className="h-5 w-5 shrink-0" />
                <h3 className="text-sm font-bold text-text-primary">Confirm Applicant Details</h3>
              </div>

              <div className="text-xs text-text-secondary space-y-2">
                <p>
                  Applicant details can be edited <strong>only once</strong>. Please confirm that all details are correct to avoid downstream correction issues in HR Emploc:
                </p>
                <div className="p-3 rounded-lg bg-surface-muted border border-border font-mono text-[11px] space-y-1">
                  <div><strong>Name:</strong> {trimmedLastName.toUpperCase()}, {trimmedFirstName.toUpperCase()} {trimmedMiddleName.toUpperCase()}</div>
                  <div><strong>Mobile:</strong> {normalizedContact}</div>
                  <div><strong>Reason:</strong> {trimmedReason}</div>
                </div>
              </div>

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  disabled={updateMutation.isPending}
                  onClick={() => setIsConfirming(false)}
                  className="px-3.5 py-1.5 rounded-lg border border-border text-xs font-semibold text-text-secondary hover:bg-surface-muted transition-colors cursor-pointer"
                >
                  Back to Edit
                </button>
                <button
                  type="button"
                  disabled={updateMutation.isPending}
                  onClick={handleConfirmSave}
                  className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-lg text-xs font-semibold text-white bg-blue-600 hover:bg-blue-700 shadow-xs transition-colors cursor-pointer"
                >
                  {updateMutation.isPending ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      <span>Saving...</span>
                    </>
                  ) : (
                    <span>Confirm and Save</span>
                  )}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
