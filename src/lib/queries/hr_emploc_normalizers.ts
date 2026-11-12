const SUFFIXES = new Set(["JR", "JR.", "SR", "SR.", "II", "III", "IV", "V"]);

export function parseFullNameString(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return "";

  const lower = trimmed.toLowerCase();
  if (
    lower.includes("vacant") ||
    lower === "unassigned" ||
    lower === "anonymous" ||
    lower === "candidate" ||
    lower === "hired worker" ||
    lower === "—" ||
    lower === "-"
  ) {
    return trimmed;
  }

  if (trimmed.includes(",")) {
    const parts = trimmed.split(",");
    const lastPart = parts[0].trim();
    const rest = parts.slice(1).join(" ").trim();
    if (lastPart && rest) {
      return `${lastPart}, ${rest}`.toUpperCase();
    }
    return trimmed.toUpperCase();
  }

  const tokens = trimmed.split(/\s+/).filter(Boolean);
  if (tokens.length <= 1) {
    return tokens[0] ? tokens[0].toUpperCase() : "";
  }

  let lastIdx = tokens.length - 1;
  let suffix = "";
  if (tokens.length >= 3 && SUFFIXES.has(tokens[lastIdx].toUpperCase())) {
    suffix = ` ${tokens[lastIdx]}`;
    lastIdx--;
  }

  const lastPart = tokens[lastIdx] + suffix;
  const firstParts = tokens.slice(0, lastIdx).join(" ");

  return `${lastPart}, ${firstParts}`.toUpperCase();
}

export function formatPersonName(
  firstName?: string | null,
  lastName?: string | null,
  middleName?: string | null,
  fullName?: string | null,
): string {
  const f = firstName?.trim() || "";
  const l = lastName?.trim() || "";
  const m = middleName?.trim() || "";

  if (l && f) {
    const fnPart = m ? `${f} ${m}` : f;
    return `${l}, ${fnPart}`.toUpperCase();
  }

  if (l && !f) {
    return l.toUpperCase();
  }

  if (f && !l) {
    return parseFullNameString(f);
  }

  const raw = fullName?.trim() || "";
  if (!raw) return "";

  return parseFullNameString(raw);
}

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

export type HrEmplocSummary = {
  pending: number;
  forEmploc: number;
  for_emploc_count?: number;
  correction: number;
  review: number;
  ready: number;
  deployed: number;
  totalPending: number;
  actionNeeded: number;
  readyToDeploy: number;
  pendingDeletion: number;
  slaBreaches: number;
};

export type HrEmplocRpcRow = Record<string, unknown>;

export function asObject(value: unknown): Record<string, unknown> {
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      return {};
    }
  }
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

export function asString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  return null;
}

export function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

export function asBoolean(value: unknown): boolean {
  return value === true;
}

export function asCount(value: unknown): number {
  return Math.max(0, Math.trunc(asNumber(value) ?? 0));
}

export function summarizeDeficiency(raw: unknown): string | null {
  if (!raw) {
    return null;
  }

  if (typeof raw === "string") {
    const trimmed = raw.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  if (typeof raw === "object") {
    const obj = raw as Record<string, unknown>;
    const summary = asString(obj.summary);
    if (summary) {
      return summary;
    }

    if (Array.isArray(obj.issues) && obj.issues.length > 0) {
      const labels = obj.issues
        .map((issue) => {
          if (!issue || typeof issue !== "object") {
            return null;
          }
          const issueObj = issue as Record<string, unknown>;
          return asString(issueObj.label) ?? asString(issueObj.code);
        })
        .filter((label): label is string => Boolean(label));

      if (labels.length > 0) {
        return labels.join(", ");
      }
    }
  }

  return null;
}

export function normalizeHrEmplocRemarks(row?: unknown, caps?: unknown): string | null {
  const r = asObject(row);
  const c = asObject(caps);
  const candidates = [
    r.ops_remarks,
    r.opsRemarks,
    c.ops_remarks,
    c.opsRemarks,
    c.remarks,
    r.remarks,
    r.hr_remarks,
    r.hrRemarks,
    c.hr_remarks,
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

  const rawAttachments = Array.isArray(row.attachments)
    ? row.attachments
    : Array.isArray(caps.attachments)
    ? (caps.attachments as unknown[])
    : [];
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
  const docCount = asCount(row.doc_count ?? caps.doc_count ?? attachments.length);

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

export function normalizeCoveredStore(item: unknown): CoveredStoreItem {
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

export function normalizeAuditLog(item: unknown): HrEmplocAuditLogItem {
  const obj = asObject(item);
  return {
    eventId: asString(obj.event_id ?? obj.eventId) ?? "",
    eventLabel: asString(obj.event_label ?? obj.eventLabel) ?? "Event",
    eventDescription: asString(obj.event_description ?? obj.eventDescription) ?? null,
    createdAt: asString(obj.created_at ?? obj.createdAt) ?? null,
    profileName: asString(obj.profile_name ?? obj.profileName) ?? null,
  };
}

export function normalizeDeletionRequest(item: unknown): DeletionRequestItem | null {
  if (!item || typeof item !== "object") {
    return null;
  }
  const obj = item as Record<string, unknown>;
  const requestId = asString(obj.request_id ?? obj.requestId ?? obj.id);
  if (!requestId) {
    return null;
  }

  const rawType = asString(obj.deletion_type ?? obj.deletionType) ?? "backout";
  const deletionType = rawType.toLowerCase().includes("duplicate") ? "duplicate" : "backout";

  return {
    requestId,
    requestedBy: asString(obj.requested_by ?? obj.requestedBy) ?? "Unknown",
    requestedAt: asString(obj.requested_at ?? obj.requestedAt) ?? null,
    deletionType,
    reason: asString(obj.reason) ?? "Placement separation requested",
    originalEmplocId: asString(obj.original_emploc_id ?? obj.originalEmplocId),
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

  const caps = asObject(row.row_capabilities ?? row.rowCapabilities ?? row.capabilities);

  const rawAttachments: unknown[] = Array.isArray(row.attachments)
    ? (row.attachments as unknown[])
    : Array.isArray(row.correction_attachments)
    ? (row.correction_attachments as unknown[])
    : Array.isArray(caps.attachments)
    ? (caps.attachments as unknown[])
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
  const docCount = asCount(row.doc_count ?? caps.doc_count ?? attachments.length);

  const rawTimeline = Array.isArray(row.timeline) ? row.timeline : [];
  const auditLogsTimeline = rawTimeline.map(normalizeAuditLog);

  const latestDeletionRequest = normalizeDeletionRequest(row.deletion_request);
  const activeDeletionRequest =
    latestDeletionRequest && latestDeletionRequest.status.trim().toLowerCase() === "pending"
      ? latestDeletionRequest
      : null;

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
