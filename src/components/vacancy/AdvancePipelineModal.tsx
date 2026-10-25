"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, Loader2, RotateCcw, UserMinus } from "lucide-react";
import {
  fetchBackoutReasons,
  fetchRejectedReasons,
  useFailBackoutApplicant,
  useUpdateApplicantPipeline,
} from "@/lib/queries/vacancy";
import { Modal } from "@/components/shared/Modal";

export interface AdvancePipelineModalProps {
  isOpen: boolean;
  onClose: () => void;
  applicant: {
    id: string;
    fullName: string;
    contactNumber?: string | null;
    status: string;
    vcode: string;
    positionTitle?: string | null;
    recruitmentRemarks?: string | null;
    opsRemarks?: string | null;
    followUpDate?: string | null;
  } | null;
  onSuccess?: () => void;
}

const PROGRESSIVE_STAGES = [
  { value: "for_interview_intro", label: "For Interview / Intro" },
  { value: "for_requirements", label: "For Requirements" },
  { value: "for_medical", label: "For Medical" },
  { value: "pending_approval", label: "Pending Approval" },
  { value: "for_deployment", label: "For Deployment" },
  { value: "for_onboard", label: "For Onboard" },
];

const TERMINAL_STAGES = [
  { value: "backout", label: "Backout (Candidate Dropout)" },
  { value: "failed", label: "Failed / Rejected by Ops" },
  { value: "rejected", label: "Rejected (Applicant)" },
  { value: "did_not_report", label: "Did Not Report (DNR)" },
];

