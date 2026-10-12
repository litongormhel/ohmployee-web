import type { PostgrestError } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

export type HrEmplocQueue =
  | "pending"
  | "correction"
  | "review"
  | "ready"
  | "deficiency"
  | "complete"
  | "deletion_pending"
  | "all";

export type HrEmplocRowCapabilities = {
  canViewDetail: boolean;
  canTagDeficiency: boolean;      // For HR Personnel
  canReviewCorrection: boolean;   // For HR Personnel — For Review records only
  canAssignEmployeeNo: boolean;   // For Encoder & Super Admin (Blocked for Head Admin)
  canMoveToPlantilla: boolean;    // For Encoder, Head Admin & Super Admin
  canRequestDeletion: boolean;    // For Ops roles (om, hrco, atl, tl)
  canReviewDeletion: boolean;     // For Encoder, Head Admin & Super Admin
  raw: Record<string, boolean>;
};

export type HrEmplocListItem = {
  id: string;
  applicantName: string;
  vcode: string;
  accountId: string | null;
  accountName: string | null;
  storeName: string | null;
  positionTitle: string | null;
  hrStatus: string;
  deploymentStatus: string;
  employeeNo: string | null;
  assignmentType: string | null;
  coveredStoresCount: number;
  deficiencySummary: string | null;
  hiredDate: string | null;
  dateRequested: string | null;
  slaBreached: boolean;
  slaElapsedDays: number;
  rowCapabilities: HrEmplocRowCapabilities;
  totalCount: number;
};

export type CoveredStoreItem = {
  storeId: string;
  storeName: string;
  address?: string;
};

export type CorrectionAttachmentItem = {
  attachmentId: string;
  fileName: string;
  fileUrl: string;
  fileSize?: number;
  uploadedAt: string | null;
  uploadedBy: string;
};

export type HrEmplocAuditLogItem = {
  eventId: string;
  eventLabel: string;
  eventDescription: string | null;
  createdAt: string | null;
  profileName: string | null;
};

export type DeletionRequestItem = {
  requestId: string;
  requestedBy: string;
  requestedAt: string | null;
  deletionType: "backout" | "duplicate";
  reason: string;
  originalEmplocId?: string | null;
  status: string;
};

export type HrEmplocDetailItem = {
  id: string;
  applicantName: string;
  vcode: string;
  accountName: string | null;
  storeName: string | null;
  positionTitle: string | null;
  hrStatus: string;
  deploymentStatus: string;
  employeeNo: string | null;
  assignmentType: string | null;
  coveredStores: CoveredStoreItem[];
  hiredDate: string | null;
  dateRequested: string | null;
  hrcoName: string | null;
  opsRemarks: string | null;
  hrRemarks: string | null;
  requirementOverallStatus: string | null;
  correctionReason: Record<string, unknown>;
  uploadedAttachments: CorrectionAttachmentItem[];
  slaBreached: boolean;
  slaElapsedDays: number;
  auditLogsTimeline: HrEmplocAuditLogItem[];
  activeDeletionRequest: DeletionRequestItem | null;
  rowCapabilities: HrEmplocRowCapabilities;
};

export type HrEmplocListParams = {
  queue?: HrEmplocQueue;
  accountId?: string;
  groupId?: string;
  position?: string;
  assignment?: "Stationary" | "Roving";
  search?: string;
  page: number;
  pageSize: number;
  sortBy?: string;
  sortDir?: "asc" | "desc";
};

export type HrEmplocSummary = {
  pending: number;          // hr_status = 'Pending'
  correction: number;       // hr_status = 'For Correction'
  review: number;           // hr_status = 'For Review'
  ready: number;            // hr_status = 'Complete'
  totalPending: number;     // legacy alias
  actionNeeded: number;     // legacy alias
  readyToDeploy: number;    // legacy alias
  pendingDeletion: number;  // hr_status = 'Pending Deletion'
  slaBreaches: number;      // Count where sla_breached = true
};

