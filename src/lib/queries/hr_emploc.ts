import { createClient } from "@/lib/supabase/client";
import { formatPersonName } from "@/lib/utils/formatName";
import { parseHrEmplocError, type ParsedHrEmplocError } from "@/lib/utils/hr_emploc_errors";

export type HrEmplocQueue =
  | "pending"
  | "for_emploc"
  | "correction"
  | "review"
  | "deployed"
  | "ready"
  | "deficiency"
  | "complete"
  | "deletion_pending"
  | "all";

export interface HrEmplocAttachment {
  id: string;
  storage_path: string;
  object_path: string;
  file_name: string;
  file_size?: number;
  file_type?: string;
  stage: "initial_requirements" | "correction";
  uploaded_at: string | null;
  uploaded_by?: string | null;
  can_remove?: boolean;
}

export type HrEmplocRowCapabilities = {
  // DB-projected capability keys (migration 84)
  can_upload_docs: boolean;
  can_submit_requirements: boolean;
  can_assign_employee_no: boolean;
  can_tag_deficiency: boolean;
  can_submit_correction: boolean;
  can_review_approve: boolean;
  can_review_return: boolean;
  can_revert_to_pending: boolean;
  can_edit_emploc_no: boolean;
  can_request_deletion: boolean;
  can_view_docs: boolean;
  can_edit_profile?: boolean;

  // CamelCase backward compatibility accessors
  canUploadDocs: boolean;
  canSubmitRequirements: boolean;
  canAssignEmployeeNo: boolean;
  canTagDeficiency: boolean;
  canSubmitCorrection: boolean;
  canReviewApprove: boolean;
  canReviewReturn: boolean;
  canRevertToPending: boolean;
  canEditEmplocNo: boolean;
  canRequestDeletion: boolean;
  canViewDocs: boolean;
  canViewDetail: boolean;
  canReviewCorrection: boolean;
  canMoveToPlantilla: boolean;
  canReviewDeletion: boolean;
  canApproveCorrection: boolean;
  canRevertCorrection: boolean;
  canEditEmploc: boolean;
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
  attachments: HrEmplocAttachment[];
  docCount: number;
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
  attachments: HrEmplocAttachment[];
  docCount: number;
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
  forEmploc: number;        // hr_status = 'For Emploc'
  for_emploc_count?: number; // DB alias
  correction: number;       // hr_status = 'For Correction'
  review: number;           // hr_status = 'For Review'
  ready: number;            // hr_status = 'Complete' / Deployed
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
  parsedError: ParsedHrEmplocError;

  constructor(kind: HrEmplocDataErrorKind, message: string, parsed?: ParsedHrEmplocError) {
    super(message);
    this.name = "HrEmplocDataError";
    this.kind = kind;
    this.parsedError = parsed || {
      code: "GENERAL_ERROR",
      title: "Operation Failed",
      message,
      rawMessage: message,
    };
  }
}

/**
 * Standardized remarks normalizer for HR Emploc:
 * Takes the first NON-EMPTY trimmed value checking ops_remarks first,
 * then caps.remarks, row.remarks, and hr_remarks.
 */
