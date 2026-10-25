// components/hr-emploc/AssignEmployeeNoModal.tsx
"use client";

import { useState } from "react";
import { AlertCircle, Hash, Loader2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useCurrentUser } from "@/lib/auth";
import { useAssignEmployeeNo, HrEmplocDataError } from "@/lib/queries/hr_emploc";

type AssignEmployeeNoModalProps = {
  hrEmplocId: string;
  candidateName: string;
  vcode: string;
  currentEmployeeNo?: string | null;
  onClose: () => void;
  onSuccess: () => void;
};

export function AssignEmployeeNoModal({
  hrEmplocId,
  candidateName,
  vcode,
  currentEmployeeNo,
  onClose,
  onSuccess,
}: AssignEmployeeNoModalProps) {
  const currentUser = useCurrentUser();
  const [employeeNo, setEmployeeNo] = useState(currentEmployeeNo ?? "");
  const [validationError, setValidationError] = useState<string | null>(null);

  const assignMutation = useAssignEmployeeNo();

  // Role validation: Encoder & Super Admin allowed; Head Admin hard-blocked
  const roleName = (currentUser?.roleName ?? currentUser?.roleKey ?? "").toLowerCase().trim();
  const isHeadAdmin = roleName === "head_admin" || roleName === "head admin";
  const isEncoderOrSuperAdmin =
    roleName === "encoder" ||
    roleName === "super_admin" ||
    roleName === "super admin" ||
    roleName === "developer" ||
    roleName === "admin";

  const isBlockedRole = isHeadAdmin || (!isEncoderOrSuperAdmin && !!currentUser);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setValidationError(null);

    if (isBlockedRole) {
      setValidationError("Head Admin is blocked from assigning employee numbers. Only Data Encoder or Super Admin can assign employee numbers.");
      return;
    }

    const trimmed = employeeNo.trim();
    if (!trimmed) {
      setValidationError("Employee number is required.");
      return;
    }

    // Clean alphanumeric with optional hyphen or dot: e.g., 2024-0012, EMP1024, 102948
    const alphanumericPattern = /^[A-Za-z0-9._-]+$/;
    if (!alphanumericPattern.test(trimmed)) {
      setValidationError("Employee number must contain only clean alphanumeric characters, hyphens, underscores, or periods.");
      return;
    }

    assignMutation.mutate(
      {
        hrEmplocId,
        employeeNo: trimmed,
      },
      {
        onSuccess: () => {
          onSuccess();
        },
        onError: (err) => {
          if (err instanceof HrEmplocDataError) {
            setValidationError(err.message);
          } else if (err instanceof Error) {
            setValidationError(err.message);
          } else {
            setValidationError("Failed to assign employee number. Please try again.");
          }
        },
      }
    );
  }

  const isDirty = employeeNo !== (currentEmployeeNo ?? "");

  return (
    <Modal
      isOpen={true}
      onClose={onClose}
      title="Assign Employee Number"
      maxWidthClass="max-w-md"
      disableBackdropClick={true}
      isSubmitting={assignMutation.isPending}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        <div className="flex items-center gap-2 pb-2 border-b border-border-subtle">
          <div className="p-1.5 bg-surface-muted text-brand-primary rounded border border-border-subtle">
            <Hash className="h-4 w-4" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-text-primary">Plantilla Identifier</h4>
            <p className="text-[11px] text-text-muted">
              Official HR identifier for Plantilla deployment
            </p>
          </div>
        </div>

        {/* Content Body */}
        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Candidate Snapshot */}
          <div className="rounded-md border border-border-subtle bg-surface-muted p-3 text-xs space-y-1">
            <div className="flex justify-between items-center">
              <span className="text-text-muted">Candidate:</span>
              <span className="font-semibold text-text-primary">{candidateName}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-text-muted">Target VCode:</span>
              <span className="font-mono text-text-primary bg-surface px-1.5 py-0.5 rounded border border-border-default">
                {vcode}
              </span>
            </div>
          </div>

          {/* Role Warning / Block notice */}
          {isBlockedRole && (
            <div className="rounded border border-border-default bg-surface-muted p-3 text-xs text-text-primary flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-text-muted" />
              <span>
                <strong>RBAC Restriction:</strong> {isHeadAdmin ? "Head Admin is explicitly blocked from assigning employee IDs." : "You need Data Encoder or Super Admin privileges to assign employee IDs."}
              </span>
            </div>
          )}

          {/* Input field */}
          <div className="space-y-1.5">
            <label htmlFor="employeeNoInput" className="block text-xs font-semibold text-text-primary">
              Employee / Emploc Number <span className="text-[var(--danger-text)]">*</span>
            </label>
            <input
              id="employeeNoInput"
              type="text"
              required
              disabled={assignMutation.isPending || isBlockedRole}
              value={employeeNo}
              onChange={(e) => {
                setEmployeeNo(e.target.value);
                setValidationError(null);
              }}
              placeholder="e.g. 2024-0045 or EMP-1092"
              className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-brand-primary focus:border-brand-primary disabled:opacity-50"
            />
            <p className="text-[11px] text-text-muted">
              Alphanumeric format, hyphens, and underscores accepted. Once assigned, this record moves to Ready status.
            </p>
          </div>

          {/* Validation or Mutation Error */}
          {validationError && (
            <div className="rounded border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
              <span>{validationError}</span>
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-border-subtle">
            <button
              type="button"
              disabled={assignMutation.isPending}
              onClick={onClose}
              className="rounded-md border border-border-default bg-surface px-4 py-2 text-xs font-medium text-text-primary hover:bg-surface-hover transition disabled:opacity-50 cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={assignMutation.isPending || isBlockedRole || !employeeNo.trim()}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-primary px-4 py-2 text-xs font-semibold text-white hover:bg-brand-primary-hover transition disabled:opacity-50 disabled:cursor-not-allowed shadow-xs cursor-pointer"
            >
              {assignMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              {assignMutation.isPending ? "Assigning..." : "Assign & Mark Ready"}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