export type HrEmplocDataErrorKind = "access_denied" | "invalid_state" | "retryable";

export class HrEmplocDataError extends Error {
  kind: HrEmplocDataErrorKind;

  constructor(kind: HrEmplocDataErrorKind, message: string) {
    super(message);
    this.name = "HrEmplocDataError";
    this.kind = kind;
  }
}

type HrEmplocRpcRow = Record<string, unknown>;

const DEFAULT_PAGE_SIZE = 25;
const MAX_PAGE_SIZE = 100;

function asObject(value: unknown): Record<string, unknown> {
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function asBoolean(value: unknown): boolean {
  return value === true;
}

function asCount(value: unknown): number {
  return Math.max(0, Math.trunc(asNumber(value) ?? 0));
}

function normalizeCapabilities(value: unknown): HrEmplocRowCapabilities {
  const raw = Object.fromEntries(
    Object.entries(asObject(value))
      .filter(([, item]) => typeof item === "boolean")
      .map(([key, item]) => [key, item === true]),
  );

  return {
    canViewDetail: raw.can_view_detail === true || raw.can_view === true,
    canTagDeficiency: raw.can_tag_deficiency === true,
    canReviewCorrection: raw.can_review_correction === true,
    canAssignEmployeeNo: raw.can_assign_employee_no === true,
    canMoveToPlantilla: raw.can_move_to_plantilla === true,
    canRequestDeletion: raw.can_request_deletion === true,
    canReviewDeletion: raw.can_review_deletion === true,
    raw,
  };
}

function getTotalCount(rows: HrEmplocListItem[]): number {
  return rows[0]?.totalCount ?? 0;
}

function getErrorKind(error: PostgrestError): HrEmplocDataErrorKind {
  const combined = `${error.code ?? ""} ${error.message ?? ""} ${error.details ?? ""}`
    .toLowerCase()
    .trim();

  if (
    combined.includes("permission denied") ||
    combined.includes("not authorized") ||
    combined.includes("unauthorized") ||
    combined.includes("forbidden") ||
    combined.includes("rls") ||
    error.code === "42501"
  ) {
    return "access_denied";
  }

  if (error.code === "P0001") {
    return "invalid_state";
  }

  return "retryable";
}

function throwHrEmplocError(error: PostgrestError): never {
  throw new HrEmplocDataError(getErrorKind(error), error.message);
}

function summarizeDeficiency(value: unknown): string | null {
  const obj = asObject(value);
  const activeCount = asCount(obj.active_count);

  if (activeCount <= 0) {
    return null;
  }

  const issues = Array.isArray(obj.issues) ? obj.issues : [];
  const labels = issues
    .map((issue) => asString(asObject(issue).label))
    .filter((label): label is string => label !== null);

  return labels.length > 0 ? labels.join(", ") : `${activeCount} issue${activeCount > 1 ? "s" : ""}`;
}

function normalizeListRow(row: HrEmplocRpcRow): HrEmplocListItem | null {
  const id = asString(row.id ?? row.hr_emploc_id);

  if (!id) {
    return null;
  }

  return {
    id,
    applicantName: asString(row.applicant_name ?? row.applicantName) ?? "Anonymous",
    vcode: asString(row.vcode) ?? "Uncoded",
    accountId: asString(row.account_id ?? row.accountId),
    accountName: asString(row.account_name ?? row.accountName),
    storeName: asString(row.store_name ?? row.storeName),
    positionTitle: asString(row.position_title ?? row.positionTitle),
    hrStatus: asString(row.hr_status ?? row.hrStatus) ?? "Pending",
    deploymentStatus: asString(row.deployment_status ?? row.deploymentStatus ?? row.status) ?? "Pending Emploc",
    employeeNo: asString(row.employee_no ?? row.employeeNo),
    assignmentType: asString(row.assignment_type ?? row.assignmentType),
    coveredStoresCount: asCount(row.covered_stores_count ?? row.coveredStoresCount),
    deficiencySummary: summarizeDeficiency(row.deficiency_summary ?? row.deficiencySummary),
    hiredDate: asString(row.hired_date ?? row.hiredDate),
    dateRequested: asString(row.date_requested ?? row.dateRequested),
    slaBreached: asBoolean(row.sla_breached ?? row.slaBreached),
    slaElapsedDays: asCount(row.aging_days ?? row.sla_elapsed_days ?? row.slaElapsedDays),
    rowCapabilities: normalizeCapabilities(row.row_capabilities ?? row.rowCapabilities),
    totalCount: asCount(row.total_count ?? row.totalCount),
  };
}

function normalizeCoveredStore(item: unknown): CoveredStoreItem {
  const obj = asObject(item);
  return {
    storeId: asString(obj.store_id ?? obj.storeId) ?? "",
    storeName: asString(obj.store_name ?? obj.storeName) ?? "Unknown Store",
    address: asString(obj.address) ?? undefined,
  };
}

function normalizeAttachment(item: unknown): CorrectionAttachmentItem {
  const obj = asObject(item);
  return {
    attachmentId: asString(obj.id ?? obj.attachment_id ?? obj.attachmentId) ?? "",
    fileName: asString(obj.original_filename ?? obj.file_name ?? obj.fileName) ?? "unnamed_file",
    fileUrl: asString(obj.storage_path ?? obj.file_url ?? obj.fileUrl) ?? "",
    fileSize: asNumber(obj.size_bytes ?? obj.file_size ?? obj.fileSize) ?? undefined,
    uploadedAt: asString(obj.uploaded_at ?? obj.uploadedAt) ?? null,
    uploadedBy: asString(obj.uploaded_by ?? obj.uploadedBy) ?? "Unknown User",
  };
}

function normalizeAuditLog(item: unknown): HrEmplocAuditLogItem {
  const obj = asObject(item);
  return {
    eventId: asString(obj.event_id ?? obj.eventId) ?? "",
    eventLabel: asString(obj.event_label ?? obj.eventLabel) ?? "Event",
    eventDescription: asString(obj.remarks ?? obj.event_description ?? obj.eventDescription) ?? null,
    createdAt: asString(obj.created_at ?? obj.createdAt) ?? null,
    profileName: asString(obj.actor_name ?? obj.profile_name ?? obj.profileName) ?? null,
  };
}

function normalizeDeletionRequest(item: unknown): DeletionRequestItem | null {
  if (!item) return null;
  const obj = asObject(item);
  const requestId = asString(obj.id ?? obj.request_id ?? obj.requestId);
  if (!requestId) return null;

  return {
    requestId,
    requestedBy: asString(obj.requested_by ?? obj.requestedBy) ?? "Unknown",
    requestedAt: asString(obj.created_at ?? obj.requested_at ?? obj.requestedAt) ?? null,
    deletionType: (asString(obj.deletion_type ?? obj.deletionType) as "backout" | "duplicate") ?? "backout",
    reason: asString(obj.reason) ?? "",
    originalEmplocId: asString(obj.original_emploc_id ?? obj.originalEmplocId) ?? null,
    status: asString(obj.status) ?? "Pending",
  };
}

function normalizeDetailRow(row: HrEmplocRpcRow): HrEmplocDetailItem | null {
  const id = asString(row.id ?? row.hr_emploc_id);

  if (!id) {
    return null;
  }

  const rawCovered = Array.isArray(row.covered_stores) ? row.covered_stores : [];
  const coveredStores = rawCovered.map(normalizeCoveredStore);

  const rawAttachments = Array.isArray(row.correction_attachments) ? row.correction_attachments : [];
  const uploadedAttachments = rawAttachments.map(normalizeAttachment);

  const rawTimeline = Array.isArray(row.timeline) ? row.timeline : [];
  const auditLogsTimeline = rawTimeline.map(normalizeAuditLog);

  const activeDeletionRequest = normalizeDeletionRequest(row.deletion_request);

  return {
    id,
    applicantName: asString(row.applicant_name ?? row.applicantName) ?? "Anonymous",
    vcode: asString(row.vcode) ?? "Uncoded",
    accountName: asString(row.account_name ?? row.accountName) ?? null,
    storeName: asString(row.store_name ?? row.storeName) ?? null,
    positionTitle: asString(row.position_title ?? row.positionTitle) ?? null,
    hrStatus: asString(row.hr_status ?? row.hrStatus) ?? "Pending",
    deploymentStatus: asString(row.deployment_status ?? row.deploymentStatus ?? row.status) ?? "Pending Emploc",
    employeeNo: asString(row.employee_no ?? row.employeeNo) ?? null,
    assignmentType: asString(row.assignment_type ?? row.assignmentType) ?? null,
    coveredStores,
    hiredDate: asString(row.hired_date ?? row.hiredDate) ?? null,
    dateRequested: asString(row.date_requested ?? row.dateRequested) ?? null,
    hrcoName: asString(row.hrco_name ?? row.hrcoName) ?? null,
    opsRemarks: asString(row.ops_remarks ?? row.opsRemarks) ?? null,
    hrRemarks: asString(row.hr_remarks ?? row.hrRemarks) ?? null,
    requirementOverallStatus: asString(row.requirement_overall_status ?? row.requirementOverallStatus) ?? null,
    correctionReason: asObject(row.correction_reason ?? row.correctionReason),
    uploadedAttachments,
    slaBreached: asBoolean(row.sla_breached ?? row.slaBreached),
    slaElapsedDays: asCount(row.aging_days ?? row.sla_elapsed_days ?? row.slaElapsedDays),
    auditLogsTimeline,
    activeDeletionRequest,
    rowCapabilities: normalizeCapabilities(row.row_capabilities ?? row.rowCapabilities),
  };
}

function normalizeSummary(data: unknown): HrEmplocSummary {
  const row = Array.isArray(data) ? asObject(data[0]) : asObject(data);

  const pending = asCount(row.pending_count ?? row.pending ?? row.total_pending ?? row.totalPending ?? row.total_processing);
  const correction = asCount(row.correction_count ?? row.correction ?? row.action_needed ?? row.actionNeeded ?? row.action_needed_count);
  const review = asCount(row.review_count ?? row.review);
  const ready = asCount(row.ready_count ?? row.ready ?? row.ready_to_deploy ?? row.readyToDeploy ?? row.ready_to_deploy_count);

  return {
    pending,
    correction,
    review,
    ready,
    totalPending: pending,
    actionNeeded: correction,
    readyToDeploy: ready,
    pendingDeletion: asCount(row.pending_deletion_count ?? row.pending_deletion ?? row.pendingDeletion),
    slaBreaches: asCount(row.sla_breached_count ?? row.sla_breaches ?? row.slaBreaches),
  };
}

export async function getWebHrEmplocSummary(
  params: Pick<HrEmplocListParams, "queue" | "accountId" | "groupId" | "search">
) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_hr_emploc_summary", {
    p_queue: params.queue || null,
    p_status: null,
    p_deficiency: null,
    p_sla_filter: null,
    p_account_id: params.accountId || null,
    p_group_id: params.groupId || null,
    p_search: params.search?.trim() || null,
  });

  if (error) {
    throwHrEmplocError(error);
  }

  return normalizeSummary(data);
}

