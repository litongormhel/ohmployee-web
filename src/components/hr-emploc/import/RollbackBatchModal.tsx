"use client";

import React, { useState } from "react";
import { AlertTriangle, Loader2, Undo2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";

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

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Rollback Import Batch"
      subtitle={fileName}
      icon={Undo2}
      maxWidthClass="max-w-md"
      disableBackdropClick={isSubmitting}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
    >
      <div className="p-6">
        <div className="mb-4 rounded-lg border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-[var(--danger-text)]">
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
          <div className="mb-4 rounded-md border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)]">
            {error}
          </div>
        )}

        <form className="space-y-4" onSubmit={handleSubmit}>
          <div>
            <label className="block text-xs font-semibold text-text-primary mb-1">
              Rollback Justification Reason *
            </label>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Explain why this batch must be rolled back (min 10 characters)..."
              className="w-full rounded-md border border-border-default bg-surface p-2 text-xs text-text-primary outline-none focus:border-brand-500"
              rows={3}
              disabled={isSubmitting}
              required
            />
            <p className="mt-1 text-[11px] text-text-muted">
              {reason.trim().length}/10 characters minimum
            </p>
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
              disabled={!isValid || isSubmitting}
              className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-md bg-[var(--danger-text)] text-white text-xs font-semibold hover:opacity-90 transition disabled:opacity-40"
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
    </Modal>
  );
}