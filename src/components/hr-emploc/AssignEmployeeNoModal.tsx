// components/hr-emploc/AssignEmployeeNoModal.tsx
"use client";

import { useState } from "react";
import { AlertCircle, Hash, Loader2, X } from "lucide-react";
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

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40 backdrop-blur-xs"
        onClick={assignMutation.isPending ? undefined : onClose}
      />

      {/* Modal Card */}
      <div className="relative z-10 w-full max-w-md bg-white rounded-lg border border-gray-200 shadow-xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-5 py-3.5 bg-gray-50/50">
          <div className="flex items-center gap-2">
            <div className="p-1.5 bg-blue-50 text-blue-600 rounded">
              <Hash className="h-4 w-4" />
            </div>
            <div>
              <h2 className="text-sm font-semibold text-gray-900">Assign Employee Number</h2>
              <p className="text-[11px] text-gray-500">
                Official HR identifier for Plantilla deployment
              </p>
            </div>
          </div>
          <button
            aria-label="Close"
            className="inline-flex h-7 w-7 items-center justify-center rounded border border-gray-200 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition disabled:opacity-40"
            disabled={assignMutation.isPending}
            onClick={onClose}
            type="button"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Content Body */}
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Candidate Snapshot */}
          <div className="rounded-md border border-gray-100 bg-gray-50/60 p-3 text-xs space-y-1">
            <div className="flex justify-between items-center">
              <span className="text-gray-500">Candidate:</span>
              <span className="font-semibold text-gray-900">{candidateName}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-gray-500">Target VCode:</span>
              <span className="font-mono text-gray-700 bg-white px-1.5 py-0.5 rounded border border-gray-200">
                {vcode}
              </span>
            </div>
          </div>

          {/* Role Warning / Block notice */}
          {isBlockedRole && (
            <div className="rounded border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-amber-600" />
              <span>
                <strong>RBAC Restriction:</strong> {isHeadAdmin ? "Head Admin is explicitly blocked from assigning employee IDs." : "You need Data Encoder or Super Admin privileges to assign employee IDs."}
              </span>
            </div>
          )}

          {/* Input field */}
          <div className="space-y-1.5">
            <label htmlFor="employeeNoInput" className="block text-xs font-semibold text-gray-700">
              Employee / Emploc Number <span className="text-red-500">*</span>
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
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 disabled:bg-gray-100 disabled:text-gray-500"
            />
            <p className="text-[11px] text-gray-400">
              Alphanumeric format, hyphens, and underscores accepted. Once assigned, this record moves to Ready status.
            </p>
          </div>

          {/* Validation or Mutation Error */}
          {validationError && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-xs text-red-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
              <span>{validationError}</span>
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-gray-100">
            <button
              type="button"
              disabled={assignMutation.isPending}
              onClick={onClose}
              className="rounded-md border border-gray-200 bg-white px-4 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50 transition disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={assignMutation.isPending || isBlockedRole || !employeeNo.trim()}
              className="inline-flex items-center gap-1.5 rounded-md bg-blue-600 px-4 py-2 text-xs font-semibold text-white hover:bg-blue-700 transition disabled:opacity-50 disabled:cursor-not-allowed shadow-xs"
            >
              {assignMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              {assignMutation.isPending ? "Assigning..." : "Assign & Mark Ready"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
