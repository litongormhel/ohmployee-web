/**
 * Unified Web RBAC Gatekeeper
 * 
 * Ported 1:1 from Mobile RBAC Source of Truth:
 *   - role_constants.dart (AppRole, RolePermissions, role groupings)
 *   - auth_service.dart (LoggedInUser getters: canViewCencom, canSeePlantilla, canSeeHREmploc)
 *   - module_visibility.dart (ModuleVisibility role defaults and overrides)
 *   - more_screen.dart (Request Center / Approvals category permissions)
 */

import type { RequestCategoryKey } from "@/lib/queries/requests";

export enum AppRole {
  SUPER_ADMIN = "super_admin",
  HEAD_ADMIN = "head_admin",
  OM = "om",
  HRCO = "hrco",
  ATL = "atl",
  TL = "tl",
  ENCODER = "encoder",
  HR_PERSONNEL = "hr_personnel",
  RECRUITMENT = "recruitment",
  BACKOFFICE_PERSONNEL = "backoffice_personnel",
  VIEWER = "viewer",
}

export type RoleIdentifiable = {
  roleKey?: string | null;
  roleName?: string | null;
  roleLevel?: number | null;
  allowedModuleKeys?: string[];
  moduleAccess?: Record<string, { visible: boolean; reason?: string }>;
};

/**
 * Normalizes any role key or display name to canonical AppRole enum.
 * Strictly matches Mobile role_constants.dart _normalize() logic.
 */
export function normalizeRole(roleKeyOrName?: string | null): AppRole | null {
  if (!roleKeyOrName || !roleKeyOrName.trim()) return null;

  const raw = roleKeyOrName.toLowerCase().replace(/[^a-z0-9]/g, "");

  switch (raw) {
    case "superadmin":
    case "owner":
      return AppRole.SUPER_ADMIN;
    case "headadmin":
      return AppRole.HEAD_ADMIN;
    case "om":
    case "operationsmanager":
    case "operations":
      return AppRole.OM;
    case "hrco":
    case "hrcoordinator":
      return AppRole.HRCO;
    case "atl":
    case "assistantteamleader":
      return AppRole.ATL;
    case "tl":
    case "teamleader":
    case "atltl":
      return AppRole.TL;
    case "encoder":
    case "datateam":
      return AppRole.ENCODER;
    case "hrpersonnel":
    case "hrdept":
    case "hrdeptteam":
    case "hrdepartment":
      return AppRole.HR_PERSONNEL;
    case "recruitment":
    case "recruitmentteam":
      return AppRole.RECRUITMENT;
    case "backoffice":
    case "backofficepersonnel":
    case "backofficeteam":
      return AppRole.BACKOFFICE_PERSONNEL;
    case "viewer":
    case "executiveviewer":
      return AppRole.VIEWER;
    default:
      return null;
  }
}

/**
 * Returns the numeric role level (10-100) for a given role identifier.
 * Evaluates normalized role name/key FIRST to guarantee exact Mobile parity.
 */
export function getRoleLevel(userOrRole?: RoleIdentifiable | string | null): number {
  if (!userOrRole) return 0;
  const roleName = typeof userOrRole === "string" ? userOrRole : userOrRole.roleKey || userOrRole.roleName;
  const role = normalizeRole(roleName);
  switch (role) {
    case AppRole.SUPER_ADMIN:
      return 100;
    case AppRole.HEAD_ADMIN:
      return 90;
    case AppRole.OM:
      return 70;
    case AppRole.HRCO:
      return 45;
    case AppRole.ATL:
      return 42;
    case AppRole.TL:
      return 41;
    case AppRole.ENCODER:
      return 30;
    case AppRole.HR_PERSONNEL:
      return 25;
    case AppRole.RECRUITMENT:
      return 20;
    case AppRole.BACKOFFICE_PERSONNEL:
      return 15;
    case AppRole.VIEWER:
      return 10;
    default:
      if (typeof userOrRole === "object" && typeof userOrRole.roleLevel === "number") {
        return userOrRole.roleLevel;
      }
      return 0;
  }
}

// ── Role Groupings (Mobile role_constants.dart parity) ──────────────────────

export function isOwner(userOrRole?: RoleIdentifiable | string | null): boolean {
  const role = normalizeRole(extractRoleString(userOrRole));
  if (role) return role === AppRole.SUPER_ADMIN;
  return getRoleLevel(userOrRole) >= 100;
}

export function hasFullAccess(userOrRole?: RoleIdentifiable | string | null): boolean {
  const role = normalizeRole(extractRoleString(userOrRole));
  if (role) return role === AppRole.SUPER_ADMIN || role === AppRole.HEAD_ADMIN;
  return getRoleLevel(userOrRole) >= 90;
}

export function isDataTeam(userOrRole?: RoleIdentifiable | string | null): boolean {
  const role = normalizeRole(extractRoleString(userOrRole));
  return role === AppRole.HEAD_ADMIN || role === AppRole.ENCODER;
}

