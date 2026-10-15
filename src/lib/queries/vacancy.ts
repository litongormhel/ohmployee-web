import type { PostgrestError } from "@supabase/supabase-js";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export type VacancyStatus =
  | "open"
  | "pipeline"
  | "hired"
  | "closure"
  | "failed_backout"
  | "with_applicant"
  | "rejected"
  | "backout";

export type VacancyAgingBucket =
  | "advance"
  | "1_15"
  | "16_30"
  | "31_60"
  | "61_120"
  | "gt121";

export type VacancyPipelineStatus = "Open" | "Pipeline";

type VacancySortField =
  | "aging_days"
  | "vacant_date"
  | "target_fill_date"
  | "urgency"
  | "account_name"
  | "group_name"
  | "store_name"
  | "position_title"
  | "vacancy_status"
  | "pipeline_status"
  | "vcode";

type VacancySortDirection = "asc" | "desc";

export type VacancyRowCapabilities = {
  canViewDetail: boolean;
  canApprove: boolean;
  canUpdateApplicantStatus: boolean;
  canRequestClosure: boolean;
  raw: Record<string, boolean>;
};

export type VacancyListItem = {
  id: string;
  vcode: string;
  accountId: string | null;
  accountName: string | null;
  groupId: string | null;
  groupName: string | null;
  storeId: string | null;
  storeName: string | null;
  storeLocation: string | null;
  position_title: string | null;
  department: string | null;
  employmentType: string | null;
  vacancyStatus: string | null;
  pipelineStatus: VacancyPipelineStatus | string | null;
  derivedStatus: string | null;
  activeApplicantCount: number;
  confirmedOnboardCount: number;
  hasRecentHire: boolean;
  hasPendingClosure: boolean;
  closureRequestStatus: string | null;
  vacantDate: string | null;
  agingDays: number | null;
  agingBucket: VacancyAgingBucket | string | null;
  targetFillDate: string | null;
  urgencyLevel: string | null;
  hrcoName: string | null;
  applicantId?: string | null;
  applicantName: string | null;
  contactNumber?: string | null;
  hiredDate?: string | null;
  stageBadge?: string | null;
  closureReason?: string | null;
  closureRequestedBy?: string | null;
  closureRequestedAt?: string | null;
  closureRequestId?: string | null;
  dropoutReason?: string | null;
  dropoutDate?: string | null;
  hasPenalty: boolean;
  penaltyExposure: number;
  penaltyAmount: number | null;
  lastActivityAt: string | null;
  rowCapabilities: VacancyRowCapabilities;
  totalCount: number;
};

export type ActiveApplicantItem = {
  applicantId: string;
  displayName: string;
  lastName: string | null;
  firstName: string | null;
  contactNumber: string | null;
  statusLabel: string;
  onboardDate: string | null;
  updatedAt: string | null;
  recruiterName: string | null;
  deployedByName: string | null;
};

export type ActivityHistoryItem = {
  eventId: string;
  eventLabel: string;
  eventDescription: string | null;
  createdAt: string | null;
  profileName: string | null;
};

export type VacancyDetailItem = {
  vacancyId: string;
  vcode: string;
  accountId: string | null;
  accountName: string | null;
  groupId: string | null;
  groupName: string | null;
  storeId: string | null;
  storeName: string | null;
  position_title: string | null;
  department: string | null;
  employmentType: string | null;
  vacancyStatus: string | null;
  pipelineStatus: string | null;
  derivedStatus: string | null;
  activeApplicantCount: number;
  confirmedOnboardCount: number;
  hasRecentHire: boolean;
  hasPendingClosure: boolean;
  closureRequestStatus: string | null;
  vacantDate: string | null;
  agingDays: number | null;
  agingBucket: string | null;
  targetFillDate: string | null;
  urgencyLevel: string | null;
  hrcoName: string | null;
  lastActivityAt: string | null;
  rowCapabilities: VacancyRowCapabilities;

  // Supplementary fields from official sheet schema
  contactNumber: string | null;
  onboardDate: string | null;
  relieverOnDuty: string | null;
  hasReliever: boolean;
  hrcoRemarks: string | null;
  recruiterName: string | null;
  deployedByName: string | null;
  hasPenalty: boolean;
  penaltyExposure: number;
  penaltyAmount: number | null;
  applicantLastName: string | null;
  applicantFirstName: string | null;
  applicantName: string | null;
  storeLocation: string | null;
  areaCity: string | null;
  areaProvince: string | null;
  storeBranch: string | null;

  // Detail-specific fields
  requestedById: string | null;
  requestedByName: string | null;
  approvedById: string | null;
  approvedByName: string | null;
  approvedAt: string | null;
  headcountRequestId: string | null;
  vacancyReason: string | null;
  jobDescription: string | null;
  closureRequestedAt: string | null;
  closureRequestedBy: string | null;
  closureReason: string | null;
  activeApplicantsList: ActiveApplicantItem[];
  activityHistory: ActivityHistoryItem[];
};

export type VacancyListParams = {
  status?: VacancyStatus;
  search?: string;
  agingBucket?: string;
  accountId?: string;
  groupId?: string;
  position?: string;
  urgency?: string;
  vacantFrom?: string;
  vacantTo?: string;
  page: number;
  pageSize: number;
};

export type VacancySummary = {
  open: number;
  pipeline: number;
  hired: number;
  closure: number;
  failedBackout: number;
  withApplicant: number;
  rejected: number;
  backout: number;
  pendingReview: number;
  agingWatch: number;
  total: number;
};

export type VacancyDataErrorKind =
  | "access_denied"
  | "retryable"
  | "validation"
  | "not_found"
  | "generic";

export class VacancyDataError extends Error {
  kind: VacancyDataErrorKind;

  constructor(kind: VacancyDataErrorKind, message: string) {
    super(message);
    this.name = "VacancyDataError";
    this.kind = kind;
  }
}

type VacancyRpcRow = Record<string, unknown>;

const MAX_PAGE_SIZE = 100;
const supportedAgingBuckets = new Set<VacancyAgingBucket>([
  "advance",
  "1_15",
  "16_30",
  "31_60",
  "61_120",
  "gt121",
]);
const supportedUrgencyLevels = new Set(["High", "Medium", "Normal"]);
const supportedSortFields = new Set<VacancySortField>([
  "aging_days",
  "vacant_date",
  "target_fill_date",
  "urgency",
  "account_name",
  "group_name",
  "store_name",
  "position_title",
  "vacancy_status",
  "pipeline_status",
  "vcode",
]);

