"use client";

import { useState, useId } from "react";
import {
  AlertCircle,
  History,
  MapPin,
  RefreshCw,
  Sparkles,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { RequiredAsterisk } from "@/components/shared/RequiredAsterisk";
import {
  useHeadcountModalMasterData,
  useSubmitStoreReactivation,
} from "@/lib/queries/requests";
import { formatStoreName } from "@/lib/utils/displayText";
import type { StoreCapacityRow } from "./types";

export interface RequestStoreReactivationModalProps {
  isOpen: boolean;
  onClose: () => void;
  store: StoreCapacityRow | null;
  accountId: string;
  accountName?: string;
  onSuccess?: () => void;
}

export function RequestStoreReactivationModal({
  isOpen,
  onClose,
  store,
  accountId,
  accountName,
  onSuccess,
}: RequestStoreReactivationModalProps) {
  const positionSelectId = useId();
  const justificationTextareaId = useId();

  const [position, setPosition] = useState<string>("");
  const [reason, setReason] = useState<string>("");
  const [formError, setFormError] = useState<string | null>(null);

  const { data: masterData, isLoading: isLoadingMasterData } =
    useHeadcountModalMasterData(accountId, { enabled: isOpen && Boolean(accountId) });

  const submitMutation = useSubmitStoreReactivation();

  const positionsList = masterData?.positions ?? [];

  const handleClose = () => {
    if (submitMutation.isPending) return;
    setPosition("");
    setReason("");
    setFormError(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!store) return;

    const trimmedReason = reason.trim();
    const selectedPosition = position.trim();

    if (!selectedPosition) {
      setFormError("Please select a target position for the initial headcount.");
      return;
    }

    if (!trimmedReason || trimmedReason.length < 5) {
      setFormError("Operational justification is required (minimum 5 characters).");
      return;
    }

    setFormError(null);

    try {
      await submitMutation.mutateAsync({
        store_id: store.id,
        position: selectedPosition,
        reason: trimmedReason,
      });

      onSuccess?.();
      handleClose();
    } catch (err: unknown) {
      setFormError(
        err instanceof Error ? err.message : "Failed to submit store reactivation request."
      );
    }
  };

  if (!store) return null;

  const locationLabel = [store.city, store.province].filter(Boolean).join(", ");
  const cleanStoreName = formatStoreName(store.storeBranch);

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Request Store Reactivation"
      subtitle="Submit store reactivation request to Data Team for review and approval"
      icon={RefreshCw}
      isSubmitting={submitMutation.isPending}
      disableBackdropClick={submitMutation.isPending}
      maxWidthClass="max-w-lg"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Store Metadata Card */}
        <div className="rounded-lg border border-border-default bg-surface-subtle p-3 text-xs space-y-2">
          <div className="flex items-start justify-between gap-2">
            <div>
              <div className="flex items-center gap-1.5 flex-wrap">
                <span className="font-bold text-sm text-text-primary">
                  {cleanStoreName}
                </span>
                {store.code ? (
                  <span className="inline-flex items-center rounded border border-blue-300 bg-blue-50 px-1.5 py-0.2 font-mono text-[10px] font-semibold text-blue-700 dark:border-blue-800 dark:bg-blue-950/60 dark:text-blue-300">
                    {store.code}
                  </span>
                ) : (
                  <span className="inline-flex items-center rounded border border-dashed border-gray-300 bg-gray-50 px-1.5 py-0.2 font-mono text-[10px] font-semibold text-gray-600 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-400">
                    No VCode
                  </span>
                )}
                <span className="inline-flex items-center rounded-full bg-surface-muted px-1.5 py-0.2 text-[10px] font-medium text-text-muted border border-border-subtle">
                  Archived
                </span>
              </div>
              <div className="flex items-center gap-1 text-[11px] text-text-secondary mt-1">
                <MapPin className="h-3 w-3 text-text-muted shrink-0" />
                <span>{locationLabel || "Unassigned Location"}</span>
              </div>
            </div>
            {accountName && (
              <span className="inline-flex items-center rounded-md border border-border-default bg-surface px-2 py-0.5 text-2xs font-medium text-text-secondary">
                {accountName}
              </span>
            )}
          </div>

          {/* VCode Preservation Notice */}
          <div className="mt-1 pt-2 border-t border-border-subtle flex items-start gap-1.5 text-[11px] text-text-secondary">
            <History className="h-3.5 w-3.5 text-brand-600 shrink-0 mt-0.5" />
            <div>
              {store.code ? (
                <span>
                  <strong>Strict VCode Preservation:</strong> Reactivating this store will retain its existing code{" "}
                  <code className="font-mono font-semibold text-text-primary px-1 bg-surface-muted rounded">
                    {store.code}
                  </code>{" "}
                  upon Data Team approval.
                </span>
              ) : (
                <span>
                  <strong>Canonical VCode Minting:</strong> No legacy VCode found on file. Data Team approval will automatically assign an official VCode.
                </span>
              )}
            </div>
          </div>
        </div>

        {/* Target Position Selection */}
        <div className="space-y-1.5">
          <label htmlFor={positionSelectId} className="block text-xs font-semibold text-text-primary">
            Target Position for Initial Vacancy <RequiredAsterisk />
          </label>
          <select
            id={positionSelectId}
            value={position}
            onChange={(e) => setPosition(e.target.value)}
            disabled={submitMutation.isPending}
            className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-xs text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
            required
          >
            <option value="">
              {isLoadingMasterData ? "Loading available positions..." : "— Select Target Position —"}
            </option>
            {positionsList.map((p) => (
              <option key={p.id} value={p.position_name}>
                {p.position_name}
              </option>
            ))}
            {!isLoadingMasterData && positionsList.length === 0 && (
              <>
                <option value="Staff">Staff</option>
                <option value="Store Crew">Store Crew</option>
                <option value="Cashier">Cashier</option>
                <option value="Sales Associate">Sales Associate</option>
                <option value="Promodiser">Promodiser</option>
              </>
            )}
          </select>
          <span className="text-[11px] text-text-muted">
            Select the primary role required when this store is reopened.
          </span>
        </div>

        {/* Headcount Rule Notice */}
        <div className="rounded-lg border border-brand-200 bg-brand-50/50 p-2.5 text-xs dark:border-brand-900/60 dark:bg-brand-950/30">
          <div className="flex items-center gap-1.5 font-semibold text-brand-900 dark:text-brand-200">
            <Sparkles className="h-3.5 w-3.5 text-brand-600" />
            <span>Automatic 1 HC Vacancy Provisioning</span>
          </div>
          <p className="text-[11px] text-text-secondary mt-1">
            Upon Data Team approval under <strong>New Store Approval</strong>, this store will immediately become active and an <strong>Open Vacancy</strong> for <strong>1 Headcount</strong> will be registered automatically.
          </p>
        </div>

        {/* Operational Justification */}
        <div className="space-y-1.5">
          <label htmlFor={justificationTextareaId} className="block text-xs font-semibold text-text-primary">
            Operational Justification <RequiredAsterisk />
          </label>
          <textarea
            id={justificationTextareaId}
            rows={3}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            disabled={submitMutation.isPending}
            placeholder="Explain why this store is being reactivated (e.g. lease renewed, new client agreement, mall reopening)..."
            className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:opacity-50"
            required
          />
          <span className="text-[11px] text-text-muted">
            The account Operations Manager (OM) and Data Team will be notified upon submission.
          </span>
        </div>

        {/* Error Feedback */}
        {formError && (
          <div className="flex items-center gap-2 rounded-md border border-border-danger bg-danger-subtle p-2.5 text-xs text-text-danger">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>{formError}</span>
          </div>
        )}

        {/* Actions */}
        <div className="flex items-center justify-end gap-2 border-t border-border-default pt-4">
          <button
            type="button"
            onClick={handleClose}
            disabled={submitMutation.isPending}
            className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 transition cursor-pointer"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={submitMutation.isPending}
            className="inline-flex items-center gap-1.5 rounded-md border border-border-brand bg-brand-500 hover:bg-brand-600 px-4 py-1.5 text-xs font-medium text-white shadow-2xs disabled:opacity-50 transition cursor-pointer"
          >
            {submitMutation.isPending && (
              <RefreshCw className="h-3 w-3 animate-spin" />
            )}
            <span>Submit Reactivation Request</span>
          </button>
        </div>
      </form>
    </Modal>
  );
}
