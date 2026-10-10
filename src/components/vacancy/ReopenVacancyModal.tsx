"use client";

import { useState } from "react";
import { Loader2, RefreshCw, X } from "lucide-react";
import { useReopenVacancy } from "@/lib/queries/vacancy";

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
      vacancy={vacancy}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function ReopenVacancyModalContent({
  vacancy,
  onClose,
  onSuccess,
}: {
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
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-blue-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-100 text-blue-700 border border-blue-200">
              <RefreshCw className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">
                Reopen Vacancy Slot
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

          <div className="rounded-md bg-gray-50 p-3 border border-gray-100 text-xs text-gray-600 space-y-1">
            <div>
              <strong>Store / Outlet:</strong> {vacancy.storeName || "—"}
            </div>
            <div>
              <strong>Account:</strong> {vacancy.accountName || "—"}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              New Vacant Date *
            </label>
            <input
              type="date"
              required
              value={vacantDate}
              onChange={(e) => setVacantDate(e.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            />
            <p className="mt-1 text-[11px] text-gray-500">
              Sets the aging clock start date for this recycled vacancy opening.
            </p>
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              Re-opening Justification / Remarks
            </label>
            <textarea
              rows={3}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. Previous hire backed out, re-opening to active recruitment pipeline..."
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            />
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
              className="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700 disabled:opacity-50"
            >
              {mutation.isPending && (
                <Loader2 className="h-4 w-4 animate-spin" />
              )}
              Reopen Slot
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
