"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { AlertCircle, AlertTriangle, Loader2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
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

  const isDirty = hasSelected || Boolean(remarks.trim());

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Return for Correction"
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={isPending}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        <div className="flex items-center gap-2 pb-2 border-b border-border-subtle">
          <div className="p-1 rounded bg-surface-muted text-text-primary border border-border-subtle">
            <AlertTriangle className="h-4 w-4" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-text-primary">Deficient Requirements</h4>
            <p className="text-[11px] text-text-muted">
              {applicantName ? `${applicantName} ` : ""}
              {vcode ? `(${vcode})` : ""} — Select deficient requirements
            </p>
          </div>
        </div>

        {/* Scrollable body */}
        <div className="space-y-3 max-h-[60vh] overflow-y-auto pr-1">
          <div className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
            Deficient Requirements (select at least one)
          </div>
          <div className="space-y-2">
            {canonicalRequirements.map((req) => (
              <div
                key={req.key}
                className={`rounded-md border p-3 space-y-2 transition-colors ${
                  selectedIssues[req.key]
                    ? "border-border-strong bg-surface-muted"
                    : "border-border-subtle bg-surface hover:bg-surface-hover"
                }`}
              >
                <label className="flex items-center gap-2.5 cursor-pointer select-none">
                  <input
                    checked={selectedIssues[req.key] ?? false}
                    className="h-4 w-4 rounded border-border-default text-brand-primary focus:ring-brand-primary"
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
                      selectedIssues[req.key] ? "text-text-primary font-semibold" : "text-text-muted"
                    }`}
                  >
                    {req.label}
                  </span>
                </label>
                {selectedIssues[req.key] && (
                  <div className="pl-6">
                    <input
                      className="w-full rounded border border-border-default bg-surface px-2.5 py-1.5 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-border-strong"
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
            <div className="text-[10px] font-semibold uppercase tracking-wider text-text-muted">
              HR Compliance Remarks (Optional)
            </div>
            <textarea
              className="w-full rounded border border-border-default bg-surface px-2.5 py-2 text-xs text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-1 focus:ring-border-strong resize-none"
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
            <div className="rounded border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
              <span>{submitError}</span>
            </div>
          )}
        </div>

        {/* Footer actions */}
        <div className="flex items-center justify-end gap-2.5 border-t border-border-subtle pt-3">
          <button
            className="rounded-md border border-border-default bg-surface px-4 py-1.5 text-xs font-medium text-text-primary hover:bg-surface-hover transition disabled:opacity-50 cursor-pointer"
            disabled={isPending}
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className="inline-flex items-center gap-1.5 rounded-md bg-brand-primary px-4 py-1.5 text-xs font-semibold text-white hover:bg-brand-primary-hover transition disabled:opacity-50 disabled:cursor-not-allowed shadow-2xs cursor-pointer"
            disabled={!hasSelected || isPending}
            onClick={handleSubmit}
            type="button"
          >
            {isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            {isPending ? "Submitting…" : "Confirm & Return"}
          </button>
        </div>
      </div>
    </Modal>
  );
}
