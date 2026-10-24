"use client";

import { Suspense, useCallback, useMemo, useState, type ComponentType } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Archive,
  ArrowRight,
  CheckCircle2,
  Clock,
  Database,
  FileSpreadsheet,
  FileText,
  History,
  Key,
  Layers,
  Lock,
  LogOut,
  Send,
  Settings,
  Shield,
  ShieldAlert,
  ShieldCheck,
  Sliders,
  TrendingUp,
  Upload,
  User,
  UserCheck,
  Users2,
  Wrench,
} from "lucide-react";
import { useCurrentUser } from "@/lib/auth";
import {
  getRoleLevel,
  isOwner,
  normalizeRole,
  AppRole,
} from "@/lib/rbac";
import { useActiveTempPermission } from "@/lib/queries/more";
import { createClient } from "@/lib/supabase/client";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";

// Modals
import { DataArchivalCenterModal } from "@/components/more/DataArchivalCenterModal";
import { EditLockControlModal } from "@/components/more/EditLockControlModal";
import { TempPermissionModal } from "@/components/more/TempPermissionModal";
import { AccessControlCenterModal } from "@/components/more/AccessControlCenterModal";
import { GlobalStoreTransferModal } from "@/components/more/GlobalStoreTransferModal";
import { AccountRequestsModal } from "@/components/more/AccountRequestsModal";
import { HrEmplocImportModal } from "@/components/more/HrEmplocImportModal";
import { PlantillaImportModal } from "@/components/more/PlantillaImportModal";
import { VacancyImportModal } from "@/components/more/VacancyImportModal";
import { MikaImportModal } from "@/components/more/MikaImportModal";
import { PayrollImportModal } from "@/components/more/PayrollImportModal";
import { PayrollReviewCenterModal } from "@/components/more/PayrollReviewCenterModal";
import { OhmsSafespaceModal } from "@/components/more/OhmsSafespaceModal";
import { SwitchRoleModal } from "@/components/more/SwitchRoleModal";
import { RovingCoverageGroupsModal } from "@/components/more/RovingCoverageGroupsModal";
import { QaCenterModal } from "@/components/more/QaCenterModal";
import { PermissionMatrixModal } from "@/components/more/PermissionMatrixModal";
import { RolePermissionsModal } from "@/components/more/RolePermissionsModal";
import { PermissionDriftModal } from "@/components/more/PermissionDriftModal";
import { SecurityEventsModal } from "@/components/more/SecurityEventsModal";
import { AuditLogsModal } from "@/components/more/AuditLogsModal";


// ============================================================================
// Types & Definitions
// ============================================================================

export type MoreTabKey = "overview" | "admin_tools" | "permissions" | "audit" | "data_control";
export type DataControlSubTab = "operations" | "batch_imports";

export interface MoreFeatureTile {
  id: string;
  title: string;
  description: string;
  icon: ComponentType<{ className?: string }>;
  href?: string;
  onClick?: () => void;
  badgeLabel?: string;
  badgeVariant?: "blue" | "amber" | "emerald" | "rose" | "purple";
  minRoleLevel?: number;
}

interface MoreTabItem {
  key: MoreTabKey;
  label: string;
  icon: ComponentType<{ className?: string }>;
}

const MORE_TABS: MoreTabItem[] = [
  {
    key: "overview",
    label: "Overview",
    icon: User,
  },
  {
    key: "admin_tools",
    label: "Admin Tools",
    icon: Wrench,
  },
  {
    key: "permissions",
    label: "Permissions & Access",
    icon: Key,
  },
  {
    key: "audit",
    label: "Audit & Integrity",
    icon: FileText,
  },
  {
    key: "data_control",
    label: "Data Control",
    icon: Database,
  },
];

// ============================================================================
// Main Page Content
// ============================================================================

function MorePageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const currentUser = useCurrentUser();

  const { data: activeTempAccess } = useActiveTempPermission(
    currentUser?.profileId ?? null
  );

  const [isLoggingOut, setIsLoggingOut] = useState(false);

  const targetModal = searchParams.get("open") || searchParams.get("modal") || searchParams.get("tool");

  // Modal Open States
  const [dataArchivalOpen, setDataArchivalOpen] = useState(
    () => targetModal === "data_archival" || targetModal === "data_archival_center"
  );
  const [editLockOpen, setEditLockOpen] = useState(
    () => targetModal === "edit_lock" || targetModal === "edit_lock_control"
  );
  const [tempPermissionOpen, setTempPermissionOpen] = useState(
    () => targetModal === "temp_permission"
  );
  const [accessControlOpen, setAccessControlOpen] = useState(
    () => targetModal === "access_control" || targetModal === "access_control_center"
  );
  const [storeTransferOpen, setStoreTransferOpen] = useState(false);
  const [accountRequestsOpen, setAccountRequestsOpen] = useState(
    () => targetModal === "account_requests"
  );
  const [hrEmplocImportOpen, setHrEmplocImportOpen] = useState(
    () => targetModal === "import_hr_emploc" || targetModal === "hr_emploc" || targetModal === "hr_emploc_import"
  );
  const [plantillaImportOpen, setPlantillaImportOpen] = useState(false);
  const [vacancyImportOpen, setVacancyImportOpen] = useState(false);
  const [mikaImportOpen, setMikaImportOpen] = useState(false);
  const [payrollImportOpen, setPayrollImportOpen] = useState(false);
  const [payrollReviewCenterOpen, setPayrollReviewCenterOpen] = useState(false);
  const [ohmsSafespaceOpen, setOhmsSafespaceOpen] = useState(
    () => targetModal === "ohms_safespace"
  );
  const [switchRoleOpen, setSwitchRoleOpen] = useState(
    () => targetModal === "switch_role"
  );
  const [rovingCoverageOpen, setRovingCoverageOpen] = useState(false);

  // Governance Modals (QA Center, Permission Matrix, Role Permissions, Drift, Security Events, Audit Logs)
  const [qaCenterOpen, setQaCenterOpen] = useState(
    () => targetModal === "qa_center"
  );
  const [permissionMatrixOpen, setPermissionMatrixOpen] = useState(
    () => targetModal === "permission_matrix"
  );
  const [rolePermissionsOpen, setRolePermissionsOpen] = useState(
    () => targetModal === "role_permissions"
  );
  const [permissionDriftOpen, setPermissionDriftOpen] = useState(
    () => targetModal === "permission_drift"
  );
  const [securityEventsOpen, setSecurityEventsOpen] = useState(
    () => targetModal === "security_events"
  );
  const [auditLogsOpen, setAuditLogsOpen] = useState(
    () => targetModal === "audit_logs"
  );


  // Derive Normalized Role & Levels using unified rbac gatekeeper
  const roleName = currentUser?.roleName ?? currentUser?.roleKey ?? "Viewer";
  const role = normalizeRole(roleName);
  const roleLevel = getRoleLevel(currentUser);
  const isSuperAdmin = roleLevel >= 100 || isOwner(currentUser);
  const isHeadAdmin = roleLevel >= 90;
  const isEncoder = role === AppRole.ENCODER;
  const isOperationsManager = role === AppRole.OM;

  const visibleTabs = useMemo(() => {
    return MORE_TABS.filter((tab) => {
      switch (tab.key) {
        case "overview":
          return true;
        case "admin_tools":
          return isSuperAdmin;
        case "permissions":
          return isHeadAdmin;
        case "audit":
          return isSuperAdmin;
        case "data_control":
          return isHeadAdmin || isEncoder;
        default:
          return false;
      }
    });
  }, [isSuperAdmin, isHeadAdmin, isEncoder]);

  // Tab State derived from URL query synchronization & permissions
  const rawTab = searchParams.get("tab") as MoreTabKey | null;
  const activeTab: MoreTabKey = useMemo(() => {
    if (rawTab && visibleTabs.some((t) => t.key === rawTab)) {
      return rawTab;
    }
    return "overview";
  }, [rawTab, visibleTabs]);

  // Data Control Sub-Tab State derived from URL query synchronization
  const rawSubTab = searchParams.get("subtab");
  const dataControlSubTab: DataControlSubTab =
    rawSubTab === "batch_imports" ? "batch_imports" : "operations";

  const handleTabChange = (tab: MoreTabKey) => {
    const params = new URLSearchParams(searchParams.toString());
    if (tab === "overview") {
      params.delete("tab");
    } else {
      params.set("tab", tab);
    }
    if (tab !== "data_control") {
      params.delete("subtab");
    }
    const query = params.toString();
    router.replace(query ? `/more?${query}` : "/more", { scroll: false });
  };

  const handleSubTabChange = (subtab: DataControlSubTab) => {
    const params = new URLSearchParams(searchParams.toString());
    if (subtab === "operations") {
      params.delete("subtab");
    } else {
      params.set("subtab", subtab);
    }
    const query = params.toString();
    router.replace(query ? `/more?${query}` : "/more", { scroll: false });
  };

  // Sign out handler
  const handleLogout = useCallback(async () => {
    setIsLoggingOut(true);
    try {
      const supabase = createClient();
      await supabase.auth.signOut();
      router.push("/login");
    } catch {
      router.push("/login");
    }
  }, [router]);

  // ── Tab 1: Overview Shortcuts ─────────────────────────────────────────────
  const overviewTiles: MoreFeatureTile[] = useMemo(() => {
    const tiles: MoreFeatureTile[] = [];

    if (isHeadAdmin) {
      tiles.push({
        id: "user_management",
        title: "User Management",
        description: "Password reset, role management, and account transfers",
        icon: Users2,
        href: "/users",
        badgeLabel: "ADMIN",
        badgeVariant: "purple",
      });
      tiles.push({
        id: "account_requests",
        title: "Account Requests",
        description: "Review, approve, or reject pending employee account registrations",
        icon: UserCheck,
        onClick: () => setAccountRequestsOpen(true),
        badgeLabel: "APPROVALS",
        badgeVariant: "blue",
      });
    }

    tiles.push({
      id: "team_directory",
      title: "Team Directory",
      description: "Find and contact Ops, Recruitment, and Data Team users",
      icon: Users2,
      href: "/team-directory",
      badgeLabel: "DIRECTORY",
      badgeVariant: "blue",
    });

    // In Mobile, Payroll Review Center is accessible to Super Admin, Head Admin, Encoder, and OM.
    // For OM, who does not have access to the Data Control tab, surface it in Overview.
    if (isOperationsManager || isHeadAdmin || isEncoder) {
      tiles.push({
        id: "payroll_review_center_overview",
        title: "Payroll Review Center",
        description: "Verify and approve payroll reconciliations and variance discrepancies",
        icon: FileText,
        onClick: () => setPayrollReviewCenterOpen(true),
        badgeLabel: "REVIEWS",
        badgeVariant: "purple",
      });
    }

    tiles.push({
      id: "account_settings",
      title: "Account Settings",
      description: "Preferences, appearance, notifications, and session timeout controls",
      icon: Settings,
      href: "/settings",
      badgeLabel: "CONFIG",
      badgeVariant: "purple",
    });

    tiles.push({
      id: "sign_out",
      title: "Sign Out",
      description: "Safely terminate active Supabase session and return to login screen",
      icon: LogOut,
      onClick: handleLogout,
      badgeLabel: "SESSION",
      badgeVariant: "rose",
    });

    return tiles;
  }, [isHeadAdmin, isOperationsManager, isEncoder, handleLogout]);

  // ── Tab 2: Admin Tools (Level 100) ────────────────────────────────────────
  const adminTiles: MoreFeatureTile[] = useMemo(
    () => [
      {
        id: "ohms_safespace",
        title: "OHM's Safespace",
        description: "Owner command center — system controls, risk, and diagnostics",
        icon: ShieldAlert,
        onClick: () => setOhmsSafespaceOpen(true),
        badgeLabel: "LEVEL 100",
        badgeVariant: "rose",
        minRoleLevel: 100,
      },
      {
        id: "data_archival_center",
        title: "Data Archival Center",
        description: "Inspect soft-deleted records, restore Plantilla or Vacancies, and view archival audit trail",
        icon: Archive,
        onClick: () => setDataArchivalOpen(true),
        badgeLabel: "LEVEL 100",
        badgeVariant: "rose",
        minRoleLevel: 100,
      },
      {
        id: "switch_role",
        title: "Switch Role",
        description: "Act as a different role with scoped access for testing",
        icon: Sliders,
        onClick: () => setSwitchRoleOpen(true),
        badgeLabel: "LEVEL 100",
        badgeVariant: "rose",
        minRoleLevel: 100,
      },
      {
        id: "qa_center",
        title: "QA Center",
        description: "Read QA health, runs, findings, schedules, and reports",
        icon: CheckCircle2,
        onClick: () => setQaCenterOpen(true),
        badgeLabel: "LEVEL 100",
        badgeVariant: "rose",
        minRoleLevel: 100,
      },
    ],
    []
  );

  // ── Tab 3: Permissions & Access ───────────────────────────────────────────
  const permissionTiles: MoreFeatureTile[] = useMemo(
    () => [
      {
        id: "temp_permission",
        title: "Temporary Group Access",
        description: "Grant time-bound group overrides to Encoders for CENCOM or operational coverage",
        icon: Clock,
        onClick: () => setTempPermissionOpen(true),
        badgeLabel: "OVERRIDE",
        badgeVariant: "amber",
        minRoleLevel: 90,
      },
      {
        id: "access_control_center",
        title: "Access Control Center",
        description: "Super Admin tool to toggle per-user module navigation overrides with full audit logging",
        icon: Sliders,
        onClick: () => setAccessControlOpen(true),
        badgeLabel: "SUPER ADMIN",
        badgeVariant: "purple",
        minRoleLevel: 100,
      },
      {
        id: "permission_matrix",
        title: "Permission Matrix",
        description: "Edit role permissions with audited overrides",
        icon: Key,
        onClick: () => setPermissionMatrixOpen(true),
        badgeLabel: "SUPER ADMIN",
        badgeVariant: "purple",
        minRoleLevel: 100,
      },
      {
        id: "role_permissions",
        title: "Role Permissions",
        description: "Read-only backend authorization matrix",
        icon: ShieldCheck,
        onClick: () => setRolePermissionsOpen(true),
        badgeLabel: "SUPER ADMIN",
        badgeVariant: "purple",
        minRoleLevel: 100,
      },
      {
        id: "permission_drift",
        title: "Permission Drift",
        description: "Authorization gap and mismatch findings",
        icon: TrendingUp,
        onClick: () => setPermissionDriftOpen(true),
        badgeLabel: "SUPER ADMIN",
        badgeVariant: "purple",
        minRoleLevel: 100,
      },
    ],
    []
  );

  // ── Tab 4: Audit & Integrity ──────────────────────────────────────────────
  const auditTiles: MoreFeatureTile[] = useMemo(
    () => [
      {
        id: "data_archival_recovery",
        title: "Data Archival & Recovery",
        description: "Archived Plantilla/Vacancy restoration and full archival audit observation logs",
        icon: Archive,
        onClick: () => setDataArchivalOpen(true),
        badgeLabel: "SUPER ADMIN",
        badgeVariant: "purple",
        minRoleLevel: 100,
      },
      {
        id: "security_events",
        title: "Security Events",
        description: "Security activity, threat indicators, and auth alerts",
        icon: Shield,
        onClick: () => setSecurityEventsOpen(true),
        badgeLabel: "SUPER ADMIN",
        badgeVariant: "purple",
        minRoleLevel: 100,
      },
      {
        id: "allocation_health",
        title: "Workforce Integrity",
        description: "Allocation, roving, import, and CENCOM operational health checks",
        icon: Layers,
        href: "/cencom",
        badgeLabel: "SUPER ADMIN",
        badgeVariant: "purple",
        minRoleLevel: 100,
      },
      {
        id: "audit_logs",
        title: "Audit Logs",
        description: "System activity, audit trails, and data changes",
        icon: History,
        onClick: () => setAuditLogsOpen(true),
        badgeLabel: "SUPER ADMIN",
        badgeVariant: "purple",
        minRoleLevel: 100,
      },
    ],

    []
  );

  // ── Tab 5: Data Control (Split: Operations & Governance + Batch Imports) ─
  const operationsTiles: MoreFeatureTile[] = useMemo(
    () => [
      {
        id: "edit_lock_control",
        title: "Edit Lock Control",
        description: "Restrict edits during CENCOM or review periods with SA temporary override controls",
        icon: Lock,
        onClick: () => setEditLockOpen(true),
        badgeLabel: "SECURITY",
        badgeVariant: "amber",
        minRoleLevel: 90,
      },
      {
        id: "data_archival_control",
        title: "Data Archival / Recovery",
        description: "Recover soft-deleted plantilla and vacancy records with audited reason logging",
        icon: Archive,
        onClick: () => setDataArchivalOpen(true),
        badgeLabel: "LEVEL 100",
        badgeVariant: "rose",
        minRoleLevel: 100,
      },
      {
        id: "global_store_transfer",
        title: "Global Store Transfer",
        description: "Request employee store transfers for SA approval with target vacant slot assignment",
        icon: Send,
        onClick: () => setStoreTransferOpen(true),
        badgeLabel: "TRANSFER",
        badgeVariant: "blue",
      },
      {
        id: "roving_coverage_groups",
        title: "Roving Coverage Groups",
        description: "Review and manage roving reliever assignments and multi-store coverage pools",
        icon: Users2,
        onClick: () => setRovingCoverageOpen(true),
        badgeLabel: "ROVING",
        badgeVariant: "blue",
      },
      {
        id: "payroll_review_center",
        title: "Payroll Review Center",
        description: "Verify and approve payroll reconciliations and variance discrepancies",
        icon: FileText,
        onClick: () => setPayrollReviewCenterOpen(true),
        badgeLabel: "REVIEWS",
        badgeVariant: "purple",
      },
    ],
    []
  );

  const batchImportTiles: MoreFeatureTile[] = useMemo(
    () => [
      {
        id: "import_hr_emploc",
        title: "Import HR Emploc",
        description: "Bulk upload HR Emploc records via XLSX with HA/SA approval",
        icon: FileSpreadsheet,
        onClick: () => setHrEmplocImportOpen(true),
        badgeLabel: "RECONCILIATION",
        badgeVariant: "purple",
      },
      {
        id: "import_plantilla",
        title: "Import Plantilla",
        description: "Bulk master plantilla baseline ingestion (CSV/XLSX parser staging)",
        icon: FileSpreadsheet,
        onClick: () => setPlantillaImportOpen(true),
        badgeLabel: "BASELINE",
        badgeVariant: "purple",
      },
      {
        id: "import_vacancy",
        title: "Import Vacancy",
        description: "Bulk import vacancy records and requisitions into current operational active groups",
        icon: FileSpreadsheet,
        onClick: () => setVacancyImportOpen(true),
        badgeLabel: "INTAKE",
        badgeVariant: "purple",
      },
      {
        id: "import_mika",
        title: "Import MIKA",
        description: "MIKA biometric attendance and store activity import staging",
        icon: FileSpreadsheet,
        onClick: () => setMikaImportOpen(true),
        badgeLabel: "BIOMETRIC",
        badgeVariant: "purple",
      },
      {
        id: "import_payroll",
        title: "Import Payroll",
        description: "Import operational payroll sheets and employee wage deductions",
        icon: FileSpreadsheet,
        onClick: () => setPayrollImportOpen(true),
        badgeLabel: "CHECKER",
        badgeVariant: "purple",
      },
    ],
    []
  );

  const visibleAdminTiles = useMemo(() => {
    return adminTiles.filter((t) => isSuperAdmin && (!t.minRoleLevel || roleLevel >= t.minRoleLevel));
  }, [adminTiles, isSuperAdmin, roleLevel]);

  const visiblePermissionTiles = useMemo(() => {
    return permissionTiles.filter((t) => !t.minRoleLevel || roleLevel >= t.minRoleLevel);
  }, [permissionTiles, roleLevel]);

  const visibleAuditTiles = useMemo(() => {
    return auditTiles.filter((t) => isSuperAdmin && (!t.minRoleLevel || roleLevel >= t.minRoleLevel));
  }, [auditTiles, isSuperAdmin, roleLevel]);

  const visibleOperationsTiles = useMemo(() => {
    return operationsTiles.filter((tile) => {
      if (tile.minRoleLevel && roleLevel < tile.minRoleLevel) return false;
      if (tile.id === "payroll_review_center") {
        return isHeadAdmin || isEncoder || isOperationsManager;
      }
      if (tile.id === "roving_coverage_groups") {
        return isHeadAdmin || isEncoder;
      }
      return isHeadAdmin;
    });
  }, [operationsTiles, roleLevel, isHeadAdmin, isEncoder, isOperationsManager]);

  const visibleBatchImportTiles = useMemo(() => {
    return batchImportTiles.filter((tile) => {
      if (tile.minRoleLevel && roleLevel < tile.minRoleLevel) return false;
      if (
        tile.id === "import_hr_emploc" ||
        tile.id === "import_plantilla" ||
        tile.id === "import_vacancy" ||
        tile.id === "import_mika" ||
        tile.id === "import_payroll"
      ) {
        return isHeadAdmin || isEncoder;
      }
      return isHeadAdmin;
    });
  }, [batchImportTiles, roleLevel, isHeadAdmin, isEncoder]);

  return (
    <div className="space-y-6">
      {/* Standard Admin Header */}
      <AdminPageHeader
        categoryTag="ADMIN PANEL"
        moduleName="More"
        title="System Hub & Governance Tools"
        subtitle="Access administrator utilities, security matrices, audit trails, data control, and command controls."
        icon={Layers}
      />

      {/* Categorized Tab Navigation Strip */}
      <div className="border-b border-border-subtle pb-3">
        <nav
          className="flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none"
          aria-label="More Navigation Tabs"
          role="tablist"
        >
          {visibleTabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.key;

            return (
              <button
                key={tab.key}
                type="button"
                role="tab"
                aria-selected={isActive}
                onClick={() => handleTabChange(tab.key)}
                className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
                  isActive
                    ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
                    : "border-transparent bg-transparent text-text-secondary hover:border-slate-200 hover:bg-surface-hover hover:text-text-primary"
                }`}
              >
                <Icon
                  className={`w-4 h-4 shrink-0 transition-colors ${
                    isActive
                      ? "text-brand-700"
                      : "text-text-muted group-hover:text-text-secondary"
                  }`}
                />
                <span>{tab.label}</span>
              </button>
            );
          })}
        </nav>
      </div>

      {/* Active Tab Panel */}
      <div className="pt-1">
        {/* Tab 1: Overview */}
        {activeTab === "overview" && (
          <div className="space-y-6">
            {/* Top Cards Grid */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {/* Profile Identity Card */}
              <div className="md:col-span-2 bg-white rounded-2xl p-5 border border-slate-200 shadow-2xs flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div className="flex items-center gap-4">
                  <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-slate-900 to-slate-700 text-white flex items-center justify-center font-bold text-xl shadow-md border-2 border-white shrink-0">
                    {currentUser?.displayName
                      ? currentUser.displayName.slice(0, 2).toUpperCase()
                      : "OH"}
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h2 className="text-lg font-bold text-slate-900 leading-tight">
                        {currentUser?.displayName || "Signed In User"}
                      </h2>
                      <span className="px-2.5 py-0.5 rounded-full text-xs font-bold uppercase tracking-wider bg-slate-900 text-white">
                        {roleName}
                      </span>
                    </div>
                    <p className="text-xs text-slate-500 mt-0.5">
                      {currentUser?.email || "No email available"}
                    </p>
                    <div className="flex items-center gap-2 mt-2 text-[11px] text-slate-400">
                      <span>
                        Scope:{" "}
                        {currentUser?.groupScope.mode === "all"
                          ? "Global"
                          : "Scoped"}
                      </span>
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
                    className="px-3.5 py-2 text-xs font-semibold text-rose-700 bg-rose-50 hover:bg-rose-100 border border-rose-200 rounded-xl transition-colors flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
                  >
                    <LogOut className="w-3.5 h-3.5" />
                    <span>{isLoggingOut ? "Signing Out..." : "Sign Out"}</span>
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
                      Groups:{" "}
                      <span className="font-semibold">
                        {activeTempAccess.additionalGroups.join(", ")}
                      </span>
                    </p>
                    <p className="text-[11px] text-slate-400 flex items-center gap-1">
                      <Clock className="w-3 h-3 text-amber-600" />
                      Expires{" "}
                      {new Date(activeTempAccess.expiresAt).toLocaleString()}
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
                      Operating with persistent role permissions. No temporary
                      overrides applied.
                    </p>
                    <p className="text-[11px] text-slate-400">
                      CENCOM Cutoff Window:{" "}
                      <span className="font-medium text-slate-600">
                        Mon 5PM – Tue 2PM
                      </span>
                    </p>
                  </div>
                )}

                <div className="pt-3 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
                  <span>Security Level:</span>
                  <span className="font-bold text-slate-800">
                    {isSuperAdmin
                      ? "Root Authority"
                      : isHeadAdmin
                      ? "Administrative"
                      : "Standard"}
                  </span>
                </div>
              </div>
            </div>

            {/* Overview Primary Shortcuts Grid */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-bold text-text-secondary uppercase tracking-wider flex items-center gap-1.5">
                  <Users2 className="w-4 h-4 text-text-muted" />
                  <span>Primary Shortcuts</span>
                </h3>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {overviewTiles.map((tile) => (
                  <TileCard key={tile.id} tile={tile} />
                ))}
              </div>
            </div>
          </div>
        )}

        {/* Tab 2: Admin Tools */}
        {activeTab === "admin_tools" && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h3 className="text-xs font-bold text-text-secondary uppercase tracking-wider flex items-center gap-1.5">
                  <ShieldAlert className="w-4 h-4 text-rose-600" />
                  <span>High-Level Command Tools</span>
                </h3>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-100 text-rose-800 uppercase tracking-wider">
                  Super Admin Level 100
                </span>
              </div>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {visibleAdminTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}

        {/* Tab 3: Permissions & Access */}
        {activeTab === "permissions" && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h3 className="text-xs font-bold text-text-secondary uppercase tracking-wider flex items-center gap-1.5">
                  <Key className="w-4 h-4 text-purple-600" />
                  <span>Authorization & Role Governance</span>
                </h3>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-purple-100 text-purple-800 uppercase tracking-wider">
                  Security Matrix
                </span>
              </div>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {visiblePermissionTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}

        {/* Tab 4: Audit & Integrity */}
        {activeTab === "audit" && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h3 className="text-xs font-bold text-text-secondary uppercase tracking-wider flex items-center gap-1.5">
                  <FileText className="w-4 h-4 text-blue-600" />
                  <span>Integrity Checks & System Audit Trails</span>
                </h3>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-blue-100 text-blue-800 uppercase tracking-wider">
                  Compliance
                </span>
              </div>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {visibleAuditTiles.map((tile) => (
                <TileCard key={tile.id} tile={tile} />
              ))}
            </div>
          </div>
        )}

        {/* Tab 5: Data Control */}
        {activeTab === "data_control" && (
          <div className="space-y-4">
            {/* Main Header / Description */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h3 className="text-xs font-bold text-text-secondary uppercase tracking-wider flex items-center gap-1.5">
                  <Database className="w-4 h-4 text-emerald-600" />
                  <span>Data Control & Batch Ingestion</span>
                </h3>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800 uppercase tracking-wider">
                  Mobile Parity
                </span>
              </div>
            </div>

            {/* Secondary Pill-Style Sub-Tab Navigation Bar */}
            <div className="inline-flex p-1 bg-slate-100/90 rounded-xl border border-slate-200/80 gap-1 self-start">
              <button
                type="button"
                role="tab"
                aria-selected={dataControlSubTab === "operations"}
                onClick={() => handleSubTabChange("operations")}
                className={`inline-flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all cursor-pointer ${
                  dataControlSubTab === "operations"
                    ? "bg-white text-slate-900 shadow-2xs border border-slate-200/60 font-bold"
                    : "text-slate-600 hover:text-slate-900 hover:bg-white/60 border border-transparent"
                }`}
              >
                <ShieldCheck className="w-3.5 h-3.5 text-slate-600" />
                <span>Operations & Governance</span>
                <span
                  className={`px-1.5 py-0.5 rounded-full text-[10px] font-bold ${
                    dataControlSubTab === "operations"
                      ? "bg-slate-100 text-slate-900"
                      : "bg-slate-200/70 text-slate-600"
                  }`}
                >
                  {visibleOperationsTiles.length}
                </span>
              </button>

              <button
                type="button"
                role="tab"
                aria-selected={dataControlSubTab === "batch_imports"}
                onClick={() => handleSubTabChange("batch_imports")}
                className={`inline-flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all cursor-pointer ${
                  dataControlSubTab === "batch_imports"
                    ? "bg-white text-slate-900 shadow-2xs border border-slate-200/60 font-bold"
                    : "text-slate-600 hover:text-slate-900 hover:bg-white/60 border border-transparent"
                }`}
              >
                <Upload className="w-3.5 h-3.5 text-slate-600" />
                <span>Batch Imports</span>
                <span
                  className={`px-1.5 py-0.5 rounded-full text-[10px] font-bold ${
                    dataControlSubTab === "batch_imports"
                      ? "bg-slate-100 text-slate-900"
                      : "bg-slate-200/70 text-slate-600"
                  }`}
                >
                  {visibleBatchImportTiles.length}
                </span>
              </button>
            </div>

            {/* Card Grid with smooth transitions */}
            <div className="pt-1 transition-all duration-200 ease-in-out">
              {dataControlSubTab === "operations" ? (
                <div
                  key="operations-grid"
                  className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 animate-in fade-in-50 duration-200"
                >
                  {visibleOperationsTiles.map((tile) => (
                    <TileCard key={tile.id} tile={tile} />
                  ))}
                </div>
              ) : (
                <div
                  key="batch-imports-grid"
                  className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 animate-in fade-in-50 duration-200"
                >
                  {visibleBatchImportTiles.map((tile) => (
                    <TileCard key={tile.id} tile={tile} />
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Modals Mounting */}
      <DataArchivalCenterModal
        isOpen={dataArchivalOpen}
        onClose={() => setDataArchivalOpen(false)}
        canRestore={isSuperAdmin}
      />

      <EditLockControlModal
        isOpen={editLockOpen}
        onClose={() => setEditLockOpen(false)}
        canManageOverrides={isHeadAdmin}
      />

      <TempPermissionModal
        isOpen={tempPermissionOpen}
        onClose={() => setTempPermissionOpen(false)}
        canManage={isHeadAdmin}
        currentUserFullName={currentUser?.displayName || "Administrator"}
      />

      <AccessControlCenterModal
        isOpen={accessControlOpen}
        onClose={() => setAccessControlOpen(false)}
        isSuperAdmin={isSuperAdmin}
      />

      <GlobalStoreTransferModal
        isOpen={storeTransferOpen}
        onClose={() => setStoreTransferOpen(false)}
        currentUserFullName={currentUser?.displayName || "Administrator"}
      />

      <AccountRequestsModal
        isOpen={accountRequestsOpen}
        onClose={() => setAccountRequestsOpen(false)}
        isSuperAdmin={isSuperAdmin}
      />

      <HrEmplocImportModal
        isOpen={hrEmplocImportOpen}
        onClose={() => setHrEmplocImportOpen(false)}
      />

      <PlantillaImportModal
        isOpen={plantillaImportOpen}
        onClose={() => setPlantillaImportOpen(false)}
      />

      <VacancyImportModal
        isOpen={vacancyImportOpen}
        onClose={() => setVacancyImportOpen(false)}
      />

      <MikaImportModal
        isOpen={mikaImportOpen}
        onClose={() => setMikaImportOpen(false)}
      />

      <PayrollImportModal
        isOpen={payrollImportOpen}
        onClose={() => setPayrollImportOpen(false)}
        onOpenReviewCenter={() => setPayrollReviewCenterOpen(true)}
      />

      <PayrollReviewCenterModal
        isOpen={payrollReviewCenterOpen}
        onClose={() => setPayrollReviewCenterOpen(false)}
      />

      <OhmsSafespaceModal
        isOpen={ohmsSafespaceOpen}
        onClose={() => setOhmsSafespaceOpen(false)}
      />

      <SwitchRoleModal
        isOpen={switchRoleOpen}
        onClose={() => setSwitchRoleOpen(false)}
      />

      <RovingCoverageGroupsModal
        isOpen={rovingCoverageOpen}
        onClose={() => setRovingCoverageOpen(false)}
      />

      <QaCenterModal
        isOpen={qaCenterOpen}
        onClose={() => setQaCenterOpen(false)}
        isSuperAdmin={isSuperAdmin}
      />

      <PermissionMatrixModal
        isOpen={permissionMatrixOpen}
        onClose={() => setPermissionMatrixOpen(false)}
        isSuperAdmin={isSuperAdmin}
      />

      <RolePermissionsModal
        isOpen={rolePermissionsOpen}
        onClose={() => setRolePermissionsOpen(false)}
        isSuperAdmin={isSuperAdmin}
      />

      <PermissionDriftModal
        isOpen={permissionDriftOpen}
        onClose={() => setPermissionDriftOpen(false)}
        isSuperAdmin={isSuperAdmin}
      />

      <SecurityEventsModal
        isOpen={securityEventsOpen}
        onClose={() => setSecurityEventsOpen(false)}
        isSuperAdmin={isSuperAdmin}
      />

      <AuditLogsModal
        isOpen={auditLogsOpen}
        onClose={() => setAuditLogsOpen(false)}
        isSuperAdmin={isSuperAdmin}
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
    <div className="h-full bg-white rounded-2xl p-5 border border-slate-200/90 hover:border-slate-300 hover:shadow-md transition-all flex flex-col justify-between group cursor-pointer">
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <div className="w-10 h-10 rounded-xl bg-slate-100 group-hover:bg-slate-900 group-hover:text-white text-slate-700 flex items-center justify-center transition-colors">
            <Icon className="w-5 h-5" />
          </div>

          <div className="flex items-center gap-1.5">
            {tile.badgeLabel && (
              <span
                className={`px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider ${
                  tile.badgeVariant === "rose"
                    ? "bg-rose-100 text-rose-800 border border-rose-200/60"
                    : tile.badgeVariant === "purple"
                    ? "bg-purple-100 text-purple-800 border border-purple-200/60"
                    : tile.badgeVariant === "amber"
                    ? "bg-amber-100 text-amber-800 border border-amber-200/60"
                    : tile.badgeVariant === "emerald"
                    ? "bg-emerald-100 text-emerald-800 border border-emerald-200/60"
                    : "bg-slate-100 text-slate-800 border border-slate-200/60"
                }`}
              >
                {tile.badgeLabel}
              </span>
            )}

            {tile.href && (
              <ArrowRight className="w-4 h-4 text-slate-300 group-hover:text-slate-600 transition-colors ml-1" />
            )}
          </div>
        </div>

        <div>
          <h3 className="text-sm font-bold text-slate-900 group-hover:text-slate-950 transition-colors leading-tight">
            {tile.title}
          </h3>
          <p className="text-xs text-slate-500 mt-1 line-clamp-2 leading-relaxed">
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
      className="block text-left w-full h-full focus:outline-hidden"
    >
      {content}
    </button>
  );
}

// ============================================================================
// Default Export with Suspense
// ============================================================================

export default function MorePage() {
  return (
    <Suspense
      fallback={
        <div className="space-y-6">
          <div className="h-14 border-b border-border-subtle bg-surface-base animate-pulse" />
          <div className="h-64 rounded-xl border border-border-default bg-surface-base animate-pulse" />
        </div>
      }
    >
      <MorePageContent />
    </Suspense>
  );
}
