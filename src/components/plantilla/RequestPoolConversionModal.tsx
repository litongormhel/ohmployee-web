"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, ArrowRightLeft, Loader2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { useCurrentUser } from "@/lib/auth";
import { fetchPlantillaScopedAccounts } from "@/lib/queries/plantilla";
import {
  useRequestPoolConversion,
  type WorkforcePoolEmployee,
} from "@/lib/queries/workforcePool";
import { Modal } from "@/components/shared/Modal";

export interface RequestPoolConversionModalProps {
  isOpen: boolean;
  onClose: () => void;
  employee: WorkforcePoolEmployee;
  onSuccess?: () => void;
}

export function RequestPoolConversionModal({
  isOpen,
  onClose,
  employee,
  onSuccess,
}: RequestPoolConversionModalProps) {
  const [targetAccountId, setTargetAccountId] = useState<string>("");
  const [targetStoreId, setTargetStoreId] = useState<string>("");
  const [position, setPosition] = useState<string>(employee.position || "Regular Staff");
  const [effectiveDate, setEffectiveDate] = useState<string>(() => new Date().toISOString().substring(0, 10));
  const [reason, setReason] = useState<string>("");
  const [notes, setNotes] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useRequestPoolConversion();

  const isDirty =
    targetAccountId !== "" ||
    targetStoreId !== "" ||
    reason.trim() !== "" ||
    notes.trim() !== "";

  const currentUser = useCurrentUser();

  // Load active accounts strictly respecting user scope
  const accountsQuery = useQuery({
    queryKey: ["plantilla", "request-accounts", currentUser?.accountScope, currentUser?.groupScope],
    queryFn: async () => {
      const accounts = await fetchPlantillaScopedAccounts(currentUser);
      return accounts.map((r) => ({ id: r.id, name: r.name }));
    },
    enabled: isOpen && !!currentUser,
  });

  // Load stores when account is selected
  const storesQuery = useQuery({
    queryKey: ["plantilla", "request-stores", targetAccountId],
    queryFn: async () => {
      if (!targetAccountId) return [];
      const supabase = createClient();
      const { data, error } = await supabase
        .from("stores")
        .select("id, store_name, store_branch, area_city")
        .eq("account_id", targetAccountId)
        .eq("is_active", true)
        .order("store_name");
      if (error) throw error;
      return (data ?? []).map((r) => ({
        id: String(r.id),
        name: String(r.store_name),
        branch: r.store_branch ? String(r.store_branch) : null,
        city: r.area_city ? String(r.area_city) : null,
      }));
    },
    enabled: isOpen && Boolean(targetAccountId),
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!targetAccountId) {
      setErrorMessage("Please select a target account.");
      return;
    }
    if (!targetStoreId) {
      setErrorMessage("Please select a target store.");
      return;
    }
    if (!position.trim()) {
      setErrorMessage("Please specify the target position.");
      return;
    }
    if (!effectiveDate) {
      setErrorMessage("Please select an effective date.");
      return;
    }
    if (!reason.trim()) {
      setErrorMessage("Please provide a reason for conversion from pool to regular plantilla.");
      return;
    }

    mutation.mutate(
      {
        employeeId: employee.id,
        targetAccountId,
        targetStoreId,
        position: position.trim(),
        effectiveDate,
        reason: reason.trim(),
        notes: notes.trim() || null,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to submit conversion request.");
        },
      }
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Request Pool Conversion"
      subtitle={
        <span className="font-mono text-text-secondary text-xs">
          {employee.employeeNo} • {employee.employeeName} ({employee.poolTypeName} → Regular)
        </span>
      }
      icon={ArrowRightLeft}
      isSubmitting={mutation.isPending}
      isDirty={isDirty}
      maxWidthClass="max-w-lg"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {errorMessage && (
          <div className="flex items-start gap-2 p-3 text-xs text-danger-text bg-danger-bg border border-danger-border rounded-lg">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5 text-danger-text" />
            <span>{errorMessage}</span>
          </div>
        )}

        <div className="space-y-3 text-sm">
          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Target Account <span className="text-danger-text">*</span>
            </label>
            <select
              value={targetAccountId}
              onChange={(e) => {
                setTargetAccountId(e.target.value);
                setTargetStoreId("");
              }}
              disabled={accountsQuery.isLoading}
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
            >
              <option value="">Select Account</option>
              {(accountsQuery.data ?? []).map((acc) => (
                <option key={acc.id} value={acc.id}>
                  {acc.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Target Store <span className="text-danger-text">*</span>
            </label>
            <select
              value={targetStoreId}
              onChange={(e) => setTargetStoreId(e.target.value)}
              disabled={!targetAccountId || storesQuery.isLoading}
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden disabled:bg-surface-muted disabled:text-text-muted"
            >
              <option value="">{targetAccountId ? "Select Store" : "Select an Account first"}</option>
              {(storesQuery.data ?? []).map((st) => (
                <option key={st.id} value={st.id}>
                  {st.name} {st.branch ? `(${st.branch})` : ""} {st.city ? `— ${st.city}` : ""}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Target Position <span className="text-danger-text">*</span>
            </label>
            <input
              type="text"
              value={position}
              onChange={(e) => setPosition(e.target.value)}
              placeholder="e.g. Sales Associate, Shift Supervisor"
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Effective Date <span className="text-danger-text">*</span>
            </label>
            <input
              type="date"
              value={effectiveDate}
              onChange={(e) => setEffectiveDate(e.target.value)}
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Reason for Conversion <span className="text-danger-text">*</span>
            </label>
            <textarea
              rows={2}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Why is this pooled employee converting to regular store plantilla?"
              className="w-full text-sm rounded-lg border border-border-default bg-surface p-2.5 text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">Additional Notes</label>
            <textarea
              rows={2}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Optional notes or references..."
              className="w-full text-sm rounded-lg border border-border-default bg-surface p-2.5 text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:outline-hidden"
            />
          </div>
        </div>

        <div className="flex items-center justify-end gap-2.5 pt-3 border-t border-border-default">
          <button
            type="button"
            onClick={onClose}
            disabled={mutation.isPending}
            className="px-4 py-2 text-xs font-semibold text-text-secondary bg-surface border border-border-default rounded-lg hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={mutation.isPending}
            className="inline-flex items-center gap-2 px-4 py-2 text-xs font-semibold text-white bg-brand-button rounded-lg hover:bg-brand-secondary transition-colors cursor-pointer shadow-xs disabled:opacity-50"
          >
            {mutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Submit Conversion Request
          </button>
        </div>
      </form>
    </Modal>
  );
}
