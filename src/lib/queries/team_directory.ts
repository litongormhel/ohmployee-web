import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ---------------------------------------------------------------------------
// Types & Interfaces
// ---------------------------------------------------------------------------

export type DirectoryStatus = "Available" | "Busy" | "On Leave" | "Offline";

export interface TeamDirectoryUser {
  authUserId: string;
  displayName: string;
  fullName: string | null;
  lastName: string | null;
  firstName: string | null;
  middleName: string | null;
  mobileNumber: string | null;
  email: string | null;
  roleName: string;
  roleLevel: number | null;
  groupNames: string[];
  accountNames: string[];
  directoryStatus: DirectoryStatus;
  profilePhotoUrl: string | null;
  reportsToAuthUserId: string | null;
  directReportAuthUserIds: string[];
}

export interface TeamDirectorySummary {
  totalMembers: number;
  opsLeadershipCount: number;
  hrcoCount: number;
  activeScopesCount: number;
}

export interface ReportingStructure {
  reportsTo: TeamDirectoryUser[];
  directReports: TeamDirectoryUser[];
}

export type TeamDirectoryErrorKind = "access_denied" | "retryable";

export class TeamDirectoryDataError extends Error {
  kind: TeamDirectoryErrorKind;

  constructor(kind: TeamDirectoryErrorKind, message: string) {
    super(message);
    this.name = "TeamDirectoryDataError";
    this.kind = kind;
  }
}

export interface FetchTeamDirectoryParams {
  search?: string;
  role?: string;
  groupId?: string;
  accountId?: string;
}

// ---------------------------------------------------------------------------
// Helpers & Formatting Utilities
// ---------------------------------------------------------------------------

export function toProperCase(text: string): string {
  if (!text) return "";
  return text
    .split(/\s+/)
    .map((word) =>
      word.length > 0 ? word[0].toUpperCase() + word.substring(1).toLowerCase() : ""
    )
    .join(" ");
}

export function formatDirectoryName(user: TeamDirectoryUser): string {
  const last = toProperCase(user.lastName?.trim() ?? "");
  const first = toProperCase(user.firstName?.trim() ?? "");
  const middle = user.middleName?.trim() ?? "";

  if (last && first) {
    if (middle) {
      const initial = middle[0].toUpperCase();
      return `${last}, ${first} ${initial}.`;
    }
    return `${last}, ${first}`;
  }

  if (user.fullName?.trim()) {
    return user.fullName.trim();
  }
  return user.displayName.trim();
}

export function getUserInitials(user: TeamDirectoryUser): string {
  const last = user.lastName?.trim();
  const first = user.firstName?.trim();
  if (last && first) {
    return `${first[0]}${last[0]}`.toUpperCase();
  }
  const source = (user.displayName || user.fullName || "").trim();
  if (!source) return "?";
  if (source.includes(",")) {
    const parts = source.split(",");
    const lPart = parts[0]?.trim() ?? "";
    const fPart = parts[1]?.trim() ?? "";
    const fWord = fPart.split(/\s+/).filter(Boolean)[0] ?? "";
    const lWord = lPart.split(/\s+/).filter(Boolean)[0] ?? "";
    if (fWord && lWord) return `${fWord[0]}${lWord[0]}`.toUpperCase();
    if (lWord) return lWord[0].toUpperCase();
  }
  const words = source.split(/\s+/).filter(Boolean);
  if (words.length >= 2) {
    return `${words[0][0]}${words[words.length - 1][0]}`.toUpperCase();
  }
  return words[0]?.[0]?.toUpperCase() ?? "?";
}

export function getRoleTint(user: TeamDirectoryUser): string {
  const role = user.roleName.toLowerCase().trim();
  if (user.roleLevel === 100 || role.includes("super admin")) {
    return "#7C3AED"; // Purple
  }
  if (user.roleLevel === 90 || role.includes("head admin")) {
    return "#0F766E"; // Teal
  }
  if (role === "om" || role.includes("operations manager")) {
    return "#0053A6"; // Brand Blue
  }
  if (role.includes("recruitment")) {
    return "#B45309"; // Amber
  }
  if (role.includes("encoder")) {
    return "#475569"; // Slate
  }
  return "#0053A6"; // Brand Primary for TL, ATL, HRCO, etc.
}

