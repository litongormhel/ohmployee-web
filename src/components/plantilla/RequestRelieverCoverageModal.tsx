"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, Loader2, UserCheck, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import {
  useRequestRelieverCoverage,
  type WorkforcePoolEmployee,
} from "@/lib/queries/workforcePool";

export interface RequestRelieverCoverageModalProps {
  isOpen: boolean;
  onClose: () => void;
  employee: WorkforcePoolEmployee;
  onSuccess?: () => void;
}

export function RequestRelieverCoverageModal({
  isOpen,
  onClose,
  employee,
  onSuccess,
}: RequestRelieverCoverageModalProps) {
  const [accountId, setAccountId] = useState<string>("");
  const [storeId, setStoreId] = useState<string>("");
  const [startDate, setStartDate] = useState<string>(() => new Date().toISOString().substring(0, 10));
  const [endDate, setEndDate] = useState<string>(() => {
    const d = new Date();
    d.setDate(d.getDate() + 14);
    return d.toISOString().substring(0, 10);
  });
  const [priority, setPriority] = useState<string>("Normal");
  const [requestedPosition, setRequestedPosition] = useState<string>(employee.position || "Staff");
  const [reason, setReason] = useState<string>("");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const mutation = useRequestRelieverCoverage();

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
    queryKey: ["plantilla", "request-stores", accountId],
    queryFn: async () => {
      if (!accountId) return [];
      const supabase = createClient();
      const { data, error } = await supabase
        .from("stores")
        .select("id, store_name, store_branch, area_city")
        .eq("account_id", accountId)
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
    enabled: isOpen && Boolean(accountId),
  });

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!accountId) {
      setErrorMessage("Please select a target account.");
      return;
    }
    if (!storeId) {
      setErrorMessage("Please select a target store.");
      return;
    }
    if (!startDate || !endDate) {
      setErrorMessage("Please select valid start and end dates.");
      return;
    }
    if (new Date(startDate) > new Date(endDate)) {
      setErrorMessage("Start date cannot be after end date.");
      return;
    }
    if (!reason.trim()) {
      setErrorMessage("Please provide a reason or justification for coverage.");
      return;
    }

    mutation.mutate(
      {
        employeeId: employee.id,
        poolTypeId: employee.poolTypeId,
        requestedAccountId: accountId,
        requestedStoreId: storeId,
        startDate,
        endDate,
        priority,
        reason: reason.trim(),
        requestedPosition: requestedPosition.trim() || null,
      },
      {
        onSuccess: () => {
          onSuccess?.();
          onClose();
        },
        onError: (err) => {
          setErrorMessage(err.message || "Failed to submit coverage request.");
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
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4 bg-blue-50/70">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-100 text-blue-700 border border-blue-200">
              <UserCheck className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-gray-900">Request Coverage Deployment</h2>
              <p className="text-xs text-gray-500 font-mono">
                {employee.employeeNo} &bull; {employee.employeeName} ({employee.poolTypeName})
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
                value={accountId}
                onChange={(e) => {
                  setAccountId(e.target.value);
                  setStoreId("");
                }}
                disabled={accountsQuery.isLoading}
                className="w-full text-sm rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
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
                value={storeId}
                onChange={(e) => setStoreId(e.target.value)}
                disabled={!accountId || storesQuery.isLoading}
                className="w-full text-sm rounded-lg border border-gray-300 bg-white px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100"
              >
                <option value="">{accountId ? "Select Store" : "Select an Account first"}</option>
                {(storesQuery.data ?? []).map((st) => (
                  <option key={st.id} value={st.id}>
                    {st.name} {st.branch ? `(${st.branch})` : ""} {st.city ? `— ${st.city}` : ""}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Position Covered</label>
              <input
                type="text"
                value={requestedPosition}
                onChange={(e) => setRequestedPosition(e.target.value)}
                placeholder="e.g. Sales Associate, Barista, Staff"
                className="w-full text-sm rounded-lg border border-gray-300 px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-semibold text-gray-700 mb-1">Start Date *</label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  className="w-full text-sm rounded-lg border border-gray-300 px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-700 mb-1">End Date *</label>
                <input
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  className="w-full text-sm rounded-lg border border-gray-300 px-3 py-2 text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Priority</label>
              <div className="grid grid-cols-3 gap-2">
                {["Normal", "High", "Critical"].map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => setPriority(p)}
                    className={`py-2 text-xs font-medium rounded-lg border transition ${
                      priority === p
                        ? "bg-blue-600 text-white border-blue-600 shadow-xs"
                        : "bg-white text-gray-700 border-gray-200 hover:bg-gray-50"
                    }`}
                  >
                    {p}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-700 mb-1">Reason / Notes *</label>
              <textarea
                rows={3}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Operational justification for deploying this reliever..."
                className="w-full text-sm rounded-lg border border-gray-300 p-2.5 text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
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
              className="inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition disabled:opacity-50"
            >
              {mutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Submit Request
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
