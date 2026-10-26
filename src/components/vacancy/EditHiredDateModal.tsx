"use client";

import { useState } from "react";
import { Calendar, Loader2 } from "lucide-react";
import { useUpdateHiredApplicantDate } from "@/lib/queries/vacancy";
import { Modal } from "@/components/shared/Modal";

export interface EditHiredDateModalProps {
  isOpen: boolean;
  onClose: () => void;
  applicant: {
    id: string;
    fullName: string;
    vcode: string;
    hiredDate?: string | null;
  } | null;
  onSuccess?: () => void;
}

export function EditHiredDateModal({
  isOpen,
  onClose,
  applicant,
  onSuccess,
}: EditHiredDateModalProps) {
  if (!isOpen || !applicant) return null;

  return (
    <EditHiredDateModalContent
      isOpen={isOpen}
      applicant={applicant}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function EditHiredDateModalContent({
  isOpen,
  applicant,
  onClose,
  onSuccess,
}: {
  isOpen: boolean;
  applicant: NonNullable<EditHiredDateModalProps["applicant"]>;
  onClose: () => void;
  onSuccess?: () => void;
}) {
  const mutation = useUpdateHiredApplicantDate();

  const [hiredDate, setHiredDate] = useState(
    applicant.hiredDate || new Date().toISOString().substring(0, 10),
  );
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    mutation.mutate(
      {
        applicantId: applicant.id,
        hiredDate,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to update hired date.");
        },
      },
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Update Hired Date"
      subtitle={`${applicant.vcode} • ${applicant.fullName}`}
      icon={Calendar}
      maxWidthClass="max-w-md"
      disableBackdropClick={true}
      isSubmitting={mutation.isPending}
      isDirty={hiredDate !== applicant.hiredDate}
    >
      <form onSubmit={handleSubmit} className="space-y-4 text-xs">
        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text font-medium">
            {errorMessage}
          </div>
        )}

        <div>
          <label className="block text-xs font-semibold text-text-secondary mb-1">
            Effective Hired / Onboard Date *
          </label>
          <input
            type="date"
            required
            value={hiredDate}
            onChange={(e) => setHiredDate(e.target.value)}
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          <p className="mt-1.5 text-[11px] text-text-muted">
            Updates the placement record and refreshes the 15-day visibility window in the Hired queue.
          </p>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 pt-3 border-t border-border-subtle">
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
            className="inline-flex items-center gap-2 rounded-lg bg-brand-500 px-4 py-2 text-sm font-semibold text-white hover:bg-brand-600 disabled:bg-surface-muted disabled:text-text-secondary disabled:border disabled:border-border-default disabled:shadow-none disabled:cursor-not-allowed cursor-pointer"
          >
            {mutation.isPending && (
              <Loader2 className="h-4 w-4 animate-spin" />
            )}
            Save Date
          </button>
        </div>
      </form>
    </Modal>
  );
}