export async function listWebHrEmplocs(params: HrEmplocListParams) {
  const supabase = createClient();
  const page = Math.max(1, Math.trunc(params.page));
  const pageSize = Math.min(
    MAX_PAGE_SIZE,
    Math.max(1, Math.trunc(params.pageSize ?? DEFAULT_PAGE_SIZE))
  );
  const offset = (page - 1) * pageSize;

  const { data, error } = await supabase.rpc("list_web_hr_emplocs", {
    p_queue: params.queue || null,
    p_status: null,
    p_deficiency: null,
    p_sla_filter: null,
    p_account_id: params.accountId || null,
    p_group_id: params.groupId || null,
    p_search: params.search?.trim() || null,
    p_limit: pageSize,
    p_offset: offset,
    p_sort_by: params.sortBy || "created_at",
    p_sort_dir: params.sortDir || "desc",
  });

  if (error) {
    throwHrEmplocError(error);
  }

  const rows = (Array.isArray(data) ? data : [])
    .map((row) => normalizeListRow(asObject(row)))
    .filter((row): row is HrEmplocListItem => row !== null);

  return {
    data: rows,
    totalCount: getTotalCount(rows),
    page,
    pageSize,
  };
}

export type TagDeficiencyParams = {
  hrEmplocId: string;
  deficiencies: Record<string, string>;
  remarks?: string | null;
};

