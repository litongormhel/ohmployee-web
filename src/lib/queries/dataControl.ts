import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { formatPersonName } from "@/lib/utils/formatName";

// ============================================================================
// Scopes & References (Plantilla, Vacancy, Accounts)
// ============================================================================

export interface DataControlScopeGroup {
  id: string;
  label: string;
  sortOrder: number;
}

export interface DataControlScopeAccount {
  id: string;
  name: string;
  groupId: string;
  groupName?: string;
}

export async function fetchDataControlGroups(): Promise<DataControlScopeGroup[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_plantilla_scope_menu");
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  const unique = new Map<string, DataControlScopeGroup>();
  for (const row of data as Record<string, unknown>[]) {
    if (row.can_view === false) continue;
    const id = String(row.scope_id ?? row.group_id ?? "");
    if (!id) continue;
    const label = String(row.label ?? row.group_name ?? "Group");
    const sortOrder = Number(row.sort_order ?? 0);
    const existing = unique.get(id);
    if (!existing || sortOrder < existing.sortOrder) {
      unique.set(id, { id, label, sortOrder });
    }
  }

  return Array.from(unique.values()).sort((a, b) => a.sortOrder - b.sortOrder);
}

export async function fetchDataControlAccounts(groupId: string): Promise<DataControlScopeAccount[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_accounts_by_group", {
    p_group_id: groupId,
  });
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[])
    .map((row) => ({
      id: String(row.account_id ?? row.id ?? ""),
      name: String(row.account_name ?? "Account"),
      groupId: String(row.group_id ?? groupId),
      groupName: row.group_name ? String(row.group_name) : undefined,
    }))
    .filter((a) => a.id.length > 0);
}

export function useDataControlGroups() {
  return useQuery({
    queryKey: ["data-control-groups"],
    queryFn: fetchDataControlGroups,
    staleTime: 5 * 60 * 1000,
  });
}

export function useDataControlAccounts(groupId: string | null) {
  return useQuery({
    queryKey: ["data-control-accounts", groupId],
    queryFn: () => (groupId ? fetchDataControlAccounts(groupId) : Promise.resolve([])),
    enabled: !!groupId,
    staleTime: 5 * 60 * 1000,
  });
}

// ============================================================================
// 1. Plantilla Bulk Import Queries & Mutations
// ============================================================================

export interface RollbackReasonOption {
  code: string;
  label: string;
}

export const IMPORT_ROLLBACK_REASONS: RollbackReasonOption[] = [
  { code: "wrong_batch", label: "Wrong batch imported" },
  { code: "wrong_group_account", label: "Wrong Group/Account" },
  { code: "wrong_vcode_list", label: "Wrong VCODE list" },
  { code: "wrong_applicant_pipeline", label: "Wrong applicant pipeline data" },
  { code: "duplicate_migration_correction", label: "Duplicate/migration correction" },
  { code: "uploaded_by_mistake", label: "Uploaded by mistake" },
  { code: "other", label: "Other" },
];

export function formatRollbackRemaining(seconds?: number | null): string {
  const total = seconds ?? 0;
  if (total <= 0) return "0h";
  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  if (days > 0) return `${days}d ${hours}h`;
  return `${hours}h`;
}

export function humanizeRollbackError(raw?: string | null): string {
  if (!raw || !raw.trim()) return "Rollback operation could not be completed.";
  const lower = raw.toLowerCase();
  if (lower.includes("records modified after import approval")) {
    return "Rollback blocked because imported records were modified after approval.";
  }
  if (lower.includes("rollback_window_expired")) {
    return "Rollback window expired.";
  }
  if (lower.includes("already in progress") || lower.includes("lock")) {
    return "Another rollback is already in progress. Please wait and retry.";
  }
  if (lower.includes("snapshot") || lower.includes("missing snapshot")) {
    return "Allocation snapshot is missing. Rollback cannot restore previous state.";
  }
  if (lower.includes("dependency") || lower.includes("foreign key")) {
    return "Rollback cannot continue due to dependent records.";
  }
  if (lower.includes("constraint") || lower.includes("violation")) {
    return "Rollback cannot continue due to data integrity constraints.";
  }
  return raw.replace(/^Exception:\s*/, "");
}

export interface PlantillaImportRollbackHistory {
  batchId: string;
  rollbackStatus?: string;
  rollbackReason?: string;
  rollbackReasonCode?: string;
  rollbackReasonNote?: string;
  rollbackRequestedBy?: string;
  rollbackRequestedByName?: string;
  rollbackRequestedAt?: string;
  rollbackApprovedBy?: string;
  rollbackApprovedByName?: string;
  rollbackApprovedAt?: string;
  rollbackCompletedAt?: string;
  rollbackErrorDetail?: string;
  rolledBackBy?: string;
  rolledBackAt?: string;
}

export interface PlantillaImportBatch {
  id: string;
  fileName: string;
  status: string;
  groupName?: string;
  accountName?: string;
  accountId?: string;
  hrcoUserId?: string;
  uploadedBy?: string;
  uploadedRole?: string;
  uploadedAt?: string;
  approvedAt?: string;
  approvedBy?: string;
  approvedByName?: string;
  rejectedBy?: string;
  rejectedByName?: string;
  rejectedAt?: string;
  rejectionReason?: string;
  rejectionReasonCode?: string;
  rejectionReasonNote?: string;
  totalRows: number;
  validRows: number;
  blockedRows: number;
  flaggedRows: number;
  skippedRows?: number;
  committedStores?: number;
  committedEmployees?: number;
  newStoresCount?: number;
  existingStoresCount?: number;
  errorSummary?: Record<string, number>;
  // Two-step rollback & window fields
  rollbackStatus?: string;
  rollbackReason?: string;
  rollbackReasonCode?: string;
  rollbackReasonNote?: string;
  rollbackRequestedBy?: string;
  rollbackRequestedAt?: string;
  rollbackApprovedBy?: string;
  rollbackApprovedAt?: string;
  rollbackCompletedAt?: string;
  rollbackErrorDetail?: string;
  rolledBackBy?: string;
  rolledBackAt?: string;
  rollbackWindowStartedAt?: string;
  rollbackExpiresAt?: string;
  rollbackRemainingSeconds?: number;
  rollbackAllowed: boolean;
  rollbackUiState?: string;
  rollbackBlockReason?: string;
  canEmergencyRollback: boolean;
  commitErrorDetail?: string;
  errorMessage?: string;
}

export interface PlantillaRowValidationError {
  field?: string;
  conflictType?: string;
  msg: string;
}

export interface PlantillaImportPreviewRow {
  rowNumber: number;
  vcode: string;
  storeName: string;
  employeeNo: string;
  employeeName: string;
  position: string;
  employmentType: string;
  requiredHc?: string | number;
  motherAccount?: string;
  scheduleDays?: string;
  scheduleTime?: string;
  dayoff?: string;
  needsHrco?: boolean;
  resolvedHrcoUserId?: string;
  hrcoEmail?: string;
  isRoving?: boolean;
  rovingStoreCount?: number;
  validationStatus: string;
  validationMessages: string[];
  validationErrors?: PlantillaRowValidationError[];
  validationFlags?: Array<{ flag?: string; msg?: string; conflictType?: string }>;
}

export interface ValidatePlantillaImportResult {
  status: string;
  totalRows: number;
  validRows: number;
  flaggedRows: number;
  skippedRows: number;
  blockedRows: number;
  errorSummary?: Record<string, number>;
  rows: PlantillaImportPreviewRow[];
}

export interface SubmitPlantillaImportResult {
  batchId: string;
  status: string;
  totalRows: number;
  validRows: number;
  flaggedRows: number;
  skippedRows: number;
  blockedRows: number;
  errorSummary?: Record<string, number>;
}

