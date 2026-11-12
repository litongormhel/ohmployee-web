"use client";

import { useState } from "react";
import {
  Hash,
  Loader2,
  AlertCircle,
  AlertTriangle,
  UserCheck,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { parseHrEmplocError, type ParsedHrEmplocError } from "@/lib/utils/hr_emploc_errors";
import {
  assignHrEmplocNumber,
  approveHrEmplocReview,
  checkEcosystemEmployeeIdUnique,
  type HrEmplocListItem,
} from "@/lib/queries/hr_emploc";

export interface AddEmplocModalProps {
  isOpen: boolean;
  onClose: () => void;
  row: HrEmplocListItem | null;
  onSuccess: (message: string) => void;
}

interface ConfirmationState {
  code: string;
  title: string;
  message: string;
  reason: string;
}

export function AddEmplocModal({
  isOpen,
  onClose,
  row,
  onSuccess,
}: AddEmplocModalProps) {
  const [employeeNo, setEmployeeNo] = useState(row?.employeeNo || "");
  const [remarks, setRemarks] = useState("");
  const [isValidating, setIsValidating] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<ParsedHrEmplocError | null>(null);

  // Interactive confirmation state for rehire/duplicate/middle-name prompts
  const [confirmState, setConfirmState] = useState<ConfirmationState | null>(null);

  if (!isOpen || !row) return null;

  const isReviewMode = row.hrStatus === "For Review";
  const modalTitle = isReviewMode ? "Approve Review & Deploy" : "Add Emploc Number";
  const modalDescription = `Applicant: ${row.applicantName} • Position: ${row.positionTitle || "N/A"} • Account: ${row.accountName || "N/A"}`;

  const executeAssignment = async (confirmReuse = false, reuseReason?: string) => {
    const trimmed = employeeNo.trim();
    if (!trimmed) {
      setError({
        code: "FIELD_REQUIRED_MISSING",
        title: "Employee ID Required",
        message: "Please enter an Employee ID to proceed.",
        rawMessage: "",
      });
      return;
    }

    // Format validation
    const alphanumericPattern = /^[A-Za-z0-9._-]+$/;
    if (!alphanumericPattern.test(trimmed)) {
      setError({
        code: "EMPLOYEE_NO_FORMAT_INVALID",
        title: "Invalid Employee ID Format",
        message: "Employee ID must contain only alphanumeric characters, hyphens, underscores, or periods (e.g. 2026-00001).",
        rawMessage: trimmed,
      });
      return;
    }

    // Ecosystem pre-check (only on initial submit, not on retry)
    if (!confirmReuse) {
      setIsValidating(true);
      try {
        const check = await checkEcosystemEmployeeIdUnique(trimmed, row.id);
        if (!check.isUnique) {
          setError({
            code: "EMPLOYEE_NO_ALREADY_ASSIGNED",
            title: "Employee ID Already Assigned",
            message: check.message || `Employee ID "${trimmed}" is already assigned to ${check.existingName || "another record"}.`,
            rawMessage: trimmed,
          });
          setIsValidating(false);
          return;
        }
      } catch {
        // Continue to server-level validation
      } finally {
        setIsValidating(false);
      }
    }

    setIsSubmitting(true);
    setError(null);

    try {
      if (isReviewMode) {
        const resolvedKeys = row.deficiencyIssues?.map((i) => i.code) ?? [];
        await approveHrEmplocReview({
          hrEmplocId: row.id,
          employeeNo: trimmed,
          resolvedKeys,
          remarks: remarks.trim() || undefined,
          confirmReuse,
          reuseReason: reuseReason?.trim() || undefined,
        });
        onSuccess(`Review approved! Employee ID ${trimmed} assigned and ${row.applicantName} deployed to Plantilla.`);
      } else {
        await assignHrEmplocNumber({
          hrEmplocId: row.id,
          employeeNo: trimmed,
          confirmReuse,
          reuseReason: reuseReason?.trim() || undefined,
        });
        onSuccess(`Employee ID ${trimmed} assigned. ${row.applicantName} deployed to Plantilla.`);
      }

      onClose();
    } catch (err) {
      const parsed = parseHrEmplocError(err);

      // Check if confirmation is required
      if (
        parsed.code === "REHIRE_CONFIRM_REQUIRED" ||
        parsed.code === "POSSIBLE_DUPLICATE_PERSON" ||
        parsed.code === "MIDDLE_NAME_CONFIRM_REQUIRED"
      ) {
        setConfirmState({
          code: parsed.code,
          title: parsed.title,
          message: parsed.message,
          reason: "",
        });
      } else {
        setError(parsed);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleInitialSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    executeAssignment(false);
  };

  const handleConfirmRetry = (e: React.FormEvent) => {
    e.preventDefault();
    if (!confirmState?.reason.trim()) {
      alert("A brief confirmation reason is required.");
      return;
    }
    executeAssignment(true, confirmState.reason);
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={modalTitle}
      subtitle={modalDescription}
      maxWidthClass="max-w-lg"
    >
      {confirmState ? (
        /* Confirmation Sub-Dialog */
        <form onSubmit={handleConfirmRetry} className="flex flex-col gap-4 text-xs">
          <div className="flex items-start gap-3 rounded-lg border border-status-warning/40 bg-status-warning/10 p-3 text-status-warning">
            <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" />
            <div className="flex-1 text-left">
              <h4 className="font-semibold text-text-primary text-xs">{confirmState.title}</h4>
              <p className="mt-1 text-2xs text-text-secondary leading-relaxed">
                {confirmState.message}
              </p>
            </div>
          </div>

          <div className="flex flex-col gap-1 text-left">
            <label htmlFor="confirmReason" className="font-semibold text-text-primary text-2xs">
              Confirmation Reason <span className="text-status-danger">*</span>
            </label>
            <input
              id="confirmReason"
              type="text"
              required
              autoFocus
              value={confirmState.reason}
              onChange={(e) =>
                setConfirmState((prev) => (prev ? { ...prev, reason: e.target.value } : null))
              }
              placeholder="e.g. Validated rehire candidate with verified identity documents"
              className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:border-accent-primary focus:outline-hidden"
            />
          </div>

          <div className="mt-2 flex items-center justify-end gap-2 border-t border-border-subtle pt-3">
            <button
              type="button"
              onClick={() => setConfirmState(null)}
              disabled={isSubmitting}
              className="rounded-lg border border-border-default px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover disabled:opacity-50"
            >
              Back
            </button>
            <button
              type="submit"
              disabled={isSubmitting || !confirmState.reason.trim()}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-button px-4 py-1.5 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover disabled:opacity-50 cursor-pointer"
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Deploying...</span>
                </>
              ) : (
                <span>Confirm & Deploy</span>
              )}
            </button>
          </div>
        </form>
      ) : (
        /* Normal Assign Form */
        <form onSubmit={handleInitialSubmit} className="flex flex-col gap-4 text-xs">
          {error && (
            <div className="flex items-start gap-2.5 rounded-lg border border-status-danger/30 bg-status-danger/10 p-3 text-status-danger text-left">
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
              <div className="flex-1">
                <p className="font-semibold">{error.title}</p>
                <p className="mt-0.5 text-2xs opacity-90 leading-relaxed">{error.message}</p>
              </div>
            </div>
          )}

          <div className="rounded-lg border border-border-subtle bg-surface-subtle p-3 text-left">
            <div className="grid grid-cols-2 gap-2 text-2xs">
              <div>
                <span className="text-text-muted">Target Store:</span>{" "}
                <span className="font-medium text-text-primary">{row.storeName || "N/A"}</span>
              </div>
              <div>
                <span className="text-text-muted">VCode:</span>{" "}
                <span className="font-mono font-medium text-text-primary">{row.vcode}</span>
              </div>
              <div>
                <span className="text-text-muted">Assignment:</span>{" "}
                <span className="font-medium text-text-primary">{row.assignmentType || "Stationary"}</span>
              </div>
              <div>
                <span className="text-text-muted">Hired Date:</span>{" "}
                <span className="font-medium text-text-primary">{row.hiredDate || "N/A"}</span>
              </div>
            </div>
          </div>

          <div className="flex flex-col gap-1 text-left">
            <label htmlFor="employeeNo" className="font-semibold text-text-primary text-2xs">
              Employee ID (Emploc Number) <span className="text-status-danger">*</span>
            </label>
            <div className="relative">
              <Hash className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-text-muted" />
              <input
                id="employeeNo"
                type="text"
                required
                autoFocus
                value={employeeNo}
                onChange={(e) => setEmployeeNo(e.target.value.toUpperCase())}
                placeholder="e.g. 2026-00001 or 12345"
                className="w-full rounded-lg border border-border-default bg-surface-base pl-8 pr-3 py-2 text-xs font-mono text-text-primary placeholder:text-text-muted focus:border-accent-primary focus:outline-hidden"
              />
            </div>
            <p className="text-3xs text-text-muted">
              Atomic action: assigning the Emploc number immediately deploys this candidate to Plantilla.
            </p>
          </div>

          {isReviewMode && (
            <div className="flex flex-col gap-1 text-left">
              <label htmlFor="reviewRemarks" className="font-semibold text-text-primary text-2xs">
                Review Remarks (Optional)
              </label>
              <textarea
                id="reviewRemarks"
                rows={2}
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                placeholder="Any remarks on the approved requirements or employee ID..."
                className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:border-accent-primary focus:outline-hidden"
              />
            </div>
          )}

          <div className="mt-2 flex items-center justify-end gap-2 border-t border-border-subtle pt-3">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting || isValidating}
              className="rounded-lg border border-border-default px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || isValidating || !employeeNo.trim()}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-button px-4 py-1.5 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover disabled:opacity-50 cursor-pointer"
            >
              {isSubmitting || isValidating ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>{isValidating ? "Validating..." : "Assigning..."}</span>
                </>
              ) : (
                <>
                  <UserCheck className="h-3.5 w-3.5" />
                  <span>Assign & Deploy</span>
                </>
              )}
            </button>
          </div>
        </form>
      )}
    </Modal>
  );
}