export function AdvancePipelineModal({
  isOpen,
  onClose,
  applicant,
  onSuccess,
}: AdvancePipelineModalProps) {
  if (!isOpen || !applicant) return null;

  return (
    <AdvancePipelineModalContent
      isOpen={isOpen}
      applicant={applicant}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function AdvancePipelineModalContent({
  isOpen,
  applicant,
  onClose,
  onSuccess,
}: {
  isOpen: boolean;
  applicant: NonNullable<AdvancePipelineModalProps["applicant"]>;
  onClose: () => void;
  onSuccess?: () => void;
}) {
  const updateMutation = useUpdateApplicantPipeline();
  const failBackoutMutation = useFailBackoutApplicant();

  const resolveInitialStage = (status: string) => {
    const raw = status
      ? status.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")
      : "";
    if (TERMINAL_STAGES.some((t) => t.value === raw)) {
      return raw;
    }
    if (raw === "for_interview" || raw === "for_online_intro" || raw === "for_face_to_face_intro") {
      return "for_interview_intro";
    }
    if (raw === "done_intro") {
      return "for_requirements";
    }
    if (raw === "waiting_sco_schedule" || raw === "waiting_approval" || raw === "endorsed") {
      return "pending_approval";
    }
    if (PROGRESSIVE_STAGES.some((s) => s.value === raw)) {
      return raw;
    }
    return "for_interview_intro";
  };

  const initialStage = resolveInitialStage(applicant.status);
  const [selectedStage, setSelectedStage] = useState(initialStage);
  const [followUpDate, setFollowUpDate] = useState(
    applicant.followUpDate || new Date().toISOString().substring(0, 10),
  );
  const [recruitmentRemarks, setRecruitmentRemarks] = useState(
    applicant.recruitmentRemarks || "",
  );
  const [opsRemarks, setOpsRemarks] = useState(applicant.opsRemarks || "");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Terminal dropout states
  const isTerminalSelected = TERMINAL_STAGES.some((t) => t.value === selectedStage);
  const [reasons, setReasons] = useState<Array<{ id: string; reason: string }>>([]);
  const [selectedReasonId, setSelectedReasonId] = useState("");
  const [customReason, setCustomReason] = useState("");
  const [isLoadingReasons, setIsLoadingReasons] = useState(false);

  useEffect(() => {
    let mounted = true;

    if (!isTerminalSelected) {
      return;
    }

    const loadReasons = async () => {
      setIsLoadingReasons(true);
      try {
        const isBackoutType = selectedStage === "backout" || selectedStage === "did_not_report";
        const data = isBackoutType
          ? await fetchBackoutReasons()
          : await fetchRejectedReasons();

        if (mounted) {
          setReasons(data);
          if (data.length > 0) {
            setSelectedReasonId((prev) => (data.some((d) => d.id === prev) ? prev : data[0].id));
          }
          setIsLoadingReasons(false);
        }
      } catch {
        if (mounted) setIsLoadingReasons(false);
      }
    };

    void loadReasons();

    return () => {
      mounted = false;
    };
  }, [isTerminalSelected, selectedStage]);

  const isPending = updateMutation.isPending || failBackoutMutation.isPending;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (isTerminalSelected) {
      const matchedReason = reasons.find((r) => r.id === selectedReasonId)?.reason;
      const finalReason = customReason.trim() || matchedReason;

      if (!finalReason) {
        setErrorMessage("Please select or specify a reason for this terminal status.");
        return;
      }

      // Map status label for canonical failBackoutApplicant RPC
      let mappedStatus: "Backout" | "Rejected" = "Backout";
      if (selectedStage === "failed" || selectedStage === "rejected") {
        mappedStatus = "Rejected";
      }

      failBackoutMutation.mutate(
        {
          applicantId: applicant.id,
          reason: finalReason,
          reasonId: selectedReasonId || null,
          status: mappedStatus,
          vcode: applicant.vcode,
        },
        {
          onSuccess: () => {
            onSuccess?.();
            onClose();
          },
          onError: (err) => {
            setErrorMessage(err.message || "Failed to update terminal status.");
          },
        },
      );
      return;
    }

    // Standard progressive pipeline stage advance
    updateMutation.mutate(
      {
        applicantId: applicant.id,
        newStatus: selectedStage,
        followUpDate: followUpDate || null,
        recruitmentRemarks: recruitmentRemarks.trim() || null,
        opsRemarks: opsRemarks.trim() || null,
        vcode: applicant.vcode,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to advance pipeline stage.");
        },
      },
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isTerminalSelected ? "Mark Candidate Dropout / Backout" : "Update Pipeline Stage"}
      subtitle={`${applicant.vcode} • ${applicant.fullName}`}
      icon={isTerminalSelected ? UserMinus : RotateCcw}
      maxWidthClass="max-w-lg"
    >
      <form onSubmit={handleSubmit} className="space-y-4 text-xs">
        {errorMessage && (
          <div className="rounded-lg border border-border-default bg-surface-muted p-3 text-xs text-text-primary">
            {errorMessage}
          </div>
        )}

        <div>
          <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
            Select Pipeline Stage / Outcome *
          </label>
          <select
            value={selectedStage}
            onChange={(e) => setSelectedStage(e.target.value)}
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500"
          >
            {PROGRESSIVE_STAGES.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
            <optgroup label="Terminal Dropout / Backout">
              {TERMINAL_STAGES.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </optgroup>
          </select>
        </div>

        {isTerminalSelected ? (
          /* Terminal Backout/Dropout Section */
          <div className="space-y-4 rounded-xl border border-border-default bg-surface-muted/50 p-4">
            <div className="flex items-start gap-2.5">
              <AlertTriangle className="h-4 w-4 text-text-secondary shrink-0 mt-0.5" />
              <p className="text-xs text-text-secondary">
                Selecting a terminal dropout will release this candidate&apos;s plantilla slot back
                to <strong>open</strong> and decrement the store&apos;s occupied headcount.
              </p>
            </div>

            <div>
              <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
                Standard Reason *
              </label>
              {isLoadingReasons ? (
                <div className="flex items-center gap-2 py-2 text-xs text-text-muted">
                  <Loader2 className="h-4 w-4 animate-spin text-text-muted" />
                  <span>Loading reasons...</span>
                </div>
              ) : reasons.length > 0 ? (
                <select
                  value={selectedReasonId}
                  onChange={(e) => setSelectedReasonId(e.target.value)}
                  className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                >
                  {reasons.map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.reason}
                    </option>
                  ))}
                </select>
              ) : (
                <p className="text-xs text-text-muted italic">No standard reasons available.</p>
              )}
            </div>

            <div>
              <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
                Custom Reason / Additional Notes
              </label>
              <textarea
                rows={2}
                value={customReason}
                onChange={(e) => setCustomReason(e.target.value)}
                placeholder="Additional details or custom dropout reason..."
                className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              />
            </div>
          </div>
        ) : (
          /* Progressive Stage Details Section */
          <>
            <div>
              <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
                Follow-up / Action Date
              </label>
              <div className="relative">
                <input
                  type="date"
                  value={followUpDate}
                  onChange={(e) => setFollowUpDate(e.target.value)}
                  className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
                Recruitment Remarks
              </label>
              <textarea
                rows={2}
                value={recruitmentRemarks}
                onChange={(e) => setRecruitmentRemarks(e.target.value)}
                placeholder="e.g. Completed initial screening, scheduled for interview..."
                className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
                Ops Remarks
              </label>
              <textarea
                rows={2}
                value={opsRemarks}
                onChange={(e) => setOpsRemarks(e.target.value)}
                placeholder="Operational feedback or endorsement notes..."
                className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              />
            </div>
          </>
        )}

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 pt-4 border-t border-border-subtle">
          <button
            type="button"
            onClick={onClose}
            disabled={isPending}
            className="rounded-lg border border-border-default px-4 py-2 text-sm font-medium text-text-secondary hover:bg-surface-hover"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={isPending}
            className="inline-flex items-center gap-2 rounded-lg bg-brand-500 hover:bg-brand-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 transition"
          >
            {isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            {isTerminalSelected ? "Confirm Dropout" : "Save Stage"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