export async function fetchPlantillaImportBatches(status?: string): Promise<PlantillaImportBatch[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_plantilla_import_batches", {
    ...(status ? { p_status: status } : {}),
  });
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    id: String(row.id ?? row.batch_id ?? ""),
    fileName: String(row.file_name ?? "Plantilla import"),
    status: String(row.status ?? "draft_uploaded"),
    groupName: row.group_name ? String(row.group_name) : undefined,
    accountName: row.account_name ? String(row.account_name) : undefined,
    accountId: row.selected_account_id ? String(row.selected_account_id) : undefined,
    hrcoUserId: row.hrco_user_id ? String(row.hrco_user_id) : undefined,
    uploadedBy: String(row.uploader_name ?? row.uploaded_by ?? ""),
    uploadedRole: row.uploaded_role ? String(row.uploaded_role) : undefined,
    uploadedAt: String(row.uploaded_at ?? row.created_at ?? ""),
    approvedAt: row.approved_at ? String(row.approved_at) : undefined,
    approvedBy: row.approved_by ? String(row.approved_by) : undefined,
    approvedByName: row.approved_by_name ? String(row.approved_by_name) : undefined,
    rejectedBy: row.rejected_by ? String(row.rejected_by) : undefined,
    rejectedByName: row.rejected_by_name ? String(row.rejected_by_name) : undefined,
    rejectedAt: row.rejected_at ? String(row.rejected_at) : undefined,
    rejectionReason: row.rejection_reason ? String(row.rejection_reason) : undefined,
    rejectionReasonCode: row.rejection_reason_code ? String(row.rejection_reason_code) : undefined,
    rejectionReasonNote: row.rejection_reason_note ? String(row.rejection_reason_note) : undefined,
    totalRows: Number(row.total_rows ?? 0),
    validRows: Number(row.valid_rows ?? 0),
    blockedRows: Number(row.blocked_rows ?? row.invalid_rows ?? 0),
    flaggedRows: Number(row.flagged_rows ?? 0),
    skippedRows: typeof row.skipped_rows === "number" ? row.skipped_rows : undefined,
    committedStores: typeof row.committed_stores === "number" ? row.committed_stores : undefined,
    committedEmployees: typeof row.committed_employees === "number" ? row.committed_employees : undefined,
    newStoresCount: typeof row.new_stores_count === "number" ? row.new_stores_count : undefined,
    existingStoresCount: typeof row.existing_stores_count === "number" ? row.existing_stores_count : undefined,
    errorSummary: row.error_summary && typeof row.error_summary === "object"
      ? (row.error_summary as Record<string, number>)
      : undefined,
    // Rollback mapping
    rollbackStatus: row.rollback_status ? String(row.rollback_status) : undefined,
    rollbackReason: row.rollback_reason ? String(row.rollback_reason) : undefined,
    rollbackReasonCode: row.rollback_reason_code ? String(row.rollback_reason_code) : undefined,
    rollbackReasonNote: row.rollback_reason_note ? String(row.rollback_reason_note) : undefined,
    rollbackRequestedBy: row.rollback_requested_by_name
      ? String(row.rollback_requested_by_name)
      : row.rollback_requested_by
      ? String(row.rollback_requested_by)
      : undefined,
    rollbackRequestedAt: row.rollback_requested_at ? String(row.rollback_requested_at) : undefined,
    rollbackApprovedBy: row.rollback_approved_by_name
      ? String(row.rollback_approved_by_name)
      : row.rollback_approved_by
      ? String(row.rollback_approved_by)
      : undefined,
    rollbackApprovedAt: row.rollback_approved_at ? String(row.rollback_approved_at) : undefined,
    rollbackCompletedAt: row.rollback_completed_at ? String(row.rollback_completed_at) : undefined,
    rollbackErrorDetail: row.rollback_error_detail ? String(row.rollback_error_detail) : undefined,
    rolledBackBy: row.rolled_back_by ? String(row.rolled_back_by) : undefined,
    rolledBackAt: row.rolled_back_at ? String(row.rolled_back_at) : undefined,
    rollbackWindowStartedAt: row.rollback_window_started_at ? String(row.rollback_window_started_at) : undefined,
    rollbackExpiresAt: row.rollback_expires_at ? String(row.rollback_expires_at) : undefined,
    rollbackRemainingSeconds: typeof row.rollback_remaining_seconds === "number" ? row.rollback_remaining_seconds : 0,
    rollbackAllowed: row.rollback_allowed === true,
    rollbackUiState: row.rollback_ui_state ? String(row.rollback_ui_state) : undefined,
    rollbackBlockReason: row.rollback_block_reason ? String(row.rollback_block_reason) : undefined,
    canEmergencyRollback: row.can_emergency_rollback === true,
    commitErrorDetail: row.commit_error_detail
      ? String(row.commit_error_detail)
      : row.error_message
      ? String(row.error_message)
      : undefined,
    errorMessage: row.error_message
      ? String(row.error_message)
      : row.commit_error_detail
      ? String(row.commit_error_detail)
      : undefined,
  }));
}

export async function fetchPlantillaImportRows(batchId: string): Promise<PlantillaImportPreviewRow[]> {
  const supabase = createClient();
  const PAGE_SIZE = 1000;
  let offset = 0;
  let allRows: Record<string, unknown>[] = [];
  let hasMore = true;

  while (hasMore) {
    const { data, error } = await supabase.rpc("get_plantilla_import_rows", {
      p_batch_id: batchId,
      p_offset: offset,
      p_limit: PAGE_SIZE,
    });
    if (error) throw error;
    if (!Array.isArray(data) || data.length === 0) {
      hasMore = false;
      break;
    }

    allRows = allRows.concat(data as Record<string, unknown>[]);
    if (data.length < PAGE_SIZE) {
      hasMore = false;
    } else {
      offset += PAGE_SIZE;
    }
  }

  return allRows.map((row) => {
    const rawErrors = Array.isArray(row.validation_errors) ? row.validation_errors : [];
    const validationErrors: PlantillaRowValidationError[] = rawErrors.map((e) => {
      if (typeof e === "object" && e !== null) {
        const item = e as Record<string, unknown>;
        return {
          field: item.field ? String(item.field) : undefined,
          conflictType: item.conflict_type ? String(item.conflict_type) : undefined,
          msg: String(item.msg ?? item.message ?? ""),
        };
      }
      return { msg: String(e) };
    });

    const rawFlags = Array.isArray(row.validation_flags) ? row.validation_flags : [];
    const validationFlags = rawFlags.map((f) => {
      if (typeof f === "object" && f !== null) {
        const item = f as Record<string, unknown>;
        return {
          flag: item.flag ? String(item.flag) : undefined,
          conflictType: item.conflict_type ? String(item.conflict_type) : undefined,
          msg: String(item.msg ?? item.message ?? ""),
        };
      }
      return { msg: String(f) };
    });

    const rawFallbackMsgs = row.validation_messages ?? row.messages ?? [];
    const fallbackList = Array.isArray(rawFallbackMsgs) ? rawFallbackMsgs.map((m) => String(m)) : [];

    const messages: string[] = [
      ...validationErrors.map((e) => (e.field ? `[${e.field}] ${e.msg}` : e.msg)),
      ...validationFlags.map((f) => (f.flag ? `(Warning: ${f.flag}) ${f.msg}` : f.msg)),
    ].filter((m) => m.trim().length > 0);

    const finalMessages = messages.length > 0 ? messages : fallbackList;

    const firstName = row.first_name ? String(row.first_name) : null;
    const lastName = row.last_name ? String(row.last_name) : null;
    const middleName = row.middle_name ? String(row.middle_name) : null;
    const rawFullName = row.employee_name ?? row.full_name ? String(row.employee_name ?? row.full_name) : null;
    const employeeName = formatPersonName(firstName, lastName, middleName, rawFullName);

    return {
      rowNumber: Number(row.row_number ?? 0),
      vcode: String(row.vcode ?? ""),
      storeName: String(row.store_name ?? ""),
      employeeNo: String(row.employee_no ?? ""),
      employeeName,
      position: String(row.position ?? ""),
      employmentType: String(row.employment_type ?? ""),
      requiredHc: row.required_hc !== undefined ? (row.required_hc as string | number) : undefined,
      motherAccount: row.mother_account ? String(row.mother_account) : undefined,
      scheduleDays: row.schedule_days ? String(row.schedule_days) : row.schedule ? String(row.schedule) : undefined,
      scheduleTime: row.schedule_time ? String(row.schedule_time) : undefined,
      dayoff: row.dayoff ? String(row.dayoff) : undefined,
      needsHrco: row.needs_hrco === true && !row.resolved_hrco_user_id && (!row.hrco_email_raw || String(row.hrco_email_raw).trim() === ""),
      resolvedHrcoUserId: row.resolved_hrco_user_id ? String(row.resolved_hrco_user_id) : undefined,
      hrcoEmail: row.hrco_email_raw ? String(row.hrco_email_raw) : undefined,
      isRoving: row.is_roving === true,
      rovingStoreCount: Number(row.roving_store_count ?? 0),
      validationStatus: String(row.validation_status ?? row.status ?? "valid"),
      validationMessages: finalMessages,
      validationErrors,
      validationFlags,
    };
  });
}