export type TagDeficiencyResult = {
  ok: boolean;
  hrEmplocId: string;
  newHrStatus: string;
  correctionReason: Record<string, unknown>;
  taggedAt: string;
};

export async function tagWebHrEmplocDeficiency(
  params: TagDeficiencyParams,
): Promise<TagDeficiencyResult> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("tag_web_hr_emploc_deficiency", {
    p_hr_emploc_id: params.hrEmplocId,
    p_deficiencies: params.deficiencies,
    p_remarks: params.remarks ?? null,
  });

  if (error) {
    throwHrEmplocError(error);
  }

  const row = asObject(data);
  return {
    ok: asBoolean(row.ok),
    hrEmplocId: asString(row.hr_emploc_id) ?? params.hrEmplocId,
    newHrStatus: asString(row.new_hr_status) ?? "For Correction",
    correctionReason: asObject(row.correction_reason),
    taggedAt: asString(row.tagged_at) ?? new Date().toISOString(),
  };
}

export type ReviewCorrectionParams = {
  hrEmplocId: string;
  decision: "approve" | "return";
  resolvedKeys?: string[] | null;
  remarks?: string | null;
};

export type ReviewCorrectionResult = {
  ok: boolean;
  hrEmplocId: string;
  decision: string;
  newHrStatus: string;
  correctionReason: Record<string, unknown>;
  reviewedAt: string;
};

