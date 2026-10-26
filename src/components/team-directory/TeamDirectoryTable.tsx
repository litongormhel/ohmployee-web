"use client";

import { useState } from "react";
import Image from "next/image";
import {
  Check,
  ChevronLeft,
  ChevronRight,
  Copy,
  Mail,
  Network,
  Phone,
  Shield,
  Users,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import { DataState } from "@/components/shared/DataState";
import {
  formatDirectoryName,
  getBroadAccessScopeLabel,
  getRoleTint,
  getUserInitials,
  type TeamDirectoryErrorKind,
  type TeamDirectoryUser,
} from "@/lib/queries/team_directory";

const tableColumns = [
  "Member",
  "Role & Tier",
  "Contact",
  "Assigned Jurisdiction",
  "Actions",
];

export interface TeamDirectoryTableProps {
  users: TeamDirectoryUser[];
  selectedUserId: string | null;
  isLoading: boolean;
  errorKind: TeamDirectoryErrorKind | null;
  onSelectUser: (user: TeamDirectoryUser) => void;
  onRetry: () => void;
}

export function TeamDirectoryTable({
  users,
  selectedUserId,
  isLoading,
  errorKind,
  onSelectUser,
  onRetry,
}: TeamDirectoryTableProps) {
  const [page, setPage] = useState(1);
  const pageSize = 15;
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const totalCount = users.length;
  const pageCount = Math.max(1, Math.ceil(totalCount / pageSize));
  const currentPage = Math.min(page, pageCount);
  const startIndex = (currentPage - 1) * pageSize;
  const visibleUsers = users.slice(startIndex, startIndex + pageSize);

  const handleCopy = (e: React.MouseEvent, text: string, key: string) => {
    e.stopPropagation();
    if (!text) return;
    navigator.clipboard.writeText(text);
    setCopiedKey(key);
    setTimeout(() => {
      setCopiedKey((curr) => (curr === key ? null : curr));
    }, 2000);
  };

  const getStatusVariant = (status: string): BadgeVariant => {
    switch (status) {
      case "Available":
        return "success";
      case "Busy":
        return "warning";
      case "On Leave":
        return "info";
      default:
        return "neutral";
    }
  };

  return (
    <section className="flex min-h-[540px] flex-col rounded-md border border-table-rule-section bg-table-row shadow-xs">
      {/* Table Toolbar Header */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-table-rule-section px-4 py-3">
        <div className="flex items-center gap-2">
          <Users className="h-4 w-4 text-brand-600" aria-hidden="true" />
          <h2 className="text-base font-semibold text-table-text">
            Team Directory Roster
          </h2>
          <Badge className="font-mono text-[10px] text-table-text-muted bg-surface-muted hover:bg-surface-muted border-none">
            {totalCount} Active Members
          </Badge>
        </div>
        <div className="text-xs text-table-text-muted">
          Showing {totalCount === 0 ? 0 : startIndex + 1}–
          {Math.min(totalCount, startIndex + pageSize)} of {totalCount} contacts
        </div>
      </div>

      {/* Main Table Container */}
      <div className="min-h-0 flex-1 overflow-auto">
        <table className="w-full min-w-[1020px] border-separate border-spacing-0 text-left text-[0.9375rem]">
          <thead className="sticky top-0 z-10 bg-table-header text-xs font-semibold uppercase text-table-text-muted">
            <tr>
              {tableColumns.map((col, idx) => (
                <th
                  key={col || `col-${idx}`}
                  scope="col"
                  className={`border-b border-table-rule-section px-4 py-2.5 ${
                    col === "Actions" ? "text-right" : ""
                  }`}
                >
                  {col}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr>
                <td colSpan={tableColumns.length} className="px-3 py-16 text-center">
                  <DataState
                    kind="loading"
                    title="Loading team directory"
                    description="Fetching operational and leadership directory from Supabase RPC."
                  />
                </td>
              </tr>
            ) : errorKind ? (
              <tr>
                <td colSpan={tableColumns.length} className="px-3 py-16 text-center">
                  <DataState
                    kind={errorKind === "access_denied" ? "access_denied" : "error"}
                    title={
                      errorKind === "access_denied"
                        ? "Directory Access Restricted"
                        : "Directory Unavailable"
                    }
                    description={
                      errorKind === "access_denied"
                        ? "You are not authorized to view this team directory scope."
                        : "Unable to load team directory data. You can retry the request."
                    }
                    onRetry={onRetry}
                  />
                </td>
              </tr>
            ) : visibleUsers.length === 0 ? (
              <tr>
                <td colSpan={tableColumns.length} className="px-3 py-16 text-center">
                  <DataState
                    kind="empty"
                    title="No team members found"
                    description="No directory profiles match your active search and filter criteria."
                  />
                </td>
              </tr>
            ) : (
              visibleUsers.map((user) => {
                const isSelected = user.authUserId === selectedUserId;
                const formattedName = formatDirectoryName(user);
                const initials = getUserInitials(user);
                const roleTint = getRoleTint(user);
                const isAvailable = user.directoryStatus === "Available";
                const broadAccess = getBroadAccessScopeLabel(user);

                return (
                  <tr
                    key={user.authUserId}
                    onClick={() => onSelectUser(user)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault();
                        onSelectUser(user);
                      }
                    }}
                    tabIndex={0}
                    role="button"
                    aria-label={`View details for ${formattedName}`}
                    className={`group cursor-pointer border-b border-table-rule transition-colors outline-none focus-visible:bg-surface-hover ${
                      isSelected
                        ? "bg-brand-50/70 hover:bg-brand-50"
                        : "hover:bg-table-row-hover"
                    }`}
                  >
                    {/* MEMBER */}
                    <td className="border-b border-table-rule px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className="relative shrink-0">
                          {user.profilePhotoUrl ? (
                            <Image
                              src={user.profilePhotoUrl}
                              alt={formattedName}
                              width={40}
                              height={40}
                              unoptimized
                              className="h-10 w-10 rounded-full object-cover shadow-xs"
                            />
                          ) : (
                            <div
                              className="flex h-10 w-10 items-center justify-center rounded-full text-xs font-bold text-white shadow-xs"
                              style={{ backgroundColor: roleTint }}
                            >
                              {initials}
                            </div>
                          )}
                          {isAvailable && (
                            <span
                              className="absolute bottom-0 right-0 h-3 w-3 rounded-full border-2 border-white bg-pct-high"
                              title="Online / Available"
                            />
                          )}
                        </div>
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="font-semibold text-table-text truncate">
                              {formattedName}
                            </span>
                            <StatusBadge
                              variant={getStatusVariant(user.directoryStatus)}
                              className="text-[10px] py-0 px-1.5"
                            >
                              {user.directoryStatus}
                            </StatusBadge>
                          </div>
                          <div className="text-xs text-table-text-muted truncate mt-0.5">
                            {user.email || "No email registered"}
                          </div>
                        </div>
                      </div>
                    </td>

                    {/* ROLE & TIER */}
                    <td className="border-b border-table-rule px-4 py-3">
                      <div className="flex flex-col items-start gap-1">
                        <span className="font-medium text-table-text text-sm">
                          {user.roleName}
                        </span>
                        {user.roleLevel !== null && (
                          <span className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[10px] font-mono font-medium bg-surface-muted text-table-text-muted border border-border-subtle">
                            <Shield className="h-2.5 w-2.5" />
                            Tier {user.roleLevel}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* CONTACT */}
                    <td className="border-b border-table-rule px-4 py-3">
                      <div className="flex flex-col gap-1 text-xs">
                        {user.mobileNumber ? (
                          <div className="flex items-center gap-1.5 text-table-text">
                            <a
                              href={`tel:${user.mobileNumber}`}
                              onClick={(e) => e.stopPropagation()}
                              className="inline-flex items-center gap-1 text-brand-600 hover:underline"
                              title="Call phone"
                            >
                              <Phone className="h-3 w-3 shrink-0" />
                              <span>{user.mobileNumber}</span>
                            </a>
                            <button
                              type="button"
                              onClick={(e) =>
                                handleCopy(
                                  e,
                                  user.mobileNumber!,
                                  `phone-${user.authUserId}`
                                )
                              }
                              className="rounded p-0.5 text-table-text-muted hover:bg-surface-hover hover:text-table-text transition-colors"
                              title="Copy phone"
                            >
                              {copiedKey === `phone-${user.authUserId}` ? (
                                <Check className="h-3 w-3 text-pct-high" />
                              ) : (
                                <Copy className="h-3 w-3" />
                              )}
                            </button>
                          </div>
                        ) : (
                          <span className="text-table-text-muted text-[11px]">
                            No mobile
                          </span>
                        )}

                        {user.email ? (
                          <div className="flex items-center gap-1.5 text-table-text-muted">
                            <a
                              href={`mailto:${user.email}`}
                              onClick={(e) => e.stopPropagation()}
                              className="inline-flex items-center gap-1 hover:text-brand-600 truncate max-w-[180px]"
                              title="Send email"
                            >
                              <Mail className="h-3 w-3 shrink-0" />
                              <span className="truncate">{user.email}</span>
                            </a>
                            <button
                              type="button"
                              onClick={(e) =>
                                handleCopy(
                                  e,
                                  user.email!,
                                  `email-${user.authUserId}`
                                )
                              }
                              className="rounded p-0.5 text-table-text-muted hover:bg-surface-hover hover:text-table-text transition-colors shrink-0"
                              title="Copy email"
                            >
                              {copiedKey === `email-${user.authUserId}` ? (
                                <Check className="h-3 w-3 text-pct-high" />
                              ) : (
                                <Copy className="h-3 w-3" />
                              )}
                            </button>
                          </div>
                        ) : null}
                      </div>
                    </td>

                    {/* ASSIGNED JURISDICTION */}
                    <td className="border-b border-table-rule px-4 py-3">
                      {broadAccess ? (
                        <Badge className="border-border-default bg-surface-subtle text-text-primary text-xs font-medium">
                          {broadAccess}
                        </Badge>
                      ) : user.groupNames.length === 0 &&
                        user.accountNames.length === 0 ? (
                        <span className="text-xs text-table-text-muted italic">
                          No scope assigned
                        </span>
                      ) : (
                        <div className="flex flex-col gap-1 max-w-[240px]">
                          {user.groupNames.length > 0 && (
                            <div className="flex flex-wrap gap-1">
                              {user.groupNames.slice(0, 2).map((group) => (
                                <span
                                  key={group}
                                  className="inline-block rounded bg-surface-muted px-1.5 py-0.5 text-[11px] font-medium text-table-text border border-border-subtle truncate max-w-[120px]"
                                  title={group}
                                >
                                  {group}
                                </span>
                              ))}
                              {user.groupNames.length > 2 && (
                                <span className="inline-block rounded bg-surface-muted px-1.5 py-0.5 text-[10px] text-table-text-muted">
                                  +{user.groupNames.length - 2} more
                                </span>
                              )}
                            </div>
                          )}

                          {user.accountNames.length > 0 && (
                            <div className="flex flex-wrap gap-1">
                              {user.accountNames.slice(0, 2).map((acc) => (
                                <span
                                  key={acc}
                                  className="inline-block rounded bg-surface-subtle border border-border-default px-1.5 py-0.5 text-[10px] font-medium text-text-secondary truncate max-w-[120px]"
                                  title={acc}
                                >
                                  {acc}
                                </span>
                              ))}
                              {user.accountNames.length > 2 && (
                                <span className="inline-block rounded bg-surface-muted px-1.5 py-0.5 text-[10px] text-table-text-muted">
                                  +{user.accountNames.length - 2} accounts
                                </span>
                              )}
                            </div>
                          )}
                        </div>
                      )}
                    </td>

                    {/* ACTIONS */}
                    <td className="border-b border-table-rule px-4 py-3 text-right">
                      <div className="inline-flex items-center gap-1.5">
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            onSelectUser(user);
                          }}
                          className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2.5 py-1.5 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover hover:text-text-primary transition-colors"
                          title="View Reporting Hierarchy & Details"
                        >
                          <Network className="h-3.5 w-3.5 text-brand-600" />
                          <span className="hidden sm:inline">Hierarchy</span>
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination Footer */}
      {!isLoading && !errorKind && totalCount > pageSize && (
        <div className="flex items-center justify-between border-t border-table-rule-section px-4 py-3 text-xs text-table-text-muted">
          <div>
            Page <span className="font-semibold text-table-text">{currentPage}</span> of{" "}
            <span className="font-semibold text-table-text">{pageCount}</span>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              disabled={currentPage <= 1}
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-50 transition-colors"
            >
              <ChevronLeft className="h-3.5 w-3.5" />
              Previous
            </button>
            <button
              type="button"
              disabled={currentPage >= pageCount}
              onClick={() => setPage((p) => Math.min(pageCount, p + 1))}
              className="inline-flex items-center gap-1 rounded-md border border-border-default bg-surface-base px-2.5 py-1 text-xs font-medium text-text-secondary shadow-2xs hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-50 transition-colors"
            >
              Next
              <ChevronRight className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
