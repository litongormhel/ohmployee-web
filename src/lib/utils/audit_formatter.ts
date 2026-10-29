/**
 * src/lib/utils/audit_formatter.ts
 *
 * Presentation-layer formatter for System Audit Logs.
 * Converts raw database actions, JSON diffs, and table names into
 * human-readable, actor-first operational activity summaries.
 */

import { formatDisplayText } from "./displayText";

export interface SystemAuditLogItem {
  id: string;
  actorId: string | null;
  actorName: string | null;
  actorRole: string | null;
  module: string;
  action: string;
  recordId: string | null;
  oldData: Record<string, unknown> | null;
  newData: Record<string, unknown> | null;
  timestamp: string;
}

export interface EntityDetails {
  subject?: string;
  position?: string;
  storeName?: string;
  vcode?: string;
  account?: string;
  employeeNo?: string;
  reason?: string;
}

export function normalizeModuleName(module: string): string {
  const clean = module.trim().toLowerCase();
  switch (clean) {
    case "hr_emploc":
    case "hremploc":
      return "HR Emploc";
    case "plantilla":
      return "Plantilla";
    case "vacancies":
    case "vacancy":
      return "Vacancies";
    case "users_profile":
    case "user_profile":
    case "user profile":
    case "profile":
      return "User Profile";
    case "security":
      return "Security";
    case "settings":
      return "Settings";
    case "cencom":
      return "CENCOM";
    case "archival":
      return "Archival";
    case "moses hq":
    case "moses":
      return "Moses HQ";
    default:
      return formatDisplayText(module);
  }
}

export type ActionBadgeVariant = "danger" | "brand" | "success" | "amber" | "neutral";

export function formatActionBadge(action: string): { label: string; variant: ActionBadgeVariant } {
  const upper = action.trim().toUpperCase();

  switch (upper) {
    case "UPDATE_AVATAR":
      return { label: "Avatar Update", variant: "brand" };
    case "SOFT_DELETE":
      return { label: "Soft Delete", variant: "danger" };
    case "UPDATE":
      return { label: "Update", variant: "brand" };
    case "INSERT":
      return { label: "Create", variant: "success" };
    case "DELETE":
      return { label: "Delete", variant: "danger" };
    case "APPROVE":
      return { label: "Approved", variant: "success" };
    case "REJECT":
      return { label: "Rejected", variant: "danger" };
    case "ROLE_CHANGE":
      return { label: "Role Change", variant: "amber" };
    case "LOGIN":
      return { label: "Login", variant: "neutral" };
    case "LOGOUT":
      return { label: "Logout", variant: "neutral" };
    case "TERMINATE_SESSION":
    case "REVOKE":
    case "REMOTE_REVOKE":
      return { label: "Session Revoked", variant: "danger" };
    case "START_ACTING_SESSION":
      return { label: "Acting Session Started", variant: "amber" };
    case "STOP_ACTING_SESSION":
      return { label: "Acting Session Stopped", variant: "neutral" };
    case "DEFICIENCY_TAGGED":
      return { label: "Correction Flagged", variant: "amber" };
    case "CORRECTION_RESOLVED":
      return { label: "Correction Resolved", variant: "success" };
    default: {
      const formatted = upper
        .split("_")
        .map((w) => w.charAt(0) + w.slice(1).toLowerCase())
        .join(" ");
      return { label: formatted, variant: "neutral" };
    }
  }
}

export function extractEntityDetails(log: SystemAuditLogItem): EntityDetails {
  const data = log.newData || log.oldData || {};
  const oldData = log.oldData || {};

  const subject =
    (data.employee_name as string) ||
    (data.applicant_name as string) ||
    (data.employee_name_snapshot as string) ||
    (data.applicant_name_snapshot as string) ||
    (data.full_name as string) ||
    (oldData.employee_name as string) ||
    (oldData.applicant_name as string) ||
    (oldData.full_name as string) ||
    (data.first_name && data.last_name ? `${data.last_name}, ${data.first_name}` : undefined) ||
    (oldData.first_name && oldData.last_name ? `${oldData.last_name}, ${oldData.first_name}` : undefined);

  const position = (data.position as string) || (oldData.position as string);
  const storeName = (data.store_name as string) || (oldData.store_name as string);
  const vcode = (data.vcode as string) || (data.vacancy_code_snapshot as string) || (oldData.vcode as string);
  const account = (data.account as string) || (oldData.account as string);
  const employeeNo = (data.employee_no as string) || (data.emploc_no as string) || (oldData.employee_no as string);
  const reason = (data.reason as string) || (data.deletion_reason as string) || (data.archive_reason as string);

  return {
    subject: subject ? formatDisplayText(subject) : undefined,
    position: position ? formatDisplayText(position) : undefined,
    storeName: storeName ? formatDisplayText(storeName) : undefined,
    vcode: vcode ? vcode.toUpperCase() : undefined,
    account: account ? formatDisplayText(account) : undefined,
    employeeNo: employeeNo ? employeeNo.trim() : undefined,
    reason: reason ? reason.trim() : undefined,
  };
}