export async function reviewWebHrEmplocCorrection(
  params: ReviewCorrectionParams,
): Promise<ReviewCorrectionResult> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("review_web_hr_emploc_correction", {
    p_hr_emploc_id: params.hrEmplocId,
    p_decision: params.decision,
    p_resolved_keys: params.resolvedKeys ?? null,
    p_remarks: params.remarks ?? null,
  });

  if (error) {
    throwHrEmplocError(error);
  }

  const row = asObject(data);
  return {
    ok: asBoolean(row.ok),
    hrEmplocId: asString(row.hr_emploc_id) ?? params.hrEmplocId,
    decision: asString(row.decision) ?? params.decision,
    newHrStatus: asString(row.new_hr_status) ?? (params.decision === "approve" ? "Complete" : "For Correction"),
    correctionReason: asObject(row.correction_reason),
    reviewedAt: asString(row.reviewed_at) ?? new Date().toISOString(),
  };
}

export async function getWebHrEmplocDetail(hrEmplocId: string): Promise<HrEmplocDetailItem> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_hr_emploc_detail", {
    p_hr_emploc_id: hrEmplocId,
  });

  if (error) {
    throwHrEmplocError(error);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new HrEmplocDataError("retryable", "No HR Emploc detail record found");
  }

  const normalized = normalizeDetailRow(asObject(row));
  if (!normalized) {
    throw new HrEmplocDataError("retryable", "Failed to normalize HR Emploc detail record");
  }

  return normalized;
}

// ─── Slot Availability Checker (ADR-001) ────────────────────────────────────

