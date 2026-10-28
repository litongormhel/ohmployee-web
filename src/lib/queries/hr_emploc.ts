import type { PostgrestError } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { formatPersonName } from "@/lib/utils/formatName";

export type HrEmplocQueue =
  | "pending"
  | "correction"
  | "review"
  | "deployed"
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
  canSubmitCorrection: boolean;   // For HRCO / Super Admin in Correction
  canApproveCorrection: boolean;  // For HR Personnel / Super Admin in Review
  canRevertCorrection: boolean;   // For HR Personnel / Super Admin in Review
  canEditEmploc: boolean;         // For Super Admin, Data Team, and HR Personnel
  canRevertToPending: boolean;    // For Super Admin, Data Team, and HR Personnel
  raw: Record<string, boolean>;
};

export type HrEmplocDeficiencyIssue = {
  code: string;
  label: string;
  comment: string | null;
};

export type HrEmplocListItem = {
  id: string;
  applicantName: string;
  vcode: string;
  accountId: string | null;
  accountName: string | null;
  groupId: string | null;
  groupName: string | null;
  storeId: string | null;
  storeName: string | null;
  positionTitle: string | null;
  hrcoName: string | null;
  hrStatus: string;
  deploymentStatus: string;
  employeeNo: string | null;
  assignmentType: string | null;
  coveredStoresCount: number;
  deficiencySummary: string | null;
  deficiencyIssues: HrEmplocDeficiencyIssue[];
  correctionReason: Record<string, unknown> | Array<unknown> | null;
  requestedByName: string | null;
  hrcoRemarks: string | null;
  notes: string | null;
  remarks: string | null;
  attachmentUrl: string | null;
  attachmentFileName: string | null;
  attachmentMetadata: Record<string, unknown> | null;
  hiredDate: string | null;
  dateRequested: string | null;
  slaBreached: boolean;
  slaElapsedDays: number;
  rowCapabilities: HrEmplocRowCapabilities;
  /** True when an active (Pending) deletion request exists for this record. */
  isPendingDeletion: boolean;
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
  accountId?: string | null;
  groupName?: string | null;
  groupId?: string | null;
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
  requestedByName: string | null;
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
  deployed: number;         // status = 'Moved to Plantilla' / Deployed
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

const DEFAULT_PAGE_SIZE = 10;
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
    canReviewCorrection: raw.can_review_correction === true || raw.can_approve_correction === true,
    canAssignEmployeeNo: raw.can_assign_employee_no === true,
    canMoveToPlantilla: raw.can_move_to_plantilla === true,
    canRequestDeletion: raw.can_request_deletion === true,
    canReviewDeletion: raw.can_review_deletion === true,
    canSubmitCorrection: raw.can_submit_correction === true,
    canApproveCorrection: raw.can_approve_correction === true || raw.can_review_correction === true,
    canRevertCorrection: raw.can_revert_correction === true,
    canEditEmploc: raw.can_edit_emploc === true,
    canRevertToPending: raw.can_revert_to_pending === true,
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

  if (error.code === "P0001" || error.code === "22023") {
    return "invalid_state";
  }

  return "retryable";
}