function asObject(value: unknown): Record<string, unknown> {
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown) {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function asTrimmedString(value: unknown) {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function asDateFilter(value: unknown) {
  const date = asTrimmedString(value);

  if (!date) {
    return null;
  }

  return /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : null;
}

function asUuidFilter(value: unknown) {
  const uuid = asTrimmedString(value);

  if (!uuid) {
    return null;
  }

  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uuid)
    ? uuid
    : null;
}

function asNumber(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function asBoolean(value: unknown) {
  return value === true;
}

function asCount(value: unknown) {
  return Math.max(0, Math.trunc(asNumber(value) ?? 0));
}

function normalizeCapabilities(value: unknown): VacancyRowCapabilities {
  const raw = Object.fromEntries(
    Object.entries(asObject(value))
      .filter(([, item]) => typeof item === "boolean")
      .map(([key, item]) => [key, item === true]),
  );

  return {
    canViewDetail: raw.can_view_detail === true,
    canApprove: raw.can_approve === true,
    canUpdateApplicantStatus: raw.can_update_applicant_status === true,
    canRequestClosure: raw.can_request_closure_hint === true || raw.can_request_closure === true,
    raw,
  };
}

function normalizeAgingBucket(value: unknown) {
  return supportedAgingBuckets.has(value as VacancyAgingBucket)
    ? (value as VacancyAgingBucket)
    : null;
}

function normalizeUrgency(value: unknown) {
  return supportedUrgencyLevels.has(value as string) ? (value as string) : null;
}

function normalizeSortField(value: unknown): VacancySortField {
  return supportedSortFields.has(value as VacancySortField)
    ? (value as VacancySortField)
    : "aging_days";
}

function normalizeSortDirection(value: unknown): VacancySortDirection {
  return value === "asc" ? "asc" : "desc";
}

function getTotalCount(rows: VacancyListItem[]) {
  return rows[0]?.totalCount ?? 0;
}

function getErrorKind(error: PostgrestError): VacancyDataErrorKind {
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

  return "retryable";
}

function throwVacancyError(error: PostgrestError): never {
  if (process.env.NODE_ENV !== "production") {
    console.error("[vacancy rpc error]", error.code, error.message, error.details, error.hint);
  }
  throw new VacancyDataError(getErrorKind(error), error.message);
}

function normalizeListRow(row: VacancyRpcRow): VacancyListItem | null {
  const id = asString(row.vacancy_id ?? row.id);

  if (!id) {
    return null;
  }

  const applicantLastName = asString(row.applicant_last_name ?? row.last_name);
  const applicantFirstName = asString(row.applicant_first_name ?? row.first_name);
  const rawApplicantName = asString(
    row.applicant_name ??
    row.applicant_full_name ??
    row.full_name ??
    row.candidate_name,
  );
  const applicantName = rawApplicantName
    ? rawApplicantName
    : applicantLastName && applicantFirstName
    ? `${applicantLastName}, ${applicantFirstName}`
    : applicantLastName || applicantFirstName || null;

  const penaltyAmount = asNumber(row.penalty_amount ?? row.penalty_exposure);
  const hasPenalty =
    asBoolean(row.has_penalty ?? row.with_penalty) ||
    (penaltyAmount !== null && penaltyAmount > 0);
  const penaltyExposure =
    asNumber(row.penalty_exposure ?? row.penalty_amount) ?? (hasPenalty ? 1 : 0);

  const areaCity = asString(row.area_city ?? row.city);
  const areaProvince = asString(
    row.area_province ?? row.area_name ?? row.province ?? row.region,
  );
  const storeLocation =
    [areaCity, areaProvince].filter(Boolean).join(" • ") || null;

  const applicantId = asString(row.applicant_id ?? row.applicantId ?? row.primary_applicant_id);
  const contactNumber = asString(
    row.contact_number ??
    row.applicant_contact_number ??
    row.applicant_mobile ??
    row.mobile_number,
  );
  const hiredDate = asString(row.hired_date ?? row.onboard_date);

  return {
    id,
    vcode: asString(row.vcode ?? row.vacancy_code) ?? "Uncoded",
    accountId: asString(row.account_id),
    accountName: asString(row.account_name ?? row.account),
    groupId: asString(row.group_id),
    groupName: asString(row.group_name),
    storeId: asString(row.store_id),
    storeName: asString(row.store_name ?? row.store),
    storeLocation,
    position_title: asString(row.position_title),
    department: asString(row.department ?? row.business_unit),
    employmentType: asString(row.employment_type),
    vacancyStatus: asString(row.vacancy_status ?? row.status),
    pipelineStatus: asString(row.pipeline_status),
    derivedStatus: asString(row.derived_status),
    activeApplicantCount: asCount(row.active_applicant_count),
    confirmedOnboardCount: asCount(row.confirmed_onboard_count),
    hasRecentHire: asBoolean(row.has_recent_hire),
    hasPendingClosure: asBoolean(row.has_pending_closure),
    closureRequestStatus: asString(row.closure_request_status),
    vacantDate: asString(row.vacant_date),
    agingDays: asNumber(row.aging_days),
    agingBucket: asString(row.aging_bucket),
    targetFillDate: asString(row.target_fill_date),
    urgencyLevel: asString(row.urgency_level ?? row.urgency),
    hrcoName: asString(row.hrco_name),
    applicantId,
    applicantName,
    contactNumber,
    hiredDate,
    stageBadge: asString(row.stage_badge ?? row.stage ?? row.top_applicant_status),
    closureReason: asString(row.closure_reason ?? row.reason),
    closureRequestedBy: asString(row.closure_requested_by ?? row.requested_by ?? row.requested_by_name),
    closureRequestedAt: asString(row.closure_requested_at ?? row.requested_at),
    closureRequestId: asString(row.closure_request_id),
    dropoutReason: asString(row.dropout_reason ?? row.backout_reason ?? row.rejection_reason),
    dropoutDate: asString(row.dropout_date ?? row.backout_date ?? row.rejected_at),
    hasPenalty,
    penaltyExposure,
    penaltyAmount,
    lastActivityAt: asString(row.last_activity_at),
    rowCapabilities: normalizeCapabilities(row.row_capabilities),
    totalCount: asCount(row.total_count),
  };
}

function normalizeActiveApplicant(item: unknown): ActiveApplicantItem {
  const obj = asObject(item);
  const lastName = asString(obj.last_name ?? obj.applicant_last_name);
  const firstName = asString(obj.first_name ?? obj.applicant_first_name);
  let displayName = asString(obj.display_name ?? obj.full_name ?? obj.name);
  if (!displayName && (lastName || firstName)) {
    displayName = [firstName, lastName].filter(Boolean).join(" ");
  }

  return {
    applicantId: asString(obj.applicant_id ?? obj.id) ?? "",
    displayName: displayName ?? "Anonymous",
    lastName,
    firstName,
    contactNumber: asString(obj.contact_number ?? obj.mobile_number ?? obj.phone),
    statusLabel: asString(obj.status_label ?? obj.status) ?? "New",
    onboardDate: asString(obj.onboard_date ?? obj.hired_date),
    updatedAt: asString(obj.updated_at ?? obj.created_at),
    recruiterName: asString(obj.recruiter_name ?? obj.recruited_by_name),
    deployedByName: asString(obj.deployed_by_name ?? obj.deployed_by),
  };
}

function normalizeActivityHistory(item: unknown): ActivityHistoryItem {
  const obj = asObject(item);
  return {
    eventId: asString(obj.event_id ?? obj.id) ?? "",
    eventLabel: asString(obj.event_label ?? obj.label) ?? "Event",
    eventDescription: asString(obj.event_description ?? obj.description),
    createdAt: asString(obj.created_at ?? obj.timestamp),
    profileName: asString(obj.profile_name ?? obj.user_name),
  };
}

function normalizeDetailRow(row: VacancyRpcRow): VacancyDetailItem | null {
  const id = asString(row.vacancy_id ?? row.id);

  if (!id) {
    return null;
  }

  const rawApplicants = Array.isArray(row.active_applicants_list)
    ? row.active_applicants_list
    : Array.isArray(row.pipeline_summary)
    ? row.pipeline_summary
    : [];
  const activeApplicantsList = rawApplicants.map(normalizeActiveApplicant);

  const rawHistory = Array.isArray(row.activity_history) ? row.activity_history : [];
  const activityHistory = rawHistory.map(normalizeActivityHistory);

  const primaryApplicant = activeApplicantsList[0];
  const applicantLastName = asString(row.applicant_last_name ?? row.last_name) ?? primaryApplicant?.lastName ?? null;
  const applicantFirstName = asString(row.applicant_first_name ?? row.first_name) ?? primaryApplicant?.firstName ?? null;
  const rawApplicantName = asString(
    row.applicant_name ??
    row.applicant_full_name ??
    row.full_name ??
    row.candidate_name,
  );
  const applicantName = rawApplicantName
    ? rawApplicantName
    : applicantLastName && applicantFirstName
    ? `${applicantLastName}, ${applicantFirstName}`
    : applicantLastName || applicantFirstName || (primaryApplicant && primaryApplicant.displayName !== "Anonymous" ? primaryApplicant.displayName : null);

  const contactNumber = asString(
    row.contact_number ??
    row.applicant_contact_number ??
    row.hrco_mobile ??
    primaryApplicant?.contactNumber,
  );

  const penaltyAmount = asNumber(row.penalty_amount ?? row.penalty_exposure);
  const hasPenalty =
    asBoolean(row.has_penalty ?? row.with_penalty) ||
    (penaltyAmount !== null && penaltyAmount > 0);
  const penaltyExposure =
    asNumber(row.penalty_exposure ?? row.penalty_amount) ?? (hasPenalty ? 1 : 0);

  const relieverOnDuty = asString(row.reliever_name ?? row.reliever);
  const hasReliever = asBoolean(row.has_reliever) || !!relieverOnDuty;

  const hrcoRemarks = asString(
    row.hrco_remarks ??
    row.remarks ??
    row.notes ??
    row.vacancy_remarks,
  );

  const recruiterName = asString(
    row.recruiter_name ??
    row.recruited_by_name ??
    row.assigned_encoder_name ??
    primaryApplicant?.recruiterName,
  );

  const deployedByName = asString(
    row.deployed_by_name ??
    row.deployed_by ??
    row.endorsed_by_name ??
    row.triggered_by_name ??
    primaryApplicant?.deployedByName,
  );

  const onboardDate = asString(
    row.onboard_date ??
    row.hired_date ??
    row.target_fill_date ??
    primaryApplicant?.onboardDate,
  );

  return {
    vacancyId: id,
    vcode: asString(row.vcode ?? row.vacancy_code) ?? "Uncoded",
    accountId: asString(row.account_id),
    accountName: asString(row.account_name ?? row.account),
    groupId: asString(row.group_id),
    groupName: asString(row.group_name),
    storeId: asString(row.store_id),
    storeName: asString(row.store_name ?? row.store),
    position_title: asString(row.position_title),
    department: asString(row.department ?? row.business_unit),
    employmentType: asString(row.employment_type),
    vacancyStatus: asString(row.vacancy_status ?? row.status),
    pipelineStatus: asString(row.pipeline_status),
    derivedStatus: asString(row.derived_status ?? row.pipeline_status),
    activeApplicantCount: asCount(row.active_applicant_count),
    confirmedOnboardCount: asCount(row.confirmed_onboard_count),
    hasRecentHire: asBoolean(row.has_recent_hire),
    hasPendingClosure:
      asBoolean(row.has_pending_closure) ||
      asBoolean((row.row_capabilities as Record<string, unknown> | undefined)?.has_pending_closure),
    closureRequestStatus:
      asString(row.closure_request_status) ||
      asString((row.row_capabilities as Record<string, unknown> | undefined)?.closure_request_status),
    vacantDate: asString(row.vacant_date),
    agingDays: asNumber(row.aging_days),
    agingBucket: asString(row.aging_bucket),
    targetFillDate: asString(row.target_fill_date),
    urgencyLevel: asString(row.urgency_level ?? row.urgency),
    hrcoName: asString(row.hrco_name),
    lastActivityAt: asString(row.last_activity_at),
    rowCapabilities: normalizeCapabilities(row.row_capabilities),

    // Supplementary fields from official sheet schema
    contactNumber,
    onboardDate,
    relieverOnDuty,
    hasReliever,
    hrcoRemarks,
    recruiterName,
    deployedByName,
    hasPenalty,
    penaltyExposure,
    penaltyAmount,
    applicantLastName,
    applicantFirstName,
    applicantName,
    storeLocation: [asString(row.area_city), asString(row.area_province ?? row.area_name ?? row.province)].filter(Boolean).join(" • ") || null,
    areaCity: asString(row.area_city),
    areaProvince: asString(row.area_province ?? row.area_name ?? row.province),
    storeBranch: asString(row.store_branch),

    // Detail-specific fields
    requestedById: asString(row.requested_by_id),
    requestedByName: asString(row.requested_by_name),
    approvedById: asString(row.approved_by_id),
    approvedByName: asString(row.approved_by_name),
    approvedAt: asString(row.approved_at),
    headcountRequestId: asString(row.headcount_request_id),
    vacancyReason: asString(row.vacancy_reason),
    jobDescription: asString(row.job_description),
    closureRequestedAt: asString(row.closure_requested_at),
    closureRequestedBy: asString(row.closure_requested_by),
    closureReason: asString(row.closure_reason),
    activeApplicantsList,
    activityHistory,
  };
}


function normalizeSummary(data: unknown): VacancySummary {
  const row = Array.isArray(data) ? asObject(data[0]) : asObject(data);

  const open = asCount(row.total_open ?? row.open ?? row.open_count ?? row.open_vacancies);
  const pipeline = asCount(
    row.pipeline ?? row.with_applicant ?? row.withApplicant ?? row.with_applicant_count ?? row.pipeline_count,
  );
  const rejected = asCount(row.rejected ?? row.rejected_count);
  const backout = asCount(row.backout ?? row.backout_count);
  const failedBackout =
    asCount(row.failed_backout ?? row.failedBackout) || rejected + backout;
  const hired = asCount(row.hired ?? row.hired_count);
  const closure = asCount(row.closure ?? row.closure_count);

  // No single "pending review" counter is exposed by get_web_vacancy_summary; left at 0.
  const pendingReview = asCount(
    row.pending_review ?? row.pending_review_count ?? row.pending_approval_count,
  );
  // No single "aging watch" counter is exposed; derive it from the aging buckets that are.
  const agingWatch =
    asCount(row.aging_watch ?? row.aging_watch_count ?? row.aging_count) ||
    asCount(row.aging_31_plus) + asCount(row.aging_unknown);

  return {
    open,
    pipeline,
    hired,
    closure,
    failedBackout,
    withApplicant: pipeline,
    rejected,
    backout,
    pendingReview,
    agingWatch,
    total: asCount(row.total ?? row.total_count) || open + pipeline + hired + closure + failedBackout,
  };
}

// Maps the frontend queue tab to the p_status value understood by the deployed RPCs.
// The backend filters on vacancy_status and pipeline_status (= derived_status from vw_vacancy_list).
// derived_status values: 'Open' (no active applicants), 'Pipeline' (has active applicants),
// 'Hired', 'Archived'. Rejected/backout tabs have no direct list-level status mapping;
// null returns all scoped active rows for those tabs.
function tabToRpcStatus(tab?: VacancyStatus): string | null {
  if (!tab) return null;
  switch (tab) {
    case "open":           return "Open";
    case "pipeline":       return "Pipeline";
    case "with_applicant": return "Pipeline";
    case "hired":          return "Hired";
    case "closure":        return "Closure";
    case "failed_backout": return null;
    case "rejected":       return null;
    case "backout":        return null;
    default:               return null;
  }
}

function getSummaryRpcParams(
  params: Partial<
    Pick<
      VacancyListParams,
      "status" | "search" | "accountId" | "groupId" | "urgency" | "vacantFrom" | "vacantTo"
    >
  >,
) {
  return {
    p_status:      params.status ? tabToRpcStatus(params.status) : null,
    p_account_id:  asUuidFilter(params.accountId),
    p_group_id:    asUuidFilter(params.groupId),
    p_urgency:     normalizeUrgency(params.urgency) ?? null,
    p_search:      asTrimmedString(params.search) ?? null,
    p_vacant_from: asDateFilter(params.vacantFrom) ?? null,
    p_vacant_to:   asDateFilter(params.vacantTo) ?? null,
  };
}

function getListRpcParams(params: VacancyListParams, pageSize: number, offset: number) {
  return {
    p_status:       tabToRpcStatus(params.status),
    p_account_id:   asUuidFilter(params.accountId),
    p_group_id:     asUuidFilter(params.groupId),
    p_aging_bucket: normalizeAgingBucket(params.agingBucket) ?? null,
    p_urgency:      normalizeUrgency(params.urgency) ?? null,
    p_search:       asTrimmedString(params.search) ?? null,
    p_vacant_from:  asDateFilter(params.vacantFrom) ?? null,
    p_vacant_to:    asDateFilter(params.vacantTo) ?? null,
    p_limit:        pageSize,
    p_offset:       offset,
    p_sort_by:      normalizeSortField("aging_days"),
    p_sort_dir:     normalizeSortDirection("desc"),
  };
}

export async function getVacancySummary(
  params: Partial<
    Pick<
      VacancyListParams,
      | "status"
      | "search"
      | "agingBucket"
      | "accountId"
      | "groupId"
      | "position"
      | "urgency"
      | "vacantFrom"
      | "vacantTo"
    >
  >,
) {
  const supabase = createClient();
  const summaryRpcParams = getSummaryRpcParams(params);

  const summaryPromise = supabase.rpc(
    "get_web_vacancy_summary",
    summaryRpcParams,
  );


  // Hired tab count: query fn_get_hired_applicants matching mobile service
  const hiredPromise = (async () => {
    try {
      const { data, error } = await supabase.rpc("fn_get_hired_applicants");
      if (error) {
        console.warn("getVacancySummary fn_get_hired_applicants error:", error.message);
        return 0;
      }
      return Array.isArray(data) ? data.length : 0;
    } catch {
      return 0;
    }
  })();

  // Closure tab count: checks for status IN ('closure', 'for_closure'), has_pending_closure = true, OR existing pending closure request
  const closurePromise = (async () => {
    try {
      // 1. Fetch pending requests from vacancy_closure_requests
      const { data: rawRequests } = await supabase
        .from("vacancy_closure_requests")
        .select("id, vacancy_vcode, status")
        .ilike("status", "pending");

      const pendingVcodes = new Set(
        (rawRequests ?? []).map((r) => r.vacancy_vcode).filter(Boolean),
      );

      // 2. Query active vacancies that match either the pending requests, has_pending_closure, or closure status
      let vacQuery = supabase
        .from("vacancies")
        .select("id, vcode, account_id, group_id, has_pending_closure, closure_request_status, status, is_archived, deleted_at")
        .eq("is_archived", false)
        .is("deleted_at", null);

      if (params.accountId) {
        vacQuery = vacQuery.eq("account_id", params.accountId);
      }
      if (params.groupId) {
        vacQuery = vacQuery.eq("group_id", params.groupId);
      }

      const { data: activeVacs, error: vacError } = await vacQuery;
      if (vacError || !activeVacs) {
        return pendingVcodes.size;
      }

      const closureVacs = activeVacs.filter((v) => {
        const vcode = v.vcode;
        const statusLower = (v.status || "").toLowerCase().trim();
        const closureReqStatusLower = (v.closure_request_status || "").toLowerCase().trim();
        const isClosureStatus = statusLower === "closure" || statusLower === "for_closure";
        const hasPendingFlag = v.has_pending_closure === true || closureReqStatusLower === "pending";
        const hasPendingRequest = vcode ? pendingVcodes.has(vcode) : false;

        return isClosureStatus || hasPendingFlag || hasPendingRequest;
      });

      return closureVacs.length;
    } catch {
      return 0;
    }
  })();

  // Failed / Backout tab count: restricted to active dropout applicants on active vacancies
  const failedPromise = (async () => {
    try {
      const { data: dropouts, error } = await supabase
        .from("applicants")
        .select("id, vacancy_vcode, status, is_archived")
        .eq("is_archived", false)
        .in("status", [
          "Backout", "backout",
          "Rejected", "rejected",
          "Failed", "failed",
          "Did Not Report", "did not report",
          "Rejected by Ops", "rejected by ops",
        ]);

      if (error || !dropouts || dropouts.length === 0) return 0;

      const vcodes = Array.from(new Set(dropouts.map((d) => d.vacancy_vcode).filter(Boolean)));
      if (vcodes.length === 0) return 0;

      let vacQuery = supabase
        .from("vacancies")
        .select("vcode, account_id, group_id")
        .in("vcode", vcodes)
        .eq("is_archived", false)
        .is("deleted_at", null);

      if (params.accountId) {
        vacQuery = vacQuery.eq("account_id", params.accountId);
      }
      if (params.groupId) {
        vacQuery = vacQuery.eq("group_id", params.groupId);
      }

      const { data: activeVacs } = await vacQuery;
      const activeVcodeSet = new Set((activeVacs ?? []).map((v) => v.vcode));
      return dropouts.filter((d) => activeVcodeSet.has(d.vacancy_vcode)).length;
    } catch {
      return 0;
    }
  })();

  const [summaryRes, hiredCountResult, closureCountResult, failedCountResult] = await Promise.allSettled([
    summaryPromise,
    hiredPromise,
    closurePromise,
    failedPromise,
  ]);

  if (summaryRes.status === "rejected") {
    throw new VacancyDataError("retryable", String(summaryRes.reason));
  }
  if (summaryRes.value.error) {
    throwVacancyError(summaryRes.value.error);
  }

  const baseSummary = normalizeSummary(summaryRes.value.data);

  const hiredCount =
    hiredCountResult.status === "fulfilled"
      ? hiredCountResult.value
      : 0;

  const closureCount =
    closureCountResult.status === "fulfilled"
      ? closureCountResult.value
      : 0;

  const failedCount =
    failedCountResult.status === "fulfilled"
      ? failedCountResult.value
      : 0;

  return {
    ...baseSummary,
    hired: hiredCount,
    closure: closureCount,
    failedBackout: failedCount,
    total: baseSummary.open + baseSummary.pipeline + hiredCount + closureCount + failedCount,
  };
}

export async function listVacancies(params: VacancyListParams) {
  const supabase = createClient();
  const page = Math.max(1, Math.trunc(params.page));
  const pageSize = Math.min(
    MAX_PAGE_SIZE,
    Math.max(1, Math.trunc(params.pageSize)),
  );
  const offset = (page - 1) * pageSize;
  const currentTab = params.status;

  if (currentTab === "hired") {
    // 2. Hired Tab: Populate rows using the hired applicants source (fn_get_hired_applicants)
    try {
      const { data: hiredData, error: hiredError } = await supabase.rpc("fn_get_hired_applicants");
      if (!hiredError && Array.isArray(hiredData)) {
        const hiredRows: VacancyListItem[] = hiredData.map((h: Record<string, unknown>, idx: number) => {
          const lName = asString(h.last_name);
          const fName = asString(h.first_name);
          const rawFull = asString(h.full_name);
          const workerName = rawFull
            ? rawFull
            : lName && fName
            ? `${lName}, ${fName}`
            : lName || fName || "Hired Worker";

          const hiredDate = asString(h.hired_date ?? h.hired_at);
          const position = asString(h.position_name ?? h.position);
          const vcode = asString(h.vacancy_vcode) ?? "Uncoded";
          const groupName = asString(h.group_name);
          const account = asString(h.account);

          return {
            id: asString(h.id) ?? `hired-${idx}`,
            vcode,
            accountId: null,
            accountName: account,
            groupId: null,
            groupName,
            storeId: null,
            storeName: null,
            storeLocation: null,
            position_title: position,
            department: null,
            employmentType: null,
            vacancyStatus: "Filled",
            pipelineStatus: "Hired",
            derivedStatus: "Hired",
            activeApplicantCount: 0,
            confirmedOnboardCount: 1,
            hasRecentHire: true,
            hasPendingClosure: false,
            closureRequestStatus: null,
            vacantDate: hiredDate,
            agingDays: null,
            agingBucket: null,
            targetFillDate: null,
            urgencyLevel: null,
            hrcoName: asString(h.hired_by) ?? "HR Team",
            applicantId: asString(h.id),
            applicantName: workerName,
            contactNumber: asString(h.contact_number),
            hiredDate,
            hasPenalty: false,
            penaltyExposure: 0,
            penaltyAmount: null,
            lastActivityAt: asString(h.hired_at),
            rowCapabilities: {
              canViewDetail: true,
              canApprove: false,
              canUpdateApplicantStatus: false,
              canRequestClosure: false,
              raw: {},
            },
            totalCount: hiredData.length,
          };
        });

        // Enrich store info for hired rows if vcodes exist
        const hiredVcodes = Array.from(new Set(hiredRows.map((r) => r.vcode).filter(Boolean)));
        if (hiredVcodes.length > 0) {
          try {
            const { data: vacsData } = await supabase
              .from("vacancies")
              .select("vcode, store_name, area_city, province, store_id, account_id, group_id, account, group_name")
              .in("vcode", hiredVcodes)
              .eq("is_archived", false)
              .is("deleted_at", null);

            if (vacsData && vacsData.length > 0) {
              const vacMap = new Map(vacsData.map((v) => [v.vcode, v]));
              for (const row of hiredRows) {
                if (vacMap.has(row.vcode)) {
                  const v = vacMap.get(row.vcode)!;
                  row.storeName = v.store_name || null;
                  row.accountId = v.account_id || row.accountId;
                  row.groupId = v.group_id || row.groupId;
                  row.storeId = v.store_id || row.storeId;
                  row.accountName = row.accountName || v.account || null;
                  row.groupName = row.groupName || v.group_name || null;
                  const loc = [v.area_city, v.province].filter(Boolean).join(" • ");
                  if (loc) row.storeLocation = loc;
                }
              }
            }
          } catch {
            // Graceful fallback
          }
        }

        // Apply filters & search on hiredRows
        let filteredHired = hiredRows;
        if (params.accountId) {
          filteredHired = filteredHired.filter((r) => r.accountId === params.accountId);
        }
        if (params.groupId) {
          filteredHired = filteredHired.filter((r) => r.groupId === params.groupId);
        }
        if (params.search) {
          const q = params.search.toLowerCase();
          filteredHired = filteredHired.filter(
            (r) =>
              r.vcode.toLowerCase().includes(q) ||
              (r.applicantName && r.applicantName.toLowerCase().includes(q)) ||
              (r.position_title && r.position_title.toLowerCase().includes(q)) ||
              (r.storeName && r.storeName.toLowerCase().includes(q)) ||
              (r.accountName && r.accountName.toLowerCase().includes(q)),
          );
        }

        const paginatedHired = filteredHired.slice(offset, offset + pageSize);
        for (const r of paginatedHired) {
          r.totalCount = filteredHired.length;
        }

        return {
          data: paginatedHired,
          totalCount: filteredHired.length,
          page,
          pageSize,
        };
      }
    } catch {
      // Return empty list on failure
    }
    return {
      data: [],
      totalCount: 0,
      page,
      pageSize,
    };
  }

  if (currentTab === "closure") {
    // 3. Closure Tab: Restrict to active vacancies with pending closure requests, has_pending_closure, or status IN ('closure', 'for_closure')
    try {
      // 1. Fetch pending requests from vacancy_closure_requests
      const { data: closureRequests } = await supabase
        .from("vacancy_closure_requests")
        .select("id, vacancy_vcode, reason, details, status, requested_by, created_at")
        .ilike("status", "pending")
        .order("created_at", { ascending: false });

      const requestMap = new Map<string, Record<string, unknown>>();
      if (Array.isArray(closureRequests)) {
        for (const cr of closureRequests) {
          const vcode = asString(cr.vacancy_vcode);
          if (vcode && !requestMap.has(vcode)) {
            requestMap.set(vcode, cr as Record<string, unknown>);
          }
        }
      }

      // 2. Fetch active vacancies
      let vacQuery = supabase
        .from("vacancies")
        .select(`
          id,
          vcode,
          store_name,
          store_branch,
          position,
          account,
          account_id,
          group_id,
          area_city,
          province,
          is_archived,
          deleted_at,
          has_pending_closure,
          closure_request_status,
          status,
          created_at,
          updated_at
        `)
        .eq("is_archived", false)
        .is("deleted_at", null);

      if (params.accountId) {
        vacQuery = vacQuery.eq("account_id", params.accountId);
      }
      if (params.groupId) {
        vacQuery = vacQuery.eq("group_id", params.groupId);
      }

      const { data: activeVacs, error: vacError } = await vacQuery;

      if (!vacError && Array.isArray(activeVacs)) {
        const closureVacs = activeVacs.filter((vac: Record<string, unknown>) => {
          const vcode = asString(vac.vcode);
          const statusLower = (asString(vac.status) || "").toLowerCase().trim();
          const closureReqStatusLower = (asString(vac.closure_request_status) || "").toLowerCase().trim();
          const isClosureStatus = statusLower === "closure" || statusLower === "for_closure";
          const hasPendingFlag = asBoolean(vac.has_pending_closure) || closureReqStatusLower === "pending";
          const hasPendingRequest = vcode ? requestMap.has(vcode) : false;

          return isClosureStatus || hasPendingFlag || hasPendingRequest;
        });

        const closureRows: VacancyListItem[] = closureVacs.map((vac: Record<string, unknown>, idx: number) => {
          const vcode = asString(vac.vcode) ?? "Uncoded";
          const cr = requestMap.get(vcode);
          const storeName = asString(vac.store_name ?? vac.store_branch);
          const position = asString(vac.position) ?? "—";
          const account = asString(vac.account);
          const loc = [asString(vac.area_city), asString(vac.province)]
            .filter(Boolean)
            .join(" • ") || null;

          const closureReason =
            asString(cr?.reason) ??
            asString(cr?.details) ??
            asString(vac.closure_reason) ??
            "Store Closed / Outlet Ceased Operations";
          const closureRequestedBy =
            asString(cr?.requested_by) ??
            asString(vac.closure_requested_by) ??
            "Operations";
          const closureRequestedAt =
            asString(cr?.created_at) ??
            asString(vac.closure_requested_at) ??
            asString(vac.updated_at);
          const closureRequestId = asString(cr?.id) ?? null;

          return {
            id: asString(vac.id) ?? asString(cr?.id) ?? `closure-${idx}`,
            vcode,
            accountId: asString(vac.account_id),
            accountName: account,
            groupId: asString(vac.group_id),
            groupName: null,
            storeId: null,
            storeName,
            storeLocation: loc,
            position_title: position,
            department: null,
            employmentType: null,
            vacancyStatus: "Closure",
            pipelineStatus: "Pending Closure",
            derivedStatus: "For Closure",
            activeApplicantCount: 0,
            confirmedOnboardCount: 0,
            hasRecentHire: false,
            hasPendingClosure: true,
            closureRequestStatus: "Pending",
            vacantDate: closureRequestedAt,
            agingDays: null,
            agingBucket: null,
            targetFillDate: null,
            urgencyLevel: null,
            hrcoName: "—",
            applicantId: null,
            applicantName: null,
            contactNumber: null,
            hiredDate: null,
            closureReason,
            closureRequestedBy,
            closureRequestedAt,
            closureRequestId,
            hasPenalty: false,
            penaltyExposure: 0,
            penaltyAmount: null,
            lastActivityAt: closureRequestedAt,
            rowCapabilities: {
              canViewDetail: true,
              canApprove: true,
              canUpdateApplicantStatus: false,
              canRequestClosure: false,
              raw: {},
            },
            totalCount: closureVacs.length,
          };
        });

        let filteredClosure = closureRows;
        if (params.search) {
          const q = params.search.toLowerCase();
          filteredClosure = filteredClosure.filter(
            (r) =>
              r.vcode.toLowerCase().includes(q) ||
              (r.position_title && r.position_title.toLowerCase().includes(q)) ||
              (r.storeName && r.storeName.toLowerCase().includes(q)) ||
              (r.accountName && r.accountName.toLowerCase().includes(q)) ||
              (r.closureReason && r.closureReason.toLowerCase().includes(q)) ||
              (r.closureRequestedBy && r.closureRequestedBy.toLowerCase().includes(q)),
          );
        }

        const paginatedClosure = filteredClosure.slice(offset, offset + pageSize);
        for (const r of paginatedClosure) {
          r.totalCount = filteredClosure.length;
        }

        return {
          data: paginatedClosure,
          totalCount: filteredClosure.length,
          page,
          pageSize,
        };
      }
    } catch {
      return {
        data: [],
        totalCount: 0,
        page,
        pageSize,
      };
    }

    return {
      data: [],
      totalCount: 0,
      page,
      pageSize,
    };
  }

  if (currentTab === "failed_backout") {
    // 4. Failed / Backout Tab: Display active dropout / failed / backout records from active vacancies
    try {
      const { data: dropoutsData, error: dropoutsError } = await supabase
        .from("applicants")
        .select(`
          id,
          vacancy_vcode,
          first_name,
          last_name,
          full_name,
          contact_number,
          status,
          backout_reason,
          backout_date,
          created_at,
          updated_at
        `)
        .eq("is_archived", false)
        .in("status", [
          "Backout", "backout",
          "Rejected", "rejected",
          "Failed", "failed",
          "Did Not Report", "did not report",
          "Rejected by Ops", "rejected by ops",
        ])
        .order("created_at", { ascending: false });

      if (!dropoutsError && Array.isArray(dropoutsData) && dropoutsData.length > 0) {
        const dropoutVcodes = Array.from(new Set(dropoutsData.map((d) => d.vacancy_vcode).filter(Boolean)));
        let vacQuery = supabase
          .from("vacancies")
          .select("id, vcode, store_name, store_branch, store_id, position, account, account_id, group_id, area_city, province, hrco_name, vacant_date, target_fill_date, urgency_level, is_archived, deleted_at")
          .in("vcode", dropoutVcodes)
          .eq("is_archived", false)
          .is("deleted_at", null);

        if (params.accountId) {
          vacQuery = vacQuery.eq("account_id", params.accountId);
        }
        if (params.groupId) {
          vacQuery = vacQuery.eq("group_id", params.groupId);
        }

        const { data: vacsData } = await vacQuery;
        const vacMap = new Map((vacsData ?? []).map((v) => [v.vcode, v]));

        // Filter dropouts to only those linked to active, non-archived vacancies
        const validDropouts = dropoutsData.filter((d) => vacMap.has(d.vacancy_vcode));

        const failedRows: VacancyListItem[] = validDropouts.map((d: Record<string, unknown>, idx: number) => {
          const vcode = asString(d.vacancy_vcode) ?? "Uncoded";
          const vac = vacMap.get(vcode);
          const lName = asString(d.last_name);
          const fName = asString(d.first_name);
          const fFull = asString(d.full_name);
          const candidateName = fFull || (lName && fName ? `${lName}, ${fName}` : lName || fName || "Candidate");
          const storeName = asString(vac?.store_name ?? vac?.store_branch);
          const position = asString(vac?.position) ?? "—";
          const loc = [asString(vac?.area_city), asString(vac?.province)].filter(Boolean).join(" • ") || null;
          const status = asString(d.status) || "Failed / Backout";
          const dropoutReason = asString(d.backout_reason) || status;
          const dropoutDate = asString(d.backout_date ?? d.updated_at ?? d.created_at);

          return {
            id: asString(vac?.id) ?? asString(d.id) ?? `failed-${idx}`,
            vcode,
            accountId: asString(vac?.account_id),
            accountName: asString(vac?.account),
            groupId: asString(vac?.group_id),
            groupName: null,
            storeId: asString(vac?.store_id),
            storeName,
            storeLocation: loc,
            position_title: position,
            department: null,
            employmentType: null,
            vacancyStatus: "Open",
            pipelineStatus: "Failed / Backout",
            derivedStatus: "Failed / Backout",
            activeApplicantCount: 0,
            confirmedOnboardCount: 0,
            hasRecentHire: false,
            hasPendingClosure: false,
            closureRequestStatus: null,
            vacantDate: asString(vac?.vacant_date),
            agingDays: null,
            agingBucket: null,
            targetFillDate: asString(vac?.target_fill_date),
            urgencyLevel: asString(vac?.urgency_level),
            hrcoName: asString(vac?.hrco_name) ?? "—",
            applicantId: asString(d.id),
            applicantName: candidateName,
            contactNumber: asString(d.contact_number),
            hiredDate: null,
            dropoutReason,
            dropoutDate,
            hasPenalty: false,
            penaltyExposure: 0,
            penaltyAmount: null,
            lastActivityAt: asString(d.updated_at ?? d.created_at),
            rowCapabilities: {
              canViewDetail: true,
              canApprove: false,
              canUpdateApplicantStatus: false,
              canRequestClosure: true,
              raw: {},
            },
            totalCount: validDropouts.length,
          };
        });

        let filteredFailed = failedRows;
        if (params.accountId) {
          filteredFailed = filteredFailed.filter((r) => r.accountId === params.accountId);
        }
        if (params.groupId) {
          filteredFailed = filteredFailed.filter((r) => r.groupId === params.groupId);
        }
        if (params.search) {
          const q = params.search.toLowerCase();
          filteredFailed = filteredFailed.filter(
            (r) =>
              r.vcode.toLowerCase().includes(q) ||
              (r.applicantName && r.applicantName.toLowerCase().includes(q)) ||
              (r.position_title && r.position_title.toLowerCase().includes(q)) ||
              (r.storeName && r.storeName.toLowerCase().includes(q)) ||
              (r.accountName && r.accountName.toLowerCase().includes(q)) ||
              (r.dropoutReason && r.dropoutReason.toLowerCase().includes(q)),
          );
        }

        const paginatedFailed = filteredFailed.slice(offset, offset + pageSize);
        for (const r of paginatedFailed) {
          r.totalCount = filteredFailed.length;
        }

        return {
          data: paginatedFailed,
          totalCount: filteredFailed.length,
          page,
          pageSize,
        };
      }
    } catch {
      // Graceful fallback
    }

    return {
      data: [],
      totalCount: 0,
      page,
      pageSize,
    };
  }

  const { data, error } = await supabase.rpc("list_web_vacancies", getListRpcParams(params, pageSize, offset));

  if (error) {
    throwVacancyError(error);
  }

  const rows = (Array.isArray(data) ? data : [])
    .map((row) => normalizeListRow(asObject(row)))
    .filter((row): row is VacancyListItem => row !== null);

  // Enrich missing store locations via stores table lookup
  const missingStoreIds = Array.from(
    new Set(
      rows
        .filter((r) => !r.storeLocation && r.storeId)
        .map((r) => r.storeId as string),
    ),
  );

  if (missingStoreIds.length > 0) {
    try {
      const { data: storesData } = await supabase
        .from("stores")
        .select("id, store_name, area_city, area_province, province")
        .in("id", missingStoreIds);

      if (storesData && storesData.length > 0) {
        const storeLocationMap = new Map<string, string>();
        for (const s of storesData) {
          const loc = [s.area_city, s.area_province || s.province]
            .filter(Boolean)
            .join(" • ");
          if (loc) {
            storeLocationMap.set(s.id, loc);
          }
        }

        for (const row of rows) {
          if (row.storeId && storeLocationMap.has(row.storeId)) {
            row.storeLocation = storeLocationMap.get(row.storeId) ?? null;
          }
        }
      }
    } catch {
      // Graceful fallback if stores lookup fails
    }
  }

  // Secondary fallback by store_name for rows where storeId was missing
  const missingStoreNames = Array.from(
    new Set(
      rows
        .filter((r) => !r.storeLocation && r.storeName)
        .map((r) => r.storeName as string),
    ),
  );

  if (missingStoreNames.length > 0) {
    try {
      const { data: storesByName } = await supabase
        .from("stores")
        .select("store_name, area_city, area_province, province")
        .in("store_name", missingStoreNames);

      if (storesByName && storesByName.length > 0) {
        const nameLocationMap = new Map<string, string>();
        for (const s of storesByName) {
          const loc = [s.area_city, s.area_province || s.province]
            .filter(Boolean)
            .join(" • ");
          if (loc && s.store_name) {
            nameLocationMap.set(s.store_name, loc);
          }
        }

        for (const row of rows) {
          if (!row.storeLocation && row.storeName && nameLocationMap.has(row.storeName)) {
            row.storeLocation = nameLocationMap.get(row.storeName) ?? null;
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Enrich missing hrcoName via vacancies table lookup and account-level fallback
  const rowsMissingHrco = rows.filter((r) => !r.hrcoName);
  if (rowsMissingHrco.length > 0) {
    try {
      const vcodesMissingHrco = Array.from(
        new Set(rowsMissingHrco.map((r) => r.vcode).filter(Boolean)),
      );
      if (vcodesMissingHrco.length > 0) {
        const { data: vacHrcoData } = await supabase
          .from("vacancies")
          .select("vcode, hrco_name, account_id, account")
          .in("vcode", vcodesMissingHrco);

        if (vacHrcoData && vacHrcoData.length > 0) {
          const hrcoMap = new Map<string, string>();
          for (const v of vacHrcoData) {
            if (v.vcode && v.hrco_name) {
              hrcoMap.set(v.vcode, v.hrco_name);
            }
          }
          for (const row of rows) {
            if (!row.hrcoName && hrcoMap.has(row.vcode)) {
              row.hrcoName = hrcoMap.get(row.vcode) ?? null;
            }
          }
        }
      }

      // Secondary fallback: if still missing hrcoName, resolve via account HRCO assignment
      const stillMissing = rows.filter((r) => !r.hrcoName);
      if (stillMissing.length > 0) {
        const accountIds = Array.from(
          new Set(stillMissing.map((r) => r.accountId).filter(Boolean) as string[]),
        );
        const accountNames = Array.from(
          new Set(stillMissing.map((r) => r.accountName).filter(Boolean) as string[]),
        );

        let acctQuery = supabase
          .from("accounts")
          .select("id, account_name, hrco_user_id, users_profile!accounts_hrco_user_id_fkey(full_name)");

        if (accountIds.length > 0) {
          acctQuery = acctQuery.in("id", accountIds);
        } else if (accountNames.length > 0) {
          acctQuery = acctQuery.in("account_name", accountNames);
        }

        const { data: acctsData, error: acctErr } = await acctQuery;

        // If join fails due to relationship name, query accounts and users_profile separately
        const acctHrcoMap = new Map<string, string>();
        if (!acctErr && acctsData) {
          for (const a of acctsData as Array<Record<string, unknown>>) {
            const profile = a.users_profile as Record<string, unknown> | null;
            const hrcoFullName = asString(profile?.full_name);
            if (hrcoFullName) {
              if (a.id) acctHrcoMap.set(String(a.id), hrcoFullName);
              if (a.account_name) acctHrcoMap.set(String(a.account_name).toLowerCase().trim(), hrcoFullName);
            }
          }
        } else {
          // Manual fallback: select accounts then users_profile
          const { data: rawAccounts } = await supabase
            .from("accounts")
            .select("id, account_name, hrco_user_id")
            .in("account_name", accountNames.length > 0 ? accountNames : ["ACTISERVE"]);

          if (rawAccounts && rawAccounts.length > 0) {
            const hrcoUserIds = Array.from(
              new Set(rawAccounts.map((a) => a.hrco_user_id).filter(Boolean)),
            );
            if (hrcoUserIds.length > 0) {
              const { data: profiles } = await supabase
                .from("users_profile")
                .select("id, full_name")
                .in("id", hrcoUserIds);

              if (profiles) {
                const profileMap = new Map(profiles.map((p) => [p.id, p.full_name]));
                for (const a of rawAccounts) {
                  const name = a.hrco_user_id ? profileMap.get(a.hrco_user_id) : null;
                  if (name) {
                    if (a.id) acctHrcoMap.set(String(a.id), name);
                    if (a.account_name) acctHrcoMap.set(String(a.account_name).toLowerCase().trim(), name);
                  }
                }
              }
            }
          }
        }

        // Apply account HRCO name to remaining rows
        for (const row of rows) {
          if (!row.hrcoName) {
            const nameByAcctId = row.accountId ? acctHrcoMap.get(row.accountId) : null;
            const nameByAcctName = row.accountName
              ? acctHrcoMap.get(row.accountName.toLowerCase().trim())
              : null;
            row.hrcoName = nameByAcctId || nameByAcctName || row.hrcoName || null;
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Enrich applicant details based on active applicants:
  const allVcodes = Array.from(new Set(rows.map((r) => r.vcode).filter(Boolean)));

  if (allVcodes.length > 0) {
    try {
      const { data: applicantsData } = await supabase
        .from("applicants")
        .select("id, vacancy_vcode, first_name, last_name, full_name, contact_number, status, hired_date, backout_reason, backout_date, created_at, updated_at")
        .in("vacancy_vcode", allVcodes)
        .eq("is_archived", false)
        .order("created_at", { ascending: false });

      if (applicantsData && applicantsData.length > 0) {
        // Group active applicants by vcode
        const activeByVcode = new Map<string, Array<Record<string, unknown>>>();

        for (const app of applicantsData) {
          const vcode = app.vacancy_vcode;
          const status = (app.status || "").toLowerCase().trim();
          const isDropout =
            status === "backout" ||
            status === "rejected" ||
            status === "failed" ||
            status === "did not report" ||
            status === "rejected by ops";

          if (!isDropout) {
            if (!activeByVcode.has(vcode)) activeByVcode.set(vcode, []);
            activeByVcode.get(vcode)!.push(app);
          }
        }

        for (const row of rows) {
          if (currentTab === "open") {
            // Open tab: Vacancies strictly without active candidate.
            row.applicantId = null;
            row.applicantName = null;
            row.contactNumber = null;
            row.stageBadge = null;
          } else {
            // Pipeline, etc.
            const actives = activeByVcode.get(row.vcode);
            const active = actives && actives[0];
            if (active) {
              row.applicantId = asString(active.id);
              row.contactNumber = row.contactNumber || asString(active.contact_number);
              row.hiredDate = row.hiredDate || asString(active.hired_date);
              const lName = asString(active.last_name);
              const fName = asString(active.first_name);
              const fFull = asString(active.full_name);
              row.applicantName = fFull || (lName && fName ? `${lName}, ${fName}` : lName || fName || row.applicantName);
              row.stageBadge = asString(active.status) || "In Pipeline";
            }
          }
        }
      }
    } catch {
      // Graceful fallback if applicants lookup fails
    }
  }

  // Final Tab Scoping Enforcement:
  // For Open Tab: Exclude any vacancy that has an active candidate assigned, active applicant count > 0,
  // or active in-flight closure requests (hasPendingClosure, closureRequestStatus = 'Pending', derivedStatus = 'For Closure')
  let finalRows = rows;
  if (currentTab === "open") {
    finalRows = rows.filter((r) => {
      const hasActive =
        (r.activeApplicantCount && r.activeApplicantCount > 0) ||
        Boolean(r.applicantName);
      const isPendingClosure =
        r.hasPendingClosure === true ||
        (r.closureRequestStatus && r.closureRequestStatus.toLowerCase() === "pending") ||
        r.derivedStatus?.toLowerCase() === "for closure" ||
        r.derivedStatus?.toLowerCase() === "closure" ||
        r.vacancyStatus?.toLowerCase() === "for_closure" ||
        r.vacancyStatus?.toLowerCase() === "closure";
      return !hasActive && !isPendingClosure;
    });
    for (const r of finalRows) {
      r.applicantId = null;
      r.applicantName = null;
      r.contactNumber = null;
      r.stageBadge = null;
    }
  }

  return {
    data: finalRows,
    totalCount: currentTab === "open" ? finalRows.length : getTotalCount(finalRows),
    page,
    pageSize,
  };
}

export async function getVacancyDetail(vacancyId: string): Promise<VacancyDetailItem> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_vacancy_detail", {
    p_vacancy_id: vacancyId,
  });

  if (error) {
    const errorKind = getErrorKind(error);
    // If access is denied (often caused by vw_vacancy_detail active-only constraint for Filled/Closed slots),
    // attempt fallback lookup for hired applicants or direct vacancy record.
    if (errorKind === "access_denied" || error.code === "42501" || error.message.includes("out of scope")) {
      try {
        // 1. Try fn_get_hired_applicants
        const { data: hiredData } = await supabase.rpc("fn_get_hired_applicants");
        if (Array.isArray(hiredData)) {
          const match = hiredData.find(
            (h: Record<string, unknown>) =>
              String(h.id) === vacancyId ||
              String(h.vacancy_vcode) === vacancyId ||
              String(h.applicant_id) === vacancyId,
          );

          if (match) {
            const vcode = asString(match.vacancy_vcode) ?? "Uncoded";
            const lName = asString(match.last_name);
            const fName = asString(match.first_name);
            const rawFull = asString(match.full_name);
            const workerName = rawFull || (lName && fName ? `${lName}, ${fName}` : lName || fName || "Hired Worker");
            const hiredDate = asString(match.hired_date ?? match.hired_at);
            const pos = asString(match.position_name ?? match.position);

            // Fetch vacancy info if available
            let vacRow: Record<string, unknown> | null = null;
            try {
              const { data: vacData } = await supabase
                .from("vacancies")
                .select("*")
                .eq("vcode", vcode)
                .maybeSingle();
              vacRow = vacData;
            } catch {
              // fallback
            }

            const areaCity = asString(vacRow?.area_city);
            const areaProvince = asString(vacRow?.area_province ?? vacRow?.province);
            const storeLocation = [areaCity, areaProvince].filter(Boolean).join(" • ") || null;

            return {
              vacancyId,
              vcode,
              accountId: asString(vacRow?.account_id),
              accountName: asString(match.account ?? vacRow?.account),
              groupId: asString(vacRow?.group_id),
              groupName: asString(match.group_name ?? vacRow?.group_name),
              storeId: asString(vacRow?.store_id),
              storeName: asString(vacRow?.store_name ?? vacRow?.store),
              position_title: pos || asString(vacRow?.position),
              department: asString(vacRow?.department ?? vacRow?.business_unit),
              employmentType: asString(vacRow?.employment_type),
              vacancyStatus: "Filled",
              pipelineStatus: "Hired",
              derivedStatus: "Hired",
              activeApplicantCount: 0,
              confirmedOnboardCount: 1,
              hasRecentHire: true,
              hasPendingClosure: false,
              closureRequestStatus: null,
              vacantDate: hiredDate,
              agingDays: null,
              agingBucket: null,
              targetFillDate: null,
              urgencyLevel: null,
              hrcoName: asString(match.hired_by ?? vacRow?.hrco_name) ?? "HR Team",
              lastActivityAt: asString(match.hired_at),
              rowCapabilities: {
                canViewDetail: true,
                canApprove: false,
                canUpdateApplicantStatus: false,
                canRequestClosure: false,
                raw: {},
              },
              contactNumber: asString(match.contact_number),
              onboardDate: hiredDate,
              relieverOnDuty: null,
              hasReliever: false,
              hrcoRemarks: null,
              recruiterName: null,
              deployedByName: asString(match.hired_by),
              hasPenalty: false,
              penaltyExposure: 0,
              penaltyAmount: null,
              applicantLastName: lName,
              applicantFirstName: fName,
              applicantName: workerName,
              storeLocation,
              areaCity,
              areaProvince,
              storeBranch: asString(vacRow?.store_branch),
              requestedById: null,
              requestedByName: null,
              approvedById: null,
              approvedByName: null,
              approvedAt: null,
              headcountRequestId: null,
              vacancyReason: null,
              jobDescription: null,
              closureRequestedAt: null,
              closureRequestedBy: null,
              closureReason: null,
              activeApplicantsList: [
                {
                  applicantId: asString(match.id) ?? vacancyId,
                  displayName: workerName,
                  lastName: lName,
                  firstName: fName,
                  contactNumber: asString(match.contact_number),
                  statusLabel: "Confirmed Onboard",
                  onboardDate: hiredDate,
                  updatedAt: asString(match.hired_at),
                  recruiterName: null,
                  deployedByName: asString(match.hired_by),
                },
              ],
              activityHistory: [],
            };
          }
        }
      } catch {
        // Fall through to original error throw
      }
    }

    throwVacancyError(error);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new VacancyDataError("retryable", "No vacancy detail record found");
  }

  const normalized = normalizeDetailRow(asObject(row));
  if (!normalized) {
    throw new VacancyDataError("retryable", "Failed to normalize vacancy detail record");
  }

  if (!normalized.storeLocation && (normalized.storeId || normalized.storeName)) {
    try {
      let storeQuery = supabase
        .from("stores")
        .select("area_city, area_province, province");

      if (normalized.storeId) {
        storeQuery = storeQuery.eq("id", normalized.storeId);
      } else if (normalized.storeName) {
        storeQuery = storeQuery.eq("store_name", normalized.storeName);
      }

      const { data: storeRow } = await storeQuery.limit(1).maybeSingle();
      if (storeRow) {
        normalized.areaCity = normalized.areaCity || storeRow.area_city || null;
        normalized.storeLocation =
          [storeRow.area_city, storeRow.area_province || storeRow.province]
            .filter(Boolean)
            .join(" • ") || null;
      }
    } catch {
      // Graceful fallback
    }
  }

  if (!normalized.hrcoName && (normalized.accountId || normalized.accountName)) {
    try {
      const { data: rawAccount } = await supabase
        .from("accounts")
        .select("id, account_name, hrco_user_id")
        .eq(normalized.accountId ? "id" : "account_name", normalized.accountId || normalized.accountName)
        .maybeSingle();

      if (rawAccount?.hrco_user_id) {
        const { data: prof } = await supabase
          .from("users_profile")
          .select("full_name")
          .eq("id", rawAccount.hrco_user_id)
          .maybeSingle();

        if (prof?.full_name) {
          normalized.hrcoName = prof.full_name;
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Ensure pending closure details are enriched if applicable
  if (!normalized.hasPendingClosure && normalized.vcode) {
    try {
      const { data: vacCheck } = await supabase
        .from("vacancies")
        .select("has_pending_closure, closure_request_status")
        .eq("vcode", normalized.vcode)
        .maybeSingle();
      if (vacCheck) {
        if (vacCheck.has_pending_closure) normalized.hasPendingClosure = true;
        if (vacCheck.closure_request_status) normalized.closureRequestStatus = vacCheck.closure_request_status;
      }
    } catch {
      // Graceful fallback
    }
  }

  if (normalized.hasPendingClosure || normalized.closureRequestStatus === "Pending") {
    try {
      const { data: closureReq } = await supabase
        .from("vacancy_closure_requests")
        .select("id, reason, details, requested_by, created_at, status")
        .eq("vacancy_vcode", normalized.vcode)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (closureReq) {
        normalized.closureReason = closureReq.reason || closureReq.details || normalized.closureReason;
        normalized.closureRequestedBy = closureReq.requested_by || normalized.closureRequestedBy;
        normalized.closureRequestedAt = closureReq.created_at || normalized.closureRequestedAt;
        normalized.closureRequestStatus = closureReq.status || normalized.closureRequestStatus;
      }
    } catch {
      // Graceful fallback
    }
  }

  return normalized;
}

export type EndorseApplicantParams = {
  vcode: string;
  firstName: string;
  lastName: string;
  middleName?: string | null;
  contactNumber: string;
  targetOnboardDate?: string | null;
  recruiterName?: string | null;
  recruiterId?: string | null;
  hrcoRemarks?: string | null;
  status?: string;
};

export type EndorseApplicantResult = {
  id: string;
  vcode: string;
  fullName: string;
  status: string;
};

export async function endorseApplicant(
  params: EndorseApplicantParams,
): Promise<EndorseApplicantResult> {
  const supabase = createClient();
  const vcode = params.vcode.trim();
  const firstName = params.firstName.trim();
  const lastName = params.lastName.trim();
  const middleName = params.middleName?.trim() || null;
  const fullName = middleName
    ? `${lastName}, ${firstName} ${middleName}`
    : `${lastName}, ${firstName}`;
  
  // Normalize contact number: must be 11 digits starting with 09
  const cleanContact = params.contactNumber.replace(/[^0-9]/g, "");
  const normalizedContact =
    cleanContact.length === 10 && cleanContact.startsWith("9")
      ? `0${cleanContact}`
      : cleanContact;

  if (!vcode) {
    throw new VacancyDataError("validation", "Target VCode is required.");
  }
  if (!firstName || !lastName) {
    throw new VacancyDataError("validation", "First Name and Last Name are required.");
  }
  if (!normalizedContact || !/^09[0-9]{9}$/.test(normalizedContact)) {
    throw new VacancyDataError(
      "validation",
      "Contact number must be 11 digits starting with 09 (e.g. 09171234567).",
    );
  }

  // 1. Verify vacancy exists and get its status
  const { data: vac, error: vacError } = await supabase
    .from("vacancies")
    .select("id, vcode, status, deleted_at, is_archived, has_pending_closure")
    .eq("vcode", vcode)
    .maybeSingle();

  if (vacError) {
    throw new VacancyDataError("generic", vacError.message);
  }
  if (!vac) {
    throw new VacancyDataError("not_found", `Vacancy with VCode ${vcode} not found.`);
  }
  if (vac.deleted_at || vac.is_archived) {
    throw new VacancyDataError("validation", `Vacancy ${vcode} is archived or inactive.`);
  }
  if (vac.has_pending_closure) {
    throw new VacancyDataError("validation", `Vacancy ${vcode} is locked pending closure.`);
  }

  // 2. Insert applicant record (matching mobile VacancyService.addApplicant direct insert)
  const applicantInsertPayload: Record<string, unknown> = {
    vacancy_vcode: vcode,
    first_name: firstName,
    last_name: lastName,
    middle_name: middleName,
    full_name: fullName,
    contact_number: normalizedContact,
    status: params.status || "New",
    remarks: params.hrcoRemarks?.trim() || null,
  };

  if (params.targetOnboardDate) {
    applicantInsertPayload.interview_date = params.targetOnboardDate;
  }
  if (params.recruiterName) {
    applicantInsertPayload.recruited_by_name = params.recruiterName.trim();
  }
  if (params.recruiterId) {
    applicantInsertPayload.recruited_by_user_id = params.recruiterId;
  }

  const { data: insertedApp, error: insertError } = await supabase
    .from("applicants")
    .insert(applicantInsertPayload)
    .select("id, vacancy_vcode, full_name, status")
    .single();

  if (insertError) {
    if (insertError.code === "42501") {
      throw new VacancyDataError("access_denied", "You do not have permission to add applicants.");
    }
    throw new VacancyDataError("generic", insertError.message);
  }

  // 3. Status transition: Update vacancy status to 'Pipeline' / 'with_applicant' if it is 'Open'
  if (vac.status === "Open" || vac.status === "open") {
    const { error: updateVacError } = await supabase
      .from("vacancies")
      .update({
        status: "Pipeline",
        updated_at: new Date().toISOString(),
      })
      .eq("vcode", vcode);

    if (updateVacError) {
      console.warn("Failed to transition vacancy status to Pipeline:", updateVacError.message);
    }
  }

  return {
    id: insertedApp.id,
    vcode: insertedApp.vacancy_vcode,
    fullName: insertedApp.full_name,
    status: insertedApp.status ?? "New",
  };
}

export function useEndorseApplicant() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: EndorseApplicantParams) => endorseApplicant(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-detail", variables.vcode] });
    },
  });
}

// ── 1. Advance Pipeline / Update Applicant Status ─────────────
export type UpdateApplicantPipelineParams = {
  applicantId: string;
  newStatus?: string | null;
  recruitmentRemarks?: string | null;
  opsRemarks?: string | null;
  followUpDate?: string | null;
  reasonId?: string | null;
  reasonType?: string | null;
  vcode?: string;
};

export async function updateApplicantPipeline(
  params: UpdateApplicantPipelineParams,
) {
  const supabase = createClient();

  const rpcParams: Record<string, unknown> = {
    p_applicant_id: params.applicantId,
    p_new_status: params.newStatus ?? null,
    p_recruitment_remarks: params.recruitmentRemarks ?? null,
    p_ops_remarks: params.opsRemarks ?? null,
    p_follow_up_date: params.followUpDate ?? null,
    p_reason_id: params.reasonId ?? null,
    p_reason_type: params.reasonType ?? null,
  };

  const { data, error } = await supabase.rpc(
    "fn_update_applicant_pipeline",
    rpcParams,
  );

  if (error) {
    // Fallback: direct table update if RPC fails
    console.warn("fn_update_applicant_pipeline error, attempting fallback update:", error.message);
    const updates: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };
    if (params.newStatus) updates.status = params.newStatus;
    if (params.recruitmentRemarks !== undefined) updates.recruitment_remarks = params.recruitmentRemarks;
    if (params.opsRemarks !== undefined) updates.ops_remarks = params.opsRemarks;
    if (params.followUpDate !== undefined) updates.follow_up_date = params.followUpDate;
    if (params.newStatus === "backout" || params.newStatus === "Backout") {
      updates.is_archived = true;
      updates.backout_date = new Date().toISOString().substring(0, 10);
    }

    const { error: fallbackError } = await supabase
      .from("applicants")
      .update(updates)
      .eq("id", params.applicantId);

    if (fallbackError) {
      throw new VacancyDataError("generic", fallbackError.message);
    }
    return { success: true };
  }

  return data;
}

export function useUpdateApplicantPipeline() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateApplicantPipelineParams) =>
      updateApplicantPipeline(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      if (variables.vcode) {
        queryClient.invalidateQueries({
          queryKey: ["vacancy-detail", variables.vcode],
        });
      }
    },
  });
}

// ── 2. Confirm Applicant Onboard / Mark Hired ─────────────────
export type ConfirmApplicantOnboardParams = {
  applicantId: string;
  lastName: string;
  firstName: string;
  middleName?: string | null;
  fullName: string;
  contactNumber: string;
  hiredByUserId?: string | null;
  hiredDate: string; // YYYY-MM-DD
  endorsedByDeployerId?: string | null;
  endorsedByName?: string | null;
  remarks?: string | null;
  rovingAssignmentId?: string | null;
  vacancyRequirementId?: string | null;
  vcode?: string;
};

export async function confirmApplicantOnboard(
  params: ConfirmApplicantOnboardParams,
) {
  const supabase = createClient();

  // Normalize contact number
  const cleanContact = params.contactNumber.replace(/[^0-9]/g, "");
  const normalizedContact =
    cleanContact.length === 10 && cleanContact.startsWith("9")
      ? `0${cleanContact}`
      : cleanContact;

  const rpcParams: Record<string, unknown> = {
    p_applicant_id: params.applicantId,
    p_last_name: params.lastName,
    p_first_name: params.firstName,
    p_middle_name: params.middleName || null,
    p_full_name: params.fullName,
    p_contact_number: normalizedContact,
    p_remarks: params.remarks || null,
    p_roving_assignment_id: params.rovingAssignmentId || null,
    p_hired_by_user_id: params.hiredByUserId,
    p_hired_date: params.hiredDate,
    p_endorsed_by_deployer_id: params.endorsedByDeployerId || null,
    p_endorsed_by_name: params.endorsedByName || null,
  };

  if (params.vacancyRequirementId) {
    rpcParams.p_vacancy_requirement_id = params.vacancyRequirementId;
  }

  const { data, error } = await supabase.rpc(
    "confirm_applicant_onboard",
    rpcParams,
  );

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  return data;
}

export function useConfirmApplicantOnboard() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ConfirmApplicantOnboardParams) =>
      confirmApplicantOnboard(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hired-applicants"] });
      if (variables.vcode) {
        queryClient.invalidateQueries({
          queryKey: ["vacancy-detail", variables.vcode],
        });
      }
    },
  });
}