export function getBroadAccessScopeLabel(user: TeamDirectoryUser): string | null {
  const role = user.roleName.toLowerCase().trim();
  if (user.roleLevel === 100 || role.includes("super admin")) {
    return "Global Access";
  }
  if (user.roleLevel === 90 || role.includes("head admin")) {
    return "All Groups";
  }
  return null;
}

export function getUserScopeSummary(user: TeamDirectoryUser): string {
  const accessLabel = getBroadAccessScopeLabel(user);
  if (accessLabel) return accessLabel;

  const groupSummary =
    user.groupNames.length === 1
      ? user.groupNames[0]
      : user.groupNames.length > 1
      ? `${user.groupNames.length} Groups`
      : null;

  const accountSummary =
    user.accountNames.length === 1
      ? user.accountNames[0]
      : user.accountNames.length > 1
      ? `${user.accountNames.length} Accounts`
      : null;

  if (!groupSummary && !accountSummary) {
    return "No scope assigned";
  }
  if (!groupSummary) return accountSummary!;
  if (!accountSummary) return groupSummary;
  return `${groupSummary} • ${accountSummary}`;
}

export function getDisplayGroupNames(user: TeamDirectoryUser): string[] {
  if (user.groupNames.length > 0) return user.groupNames;
  const accessLabel = getBroadAccessScopeLabel(user);
  return accessLabel ? [accessLabel] : [];
}

export function getDisplayAccountNames(user: TeamDirectoryUser): string[] {
  if (user.accountNames.length > 0) return user.accountNames;
  const role = user.roleName.toLowerCase().trim();
  if (user.roleLevel === 100 || role.includes("super admin")) {
    return ["Global Access"];
  }
  if (user.roleLevel === 90 || role.includes("head admin")) {
    return ["All Accounts"];
  }
  return [];
}

// ---------------------------------------------------------------------------
// Hierarchical Reporting Calculator
// ---------------------------------------------------------------------------

function getRoleKey(user: TeamDirectoryUser): string | null {
  const normalized = user.roleName.trim().toLowerCase();
  if (user.roleLevel === 100 || normalized === "super admin") {
    return "super_admin";
  }
  if (user.roleLevel === 90 || normalized === "head admin") {
    return "head_admin";
  }
  if (normalized === "encoder") return "encoder";
  if (normalized === "om" || normalized === "operations manager") return "om";
  if (normalized === "tl" || normalized === "team leader") return "tl";
  if (normalized === "atl" || normalized === "assistant team leader") {
    return "atl";
  }
  if (normalized === "hrco" || normalized === "hr coordinator") return "hrco";
  return null;
}

function getManagerRoleKey(user: TeamDirectoryUser): string | null {
  const key = getRoleKey(user);
  switch (key) {
    case "head_admin":
      return "super_admin";
    case "encoder":
      return "head_admin";
    case "tl":
      return "om";
    case "atl":
      return "tl";
    case "hrco":
      return "atl";
    default:
      return null;
  }
}

function getDirectReportRoleKey(user: TeamDirectoryUser): string | null {
  const key = getRoleKey(user);
  switch (key) {
    case "super_admin":
      return "head_admin";
    case "head_admin":
      return "encoder";
    case "om":
      return "tl";
    case "tl":
      return "atl";
    case "atl":
      return "hrco";
    default:
      return null;
  }
}

function sharesScope(user: TeamDirectoryUser, other: TeamDirectoryUser): boolean {
  if (getBroadAccessScopeLabel(user) || getBroadAccessScopeLabel(other)) {
    return true;
  }

  const userGroups = new Set(user.groupNames.map((g) => g.toLowerCase().trim()));
  const otherGroups = new Set(other.groupNames.map((g) => g.toLowerCase().trim()));
  const userAccounts = new Set(user.accountNames.map((a) => a.toLowerCase().trim()));
  const otherAccounts = new Set(other.accountNames.map((a) => a.toLowerCase().trim()));

  if (userGroups.size === 0 && userAccounts.size === 0) return false;
  if (otherGroups.size === 0 && otherAccounts.size === 0) return false;

  for (const g of userGroups) {
    if (otherGroups.has(g)) return true;
  }
  for (const a of userAccounts) {
    if (otherAccounts.has(a)) return true;
  }
  return false;
}

