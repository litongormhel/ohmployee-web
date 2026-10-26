"use client";

import { useState } from "react";
import { Loader2, RefreshCw } from "lucide-react";
import { useReopenVacancy } from "@/lib/queries/vacancy";
import { Modal } from "@/components/shared/Modal";

export interface ReopenVacancyModalProps {
  isOpen: boolean;
  onClose: () => void;
  vacancy: {
    vcode: string;
    positionTitle?: string | null;
    storeName?: string | null;
    accountName?: string | null;
  } | null;
  onSuccess?: () => void;
}

export function ReopenVacancyModal({
  isOpen,
  onClose,
  vacancy,
  onSuccess,
}: ReopenVacancyModalProps) {
  if (!isOpen || !vacancy) return null;

  return (
    <ReopenVacancyModalContent
      isOpen={isOpen}
      vacancy={vacancy}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function ReopenVacancyModalContent({
  isOpen,
  vacancy,
  onClose,
  onSuccess,
}: {
  isOpen: boolean;
  vacancy: NonNullable<ReopenVacancyModalProps["vacancy"]>;
  onClose: () => void;
  onSuccess?: () => void;
}) {
  const mutation = useReopenVacancy();

  const [vacantDate, setVacantDate] = useState(
    new Date().toISOString().substring(0, 10),
  );
  const [reason, setReason] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    mutation.mutate(
      {
        vcode: vacancy.vcode,
        vacantDate,
        reason: reason.trim() || undefined,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to reopen vacancy slot.");
        },
      },
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Reopen Vacancy Slot"
      subtitle={`${vacancy.vcode} • ${vacancy.positionTitle || "Position"}`}
      icon={RefreshCw}
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={mutation.isPending}
      isDirty={Boolean(reason)}
    >
      <form onSubmit={handleSubmit} className="space-y-4 text-xs">
        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text font-medium">
            {errorMessage}
          </div>
        )}

        <div className="rounded-md bg-surface-muted p-3 border border-border-subtle text-xs text-text-secondary space-y-1">
          <div>
            <strong>Store / Outlet:</strong> {vacancy.storeName || "—"}
          </div>
          <div>
            <strong>Account:</strong> {vacancy.accountName || "—"}
          </div>
        </div>

        <div>
          <label className="block text-xs font-semibold text-text-secondary mb-1">
            New Vacant Date *
          </label>
          <input
            type="date"
            required
            value={vacantDate}
            onChange={(e) => setVacantDate(e.target.value)}
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          <p className="mt-1 text-[11px] text-text-muted">
            Sets the aging clock start date for this recycled vacancy opening.
          </p>
        </div>

        <div>
          <label className="block text-xs font-semibold text-text-secondary mb-1">
            Re-opening Justification / Remarks
          </label>
          <textarea
            rows={3}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. Previous hire backed out, re-opening to active recruitment pipeline..."
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 pt-4 border-t border-border-subtle">
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="rounded-lg border border-border-default px-4 py-2 text-sm font-medium text-text-secondary hover:bg-surface-hover"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={mutation.isPending}
            className="inline-flex items-center gap-2 rounded-lg bg-brand-500 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-600 disabled:opacity-50"
          >
            {mutation.isPending && (
              <Loader2 className="h-4 w-4 animate-spin" />
            )}
            Reopen Slot
          </button>
        </div>
      </form>
    </Modal>
  );
}