// ── 3. Fail / Backout Applicant ──────────────────────────────
export type FailBackoutParams = {
  applicantId: string;
  reason: string;
  reasonId?: string | null;
  status: "Backout" | "Failed" | "Rejected";
  vcode: string;
};

export async function failBackoutApplicant(params: FailBackoutParams) {
  const supabase = createClient();
  const statusCode =
    params.status.toLowerCase() === "backout" ? "backout" : "rejected";

  const { error } = await supabase
    .from("applicants")
    .update({
      status: params.status,
      backout_reason: params.reason,
      backout_date: new Date().toISOString().substring(0, 10),
      is_archived: true,
      updated_at: new Date().toISOString(),
    })
    .eq("id", params.applicantId);

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  // Also record in applicant_status_history if available
  try {
    await supabase.rpc("fn_update_applicant_pipeline", {
      p_applicant_id: params.applicantId,
      p_new_status: statusCode,
      p_reason_id: params.reasonId || null,
      p_reason_type: statusCode,
    });
  } catch {
    // Non-fatal if history logging fails
  }

  // If this vacancy now has 0 remaining active pipeline candidates, return vacancy status to 'Open'
  const { data: remainingActive } = await supabase
    .from("applicants")
    .select("id")
    .eq("vacancy_vcode", params.vcode)
    .or("is_archived.is.null,is_archived.eq.false")
    .neq("id", params.applicantId);

  if (!remainingActive || remainingActive.length === 0) {
    await supabase
      .from("vacancies")
      .update({
        status: "Open",
        updated_at: new Date().toISOString(),
      })
      .eq("vcode", params.vcode);
  }

  return { success: true };
}

