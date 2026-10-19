"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, ArrowRightLeft, Loader2, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import {
  useRequestPoolConversion,
  type WorkforcePoolEmployee,
} from "@/lib/queries/workforcePool";

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

  // Load active accounts
  const accountsQuery = useQuery({
    queryKey: ["plantilla", "request-accounts"],
    queryFn: async () => {
      const supabase = createClient();
      const { data, error } = await supabase
        .from("accounts")
        .select("id, account_name")
        .eq("is_active", true)
        .order("account_name");
      if (error) throw error;
      return (data ?? []).map((r) => ({ id: String(r.id), name: String(r.account_name) }));
    },
    enabled: isOpen,
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

  if (!isOpen) return null;

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
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in duration-150"
    >
      <div className="relative w-full max-w-lg rounded-xl border border-gray-200 bg-white shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-purple-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-purple-100 text-purple-700 border border-purple-200">
              <ArrowRightLeft className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">Request Pool Conversion</h2>
              <p className="text-xs text-gray-500 font-mono">
                {employee.employeeNo} &bull; {employee.employeeName} ({employee.poolTypeName} &rarr; Regular)
              </p>
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
              <label className="block text-xs font-semibold text-gray-700 mb-1">Target Account *</label>
              <select
                value={targetAccountId}
                onChange={(e) => {
                  setTargetAccountId(e.target.value);
                  setTargetStoreId("");
                }}
                disabled={accountsQuery.isLoading}
                className="w-full text-sm rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-purple-500"
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
              <label className="block text-xs font-semibold text-gray-700 mb-1">Target Store *</label>
              <select
                value={targetStoreId}
                onChange={(e) => setTargetStoreId(e.target.value)}
                disabled={!targetAccountId || storesQuery.isLoading}
                className="w-full text-sm rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-purple-500 disabled:bg-gray-100"
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
              <label className="block text-xs font-semibold text-gray-700 mb-1">Target Position *</label>
              <input
                type="text"
                value={position}
                onChange={(e) => setPosition(e.target.value)}
                placeholder="e.g. Sales Associate, Shift Supervisor"
                className="w-full text-sm rounded-lg border border-gray-300 px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-purple-500"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Effective Date *</label>
              <input
                type="date"
                value={effectiveDate}
                onChange={(e) => setEffectiveDate(e.target.value)}
                className="w-full text-sm rounded-lg border border-gray-300 px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-purple-500"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Reason for Conversion *</label>
              <textarea
                rows={2}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Why is this pooled employee converting to regular store plantilla?"
                className="w-full text-sm rounded-lg border border-gray-300 p-2.5 text-gray-900 focus:outline-none focus:ring-2 focus:ring-purple-500"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Additional Notes</label>
              <textarea
                rows={2}
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Optional notes or references..."
                className="w-full text-sm rounded-lg border border-gray-300 p-2.5 text-gray-900 focus:outline-none focus:ring-2 focus:ring-purple-500"
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
              className="inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-purple-600 rounded-lg hover:bg-purple-700 transition disabled:opacity-50"
            >
              {mutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Submit Conversion Request
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
