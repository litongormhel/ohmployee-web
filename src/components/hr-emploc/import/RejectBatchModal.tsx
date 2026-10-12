"use client";

import React, { useState } from "react";
import { AlertCircle, Loader2, X } from "lucide-react";

export const REJECTION_REASONS = [
  { code: "invalid_file", label: "Invalid or incorrect file" },
  { code: "wrong_group", label: "Wrong group selected" },
  { code: "invalid_vcodes", label: "VCodes do not match records" },
  { code: "data_errors", label: "Too many data errors" },
  { code: "unauthorized", label: "Unauthorized submission" },
  { code: "duplicate_batch", label: "Duplicate import batch" },
  { code: "others", label: "Others (specify in note)" },
] as const;

interface RejectBatchModalProps {
  isOpen: boolean;
  onClose: () => void;
  fileName: string;
  onConfirm: (reasonCode: string, reasonNote?: string | null) => Promise<void>;
  isSubmitting?: boolean;
}

export function RejectBatchModal({
  isOpen,
  onClose,
  fileName,
  onConfirm,
  isSubmitting = false,
}: RejectBatchModalProps) {
  const [selectedCode, setSelectedCode] = useState<string>("invalid_file");
  const [note, setNote] = useState<string>("");
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      await onConfirm(selectedCode, note.trim() || null);
      onClose();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to reject import batch");
    }
  }

  return (
    <div
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs animate-fade-in"
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
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-red-100 text-red-600">
            <AlertCircle className="h-5 w-5" />
          </div>
          <div>
            <h2 className="text-base font-bold text-gray-900">Reject Import Batch</h2>
            <p className="text-xs text-gray-500 truncate max-w-[260px]">{fileName}</p>
          </div>
        </div>

        {error && (
          <div className="mt-4 rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
            {error}
          </div>
        )}

        <form className="mt-4 space-y-4" onSubmit={handleSubmit}>
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-gray-600 mb-2">
              Select Reason for Rejection *
            </label>
            <div className="space-y-2 max-h-48 overflow-y-auto pr-1">
              {REJECTION_REASONS.map((reason) => (
                <label
                  key={reason.code}
                  className={`flex items-center gap-2.5 rounded-lg border p-2.5 text-xs font-medium cursor-pointer transition ${
                    selectedCode === reason.code
                      ? "border-red-500 bg-red-50/50 text-red-900"
                      : "border-gray-200 bg-white text-gray-700 hover:bg-gray-50"
                  }`}
                >
                  <input
                    checked={selectedCode === reason.code}
                    className="h-4 w-4 text-red-600 focus:ring-red-500 border-gray-300"
                    name="rejectionReason"
                    onChange={() => setSelectedCode(reason.code)}
                    type="radio"
                    value={reason.code}
                  />
                  <span>{reason.label}</span>
                </label>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-gray-600 mb-1">
              Additional Note (Optional)
            </label>
            <textarea
              className="w-full rounded-md border border-gray-300 p-2.5 text-xs text-gray-900 placeholder-gray-400 focus:border-red-500 focus:outline-hidden focus:ring-1 focus:ring-red-500"
              disabled={isSubmitting}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Provide extra details for the encoder..."
              rows={3}
              value={note}
            />
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
              className="inline-flex items-center gap-1.5 rounded-lg bg-red-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-red-700 transition disabled:opacity-50"
              disabled={isSubmitting || !selectedCode}
              type="submit"
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Rejecting...</span>
                </>
              ) : (
                <span>Confirm Rejection</span>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
