// components/hr-emploc/ReviewApproveModal.tsx
"use client";

import { useState } from "react";
import {
  X,
  CheckCircle2,
  Loader2,
  AlertCircle,
  FileCheck,
} from "lucide-react";
import {
  approveHrEmplocReview,
  type HrEmplocListItem,
} from "@/lib/queries/hr_emploc";

type ReviewApproveModalProps = {
  isOpen: boolean;
  onClose: () => void;
  row: HrEmplocListItem | null;
  onSuccess: (message: string) => void;
};

export function ReviewApproveModal({
  isOpen,
  onClose,
  row,
  onSuccess,
}: ReviewApproveModalProps) {
  const [remarks, setRemarks] = useState("");
  const [isApproving, setIsApproving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen || !row) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsApproving(true);
    setError(null);

    try {
      const resolvedKeys = row.deficiencyIssues?.map((i) => i.code) ?? [];
      await approveHrEmplocReview({
        hrEmplocId: row.id,
        resolvedKeys,
        remarks: remarks.trim() || undefined,
      });

      onSuccess(`Correction for "${row.applicantName}" approved and moved to Ready.`);
      handleClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to approve correction review.");
    } finally {
      setIsApproving(false);
    }
  };

  const handleClose = () => {
    setRemarks("");
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
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-lg bg-emerald-50 text-emerald-600 border border-emerald-100">
              <FileCheck className="h-5 w-5" />
            </div>
            <div>
              <h3 className="text-base font-semibold text-gray-900">
                Approve Correction
              </h3>
              <p className="text-xs text-gray-500 mt-0.5">
                Confirm compliance and advance to Ready.
              </p>
            </div>
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

        <div className="rounded-lg bg-gray-50 p-3 space-y-2 border border-gray-100 text-xs">
          <div className="flex justify-between">
            <span className="text-gray-500">Applicant:</span>
            <span className="font-semibold text-gray-800">{row.applicantName}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-500">Account:</span>
            <span className="font-medium text-gray-700">{row.accountName ?? "--"}</span>
          </div>
          {row.deficiencySummary && (
            <div className="flex justify-between">
              <span className="text-gray-500">Deficiencies:</span>
              <span className="font-medium text-amber-800 text-right">{row.deficiencySummary}</span>
            </div>
          )}
          {row.notes && (
            <div className="border-t border-gray-200/60 pt-2 flex flex-col gap-0.5">
              <span className="text-gray-500 font-medium">HRCO Remarks:</span>
              <span className="text-gray-800 italic">&ldquo;{row.notes}&rdquo;</span>
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

          <div className="space-y-1.5">
            <label
              htmlFor="approval-remarks"
              className="text-xs font-semibold text-gray-700"
            >
              Approval Remarks (Optional)
            </label>
            <textarea
              id="approval-remarks"
              rows={2}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Optional confirmation note or audit remarks..."
              className="w-full rounded-md border border-gray-300 p-2.5 text-xs text-gray-900 placeholder:text-gray-400 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
              disabled={isApproving}
            />
          </div>

          <div className="flex items-center justify-end gap-2.5 border-t border-gray-100 pt-3">
            <button
              type="button"
              onClick={handleClose}
              disabled={isApproving}
              className="rounded-md border border-gray-300 bg-white px-3.5 py-1.5 text-xs font-semibold text-gray-700 hover:bg-gray-50 transition cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isApproving}
              className="inline-flex items-center gap-1.5 rounded-md bg-emerald-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-emerald-700 transition cursor-pointer disabled:opacity-50"
            >
              {isApproving ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  <span>Approving...</span>
                </>
              ) : (
                <>
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  <span>Approve & Move to Ready</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
