"use client";

import { useState } from "react";
import { Archive, Loader2 } from "lucide-react";
import { useRequestVacancyClosure } from "@/lib/queries/vacancy";
import { useCurrentUser } from "@/lib/auth";
import { Modal } from "@/components/shared/Modal";

export interface RequestVacancyClosureModalProps {
  isOpen: boolean;
  onClose: () => void;
  vacancy: {
    vcode: string;
    positionTitle?: string | null;
    storeName?: string | null;
  } | null;
  onSuccess?: () => void;
}

const CLOSURE_REASONS = [
  "Store Closed / Outlet Ceased Operations",
  "Headcount Allocation Cancelled by Client",
  "Converted to Reliever / Roving Coverage",
  "Duplicate Headcount Request",
  "Operational Restructuring",
  "Other Reason",
];

export function RequestVacancyClosureModal({
  isOpen,
  onClose,
  vacancy,
  onSuccess,
}: RequestVacancyClosureModalProps) {
  if (!isOpen || !vacancy) return null;

  return (
    <RequestVacancyClosureModalContent
      isOpen={isOpen}
      vacancy={vacancy}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function RequestVacancyClosureModalContent({
  isOpen,
  vacancy,
  onClose,
  onSuccess,
}: {
  isOpen: boolean;
  vacancy: NonNullable<RequestVacancyClosureModalProps["vacancy"]>;
  onClose: () => void;
  onSuccess?: () => void;
}) {
  const currentUser = useCurrentUser();
  const mutation = useRequestVacancyClosure();

  const [reason, setReason] = useState(CLOSURE_REASONS[0]);
  const [details, setDetails] = useState("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    mutation.mutate(
      {
        vcode: vacancy.vcode,
        reason,
        details: details.trim() || undefined,
        requestedBy: currentUser?.displayName || "System User",
        requestedByRole: currentUser?.roleKey || "Ops",
        requestedByUserId: currentUser?.profileId ?? null,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to submit closure request.");
        },
      },
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Request Vacancy Closure"
      subtitle={`${vacancy.vcode} • ${vacancy.positionTitle || "Position"}`}
      icon={Archive}
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={mutation.isPending}
      isDirty={Boolean(details)}
    >
      <form onSubmit={handleSubmit} className="space-y-4 text-xs">
        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text font-medium">
            {errorMessage}
          </div>
        )}

        <div>
          <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
            Closure Reason *
          </label>
          <select
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          >
            {CLOSURE_REASONS.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
            Details / Supporting Justification
          </label>
          <textarea
            rows={3}
            value={details}
            onChange={(e) => setDetails(e.target.value)}
            placeholder="Provide context for management approval of this closure..."
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>

        <div className="rounded-lg border border-border-default bg-surface-muted p-3 text-xs text-text-secondary leading-relaxed">
          Submitting this request flags the vacancy for review. Once approved, the vacancy will be archived and removed from active sourcing.
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
            className="inline-flex items-center gap-2 rounded-lg bg-danger-text text-white hover:opacity-90 px-4 py-2 text-sm font-semibold disabled:opacity-50 cursor-pointer transition-opacity"
          >
            {mutation.isPending && (
              <Loader2 className="h-4 w-4 animate-spin" />
            )}
            Submit Closure Request
          </button>
        </div>
      </form>
    </Modal>
  );
}