function throwHrEmplocError(error: PostgrestError): never {
  const message = [error.message, error.details, error.hint]
    .filter(Boolean)
    .join(" — ") || "Database error";
  throw new HrEmplocDataError(getErrorKind(error), message);
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

  const caps = asObject(row.row_capabilities ?? row.rowCapabilities);
  const defSummary = asObject(row.deficiency_summary ?? row.deficiencySummary);
  const rawIssues = Array.isArray(defSummary.issues) ? defSummary.issues : [];
  const deficiencyIssues: HrEmplocDeficiencyIssue[] = rawIssues.map((item) => {
    const obj = asObject(item);
    return {
      code: asString(obj.code) ?? "OTHER",
      label: asString(obj.label) ?? asString(obj.code) ?? "Other",
      comment: asString(obj.comment) ?? null,
    };
  });

  const requestedByName = asString(
    row.requested_by_name ??
    row.requestedByName ??
    row.hr_reviewed_by ??
    row.hrReviewedBy ??
    caps.requested_by_name ??
    caps.requestedByName ??
    caps.hr_reviewed_by
  );

  const hrcoRemarks = asString(
    caps.remarks ??
    row.remarks ??
    row.hrco_remarks ??
    row.hrcoRemarks ??
    row.ops_remarks ??
    row.opsRemarks ??
    row.notes ??
    caps.hrco_remarks ??
    caps.notes ??
    caps.ops_remarks ??
    caps.hr_remarks
  );

  const attachmentUrl = asString(
    row.attachment_url ??
    row.attachmentUrl ??
    caps.attachment_url ??
    caps.attachmentUrl
  );

  const attachmentFileName = asString(
    row.attachment_file_name ??
    row.attachmentFileName ??
    caps.attachment_file_name ??
    caps.attachmentFileName
  );

  const attachmentMetadata = (row.attachment_metadata ?? row.attachmentMetadata ?? caps.attachment_metadata ?? caps.attachmentMetadata) as Record<string, unknown> | null;

  return {
    id,
    applicantName: formatPersonName(null, null, null, asString(row.applicant_name ?? row.applicantName) ?? "Anonymous"),
    vcode: asString(row.vcode) ?? "Uncoded",
    accountId: asString(row.account_id ?? row.accountId),
    accountName: asString(row.account_name ?? row.accountName),
    groupId: asString(row.group_id ?? row.groupId),
    groupName: asString(row.group_name ?? row.groupName),
    storeId: asString(row.store_id ?? row.storeId),
    storeName: asString(row.store_name ?? row.storeName),
    positionTitle: asString(row.position_title ?? row.positionTitle),
    hrcoName: asString(
      row.hrco_name ??
      row.hrcoName ??
      caps.hrco_name ??
      caps.hrcoName
    ),
    hrStatus: asString(row.hr_status ?? row.hrStatus) ?? "Pending",
    deploymentStatus: asString(row.deployment_status ?? row.deploymentStatus ?? row.status) ?? "Pending Emploc",
    employeeNo: asString(row.employee_no ?? row.employeeNo),
    assignmentType: asString(row.assignment_type ?? row.assignmentType),
    coveredStoresCount: asCount(row.covered_stores_count ?? row.coveredStoresCount),
    deficiencySummary: summarizeDeficiency(row.deficiency_summary ?? row.deficiencySummary),
    deficiencyIssues,
    correctionReason: (row.correction_reason ?? row.correctionReason ?? caps.correction_reason) as Record<string, unknown> | Array<unknown> | null,
    requestedByName,
    hrcoRemarks,
    notes: hrcoRemarks,
    remarks: hrcoRemarks,
    attachmentUrl,
    attachmentFileName,
    attachmentMetadata,
    hiredDate: asString(row.hired_date ?? row.hiredDate),
    dateRequested: asString(row.date_requested ?? row.dateRequested),
    slaBreached: asBoolean(row.sla_breached ?? row.slaBreached),
    slaElapsedDays: asCount(row.aging_days ?? row.sla_elapsed_days ?? row.slaElapsedDays),
    rowCapabilities: normalizeCapabilities(caps),
    isPendingDeletion: asBoolean(row.is_pending_deletion ?? row.isPendingDeletion),
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

  // The RPC returns the latest deletion request regardless of status; only a Pending one is active.
  const latestDeletionRequest = normalizeDeletionRequest(row.deletion_request);
  const activeDeletionRequest =
    latestDeletionRequest && latestDeletionRequest.status.trim().toLowerCase() === "pending"
      ? latestDeletionRequest
      : null;

  return {
    id,
    applicantName: formatPersonName(null, null, null, asString(row.applicant_name ?? row.applicantName) ?? "Anonymous"),
    vcode: asString(row.vcode) ?? "Uncoded",
    accountName: asString(row.account_name ?? row.accountName) ?? null,
    accountId: asString(row.account_id ?? row.accountId) ?? null,
    groupName: asString(row.group_name ?? row.groupName) ?? null,
    groupId: asString(row.group_id ?? row.groupId) ?? null,
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
    requestedByName: asString(row.hr_reviewed_by ?? row.hrReviewedBy ?? row.requested_by_name ?? row.requestedByName) ?? null,
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
  const deployed = asCount(row.deployed_count ?? row.deployed ?? row.ready_count ?? row.ready);

  return {
    pending,
    correction,
    review,
    ready,
    deployed,
    totalPending: pending,
    actionNeeded: correction,
    readyToDeploy: ready,
    pendingDeletion: asCount(row.pending_deletion_count ?? row.pending_deletion ?? row.pendingDeletion),
    slaBreaches: asCount(row.sla_breached_count ?? row.sla_breaches ?? row.slaBreaches),
  };
}

export async function getWebHrEmplocSummary(
  params: Partial<Pick<HrEmplocListParams, "queue" | "accountId" | "groupId" | "search">> = {}
) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_hr_emploc_summary", {
    p_queue: null,
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
  deficiencies: Array<{ code: string; comment?: string }> | Record<string, string>;
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
  const deficienciesArray = Array.isArray(params.deficiencies)
    ? params.deficiencies.map((d) => ({
        code: String(d.code),
        comment: d.comment ? String(d.comment).trim() : "",
      }))
    : Object.entries(params.deficiencies).map(([code, comment]) => ({
        code,
        comment: typeof comment === "string" ? comment.trim() : "",
      }));

  const { data, error } = await supabase.rpc("tag_web_hr_emploc_deficiency", {
    p_hr_emploc_id: params.hrEmplocId,
    p_deficiencies: deficienciesArray,
    p_remarks: params.remarks ?? null,
  });

  if (error) {
    throwHrEmplocError(error);
  }

  const row = asObject(data);
  return {
    ok: asBoolean(row.ok) || row.status === "ok",
    hrEmplocId: asString(row.hr_emploc_id) ?? params.hrEmplocId,
    newHrStatus: asString(row.new_hr_status ?? row.hr_status) ?? "For Correction",
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

/**
 * Checks whether the tagged deficiency items consist exclusively of benefits-related issues:
 * SSS, PhilHealth (PH), and/or Pag-IBIG.
 * Matches Mobile app parity rule: When benefits-only, document upload is hidden.
 */
export function isBenefitsOnlyCorrection(
  correctionReason: unknown,
  deficiencyIssues?: HrEmplocDeficiencyIssue[] | null
): boolean {
  const codes: string[] = [];

  if (Array.isArray(deficiencyIssues) && deficiencyIssues.length > 0) {
    for (const issue of deficiencyIssues) {
      if (issue.code) codes.push(issue.code.toUpperCase().trim());
      else if (issue.label) codes.push(issue.label.toUpperCase().trim());
    }
  } else if (Array.isArray(correctionReason)) {
    for (const item of correctionReason) {
      if (typeof item === "string") {
        codes.push(item.toUpperCase().trim());
      } else if (item && typeof item === "object") {
        const c = (item as Record<string, unknown>).code ?? (item as Record<string, unknown>).type;
        if (typeof c === "string") codes.push(c.toUpperCase().trim());
      }
    }
  } else if (correctionReason && typeof correctionReason === "object") {
    const c = (correctionReason as Record<string, unknown>).type ?? (correctionReason as Record<string, unknown>).code;
    if (typeof c === "string") codes.push(c.toUpperCase().trim());
  }

  if (codes.length === 0) {
    return false;
  }

  const benefitsCodes = new Set([
    "INVALID_SSS",
    "INVALID_PHILHEALTH",
    "INVALID_PAGIBIG",
    "SSS",
    "PHILHEALTH",
    "PAGIBIG",
    "PAG-IBIG",
    "PH",
  ]);

  return codes.every((code) => {
    if (benefitsCodes.has(code)) return true;
    const normalized = code.replace(/[^A-Z]/g, "");
    return (
      normalized.includes("SSS") ||
      normalized.includes("PHILHEALTH") ||
      normalized.includes("PAGIBIG")
    );
  });
}

/**
 * Uploads a correction compliance attachment to the private 'hr-corrections' Supabase storage bucket
 * and registers metadata in public.hr_emploc_correction_attachments.
 */
export async function uploadCorrectionAttachment(params: {
  hrEmplocId: string;
  file: File;
}): Promise<{ id: string; storagePath: string; fileName: string }> {
  const allowed = ["image/jpeg", "image/png", "application/pdf"];
  if (!allowed.includes(params.file.type)) {
    throw new HrEmplocDataError(
      "invalid_state",
      `Unsupported file type: ${params.file.type}. Allowed formats are JPG, PNG, and PDF.`
    );
  }
  if (params.file.size > 5 * 1024 * 1024) {
    throw new HrEmplocDataError(
      "invalid_state",
      `File exceeds 5 MB limit: ${params.file.name}`
    );
  }

  const supabase = createClient();
  const ext = params.file.name.split(".").pop() || "jpg";
  const uniqueId =
    typeof crypto !== "undefined" && crypto.randomUUID
      ? crypto.randomUUID()
      : Math.random().toString(36).substring(2);
  const objectPath = `${uniqueId}.${ext}`;
  const fullStoragePath = `hr-corrections/${objectPath}`;

  const { error: uploadError } = await supabase.storage
    .from("hr-corrections")
    .upload(objectPath, params.file, {
      contentType: params.file.type,
      upsert: false,
    });

  if (uploadError) {
    throw new HrEmplocDataError(
      "retryable",
      `Storage upload failed: ${uploadError.message}`
    );
  }

  const { data: row, error: insertError } = await supabase
    .from("hr_emploc_correction_attachments")
    .insert({
      hr_emploc_id: params.hrEmplocId,
      storage_path: fullStoragePath,
      original_filename: params.file.name,
      mime_type: params.file.type,
      size_bytes: params.file.size,
    })
    .select("id, storage_path, original_filename")
    .single();

  if (insertError) {
    try {
      await supabase.storage.from("hr-corrections").remove([objectPath]);
    } catch {
      // Ignored orphan cleanup
    }
    throwHrEmplocError(insertError);
  }

  return {
    id: row.id,
    storagePath: row.storage_path,
    fileName: row.original_filename,
  };
}

/**
 * Creates a 1-hour signed URL for an attachment in the private 'hr-corrections' bucket.
 */
export async function getCorrectionAttachmentSignedUrl(
  storagePath: string
): Promise<string> {
  const supabase = createClient();
  const objectPath = storagePath.startsWith("hr-corrections/")
    ? storagePath.replace("hr-corrections/", "")
    : storagePath;

  const { data, error } = await supabase.storage
    .from("hr-corrections")
    .createSignedUrl(objectPath, 3600, {
      download: true,
    });

  if (error || !data?.signedUrl) {
    throw new HrEmplocDataError(
      "retryable",
      `Failed to generate signed download link: ${error?.message || "File unavailable"}`
    );
  }

  return data.signedUrl;
}

/**
 * Submits HRCO correction notes (and uploads any provided attachments),
 * transitioning the record from 'For Correction' to 'For Review'.
 */
export async function submitHrcoCorrection(params: {
  hrEmplocId: string;
  hrcoNotes?: string | null;
  attachments?: File[];
}): Promise<void> {
  const trimmedNotes = params.hrcoNotes?.trim() || null;

  if (params.attachments && params.attachments.length > 0) {
    for (const file of params.attachments) {
      await uploadCorrectionAttachment({
        hrEmplocId: params.hrEmplocId,
        file,
      });
    }
  }

  const supabase = createClient();
  const { error } = await supabase.rpc("submit_hrco_correction_update", {
    p_correction_request_id: params.hrEmplocId,
    p_hrco_notes: trimmedNotes,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}

/**
 * Approves a record currently in Review, resolving deficiencies and moving it to Complete/Ready.
 */
export async function approveHrEmplocReview(params: {
  hrEmplocId: string;
  resolvedKeys?: string[];
  remarks?: string;
}): Promise<void> {
  const supabase = createClient();

  const { error } = await supabase.rpc("review_web_hr_emploc_correction", {
    p_hr_emploc_id: params.hrEmplocId,
    p_decision: "approve",
    p_resolved_keys: params.resolvedKeys ?? [],
    p_remarks: params.remarks?.trim() || null,
  });

  if (error) {
    // Fallback: try approve_correction_request if review_web_hr_emploc_correction errored on resolution keys
    const { error: approveError } = await supabase.rpc("approve_correction_request", {
      p_correction_request_id: params.hrEmplocId,
      p_approved_by: null,
    });
    if (approveError) {
      throwHrEmplocError(error);
    }
  }
}

/**
 * Reverts a record currently in Review back to Correction with HR remarks.
 */
export async function revertHrEmplocReview(params: {
  hrEmplocId: string;
  remarks: string;
}): Promise<void> {
  const trimmed = params.remarks.trim();
  if (!trimmed) {
    throw new HrEmplocDataError(
      "invalid_state",
      "HR remarks explaining what must be corrected are required to revert."
    );
  }

  const supabase = createClient();

  // Prefer reject_correction_request (exact Mobile counterpart)
  const { error: rejectError } = await supabase.rpc("reject_correction_request", {
    p_correction_request_id: params.hrEmplocId,
    p_hr_remarks: trimmed,
  });

  if (rejectError) {
    // Fallback to review_web_hr_emploc_correction return
    const { error: returnError } = await supabase.rpc("review_web_hr_emploc_correction", {
      p_hr_emploc_id: params.hrEmplocId,
      p_decision: "return",
      p_resolved_keys: [],
      p_remarks: trimmed,
    });
    if (returnError) {
      throwHrEmplocError(returnError);
    }
  }
}

export async function getWebHrEmplocDetail(hrEmplocId: string): Promise<HrEmplocDetailItem | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_hr_emploc_detail", {
    p_hr_emploc_id: hrEmplocId,
  });

  if (error) {
    throwHrEmplocError(error);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }

  const normalized = normalizeDetailRow(asObject(row));
  if (!normalized) {
    return null;
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
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
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
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
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

// ─── Ecosystem Uniqueness, Edit Emploc & Revert to Pending ──────────────────

export type EcosystemUniquenessResult = {
  isUnique: boolean;
  message?: string;
  existingName?: string;
  existingModule?: string;
};

export async function checkEcosystemEmployeeIdUnique(
  employeeId: string,
  excludeHrEmplocId?: string | null
): Promise<EcosystemUniquenessResult> {
  const cleanId = employeeId.trim();
  if (!cleanId) {
    return { isUnique: false, message: "Employee ID is required." };
  }

  const supabase = createClient();

  // 1. Try SECURITY DEFINER RPC first
  try {
    const { data, error } = await supabase.rpc("check_ecosystem_employee_id_unique", {
      p_employee_id: cleanId,
      p_exclude_hr_emploc_id: excludeHrEmplocId || null,
    });

    if (!error && data && typeof data === "object") {
      const obj = data as Record<string, unknown>;
      const isUnique = obj.is_unique === true;
      if (!isUnique) {
        const existingName = asString(obj.existing_name) ?? "Existing Employee";
        const existingModule = asString(obj.existing_module) ?? "System";
        const message = asString(obj.message) ?? `Employee ID ${cleanId} is already assigned to ${existingName} (${existingModule}). Duplicate Emploc numbers are not allowed.`;
        return { isUnique: false, message, existingName, existingModule };
      }
      return { isUnique: true };
    }
  } catch {
    // Continue to client query fallback
  }

  // 2. Client-side fallback check
  // Check hr_emploc
  let emplocQuery = supabase
    .from("hr_emploc")
    .select("applicant_name, employee_no, emploc_no")
    .or(`employee_no.ilike.${cleanId},emploc_no.ilike.${cleanId}`)
    .is("deleted_at", null)
    .neq("status", "Backout");

  if (excludeHrEmplocId) {
    emplocQuery = emplocQuery.neq("id", excludeHrEmplocId);
  }

  const { data: emplocData } = await emplocQuery.limit(1);
  if (emplocData && emplocData.length > 0) {
    const name = asString(emplocData[0].applicant_name) ?? "Existing Candidate";
    return {
      isUnique: false,
      message: `Employee ID ${cleanId} is already assigned to ${name} (HR Emploc). Duplicate Emploc numbers are not allowed.`,
      existingName: name,
      existingModule: "HR Emploc",
    };
  }

  // Check plantilla
  let plantillaQuery = supabase
    .from("plantilla")
    .select("employee_name, employee_name_snapshot, employee_no")
    .or(`employee_no.ilike.${cleanId},emploc_no.ilike.${cleanId}`)
    .or("is_deleted.is.null,is_deleted.eq.false");

  if (excludeHrEmplocId) {
    plantillaQuery = plantillaQuery.or(`hr_emploc_id.is.null,hr_emploc_id.neq.${excludeHrEmplocId}`);
  }

  const { data: plantillaData } = await plantillaQuery.limit(1);
  if (plantillaData && plantillaData.length > 0) {
    const p = plantillaData[0];
    const name = asString(p.employee_name_snapshot ?? p.employee_name) ?? "Existing Employee";
    return {
      isUnique: false,
      message: `Employee ID ${cleanId} is already assigned to ${name} (Plantilla). Duplicate Emploc numbers are not allowed.`,
      existingName: name,
      existingModule: "Plantilla",
    };
  }

  // Check users_profile
  const { data: usersData } = await supabase
    .from("users_profile")
    .select("full_name")
    .is("archived_at", null)
    .not("auth_user_id", "is", null)
    .or(`metadata->>employee_id.ilike.${cleanId},metadata->>employee_no.ilike.${cleanId}`)
    .limit(1);

  if (usersData && usersData.length > 0) {
    const name = asString(usersData[0].full_name) ?? "Staff Member";
    return {
      isUnique: false,
      message: `Employee ID ${cleanId} is already assigned to ${name} (User Management). Duplicate Emploc numbers are not allowed.`,
      existingName: name,
      existingModule: "User Management",
    };
  }

  return { isUnique: true };
}

export type UpdateDeployedEmplocParams = {
  hrEmplocId: string;
  newEmployeeNo: string;
  reason: string;
};

export async function updateDeployedEmployeeId(params: UpdateDeployedEmplocParams): Promise<void> {
  const cleanId = params.newEmployeeNo.trim();
  const reason = params.reason.trim();
  if (!cleanId) throw new HrEmplocDataError("invalid_state", "New Employee ID is required.");
  if (!reason) throw new HrEmplocDataError("invalid_state", "Reason for edit is required.");

  const supabase = createClient();

  const { error } = await supabase.rpc("update_deployed_employee_id", {
    p_hr_emploc_id: params.hrEmplocId,
    p_new_employee_no: cleanId,
    p_reason: reason,
  });

  if (error) {
    if (error.code === "42883") {
      const { error: emplocErr } = await supabase
        .from("hr_emploc")
        .update({
          employee_no: cleanId,
          emploc_no: cleanId,
          updated_at: new Date().toISOString(),
        })
        .eq("id", params.hrEmplocId);
      if (emplocErr) throwHrEmplocError(emplocErr);

      await supabase
        .from("plantilla")
        .update({
          employee_no: cleanId,
          emploc_no: cleanId,
          updated_at: new Date().toISOString(),
        })
        .eq("hr_emploc_id", params.hrEmplocId);

      return;
    }
    throwHrEmplocError(error);
  }
}

export function useUpdateDeployedEmployeeId() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateDeployedEmplocParams) => updateDeployedEmployeeId(params),
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

export type RevertHrEmplocParams = {
  hrEmplocId: string;
  reason: string;
  vcode?: string | null;
};

export async function revertHrEmplocToPending(params: RevertHrEmplocParams): Promise<void> {
  const reason = params.reason.trim();
  if (!reason) throw new HrEmplocDataError("invalid_state", "Reason for revert is required.");

  const supabase = createClient();

  const { error } = await supabase.rpc("revert_hr_emploc_to_pending", {
    p_hr_emploc_id: params.hrEmplocId,
    p_reason: reason,
  });

  if (error) {
    if (error.code === "42883") {
      await supabase
        .from("plantilla")
        .update({
          is_deleted: true,
          deleted_at: new Date().toISOString(),
          status: "Separated",
        })
        .eq("hr_emploc_id", params.hrEmplocId);

      const { error: emplocErr } = await supabase
        .from("hr_emploc")
        .update({
          employee_no: null,
          emploc_no: null,
          status: "Pending Emploc",
          hr_status: "Pending",
          moved_to_plantilla_at: null,
          moved_to_plantilla_by: null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", params.hrEmplocId);

      if (emplocErr) throwHrEmplocError(emplocErr);

      if (params.vcode?.trim()) {
        await supabase
          .from("vacancies")
          .update({
            status: "Open",
            updated_at: new Date().toISOString(),
          })
          .eq("vcode", params.vcode.trim())
          .eq("status", "Filled");
      }
      return;
    }
    throwHrEmplocError(error);
  }
}

export function useRevertHrEmplocToPending() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RevertHrEmplocParams) => revertHrEmplocToPending(params),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail", variables.hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail", variables.hrEmplocId] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
    },
  });
}

