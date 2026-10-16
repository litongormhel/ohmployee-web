// components/hr-emploc/UploadAttachmentModal.tsx
"use client";

import { useState } from "react";
import {
  X,
  Upload,
  FileText,
  Loader2,
  AlertCircle,
  Trash2,
} from "lucide-react";
import {
  uploadCorrectionAttachment,
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
      await uploadCorrectionAttachment({
        hrEmplocId: row.id,
        file: selectedFile,
      });

      onSuccess(`Attachment "${selectedFile.name}" uploaded successfully.`);
      handleClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to upload attachment.");
    } finally {
      setIsUploading(false);
    }
  };

  const handleClose = () => {
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
        className="relative w-full max-w-md rounded-xl border border-gray-200 bg-white shadow-2xl p-6 space-y-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between border-b border-gray-100 pb-3">
          <div>
            <h3 className="text-base font-semibold text-gray-900">
              Upload Compliance File
            </h3>
            <p className="text-xs text-gray-500 mt-0.5">
              Attach supporting compliance documents for {row.applicantName}.
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

        {row.deficiencySummary && (
          <div className="rounded-lg bg-amber-50 p-2.5 text-xs text-amber-900 border border-amber-200">
            <span className="font-semibold">Current Deficiency: </span>
            <span>{row.deficiencySummary}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-center gap-2 rounded-lg bg-red-50 p-3 text-xs text-red-700 border border-red-200">
              <AlertCircle className="h-4 w-4 shrink-0 text-red-600" />
              <span>{error}</span>
            </div>
          )}

          <div className="space-y-1.5">
            <label className="text-xs font-semibold text-gray-700 flex items-center justify-between">
              <span>Select File</span>
              <span className="text-[10px] text-gray-400 font-normal">JPG, PNG, PDF max 5MB</span>
            </label>

            {selectedFile ? (
              <div className="flex items-center justify-between p-3 rounded-lg border border-gray-200 bg-gray-50 text-xs">
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
              <label className="flex flex-col items-center justify-center p-6 border-2 border-dashed border-gray-200 rounded-lg cursor-pointer hover:border-gray-300 hover:bg-gray-50/50 transition">
                <Upload className="h-6 w-6 text-gray-400 mb-1.5" />
                <span className="text-xs font-medium text-gray-700">
                  Click to select attachment
                </span>
                <span className="text-[10px] text-gray-400 mt-0.5">
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

          <div className="flex items-center justify-end gap-2.5 border-t border-gray-100 pt-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isUploading}
              className="rounded-md border border-gray-300 bg-white px-3.5 py-1.5 text-xs font-semibold text-gray-700 hover:bg-gray-50 transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isUploading || !selectedFile}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-700 transition cursor-pointer disabled:opacity-50"
            >
              {isUploading ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Uploading...</span>
                </>
              ) : (
                <>
                  <Upload className="h-3.5 w-3.5" />
                  <span>Upload File</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
