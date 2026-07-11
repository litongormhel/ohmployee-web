import type { PostgrestError } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

export type HrEmplocQueue = "pending" | "deficiency" | "complete" | "deletion_pending" | "all";

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
  totalPending: number;     // hr_status IN ('Pending', 'For Review')
  actionNeeded: number;     // hr_status = 'For Correction'
  readyToDeploy: number;    // hr_status = 'Complete' AND employee_no IS NULL
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

  return {
    totalPending: asCount(row.pending_count ?? row.total_pending ?? row.totalPending ?? row.total_processing),
    actionNeeded: asCount(row.correction_count ?? row.action_needed ?? row.actionNeeded ?? row.action_needed_count),
    readyToDeploy: asCount(row.ready_count ?? row.ready_to_deploy ?? row.readyToDeploy ?? row.ready_to_deploy_count),
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
