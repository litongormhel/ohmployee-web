"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import {
  Briefcase,
  Building2,
  Check,
  ChevronRight,
  Copy,
  ExternalLink,
  FileText,
  Mail,
  MapPin,
  MessageSquare,
  Network,
  Phone,
  Shield,
  Users,
} from "lucide-react";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import { Badge } from "@/components/ui/badge";
import { StatusBadge, type BadgeVariant } from "@/components/ui/StatusBadge";
import {
  formatDirectoryName,
  getBroadAccessScopeLabel,
  getDisplayAccountNames,
  getDisplayGroupNames,
  getReportingStructure,
  getRoleTint,
  getUserInitials,
  getUserScopeSummary,
  type TeamDirectoryUser,
} from "@/lib/queries/team_directory";

export interface TeamDirectoryDetailDrawerProps {
  isOpen: boolean;
  user: TeamDirectoryUser | null;
  allUsers: TeamDirectoryUser[];
  onClose: () => void;
  onSelectUser: (user: TeamDirectoryUser) => void;
}

function RoleIconBadge({ role, level, className }: { role: string; level: number | null; className?: string }) {
  const r = role.toLowerCase();
  if (level === 100 || r.includes("super admin") || r.includes("head admin")) {
    return <Shield className={className} />;
  }
  if (r.includes("om") || r.includes("operations manager") || r.includes("team leader")) {
    return <Briefcase className={className} />;
  }
  if (r.includes("recruitment") || r.includes("hrco") || r.includes("coordinator")) {
    return <Users className={className} />;
  }
  return <FileText className={className} />;
}