export function formatAuditSentence(log: SystemAuditLogItem): string {
  const { action, module, oldData, newData } = log;
  const upperAction = action.toUpperCase();
  const lowerModule = module.toLowerCase();
  const entity = extractEntityDetails(log);

  // 1. Direct log message if present in payload
  const logMessage = (newData?.log_message as string) || (oldData?.log_message as string);
  if (logMessage && logMessage.trim().length > 0) {
    return logMessage.trim();
  }

  // 2. Avatar Update
  if (upperAction === "UPDATE_AVATAR") {
    const name = entity.subject || log.actorName || "user";
    return `Updated profile photo for ${name}.`;
  }

  // 3. Plantilla Module
  if (lowerModule.includes("plantilla")) {
    const subjectDesc = entity.subject
      ? `${entity.subject}${entity.position ? ` (${entity.position})` : ""}`
      : "plantilla record";
    const locDesc = entity.storeName ? ` at ${entity.storeName}` : "";
    const vcodeDesc = entity.vcode ? ` [${entity.vcode}]` : "";

    if (upperAction === "SOFT_DELETE" || newData?.status === "Deactivated" || newData?.is_deleted === true) {
      return `Deactivated plantilla slot for ${subjectDesc}${locDesc}${vcodeDesc}.`;
    }
    if (upperAction === "INSERT") {
      return `Deployed ${subjectDesc}${locDesc}${vcodeDesc} to plantilla.`;
    }
    if (oldData?.status && newData?.status && oldData.status !== newData.status) {
      return `Changed plantilla status for ${subjectDesc} from "${oldData.status}" to "${newData.status}".`;
    }
    return `Updated plantilla record for ${subjectDesc}${locDesc}${vcodeDesc}.`;
  }

  // 4. Vacancy Module
  if (lowerModule.includes("vacanc")) {
    const posDesc = entity.position ? entity.position : "vacancy";
    const locDesc = entity.storeName ? ` at ${entity.storeName}` : "";
    const vcodeDesc = entity.vcode ? ` [${entity.vcode}]` : "";

    if (oldData?.status === "Filled" && newData?.status === "Open") {
      return `Reopened ${posDesc}${locDesc}${vcodeDesc}.`;
    }
    if (oldData?.status && newData?.status && oldData.status !== newData.status) {
      return `Updated status for ${posDesc}${locDesc}${vcodeDesc} from "${oldData.status}" to "${newData.status}".`;
    }
    if (upperAction === "INSERT") {
      return `Created new ${posDesc} slot${locDesc}${vcodeDesc}.`;
    }
    if (upperAction === "DELETE" || newData?.is_archived === true) {
      return `Archived or closed vacancy for ${posDesc}${locDesc}${vcodeDesc}.`;
    }
    return `Updated vacancy details for ${posDesc}${locDesc}${vcodeDesc}.`;
  }

  // 5. HR Emploc Module
  if (lowerModule.includes("hr_emploc") || lowerModule.includes("emploc")) {
    const subjectDesc = entity.subject || "employee";
    const vcodeDesc = entity.vcode ? ` [${entity.vcode}]` : "";

    if (oldData?.status === "Moved to Plantilla" && newData?.status === "Pending Emploc") {
      const reasonPart = entity.reason ? ` (Reason: ${entity.reason})` : "";
      return `Reverted ${subjectDesc} from Deployed back to Pending${reasonPart}${vcodeDesc}.`;
    }
    if (oldData?.status && newData?.status && oldData.status !== newData.status) {
      return `Updated ${subjectDesc}'s status from "${oldData.status}" to "${newData.status}"${vcodeDesc}.`;
    }
    if (oldData?.hr_status && newData?.hr_status && oldData.hr_status !== newData.hr_status) {
      return `Changed HR status for ${subjectDesc} from "${oldData.hr_status}" to "${newData.hr_status}".`;
    }
    if (!oldData?.employee_no && newData?.employee_no) {
      return `Assigned Employee No. ${newData.employee_no} to ${subjectDesc}.`;
    }
    return `Updated HR Emploc details for ${subjectDesc}${vcodeDesc}.`;
  }

  // 6. Generic Field Diff Fallback
  if (oldData && newData) {
    const changedKeys = Object.keys(newData).filter((k) => {
      if (["updated_at", "updated_by", "timestamp"].includes(k)) return false;
      return JSON.stringify(oldData[k]) !== JSON.stringify(newData[k]);
    });

    if (changedKeys.includes("status")) {
      return `Updated status from "${oldData.status ?? 'none'}" to "${newData.status ?? 'none'}".`;
    }
    if (changedKeys.length === 1) {
      const key = changedKeys[0];
      return `Modified ${key.replace(/_/g, " ")} on ${normalizeModuleName(module)}.`;
    }
    if (changedKeys.length > 1) {
      return `Modified ${changedKeys.length} fields on ${normalizeModuleName(module)} record.`;
    }
  }

  // 7. Last Fallback
  const actionLabel = formatActionBadge(action).label;
  return `${actionLabel} performed on ${normalizeModuleName(module)} record.`;
}

