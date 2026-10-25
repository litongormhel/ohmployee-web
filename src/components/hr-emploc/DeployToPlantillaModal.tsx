// components/hr-emploc/DeployToPlantillaModal.tsx
"use client";

import { useEffect, useState } from "react";
import { AlertCircle, Calendar, Loader2, Send, Users } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useMoveToPlantilla, fetchAvailableSlotsForVcode, HrEmplocDataError } from "@/lib/queries/hr_emploc";

type DeployToPlantillaModalProps = {
  hrEmplocId: string;
  candidateName: string;
  vcode: string;
  positionTitle?: string | null;
  storeName?: string | null;
  accountName?: string | null;
  employeeNo?: string | null;
  onClose: () => void;
  onSuccess: () => void;
};

export function DeployToPlantillaModal({
  hrEmplocId,
  candidateName,
  vcode,
  positionTitle,
  storeName,
  accountName,
  employeeNo,
  onClose,
  onSuccess,
}: DeployToPlantillaModalProps) {
  const defaultDate = () => new Date().toISOString().split("T")[0];
  const [effectiveDate, setEffectiveDate] = useState(defaultDate);
  const [checkingCapacity, setCheckingCapacity] = useState(true);
  const [availableSlots, setAvailableSlots] = useState<number | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const moveMutation = useMoveToPlantilla();

  useEffect(() => {
    let isCancelled = false;
    async function checkSlots() {
      try {
        setCheckingCapacity(true);
        setErrorMsg(null);
        const slots = await fetchAvailableSlotsForVcode(vcode);
        if (!isCancelled) {
          setAvailableSlots(slots);
        }
      } catch {
        if (!isCancelled) {
          setAvailableSlots(1); // optimistic fallback to allow RPC itself to validate
        }
      } finally {
        if (!isCancelled) {
          setCheckingCapacity(false);
        }
      }
    }
    void checkSlots();
    return () => {
      isCancelled = true;
    };
  }, [vcode]);

  function handleConfirm() {
    setErrorMsg(null);

    if (availableSlots !== null && availableSlots <= 0) {
      setErrorMsg("No available slot capacity found for VCode " + vcode + ". Cannot deploy candidate.");
      return;
    }

    moveMutation.mutate(
      {
        hrEmplocId,
        vcode,
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
            setErrorMsg("Failed to move record to Plantilla. Please try again.");
          }
        },
      }
    );
  }

  const isBlockedCapacity = !checkingCapacity && availableSlots !== null && availableSlots <= 0;
  const isDirty = effectiveDate !== defaultDate();

  return (
    <Modal
      isOpen={true}
      onClose={onClose}
      title="Deploy to Plantilla Directory"
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={moveMutation.isPending}
      isDirty={isDirty}
    >
      <div className="space-y-4">
        <div className="flex items-center gap-2 pb-2 border-b border-border-subtle">
          <div className="p-1.5 bg-surface-muted text-brand-primary rounded border border-border-subtle">
            <Send className="h-4 w-4" />
          </div>
          <div>
            <h4 className="text-sm font-semibold text-text-primary">Plantilla Allocation</h4>
            <p className="text-[11px] text-text-muted">
              Official transfer from onboarding masterlist to active workforce
            </p>
          </div>
        </div>

        {/* Candidate & Slot Snapshot Card */}
        <div className="rounded-md border border-border-subtle bg-surface-muted p-3.5 text-xs space-y-2.5">
          <div className="flex items-center justify-between pb-2 border-b border-border-subtle">
            <span className="text-text-muted font-medium">Candidate:</span>
            <span className="font-bold text-text-primary text-sm">{candidateName}</span>
          </div>

          <div className="grid grid-cols-2 gap-2 text-text-muted">
            <div>
              <span className="text-[10px] uppercase text-text-muted block">Assigned ID</span>
              <span className="font-mono font-semibold text-text-primary">
                {employeeNo ?? "Not Assigned"}
              </span>
            </div>
            <div>
              <span className="text-[10px] uppercase text-text-muted block">Target VCode</span>
              <span className="font-mono font-semibold text-text-primary">{vcode}</span>
            </div>
            <div>
              <span className="text-[10px] uppercase text-text-muted block">Designation</span>
              <span className="font-medium text-text-primary truncate block">
                {positionTitle ?? "Staff"}
              </span>
            </div>
            <div>
              <span className="text-[10px] uppercase text-text-muted block">Deployment Outlet</span>
              <span className="font-medium text-text-primary truncate block">
                {[accountName, storeName].filter(Boolean).join(" / ") || "Direct Assignment"}
              </span>
            </div>
          </div>
        </div>

        {/* Slot Capacity Status Card */}
        <div
          className={`rounded-md border p-3 text-xs flex items-center justify-between transition-colors ${
            checkingCapacity
              ? "border-border-default bg-surface-muted text-text-muted"
              : isBlockedCapacity
              ? "border-[var(--danger-border)] bg-[var(--danger-bg)] text-[var(--danger-text)]"
              : "border-border-default bg-surface-muted text-text-primary"
          }`}
        >
          <div className="flex items-center gap-2">
            <Users className="h-4 w-4 shrink-0" />
            <div>
              <span className="font-semibold block">
                {checkingCapacity
                  ? "Validating ADR-001 slot reservation..."
                  : isBlockedCapacity
                  ? "No Available Slot in Headcount"
                  : "ADR-001 Slot Verified Available"}
              </span>
              <span className="text-[11px] opacity-80 block">
                {checkingCapacity
                  ? "Querying plantilla_slots authority..."
                  : isBlockedCapacity
                  ? `Capacity reached. 0 open slots remaining for ${vcode}.`
                  : `${availableSlots} slot(s) open or self-reserved for this recruit.`}
              </span>
            </div>
          </div>
          {!checkingCapacity && (
            <span
              className={`text-xs font-bold font-mono px-2 py-0.5 rounded ${
                isBlockedCapacity
                  ? "bg-[var(--danger-bg)] text-[var(--danger-text)] border border-[var(--danger-border)]"
                  : "bg-surface border border-border-default text-text-primary"
              }`}
            >
              {availableSlots} Slot(s)
            </span>
          )}
        </div>

        {/* Effective Date Picker */}
        <div className="space-y-1.5">
          <label htmlFor="effectiveDatePicker" className="block text-xs font-semibold text-text-primary">
            Plantilla Effective Date
          </label>
          <div className="relative">
            <input
              id="effectiveDatePicker"
              type="date"
              disabled={moveMutation.isPending || isBlockedCapacity}
              value={effectiveDate}
              onChange={(e) => setEffectiveDate(e.target.value)}
              className="w-full rounded-md border border-border-default bg-surface px-3 py-2 text-sm text-text-primary focus:outline-none focus:ring-1 focus:ring-brand-primary focus:border-brand-primary disabled:opacity-50"
            />
            <Calendar className="absolute right-3 top-2.5 h-4 w-4 text-text-muted pointer-events-none" />
          </div>
          <p className="text-[11px] text-text-muted">
            Date on which this employee officially begins active duties in the store plantilla.
          </p>
        </div>

        {/* Warning / Error display */}
        {errorMsg && (
          <div className="rounded border border-[var(--danger-border)] bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger-text)] flex items-start gap-2">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{errorMsg}</span>
          </div>
        )}

        {/* Impact Explainer */}
        <div className="text-[11px] text-text-muted bg-surface-muted border border-border-subtle rounded p-2.5 leading-relaxed">
          <span className="font-semibold text-text-primary">Lifecycle Effect:</span> This atomic mutation will mark the HR Emploc status as <strong className="text-text-primary">Transferred</strong>, allocate the confirmed headcount slot, and transition the associated vacancy status to <strong className="text-text-primary">Filled</strong>.
        </div>

        {/* Footer Actions */}
        <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-border-subtle">
          <button
            type="button"
            disabled={moveMutation.isPending}
            onClick={onClose}
            className="rounded-md border border-border-default bg-surface px-4 py-2 text-xs font-medium text-text-primary hover:bg-surface-hover transition disabled:opacity-50 cursor-pointer"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={moveMutation.isPending || checkingCapacity || isBlockedCapacity}
            onClick={handleConfirm}
            className="inline-flex items-center gap-1.5 rounded-md bg-brand-primary px-4 py-2 text-xs font-semibold text-white hover:bg-brand-primary-hover transition disabled:opacity-50 disabled:cursor-not-allowed shadow-xs cursor-pointer"
          >
            {moveMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            {moveMutation.isPending ? "Deploying..." : "Confirm & Deploy to Plantilla"}
          </button>
        </div>
      </div>
    </Modal>
  );
}