export async function notifyAllHrcosForCorrection(params: {
  hrEmplocId: string;
  applicantName: string;
  vcode: string;
  accountId?: string | null;
  groupId?: string | null;
  remarks?: string | null;
}): Promise<void> {
  const supabase = createClient();
  try {
    const { data: hrcoList } = await supabase
      .from("user_scopes")
      .select("user_id, users_profile!inner(id, auth_user_id, is_active, archived_at, roles!inner(role_name))")
      .or(
        [
          params.accountId ? `account_id.eq.${params.accountId}` : null,
          params.groupId ? `group_id.eq.${params.groupId}` : null,
        ]
          .filter(Boolean)
          .join(",")
      );

    const recipientAuthUserIds = new Set<string>();
    if (Array.isArray(hrcoList)) {
      for (const item of hrcoList) {
        const profile = item.users_profile as unknown as Record<string, unknown> | null;
        const role = profile?.roles as unknown as Record<string, unknown> | null;
        if (
          role?.role_name === "HRCO" &&
          profile?.is_active !== false &&
          !profile?.archived_at &&
          profile?.auth_user_id
        ) {
          recipientAuthUserIds.add(String(profile.auth_user_id));
        }
      }
    }

    if (recipientAuthUserIds.size === 0) return;

    const notifs = Array.from(recipientAuthUserIds).map((authId) => ({
      recipient_user_id: authId,
      recipient_role: "HRCO",
      title: "Record Flagged for Correction",
      message: `${params.applicantName} (${params.vcode}) has been flagged for correction. Remarks: ${params.remarks || "Deficiencies tagged"}`,
      reference_type: "hr_emploc",
      reference_id: params.hrEmplocId,
      deep_link_route: `/hr-emploc?queue=correction&id=${params.hrEmplocId}`,
      notification_type: "alert",
      event_type: "hr_emploc_correction_tagged",
    }));

    await supabase.from("notifications").insert(notifs);
  } catch (err) {
    console.warn("Failed to notify HRCOs for correction:", err);
  }
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
  /** Current status */
  status: string;
  /** Reason / remarks from requester */
  reason: string | null;
  /** Original emploc ID when deletion_type = 'Duplicate Record' */
  originalEmplocId: string | null;
  reviewedBy: string | null;
  reviewedAt: string | null;
  reviewerRemarks: string | null;
  groupName?: string | null;
  accountName?: string | null;
};