export async function fetchAvailableSlotsForVcode(vcode: string): Promise<number> {
  const cleanVcode = vcode.trim();
  if (!cleanVcode) return 1;

  const supabase = createClient();

  // 1. Try checking plantilla_slots for stationary/roving slots
  try {
    const { data: slotRows, error: slotError } = await supabase
      .from("plantilla_slots")
      .select("id, slot_status")
      .eq("legacy_vcode", cleanVcode);

    if (!slotError && Array.isArray(slotRows) && slotRows.length > 0) {
      let available = 0;
      const hrProcessingSlotIds: string[] = [];

      for (const r of slotRows) {
        const status = (asString(r.slot_status) ?? "").toLowerCase();
        const id = asString(r.id);
        if (status === "open") {
          available++;
        } else if (status === "hr_processing" && id) {
          hrProcessingSlotIds.push(id);
        }
      }

      if (hrProcessingSlotIds.length > 0) {
        const { data: reservedRows } = await supabase
          .from("hr_emploc")
          .select("slot_id")
          .in("slot_id", hrProcessingSlotIds)
          .is("deleted_at", null)
          .is("moved_to_plantilla_at", null);

        if (Array.isArray(reservedRows)) {
          const uniqueReserved = new Set(
            reservedRows.map((row) => asString(row.slot_id)).filter(Boolean)
          );
          available += uniqueReserved.size;
        }
      }

      return available;
    }
  } catch {
    // Continue to pool check
  }

  // 2. Try checking workforce_pool_slots for pool vacancies
  try {
    const { data: poolRows, error: poolError } = await supabase
      .from("workforce_pool_slots")
      .select("id, status")
      .eq("vcode", cleanVcode)
      .eq("is_active", true)
      .is("deleted_at", null);

    if (!poolError && Array.isArray(poolRows) && poolRows.length > 0) {
      let available = 0;
      const hrProcessingPoolIds: string[] = [];

      for (const r of poolRows) {
        const status = (asString(r.status) ?? "").toLowerCase();
        const id = asString(r.id);
        if (status === "open") {
          available++;
        } else if (status === "hr_processing" && id) {
          hrProcessingPoolIds.push(id);
        }
      }

      if (hrProcessingPoolIds.length > 0) {
        const { data: reservedPoolRows } = await supabase
          .from("hr_emploc")
          .select("pool_slot_id")
          .in("pool_slot_id", hrProcessingPoolIds)
          .is("deleted_at", null)
          .is("moved_to_plantilla_at", null);

        if (Array.isArray(reservedPoolRows)) {
          const uniqueReservedPool = new Set(
            reservedPoolRows.map((row) => asString(row.pool_slot_id)).filter(Boolean)
          );
          available += uniqueReservedPool.size;
        }
      }

      return available;
    }
  } catch {
    // Fallback
  }

  return 1;
}

// ─── Lifecycle Mutation Actions ──────────────────────────────────────────────

export type AssignEmployeeNoParams = {
  hrEmplocId: string;
  employeeNo: string;
};

