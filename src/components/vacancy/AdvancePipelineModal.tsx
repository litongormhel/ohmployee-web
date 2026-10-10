"use client";

import { useState } from "react";
import { Loader2, RotateCcw, X } from "lucide-react";
import { useUpdateApplicantPipeline } from "@/lib/queries/vacancy";

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

const STAGE_OPTIONS = [
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

  const [selectedStage, setSelectedStage] = useState(
    applicant.status.toLowerCase().replace(/\s+/g, "_") || "for_interview",
  );
  const [followUpDate, setFollowUpDate] = useState(
    applicant.followUpDate ||
      new Date().toISOString().substring(0, 10),
  );
  const [recruitmentRemarks, setRecruitmentRemarks] = useState(
    applicant.recruitmentRemarks || "",
  );
  const [opsRemarks, setOpsRemarks] = useState(applicant.opsRemarks || "");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

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
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-gray-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-indigo-50 text-indigo-600 border border-indigo-100">
              <RotateCcw className="h-4.5 w-4.5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">
                Update Pipeline Stage
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
              Select Pipeline Stage *
            </label>
            <select
              value={selectedStage}
              onChange={(e) => setSelectedStage(e.target.value)}
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              {STAGE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </select>
          </div>

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

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-gray-100">
            <button
              type="button"
              onClick={onClose}
              disabled={updateMutation.isPending}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={updateMutation.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-700 disabled:opacity-50"
            >
              {updateMutation.isPending && (
                <Loader2 className="h-4 w-4 animate-spin" />
              )}
              Save Stage
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
