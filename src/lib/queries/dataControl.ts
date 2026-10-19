import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

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

export interface PlantillaImportBatch {
  id: string;
  fileName: string;
  status: string;
  groupName?: string;
  accountName?: string;
  uploadedBy?: string;
  uploadedRole?: string;
  uploadedAt?: string;
  approvedAt?: string;
  rejectionReason?: string;
  totalRows: number;
  validRows: number;
  blockedRows: number;
  flaggedRows: number;
}

export interface PlantillaImportPreviewRow {
  rowNumber: number;
  vcode: string;
  storeName: string;
  employeeNo: string;
  employeeName: string;
  position: string;
  employmentType: string;
  validationStatus: string;
  validationMessages: string[];
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
    uploadedBy: String(row.uploader_name ?? row.uploaded_by ?? ""),
    uploadedRole: row.uploaded_role ? String(row.uploaded_role) : undefined,
    uploadedAt: String(row.uploaded_at ?? row.created_at ?? ""),
    approvedAt: row.approved_at ? String(row.approved_at) : undefined,
    rejectionReason: row.rejection_reason ? String(row.rejection_reason) : undefined,
    totalRows: Number(row.total_rows ?? 0),
    validRows: Number(row.valid_rows ?? 0),
    blockedRows: Number(row.blocked_rows ?? row.invalid_rows ?? 0),
    flaggedRows: Number(row.flagged_rows ?? 0),
  }));
}

export async function fetchPlantillaImportRows(batchId: string): Promise<PlantillaImportPreviewRow[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_plantilla_import_rows", {
    p_batch_id: batchId,
    p_offset: 0,
    p_limit: 500,
  });
  if (error) throw error;
  if (!Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((row) => {
    const rawMsgs = row.validation_messages ?? row.validation_errors ?? row.messages ?? [];
    const messages = Array.isArray(rawMsgs)
      ? rawMsgs.map((m) => (typeof m === "object" && m !== null && "msg" in m ? String((m as { msg: unknown }).msg) : String(m)))
      : [];

    return {
      rowNumber: Number(row.row_number ?? 0),
      vcode: String(row.vcode ?? ""),
      storeName: String(row.store_name ?? ""),
      employeeNo: String(row.employee_no ?? ""),
      employeeName: String(row.employee_name ?? row.full_name ?? ""),
      position: String(row.position ?? ""),
      employmentType: String(row.employment_type ?? ""),
      validationStatus: String(row.validation_status ?? row.status ?? "valid"),
      validationMessages: messages,
    };
  });
}