export async function validatePlantillaBaselineImport(params: {
  fileName: string;
  groupId: string;
  accountId: string;
  rows: Record<string, string>[];
}): Promise<ValidatePlantillaImportResult> {
  const supabase = createClient();
  const rpcRows = params.rows.map((r) => ({
    VCODE: r.VCODE ?? "",
    STORE_NAME: r.STORE_NAME ?? "",
    MOTHER_ACCOUNT: r.MOTHER_ACCOUNT ?? r.ACCOUNT_NAME ?? "",
    AREA_PROVINCE: r.AREA_PROVINCE ?? "",
    AREA_CITY: r.AREA_CITY ?? "",
    POSITION: r.POSITION ?? "",
    EMPLOYMENT_TYPE: r.EMPLOYMENT_TYPE ?? "stationary",
    REQUIRED_HC: r.REQUIRED_HC ?? "1",
    WITH_PENALTY: r.WITH_PENALTY ?? "false",
    EMPLOYEE_NO: r.EMPLOYEE_NO ?? "",
    LAST_NAME: r.LAST_NAME ?? "",
    FIRST_NAME: r.FIRST_NAME ?? "",
    MIDDLE_NAME: r.MIDDLE_NAME ?? "",
    DATE_HIRED: r.DATE_HIRED ?? "",
    CIVIL_STATUS: r.CIVIL_STATUS ?? "",
    RATE: r.RATE ?? "",
    DATE_OF_BIRTH: r.DATE_OF_BIRTH ?? r.BIRTHDATE ?? "",
    CONTACT_NO: r.CONTACT_NO ?? r.CONTACT ?? "",
    ADDRESS: r.ADDRESS ?? "",
    SCHEDULE_DAYS: r.SCHEDULE_DAYS ?? r.SCHEDULE ?? "",
    SCHEDULE_TIME: r.SCHEDULE_TIME ?? "",
    DAYOFF: r.DAYOFF ?? "",
    COORDINATOR: r.COORDINATOR ?? "",
    HRCO_EMAIL: r.HRCO_EMAIL ?? "",
  }));

  const { data, error } = await supabase.rpc("validate_plantilla_baseline_import", {
    p_file_name: params.fileName,
    p_group_id: params.groupId,
    p_account_id: params.accountId,
    p_rows: rpcRows,
  });

  if (error) throw error;
  const res = data as Record<string, unknown>;
  const rawRows = Array.isArray(res.rows) ? (res.rows as Record<string, unknown>[]) : [];

  const previewRows: PlantillaImportPreviewRow[] = rawRows.map((row) => {
    const rawErrors = Array.isArray(row.validation_errors) ? row.validation_errors : [];
    const validationErrors: PlantillaRowValidationError[] = rawErrors.map((e) => {
      if (typeof e === "object" && e !== null) {
        const item = e as Record<string, unknown>;
        return {
          field: item.field ? String(item.field) : undefined,
          conflictType: item.conflict_type ? String(item.conflict_type) : undefined,
          msg: String(item.msg ?? item.message ?? ""),
        };
      }
      return { msg: String(e) };
    });

    const rawFlags = Array.isArray(row.validation_flags) ? row.validation_flags : [];
    const validationFlags = rawFlags.map((f) => {
      if (typeof f === "object" && f !== null) {
        const item = f as Record<string, unknown>;
        return {
          flag: item.flag ? String(item.flag) : undefined,
          conflictType: item.conflict_type ? String(item.conflict_type) : undefined,
          msg: String(item.msg ?? item.message ?? ""),
        };
      }
      return { msg: String(f) };
    });

    const messages: string[] = [
      ...validationErrors.map((e) => (e.field ? `[${e.field}] ${e.msg}` : e.msg)),
      ...validationFlags.map((f) => (f.flag ? `(Warning: ${f.flag}) ${f.msg}` : f.msg)),
    ].filter((m) => m.trim().length > 0);

    const firstName = row.first_name ? String(row.first_name) : null;
    const lastName = row.last_name ? String(row.last_name) : null;
    const middleName = row.middle_name ? String(row.middle_name) : null;
    const rawFullName = row.employee_name ?? row.full_name ? String(row.employee_name ?? row.full_name) : null;
    const employeeName = formatPersonName(firstName, lastName, middleName, rawFullName);

    return {
      rowNumber: Number(row.row_number ?? 0),
      vcode: String(row.vcode ?? ""),
      storeName: String(row.store_name ?? ""),
      employeeNo: String(row.employee_no ?? ""),
      employeeName,
      position: String(row.position ?? ""),
      employmentType: String(row.employment_type ?? ""),
      requiredHc: row.required_hc !== undefined ? (row.required_hc as string | number) : undefined,
      motherAccount: row.mother_account ? String(row.mother_account) : undefined,
      scheduleDays: row.schedule_days ? String(row.schedule_days) : undefined,
      scheduleTime: row.schedule_time ? String(row.schedule_time) : undefined,
      dayoff: row.dayoff ? String(row.dayoff) : undefined,
      needsHrco: row.needs_hrco === true,
      resolvedHrcoUserId: row.resolved_hrco_user_id ? String(row.resolved_hrco_user_id) : undefined,
      hrcoEmail: row.hrco_email_raw ? String(row.hrco_email_raw) : undefined,
      isRoving: row.is_roving === true,
      rovingStoreCount: Number(row.roving_store_count ?? 0),
      validationStatus: String(row.validation_status ?? "valid"),
      validationMessages: messages,
      validationErrors,
      validationFlags,
    };
  });

  return {
    status: String(res.status ?? "valid"),
    totalRows: Number(res.total_rows ?? 0),
    validRows: Number(res.valid_rows ?? 0),
    flaggedRows: Number(res.flagged_rows ?? 0),
    skippedRows: Number(res.skipped_rows ?? 0),
    blockedRows: Number(res.blocked_rows ?? 0),
    errorSummary: res.error_summary ? (res.error_summary as Record<string, number>) : undefined,
    rows: previewRows,
  };
}

export async function submitPlantillaBaselineImport(params: {
  fileName: string;
  groupId: string;
  accountId: string;
  rows: Record<string, string>[];
}): Promise<SubmitPlantillaImportResult> {
  const supabase = createClient();
  const rpcRows = params.rows.map((r) => ({
    VCODE: r.VCODE ?? "",
    STORE_NAME: r.STORE_NAME ?? "",
    MOTHER_ACCOUNT: r.MOTHER_ACCOUNT ?? r.ACCOUNT_NAME ?? "",
    AREA_PROVINCE: r.AREA_PROVINCE ?? "",
    AREA_CITY: r.AREA_CITY ?? "",
    POSITION: r.POSITION ?? "",
    EMPLOYMENT_TYPE: r.EMPLOYMENT_TYPE ?? "stationary",
    REQUIRED_HC: r.REQUIRED_HC ?? "1",
    WITH_PENALTY: r.WITH_PENALTY ?? "no",
    EMPLOYEE_NO: r.EMPLOYEE_NO ?? "",
    LAST_NAME: r.LAST_NAME ?? "",
    FIRST_NAME: r.FIRST_NAME ?? "",
    MIDDLE_NAME: r.MIDDLE_NAME ?? "",
    DATE_HIRED: r.DATE_HIRED ?? "",
    CIVIL_STATUS: r.CIVIL_STATUS ?? "",
    RATE: r.RATE ?? "",
    BIRTHDATE: r.DATE_OF_BIRTH ?? r.BIRTHDATE ?? "",
    CONTACT: r.CONTACT_NO ?? r.CONTACT ?? "",
    ADDRESS: r.ADDRESS ?? "",
    SCHEDULE: r.SCHEDULE_DAYS ?? r.SCHEDULE ?? "",
    SCHEDULE_DAYS: r.SCHEDULE_DAYS ?? r.SCHEDULE ?? "",
    SCHEDULE_TIME: r.SCHEDULE_TIME ?? "",
    DAYOFF: r.DAYOFF ?? "",
    COORDINATOR: r.COORDINATOR ?? "",
    HRCO_EMAIL: r.HRCO_EMAIL ?? "",
  }));

  const { data, error } = await supabase.rpc("submit_plantilla_baseline_import", {
    p_file_name: params.fileName,
    p_group_id: params.groupId,
    p_account_id: params.accountId,
    p_rows: rpcRows,
  });
  if (error) {
    const errorMsg = [error.message, error.details, error.hint].filter(Boolean).join(" - ") || "Failed to submit plantilla import batch.";
    throw new Error(errorMsg);
  }

  const res = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
  const batchId = String(res.batch_id ?? (typeof data === "string" ? data : ""));
  const status = String(res.status ?? "draft_uploaded");
  const totalRows = Number(res.total_rows ?? params.rows.length);
  const validRows = Number(res.valid_rows ?? 0);
  const flaggedRows = Number(res.flagged_rows ?? 0);
  const skippedRows = Number(res.skipped_rows ?? 0);
  const blockedRows = Number(res.blocked_rows ?? 0);
  const errorSummary = res.error_summary && typeof res.error_summary === "object"
    ? (res.error_summary as Record<string, number>)
    : undefined;

  return {
    batchId,
    status,
    totalRows,
    validRows,
    flaggedRows,
    skippedRows,
    blockedRows,
    errorSummary,
  };
}

export async function approvePlantillaImportBatch(batchId: string): Promise<void> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("approve_plantilla_import_batch", {
    p_batch_id: batchId,
  });
  if (error) {
    const errorMsg = [error.message, error.details, error.hint].filter(Boolean).join(" - ") || "Failed to approve plantilla import batch.";
    throw new Error(errorMsg);
  }
  if (data && typeof data === "object") {
    const res = data as Record<string, unknown>;
    if (res.status === "commit_failed") {
      const errorMsg = String(res.error || res.message || "Plantilla batch commit failed.");
      throw new Error(errorMsg);
    }
  }
}

