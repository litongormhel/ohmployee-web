"use client";

import { useState } from "react";
import { AlertCircle, ArrowRight, Minus, Plus, ShieldAlert } from "lucide-react";
import { useSubmitHeadcountAmendment, useVcodeQuotaDetails } from "@/lib/queries/quota";
import { Modal } from "@/components/shared/Modal";

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
  const isDirty = Boolean(userProposedQuota !== null || justification.trim().length > 0);

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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={
        <span className="flex items-center gap-2">
          <span className="inline-flex items-center rounded bg-[var(--surface-sunken)] px-2 py-0.5 font-mono text-[11px] font-semibold text-[var(--foreground)] border border-[var(--border-subtle)]">
            Ops Amendment
          </span>
          <span>Request HC Adjustment</span>
        </span>
      }
      subtitle="Submit operational headcount quota amendment to Request Center"
      disableBackdropClick={amendmentMutation.isPending}
      isSubmitting={amendmentMutation.isPending}
      isDirty={isDirty}
    >
      <form onSubmit={handleSubmit} className="p-6 space-y-5">
        {/* Target Metadata Banner */}
        <div className="rounded-md border border-[var(--border-subtle)] bg-[var(--surface-sunken)] p-3.5 space-y-1.5">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-[var(--text-muted)]">Position & Store</span>
            <span className="font-mono text-xs font-semibold text-[var(--foreground)] bg-[var(--surface-base)] border border-[var(--border-subtle)] rounded px-2 py-0.5">
              {vcode}
            </span>
          </div>
          <div className="text-sm font-semibold text-[var(--foreground)]">
            {resolvedPosition}
          </div>
          <div className="text-xs text-[var(--text-muted)]">
            {resolvedStoreName}
          </div>
        </div>

        {isLoading ? (
          <div className="py-6 space-y-3 animate-pulse">
            <div className="h-4 bg-[var(--surface-sunken)] rounded w-3/4" />
            <div className="h-16 bg-[var(--surface-sunken)] rounded" />
            <div className="h-10 bg-[var(--surface-sunken)] rounded" />
          </div>
        ) : isError ? (
          <div className="flex items-center gap-2 rounded-md border border-[var(--danger)]/30 bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger)]">
            <AlertCircle className="h-4 w-4 shrink-0 text-[var(--danger)]" />
            <span>Failed to load live commitments: {error?.message}</span>
          </div>
        ) : (
          <>
            {/* Quota Transition & Delta Badge */}
            <div className="rounded-md border border-[var(--border-subtle)] bg-[var(--surface-base)] p-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="text-center">
                    <div className="text-[10px] uppercase font-semibold text-[var(--text-muted)]">Current</div>
                    <div className="text-xl font-bold font-mono text-[var(--foreground)]">{currentQuota}</div>
                  </div>
                  <ArrowRight className="h-4 w-4 text-[var(--text-muted)]" />
                  <div className="text-center">
                    <div className="text-[10px] uppercase font-semibold text-[var(--text-muted)]">Proposed</div>
                    <div className="text-xl font-bold font-mono text-[var(--brand)]">{proposedQuota}</div>
                  </div>
                </div>

                {/* Delta Badge */}
                <div>
                  {delta > 0 ? (
                    <span className="inline-flex items-center rounded-full bg-[var(--surface-sunken)] px-3 py-1 font-mono text-xs font-semibold text-[var(--foreground)] border border-[var(--border-subtle)]">
                      +{delta} (Expansion)
                    </span>
                  ) : delta < 0 ? (
                    <span className="inline-flex items-center rounded-full bg-[var(--surface-sunken)] px-3 py-1 font-mono text-xs font-semibold text-[var(--foreground)] border border-[var(--border-subtle)]">
                      {delta} (Reduction)
                    </span>
                  ) : (
                    <span className="inline-flex items-center rounded-full bg-[var(--surface-sunken)] px-3 py-1 font-mono text-xs font-medium text-[var(--text-muted)] border border-[var(--border-subtle)]">
                      No Change
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Live Commitments Safety Floor */}
            <div className="rounded-md border border-[var(--border-subtle)] bg-[var(--surface-sunken)] p-3.5 space-y-2.5">
              <div className="flex items-center justify-between text-xs">
                <span className="font-semibold text-[var(--foreground)] uppercase tracking-wide text-[11px]">
                  Live Commitments Floor
                </span>
                <span className="font-mono font-semibold text-[var(--foreground)] bg-[var(--surface-base)] border border-[var(--border-subtle)] rounded px-2 py-0.5 text-xs">
                  Safety Floor: {safetyFloor}
                </span>
              </div>

              <div className="grid grid-cols-3 gap-2 text-center">
                <div className="rounded border border-[var(--border-subtle)] bg-[var(--surface-base)] p-2">
                  <div className="text-[10px] uppercase font-semibold text-[var(--text-muted)]">Occupied</div>
                  <div className="text-base font-bold text-[var(--foreground)] font-mono">{occupied}</div>
                </div>
                <div className="rounded border border-[var(--border-subtle)] bg-[var(--surface-base)] p-2">
                  <div className="text-[10px] uppercase font-semibold text-[var(--text-muted)]">HR Processing</div>
                  <div className="text-base font-bold text-[var(--foreground)] font-mono">{hrProcessing}</div>
                </div>
                <div className="rounded border border-[var(--border-subtle)] bg-[var(--surface-base)] p-2">
                  <div className="text-[10px] uppercase font-semibold text-[var(--text-muted)]">Pipeline</div>
                  <div className="text-base font-bold text-[var(--foreground)] font-mono">{pipeline}</div>
                </div>
              </div>

              <p className="text-[11px] text-[var(--text-muted)] leading-tight">
                Floor represents active occupied staff ({occupied}) + HR processing ({hrProcessing}) + pipeline candidates ({pipeline}).
                Proposed quota cannot be lower than <strong>{safetyFloor}</strong>.
              </p>
            </div>

            {/* Proposed Quota Stepper Input */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label htmlFor="proposed-quota-input" className="text-xs font-semibold text-[var(--foreground)]">
                  Proposed Headcount Target
                </label>
                <span className="text-[11px] text-[var(--text-muted)]">
                  Safety Floor: <strong className="text-[var(--foreground)] font-mono">{safetyFloor}</strong>
                </span>
              </div>

              <div className="flex items-center gap-3">
                <div className="flex items-center rounded-md border border-[var(--border-subtle)] bg-[var(--surface-base)] shadow-xs">
                  <button
                    type="button"
                    onClick={handleDecrement}
                    disabled={proposedQuota <= safetyFloor || proposedQuota <= 1 || amendmentMutation.isPending}
                    className="flex h-10 w-10 items-center justify-center text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--foreground)] disabled:opacity-30 disabled:cursor-not-allowed transition-colors rounded-l-md"
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
                    className="h-10 w-20 text-center font-mono text-base font-semibold text-[var(--foreground)] outline-none border-x border-[var(--border-subtle)] bg-transparent"
                  />
                  <button
                    type="button"
                    onClick={handleIncrement}
                    disabled={amendmentMutation.isPending}
                    className="flex h-10 w-10 items-center justify-center text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--foreground)] disabled:opacity-30 transition-colors rounded-r-md"
                    aria-label="Increase proposed quota"
                  >
                    <Plus className="h-4 w-4" />
                  </button>
                </div>

                <div className="text-xs text-[var(--text-muted)] leading-tight">
                  {delta === 0 ? (
                    <span className="text-[var(--text-muted)] font-medium">
                      Change proposed headcount above or below current ({currentQuota}).
                    </span>
                  ) : delta > 0 ? (
                    <span className="text-[var(--foreground)] font-medium">
                      Requesting addition of +{delta} slot{delta > 1 ? "s" : ""}.
                    </span>
                  ) : (
                    <span className="text-[var(--foreground)] font-medium">
                      Requesting reduction of {Math.abs(delta)} slot{Math.abs(delta) > 1 ? "s" : ""}.
                    </span>
                  )}
                </div>
              </div>

              {/* Safety Floor Enforced Policy Notice */}
              {isFloorViolated && (
                <div className="flex items-start gap-2 rounded-md border border-[var(--border-subtle)] bg-[var(--surface-sunken)] p-2.5 text-xs text-[var(--foreground)]">
                  <ShieldAlert className="h-4 w-4 shrink-0 text-[var(--text-muted)] mt-0.5" />
                  <div>
                    <strong className="font-semibold">Safety Floor Enforced: </strong>
                    Proposed target ({proposedQuota}) cannot be lower than active commitments floor of {safetyFloor}.
                  </div>
                </div>
              )}

              {/* No Change Alert */}
              {delta === 0 && (
                <p className="text-[11px] text-[var(--text-muted)]">
                  Proposed quota must differ from current quota ({currentQuota}).
                </p>
              )}
            </div>

            {/* Operational Justification */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between">
                <label htmlFor="amendment-justification" className="text-xs font-semibold text-[var(--foreground)]">
                  Operational Justification <span className="text-[var(--danger)]">*</span>
                </label>
                <span className="text-[11px] text-[var(--text-muted)] font-mono">
                  {justification.trim().length}/5 chars min
                </span>
              </div>
              <textarea
                id="amendment-justification"
                rows={3}
                value={justification}
                onChange={(e) => setJustification(e.target.value)}
                placeholder="Explain why this quota adjustment is required by Operations (e.g. Peak season volume expansion, store footprint reduction, etc.)..."
                className="w-full rounded-md border border-[var(--border-subtle)] bg-[var(--surface-base)] p-2.5 text-xs text-[var(--foreground)] outline-none placeholder:text-[var(--text-muted)] focus:border-[var(--brand)] focus:ring-1 focus:ring-[var(--brand)] transition-colors"
              />
            </div>

            {/* Submission Error Banner */}
            {submitError && (
              <div className="flex items-center gap-2 rounded-md border border-[var(--danger)]/30 bg-[var(--danger-bg)] p-3 text-xs text-[var(--danger)]">
                <AlertCircle className="h-4 w-4 shrink-0 text-[var(--danger)]" />
                <span>{submitError}</span>
              </div>
            )}
          </>
        )}

        {/* Footer Actions */}
        <div className="flex items-center justify-end gap-3 border-t border-[var(--border-subtle)] pt-4">
          <button
            type="button"
            onClick={onClose}
            disabled={amendmentMutation.isPending}
            className="rounded-md border border-[var(--border-subtle)] bg-[var(--surface-base)] px-4 py-2 text-xs font-medium text-[var(--foreground)] hover:bg-[var(--surface-hover)] transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={!canSubmit}
            className="inline-flex items-center gap-1.5 rounded-md bg-[var(--brand)] px-4 py-2 text-xs font-semibold text-white shadow-xs hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          >
            {amendmentMutation.isPending ? "Submitting..." : "Submit Request"}
          </button>
        </div>
      </form>
    </Modal>
  );
}