import { createClient } from "@/lib/supabase/client";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export interface HrEmplocImportGroup {
  id: string;
  groupName: string;
  sortOrder: number;
}

export type ImportBatchStatus =
  | "pending_approval"
  | "approved"
  | "rejected"
  | "rolled_back";

export interface HrEmplocImportBatch {
  id: string;
  fileName: string;
  status: ImportBatchStatus;
  groupId: string;
  groupName: string | null;
  totalRows: number;
  validRows: number;
  blockedRows: number;
  duplicateRows: number;
  createdRows: number;
  uploadedBy: string | null;
  uploadedByName: string | null;
  uploadedAt: string | null;
  approvedBy: string | null;
  approvedByName: string | null;
  approvedAt: string | null;
  rejectedBy: string | null;
  rejectedByName: string | null;
  rejectedAt: string | null;
  rejectionReasonCode: string | null;
  rejectionReasonNote: string | null;
  rolledBackBy: string | null;
  rolledBackByName: string | null;
  rolledBackAt: string | null;
  rollbackReason: string | null;
  createdAt: string | null;
}

export interface HrEmplocImportValidationError {
  field: string;
  msg: string;
}

export interface HrEmplocImportRow {
  id: string;
  batchId: string;
  rowNumber: number;
  groupName: string | null;
  accountName: string | null;
  lastName: string | null;
  firstName: string | null;
  middleName: string | null;
  dateHired: string | null;
  positionName: string | null;
  storeName: string | null;
  employmentType: string | null;
  vcode: string | null;
  validationStatus: "valid" | "blocked";
  validationErrors: HrEmplocImportValidationError[];
  hrEmplocId: string | null;
  displayName: string;
}

export interface HrEmplocImportRowSummary {
  totalRows: number;
  validRows: number;
  blockedRows: number;
  duplicateRows: number;
  rows: HrEmplocImportRow[];
  errorsByReason: Record<string, HrEmplocImportRow[]>;
}

export interface SubmitImportBatchParams {
  groupId: string;
  filename: string;
  rows: Record<string, unknown>[];
}

export interface RejectImportBatchParams {
  batchId: string;
  reasonCode: string;
  reasonNote?: string | null;
}

