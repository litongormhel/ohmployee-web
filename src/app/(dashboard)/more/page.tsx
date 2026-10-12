"use client";

import { useMemo, useState, type ComponentType } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Archive,
  ArrowRight,
  Briefcase,
  Building2,
  CheckCircle2,
  Clock,
  FileSpreadsheet,
  FileText,
  FolderSync,
  History,
  Key,
  Layers,
  Lock,
  LogOut,
  RotateCcw,
  Settings,
  Shield,
  ShieldAlert,
  ShieldCheck,
  Sliders,
  Trash2,
  TrendingUp,
  UserCheck,
  UserMinus,
  UserPlus,
  Users,
  Users2,
  Wrench,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import { useRequestCategoryCounts } from "@/lib/queries/requests";
import { useActiveTempPermission } from "@/lib/queries/more";
import { createClient } from "@/lib/supabase/client";

import { EditLockControlModal } from "@/components/more/EditLockControlModal";
import { TempPermissionModal } from "@/components/more/TempPermissionModal";
import { DataArchivalCenterModal } from "@/components/more/DataArchivalCenterModal";

// ============================================================================
// Tile Definitions & Role Configuration
// ============================================================================

export type MoreSectionKey =
  | "team_directory"
  | "admin_tools"
  | "request_center"
  | "access_management"
  | "data_control"
  | "system_settings";

export interface MoreFeatureTile {
  id: string;
  title: string;
  description: string;
  icon: ComponentType<{ className?: string }>;
  href?: string;
  onClick?: () => void;
  section: MoreSectionKey;
  badgeCount?: number;
  badgeLabel?: string;
  badgeVariant?: "blue" | "amber" | "emerald" | "rose" | "purple";
  isGated?: boolean;
  minRoleLevel?: number;
  rolesAllowed?: string[];
}

