"use client";

import { useState } from "react";
import { Calendar, Loader2, X } from "lucide-react";
import { useUpdateHiredApplicantDate } from "@/lib/queries/vacancy";

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
      applicant={applicant}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function EditHiredDateModalContent({
  applicant,
  onClose,
  onSuccess,
}: {
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
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-md rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-emerald-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700 border border-emerald-200">
              <Calendar className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">
                Update Hired Date
              </h2>
              <p className="text-xs text-gray-500 font-mono">
                {applicant.vcode} &bull; {applicant.fullName}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {errorMessage && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700">
              {errorMessage}
            </div>
          )}

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              Effective Hired / Onboard Date *
            </label>
            <input
              type="date"
              required
              value={hiredDate}
              onChange={(e) => setHiredDate(e.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
            />
            <p className="mt-1.5 text-[11px] text-gray-500">
              Updates the placement record and refreshes the 15-day visibility window in the Hired queue.
            </p>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 pt-3 border-t border-gray-100">
            <button
              type="button"
              onClick={onClose}
              disabled={mutation.isPending}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={mutation.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50"
            >
              {mutation.isPending && (
                <Loader2 className="h-4 w-4 animate-spin" />
              )}
              Save Date
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