export async function assignHrEmplocNumber(params: AssignEmployeeNoParams): Promise<void> {
  const normalizedEmployeeNo = params.employeeNo.trim();
  if (!normalizedEmployeeNo) {
    throw new HrEmplocDataError("invalid_state", "Employee number is required.");
  }

  const supabase = createClient();
  const { error } = await supabase.rpc("assign_hr_emploc_number", {
    p_id: params.hrEmplocId,
    p_employee_no: normalizedEmployeeNo,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}

export type MoveToPlantillaParams = {
  hrEmplocId: string;
  vcode?: string;
};

export async function moveToPlantilla(params: MoveToPlantillaParams): Promise<void> {
  if (params.vcode?.trim()) {
    const availableSlots = await fetchAvailableSlotsForVcode(params.vcode.trim());
    if (availableSlots <= 0) {
      throw new HrEmplocDataError(
        "invalid_state",
        "No available slot capacity found for VCode " + params.vcode.trim() + "."
      );
    }
  }

  const supabase = createClient();
  const { error } = await supabase.rpc("move_to_plantilla", {
    p_id: params.hrEmplocId,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}

export type BulkMoveResultItem = {
  hrEmplocId: string;
  plantillaId: string | null;
  result: "moved" | "skipped";
  error: string | null;
};

export async function bulkMoveReadyToPlantilla(): Promise<BulkMoveResultItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("bulk_move_ready_to_plantilla");

  if (error) {
    throwHrEmplocError(error);
  }

  const rows = Array.isArray(data) ? data : [];
  return rows.map((r) => {
    const obj = asObject(r);
    return {
      hrEmplocId: asString(obj.hr_emploc_id) ?? "",
      plantillaId: asString(obj.plantilla_id),
      result: (asString(obj.result) ?? "skipped") as "moved" | "skipped",
      error: asString(obj.error),
    };
  });
}

export type RequestEmplocDeletionParams = {
  hrEmplocId: string;
  reason: string;
  deletionType: "backout" | "duplicate";
  originalEmplocId?: string | null;
};

export async function requestEmplocDeletion(params: RequestEmplocDeletionParams): Promise<void> {
  const normalizedReason = params.reason.trim();
  if (!normalizedReason) {
    throw new HrEmplocDataError("invalid_state", "A reason or remarks for deletion is required.");
  }

  // Canonical database values: 'Backout' | 'Duplicate Record'
  const dbDeletionType = params.deletionType === "duplicate" ? "Duplicate Record" : "Backout";

  if (params.deletionType === "duplicate" && !params.originalEmplocId?.trim()) {
    throw new HrEmplocDataError(
      "invalid_state",
      "Original Emploc ID is required when flagging a duplicate record."
    );
  }

  const supabase = createClient();
  const { error } = await supabase.rpc("fn_request_emploc_deletion", {
    p_hr_emploc_id: params.hrEmplocId,
    p_reason: normalizedReason,
    p_deletion_type: dbDeletionType,
    p_original_emploc_id: params.originalEmplocId?.trim() || null,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}

export type WithdrawEmplocDeletionParams = {
  requestId: string;
  reason?: string | null;
};

export async function withdrawEmplocDeletionRequest(
  params: WithdrawEmplocDeletionParams
): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("fn_withdraw_emploc_deletion_request", {
    p_request_id: params.requestId,
    p_reason: params.reason?.trim() || null,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}

// ─── React Query Mutation Hooks ──────────────────────────────────────────────

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export function useAssignEmployeeNo() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: AssignEmployeeNoParams) => assignHrEmplocNumber(params),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail", variables.hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", variables.hrEmplocId] });
    },
  });
}

export function useMoveToPlantilla() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: MoveToPlantillaParams) => moveToPlantilla(params),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail", variables.hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", variables.hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useBulkMoveToPlantilla() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: () => bulkMoveReadyToPlantilla(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useRequestEmplocDeletion() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RequestEmplocDeletionParams) => requestEmplocDeletion(params),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail", variables.hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", variables.hrEmplocId] });
    },
  });
}

export function useWithdrawEmplocDeletion() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: WithdrawEmplocDeletionParams) =>
      withdrawEmplocDeletionRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail"] });
    },
  });
}

// ─── Approvals Center: Deletion Review Queue ─────────────────────────────────

export type EmplocDeletionRequestItem = {
  /** `hr_emploc_deletion_requests.id` */
  id: string;
  hrEmplocId: string;
  /** Employee display name from hr_emploc */
  applicantName: string;
  /** Employee number from hr_emploc */
  employeeNo: string | null;
  /** Store name from hr_emploc */
  storeName: string | null;
  /** Position title from hr_emploc */
  positionTitle: string | null;
  /** VCode from hr_emploc */
  vcode: string;
  /** 'Backout' | 'Duplicate Record' */
  deletionType: string;
  /** Requester's display name */
  requestedByName: string | null;
  /** ISO timestamp of the request */
  requestedAt: string | null;
  /** Current status — should be 'Pending' for this queue */
  status: string;
  /** Reason / remarks from requester */
  reason: string | null;
  /** Original emploc ID when deletion_type = 'Duplicate Record' */
  originalEmplocId: string | null;
};

