// components/hr-emploc/SubmitCorrectionModal.tsx
"use client";

import { useState } from "react";
import {
  Upload,
  FileText,
  Loader2,
  Send,
  AlertCircle,
  Trash2,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  submitHrcoCorrection,
  type HrEmplocListItem,
} from "@/lib/queries/hr_emploc";

type SubmitCorrectionModalProps = {
  isOpen: boolean;
  onClose: () => void;
  row: HrEmplocListItem | null;
  canUploadAttachments: boolean;
  onSuccess: (message: string) => void;
};

export function SubmitCorrectionModal({
  isOpen,
  onClose,
  row,
  canUploadAttachments,
  onSuccess,
}: SubmitCorrectionModalProps) {
  const [remarks, setRemarks] = useState("");
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen || !row) return null;

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const allowed = ["image/jpeg", "image/png", "application/pdf"];
    if (!allowed.includes(file.type)) {
      setError("Unsupported file format. Please upload JPG, PNG, or PDF.");
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      setError("File exceeds maximum allowed size of 5 MB.");
      return;
    }

    setError(null);
    setSelectedFile(file);
  };

  const handleRemoveFile = () => {
    setSelectedFile(null);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = remarks.trim();
    if (!trimmed) {
      setError("Correction remarks/notes are required before submitting.");
      return;
    }

    setIsSubmitting(true);
    setError(null);

    try {
      await submitHrcoCorrection({
        hrEmplocId: row.id,
        hrcoNotes: trimmed,
        attachments: selectedFile ? [selectedFile] : undefined,
      });

      onSuccess("Correction submitted for review.");
      handleClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to submit correction update.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleClose = () => {
    setRemarks("");
    setSelectedFile(null);
    setError(null);
    onClose();
  };

  const isDirty = Boolean(remarks.trim() || selectedFile);

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Submit Correction"
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={isSubmitting}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        <p className="text-xs text-text-muted">
          Send corrected compliance information to HR for review.
        </p>

        {/* Record Overview */}
        <div className="rounded-lg bg-surface-muted p-3.5 space-y-2 border border-border-subtle text-xs">
          <div className="flex justify-between">
            <span className="text-text-muted">Applicant:</span>
            <span className="font-semibold text-text-primary">{row.applicantName}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-muted">Account:</span>
            <span className="font-medium text-text-primary">{row.accountName ?? "--"}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-text-muted">Position:</span>
            <span className="font-medium text-text-primary">{row.positionTitle ?? "--"}</span>
          </div>
          {row.deficiencySummary && (
            <div className="border-t border-border-subtle pt-2 flex items-start justify-between gap-2">
              <span className="text-text-primary font-semibold shrink-0">Deficiency Reason:</span>
              <span className="text-text-primary text-right font-medium">{row.deficiencySummary}</span>
            </div>
          )}
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-center gap-2 rounded-lg bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] border border-[var(--danger-border)]">
              <AlertCircle className="h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* Notes / HRCO Remarks */}
          <div className="space-y-1.5">
            <label
              htmlFor="hrco-remarks"
              className="text-xs font-semibold text-text-primary"
            >
              Notes / HRCO Remarks <span className="text-[var(--danger-text)]">*</span>
            </label>
            <textarea
              id="hrco-remarks"
              rows={3}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Explain the correction made or details updated for HR to verify..."
              className="w-full rounded-md border border-border-default bg-surface p-2.5 text-xs text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-none focus:ring-1 focus:ring-brand-primary"
              disabled={isSubmitting}
            />
          </div>

          {/* Optional Attachment Upload */}
          {canUploadAttachments && (
            <div className="space-y-1.5 border-t border-border-subtle pt-3">
              <label className="text-xs font-semibold text-text-primary flex items-center justify-between">
                <span>Compliance Attachment (Optional)</span>
                <span className="text-[10px] text-text-muted font-normal">JPG, PNG, PDF max 5MB</span>
              </label>

              {selectedFile ? (
                <div className="flex items-center justify-between p-2.5 rounded-lg border border-border-default bg-surface-muted text-xs">
                  <div className="flex items-center gap-2 min-w-0">
                    <FileText className="h-4 w-4 text-brand-primary shrink-0" />
                    <span className="font-medium text-text-primary truncate">
                      {selectedFile.name}
                    </span>
                    <span className="text-text-muted text-[10px] shrink-0">
                      ({(selectedFile.size / 1024).toFixed(1)} KB)
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={handleRemoveFile}
                    className="p-1 text-text-muted hover:text-[var(--danger-text)] transition cursor-pointer"
                    title="Remove file"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              ) : (
                <label className="flex flex-col items-center justify-center p-3 border-2 border-dashed border-border-default rounded-lg cursor-pointer hover:border-border-strong hover:bg-surface-hover transition">
                  <Upload className="h-5 w-5 text-text-muted mb-1" />
                  <span className="text-xs font-medium text-text-primary">
                    Click to choose file
                  </span>
                  <input
                    type="file"
                    accept="image/jpeg,image/png,application/pdf"
                    onChange={handleFileChange}
                    className="hidden"
                    disabled={isSubmitting}
                  />
                </label>
              )}
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center justify-end gap-2.5 border-t border-border-subtle pt-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-primary px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-primary-hover transition cursor-pointer disabled:opacity-50"
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Submitting...</span>
                </>
              ) : (
                <>
                  <Send className="h-3.5 w-3.5" />
                  <span>Submit Correction for Review</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
