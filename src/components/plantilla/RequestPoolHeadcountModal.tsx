"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, Loader2, PlusCircle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import {
  useCreatePoolVacancy,
  usePoolPositions,
  useWorkforcePoolTypes,
} from "@/lib/queries/workforcePool";
import { Modal } from "@/components/shared/Modal";

export interface RequestPoolHeadcountModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

export function RequestPoolHeadcountModal({
  isOpen,
  onClose,
  onSuccess,
}: RequestPoolHeadcountModalProps) {
  const [poolTypeCode, setPoolTypeCode] = useState<string>("RELIEVER");
  const [positionId, setPositionId] = useState<string>("");
  const [accountId, setAccountId] = useState<string>("");
  const [headcountNeeded, setHeadcountNeeded] = useState<number>(1);
  const [priority, setPriority] = useState<string>("Normal");
  const [reason, setReason] = useState<string>("");
  const [province, setProvince] = useState<string>("");
  const [city, setCity] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useCreatePoolVacancy();
  const poolTypesQuery = useWorkforcePoolTypes();
  const positionsQuery = usePoolPositions();

  const isDirty =
    positionId !== "" ||
    accountId !== "" ||
    headcountNeeded !== 1 ||
    reason.trim() !== "" ||
    province.trim() !== "" ||
    city.trim() !== "";

  // Load pool accounts or general accounts
  const accountsQuery = useQuery({
    queryKey: ["plantilla", "request-accounts"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("accounts")
        .select("id, account_name, is_pool_account")
        .eq("is_active", true)
        .order("is_pool_account", { ascending: false })
        .order("account_name");
      if (error) throw error;
      return (data ?? []).map((r) => ({
        id: String(r.id),
        name: String(r.account_name),
        isPoolAccount: Boolean(r.is_pool_account),
      }));
    },
    enabled: isOpen,
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!poolTypeCode) {
      setErrorMessage("Please select a pool type.");
      return;
    }
    if (!positionId) {
      setErrorMessage("Please select a pool position.");
      return;
    }
    if (!accountId) {
      setErrorMessage("Please select an account.");
      return;
    }
    if (headcountNeeded < 1) {
      setErrorMessage("Headcount must be at least 1.");
      return;
    }

    mutation.mutate(
      {
        poolTypeCode,
        positionId,
        requestingAccountId: accountId,
        headcountNeeded,
        priority: priority.toLowerCase(),
        reason: reason.trim() || null,
        requestedProvince: province.trim() || null,
        requestedCity: city.trim() || null,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to create pool vacancy.");
        },
      }
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Request Moses Pool Headcount"
      subtitle="Create new approved pool slots / vacancies"
      icon={PlusCircle}
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
              Workforce Pool Type <span className="text-danger-text">*</span>
            </label>
            <select
              value={poolTypeCode}
              onChange={(e) => setPoolTypeCode(e.target.value)}
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
            >
              {(poolTypesQuery.data ?? []).map((t) => (
                <option key={t.id} value={t.code || t.name.toUpperCase()}>
                  {t.name} ({t.code || t.name})
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Pool Position <span className="text-danger-text">*</span>
            </label>
            <select
              value={positionId}
              onChange={(e) => setPositionId(e.target.value)}
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
            >
              <option value="">Select Pool Position</option>
              {(positionsQuery.data ?? []).map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Account <span className="text-danger-text">*</span>
            </label>
            <select
              value={accountId}
              onChange={(e) => setAccountId(e.target.value)}
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
            >
              <option value="">Select Account</option>
              {(accountsQuery.data ?? []).map((acc) => (
                <option key={acc.id} value={acc.id}>
                  {acc.isPoolAccount ? `★ ${acc.name} (HQ Pool)` : acc.name}
                </option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-text-secondary mb-1">
                Headcount Needed <span className="text-danger-text">*</span>
              </label>
              <input
                type="number"
                min={1}
                max={50}
                value={headcountNeeded}
                onChange={(e) => setHeadcountNeeded(Number(e.target.value))}
                className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-text-secondary mb-1">Priority</label>
              <select
                value={priority}
                onChange={(e) => setPriority(e.target.value)}
                className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
              >
                <option value="Normal">Normal</option>
                <option value="High">Urgent / High</option>
                <option value="Critical">Critical</option>
              </select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-text-secondary mb-1">Target Province</label>
              <input
                type="text"
                value={province}
                onChange={(e) => setProvince(e.target.value)}
                placeholder="e.g. Metro Manila, Cebu"
                className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-text-secondary mb-1">Target City</label>
              <input
                type="text"
                value={city}
                onChange={(e) => setCity(e.target.value)}
                placeholder="e.g. Quezon City, Makati"
                className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">Reason / Justification</label>
            <textarea
              rows={2}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Operational reasons for expanding pool quota..."
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
            className="inline-flex items-center gap-2 px-4 py-2 text-xs font-semibold text-white bg-brand-primary rounded-lg hover:bg-brand-secondary transition-colors cursor-pointer shadow-xs disabled:opacity-50"
          >
            {mutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Create Pool Vacancy
          </button>
        </div>
      </form>
    </Modal>
  );
}
