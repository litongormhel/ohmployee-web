"use client";

import React, { useState } from "react";
import { AlertCircle, Loader2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";

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

  const isDirty = Boolean(note.trim() || selectedCode !== "invalid_file");

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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Reject Import Batch"
      subtitle={fileName}
      icon={AlertCircle}
      maxWidthClass="max-w-md"
      disableBackdropClick={isSubmitting}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
    >
      <div className="p-6">
        {error && (
          <div className="mb-4 rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)]">
            {error}
          </div>
        )}

        <form className="space-y-4" onSubmit={handleSubmit}>
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-text-primary mb-2">
              Select Reason for Rejection *
            </label>
            <div className="space-y-2">
              {REJECTION_REASONS.map((r) => (
                <label
                  key={r.code}
                  className={`flex items-center gap-2 p-2.5 rounded-lg border text-xs cursor-pointer transition ${
                    selectedCode === r.code
                      ? "border-border-default bg-surface-muted text-text-primary font-semibold"
                      : "border-border-default bg-surface text-text-secondary hover:bg-surface-hover"
                  }`}
                >
                  <input
                    type="radio"
                    name="rejectionReason"
                    value={r.code}
                    checked={selectedCode === r.code}
                    onChange={() => setSelectedCode(r.code)}
                    className="accent-brand-600"
                    disabled={isSubmitting}
                  />
                  <span>{r.label}</span>
                </label>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-text-primary mb-1">
              Internal Rejection Note {selectedCode === "others" ? "*" : "(Optional)"}
            </label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Provide context on why this batch was rejected..."
              className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary outline-none focus:border-brand-500"
              rows={3}
              disabled={isSubmitting}
              required={selectedCode === "others"}
            />
          </div>

          <div className="flex items-center justify-end gap-3 pt-4 border-t border-border-subtle">
            <button
              type="button"
              onClick={onClose}
              disabled={isSubmitting}
              className="px-3.5 py-1.5 rounded-md border border-border-default bg-surface text-xs font-medium text-text-secondary hover:bg-surface-hover transition disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting || (selectedCode === "others" && !note.trim())}
              className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-md bg-[var(--danger-text)] text-white text-xs font-semibold hover:opacity-90 transition disabled:opacity-40"
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
    </Modal>
  );
}