export function formatTargetLabel(log: SystemAuditLogItem): string {
  const { module } = log;
  const lowerModule = module.toLowerCase();
  const entity = extractEntityDetails(log);

  if (lowerModule.includes("profile")) {
    return entity.subject ? entity.subject : "User Profile";
  }

  if (lowerModule.includes("plantilla")) {
    if (entity.vcode && entity.storeName) {
      return `${entity.vcode} • ${entity.storeName}`;
    }
    if (entity.subject && entity.vcode) {
      return `${entity.subject} (${entity.vcode})`;
    }
    return entity.vcode || entity.subject || "Plantilla Slot";
  }

  if (lowerModule.includes("vacanc")) {
    if (entity.vcode && entity.position) {
      return `${entity.vcode} • ${entity.position}${entity.storeName ? ` (${entity.storeName})` : ""}`;
    }
    return entity.vcode || entity.position || "Vacancy Slot";
  }

  if (lowerModule.includes("emploc")) {
    if (entity.subject && entity.vcode) {
      return `${entity.subject} (${entity.vcode})`;
    }
    return entity.subject || entity.vcode || "HR Emploc Record";
  }

  return (
    entity.subject ||
    entity.vcode ||
    entity.storeName ||
    `${normalizeModuleName(module)} Record`
  );
}

export interface FieldChange {
  key: string;
  label: string;
  oldValue: string;
  newValue: string;
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuidOrStoragePath(val: unknown): boolean {
  if (typeof val !== "string") return false;
  return UUID_REGEX.test(val.trim()) || val.includes("/avatar.webp");
}

export function computeMeaningfulDiff(
  oldData: Record<string, unknown> | null,
  newData: Record<string, unknown> | null
): FieldChange[] {
  if (!oldData && !newData) return [];
  const oldObj = oldData || {};
  const newObj = newData || {};

  const allKeys = Array.from(new Set([...Object.keys(oldObj), ...Object.keys(newObj)]));
  const diffs: FieldChange[] = [];

  for (const key of allKeys) {
    // 1. Filter technical noise and foreign keys
    if (
      key === "id" ||
      key.endsWith("_id") ||
      key.endsWith("_by") ||
      key.endsWith("_at") ||
      key.endsWith("_snapshot") ||
      key.startsWith("qa_archive") ||
      key.startsWith("source_") ||
      key === "log_message" ||
      key === "timestamp"
    ) {
      continue;
    }

    const v1 = oldObj[key];
    const v2 = newObj[key];

    // If identical, skip
    if (JSON.stringify(v1) === JSON.stringify(v2)) {
      continue;
    }

    // Special translation for avatar photo path
    if (key === "avatar_path") {
      diffs.push({
        key,
        label: "Profile Photo",
        oldValue: v1 ? "Existing Photo" : "No Photo",
        newValue: v2 ? "New Photo Uploaded" : "Photo Removed",
      });
      continue;
    }

    // Skip raw UUIDs or technical storage paths
    if (isUuidOrStoragePath(v1) || isUuidOrStoragePath(v2)) {
      continue;
    }

    // Special translation for boolean flags
    if (key === "is_deleted") {
      diffs.push({
        key,
        label: "Plantilla Status",
        oldValue: v1 ? "Separated / Inactive" : "Active",
        newValue: v2 ? "Separated / Inactive" : "Active",
      });
      continue;
    }

    if (key === "is_archived") {
      diffs.push({
        key,
        label: "Archive Status",
        oldValue: v1 ? "Archived" : "Active",
        newValue: v2 ? "Archived" : "Active",
      });
      continue;
    }

    if (key === "has_penalty") {
      diffs.push({
        key,
        label: "Penalty Exposure",
        oldValue: v1 ? "Yes" : "No",
        newValue: v2 ? "Yes" : "No",
      });
      continue;
    }

    // Standard human label
    const label = formatFieldLabel(key);
    diffs.push({
      key,
      label,
      oldValue: formatValueForDisplay(v1),
      newValue: formatValueForDisplay(v2),
    });
  }

  return diffs;
}

function formatFieldLabel(key: string): string {
  switch (key) {
    case "status":
      return "Status";
    case "hr_status":
      return "HR Status";
    case "employee_no":
    case "emploc_no":
      return "Employee ID";
    case "position":
      return "Position";
    case "store_name":
      return "Store Outlet";
    case "vcode":
      return "Vacancy Code";
    case "account":
      return "Account";
    case "reason":
    case "deletion_reason":
      return "Reason";
    case "remarks":
      return "Remarks";
    case "full_name":
      return "Full Name";
    case "mobile_number":
      return "Mobile Number";
    case "date_hired":
      return "Date Hired";
    case "resignation_date":
      return "Resignation Date";
    case "required_headcount":
      return "Headcount Quota";
    default:
      return key.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  }
}

function formatValueForDisplay(val: unknown): string {
  if (val === null || val === undefined) return "null";
  if (typeof val === "boolean") return val ? "true" : "false";
  if (typeof val === "string") return val.trim().length === 0 ? '""' : val;
  if (typeof val === "object") return JSON.stringify(val);
  return String(val);
}
