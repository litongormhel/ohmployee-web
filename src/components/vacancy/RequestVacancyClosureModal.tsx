"use client";

import { useState } from "react";
import { Archive, Loader2, X } from "lucide-react";
import { useRequestVacancyClosure } from "@/lib/queries/vacancy";
import { useCurrentUser } from "@/lib/auth";

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
      vacancy={vacancy}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function RequestVacancyClosureModalContent({
  vacancy,
  onClose,
  onSuccess,
}: {
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
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-gray-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-gray-100 text-gray-700 border border-gray-200">
              <Archive className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">
                Request Vacancy Closure
              </h2>
              <p className="text-xs text-gray-500 font-mono">
                {vacancy.vcode} &bull; {vacancy.positionTitle || "Position"}
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
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-4">
          {errorMessage && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700">
              {errorMessage}
            </div>
          )}

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              Closure Reason *
            </label>
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-gray-500 focus:outline-none focus:ring-1 focus:ring-gray-500"
            >
              {CLOSURE_REASONS.map((r) => (
                <option key={r} value={r}>
                  {r}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              Details / Supporting Justification
            </label>
            <textarea
              rows={3}
              value={details}
              onChange={(e) => setDetails(e.target.value)}
              placeholder="Provide context for management approval of this closure..."
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-gray-500 focus:outline-none focus:ring-1 focus:ring-gray-500"
            />
          </div>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 text-xs text-gray-600 leading-relaxed">
            Submitting this request flags the vacancy for review. Once approved, the vacancy will be archived and removed from active sourcing.
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-gray-100">
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
              className="inline-flex items-center gap-2 rounded-lg bg-gray-900 px-4 py-2 text-sm font-semibold text-white hover:bg-black disabled:opacity-50"
            >
              {mutation.isPending && (
                <Loader2 className="h-4 w-4 animate-spin" />
              )}
              Submit Closure Request
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