export default function MorePage() {
  const router = useRouter();
  const currentUser = useCurrentUser();
  const { data: requestCounts } = useRequestCategoryCounts();
  const { data: activeTempAccess, refetch: refetchTempAccess } = useActiveTempPermission(
    currentUser?.profileId ?? null
  );

  // Modals
  const [isEditLockModalOpen, setIsEditLockModalOpen] = useState(false);
  const [isTempPermModalOpen, setIsTempPermModalOpen] = useState(false);
  const [isArchivalModalOpen, setIsArchivalModalOpen] = useState(false);
  const [isLoggingOut, setIsLoggingOut] = useState(false);

  // Derive Normalized Role & Levels
  const roleName = currentUser?.roleName ?? currentUser?.roleKey ?? "Viewer";
  const normalizedRole = roleName.toLowerCase().replace(/[^a-z0-9]/g, "_");

  const isSuperAdmin =
    normalizedRole === "super_admin" ||
    normalizedRole.includes("superadmin") ||
    normalizedRole === "owner";

  const isHeadAdmin =
    isSuperAdmin ||
    normalizedRole === "head_admin" ||
    normalizedRole.includes("headadmin");

  const isEncoder = normalizedRole === "encoder";
  const isOperationsManager = normalizedRole === "om" || normalizedRole === "operations_manager";
  const isOpsTeam =
    isOperationsManager ||
    normalizedRole === "atl" ||
    normalizedRole === "tl" ||
    normalizedRole === "hrco";

  // Numeric Role Level approximation matching mobile:
  // Super Admin: 100, Head Admin: 90, Operations/Data: 30-80, Viewer: 0
  const roleLevel = isSuperAdmin ? 100 : isHeadAdmin ? 90 : isEncoder ? 30 : isOpsTeam ? 50 : 10;

  // Sign out handler
  const handleLogout = async () => {
    setIsLoggingOut(true);
    try {
      const supabase = createClient();
      await supabase.auth.signOut();
      router.push("/login");
    } catch {
      router.push("/login");
    }
  };

  // Build tile definitions
  const allTiles: MoreFeatureTile[] = useMemo(() => {
    const list: MoreFeatureTile[] = [
      // ── 1. Team Directory ────────────────────────────────────────────────
      {
        id: "team_directory",
        title: "Team Directory",
        description: "Find and contact Ops, Recruitment, and Data Team users",
        icon: Users2,
        href: "/team-directory",
        section: "team_directory",
      },

      // ── 2. Admin Tools (Super Admin Level 100 Gate) ──────────────────────
      {
        id: "ohms_safespace",
        title: "OHM's Safespace",
        description: "Owner command center — system controls, risk, and diagnostics",
        icon: ShieldAlert,
        href: "/admin/safespace",
        section: "admin_tools",
        minRoleLevel: 100,
        badgeLabel: "Level 100",
        badgeVariant: "rose",
      },
      {
        id: "switch_role",
        title: "Switch Role",
        description: "Act as a different role with scoped access for testing",
        icon: Sliders,
        onClick: () => {
          alert("Role switcher is enabled in Super Admin development environment.");
        },
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "qa_center",
        title: "QA Center",
        description: "Read QA health, runs, findings, schedules, and reports",
        icon: CheckCircle2,
        href: "/reports",
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "permission_matrix",
        title: "Permission Matrix",
        description: "Edit role permissions with audited overrides",
        icon: Key,
        href: "/settings",
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "role_permissions",
        title: "Role Permissions",
        description: "Read-only backend authorization matrix",
        icon: ShieldCheck,
        href: "/settings",
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "permission_drift",
        title: "Permission Drift",
        description: "Authorization gap and mismatch findings",
        icon: TrendingUp,
        href: "/reports",
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "security_events",
        title: "Security Events",
        description: "Security activity, threat indicators, and auth alerts",
        icon: Shield,
        href: "/settings",
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "allocation_health",
        title: "Workforce Integrity",
        description: "Allocation, roving, import, and CENCOM operational health checks",
        icon: Layers,
        href: "/cencom",
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "audit_logs",
        title: "Audit Logs",
        description: "System activity, audit trails, and data changes",
        icon: History,
        href: "/settings",
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "access_control_center",
        title: "Access Control Center",
        description: "Module visibility overrides per user (OHM2026_3001)",
        icon: Wrench,
        href: "/users",
        section: "admin_tools",
        minRoleLevel: 100,
      },
      {
        id: "data_archival_center",
        title: "Data Archival Center",
        description: "Archive and rollback operational data with audit controls",
        icon: Archive,
        onClick: () => setIsArchivalModalOpen(true),
        section: "admin_tools",
        minRoleLevel: 100,
      },

      // ── 3. Request Center ────────────────────────────────────────────────
      {
        id: "my_requests",
        title: "My Requests",
        description: "Track status of your submitted requisitions and requests",
        icon: Clock,
        href: "/approvals",
        section: "request_center",
        badgeCount: 0,
      },
      {
        id: "new_store_request",
        title: "New Stores",
        description: "Review store creation request status and branch onboarding",
        icon: Building2,
        href: "/approvals?tab=new_stores",
        section: "request_center",
        badgeCount: requestCounts?.new_stores ?? 0,
        badgeVariant: "amber",
        rolesAllowed: ["super_admin", "head_admin"],
      },
      {
        id: "headcount_requests",
        title: "Headcount",
        description: "Review quota amendments, expansions, and replacements",
        icon: Users,
        href: "/approvals?tab=headcount",
        section: "request_center",
        badgeCount: requestCounts?.headcount ?? 0,
        badgeVariant: "blue",
      },
      {
        id: "coverage_requests",
        title: "Coverage",
        description: "Draft and review structure-only roving coverage changes",
        icon: FolderSync,
        href: "/approvals?tab=coverage",
        section: "request_center",
        badgeCount: requestCounts?.coverage ?? 0,
        badgeVariant: "purple",
      },
      {
        id: "vacancy_closure",
        title: "Vacancy Closures",
        description: "Review closure and requisition retirement requests",
        icon: Archive,
        href: "/approvals?tab=vacancy_closures",
        section: "request_center",
        badgeCount: requestCounts?.vacancy_closures ?? 0,
        badgeVariant: "rose",
      },
      {
        id: "emploc_deletion",
        title: "HR Emploc Deletions",
        description: "Review HR Emploc assignment deletion requests",
        icon: Trash2,
        href: "/approvals?tab=hr_emploc_deletions",
        section: "request_center",
        badgeCount: requestCounts?.hr_emploc_deletions ?? 0,
        badgeVariant: "rose",
      },
      {
        id: "deactivation",
        title: "Deactivations",
        description: "Manage employee separation clearance and deactivation requests",
        icon: UserMinus,
        href: "/approvals?tab=deactivations",
        section: "request_center",
        badgeCount: requestCounts?.deactivations ?? 0,
        badgeVariant: "rose",
      },
      {
        id: "applicant_movement_requests",
        title: "Applicant Movements",
        description: "Transfer or swap pipeline applicants between store vacancies",
        icon: UserPlus,
        href: "/approvals?tab=applicant_movements",
        section: "request_center",
        badgeCount: requestCounts?.applicant_movements ?? 0,
        badgeVariant: "amber",
        rolesAllowed: ["super_admin", "head_admin", "encoder"],
      },
      {
        id: "account_group_transfer_requests",
        title: "Account Group Transfers",
        description: "Transfer account ownership between CENCOM operational groups",
        icon: FolderSync,
        href: "/approvals?tab=account_group_transfers",
        section: "request_center",
        badgeCount: requestCounts?.account_group_transfers ?? 0,
        badgeVariant: "purple",
        rolesAllowed: ["super_admin", "head_admin"],
      },

      // ── 4. Access Management ─────────────────────────────────────────────
      {
        id: "account_requests",
        title: "Account Requests",
        description: "Approve or reject new user invitations and self-registrations",
        icon: UserCheck,
        href: "/users?tab=requests",
        section: "access_management",
        minRoleLevel: 90,
      },
      {
        id: "user_management",
        title: "User Management",
        description: "Manage system accounts, roles, reset passwords, and profiles",
        icon: Users,
        href: "/users",
        section: "access_management",
        minRoleLevel: 90,
      },
      {
        id: "access_control",
        title: "Temporary Group Access",
        description: "Grant and audit time-bound additional CENCOM scope to encoders",
        icon: Key,
        onClick: () => setIsTempPermModalOpen(true),
        section: "access_management",
        minRoleLevel: 90,
      },

      // ── 5. Data Control ──────────────────────────────────────────────────
      {
        id: "import_plantilla",
        title: "Import Plantilla",
        description: "Upload and validate Store Master List and Plantilla CSV",
        icon: FileSpreadsheet,
        href: "/plantilla",
        section: "data_control",
        rolesAllowed: ["super_admin", "head_admin", "encoder"],
      },
      {
        id: "import_hr_emploc",
        title: "Import HR Emploc",
        description: "Bulk upload HR Emploc records via XLSX with admin staging",
        icon: FileText,
        href: "/hr-emploc/import",
        section: "data_control",
        rolesAllowed: ["super_admin", "head_admin", "encoder"],
      },
      {
        id: "global_store_transfer",
        title: "Global Store Transfer",
        description: "Request and approve employee store transfers across accounts",
        icon: FolderSync,
        href: "/plantilla",
        section: "data_control",
        minRoleLevel: 90,
      },
      {
        id: "import_vacancy",
        title: "Import Vacancy",
        description: "One-time migration wizard for legacy vacancies",
        icon: Briefcase,
        href: "/vacancy",
        section: "data_control",
        rolesAllowed: ["super_admin", "head_admin", "encoder"],
      },
      {
        id: "import_files",
        title: "Import MIKA",
        description: "Upload MIKA operational and schedule reports",
        icon: FileSpreadsheet,
        href: "/cencom",
        section: "data_control",
        minRoleLevel: 90,
      },
      {
        id: "import_payroll",
        title: "Import Payroll",
        description: "Compare external payroll files against active Plantilla roster",
        icon: FileSpreadsheet,
        href: "/plantilla",
        section: "data_control",
        minRoleLevel: 90,
      },
      {
        id: "payroll_review_center",
        title: "Payroll Review Center",
        description: "Review operational variances with Ops and track resolution",
        icon: CheckCircle2,
        href: "/reports",
        section: "data_control",
        rolesAllowed: ["super_admin", "head_admin", "encoder", "om", "operations_manager"],
      },
      {
        id: "edit_lock",
        title: "Edit Lock Control",
        description: "Freeze operational edits during CENCOM cutoffs or audit periods",
        icon: Lock,
        onClick: () => setIsEditLockModalOpen(true),
        section: "data_control",
        minRoleLevel: 90,
      },
      {
        id: "roving_coverage_groups",
        title: "Roving Coverage Groups",
        description: "Manage multi-store roving coverage clusters and schedules",
        icon: Layers,
        href: "/cencom",
        section: "data_control",
        rolesAllowed: ["super_admin", "head_admin", "encoder"],
      },
      {
        id: "data_recovery",
        title: "Data Archival / Recovery",
        description: "Review archived records, audit history, and one-click restore",
        icon: RotateCcw,
        onClick: () => setIsArchivalModalOpen(true),
        section: "data_control",
        minRoleLevel: 90,
      },

      // ── 6. System & Settings ─────────────────────────────────────────────
      {
        id: "app_settings",
        title: "App Settings",
        description: "Preferences, appearance, notifications, and session timeout controls",
        icon: Settings,
        href: "/settings",
        section: "system_settings",
      },
    ];

    return list;
  }, [requestCounts]);

  // Section Filter Helper
  const filterTilesBySection = (sec: MoreSectionKey) => {
    return allTiles.filter((tile) => {
      if (tile.section !== sec) return false;

      // Gate by minimum role level
      if (tile.minRoleLevel !== undefined && roleLevel < tile.minRoleLevel) {
        return false;
      }

      // Gate by specific allowed roles
      if (tile.rolesAllowed && !tile.rolesAllowed.includes(normalizedRole)) {
        if (!isSuperAdmin) return false;
      }

      return true;
    });
  };

  const adminTiles = filterTilesBySection("admin_tools");
  const requestTiles = filterTilesBySection("request_center");
  const accessTiles = filterTilesBySection("access_management");
  const dataTiles = filterTilesBySection("data_control");
  const systemTiles = filterTilesBySection("system_settings");
  const directoryTiles = filterTilesBySection("team_directory");

  return (
    <div className="min-h-full bg-slate-100/60 pb-16">
      {/* Top Banner / Header Container */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-6 space-y-6">
        {/* Top Cards Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Profile Identity Card */}
          <div className="md:col-span-2 bg-white rounded-2xl p-5 border border-slate-200 shadow-2xs flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="flex items-center gap-4">
              <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-slate-900 to-slate-700 text-white flex items-center justify-center font-bold text-xl shadow-md border-2 border-white">
                {currentUser?.displayName
                  ? currentUser.displayName.slice(0, 2).toUpperCase()
                  : "OH"}
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-lg font-bold text-slate-900 leading-tight">
                    {currentUser?.displayName || "Signed In User"}
                  </h1>
                  <span className="px-2.5 py-0.5 rounded-full text-xs font-bold uppercase tracking-wider bg-slate-900 text-white">
                    {roleName}
                  </span>
                </div>
                <p className="text-xs text-slate-500 mt-0.5">
                  {currentUser?.email || "No email available"}
                </p>
                <div className="flex items-center gap-2 mt-2 text-[11px] text-slate-400">
                  <span>Scope: {currentUser?.groupScope.mode === "all" ? "Global" : "Scoped"}</span>
                  <span>•</span>
                  <span>Role Level {roleLevel}</span>
                </div>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Link
                href="/settings"
                className="px-3.5 py-2 text-xs font-semibold text-slate-700 bg-slate-50 hover:bg-slate-100 border border-slate-200 rounded-xl transition-colors flex items-center gap-1.5"
              >
                <Settings className="w-3.5 h-3.5" />
                <span>Account Settings</span>
              </Link>
              <button
                type="button"
                onClick={handleLogout}
                disabled={isLoggingOut}
                className="px-3.5 py-2 text-xs font-semibold text-rose-700 bg-rose-50 hover:bg-rose-100 border border-rose-200 rounded-xl transition-colors flex items-center gap-1.5"
              >
                <LogOut className="w-3.5 h-3.5" />
                <span>Sign Out</span>
              </button>
            </div>
          </div>

          {/* Quick Metrics / Temp Access Banner Card */}
          <div className="bg-white rounded-2xl p-5 border border-slate-200 shadow-2xs flex flex-col justify-between">
            {activeTempAccess && !activeTempAccess.isExpired ? (
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="flex items-center gap-1.5 text-xs font-bold text-amber-800">
                    <Key className="w-4 h-4 text-amber-600" />
                    <span>Temporary Access Active</span>
                  </span>
                  <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-100 text-amber-900 uppercase">
                    Override
                  </span>
                </div>
                <p className="text-xs text-slate-600">
                  Groups: <span className="font-semibold">{activeTempAccess.additionalGroups.join(", ")}</span>
                </p>
                <p className="text-[11px] text-slate-400 flex items-center gap-1">
                  <Clock className="w-3 h-3 text-amber-600" />
                  Expires {new Date(activeTempAccess.expiresAt).toLocaleString()}
                </p>
              </div>
            ) : (
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="flex items-center gap-1.5 text-xs font-bold text-slate-800">
                    <ShieldCheck className="w-4 h-4 text-emerald-600" />
                    <span>Standard Governance Scope</span>
                  </span>
                  <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200 uppercase">
                    Normal
                  </span>
                </div>
                <p className="text-xs text-slate-500">
                  Operating with persistent role permissions. No temporary overrides applied.
                </p>
                <p className="text-[11px] text-slate-400">
                  CENCOM Cutoff Window: <span className="font-medium text-slate-600">Mon 5PM – Tue 2PM</span>
                </p>
              </div>
            )}

            <div className="pt-3 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
              <span>Security Level:</span>
              <span className="font-bold text-slate-800">
                {isSuperAdmin ? "Root Authority" : isHeadAdmin ? "Administrative" : "Standard"}
              </span>
            </div>
          </div>
        </div>

        {/* Section 1: Team Directory */}
        {directoryTiles.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-xs font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                <Users2 className="w-4 h-4 text-slate-400" />
                <span>Team Directory</span>
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5">
              {directoryTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}

        {/* Section 2: Admin Tools (Gated to Super Admin) */}
        {isSuperAdmin && adminTiles.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h2 className="text-xs font-bold text-slate-900 uppercase tracking-wider flex items-center gap-1.5">
                  <ShieldAlert className="w-4 h-4 text-rose-600" />
                  <span>Admin Tools</span>
                </h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-100 text-rose-800 uppercase tracking-wider">
                  Super Admin Level 100
                </span>
              </div>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5">
              {adminTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}

        {/* Section 3: Request Center */}
        {requestTiles.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-xs font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                <Clock className="w-4 h-4 text-slate-400" />
                <span>Request Center</span>
              </h2>
              <Link
                href="/approvals"
                className="text-xs font-semibold text-blue-600 hover:text-blue-800 flex items-center gap-1"
              >
                <span>View All Approvals</span>
                <ArrowRight className="w-3.5 h-3.5" />
              </Link>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5">
              {requestTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}

        {/* Section 4: Access Management */}
        {accessTiles.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-xs font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                <Key className="w-4 h-4 text-slate-400" />
                <span>Access Management</span>
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5">
              {accessTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}

        {/* Section 5: Data Control */}
        {dataTiles.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-xs font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                <FolderSync className="w-4 h-4 text-slate-400" />
                <span>Data Control</span>
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5">
              {dataTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}

        {/* Section 6: System & Settings */}
        {systemTiles.length > 0 && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-xs font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                <Settings className="w-4 h-4 text-slate-400" />
                <span>System & Settings</span>
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5">
              {systemTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Governance Modals */}
      <EditLockControlModal
        isOpen={isEditLockModalOpen}
        onClose={() => setIsEditLockModalOpen(false)}
        canManageOverrides={roleLevel >= 90}
      />

      <TempPermissionModal
        isOpen={isTempPermModalOpen}
        onClose={() => {
          setIsTempPermModalOpen(false);
          refetchTempAccess();
        }}
        canManage={roleLevel >= 90}
        currentUserFullName={currentUser?.displayName || "Admin User"}
      />

      <DataArchivalCenterModal
        isOpen={isArchivalModalOpen}
        onClose={() => setIsArchivalModalOpen(false)}
        canRestore={roleLevel >= 90}
      />
    </div>
  );
}

// ============================================================================
// Tile Card Sub-Component
// ============================================================================

function TileCard({ tile }: { tile: MoreFeatureTile }) {
  const Icon = tile.icon;

  const content = (
    <div className="h-full bg-white rounded-2xl p-4.5 border border-slate-200/90 hover:border-slate-300 hover:shadow-md transition-all flex flex-col justify-between group cursor-pointer">
      <div className="space-y-2.5">
        <div className="flex items-center justify-between">
          <div className="w-9 h-9 rounded-xl bg-slate-100 group-hover:bg-slate-900 group-hover:text-white text-slate-700 flex items-center justify-center transition-colors">
            <Icon className="w-4.5 h-4.5" />
          </div>

          <div className="flex items-center gap-1.5">
            {tile.badgeLabel && (
              <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-slate-100 text-slate-800 uppercase tracking-wider">
                {tile.badgeLabel}
              </span>
            )}

            {tile.badgeCount !== undefined && tile.badgeCount > 0 && (
              <span
                className={`px-2 py-0.5 rounded-full text-[11px] font-bold ${
                  tile.badgeVariant === "rose"
                    ? "bg-rose-100 text-rose-800"
                    : tile.badgeVariant === "amber"
                    ? "bg-amber-100 text-amber-800"
                    : tile.badgeVariant === "purple"
                    ? "bg-purple-100 text-purple-800"
                    : "bg-blue-100 text-blue-800"
                }`}
              >
                {tile.badgeCount}
              </span>
            )}

            {tile.href && (
              <ArrowRight className="w-3.5 h-3.5 text-slate-300 group-hover:text-slate-600 transition-colors ml-1" />
            )}
          </div>
        </div>

        <div>
          <h3 className="text-xs font-bold text-slate-900 group-hover:text-slate-950 transition-colors leading-tight">
            {tile.title}
          </h3>
          <p className="text-[11px] text-slate-500 mt-1 line-clamp-2 leading-relaxed">
            {tile.description}
          </p>
        </div>
      </div>
    </div>
  );

  if (tile.href) {
    return (
      <Link href={tile.href} className="block h-full">
        {content}
      </Link>
    );
  }

  return (
    <button
      type="button"
      onClick={tile.onClick}
      className="block text-left w-full h-full focus:outline-none"
    >
      {content}
    </button>
  );
}