export async function rejectPlantillaImportBatch(params: {
  batchId: string;
  reasonCode: string;
  reasonNote?: string;
}): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("reject_plantilla_import_batch", {
    p_batch_id: params.batchId,
    p_reason_code: params.reasonCode,
    p_reason_note: params.reasonNote,
  });
  if (error) {
    const errorMsg = [error.message, error.details, error.hint].filter(Boolean).join(" - ") || "Failed to reject plantilla batch.";
    throw new Error(errorMsg);
  }
}

export async function requestPlantillaImportRollback(params: {
  batchId: string;
  reasonCode: string;
  reasonNote: string;
}): Promise<Record<string, unknown>> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("request_plantilla_import_rollback", {
    p_batch_id: params.batchId,
    p_reason_code: params.reasonCode,
    p_reason_note: params.reasonNote,
  });
  if (error) throw error;
  return (data as Record<string, unknown>) ?? {};
}

export async function approvePlantillaImportRollback(batchId: string): Promise<Record<string, unknown>> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("approve_plantilla_import_rollback", {
    p_batch_id: batchId,
  });
  if (error) throw error;
  return (data as Record<string, unknown>) ?? {};
}

export async function rejectPlantillaImportRollback(params: {
  batchId: string;
  reason?: string;
}): Promise<Record<string, unknown>> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("reject_plantilla_import_rollback", {
    p_batch_id: params.batchId,
    p_reason: params.reason ?? "Rejected by Administrator",
  });
  if (error) throw error;
  return (data as Record<string, unknown>) ?? {};
}

export async function overridePlantillaImportRollback(params: {
  batchId: string;
  reason: string;
}): Promise<Record<string, unknown>> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("override_plantilla_import_rollback", {
    p_batch_id: params.batchId,
    p_reason: params.reason,
  });
  if (error) throw error;
  return (data as Record<string, unknown>) ?? {};
}

export async function emergencyRollbackPlantillaImport(params: {
  batchId: string;
  reason: string;
}): Promise<Record<string, unknown>> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("emergency_rollback_plantilla_import", {
    p_batch_id: params.batchId,
    p_reason: params.reason,
  });
  if (error) throw error;
  return (data as Record<string, unknown>) ?? {};
}

export async function fetchPlantillaImportRollbackHistory(
  batchId: string
): Promise<PlantillaImportRollbackHistory | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_plantilla_import_rollback_history", {
    p_batch_id: batchId,
  });
  if (error) throw error;
  if (!Array.isArray(data) || data.length === 0) return null;
  const row = data[0] as Record<string, unknown>;
  return {
    batchId: String(row.batch_id ?? batchId),
    rollbackStatus: row.rollback_status ? String(row.rollback_status) : undefined,
    rollbackReason: row.rollback_reason ? String(row.rollback_reason) : undefined,
    rollbackReasonCode: row.rollback_reason_code ? String(row.rollback_reason_code) : undefined,
    rollbackReasonNote: row.rollback_reason_note ? String(row.rollback_reason_note) : undefined,
    rollbackRequestedBy: row.rollback_requested_by ? String(row.rollback_requested_by) : undefined,
    rollbackRequestedByName: row.rollback_requested_by_name ? String(row.rollback_requested_by_name) : undefined,
    rollbackRequestedAt: row.rollback_requested_at ? String(row.rollback_requested_at) : undefined,
    rollbackApprovedBy: row.rollback_approved_by ? String(row.rollback_approved_by) : undefined,
    rollbackApprovedByName: row.rollback_approved_by_name ? String(row.rollback_approved_by_name) : undefined,
    rollbackApprovedAt: row.rollback_approved_at ? String(row.rollback_approved_at) : undefined,
    rollbackCompletedAt: row.rollback_completed_at ? String(row.rollback_completed_at) : undefined,
    rollbackErrorDetail: row.rollback_error_detail ? String(row.rollback_error_detail) : undefined,
    rolledBackBy: row.rolled_back_by ? String(row.rolled_back_by) : undefined,
    rolledBackAt: row.rolled_back_at ? String(row.rolled_back_at) : undefined,
  };
}

export function usePlantillaImportRollbackHistory(batchId: string | null) {
  return useQuery({
    queryKey: ["plantilla-import-rollback-history", batchId],
    queryFn: () => (batchId ? fetchPlantillaImportRollbackHistory(batchId) : Promise.resolve(null)),
    enabled: !!batchId,
  });
}

export function usePlantillaImportBatches(status?: string) {
  return useQuery({
    queryKey: ["plantilla-import-batches", status],
    queryFn: () => fetchPlantillaImportBatches(status),
  });
}

export function usePlantillaImportRows(batchId: string | null) {
  return useQuery({
    queryKey: ["plantilla-import-rows", batchId],
    queryFn: () => (batchId ? fetchPlantillaImportRows(batchId) : Promise.resolve([])),
    enabled: !!batchId,
  });
}

// ============================================================================
// 2. Vacancy Bulk Import Queries & Mutations
// ============================================================================

export interface VacancyImportRollbackHistory {
  batchId?: string;
  status?: string;
  reason?: string;
  reasonCode?: string;
  reasonNote?: string;
  requestedBy?: string;
  requestedAt?: string;
  approvedBy?: string;
  approvedAt?: string;
  completedAt?: string;
  errorDetail?: string;
  vacanciesCount?: number;
  applicantsCount?: number;
}

export interface VacancyImportBatch {
  id: string;
  fileName: string;
  status: string;
  groupName?: string;
  accountName?: string;
  uploadedBy?: string;
  uploadedRole?: string;
  createdAt?: string;
  approvedAt?: string;
  approvedBy?: string;
  rejectionReason?: string;
  rejectionReasonCode?: string;
  rejectionReasonNote?: string;
  totalRows: number;
  validRows: number;
  blockedRows: number;
  flaggedRows: number;
  // Two-step rollback & window fields
  rollbackStatus?: string;
  rollbackReason?: string;
  rollbackReasonCode?: string;
  rollbackReasonNote?: string;
  rollbackRequestedBy?: string;
  rollbackRequestedAt?: string;
  rollbackApprovedBy?: string;
  rollbackApprovedAt?: string;
  rollbackCompletedAt?: string;
  rollbackErrorDetail?: string;
  rollbackVacanciesCount?: number;
  rollbackApplicantsCount?: number;
  rollbackWindowStartedAt?: string;
  rollbackExpiresAt?: string;
  rollbackRemainingSeconds?: number;
  rollbackAllowed: boolean;
  rollbackUiState?: string;
  rollbackBlockReason?: string;
  canEmergencyRollback: boolean;
}

export interface VacancyImportPreviewRow {
  rowNumber: number;
  vcode: string;
  storeName: string;
  position: string;
  tab: string;
  validationStatus: string;
  messages: string[];
  contactNumber?: string;
}

export async function fetchVacancyImportBatches(status?: string): Promise<VacancyImportBatch[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_vacancy_import_batches", {
    ...(status ? { p_status: status } : {}),
  });
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    id: String(row.id ?? row.batch_id ?? ""),
    fileName: String(row.file_name ?? "Vacancy import"),
    status: String(row.status ?? "pending_approval"),
    groupName: row.group_name ? String(row.group_name) : undefined,
    accountName: row.account_name ? String(row.account_name) : undefined,
    accountId: row.selected_account_id ? String(row.selected_account_id) : undefined,
    hrcoUserId: row.hrco_user_id ? String(row.hrco_user_id) : undefined,
    uploadedBy: String(row.uploader_name ?? row.uploaded_by ?? ""),
    uploadedRole: row.uploaded_role ? String(row.uploaded_role) : undefined,
    createdAt: String(row.created_at ?? row.uploaded_at ?? ""),
    approvedAt: row.approved_at ? String(row.approved_at) : undefined,
    approvedBy: row.approved_by_name ? String(row.approved_by_name) : row.approved_by ? String(row.approved_by) : undefined,
    rejectionReason: row.rejection_reason ? String(row.rejection_reason) : undefined,
    rejectionReasonCode: row.rejection_reason_code ? String(row.rejection_reason_code) : undefined,
    rejectionReasonNote: row.rejection_reason_note ? String(row.rejection_reason_note) : undefined,
    totalRows: Number(row.total_rows ?? 0),
    validRows: Number(row.valid_rows ?? 0),
    blockedRows: Number(row.blocked_rows ?? row.invalid_rows ?? 0),
    flaggedRows: Number(row.flagged_rows ?? 0),
    // Rollback mapping
    rollbackStatus: row.rollback_status ? String(row.rollback_status) : undefined,
    rollbackReason: row.rollback_reason ? String(row.rollback_reason) : undefined,
    rollbackReasonCode: row.rollback_reason_code ? String(row.rollback_reason_code) : undefined,
    rollbackReasonNote: row.rollback_reason_note ? String(row.rollback_reason_note) : undefined,
    rollbackRequestedBy: row.rollback_requested_by_name
      ? String(row.rollback_requested_by_name)
      : row.rollback_requested_by
      ? String(row.rollback_requested_by)
      : undefined,
    rollbackRequestedAt: row.rollback_requested_at ? String(row.rollback_requested_at) : undefined,
    rollbackApprovedBy: row.rollback_approved_by_name
      ? String(row.rollback_approved_by_name)
      : row.rollback_approved_by
      ? String(row.rollback_approved_by)
      : undefined,
    rollbackApprovedAt: row.rollback_approved_at ? String(row.rollback_approved_at) : undefined,
    rollbackCompletedAt: row.rollback_completed_at ? String(row.rollback_completed_at) : undefined,
    rollbackErrorDetail: row.rollback_error_detail ? String(row.rollback_error_detail) : undefined,
    rollbackVacanciesCount: typeof row.rollback_vacancies_count === "number" ? row.rollback_vacancies_count : 0,
    rollbackApplicantsCount: typeof row.rollback_applicants_count === "number" ? row.rollback_applicants_count : 0,
    rollbackWindowStartedAt: row.rollback_window_started_at ? String(row.rollback_window_started_at) : undefined,
    rollbackExpiresAt: row.rollback_expires_at ? String(row.rollback_expires_at) : undefined,
    rollbackRemainingSeconds: typeof row.rollback_remaining_seconds === "number" ? row.rollback_remaining_seconds : 0,
    rollbackAllowed: row.rollback_allowed === true,
    rollbackUiState: row.rollback_ui_state ? String(row.rollback_ui_state) : undefined,
    rollbackBlockReason: row.rollback_block_reason ? String(row.rollback_block_reason) : undefined,
    canEmergencyRollback: row.can_emergency_rollback === true,
  }));
}