export function TeamDirectoryDetailDrawer({
  isOpen,
  user,
  allUsers,
  onClose,
  onSelectUser,
}: TeamDirectoryDetailDrawerProps) {
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const reportingStructure = useMemo(() => {
    if (!user) return { reportsTo: [], directReports: [] };
    return getReportingStructure(user, allUsers);
  }, [user, allUsers]);

  if (!user) return null;

  const formattedName = formatDirectoryName(user);
  const initials = getUserInitials(user);
  const roleTint = getRoleTint(user);
  const broadAccess = getBroadAccessScopeLabel(user);
  const isAvailable = user.directoryStatus === "Available";
  const displayGroups = getDisplayGroupNames(user);
  const displayAccounts = getDisplayAccountNames(user);

  const handleCopy = (text: string, key: string) => {
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

  const isOpsOrHrco =
    user.roleName.toLowerCase().includes("hrco") ||
    user.roleName.toLowerCase().includes("team leader") ||
    user.roleName.toLowerCase().includes("operations") ||
    user.roleLevel === 30 ||
    user.roleLevel === 40 ||
    user.roleLevel === 70;

  return (
    <DetailDrawer
      isOpen={isOpen}
      onClose={onClose}
      title={formattedName}
      subtitle={
        <span className="flex items-center gap-1.5 font-medium">
          <span>{user.roleName}</span>
          {user.roleLevel !== null && (
            <>
              <span>•</span>
              <span className="font-mono">Tier {user.roleLevel}</span>
            </>
          )}
        </span>
      }
      badge={
        <div className="flex items-center gap-2">
          <StatusBadge
            variant={getStatusVariant(user.directoryStatus)}
            className="text-[11px]"
          >
            {user.directoryStatus}
          </StatusBadge>
          {broadAccess && (
            <Badge className="border-border-default bg-surface-subtle text-text-primary text-[10px]">
              {broadAccess}
            </Badge>
          )}
        </div>
      }
      widthClass="w-[560px] max-w-full"
    >
      <div className="space-y-5">
        {/* Identity Header Card */}
        <div className="rounded-lg border border-border-default bg-surface-muted/50 p-4 shadow-2xs">
          <div className="flex items-start gap-4">
            {/* Large Avatar */}
            <div className="relative shrink-0">
              {user.profilePhotoUrl ? (
                <Image
                  src={user.profilePhotoUrl}
                  alt={formattedName}
                  width={64}
                  height={64}
                  unoptimized
                  className="h-16 w-16 rounded-full object-cover shadow-sm ring-2 ring-white"
                />
              ) : (
                <div
                  className="flex h-16 w-16 items-center justify-center rounded-full text-xl font-bold text-white shadow-sm ring-2 ring-white"
                  style={{ backgroundColor: roleTint }}
                >
                  {initials}
                </div>
              )}
              {isAvailable && (
                <span
                  className="absolute bottom-0 right-0 h-4 w-4 rounded-full border-2 border-white bg-pct-high shadow-2xs"
                  title="Online / Available"
                />
              )}
            </div>

            {/* Profile Meta */}
            <div className="min-w-0 flex-1">
              <h3 className="text-lg font-bold text-text-primary truncate">
                {formattedName}
              </h3>
              <div className="mt-1 flex items-center gap-2">
                <div className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-muted px-2 py-0.5 text-xs font-semibold text-text-primary">
                  <RoleIconBadge role={user.roleName} level={user.roleLevel} className="h-3.5 w-3.5 text-text-muted shrink-0" />
                  <span>{user.roleName}</span>
                  {user.roleLevel !== null && (
                    <span className="font-mono text-[10px] text-text-muted border-l border-border-subtle pl-1.5">
                      L{user.roleLevel}
                    </span>
                  )}
                </div>
              </div>

              {/* Quick Contact Links */}
              <div className="mt-3 flex flex-wrap gap-2 text-xs">
                {user.mobileNumber && (
                  <div className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2 py-1 shadow-2xs">
                    <Phone className="h-3 w-3 text-brand-600" />
                    <span className="text-text-primary font-medium">
                      {user.mobileNumber}
                    </span>
                    <button
                      type="button"
                      onClick={() =>
                        handleCopy(user.mobileNumber!, "drawer-phone")
                      }
                      className="ml-1 rounded p-0.5 text-text-muted hover:text-text-primary"
                      title="Copy phone"
                    >
                      {copiedKey === "drawer-phone" ? (
                        <Check className="h-3 w-3 text-pct-high" />
                      ) : (
                        <Copy className="h-3 w-3" />
                      )}
                    </button>
                  </div>
                )}

                {user.email && (
                  <div className="inline-flex items-center gap-1.5 rounded-md border border-border-default bg-surface-base px-2 py-1 shadow-2xs">
                    <Mail className="h-3 w-3 text-brand-600" />
                    <span className="text-text-primary font-medium truncate max-w-[180px]">
                      {user.email}
                    </span>
                    <button
                      type="button"
                      onClick={() => handleCopy(user.email!, "drawer-email")}
                      className="ml-1 rounded p-0.5 text-text-muted hover:text-text-primary"
                      title="Copy email"
                    >
                      {copiedKey === "drawer-email" ? (
                        <Check className="h-3 w-3 text-pct-high" />
                      ) : (
                        <Copy className="h-3 w-3" />
                      )}
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Jurisdiction & Scope Summary Card */}
        <div className="rounded-lg border border-border-default bg-surface-base p-4 shadow-2xs">
          <div className="flex items-center justify-between border-b border-border-subtle pb-2.5 mb-3">
            <div className="flex items-center gap-2">
              <Building2 className="h-4 w-4 text-brand-600" />
              <h4 className="text-sm font-semibold text-text-primary">
                Assigned Jurisdiction
              </h4>
            </div>
            {isOpsOrHrco && (
              <Link
                href={`/plantilla?search=${encodeURIComponent(
                  user.lastName || user.displayName
                )}`}
                className="inline-flex items-center gap-1 text-xs font-semibold text-brand-600 hover:text-brand-700 hover:underline"
                title="View assigned roster in Plantilla"
              >
                <span>View Workforce</span>
                <ExternalLink className="h-3 w-3" />
              </Link>
            )}
          </div>

          <div className="space-y-3 text-xs">
            {/* Groups */}
            <div>
              <div className="text-xs font-semibold text-text-muted mb-1.5">
                CENCOM Groups ({displayGroups.length})
              </div>
              {displayGroups.length === 0 ? (
                <div className="text-text-muted italic">No groups assigned</div>
              ) : (
                <div className="flex flex-wrap gap-1.5">
                  {displayGroups.map((group) => (
                    <span
                      key={group}
                      className="inline-flex items-center gap-1 rounded-md bg-surface-subtle border border-border-default px-2 py-1 font-medium text-text-primary"
                    >
                      <MapPin className="h-3 w-3 text-text-secondary" />
                      {group}
                    </span>
                  ))}
                </div>
              )}
            </div>

            {/* Accounts */}
            <div>
              <div className="text-xs font-semibold text-text-muted mb-1.5">
                Accounts ({displayAccounts.length})
              </div>
              {displayAccounts.length === 0 ? (
                <div className="text-text-muted italic">No accounts assigned</div>
              ) : (
                <div className="flex flex-wrap gap-1.5 max-h-[140px] overflow-y-auto pr-1">
                  {displayAccounts.map((account) => (
                    <Link
                      key={account}
                      href={`/plantilla?account=${encodeURIComponent(account)}`}
                      className="group inline-flex items-center gap-1 rounded-md bg-surface-subtle border border-border-default px-2 py-1 font-medium text-text-secondary hover:bg-surface-hover hover:border-border-strong transition-colors"
                      title={`Jump to Plantilla for ${account}`}
                    >
                      <span>{account}</span>
                      <ExternalLink className="h-2.5 w-2.5 opacity-60 group-hover:opacity-100" />
                    </Link>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Reporting Structure Section */}
        <div className="rounded-lg border border-border-default bg-surface-base p-4 shadow-2xs space-y-4">
          <div className="flex items-center gap-2 border-b border-border-subtle pb-2.5">
            <Network className="h-4 w-4 text-brand-600" />
            <h4 className="text-sm font-semibold text-text-primary">
              Operational Reporting Lines
            </h4>
          </div>

          {/* Reports To Section */}
          <div>
            <div className="text-xs font-semibold text-text-muted mb-2">
              Reports to (supervisor)
            </div>
            {reportingStructure.reportsTo.length === 0 ? (
              <div className="rounded-md border border-dashed border-border-default bg-surface-muted/40 p-3 text-center text-xs text-text-muted">
                No direct supervisor found in current scope.
              </div>
            ) : (
              <div className="space-y-2">
                {reportingStructure.reportsTo.map((supervisor) => {
                  const sName = formatDirectoryName(supervisor);
                  const sInitials = getUserInitials(supervisor);
                  const sTint = getRoleTint(supervisor);
                  const sScope = getUserScopeSummary(supervisor);

                  return (
                    <div
                      key={supervisor.authUserId}
                      onClick={() => onSelectUser(supervisor)}
                      role="button"
                      tabIndex={0}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          onSelectUser(supervisor);
                        }
                      }}
                      className="group flex cursor-pointer items-center justify-between rounded-lg border border-border-default bg-surface-muted/30 p-2.5 hover:bg-surface-hover hover:border-brand-300 transition-all shadow-2xs"
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        <div
                          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white shadow-2xs"
                          style={{ backgroundColor: sTint }}
                        >
                          {sInitials}
                        </div>
                        <div className="min-w-0">
                          <div className="text-xs font-bold text-text-primary truncate group-hover:text-brand-600">
                            {sName}
                          </div>
                          <div className="text-xs text-text-secondary truncate">
                            {supervisor.roleName}
                            {sScope !== "No scope assigned" && ` • ${sScope}`}
                          </div>
                        </div>
                      </div>
                      <ChevronRight className="h-4 w-4 text-text-muted group-hover:text-brand-600 shrink-0 ml-2" />
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Direct Reports Section */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-semibold text-text-muted">
                Direct reports ({reportingStructure.directReports.length})
              </span>
            </div>
            {reportingStructure.directReports.length === 0 ? (
              <div className="rounded-md border border-dashed border-border-default bg-surface-muted/40 p-3 text-center text-xs text-text-muted">
                No direct subordinates assigned in this cluster.
              </div>
            ) : (
              <div className="space-y-2 max-h-[220px] overflow-y-auto pr-1">
                {reportingStructure.directReports.map((subordinate) => {
                  const subName = formatDirectoryName(subordinate);
                  const subInitials = getUserInitials(subordinate);
                  const subTint = getRoleTint(subordinate);
                  const subScope = getUserScopeSummary(subordinate);

                  return (
                    <div
                      key={subordinate.authUserId}
                      onClick={() => onSelectUser(subordinate)}
                      role="button"
                      tabIndex={0}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === " ") {
                          e.preventDefault();
                          onSelectUser(subordinate);
                        }
                      }}
                      className="group flex cursor-pointer items-center justify-between rounded-lg border border-border-default bg-surface-muted/30 p-2.5 hover:bg-surface-hover hover:border-brand-300 transition-all shadow-2xs"
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        <div
                          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white shadow-2xs"
                          style={{ backgroundColor: subTint }}
                        >
                          {subInitials}
                        </div>
                        <div className="min-w-0">
                          <div className="text-xs font-bold text-text-primary truncate group-hover:text-brand-600">
                            {subName}
                          </div>
                          <div className="text-[11px] text-text-secondary truncate">
                            {subordinate.roleName}
                            {subScope !== "No scope assigned" && ` • ${subScope}`}
                          </div>
                        </div>
                      </div>
                      <ChevronRight className="h-4 w-4 text-text-muted group-hover:text-brand-600 shrink-0 ml-2" />
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        {/* Primary Contact Action Strip */}
        <div className="rounded-lg border border-border-default bg-surface-base p-3 shadow-2xs">
          <div className="text-[11px] font-bold text-text-muted tracking-wider mb-2">
            Direct Communications
          </div>
          <div className="grid grid-cols-3 gap-2">
            <a
              href={user.mobileNumber ? `tel:${user.mobileNumber}` : undefined}
              className={`inline-flex items-center justify-center gap-1.5 rounded-md border border-border-default px-3 py-2 text-xs font-semibold shadow-2xs transition-colors ${
                user.mobileNumber
                  ? "bg-surface-base text-brand-600 hover:bg-surface-hover hover:border-brand-400"
                  : "bg-surface-muted text-text-muted cursor-not-allowed opacity-60"
              }`}
              title={user.mobileNumber ? "Call via phone" : "No phone available"}
            >
              <Phone className="h-3.5 w-3.5" />
              <span>Call</span>
            </a>

            <a
              href={user.mobileNumber ? `sms:${user.mobileNumber}` : undefined}
              className={`inline-flex items-center justify-center gap-1.5 rounded-md border border-border-default px-3 py-2 text-xs font-semibold shadow-2xs transition-colors ${
                user.mobileNumber
                  ? "bg-surface-base text-brand-600 hover:bg-surface-hover hover:border-brand-400"
                  : "bg-surface-muted text-text-muted cursor-not-allowed opacity-60"
              }`}
              title={user.mobileNumber ? "Send SMS" : "No mobile available"}
            >
              <MessageSquare className="h-3.5 w-3.5" />
              <span>SMS</span>
            </a>

            <a
              href={user.email ? `mailto:${user.email}` : undefined}
              className={`inline-flex items-center justify-center gap-1.5 rounded-md border border-border-default px-3 py-2 text-xs font-semibold shadow-2xs transition-colors ${
                user.email
                  ? "bg-surface-base text-brand-600 hover:bg-surface-hover hover:border-brand-400"
                  : "bg-surface-muted text-text-muted cursor-not-allowed opacity-60"
              }`}
              title={user.email ? "Send email" : "No email available"}
            >
              <Mail className="h-3.5 w-3.5" />
              <span>Email</span>
            </a>
          </div>
        </div>
      </div>
    </DetailDrawer>
  );
}
