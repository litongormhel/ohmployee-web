"use client";

import { useState, useId } from "react";
import { AlertCircle, AlertTriangle, CheckCircle2, Edit3, Loader2, ShieldAlert } from "lucide-react";
import { useUpdateApplicantProfile } from "@/lib/queries/vacancy";
import { useCurrentUser } from "@/lib/auth";
import { hasFullAccess, canEditApplicantProfile } from "@/lib/rbac";
import { Modal } from "@/components/shared/Modal";

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
      isOpen={isOpen}
      applicant={applicant}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function EditApplicantModalContent({
  isOpen,
  applicant,
  onClose,
  onSuccess,
}: {
  isOpen: boolean;
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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Edit Applicant Details"
      subtitle={applicant.vcode ? `Requisition: ${applicant.vcode}` : "Candidate Identity Correction"}
      icon={Edit3}
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={updateMutation.isPending}
      isDirty={hasFieldChanges || Boolean(reason)}
    >
      <div className="space-y-4 text-xs">
          {/* Status Banners */}
          {isLockedStatus && (
            <div className="p-3 rounded-lg border border-border-default bg-surface-muted text-text-primary flex items-start gap-2">
              <ShieldAlert className="h-4 w-4 shrink-0 mt-0.5 text-text-secondary" />
              <div>
                <p className="font-semibold">Candidate Profile Locked</p>
                <p className="text-[11px] text-text-muted mt-0.5">
                  This applicant has progressed beyond the Vacancy pipeline ({applicant.statusLabel}). Profile changes must be requested through HR Emploc corrections.
                </p>
              </div>
            </div>
          )}

          {isBlockedByEditLimit && !isLockedStatus && (
            <div className="p-3 rounded-lg border border-border-default bg-surface-muted text-text-primary flex items-start gap-2">
              <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5 text-text-secondary" />
              <div>
                <p className="font-semibold">One-Time Edit Already Used</p>
                <p className="text-[11px] text-text-muted mt-0.5">
                  Applicant details can be edited only once to protect downstream payroll and HR records. A Head Admin or Super Admin override is required to make further corrections.
                </p>
              </div>
            </div>
          )}

          {isOverrideMode && !isLockedStatus && (
            <div className="p-3 rounded-lg border border-border-default bg-surface-muted text-text-primary flex items-start gap-2">
              <ShieldAlert className="h-4 w-4 shrink-0 mt-0.5 text-text-secondary" />
              <div>
                <p className="font-semibold">Administrator Override Mode Active</p>
                <p className="text-[11px] text-text-muted mt-0.5">
                  This applicant has already used their standard profile edit. As a full-access administrator, your update will be recorded as an audit override without resetting the caller limit.
                </p>
              </div>
            </div>
          )}

          {!isOneTimeUsed && !isLockedStatus && (
            <div className="p-3 rounded-lg border border-border-default bg-surface-muted text-text-primary flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-text-secondary" />
              <div>
                <p className="font-semibold">One-Time Policy Warning</p>
                <p className="text-[11px] text-text-muted mt-0.5">
                  Applicant details can only be edited once. Please ensure exact legal name spelling and correct phone digits to prevent downstream correction issues in HR Emploc.
                </p>
              </div>
            </div>
          )}

          {formError && (
            <div className="p-3 rounded-lg border border-danger-border bg-danger-bg text-danger-text flex items-start gap-2 animate-in fade-in">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-danger-text" />
              <span>{formError}</span>
            </div>
          )}

          {/* Form Fields */}
          <form id="edit-applicant-form" onSubmit={handleInitialSubmit} className="space-y-3.5">
            {/* Last Name */}
            <div>
              <label htmlFor={lastNameId} className="block font-semibold text-text-primary mb-1">
                Last Name <span className="text-text-muted">*</span>
              </label>
              <input
                id={lastNameId}
                type="text"
                disabled={isLockedStatus || isBlockedByEditLimit || updateMutation.isPending}
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                onBlur={() => setTouched((p) => ({ ...p, lastName: true }))}
                placeholder="e.g. DELA CRUZ"
                className={`w-full rounded-lg border px-3 py-2 text-text-primary  tracking-wide focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 ${
                  touched.lastName && !isLastNameValid
                    ? "border-border-strong bg-surface-muted/30"
                    : "border-border-default bg-surface-base"
                }`}
              />
              {touched.lastName && !isLastNameValid && (
                <p className="mt-1 text-[11px] text-text-secondary">Last name is required.</p>
              )}
            </div>

            {/* First Name */}
            <div>
              <label htmlFor={firstNameId} className="block font-semibold text-text-primary mb-1">
                First Name <span className="text-text-muted">*</span>
              </label>
              <input
                id={firstNameId}
                type="text"
                disabled={isLockedStatus || isBlockedByEditLimit || updateMutation.isPending}
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                onBlur={() => setTouched((p) => ({ ...p, firstName: true }))}
                placeholder="e.g. JUAN"
                className={`w-full rounded-lg border px-3 py-2 text-text-primary  tracking-wide focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 ${
                  touched.firstName && !isFirstNameValid
                    ? "border-border-strong bg-surface-muted/30"
                    : "border-border-default bg-surface-base"
                }`}
              />
              {touched.firstName && !isFirstNameValid && (
                <p className="mt-1 text-[11px] text-text-secondary">First name is required.</p>
              )}
            </div>

            {/* Middle Name */}
            <div>
              <label htmlFor={middleNameId} className="block font-semibold text-text-primary mb-1">
                Middle Name <span className="text-text-muted">*</span>{" "}
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
                className={`w-full rounded-lg border px-3 py-2 text-text-primary  tracking-wide focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 ${
                  touched.middleName && !isMiddleNameValid
                    ? "border-border-strong bg-surface-muted/30"
                    : "border-border-default bg-surface-base"
                }`}
              />
              {touched.middleName && !isMiddleNameValid && (
                <p className="mt-1 text-[11px] text-text-secondary">Middle name or NA is required.</p>
              )}
            </div>

            {/* Contact Number */}
            <div>
              <label htmlFor={contactNumberId} className="block font-semibold text-text-primary mb-1">
                Contact Number (11-digit mobile) <span className="text-text-muted">*</span>
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
                className={`w-full rounded-lg border px-3 py-2 font-mono text-text-primary focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 ${
                  touched.contactNumber && !isContactValid
                    ? "border-border-strong bg-surface-muted/30"
                    : "border-border-default bg-surface-base"
                }`}
              />
              {touched.contactNumber && !isContactValid && (
                <p className="mt-1 text-[11px] text-danger-text">
                  Must be 11 digits starting with 09 (e.g., 09171234567).
                </p>
              )}
            </div>

            {/* Comments / Reason */}
            <div>
              <label htmlFor={reasonId} className="block font-semibold text-text-primary mb-1">
                Reason / Comments <span className="text-text-muted">*</span>
              </label>
              <textarea
                id={reasonId}
                rows={2}
                disabled={isLockedStatus || isBlockedByEditLimit || updateMutation.isPending}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                onBlur={() => setTouched((p) => ({ ...p, reason: true }))}
                placeholder="Explain reason for editing candidate profile (e.g., Corrected misspelled middle name per valid ID)..."
                className={`w-full rounded-lg border px-3 py-2 text-text-primary focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 ${
                  touched.reason && !isReasonValid
                    ? "border-danger-border bg-danger-bg/20"
                    : "border-border-default bg-surface-base"
                }`}
              />
              {touched.reason && !isReasonValid && (
                <p className="mt-1 text-[11px] text-danger-text">Reason is required for audit history.</p>
              )}
            </div>
          </form>

          {/* Footer */}
          <div className="flex items-center justify-between pt-4 border-t border-border-subtle">
            <button
              type="button"
              onClick={onClose}
              disabled={updateMutation.isPending}
              className="px-4 py-2 rounded-lg border border-border-default text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors cursor-pointer"
            >
              Cancel
            </button>

            <button
              type="submit"
              form="edit-applicant-form"
              disabled={!isFormValid}
              className={`inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-semibold text-white shadow-xs transition-colors ${
                !isFormValid
                  ? "bg-brand-500/40 cursor-not-allowed"
                  : "bg-brand-500 hover:bg-brand-600 cursor-pointer"
              }`}
            >
              <CheckCircle2 className="h-4 w-4" />
              <span>Review & Save</span>
            </button>
          </div>

          {/* Confirmation Modal Overlay */}
          {isConfirming && (
            <div className="absolute inset-0 z-20 flex items-center justify-center p-6 bg-surface-overlay animate-in fade-in duration-150">
              <div className="w-full max-w-md rounded-xl bg-surface-base border border-border-default p-5 shadow-2xl space-y-4">
                <div className="flex items-center gap-2.5 text-text-primary">
                  <AlertTriangle className="h-5 w-5 shrink-0 text-text-secondary" />
                  <h3 className="text-sm font-bold text-text-primary">Confirm Applicant Details</h3>
                </div>

                <div className="text-xs text-text-secondary space-y-2">
                  <p>
                    Applicant details can be edited <strong>only once</strong>. Please confirm that all details are correct to avoid downstream correction issues in HR Emploc:
                  </p>
                  <div className="p-3 rounded-lg bg-surface-muted border border-border-default font-mono text-[11px] space-y-1 text-text-primary">
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
                    className="px-3.5 py-1.5 rounded-lg border border-border-default text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors cursor-pointer"
                  >
                    Back to Edit
                  </button>
                  <button
                    type="button"
                    disabled={updateMutation.isPending}
                    onClick={handleConfirmSave}
                    className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-lg text-xs font-semibold text-white bg-brand-500 hover:bg-brand-600 shadow-xs transition-colors cursor-pointer"
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
    </Modal>
  );
}
