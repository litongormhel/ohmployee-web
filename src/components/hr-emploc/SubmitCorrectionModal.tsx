// components/hr-emploc/SubmitCorrectionModal.tsx
"use client";

import { useState } from "react";
import {
  X,
  Upload,
  FileText,
  Loader2,
  Send,
  AlertCircle,
  Trash2,
} from "lucide-react";
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

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 animate-in fade-in duration-150"
      onClick={handleClose}
      role="dialog"
      aria-modal="true"
    >
      <div
        className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl p-6 space-y-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between border-b border-gray-100 pb-3">
          <div>
            <h3 className="text-base font-semibold text-gray-900">
              Submit Correction
            </h3>
            <p className="text-xs text-gray-500 mt-0.5">
              Send corrected compliance information to HR for review.
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="text-gray-400 hover:text-gray-600 rounded-md p-1 transition cursor-pointer"
            aria-label="Close modal"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Record Overview */}
        <div className="rounded-lg bg-gray-50 p-3.5 space-y-2 border border-gray-100 text-xs">
          <div className="flex justify-between">
            <span className="text-gray-500">Applicant:</span>
            <span className="font-semibold text-gray-800">{row.applicantName}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-500">Account:</span>
            <span className="font-medium text-gray-700">{row.accountName ?? "--"}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-500">Position:</span>
            <span className="font-medium text-gray-700">{row.positionTitle ?? "--"}</span>
          </div>
          {row.deficiencySummary && (
            <div className="border-t border-gray-200/60 pt-2 flex items-start justify-between gap-2">
              <span className="text-amber-800 font-semibold shrink-0">Deficiency Reason:</span>
              <span className="text-amber-900 text-right font-medium">{row.deficiencySummary}</span>
            </div>
          )}
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-center gap-2 rounded-lg bg-red-50 p-3 text-xs text-red-700 border border-red-200">
              <AlertCircle className="h-4 w-4 shrink-0 text-red-600" />
              <span>{error}</span>
            </div>
          )}

          {/* Notes / HRCO Remarks */}
          <div className="space-y-1.5">
            <label
              htmlFor="hrco-remarks"
              className="text-xs font-semibold text-gray-700"
            >
              Notes / HRCO Remarks <span className="text-red-500">*</span>
            </label>
            <textarea
              id="hrco-remarks"
              rows={3}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Explain the correction made or details updated for HR to verify..."
              className="w-full rounded-md border border-gray-300 p-2.5 text-xs text-gray-900 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              disabled={isSubmitting}
            />
          </div>

          {/* Optional Attachment Upload */}
          {canUploadAttachments && (
            <div className="space-y-1.5 border-t border-gray-100 pt-3">
              <label className="text-xs font-semibold text-gray-700 flex items-center justify-between">
                <span>Compliance Attachment (Optional)</span>
                <span className="text-[10px] text-gray-400 font-normal">JPG, PNG, PDF max 5MB</span>
              </label>

              {selectedFile ? (
                <div className="flex items-center justify-between p-2.5 rounded-lg border border-gray-200 bg-gray-50/80 text-xs">
                  <div className="flex items-center gap-2 min-w-0">
                    <FileText className="h-4 w-4 text-blue-600 shrink-0" />
                    <span className="font-medium text-gray-800 truncate">
                      {selectedFile.name}
                    </span>
                    <span className="text-gray-400 text-[10px] shrink-0">
                      ({(selectedFile.size / 1024).toFixed(1)} KB)
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={handleRemoveFile}
                    className="p-1 text-gray-400 hover:text-red-600 transition cursor-pointer"
                    title="Remove file"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              ) : (
                <label className="flex flex-col items-center justify-center p-3 border-2 border-dashed border-gray-200 rounded-lg cursor-pointer hover:border-gray-300 hover:bg-gray-50/50 transition">
                  <Upload className="h-5 w-5 text-gray-400 mb-1" />
                  <span className="text-xs font-medium text-gray-600">
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
          <div className="flex items-center justify-end gap-2.5 border-t border-gray-100 pt-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isSubmitting}
              className="rounded-md border border-gray-300 bg-white px-3.5 py-1.5 text-xs font-semibold text-gray-700 hover:bg-gray-50 transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-700 transition cursor-pointer disabled:opacity-50"
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
    </div>
  );
}
