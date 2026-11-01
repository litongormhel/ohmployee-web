"use client";

import { useState } from "react";
import { AlertTriangle, Archive, Loader2, ArrowRightLeft, AlertCircle, ShieldAlert } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { requestAccountArchive } from "@/lib/queries/plantilla";
import { useCurrentUser } from "@/lib/auth";
import { useQueryClient } from "@tanstack/react-query";

export interface ArchiveAccountModalProps {
  isOpen: boolean;
  onClose: () => void;
  account: {
    id: string;
    name: string;
    actual: number;
    vacant: number;
    required: number;
    groupName?: string | null;
  } | null;
  onRouteToAbsorption: (account: { id: string; name: string }) => void;
  onSuccess?: (accountName: string) => void;
}

export function ArchiveAccountModal({
  isOpen,
  onClose,
  account,
  onRouteToAbsorption,
  onSuccess,
}: ArchiveAccountModalProps) {
  const [forceRemarks, setForceRemarks] = useState(false);
  const [remarks, setRemarks] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const currentUser = useCurrentUser();
  const queryClient = useQueryClient();

  const MIN_REMARKS_LENGTH = 30;
  const remarksTrimmed = remarks.trim();
  const isRemarksValid = remarksTrimmed.length >= MIN_REMARKS_LENGTH;

  // Derive step purely from state without useEffect cascading renders
  const step: "intercept" | "remarks" =
    account && account.actual > 0 && !forceRemarks ? "intercept" : "remarks";

  const handleClose = () => {
    if (isSubmitting) return;
    setForceRemarks(false);
    setRemarks("");
    setErrorMessage(null);
    onClose();
  };

  const handleProceedToRemarks = () => {
    setForceRemarks(true);
  };

  const handleRouteToAbsorption = () => {
    if (!account) return;
    handleClose();
    onRouteToAbsorption({ id: account.id, name: account.name });
  };

  const handleSubmitArchive = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!account) return;
    if (!isRemarksValid) {
      setErrorMessage(`Remarks must be at least ${MIN_REMARKS_LENGTH} characters long.`);
      return;
    }

    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      await requestAccountArchive({
        accountId: account.id,
        accountName: account.name,
        remarks: remarksTrimmed,
        requestedBy: currentUser?.profileId ?? currentUser?.authUserId,
        requestedByName: currentUser?.displayName ?? "Admin",
        actual: account.actual,
        vacant: account.vacant,
        required: account.required,
        groupName: account.groupName,
      });

      // Refresh queries
      queryClient.invalidateQueries({ queryKey: ["plantilla", "allowed-accounts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla", "account-metrics"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });

      const name = account.name;
      handleClose();
      onSuccess?.(name);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Failed to submit archive request.";
      setErrorMessage(msg);
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!account) return null;

  // Step 1: Intercepting dialog if active employees exist and user hasn't chosen to proceed anyway
  if (step === "intercept") {
    return (
      <Modal
        isOpen={isOpen}
        onClose={handleClose}
        title="Active Employees Detected"
        subtitle={`Account: ${account.name}`}
        icon={AlertTriangle}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex flex-col-reverse sm:flex-row items-center justify-end gap-2.5 w-full">
            <button
              type="button"
              onClick={handleProceedToRemarks}
              className="w-full sm:w-auto rounded-lg border border-border-default bg-surface-base px-3.5 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer"
            >
              Proceed to Archive
            </button>
            <button
              type="button"
              onClick={handleRouteToAbsorption}
              className="w-full sm:w-auto inline-flex items-center justify-center gap-1.5 rounded-lg bg-brand-button px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover transition cursor-pointer"
            >
              <ArrowRightLeft className="h-3.5 w-3.5" />
              <span>Absorb Employees First</span>
            </button>
          </div>
        }
      >
        <div className="space-y-4">
          <div className="rounded-xl border border-pct-warn-border bg-pct-warn-bg/30 p-4">
            <div className="flex items-start gap-3">
              <ShieldAlert className="h-5 w-5 text-pct-warn-text shrink-0 mt-0.5" />
              <div className="text-xs space-y-1.5">
                <p className="font-semibold text-text-primary">
                  There are active employees in this account.
                </p>
                <p className="text-text-secondary leading-relaxed">
                  This account currently has <strong className="text-text-primary font-bold">{account.actual} active employees</strong> deployed. Would you like to absorb them into another account first to preserve staffing coverage?
                </p>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-2 rounded-lg border border-border-subtle bg-surface-muted p-3 text-center">
            <div>
              <p className="text-[10px] font-medium text-text-muted uppercase">Active Deployed</p>
              <p className="text-base font-bold text-text-primary mt-0.5">{account.actual}</p>
            </div>
            <div>
              <p className="text-[10px] font-medium text-text-muted uppercase">Vacant Slots</p>
              <p className="text-base font-bold text-text-secondary mt-0.5">{account.vacant}</p>
            </div>
            <div>
              <p className="text-[10px] font-medium text-text-muted uppercase">Required Cap</p>
              <p className="text-base font-bold text-text-secondary mt-0.5">{account.required}</p>
            </div>
          </div>
        </div>
      </Modal>
    );
  }

  // Step 2: Archive confirmation modal with required remarks
  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Archive Account"
      subtitle={`Account: ${account.name}`}
      icon={Archive}
      maxWidthClass="max-w-lg"
      isDirty={remarks.trim() !== ""}
      isSubmitting={isSubmitting}
      footer={
        <div className="flex items-center justify-end gap-3 w-full">
          <button
            type="button"
            onClick={handleClose}
            disabled={isSubmitting}
            className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-xs font-semibold text-text-secondary hover:bg-surface-hover hover:text-text-primary transition cursor-pointer disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSubmitArchive}
            disabled={isSubmitting || !isRemarksValid}
            className="inline-flex items-center justify-center gap-1.5 rounded-lg bg-danger-bg border border-danger-border px-4 py-2 text-xs font-semibold text-danger-text hover:bg-danger-border/30 transition cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {isSubmitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            <span>{isSubmitting ? "Submitting Request..." : "Submit Archive Request"}</span>
          </button>
        </div>
      }
    >
      <form onSubmit={handleSubmitArchive} className="space-y-4">
        {errorMessage && (
          <div className="flex items-start gap-2.5 rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <p className="leading-relaxed">{errorMessage}</p>
          </div>
        )}

        <div className="rounded-lg border border-border-subtle bg-surface-muted p-3 text-xs text-text-secondary space-y-1">
          <p className="font-semibold text-text-primary">Governance Notice:</p>
          <p className="leading-relaxed">
            Submitting this request will <strong className="text-text-primary">not delete or hide the account immediately</strong>. It creates a pending archive request for Super Admin (SA) approval. While pending, the account remains visible and its headcount/capacity data continues to be included in all dashboard summary computations.
          </p>
        </div>

        {/* Remarks Input */}
        <div>
          <div className="flex items-center justify-between mb-1">
            <label className="text-xs font-semibold text-text-primary">
              Archive Justification & Remarks <span className="text-danger-text">*</span>
            </label>
            <span
              className={`text-[11px] font-mono ${
                isRemarksValid ? "text-pct-good-text font-bold" : "text-text-muted"
              }`}
            >
              {remarksTrimmed.length} / {MIN_REMARKS_LENGTH} min characters
            </span>
          </div>
          <textarea
            required
            rows={4}
            placeholder="Provide a comprehensive operational reason for archiving this billing account (minimum 30 characters required)..."
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            disabled={isSubmitting}
            className="w-full rounded-lg border border-border-default bg-surface-base p-3 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none transition-colors"
          />
          {!isRemarksValid && remarksTrimmed.length > 0 && (
            <p className="mt-1 text-[11px] text-danger-text">
              Please enter at least {MIN_REMARKS_LENGTH - remarksTrimmed.length} more characters.
            </p>
          )}
        </div>
      </form>
    </Modal>
  );
}
