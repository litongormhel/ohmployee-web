// components/hr-emploc/UploadAttachmentModal.tsx
"use client";

import { useState } from "react";
import {
  Upload,
  FileText,
  Loader2,
  AlertCircle,
  Trash2,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  submitHrcoCorrection,
  type HrEmplocListItem,
} from "@/lib/queries/hr_emploc";

type UploadAttachmentModalProps = {
  isOpen: boolean;
  onClose: () => void;
  row: HrEmplocListItem | null;
  onSuccess: (message: string) => void;
};

export function UploadAttachmentModal({
  isOpen,
  onClose,
  row,
  onSuccess,
}: UploadAttachmentModalProps) {
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [notes, setNotes] = useState("");
  const [isUploading, setIsUploading] = useState(false);
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
    if (!selectedFile) {
      setError("Please select a file to upload.");
      return;
    }

    setIsUploading(true);
    setError(null);

    try {
      const trimmedNotes = notes.trim() || null;
      await submitHrcoCorrection({
        hrEmplocId: row.id,
        hrcoNotes: trimmedNotes,
        attachments: [selectedFile],
      });

      onSuccess(`Attachment "${selectedFile.name}" uploaded and submitted to Review.`);
      handleClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to upload attachment and submit correction.");
    } finally {
      setIsUploading(false);
    }
  };

  const handleClose = () => {
    setSelectedFile(null);
    setNotes("");
    setError(null);
    onClose();
  };

  const isDirty = Boolean(selectedFile || notes.trim());

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Upload Compliance File"
      maxWidthClass="max-w-md"
      disableBackdropClick={true}
      isSubmitting={isUploading}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        <p className="text-xs text-text-muted">
          Attach supporting compliance documents for {row.applicantName}.
        </p>

        {row.deficiencySummary && (
          <div className="rounded-lg bg-surface-muted p-2.5 text-xs text-text-primary border border-border-subtle">
            <span className="font-semibold">Current Deficiency: </span>
            <span>{row.deficiencySummary}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-center gap-2 rounded-lg bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] border border-[var(--danger-border)]">
              <AlertCircle className="h-4 w-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="space-y-1.5">
            <label className="text-xs font-semibold text-text-primary flex items-center justify-between">
              <span>Select File</span>
              <span className="text-[10px] text-text-muted font-normal">JPG, PNG, PDF max 5MB</span>
            </label>

            {selectedFile ? (
              <div className="flex items-center justify-between p-3 rounded-lg border border-border-default bg-surface-muted text-xs">
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
              <label className="flex flex-col items-center justify-center p-6 border-2 border-dashed border-border-default rounded-lg cursor-pointer hover:border-border-strong hover:bg-surface-hover transition">
                <Upload className="h-6 w-6 text-text-muted mb-1.5" />
                <span className="text-xs font-medium text-text-primary">
                  Click to select attachment
                </span>
                <span className="text-[10px] text-text-muted mt-0.5">
                  or drag and drop here
                </span>
                <input
                  type="file"
                  accept="image/jpeg,image/png,application/pdf"
                  onChange={handleFileChange}
                  className="hidden"
                  disabled={isUploading}
                />
              </label>
            )}
          </div>

          <div className="space-y-1.5">
            <label className="text-xs font-semibold text-text-primary flex items-center justify-between">
              <span>Compliance Notes</span>
              <span className="text-[10px] text-text-muted font-normal">(Optional)</span>
            </label>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Add notes for the compliance reviewer (optional)..."
              disabled={isUploading}
              rows={2}
              maxLength={500}
              className="w-full rounded border border-border-default bg-surface px-2.5 py-1.5 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-border-strong resize-none"
            />
          </div>

          <div className="flex items-center justify-end gap-2.5 border-t border-border-subtle pt-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isUploading}
              className="rounded-md border border-border-default bg-surface px-3.5 py-1.5 text-xs font-semibold text-text-primary hover:bg-surface-hover transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isUploading || !selectedFile}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-button px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-primary-hover transition cursor-pointer disabled:opacity-50"
            >
              {isUploading ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Submitting to Review...</span>
                </>
              ) : (
                <>
                  <Upload className="h-3.5 w-3.5" />
                  <span>Upload & Submit to Review</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
