"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, Loader2, RotateCcw, UserMinus, X } from "lucide-react";
import {
  fetchBackoutReasons,
  fetchRejectedReasons,
  useFailBackoutApplicant,
  useUpdateApplicantPipeline,
} from "@/lib/queries/vacancy";

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
  { value: "for_interview", label: "For Interview" },
  { value: "for_online_intro", label: "For Online Intro" },
  { value: "for_face_to_face_intro", label: "For Face-to-Face Intro" },
  { value: "done_intro", label: "Done Intro" },
  { value: "for_requirements", label: "For Requirements" },
  { value: "for_medical", label: "For Medical" },
  { value: "waiting_sco_schedule", label: "Waiting SCO Schedule" },
  { value: "waiting_approval", label: "Waiting Approval" },
  { value: "endorsed", label: "Endorsed to Ops" },
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
      applicant={applicant}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function AdvancePipelineModalContent({
  applicant,
  onClose,
  onSuccess,
}: {
  applicant: NonNullable<AdvancePipelineModalProps["applicant"]>;
  onClose: () => void;
  onSuccess?: () => void;
}) {
  const updateMutation = useUpdateApplicantPipeline();
  const failBackoutMutation = useFailBackoutApplicant();

  const initialStatusNorm = applicant.status.toLowerCase().replace(/\s+/g, "_");
  const isInitialTerminal = TERMINAL_STAGES.some((t) => t.value === initialStatusNorm);

  const [selectedStage, setSelectedStage] = useState(
    isInitialTerminal ? initialStatusNorm : initialStatusNorm || "for_interview",
  );
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
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div
          className={`flex items-center justify-between border-b border-gray-100 px-6 py-4 ${
            isTerminalSelected ? "bg-rose-50/70" : "bg-gray-50/70"
          }`}
        >
          <div className="flex items-center gap-3">
            <div
              className={`flex h-9 w-9 items-center justify-center rounded-lg border ${
                isTerminalSelected
                  ? "bg-rose-100 text-rose-700 border-rose-200"
                  : "bg-indigo-50 text-indigo-600 border-indigo-100"
              }`}
            >
              {isTerminalSelected ? (
                <UserMinus className="h-5 w-5" />
              ) : (
                <RotateCcw className="h-4.5 w-4.5" />
              )}
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">
                {isTerminalSelected ? "Mark Candidate Dropout / Backout" : "Update Pipeline Stage"}
              </h2>
              <p className="text-xs text-gray-500 font-mono">
                {applicant.vcode} &bull; {applicant.fullName}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-4">
          {errorMessage && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-700">
              {errorMessage}
            </div>
          )}

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              Select Pipeline Stage / Outcome *
            </label>
            <select
              value={selectedStage}
              onChange={(e) => setSelectedStage(e.target.value)}
              className={`w-full rounded-lg border bg-white px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-1 ${
                isTerminalSelected
                  ? "border-rose-300 focus:border-rose-500 focus:ring-rose-500"
                  : "border-gray-300 focus:border-indigo-500 focus:ring-indigo-500"
              }`}
            >
              <optgroup label="Progressive Pipeline Stages">
                {PROGRESSIVE_STAGES.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </optgroup>
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
            <div className="space-y-4 rounded-xl border border-rose-200/80 bg-rose-50/40 p-4">
              <div className="flex items-start gap-2.5">
                <AlertTriangle className="h-4 w-4 text-rose-600 shrink-0 mt-0.5" />
                <p className="text-xs text-rose-700">
                  Selecting a terminal dropout will release this candidate&apos;s plantilla slot back
                  to <strong>open</strong> and decrement the store&apos;s occupied headcount.
                </p>
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                  Standard Reason *
                </label>
                {isLoadingReasons ? (
                  <div className="flex items-center gap-2 py-2 text-xs text-gray-500">
                    <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
                    <span>Loading reasons...</span>
                  </div>
                ) : reasons.length > 0 ? (
                  <select
                    value={selectedReasonId}
                    onChange={(e) => setSelectedReasonId(e.target.value)}
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-rose-500 focus:outline-none focus:ring-1 focus:ring-rose-500"
                  >
                    {reasons.map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.reason}
                      </option>
                    ))}
                  </select>
                ) : (
                  <p className="text-xs text-gray-400 italic">No standard reasons available.</p>
                )}
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                  Custom Reason / Additional Notes
                </label>
                <textarea
                  rows={2}
                  value={customReason}
                  onChange={(e) => setCustomReason(e.target.value)}
                  placeholder="Additional details or custom dropout reason..."
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-rose-500 focus:outline-none focus:ring-1 focus:ring-rose-500"
                />
              </div>
            </div>
          ) : (
            /* Progressive Stage Details Section */
            <>
              <div>
                <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                  Follow-up / Action Date
                </label>
                <div className="relative">
                  <input
                    type="date"
                    value={followUpDate}
                    onChange={(e) => setFollowUpDate(e.target.value)}
                    className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                  Recruitment Remarks
                </label>
                <textarea
                  rows={2}
                  value={recruitmentRemarks}
                  onChange={(e) => setRecruitmentRemarks(e.target.value)}
                  placeholder="e.g. Completed initial screening, scheduled for interview..."
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
                  Ops Remarks
                </label>
                <textarea
                  rows={2}
                  value={opsRemarks}
                  onChange={(e) => setOpsRemarks(e.target.value)}
                  placeholder="Operational feedback or endorsement notes..."
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>
            </>
          )}

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-gray-100">
            <button
              type="button"
              onClick={onClose}
              disabled={isPending}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isPending}
              className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 transition ${
                isTerminalSelected
                  ? "bg-rose-600 hover:bg-rose-700"
                  : "bg-indigo-600 hover:bg-indigo-700"
              }`}
            >
              {isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              {isTerminalSelected ? "Confirm Dropout" : "Save Stage"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
