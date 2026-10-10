"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, Loader2, UserMinus, X } from "lucide-react";
import {
  fetchBackoutReasons,
  fetchRejectedReasons,
  useFailBackoutApplicant,
} from "@/lib/queries/vacancy";

export interface FailBackoutModalProps {
  isOpen: boolean;
  onClose: () => void;
  applicant: {
    id: string;
    fullName: string;
    status: string;
    vcode: string;
    positionTitle?: string | null;
  } | null;
  initialType?: "Backout" | "Failed";
  onSuccess?: () => void;
}

export function FailBackoutModal({
  isOpen,
  onClose,
  applicant,
  initialType = "Backout",
  onSuccess,
}: FailBackoutModalProps) {
  if (!isOpen || !applicant) return null;

  return (
    <FailBackoutModalContent
      applicant={applicant}
      initialType={initialType}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function FailBackoutModalContent({
  applicant,
  initialType,
  onClose,
  onSuccess,
}: {
  applicant: NonNullable<FailBackoutModalProps["applicant"]>;
  initialType: "Backout" | "Failed";
  onClose: () => void;
  onSuccess?: () => void;
}) {
  const mutation = useFailBackoutApplicant();

  const [terminalType, setTerminalType] = useState<"Backout" | "Failed">(initialType);
  const [reasons, setReasons] = useState<Array<{ id: string; reason: string }>>([]);
  const [selectedReasonId, setSelectedReasonId] = useState("");
  const [customReason, setCustomReason] = useState("");
  const [isLoadingReasons, setIsLoadingReasons] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;

    const loadReasons = async () => {
      setIsLoadingReasons(true);
      try {
        const data =
          terminalType === "Backout"
            ? await fetchBackoutReasons()
            : await fetchRejectedReasons();
        if (mounted) {
          setReasons(data);
          if (data.length > 0) {
            setSelectedReasonId(data[0].id);
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
  }, [terminalType]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    const matchedReason = reasons.find((r) => r.id === selectedReasonId)?.reason;
    const finalReason = customReason.trim() || matchedReason || "Candidate dropout / rejected";

    mutation.mutate(
      {
        applicantId: applicant.id,
        reason: finalReason,
        reasonId: selectedReasonId || null,
        status: terminalType === "Backout" ? "Backout" : "Rejected",
        vcode: applicant.vcode,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to process dropout.");
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
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-rose-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-rose-100 text-rose-700 border border-rose-200">
              <UserMinus className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">
                Mark Candidate Dropout / Backout
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
              Terminal Outcome
            </label>
            <div className="grid grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => setTerminalType("Backout")}
                className={`flex items-center justify-center gap-2 rounded-lg border py-2.5 text-xs font-semibold transition ${
                  terminalType === "Backout"
                    ? "border-amber-500 bg-amber-50 text-amber-800"
                    : "border-gray-200 bg-white text-gray-600 hover:bg-gray-50"
                }`}
              >
                Candidate Backout
              </button>
              <button
                type="button"
                onClick={() => setTerminalType("Failed")}
                className={`flex items-center justify-center gap-2 rounded-lg border py-2.5 text-xs font-semibold transition ${
                  terminalType === "Failed"
                    ? "border-rose-500 bg-rose-50 text-rose-800"
                    : "border-gray-200 bg-white text-gray-600 hover:bg-gray-50"
                }`}
              >
                Failed / Rejected by Ops
              </button>
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              Standard Reason *
            </label>
            {isLoadingReasons ? (
              <div className="flex items-center gap-2 py-2 text-xs text-gray-500">
                <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
                <span>Loading standard reasons...</span>
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
              <p className="text-xs text-gray-400 italic">No standard reasons found.</p>
            )}
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700 uppercase tracking-wider mb-1">
              Additional Details / Reason Notes
            </label>
            <textarea
              rows={2}
              value={customReason}
              onChange={(e) => setCustomReason(e.target.value)}
              placeholder="Provide specific notes regarding why candidate failed or backed out..."
              className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-rose-500 focus:outline-none focus:ring-1 focus:ring-rose-500"
            />
          </div>

          <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 flex items-start gap-2 text-xs text-amber-800">
            <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5 text-amber-600" />
            <div className="leading-relaxed">
              <strong>Slot Recycling Notice:</strong> Archiving this candidate will immediately release their hold on this requisition. If no other active candidates remain, this vacancy will automatically cycle back into the <strong>Open</strong> tab for sourcing.
            </div>
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-gray-100">
            <button
              type="button"
              onClick={onClose}
              disabled={mutation.isPending}
              className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={mutation.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-rose-600 px-4 py-2 text-sm font-semibold text-white hover:bg-rose-700 disabled:opacity-50"
            >
              {mutation.isPending && (
                <Loader2 className="h-4 w-4 animate-spin" />
              )}
              Confirm Dropout
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
