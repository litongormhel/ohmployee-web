"use client";

import { useState } from "react";
import {
  CheckCircle2,
  Clock,
  Key,
  Plus,
  RefreshCw,
  Trash2,
  X,
} from "lucide-react";
import {
  useAllTempPermissions,
  useEncodersAndGroups,
  useGrantTempPermission,
  useRevokeTempPermission,
  type TempPermissionRecord,
} from "@/lib/queries/more";

export interface TempPermissionModalProps {
  isOpen: boolean;
  onClose: () => void;
  canManage: boolean;
  currentUserFullName: string;
}

export function TempPermissionModal({
  isOpen,
  onClose,
  canManage,
  currentUserFullName,
}: TempPermissionModalProps) {
  const [activeTab, setActiveTab] = useState<"active" | "history" | "grant">("active");

  const { data: permissions, isLoading, refetch, isFetching } = useAllTempPermissions();
  const { data: encodersAndGroups } = useEncodersAndGroups();
  const grantMutation = useGrantTempPermission();
  const revokeMutation = useRevokeTempPermission();

  // Grant Form States
  const [selectedUserId, setSelectedUserId] = useState<string>("");
  const [selectedGroups, setSelectedGroups] = useState<string[]>([]);
  const [expiryDays, setExpiryDays] = useState<number>(3);
  const [reason, setReason] = useState<string>("");
  const [formError, setFormError] = useState<string | null>(null);

  if (!isOpen) return null;

  const activeList = permissions?.active ?? [];
  const historyList = permissions?.history ?? [];

  const handleToggleGroup = (groupName: string) => {
    setSelectedGroups((prev) =>
      prev.includes(groupName)
        ? prev.filter((g) => g !== groupName)
        : [...prev, groupName]
    );
  };

  const handleGrantSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedUserId) {
      setFormError("Please select an encoder.");
      return;
    }
    if (selectedGroups.length === 0) {
      setFormError("Please select at least one CENCOM operational group.");
      return;
    }

    try {
      setFormError(null);
      const expiresAt = new Date(Date.now() + expiryDays * 24 * 60 * 60 * 1000).toISOString();
      await grantMutation.mutateAsync({
        userId: selectedUserId,
        additionalGroups: selectedGroups,
        expiresAt,
        reason: reason.trim() || undefined,
        grantedBy: currentUserFullName,
      });

      // Reset form and return to active tab
      setSelectedUserId("");
      setSelectedGroups([]);
      setReason("");
      setActiveTab("active");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to grant temporary permission override.";
      setFormError(msg);
    }
  };

  const handleRevoke = async (item: TempPermissionRecord) => {
    if (
      !confirm(
        `Are you sure you want to revoke temporary access for ${item.userFullName}?\nGroups: ${item.additionalGroups.join(", ")}`
      )
    ) {
      return;
    }

    try {
      await revokeMutation.mutateAsync({
        overrideId: item.id,
        revokedBy: currentUserFullName,
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to revoke access.";
      alert(msg);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="temp-permission-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/60 backdrop-blur-xs animate-in fade-in duration-200"
    >
      <div className="relative w-full max-w-2xl bg-white rounded-2xl shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4.5 border-b border-slate-200 bg-slate-50/80">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-amber-100 text-amber-700 flex items-center justify-center">
              <Key className="w-5 h-5" />
            </div>
            <div>
              <h2 id="temp-permission-title" className="text-base font-bold text-slate-900 leading-tight">
                Temporary Group Access
              </h2>
              <p className="text-xs text-slate-500">
                Grant and audit time-bound CENCOM group scope overrides for Encoders
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-200/60 transition-colors"
            aria-label="Close modal"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Tab Strip */}
        <div className="px-6 pt-3 border-b border-slate-200 bg-white flex items-center justify-between">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => setActiveTab("active")}
              className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                activeTab === "active"
                  ? "border-amber-600 text-amber-900"
                  : "border-transparent text-slate-500 hover:text-slate-800"
              }`}
            >
              <span>Active Overrides</span>
              <span className="px-1.5 py-0.2 rounded-full text-[10px] bg-amber-100 text-amber-800 font-bold">
                {activeList.length}
              </span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("history")}
              className={`pb-3 px-3 text-xs font-semibold border-b-2 transition-colors flex items-center gap-1.5 ${
                activeTab === "history"
                  ? "border-amber-600 text-amber-900"
                  : "border-transparent text-slate-500 hover:text-slate-800"
              }`}
            >
              <span>History</span>
              <span className="px-1.5 py-0.2 rounded-full text-[10px] bg-slate-100 text-slate-600 font-bold">
                {historyList.length}
              </span>
            </button>
          </div>

          {canManage && (
            <button
              type="button"
              onClick={() => setActiveTab(activeTab === "grant" ? "active" : "grant")}
              className={`mb-2 px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 ${
                activeTab === "grant"
                  ? "bg-slate-200 text-slate-800"
                  : "bg-amber-600 hover:bg-amber-700 text-white shadow-xs"
              }`}
            >
              {activeTab === "grant" ? (
                <>
                  <X className="w-3.5 h-3.5" />
                  <span>Cancel Grant</span>
                </>
              ) : (
                <>
                  <Plus className="w-3.5 h-3.5" />
                  <span>Grant Access</span>
                </>
              )}
            </button>
          )}
        </div>

        {/* Modal Body */}
        <div className="p-6 overflow-y-auto flex-1 space-y-4">
          {activeTab === "grant" ? (
            /* Grant Form */
            <form onSubmit={handleGrantSubmit} className="space-y-4 text-xs">
              <div className="p-3.5 bg-amber-50/70 border border-amber-200/80 rounded-xl text-amber-900">
                <span className="font-semibold block mb-0.5">Time-Bound Security Override</span>
                <span>
                  Granted scopes allow the selected encoder to view and edit requisitions within the assigned CENCOM
                  groups until expiration.
                </span>
              </div>

              <div>
                <label className="block font-semibold text-slate-700 mb-1.5">
                  Select Encoder <span className="text-rose-500">*</span>
                </label>
                <select
                  value={selectedUserId}
                  onChange={(e) => setSelectedUserId(e.target.value)}
                  className="w-full text-xs px-3 py-2 border border-slate-300 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-amber-500"
                >
                  <option value="">-- Choose Encoder --</option>
                  {(encodersAndGroups?.encoders ?? []).map((enc) => (
                    <option key={enc.id} value={enc.id}>
                      {enc.fullName}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block font-semibold text-slate-700 mb-1.5">
                  Select CENCOM Group(s) <span className="text-rose-500">*</span>
                </label>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 border border-slate-200 p-3 rounded-xl max-h-40 overflow-y-auto bg-slate-50/50">
                  {(encodersAndGroups?.groups ?? []).map((grp) => {
                    const checked = selectedGroups.includes(grp.groupName);
                    return (
                      <button
                        type="button"
                        key={grp.id}
                        onClick={() => handleToggleGroup(grp.groupName)}
                        className={`px-2.5 py-1.5 text-xs text-left rounded-lg border transition-all flex items-center justify-between ${
                          checked
                            ? "bg-amber-100/70 border-amber-400 text-amber-900 font-bold"
                            : "bg-white border-slate-200 text-slate-700 hover:border-slate-300"
                        }`}
                      >
                        <span className="truncate">{grp.groupName}</span>
                        {checked && <CheckCircle2 className="w-3.5 h-3.5 text-amber-700 shrink-0 ml-1" />}
                      </button>
                    );
                  })}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-semibold text-slate-700 mb-1.5">
                    Duration Window <span className="text-rose-500">*</span>
                  </label>
                  <select
                    value={expiryDays}
                    onChange={(e) => setExpiryDays(Number(e.target.value))}
                    className="w-full text-xs px-3 py-2 border border-slate-300 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-amber-500"
                  >
                    <option value={1}>1 Day (24 hours)</option>
                    <option value={3}>3 Days</option>
                    <option value={7}>7 Days (1 Week)</option>
                    <option value={14}>14 Days (2 Weeks)</option>
                    <option value={30}>30 Days (1 Month)</option>
                  </select>
                </div>
                <div>
                  <label className="block font-semibold text-slate-700 mb-1.5">
                    Notification
                  </label>
                  <div className="flex items-center gap-2 h-9 px-3 border border-slate-200 rounded-lg bg-slate-50 text-slate-600">
                    <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                    <span>In-app banner alert</span>
                  </div>
                </div>
              </div>

              <div>
                <label className="block font-semibold text-slate-700 mb-1.5">
                  Business Reason / Purpose
                </label>
                <textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g., Covering for absent encoder during payroll cutoff period..."
                  rows={2}
                  className="w-full text-xs px-3 py-2 border border-slate-300 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-amber-500"
                />
              </div>

              {formError && (
                <p className="text-xs text-rose-600 font-medium">{formError}</p>
              )}

              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setActiveTab("active")}
                  className="px-3.5 py-2 text-xs text-slate-700 bg-white border border-slate-300 rounded-xl hover:bg-slate-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={grantMutation.isPending}
                  className="px-4 py-2 text-xs font-semibold text-white bg-amber-600 hover:bg-amber-700 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
                >
                  {grantMutation.isPending && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                  <span>Confirm & Grant Access</span>
                </button>
              </div>
            </form>
          ) : activeTab === "active" ? (
            /* Active List */
            <div className="space-y-3">
              {isLoading ? (
                <div className="py-12 text-center text-xs text-slate-400">Loading active overrides...</div>
              ) : activeList.length === 0 ? (
                <div className="py-12 text-center border-2 border-dashed border-slate-200 rounded-2xl">
                  <Key className="w-8 h-8 text-slate-300 mx-auto mb-2" />
                  <p className="text-xs font-semibold text-slate-700">No active temporary overrides</p>
                  <p className="text-[11px] text-slate-400 mt-0.5">
                    All encoders currently operate under standard permanent role scopes.
                  </p>
                </div>
              ) : (
                activeList.map((item) => (
                  <div
                    key={item.id}
                    className="p-4 rounded-xl border border-slate-200 bg-white hover:border-amber-300 transition-all shadow-2xs space-y-2.5"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-xs text-slate-900">{item.userFullName}</span>
                          <span className="px-1.5 py-0.2 rounded-md text-[10px] font-semibold bg-blue-50 text-blue-700 border border-blue-200">
                            {item.userRole}
                          </span>
                        </div>
                        <p className="text-[11px] text-slate-500 mt-0.5">
                          Granted by <span className="font-medium text-slate-700">{item.grantedBy}</span>
                        </p>
                      </div>

                      {canManage && (
                        <button
                          type="button"
                          onClick={() => handleRevoke(item)}
                          disabled={revokeMutation.isPending}
                          className="px-2.5 py-1 text-[11px] font-semibold text-rose-700 bg-rose-50 hover:bg-rose-100 rounded-lg border border-rose-200 flex items-center gap-1 transition-colors"
                        >
                          <Trash2 className="w-3 h-3" />
                          <span>Revoke</span>
                        </button>
                      )}
                    </div>

                    <div className="flex flex-wrap items-center gap-1.5 pt-1">
                      <span className="text-[11px] text-slate-400">Groups:</span>
                      {item.additionalGroups.map((grp) => (
                        <span
                          key={grp}
                          className="px-2 py-0.5 rounded-md text-[11px] font-semibold bg-amber-50 text-amber-800 border border-amber-200"
                        >
                          {grp}
                        </span>
                      ))}
                    </div>

                    {item.reason && (
                      <p className="text-[11px] text-slate-600 bg-slate-50 p-2 rounded-lg italic">
                        “{item.reason}”
                      </p>
                    )}

                    <div className="flex items-center justify-between text-[11px] text-slate-500 pt-1 border-t border-slate-100">
                      <span className="flex items-center gap-1">
                        <Clock className="w-3 h-3 text-slate-400" />
                        Expires {new Date(item.expiresAt).toLocaleString()}
                      </span>
                      <span className="font-semibold text-amber-700">Active</span>
                    </div>
                  </div>
                ))
              )}
            </div>
          ) : (
            /* History List */
            <div className="space-y-3">
              {isLoading ? (
                <div className="py-12 text-center text-xs text-slate-400">Loading history...</div>
              ) : historyList.length === 0 ? (
                <div className="py-12 text-center text-xs text-slate-400">No past override records found.</div>
              ) : (
                historyList.map((item) => (
                  <div
                    key={item.id}
                    className="p-3.5 rounded-xl border border-slate-200 bg-slate-50/50 text-xs space-y-1.5 opacity-80"
                  >
                    <div className="flex items-center justify-between">
                      <span className="font-semibold text-slate-800">{item.userFullName}</span>
                      <span className="px-2 py-0.5 rounded-full text-[10px] font-semibold bg-slate-200 text-slate-700">
                        {item.revokedBy ? "Revoked" : "Expired"}
                      </span>
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {item.additionalGroups.map((g) => (
                        <span key={g} className="px-1.5 py-0.2 rounded text-[10px] bg-white border border-slate-200 text-slate-600">
                          {g}
                        </span>
                      ))}
                    </div>
                    <div className="text-[11px] text-slate-400 flex items-center justify-between pt-1">
                      <span>Created {new Date(item.createdAt).toLocaleDateString()}</span>
                      {item.revokedBy && <span>Revoked by {item.revokedBy}</span>}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-4 border-t border-slate-200 bg-slate-50/50">
          <button
            type="button"
            onClick={() => refetch()}
            disabled={isFetching}
            className="flex items-center gap-1.5 text-xs text-slate-500 hover:text-slate-800"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isFetching ? "animate-spin" : ""}`} />
            <span>Refresh</span>
          </button>
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-slate-700 bg-white border border-slate-300 rounded-xl hover:bg-slate-50 transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