export interface RollbackImportBatchParams {
  batchId: string;
  reason: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Raw RPC Normalizers
// ─────────────────────────────────────────────────────────────────────────────

function normalizeGroup(row: Record<string, unknown>): HrEmplocImportGroup {
  return {
    id: String(row.group_id ?? row.id ?? ""),
    groupName: String(row.group_name ?? row.name ?? ""),
    sortOrder: typeof row.sort_order === "number" ? row.sort_order : 0,
  };
}

function normalizeBatch(row: Record<string, unknown>): HrEmplocImportBatch {
  return {
    id: String(row.id ?? ""),
    fileName: String(row.file_name ?? ""),
    status: (row.status as ImportBatchStatus) ?? "pending_approval",
    groupId: String(row.group_id ?? ""),
    groupName: row.group_name ? String(row.group_name) : null,
    totalRows: Number(row.total_rows ?? 0),
    validRows: Number(row.valid_rows ?? 0),
    blockedRows: Number(row.blocked_rows ?? 0),
    duplicateRows: Number(row.duplicate_rows ?? 0),
    createdRows: Number(row.created_rows ?? 0),
    uploadedBy: row.uploaded_by ? String(row.uploaded_by) : null,
    uploadedByName: row.uploaded_by_name ? String(row.uploaded_by_name) : null,
    uploadedAt: row.uploaded_at ? String(row.uploaded_at) : null,
    approvedBy: row.approved_by ? String(row.approved_by) : null,
    approvedByName: row.approved_by_name ? String(row.approved_by_name) : null,
    approvedAt: row.approved_at ? String(row.approved_at) : null,
    rejectedBy: row.rejected_by ? String(row.rejected_by) : null,
    rejectedByName: row.rejected_by_name ? String(row.rejected_by_name) : null,
    rejectedAt: row.rejected_at ? String(row.rejected_at) : null,
    rejectionReasonCode: row.rejection_reason_code
      ? String(row.rejection_reason_code)
      : null,
    rejectionReasonNote: row.rejection_reason_note
      ? String(row.rejection_reason_note)
      : null,
    rolledBackBy: row.rolled_back_by ? String(row.rolled_back_by) : null,
    rolledBackByName: row.rolled_back_by_name
      ? String(row.rolled_back_by_name)
      : null,
    rolledBackAt: row.rolled_back_at ? String(row.rolled_back_at) : null,
    rollbackReason: row.rollback_reason ? String(row.rollback_reason) : null,
    createdAt: row.created_at ? String(row.created_at) : null,
  };
}

function normalizeValidationErrors(raw: unknown): HrEmplocImportValidationError[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((e) => {
      if (typeof e === "object" && e !== null) {
        const item = e as Record<string, unknown>;
        return {
          field: String(item.field ?? ""),
          msg: String(item.msg ?? item.message ?? ""),
        };
      }
      return null;
    })
    .filter((e): e is HrEmplocImportValidationError => e !== null);
}

function normalizeRow(row: Record<string, unknown>): HrEmplocImportRow {
  const firstName = row.first_name ? String(row.first_name) : null;
  const middleName = row.middle_name ? String(row.middle_name) : null;
  const lastName = row.last_name ? String(row.last_name) : null;

  const parts = [firstName, middleName, lastName].filter(Boolean);
  const displayName = parts.length > 0 ? parts.join(" ") : "Unnamed Employee";

  return {
    id: String(row.id ?? ""),
    batchId: String(row.batch_id ?? ""),
    rowNumber: Number(row.row_number ?? 0),
    groupName: row.group_name ? String(row.group_name) : null,
    accountName: row.account_name ? String(row.account_name) : null,
    lastName,
    firstName,
    middleName,
    dateHired: row.date_hired ? String(row.date_hired) : null,
    positionName: row.position_name
      ? String(row.position_name)
      : row.position
      ? String(row.position)
      : null,
    storeName: row.store_name ? String(row.store_name) : null,
    employmentType: row.employment_type ? String(row.employment_type) : null,
    vcode: row.vcode ? String(row.vcode) : null,
    validationStatus:
      String(row.validation_status ?? "blocked") === "valid"
        ? "valid"
        : "blocked",
    validationErrors: normalizeValidationErrors(row.validation_errors),
    hrEmplocId: row.hr_emploc_id ? String(row.hr_emploc_id) : null,
    displayName,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// RPC Wrappers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 1. Fetch operational groups for import dropdown.
 * Invokes RPC: get_hr_emploc_import_groups()
 */
export async function fetchImportGroups(): Promise<HrEmplocImportGroup[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_hr_emploc_import_groups");

  if (error) {
    throw new Error(`Failed to load import groups: ${error.message}`);
  }

  return (data as Record<string, unknown>[]).map(normalizeGroup);
}

/**
 * 2. Submit XLSX rows (Validates slot-first, creates batch in pending_approval).
 * Invokes RPC: submit_hr_emploc_import(p_file_name, p_group_id, p_rows)
 * Accepts either:
 *   - Object: { groupId, filename, rows }
 *   - Positional: (groupId, filename, rows) or (p_group_id, p_filename, p_rows_json)
 */
export async function submitImportBatch(
  param1: string | SubmitImportBatchParams,
  param2?: string,
  param3?: Record<string, unknown>[],
): Promise<{ batchId: string }> {
  let groupId: string;
  let filename: string;
  let rows: Record<string, unknown>[];

  if (typeof param1 === "object" && param1 !== null) {
    groupId = param1.groupId;
    filename = param1.filename;
    rows = param1.rows;
  } else {
    groupId = param1;
    filename = param2 ?? "import.xlsx";
    rows = param3 ?? [];
  }

  const supabase = createClient();
  const { data, error } = await supabase.rpc("submit_hr_emploc_import", {
    p_file_name: filename,
    p_group_id: groupId,
    p_rows: rows,
  });

  if (error) {
    throw new Error(error.message);
  }

  const result = data as { batch_id?: string } | null;
  const batchId = result?.batch_id ?? "";
  if (!batchId) {
    throw new Error("Batch submission succeeded but returned no batch ID.");
  }

  return { batchId };
}

/**
 * 3. Fetch import batches.
 * Invokes RPC: get_hr_emploc_import_batches()
 */
export async function fetchImportBatches(): Promise<HrEmplocImportBatch[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_hr_emploc_import_batches");

  if (error) {
    throw new Error(`Failed to fetch import batches: ${error.message}`);
  }

  return (data as Record<string, unknown>[]).map(normalizeBatch);
}

/**
 * 4. Fetch row-level staged items for review.
 * Invokes RPC: get_hr_emploc_import_rows(p_batch_id)
 */
export async function fetchBatchRows(
  batchId: string,
): Promise<HrEmplocImportRowSummary> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_hr_emploc_import_rows", {
    p_batch_id: batchId,
  });

  if (error) {
    throw new Error(`Failed to fetch import batch rows: ${error.message}`);
  }

