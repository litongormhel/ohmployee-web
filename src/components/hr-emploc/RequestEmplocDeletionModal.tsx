// components/hr-emploc/RequestEmplocDeletionModal.tsx
"use client";

import { useState } from "react";
import { AlertCircle, AlertTriangle, Loader2, Trash2, X } from "lucide-react";
import { useRequestEmplocDeletion, HrEmplocDataError } from "@/lib/queries/hr_emploc";

type RequestEmplocDeletionModalProps = {
  hrEmplocId: string;
  candidateName: string;
  vcode: string;
  onClose: () => void;
  onSuccess: () => void;
};

export function RequestEmplocDeletionModal({
  hrEmplocId,
  candidateName,
  vcode,
  onClose,
  onSuccess,
}: RequestEmplocDeletionModalProps) {
  const [deletionType, setDeletionType] = useState<"backout" | "duplicate">("backout");
  const [reason, setReason] = useState("");
  const [originalEmplocId, setOriginalEmplocId] = useState("");
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const requestDeletionMutation = useRequestEmplocDeletion();

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setErrorMsg(null);

    const trimmedReason = reason.trim();
    if (!trimmedReason) {
      setErrorMsg("A detailed justification or remarks explaining the deletion is required.");
      return;
    }

    if (deletionType === "duplicate" && !originalEmplocId.trim()) {
      setErrorMsg("Please provide the original / master HR Emploc Record UUID to merge against.");
      return;
    }

    requestDeletionMutation.mutate(
      {
        hrEmplocId,
        reason: trimmedReason,
        deletionType,
        originalEmplocId: deletionType === "duplicate" ? originalEmplocId.trim() : null,
      },
      {
        onSuccess: () => {
          onSuccess();
        },
        onError: (err) => {
          if (err instanceof HrEmplocDataError) {
            setErrorMsg(err.message);
          } else if (err instanceof Error) {
            setErrorMsg(err.message);
          } else {
            setErrorMsg("Failed to submit deletion request. Please try again.");
          }
        },
      }
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40 backdrop-blur-xs"
        onClick={requestDeletionMutation.isPending ? undefined : onClose}
      />

      {/* Modal Card */}
      <div className="relative z-10 w-full max-w-lg bg-white rounded-lg border border-red-200 shadow-xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-red-100 px-5 py-3.5 bg-red-50/70">
          <div className="flex items-center gap-2">
            <div className="p-1.5 bg-red-100 text-red-700 rounded">
              <Trash2 className="h-4 w-4" />
            </div>
            <div>
              <h2 className="text-sm font-semibold text-red-950">
                Request Placement Separation / Deletion
              </h2>
              <p className="text-[11px] text-red-700">
                Submit an auditable request to remove or backout this recruit
              </p>
            </div>
          </div>
          <button
            aria-label="Close"
            className="inline-flex h-7 w-7 items-center justify-center rounded border border-red-200 text-red-400 hover:bg-red-100 hover:text-red-700 transition disabled:opacity-40"
            disabled={requestDeletionMutation.isPending}
            onClick={onClose}
            type="button"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Content Body */}
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Target Record Details */}
          <div className="rounded-md border border-gray-100 bg-gray-50/60 p-3 text-xs space-y-1">
            <div className="flex justify-between items-center">
              <span className="text-gray-500">Candidate:</span>
              <span className="font-semibold text-gray-900">{candidateName}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-gray-500">VCode:</span>
              <span className="font-mono text-gray-700 bg-white px-1.5 py-0.5 rounded border border-gray-200">
                {vcode}
              </span>
            </div>
          </div>

          {/* Deletion Reason Radio Selector */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-gray-700">
              Reason for Deletion <span className="text-red-500">*</span>
            </label>
            <div className="grid grid-cols-2 gap-3">
              <label
                className={`flex flex-col p-3 rounded-md border cursor-pointer transition-colors ${
                  deletionType === "backout"
                    ? "border-red-400 bg-red-50/40 text-red-900"
                    : "border-gray-200 bg-white hover:bg-gray-50 text-gray-700"
                }`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <input
                    type="radio"
                    name="deletionReason"
                    value="backout"
                    checked={deletionType === "backout"}
                    onChange={() => setDeletionType("backout")}
                    disabled={requestDeletionMutation.isPending}
                    className="h-4 w-4 text-red-600 focus:ring-red-500 border-gray-300"
                  />
                  <span className="text-xs font-bold">Applicant Backout</span>
                </div>
                <span className="text-[11px] text-gray-500 pl-6 leading-tight">
                  Candidate declined offer, backed out, or failed to report on start date.
                </span>
              </label>

              <label
                className={`flex flex-col p-3 rounded-md border cursor-pointer transition-colors ${
                  deletionType === "duplicate"
                    ? "border-red-400 bg-red-50/40 text-red-900"
                    : "border-gray-200 bg-white hover:bg-gray-50 text-gray-700"
                }`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <input
                    type="radio"
                    name="deletionReason"
                    value="duplicate"
                    checked={deletionType === "duplicate"}
                    onChange={() => setDeletionType("duplicate")}
                    disabled={requestDeletionMutation.isPending}
                    className="h-4 w-4 text-red-600 focus:ring-red-500 border-gray-300"
                  />
                  <span className="text-xs font-bold">Duplicate Record</span>
                </div>
                <span className="text-[11px] text-gray-500 pl-6 leading-tight">
                  Accidental multiple creation or import of the same applicant.
                </span>
              </label>
            </div>
          </div>

          {/* Original Record ID input (for Duplicate) */}
          {deletionType === "duplicate" && (
            <div className="space-y-1.5 p-3 rounded-md border border-amber-200 bg-amber-50/40">
              <label htmlFor="originalRecordIdInput" className="block text-xs font-semibold text-amber-900">
                Original Record UUID <span className="text-red-500">*</span>
              </label>
              <input
                id="originalRecordIdInput"
                type="text"
                required
                disabled={requestDeletionMutation.isPending}
                value={originalEmplocId}
                onChange={(e) => setOriginalEmplocId(e.target.value)}
                placeholder="e.g. 550e8400-e29b-41d4-a716-446655440000"
                className="w-full rounded border border-amber-300 bg-white px-3 py-1.5 text-xs font-mono text-gray-900 focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
              <p className="text-[10px] text-amber-800">
                Identifier of the legitimate record that will remain active in the system.
              </p>
            </div>
          )}

          {/* Justification remarks textarea */}
          <div className="space-y-1.5">
            <label htmlFor="justificationInput" className="block text-xs font-semibold text-gray-700">
              Justification & Operational Remarks <span className="text-red-500">*</span>
            </label>
            <textarea
              id="justificationInput"
              required
              rows={3}
              maxLength={1000}
              disabled={requestDeletionMutation.isPending}
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                setErrorMsg(null);
              }}
              placeholder="Detail reasons for separation, date of notice, or coordination background..."
              className="w-full rounded-md border border-gray-300 px-3 py-2 text-xs text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500 resize-none disabled:bg-gray-100"
            />
            <p className="text-[11px] text-gray-400">
              This reason will be visible to Encoders and Super Admins during request review.
            </p>
          </div>

          {/* Locking Alert */}
          <div className="rounded border border-red-200 bg-red-50 p-2.5 text-[11px] text-red-800 flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
            <span>
              <strong>Lock Notice:</strong> Submitting this request will lock this record into <em>Pending Deletion</em> status and temporarily prevent modifications, approvals, and employee number assignments until reviewed or withdrawn.
            </span>
          </div>

          {/* Error Message */}
          {errorMsg && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-xs text-red-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
              <span>{errorMsg}</span>
            </div>
          )}

          {/* Footer Actions */}
          <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-gray-100">
            <button
              type="button"
              disabled={requestDeletionMutation.isPending}
              onClick={onClose}
              className="rounded-md border border-gray-200 bg-white px-4 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50 transition disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={requestDeletionMutation.isPending || !reason.trim()}
              className="inline-flex items-center gap-1.5 rounded-md bg-red-600 px-4 py-2 text-xs font-semibold text-white hover:bg-red-700 transition disabled:opacity-50 disabled:cursor-not-allowed shadow-xs"
            >
              {requestDeletionMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              {requestDeletionMutation.isPending ? "Submitting..." : "Submit Deletion Request"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
