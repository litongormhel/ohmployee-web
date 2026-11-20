"use client";

import { useState } from "react";
import { GitFork, Loader2, AlertTriangle, Building, Store, Users, UserCheck } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  transferAccountGroupDirect,
  simulateAccountGroupTransfer,
  type PlantillaScopedAccountItem,
} from "@/lib/queries/plantilla";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { formatAccountName, formatDisplayText } from "@/lib/utils/displayText";

export interface TransferAccountGroupModalProps {
  isOpen: boolean;
  onClose: () => void;
  account: PlantillaScopedAccountItem | null;
  uniqueGroups: { id: string; name: string }[];
  onSuccess: (accountName: string, targetGroupName: string) => void;
}

export function TransferAccountGroupModal({
  isOpen,
  onClose,
  account,
  uniqueGroups,
  onSuccess,
}: TransferAccountGroupModalProps) {
  const queryClient = useQueryClient();
  const [selectedGroupId, setSelectedGroupId] = useState("");
  const [reason, setReason] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Available destination groups (exclude account's current group)
  const destinationGroups = uniqueGroups.filter(
    (g) => g.id !== account?.groupId
  );

  // Simulation query using TanStack Query
  const { data: simulation, isLoading: isSimulating } = useQuery({
    queryKey: ["simulate-group-transfer", account?.id, selectedGroupId],
    queryFn: () =>
      simulateAccountGroupTransfer({
        accountId: account!.id,
        toGroupId: selectedGroupId,
      }),
    enabled: Boolean(account?.id && selectedGroupId),
    staleTime: 60 * 1000,
  });

  const handleClose = () => {
    if (isSubmitting) return;
    setSelectedGroupId("");
    setReason("");
    setErrorMessage(null);
    onClose();
  };

  const handleConfirm = async () => {
    if (!account?.id || !selectedGroupId) return;

    try {
      setIsSubmitting(true);
      setErrorMessage(null);

      const result = await transferAccountGroupDirect({
        accountId: account.id,
        toGroupId: selectedGroupId,
        reason: reason.trim() || undefined,
      });

      // Invalidate relevant query caches
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["plantilla"] }),
        queryClient.invalidateQueries({ queryKey: ["allowed-accounts"] }),
        queryClient.invalidateQueries({ queryKey: ["cencom"] }),
        queryClient.invalidateQueries({ queryKey: ["accounts"] }),
        queryClient.invalidateQueries({ queryKey: ["stores"] }),
      ]);

      const targetGroup = uniqueGroups.find((g) => g.id === selectedGroupId);
      onSuccess(account.name, targetGroup?.name || result.to_group_name || "New Group");
      handleClose();
    } catch (err: unknown) {
      console.error("[TransferAccountGroupModal] Transfer failed:", err);
      setErrorMessage(
        err instanceof Error ? err.message : "Failed to transfer account group."
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  if (!account) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Transfer Account Group"
      subtitle="Directly reassign this account and all its associated doors to another operational group. (Requires Head Admin or Super Admin)"
      maxWidthClass="max-w-xl"
    >
      <div className="space-y-5">
        {/* Account Details Banner */}
        <div className="rounded-xl border border-border-default bg-surface-muted/50 p-4">
          <div className="flex items-center gap-3">
            <div className="rounded-lg bg-brand-50 p-2 text-brand-600">
              <Building className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <h4 className="text-sm font-bold text-text-primary truncate">
                {formatAccountName(account.name)}
              </h4>
              <p className="text-xs text-text-secondary">
                Current Group:{" "}
                <span className="font-semibold text-text-primary">
                  {account.groupName ? formatDisplayText(account.groupName) : "Unassigned"}
                </span>
              </p>
            </div>
          </div>
        </div>

        {/* Destination Group Selection */}
        <div>
          <label
            htmlFor="target-group-select"
            className="block text-xs font-bold uppercase tracking-wider text-text-secondary mb-1.5"
          >
            Destination Group <span className="text-danger-text">*</span>
          </label>
          <select
            id="target-group-select"
            value={selectedGroupId}
            onChange={(e) => setSelectedGroupId(e.target.value)}
            disabled={isSubmitting}
            className="h-10 w-full rounded-lg border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
          >
            <option value="">Select destination group...</option>
            {destinationGroups.map((g) => (
              <option key={g.id} value={g.id}>
                {formatDisplayText(g.name)}
              </option>
            ))}
          </select>
        </div>

        {/* Impact Simulation Preview */}
        {selectedGroupId && (
          <div className="rounded-xl border border-border-default bg-surface-base p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-text-secondary">
                Transfer Impact Summary
              </span>
              {isSimulating && (
                <span className="inline-flex items-center gap-1.5 text-xs text-text-muted">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Calculating...
                </span>
              )}
            </div>

            {simulation && !isSimulating && (
              <>
                <div className="grid grid-cols-3 gap-3">
                  <div className="rounded-lg border border-border-subtle bg-surface-muted/30 p-2.5 text-center">
                    <div className="flex items-center justify-center text-text-muted mb-1">
                      <Store className="h-4 w-4" />
                    </div>
                    <div className="text-base font-bold text-text-primary">
                      {simulation.affected_stores ?? 0}
                    </div>
                    <div className="text-[11px] text-text-secondary">Doors Moving</div>
                  </div>

                  <div className="rounded-lg border border-border-subtle bg-surface-muted/30 p-2.5 text-center">
                    <div className="flex items-center justify-center text-text-muted mb-1">
                      <Users className="h-4 w-4" />
                    </div>
                    <div className="text-base font-bold text-text-primary">
                      {simulation.affected_plantilla_count ?? 0}
                    </div>
                    <div className="text-[11px] text-text-secondary">Active Employees</div>
                  </div>

                  <div className="rounded-lg border border-border-subtle bg-surface-muted/30 p-2.5 text-center">
                    <div className="flex items-center justify-center text-text-muted mb-1">
                      <UserCheck className="h-4 w-4" />
                    </div>
                    <div className="text-base font-bold text-text-primary">
                      {simulation.affected_vacancies_count ?? 0}
                    </div>
                    <div className="text-[11px] text-text-secondary">Open Vacancies</div>
                  </div>
                </div>

                {/* Warnings if any */}
                {simulation.warnings && simulation.warnings.length > 0 && (
                  <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 space-y-1">
                    <div className="flex items-center gap-1.5 font-bold text-amber-900">
                      <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
                      Notice & Conflicts
                    </div>
                    {simulation.warnings.map((warn, i) => (
                      <div key={i} className="pl-5 list-item">
                        {warn}
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>
        )}

        {/* Reason / Justification */}
        <div>
          <label
            htmlFor="transfer-reason"
            className="block text-xs font-bold uppercase tracking-wider text-text-secondary mb-1.5"
          >
            Transfer Reason / Notes (Audit Logged)
          </label>
          <textarea
            id="transfer-reason"
            rows={2}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            disabled={isSubmitting}
            placeholder="Operational realignment, account turnover, territory restructuring..."
            className="w-full rounded-lg border border-border-default bg-surface-base p-3 text-sm text-text-primary outline-none focus:border-brand-500 transition-colors"
          />
        </div>

        {/* Error message */}
        {errorMessage && (
          <div className="rounded-lg border border-danger-border bg-danger-bg/50 p-3 text-xs text-danger-text flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Modal Actions */}
        <div className="flex items-center justify-end gap-3 pt-2 border-t border-border-default">
          <button
            type="button"
            onClick={handleClose}
            disabled={isSubmitting}
            className="rounded-lg border border-border-default bg-surface-base px-4 py-2 text-sm font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleConfirm}
            disabled={!selectedGroupId || isSubmitting || isSimulating}
            className="inline-flex items-center gap-2 rounded-lg bg-brand-primary px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-primary/90 disabled:opacity-50 transition cursor-pointer"
          >
            {isSubmitting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Transferring...
              </>
            ) : (
              <>
                <GitFork className="h-4 w-4" />
                Execute Transfer
              </>
            )}
          </button>
        </div>
      </div>
    </Modal>
  );
}
