"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, Loader2, UserMinus } from "lucide-react";
import {
  fetchBackoutReasons,
  fetchRejectedReasons,
  useFailBackoutApplicant,
} from "@/lib/queries/vacancy";
import { Modal } from "@/components/shared/Modal";

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
      isOpen={isOpen}
      applicant={applicant}
      initialType={initialType}
      onClose={onClose}
      onSuccess={onSuccess}
    />
  );
}

function FailBackoutModalContent({
  isOpen,
  applicant,
  initialType,
  onClose,
  onSuccess,
}: {
  isOpen: boolean;
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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Mark Candidate Dropout / Backout"
      subtitle={`${applicant.vcode} • ${applicant.fullName}`}
      icon={UserMinus}
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={mutation.isPending}
      isDirty={Boolean(customReason)}
    >
      <form onSubmit={handleSubmit} className="space-y-4 text-xs">
        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg p-3 text-xs text-danger-text font-medium">
            {errorMessage}
          </div>
        )}

        <div>
          <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
            Terminal Outcome
          </label>
          <div className="grid grid-cols-2 gap-3">
            <button
              type="button"
              onClick={() => setTerminalType("Backout")}
              className={`flex items-center justify-center gap-2 rounded-lg border py-2.5 text-xs font-semibold transition cursor-pointer ${
                terminalType === "Backout"
                  ? "border-brand-primary bg-surface-selected text-text-primary font-bold shadow-2xs"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              Candidate Backout
            </button>
            <button
              type="button"
              onClick={() => setTerminalType("Failed")}
              className={`flex items-center justify-center gap-2 rounded-lg border py-2.5 text-xs font-semibold transition cursor-pointer ${
                terminalType === "Failed"
                  ? "border-brand-primary bg-surface-selected text-text-primary font-bold shadow-2xs"
                  : "border-border-default bg-surface-base text-text-secondary hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              Failed / Rejected by Ops
            </button>
          </div>
        </div>

        <div>
          <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
            Standard Reason *
          </label>
          {isLoadingReasons ? (
            <div className="flex items-center gap-2 py-2 text-xs text-text-muted">
              <Loader2 className="h-4 w-4 animate-spin text-text-muted" />
              <span>Loading standard reasons...</span>
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
            <p className="text-xs text-text-muted italic">No standard reasons found.</p>
          )}
        </div>

        <div>
          <label className="block text-xs font-semibold text-text-secondary uppercase tracking-wider mb-1">
            Additional Details / Reason Notes
          </label>
          <textarea
            rows={2}
            value={customReason}
            onChange={(e) => setCustomReason(e.target.value)}
            placeholder="Provide specific notes regarding why candidate failed or backed out..."
            className="w-full rounded-lg border border-border-default bg-surface-base px-3 py-2 text-sm text-text-primary focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
        </div>

        <div className="rounded-lg border border-border-default bg-surface-muted p-3 flex items-start gap-2 text-xs text-text-secondary">
          <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5 text-text-muted" />
          <div className="leading-relaxed">
            <strong>Slot Recycling Notice:</strong> Archiving this candidate will immediately release their hold on this requisition. If no other active candidates remain, this vacancy will automatically cycle back into the <strong>Open</strong> tab for sourcing.
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 pt-4 border-t border-border-subtle">
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="rounded-lg border border-border-default px-4 py-2 text-sm font-medium text-text-secondary hover:bg-surface-hover"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={mutation.isPending}
            className="inline-flex items-center gap-2 rounded-lg bg-danger-text px-4 py-2 text-sm font-semibold text-white hover:opacity-90 disabled:opacity-50 cursor-pointer transition-opacity"
          >
            {mutation.isPending && (
              <Loader2 className="h-4 w-4 animate-spin" />
            )}
            Confirm Dropout
          </button>
        </div>
      </form>
    </Modal>
  );
}
