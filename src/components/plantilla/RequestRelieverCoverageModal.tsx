"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertCircle, Loader2, UserCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import {
  useRequestRelieverCoverage,
  type WorkforcePoolEmployee,
} from "@/lib/queries/workforcePool";
import { Modal } from "@/components/shared/Modal";

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

  const isDirty =
    accountId !== "" ||
    storeId !== "" ||
    reason.trim() !== "";

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
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Request Coverage Deployment"
      subtitle={
        <span className="font-mono text-text-secondary text-xs">
          {employee.employeeNo} • {employee.employeeName} ({employee.poolTypeName})
        </span>
      }
      icon={UserCheck}
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
              value={accountId}
              onChange={(e) => {
                setAccountId(e.target.value);
                setStoreId("");
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
              value={storeId}
              onChange={(e) => setStoreId(e.target.value)}
              disabled={!accountId || storesQuery.isLoading}
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden disabled:bg-surface-muted disabled:text-text-muted"
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
            <label className="block text-xs font-semibold text-text-secondary mb-1">Position Covered</label>
            <input
              type="text"
              value={requestedPosition}
              onChange={(e) => setRequestedPosition(e.target.value)}
              placeholder="e.g. Sales Associate, Barista, Staff"
              className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-text-secondary mb-1">
                Start Date <span className="text-danger-text">*</span>
              </label>
              <input
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-text-secondary mb-1">
                End Date <span className="text-danger-text">*</span>
              </label>
              <input
                type="date"
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                className="w-full text-sm rounded-lg border border-border-default bg-surface px-3 py-2 text-text-primary focus:border-brand-primary focus:outline-hidden"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">Priority</label>
            <div className="grid grid-cols-3 gap-2">
              {["Normal", "High", "Critical"].map((p) => (
                <button
                  key={p}
                  type="button"
                  onClick={() => setPriority(p)}
                  className={`py-2 text-xs font-semibold rounded-lg border transition-colors cursor-pointer ${
                    priority === p
                      ? "bg-brand-primary text-white border-brand-primary shadow-xs"
                      : "bg-surface text-text-secondary border-border-default hover:bg-surface-hover hover:text-text-primary"
                  }`}
                >
                  {p}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary mb-1">
              Reason / Notes <span className="text-danger-text">*</span>
            </label>
            <textarea
              rows={3}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Operational justification for deploying this reliever..."
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
            Submit Request
          </button>
        </div>
      </form>
    </Modal>
  );
}
