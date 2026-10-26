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
import { Modal } from "@/components/shared/Modal";

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

  const isFormDirty = activeTab === "grant" && Boolean(selectedUserId || selectedGroups.length > 0 || reason.trim());

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Temporary Group Access"
      subtitle="Grant and audit time-bound CENCOM group scope overrides for Encoders"
      icon={Key}
      maxWidthClass="max-w-2xl"
      isSubmitting={grantMutation.isPending}
      disableBackdropClick={grantMutation.isPending}
      isDirty={isFormDirty}
      footer={
        <div className="flex w-full items-center justify-between text-xs text-text-muted">
          <button
            type="button"
            onClick={() => refetch()}
            disabled={isFetching}
            className="flex items-center gap-1.5 text-xs text-text-secondary hover:text-text-primary cursor-pointer disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isFetching ? "animate-spin text-brand-primary" : ""}`} />
            <span>Refresh</span>
          </button>
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl border border-border-default bg-surface-primary px-4 py-2 text-xs font-semibold text-text-primary transition hover:bg-surface-hover cursor-pointer"
          >
            Close
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        {/* Navigation & Action Bar */}
        <div className="flex items-center justify-between border-b border-border-default pb-3">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => setActiveTab("active")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "active"
                  ? "bg-brand-50 text-brand-900 border border-brand-200"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              <span>Active Overrides</span>
              <span className="px-1.5 py-0.2 rounded-full text-xs bg-surface-subtle text-text-muted">
                {activeList.length}
              </span>
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("history")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "history"
                  ? "bg-brand-50 text-brand-900 border border-brand-200"
                  : "text-text-secondary hover:text-text-primary hover:bg-surface-hover"
              }`}
            >
              <span>History</span>
              <span className="px-1.5 py-0.2 rounded-full text-xs bg-surface-subtle text-text-muted">
                {historyList.length}
              </span>
            </button>
          </div>

          {canManage && (
            <button
              type="button"
              onClick={() => setActiveTab(activeTab === "grant" ? "active" : "grant")}
              className={`px-3 py-1.5 text-xs font-semibold rounded-xl transition-colors flex items-center gap-1.5 cursor-pointer ${
                activeTab === "grant"
                  ? "bg-surface-subtle border border-border-default text-text-primary"
                  : "bg-brand-primary hover:bg-brand-primary-hover text-surface-primary shadow-2xs"
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

        {/* Tab Content */}
        <div className="max-h-[55vh] overflow-y-auto space-y-3 pr-1">
          {activeTab === "grant" ? (
            /* Grant Access Form */
            <form onSubmit={handleGrantSubmit} className="space-y-4 text-xs">
              <div className="p-3.5 bg-surface-subtle border border-border-default rounded-xl text-text-secondary">
                <span className="font-semibold block mb-0.5 text-text-primary">Time-Bound Security Override</span>
                <span>
                  Granted scopes allow the selected encoder to view and edit requisitions within the assigned CENCOM
                  groups until expiration.
                </span>
              </div>

              <div>
                <label className="block font-bold text-text-primary mb-1.5">
                  Select Encoder *
                </label>
                <select
                  required
                  value={selectedUserId}
                  onChange={(e) => setSelectedUserId(e.target.value)}
                  className="w-full text-xs px-3 py-2 border border-border-default rounded-xl bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary"
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
                <label className="block font-bold text-text-primary mb-1.5">
                  Select CENCOM Group(s) *
                </label>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 border border-border-default p-3 rounded-xl max-h-40 overflow-y-auto bg-surface-subtle">
                  {(encodersAndGroups?.groups ?? []).map((grp) => {
                    const checked = selectedGroups.includes(grp.groupName);
                    return (
                      <button
                        type="button"
                        key={grp.id}
                        onClick={() => handleToggleGroup(grp.groupName)}
                        className={`px-2.5 py-1.5 text-xs text-left rounded-lg border transition-all flex items-center justify-between cursor-pointer ${
                          checked
                            ? "bg-brand-50 border-brand-primary text-brand-900 font-bold"
                            : "bg-surface-primary border-border-default text-text-secondary hover:border-brand-primary"
                        }`}
                      >
                        <span className="truncate">{grp.groupName}</span>
                        {checked && <CheckCircle2 className="w-3.5 h-3.5 text-brand-primary shrink-0 ml-1" />}
                      </button>
                    );
                  })}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block font-bold text-text-primary mb-1.5">
                    Duration Window *
                  </label>
                  <select
                    value={expiryDays}
                    onChange={(e) => setExpiryDays(Number(e.target.value))}
                    className="w-full text-xs px-3 py-2 border border-border-default rounded-xl bg-surface-primary text-text-primary focus:outline-hidden focus:border-brand-primary"
                  >
                    <option value={1}>1 Day (24 hours)</option>
                    <option value={3}>3 Days</option>
                    <option value={7}>7 Days (1 Week)</option>
                    <option value={14}>14 Days (2 Weeks)</option>
                    <option value={30}>30 Days (1 Month)</option>
                  </select>
                </div>
                <div>
                  <label className="block font-bold text-text-primary mb-1.5">
                    Notification
                  </label>
                  <div className="flex items-center gap-2 h-9 px-3 border border-border-default rounded-xl bg-surface-subtle text-text-secondary">
                    <CheckCircle2 className="w-4 h-4 text-text-primary" />
                    <span>In-app banner alert</span>
                  </div>
                </div>
              </div>

              <div>
                <label className="block font-bold text-text-primary mb-1.5">
                  Business Reason / Purpose
                </label>
                <textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g., Covering for absent encoder during payroll cutoff period..."
                  rows={2}
                  className="w-full text-xs px-3 py-2 border border-border-default rounded-xl bg-surface-primary text-text-primary placeholder:text-text-muted focus:outline-hidden focus:border-brand-primary"
                />
              </div>

              {formError && (
                <div className="p-3 rounded-xl bg-danger-surface border border-danger-border text-xs text-danger-text">
                  {formError}
                </div>
              )}

              <div className="flex justify-end gap-2 pt-2 border-t border-border-default">
                <button
                  type="button"
                  onClick={() => setActiveTab("active")}
                  className="px-3.5 py-2 text-xs font-semibold text-text-secondary bg-surface-primary border border-border-default rounded-xl hover:bg-surface-hover cursor-pointer"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={grantMutation.isPending}
                  className="px-4 py-2 text-xs font-semibold text-surface-primary bg-brand-primary hover:bg-brand-primary-hover rounded-xl shadow-2xs transition-colors flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
                >
                  {grantMutation.isPending && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                  <span>Confirm & Grant Access</span>
                </button>
              </div>
            </form>
          ) : activeTab === "active" ? (
            /* Active Overrides Stream */
            <div className="space-y-3">
              {isLoading ? (
                <div className="py-12 text-center text-xs text-text-muted">Loading active overrides...</div>
              ) : activeList.length === 0 ? (
                <div className="py-12 text-center border border-dashed border-border-default rounded-2xl">
                  <Key className="w-8 h-8 text-text-muted mx-auto mb-2" />
                  <p className="text-sm font-semibold text-text-primary">No active temporary overrides</p>
                  <p className="text-xs text-text-muted mt-0.5">
                    All encoders currently operate under standard permanent role scopes.
                  </p>
                </div>
              ) : (
                activeList.map((item) => (
                  <div
                    key={item.id}
                    className="p-4 rounded-xl border border-border-default bg-surface-primary hover:border-brand-primary transition-all shadow-2xs space-y-2.5"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-sm text-text-primary">{item.userFullName}</span>
                          <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-surface-subtle text-text-secondary border border-border-default">
                            {item.userRole}
                          </span>
                        </div>
                        <p className="text-xs text-text-muted mt-0.5">
                          Granted by <span className="font-medium text-text-secondary">{item.grantedBy}</span>
                        </p>
                      </div>

                      {canManage && (
                        <button
                          type="button"
                          onClick={() => handleRevoke(item)}
                          disabled={revokeMutation.isPending}
                          className="px-2.5 py-1 text-xs font-semibold text-danger-text bg-danger-surface hover:bg-danger-border/30 rounded-lg border border-danger-border flex items-center gap-1 transition-colors cursor-pointer disabled:opacity-50"
                        >
                          <Trash2 className="w-3 h-3" />
                          <span>Revoke</span>
                        </button>
                      )}
                    </div>

                    <div className="flex flex-wrap items-center gap-1.5 pt-1">
                      <span className="text-xs text-text-muted">Groups:</span>
                      {item.additionalGroups.map((grp) => (
                        <span
                          key={grp}
                          className="px-2 py-0.5 rounded-md text-xs font-semibold bg-surface-subtle text-text-primary border border-border-default"
                        >
                          {grp}
                        </span>
                      ))}
                    </div>

                    {item.reason && (
                      <p className="text-xs text-text-secondary bg-surface-subtle p-2 rounded-lg italic border border-border-default">
                        “{item.reason}”
                      </p>
                    )}

                    <div className="flex items-center justify-between text-xs text-text-secondary pt-1 border-t border-border-subtle">
                      <span className="flex items-center gap-1">
                        <Clock className="w-3 h-3 text-text-muted" />
                        Expires {new Date(item.expiresAt).toLocaleString()}
                      </span>
                      <span className="font-semibold text-text-primary">Active</span>
                    </div>
                  </div>
                ))
              )}
            </div>
          ) : (
            /* History Log Stream */
            <div className="space-y-3">
              {isLoading ? (
                <div className="py-12 text-center text-xs text-text-muted">Loading history...</div>
              ) : historyList.length === 0 ? (
                <div className="py-12 text-center text-xs text-text-muted border border-dashed border-border-default rounded-2xl">
                  No past override records found.
                </div>
              ) : (
                historyList.map((item) => (
                  <div
                    key={item.id}
                    className="p-3.5 rounded-xl border border-border-default bg-surface-subtle text-xs space-y-1.5"
                  >
                    <div className="flex items-center justify-between">
                      <span className="font-semibold text-sm text-text-primary">{item.userFullName}</span>
                      <span className="px-2 py-0.5 rounded-full text-xs font-semibold bg-surface-primary border border-border-default text-text-secondary">
                        {item.revokedBy ? "Revoked" : "Expired"}
                      </span>
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {item.additionalGroups.map((g) => (
                        <span key={g} className="px-1.5 py-0.2 rounded text-xs bg-surface-primary border border-border-default text-text-secondary">
                          {g}
                        </span>
                      ))}
                    </div>
                    <div className="text-xs text-text-muted flex items-center justify-between pt-1">
                      <span>Created {new Date(item.createdAt).toLocaleDateString()}</span>
                      {item.revokedBy && <span>Revoked by {item.revokedBy}</span>}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