/**
 * Fetches HR Emploc deletion requests joined with hr_emploc data, filtered by status tab.
 */
export async function fetchEmplocDeletionRequests(
  tab: "pending" | "approved" | "rejected" = "pending",
  pagination?: { page?: number; limit?: number }
): Promise<EmplocDeletionRequestItem[]> {
  const supabase = createClient();

  let query = supabase
    .from("hr_emploc_deletion_requests")
    .select(`
      id,
      hr_emploc_id,
      applicant_name,
      vcode,
      reason,
      deletion_type,
      original_emploc_id,
      status,
      requested_by,
      created_at,
      snapshot_store,
      snapshot_position,
      reviewed_by,
      reviewed_at,
      reviewer_remarks,
      hr_emploc:hr_emploc_id (
        applicant_name,
        employee_no,
        store_name,
        position,
        vcode,
        account_name
      )
    `);

  if (tab === "pending") {
    query = query.ilike("status", "pending");
  } else if (tab === "approved") {
    query = query.or("status.ilike.approved,status.ilike.completed");
  } else if (tab === "rejected") {
    query = query.or("status.ilike.rejected,status.ilike.withdrawn");
  }

  query = query
    .or("is_archived.is.null,is_archived.eq.false")
    .is("suppressed_by_batch_id", null);

  let orderedQuery = query.order("created_at", { ascending: false });
  if (pagination?.page && pagination?.limit) {
    const page = Math.max(1, Math.trunc(pagination.page));
    const limit = Math.max(1, Math.trunc(pagination.limit));
    const offset = (page - 1) * limit;
    orderedQuery = orderedQuery.range(offset, offset + limit - 1);
  }

  const { data, error } = await orderedQuery;

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
      applicantName: asString(emploc.applicant_name) ?? asString(row.applicant_name) ?? "Anonymous",
      employeeNo: asString(emploc.employee_no),
      storeName: asString(emploc.store_name) ?? asString(row.snapshot_store),
      positionTitle: asString(emploc.position) ?? asString(row.snapshot_position),
      vcode: asString(emploc.vcode) ?? asString(row.vcode) ?? "Uncoded",
      deletionType: asString(row.deletion_type) ?? "Backout",
      requestedByName: asString(row.requested_by),
      requestedAt: asString(row.created_at),
      status: asString(row.status) ?? "Pending",
      reason: asString(row.reason),
      originalEmplocId: asString(row.original_emploc_id),
      reviewedBy: asString(row.reviewed_by),
      reviewedAt: asString(row.reviewed_at),
      reviewerRemarks: asString(row.reviewer_remarks),
      accountName: asString(emploc.account_name) ?? null,
      groupName: null,
    };
  });
}

