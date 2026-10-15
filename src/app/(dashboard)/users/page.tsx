"use client";

import { useState, useMemo } from "react";
import {
  AdminPageHeader,
} from "@/components/shared/AdminPageHeader";
import { AdminFilterBar } from "@/components/shared/AdminFilterBar";
import { UserMetricsCards } from "@/components/users/UserMetricsCards";
import { UsersTable } from "@/components/users/UsersTable";
import { UserDetailDrawer } from "@/components/users/UserDetailDrawer";
import { CreateUserModal } from "@/components/users/CreateUserModal";
import { useCurrentUser } from "@/lib/auth";
import {
  useUsersList,
  type UserProfileItem,
} from "@/lib/queries/users";
import { Users, UserPlus, ShieldAlert, UserCheck, UserX } from "lucide-react";

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

  // Tabs: "active" | "inactive"
  const [activeTab, setActiveTab] = useState<"active" | "inactive">("active");

  // Filters
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedRoleFilter, setSelectedRoleFilter] = useState("All");

  // Drawer & Modal selection state
  const [selectedUser, setSelectedUser] = useState<UserProfileItem | null>(null);
  const [createUserOpen, setCreateUserOpen] = useState(false);

  // Users Query
  const { data: allUsers = [], isLoading, refetch } = useUsersList();

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

  // Aggregate KPI counts
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

  // Tab & Search filtered list
  const filteredUsers = useMemo(() => {
    let list = visibleUsers;

    // 1. Tab filter
    if (activeTab === "active") {
      list = list.filter((u) => u.status === "Active");
    } else {
      list = list.filter((u) => u.status !== "Active");
    }

    // 2. Role filter
    if (selectedRoleFilter !== "All") {
      list = list.filter(
        (u) => u.roleName.toLowerCase() === selectedRoleFilter.toLowerCase(),
      );
    }

    // 3. Search query filter
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
  }, [visibleUsers, activeTab, selectedRoleFilter, searchQuery]);

  // Access denied fallback if caller role < 90
  if (!hasAccess && !isLoading) {
    return (
      <div className="flex h-96 flex-col items-center justify-center p-8 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-full bg-red-50 text-red-600 mb-4">
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
    <div className="space-y-6 p-6">
      {/* Top Header */}
      <AdminPageHeader
        title="User Management"
        subtitle="Manage user directories, organizational roles, and cascaded group/account scopes."
        icon={Users}
        actionSlot={
          isSuperAdmin ? (
            <button
              type="button"
              onClick={() => setCreateUserOpen(true)}
              className="inline-flex h-10 items-center gap-2 rounded-md bg-blue-600 px-4 text-sm font-semibold text-white shadow-xs transition-colors hover:bg-blue-700"
            >
              <UserPlus className="h-4 w-4" />
              Create User
            </button>
          ) : null
        }
      />

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
                  ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <UserCheck
                className={`w-4 h-4 shrink-0 transition-colors ${
                  activeTab === "active"
                    ? "text-brand-700"
                    : "text-text-muted group-hover:text-text-secondary"
                }`}
              />
              <span>Active</span>
              <span
                className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                  activeTab === "active"
                    ? "bg-brand-600 text-white"
                    : "bg-slate-100 text-slate-600 border border-slate-200/80"
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
                  ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                  : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
              }`}
            >
              <UserX
                className={`w-4 h-4 shrink-0 transition-colors ${
                  activeTab === "inactive"
                    ? "text-brand-700"
                    : "text-text-muted group-hover:text-text-secondary"
                }`}
              />
              <span>Inactive</span>
              <span
                className={`ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 font-mono text-xs font-semibold shadow-2xs transition-colors ${
                  activeTab === "inactive"
                    ? "bg-brand-600 text-white"
                    : "bg-slate-100 text-slate-600 border border-slate-200/80"
                }`}
              >
                {inactiveCount}
              </span>
            </button>
          </div>
        </div>

        {/* Search & Filter Toolbar */}
        <AdminFilterBar
          searchPlaceholder="Search by name, email, role, or scope..."
          searchVal={searchQuery}
          onSearchChange={setSearchQuery}
          showApplyButton={false}
          showResetButton={Boolean(searchQuery || selectedRoleFilter !== "All")}
          onReset={() => {
            setSearchQuery("");
            setSelectedRoleFilter("All");
          }}
          filterSlot={
            <div className="flex items-center gap-2">
              <label htmlFor="user-role-filter" className="text-xs font-semibold text-text-secondary whitespace-nowrap">
                Role:
              </label>
              <select
                id="user-role-filter"
                value={selectedRoleFilter}
                onChange={(e) => setSelectedRoleFilter(e.target.value)}
                className="h-10 rounded-md border border-border-default bg-surface-muted px-3 text-xs font-semibold text-text-primary outline-none transition-colors focus:border-brand-500"
              >
                {availableRoles.map((role) => (
                  <option key={role} value={role}>
                    {role}
                  </option>
                ))}
              </select>
            </div>
          }
        />

        {/* Data Table */}
        <UsersTable
          users={filteredUsers}
          selectedUser={selectedUser}
          onSelectUser={(u) => setSelectedUser(u)}
          isLoading={isLoading}
          canManageUser={canManageUser}
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
    </div>
  );
}
