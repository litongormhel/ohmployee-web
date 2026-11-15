"use client";

import { useState } from "react";
import { Eye, EyeOff, Lock, CheckCircle2, AlertCircle } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { createClient } from "@/lib/supabase/client";

interface ChangePasswordModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export function ChangePasswordModal({
  isOpen,
  onClose,
  onSuccess,
}: ChangePasswordModalProps) {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Validation criteria
  const hasCurrentPassword = currentPassword.trim().length > 0;
  const hasMinLength = newPassword.length >= 8;
  const hasLetter = /[a-zA-Z]/.test(newPassword);
  const hasNumber = /[0-9]/.test(newPassword);
  const passwordsMatch = newPassword.length > 0 && newPassword === confirmPassword;
  const notSameAsCurrent = !currentPassword || newPassword !== currentPassword;
  const isValid = hasCurrentPassword && hasMinLength && hasLetter && hasNumber && passwordsMatch && notSameAsCurrent;
  const isDirty = Boolean(currentPassword || newPassword || confirmPassword);

  const handleModalClose = () => {
    if (isSubmitting) return;
    setCurrentPassword("");
    setNewPassword("");
    setConfirmPassword("");
    setErrorMsg(null);
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isValid) return;

    setIsSubmitting(true);
    setErrorMsg(null);

    try {
      const supabase = createClient();

      // 1. Verify user session & credentials with current password
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        throw new Error("No active user session. Please log in again.");
      }

      const email = user.email;
      const phone = user.phone;

      if (email) {
        const { error: verifyError } = await supabase.auth.signInWithPassword({
          email,
          password: currentPassword,
        });
        if (verifyError) {
          throw new Error("Incorrect current password. Please check and try again.");
        }
      } else if (phone) {
        const { error: verifyError } = await supabase.auth.signInWithPassword({
          phone,
          password: currentPassword,
        });
        if (verifyError) {
          throw new Error("Incorrect current password. Please check and try again.");
        }
      }

      // 2. Safely update to the new password
      const { error: updateError } = await supabase.auth.updateUser({
        password: newPassword,
      });

      if (updateError) {
        throw updateError;
      }

      onSuccess();
      handleModalClose();
    } catch (err: unknown) {
      const msg = (err as { message?: string })?.message ?? "Failed to update password.";
      setErrorMsg(msg);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleModalClose}
      title="Change Account Password"
      subtitle="Verify your current password and set a new password."
      icon={Lock}
      maxWidthClass="max-w-md"
      isSubmitting={isSubmitting}
      disableBackdropClick={isSubmitting}
      isDirty={isDirty}
    >
      <div>
        {errorMsg && (
          <div className="mb-4 flex items-center gap-2 rounded-lg border border-danger-border bg-danger-subtle p-3 text-xs text-danger">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>{errorMsg}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold text-text-secondary">
              Current Password
            </label>
            <div className="relative mt-1">
              <input
                type={showCurrent ? "text" : "password"}
                value={currentPassword}
                onChange={(e) => setCurrentPassword(e.target.value)}
                placeholder="Enter current password"
                className="w-full rounded-lg border border-border-default bg-surface-base px-3.5 py-2 pr-10 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
                required
              />
              <button
                type="button"
                onClick={() => setShowCurrent(!showCurrent)}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary cursor-pointer"
              >
                {showCurrent ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary">
              New Password
            </label>
            <div className="relative mt-1">
              <input
                type={showNew ? "text" : "password"}
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                placeholder="Enter at least 8 characters"
                className="w-full rounded-lg border border-border-default bg-surface-base px-3.5 py-2 pr-10 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
                required
              />
              <button
                type="button"
                onClick={() => setShowNew(!showNew)}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary cursor-pointer"
              >
                {showNew ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-text-secondary">
              Confirm New Password
            </label>
            <div className="relative mt-1">
              <input
                type={showConfirm ? "text" : "password"}
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                placeholder="Re-enter new password"
                className="w-full rounded-lg border border-border-default bg-surface-base px-3.5 py-2 pr-10 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default"
                required
              />
              <button
                type="button"
                onClick={() => setShowConfirm(!showConfirm)}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary cursor-pointer"
              >
                {showConfirm ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>

          {/* Validation criteria pills */}
          <div className="space-y-1.5 rounded-lg border border-border-default bg-surface-muted/50 p-3 text-xs text-text-secondary">
            <div className="flex items-center gap-2">
              <CheckCircle2
                className={`h-3.5 w-3.5 ${hasMinLength ? "text-brand-primary" : "text-text-muted"}`}
              />
              <span className={hasMinLength ? "text-text-primary font-medium" : ""}>
                At least 8 characters
              </span>
            </div>
            <div className="flex items-center gap-2">
              <CheckCircle2
                className={`h-3.5 w-3.5 ${hasLetter && hasNumber ? "text-brand-primary" : "text-text-muted"}`}
              />
              <span className={hasLetter && hasNumber ? "text-text-primary font-medium" : ""}>
                Contains both letters and numbers
              </span>
            </div>
            <div className="flex items-center gap-2">
              <CheckCircle2
                className={`h-3.5 w-3.5 ${passwordsMatch ? "text-brand-primary" : "text-text-muted"}`}
              />
              <span className={passwordsMatch ? "text-text-primary font-medium" : ""}>
                Passwords match
              </span>
            </div>
            {currentPassword && newPassword && currentPassword === newPassword && (
              <div className="flex items-center gap-2 text-danger">
                <AlertCircle className="h-3.5 w-3.5 shrink-0" />
                <span>New password cannot be the same as current password</span>
              </div>
            )}
          </div>

          <div className="mt-6 flex items-center justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={handleModalClose}
              disabled={isSubmitting}
              className="rounded-lg border border-border-default px-4 py-2 text-sm font-medium text-text-secondary hover:bg-surface-hover disabled:opacity-50 cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!isValid || isSubmitting}
              className="inline-flex items-center gap-2 rounded-lg bg-brand-primary px-4 py-2 text-sm font-semibold text-text-inverse shadow-xs hover:bg-brand-primary/90 disabled:cursor-not-allowed disabled:opacity-50 cursor-pointer"
            >
              {isSubmitting ? "Updating..." : "Update Password"}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
