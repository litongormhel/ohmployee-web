"use client";

import React, { useState } from "react";
import { AlertTriangle, Loader2, Undo2, X } from "lucide-react";

interface RollbackBatchModalProps {
  isOpen: boolean;
  onClose: () => void;
  fileName: string;
  onConfirm: (reason: string) => Promise<void>;
  isSubmitting?: boolean;
}

export function RollbackBatchModal({
  isOpen,
  onClose,
  fileName,
  onConfirm,
  isSubmitting = false,
}: RollbackBatchModalProps) {
  const [reason, setReason] = useState<string>("");
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const isValid = reason.trim().length >= 10;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!isValid) return;
    setError(null);
    try {
      await onConfirm(reason.trim());
      onClose();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to rollback import batch");
    }
  }

  return (
    <div
      aria-modal="true"
      className="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs animate-fade-in"
      role="dialog"
    >
      <div className="relative w-full max-w-md rounded-xl border border-border-default bg-surface-card p-6 shadow-xl">
        <button
          className="absolute top-4 right-4 text-gray-400 hover:text-gray-600 transition"
          disabled={isSubmitting}
          onClick={onClose}
          type="button"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="flex items-center gap-3 pb-3 border-b border-border-default">
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-amber-100 text-amber-700">
            <Undo2 className="h-5 w-5" />
          </div>
          <div>
            <h2 className="text-base font-bold text-gray-900">Rollback Import Batch</h2>
            <p className="text-xs text-gray-500 truncate max-w-[260px]">{fileName}</p>
          </div>
        </div>

        <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-3">
          <div className="flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 text-amber-700 mt-0.5 shrink-0" />
            <div className="text-xs text-amber-900">
              <p className="font-semibold">Destructive Action Notice</p>
              <p className="mt-0.5 text-amber-800">
                This will soft-delete all HR Emploc records created by this batch, restore reserved Plantilla slots to Open, and reopen vacancies. Records that have already moved to Plantilla cannot be rolled back.
              </p>
            </div>
          </div>
        </div>

        {error && (
          <div className="mt-4 rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
            {error}
          </div>
        )}

        <form className="mt-4 space-y-4" onSubmit={handleSubmit}>
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-gray-600 mb-1">
              Rollback Justification / Reason * (min 10 characters)
            </label>
            <textarea
              className="w-full rounded-md border border-gray-300 p-2.5 text-xs text-gray-900 placeholder-gray-400 focus:border-amber-600 focus:outline-hidden focus:ring-1 focus:ring-amber-600"
              disabled={isSubmitting}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Explain why this import batch is being rolled back (e.g., duplicated deployment batch from wrong branch)..."
              rows={3}
              value={reason}
            />
            <p className="mt-1 text-[11px] text-gray-500">
              {reason.trim().length} / 10 characters minimum
            </p>
          </div>

          <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-default">
            <button
              className="rounded-lg border border-gray-300 bg-white px-4 py-2 text-xs font-semibold text-gray-700 hover:bg-gray-50 transition"
              disabled={isSubmitting}
              onClick={onClose}
              type="button"
            >
              Cancel
            </button>
            <button
              className="inline-flex items-center gap-1.5 rounded-lg bg-amber-700 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-amber-800 transition disabled:opacity-50"
              disabled={isSubmitting || !isValid}
              type="submit"
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Rolling back...</span>
                </>
              ) : (
                <span>Confirm Rollback</span>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