export async function fetchEmplocDeletionCounts(): Promise<{
  pending: number;
  approved: number;
  rejected: number;
}> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("hr_emploc_deletion_requests")
    .select("status")
    .or("is_archived.is.null,is_archived.eq.false")
    .is("suppressed_by_batch_id", null);
  if (error) {
    console.error("[fetchEmplocDeletionCounts] query failed:", error.code, error.message);
    throwHrEmplocError(error);
  }
  if (!data) return { pending: 0, approved: 0, rejected: 0 };
  let pending = 0;
  let approved = 0;
  let rejected = 0;
  for (const row of data) {
    const s = (asString(row.status) || "").toLowerCase();
    if (s === "pending") pending++;
    else if (s === "approved" || s === "completed") approved++;
    else if (s === "rejected" || s === "withdrawn") rejected++;
  }
  return { pending, approved, rejected };
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


export function useEmplocDeletionRequests(
  tab: "pending" | "approved" | "rejected" = "pending",
  pagination?: { page?: number; limit?: number }
) {
  return useQuery({
    queryKey: ["emploc_deletion_requests", tab, pagination],
    queryFn: () => fetchEmplocDeletionRequests(tab, pagination),
  });
}

export function useEmplocDeletionCounts() {
  return useQuery({
    queryKey: ["emploc_deletion_counts"],
    queryFn: () => fetchEmplocDeletionCounts(),
    retry: 1,
  });
}

