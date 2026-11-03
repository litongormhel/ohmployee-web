// components/hr-emploc/ReviewApproveModal.tsx
"use client";

import { useState } from "react";
import {
  CheckCircle2,
  Loader2,
  AlertCircle,
  FileCheck,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  approveHrEmplocReview,
  checkEcosystemEmployeeIdUnique,
  type HrEmplocListItem,
} from "@/lib/queries/hr_emploc";

type ReviewApproveModalProps = {
  isOpen: boolean;
  onClose: () => void;
  row: HrEmplocListItem | null;
  onSuccess: (message: string) => void;
};

export function ReviewApproveModal({
  isOpen,
  onClose,
  row,
  onSuccess,
}: ReviewApproveModalProps) {
  const [employeeNo, setEmployeeNo] = useState(row?.employeeNo ?? "");
  const [remarks, setRemarks] = useState("");
  const [isValidating, setIsValidating] = useState(false);
  const [isApproving, setIsApproving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen || !row) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const trimmedEmployeeNo = employeeNo.trim();
    if (!trimmedEmployeeNo) {
      setError("Emploc ID (Employee Number) is required to approve and move to Ready.");
      return;
    }

    // Alphanumeric with optional hyphen, underscore, or dot
    const alphanumericPattern = /^[A-Za-z0-9._-]+$/;
    if (!alphanumericPattern.test(trimmedEmployeeNo)) {
      setError("Employee ID must contain only alphanumeric characters, hyphens, underscores, or periods.");
      return;
    }

    // Ecosystem Uniqueness Pre-check
    setIsValidating(true);
    try {
      const check = await checkEcosystemEmployeeIdUnique(trimmedEmployeeNo, row.id);
      if (!check.isUnique) {
        setError(
          check.message ||
            `Employee ID "${trimmedEmployeeNo}" is already assigned to ${check.existingName || "Existing Employee"} (${check.existingModule || "System"}). Duplicate Emploc numbers are not allowed.`
        );
        setIsValidating(false);
        return;
      }
    } catch {
      // Allow proceeding to backend transaction check
    } finally {
      setIsValidating(false);
    }

    setIsApproving(true);

    try {
      const resolvedKeys = row.deficiencyIssues?.map((i) => i.code) ?? [];
      await approveHrEmplocReview({
        hrEmplocId: row.id,
        employeeNo: trimmedEmployeeNo,
        resolvedKeys,
        remarks: remarks.trim() || undefined,
      });

      onSuccess(`Correction for "${row.applicantName}" approved with Emploc ID ${trimmedEmployeeNo} and moved to Ready.`);
      handleClose();
    } catch (err) {
      const rawMsg = err instanceof Error ? err.message : String(err);
      if (rawMsg.includes("23505") || rawMsg.toLowerCase().includes("already exists") || rawMsg.toLowerCase().includes("duplicate")) {
        setError(`Employee ID "${trimmedEmployeeNo}" is already assigned to another active record or plantilla occupant.`);
      } else if (rawMsg.includes("22023") || rawMsg.toLowerCase().includes("empty") || rawMsg.toLowerCase().includes("whitespace")) {
        setError("Employee ID cannot be empty or whitespace.");
      } else if (rawMsg.includes("P0001") || rawMsg.toLowerCase().includes("pending deletion")) {
        setError("Cannot approve: record has a pending deletion request or unresolved corrections.");
      } else if (rawMsg.includes("42501") || rawMsg.toLowerCase().includes("forbidden") || rawMsg.toLowerCase().includes("permission denied")) {
        setError("Permission denied: only HR Personnel or Administrators can approve corrections.");
      } else {
        setError(rawMsg || "Failed to approve correction review.");
      }
    } finally {
      setIsApproving(false);
    }
  };

  const handleClose = () => {
    setEmployeeNo(row?.employeeNo ?? "");
    setRemarks("");
    setError(null);
    onClose();
  };

  const isSubmitting = isApproving || isValidating;
  const isDirty = Boolean(remarks.trim() || employeeNo.trim() !== (row.employeeNo ?? ""));

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Approve Correction"
      maxWidthClass="max-w-md"
      disableBackdropClick={true}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        <div className="flex items-center gap-2.5 pb-2 border-b border-border-subtle">
          <div className="p-2 rounded-lg bg-surface-muted text-brand-primary border border-border-subtle">
            <FileCheck className="h-5 w-5" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-text-primary">
              Compliance Verification
            </h4>
            <p className="text-xs text-text-muted mt-0.5">
              Assign Emploc ID, confirm compliance, and advance to Ready.
            </p>
          </div>
        </div>

        <div className="rounded-lg bg-surface-muted p-3 space-y-2 border border-border-subtle text-xs">
          <div className="flex justify-between">
            <span className="text-text-muted">Applicant:</span>
            <span className="font-semibold text-text-primary">{row.applicantName}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-muted">Account:</span>
            <span className="font-medium text-text-primary">{row.accountName ?? "--"}</span>
          </div>
          {row.deficiencySummary && (
            <div className="flex justify-between">
              <span className="text-text-muted">Deficiencies:</span>
              <span className="font-medium text-text-primary text-right">{row.deficiencySummary}</span>
            </div>
          )}
          {row.notes && (
            <div className="border-t border-border-subtle pt-2 flex flex-col gap-0.5">
              <span className="text-text-muted font-medium">Ops Correction Remarks:</span>
              <span className="text-text-primary italic">&ldquo;{row.notes}&rdquo;</span>
            </div>
          )}
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-center gap-2 rounded-lg bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)] p-3 text-xs">
              <AlertCircle className="h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="space-y-1.5">
            <label
              htmlFor="emploc-id"
              className="text-xs font-semibold text-text-primary"
            >
              Emploc ID (Employee Number) <span className="text-[var(--danger-text)]">*</span>
            </label>
            <input
              id="emploc-id"
              type="text"
              required
              value={employeeNo}
              onChange={(e) => {
                setEmployeeNo(e.target.value);
                if (error) setError(null);
              }}
              placeholder="e.g. 2024-0012, EMP1024, 102948"
              className="w-full rounded-md border border-border-default bg-surface px-2.5 py-1.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-none focus:ring-1 focus:ring-brand-primary disabled:opacity-50"
              disabled={isSubmitting}
              autoFocus
            />
          </div>

          <div className="space-y-1.5">
            <label
              htmlFor="approval-remarks"
              className="text-xs font-semibold text-text-primary"
            >
              Approval Remarks (Optional)
            </label>
            <textarea
              id="approval-remarks"
              rows={2}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Optional confirmation note or audit remarks..."
              className="w-full rounded-md border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-none focus:ring-1 focus:ring-brand-primary"
              disabled={isSubmitting}
            />
          </div>

          <div className="flex items-center justify-end gap-2.5 border-t border-border-subtle pt-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || !employeeNo.trim()}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-button px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-primary-hover transition cursor-pointer disabled:opacity-50"
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>{isValidating ? "Validating ID..." : "Approving..."}</span>
                </>
              ) : (
                <>
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  <span>Approve & Move to Ready</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
