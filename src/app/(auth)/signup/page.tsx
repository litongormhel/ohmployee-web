"use client";

import { useMemo, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import {
  AlertCircle,
  ArrowLeft,
  Building2,
  CheckCircle2,
  Eye,
  EyeOff,
  Lock,
  Mail,
  Phone,
  Shield,
  User,
  UserX,
  Users,
} from "lucide-react";
import {
  submitAccountRequest,
  useSignupOptions,
} from "@/lib/queries/signup";

export default function SignUpPage() {
  const { data: options, isLoading: isLoadingOptions, error: optionsError } = useSignupOptions();

  // Form states
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [middleName, setMiddleName] = useState("");
  const [email, setEmail] = useState("");
  const [mobileNumber, setMobileNumber] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);

  // Role and scope states
  const [selectedRoleId, setSelectedRoleId] = useState("");
  const [selectedGroupIds, setSelectedGroupIds] = useState<string[]>([]);
  const [selectedAccountIds, setSelectedAccountIds] = useState<string[]>([]);
  const [notes, setNotes] = useState("");

  // Status and feedback
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isSuccess, setIsSuccess] = useState(false);

  const isRegistrationEnabled = options?.is_registration_enabled ?? true;

  // Selected role metadata
  const roles = options?.roles;
  const selectedRole = useMemo(() => {
    return roles?.find((r) => r.id === selectedRoleId);
  }, [roles, selectedRoleId]);

  const selectedRoleName = selectedRole?.role_name?.toLowerCase() || "";
  const isRecruitment = selectedRoleName.includes("recruitment");
  const requiresAccounts =
    selectedRoleName.includes("hrco") ||
    selectedRoleName.includes("recruitment") ||
    selectedRoleName.includes("atl") ||
    selectedRoleName.includes("tl") ||
    selectedRoleName === "hr coordinator";

  // Filter accounts belonging to selected group(s)
  const accounts = options?.accounts;
  const filteredAccounts = useMemo(() => {
    if (!accounts || selectedGroupIds.length === 0) return [];
    return accounts.filter((acc) =>
      selectedGroupIds.includes(acc.group_id)
    );
  }, [accounts, selectedGroupIds]);

  const handleRoleChange = (roleId: string) => {
    setSelectedRoleId(roleId);
    setSelectedGroupIds([]);
    setSelectedAccountIds([]);
  };

  const handleGroupToggle = (groupId: string) => {
    if (isRecruitment) {
      // Multiple groups allowed for Recruitment
      setSelectedGroupIds((prev) =>
        prev.includes(groupId) ? prev.filter((id) => id !== groupId) : [...prev, groupId]
      );
    } else {
      // Exactly one group for all other roles
      setSelectedGroupIds([groupId]);
    }
    // Prune accounts that no longer belong to selected groups
    setSelectedAccountIds((prev) =>
      prev.filter((accId) => {
        const acc = options?.accounts.find((a) => a.id === accId);
        return acc && (isRecruitment ? [...selectedGroupIds, groupId].includes(acc.group_id) : acc.group_id === groupId);
      })
    );
  };

  const handleAccountToggle = (accountId: string) => {
    setSelectedAccountIds((prev) =>
      prev.includes(accountId)
        ? prev.filter((id) => id !== accountId)
        : [...prev, accountId]
    );
  };

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setError(null);

    if (!isRegistrationEnabled) {
      setError("Account sign-up is currently disabled by administrator.");
      return;
    }

    if (!firstName.trim() || !lastName.trim()) {
      setError("First and last names are required.");
      return;
    }

    if (password.length < 6) {
      setError("Password must be at least 6 characters long.");
      return;
    }

    if (password !== confirmPassword) {
      setError("Passwords do not match. Please verify your password entry.");
      return;
    }

    if (!selectedRoleId) {
      setError("Please select your requested role.");
      return;
    }

    if (selectedGroupIds.length === 0) {
      setError("Please select at least one assigned group scope.");
      return;
    }

    if (requiresAccounts && selectedAccountIds.length === 0) {
      setError("This role requires at least one account assignment.");
      return;
    }

    setIsSubmitting(true);

    try {
      await submitAccountRequest({
        email: email.trim(),
        password,
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        middleName: middleName.trim() || undefined,
        mobileNumber: mobileNumber.trim() || undefined,
        requestedRoleId: selectedRoleId,
        groupIds: selectedGroupIds,
        accountIds: requiresAccounts ? selectedAccountIds : [],
        notes: notes.trim() || undefined,
      });

      setIsSuccess(true);
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message.replace("Exception: ", "")
          : "Failed to submit account request."
      );
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="relative min-h-screen flex flex-col items-center justify-center bg-background px-4 py-12 overflow-x-hidden">
      {/* Ambient background glows */}
      <div className="absolute top-1/4 left-1/4 -translate-x-1/2 -translate-y-1/2 w-80 h-80 rounded-full bg-brand-500/10 blur-[100px] pointer-events-none" />
      <div className="absolute bottom-1/4 right-1/4 translate-x-1/2 translate-y-1/2 w-96 h-96 rounded-full bg-brand-600/10 blur-[120px] pointer-events-none" />

      <div className="w-full max-w-xl z-10 space-y-6">
        {/* Brand Header */}
        <div className="flex flex-col items-center space-y-2 text-center">
          <div className="h-16 w-16 flex items-center justify-center transition-transform hover:scale-105 duration-200">
            <Image
              src="/images/ohm_logo_transparent.png"
              alt="OHMployee Logo"
              width={64}
              height={64}
              priority
              className="h-16 w-16 object-contain drop-shadow-sm select-none"
            />
          </div>
          <h1 className="text-2xl font-extrabold tracking-tight text-text-primary">
            OHMployee
          </h1>
          <p className="text-xs text-text-secondary">
            Workforce Operations Platform
          </p>
        </div>

        {/* Card Container */}
        <div className="bg-surface-base border border-border-default rounded-2xl shadow-xl p-6 sm:p-8 space-y-6 backdrop-blur-md">
          {/* Sign-Up Disabled Notice */}
          {!isRegistrationEnabled ? (
            <div className="space-y-5 text-center py-4">
              <div className="w-14 h-14 bg-rose-500/10 text-rose-600 rounded-full flex items-center justify-center mx-auto border border-rose-500/20">
                <UserX className="w-7 h-7" />
              </div>
              <div className="space-y-1.5">
                <h2 className="text-xl font-bold text-text-primary">
                  Account Sign-Up is Paused
                </h2>
                <p className="text-xs text-text-secondary leading-relaxed max-w-md mx-auto">
                  New user registrations are currently disabled by system administrators.
                  If you need an account to perform field or operational duties, please contact your
                  Operations Manager or Super Admin directly.
                </p>
              </div>

              <div className="pt-2">
                <Link
                  href="/login"
                  className="w-full h-11 inline-flex items-center justify-center rounded-lg bg-brand-600 text-white font-medium text-sm transition-all hover:bg-brand-700 shadow-md shadow-brand-600/10 cursor-pointer"
                >
                  Return to Sign In
                </Link>
              </div>
            </div>
          ) : isSuccess ? (
            /* Success Confirmation Screen */
            <div className="space-y-5 text-center py-4">
              <div className="w-14 h-14 bg-emerald-500/10 text-emerald-600 rounded-full flex items-center justify-center mx-auto border border-emerald-500/20">
                <CheckCircle2 className="w-7 h-7" />
              </div>
              <div className="space-y-1.5">
                <h2 className="text-xl font-bold text-text-primary">
                  Account Request Submitted!
                </h2>
                <p className="text-xs text-text-secondary leading-relaxed max-w-md mx-auto">
                  Your registration request for <strong className="text-text-primary font-semibold">{email}</strong> has
                  been submitted to the administration team. An administrator will review your requested role and verify your
                  group allocations before activating your account.
                </p>
              </div>

              <div className="p-3.5 bg-surface-subtle border border-border-default rounded-xl text-xs text-text-muted text-left space-y-1">
                <div className="flex justify-between">
                  <span>Requested Role:</span>
                  <span className="font-semibold text-text-primary">{selectedRole?.role_name}</span>
                </div>
                <div className="flex justify-between">
                  <span>Groups:</span>
                  <span className="font-semibold text-text-primary">{selectedGroupIds.length} assigned</span>
                </div>
                {requiresAccounts && (
                  <div className="flex justify-between">
                    <span>Accounts:</span>
                    <span className="font-semibold text-text-primary">{selectedAccountIds.length} assigned</span>
                  </div>
                )}
              </div>

              <div className="pt-2">
                <Link
                  href="/login"
                  className="w-full h-11 inline-flex items-center justify-center rounded-lg bg-brand-600 text-white font-medium text-sm transition-all hover:bg-brand-700 shadow-md shadow-brand-600/10 cursor-pointer"
                >
                  Back to Sign In
                </Link>
              </div>
            </div>
          ) : (
            /* Registration Form */
            <>
              <div>
                <h2 className="text-xl font-bold text-text-primary">
                  Request an Account
                </h2>
                <p className="text-xs text-text-secondary mt-1">
                  Fill in your details and operational role to submit a registration request.
                </p>
              </div>

              {error && (
                <div className="flex items-center gap-3 rounded-lg border border-status-danger-border bg-status-danger-bg p-3.5 text-sm text-status-danger-text">
                  <AlertCircle className="h-5 w-5 shrink-0" />
                  <span>{error}</span>
                </div>
              )}

              {optionsError && (
                <div className="flex items-center gap-3 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-800 dark:text-amber-300">
                  <AlertCircle className="h-4 w-4 shrink-0" />
                  <span>Unable to refresh dynamic scopes. Standard defaults are loaded.</span>
                </div>
              )}

              <form onSubmit={handleSubmit} className="space-y-5">
                {/* Section 1: Personal Details */}
                <div className="space-y-3">
                  <span className="text-xs font-bold text-text-secondary uppercase tracking-wider flex items-center gap-1.5">
                    <User className="w-3.5 h-3.5 text-brand-primary" />
                    <span>Personal Information</span>
                  </span>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div className="space-y-1">
                      <label className="text-xs font-semibold text-text-secondary">
                        First Name <span className="text-danger-text">*</span>
                      </label>
                      <input
                        required
                        type="text"
                        placeholder="Juan"
                        value={firstName}
                        onChange={(e) => setFirstName(e.target.value)}
                        className="h-10 w-full rounded-lg border border-border-default bg-surface-muted px-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                      />
                    </div>

                    <div className="space-y-1">
                      <label className="text-xs font-semibold text-text-secondary">
                        Last Name <span className="text-danger-text">*</span>
                      </label>
                      <input
                        required
                        type="text"
                        placeholder="Dela Cruz"
                        value={lastName}
                        onChange={(e) => setLastName(e.target.value)}
                        className="h-10 w-full rounded-lg border border-border-default bg-surface-muted px-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                      />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div className="space-y-1">
                      <label className="text-xs font-semibold text-text-secondary">
                        Middle Name <span className="text-text-muted font-normal">(Optional)</span>
                      </label>
                      <input
                        type="text"
                        placeholder="Santos"
                        value={middleName}
                        onChange={(e) => setMiddleName(e.target.value)}
                        className="h-10 w-full rounded-lg border border-border-default bg-surface-muted px-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                      />
                    </div>

                    <div className="space-y-1">
                      <label className="text-xs font-semibold text-text-secondary">
                        Mobile Number <span className="text-text-muted font-normal">(Optional)</span>
                      </label>
                      <div className="relative">
                        <div className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-muted">
                          <Phone className="h-4 w-4" />
                        </div>
                        <input
                          type="tel"
                          placeholder="09171234567"
                          value={mobileNumber}
                          onChange={(e) => setMobileNumber(e.target.value)}
                          className="h-10 w-full rounded-lg border border-border-default bg-surface-muted pl-9 pr-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                        />
                      </div>
                    </div>
                  </div>
                </div>

                {/* Section 2: Account Credentials */}
                <div className="space-y-3 pt-1 border-t border-border-subtle">
                  <span className="text-xs font-bold text-text-secondary uppercase tracking-wider flex items-center gap-1.5 pt-2">
                    <Mail className="w-3.5 h-3.5 text-brand-primary" />
                    <span>Account Credentials</span>
                  </span>

                  <div className="space-y-1">
                    <label className="text-xs font-semibold text-text-secondary">
                      Work Email Address <span className="text-danger-text">*</span>
                    </label>
                    <div className="relative">
                      <div className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-muted">
                        <Mail className="h-4 w-4" />
                      </div>
                      <input
                        required
                        type="email"
                        placeholder="juan.delacruz@company.com"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        className="h-10 w-full rounded-lg border border-border-default bg-surface-muted pl-9 pr-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                      />
                    </div>
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div className="space-y-1">
                      <label className="text-xs font-semibold text-text-secondary">
                        Password <span className="text-danger-text">*</span>
                      </label>
                      <div className="relative">
                        <div className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-muted">
                          <Lock className="h-4 w-4" />
                        </div>
                        <input
                          required
                          type={showPassword ? "text" : "password"}
                          placeholder="At least 6 chars"
                          value={password}
                          onChange={(e) => setPassword(e.target.value)}
                          className="h-10 w-full rounded-lg border border-border-default bg-surface-muted pl-9 pr-9 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                        />
                        <button
                          type="button"
                          onClick={() => setShowPassword(!showPassword)}
                          className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-secondary"
                        >
                          {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                        </button>
                      </div>
                    </div>

                    <div className="space-y-1">
                      <label className="text-xs font-semibold text-text-secondary">
                        Confirm Password <span className="text-danger-text">*</span>
                      </label>
                      <div className="relative">
                        <div className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-muted">
                          <Lock className="h-4 w-4" />
                        </div>
                        <input
                          required
                          type={showConfirm ? "text" : "password"}
                          placeholder="Repeat password"
                          value={confirmPassword}
                          onChange={(e) => setConfirmPassword(e.target.value)}
                          className="h-10 w-full rounded-lg border border-border-default bg-surface-muted pl-9 pr-9 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                        />
                        <button
                          type="button"
                          onClick={() => setShowConfirm(!showConfirm)}
                          className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-secondary"
                        >
                          {showConfirm ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                        </button>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Section 3: Role & Scope Selection */}
                <div className="space-y-3 pt-1 border-t border-border-subtle">
                  <span className="text-xs font-bold text-text-secondary uppercase tracking-wider flex items-center gap-1.5 pt-2">
                    <Shield className="w-3.5 h-3.5 text-brand-primary" />
                    <span>Role & Scope Allocation</span>
                  </span>

                  <div className="space-y-1">
                    <label className="text-xs font-semibold text-text-secondary">
                      Requested Role <span className="text-danger-text">*</span>
                    </label>
                    <select
                      required
                      value={selectedRoleId}
                      onChange={(e) => handleRoleChange(e.target.value)}
                      className="h-10 w-full rounded-lg border border-border-default bg-surface-muted px-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
                    >
                      <option value="">-- Select Requested Role --</option>
                      {options?.roles.map((r) => (
                        <option key={r.id} value={r.id}>
                          {r.role_name}
                        </option>
                      ))}
                    </select>
                  </div>

                  {/* Group Selection */}
                  {selectedRoleId && (
                    <div className="space-y-2">
                      <div className="flex items-center justify-between">
                        <label className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                          <Users className="w-3.5 h-3.5 text-text-muted" />
                          <span>
                            Assigned Group(s) <span className="text-danger-text">*</span>
                          </span>
                        </label>
                        <span className="text-xs text-text-muted">
                          {isRecruitment ? "Multiple groups allowed" : "Select exactly 1 group"}
                        </span>
                      </div>

                      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                        {options?.groups.map((group) => {
                          const isSelected = selectedGroupIds.includes(group.id);
                          return (
                            <button
                              key={group.id}
                              type="button"
                              onClick={() => handleGroupToggle(group.id)}
                              className={`p-2.5 rounded-lg border text-xs font-semibold text-left transition-all cursor-pointer flex items-center justify-between gap-1.5 ${
                                isSelected
                                  ? "border-brand-500 bg-brand-500/10 text-brand-700 dark:text-brand-300 shadow-2xs font-bold"
                                  : "border-border-default bg-surface-muted text-text-secondary hover:border-border-hover hover:text-text-primary"
                              }`}
                            >
                              <span className="truncate">{group.group_name}</span>
                              {isSelected && <CheckCircle2 className="w-3.5 h-3.5 text-brand-600 shrink-0" />}
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  )}

                  {/* Account Selection (Conditional) */}
                  {requiresAccounts && selectedGroupIds.length > 0 && (
                    <div className="space-y-2">
                      <div className="flex items-center justify-between">
                        <label className="text-xs font-semibold text-text-secondary flex items-center gap-1.5">
                          <Building2 className="w-3.5 h-3.5 text-text-muted" />
                          <span>
                            Assigned Accounts <span className="text-danger-text">*</span>
                          </span>
                        </label>
                        <span className="text-xs text-text-muted">
                          {selectedAccountIds.length} selected
                        </span>
                      </div>

                      {filteredAccounts.length === 0 ? (
                        <div className="p-3 rounded-lg border border-dashed border-border-default text-xs text-text-muted text-center">
                          No active accounts mapped to the selected group(s).
                        </div>
                      ) : (
                        <div className="max-h-36 overflow-y-auto space-y-1 p-2 rounded-lg border border-border-default bg-surface-muted no-scrollbar scrollbar-none">
                          {filteredAccounts.map((account) => {
                            const isSelected = selectedAccountIds.includes(account.id);
                            return (
                              <button
                                key={account.id}
                                type="button"
                                onClick={() => handleAccountToggle(account.id)}
                                className={`w-full p-2 rounded text-xs text-left transition-colors flex items-center justify-between cursor-pointer ${
                                  isSelected
                                    ? "bg-brand-500/10 text-brand-700 dark:text-brand-300 font-semibold"
                                    : "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
                                
                                }`}
                              >
                                <span className="truncate">{account.account_name}</span>
                                {isSelected && <CheckCircle2 className="w-3.5 h-3.5 text-brand-600 shrink-0" />}
                              </button>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  )}

                  {/* Optional Notes */}
                  <div className="space-y-1">
                    <label className="text-xs font-semibold text-text-secondary">
                      Operational Remarks / Justification <span className="text-text-muted font-normal">(Optional)</span>
                    </label>
                    <textarea
                      rows={2}
                      placeholder="e.g., Assigned to Super 8 stores under Bulacan operations cluster."
                      value={notes}
                      onChange={(e) => setNotes(e.target.value)}
                      className="w-full rounded-lg border border-border-default bg-surface-muted p-2.5 text-xs text-text-primary outline-none transition-colors focus:border-brand-500"
                    />
                  </div>
                </div>

                {/* Submit Action */}
                <div className="pt-2">
                  <button
                    type="submit"
                    disabled={isSubmitting || isLoadingOptions}
                    className="w-full h-11 inline-flex items-center justify-center rounded-lg bg-brand-600 text-white font-medium text-sm transition-all hover:bg-brand-700 active:bg-brand-800 disabled:cursor-not-allowed disabled:opacity-50 shadow-md shadow-brand-600/10 cursor-pointer"
                  >
                    {isSubmitting ? (
                      <>
                        <span className="animate-spin mr-2 h-4 w-4 border-2 border-white border-t-transparent rounded-full" />
                        Submitting Request...
                      </>
                    ) : (
                      "Submit Account Request"
                    )}
                  </button>
                </div>
              </form>

              {/* Back to Login Link */}
              <div className="text-center pt-2">
                <Link
                  href="/login"
                  className="inline-flex items-center gap-1.5 text-xs font-semibold text-brand-600 hover:text-brand-700 transition-colors"
                >
                  <ArrowLeft className="w-3.5 h-3.5" />
                  <span>Already have an account? Sign In</span>
                </Link>
              </div>
            </>
          )}
        </div>

        <div className="text-center text-xs text-text-muted">
          &copy; {new Date().getFullYear()} OHMployee. All rights reserved.
        </div>
      </div>
    </div>
  );
}