export async function fetchVacancyImportRows(batchId: string): Promise<VacancyImportPreviewRow[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_vacancy_import_rows", {
    p_batch_id: batchId,
  });
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((row) => {
    const rawMsgs = [
      ...(Array.isArray(row.validation_errors) ? row.validation_errors : []),
      ...(Array.isArray(row.validation_flags) ? row.validation_flags : []),
    ];
    const messages = rawMsgs.map((m) =>
      typeof m === "object" && m !== null && "msg" in m ? String((m as { msg: unknown }).msg) : String(m)
    );

    return {
      rowNumber: Number(row.row_number ?? 0),
      vcode: String(row.vcode ?? ""),
      storeName: String(row.store_name ?? ""),
      position: String(row.position ?? ""),
      tab: String(row.derived_tab ?? "open"),
      validationStatus: String(row.validation_status ?? "valid"),
      messages,
      contactNumber: row.contact_number ? String(row.contact_number) : undefined,
    };
  });
}

export async function submitVacancyImport(params: {
  fileName: string;
  groupId: string;
  accountId: string;
  rows: Record<string, string>[];
}): Promise<string> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("submit_vacancy_import", {
    p_file_name: params.fileName,
    p_group_id: params.groupId,
    p_account_id: params.accountId,
    p_rows: params.rows,
  });
  if (error) throw error;
  if (typeof data === "string") return data;
  if (data && typeof data === "object" && "batch_id" in data) {
    return String((data as { batch_id: unknown }).batch_id);
  }
  return String(data);
}

export async function approveVacancyImportBatch(batchId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("approve_vacancy_import", {
    p_batch_id: batchId,
  });
  if (error) throw error;
}

export async function rejectVacancyImportBatch(params: {
  batchId: string;
  reasonCode: string;
  reasonNote?: string;
}): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("reject_vacancy_import", {
    p_batch_id: params.batchId,
    p_reason_code: params.reasonCode,
    p_reason_note: params.reasonNote,
  });
  if (error) throw error;
}

export async function requestVacancyImportRollback(params: {
  batchId: string;
  reasonCode: string;
  reasonNote: string;
}): Promise<Record<string, unknown>> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("request_vacancy_import_rollback", {
    p_batch_id: params.batchId,
    p_reason_code: params.reasonCode,
    p_reason_note: params.reasonNote,
  });
  if (error) throw error;
  return (data as Record<string, unknown>) ?? {};
}

export async function approveVacancyImportRollback(batchId: string): Promise<Record<string, unknown>> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("approve_vacancy_import_rollback", {
    p_batch_id: batchId,
  });
  if (error) throw error;
  return (data as Record<string, unknown>) ?? {};
}

export async function emergencyRollbackVacancyImport(params: {
  batchId: string;
  reason: string;
}): Promise<Record<string, unknown>> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("emergency_rollback_vacancy_import", {
    p_batch_id: params.batchId,
    p_reason: params.reason,
  });
  if (error) throw error;
  return (data as Record<string, unknown>) ?? {};
}

export async function fetchVacancyImportRollbackHistory(
  batchId: string
): Promise<VacancyImportRollbackHistory | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_vacancy_import_rollback_history", {
    p_batch_id: batchId,
  });
  if (error) throw error;
  if (!Array.isArray(data) || data.length === 0) return null;
  const row = data[0] as Record<string, unknown>;
  return {
    batchId: String(row.batch_id ?? batchId),
    status: row.rollback_status ? String(row.rollback_status) : row.status ? String(row.status) : undefined,
    reason: row.rollback_reason ? String(row.rollback_reason) : row.reason ? String(row.reason) : undefined,
    reasonCode: row.rollback_reason_code ? String(row.rollback_reason_code) : row.reason_code ? String(row.reason_code) : undefined,
    reasonNote: row.rollback_reason_note ? String(row.rollback_reason_note) : row.reason_note ? String(row.reason_note) : undefined,
    requestedBy: row.rollback_requested_by_name
      ? String(row.rollback_requested_by_name)
      : row.rollback_requested_by
      ? String(row.rollback_requested_by)
      : row.requested_by
      ? String(row.requested_by)
      : undefined,
    requestedAt: row.rollback_requested_at
      ? String(row.rollback_requested_at)
      : row.requested_at
      ? String(row.requested_at)
      : undefined,
    approvedBy: row.rollback_approved_by_name
      ? String(row.rollback_approved_by_name)
      : row.rollback_approved_by
      ? String(row.rollback_approved_by)
      : row.approved_by
      ? String(row.approved_by)
      : undefined,
    approvedAt: row.rollback_approved_at
      ? String(row.rollback_approved_at)
      : row.approved_at
      ? String(row.approved_at)
      : undefined,
    completedAt: row.rollback_completed_at
      ? String(row.rollback_completed_at)
      : row.completed_at
      ? String(row.completed_at)
      : undefined,
    errorDetail: row.rollback_error_detail
      ? String(row.rollback_error_detail)
      : row.error_detail
      ? String(row.error_detail)
      : undefined,
    vacanciesCount: typeof row.rollback_vacancies_count === "number"
      ? row.rollback_vacancies_count
      : typeof row.vacancies_count === "number"
      ? row.vacancies_count
      : undefined,
    applicantsCount: typeof row.rollback_applicants_count === "number"
      ? row.rollback_applicants_count
      : typeof row.applicants_count === "number"
      ? row.applicants_count
      : undefined,
  };
}

export function useVacancyImportRollbackHistory(batchId: string | null) {
  return useQuery({
    queryKey: ["vacancy-import-rollback-history", batchId],
    queryFn: () => (batchId ? fetchVacancyImportRollbackHistory(batchId) : Promise.resolve(null)),
    enabled: !!batchId,
  });
}

export function useVacancyImportBatches(status?: string) {
  return useQuery({
    queryKey: ["vacancy-import-batches", status],
    queryFn: () => fetchVacancyImportBatches(status),
  });
}

export function useVacancyImportRows(batchId: string | null) {
  return useQuery({
    queryKey: ["vacancy-import-rows", batchId],
    queryFn: () => (batchId ? fetchVacancyImportRows(batchId) : Promise.resolve([])),
    enabled: !!batchId,
  });
}

// ============================================================================
// 3. MIKA Import Queries & Mutations
// ============================================================================

export interface MikaImportLogItem {
  id: string;
  uploadedBy: string;
  uploadedByRole: string;
  approvedBy?: string;
  fileName: string;
  totalRows: number;
  cleanRows: number;
  status: string;
  remarks?: string;
  submittedAt: string;
  reviewedAt?: string;
  matchedCount: number;
  ghostCount: number;
  blockedCount: number;
  skippedCount: number;
}

export interface MikaEmployeeRow {
  employeeNo: string;
  account: string;
  storeName?: string;
  lastName: string;
  firstName: string;
  middleName?: string;
  position?: string;
  contactNumber?: string;
  address?: string;
  sssNo?: string;
  philhealthNo?: string;
  pagibigNo?: string;
  tinNo?: string;
  atmNo?: string;
  birthdate?: string;
  civilStatus?: string;
  dateHired?: string;
  flagType: "clean" | "matched" | "ghost" | "blocked" | "skipped";
  flagReason?: string;
}

