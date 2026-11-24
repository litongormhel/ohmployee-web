"use client";

import { useState } from "react";
import {
  AlertCircle,
  CheckCircle2,
  Clock,
  ShieldCheck,
  UserCheck,
  UserPlus,
  UserX,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { useCurrentUser } from "@/lib/auth";
import {
  useGovernanceControls,
  useUpdateGovernanceControl,
} from "@/lib/queries/more";
import { useQueryClient } from "@tanstack/react-query";

export interface AccountSignupControlModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function AccountSignupControlModal({
  isOpen,
  onClose,
}: AccountSignupControlModalProps) {
  const currentUser = useCurrentUser();
  const queryClient = useQueryClient();
  const { data: govControls = [], isLoading } = useGovernanceControls();
  const updateGovMutation = useUpdateGovernanceControl();

  const registrationControl = govControls.find(
    (c) => c.controlKey === "account_registration"
  );
  const isEnabled = registrationControl ? registrationControl.enabled : true;

  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  const handleToggle = async (targetState: boolean) => {
    if (!currentUser?.profileId) {
      setError("Active administrator session not found.");
      return;
    }

    if (!reason.trim()) {
      setError("Please provide an audited reason for this governance change.");
      return;
    }

    try {
      setError(null);
      await updateGovMutation.mutateAsync({
        controlKey: "account_registration",
        enabled: targetState,
        reason: reason.trim(),
        actorId: currentUser.profileId,
      });

      // Invalidate relevant query keys
      queryClient.invalidateQueries({ queryKey: ["governance-controls"] });
      queryClient.invalidateQueries({ queryKey: ["auth", "account-signup-status"] });
      queryClient.invalidateQueries({ queryKey: ["auth", "signup-options"] });

      setSuccessMessage(
        targetState
          ? "Account sign-up has been successfully enabled."
          : "Account sign-up has been successfully paused/disabled."
      );
      setReason("");
      setTimeout(() => setSuccessMessage(null), 4000);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to update sign-up setting.");
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Account Sign-Up Control"
      subtitle="Manage public registration availability across Web and Mobile with audited tracking."
      icon={UserPlus}
      maxWidthClass="max-w-xl"
      footer={
        <div className="flex w-full items-center justify-between text-xs text-text-muted">
          <span>Admin Tools • Level 100 System Governance</span>
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
      <div className="space-y-5">
        {/* Status Callout Card */}
        <div
          className={`p-4 rounded-2xl border transition-all ${
            isEnabled
              ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-950 dark:text-emerald-200"
              : "bg-rose-500/10 border-rose-500/30 text-rose-950 dark:text-rose-200"
          }`}
        >
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <div
                className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${
                  isEnabled
                    ? "bg-emerald-500 text-white shadow-md shadow-emerald-500/20"
                    : "bg-rose-500 text-white shadow-md shadow-rose-500/20"
                }`}
              >
                {isEnabled ? (
                  <UserCheck className="w-5 h-5" />
                ) : (
                  <UserX className="w-5 h-5" />
                )}
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <h3 className="text-sm font-bold">
                    {isEnabled ? "Sign-Up is ENABLED" : "Sign-Up is DISABLED"}
                  </h3>
                  <span
                    className={`px-2 py-0.5 rounded-full text-xs font-bold uppercase tracking-wider ${
                      isEnabled
                        ? "bg-emerald-500/20 text-emerald-700 dark:text-emerald-300 border border-emerald-500/30"
                        : "bg-rose-500/20 text-rose-700 dark:text-rose-300 border border-rose-500/30"
                    }`}
                  >
                    {isEnabled ? "Active" : "Paused"}
                  </span>
                </div>
                <p className="text-xs text-text-secondary mt-0.5 leading-relaxed">
                  {isEnabled
                    ? "New users can submit account registration requests via the Web and Mobile login screens."
                    : "New registrations are paused system-wide. Public sign-up forms are blocked from submitting."}
                </p>
              </div>
            </div>
          </div>

          {registrationControl && (
            <div className="mt-3 pt-3 border-t border-border-default/40 flex flex-wrap items-center justify-between text-xs text-text-muted gap-2">
              <span className="flex items-center gap-1.5">
                <Clock className="w-3.5 h-3.5" />
                Last updated: {new Date(registrationControl.updatedAt).toLocaleString()}
              </span>
              {registrationControl.updatedByName && (
                <span>By: {registrationControl.updatedByName}</span>
              )}
            </div>
          )}

          {registrationControl?.reason && (
            <p className="mt-2 text-xs italic text-text-secondary bg-surface-base/60 p-2 rounded-lg border border-border-subtle">
              “{registrationControl.reason}”
            </p>
          )}
        </div>

        {/* Feedback Alerts */}
        {error && (
          <div className="p-3 bg-danger-surface border border-danger-border rounded-xl text-xs text-danger-text flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {successMessage && (
          <div className="p-3 bg-emerald-500/10 border border-emerald-500/30 rounded-xl text-xs text-emerald-700 dark:text-emerald-300 flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 shrink-0" />
            <span>{successMessage}</span>
          </div>
        )}

        {/* Action Form */}
        <div className="space-y-3 bg-surface-subtle p-4 rounded-xl border border-border-default">
          <label className="block text-xs font-semibold text-text-secondary">
            Audited Reason for Change <span className="text-danger-text">*</span>
          </label>
          <textarea
            rows={2}
            className="w-full text-xs rounded-lg border border-border-default bg-surface-primary p-2.5 text-text-primary focus:border-brand-primary outline-none transition-colors"
            placeholder={
              isEnabled
                ? "e.g., Pausing registrations during headcount review period..."
                : "e.g., Opening registrations for newly onboarded team coordinators..."
            }
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />

          <div className="pt-2 flex items-center gap-3">
            {isEnabled ? (
              <button
                type="button"
                onClick={() => handleToggle(false)}
                disabled={updateGovMutation.isPending || isLoading}
                className="flex-1 py-2.5 px-4 rounded-xl text-xs font-bold text-white bg-danger-solid hover:opacity-90 disabled:opacity-50 transition-all cursor-pointer shadow-md shadow-danger-solid/10 flex items-center justify-center gap-2"
              >
                {updateGovMutation.isPending ? (
                  <>
                    <span className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                    Updating...
                  </>
                ) : (
                  <>
                    <UserX className="w-4 h-4" />
                    Disable Account Sign-Up
                  </>
                )}
              </button>
            ) : (
              <button
                type="button"
                onClick={() => handleToggle(true)}
                disabled={updateGovMutation.isPending || isLoading}
                className="flex-1 py-2.5 px-4 rounded-xl text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 transition-all cursor-pointer shadow-md shadow-emerald-600/10 flex items-center justify-center gap-2"
              >
                {updateGovMutation.isPending ? (
                  <>
                    <span className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                    Updating...
                  </>
                ) : (
                  <>
                    <UserCheck className="w-4 h-4" />
                    Enable Account Sign-Up
                  </>
                )}
              </button>
            )}
          </div>
        </div>

        {/* Security Info */}
        <div className="p-3 bg-surface-base border border-border-default rounded-xl text-xs text-text-muted flex items-center gap-2">
          <ShieldCheck className="w-4 h-4 text-brand-primary shrink-0" />
          <span>
            Every toggle transition writes an immutable security record to <code>governance_audit_log</code>.
          </span>
        </div>
      </div>
    </Modal>
  );
}