/**
 * Fetches pending HR Emploc deletion requests joined with hr_emploc data.
 * Queries `hr_emploc_deletion_requests` joined with `hr_emploc` for name,
 * store, position, and employee_no context needed by reviewers.
 */
export async function fetchEmplocDeletionRequests(): Promise<EmplocDeletionRequestItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("hr_emploc_deletion_requests")
    .select(`
      id,
      hr_emploc_id,
      deletion_type,
      reason,
      original_emploc_id,
      status,
      requested_by,
      created_at,
      hr_emploc (
        applicant_name,
        employee_no,
        store_name,
        position_title,
        vcode
      )
    `)
    .ilike("status", "pending")
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42501") {
      throw new HrEmplocDataError("access_denied", "Unauthorized: Scoped access restricted.");
    }
    throw new HrEmplocDataError("retryable", error.message);
  }

  return (data ?? []).map((row): EmplocDeletionRequestItem => {
    const emploc = asObject(
      Array.isArray(row.hr_emploc) ? row.hr_emploc[0] : row.hr_emploc
    );
    return {
      id: asString(row.id) ?? "",
      hrEmplocId: asString(row.hr_emploc_id) ?? "",
      applicantName: asString(emploc.applicant_name) ?? "Anonymous",
      employeeNo: asString(emploc.employee_no),
      storeName: asString(emploc.store_name),
      positionTitle: asString(emploc.position_title),
      vcode: asString(emploc.vcode) ?? "Uncoded",
      deletionType: asString(row.deletion_type) ?? "Backout",
      requestedByName: asString(row.requested_by),
      requestedAt: asString(row.created_at),
      status: asString(row.status) ?? "Pending",
      reason: asString(row.reason),
      originalEmplocId: asString(row.original_emploc_id),
    };
  });
}

export type ApproveEmplocDeletionParams = {
  requestId: string;
  reopenVacancy: boolean;
  notes?: string | null;
};

/**
 * Approves an emploc deletion request via RPC.
 * `p_reopen_vacancy` controls whether the linked vacancy slot is reopened
 * (defaults true for Backout, false for Duplicate Record).
 */
export async function approveEmplocDeletion(
  params: ApproveEmplocDeletionParams
): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("fn_approve_emploc_deletion_request", {
    p_request_id: params.requestId,
    p_reviewer_remarks: params.notes?.trim() || null,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}

export type RejectEmplocDeletionParams = {
  requestId: string;
  rejectionReason: string;
};

/**
 * Rejects an emploc deletion request via RPC.
 * `p_reviewer_remarks` is required — validated client-side before calling.
 */
export async function rejectEmplocDeletion(
  params: RejectEmplocDeletionParams
): Promise<void> {
  const trimmedReason = params.rejectionReason.trim();
  if (!trimmedReason) {
    throw new HrEmplocDataError("invalid_state", "A rejection reason is required.");
  }

  const supabase = createClient();
  const { error } = await supabase.rpc("fn_reject_emploc_deletion_request", {
    p_request_id: params.requestId,
    p_reviewer_remarks: trimmedReason,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}


export function useEmplocDeletionRequests() {
  return useQuery({
    queryKey: ["emploc_deletion_requests"],
    queryFn: () => fetchEmplocDeletionRequests(),
  });
}

export function useApproveEmplocDeletion() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ApproveEmplocDeletionParams) => approveEmplocDeletion(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["emploc_deletion_requests"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
    },
  });
}

export function useRejectEmplocDeletion() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RejectEmplocDeletionParams) => rejectEmplocDeletion(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["emploc_deletion_requests"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
    },
  });
}
