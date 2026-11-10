"use client";

import { useState, useMemo } from "react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";
import { Modal } from "@/components/shared/Modal";
import { UsersTable } from "@/components/users/UsersTable";
import { UserMetricsCards } from "@/components/users/UserMetricsCards";
import { UserDetailDrawer } from "@/components/users/UserDetailDrawer";
import { CreateUserModal } from "@/components/users/CreateUserModal";
import { AccountRequestsModal } from "@/components/more/AccountRequestsModal";
import { TempPermissionModal } from "@/components/users/TempPermissionModal";
import { useCurrentUser } from "@/lib/auth";
import {
  useUsersList,
  useGroupsQuery,
  useActiveTempPermissionsQuery,
  useToggleUserStatus,
  useResetUserPassword,
  useArchiveUser,
  friendlyUserError,
  type UserProfileItem,
} from "@/lib/queries/users";
import {
  Users,
  UserPlus,
  ShieldAlert,
  UserCheck,
  UserX,
  Clock,
  AlertTriangle,
  CheckCircle2,
} from "lucide-react";

export default function UsersPage() {
  const currentUser = useCurrentUser();

  // Role Level Guards:
  // Super Admin: level >= 100
  // Head Admin: level >= 90
  const callerRoleLevel = useMemo(() => {
    const roleKey = (currentUser?.roleKey || currentUser?.roleName || "").toLowerCase();
    if (roleKey.includes("super_admin") || roleKey === "super admin") return 100;
    if (roleKey.includes("head_admin") || roleKey === "head admin") return 90;
    return 50;
  }, [currentUser]);

  const isSuperAdmin = callerRoleLevel >= 100;
  const isHeadAdmin = callerRoleLevel >= 90 && callerRoleLevel < 100;
  const hasAccess = callerRoleLevel >= 90;

  // Tabs: "all" | "active" | "inactive" (Unified compact KPI tabs)
  const [activeTab, setActiveTab] = useState<"all" | "active" | "inactive">("all");

  // Filters
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedRoleFilter, setSelectedRoleFilter] = useState("All");
  const [selectedGroupFilter, setSelectedGroupFilter] = useState("All");

  // Pagination state
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);

  // Drawer & Modal selection state
  const [selectedUser, setSelectedUser] = useState<UserProfileItem | null>(null);
  const [createUserOpen, setCreateUserOpen] = useState(false);
  const [accountRequestsOpen, setAccountRequestsOpen] = useState(false);
  const [tempPermissionOpen, setTempPermissionOpen] = useState(false);

  // Kebab action confirmation modals
  const [statusTargetUser, setStatusTargetUser] = useState<UserProfileItem | null>(null);
  const [resetPwTargetUser, setResetPwTargetUser] = useState<UserProfileItem | null>(null);
  const [archiveTargetUser, setArchiveTargetUser] = useState<UserProfileItem | null>(null);
  const [pageFeedback, setPageFeedback] = useState<{ type: "success" | "error"; text: string } | null>(null);

  // Queries & Mutations
  const { data: allUsers = [], isLoading, refetch } = useUsersList();
  const { data: groups = [] } = useGroupsQuery();
  const { data: activeTempOverrides = [] } = useActiveTempPermissionsQuery();
  const toggleStatusMutation = useToggleUserStatus();
  const resetPasswordMutation = useResetUserPassword();
  const archiveMutation = useArchiveUser();

  // Hierarchy Visibility Guard:
  // Head Admin cannot see or manage Super Admin profiles
  const canSeeUser = useMemo(() => {
    return (user: UserProfileItem) => {
      if (isSuperAdmin) return true;
      if (isHeadAdmin) return user.roleName !== "Super Admin";
      return false;
    };
  }, [isSuperAdmin, isHeadAdmin]);

  const canManageUser = useMemo(() => {
    return (user: UserProfileItem) => {
      if (isSuperAdmin) return true;
      if (isHeadAdmin) return user.roleName !== "Super Admin";
      return false;
    };
  }, [isSuperAdmin, isHeadAdmin]);

  // Base list filtered by visibility rules
  const visibleUsers = useMemo(() => {
    return allUsers.filter(canSeeUser);
  }, [allUsers, canSeeUser]);

  // Aggregate KPI counts for compact unified tab header
  const totalCount = visibleUsers.length;
  const activeCount = visibleUsers.filter((u) => u.status === "Active").length;
  const inactiveCount = visibleUsers.filter((u) => u.status !== "Active").length;

  // Available roles for filter dropdown
  const availableRoles = useMemo(() => {
    const roles = Array.from(
      new Set(
        visibleUsers
          .map((u) => u.roleName?.trim())
          .filter((r): r is string => Boolean(r && r.length > 0)),
      ),
    ).sort();
    return ["All", ...roles];
  }, [visibleUsers]);

  // Tab, Search, Role, and Group filtered list
  const filteredUsers = useMemo(() => {
    let list = visibleUsers;

    // 1. Tab filter
    if (activeTab === "active") {
      list = list.filter((u) => u.status === "Active");
    } else if (activeTab === "inactive") {
      list = list.filter((u) => u.status !== "Active");
    }

    // 2. Role filter
    if (selectedRoleFilter !== "All") {
      list = list.filter(
        (u) => u.roleName.toLowerCase() === selectedRoleFilter.toLowerCase(),
      );
    }

    // 3. Group filter
    if (selectedGroupFilter !== "All") {
      list = list.filter(
        (u) =>
          u.scopedGroupIds.includes(selectedGroupFilter) ||
          u.scopes.some((s) => s.groupId === selectedGroupFilter),
      );
    }

    // 4. Search query filter
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      list = list.filter((u) => {
        return (
          u.fullName.toLowerCase().includes(q) ||
          u.normalizedName.toLowerCase().includes(q) ||
          u.email.toLowerCase().includes(q) ||
          u.roleName.toLowerCase().includes(q) ||
          u.scopeLabel.toLowerCase().includes(q) ||
          u.scopeSummaries.some((s) => s.toLowerCase().includes(q))
        );
      });
    }

    return list;
  }, [visibleUsers, activeTab, selectedRoleFilter, selectedGroupFilter, searchQuery]);

  // Paginated user slice
  const paginatedUsers = useMemo(() => {
    const startIndex = (page - 1) * pageSize;
    return filteredUsers.slice(startIndex, startIndex + pageSize);
  }, [filteredUsers, page, pageSize]);

  // Kebab Handler: Status Toggle
  const handleConfirmToggleStatus = async () => {
    if (!statusTargetUser) return;
    setPageFeedback(null);
    try {
      const nextActive = !statusTargetUser.isActive;
      await toggleStatusMutation.mutateAsync({
        profileId: statusTargetUser.id,
        isActive: nextActive,
      });
      setPageFeedback({
        type: "success",
        text: `User ${statusTargetUser.fullName} successfully ${nextActive ? "activated" : "deactivated"}.`,
      });
      setStatusTargetUser(null);
      refetch();
    } catch (err) {
      setPageFeedback({
        type: "error",
        text: friendlyUserError(err),
      });
      setStatusTargetUser(null);
    }
  };

  // Kebab Handler: Password Reset
  const handleConfirmResetPassword = async () => {
    if (!resetPwTargetUser) return;
    setPageFeedback(null);
    try {
      await resetPasswordMutation.mutateAsync(resetPwTargetUser.id);
      setPageFeedback({
        type: "success",
        text: `Password reset instructions sent to ${resetPwTargetUser.email}.`,
      });
      setResetPwTargetUser(null);
    } catch (err) {
      setPageFeedback({
        type: "error",
        text: friendlyUserError(err),
      });
      setResetPwTargetUser(null);
    }
  };

  // Kebab Handler: Archive User
  const handleConfirmArchiveUser = async () => {
    if (!archiveTargetUser) return;
    setPageFeedback(null);
    try {
      await archiveMutation.mutateAsync(archiveTargetUser.id);
      setPageFeedback({
        type: "success",
        text: `User account ${archiveTargetUser.fullName} archived successfully.`,
      });
      setArchiveTargetUser(null);
      refetch();
    } catch (err) {
      setPageFeedback({
        type: "error",
        text: friendlyUserError(err),
      });
      setArchiveTargetUser(null);
    }
  };

  // Access denied fallback if caller role < 90
  if (!hasAccess && !isLoading) {
    return (
      <div className="flex h-96 flex-col items-center justify-center p-8 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-full bg-danger-subtle text-danger-text mb-4">
          <ShieldAlert className="h-7 w-7" />
        </div>
        <h2 className="text-lg font-bold text-text-primary">Access Restricted</h2>
        <p className="mt-1 max-w-md text-sm text-text-secondary">
          User Management is an administrative facility restricted to Super Admin and Head Admin accounts.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {/* Top Header */}
      <AdminPageHeader
        categoryTag="Admin panel"
        moduleName="User Management"
        title="User Access & Security"
        subtitle="Manage user directories, organizational roles, and cascaded group/account scopes."
        icon={Users}
        actionSlot={
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => setTempPermissionOpen(true)}
              className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-border-default bg-surface px-3.5 py-2 text-xs font-semibold text-text-secondary hover:text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <Clock className="h-3.5 w-3.5 text-text-secondary" />
              <span>Temporary Overrides</span>
              {activeTempOverrides.length > 0 && (
                <span className="ml-1 rounded-full border border-border-default bg-surface-subtle px-1.5 py-0.2 text-[10px] font-mono font-bold text-text-secondary">
                  {activeTempOverrides.length}
                </span>
              )}
            </button>
            <button
              type="button"
              onClick={() => setAccountRequestsOpen(true)}
              className="inline-flex h-9 items-center gap-1.5 rounded-lg border border-border-default bg-surface px-3.5 py-2 text-xs font-semibold text-text-secondary hover:text-text-primary shadow-2xs hover:bg-surface-hover transition cursor-pointer"
            >
              <UserCheck className="h-3.5 w-3.5 text-text-secondary" />
              <span>Account Requests</span>
            </button>
            {isSuperAdmin && (
              <button
                type="button"
                onClick={() => setCreateUserOpen(true)}
                className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-brand-500 px-3.5 py-2 text-xs font-semibold text-white shadow-2xs hover:bg-brand-600 transition cursor-pointer"
              >
                <UserPlus className="h-3.5 w-3.5" />
                <span>Create User</span>
              </button>
            )}
          </div>
        }
      />

      {/* Page Feedback Banner */}
      {pageFeedback && (
        <div
          className={`flex items-center gap-2 rounded-xl p-3 text-xs font-medium border ${
            pageFeedback.type === "success"
              ? "bg-surface-subtle text-text-primary border-border-default"
              : "bg-danger-subtle text-danger-text border-danger-border"
          }`}
        >
          {pageFeedback.type === "success" ? (
            <CheckCircle2 className="h-4 w-4 shrink-0 text-pct-high" />
          ) : (
            <AlertTriangle className="h-4 w-4 shrink-0 text-danger-icon" />
          )}
          <span>{pageFeedback.text}</span>
        </div>
      )}

      {/* Top KPI Metrics Grid */}
      <UserMetricsCards
        totalCount={totalCount}
        activeCount={activeCount}
        inactiveCount={inactiveCount}
        isLoading={isLoading}
      />

      {/* Directory Main Card */}
      <div className="space-y-4 rounded-xl border border-border-default bg-surface-base p-4 shadow-xs">
        {/* Segmented Control Tabs */}
        <div className="flex items-center justify-between border-b border-border-subtle pb-3">
          <div className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none" role="tablist" aria-label="User Status Tabs">
            <button
              type="button"
              role="tab"
              aria-selected={activeTab === "active"}
              onClick={() => setActiveTab("active")}
              className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                activeTab === "active"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <UserCheck
                className={`w-4 h-4 shrink-0 transition-colors ${
                  activeTab === "active"
                    ? "text-tab-active-text"
                    : "text-text-muted group-hover:text-text-secondary"
                }`}
              />
              <span>Active</span>
              <span
                className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-sans tabular-nums text-xs font-semibold shadow-2xs transition-colors ${
                  activeTab === "active"
                    ? "bg-brand-button text-white"
                    : "border border-border-default bg-surface-subtle text-text-secondary"
                }`}
              >
                {activeCount}
              </span>
            </button>

            <button
              type="button"
              role="tab"
              aria-selected={activeTab === "inactive"}
              onClick={() => setActiveTab("inactive")}
              className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                activeTab === "inactive"
                  ? "border-tab-active-border bg-tab-active-bg text-tab-active-text shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-border-default hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <UserX
                className={`w-4 h-4 shrink-0 transition-colors ${
                  activeTab === "inactive"
                    ? "text-tab-active-text"
                    : "text-text-muted group-hover:text-text-secondary"
                }`}
              />
              <span>Inactive</span>
              <span
                className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-sans tabular-nums text-xs font-semibold shadow-2xs transition-colors ${
                  activeTab === "inactive"
                    ? "bg-brand-button text-white"
                    : "border border-border-default bg-surface-subtle text-text-secondary"
                }`}
              >
                {inactiveCount}
              </span>
            </button>
          </div>
        </div>
      </div>

      {/* Main Directory Container */}
      <div className="space-y-4 rounded-xl border border-border-default bg-surface-base p-4 shadow-2xs">
        {/* Filters Row: Search Bar, Role Dropdown, and Group Dropdown on the same horizontal row */}
        <AdminFilterBar
          searchPlaceholder="Search by name, email, role, or scope..."
          searchVal={searchQuery}
          onSearchChange={(val) => {
            setSearchQuery(val);
            setPage(1);
          }}
          showApplyButton={false}
          showResetButton={Boolean(searchQuery || selectedRoleFilter !== "All" || selectedGroupFilter !== "All")}
          onReset={() => {
            setSearchQuery("");
            setSelectedRoleFilter("All");
            setSelectedGroupFilter("All");
            setPage(1);
          }}
          filterSlot={
            <div className="flex flex-wrap items-center gap-2">
              {/* Role Dropdown */}
              <div className="flex items-center gap-1.5">
                <label htmlFor="user-role-filter" className="text-xs font-semibold text-text-secondary whitespace-nowrap">
                  Role:
                </label>
                <select
                  id="user-role-filter"
                  value={selectedRoleFilter}
                  onChange={(e) => {
                    setSelectedRoleFilter(e.target.value);
                    setPage(1);
                  }}
                  className="h-9 rounded-lg border border-border-default bg-surface px-2.5 text-xs font-semibold text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
                >
                  {availableRoles.map((role) => (
                    <option key={role} value={role}>
                      {role}
                    </option>
                  ))}
                </select>
              </div>

              {/* Group Dropdown (placed right next to Role) */}
              <div className="flex items-center gap-1.5">
                <label htmlFor="user-group-filter" className="text-xs font-semibold text-text-secondary whitespace-nowrap">
                  Group:
                </label>
                <select
                  id="user-group-filter"
                  value={selectedGroupFilter}
                  onChange={(e) => {
                    setSelectedGroupFilter(e.target.value);
                    setPage(1);
                  }}
                  className="h-9 rounded-lg border border-border-default bg-surface px-2.5 text-xs font-semibold text-text-primary outline-none transition-colors focus:border-brand-500 cursor-pointer"
                >
                  <option value="All">All Groups</option>
                  {groups.map((g) => (
                    <option key={g.id} value={g.id}>
                      {g.name}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          }
        />

        {/* Data Table with compact row spacing, kebab menu, and standard bottom pagination */}
        <UsersTable
          users={paginatedUsers}
          selectedUser={selectedUser}
          onSelectUser={(u) => setSelectedUser(u)}
          isLoading={isLoading}
          canManageUser={canManageUser}
          page={page}
          pageSize={pageSize}
          totalCount={filteredUsers.length}
          onPageChange={(newPage) => setPage(newPage)}
          onPageSizeChange={(newSize) => {
            setPageSize(newSize);
            setPage(1);
          }}
          onToggleStatus={(u) => setStatusTargetUser(u)}
          onResetPassword={(u) => setResetPwTargetUser(u)}
          onArchiveUser={(u) => setArchiveTargetUser(u)}
          isSuperAdmin={isSuperAdmin}
        />
      </div>

      {/* User Detail & Edit Drawer */}
      <UserDetailDrawer
        user={selectedUser}
        onClose={() => setSelectedUser(null)}
        onSaved={() => {
          refetch();
          setSelectedUser(null);
        }}
      />

      {/* Create User Modal */}
      <CreateUserModal
        isOpen={createUserOpen}
        onClose={() => setCreateUserOpen(false)}
        onSuccess={() => {
          refetch();
        }}
      />

      {/* Account Requests Queue Modal */}
      <AccountRequestsModal
        isOpen={accountRequestsOpen}
        onClose={() => setAccountRequestsOpen(false)}
        isSuperAdmin={isSuperAdmin}
      />

      {/* Temporary Permission Overrides Management Modal */}
      <TempPermissionModal
        isOpen={tempPermissionOpen}
        onClose={() => {
          setTempPermissionOpen(false);
          refetch();
        }}
      />

      {/* Kebab Action Modal 1: Toggle Status */}
      <Modal
        isOpen={Boolean(statusTargetUser)}
        onClose={() => setStatusTargetUser(null)}
        title={statusTargetUser?.isActive ? "Deactivate User Access?" : "Activate User Access?"}
        isSubmitting={toggleStatusMutation.isPending}
        disableBackdropClick={toggleStatusMutation.isPending}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setStatusTargetUser(null)}
              className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleConfirmToggleStatus}
              disabled={toggleStatusMutation.isPending}
              className={`rounded-lg px-3.5 py-1.5 text-xs font-bold disabled:opacity-50 transition-colors cursor-pointer ${
                statusTargetUser?.isActive
                  ? "bg-danger-button hover:bg-danger-button-hover text-danger-button-text"
                  : "bg-brand-500 hover:bg-brand-600 text-white"
              }`}
            >
              {toggleStatusMutation.isPending
                ? "Updating..."
                : statusTargetUser?.isActive
                ? "Deactivate User"
                : "Activate User"}
            </button>
          </div>
        }
      >
        <p className="text-xs text-text-secondary">
          {statusTargetUser?.isActive
            ? `Deactivating ${statusTargetUser.fullName} will suspend their login privileges immediately.`
            : `Activating ${statusTargetUser?.fullName} will restore their login access.`}
        </p>
      </Modal>

      {/* Kebab Action Modal 2: Reset Password */}
      <Modal
        isOpen={Boolean(resetPwTargetUser)}
        onClose={() => setResetPwTargetUser(null)}
        title="Reset User Password?"
        isSubmitting={resetPasswordMutation.isPending}
        disableBackdropClick={resetPasswordMutation.isPending}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setResetPwTargetUser(null)}
              className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleConfirmResetPassword}
              disabled={resetPasswordMutation.isPending}
              className="rounded-lg bg-brand-500 px-3.5 py-1.5 text-xs font-bold text-white hover:bg-brand-600 disabled:opacity-50 transition-colors cursor-pointer"
            >
              {resetPasswordMutation.isPending ? "Sending..." : "Send Reset Email"}
            </button>
          </div>
        }
      >
        <p className="text-xs text-text-secondary">
          A password reset link will be dispatched to <strong>{resetPwTargetUser?.email}</strong>.
        </p>
      </Modal>

      {/* Kebab Action Modal 3: Archive User */}
      <Modal
        isOpen={Boolean(archiveTargetUser)}
        onClose={() => setArchiveTargetUser(null)}
        title="Archive User Account?"
        icon={AlertTriangle}
        isSubmitting={archiveMutation.isPending}
        disableBackdropClick={archiveMutation.isPending}
        maxWidthClass="max-w-md"
        footer={
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => setArchiveTargetUser(null)}
              className="rounded-lg border border-border-default bg-surface px-3 py-1.5 text-xs font-semibold text-text-secondary hover:bg-surface-hover transition-colors cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleConfirmArchiveUser}
              disabled={archiveMutation.isPending}
              className="rounded-lg bg-danger-button px-3.5 py-1.5 text-xs font-bold text-danger-button-text hover:bg-danger-button-hover disabled:opacity-50 transition-colors cursor-pointer"
            >
              {archiveMutation.isPending ? "Archiving..." : "Archive User"}
            </button>
          </div>
        }
      >
        <p className="text-xs text-text-secondary">
          Archiving <strong>{archiveTargetUser?.fullName}</strong> will disable authentication and move their record to the archival registry.
        </p>
      </Modal>
    </div>
  );
}
