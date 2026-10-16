"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { AlertCircle, AlertTriangle, Loader2, X } from "lucide-react";
import {
  tagWebHrEmplocDeficiency,
  HrEmplocDataError,
  type TagDeficiencyParams,
} from "@/lib/queries/hr_emploc";

export interface TagDeficiencyModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  hrEmplocId: string;
  applicantName?: string;
  vcode?: string;
}

const canonicalRequirements = [
  { key: "sss_card", label: "SSS Card / ID Document" },
  { key: "pagibig_id", label: "PagIBIG Member ID" },
  { key: "philhealth_id", label: "PhilHealth ID / MDF" },
  { key: "nbi_clearance", label: "NBI Clearance Certificate" },
  { key: "birth_certificate", label: "PSA Birth Certificate" },
];

export function TagDeficiencyModal({
  isOpen,
  onClose,
  onSuccess,
  hrEmplocId,
  applicantName,
  vcode,
}: TagDeficiencyModalProps) {
  const queryClient = useQueryClient();
  const [selectedIssues, setSelectedIssues] = useState<Record<string, boolean>>({});
  const [issueNotes, setIssueNotes] = useState<Record<string, string>>({});
  const [remarks, setRemarks] = useState("");
  const [submitError, setSubmitError] = useState<string | null>(null);

  const hasSelected = canonicalRequirements.some((r) => selectedIssues[r.key]);

  const { mutate, isPending } = useMutation({
    mutationFn: (params: TagDeficiencyParams) => tagWebHrEmplocDeficiency(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      onSuccess();
    },
    onError: (err) => {
      if (err instanceof HrEmplocDataError) {
        if (err.kind === "access_denied") {
          setSubmitError(
            "You are not authorized to return this record for correction. Your session may have expired."
          );
        } else if (err.kind === "invalid_state") {
          setSubmitError(err.message);
        } else {
          setSubmitError("A network error occurred. Please check your connection and try again.");
        }
      } else {
        setSubmitError("An unexpected error occurred. Please try again.");
      }
    },
  });

  if (!isOpen) return null;

  function handleSubmit() {
    setSubmitError(null);
    const deficiencies: Record<string, string> = {};
    for (const req of canonicalRequirements) {
      if (selectedIssues[req.key]) {
        deficiencies[req.key] = issueNotes[req.key]?.trim() ?? "";
      }
    }
    mutate({
      hrEmplocId,
      deficiencies,
      remarks: remarks.trim() || null,
    });
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40 backdrop-blur-xs"
        onClick={isPending ? undefined : onClose}
      />

      {/* Modal panel */}
      <div className="relative z-10 w-full max-w-lg bg-white rounded-lg border border-gray-200 shadow-xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-5 py-3.5 bg-amber-50/50">
          <div className="flex items-center gap-2">
            <div className="p-1 rounded bg-amber-100 text-amber-700">
              <AlertTriangle className="h-4 w-4" />
            </div>
            <div>
              <h2 className="text-sm font-semibold text-gray-900">Return for Correction</h2>
              <p className="text-[11px] text-gray-500">
                {applicantName ? `${applicantName} ` : ""}
                {vcode ? `(${vcode})` : ""} — Select deficient requirements
              </p>
            </div>
          </div>
          <button
            aria-label="Close"
            className="inline-flex h-7 w-7 items-center justify-center rounded border border-gray-200 text-gray-400 hover:bg-gray-50 hover:text-gray-600 transition disabled:opacity-40 cursor-pointer"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Scrollable body */}
        <div className="px-5 py-4 space-y-3 max-h-[60vh] overflow-y-auto">
          <div className="text-[10px] font-semibold uppercase tracking-wider text-gray-400">
            Deficient Requirements (select at least one)
          </div>
          <div className="space-y-2">
            {canonicalRequirements.map((req) => (
              <div
                key={req.key}
                className={`rounded-md border p-3 space-y-2 transition-colors ${
                  selectedIssues[req.key]
                    ? "border-amber-200 bg-amber-50/40"
                    : "border-gray-100 bg-gray-50/30 hover:bg-gray-50"
                }`}
              >
                <label className="flex items-center gap-2.5 cursor-pointer select-none">
                  <input
                    checked={selectedIssues[req.key] ?? false}
                    className="h-4 w-4 rounded border-gray-300 accent-amber-600"
                    disabled={isPending}
                    onChange={(e) => {
                      setSelectedIssues((prev) => ({
                        ...prev,
                        [req.key]: e.target.checked,
                      }));
                      if (!e.target.checked) {
                        setIssueNotes((prev) => ({ ...prev, [req.key]: "" }));
                      }
                    }}
                    type="checkbox"
                  />
                  <span
                    className={`text-xs font-medium ${
                      selectedIssues[req.key] ? "text-amber-900 font-semibold" : "text-gray-700"
                    }`}
                  >
                    {req.label}
                  </span>
                </label>
                {selectedIssues[req.key] && (
                  <div className="pl-6">
                    <input
                      className="w-full rounded border border-amber-200 bg-white px-2.5 py-1.5 text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-amber-300"
                      disabled={isPending}
                      maxLength={500}
                      onChange={(e) =>
                        setIssueNotes((prev) => ({
                          ...prev,
                          [req.key]: e.target.value,
                        }))
                      }
                      placeholder="Brief deficiency note (optional)"
                      type="text"
                      value={issueNotes[req.key] ?? ""}
                    />
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* Remarks */}
          <div className="pt-1 space-y-1.5">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-gray-400">
              HR Compliance Remarks (Optional)
            </div>
            <textarea
              className="w-full rounded border border-gray-200 px-2.5 py-2 text-xs text-gray-800 placeholder-gray-400 focus:outline-none focus:ring-1 focus:ring-blue-300 resize-none"
              disabled={isPending}
              maxLength={1000}
              onChange={(e) => setRemarks(e.target.value)}
              placeholder="Add overall remarks for the field coordinator…"
              rows={3}
              value={remarks}
            />
          </div>

          {/* Inline error */}
          {submitError && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-xs text-red-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
              <span>{submitError}</span>
            </div>
          )}
        </div>

        {/* Footer actions */}
        <div className="flex items-center justify-end gap-2.5 border-t border-gray-100 px-5 py-3 bg-gray-50/50">
          <button
            className="rounded-md border border-gray-200 bg-white px-4 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 transition disabled:opacity-50 cursor-pointer"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className="inline-flex items-center gap-1.5 rounded-md bg-amber-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-amber-700 transition disabled:opacity-50 disabled:cursor-not-allowed shadow-2xs cursor-pointer"
            disabled={!hasSelected || isPending}
            onClick={handleSubmit}
            type="button"
          >
            {isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            {isPending ? "Submitting…" : "Confirm & Return"}
          </button>
        </div>
      </div>
    </div>
  );
}
