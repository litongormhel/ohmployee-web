import type { PostgrestError } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

export type VacancyStatus = "open" | "with_applicant" | "rejected" | "backout";

export type VacancyAgingBucket =
  | "advance"
  | "1_15"
  | "16_30"
  | "31_60"
  | "61_120"
  | "gt121";

export type VacancyPipelineStatus = "Open" | "Pipeline";

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
  accountName: string | null;
  groupName: string | null;
  storeName: string | null;
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
  lastActivityAt: string | null;
  rowCapabilities: VacancyRowCapabilities;
  totalCount: number;
};

export type ActiveApplicantItem = {
  applicantId: string;
  displayName: string;
  statusLabel: string;
  updatedAt: string | null;
};

export type ActivityHistoryItem = {
  eventId: string;
  eventLabel: string;
  eventDescription: string | null;
  createdAt: string;
  profileName: string | null;
};

export type VacancyDetailItem = {
  vacancyId: string;
  vcode: string;
  accountName: string | null;
  groupName: string | null;
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
  status: VacancyStatus;
  search?: string;
  agingBucket?: string;
  pipelineStatus?: string;
  page: number;
  pageSize: number;
};

export type VacancySummary = {
  open: number;
  withApplicant: number;
  rejected: number;
  backout: number;
  pendingReview: number;
  agingWatch: number;
  total: number;
};

export type VacancyDataErrorKind = "access_denied" | "retryable";

export class VacancyDataError extends Error {
  kind: VacancyDataErrorKind;

  constructor(kind: VacancyDataErrorKind, message: string) {
    super(message);
    this.name = "VacancyDataError";
    this.kind = kind;
  }
}

type VacancyRpcRow = Record<string, unknown>;

const DEFAULT_PAGE_SIZE = 25;
const MAX_PAGE_SIZE = 100;

function asObject(value: unknown): Record<string, unknown> {
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown) {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
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
    canRequestClosure: raw.can_request_closure === true,
    raw,
  };
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
  throw new VacancyDataError(getErrorKind(error), error.message);
}

function normalizeListRow(row: VacancyRpcRow): VacancyListItem | null {
  const id = asString(row.vacancy_id ?? row.id);

  if (!id) {
    return null;
  }

  return {
    id,
    vcode: asString(row.vcode ?? row.vacancy_code) ?? "Uncoded",
    accountName: asString(row.account_name ?? row.account),
    groupName: asString(row.group_name),
    storeName: asString(row.store_name ?? row.store),
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
    urgencyLevel: asString(row.urgency_level),
    hrcoName: asString(row.hrco_name),
    lastActivityAt: asString(row.last_activity_at),
    rowCapabilities: normalizeCapabilities(row.row_capabilities),
    totalCount: asCount(row.total_count),
  };
}

function normalizeActiveApplicant(item: unknown): ActiveApplicantItem {
  const obj = asObject(item);
  return {
    applicantId: asString(obj.applicant_id) ?? "",
    displayName: asString(obj.display_name) ?? "Anonymous",
    statusLabel: asString(obj.status_label) ?? "New",
    updatedAt: asString(obj.updated_at),
  };
}

function normalizeActivityHistory(item: unknown): ActivityHistoryItem {
  const obj = asObject(item);
  return {
    eventId: asString(obj.event_id ?? obj.id) ?? "",
    eventLabel: asString(obj.event_label ?? obj.label) ?? "Event",
    eventDescription: asString(obj.event_description ?? obj.description),
    createdAt: asString(obj.created_at ?? obj.timestamp) ?? new Date().toISOString(),
    profileName: asString(obj.profile_name ?? obj.user_name),
  };
}

function normalizeDetailRow(row: VacancyRpcRow): VacancyDetailItem | null {
  const id = asString(row.vacancy_id ?? row.id);

  if (!id) {
    return null;
  }

  const rawApplicants = Array.isArray(row.active_applicants_list) ? row.active_applicants_list : [];
  const activeApplicantsList = rawApplicants.map(normalizeActiveApplicant);

  const rawHistory = Array.isArray(row.activity_history) ? row.activity_history : [];
  const activityHistory = rawHistory.map(normalizeActivityHistory);

  return {
    vacancyId: id,
    vcode: asString(row.vcode ?? row.vacancy_code) ?? "Uncoded",
    accountName: asString(row.account_name ?? row.account),
    groupName: asString(row.group_name),
    storeName: asString(row.store_name ?? row.store),
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
    urgencyLevel: asString(row.urgency_level),
    hrcoName: asString(row.hrco_name),
    lastActivityAt: asString(row.last_activity_at),
    rowCapabilities: normalizeCapabilities(row.row_capabilities),

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

  return {
    open: asCount(row.open ?? row.open_count ?? row.open_vacancies),
    withApplicant: asCount(
      row.with_applicant ?? row.with_applicant_count ?? row.pipeline_count,
    ),
    rejected: asCount(row.rejected ?? row.rejected_count),
    backout: asCount(row.backout ?? row.backout_count),
    pendingReview: asCount(
      row.pending_review ?? row.pending_review_count ?? row.pending_approval_count,
    ),
    agingWatch: asCount(row.aging_watch ?? row.aging_watch_count ?? row.aging_count),
    total: asCount(row.total ?? row.total_count),
  };
}

function getFilters(params: VacancyListParams) {
  return {
    ...(params.agingBucket ? { aging_buckets: [params.agingBucket] } : {}),
  };
}

export async function getVacancySummary(params: Pick<VacancyListParams, "status" | "search" | "agingBucket" | "pipelineStatus">) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_vacancy_summary", {
    p_search: params.search?.trim() || null,
    p_filters: getFilters({
      ...params,
      page: 1,
      pageSize: DEFAULT_PAGE_SIZE,
    }),
  });

  if (error) {
    throwVacancyError(error);
  }

  return normalizeSummary(data);
}

export async function listVacancies(params: VacancyListParams) {
  const supabase = createClient();
  const page = Math.max(1, Math.trunc(params.page));
  const pageSize = Math.min(
    MAX_PAGE_SIZE,
    Math.max(1, Math.trunc(params.pageSize)),
  );
  const offset = (page - 1) * pageSize;

  const { data, error } = await supabase.rpc("list_web_vacancies", {
    p_queue: params.status,
    p_search: params.search?.trim() || null,
    p_filters: getFilters(params),
    p_sort: "aging_days",
    p_sort_dir: "desc",
    p_limit: pageSize,
    p_offset: offset,
  });

  if (error) {
    throwVacancyError(error);
  }

  const rows = (Array.isArray(data) ? data : [])
    .map((row) => normalizeListRow(asObject(row)))
    .filter((row): row is VacancyListItem => row !== null);

  return {
    data: rows,
    totalCount: getTotalCount(rows),
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

  return normalized;
}