  const rows = (data as Record<string, unknown>[]).map(normalizeRow);
  const validRows = rows.filter((r) => r.validationStatus === "valid").length;
  const blockedRows = rows.filter((r) => r.validationStatus === "blocked").length;
  const duplicateRows = rows.filter(
    (r) =>
      r.validationStatus === "blocked" &&
      r.validationErrors.some((e) => e.field.toLowerCase() === "identity"),
  ).length;

  const errorsByReason: Record<string, HrEmplocImportRow[]> = {};
  for (const row of rows.filter((r) => r.validationStatus === "blocked")) {
    for (const err of row.validationErrors) {
      const key = err.msg || "Unknown error";
      if (!errorsByReason[key]) {
        errorsByReason[key] = [];
      }
      errorsByReason[key].push(row);
    }
  }

  return {
    totalRows: rows.length,
    validRows,
    blockedRows,
    duplicateRows,
    rows,
    errorsByReason,
  };
}

/**
 * 5. HA/SA Approval (Atomic slot claim, vacancy closure, hr_emploc insertion).
 * Invokes RPC: approve_hr_emploc_import(p_batch_id)
 */
export async function approveImportBatch(
  batchId: string,
  _notes?: string,
): Promise<{ recordsCreated: number }> {
  void _notes;
  const supabase = createClient();
  const { data, error } = await supabase.rpc("approve_hr_emploc_import", {
    p_batch_id: batchId,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = data as { records_created?: number } | null;
  return { recordsCreated: Number(res?.records_created ?? 0) };
}

/**
 * 6. Reject batch.
 * Invokes RPC: reject_hr_emploc_import(p_batch_id, p_reason_code, p_reason_note)
 */
export async function rejectImportBatch(
  batchId: string,
  rejectionReason: string,
  notes?: string | null,
): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("reject_hr_emploc_import", {
    p_batch_id: batchId,
    p_reason_code: rejectionReason,
    p_reason_note: notes ?? null,
  });

  if (error) {
    throw new Error(error.message);
  }
}

/**
 * 7. Rollback batch (Soft-deletes batch records, reopens slots & vacancies).
 * Invokes RPC: rollback_hr_emploc_import(p_batch_id, p_reason)
 */
export async function rollbackImportBatch(
  batchId: string,
  reason: string,
): Promise<{ recordsRemoved: number }> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("rollback_hr_emploc_import", {
    p_batch_id: batchId,
    p_reason: reason,
  });

  if (error) {
    throw new Error(error.message);
  }

  const res = data as { records_removed?: number } | null;
  return { recordsRemoved: Number(res?.records_removed ?? 0) };
}

// ─────────────────────────────────────────────────────────────────────────────
// React Query Hooks
// ─────────────────────────────────────────────────────────────────────────────

export function useImportGroups() {
  return useQuery({
    queryKey: ["hr-emploc-import-groups"],
    queryFn: fetchImportGroups,
    staleTime: 5 * 60 * 1000,
  });
}

export function useImportBatches() {
  return useQuery({
    queryKey: ["hr-emploc-import-batches"],
    queryFn: fetchImportBatches,
    staleTime: 30 * 1000,
  });
}

export function useBatchRows(batchId: string | null) {
  return useQuery({
    queryKey: ["hr-emploc-import-rows", batchId],
    queryFn: () => (batchId ? fetchBatchRows(batchId) : null),
    enabled: Boolean(batchId),
    staleTime: 30 * 1000,
  });
}

export function useSubmitImportBatch() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (params: SubmitImportBatchParams) => submitImportBatch(params),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["hr-emploc-import-batches"],
      });
    },
  });
}

export function useApproveImportBatch() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ batchId, notes }: { batchId: string; notes?: string }) =>
      approveImportBatch(batchId, notes),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["hr-emploc-import-batches"],
      });
      void queryClient.invalidateQueries({
        queryKey: ["hr-emploc-list"],
      });
      void queryClient.invalidateQueries({
        queryKey: ["hr-emploc-summary"],
      });
    },
  });
}

export function useRejectImportBatch() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ batchId, reasonCode, reasonNote }: RejectImportBatchParams) =>
      rejectImportBatch(batchId, reasonCode, reasonNote),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["hr-emploc-import-batches"],
      });
    },
  });
}

export function useRollbackImportBatch() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ batchId, reason }: RollbackImportBatchParams) =>
      rollbackImportBatch(batchId, reason),
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["hr-emploc-import-batches"],
      });
      void queryClient.invalidateQueries({
        queryKey: ["hr-emploc-list"],
      });
      void queryClient.invalidateQueries({
        queryKey: ["hr-emploc-summary"],
      });
    },
  });
}
