"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, Loader2, PlusCircle, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import {
  useCreatePoolVacancy,
  usePoolPositions,
  useWorkforcePoolTypes,
} from "@/lib/queries/workforcePool";

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

  if (!isOpen) return null;

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
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-emerald-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700 border border-emerald-200">
              <PlusCircle className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">Request Moses Pool Headcount</h2>
              <p className="text-xs text-gray-500 font-mono">Create new approved pool slots / vacancies</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition"
            aria-label="Close"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-4">
          {errorMessage && (
            <div className="flex items-start gap-2 p-3 text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg">
              <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
              <span>{errorMessage}</span>
            </div>
          )}

          <div className="space-y-3">
            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Workforce Pool Type *</label>
              <select
                value={poolTypeCode}
                onChange={(e) => setPoolTypeCode(e.target.value)}
                className="w-full text-sm rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500"
              >
                {(poolTypesQuery.data ?? []).map((t) => (
                  <option key={t.id} value={t.code || t.name.toUpperCase()}>
                    {t.name} ({t.code || t.name})
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Pool Position *</label>
              <select
                value={positionId}
                onChange={(e) => setPositionId(e.target.value)}
                className="w-full text-sm rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500"
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
              <label className="block text-xs font-semibold text-gray-700 mb-1">Account *</label>
              <select
                value={accountId}
                onChange={(e) => setAccountId(e.target.value)}
                className="w-full text-sm rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500"
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
                <label className="block text-xs font-semibold text-gray-700 mb-1">Headcount Needed *</label>
                <input
                  type="number"
                  min={1}
                  max={50}
                  value={headcountNeeded}
                  onChange={(e) => setHeadcountNeeded(Number(e.target.value))}
                  className="w-full text-sm rounded-lg border border-gray-300 px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-700 mb-1">Priority</label>
                <select
                  value={priority}
                  onChange={(e) => setPriority(e.target.value)}
                  className="w-full text-sm rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500"
                >
                  <option value="Normal">Normal</option>
                  <option value="High">Urgent / High</option>
                  <option value="Critical">Critical</option>
                </select>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-semibold text-gray-700 mb-1">Target Province</label>
                <input
                  type="text"
                  value={province}
                  onChange={(e) => setProvince(e.target.value)}
                  placeholder="e.g. Metro Manila, Cebu"
                  className="w-full text-sm rounded-lg border border-gray-300 px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-700 mb-1">Target City</label>
                <input
                  type="text"
                  value={city}
                  onChange={(e) => setCity(e.target.value)}
                  placeholder="e.g. Quezon City, Makati"
                  className="w-full text-sm rounded-lg border border-gray-300 px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Reason / Justification</label>
              <textarea
                rows={2}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Operational reasons for expanding pool quota..."
                className="w-full text-sm rounded-lg border border-gray-300 p-2.5 text-gray-900 focus:outline-none focus:ring-2 focus:ring-emerald-500"
              />
            </div>
          </div>

          <div className="flex items-center justify-end gap-3 pt-4 border-t border-gray-100">
            <button
              type="button"
              onClick={onClose}
              disabled={mutation.isPending}
              className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={mutation.isPending}
              className="inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-emerald-600 rounded-lg hover:bg-emerald-700 transition disabled:opacity-50"
            >
              {mutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Create Pool Vacancy
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
