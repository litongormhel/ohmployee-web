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
  const isDirty = Boolean(reason.trim());

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

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Escape") {
      if (isSubmitting || isDirty) {
        e.preventDefault();
        return;
      }
      onClose();
    }
  };

  return (
    <div
      aria-modal="true"
      className="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-4 backdrop-blur-xs animate-fade-in"
      role="dialog"
      onKeyDown={handleKeyDown}
    >
      {/* Backdrop: click disabled per modal hardening rules */}
      <div className="absolute inset-0" />

      <div className="relative w-full max-w-md rounded-xl border border-border-default bg-surface p-6 shadow-xl z-10">
        <button
          className="absolute top-4 right-4 text-text-muted hover:text-text-primary transition cursor-pointer disabled:opacity-40"
          disabled={isSubmitting}
          onClick={onClose}
          type="button"
          aria-label="Close"
        >
          <X className="h-5 w-5" />
        </button>

        <div className="flex items-center gap-3 pb-3 border-b border-border-subtle">
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)]">
            <Undo2 className="h-5 w-5" />
          </div>
          <div>
            <h2 className="text-base font-bold text-text-primary">Rollback Import Batch</h2>
            <p className="text-xs text-text-muted truncate max-w-[260px]">{fileName}</p>
          </div>
        </div>

        <div className="mt-4 rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-[var(--danger-text)]">
          <div className="flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
            <div className="text-xs">
              <p className="font-semibold">Destructive Action Notice</p>
              <p className="mt-0.5 opacity-90">
                This will soft-delete all HR Emploc records created by this batch, restore reserved Plantilla slots to Open, and reopen vacancies. Records that have already moved to Plantilla cannot be rolled back.
              </p>
            </div>
          </div>
        </div>

        {error && (
          <div className="mt-4 rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)]">
            {error}
          </div>
        )}

        <form className="mt-4 space-y-4" onSubmit={handleSubmit}>
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-text-primary mb-1">
              Rollback Justification / Reason * (min 10 characters)
            </label>
            <textarea
              className="w-full rounded-md border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-border-strong focus:outline-hidden focus:ring-1 focus:ring-border-strong"
              disabled={isSubmitting}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Explain why this import batch is being rolled back (e.g., duplicated deployment batch from wrong branch)..."
              rows={3}
              value={reason}
            />
            <p className="mt-1 text-[11px] text-text-muted">
              {reason.trim().length} / 10 characters minimum
            </p>
          </div>

          <div className="flex items-center justify-end gap-2 pt-2 border-t border-border-subtle">
            <button
              className="rounded-lg border border-border-default bg-surface px-4 py-2 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
              disabled={isSubmitting}
              onClick={onClose}
              type="button"
            >
              Cancel
            </button>
            <button
              className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] px-4 py-2 text-xs font-semibold text-[var(--danger-text)] shadow-xs hover:opacity-90 transition disabled:opacity-50 cursor-pointer"
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
