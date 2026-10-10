// components/hr-emploc/DeployToPlantillaModal.tsx
"use client";

import { useEffect, useState } from "react";
import { AlertCircle, Calendar, Loader2, Send, Users, X } from "lucide-react";
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
  const [effectiveDate, setEffectiveDate] = useState(() => {
    return new Date().toISOString().split("T")[0];
  });
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

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/40 backdrop-blur-xs"
        onClick={moveMutation.isPending ? undefined : onClose}
      />

      {/* Modal Card */}
      <div className="relative z-10 w-full max-w-lg bg-white rounded-lg border border-gray-200 shadow-xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-5 py-3.5 bg-emerald-50/40">
          <div className="flex items-center gap-2">
            <div className="p-1.5 bg-emerald-100 text-emerald-700 rounded">
              <Send className="h-4 w-4" />
            </div>
            <div>
              <h2 className="text-sm font-semibold text-gray-900">Deploy to Plantilla Directory</h2>
              <p className="text-[11px] text-gray-500">
                Official transfer from onboarding masterlist to active workforce
              </p>
            </div>
          </div>
          <button
            aria-label="Close"
            className="inline-flex h-7 w-7 items-center justify-center rounded border border-gray-200 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition disabled:opacity-40"
            disabled={moveMutation.isPending}
            onClick={onClose}
            type="button"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Content Body */}
        <div className="p-5 space-y-4">
          {/* Candidate & Slot Snapshot Card */}
          <div className="rounded-md border border-gray-100 bg-gray-50/70 p-3.5 text-xs space-y-2.5">
            <div className="flex items-center justify-between pb-2 border-b border-gray-200/60">
              <span className="text-gray-500 font-medium">Candidate:</span>
              <span className="font-bold text-gray-900 text-sm">{candidateName}</span>
            </div>

            <div className="grid grid-cols-2 gap-2 text-gray-600">
              <div>
                <span className="text-[10px] uppercase text-gray-400 block">Assigned ID</span>
                <span className="font-mono font-semibold text-emerald-700">
                  {employeeNo ?? "Not Assigned"}
                </span>
              </div>
              <div>
                <span className="text-[10px] uppercase text-gray-400 block">Target VCode</span>
                <span className="font-mono font-semibold text-gray-800">{vcode}</span>
              </div>
              <div>
                <span className="text-[10px] uppercase text-gray-400 block">Designation</span>
                <span className="font-medium text-gray-800 truncate block">
                  {positionTitle ?? "Staff"}
                </span>
              </div>
              <div>
                <span className="text-[10px] uppercase text-gray-400 block">Deployment Outlet</span>
                <span className="font-medium text-gray-800 truncate block">
                  {[accountName, storeName].filter(Boolean).join(" / ") || "Direct Assignment"}
                </span>
              </div>
            </div>
          </div>

          {/* Slot Capacity Status Card */}
          <div
            className={`rounded-md border p-3 text-xs flex items-center justify-between transition-colors ${
              checkingCapacity
                ? "border-gray-200 bg-gray-50 text-gray-600"
                : isBlockedCapacity
                ? "border-red-200 bg-red-50 text-red-800"
                : "border-emerald-200 bg-emerald-50/60 text-emerald-800"
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
                  isBlockedCapacity ? "bg-red-200 text-red-900" : "bg-emerald-200 text-emerald-900"
                }`}
              >
                {availableSlots} Slot(s)
              </span>
            )}
          </div>

          {/* Effective Date Picker */}
          <div className="space-y-1.5">
            <label htmlFor="effectiveDatePicker" className="block text-xs font-semibold text-gray-700">
              Plantilla Effective Date
            </label>
            <div className="relative">
              <input
                id="effectiveDatePicker"
                type="date"
                disabled={moveMutation.isPending || isBlockedCapacity}
                value={effectiveDate}
                onChange={(e) => setEffectiveDate(e.target.value)}
                className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500 disabled:bg-gray-100"
              />
              <Calendar className="absolute right-3 top-2.5 h-4 w-4 text-gray-400 pointer-events-none" />
            </div>
            <p className="text-[11px] text-gray-400">
              Date on which this employee officially begins active duties in the store plantilla.
            </p>
          </div>

          {/* Warning / Error display */}
          {errorMsg && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-xs text-red-800 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-red-600" />
              <span>{errorMsg}</span>
            </div>
          )}

          {/* Impact Explainer */}
          <div className="text-[11px] text-gray-500 bg-slate-50 border border-slate-200/60 rounded p-2.5 leading-relaxed">
            <span className="font-semibold text-gray-700">Lifecycle Effect:</span> This atomic mutation will mark the HR Emploc status as <strong className="text-gray-800">Transferred</strong>, allocate the confirmed headcount slot, and transition the associated vacancy status to <strong className="text-gray-800">Filled</strong>.
          </div>

          {/* Footer Actions */}
          <div className="flex items-center justify-end gap-2.5 pt-2 border-t border-gray-100">
            <button
              type="button"
              disabled={moveMutation.isPending}
              onClick={onClose}
              className="rounded-md border border-gray-200 bg-white px-4 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50 transition disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={moveMutation.isPending || checkingCapacity || isBlockedCapacity}
              onClick={handleConfirm}
              className="inline-flex items-center gap-1.5 rounded-md bg-emerald-700 px-4 py-2 text-xs font-semibold text-white hover:bg-emerald-800 transition disabled:opacity-50 disabled:cursor-not-allowed shadow-xs"
            >
              {moveMutation.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              {moveMutation.isPending ? "Deploying..." : "Confirm & Deploy to Plantilla"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