export function getReportingStructure(
  user: TeamDirectoryUser,
  allUsers: TeamDirectoryUser[]
): ReportingStructure {
  const userById = new Map<string, TeamDirectoryUser>();
  for (const person of allUsers) {
    if (person.authUserId) {
      userById.set(person.authUserId, person);
    }
  }

  const explicitManager = user.reportsToAuthUserId
    ? userById.get(user.reportsToAuthUserId) ?? null
    : null;

  const explicitReports = user.directReportAuthUserIds
    .map((id) => userById.get(id))
    .filter((person): person is TeamDirectoryUser =>
      Boolean(person && person.authUserId !== user.authUserId)
    );

  const fallbackManagerKey = getManagerRoleKey(user);
  const fallbackReportKey = getDirectReportRoleKey(user);

  const reportsTo = explicitManager
    ? [explicitManager]
    : allUsers.filter(
        (person) =>
          person.authUserId !== user.authUserId &&
          fallbackManagerKey !== null &&
          getRoleKey(person) === fallbackManagerKey &&
          sharesScope(user, person)
      );

  const directReports =
    explicitReports.length > 0
      ? explicitReports
      : allUsers.filter(
          (person) =>
            person.authUserId !== user.authUserId &&
            fallbackReportKey !== null &&
            getRoleKey(person) === fallbackReportKey &&
            sharesScope(user, person)
        );

  const sortFn = (a: TeamDirectoryUser, b: TeamDirectoryUser) =>
    formatDirectoryName(a).localeCompare(formatDirectoryName(b));

  reportsTo.sort(sortFn);
  directReports.sort(sortFn);

  return { reportsTo, directReports };
}

// ---------------------------------------------------------------------------
// Summary Calculator
// ---------------------------------------------------------------------------

export function calculateTeamDirectorySummary(
  users: TeamDirectoryUser[]
): TeamDirectorySummary {
  const totalMembers = users.length;
  let opsLeadershipCount = 0;
  let hrcoCount = 0;
  const uniqueScopes = new Set<string>();

  for (const user of users) {
    const role = user.roleName.toLowerCase().trim();
    if (
      role === "om" ||
      role.includes("operations manager") ||
      role === "tl" ||
      role.includes("team leader") ||
      role === "atl" ||
      role.includes("assistant team leader") ||
      (user.roleLevel !== null && user.roleLevel >= 35 && user.roleLevel <= 70)
    ) {
      opsLeadershipCount++;
    } else if (
      role === "hrco" ||
      role.includes("hr coordinator") ||
      user.roleLevel === 30
    ) {
      hrcoCount++;
    }

    user.groupNames.forEach((g) => uniqueScopes.add(`g:${g.toLowerCase().trim()}`));
    user.accountNames.forEach((a) => uniqueScopes.add(`a:${a.toLowerCase().trim()}`));
  }

  return {
    totalMembers,
    opsLeadershipCount,
    hrcoCount,
    activeScopesCount: uniqueScopes.size,
  };
}

// ---------------------------------------------------------------------------
// Data Mapping & Fetcher
// ---------------------------------------------------------------------------