export function useApproveEmplocDeletion() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ApproveEmplocDeletionParams) => approveEmplocDeletion(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["emploc_deletion_requests"] });
      queryClient.invalidateQueries({ queryKey: ["emploc_deletion_counts"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emplocs"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-list"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hr_emploc_detail"] });
      queryClient.invalidateQueries({ queryKey: ["hr-emploc-detail"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
    },
  });
}

export function useRejectEmplocDeletion() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RejectEmplocDeletionParams) => rejectEmplocDeletion(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["emploc_deletion_requests"] });
      queryClient.invalidateQueries({ queryKey: ["emploc_deletion_counts"] });
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

// ─────────────────────────────────────────────────────────────────────────────
// Unpaginated Export Utilities
// ─────────────────────────────────────────────────────────────────────────────

export interface HrEmplocExportFilters {
  search?: string;
  accountId?: string;
  groupId?: string;
}

export interface HrEmplocExportResult {
  csv: string;
  rowCount: number;
  filename: string;
  scopeTitle: string;
}

function escapeCsvValue(val: unknown): string {
  if (val === null || val === undefined) return '""';
  const str = String(val).replace(/"/g, '""');
  return `"${str}"`;
}

export const HR_EMPLOC_EXPORT_HEADERS = [
  "Group",
  "Account",
  "Store",
  "VCode",
  "Applicant",
  "Employee ID",
  "Position",
  "HRCO",
  "SLA (Days)",
  "HR Status",
  "Deployment Status",
  "Hired Date",
  "Date Requested",
] as const;

export async function fetchHrEmplocsForExport(
  scope: "current_view" | "masterlist",
  queue: HrEmplocQueue,
  filters: HrEmplocExportFilters = {}
): Promise<HrEmplocExportResult> {
  const supabase = createClient();
  const PAGE_BATCH = 200;
  let offset = 0;
  const allRows: HrEmplocListItem[] = [];

  const queueParam = scope === "current_view" ? queue : null;

  while (true) {
    const { data, error } = await supabase.rpc("list_web_hr_emplocs", {
      p_queue: queueParam,
      p_status: null,
      p_deficiency: null,
      p_sla_filter: null,
      p_account_id: filters.accountId || null,
      p_group_id: filters.groupId || null,
      p_search: filters.search?.trim() || null,
      p_limit: PAGE_BATCH,
      p_offset: offset,
      p_sort_by: "created_at",
      p_sort_dir: "desc",
    });

    if (error) {
      throwHrEmplocError(error);
    }

    const batch = (Array.isArray(data) ? data : [])
      .map((row) => normalizeListRow(asObject(row)))
      .filter((row): row is HrEmplocListItem => row !== null);

    allRows.push(...batch);

    if (batch.length < PAGE_BATCH) {
      break;
    }

    offset += PAGE_BATCH;
  }

  const now = new Date();
  const timestamp = [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, "0"),
    String(now.getDate()).padStart(2, "0"),
    "_",
    String(now.getHours()).padStart(2, "0"),
    String(now.getMinutes()).padStart(2, "0"),
  ].join("");

  const scopeTitle =
    scope === "current_view"
      ? queue.charAt(0).toUpperCase() + queue.slice(1)
      : "Masterlist";

  const filename = `OHMployee_Emploc_${scopeTitle}_${timestamp}.csv`;

  const headerLine = HR_EMPLOC_EXPORT_HEADERS.map(escapeCsvValue).join(",");
  const dataLines = allRows.map((r) =>
    [
      escapeCsvValue(r.groupName || "--"),
      escapeCsvValue(r.accountName || "--"),
      escapeCsvValue(r.storeName || "--"),
      escapeCsvValue(r.vcode),
      escapeCsvValue(r.applicantName),
      escapeCsvValue(r.employeeNo || "--"),
      escapeCsvValue(r.positionTitle || "--"),
      escapeCsvValue(r.hrcoName || "--"),
      escapeCsvValue(r.slaElapsedDays),
      escapeCsvValue(r.hrStatus),
      escapeCsvValue(r.deploymentStatus),
      escapeCsvValue(r.hiredDate || "--"),
      escapeCsvValue(r.dateRequested || "--"),
    ].join(",")
  );

  // UTF-8 Excel BOM encoding
  const csv = "\uFEFF" + [headerLine, ...dataLines].join("\r\n");

  return {
    csv,
    rowCount: allRows.length,
    filename,
    scopeTitle,
  };
}

export function downloadCsv(csv: string, filename: string): void {
  if (typeof window === "undefined") return;
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.setAttribute("download", filename);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