export function useFailBackoutApplicant() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: FailBackoutParams) => failBackoutApplicant(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({
        queryKey: ["vacancy-detail", variables.vcode],
      });
    },
  });
}

// ── 4. Reopen Vacancy Modal / Recycling to Open Queue ────────
export type ReopenVacancyParams = {
  vcode: string;
  reason?: string;
  vacantDate?: string;
};

export async function reopenVacancy(params: ReopenVacancyParams) {
  const supabase = createClient();
  const vcode = params.vcode.trim();

  // Reset status to Open and clear pending closure flags
  const updatePayload: Record<string, unknown> = {
    status: "Open",
    is_archived: false,
    has_pending_closure: false,
    updated_at: new Date().toISOString(),
  };

  if (params.vacantDate) {
    updatePayload.vacant_date = params.vacantDate;
  }

  const { data, error } = await supabase
    .from("vacancies")
    .update(updatePayload)
    .eq("vcode", vcode)
    .select()
    .single();

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  return data;
}

export function useReopenVacancy() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ReopenVacancyParams) => reopenVacancy(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({
        queryKey: ["vacancy-detail", variables.vcode],
      });
    },
  });
}

// ── 5. Vacancy Closure Management ────────────────────────────
export type RequestVacancyClosureParams = {
  vcode: string;
  reason: string;
  details?: string;
  requestedBy: string;
  requestedByRole?: string;
  requestedByUserId?: string | null;
};