export function isEncoder(userOrRole?: RoleIdentifiable | string | null): boolean {
  const role = normalizeRole(extractRoleString(userOrRole));
  return role === AppRole.ENCODER || getRoleLevel(userOrRole) === 30;
}

export function isOpsTeam(userOrRole?: RoleIdentifiable | string | null): boolean {
  const role = normalizeRole(extractRoleString(userOrRole));
  return (
    role === AppRole.OM ||
    role === AppRole.HRCO ||
    role === AppRole.ATL ||
    role === AppRole.TL
  );
}

/**
 * Can add applicant to an open vacancy.
 * Allowed: Super Admin, Head Admin, OM, HRCO, ATL, TL, Encoder, HR Personnel, Recruitment.
 * Denied: Backoffice Personnel, Viewer.
 */
export function canAddApplicant(userOrRole?: RoleIdentifiable | string | null): boolean {
  if (hasFullAccess(userOrRole)) return true;
  const role = normalizeRole(extractRoleString(userOrRole));
  if (!role || role === AppRole.VIEWER || role === AppRole.BACKOFFICE_PERSONNEL) {
    return false;
  }
  return true;
}

/**
 * Can advance applicant pipeline stages, mark hired, backout, or reopen failed vacancy slots.
 * Allowed: Super Admin, Head Admin, OM, HRCO, ATL, TL, Encoder, HR Personnel, Recruitment.
 * Denied: Backoffice Personnel, Viewer.
 */
export function canManageApplicantPipeline(userOrRole?: RoleIdentifiable | string | null): boolean {
  return canAddApplicant(userOrRole);
}

/**
 * Can review/approve/reject vacancy closures.
 * Restricted strictly to Super Admin, Head Admin, and Encoder.
 */
export function canReviewVacancyClosures(userOrRole?: RoleIdentifiable | string | null): boolean {
  if (hasFullAccess(userOrRole)) return true;
  const role = normalizeRole(extractRoleString(userOrRole));
  return role === AppRole.ENCODER || getRoleLevel(userOrRole) === 30;
}

/**
 * Can request vacancy closure.
 * Allowed: Super Admin, Head Admin, Ops Team (OM, HRCO, ATL, TL), Encoder.
 * Denied: HR Personnel, Recruitment, Backoffice Personnel, Viewer.
 */
export function canRequestVacancyClosure(userOrRole?: RoleIdentifiable | string | null): boolean {
  if (hasFullAccess(userOrRole)) return true;
  const role = normalizeRole(extractRoleString(userOrRole));
  return isOpsTeam(userOrRole) || role === AppRole.ENCODER || getRoleLevel(userOrRole) === 30;
}

function extractRoleString(userOrRole?: RoleIdentifiable | string | null): string | null {
  if (!userOrRole) return null;
  if (typeof userOrRole === "string") return userOrRole;
  return userOrRole.roleKey || userOrRole.roleName || null;
}

// ── Module Permission Getters (Mobile auth_service.dart parity) ─────────────

/**
 * CENCOM visibility (OHM2026_3011).
 * Allowed: Super Admin, Head Admin, Encoder, OM, TL, ATL, Viewer.
 * Explicitly DENIED: HRCO, Recruitment, HR Personnel, Backoffice Personnel.
 */
export function canViewCencom(userOrRole?: RoleIdentifiable | string | null): boolean {
  if (hasFullAccess(userOrRole)) return true;
  const role = normalizeRole(extractRoleString(userOrRole));
  return (
    role === AppRole.ENCODER ||
    role === AppRole.OM ||
    role === AppRole.TL ||
    role === AppRole.ATL ||
    role === AppRole.VIEWER
  );
}

/**
 * Vacancy visibility.
 * Allowed to all roles.
 */
export function canViewVacancy(userOrRole?: RoleIdentifiable | string | null): boolean {
  return Boolean(userOrRole);
}

/**
 * HR Emploc visibility (RolePermissions.canViewHrEmploc).
 * Denied: Recruitment and Viewer.
 * Allowed: Super Admin, Head Admin, OM, HRCO, ATL, TL, Encoder, HR Personnel, Backoffice Personnel.
 */
export function canViewHrEmploc(userOrRole?: RoleIdentifiable | string | null): boolean {
  const role = normalizeRole(extractRoleString(userOrRole));
  if (!role) return false;
  return role !== AppRole.RECRUITMENT && role !== AppRole.VIEWER;
}

/**
 * Plantilla visibility (RolePermissions.canViewPlantilla).
 * Allowed: Super Admin, Head Admin, Ops Team (OM, HRCO, ATL, TL), Data Team (Encoder), Viewer.
 * Denied: Recruitment, HR Personnel, Backoffice Personnel.
 */
export function canViewPlantilla(userOrRole?: RoleIdentifiable | string | null): boolean {
  if (hasFullAccess(userOrRole)) return true;
  const role = normalizeRole(extractRoleString(userOrRole));
  return (
    isOpsTeam(userOrRole) ||
    isDataTeam(userOrRole) ||
    role === AppRole.VIEWER
  );
}