export async function fetchMikaImportLogs(mode: "pending" | "history"): Promise<MikaImportLogItem[]> {
  const supabase = createClient();
  let query = supabase.from("mika_import_logs").select("*").order("submitted_at", { ascending: false });

  if (mode === "pending") {
    query = query.eq("status", "Pending");
  } else {
    query = query.neq("status", "Pending").limit(30);
  }

  const { data, error } = await query;
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    id: String(row.id ?? ""),
    uploadedBy: String(row.uploaded_by ?? ""),
    uploadedByRole: String(row.uploaded_by_role ?? ""),
    approvedBy: row.approved_by ? String(row.approved_by) : undefined,
    fileName: String(row.file_name ?? "MIKA import"),
    totalRows: Number(row.total_rows ?? 0),
    cleanRows: Number(row.clean_rows ?? 0),
    status: String(row.status ?? "Pending"),
    remarks: row.remarks ? String(row.remarks) : undefined,
    submittedAt: String(row.submitted_at ?? ""),
    reviewedAt: row.reviewed_at ? String(row.reviewed_at) : undefined,
    matchedCount: Number(row.matched_count ?? 0),
    ghostCount: Number(row.ghost_count ?? 0),
    blockedCount: Number(row.blocked_count ?? 0),
    skippedCount: Number(row.skipped_count ?? 0),
  }));
}

export async function fetchMikaImportRows(importLogId: string): Promise<MikaEmployeeRow[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("mika_import_rows")
    .select("*")
    .eq("import_log_id", importLogId);

  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    employeeNo: String(row.employee_no ?? ""),
    account: String(row.account ?? ""),
    storeName: row.store_name ? String(row.store_name) : undefined,
    lastName: String(row.last_name ?? ""),
    firstName: String(row.first_name ?? ""),
    middleName: row.middle_name ? String(row.middle_name) : undefined,
    position: row.position ? String(row.position) : undefined,
    contactNumber: row.contact_number ? String(row.contact_number) : undefined,
    address: row.address ? String(row.address) : undefined,
    sssNo: row.sss_no ? String(row.sss_no) : undefined,
    philhealthNo: row.philhealth_no ? String(row.philhealth_no) : undefined,
    pagibigNo: row.pagibig_no ? String(row.pagibig_no) : undefined,
    tinNo: row.tin_no ? String(row.tin_no) : undefined,
    atmNo: row.atm_no ? String(row.atm_no) : undefined,
    birthdate: row.birthdate ? String(row.birthdate) : undefined,
    civilStatus: row.civil_status ? String(row.civil_status) : undefined,
    dateHired: row.date_hired ? String(row.date_hired) : undefined,
    flagType: (row.flag_type as MikaEmployeeRow["flagType"]) ?? "clean",
    flagReason: row.flag_reason ? String(row.flag_reason) : undefined,
  }));
}

export async function submitMikaImport(params: {
  uploadedBy: string;
  uploadedByRole: string;
  fileName: string;
  rows: MikaEmployeeRow[];
}): Promise<string> {
  const supabase = createClient();
  const matched = params.rows.filter((r) => r.flagType === "matched").length;
  const ghost = params.rows.filter((r) => r.flagType === "ghost").length;
  const blocked = params.rows.filter((r) => r.flagType === "blocked").length;
  const skipped = params.rows.filter((r) => r.flagType === "skipped").length;

  const { data: log, error: logError } = await supabase
    .from("mika_import_logs")
    .insert({
      uploaded_by: params.uploadedBy,
      uploaded_by_role: params.uploadedByRole,
      file_name: params.fileName,
      total_rows: params.rows.length,
      clean_rows: matched,
      new_rows: blocked,
      type_a_flagged: ghost,
      type_b_flagged: skipped,
      status: "Pending",
      matched_count: matched,
      ghost_count: ghost,
      blocked_count: blocked,
      skipped_count: skipped,
    })
    .select("id")
    .single();

  if (logError) throw logError;
  const importLogId = String(log.id);

  // Insert rows in chunks of 100
  const chunkSize = 100;
  for (let i = 0; i < params.rows.length; i += chunkSize) {
    const chunk = params.rows.slice(i, i + chunkSize);
    const { error: rowsError } = await supabase.from("mika_import_rows").insert(
      chunk.map((r) => ({
        import_log_id: importLogId,
        employee_no: r.employeeNo,
        account: r.account,
        store_name: null,
        last_name: r.lastName,
        first_name: r.firstName,
        middle_name: r.middleName ?? null,
        position: r.position ?? null,
        contact_number: r.contactNumber ?? null,
        address: r.address ?? null,
        sss_no: r.sssNo ?? null,
        philhealth_no: r.philhealthNo ?? null,
        pagibig_no: r.pagibigNo ?? null,
        tin_no: r.tinNo ?? null,
        atm_no: r.atmNo ?? null,
        birthdate: r.birthdate ?? null,
        civil_status: r.civilStatus ?? null,
        date_hired: r.dateHired ?? null,
        flag_type: r.flagType,
        flag_reason: r.flagReason ?? null,
      }))
    );
    if (rowsError) {
      await supabase.from("mika_import_logs").delete().eq("id", importLogId);
      throw rowsError;
    }
  }

  return importLogId;
}

export async function approveMikaImport(params: {
  importLogId: string;
  approvedBy: string;
  remarks?: string;
  cleanRowsCount: number;
}): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase
    .from("mika_import_logs")
    .update({
      status: "Approved",
      approved_by: params.approvedBy,
      reviewed_at: new Date().toISOString(),
      remarks: params.remarks ?? null,
      updated_rows: params.cleanRowsCount,
    })
    .eq("id", params.importLogId);

  if (error) throw error;

  // Propagate approved matched employee rows into public.plantilla and employees
  try {
    const { data: rows } = await supabase
      .from("mika_import_rows")
      .select("employee_no, sss_no, philhealth_no, pagibig_no, tin_no, atm_no, civil_status, birthdate, address, contact_number")
      .eq("import_log_id", params.importLogId)
      .eq("flag_type", "matched");

    if (rows && rows.length > 0) {
      for (const r of rows) {
        if (!r.employee_no) continue;
        const updates: Record<string, unknown> = {
          last_mika_synced_at: new Date().toISOString(),
        };
        if (r.sss_no) updates.sss_no = r.sss_no;
        if (r.philhealth_no) updates.philhealth_no = r.philhealth_no;
        if (r.pagibig_no) updates.pagibig_no = r.pagibig_no;
        if (r.atm_no) updates.atm_no = r.atm_no;
        if (r.civil_status) updates.civil_status = r.civil_status;
        if (r.birthdate) updates.date_of_birth = r.birthdate;
        if (r.address) updates.address = r.address;
        if (r.contact_number) updates.contact_no = r.contact_number;

        await supabase
          .from("plantilla")
          .update(updates)
          .eq("employee_no", r.employee_no);

        if (r.tin_no) {
          try {
            await supabase
              .from("employees")
              .update({
                tin_no: r.tin_no,
                ...(r.sss_no ? { sss_no: r.sss_no } : {}),
                ...(r.philhealth_no ? { philhealth_no: r.philhealth_no } : {}),
                ...(r.pagibig_no ? { pagibig_no: r.pagibig_no } : {}),
                ...(r.atm_no ? { atm_no: r.atm_no } : {}),
              })
              .eq("employee_no", r.employee_no);
          } catch {
            // Graceful fallback if employee record does not exist
          }
        }
      }
    }
  } catch (syncErr) {
    console.warn("[DataControl] Error syncing approved MIKA rows to plantilla:", syncErr);
  }

  // Register or revalidate ghost employee detection cases & dispatch targeted notifications
  try {
    const { data: ghostRows } = await supabase
      .from("mika_import_rows")
      .select("employee_no, first_name, last_name, middle_name, account, store_name, position, flag_reason")
      .eq("import_log_id", params.importLogId)
      .eq("flag_type", "ghost");

    if (ghostRows && ghostRows.length > 0) {
      const accountCounts: Record<string, number> = {};

      for (const gr of ghostRows) {
        if (!gr.employee_no) continue;
        const acct = gr.account?.trim() || "Unassigned";
        accountCounts[acct] = (accountCounts[acct] || 0) + 1;

        const fullName = [gr.last_name, gr.first_name, gr.middle_name].filter(Boolean).join(", ") || gr.employee_no;
        const isTypeB = gr.flag_reason?.toLowerCase().includes("inactive");
        const ghostType: "Type A" | "Type B" = isTypeB ? "Type B" : "Type A";

        const { data: existing } = await supabase
          .from("possible_ghost_employees")
          .select("id")
          .eq("employee_no", gr.employee_no)
          .not("status", "in", '("Cleared","Resolved","Auto Resolved","Confirmed Ghost","For Termination")')
          .maybeSingle();

        if (!existing) {
          await supabase.from("possible_ghost_employees").insert({
            import_log_id: params.importLogId,
            employee_no: gr.employee_no,
            full_name: fullName,
            ghost_type: ghostType,
            status: "Under Investigation",
            account: gr.account,
            store_name: gr.store_name,
            position: gr.position,
          });
        } else {
          await supabase
            .from("possible_ghost_employees")
            .update({
              last_revalidated_at: new Date().toISOString(),
              import_log_id: params.importLogId,
            })
            .eq("id", existing.id);
        }
      }

      // 1. Dispatch global notifications to OM, HA, SA
      const totalGhosts = ghostRows.length;
      const globalRoles = ["Super Admin", "Head Admin", "Operations Manager"];
      const globalNotifs = globalRoles.map((role) => ({
        recipient_role: role,
        title: "⚠️ Possible Ghost Employees Flagged",
        message: `${totalGhosts} possible ghost employees flagged across all accounts. View here`,
        reference_type: "ghost_detection",
        reference_id: params.importLogId,
        deep_link_route: "/more?tab=data_control&subtab=operations&tool=ghost_detection",
      }));

      // 2. Dispatch account-scoped notifications for Field Ops & Encoders
      const accountNotifs: Array<{
        recipient_role: string;
        title: string;
        message: string;
        reference_type: string;
        reference_id: string;
        deep_link_route: string;
      }> = [];

      const fieldRoles = ["HR Coordinator", "Team Leader", "Area Team Leader", "Encoder"];
      for (const [account, count] of Object.entries(accountCounts)) {
        for (const role of fieldRoles) {
          accountNotifs.push({
            recipient_role: role,
            title: `⚠️ Ghost Alert: ${account}`,
            message: `${count} possible ghost employees flagged in ${account}. Verify here`,
            reference_type: "ghost_detection",
            reference_id: params.importLogId,
            deep_link_route: `/more?tab=data_control&subtab=operations&tool=ghost_detection&account=${encodeURIComponent(account)}`,
          });
        }
      }

      const allNotifs = [...globalNotifs, ...accountNotifs];
      if (allNotifs.length > 0) {
        await supabase.from("notifications").insert(allNotifs);
      }
    }
  } catch (ghostErr) {
    console.warn("[DataControl] Error registering ghost employee cases or notifications:", ghostErr);
  }
}