export function mapTeamDirectoryUser(raw: Record<string, unknown>): TeamDirectoryUser {
  const authUserId = String(raw.auth_user_id ?? "").trim();
  const fullName = raw.full_name ? String(raw.full_name).trim() : null;
  const rawDisplayName = raw.display_name ? String(raw.display_name).trim() : "";
  const displayName = rawDisplayName || fullName || "User";
  const lastName = raw.last_name ? String(raw.last_name).trim() : null;
  const firstName = raw.first_name ? String(raw.first_name).trim() : null;
  const middleName = raw.middle_name ? String(raw.middle_name).trim() : null;
  const mobileNumber = raw.mobile_number ? String(raw.mobile_number).trim() : null;
  const email = raw.email ? String(raw.email).trim() : null;
  const roleName = raw.role_name ? String(raw.role_name).trim() : "User";
  const roleLevel =
    raw.role_level !== undefined && raw.role_level !== null
      ? Number(raw.role_level)
      : null;

  const normalizeList = (val: unknown): string[] => {
    if (!val) return [];
    if (Array.isArray(val)) {
      return val.map((v) => String(v).trim()).filter(Boolean);
    }
    const str = String(val).trim();
    if (!str) return [];
    return str
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
  };

  const groupNames = normalizeList(raw.group_names);
  const accountNames = normalizeList(raw.account_names);

  const rawStatus = raw.directory_status ? String(raw.directory_status).trim() : "Available";
  const directoryStatus: DirectoryStatus =
    rawStatus === "Busy" || rawStatus === "On Leave" || rawStatus === "Offline"
      ? rawStatus
      : "Available";

  const profilePhotoUrl = raw.profile_photo_url
    ? String(raw.profile_photo_url).trim()
    : null;

  const reportsTo = raw.reports_to_auth_user_id ?? raw.manager_auth_user_id;
  const reportsToAuthUserId = reportsTo ? String(reportsTo).trim() : null;

  const directReportIds = normalizeList(
    raw.direct_report_auth_user_ids ?? raw.direct_reports_auth_user_ids
  );

  return {
    authUserId,
    displayName,
    fullName,
    lastName,
    firstName,
    middleName,
    mobileNumber,
    email,
    roleName,
    roleLevel,
    groupNames,
    accountNames,
    directoryStatus,
    profilePhotoUrl,
    reportsToAuthUserId,
    directReportAuthUserIds: directReportIds,
  };
}

export async function fetchTeamDirectory(
  params?: FetchTeamDirectoryParams
): Promise<TeamDirectoryUser[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_team_directory", {
    p_search: params?.search?.trim() || null,
    p_role: params?.role?.trim() || null,
    p_group_id: params?.groupId?.trim() || null,
    p_account_id: params?.accountId?.trim() || null,
  });

  if (error) {
    const code = error.code ?? "";
    const msg = error.message ?? "";
    if (code === "42501" || msg.toLowerCase().includes("permission denied")) {
      throw new TeamDirectoryDataError("access_denied", msg);
    }
    throw new TeamDirectoryDataError("retryable", msg);
  }

  const rows = Array.isArray(data) ? (data as Record<string, unknown>[]) : [];
  return rows.map(mapTeamDirectoryUser);
}

// ---------------------------------------------------------------------------
// React Query Hooks
// ---------------------------------------------------------------------------

export function useTeamDirectory(params?: FetchTeamDirectoryParams) {
  return useQuery({
    queryKey: ["team-directory", params],
    queryFn: () => fetchTeamDirectory(params),
    staleTime: 60_000,
  });
}

export function useTeamDirectoryRoster(params?: FetchTeamDirectoryParams) {
  const allDirectoryQuery = useQuery({
    queryKey: ["team-directory", "all"],
    queryFn: () => fetchTeamDirectory(),
    staleTime: 60_000,
  });

  const isFiltered = Boolean(
    params?.search || params?.role || params?.groupId || params?.accountId
  );

  const filteredQuery = useQuery({
    queryKey: ["team-directory", params],
    queryFn: () => fetchTeamDirectory(params),
    staleTime: 60_000,
    enabled: isFiltered,
  });

  const data = isFiltered
    ? (filteredQuery.data ?? [])
    : (allDirectoryQuery.data ?? []);
  const allUsers = allDirectoryQuery.data ?? [];
  const isLoading = isFiltered
    ? filteredQuery.isLoading || allDirectoryQuery.isLoading
    : allDirectoryQuery.isLoading;
  const error = isFiltered
    ? filteredQuery.error || allDirectoryQuery.error
    : allDirectoryQuery.error;
  const refetch = isFiltered
    ? () => {
        filteredQuery.refetch();
        allDirectoryQuery.refetch();
      }
    : () => allDirectoryQuery.refetch();

  return {
    users: data,
    allUsers: allUsers.length > 0 ? allUsers : data,
    summary: calculateTeamDirectorySummary(allUsers.length > 0 ? allUsers : data),
    isLoading,
    error,
    refetch,
  };
}
