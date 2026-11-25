"use client";

import { useState, useMemo, useEffect, useRef, type ReactNode } from "react";
import {
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
import { Modal } from "@/components/shared/Modal";
import type {
  UserProfileItem,
  AuditLogEntry,
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
import { formatPersonName } from "@/lib/utils/displayText";

// Helper: Format audit timestamp to conversational style (e.g. "Nov 9, 2026 at 09:38 AM")
function formatAuditTime(timestamp: string): string {
  const d = new Date(timestamp);
  if (isNaN(d.getTime())) return timestamp;
  const month = d.toLocaleDateString("en-US", { month: "short" });
  const day = d.getDate();
  const year = d.getFullYear();
  let hours = d.getHours();
  const minutes = String(d.getMinutes()).padStart(2, "0");
  const ampm = hours >= 12 ? "PM" : "AM";
  hours = hours % 12 || 12;
  const formattedHours = String(hours).padStart(2, "0");
  return `${month} ${day}, ${year} at ${formattedHours}:${minutes} ${ampm}`;
}

// Helper: Translate raw audit actions into conversational sentences
function getAuditDescription(log: AuditLogEntry, targetUser: UserProfileItem | null): ReactNode {
  const action = (log.action || "").toUpperCase();
  const oldData = log.oldData || {};
  const newData = log.newData || {};

  if (action === "UPDATE_USER_ROLE" || action.includes("ROLE")) {
    const oldRole =
      (oldData.role_name as string) ||
      (oldData.roleName as string) ||
      (oldData.role as string) ||
      "";
    const newRole =
      (newData.role_name as string) ||
      (newData.roleName as string) ||
      (newData.role as string) ||
      targetUser?.roleName ||
      "";

    if (oldRole && newRole && oldRole !== newRole) {
      return (
        <>
          changed the user&apos;s role from{" "}
          <span className="font-semibold text-text-primary">{oldRole}</span> to{" "}
          <span className="font-semibold text-text-primary">{newRole}</span>
        </>
      );
    }
    if (newRole) {
      return (
        <>
          changed the user&apos;s role to{" "}
          <span className="font-semibold text-text-primary">{newRole}</span>
        </>
      );
    }
    return <>changed the user&apos;s role</>;
  }

  if (action === "UPDATE_USER_STATUS" || action === "TOGGLE_USER_STATUS" || action.includes("STATUS")) {
    const isActive = newData.is_active ?? newData.isActive;
    if (isActive === true) {
      return <>activated the user account</>;
    }
    if (isActive === false) {
      return <>deactivated the user account</>;
    }
    return <>updated the user&apos;s account status</>;
  }

  if (action.includes("DEACTIVATE")) {
    return <>deactivated the user account</>;
  }

  if (action.includes("ACTIVATE")) {
    return <>activated the user account</>;
  }

  if (action === "RESET_PASSWORD" || action.includes("PASSWORD")) {
    return <>dispatched password reset instructions for this user</>;
  }

  if (action === "ARCHIVE_USER" || action.includes("ARCHIVE")) {
    return <>archived this user account</>;
  }

  if (action === "UPDATE_USER_SCOPES" || action.includes("SCOPE")) {
    return <>updated assigned organizational group and account scopes</>;
  }

  if (action === "CREATE_USER" || action.includes("CREATE")) {
    return <>created this user account</>;
  }

  const readable = log.action.replace(/_/g, " ").toLowerCase();
  return <>performed {readable}</>;
}


export interface UserDetailDrawerProps {
  user: UserProfileItem | null;
  onClose: () => void;
  onSaved?: () => void;
}

export type UserDetailModalProps = UserDetailDrawerProps;

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

  const accountGroupRef = useRef<Map<string, string>>(new Map());

  // Seed / update accountGroupRef from user.scopes
  useEffect(() => {
    if (user?.scopes) {
      for (const s of user.scopes) {
        if (s.accountId && s.groupId) {
          accountGroupRef.current.set(s.accountId, s.groupId);
        }
      }
    }
  }, [user]);

  // Keep accountGroupRef updated whenever accounts query returns
  useEffect(() => {
    for (const a of accounts) {
      if (a.id && a.group_id) {
        accountGroupRef.current.set(a.id, a.group_id);
      }
    }
  }, [accounts]);

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
    const isCurrentlySelected = selectedGroupIds.includes(groupId);
    if (isCurrentlySelected) {
      setSelectedGroupIds((prev) => prev.filter((id) => id !== groupId));
      setSelectedAccountIds((prev) =>
        prev.filter((aid) => accountGroupRef.current.get(aid) !== groupId)
      );
    } else {
      setSelectedGroupIds((prev) => [...prev, groupId]);
    }
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
    const validIds = selectedAccountIds.filter((aid) => accounts.some((a) => a.id === aid));
    if (validIds.length === 0) return "All Accounts (Group Wide)";
    const count = validIds.length;
    const firstTwo = validIds
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

    const sanitizedAccountIds = isGlobalHQSelected
      ? []
      : selectedAccountIds.filter((aid) => {
          const gid = accountGroupRef.current.get(aid) || accounts.find((a) => a.id === aid)?.group_id;
          return gid ? selectedGroupIds.includes(gid) : accounts.some((a) => a.id === aid);
        });

    try {
      await upsertMutation.mutateAsync({
        fullName: user.fullName,
        email: user.email,
        roleId: selectedRoleId,
        groupIds: selectedGroupIds,
        accountIds: sanitizedAccountIds,
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
      onSaved?.();
    } catch (err) {
      setFeedbackNotice({
        type: "error",
        text: friendlyUserError(err),
      });
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

  const isBusy =
    upsertMutation.isPending ||
    toggleStatusMutation.isPending ||
    archiveMutation.isPending ||
    resetPasswordMutation.isPending;

  return (
    <>
      <Modal
        isOpen={Boolean(user)}
        onClose={onClose}
        maxWidthClass="max-w-2xl"
        disableBackdropClick={isBusy}
        isSubmitting={isBusy}
        isDirty={hasEditableChanges}
        title={
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-brand-50 text-base font-black text-brand-700 border border-brand-200 shadow-xs">
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
            <span className="inline-flex items-center rounded-full bg-surface-subtle px-2.5 py-0.5 text-xs font-semibold text-text-primary border border-border-default">
              {targetRole.name}
            </span>
            <span className="inline-flex items-center rounded-full border border-border-default bg-surface-subtle px-2.5 py-0.5 text-xs font-semibold text-text-secondary">
              {user.status}
            </span>
            {activeTempOverride && (
              <button
                type="button"
                onClick={() => setTempPermissionModalOpen(true)}
                className="inline-flex items-center gap-1 rounded-full border border-border-default bg-surface-subtle px-2.5 py-0.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition cursor-pointer"
                title="Active temporary permission override in effect"
              >
                <Clock className="h-3 w-3 text-text-secondary" />
                <span>{activeTempOverride.expiresLabel}</span>
              </button>
            )}
            {isTargetLocked && (
              <span className="inline-flex items-center gap-1 rounded-full border border-border-default bg-surface-subtle px-2 py-0.5 text-[11px] font-medium text-text-secondary">
                <Lock className="h-3 w-3" /> Protected
              </span>
            )}
          </div>
        }
        footer={
          hasEditableChanges && !isTargetLocked ? (
            <div className="flex w-full items-center justify-between">
              <span className="text-xs font-medium text-text-secondary">
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
                  className="rounded-md border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover cursor-pointer"
                >
                  Reset
                </button>
                <button
                  type="button"
                  onClick={handleSave}
                  disabled={upsertMutation.isPending}
                  className="inline-flex items-center gap-1.5 rounded-md bg-brand-500 px-4 py-1.5 text-xs font-bold text-white shadow-xs hover:bg-brand-600 cursor-pointer disabled:opacity-50"
                >
                  {upsertMutation.isPending ? "Saving..." : "Save Changes"}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex w-full justify-end">
              <button
                type="button"
                onClick={onClose}
                className="rounded-md border border-border-default bg-surface px-4 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover cursor-pointer"
              >
                Close
              </button>
            </div>
          )
        }
      >

        <div className="space-y-5">
          {/* Top Feedback Banner */}
          {feedbackNotice && (
            <div
              className={`flex items-center gap-2 rounded-lg p-3 text-xs font-medium border ${
                feedbackNotice.type === "success"
                  ? "bg-surface-subtle text-text-primary border-border-default"
                  : "bg-danger-subtle text-danger-text border-danger-border"
              }`}
            >
              {feedbackNotice.type === "success" ? (
                <CheckCircle2 className="h-4 w-4 shrink-0 text-pct-high" />
              ) : (
                <AlertTriangle className="h-4 w-4 shrink-0 text-danger-icon" />
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
              {/* Profile Details & Role */}
              <div className="rounded-xl border border-border-default bg-surface-base p-4 space-y-3.5 shadow-2xs">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 text-xs">
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted uppercase tracking-wider">
                      Full Name
                    </span>
                    <p className="mt-0.5 text-xs font-semibold text-text-primary">{user.fullName}</p>
                  </div>
                  <div>
                    <span className="text-[11px] font-semibold text-text-muted uppercase tracking-wider">
                      Email Address
                    </span>
                    <p className="mt-0.5 text-xs font-medium text-text-secondary">
                      {user.email || "No email assigned"}
                    </p>
                  </div>
                </div>

                {/* Role Dropdown */}
                <div className="pt-3 border-t border-border-subtle">
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                    <div>
                      <label className="text-xs font-semibold text-text-primary flex items-center gap-1.5">
                        <Shield className="h-3.5 w-3.5 text-brand-primary" />
                        Role Assignment
                      </label>
                      <p className="text-[11px] text-text-muted mt-0.5">
                        {isTargetLocked
                          ? "Protected account — role cannot be modified."
                          : "Defines system-wide authorization and capability access."}
                      </p>
                    </div>
                    <select
                      value={selectedRoleId}
                      onChange={(e) => setSelectedRoleId(e.target.value)}
                      disabled={isTargetLocked || assignableRoles.length === 0 || isSelf}
                      className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-primary focus:border-brand-500 disabled:opacity-60 disabled:cursor-not-allowed cursor-pointer"
                    >
                      {assignableRoles.map((r) => (
                        <option key={r.id} value={r.id}>
                          {r.name}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>

                {/* HRCO Cross-Group Visibility Toggle */}
                {isHrcoRole && (
                  <div className="pt-3 border-t border-border-subtle flex items-center justify-between gap-3">
                    <div>
                      <span className="text-xs font-semibold text-text-primary">
                        Cross-Group Roster Visibility
                      </span>
                      <p className="text-[11px] text-text-muted mt-0.5">
                        Allow HRCO to view personnel across all organizational groups
                      </p>
                    </div>
                    <input
                      type="checkbox"
                      checked={hrcoGlobalVisibility}
                      disabled={isTargetLocked || (!isSuperAdmin && !isHeadAdmin)}
                      onChange={(e) => setHrcoGlobalVisibilityState(e.target.checked)}
                      className="h-4 w-4 rounded border-border-default text-brand-primary focus:ring-brand-primary cursor-pointer disabled:cursor-not-allowed"
                    />
                  </div>
                )}

                {/* Scope Assignment Summary Row */}
                <div className="pt-3 border-t border-border-subtle flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <span className="text-xs font-semibold text-text-primary flex items-center gap-1.5">
                      <Layers className="h-3.5 w-3.5 text-text-secondary" />
                      Assigned Scopes
                    </span>
                    <p className="text-[11px] text-text-secondary mt-0.5 truncate">
                      <strong>Groups:</strong> {summaryGroupNames} &nbsp;•&nbsp; <strong>Accounts:</strong>{" "}
                      {summaryAccountNames}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setActiveTab("scope")}
                    className="shrink-0 text-xs font-semibold text-brand-primary hover:underline cursor-pointer"
                  >
                    Configure Scopes →
                  </button>
                </div>

                {/* Temporary Overrides Row */}
                <div className="pt-3 border-t border-border-subtle flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <span className="text-xs font-semibold text-text-primary flex items-center gap-1.5">
                      <Clock className="h-3.5 w-3.5 text-text-secondary" />
                      Temporary Permission Override
                    </span>
                    <p className="text-[11px] text-text-muted mt-0.5 truncate">
                      {activeTempOverride
                        ? `Active: ${activeTempOverride.expiresLabel} (${activeTempOverride.scopeType})`
                        : "No active temporary override in effect."}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setTempPermissionModalOpen(true)}
                    className="shrink-0 inline-flex items-center gap-1 text-xs font-semibold text-brand-primary hover:underline cursor-pointer"
                  >
                    <KeyRound className="h-3 w-3" />
                    {activeTempOverride ? "Manage Override" : "Grant Override"}
                  </button>
                </div>
              </div>

              {/* Quick Account Actions */}
              <div className="rounded-xl border border-border-default bg-surface-base p-4 space-y-2.5 shadow-2xs">
                <span className="block text-xs font-bold text-text-muted uppercase tracking-wider">
                  Account Actions
                </span>
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    disabled={isSelf || isTargetLocked || toggleStatusMutation.isPending}
                    onClick={() => setStatusConfirmOpen(true)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <Power className="h-3.5 w-3.5 text-text-secondary" />
                    <span>{user.isActive ? "Deactivate User" : "Activate User"}</span>
                  </button>

                  <button
                    type="button"
                    disabled={isSelf || isTargetLocked || resetPasswordMutation.isPending}
                    onClick={() => setResetPwConfirmOpen(true)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <KeyRound className="h-3.5 w-3.5 text-text-secondary" />
                    <span>Reset Password</span>
                  </button>

                  {isSuperAdmin && (
                    <button
                      type="button"
                      disabled={isSelf || isTargetLocked || archiveMutation.isPending}
                      onClick={() => setArchiveConfirmOpen(true)}
                      className="inline-flex items-center gap-1.5 rounded-lg border border-danger-border bg-danger-subtle/30 px-3 py-1.5 text-xs font-semibold text-danger-text shadow-2xs hover:bg-danger-subtle cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      <Archive className="h-3.5 w-3.5 text-danger-icon" />
                      <span>Archive Account</span>
                    </button>
                  )}
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
                  <div className="flex items-center gap-2 text-xs font-bold text-text-muted">
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
                            ? "bg-brand-50 text-brand-700 border border-brand-200"
                            : "bg-surface-subtle text-text-secondary border border-border-default hover:bg-surface-hover"
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
                  <div className="flex items-center gap-2 text-xs font-bold text-text-muted">
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
                        className="text-xs font-semibold text-danger-text hover:underline"
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
                  <div className="flex items-center gap-2 rounded-lg border border-border-default bg-surface-subtle p-3 text-xs text-text-primary">
                    <CheckCircle2 className="h-4 w-4 shrink-0 text-text-secondary" />
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
                        className="w-full rounded-md border border-border-default bg-surface pl-8 pr-3 py-1.5 text-xs text-text-primary outline-none focus:border-brand-500"
                      />
                    </div>
                    <div className="max-h-48 overflow-y-auto rounded-lg border border-border-default bg-surface-subtle divide-y divide-border-subtle">
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
                      <div className="w-9 h-5 bg-surface-muted peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-[var(--border-subtle)] after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-[var(--surface-base)] after:border-border-default after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-brand-500"></div>
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
                <div className="rounded-xl border border-border-default bg-surface-base p-8 text-center text-xs text-text-muted">
                  No activity logs recorded for this user.
                </div>
              ) : (
                <div className="space-y-3">
                  {auditLogs.map((log) => {
                    const actorFullName = log.actorName ? formatPersonName(log.actorName) : "System Admin";
                    const actorRoleText = log.actorRole || "Admin";
                    const initials = (log.actorName || "SA")
                      .split(/\s+/)
                      .slice(0, 2)
                      .map((p) => p[0]?.toUpperCase() || "")
                      .join("") || "SA";
                    const formattedDate = formatAuditTime(log.timestamp);
                    const description = getAuditDescription(log, user);

                    return (
                      <div
                        key={log.id}
                        className="flex items-start gap-3 rounded-xl border border-border-default bg-surface-base p-3.5 shadow-2xs"
                      >
                        {/* Circular Avatar (Initials) */}
                        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-surface-subtle text-xs font-bold text-text-primary border border-border-default">
                          {initials}
                        </div>
                        {/* Conversational Description */}
                        <div className="min-w-0 flex-1 text-xs leading-relaxed text-text-secondary">
                          <span className="font-semibold text-text-primary">{actorFullName}</span>{" "}
                          <span className="text-text-muted">({actorRoleText})</span>{" "}
                          <span>{description}</span>{" "}
                          <span className="text-text-muted">on</span>{" "}
                          <span className="font-medium text-text-primary whitespace-nowrap">
                            {formattedDate}
                          </span>
                          .
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </div>

      </Modal>

      {/* MODAL 2: Status Toggle Confirmation */}
      <Modal
        isOpen={statusConfirmOpen}
        onClose={() => setStatusConfirmOpen(false)}
        title={user.isActive ? "Suspend User Account?" : "Activate User Account?"}
        isSubmitting={toggleStatusMutation.isPending}
        disableBackdropClick={toggleStatusMutation.isPending}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setStatusConfirmOpen(false)}
              className="rounded-md border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleToggleStatus}
              disabled={toggleStatusMutation.isPending}
              className={`rounded-md px-3 py-1.5 text-xs font-bold disabled:opacity-50 ${
                user.isActive
                  ? "bg-danger-button hover:bg-danger-button-hover text-danger-button-text"
                  : "bg-brand-500 hover:bg-brand-600 text-white"
              }`}
            >
              {toggleStatusMutation.isPending
                ? "Processing..."
                : user.isActive
                ? "Suspend User"
                : "Activate User"}
            </button>
          </div>
        }
      >
        <p className="text-xs text-text-secondary">
          {user.isActive
            ? `Suspending ${user.fullName} will revoke access to OHMployee immediately.`
            : `Activating ${user.fullName} will grant authorized access according to assigned scopes.`}
        </p>
      </Modal>

      {/* MODAL 3: Reset Password Confirmation */}
      <Modal
        isOpen={resetPwConfirmOpen}
        onClose={() => setResetPwConfirmOpen(false)}
        title="Reset Password?"
        isSubmitting={resetPasswordMutation.isPending}
        disableBackdropClick={resetPasswordMutation.isPending}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setResetPwConfirmOpen(false)}
              className="rounded-md border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleResetPassword}
              disabled={resetPasswordMutation.isPending}
              className="rounded-md bg-brand-500 px-3 py-1.5 text-xs font-bold text-white hover:bg-brand-600 disabled:opacity-50"
            >
              {resetPasswordMutation.isPending ? "Sending..." : "Send Reset Email"}
            </button>
          </div>
        }
      >
        <p className="text-xs text-text-secondary">
          A secure password reset email will be dispatched to <strong>{user.email}</strong>.
        </p>
      </Modal>

      {/* MODAL 4: Archive Confirmation */}
      <Modal
        isOpen={archiveConfirmOpen}
        onClose={() => setArchiveConfirmOpen(false)}
        title="Confirm Account Archival"
        icon={AlertTriangle}
        isSubmitting={archiveMutation.isPending}
        disableBackdropClick={archiveMutation.isPending}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setArchiveConfirmOpen(false)}
              className="rounded-md border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleArchive}
              disabled={archiveMutation.isPending}
              className="rounded-md bg-danger-button px-3 py-1.5 text-xs font-bold text-danger-button-text hover:bg-danger-button-hover disabled:opacity-50"
            >
              {archiveMutation.isPending ? "Archiving..." : "Archive Account"}
            </button>
          </div>
        }
      >
        <p className="text-xs text-text-secondary">
          Soft-archiving <strong>{user.fullName}</strong> will disable access and mark the profile as archived. This action will be audited.
        </p>
      </Modal>

      {/* MODAL 6: Temporary Permission Overrides */}
      <TempPermissionModal
        isOpen={tempPermissionModalOpen}
        onClose={() => setTempPermissionModalOpen(false)}
        presetUser={user}
      />
    </>
  );
}

export const UserDetailModal = UserDetailDrawer;

