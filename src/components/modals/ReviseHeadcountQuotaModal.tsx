"use client";

import { useState } from "react";
import { AlertCircle, Minus, Plus, ShieldAlert, X } from "lucide-react";
import { useReviseHeadcountQuota, useVcodeQuotaDetails } from "@/lib/queries/quota";

export interface ReviseHeadcountQuotaModalProps {
  isOpen: boolean;
  onClose: () => void;
  vcode: string;
  storeName?: string | null;
  positionTitle?: string | null;
  initialQuota?: number | null;
  onSuccess?: () => void;
}

export function ReviseHeadcountQuotaModal({
  isOpen,
  onClose,
  vcode,
  storeName,
  positionTitle,
  initialQuota,
  onSuccess,
}: ReviseHeadcountQuotaModalProps) {
  const { data: quotaDetails, isLoading, isError, error } = useVcodeQuotaDetails(isOpen ? vcode : null);
  const reviseMutation = useReviseHeadcountQuota();

  const currentQuota = quotaDetails?.currentQuota ?? initialQuota ?? 1;
  const occupied = quotaDetails?.occupied ?? 0;
  const hrProcessing = quotaDetails?.hrProcessing ?? 0;
  const pipeline = quotaDetails?.pipeline ?? 0;
  const commitments = occupied + hrProcessing + pipeline;
  const safetyFloor = quotaDetails?.safetyFloor ?? Math.max(1, commitments);

  const [userTargetQuota, setUserTargetQuota] = useState<number | null>(null);
  const targetQuota = userTargetQuota ?? currentQuota;
  const [reason, setReason] = useState("");
  const [submitError, setSubmitError] = useState<string | null>(null);

  if (!isOpen) return null;

  const isFloorViolated = targetQuota < safetyFloor;
  const isReasonValid = reason.trim().length >= 5;
  const isTargetValid = targetQuota >= 1 && !isFloorViolated;
  const canSubmit = isTargetValid && isReasonValid && !reviseMutation.isPending && !isLoading;

  const handleDecrement = () => {
    if (targetQuota > safetyFloor && targetQuota > 1) {
      setUserTargetQuota(targetQuota - 1);
    }
  };

  const handleIncrement = () => {
    setUserTargetQuota(targetQuota + 1);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;

    setSubmitError(null);
    reviseMutation.mutate(
      {
        vcode,
        newQuota: targetQuota,
        reason: reason.trim(),
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setSubmitError(err.message || "Failed to revise headcount quota.");
        },
      },
    );
  };

  const resolvedStoreName = quotaDetails?.storeName ?? storeName ?? "Store Allocation";
  const resolvedPosition = quotaDetails?.positionTitle ?? positionTitle ?? "Position Title";
  const delta = targetQuota - currentQuota;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/40 transition-opacity"
        onClick={reviseMutation.isPending ? undefined : onClose}
        aria-hidden="true"
      />

      {/* Modal Dialog Card */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="revise-quota-title"
        className="relative z-10 w-full max-w-lg rounded-lg border border-border-default bg-surface-base shadow-2xl transition-all"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-default px-6 py-4">
          <div>
            <div className="flex items-center gap-2">
              <span className="inline-flex items-center rounded bg-amber-500/10 px-2 py-0.5 font-mono text-[11px] font-semibold text-amber-700 border border-amber-500/20">
                Direct Override
              </span>
              <h2 id="revise-quota-title" className="text-base font-semibold text-text-primary">
                Adjust Headcount Quota
              </h2>
            </div>
            <p className="mt-1 text-xs text-text-secondary">
              Data Team override via <code className="font-mono text-[11px] font-medium text-text-primary">revise_vcode_headcount_quota</code>
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={reviseMutation.isPending}
            className="rounded p-1 text-text-muted hover:bg-surface-hover hover:text-text-primary transition-colors disabled:opacity-50"
            aria-label="Close dialog"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Content Body */}
        <form onSubmit={handleSubmit} className="px-6 py-5 space-y-5">
          {/* Target Metadata Banner */}
          <div className="rounded-md border border-border-default bg-surface-muted p-3.5 space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-text-secondary">Position & Store</span>
              <span className="font-mono text-xs font-semibold text-text-primary bg-surface-base border border-border-default rounded px-2 py-0.5">
                {vcode}
              </span>
            </div>
            <div className="text-sm font-semibold text-text-primary">
              {resolvedPosition}
            </div>
            <div className="text-xs text-text-secondary">
              {resolvedStoreName}
            </div>
          </div>

          {isLoading ? (
            <div className="py-6 space-y-3 animate-pulse">
              <div className="h-4 bg-surface-muted rounded w-3/4" />
              <div className="h-16 bg-surface-muted rounded" />
              <div className="h-10 bg-surface-muted rounded" />
            </div>
          ) : isError ? (
            <div className="flex items-center gap-2 rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
              <AlertCircle className="h-4 w-4 shrink-0 text-red-600" />
              <span>Failed to load live commitments: {error?.message}</span>
            </div>
          ) : (
            <>
              {/* Safety Floor Breakdown Grid */}
              <div className="rounded-md border border-border-subtle bg-slate-50/70 p-3.5 space-y-2.5">
                <div className="flex items-center justify-between text-xs">
                  <span className="font-semibold text-text-primary uppercase tracking-wide text-[11px]">
                    Safety Floor Breakdown
                  </span>
                  <span className="font-mono font-semibold text-slate-800 bg-white border border-slate-200 rounded px-2 py-0.5 text-xs">
                    Floor: {safetyFloor} slot{safetyFloor !== 1 ? "s" : ""}
                  </span>
                </div>

                <div className="grid grid-cols-3 gap-2 text-center">
                  <div className="rounded border border-border-subtle bg-white p-2">
                    <div className="text-[10px] uppercase font-semibold text-text-muted">Occupied</div>
                    <div className="text-base font-bold text-text-primary font-mono">{occupied}</div>
                  </div>
                  <div className="rounded border border-border-subtle bg-white p-2">
                    <div className="text-[10px] uppercase font-semibold text-text-muted">HR Processing</div>
                    <div className="text-base font-bold text-amber-700 font-mono">{hrProcessing}</div>
                  </div>
                  <div className="rounded border border-border-subtle bg-white p-2">
                    <div className="text-[10px] uppercase font-semibold text-text-muted">Pipeline</div>
                    <div className="text-base font-bold text-blue-700 font-mono">{pipeline}</div>
                  </div>
                </div>

                <p className="text-[11px] text-text-muted leading-tight">
                  <span className="font-semibold text-text-secondary">Safety Floor: </span>
                  max(1, Occupied ({occupied}) + HR Processing ({hrProcessing}) + Pipeline ({pipeline})) = <strong>{safetyFloor}</strong>.
                  Target quota cannot be reduced below active commitments.
                </p>
              </div>

              {/* Target Quota Input with Steppers */}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <label htmlFor="target-quota-input" className="text-xs font-semibold text-text-primary">
                    Target Headcount Quota
                  </label>
                  <div className="text-xs text-text-secondary">
                    Current Quota: <span className="font-mono font-semibold text-text-primary">{currentQuota}</span>
                    {delta !== 0 && (
                      <span
                        className={`ml-2 font-mono font-medium ${
                          delta > 0 ? "text-emerald-700" : "text-amber-700"
                        }`}
                      >
                        ({delta > 0 ? `+${delta}` : delta})
                      </span>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <div className="flex items-center rounded-md border border-border-default bg-surface-base shadow-xs">
                    <button
                      type="button"
                      onClick={handleDecrement}
                      disabled={targetQuota <= safetyFloor || targetQuota <= 1 || reviseMutation.isPending}
                      className="flex h-10 w-10 items-center justify-center text-text-secondary hover:bg-surface-hover hover:text-text-primary disabled:opacity-30 disabled:cursor-not-allowed transition-colors rounded-l-md"
                      title={targetQuota <= safetyFloor ? `Cannot reduce below safety floor (${safetyFloor})` : "Decrement"}
                      aria-label="Decrease target quota"
                    >
                      <Minus className="h-4 w-4" />
                    </button>
                    <input
                      id="target-quota-input"
                      type="number"
                      min={safetyFloor}
                      value={targetQuota}
                      onChange={(e) => {
                        const val = parseInt(e.target.value, 10);
                        setUserTargetQuota(Number.isNaN(val) ? 0 : val);
                      }}
                      className="h-10 w-20 text-center font-mono text-base font-semibold text-text-primary outline-none border-x border-border-default bg-transparent"
                    />
                    <button
                      type="button"
                      onClick={handleIncrement}
                      disabled={reviseMutation.isPending}
                      className="flex h-10 w-10 items-center justify-center text-text-secondary hover:bg-surface-hover hover:text-text-primary disabled:opacity-30 transition-colors rounded-r-md"
                      aria-label="Increase target quota"
                    >
                      <Plus className="h-4 w-4" />
                    </button>
                  </div>

                  <div className="text-xs text-text-muted leading-tight">
                    {delta > 0 ? (
                      <span className="text-emerald-700 font-medium">
                        Expansion of {delta} slot{delta > 1 ? "s" : ""}. New open slots will be initialized.
                      </span>
                    ) : delta < 0 ? (
                      <span className="text-amber-700 font-medium">
                        Reduction of {Math.abs(delta)} open slot{Math.abs(delta) > 1 ? "s" : ""}.
                      </span>
                    ) : (
                      <span>No change in quota.</span>
                    )}
                  </div>
                </div>

                {/* Safety Floor Violation Warning */}
                {isFloorViolated && (
                  <div className="flex items-start gap-2 rounded-md border border-red-200 bg-red-50 p-2.5 text-xs text-red-700">
                    <ShieldAlert className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
                    <div>
                      <strong className="font-semibold">Safety Floor Enforced: </strong>
                      Target quota ({targetQuota}) cannot be lower than the safety floor of {safetyFloor}.
                      Active occupied employees and candidates in process cannot be orphaned.
                    </div>
                  </div>
                )}
              </div>

              {/* Revision Justification */}
              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <label htmlFor="revision-reason" className="text-xs font-semibold text-text-primary">
                    Reason for Quota Revision <span className="text-red-500">*</span>
                  </label>
                  <span
                    className={`text-[11px] ${
                      reason.trim().length >= 5 ? "text-emerald-600" : "text-text-muted"
                    }`}
                  >
                    {reason.trim().length}/5 chars min
                  </span>
                </div>
                <textarea
                  id="revision-reason"
                  rows={3}
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="Provide audit reason for revising this vacancy target quota (e.g. Approved plantilla expansion by Ops Director)..."
                  className="w-full rounded-md border border-border-default bg-surface-base p-2.5 text-xs text-text-primary outline-none placeholder:text-text-muted focus:border-brand-500 focus:ring-1 focus:ring-brand-500 transition-colors"
                />
              </div>

              {/* Submission Error Banner */}
              {submitError && (
                <div className="flex items-center gap-2 rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
                  <AlertCircle className="h-4 w-4 shrink-0 text-red-600" />
                  <span>{submitError}</span>
                </div>
              )}
            </>
          )}

          {/* Footer Actions */}
          <div className="flex items-center justify-end gap-3 border-t border-border-default pt-4">
            <button
              type="button"
              onClick={onClose}
              disabled={reviseMutation.isPending}
              className="rounded-md border border-border-default bg-surface-base px-4 py-2 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!canSubmit}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              {reviseMutation.isPending ? "Applying..." : "Confirm Revision"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