/**
 * Approvals Review Hub.
 * In Mobile (more_screen.dart), review queues are restricted strictly to:
 *   - Super Admin (100) & Head Admin (90)
 *   - Encoder (30) (headcount, coverage, closure, emploc deletions, movements, relievers)
 *   - Backoffice Personnel (15) (deactivations only)
 * OM and HRCO are requesters only (they submit requests / view my_requests).
 */
export function canViewApprovalsHub(userOrRole?: RoleIdentifiable | string | null): boolean {
  if (hasFullAccess(userOrRole)) return true;
  const role = normalizeRole(extractRoleString(userOrRole));
  return role === AppRole.ENCODER || role === AppRole.BACKOFFICE_PERSONNEL;
}

/**
 * Reports visibility.
 * Lives inside CENCOM in Mobile and follows CENCOM visibility.
 */
export function canViewReports(userOrRole?: RoleIdentifiable | string | null): boolean {
  return canViewCencom(userOrRole);
}

/**
 * User Management visibility.
 * Super Admin and Head Admin only.
 */
export function canManageUsers(userOrRole?: RoleIdentifiable | string | null): boolean {
  return hasFullAccess(userOrRole);
}

/**
 * Team Directory visibility.
 * In Mobile, all 11 active authenticated roles (Viewer and above) can access.
 */
export function canViewTeamDirectory(userOrRole?: RoleIdentifiable | string | null): boolean {
  if (!userOrRole) return false;
  const role = normalizeRole(extractRoleString(userOrRole));
  if (role !== null) return true;
  return getRoleLevel(userOrRole) >= 10;
}

/**
 * Returns allowed approval categories for a role in the Approvals review queue.
 * Matches Mobile more_screen.dart lines 292-391.
 */
export function getAllowedApprovalCategories(
  userOrRole?: RoleIdentifiable | string | null,
): RequestCategoryKey[] {
  if (hasFullAccess(userOrRole)) {
    return [
      "new_stores",
      "headcount",
      "plantilla_approvals",
      "account_requests",
      "coverage",
      "vacancy_closures",
      "hr_emploc_deletions",
      "deactivations",
      "applicant_movements",
      "account_group_transfers",
      "relievers",
    ];
  }

  const role = normalizeRole(extractRoleString(userOrRole));

  if (role === AppRole.ENCODER) {
    return [
      "headcount",
      "coverage",
      "vacancy_closures",
      "hr_emploc_deletions",
      "applicant_movements",
      "relievers",
    ];
  }

  if (role === AppRole.BACKOFFICE_PERSONNEL) {
    return ["deactivations"];
  }

  return [];
}

/**
 * Master check: determines whether a module is permitted for the given user,
 * taking into account role defaults and any explicit module visibility overrides.
 */
export function isModuleAllowedForUser(
  moduleKey: string,
  user?: RoleIdentifiable | null,
): boolean {
  if (!user) return false;

  const role = normalizeRole(extractRoleString(user));

  // Hard defense-in-depth against role regressions / leaks
  if (role === AppRole.HRCO && (moduleKey === "cencom" || moduleKey === "approvals" || moduleKey === "reports")) {
    return false;
  }
  if ((role === AppRole.RECRUITMENT || role === AppRole.HR_PERSONNEL || role === AppRole.BACKOFFICE_PERSONNEL) &&
      (moduleKey === "cencom" || moduleKey === "reports")) {
    return false;
  }
  if ((role === AppRole.RECRUITMENT || role === AppRole.HR_PERSONNEL || role === AppRole.BACKOFFICE_PERSONNEL) &&
      moduleKey === "plantilla") {
    return false;
  }
  if ((role === AppRole.RECRUITMENT || role === AppRole.VIEWER) && moduleKey === "hr_emploc") {
    return false;
  }
  if (role !== AppRole.SUPER_ADMIN && role !== AppRole.HEAD_ADMIN && moduleKey === "users") {
    return false;
  }
  if (role !== AppRole.SUPER_ADMIN && role !== AppRole.HEAD_ADMIN && role !== AppRole.ENCODER && role !== AppRole.BACKOFFICE_PERSONNEL && moduleKey === "approvals") {
    return false;
  }

  // 1. Check explicit moduleAccess override if populated by RPC / ACC V1
  const explicitAccess = user.moduleAccess?.[moduleKey];
  if (explicitAccess !== undefined) {
    return explicitAccess.visible;
  }

  // 2. Fall back to Mobile RBAC Role Defaults
  switch (moduleKey) {
    case "dashboard":
      return true;
    case "vacancy":
      return canViewVacancy(user);
    case "cencom":
      return canViewCencom(user);
    case "hr_emploc":
      return canViewHrEmploc(user);
    case "plantilla":
      return canViewPlantilla(user);
    case "approvals":
      return canViewApprovalsHub(user);
    case "users":
      return canManageUsers(user);
    case "team_directory":
      return canViewTeamDirectory(user);
    case "notifications":
      return true;
    case "reports":
      return canViewReports(user);
    case "settings":
      return true;
    case "more":
      return true;
    default:
      return false;
  }
}
