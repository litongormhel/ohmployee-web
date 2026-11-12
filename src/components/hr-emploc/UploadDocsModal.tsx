"use client";

import { useState, useRef } from "react";
import {
  Upload,
  FileText,
  Loader2,
  AlertCircle,
  Trash2,
  CheckCircle2,
  X,
  FileCheck,
  Eye,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";
import { compressDocumentFile } from "@/lib/utils/image_compression";
import { parseHrEmplocError, type ParsedHrEmplocError } from "@/lib/utils/hr_emploc_errors";
import {
  authorizeHrEmplocDocUpload,
  registerHrEmplocDocument,
  removeHrEmplocDocument,
  submitHrEmplocRequirements,
  submitHrcoCorrection,
  type HrEmplocListItem,
  type HrEmplocAttachment,
} from "@/lib/queries/hr_emploc";

interface UploadFileItem {
  id: string;
  file: File;
  compressedFile?: File;
  progress: number;
  status: "pending" | "compressing" | "authorizing" | "uploading" | "registering" | "completed" | "error";
  error?: string;
  storagePath?: string;
  objectPath?: string;
  registeredAttachment?: HrEmplocAttachment;
}

export interface UploadDocsModalProps {
  isOpen: boolean;
  onClose: () => void;
  row: HrEmplocListItem | null;
  mode?: "pending" | "correction";
  onSuccess: (message: string) => void;
  onPreviewAttachment?: (attachment: HrEmplocAttachment) => void;
}

export function UploadDocsModal({
  isOpen,
  onClose,
  row,
  mode = "pending",
  onSuccess,
  onPreviewAttachment,
}: UploadDocsModalProps) {
  const [queue, setQueue] = useState<UploadFileItem[]>([]);
  const [notes, setNotes] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [globalError, setGlobalError] = useState<ParsedHrEmplocError | null>(null);
  const [removingId, setRemovingId] = useState<string | null>(null);
  const [existingDocs, setExistingDocs] = useState<HrEmplocAttachment[]>(row?.attachments || []);

  const fileInputRef = useRef<HTMLInputElement>(null);

  if (!isOpen || !row) return null;

  const isCorrectionMode = mode === "correction" || row.hrStatus === "For Correction";
  const title = isCorrectionMode ? "Upload Correction Documents" : "Upload Requirements";
  const submitLabel = isCorrectionMode ? "Submit Correction" : "Submit & Move to For Emploc";

  const handleFilesSelected = (files: FileList | null) => {
    if (!files || files.length === 0) return;

    const allowedMimes = ["image/jpeg", "image/png", "image/webp", "application/pdf"];
    const newItems: UploadFileItem[] = [];

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      if (!allowedMimes.includes(file.type)) {
        setGlobalError({
          code: "DOC_INVALID_MIME_TYPE",
          title: "Unsupported File Type",
          message: `File "${file.name}" has an unsupported format. Allowed: PDF, JPG, PNG, WEBP.`,
          rawMessage: file.type,
        });
        continue;
      }

      if (file.size > 10 * 1024 * 1024) {
        setGlobalError({
          code: "DOC_FILE_TOO_LARGE",
          title: "File Too Large",
          message: `File "${file.name}" exceeds the maximum limit of 10 MB.`,
          rawMessage: `${file.size} bytes`,
        });
        continue;
      }

      newItems.push({
        id: `${file.name}-${file.size}-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        file,
        progress: 0,
        status: "pending",
      });
    }

    if (newItems.length > 0) {
      setGlobalError(null);
      setQueue((prev) => [...prev, ...newItems]);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    handleFilesSelected(e.dataTransfer.files);
  };

  const removeQueueItem = (id: string) => {
    setQueue((prev) => prev.filter((item) => item.id !== id));
  };

  const handleRemoveExistingDoc = async (attachment: HrEmplocAttachment) => {
    if (!confirm(`Are you sure you want to remove "${attachment.file_name}"?`)) return;

    setRemovingId(attachment.id);
    setGlobalError(null);
    try {
      await removeHrEmplocDocument(attachment.id);
      setExistingDocs((prev) => prev.filter((d) => d.id !== attachment.id));
    } catch (err) {
      setGlobalError(parseHrEmplocError(err));
    } finally {
      setRemovingId(null);
    }
  };

  // Upload sequential runner
  const processUploads = async (): Promise<boolean> => {
    const supabase = createClient();
    const stage = isCorrectionMode ? "correction" : "initial_requirements";
    let allOk = true;

    for (const item of queue) {
      if (item.status === "completed") continue; // Already registered

      try {
        // Step 1: Compress image if applicable
        setQueue((prev) =>
          prev.map((it) => (it.id === item.id ? { ...it, status: "compressing", progress: 10 } : it))
        );
        const fileToUpload = await compressDocumentFile(item.file);

        // Step 2: Authorize
        setQueue((prev) =>
          prev.map((it) => (it.id === item.id ? { ...it, status: "authorizing", progress: 25 } : it))
        );
        const authRes = await authorizeHrEmplocDocUpload({
          hrEmplocId: row.id,
          fileName: fileToUpload.name,
          mimeType: fileToUpload.type,
          fileSize: fileToUpload.size,
        });

        if (!authRes.authorized || !authRes.object_path) {
          throw new Error("Upload authorization rejected by server.");
        }

        // Step 3: Supabase Storage upload
        setQueue((prev) =>
          prev.map((it) => (it.id === item.id ? { ...it, status: "uploading", progress: 50 } : it))
        );
        const { error: uploadError } = await supabase.storage
          .from("hr-corrections")
          .upload(authRes.object_path, fileToUpload, {
            contentType: fileToUpload.type,
            upsert: false,
          });

        if (uploadError) {
          throw uploadError;
        }

        // Step 4: Register document in DB (idempotent)
        setQueue((prev) =>
          prev.map((it) => (it.id === item.id ? { ...it, status: "registering", progress: 85 } : it))
        );
        const registeredDoc = await registerHrEmplocDocument({
          hrEmplocId: row.id,
          storagePath: authRes.storage_path,
          fileName: fileToUpload.name,
          mimeType: fileToUpload.type,
          fileSize: fileToUpload.size,
          stage,
        });

        // Step 5: Mark completed
        setQueue((prev) =>
          prev.map((it) =>
            it.id === item.id
              ? {
                  ...it,
                  status: "completed",
                  progress: 100,
                  registeredAttachment: registeredDoc,
                  storagePath: authRes.storage_path,
                  objectPath: authRes.object_path,
                }
              : it
          )
        );
        setExistingDocs((prev) => [...prev, registeredDoc]);
      } catch (err) {
        allOk = false;
        const parsed = parseHrEmplocError(err);
        setQueue((prev) =>
          prev.map((it) =>
            it.id === item.id
              ? {
                  ...it,
                  status: "error",
                  error: parsed.message,
                }
              : it
          )
        );
        setGlobalError(parsed);
      }
    }

    return allOk;
  };

  const handleFinalSubmit = async () => {
    setIsSubmitting(true);
    setGlobalError(null);

    try {
      // If there are pending files in queue, upload them first
      const hasPendingQueue = queue.some((it) => it.status !== "completed");
      if (hasPendingQueue) {
        const uploadSuccess = await processUploads();
        if (!uploadSuccess) {
          setIsSubmitting(false);
          return;
        }
      }

      // Check that at least one document exists before moving to For Emploc in Pending mode
      const totalDocs = existingDocs.length;
      if (!isCorrectionMode && totalDocs === 0) {
        setGlobalError({
          code: "REQUIREMENTS_DOCS_MISSING",
          title: "Requirements Missing",
          message: "At least one requirement document must be uploaded before moving to 'For Emploc'.",
          rawMessage: "",
        });
        setIsSubmitting(false);
        return;
      }

      const trimmedNotes = notes.trim() || null;

      if (isCorrectionMode) {
        await submitHrcoCorrection({
          hrEmplocId: row.id,
          hrcoNotes: trimmedNotes,
        });
        onSuccess(`Correction submitted for ${row.applicantName}. Record moved to Review.`);
      } else {
        await submitHrEmplocRequirements({
          hrEmplocId: row.id,
          notes: trimmedNotes,
        });
        onSuccess(`Requirements submitted for ${row.applicantName}. Record moved to For Emploc.`);
      }

      onClose();
    } catch (err) {
      setGlobalError(parseHrEmplocError(err));
    } finally {
      setIsSubmitting(false);
    }
  };

  const isAnyProcessing = queue.some((it) =>
    ["compressing", "authorizing", "uploading", "registering"].includes(it.status)
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={title}
      subtitle={`Candidate: ${row.applicantName} • Account: ${row.accountName || "N/A"}`}
      maxWidthClass="max-w-2xl"
    >
      <div className="flex flex-col gap-4 text-xs">
        {/* Global Error Banner */}
        {globalError && (
          <div className="flex items-start gap-2.5 rounded-lg border border-status-danger/30 bg-status-danger/10 p-3 text-status-danger">
            <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
            <div className="flex-1">
              <p className="font-semibold">{globalError.title}</p>
              <p className="mt-0.5 text-2xs opacity-90 leading-relaxed">{globalError.message}</p>
            </div>
            <button
              type="button"
              onClick={() => setGlobalError(null)}
              className="text-status-danger hover:opacity-75"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        )}

        {/* Existing Documents List */}
        {existingDocs.length > 0 && (
          <div className="flex flex-col gap-1.5">
            <p className="font-semibold text-text-secondary uppercase tracking-wider text-3xs">
              Existing Documents ({existingDocs.length})
            </p>
            <div className="flex flex-col divide-y divide-border-subtle rounded-lg border border-border-default bg-surface-subtle max-h-40 overflow-y-auto">
              {existingDocs.map((doc) => (
                <div
                  key={doc.id}
                  className="flex items-center justify-between px-3 py-2 text-xs"
                >
                  <div className="flex items-center gap-2 overflow-hidden pr-2">
                    <FileCheck className="h-4 w-4 shrink-0 text-status-success" />
                    <span className="truncate text-text-primary" title={doc.file_name}>
                      {doc.file_name}
                    </span>
                    <span className="rounded bg-surface-hover px-1.5 py-0.5 text-3xs text-text-muted">
                      {doc.stage === "correction" ? "Correction" : "Requirement"}
                    </span>
                  </div>
                  <div className="flex items-center gap-1.5 shrink-0">
                    {onPreviewAttachment && (
                      <button
                        type="button"
                        onClick={() => onPreviewAttachment(doc)}
                        className="rounded p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary cursor-pointer"
                        title="Preview Document"
                      >
                        <Eye className="h-3.5 w-3.5" />
                      </button>
                    )}
                    {doc.can_remove && (
                      <button
                        type="button"
                        onClick={() => handleRemoveExistingDoc(doc)}
                        disabled={removingId === doc.id}
                        className="rounded p-1 text-text-muted hover:bg-status-danger/10 hover:text-status-danger cursor-pointer disabled:opacity-50"
                        title="Remove Document"
                      >
                        {removingId === doc.id ? (
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        ) : (
                          <Trash2 className="h-3.5 w-3.5" />
                        )}
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Multi-file Dropzone */}
        <div
          onDragOver={(e) => e.preventDefault()}
          onDrop={handleDrop}
          onClick={() => fileInputRef.current?.click()}
          className="flex flex-col items-center justify-center rounded-xl border-2 border-dashed border-border-default bg-surface-subtle/50 px-4 py-6 text-center transition hover:border-accent-primary hover:bg-accent-primary/5 cursor-pointer"
        >
          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept=".pdf,.jpg,.jpeg,.png,.webp"
            className="hidden"
            onChange={(e) => handleFilesSelected(e.target.files)}
          />
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-accent-primary/10 text-accent-primary mb-2">
            <Upload className="h-5 w-5" />
          </div>
          <p className="text-xs font-semibold text-text-primary">
            Click to browse or drag and drop documents
          </p>
          <p className="mt-1 text-3xs text-text-muted">
            PDF, JPG, PNG, WEBP up to 10 MB each • Images are automatically optimized
          </p>
        </div>

        {/* Selected Upload Queue */}
        {queue.length > 0 && (
          <div className="flex flex-col gap-1.5">
            <p className="font-semibold text-text-secondary uppercase tracking-wider text-3xs">
              Selected to Upload ({queue.length})
            </p>
            <div className="flex flex-col gap-1.5 max-h-48 overflow-y-auto">
              {queue.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center justify-between rounded-lg border border-border-default bg-surface-base px-3 py-2"
                >
                  <div className="flex items-center gap-2 overflow-hidden pr-2">
                    <FileText className="h-4 w-4 shrink-0 text-text-muted" />
                    <div className="truncate text-left">
                      <p className="truncate text-xs text-text-primary" title={item.file.name}>
                        {item.file.name}
                      </p>
                      <p className="text-3xs text-text-muted">
                        {(item.file.size / 1024).toFixed(0)} KB •{" "}
                        <span className="capitalize">{item.status}</span>
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 shrink-0">
                    {item.status === "completed" ? (
                      <span className="flex items-center gap-1 text-2xs text-status-success font-medium">
                        <CheckCircle2 className="h-3.5 w-3.5" />
                        Uploaded
                      </span>
                    ) : item.status === "error" ? (
                      <span className="text-2xs text-status-danger font-medium" title={item.error}>
                        Failed
                      </span>
                    ) : item.status !== "pending" ? (
                      <div className="flex items-center gap-1 text-2xs text-accent-primary">
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        <span>{item.progress}%</span>
                      </div>
                    ) : (
                      <button
                        type="button"
                        onClick={() => removeQueueItem(item.id)}
                        className="rounded p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary"
                        title="Remove from queue"
                      >
                        <X className="h-3.5 w-3.5" />
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Notes / Remarks Field */}
        <div className="flex flex-col gap-1">
          <label htmlFor="notes" className="font-semibold text-text-primary text-2xs">
            Ops Remarks / Notes (Optional)
          </label>
          <textarea
            id="notes"
            rows={2}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Add any relevant notes about uploaded requirements..."
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-xs text-text-primary placeholder:text-text-muted focus:border-accent-primary focus:outline-hidden"
          />
        </div>

        {/* Modal Actions */}
        <div className="mt-2 flex items-center justify-end gap-2 border-t border-border-subtle pt-3">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting || isAnyProcessing}
            className="rounded-lg border border-border-default px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover disabled:opacity-50"
          >
            Cancel
          </button>

          <button
            type="button"
            onClick={handleFinalSubmit}
            disabled={isSubmitting || isAnyProcessing || (existingDocs.length === 0 && queue.length === 0)}
            className="inline-flex items-center gap-1.5 rounded-lg bg-brand-button px-4 py-1.5 text-xs font-semibold text-white shadow-xs hover:bg-brand-button-hover disabled:opacity-50 cursor-pointer"
          >
            {isSubmitting || isAnyProcessing ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                <span>Processing...</span>
              </>
            ) : (
              <span>{submitLabel}</span>
            )}
          </button>
        </div>
      </div>
    </Modal>
  );
}