export function normalizeHrEmplocRemarks(row?: unknown, caps?: unknown): string | null {
  const r = asObject(row);
  const c = asObject(caps);
  const statusStr = (asString(r.hr_status ?? r.hrStatus ?? r.status) || "").toLowerCase().trim();
  const isIssueQueue = statusStr.includes("correction") || statusStr.includes("review");

  const candidates = isIssueQueue
    ? [
        r.hr_remarks,
        r.hrRemarks,
        c.hr_remarks,
        r.ops_remarks,
        r.opsRemarks,
        c.ops_remarks,
        c.opsRemarks,
        c.remarks,
        r.remarks,
        r.hrco_remarks,
        r.hrcoRemarks,
        r.notes,
        c.notes,
      ]
    : [
        r.ops_remarks,
        r.opsRemarks,
        c.ops_remarks,
        c.opsRemarks,
        r.hr_remarks,
        r.hrRemarks,
        c.hr_remarks,
        c.remarks,
        r.remarks,
        r.hrco_remarks,
        r.hrcoRemarks,
        r.notes,
        c.notes,
      ];
  for (const candidate of candidates) {
    if (typeof candidate === "string" && candidate.trim().length > 0) {
      return candidate.trim();
    }
  }
  return null;
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

export function normalizeCapabilities(value: unknown): HrEmplocRowCapabilities {
  const raw = Object.fromEntries(
    Object.entries(asObject(value))
      .filter(([, item]) => typeof item === "boolean")
      .map(([key, item]) => [key, item === true]),
  );

  const can_upload_docs = raw.can_upload_docs === true;
  const can_submit_requirements = raw.can_submit_requirements === true;
  const can_assign_employee_no = raw.can_assign_employee_no === true;
  const can_tag_deficiency = raw.can_tag_deficiency === true;
  const can_submit_correction = raw.can_submit_correction === true;
  const can_review_approve = raw.can_review_approve === true;
  const can_review_return = raw.can_review_return === true;
  const can_revert_to_pending = raw.can_revert_to_pending === true;
  const can_edit_emploc_no = raw.can_edit_emploc_no === true;
  const can_request_deletion = raw.can_request_deletion === true;
  const can_view_docs = raw.can_view_docs === true;

  return {
    // Database canonical keys
    can_upload_docs,
    can_submit_requirements,
    can_assign_employee_no,
    can_tag_deficiency,
    can_submit_correction,
    can_review_approve,
    can_review_return,
    can_revert_to_pending,
    can_edit_emploc_no,
    can_request_deletion,
    can_view_docs,
    can_edit_profile: raw.can_edit_profile === true,

    // Backward compatibility aliases
    canUploadDocs: can_upload_docs,
    canSubmitRequirements: can_submit_requirements,
    canAssignEmployeeNo: can_assign_employee_no,
    canTagDeficiency: can_tag_deficiency,
    canSubmitCorrection: can_submit_correction,
    canReviewApprove: can_review_approve,
    canReviewReturn: can_review_return,
    canRevertToPending: can_revert_to_pending,
    canEditEmplocNo: can_edit_emploc_no,
    canRequestDeletion: can_request_deletion,
    canViewDocs: can_view_docs,
    canViewDetail: true,
    canReviewCorrection: can_review_approve || can_review_return,
    canMoveToPlantilla: can_assign_employee_no,
    canReviewDeletion: raw.can_review_deletion === true,
    canApproveCorrection: can_review_approve,
    canRevertCorrection: can_review_return,
    canEditEmploc: can_edit_emploc_no,
    raw,
  };
}

function getTotalCount(rows: HrEmplocListItem[]): number {
  return rows[0]?.totalCount ?? 0;
}

function throwHrEmplocError(error: unknown): never {
  const parsed = parseHrEmplocError(error);
  let kind: HrEmplocDataErrorKind = "retryable";

  if (
    parsed.code === "FORBIDDEN_ROLE_OR_SCOPE" ||
    parsed.code === "FORBIDDEN_NOT_UPLOADER" ||
    parsed.code === "FORBIDDEN_REVERT" ||
    parsed.sqlstate === "42501"
  ) {
    kind = "access_denied";
  } else if (
    parsed.code.startsWith("INVALID_") ||
    parsed.code === "REQUIREMENTS_DOCS_MISSING" ||
    parsed.code === "ACTION_LOCKED_PENDING_DELETION" ||
    parsed.code === "REHIRE_CONFIRM_REQUIRED" ||
    parsed.code === "MIDDLE_NAME_CONFIRM_REQUIRED" ||
    parsed.code === "POSSIBLE_DUPLICATE_PERSON" ||
    parsed.code === "EMPLOYEE_ALREADY_ACTIVE" ||
    parsed.code === "EMPLOYEE_NO_ALREADY_ASSIGNED" ||
    parsed.code === "FIELD_REQUIRED_MISSING" ||
    parsed.code === "SLOT_UNAVAILABLE" ||
    parsed.code === "REVERT_GRACE_EXPIRED" ||
    parsed.sqlstate === "22023" ||
    parsed.sqlstate === "23505" ||
    parsed.sqlstate === "P0001"
  ) {
    kind = "invalid_state";
  }

  throw new HrEmplocDataError(kind, parsed.message, parsed);
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

export function normalizeListRow(row: HrEmplocRpcRow): HrEmplocListItem | null {
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

  const hrcoRemarks = normalizeHrEmplocRemarks(row, caps);

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

  const rawAttachments = Array.isArray(row.attachments) ? row.attachments : [];
  const attachments: HrEmplocAttachment[] = rawAttachments.map((att) => {
    const a = asObject(att);
    const storagePath = asString(a.storage_path) || "";
    const objectPath = asString(a.object_path) || storagePath.replace(/^hr-corrections\//, "");
    return {
      id: asString(a.id) || "",
      storage_path: storagePath,
      object_path: objectPath,
      file_name: asString(a.file_name ?? a.fileName ?? a.original_filename) || "document",
      file_size: asNumber(a.file_size ?? a.size_bytes) ?? undefined,
      file_type: asString(a.file_type ?? a.mime_type) ?? undefined,
      stage: (asString(a.stage) === "correction" ? "correction" : "initial_requirements") as "initial_requirements" | "correction",
      uploaded_at: asString(a.uploaded_at),
      uploaded_by: asString(a.uploaded_by),
      can_remove: a.can_remove === true,
    };
  });
  const docCount = asCount(row.doc_count ?? attachments.length);

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
    attachments,
    docCount,
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

export function normalizeAttachment(item: unknown): CorrectionAttachmentItem {
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

export function normalizeDetailRow(row: HrEmplocRpcRow): HrEmplocDetailItem | null {
  const id = asString(row.id ?? row.hr_emploc_id);

  if (!id) {
    return null;
  }

  const rawCovered = Array.isArray(row.covered_stores) ? row.covered_stores : [];
  const coveredStores = rawCovered.map(normalizeCoveredStore);

  const rawAttachments: unknown[] = Array.isArray(row.attachments)
    ? (row.attachments as unknown[])
    : Array.isArray(row.correction_attachments)
    ? (row.correction_attachments as unknown[])
    : [];
  const uploadedAttachments = rawAttachments.map(normalizeAttachment);

  const attachments: HrEmplocAttachment[] = rawAttachments.map((att: unknown) => {
    const a = asObject(att);
    const storagePath = asString(a.storage_path) || "";
    const objectPath = asString(a.object_path) || storagePath.replace(/^hr-corrections\//, "");
    return {
      id: asString(a.id) || "",
      storage_path: storagePath,
      object_path: objectPath,
      file_name: asString(a.file_name ?? a.fileName ?? a.original_filename) || "document",
      file_size: asNumber(a.file_size ?? a.size_bytes) ?? undefined,
      file_type: asString(a.file_type ?? a.mime_type) ?? undefined,
      stage: (asString(a.stage) === "correction" ? "correction" : "initial_requirements") as "initial_requirements" | "correction",
      uploaded_at: asString(a.uploaded_at),
      uploaded_by: asString(a.uploaded_by),
      can_remove: a.can_remove === true,
    };
  });
  const docCount = asCount(row.doc_count ?? attachments.length);

  const rawTimeline = Array.isArray(row.timeline) ? row.timeline : [];
  const auditLogsTimeline = rawTimeline.map(normalizeAuditLog);

  // The RPC returns the latest deletion request regardless of status; only a Pending one is active.
  const latestDeletionRequest = normalizeDeletionRequest(row.deletion_request);
  const activeDeletionRequest =
    latestDeletionRequest && latestDeletionRequest.status.trim().toLowerCase() === "pending"
      ? latestDeletionRequest
      : null;

  const caps = asObject(row.row_capabilities ?? row.rowCapabilities);
  const opsRemarks = normalizeHrEmplocRemarks(row, caps);

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
    opsRemarks,
    hrRemarks: asString(row.hr_remarks ?? row.hrRemarks) ?? null,
    requestedByName: asString(row.hr_reviewed_by ?? row.hrReviewedBy ?? row.requested_by_name ?? row.requestedByName) ?? null,
    requirementOverallStatus: asString(row.requirement_overall_status ?? row.requirementOverallStatus) ?? null,
    correctionReason: asObject(row.correction_reason ?? row.correctionReason),
    uploadedAttachments,
    attachments,
    docCount,
    slaBreached: asBoolean(row.sla_breached ?? row.slaBreached),
    slaElapsedDays: asCount(row.aging_days ?? row.sla_elapsed_days ?? row.slaElapsedDays),
    auditLogsTimeline,
    activeDeletionRequest,
    rowCapabilities: normalizeCapabilities(caps),
  };
}

export function normalizeSummary(data: unknown): HrEmplocSummary {
  const row = Array.isArray(data) ? asObject(data[0]) : asObject(data);

  const pending = asCount(row.pending_count ?? row.pending ?? row.total_pending ?? row.totalPending ?? row.total_processing);
  const forEmploc = asCount(row.for_emploc_count ?? row.for_emploc ?? row.forEmploc);
  const correction = asCount(row.correction_count ?? row.correction ?? row.action_needed ?? row.actionNeeded ?? row.action_needed_count);
  const review = asCount(row.review_count ?? row.review);
  const ready = asCount(row.ready_count ?? row.ready ?? row.ready_to_deploy ?? row.readyToDeploy ?? row.ready_to_deploy_count);
  const deployed = asCount(row.deployed_count ?? row.deployed ?? row.ready_count ?? row.ready);

  return {
    pending,
    forEmploc,
    for_emploc_count: forEmploc,
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
  employeeNo?: string | null;
  confirmReuse?: boolean;
  reuseReason?: string | null;
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
    p_resolved_keys: params.resolvedKeys ?? [],
    p_remarks: params.remarks ?? null,
    p_employee_no: params.employeeNo?.trim() || null,
    p_confirm_reuse: params.confirmReuse === true,
    p_reuse_reason: params.reuseReason?.trim() || null,
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

// ─── Scoped Document Lifecycle (Stage 2b) ────────────────────────────────────

export type AuthorizeDocUploadParams = {
  hrEmplocId: string;
  fileName: string;
  mimeType: string;
  fileSize: number;
};

export type AuthorizeDocUploadResult = {
  authorized: boolean;
  bucket: string;
  object_path: string;
  storage_path: string;
};

export async function authorizeHrEmplocDocUpload(
  params: AuthorizeDocUploadParams
): Promise<AuthorizeDocUploadResult> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("authorize_hr_emploc_doc_upload", {
    p_hr_emploc_id: params.hrEmplocId,
    p_file_name: params.fileName,
    p_mime_type: params.mimeType,
    p_file_size: params.fileSize,
  });

  if (error) {
    throwHrEmplocError(error);
  }

  const res = asObject(data);
  return {
    authorized: res.authorized === true,
    bucket: asString(res.bucket) || "hr-corrections",
    object_path: asString(res.object_path) || "",
    storage_path: asString(res.storage_path) || "",
  };
}

export type RegisterDocParams = {
  hrEmplocId: string;
  storagePath: string;
  fileName: string;
  mimeType: string;
  fileSize: number;
  stage?: "initial_requirements" | "correction";
};

export async function registerHrEmplocDocument(
  params: RegisterDocParams
): Promise<HrEmplocAttachment> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("register_hr_emploc_document", {
    p_hr_emploc_id: params.hrEmplocId,
    p_storage_path: params.storagePath,
    p_file_name: params.fileName,
    p_mime_type: params.mimeType,
    p_file_size: params.fileSize,
    p_stage: params.stage || null,
  });

  if (error) {
    throwHrEmplocError(error);
  }

  const row = asObject(data);
  const storagePath = asString(row.storage_path) || params.storagePath;
  const objectPath = asString(row.object_path) || storagePath.replace(/^hr-corrections\//, "");

  return {
    id: asString(row.id) || "",
    storage_path: storagePath,
    object_path: objectPath,
    file_name: asString(row.original_filename ?? row.file_name) || params.fileName,
    file_size: asNumber(row.size_bytes ?? row.file_size) ?? params.fileSize,
    file_type: asString(row.mime_type ?? row.file_type) || params.mimeType,
    stage: (asString(row.stage) === "correction" ? "correction" : "initial_requirements") as "initial_requirements" | "correction",
    uploaded_at: asString(row.uploaded_at),
    uploaded_by: asString(row.uploaded_by),
    can_remove: row.can_remove === true,
  };
}

export async function removeHrEmplocDocument(attachmentId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("remove_hr_emploc_document", {
    p_attachment_id: attachmentId,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}

export async function submitHrEmplocRequirements(params: {
  hrEmplocId: string;
  notes?: string | null;
}): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("submit_hr_emploc_requirements", {
    p_hr_emploc_id: params.hrEmplocId,
    p_notes: params.notes?.trim() || null,
  });

  if (error) {
    throwHrEmplocError(error);
  }
}

export async function getHrEmplocDocSignedUrl(
  path: string,
  options?: { download?: boolean; expiresIn?: number }
): Promise<string> {
  const supabase = createClient();
  const objectPath = path.replace(/^hr-corrections\//, "");
  const expiresIn = options?.expiresIn ?? 300; // 5-minute short TTL

  const { data, error } = await supabase.storage
    .from("hr-corrections")
    .createSignedUrl(objectPath, expiresIn, {
      download: options?.download ?? false,
    });

  if (error || !data?.signedUrl) {
    throw new HrEmplocDataError(
      "retryable",
      `Failed to generate document link: ${error?.message || "File unavailable"}`
    );
  }

  return data.signedUrl;
}

export const getCorrectionAttachmentSignedUrl = getHrEmplocDocSignedUrl;

/**
 * Submits HRCO correction notes, transitioning the record from 'For Correction' to 'For Review'.
 */
export async function submitHrcoCorrection(params: {
  hrEmplocId: string;
  hrcoNotes?: string | null;
  attachments?: File[];
}): Promise<void> {
  const trimmedNotes = params.hrcoNotes?.trim() || null;
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
 * Approves a record currently in Review, assigning Employee Number, resolving deficiencies, and moving it to Plantilla.
 */
export async function approveHrEmplocReview(params: {
  hrEmplocId: string;
  employeeNo: string;
  resolvedKeys?: string[];
  remarks?: string;
  confirmReuse?: boolean;
  reuseReason?: string | null;
}): Promise<void> {
  const supabase = createClient();

  const { error } = await supabase.rpc("review_web_hr_emploc_correction", {
    p_hr_emploc_id: params.hrEmplocId,
    p_decision: "approve",
    p_resolved_keys: params.resolvedKeys ?? [],
    p_remarks: params.remarks?.trim() || null,
    p_employee_no: params.employeeNo.trim(),
    p_confirm_reuse: params.confirmReuse === true,
    p_reuse_reason: params.reuseReason?.trim() || null,
  });

  if (error) {
    throwHrEmplocError(error);
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
  const { error } = await supabase.rpc("reject_correction_request", {
    p_correction_request_id: params.hrEmplocId,
    p_hr_remarks: trimmed,
  });

  if (error) {
    throwHrEmplocError(error);
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

// ─── Lifecycle Mutation Actions ──────────────────────────────────────────────

export type AssignEmployeeNoParams = {
  hrEmplocId: string;
  employeeNo: string;
  confirmReuse?: boolean;
  reuseReason?: string | null;
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
    p_confirm_reuse: params.confirmReuse === true,
    p_reuse_reason: params.reuseReason?.trim() || null,
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

export function useAuthorizeDocUpload() {
  return useMutation({
    mutationFn: (params: AuthorizeDocUploadParams) => authorizeHrEmplocDocUpload(params),
  });
}

export function useRegisterDoc() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RegisterDocParams) => registerHrEmplocDocument(params),
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

export function useRemoveDoc() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (attachmentId: string) => removeHrEmplocDocument(attachmentId),
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

export function useSubmitHrEmplocRequirements() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: { hrEmplocId: string; notes?: string | null }) =>
      submitHrEmplocRequirements(params),
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
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard"] });
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
      account,
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
      hr_emploc:hr_emploc!hr_emploc_id (
        applicant_name,
        employee_no,
        store_name,
        position,
        vcode,
        account,
        account_id
      )
    `);

  if (tab === "pending") {
    query = query.ilike("status", "pending");
  } else if (tab === "approved") {
    query = query.or("status.ilike.approved,status.ilike.completed");
  } else if (tab === "rejected") {
    query = query.or("status.ilike.rejected,status.ilike.withdrawn");
  }

  let orderedQuery = query.order("created_at", { ascending: false });
  if (pagination?.page && pagination?.limit) {
    const page = Math.max(1, Math.trunc(pagination.page));
    const limit = Math.max(1, Math.trunc(pagination.limit));
    const offset = (page - 1) * limit;
    orderedQuery = orderedQuery.range(offset, offset + limit - 1);
  }

  const { data, error } = await orderedQuery;

  if (error) {
    console.error("[fetchEmplocDeletionRequests] query failed:", error);
    if (error.code === "42501") {
      throw new HrEmplocDataError("access_denied", "Unauthorized: Scoped access restricted.");
    }
    throw new HrEmplocDataError("retryable", error.message);
  }

  const rawRows = data ?? [];

  // Extract candidate account_ids, account names, and vcodes for batch lookup
  const accountIds = Array.from(
    new Set(
      rawRows
        .map((row) => {
          const emploc = asObject(
            Array.isArray(row.hr_emploc) ? row.hr_emploc[0] : row.hr_emploc
          );
          return asString(emploc.account_id);
        })
        .filter((id): id is string => Boolean(id))
    )
  );

  const accountNames = Array.from(
    new Set(
      rawRows
        .flatMap((row) => {
          const emploc = asObject(
            Array.isArray(row.hr_emploc) ? row.hr_emploc[0] : row.hr_emploc
          );
          return [asString(row.account), asString(emploc.account)];
        })
        .filter((name): name is string => Boolean(name && name.trim()))
    )
  );

  const vcodes = Array.from(
    new Set(
      rawRows
        .flatMap((row) => {
          const emploc = asObject(
            Array.isArray(row.hr_emploc) ? row.hr_emploc[0] : row.hr_emploc
          );
          return [asString(emploc.vcode), asString(row.vcode)];
        })
        .filter((v): v is string => Boolean(v && v.trim()))
    )
  );

  const accountByIdMap = new Map<string, { accountName: string; groupName: string | null }>();
  const accountByNameMap = new Map<string, { accountName: string; groupName: string | null }>();

  if (accountIds.length > 0 || accountNames.length > 0) {
    try {
      const promises: Promise<void>[] = [];

      if (accountIds.length > 0) {
        promises.push(
          (async () => {
            const { data: byId } = await supabase
              .from("accounts")
              .select(`
                id,
                account_name,
                groups (
                  group_name
                )
              `)
              .in("id", accountIds);

            for (const acc of byId ?? []) {
              const groupRelation = acc.groups as unknown as
                | { group_name?: string | null }
                | { group_name?: string | null }[]
                | null;
              const groupName = Array.isArray(groupRelation)
                ? groupRelation[0]?.group_name ?? null
                : groupRelation?.group_name ?? null;

              const info = { accountName: acc.account_name, groupName };
              accountByIdMap.set(acc.id, info);
              accountByNameMap.set(acc.account_name.toLowerCase(), info);
            }
          })()
        );
      }

      if (accountNames.length > 0) {
        promises.push(
          (async () => {
            const { data: byName } = await supabase
              .from("accounts")
              .select(`
                id,
                account_name,
                groups (
                  group_name
                )
              `)
              .in("account_name", accountNames);

            for (const acc of byName ?? []) {
              const groupRelation = acc.groups as unknown as
                | { group_name?: string | null }
                | { group_name?: string | null }[]
                | null;
              const groupName = Array.isArray(groupRelation)
                ? groupRelation[0]?.group_name ?? null
                : groupRelation?.group_name ?? null;

              const info = { accountName: acc.account_name, groupName };
              accountByIdMap.set(acc.id, info);
              accountByNameMap.set(acc.account_name.toLowerCase(), info);
            }
          })()
        );
      }

      await Promise.allSettled(promises);
    } catch {
      // Non-blocking fallback
    }
  }

  // Secondary fallback: lookup by VCODE in vacancies
  const vcodeMap = new Map<string, { accountName: string | null; groupName: string | null }>();
  if (vcodes.length > 0) {
    try {
      const { data: vacsData } = await supabase
        .from("vacancies")
        .select(`
          vcode,
          account,
          account_id,
          group_id,
          accounts (
            account_name,
            groups (
              group_name
            )
          ),
          groups (
            group_name
          )
        `)
        .in("vcode", vcodes);

      for (const vac of vacsData ?? []) {
        const accRel = vac.accounts as unknown as
          | { account_name?: string | null; groups?: { group_name?: string | null } | { group_name?: string | null }[] | null }
          | null;
        const grpRel = vac.groups as unknown as
          | { group_name?: string | null }
          | { group_name?: string | null }[]
          | null;

        const accountName =
          accRel?.account_name ||
          (typeof vac.account === "string" && vac.account.trim() ? vac.account : null);

        const groupRelFromAcc = accRel?.groups;
        const groupNameFromAcc = Array.isArray(groupRelFromAcc)
          ? groupRelFromAcc[0]?.group_name
          : groupRelFromAcc?.group_name;
        const groupNameDirect = Array.isArray(grpRel)
          ? grpRel[0]?.group_name
          : grpRel?.group_name;
        const groupName = groupNameDirect || groupNameFromAcc || null;

        if (vac.vcode) {
          vcodeMap.set(vac.vcode, { accountName: accountName ?? null, groupName: groupName ?? null });
        }
      }
    } catch {
      // Non-blocking fallback
    }
  }

  return rawRows.map((row): EmplocDeletionRequestItem => {
    const emploc = asObject(
      Array.isArray(row.hr_emploc) ? row.hr_emploc[0] : row.hr_emploc
    );

    const emplocAccountId = asString(emploc.account_id);
    const directAccount = asString(row.account) || asString(emploc.account);
    const rowVcode = asString(emploc.vcode) ?? asString(row.vcode) ?? "";

    let resolvedAccount: string | null = null;
    let resolvedGroup: string | null = null;

    // 1. Try accountByIdMap
    if (emplocAccountId && accountByIdMap.has(emplocAccountId)) {
      const found = accountByIdMap.get(emplocAccountId)!;
      resolvedAccount = found.accountName;
      resolvedGroup = found.groupName;
    }

    // 2. Try accountByNameMap if group is missing
    if (!resolvedGroup && directAccount && accountByNameMap.has(directAccount.toLowerCase())) {
      const found = accountByNameMap.get(directAccount.toLowerCase())!;
      resolvedAccount = resolvedAccount || found.accountName;
      resolvedGroup = found.groupName;
    }

    // 3. Try vcodeMap if account or group is still missing
    if ((!resolvedAccount || !resolvedGroup) && rowVcode && vcodeMap.has(rowVcode)) {
      const found = vcodeMap.get(rowVcode)!;
      resolvedAccount = resolvedAccount || found.accountName;
      resolvedGroup = resolvedGroup || found.groupName;
    }

    // 4. Fallback to directAccount string
    resolvedAccount = resolvedAccount || directAccount || null;

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
      accountName: resolvedAccount,
      groupName: resolvedGroup,
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
    .select("status");
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