export async function rollbackMikaImport(params: {
  importLogId: string;
  rolledBackBy: string;
  reason: string;
}): Promise<void> {
  const supabase = createClient();
  const { error: logErr } = await supabase
    .from("mika_import_logs")
    .update({
      status: "Rolled Back",
      remarks: `Rolled back by ${params.rolledBackBy}: ${params.reason}`,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", params.importLogId);

  if (logErr) throw logErr;

  // Clear open ghost records generated from this import batch
  await supabase
    .from("possible_ghost_employees")
    .update({
      status: "Cleared",
      auto_resolved: true,
      resolved_at: new Date().toISOString(),
      resolved_by: params.rolledBackBy,
      resolution_remarks: `Import Batch Rolled Back: ${params.reason}`,
    })
    .eq("import_log_id", params.importLogId)
    .not("status", "in", '("Cleared","Confirmed Ghost","For Termination")');

  try {
    await supabase.from("audit_logs").insert({
      action: "MIKA_IMPORT_ROLLBACK",
      table_name: "mika_import_logs",
      record_id: params.importLogId,
      performed_by: params.rolledBackBy,
      details: {
        reason: params.reason,
        import_log_id: params.importLogId,
      },
    });
  } catch (auditErr) {
    console.warn("[DataControl] Error logging MIKA rollback audit:", auditErr);
  }
}

export async function rejectMikaImport(params: {
  importLogId: string;
  rejectedBy: string;
  remarks?: string;
}): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase
    .from("mika_import_logs")
    .update({
      status: "Rejected",
      approved_by: params.rejectedBy,
      reviewed_at: new Date().toISOString(),
      remarks: params.remarks ?? null,
    })
    .eq("id", params.importLogId);

  if (error) throw error;
}

export function useMikaImportLogs(mode: "pending" | "history") {
  return useQuery({
    queryKey: ["mika-import-logs", mode],
    queryFn: () => fetchMikaImportLogs(mode),
  });
}

export function useMikaImportRowsQuery(logId: string | null) {
  return useQuery({
    queryKey: ["mika-import-rows", logId],
    queryFn: () => (logId ? fetchMikaImportRows(logId) : Promise.resolve([])),
    enabled: !!logId,
  });
}

// ============================================================================
// 3.5 Ghost Employees Detection Center Queries & Mutations
// ============================================================================

export interface GhostEmployeeCase {
  id: string;
  importLogId: string | null;
  employeeNo: string;
  fullName: string;
  ghostType: "Type A" | "Type B";
  status: "Under Investigation" | "For Encoding" | "Cleared" | "Confirmed Ghost" | "For Termination" | "Resolved";
  account: string | null;
  storeName: string | null;
  position: string | null;
  assignedEncoder: string | null;
  encodingDeadline: string | null;
  notified48hr: boolean;
  notified72hr: boolean;
  resolvedBy: string | null;
  resolvedByRole: string | null;
  resolvedAt: string | null;
  resolutionType: string | null;
  resolutionNotes: string | null;
  resolutionRemarks: string | null;
  autoResolved: boolean;
  createdAt: string;
  updatedAt: string;
  lastRevalidatedAt: string | null;
}

export async function fetchGhostEmployees(filters?: {
  account?: string;
  statusCategory?: "open" | "resolved" | "all";
  ghostType?: "Type A" | "Type B";
}): Promise<GhostEmployeeCase[]> {
  const supabase = createClient();
  let query = supabase
    .from("possible_ghost_employees")
    .select("*")
    .order("created_at", { ascending: false });

  if (filters?.account && filters.account !== "ALL") {
    query = query.eq("account", filters.account);
  }

  if (filters?.ghostType) {
    query = query.eq("ghost_type", filters.ghostType);
  }

  if (filters?.statusCategory === "open") {
    query = query.not(
      "status",
      "in",
      '("Cleared","Resolved","Auto Resolved","Confirmed Ghost","For Termination")'
    );
  } else if (filters?.statusCategory === "resolved") {
    query = query.in(
      "status",
      ["Cleared", "Resolved", "Auto Resolved", "Confirmed Ghost", "For Termination"]
    );
  }

  const { data, error } = await query;
  if (error) {
    console.error("[PostgREST Schema Error] fetchGhostEmployees failed:", error);
    return [];
  }

  return (data ?? []).map((row) => ({
    id: String(row.id),
    importLogId: row.import_log_id ? String(row.import_log_id) : null,
    employeeNo: String(row.employee_no || ""),
    fullName: String(row.full_name || ""),
    ghostType: (row.ghost_type as "Type A" | "Type B") || "Type A",
    status: (row.status as GhostEmployeeCase["status"]) || "Under Investigation",
    account: row.account ? String(row.account) : null,
    storeName: row.store_name ? String(row.store_name) : null,
    position: row.position ? String(row.position) : null,
    assignedEncoder: row.assigned_encoder ? String(row.assigned_encoder) : null,
    encodingDeadline: row.encoding_deadline ? String(row.encoding_deadline) : null,
    notified48hr: Boolean(row.notified_48hr),
    notified72hr: Boolean(row.notified_72hr),
    resolvedBy: row.resolved_by ? String(row.resolved_by) : null,
    resolvedByRole: row.resolved_by_role ? String(row.resolved_by_role) : null,
    resolvedAt: row.resolved_at ? String(row.resolved_at) : null,
    resolutionType: row.resolution_type ? String(row.resolution_type) : null,
    resolutionNotes: row.resolution_notes ? String(row.resolution_notes) : null,
    resolutionRemarks: row.resolution_remarks ? String(row.resolution_remarks) : null,
    autoResolved: Boolean(row.auto_resolved),
    createdAt: String(row.created_at || new Date().toISOString()),
    updatedAt: String(row.updated_at || new Date().toISOString()),
    lastRevalidatedAt: row.last_revalidated_at ? String(row.last_revalidated_at) : null,
  }));
}

export function useGhostEmployeesQuery(filters?: {
  account?: string;
  statusCategory?: "open" | "resolved" | "all";
  ghostType?: "Type A" | "Type B";
}) {
  return useQuery({
    queryKey: ["ghost-employees", filters],
    queryFn: () => fetchGhostEmployees(filters),
  });
}

export async function submitGhostVerificationNote(params: {
  caseId: string;
  note: string;
  authorName: string;
  authorRole: string;
}): Promise<void> {
  const supabase = createClient();
  const timestamp = new Date().toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
  const formattedEntry = `[${timestamp}] ${params.authorName} (${params.authorRole}): ${params.note}`;

  const { data: current } = await supabase
    .from("possible_ghost_employees")
    .select("resolution_notes")
    .eq("id", params.caseId)
    .single();

  const combinedNotes = current?.resolution_notes
    ? `${current.resolution_notes}\n\n${formattedEntry}`
    : formattedEntry;

  const { error } = await supabase
    .from("possible_ghost_employees")
    .update({
      resolution_notes: combinedNotes,
      updated_at: new Date().toISOString(),
    })
    .eq("id", params.caseId);

  if (error) {
    console.error("[PostgREST Schema Error] submitGhostVerificationNote failed:", error);
    throw error;
  }
}

export async function updateGhostCaseStatus(params: {
  caseId: string;
  status: "Cleared" | "For Encoding" | "Confirmed Ghost" | "For Termination" | "Under Investigation";
  actorName: string;
  actorRole: string;
  remarks: string;
  assignedEncoder?: string;
}): Promise<void> {
  const supabase = createClient();
  const updates: Record<string, unknown> = {
    status: params.status,
    resolved_by: params.actorName,
    resolved_by_role: params.actorRole,
    resolution_remarks: params.remarks,
    updated_at: new Date().toISOString(),
  };

  if (params.status === "Cleared" || params.status === "Confirmed Ghost" || params.status === "For Termination") {
    updates.resolved_at = new Date().toISOString();
    updates.auto_resolved = false;
  }

  if (params.status === "For Encoding") {
    if (params.assignedEncoder) {
      updates.assigned_encoder = params.assignedEncoder;
    }
    const deadline = new Date();
    deadline.setHours(deadline.getHours() + 72);
    updates.encoding_deadline = deadline.toISOString();
  }

  const { error } = await supabase
    .from("possible_ghost_employees")
    .update(updates)
    .eq("id", params.caseId);

  if (error) {
    console.error("[PostgREST Schema Error] updateGhostCaseStatus failed:", error);
    throw error;
  }
}

// ============================================================================
// 4. Payroll Check & Reconciliation Queries
// ============================================================================

import type {
  PlantillaCheckRow,
  PayrollFinding,
  PayrollCheckResult,
} from "@/lib/utils/payroll_reconciliation";
export type {
  PlantillaCheckRow,
  PayrollFinding,
  PayrollCheckResult,
};
export { reconcilePayroll } from "@/lib/utils/payroll_reconciliation";

export async function fetchGlobalPlantillaForPayrollCheck(): Promise<PlantillaCheckRow[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_global_plantilla_for_payroll_check");
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((m) => ({
    plantillaId: String(m.plantilla_id ?? ""),
    employeeNo: String(m.employee_no ?? "").trim(),
    lastName: String(m.last_name ?? ""),
    firstName: String(m.first_name ?? ""),
    middleName: String(m.middle_name ?? ""),
    accountName: String(m.account_name ?? ""),
    groupName: String(m.group_name ?? ""),
    isActive: m.is_active === true,
  }));
}

// ============================================================================
// 5. Payroll Review Center Queries & Mutations
// ============================================================================

export interface PayrollReviewSessionItem {
  id: string;
  payrollFileName: string;
  createdByName: string;
  status: string;
  totalItems: number;
  notes?: string;
  closedByName?: string;
  closedAt?: string;
  createdAt: string;
  pendingCount: number;
  commentedCount: number;
  needsFixingCount: number;
  confirmedCount: number;
  notMyScopeCount: number;
  closedCount: number;
}

export interface PayrollReviewDetailItem {
  id: string;
  sessionId: string;
  findingType: string;
  employeeNumber: string;
  payrollFullName?: string;
  plantillaFullName?: string;
  payrollAccount?: string;
  payrollGroup?: string;
  plantillaAccount?: string;
  plantillaGroup?: string;
  status: string;
  opsResponse?: string;
  opsComment?: string;
  commentedByName?: string;
  commentedAt?: string;
  closedByName?: string;
  closedAt?: string;
  createdAt: string;
}

export async function fetchPayrollReviewSessions(status?: string): Promise<PayrollReviewSessionItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("list_payroll_review_sessions", {
    ...(status ? { p_status: status } : {}),
  });
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((m) => ({
    id: String(m.id ?? ""),
    payrollFileName: String(m.payroll_file_name ?? ""),
    createdByName: String(m.created_by_name ?? ""),
    status: String(m.status ?? "Open"),
    totalItems: Number(m.total_items ?? 0),
    notes: m.notes ? String(m.notes) : undefined,
    closedByName: m.closed_by_name ? String(m.closed_by_name) : undefined,
    closedAt: m.closed_at ? String(m.closed_at) : undefined,
    createdAt: String(m.created_at ?? ""),
    pendingCount: Number(m.pending_count ?? 0),
    commentedCount: Number(m.commented_count ?? 0),
    needsFixingCount: Number(m.needs_fixing_count ?? 0),
    confirmedCount: Number(m.confirmed_count ?? 0),
    notMyScopeCount: Number(m.not_my_scope_count ?? 0),
    closedCount: Number(m.closed_count ?? 0),
  }));
}

