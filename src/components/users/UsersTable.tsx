"use client";

import {
  User,
  Lock,
} from "lucide-react";
import { StatusBadge } from "@/components/ui/StatusBadge";
import type { UserProfileItem } from "@/lib/queries/users";

export interface UsersTableProps {
  users: UserProfileItem[];
  selectedUser: UserProfileItem | null;
  onSelectUser: (user: UserProfileItem) => void;
  isLoading?: boolean;
  canManageUser: (user: UserProfileItem) => boolean;
}

export function UsersTable({
  users,
  selectedUser,
  onSelectUser,
  isLoading = false,
  canManageUser,
}: UsersTableProps) {
  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center rounded-lg border border-border-default bg-surface-base p-12 text-center">
        <div className="h-7 w-7 animate-spin rounded-full border-2 border-brand-600 border-t-transparent" />
        <p className="mt-3 text-sm font-medium text-text-secondary">Loading directory users...</p>
      </div>
    );
  }

  if (users.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center rounded-lg border border-border-default bg-surface-base p-12 text-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface-muted text-text-muted">
          <User className="h-6 w-6" />
        </div>
        <h3 className="mt-3 text-sm font-semibold text-text-primary">No users found</h3>
        <p className="mt-1 text-xs text-text-secondary">
          No user profiles match the selected tab or search criteria.
        </p>
      </div>
    );
  }

  return (
    <div className="overflow-hidden rounded-lg border border-border-default bg-surface-base shadow-xs">
      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b border-border-default bg-surface-muted/50 text-[11px] font-bold uppercase tracking-wider text-text-muted">
              <th className="px-4 py-3">User</th>
              <th className="px-4 py-3">Role</th>
              <th className="px-4 py-3">Assigned Scopes</th>
              <th className="px-4 py-3">Status</th>
              <th className="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-subtle">
            {users.map((user) => {
              const isSelected = selectedUser?.id === user.id;
              const manageable = canManageUser(user);

              return (
                <tr
                  key={user.id}
                  onClick={() => manageable && onSelectUser(user)}
                  className={`group transition-colors ${
                    manageable ? "cursor-pointer hover:bg-surface-hover/70" : "cursor-default opacity-90"
                  } ${isSelected ? "bg-brand-50/60 font-medium" : ""}`}
                >
                  {/* User Column */}
                  <td className="px-4 py-3.5">
                    <div className="flex items-center gap-3">
                      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand-50 text-sm font-bold text-brand-700 border border-brand-200 shadow-xs">
                        {user.normalizedName ? user.normalizedName[0].toUpperCase() : "?"}
                      </div>
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="truncate font-semibold text-text-primary">
                            {user.normalizedName || user.fullName}
                          </span>
                          {!user.isLinked && (
                            <span
                              title="No active login linked"
                              className="inline-flex items-center rounded-full bg-surface-subtle px-2 py-0.5 text-[10px] font-semibold text-text-secondary border border-border-default"
                            >
                              No login linked
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

                  {/* Assigned Scopes Column */}
                  <td className="px-4 py-3.5">
                    <div className="flex flex-col gap-1 max-w-sm">
                      {user.scopeSummaries.map((summary, idx) => (
                        <div
                          key={idx}
                          className="truncate text-xs font-medium text-text-secondary"
                          title={summary}
                        >
                          {summary}
                        </div>
                      ))}
                    </div>
                  </td>

                  {/* Status Column */}
                  <td className="px-4 py-3.5 whitespace-nowrap">
                    {user.status === "Active" ? (
                      <StatusBadge variant="success" text="Active" />
                    ) : user.status === "Suspended" ? (
                      <StatusBadge variant="warning" text="Suspended" />
                    ) : (
                      <StatusBadge variant="neutral" text="Archived" />
                    )}
                  </td>

                  {/* Actions Column */}
                  <td className="px-4 py-3.5 text-right whitespace-nowrap">
                    {manageable ? (
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          onSelectUser(user);
                        }}
                        className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 py-1.5 text-xs font-semibold text-text-secondary shadow-xs hover:bg-surface-hover hover:text-text-primary"
                      >
                        Inspect
                      </button>
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
    </div>
  );
}
