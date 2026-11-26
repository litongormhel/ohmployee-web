"use client";

import { useState } from "react";
import { AlertTriangle, RefreshCw, XCircle } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useWithdrawStoreReactivation } from "@/lib/queries/requests";
import { formatStoreName } from "@/lib/utils/displayText";
import type { StoreCapacityRow } from "./types";

export interface WithdrawStoreReactivationModalProps {
  isOpen: boolean;
  onClose: () => void;
  store: StoreCapacityRow | null;
  requestId: string;
  onSuccess?: () => void;
}

export function WithdrawStoreReactivationModal({
  isOpen,
  onClose,
  store,
  requestId,
  onSuccess,
}: WithdrawStoreReactivationModalProps) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);

  const withdrawMutation = useWithdrawStoreReactivation();

  const handleClose = () => {
    if (withdrawMutation.isPending) return;
    setReason("");
    setError(null);
    onClose();
  };

  const handleConfirm = async () => {
    if (!requestId) return;
    setError(null);

    try {
      await withdrawMutation.mutateAsync({
        requestId,
        reason: reason.trim() || null,
      });

      onSuccess?.();
      handleClose();
    } catch (err: unknown) {
      setError(
        err instanceof Error
          ? err.message
          : "Failed to withdraw reactivation request."
      );
    }
  };

  if (!store) return null;

  const cleanStoreName = formatStoreName(store.storeBranch);

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Withdraw Reactivation Request"
      subtitle="Cancel pending store reactivation request"
      icon={XCircle}
      isSubmitting={withdrawMutation.isPending}
      disableBackdropClick={withdrawMutation.isPending}
      maxWidthClass="max-w-md"
    >
      <div className="space-y-4">
        {/* Warning Card */}
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs dark:border-amber-900/60 dark:bg-amber-950/40">
          <div className="flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 text-amber-600 shrink-0 mt-0.5" />
            <div className="space-y-1 text-amber-900 dark:text-amber-200">
              <p className="font-semibold">
                Are you sure you want to withdraw the reactivation request for{" "}
                <span className="font-bold underline">{cleanStoreName}</span>?
              </p>
              <p className="text-[11px] text-amber-800 dark:text-amber-300">
                This will remove the request from the Data Team review queue and notify the Operations Manager (OM).
              </p>
            </div>
          </div>
        </div>

        {/* Optional remarks */}
        <div className="space-y-1.5">
          <label className="block text-xs font-medium text-text-primary">
            Withdrawal Remarks <span className="text-text-muted font-normal">(Optional)</span>
          </label>
          <textarea
            rows={2}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            disabled={withdrawMutation.isPending}
            placeholder="Reason for withdrawing this request..."
            className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
          />
        </div>

        {error && (
          <div className="flex items-center gap-2 rounded-md border border-border-danger bg-danger-subtle p-2.5 text-xs text-text-danger">
            <AlertTriangle className="h-4 w-4 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Actions */}
        <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
          <button
            type="button"
            onClick={handleClose}
            disabled={withdrawMutation.isPending}
            className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 transition cursor-pointer"
          >
            Keep Request
          </button>
          <button
            type="button"
            onClick={handleConfirm}
            disabled={withdrawMutation.isPending}
            className="inline-flex items-center gap-1.5 rounded-md border border-red-600 bg-red-600 hover:bg-red-700 px-4 py-1.5 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
          >
            {withdrawMutation.isPending && (
              <RefreshCw className="h-3 w-3 animate-spin" />
            )}
            <span>Confirm Withdrawal</span>
          </button>
        </div>
      </div>
    </Modal>
  );
}
