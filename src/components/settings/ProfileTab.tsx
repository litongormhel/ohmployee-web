"use client";

import { useState, useRef } from "react";
import Image from "next/image";
import {
  Camera,
  Trash2,
  Upload,
  User as UserIcon,
  Phone,
  Mail,
  Shield,
  Layers,
  Building,
  KeyRound,
  Check,
  AlertCircle,
  Loader2,
} from "lucide-react";
import {
  useOwnProfile,
  uploadOwnAvatar,
  deleteOwnAvatar,
  useUpdateOwnProfile,
} from "@/lib/queries/settings";
import { ChangePasswordModal } from "./ChangePasswordModal";
import { StatusBadge } from "@/components/ui/StatusBadge";

export function ProfileTab() {
  const { data: profile, isLoading, error, refetch } = useOwnProfile();
  const updateProfileMutation = useUpdateOwnProfile();

  const [editedMobileNumber, setEditedMobileNumber] = useState<string | null>(null);
  const [mobileError, setMobileError] = useState<string | null>(null);
  const [saveSuccess, setSaveSuccess] = useState(false);

  const [isUploadingAvatar, setIsUploadingAvatar] = useState(false);
  const [isDeletingAvatar, setIsDeletingAvatar] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);

  const [isPasswordModalOpen, setIsPasswordModalOpen] = useState(false);
  const [passwordSuccessToast, setPasswordSuccessToast] = useState(false);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const mobileNumber = editedMobileNumber ?? profile?.mobileNumber ?? "";

  // Philippine Mobile Number Regex: 11 digits starting with 09
  const PH_MOBILE_REGEX = /^09[0-9]{9}$/;

  const validateMobile = (val: string): boolean => {
    if (!val || val.trim().length === 0) {
      setMobileError(null);
      return true; // Optional/nullable
    }
    const clean = val.trim();
    if (!PH_MOBILE_REGEX.test(clean)) {
      setMobileError("Mobile number must be 11 digits starting with '09' (e.g. 09171234567)");
      return false;
    }
    setMobileError(null);
    return true;
  };

  const handleMobileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value.replace(/[^0-9]/g, "").slice(0, 11);
    setEditedMobileNumber(val);
    validateMobile(val);
  };

  const handleSaveMobile = async () => {
    if (!validateMobile(mobileNumber)) return;

    try {
      setSaveSuccess(false);
      await updateProfileMutation.mutateAsync({
        mobileNumber: mobileNumber.trim() || null,
        avatarPath: profile?.avatarPath,
      });
      setEditedMobileNumber(null);
      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 3000);
    } catch (err: unknown) {
      const msg = (err as { message?: string })?.message ?? "Failed to save profile.";
      setMobileError(msg);
    }
  };

  const handleFileSelected = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    // Validate size before upload
    if (file.size > 5 * 1024 * 1024) {
      setAvatarError("Selected file must be smaller than 5 MB.");
      return;
    }

    setIsUploadingAvatar(true);
    setAvatarError(null);

    try {
      await uploadOwnAvatar(file, profile?.mobileNumber);
      await refetch();
    } catch (err: unknown) {
      const msg = (err as { message?: string })?.message ?? "Failed to upload avatar.";
      setAvatarError(msg);
    } finally {
      setIsUploadingAvatar(false);
      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
    }
  };

  const handleDeleteAvatar = async () => {
    if (!profile?.avatarPath) return;

    if (!confirm("Are you sure you want to remove your profile photo?")) {
      return;
    }

    setIsDeletingAvatar(true);
    setAvatarError(null);

    try {
      await deleteOwnAvatar(profile?.mobileNumber);
      await refetch();
    } catch (err: unknown) {
      const msg = (err as { message?: string })?.message ?? "Failed to remove avatar.";
      setAvatarError(msg);
    } finally {
      setIsDeletingAvatar(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <div className="flex items-center gap-2 text-sm text-text-secondary">
          <Loader2 className="h-5 w-5 animate-spin text-brand-primary" />
          <span>Loading profile information...</span>
        </div>
      </div>
    );
  }

  if (error || !profile) {
    return (
      <div className="rounded-xl border border-danger-border bg-danger-subtle p-6 text-center">
        <AlertCircle className="mx-auto h-8 w-8 text-danger" />
        <h3 className="mt-2 text-sm font-semibold text-danger">
          Could not load profile
        </h3>
        <p className="mt-1 text-xs text-text-muted">
          {(error as Error)?.message || "Profile data is unavailable."}
        </p>
        <button
          onClick={() => refetch()}
          className="mt-4 rounded-lg bg-danger-button px-3.5 py-1.5 text-xs font-medium text-danger-button-text hover:bg-danger-button-hover cursor-pointer"
        >
          Try Again
        </button>
      </div>
    );
  }

  // Get initials for avatar fallback
  const getInitials = (name: string) => {
    const parts = name.trim().split(/\s+/);
    if (parts.length >= 2) {
      return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
    }
    return parts[0]?.[0]?.toUpperCase() ?? "U";
  };

  const initials = getInitials(profile.fullName);
  const isDirty = (profile.mobileNumber ?? "") !== mobileNumber;

  return (
    <div className="space-y-6">
      {/* Success Banner for Password Update */}
      {passwordSuccessToast && (
        <div className="flex items-center justify-between rounded-xl border border-border-default bg-surface-subtle px-4 py-3 text-sm text-text-primary">
          <div className="flex items-center gap-2">
            <Check className="h-4 w-4 text-brand-primary" />
            <span>Password updated successfully!</span>
          </div>
          <button
            onClick={() => setPasswordSuccessToast(false)}
            className="text-xs text-text-secondary hover:text-text-primary cursor-pointer"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* Profile Overview Card */}
      <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs">
        <div className="flex flex-col sm:flex-row items-start sm:items-center gap-6">
          {/* Avatar Section */}
          <div className="relative group">
            <div className="relative h-28 w-28 overflow-hidden rounded-full border-4 border-surface-base bg-brand-subtle shadow-xs flex items-center justify-center">
              {profile.signedAvatarUrl ? (
                <Image
                  src={profile.signedAvatarUrl}
                  alt={profile.fullName}
                  fill
                  className="object-cover"
                  unoptimized
                />
              ) : (
                <span className="text-2xl font-bold tracking-wider text-brand-primary">
                  {initials}
                </span>
              )}

              {(isUploadingAvatar || isDeletingAvatar) && (
                <div className="absolute inset-0 flex items-center justify-center bg-[var(--surface-overlay)] text-[var(--foreground)]">
                  <Loader2 className="h-6 w-6 animate-spin" />
                </div>
              )}
            </div>

            {/* Hidden file input */}
            <input
              ref={fileInputRef}
              type="file"
              accept="image/png,image/jpeg,image/webp"
              onChange={handleFileSelected}
              className="hidden"
            />

            {/* Upload Button overlay */}
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              disabled={isUploadingAvatar || isDeletingAvatar}
              className="absolute bottom-0 right-0 flex h-8 w-8 items-center justify-center rounded-full border-2 border-surface-base bg-brand-primary text-text-inverse shadow-xs hover:bg-brand-primary/90 disabled:opacity-50 cursor-pointer"
              title="Change Profile Photo"
            >
              <Camera className="h-4 w-4" />
            </button>
          </div>

          {/* Identity info */}
          <div className="flex-1 space-y-1.5">
            <div className="flex flex-wrap items-center gap-2.5">
              <h2 className="text-xl font-bold text-text-primary">
                {profile.fullName}
              </h2>
              <StatusBadge
                variant="info"
                text={profile.roleName}
              />
              {profile.roleLevel !== null && (
                <span className="inline-flex items-center rounded-md bg-surface-subtle px-2 py-0.5 text-xs font-semibold text-text-secondary border border-border-default">
                  Level {profile.roleLevel}
                </span>
              )}
            </div>
            <p className="flex items-center gap-1.5 text-sm text-text-secondary">
              <Mail className="h-3.5 w-3.5 text-text-muted" />
              <span>{profile.email}</span>
            </p>

            <div className="mt-3 flex flex-wrap items-center gap-2 pt-1">
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={isUploadingAvatar || isDeletingAvatar}
                className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover cursor-pointer"
              >
                <Upload className="h-3.5 w-3.5 text-text-secondary" />
                Upload New Photo
              </button>

              {profile.avatarPath && (
                <button
                  type="button"
                  onClick={handleDeleteAvatar}
                  disabled={isUploadingAvatar || isDeletingAvatar}
                  className="inline-flex items-center gap-1.5 rounded-lg border border-danger-border bg-danger-subtle px-3 py-1.5 text-xs font-semibold text-danger hover:bg-danger-subtle/80 cursor-pointer"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                  Remove Photo
                </button>
              )}

              <button
                type="button"
                onClick={() => setIsPasswordModalOpen(true)}
                className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover ml-auto cursor-pointer"
              >
                <KeyRound className="h-3.5 w-3.5 text-brand-primary" />
                Change Password
              </button>
            </div>

            {avatarError && (
              <p className="mt-2 text-xs text-danger flex items-center gap-1">
                <AlertCircle className="h-3.5 w-3.5" />
                <span>{avatarError}</span>
              </p>
            )}
          </div>
        </div>
      </div>

      {/* Account Details & Contact Card */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Left Card: Account & Scopes (Read-only) */}
        <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs space-y-4">
          <div className="flex items-center gap-2 border-b border-border-default pb-3">
            <Shield className="h-4 w-4 text-brand-primary" />
            <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
              Account & Security Clearance
            </h3>
          </div>

          <div className="space-y-3.5 text-sm">
            <div>
              <label className="text-xs font-medium text-text-secondary">Full Legal Name</label>
              <div className="mt-1 flex items-center gap-2 rounded-lg border border-border-default bg-surface-subtle px-3 py-2 text-text-primary">
                <UserIcon className="h-4 w-4 text-text-muted" />
                <span className="font-medium">{profile.fullName}</span>
              </div>
            </div>

            <div>
              <label className="text-xs font-medium text-text-secondary">Email Address (Read-only)</label>
              <div className="mt-1 flex items-center gap-2 rounded-lg border border-border-default bg-surface-subtle px-3 py-2 text-text-primary">
                <Mail className="h-4 w-4 text-text-muted" />
                <span>{profile.email}</span>
              </div>
            </div>

            <div>
              <label className="text-xs font-medium text-text-secondary">Assigned CENCOM Groups</label>
              <div className="mt-1.5 flex flex-wrap gap-1.5">
                {profile.groups.length > 0 ? (
                  profile.groups.map((group) => (
                    <span
                      key={group}
                      className="inline-flex items-center gap-1 rounded-md bg-brand-subtle px-2 py-0.5 text-xs font-medium text-brand-primary border border-brand-border"
                    >
                      <Layers className="h-3 w-3" />
                      {group}
                    </span>
                  ))
                ) : (
                  <span className="text-xs text-text-muted italic">Global or Unassigned</span>
                )}
              </div>
            </div>

            <div>
              <label className="text-xs font-medium text-text-secondary">Assigned Accounts</label>
              <div className="mt-1.5 flex flex-wrap gap-1.5">
                {profile.accounts.length > 0 ? (
                  profile.accounts.map((acc) => (
                    <span
                      key={acc}
                      className="inline-flex items-center gap-1 rounded-md bg-surface-subtle px-2 py-0.5 text-xs font-medium text-text-secondary border border-border-default"
                    >
                      <Building className="h-3 w-3" />
                      {acc}
                    </span>
                  ))
                ) : (
                  <span className="text-xs text-text-muted italic">All Accounts Authorized</span>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Right Card: Contact Details (Editable) */}
        <div className="rounded-xl border border-border-default bg-surface-base p-6 shadow-2xs space-y-4 flex flex-col justify-between">
          <div>
            <div className="flex items-center gap-2 border-b border-border-default pb-3">
              <Phone className="h-4 w-4 text-brand-primary" />
              <h3 className="text-sm font-semibold uppercase tracking-wider text-text-primary">
                Self-Service Contact Details
              </h3>
            </div>

            <div className="mt-4 space-y-3">
              <div>
                <label className="block text-xs font-medium text-text-secondary">
                  Philippine Mobile Contact Number
                </label>
                <div className="mt-1 relative">
                  <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-text-muted text-sm">
                    🇵🇭 +63
                  </div>
                  <input
                    type="tel"
                    value={mobileNumber}
                    onChange={handleMobileChange}
                    placeholder="09171234567"
                    maxLength={11}
                    className="w-full rounded-lg border border-border-default bg-surface-base pl-18 pr-3.5 py-2 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-default focus:outline-hidden focus:ring-1 focus:ring-brand-default font-mono"
                  />
                </div>
                <p className="mt-1.5 text-xs text-text-muted">
                  Standard Philippine format: 11 digits starting with <code className="font-mono">09</code>.
                </p>
                {mobileError && (
                  <p className="mt-1 text-xs text-danger flex items-center gap-1">
                    <AlertCircle className="h-3.5 w-3.5" />
                    <span>{mobileError}</span>
                  </p>
                )}
                {saveSuccess && (
                  <p className="mt-1 text-xs text-brand-primary flex items-center gap-1 font-medium">
                    <Check className="h-3.5 w-3.5" />
                    <span>Contact details updated successfully!</span>
                  </p>
                )}
              </div>
            </div>
          </div>

          <div className="border-t border-border-default pt-4 flex items-center justify-between">
            <span className="text-xs text-text-muted">
              {isDirty ? "Unsaved changes detected" : "All changes saved"}
            </span>
            <button
              type="button"
              onClick={handleSaveMobile}
              disabled={!isDirty || !!mobileError || updateProfileMutation.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-brand-primary px-4 py-2 text-sm font-semibold text-text-inverse shadow-xs hover:bg-brand-primary/90 disabled:cursor-not-allowed disabled:opacity-50 cursor-pointer"
            >
              {updateProfileMutation.isPending ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  <span>Saving...</span>
                </>
              ) : (
                <>
                  <Check className="h-4 w-4" />
                  <span>Save Changes</span>
                </>
              )}
            </button>
          </div>
        </div>
      </div>

      {/* Change Password Modal */}
      <ChangePasswordModal
        isOpen={isPasswordModalOpen}
        onClose={() => setIsPasswordModalOpen(false)}
        onSuccess={() => {
          setPasswordSuccessToast(true);
          setTimeout(() => setPasswordSuccessToast(false), 5000);
        }}
      />
    </div>
  );
}