export async function requestVacancyClosure(
  params: RequestVacancyClosureParams,
) {
  const supabase = createClient();

  try {
    const { data, error } = await supabase.rpc(
      "rpc_submit_vacancy_closure_request",
      {
        p_vacancy_vcode: params.vcode,
        p_reason: params.reason,
        p_details: params.details || null,
        p_requested_by: params.requestedBy,
        p_requested_by_role: params.requestedByRole || "Ops",
        p_requested_by_user_id: params.requestedByUserId || null,
      },
    );
    if (error) throw error;
    return data;
  } catch {
    // Fallback: direct table insert
    const { data, error: insertError } = await supabase
      .from("vacancy_closure_requests")
      .insert({
        vacancy_vcode: params.vcode,
        reason: params.reason,
        details: params.details || null,
        requested_by: params.requestedBy,
        requested_by_user_id: params.requestedByUserId || null,
        status: "Pending",
      })
      .select()
      .single();

    if (insertError) {
      throw new VacancyDataError("generic", insertError.message);
    }
    return data;
  }
}

export function useRequestVacancyClosure() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RequestVacancyClosureParams) =>
      requestVacancyClosure(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-counts"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["pending-vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-closure-counts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
      queryClient.invalidateQueries({
        queryKey: ["vacancy-detail", variables.vcode],
      });
    },
  });
}

