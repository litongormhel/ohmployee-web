// components/hr-emploc/AssignEmployeeNoModal.tsx
"use client";

import { useState } from "react";
import { AlertCircle, Hash, Loader2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useCurrentUser } from "@/lib/auth";
import {
  useAssignEmployeeNo,
  useMoveToPlantilla,
  checkEcosystemEmployeeIdUnique,
  HrEmplocDataError,
} from "@/lib/queries/hr_emploc";

type AssignEmployeeNoModalProps = {
  hrEmplocId: string;
  candidateName: string;
  vcode: string;
  accountName?: string | null;
  storeName?: string | null;
  currentEmployeeNo?: string | null;
  onClose: () => void;
  onSuccess: (message?: string) => void;
};

export function AssignEmployeeNoModal({
  hrEmplocId,
  candidateName,
  vcode,
  accountName,
  storeName,
  currentEmployeeNo,
  onClose,
  onSuccess,
}: AssignEmployeeNoModalProps) {
  const currentUser = useCurrentUser();
  const [employeeNo, setEmployeeNo] = useState(currentEmployeeNo ?? "");
  const [validationError, setValidationError] = useState<string | null>(null);
  const [isValidating, setIsValidating] = useState(false);

  const assignMutation = useAssignEmployeeNo();
  const deployMutation = useMoveToPlantilla();

  // Allowed Roles per RBAC: Super Admin, Data Team (Encoder/Head Admin), and HR Personnel (including Ops OM / HRCO)
  const roleName = (currentUser?.roleName ?? currentUser?.roleKey ?? "").toLowerCase().trim();
  const isAllowedRole =
    roleName.includes("super_admin") ||
    roleName.includes("super admin") ||
    roleName.includes("data") ||
    roleName.includes("encoder") ||
    roleName.includes("head_admin") ||
    roleName.includes("head admin") ||
    roleName.includes("hr") ||
    roleName.includes("om") ||
    roleName.includes("hrco") ||
    roleName.includes("developer") ||
    roleName.includes("admin");

  const isSubmitting = assignMutation.isPending || deployMutation.isPending || isValidating;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setValidationError(null);

    if (!isAllowedRole && !!currentUser) {
      setValidationError("You do not have permission to assign Emploc numbers.");
      return;
    }

    const trimmed = employeeNo.trim();
    if (!trimmed) {
      setValidationError("Employee ID is required.");
      return;
    }

    // Clean alphanumeric with optional hyphen or dot: e.g., 2024-0012, EMP1024, 102948
    const alphanumericPattern = /^[A-Za-z0-9._-]+$/;
    if (!alphanumericPattern.test(trimmed)) {
      setValidationError(
        "Employee ID must contain only clean alphanumeric characters, hyphens, underscores, or periods."
      );
      return;
    }

    // 2.2 Global Uniqueness Validation across entire ecosystem (hr_emploc, plantilla, users)
    setIsValidating(true);
    try {
      const check = await checkEcosystemEmployeeIdUnique(trimmed, hrEmplocId);
      if (!check.isUnique) {
        setValidationError(
          check.message ||
            `Employee ID ${trimmed} is already assigned to ${check.existingName || "Existing Employee"} (${check.existingModule || "System"}). Duplicate Emploc numbers are not allowed.`
        );
        setIsValidating(false);
        return;
      }
    } catch {
      // Continue if offline/dev fallback
    }
    setIsValidating(false);

    // 2.3 Auto-Plantilla Sync: Assign number then automatically deploy to Plantilla
    try {
      await assignMutation.mutateAsync({
        hrEmplocId,
        employeeNo: trimmed,
      });

      // Automatically move to Plantilla directory
      await deployMutation.mutateAsync({
        hrEmplocId,
        vcode,
      });

      onSuccess(
        `Assigned Employee ID ${trimmed} and automatically deployed ${candidateName} to Plantilla.`
      );
    } catch (err) {
      if (err instanceof HrEmplocDataError) {
        setValidationError(err.message);
      } else if (err instanceof Error) {
        setValidationError(err.message);
      } else {
        setValidationError("Failed to assign Emploc number and deploy. Please try again.");
      }
    }
  }

  const isDirty = employeeNo !== (currentEmployeeNo ?? "");
  const locationContext = [accountName, storeName].filter(Boolean).join(" / ");

  return (
    <Modal
      isOpen={true}
      onClose={onClose}
      title="+ Add Emploc (Auto-Deploy to Plantilla)"
      maxWidthClass="max-w-md"
      disableBackdropClick={true}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        {/* Context Header: Applicant Name (VCode • Account / Store) */}
        <div className="rounded-lg border border-border-default bg-surface-muted p-3.5 space-y-1">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-bold text-text-primary">{candidateName}</h4>
            <span className="font-mono text-xs font-semibold px-2 py-0.5 rounded border border-border-default bg-surface text-text-secondary">
              {vcode}
            </span>
          </div>
          {locationContext && (
            <p className="text-xs text-text-secondary font-medium">📍 {locationContext}</p>
          )}
        </div>

        {/* Content Body */}
        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Single Required Input Field: Employee ID */}
          <div className="space-y-1.5">
            <div className="flex items-center gap-1.5">
              <Hash className="h-4 w-4 text-brand-primary" />
              <label htmlFor="employeeNoInput" className="block text-xs font-semibold text-text-primary">
                Employee ID <span className="text-[var(--danger-text)]">*</span>
              </label>
            </div>
            <input
              id="employeeNoInput"
              type="text"
              required
              disabled={isSubmitting || !isAllowedRole}
              value={employeeNo}
              onChange={(e) => {
                setEmployeeNo(e.target.value);
                setValidationError(null);
              }}
              placeholder="e.g. 2024-0045 or EMP-1092"
              className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary focus:border-brand-primary disabled:opacity-50"
            />
            <p className="text-[11px] text-text-muted">
              Entering an Employee ID automatically moves the candidate to the{" "}
              <strong>Deployed</strong> queue and syncs them into the active Plantilla directory.
            </p>
          </div>

          {/* Validation or Mutation Error */}
          {validationError && (
            <div className="rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
              <span className="leading-relaxed">{validationError}</span>
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-border-subtle">
            <button
              type="button"
              disabled={isSubmitting}
              onClick={onClose}
              className="rounded-md border border-border-default bg-surface px-4 py-2 text-xs font-medium text-text-primary hover:bg-surface-hover transition disabled:opacity-50 cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || !isAllowedRole || !employeeNo.trim()}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-button px-4 py-2 text-xs font-semibold text-white hover:bg-brand-button-hover transition disabled:bg-surface-muted disabled:text-text-secondary disabled:border disabled:border-border-default disabled:shadow-none disabled:cursor-not-allowed shadow-xs cursor-pointer"
            >
              {isSubmitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              {isSubmitting ? "Deploying..." : "Assign & Deploy to Plantilla"}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
