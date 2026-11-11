"use client";

import { useState, useRef, useEffect } from "react";
import {
  User as UserIcon,
  Lock,
  MoreVertical,
  Power,
  KeyRound,
  Archive,
} from "lucide-react";
import type { UserProfileItem } from "@/lib/queries/users";
import { formatPersonName } from "@/lib/utils/displayText";
import { TablePagination } from "@/components/shared/TablePagination";

export interface UsersTableProps {
  users: UserProfileItem[];
  selectedUser: UserProfileItem | null;
  onSelectUser: (user: UserProfileItem) => void;
  isLoading?: boolean;
  canManageUser: (user: UserProfileItem) => boolean;
  // Pagination props
  page: number;
  pageSize: number;
  totalCount: number;
  onPageChange: (newPage: number) => void;
  onPageSizeChange: (newPageSize: number) => void;
  // Kebab action callbacks
  onToggleStatus?: (user: UserProfileItem) => void;
  onResetPassword?: (user: UserProfileItem) => void;
  onArchiveUser?: (user: UserProfileItem) => void;
  isSuperAdmin?: boolean;
}

export function UsersTable({
  users,
  selectedUser,
  onSelectUser,
  isLoading = false,
  canManageUser,
  page,
  pageSize,
  totalCount,
  onPageChange,
  onPageSizeChange,
  onToggleStatus,
  onResetPassword,
  onArchiveUser,
  isSuperAdmin = false,
}: UsersTableProps) {
  // Track open kebab menu for specific user id
  const [openKebabUserId, setOpenKebabUserId] = useState<string | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  // Close kebab menu on outside click or escape
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setOpenKebabUserId(null);
      }
    }
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setOpenKebabUserId(null);
      }
    }
    if (openKebabUserId) {
      document.addEventListener("mousedown", handleClickOutside);
      document.addEventListener("keydown", handleKeyDown);
    }
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [openKebabUserId]);

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center rounded-xl border border-border-default bg-surface-base p-12 text-center">
        <div className="h-7 w-7 animate-spin rounded-full border-2 border-brand-primary border-t-transparent" />
        <p className="mt-3 text-sm font-medium text-text-secondary">Loading directory users...</p>
      </div>
    );
  }

  if (totalCount === 0) {
    return (
      <div className="flex flex-col items-center justify-center rounded-xl border border-border-default bg-surface-base p-12 text-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-muted text-text-muted">
          <UserIcon className="h-6 w-6" />
        </div>
        <h3 className="mt-3 text-sm font-semibold text-text-primary">No users found</h3>
        <p className="mt-1 text-xs text-text-secondary">
          No user profiles match the selected filters or search criteria.
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-border-default bg-surface-base shadow-2xs">
      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b border-table-rule-section bg-table-header text-xs font-semibold text-text-secondary">
              <th className="px-4 py-2.5 whitespace-nowrap">User</th>
              <th className="px-4 py-2.5 whitespace-nowrap">Role</th>
              <th className="px-4 py-2.5 whitespace-nowrap">Group</th>
              <th className="px-4 py-2.5 whitespace-nowrap">Account</th>
              <th className="px-4 py-2.5 text-right whitespace-nowrap">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-subtle">
            {users.map((user) => {
              const isSelected = selectedUser?.id === user.id;
              const manageable = canManageUser(user);
              const isKebabOpen = openKebabUserId === user.id;

              // Derive readable group summary
              const distinctGroups = Array.from(
                new Set(user.scopes.map((s) => s.groupName).filter(Boolean) as string[]),
              );
              let groupText = "Global HQ";
              if (distinctGroups.length === 1) {
                groupText = distinctGroups[0];
              } else if (distinctGroups.length > 1) {
                groupText = `${distinctGroups[0]} (+${distinctGroups.length - 1})`;
              } else if (user.scopeLabel) {
                groupText = user.scopeLabel.split(",")[0].trim();
              }

              // Derive readable account summary
              const distinctAccounts = Array.from(
                new Set(user.scopes.map((s) => s.accountName).filter(Boolean) as string[]),
              );
              const hasAllAccounts = user.scopes.length === 0 || user.scopes.some((s) => !s.accountId);
              let accountText = hasAllAccounts ? "All Accounts" : "Unassigned";
              if (distinctAccounts.length === 1) {
                accountText = distinctAccounts[0];
              } else if (distinctAccounts.length > 1) {
                accountText = `${distinctAccounts[0]} (+${distinctAccounts.length - 1})`;
              }

              // User initials
              const displayName = formatPersonName(user.normalizedName || user.fullName);
              const initials = (user.normalizedName || user.fullName || "?")
                .split(/\s+/)
                .slice(0, 2)
                .map((part) => part[0]?.toUpperCase() || "")
                .join("") || "?";

              return (
                <tr
                  key={user.id}
                  onClick={() => manageable && onSelectUser(user)}
                  className={`group transition-colors ${
                    manageable ? "cursor-pointer hover:bg-surface-hover/70" : "cursor-default opacity-90"
                  } ${isSelected ? "bg-surface-selected font-medium" : ""}`}
                >
                  {/* User Column: Circular Avatar (Initials) + Full Name + Email below */}
                  <td className="px-4 py-2.5">
                    <div className="flex items-center gap-3">
                      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand-50 text-sm font-bold text-brand-700 border border-brand-200 shadow-xs">
                        {initials}
                      </div>
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="truncate font-semibold text-text-primary">
                            {displayName}
                          </span>
                          {!user.isLinked && (
                            <span
                              title="No active login linked"
                              className="inline-flex items-center rounded-full bg-surface-subtle px-2 py-0.5 text-[10px] font-semibold text-text-secondary border border-border-default"
                            >
                              No login
                            </span>
                          )}
                        </div>
                        <div className="truncate text-xs text-text-secondary">{user.email || "No email"}</div>
                      </div>
                    </div>
                  </td>

                  {/* Role Column */}
                  <td className="px-4 py-3.5 whitespace-nowrap">
                    <div className="flex items-center gap-1.5">
                      <span className="inline-flex items-center rounded-full bg-surface-subtle px-2.5 py-0.5 text-xs font-semibold text-text-primary border border-border-default">
                        {user.roleName || "No Role"}
                      </span>
                      {user.roleName === "HRCO" && (
                        <span
                          className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                            user.hrcoGlobalVisibility
                              ? "bg-brand-50 text-brand-700 border border-brand-200"
                              : "bg-surface-subtle text-text-secondary border border-border-default"
                          }`}
                        >
                          {user.hrcoGlobalVisibility ? "Global" : "Scoped"}
                        </span>
                      )}
                    </div>
                  </td>

                  {/* Group Column: Plain text */}
                  <td className="px-4 py-2.5 whitespace-nowrap">
                    <span className="text-xs font-medium text-text-secondary" title={distinctGroups.join(", ") || groupText}>
                      {groupText}
                    </span>
                  </td>

                  {/* Account Column: Plain text */}
                  <td className="px-4 py-2.5 whitespace-nowrap">
                    <span className="text-xs font-medium text-text-secondary" title={distinctAccounts.join(", ") || accountText}>
                      {accountText}
                    </span>
                  </td>

                  {/* Actions Column: Kebab menu (...) */}
                  <td className="px-4 py-2.5 text-right whitespace-nowrap">
                    {manageable ? (
                      <div className="relative inline-block text-left" ref={isKebabOpen ? menuRef : undefined}>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            setOpenKebabUserId((prev) => (prev === user.id ? null : user.id));
                          }}
                          aria-label={`Actions for ${displayName}`}
                          aria-expanded={isKebabOpen}
                          className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-border-default bg-surface text-text-secondary shadow-2xs hover:bg-surface-hover hover:text-text-primary transition-colors cursor-pointer"
                        >
                          <MoreVertical className="h-4 w-4" />
                        </button>

                        {isKebabOpen && (
                          <div
                            onClick={(e) => e.stopPropagation()}
                            className="absolute right-0 z-30 mt-1.5 w-48 rounded-xl border border-border-default bg-surface-base p-1.5 shadow-md focus:outline-none animate-fade-in"
                            role="menu"
                            aria-orientation="vertical"
                          >
                            <button
                              type="button"
                              onClick={() => {
                                setOpenKebabUserId(null);
                                onToggleStatus?.(user);
                              }}
                              className="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-text-primary hover:bg-surface-hover transition-colors cursor-pointer text-left"
                              role="menuitem"
                            >
                              <Power className="h-3.5 w-3.5 text-text-secondary" />
                              <span>{user.status === "Active" ? "Deactivate user" : "Activate user"}</span>
                            </button>

                            <button
                              type="button"
                              onClick={() => {
                                setOpenKebabUserId(null);
                                onResetPassword?.(user);
                              }}
                              className="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-text-primary hover:bg-surface-hover transition-colors cursor-pointer text-left"
                              role="menuitem"
                            >
                              <KeyRound className="h-3.5 w-3.5 text-text-secondary" />
                              <span>Reset password</span>
                            </button>

                            {isSuperAdmin && (
                              <button
                                type="button"
                                onClick={() => {
                                  setOpenKebabUserId(null);
                                  onArchiveUser?.(user);
                                }}
                                className="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs font-medium text-danger-text hover:bg-danger-subtle transition-colors cursor-pointer text-left"
                                role="menuitem"
                              >
                                <Archive className="h-3.5 w-3.5 text-danger-icon" />
                                <span>Archive user</span>
                              </button>
                            )}
                          </div>
                        )}
                      </div>
                    ) : (
                      <span className="inline-flex items-center gap-1 text-xs text-text-muted italic">
                        <Lock className="h-3 w-3" /> Locked
                      </span>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Standard bottom pagination */}
      <TablePagination
        page={page}
        pageSize={pageSize}
        totalCount={totalCount}
        pageSizeOptions={[10, 25, 50]}
        onPageChange={onPageChange}
        onPageSizeChange={onPageSizeChange}
        isLoading={isLoading}
      />
    </div>
  );
}