export type ReviewClosureRequestParams = {
  requestId: string;
  status: "Approved" | "Rejected";
  reviewedBy: string;
  remarks?: string;
  vcode?: string;
};

export async function reviewClosureRequest(
  params: ReviewClosureRequestParams,
) {
  const supabase = createClient();

  const { error } = await supabase
    .from("vacancy_closure_requests")
    .update({
      status: params.status,
      reviewed_by: params.reviewedBy,
      reviewed_at: new Date().toISOString(),
      reviewer_remarks: params.remarks || null,
    })
    .eq("id", params.requestId);

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  return { success: true };
}

export function useReviewClosureRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ReviewClosureRequestParams) =>
      reviewClosureRequest(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-counts"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["pending-vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-closure-counts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
      if (variables.vcode) {
        queryClient.invalidateQueries({
          queryKey: ["vacancy-detail", variables.vcode],
        });
      }
    },
  });
}

export async function approveAllClosureRequests(requestIds?: string[]) {
  const supabase = createClient();
  const rpcParams: Record<string, unknown> = {};
  if (requestIds && requestIds.length > 0) {
    rpcParams.p_request_ids = requestIds;
  }

  const { data, error } = await supabase.rpc(
    "approve_all_vacancy_closure_requests",
    rpcParams,
  );

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  return data;
}

