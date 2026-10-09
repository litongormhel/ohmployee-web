"use client";

import { useState } from "react";
import { AlertCircle, ArrowRight, Minus, Plus, ShieldAlert, X } from "lucide-react";
import { useSubmitHeadcountAmendment, useVcodeQuotaDetails } from "@/lib/queries/quota";

export interface RequestHeadcountAdjustmentModalProps {
  isOpen: boolean;
  onClose: () => void;
  vcode: string;
  storeName?: string | null;
  positionTitle?: string | null;
  accountId?: string | null;
  storeId?: string | null;
  positionId?: string | null;
  initialQuota?: number | null;
  onSuccess?: () => void;
}

export function RequestHeadcountAdjustmentModal({
  isOpen,
  onClose,
  vcode,
  storeName,
  positionTitle,
  accountId,
  storeId,
  positionId,
  initialQuota,
  onSuccess,
}: RequestHeadcountAdjustmentModalProps) {
  const { data: quotaDetails, isLoading, isError, error } = useVcodeQuotaDetails(isOpen ? vcode : null);
  const amendmentMutation = useSubmitHeadcountAmendment();

  const currentQuota = quotaDetails?.currentQuota ?? initialQuota ?? 1;
  const occupied = quotaDetails?.occupied ?? 0;
  const hrProcessing = quotaDetails?.hrProcessing ?? 0;
  const pipeline = quotaDetails?.pipeline ?? 0;
  const commitments = occupied + hrProcessing + pipeline;
  const safetyFloor = quotaDetails?.safetyFloor ?? Math.max(1, commitments);

  const [userProposedQuota, setUserProposedQuota] = useState<number | null>(null);
  const proposedQuota = userProposedQuota ?? currentQuota;
  const [justification, setJustification] = useState("");
  const [submitError, setSubmitError] = useState<string | null>(null);

  if (!isOpen) return null;

  const delta = proposedQuota - currentQuota;
  const isFloorViolated = proposedQuota < safetyFloor;
  const isJustificationValid = justification.trim().length >= 5;
  const isChanged = delta !== 0;
  const isProposedValid = proposedQuota >= 1 && !isFloorViolated && isChanged;
  const canSubmit = isProposedValid && isJustificationValid && !amendmentMutation.isPending && !isLoading;

  const handleDecrement = () => {
    if (proposedQuota > safetyFloor && proposedQuota > 1) {
      setUserProposedQuota(proposedQuota - 1);
    }
  };

  const handleIncrement = () => {
    setUserProposedQuota(proposedQuota + 1);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;

    setSubmitError(null);
    amendmentMutation.mutate(
      {
        targetVcode: vcode,
        proposedQuota,
        justification: justification.trim(),
        currentQuota,
        accountId: quotaDetails?.accountId ?? accountId ?? null,
        storeId: quotaDetails?.storeId ?? storeId ?? null,
        positionId: quotaDetails?.positionId ?? positionId ?? null,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setSubmitError(err.message || "Failed to submit headcount amendment request.");
        },
      },
    );
  };

  const resolvedStoreName = quotaDetails?.storeName ?? storeName ?? "Store Allocation";
  const resolvedPosition = quotaDetails?.positionTitle ?? positionTitle ?? "Position Title";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/40 transition-opacity"
        onClick={amendmentMutation.isPending ? undefined : onClose}
        aria-hidden="true"
      />

      {/* Modal Dialog Card */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="amendment-quota-title"
        className="relative z-10 w-full max-w-lg rounded-lg border border-border-default bg-surface-base shadow-2xl transition-all"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border-default px-6 py-4">
          <div>
            <div className="flex items-center gap-2">
              <span className="inline-flex items-center rounded bg-blue-500/10 px-2 py-0.5 font-mono text-[11px] font-semibold text-blue-700 border border-blue-500/20">
                Ops Amendment
              </span>
              <h2 id="amendment-quota-title" className="text-base font-semibold text-text-primary">
                Request HC Adjustment
              </h2>
            </div>
            <p className="mt-1 text-xs text-text-secondary">
              Submit operational headcount quota amendment to Request Center
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={amendmentMutation.isPending}
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
              {/* Quota Transition & Delta Badge */}
              <div className="rounded-md border border-border-default bg-surface-base p-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="text-center">
                      <div className="text-[10px] uppercase font-semibold text-text-muted">Current</div>
                      <div className="text-xl font-bold font-mono text-text-primary">{currentQuota}</div>
                    </div>
                    <ArrowRight className="h-4 w-4 text-text-muted" />
                    <div className="text-center">
                      <div className="text-[10px] uppercase font-semibold text-text-muted">Proposed</div>
                      <div className="text-xl font-bold font-mono text-brand-600">{proposedQuota}</div>
                    </div>
                  </div>

                  {/* Delta Badge */}
                  <div>
                    {delta > 0 ? (
                      <span className="inline-flex items-center rounded-full bg-emerald-50 px-3 py-1 font-mono text-xs font-semibold text-emerald-700 border border-emerald-200">
                        +{delta} (Expansion)
                      </span>
                    ) : delta < 0 ? (
                      <span className="inline-flex items-center rounded-full bg-amber-50 px-3 py-1 font-mono text-xs font-semibold text-amber-700 border border-amber-200">
                        {delta} (Reduction)
                      </span>
                    ) : (
                      <span className="inline-flex items-center rounded-full bg-slate-50 px-3 py-1 font-mono text-xs font-medium text-slate-600 border border-slate-200">
                        No Change
                      </span>
                    )}
                  </div>
                </div>
              </div>

              {/* Live Commitments Safety Floor */}
              <div className="rounded-md border border-border-subtle bg-slate-50/70 p-3.5 space-y-2.5">
                <div className="flex items-center justify-between text-xs">
                  <span className="font-semibold text-text-primary uppercase tracking-wide text-[11px]">
                    Live Commitments Floor
                  </span>
                  <span className="font-mono font-semibold text-slate-800 bg-white border border-slate-200 rounded px-2 py-0.5 text-xs">
                    Safety Floor: {safetyFloor}
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
                  Floor represents active occupied staff ({occupied}) + HR processing ({hrProcessing}) + pipeline candidates ({pipeline}).
                  Proposed quota cannot be lower than <strong>{safetyFloor}</strong>.
                </p>
              </div>

              {/* Proposed Quota Stepper Input */}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <label htmlFor="proposed-quota-input" className="text-xs font-semibold text-text-primary">
                    Proposed Headcount Target
                  </label>
                  <span className="text-[11px] text-text-muted">
                    Safety Floor: <strong className="text-text-primary font-mono">{safetyFloor}</strong>
                  </span>
                </div>

                <div className="flex items-center gap-3">
                  <div className="flex items-center rounded-md border border-border-default bg-surface-base shadow-xs">
                    <button
                      type="button"
                      onClick={handleDecrement}
                      disabled={proposedQuota <= safetyFloor || proposedQuota <= 1 || amendmentMutation.isPending}
                      className="flex h-10 w-10 items-center justify-center text-text-secondary hover:bg-surface-hover hover:text-text-primary disabled:opacity-30 disabled:cursor-not-allowed transition-colors rounded-l-md"
                      title={proposedQuota <= safetyFloor ? `Cannot reduce below commitments floor (${safetyFloor})` : "Decrement"}
                      aria-label="Decrease proposed quota"
                    >
                      <Minus className="h-4 w-4" />
                    </button>
                    <input
                      id="proposed-quota-input"
                      type="number"
                      min={safetyFloor}
                      value={proposedQuota}
                      onChange={(e) => {
                        const val = parseInt(e.target.value, 10);
                        setUserProposedQuota(Number.isNaN(val) ? 0 : val);
                      }}
                      className="h-10 w-20 text-center font-mono text-base font-semibold text-text-primary outline-none border-x border-border-default bg-transparent"
                    />
                    <button
                      type="button"
                      onClick={handleIncrement}
                      disabled={amendmentMutation.isPending}
                      className="flex h-10 w-10 items-center justify-center text-text-secondary hover:bg-surface-hover hover:text-text-primary disabled:opacity-30 transition-colors rounded-r-md"
                      aria-label="Increase proposed quota"
                    >
                      <Plus className="h-4 w-4" />
                    </button>
                  </div>

                  <div className="text-xs text-text-muted leading-tight">
                    {delta === 0 ? (
                      <span className="text-amber-600 font-medium">
                        Change proposed headcount above or below current ({currentQuota}).
                      </span>
                    ) : delta > 0 ? (
                      <span className="text-emerald-700 font-medium">
                        Requesting addition of +{delta} slot{delta > 1 ? "s" : ""}.
                      </span>
                    ) : (
                      <span className="text-amber-700 font-medium">
                        Requesting reduction of {Math.abs(delta)} slot{Math.abs(delta) > 1 ? "s" : ""}.
                      </span>
                    )}
                  </div>
                </div>

                {/* Safety Floor Enforced Alert */}
                {isFloorViolated && (
                  <div className="flex items-start gap-2 rounded-md border border-red-200 bg-red-50 p-2.5 text-xs text-red-700">
                    <ShieldAlert className="h-4 w-4 shrink-0 text-red-600 mt-0.5" />
                    <div>
                      <strong className="font-semibold">Safety Floor Enforced: </strong>
                      Proposed target ({proposedQuota}) cannot be lower than active commitments floor of {safetyFloor}.
                    </div>
                  </div>
                )}

                {/* No Change Alert */}
                {delta === 0 && (
                  <p className="text-[11px] text-amber-600">
                    Proposed quota must differ from current quota ({currentQuota}).
                  </p>
                )}
              </div>

              {/* Operational Justification */}
              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <label htmlFor="amendment-justification" className="text-xs font-semibold text-text-primary">
                    Operational Justification <span className="text-red-500">*</span>
                  </label>
                  <span
                    className={`text-[11px] ${
                      justification.trim().length >= 5 ? "text-emerald-600" : "text-text-muted"
                    }`}
                  >
                    {justification.trim().length}/5 chars min
                  </span>
                </div>
                <textarea
                  id="amendment-justification"
                  rows={3}
                  value={justification}
                  onChange={(e) => setJustification(e.target.value)}
                  placeholder="Explain why this quota adjustment is required by Operations (e.g. Peak season volume expansion, store footprint reduction, etc.)..."
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
              disabled={amendmentMutation.isPending}
              className="rounded-md border border-border-default bg-surface-base px-4 py-2 text-xs font-medium text-text-secondary hover:bg-surface-hover hover:text-text-primary transition-colors disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!canSubmit}
              className="inline-flex items-center gap-1.5 rounded-md bg-brand-600 px-4 py-2 text-xs font-semibold text-white shadow-xs hover:bg-brand-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              {amendmentMutation.isPending ? "Submitting..." : "Submit Request"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
