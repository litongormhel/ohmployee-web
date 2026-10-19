"use client";

import { useState, useMemo } from "react";
import {
  User,
  Shield,
  Layers,
  Store,
  AlertTriangle,
  CheckCircle2,
  Lock,
  Archive,
  Power,
  KeyRound,
  Check,
  Search,
  Clock,
} from "lucide-react";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import type {
  UserProfileItem,
} from "@/lib/queries/users";
import {
  useRolesQuery,
  useGroupsQuery,
  useAccountsByGroupsQuery,
  useUserAuditLogs,
  useUpsertUser,
  useToggleUserStatus,
  useArchiveUser,
  useResetUserPassword,
  useSetHrcoGlobalVisibility,
  friendlyUserError,
  useActiveTempPermissionsQuery,
} from "@/lib/queries/users";
import { useCurrentUser } from "@/lib/auth";
import { TempPermissionModal } from "@/components/users/TempPermissionModal";


export interface UserDetailDrawerProps {
  user: UserProfileItem | null;
  onClose: () => void;
  onSaved?: () => void;
}

export function UserDetailDrawer({ user, onClose, onSaved }: UserDetailDrawerProps) {
  const currentUser = useCurrentUser();
  const currentRoleLevel = useMemo(() => {
    const roleKey = (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
    if (roleKey.includes("super_admin") || roleKey === "super admin") return 100;
    if (roleKey.includes("head_admin") || roleKey === "head admin") return 90;
    return 50;
  }, [currentUser]);

  const isSuperAdmin = currentRoleLevel >= 100;
  const isHeadAdmin = currentRoleLevel >= 90 && currentRoleLevel < 100;
  const isSelf = user?.id === currentUser?.profileId;

  // Active Tab: "overview" | "scope" | "activity"
  const [activeTab, setActiveTab] = useState<"overview" | "scope" | "activity">("overview");

  // Track the previous user id to reset form state when user changes without unmounting
  const [prevUserId, setPrevUserId] = useState<string | null>(null);

  // Form State
  const [selectedRoleId, setSelectedRoleId] = useState<string>("");
  const [selectedGroupIds, setSelectedGroupIds] = useState<string[]>([]);
  const [selectedAccountIds, setSelectedAccountIds] = useState<string[]>([]);
  const [hrcoGlobalVisibility, setHrcoGlobalVisibilityState] = useState<boolean>(false);
  const [accountSearch, setAccountSearch] = useState<string>("");

  // Confirmation Modals State
  const [statusConfirmOpen, setStatusConfirmOpen] = useState(false);
  const [resetPwConfirmOpen, setResetPwConfirmOpen] = useState(false);
  const [archiveConfirmOpen, setArchiveConfirmOpen] = useState(false);
  const [saveDiffConfirmOpen, setSaveDiffConfirmOpen] = useState(false);
  const [tempPermissionModalOpen, setTempPermissionModalOpen] = useState(false);
  const [feedbackNotice, setFeedbackNotice] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // State derivation when user changes:
  if (user && user.id !== prevUserId) {
    setPrevUserId(user.id);
    setSelectedRoleId(user.roleId);
    setSelectedGroupIds([...user.scopedGroupIds]);
    setSelectedAccountIds(
      user.scopes.filter((s) => s.accountId).map((s) => s.accountId as string),
    );
    setHrcoGlobalVisibilityState(user.hrcoGlobalVisibility);
    setActiveTab("overview");
    setFeedbackNotice(null);
  }

  // Queries
  const { data: roles = [] } = useRolesQuery();
  const { data: groups = [] } = useGroupsQuery();
  const { data: accounts = [], isLoading: accountsLoading } = useAccountsByGroupsQuery(selectedGroupIds);
  const { data: auditLogs = [], isLoading: logsLoading } = useUserAuditLogs(user?.id);
  const { data: userTempOverrides = [] } = useActiveTempPermissionsQuery(user?.id);
  const activeTempOverride = userTempOverrides[0];

  // Mutations
  const upsertMutation = useUpsertUser();
  const toggleStatusMutation = useToggleUserStatus();
  const archiveMutation = useArchiveUser();
  const resetPasswordMutation = useResetUserPassword();
  const hrcoVisibilityMutation = useSetHrcoGlobalVisibility();

  // Head admin target locked if target is Super Admin or Head Admin
  const isTargetLocked = useMemo(() => {
    if (!user) return false;
    if (isHeadAdmin && (user.roleName === "Super Admin" || user.roleName === "Head Admin")) {
      return true;
    }
    return false;
  }, [user, isHeadAdmin]);

  // Assignable roles based on current caller's level
  const assignableRoles = useMemo(() => {
    if (isSuperAdmin) return roles;
    if (isHeadAdmin) {
      return roles.filter((r) => r.name !== "Super Admin" && r.name !== "Head Admin");
    }
    return [];
  }, [roles, isSuperAdmin, isHeadAdmin]);

  const isGlobalHQSelected = useMemo(() => {
    return selectedGroupIds.some((gid) => {
      const g = groups.find((group) => group.id === gid);
      return g?.name.trim().toLowerCase() === "global hq";
    });
  }, [selectedGroupIds, groups]);

  const targetRole = useMemo(() => {
    return roles.find((r) => r.id === selectedRoleId) || { name: user?.roleName || "No Role" };
  }, [roles, selectedRoleId, user]);

  const isHrcoRole = targetRole.name === "HRCO";

  // Detect has editable changes
  const hasEditableChanges = useMemo(() => {
    if (!user) return false;

    const initialGroups = [...user.scopedGroupIds].sort();
    const currentGroups = [...selectedGroupIds].sort();
    const groupsChanged = JSON.stringify(initialGroups) !== JSON.stringify(currentGroups);

    const initialAccounts = user.scopes
      .filter((s) => s.accountId)
      .map((s) => s.accountId as string)
      .sort();
    const currentAccounts = isGlobalHQSelected ? [] : [...selectedAccountIds].sort();
    const accountsChanged = JSON.stringify(initialAccounts) !== JSON.stringify(currentAccounts);

    const roleChanged = selectedRoleId !== user.roleId;
    const hrcoChanged = isHrcoRole && hrcoGlobalVisibility !== user.hrcoGlobalVisibility;

    return roleChanged || groupsChanged || accountsChanged || hrcoChanged;
  }, [user, selectedRoleId, selectedGroupIds, selectedAccountIds, hrcoGlobalVisibility, isGlobalHQSelected, isHrcoRole]);

  // Filter accounts by search
  const selectableAccounts = useMemo(() => {
    if (isGlobalHQSelected) return accounts;
    return accounts.filter((acc) => selectedGroupIds.includes(acc.group_id));
  }, [accounts, selectedGroupIds, isGlobalHQSelected]);

  const filteredAccounts = useMemo(() => {
    if (!accountSearch.trim()) return selectableAccounts;
    const q = accountSearch.toLowerCase();
    return selectableAccounts.filter((a) => a.account_name.toLowerCase().includes(q));
  }, [selectableAccounts, accountSearch]);

  const toggleGroup = (groupId: string) => {
    if (isTargetLocked) return;
    setSelectedGroupIds((prev) => {
      const isSelected = prev.includes(groupId);
      return isSelected ? prev.filter((id) => id !== groupId) : [...prev, groupId];
    });
  };

  const toggleAccount = (accountId: string) => {
    if (isTargetLocked || isGlobalHQSelected) return;
    setSelectedAccountIds((prev) => {
      const isSelected = prev.includes(accountId);
      return isSelected ? prev.filter((id) => id !== accountId) : [...prev, accountId];
    });
  };

  const selectAllAccounts = () => {
    if (isTargetLocked || isGlobalHQSelected) return;
    setSelectedAccountIds(selectableAccounts.map((a) => a.id));
  };

  const clearAllAccounts = () => {
    if (isTargetLocked || isGlobalHQSelected) return;
    setSelectedAccountIds([]);
  };

  // Permission summary text resolution
  const summaryGroupNames = useMemo(() => {
    if (isGlobalHQSelected) return "Global HQ / All Groups";
    const names = selectedGroupIds
      .map((gid) => groups.find((g) => g.id === gid)?.name)
      .filter(Boolean);
    return names.length > 0 ? names.join(", ") : "None";
  }, [isGlobalHQSelected, selectedGroupIds, groups]);

  const summaryAccountNames = useMemo(() => {
    if (isGlobalHQSelected) return "All Accounts (Global HQ)";
    if (selectedAccountIds.length === 0) return "All Accounts (Group Wide)";
    const count = selectedAccountIds.length;
    const firstTwo = selectedAccountIds
      .slice(0, 2)
      .map((aid) => accounts.find((a) => a.id === aid)?.account_name)
      .filter(Boolean)
      .join(", ");
    if (count <= 2) return `(${count}) ${firstTwo}`;
    return `(${count}) ${firstTwo}, +${count - 2} more`;
  }, [isGlobalHQSelected, selectedAccountIds, accounts]);

  // Action: Save Changes
  const handleSave = async () => {
    if (!user || isTargetLocked) return;
    setFeedbackNotice(null);

    try {
      await upsertMutation.mutateAsync({
        fullName: user.fullName,
        email: user.email,
        roleId: selectedRoleId,
        groupIds: selectedGroupIds,
        accountIds: isGlobalHQSelected ? [] : selectedAccountIds,
        existingProfileId: user.id,
      });

      if (isHrcoRole && hrcoGlobalVisibility !== user.hrcoGlobalVisibility) {
        await hrcoVisibilityMutation.mutateAsync({
          profileId: user.id,
          enabled: hrcoGlobalVisibility,
        });
      }

      setFeedbackNotice({
        type: "success",
        text: "User profile updated successfully. Scope changes take effect after next login.",
      });
      setSaveDiffConfirmOpen(false);
      onSaved?.();
    } catch (err) {
      setFeedbackNotice({
        type: "error",
        text: friendlyUserError(err),
      });
      setSaveDiffConfirmOpen(false);
    }
  };

  // Action: Toggle Status
  const handleToggleStatus = async () => {
    if (!user || isSelf || isTargetLocked) return;
    setFeedbackNotice(null);

    try {
      const nextActive = !user.isActive;
      await toggleStatusMutation.mutateAsync({
        profileId: user.id,
        isActive: nextActive,
      });

      setFeedbackNotice({
        type: "success",
        text: `User account successfully ${nextActive ? "activated" : "suspended"}.`,
      });
      setStatusConfirmOpen(false);
      onSaved?.();
    } catch (err) {
      setFeedbackNotice({
        type: "error",
        text: friendlyUserError(err),
      });
      setStatusConfirmOpen(false);
    }
  };

  // Action: Archive Account
  const handleArchive = async () => {
    if (!user || isSelf || isTargetLocked) return;
    setFeedbackNotice(null);

    try {
      await archiveMutation.mutateAsync(user.id);
      setFeedbackNotice({
        type: "success",
        text: "User account archived successfully.",
      });
      setArchiveConfirmOpen(false);
      onSaved?.();
    } catch (err) {
      setFeedbackNotice({
        type: "error",
        text: friendlyUserError(err),
      });
      setArchiveConfirmOpen(false);
    }
  };

  // Action: Reset Password
  const handleResetPassword = async () => {
    if (!user || isSelf || isTargetLocked) return;
    setFeedbackNotice(null);

    try {
      await resetPasswordMutation.mutateAsync(user.id);
      setFeedbackNotice({
        type: "success",
        text: `Password reset instructions sent to ${user.email}.`,
      });
      setResetPwConfirmOpen(false);
    } catch (err) {
      setFeedbackNotice({
        type: "error",
        text: friendlyUserError(err),
      });
      setResetPwConfirmOpen(false);
    }
  };

  if (!user) return null;

  return (
    <>
      <DetailDrawer
        isOpen={Boolean(user)}
        onClose={onClose}
        widthClass="w-[var(--drawer-width-lg)] max-w-full"
        title={
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-blue-100 text-base font-black text-blue-700 shadow-xs">
              {user.normalizedName ? user.normalizedName[0].toUpperCase() : "?"}
            </div>
            <div className="min-w-0">
              <div className="truncate text-base font-bold text-text-primary">
                {user.normalizedName || user.fullName}
              </div>
              <div className="truncate text-xs font-medium text-text-secondary">
                {user.email || "No email address linked"}
              </div>
            </div>
          </div>
        }
        subtitle={
          <div className="flex flex-wrap items-center gap-2 pt-1">
            <span className="inline-flex items-center rounded-full bg-indigo-50 px-2.5 py-0.5 text-xs font-semibold text-indigo-700 border border-indigo-200">
              {targetRole.name}
            </span>
            <span
              className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                user.status === "Active"
                  ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                  : user.status === "Suspended"
                  ? "bg-amber-50 text-amber-700 border border-amber-200"
                  : "bg-slate-100 text-slate-700 border border-slate-200"
              }`}
            >
              {user.status}
            </span>
            {activeTempOverride && (
              <button
                type="button"
                onClick={() => setTempPermissionModalOpen(true)}
                className="inline-flex items-center gap-1 rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-semibold text-amber-800 border border-amber-300 hover:bg-amber-100 transition cursor-pointer"
                title="Active temporary permission override in effect"
              >
                <Clock className="h-3 w-3 text-amber-600" />
                <span>{activeTempOverride.expiresLabel}</span>
              </button>
            )}
            {isTargetLocked && (
              <span className="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium text-slate-600">
                <Lock className="h-3 w-3" /> Protected
              </span>
            )}
          </div>
        }
      >

        <div className="space-y-5">
          {/* Top Feedback Banner */}
          {feedbackNotice && (
            <div
              className={`flex items-center gap-2 rounded-lg p-3 text-xs font-medium border ${
                feedbackNotice.type === "success"
                  ? "bg-emerald-50 text-emerald-800 border-emerald-200"
                  : "bg-red-50 text-red-800 border-red-200"
              }`}
            >
              {feedbackNotice.type === "success" ? (
                <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-600" />
              ) : (
                <AlertTriangle className="h-4 w-4 shrink-0 text-red-600" />
              )}
              <span>{feedbackNotice.text}</span>
            </div>
          )}

          {/* Segmented 3-Tab Header */}
          <div className="flex rounded-lg border border-border-default bg-surface-muted p-1">
            <button
              type="button"
              onClick={() => setActiveTab("overview")}
              className={`flex-1 rounded-md py-1.5 text-xs font-bold transition-colors ${
                activeTab === "overview"
                  ? "bg-surface-base text-brand-600 shadow-xs"
                  : "text-text-secondary hover:text-text-primary"
              }`}
            >
              Overview
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("scope")}
              className={`flex-1 rounded-md py-1.5 text-xs font-bold transition-colors ${
                activeTab === "scope"
                  ? "bg-surface-base text-brand-600 shadow-xs"
                  : "text-text-secondary hover:text-text-primary"
              }`}
            >
              Scope Assignment
            </button>
            <button
              type="button"
              onClick={() => setActiveTab("activity")}
              className={`flex-1 rounded-md py-1.5 text-xs font-bold transition-colors ${
                activeTab === "activity"
                  ? "bg-surface-base text-brand-600 shadow-xs"
                  : "text-text-secondary hover:text-text-primary"
              }`}
            >
              Activity Log ({auditLogs.length})
            </button>
          </div>

          {/* TAB 1: OVERVIEW */}
          {activeTab === "overview" && (
            <div className="space-y-4">
              {/* Basic Information Card */}
              <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-3">
                <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-text-muted">
                  <User className="h-4 w-4 text-brand-600" />
                  Basic Information
                </div>

                {isTargetLocked && (
                  <div className="rounded-md border border-amber-200 bg-amber-50 p-2.5 text-xs text-amber-800">
                    Head Admin cannot change roles or scopes of Super Admin or Head Admin accounts.
                  </div>
                )}

                <div className="space-y-2.5">
                  <div>
                    <label className="block text-xs font-semibold text-text-secondary mb-1">
                      Full Name
                    </label>
                    <input
                      type="text"
                      disabled
                      value={user.fullName}
                      className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-xs text-text-primary font-medium cursor-not-allowed opacity-80"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-semibold text-text-secondary mb-1">
                      Email Address
                    </label>
                    <input
                      type="text"
                      disabled
                      value={user.email || "No email assigned"}
                      className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-xs text-text-primary font-medium cursor-not-allowed opacity-80"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-semibold text-text-primary mb-1">
                      Role Assignment
                    </label>
                    {isTargetLocked ? (
                      <input
                        type="text"
                        disabled
                        value={user.roleName}
                        className="w-full rounded-md border border-border-default bg-surface-muted px-3 py-2 text-xs text-text-primary font-medium cursor-not-allowed opacity-80"
                      />
                    ) : (
                      <select
                        value={selectedRoleId}
                        onChange={(e) => setSelectedRoleId(e.target.value)}
                        className="w-full rounded-md border border-border-default bg-surface-base px-3 py-2 text-xs font-semibold text-text-primary outline-none focus:border-brand-500"
                      >
                        {assignableRoles.map((r) => (
                          <option key={r.id} value={r.id}>
                            {r.name}
                          </option>
                        ))}
                      </select>
                    )}
                  </div>
                </div>
              </div>

              {/* Permission Summary Preview Card */}
              <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-2.5">
                <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-text-muted">
                  <Shield className="h-4 w-4 text-emerald-600" />
                  Live Permission Summary
                </div>
                <div className="space-y-1.5 text-xs">
                  <div className="flex items-start gap-2">
                    <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-emerald-600 shrink-0" />
                    <div>
                      <strong className="text-text-primary">Role:</strong>{" "}
                      <span className="text-text-secondary">{targetRole.name}</span>
                    </div>
                  </div>
                  <div className="flex items-start gap-2">
                    <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-emerald-600 shrink-0" />
                    <div>
                      <strong className="text-text-primary">Groups:</strong>{" "}
                      <span className="text-text-secondary">{summaryGroupNames}</span>
                    </div>
                  </div>
                  <div className="flex items-start gap-2">
                    <CheckCircle2 className="h-3.5 w-3.5 mt-0.5 text-emerald-600 shrink-0" />
                    <div>
                      <strong className="text-text-primary">Accounts:</strong>{" "}
                      <span className="text-text-secondary">{summaryAccountNames}</span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Temporary Overrides & Delegations Card */}
              <div className="rounded-lg border border-amber-200/90 bg-amber-50/40 p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-amber-900">
                    <Clock className="h-4 w-4 text-amber-600" />
                    Temporary Permission Overrides
                  </div>
                  {activeTempOverride && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-[10px] font-semibold text-emerald-700 border border-emerald-200">
                      <span className="relative flex h-1.5 w-1.5">
                        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                        <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-500"></span>
                      </span>
                      Active Override
                    </span>
                  )}
                </div>

                {activeTempOverride ? (
                  <div className="space-y-2 rounded-md bg-white p-3 border border-amber-200/80 text-xs text-text-secondary">
                    <div className="flex items-center justify-between">
                      <span className="font-semibold text-text-primary">
                        Delegated Scope ({activeTempOverride.scopeType}):
                      </span>
                      <span className="font-mono text-amber-800 font-bold text-[11px]">
                        {activeTempOverride.expiresLabel}
                      </span>
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {activeTempOverride.additionalGroups.map((g) => (
                        <span
                          key={g}
                          className="inline-flex items-center gap-1 rounded bg-blue-50 px-2 py-0.5 text-[11px] font-semibold text-blue-700 border border-blue-200"
                        >
                          <Layers className="h-2.5 w-2.5 text-blue-500" />
                          {g}
                        </span>
                      ))}
                    </div>
                    <div className="text-[11px] text-text-muted pt-1 border-t border-slate-100 flex items-center justify-between">
                      <span>Granted by: {activeTempOverride.grantedBy}</span>
                      <span>Expires: {new Date(activeTempOverride.expiresAt).toLocaleDateString()}</span>
                    </div>
                    {activeTempOverride.displayReason && (
                      <p className="italic text-[11px] text-text-muted bg-slate-50 p-2 rounded border border-slate-100">
                        &ldquo;{activeTempOverride.displayReason}&rdquo;
                      </p>
                    )}
                    <button
                      type="button"
                      onClick={() => setTempPermissionModalOpen(true)}
                      className="w-full mt-2 rounded-md border border-amber-300 bg-amber-50 px-3 py-1.5 text-xs font-bold text-amber-900 hover:bg-amber-100 transition cursor-pointer"
                    >
                      Manage / Revoke Temporary Override
                    </button>
                  </div>
                ) : (
                  <div className="flex items-center justify-between rounded-md bg-white p-3 border border-border-default text-xs gap-3">
                    <div className="text-text-secondary">
                      No active time-bound overrides. User operates strictly under assigned role scopes.
                    </div>
                    <button
                      type="button"
                      onClick={() => setTempPermissionModalOpen(true)}
                      className="shrink-0 inline-flex items-center gap-1.5 rounded-md bg-amber-600 px-3 py-1.5 text-xs font-bold text-white hover:bg-amber-700 transition cursor-pointer"
                    >
                      <KeyRound className="h-3.5 w-3.5" />
                      <span>Grant Override</span>
                    </button>
                  </div>
                )}
              </div>

              {/* Danger Zone Card */}
              <div className="rounded-lg border border-red-200 bg-red-50/40 p-4 space-y-3">

                <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-red-700">
                  <AlertTriangle className="h-4 w-4 text-red-600" />
                  Danger Zone
                </div>

                {isSelf && (
                  <p className="text-xs text-red-600 italic">
                    Self-service destructive actions are disabled on your own account.
                  </p>
                )}

                <div className="space-y-2">
                  <button
                    type="button"
                    disabled={isSelf || isTargetLocked || toggleStatusMutation.isPending}
                    onClick={() => setStatusConfirmOpen(true)}
                    className="flex w-full items-center justify-between rounded-md border border-border-default bg-surface-base px-3 py-2 text-xs font-semibold text-text-primary shadow-xs hover:bg-surface-hover disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <span className="flex items-center gap-2">
                      <Power className="h-3.5 w-3.5 text-amber-600" />
                      {user.isActive ? "Deactivate User" : "Activate User"}
                    </span>
                    <span className="text-[11px] text-text-muted">
                      {user.isActive ? "Set to Suspended" : "Restore active access"}
                    </span>
                  </button>

                  <button
                    type="button"
                    disabled={isSelf || isTargetLocked || resetPasswordMutation.isPending}
                    onClick={() => setResetPwConfirmOpen(true)}
                    className="flex w-full items-center justify-between rounded-md border border-border-default bg-surface-base px-3 py-2 text-xs font-semibold text-text-primary shadow-xs hover:bg-surface-hover disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <span className="flex items-center gap-2">
                      <KeyRound className="h-3.5 w-3.5 text-blue-600" />
                      Reset Password
                    </span>
                    <span className="text-[11px] text-text-muted">Dispatch reset link</span>
                  </button>

                  <button
                    type="button"
                    disabled={isSelf || isTargetLocked || archiveMutation.isPending}
                    onClick={() => setArchiveConfirmOpen(true)}
                    className="flex w-full items-center justify-between rounded-md border border-red-200 bg-red-50 px-3 py-2 text-xs font-semibold text-red-700 shadow-xs hover:bg-red-100 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <span className="flex items-center gap-2">
                      <Archive className="h-3.5 w-3.5 text-red-600" />
                      Archive Account
                    </span>
                    <span className="text-[11px] text-red-500">Soft-archive profile</span>
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: SCOPE ASSIGNMENT */}
          {activeTab === "scope" && (
            <div className="space-y-4">
              {/* Group Scope Card */}
              <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-text-muted">
                    <Layers className="h-4 w-4 text-brand-600" />
                    Group Scopes
                  </div>
                  <span className="text-xs text-text-secondary">
                    {selectedGroupIds.length} selected
                  </span>
                </div>
                <p className="text-xs text-text-secondary">
                  Selecting Global HQ grants unrestricted visibility across all organizational divisions.
                </p>
                <div className="flex flex-wrap gap-2 max-h-48 overflow-y-auto p-1">
                  {groups.map((group) => {
                    const isSelected = selectedGroupIds.includes(group.id);
                    return (
                      <button
                        key={group.id}
                        type="button"
                        disabled={isTargetLocked}
                        onClick={() => toggleGroup(group.id)}
                        className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold transition-colors ${
                          isSelected
                            ? "bg-blue-100 text-blue-700 border border-blue-300"
                            : "bg-surface-muted text-text-secondary border border-border-default hover:bg-surface-hover"
                        } ${isTargetLocked ? "opacity-60 cursor-not-allowed" : ""}`}
                      >
                        {isSelected && <Check className="h-3 w-3" />}
                        {group.name}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Account Scope Card */}
              <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-text-muted">
                    <Store className="h-4 w-4 text-brand-600" />
                    Account Scopes
                  </div>
                  {!isGlobalHQSelected && selectedGroupIds.length > 0 && !isTargetLocked && (
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={selectAllAccounts}
                        className="text-xs font-semibold text-brand-600 hover:underline"
                      >
                        Select All
                      </button>
                      <span className="text-text-muted">•</span>
                      <button
                        type="button"
                        onClick={clearAllAccounts}
                        className="text-xs font-semibold text-red-600 hover:underline"
                      >
                        Clear All
                      </button>
                    </div>
                  )}
                </div>

                {selectedGroupIds.length === 0 ? (
                  <div className="rounded-lg border border-dashed border-border-default p-4 text-center text-xs text-text-muted">
                    Select one or more group scopes above to configure specific account access.
                  </div>
                ) : isGlobalHQSelected ? (
                  <div className="flex items-center gap-2 rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-800">
                    <CheckCircle2 className="h-4 w-4 shrink-0 text-blue-600" />
                    <span>
                      <strong>Global HQ Active:</strong> User automatically has access to all current and future accounts.
                    </span>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <div className="relative">
                      <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-muted" />
                      <input
                        type="text"
                        placeholder="Search accounts in selected groups..."
                        value={accountSearch}
                        onChange={(e) => setAccountSearch(e.target.value)}
                        className="w-full rounded-md border border-border-default bg-surface-muted pl-8 pr-3 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500"
                      />
                    </div>
                    <div className="max-h-48 overflow-y-auto rounded-lg border border-border-default bg-surface-muted/30 divide-y divide-border-subtle">
                      {accountsLoading ? (
                        <div className="p-3 text-center text-xs text-text-muted">Loading accounts...</div>
                      ) : filteredAccounts.length === 0 ? (
                        <div className="p-3 text-center text-xs text-text-muted">No accounts match search.</div>
                      ) : (
                        filteredAccounts.map((acc) => {
                          const isChecked = selectedAccountIds.includes(acc.id);
                          return (
                            <label
                              key={acc.id}
                              className={`flex items-center gap-2.5 px-3 py-2 text-xs hover:bg-surface-hover ${
                                isTargetLocked ? "cursor-not-allowed opacity-60" : "cursor-pointer"
                              }`}
                            >
                              <input
                                type="checkbox"
                                disabled={isTargetLocked}
                                checked={isChecked}
                                onChange={() => toggleAccount(acc.id)}
                                className="rounded border-border-default text-brand-600 focus:ring-brand-500"
                              />
                              <span className="font-medium text-text-primary">{acc.account_name}</span>
                            </label>
                          );
                        })
                      )}
                    </div>
                    <p className="text-[11px] text-text-muted">
                      Leaving account scope empty permits access across all accounts within the selected groups.
                    </p>
                  </div>
                )}
              </div>

              {/* Conditional HRCO Global Visibility Card */}
              {isHrcoRole && (
                <div className="rounded-lg border border-border-default bg-surface-base p-4 space-y-2">
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="text-xs font-bold text-text-primary">
                        HRCO Global Visibility
                      </div>
                      <p className="text-xs text-text-secondary mt-0.5">
                        Bypasses per-employee plantilla HRCO assignments. Allows HRCO to view all employees in permitted accounts.
                      </p>
                    </div>
                    <label className="relative inline-flex items-center cursor-pointer">
                      <input
                        type="checkbox"
                        disabled={isTargetLocked}
                        checked={hrcoGlobalVisibility}
                        onChange={(e) => setHrcoGlobalVisibilityState(e.target.checked)}
                        className="sr-only peer"
                      />
                      <div className="w-9 h-5 bg-gray-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-blue-600"></div>
                    </label>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* TAB 3: ACTIVITY LOG */}
          {activeTab === "activity" && (
            <div className="space-y-3">
              {logsLoading ? (
                <div className="p-8 text-center text-xs text-text-muted">Loading audit trail...</div>
              ) : auditLogs.length === 0 ? (
                <div className="rounded-lg border border-border-default bg-surface-base p-8 text-center text-xs text-text-muted">
                  No activity logs recorded for this user.
                </div>
              ) : (
                <div className="space-y-3">
                  {auditLogs.map((log) => {
                    const date = new Date(log.timestamp);
                    const formattedDate = !isNaN(date.getTime())
                      ? `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
                          date.getDate(),
                        ).padStart(2, "0")} ${String(date.getHours()).padStart(2, "0")}:${String(
                          date.getMinutes(),
                        ).padStart(2, "0")}:${String(date.getSeconds()).padStart(2, "0")}`
                      : log.timestamp;

                    return (
                      <div
                        key={log.id}
                        className="rounded-xl border border-border-default bg-surface-base p-4 space-y-2.5 shadow-xs"
                      >
                        <div className="flex items-center justify-between">
                          <span className="inline-flex items-center rounded-md bg-blue-50 px-2.5 py-1 text-[11px] font-bold text-blue-700">
                            {log.action}
                          </span>
                          <span className="text-xs font-semibold text-text-muted">
                            {formattedDate}
                          </span>
                        </div>
                        <div className="flex items-center gap-1.5 text-xs text-text-secondary">
                          <User className="h-3.5 w-3.5 text-text-muted shrink-0" />
                          <span>
                            By: <strong className="text-text-primary">{log.actorName || "System"}</strong> (
                            {log.actorRole || "None"})
                          </span>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Sticky Action Footer */}
        {hasEditableChanges && !isTargetLocked && (
          <div className="sticky bottom-0 -mx-5 -mb-5 border-t border-border-default bg-surface-base px-5 py-3 shadow-lg flex items-center justify-between">
            <span className="text-xs font-medium text-amber-700">
              Unsaved changes pending.
            </span>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => {
                  setSelectedRoleId(user.roleId);
                  setSelectedGroupIds([...user.scopedGroupIds]);
                  setSelectedAccountIds(
                    user.scopes.filter((s) => s.accountId).map((s) => s.accountId as string),
                  );
                  setHrcoGlobalVisibilityState(user.hrcoGlobalVisibility);
                }}
                className="rounded-md border border-border-default bg-surface-base px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Reset
              </button>
              <button
                type="button"
                onClick={() => setSaveDiffConfirmOpen(true)}
                disabled={upsertMutation.isPending}
                className="inline-flex items-center gap-1.5 rounded-md bg-blue-600 px-4 py-1.5 text-xs font-bold text-white shadow-xs hover:bg-blue-700"
              >
                Save Changes
              </button>
            </div>
          </div>
        )}
      </DetailDrawer>

      {/* MODAL 1: Save Diff Confirmation */}
      {saveDiffConfirmOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="fixed inset-0 bg-black/40 backdrop-blur-xs" onClick={() => setSaveDiffConfirmOpen(false)} />
          <div className="relative z-50 w-full max-w-md rounded-xl border border-border-default bg-surface-base p-5 shadow-2xl space-y-4">
            <h3 className="text-sm font-bold text-text-primary">Confirm Profile Updates</h3>
            <p className="text-xs text-text-secondary">
              Review modifications before applying changes to <strong>{user.fullName}</strong>.
            </p>
            <div className="rounded-lg border border-border-subtle bg-surface-muted/50 p-3 space-y-2 text-xs">
              <div className="flex justify-between">
                <span className="text-text-muted">Target Role:</span>
                <span className="font-semibold text-text-primary">{targetRole.name}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Groups:</span>
                <span className="font-semibold text-text-primary">{summaryGroupNames}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Accounts:</span>
                <span className="font-semibold text-text-primary">{summaryAccountNames}</span>
              </div>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setSaveDiffConfirmOpen(false)}
                className="rounded-md border border-border-default px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleSave}
                disabled={upsertMutation.isPending}
                className="rounded-md bg-blue-600 px-3 py-1.5 text-xs font-bold text-white hover:bg-blue-700 disabled:opacity-50"
              >
                {upsertMutation.isPending ? "Saving..." : "Confirm & Save"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 2: Status Toggle Confirmation */}
      {statusConfirmOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="fixed inset-0 bg-black/40 backdrop-blur-xs" onClick={() => setStatusConfirmOpen(false)} />
          <div className="relative z-50 w-full max-w-md rounded-xl border border-border-default bg-surface-base p-5 shadow-2xl space-y-4">
            <h3 className="text-sm font-bold text-text-primary">
              {user.isActive ? "Suspend User Account?" : "Activate User Account?"}
            </h3>
            <p className="text-xs text-text-secondary">
              {user.isActive
                ? `Suspending ${user.fullName} will revoke access to OHMployee immediately.`
                : `Activating ${user.fullName} will grant authorized access according to assigned scopes.`}
            </p>
            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setStatusConfirmOpen(false)}
                className="rounded-md border border-border-default px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleToggleStatus}
                disabled={toggleStatusMutation.isPending}
                className={`rounded-md px-3 py-1.5 text-xs font-bold text-white disabled:opacity-50 ${
                  user.isActive ? "bg-red-600 hover:bg-red-700" : "bg-emerald-600 hover:bg-emerald-700"
                }`}
              >
                {toggleStatusMutation.isPending
                  ? "Processing..."
                  : user.isActive
                  ? "Suspend User"
                  : "Activate User"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 3: Reset Password Confirmation */}
      {resetPwConfirmOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="fixed inset-0 bg-black/40 backdrop-blur-xs" onClick={() => setResetPwConfirmOpen(false)} />
          <div className="relative z-50 w-full max-w-md rounded-xl border border-border-default bg-surface-base p-5 shadow-2xl space-y-4">
            <h3 className="text-sm font-bold text-text-primary">Reset Password?</h3>
            <p className="text-xs text-text-secondary">
              A secure password reset email will be dispatched to <strong>{user.email}</strong>.
            </p>
            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setResetPwConfirmOpen(false)}
                className="rounded-md border border-border-default px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleResetPassword}
                disabled={resetPasswordMutation.isPending}
                className="rounded-md bg-blue-600 px-3 py-1.5 text-xs font-bold text-white hover:bg-blue-700 disabled:opacity-50"
              >
                {resetPasswordMutation.isPending ? "Sending..." : "Send Reset Email"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 4: Archive Confirmation */}
      {archiveConfirmOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="fixed inset-0 bg-black/40 backdrop-blur-xs" onClick={() => setArchiveConfirmOpen(false)} />
          <div className="relative z-50 w-full max-w-md rounded-xl border border-red-200 bg-surface-base p-5 shadow-2xl space-y-4">
            <div className="flex items-center gap-2 text-red-600 font-bold text-sm">
              <AlertTriangle className="h-4 w-4" />
              Confirm Account Archival
            </div>
            <p className="text-xs text-text-secondary">
              Soft-archiving <strong>{user.fullName}</strong> will disable access and mark the profile as archived. This action will be audited.
            </p>
            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setArchiveConfirmOpen(false)}
                className="rounded-md border border-border-default px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleArchive}
                disabled={archiveMutation.isPending}
                className="rounded-md bg-red-600 px-3 py-1.5 text-xs font-bold text-white hover:bg-red-700 disabled:opacity-50"
              >
                {archiveMutation.isPending ? "Archiving..." : "Archive Account"}
              </button>
            </div>
          </div>
        </div>
      )}
      {/* MODAL 5: Temporary Permission Overrides */}
      <TempPermissionModal
        isOpen={tempPermissionModalOpen}
        onClose={() => setTempPermissionModalOpen(false)}
        presetUser={user}
      />
    </>
  );
}