export async function submitPlantillaBaselineImport(params: {
  fileName: string;
  groupId: string;
  accountId: string;
  rows: Record<string, string>[];
}): Promise<string> {
  const supabase = createClient();
  const rpcRows = params.rows.map((r) => ({
    VCODE: r.VCODE ?? "",
    STORE_NAME: r.STORE_NAME ?? "",
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
    SCHEDULE: r.SCHEDULE ?? "",
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
  if (error) throw error;
  if (typeof data === "string") return data;
  if (data && typeof data === "object" && "batch_id" in data) {
    return String((data as { batch_id: unknown }).batch_id);
  }
  return String(data);
}

export async function approvePlantillaImportBatch(batchId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("approve_plantilla_import_batch", {
    p_batch_id: batchId,
  });
  if (error) throw error;
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
  if (error) throw error;
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

export interface VacancyImportBatch {
  id: string;
  fileName: string;
  status: string;
  groupName?: string;
  accountName?: string;
  uploadedBy?: string;
  uploadedRole?: string;
  createdAt?: string;
  totalRows: number;
  validRows: number;
  blockedRows: number;
  flaggedRows: number;
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
    uploadedBy: String(row.uploader_name ?? row.uploaded_by ?? ""),
    uploadedRole: row.uploaded_role ? String(row.uploaded_role) : undefined,
    createdAt: String(row.created_at ?? row.uploaded_at ?? ""),
    totalRows: Number(row.total_rows ?? 0),
    validRows: Number(row.valid_rows ?? 0),
    blockedRows: Number(row.blocked_rows ?? row.invalid_rows ?? 0),
    flaggedRows: Number(row.flagged_rows ?? 0),
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
        store_name: r.storeName ?? null,
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
        dateHired: r.dateHired ?? null,
        flag_type: r.flagType,
        flag_reason: r.flagReason ?? null,
      }))
    );
    if (rowsError) throw rowsError;
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
// 4. Payroll Check & Reconciliation Queries
// ============================================================================

export interface PlantillaCheckRow {
  plantillaId: string;
  employeeNo: string;
  lastName: string;
  firstName: string;
  middleName: string;
  accountName: string;
  groupName: string;
  isActive: boolean;
}

export interface PayrollFinding {
  employeeNumber: string;
  payrollFullName?: string;
  plantillaFullName?: string;
  payrollAccountGroup?: string;
  plantillaAccountGroup?: string;
  findingType: "missingInPayroll" | "missingInPlantilla" | "paidInactive" | "mismatch" | "duplicate" | "clean";
}

export interface PayrollCheckResult {
  payrollRows: number;
  activePlantillaCount: number;
  missingInPayroll: PayrollFinding[];
  missingInPlantilla: PayrollFinding[];
  paidInactive: PayrollFinding[];
  mismatch: PayrollFinding[];
  duplicates: PayrollFinding[];
  clean: PayrollFinding[];
}

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

export function reconcilePayroll(
  payrollRows: { rowNumber: number; employeeNumber: string; fullName: string; accountGroup: string }[],
  plantillaRows: PlantillaCheckRow[]
): PayrollCheckResult {
  const plantillaByEmpNo = new Map<string, PlantillaCheckRow[]>();
  for (const p of plantillaRows) {
    const key = p.employeeNo.trim().toUpperCase();
    const existing = plantillaByEmpNo.get(key) ?? [];
    existing.push(p);
    plantillaByEmpNo.set(key, existing);
  }

  const activePlantillaCount = plantillaRows.filter((p) => p.isActive).length;

  const payrollCountByEmpNo = new Map<string, number>();
  for (const r of payrollRows) {
    const key = r.employeeNumber.trim().toUpperCase();
    payrollCountByEmpNo.set(key, (payrollCountByEmpNo.get(key) ?? 0) + 1);
  }

  const duplicateEmpNos = new Set(
    Array.from(payrollCountByEmpNo.entries())
      .filter(([, count]) => count > 1)
      .map(([empNo]) => empNo)
  );

  const payrollEmpNosProcessed = new Set<string>();

  const missingInPayroll: PayrollFinding[] = [];
  const missingInPlantilla: PayrollFinding[] = [];
  const paidInactive: PayrollFinding[] = [];
  const mismatch: PayrollFinding[] = [];
  const duplicates: PayrollFinding[] = [];
  const clean: PayrollFinding[] = [];

  for (const row of payrollRows) {
    const empNo = row.employeeNumber.trim().toUpperCase();

    if (duplicateEmpNos.has(empNo)) {
      duplicates.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        payrollAccountGroup: row.accountGroup,
        findingType: "duplicate",
      });
      continue;
    }

    payrollEmpNosProcessed.add(empNo);
    const matches = plantillaByEmpNo.get(empNo);

    if (!matches || matches.length === 0) {
      missingInPlantilla.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        payrollAccountGroup: row.accountGroup,
        findingType: "missingInPlantilla",
      });
      continue;
    }

    const p = matches[0];
    const pFullName = `${p.lastName.trim()}, ${p.firstName.trim()}${p.middleName.trim() ? " " + p.middleName.trim() : ""}`.toUpperCase();
    const pAccountGroup = `${p.accountName.trim()} / ${p.groupName.trim()}`.toUpperCase();

    if (!p.isActive) {
      paidInactive.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        plantillaFullName: pFullName,
        payrollAccountGroup: row.accountGroup,
        plantillaAccountGroup: pAccountGroup,
        findingType: "paidInactive",
      });
      continue;
    }

    const normPayName = row.fullName.replace(/[^A-Z0-9]/gi, "").toUpperCase();
    const normPlanName = pFullName.replace(/[^A-Z0-9]/gi, "").toUpperCase();
    const normPayAcct = row.accountGroup.replace(/[^A-Z0-9]/gi, "").toUpperCase();
    const normPlanAcct = pAccountGroup.replace(/[^A-Z0-9]/gi, "").toUpperCase();

    const nameDiffers = normPayName !== normPlanName;
    const acctDiffers = normPayAcct !== normPlanAcct;

    if (nameDiffers || acctDiffers) {
      mismatch.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        plantillaFullName: pFullName,
        payrollAccountGroup: row.accountGroup,
        plantillaAccountGroup: pAccountGroup,
        findingType: "mismatch",
      });
    } else {
      clean.push({
        employeeNumber: empNo,
        payrollFullName: row.fullName,
        plantillaFullName: pFullName,
        payrollAccountGroup: row.accountGroup,
        plantillaAccountGroup: pAccountGroup,
        findingType: "clean",
      });
    }
  }

  // Missing in Payroll
  for (const p of plantillaRows) {
    if (!p.isActive) continue;
    const empNo = p.employeeNo.trim().toUpperCase();
    if (!payrollEmpNosProcessed.has(empNo) && !duplicateEmpNos.has(empNo)) {
      const pFullName = `${p.lastName.trim()}, ${p.firstName.trim()}${p.middleName.trim() ? " " + p.middleName.trim() : ""}`.toUpperCase();
      const pAccountGroup = `${p.accountName.trim()} / ${p.groupName.trim()}`.toUpperCase();
      missingInPayroll.push({
        employeeNumber: empNo,
        plantillaFullName: pFullName,
        plantillaAccountGroup: pAccountGroup,
        findingType: "missingInPayroll",
      });
    }
  }

  return {
    payrollRows: payrollRows.length,
    activePlantillaCount,
    missingInPayroll,
    missingInPlantilla,
    paidInactive,
    mismatch,
    duplicates,
    clean,
  };
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