export async function fetchPayrollReviewItems(sessionId: string, status?: string): Promise<PayrollReviewDetailItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("list_payroll_review_items", {
    p_session_id: sessionId,
    ...(status ? { p_status: status } : {}),
  });
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((m) => ({
    id: String(m.id ?? ""),
    sessionId: String(m.session_id ?? sessionId),
    findingType: String(m.finding_type ?? ""),
    employeeNumber: String(m.employee_number ?? ""),
    payrollFullName: m.payroll_full_name ? String(m.payroll_full_name) : undefined,
    plantillaFullName: m.plantilla_full_name ? String(m.plantilla_full_name) : undefined,
    payrollAccount: m.payroll_account ? String(m.payroll_account) : undefined,
    payrollGroup: m.payroll_group ? String(m.payroll_group) : undefined,
    plantillaAccount: m.plantilla_account ? String(m.plantilla_account) : undefined,
    plantillaGroup: m.plantilla_group ? String(m.plantilla_group) : undefined,
    status: String(m.status ?? "Pending Ops Review"),
    opsResponse: m.ops_response ? String(m.ops_response) : undefined,
    opsComment: m.ops_comment ? String(m.ops_comment) : undefined,
    commentedByName: m.commented_by_name ? String(m.commented_by_name) : undefined,
    commentedAt: m.commented_at ? String(m.commented_at) : undefined,
    closedByName: m.closed_by_name ? String(m.closed_by_name) : undefined,
    closedAt: m.closed_at ? String(m.closed_at) : undefined,
    createdAt: String(m.created_at ?? ""),
  }));
}

export async function createPayrollReviewSession(params: {
  payrollFileName: string;
  notes?: string;
  items: {
    findingType: string;
    employeeNumber: string;
    payrollFullName?: string;
    plantillaFullName?: string;
    payrollAccount?: string;
    payrollGroup?: string;
    plantillaAccount?: string;
    plantillaGroup?: string;
    assignedAccountId: string;
    assignedGroupId?: string;
  }[];
}): Promise<string> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("create_payroll_review_session", {
    p_input: {
      session: {
        payroll_file_name: params.payrollFileName,
        notes: params.notes ?? null,
      },
      items: params.items.map((i) => ({
        finding_type: i.findingType,
        employee_number: i.employeeNumber,
        payroll_full_name: i.payrollFullName ?? null,
        plantilla_full_name: i.plantillaFullName ?? null,
        payroll_account: i.payrollAccount ?? null,
        payroll_group: i.payrollGroup ?? null,
        plantilla_account: i.plantillaAccount ?? null,
        plantilla_group: i.plantillaGroup ?? null,
        assigned_account_id: i.assignedAccountId,
        assigned_group_id: i.assignedGroupId ?? null,
      })),
    },
  });
  if (error) throw error;
  if (data && typeof data === "object" && "session_id" in data) {
    return String((data as { session_id: unknown }).session_id);
  }
  return String(data);
}

export async function closePayrollReviewItem(itemId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("close_payroll_review_item", {
    p_item_id: itemId,
  });
  if (error) throw error;
}

export async function closePayrollReviewSession(sessionId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("close_payroll_review_session", {
    p_session_id: sessionId,
  });
  if (error) throw error;
}

export async function submitOpsPayrollReviewComment(params: {
  itemId: string;
  opsResponse: string;
  comment?: string;
}): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("submit_ops_payroll_review_comment", {
    p_item_id: params.itemId,
    p_ops_response: params.opsResponse,
    p_comment: params.comment ?? null,
  });
  if (error) throw error;
}

export function usePayrollReviewSessions(status?: string) {
  return useQuery({
    queryKey: ["payroll-review-sessions", status],
    queryFn: () => fetchPayrollReviewSessions(status),
  });
}

export function usePayrollReviewItemsQuery(sessionId: string | null, status?: string) {
  return useQuery({
    queryKey: ["payroll-review-items", sessionId, status],
    queryFn: () => (sessionId ? fetchPayrollReviewItems(sessionId, status) : Promise.resolve([])),
    enabled: !!sessionId,
  });
}

export async function fetchAllScopedAccounts(): Promise<{ id: string; name: string; groupId?: string }[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_my_scoped_accounts");
  if (error) {
    // Fallback directly to accounts table
    const { data: direct, error: directErr } = await supabase
      .from("accounts")
      .select("id, account_name, group_id")
      .order("account_name");
    if (directErr) throw directErr;
    return (direct ?? []).map((a) => ({
      id: String(a.id),
      name: String(a.account_name ?? "Account"),
      groupId: a.group_id ? String(a.group_id) : undefined,
    }));
  }
  if (!Array.isArray(data)) return [];
  return (data as Record<string, unknown>[]).map((row) => ({
    id: String(row.account_id ?? row.id ?? ""),
    name: String(row.account_name ?? "Account"),
    groupId: row.group_id ? String(row.group_id) : undefined,
  }));
}
