"use client";

import { useMemo, useState } from "react";
import {
  RotateCcw,
  Search,
  UsersRound,
} from "lucide-react";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";
import { TeamDirectoryTable } from "@/components/team-directory/TeamDirectoryTable";
import { TeamDirectoryDetailDrawer } from "@/components/team-directory/TeamDirectoryDetailDrawer";
import {
  formatDirectoryName,
  useTeamDirectoryRoster,
  type TeamDirectoryErrorKind,
  type TeamDirectoryUser,
} from "@/lib/queries/team_directory";

export default function TeamDirectoryPage() {
  const [searchVal, setSearchVal] = useState("");
  const [selectedRole, setSelectedRole] = useState<string>("ALL");
  const [selectedGroup, setSelectedGroup] = useState<string>("ALL");
  const [selectedUser, setSelectedUser] = useState<TeamDirectoryUser | null>(
    null
  );

  const { allUsers, summary, isLoading, error, refetch } =
    useTeamDirectoryRoster();

  // Extract distinct sorted role names
  const roleOptions = useMemo(() => {
    const set = new Set<string>();
    allUsers.forEach((u) => {
      if (u.roleName?.trim()) set.add(u.roleName.trim());
    });
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }, [allUsers]);

  // Extract distinct sorted group names
  const groupOptions = useMemo(() => {
    const set = new Set<string>();
    allUsers.forEach((u) => {
      u.groupNames.forEach((g) => {
        if (g.trim()) set.add(g.trim());
      });
    });
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }, [allUsers]);

  // Multi-field filtered dataset
  const filteredUsers = useMemo(() => {
    const query = searchVal.trim().toLowerCase();

    return allUsers.filter((user) => {
      // Role filter
      if (selectedRole !== "ALL" && user.roleName !== selectedRole) {
        return false;
      }

      // Group filter
      if (
        selectedGroup !== "ALL" &&
        !user.groupNames.some(
          (g) => g.toLowerCase() === selectedGroup.toLowerCase()
        )
      ) {
        return false;
      }

      // Search query across multiple fields: Name, Email, Role, Contact, Group, Account
      if (query) {
        const nameFormatted = formatDirectoryName(user).toLowerCase();
        const display = user.displayName.toLowerCase();
        const full = (user.fullName ?? "").toLowerCase();
        const email = (user.email ?? "").toLowerCase();
        const mobile = (user.mobileNumber ?? "").toLowerCase();
        const role = user.roleName.toLowerCase();
        const inGroups = user.groupNames.some((g) =>
          g.toLowerCase().includes(query)
        );
        const inAccounts = user.accountNames.some((a) =>
          a.toLowerCase().includes(query)
        );

        const match =
          nameFormatted.includes(query) ||
          display.includes(query) ||
          full.includes(query) ||
          email.includes(query) ||
          mobile.includes(query) ||
          role.includes(query) ||
          inGroups ||
          inAccounts;

        if (!match) return false;
      }

      return true;
    });
  }, [allUsers, searchVal, selectedRole, selectedGroup]);

  // Handle error kind
  const errorKind: TeamDirectoryErrorKind | null = error
    ? (error as { kind?: TeamDirectoryErrorKind }).kind ?? "retryable"
    : null;

  const hasActiveFilters =
    Boolean(searchVal.trim()) ||
    selectedRole !== "ALL" ||
    selectedGroup !== "ALL";

  const handleResetFilters = () => {
    setSearchVal("");
    setSelectedRole("ALL");
    setSelectedGroup("ALL");
  };

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <AdminPageHeader
        categoryTag="ADMIN PANEL"
        moduleName="Team Directory"
        title="Team Directory"
        subtitle="Corporate operations, recruitment, and field leadership roster."
        icon={UsersRound}
        primaryAction={{
          label: "Refresh Roster",
          onClick: () => refetch(),
          disabled: isLoading,
          icon: RotateCcw,
        }}
      />

      {/* Top KPI Metrics Bar */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          label="Total Members"
          value={summary.totalMembers}
          helperText="Active directory profiles"
          isLoading={isLoading}
          isError={Boolean(error)}
        />
        <MetricCard
          label="Operations Leadership"
          value={summary.opsLeadershipCount}
          helperText="OM, TL & ATL field supervisors"
          isLoading={isLoading}
          isError={Boolean(error)}
        />
        <MetricCard
          label="HR Coordinators"
          value={summary.hrcoCount}
          helperText="Assigned store coordinators (HRCO)"
          isLoading={isLoading}
          isError={Boolean(error)}
        />
        <MetricCard
          label="Active Scopes"
          value={summary.activeScopesCount}
          helperText="Jurisdictions & store clusters"
          isLoading={isLoading}
          isError={Boolean(error)}
        />
      </div>

      {/* Filter & Multi-Field Search Bar */}
      <div className="flex flex-wrap items-center gap-2.5 rounded-md border border-border-default bg-surface-base p-3 shadow-2xs">
        {/* Search Input */}
        <label className="relative min-w-[280px] flex-1">
          <Search
            className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted"
            aria-hidden="true"
          />
          <input
            type="search"
            value={searchVal}
            onChange={(e) => setSearchVal(e.target.value)}
            placeholder="Search name, email, role, phone, group, or account..."
            className="h-10 w-full rounded-md border border-border-default bg-surface-muted pl-9 pr-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500 focus:bg-surface-base"
          />
        </label>

        {/* Role Filter Dropdown */}
        <div className="min-w-[160px]">
          <select
            value={selectedRole}
            onChange={(e) => setSelectedRole(e.target.value)}
            className="h-10 w-full rounded-md border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
            aria-label="Filter by Role"
          >
            <option value="ALL">All Roles ({roleOptions.length})</option>
            {roleOptions.map((role) => (
              <option key={role} value={role}>
                {role}
              </option>
            ))}
          </select>
        </div>

        {/* Group Scope Filter Dropdown */}
        <div className="min-w-[170px]">
          <select
            value={selectedGroup}
            onChange={(e) => setSelectedGroup(e.target.value)}
            className="h-10 w-full rounded-md border border-border-default bg-surface-base px-3 text-sm text-text-primary outline-none transition-colors focus:border-brand-500"
            aria-label="Filter by Group Scope"
          >
            <option value="ALL">All Groups ({groupOptions.length})</option>
            {groupOptions.map((grp) => (
              <option key={grp} value={grp}>
                {grp}
              </option>
            ))}
          </select>
        </div>

        {/* Reset Filter Button */}
        {hasActiveFilters && (
          <button
            type="button"
            onClick={handleResetFilters}
            className="inline-flex h-10 items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-3 text-sm font-medium text-text-muted hover:bg-surface-hover hover:text-text-primary transition-colors shadow-2xs"
            title="Reset active filters"
          >
            <RotateCcw className="h-3.5 w-3.5" />
            <span>Reset</span>
          </button>
        )}
      </div>

      {/* Directory Data Table */}
      <TeamDirectoryTable
        users={filteredUsers}
        selectedUserId={selectedUser?.authUserId ?? null}
        isLoading={isLoading}
        errorKind={errorKind}
        onSelectUser={(u) => setSelectedUser(u)}
        onRetry={() => refetch()}
      />

      {/* User Inspector & Reporting Tree Drawer */}
      <TeamDirectoryDetailDrawer
        isOpen={Boolean(selectedUser)}
        user={selectedUser}
        allUsers={allUsers}
        onClose={() => setSelectedUser(null)}
        onSelectUser={(u) => setSelectedUser(u)}
      />
    </div>
  );
}