export function useApproveAllClosureRequests() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (requestIds?: string[]) =>
      approveAllClosureRequests(requestIds),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-counts"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["pending-vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-closure-counts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
    },
  });
}

// ── 6. Update Hired Applicant Date ───────────────────────────
export type UpdateHiredDateParams = {
  applicantId: string;
  hiredDate: string; // YYYY-MM-DD
};

export async function updateHiredApplicantDate(params: UpdateHiredDateParams) {
  const supabase = createClient();
  const hiredDate = new Date(params.hiredDate);
  const visibleUntil = new Date(
    hiredDate.getFullYear(),
    hiredDate.getMonth(),
    hiredDate.getDate() + 15,
  ).toISOString();

  const { error } = await supabase
    .from("applicants")
    .update({
      hired_date: params.hiredDate,
      hired_visible_until: visibleUntil,
    })
    .eq("id", params.applicantId);

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  return { success: true };
}

export function useUpdateHiredApplicantDate() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateHiredDateParams) =>
      updateHiredApplicantDate(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["hired-applicants"] });
    },
  });
}

// ── 7. Fetch Reasons (Backout / Rejection) ───────────────────
export async function fetchBackoutReasons(): Promise<Array<{ id: string; reason: string }>> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("backout_reasons")
    .select("id, reason")
    .eq("is_active", true)
    .order("reason");

  if (error) {
    console.warn("fetchBackoutReasons error:", error.message);
    return [];
  }
  return data ?? [];
}

export async function fetchRejectedReasons(): Promise<Array<{ id: string; reason: string }>> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("rejected_reasons")
    .select("id, reason")
    .eq("is_active", true)
    .order("reason");

  if (error) {
    console.warn("fetchRejectedReasons error:", error.message);
    return [];
  }
  return data ?? [];
}

export async function fetchHiredApplicantsList(vcode?: string) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("fn_get_hired_applicants", {
    p_vcode: vcode || null,
  });

  if (error) {
    console.warn("fetchHiredApplicants error:", error.message);
    return [];
  }
  return Array.isArray(data) ? data : [];
}

