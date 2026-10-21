import type { PostgrestError } from "@supabase/supabase-js";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { formatPersonName, parseCandidateFullName } from "@/lib/utils/formatName";

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
  cgCode?: string | null;
  assignedStores?: string[];
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
  applicantFirstName?: string | null;
  applicantLastName?: string | null;
  applicantMiddleName?: string | null;
  contactNumber?: string | null;
  hiredDate?: string | null;
  daysToFill?: number | null;
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
  headcount?: number;
  hcFilled?: number;
  hcTotal?: number;
  hcDisplay?: string;
  lastActivityAt: string | null;
  rowCapabilities: VacancyRowCapabilities;
  profileEditCount?: number | null;
  totalCount: number;
};

export type ActiveApplicantItem = {
  applicantId: string;
  displayName: string;
  lastName: string | null;
  firstName: string | null;
  middleName?: string | null;
  contactNumber: string | null;
  statusLabel: string;
  onboardDate: string | null;
  updatedAt: string | null;
  recruiterName: string | null;
  deployedByName: string | null;
  profileEditCount?: number | null;
  createdAt?: string | null;
  agingDays?: number | null;
};

export type ActivityHistoryItem = {
  eventId: string;
  eventLabel: string;
  eventDescription: string | null;
  createdAt: string | null;
  profileName: string | null;
};

export type VacancyRequirementItem = {
  id: string;
  positionName: string;
  employmentType?: string | null;
  hcNeeded: number;
  hcFilled: number;
  pipelineCount: number;
};

export type VacancyDetailItem = {
  vacancyId: string;
  vcode: string;
  cgCode?: string | null;
  assignedStores?: string[];
  source?: string | null;
  vacancyType?: string | null;
  createdAt?: string | null;
  requirements?: VacancyRequirementItem[];
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
  daysToFill?: number | null;
  relieverOnDuty: string | null;
  hasReliever: boolean;
  hrcoRemarks: string | null;
  recruiterName: string | null;
  deployedByName: string | null;
  hasPenalty: boolean;
  penaltyExposure: number;
  penaltyAmount: number | null;
  headcount?: number;
  hcFilled?: number;
  hcTotal?: number;
  hcDisplay?: string;
  applicantId?: string | null;
  applicantLastName: string | null;
  applicantFirstName: string | null;
  applicantMiddleName: string | null;
  applicantName: string | null;
  storeLocation: string | null;
  areaCity: string | null;
  areaProvince: string | null;
  storeBranch: string | null;
  omName?: string | null;
  tlName?: string | null;
  atlName?: string | null;

  // Detail-specific fields
  requestedById: string | null;
  requestedByName: string | null;
  triggeredByName?: string | null;
  approvedById: string | null;
  approvedByName: string | null;
  approvedAt: string | null;
  headcountRequestId: string | null;
  vacancyReason: string | null;
  jobDescription: string | null;
  closureRequestedAt: string | null;
  closureRequestedBy: string | null;
  closureReason: string | null;
  profileEditCount?: number | null;
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

export function calculateDaysToFill(
  vacantDate?: string | null,
  onboardDate?: string | null,
): number | null {
  if (!vacantDate || !onboardDate) return null;
  const vClean = vacantDate.substring(0, 10);
  const oClean = onboardDate.substring(0, 10);
  const vTime = Date.parse(`${vClean}T00:00:00Z`);
  const oTime = Date.parse(`${oClean}T00:00:00Z`);
  if (isNaN(vTime) || isNaN(oTime)) return null;
  const diffDays = Math.round((oTime - vTime) / 86400000);
  return Math.max(0, diffDays);
}

export function formatGroupName(groupName?: string | null, accountName?: string | null): string {
  if (accountName && accountName.trim().toLowerCase() === "moses hq") {
    return "MOSES HQ";
  }
  if (!groupName) return "";
  const trimmed = groupName.trim();
  if (trimmed.toLowerCase() === "global hq" || trimmed.toLowerCase() === "ghq") {
    return "MOSES HQ";
  }
  return trimmed;
}

export async function fetchGroupMap(supabase: ReturnType<typeof createClient>): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  try {
    const { data } = await supabase.from("groups").select("id, group_name");
    if (Array.isArray(data)) {
      for (const g of data) {
        if (g.id && g.group_name) {
          map.set(String(g.id), String(g.group_name));
        }
      }
    }
  } catch {
    // Graceful fallback
  }
  return map;
}

function normalizeListRow(row: VacancyRpcRow): VacancyListItem | null {
  const id = asString(row.vacancy_id ?? row.id);

  if (!id) {
    return null;
  }

  let applicantLastName = asString(row.applicant_last_name ?? row.last_name);
  let applicantFirstName = asString(row.applicant_first_name ?? row.first_name);
  let applicantMiddleName = asString(row.applicant_middle_name ?? row.middle_name);
  const rawApplicantName = asString(
    row.applicant_name ??
    row.applicant_full_name ??
    row.full_name ??
    row.candidate_name,
  );
  const applicantName = formatPersonName(
    applicantFirstName,
    applicantLastName,
    applicantMiddleName,
    rawApplicantName,
  ) || null;

  if ((!applicantLastName || !applicantFirstName) && (applicantName || rawApplicantName)) {
    const parsed = parseCandidateFullName(applicantName || rawApplicantName, {
      firstName: applicantFirstName,
      lastName: applicantLastName,
      middleName: applicantMiddleName,
    });
    applicantLastName = applicantLastName || parsed.lastName || null;
    applicantFirstName = applicantFirstName || parsed.firstName || null;
    applicantMiddleName = applicantMiddleName || parsed.middleName || null;
  }

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

  const rawVcode = asString(row.vcode ?? row.vacancy_code) ?? "Uncoded";
  const cgCode = asString(row.cg_code ?? row.coverage_code) ?? (rawVcode.startsWith("CG-") ? rawVcode : null);
  const vcode = cgCode || rawVcode;

  let agingDays = asNumber(row.aging_days);
  if (agingDays === null || isNaN(agingDays)) {
    const vDateStr = asString(row.vacant_date ?? row.created_at);
    if (vDateStr) {
      const vDate = new Date(vDateStr);
      if (!isNaN(vDate.getTime())) {
        const diffMs = Date.now() - vDate.getTime();
        agingDays = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
      }
    }
  }

  let agingBucket = asString(row.aging_bucket);
  if ((!agingBucket || agingBucket === "unknown") && agingDays !== null) {
    if (agingDays <= 7) agingBucket = "0_7";
    else if (agingDays <= 14) agingBucket = "8_14";
    else if (agingDays <= 30) agingBucket = "15_30";
    else agingBucket = "31_plus";
  }

  const accountName = asString(row.account_name ?? row.account);
  const rawStoreName = asString(row.store_name ?? row.store);
  const isMosesPool =
    Boolean(vcode && vcode.includes("GHQ")) ||
    Boolean(cgCode && cgCode.includes("GHQ")) ||
    (accountName && accountName.toLowerCase() === "moses hq") ||
    asString(row.source)?.toLowerCase() === "pool" ||
    asBoolean(row.is_pool_vacancy);
  const storeName =
    rawStoreName && rawStoreName !== "—" && rawStoreName !== "-"
      ? rawStoreName
      : isMosesPool
      ? "Moses HQ"
      : rawStoreName;

  const rowCaps = asObject(row.row_capabilities);
  const hcFilled =
    asNumber(row.hc_filled ?? rowCaps.hc_filled) ??
    asCount(row.confirmed_onboard_count);
  const hcTotal =
    asNumber(row.hc_total ?? rowCaps.hc_total ?? row.required_headcount ?? row.headcount ?? row.hc) ?? 1;
  const hcDisplay =
    asString(row.hc_display ?? rowCaps.hc_display) ?? `${hcFilled}/${hcTotal}`;

  return {
    id,
    vcode,
    cgCode,
    accountId: asString(row.account_id),
    accountName,
    groupId: asString(row.group_id),
    groupName: formatGroupName(asString(row.group_name), accountName) || null,
    storeId: asString(row.store_id),
    storeName,
    storeLocation,
    position_title: asString(row.position_title),
    department: asString(row.department ?? row.business_unit),
    employmentType: asString(row.employment_type),
    vacancyStatus: asString(row.vacancy_status ?? row.status),
    pipelineStatus: asString(row.pipeline_status),
    derivedStatus: asString(row.derived_status),
    activeApplicantCount: asCount(row.active_applicant_count),
    confirmedOnboardCount: hcFilled,
    hasRecentHire: asBoolean(row.has_recent_hire),
    hasPendingClosure: asBoolean(row.has_pending_closure),
    closureRequestStatus: asString(row.closure_request_status),
    vacantDate: asString(row.vacant_date),
    agingDays,
    agingBucket,
    targetFillDate: asString(row.target_fill_date),
    urgencyLevel: asString(row.urgency_level ?? row.urgency),
    hrcoName: asString(row.hrco_name),
    applicantId,
    applicantName,
    applicantFirstName,
    applicantLastName,
    applicantMiddleName,
    contactNumber,
    hiredDate,
    profileEditCount: asNumber(row.profile_edit_count ?? row.applicant_profile_edit_count) ?? 0,
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
    headcount: hcTotal,
    hcFilled,
    hcTotal,
    hcDisplay,
    lastActivityAt: asString(row.last_activity_at),
    rowCapabilities: normalizeCapabilities(row.row_capabilities),
    totalCount: asCount(row.total_count),
  };
}

function normalizeActiveApplicant(item: unknown): ActiveApplicantItem {
  const obj = asObject(item);
  let lastName = asString(obj.last_name ?? obj.applicant_last_name);
  let firstName = asString(obj.first_name ?? obj.applicant_first_name);
  let middleName = asString(obj.middle_name ?? obj.applicant_middle_name);
  const rawDisplayName = asString(obj.display_name ?? obj.full_name ?? obj.name);
  const displayName = formatPersonName(firstName, lastName, middleName, rawDisplayName) || "Anonymous";

  if ((!lastName || !firstName) && (displayName !== "Anonymous" || rawDisplayName)) {
    const parsed = parseCandidateFullName(displayName !== "Anonymous" ? displayName : rawDisplayName, {
      firstName,
      lastName,
      middleName,
    });
    lastName = lastName || parsed.lastName || null;
    firstName = firstName || parsed.firstName || null;
    middleName = middleName || parsed.middleName || null;
  }

  return {
    applicantId: asString(obj.applicant_id ?? obj.id) ?? "",
    displayName,
    lastName,
    firstName,
    middleName,
    contactNumber: asString(obj.contact_number ?? obj.mobile_number ?? obj.phone),
    statusLabel: asString(obj.status_label ?? obj.status) ?? "New",
    onboardDate: asString(obj.onboard_date ?? obj.hired_date),
    updatedAt: asString(obj.updated_at ?? obj.created_at),
    recruiterName: formatPersonName(null, null, null, asString(obj.recruiter_name ?? obj.recruited_by_name)) || null,
    deployedByName: formatPersonName(null, null, null, asString(obj.deployed_by_name ?? obj.deployed_by)) || null,
    profileEditCount: typeof obj.profile_edit_count === "number" ? obj.profile_edit_count : typeof obj.profile_edit_count === "string" ? parseInt(obj.profile_edit_count, 10) : 0,
    createdAt: asString(obj.created_at ?? obj.applied_at),
    agingDays: asNumber(obj.aging_days),
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
  let applicantLastName = asString(row.applicant_last_name ?? row.last_name) ?? primaryApplicant?.lastName ?? null;
  let applicantFirstName = asString(row.applicant_first_name ?? row.first_name) ?? primaryApplicant?.firstName ?? null;
  let applicantMiddleName = asString(row.applicant_middle_name ?? row.middle_name) ?? primaryApplicant?.middleName ?? null;
  const rawApplicantName = asString(
    row.applicant_name ??
    row.applicant_full_name ??
    row.full_name ??
    row.candidate_name,
  );
  const applicantName = formatPersonName(
    applicantFirstName,
    applicantLastName,
    applicantMiddleName,
    rawApplicantName || (primaryApplicant && primaryApplicant.displayName !== "Anonymous" ? primaryApplicant.displayName : null),
  ) || null;

  if (
    (!applicantLastName || !applicantFirstName) &&
    (applicantName || rawApplicantName || (primaryApplicant && primaryApplicant.displayName !== "Anonymous"))
  ) {
    const parsed = parseCandidateFullName(
      applicantName || rawApplicantName || (primaryApplicant ? primaryApplicant.displayName : ""),
      {
        firstName: applicantFirstName,
        lastName: applicantLastName,
        middleName: applicantMiddleName,
      },
    );
    applicantLastName = applicantLastName || parsed.lastName || null;
    applicantFirstName = applicantFirstName || parsed.firstName || null;
    applicantMiddleName = applicantMiddleName || parsed.middleName || null;
  }

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

  const recruiterName = formatPersonName(
    null,
    null,
    null,
    asString(
      row.recruiter_name ??
      row.recruited_by_name ??
      row.assigned_encoder_name ??
      primaryApplicant?.recruiterName,
    ),
  ) || null;

  const deployedByName = formatPersonName(
    null,
    null,
    null,
    asString(
      row.deployed_by_name ??
      row.deployed_by ??
      row.endorsed_by_name ??
      primaryApplicant?.deployedByName,
    ),
  ) || null;

  const triggeredByName = formatPersonName(
    null,
    null,
    null,
    asString(
      row.triggered_by_name ??
      row.triggered_by_full_name ??
      row.requester_name,
    ),
  ) || null;

  const onboardDate = asString(
    row.onboard_date ??
    row.hired_date ??
    row.target_fill_date ??
    primaryApplicant?.onboardDate,
  );

  const rawVcode = asString(row.vcode ?? row.vacancy_code) ?? "Uncoded";
  const cgCode = asString(row.cg_code ?? row.coverage_code) ?? (rawVcode.startsWith("CG-") ? rawVcode : null);
  const vcode = cgCode || rawVcode;

  let agingDays = asNumber(row.aging_days);
  if (agingDays === null || isNaN(agingDays)) {
    const vDateStr = asString(row.vacant_date ?? row.created_at);
    if (vDateStr) {
      const vDate = new Date(vDateStr);
      if (!isNaN(vDate.getTime())) {
        const diffMs = Date.now() - vDate.getTime();
        agingDays = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
      }
    }
  }

  let agingBucket = asString(row.aging_bucket);
  if ((!agingBucket || agingBucket === "unknown") && agingDays !== null) {
    if (agingDays <= 7) agingBucket = "0_7";
    else if (agingDays <= 14) agingBucket = "8_14";
    else if (agingDays <= 30) agingBucket = "15_30";
    else agingBucket = "31_plus";
  }

  const accountName = asString(row.account_name ?? row.account);
  const rawStoreName = asString(row.store_name ?? row.store);
  const isMosesPool =
    Boolean(vcode && vcode.includes("GHQ")) ||
    Boolean(cgCode && cgCode.includes("GHQ")) ||
    (accountName && accountName.toLowerCase() === "moses hq") ||
    asString(row.source)?.toLowerCase() === "pool" ||
    asBoolean(row.is_pool_vacancy);
  const storeName =
    rawStoreName && rawStoreName !== "—" && rawStoreName !== "-"
      ? rawStoreName
      : isMosesPool
      ? "Moses HQ"
      : rawStoreName;

  const rowCaps = asObject(row.row_capabilities);
  const hcFilled =
    asNumber(row.hc_filled ?? rowCaps.hc_filled ?? row.confirmed_onboard_count ?? rowCaps.confirmed_onboard_count) ??
    asCount(row.confirmed_onboard_count);
  const hcTotal =
    asNumber(row.hc_total ?? rowCaps.hc_total ?? row.required_headcount ?? rowCaps.required_headcount ?? row.headcount ?? row.hc) ?? 1;
  const hcDisplay =
    asString(row.hc_display ?? rowCaps.hc_display) ?? `${hcFilled}/${hcTotal}`;

  return {
    vacancyId: id,
    vcode,
    cgCode,
    assignedStores: Array.isArray(row.assigned_stores)
      ? (row.assigned_stores as string[])
      : Array.isArray(row.assignedStores)
      ? (row.assignedStores as string[])
      : undefined,
    source: asString(row.source),
    vacancyType: asString(row.vacancy_type),
    createdAt: asString(row.created_at),
    accountId: asString(row.account_id),
    accountName,
    groupId: asString(row.group_id),
    groupName: formatGroupName(asString(row.group_name), accountName) || null,
    storeId: asString(row.store_id),
    storeName,
    position_title: asString(row.position_title),
    department: asString(row.department ?? row.business_unit),
    employmentType: asString(row.employment_type),
    vacancyStatus: asString(row.vacancy_status ?? row.status),
    pipelineStatus: asString(row.pipeline_status),
    derivedStatus: asString(row.derived_status ?? row.pipeline_status),
    activeApplicantCount: asCount(row.active_applicant_count),
    confirmedOnboardCount: hcFilled,
    hasRecentHire: asBoolean(row.has_recent_hire),
    hasPendingClosure:
      asBoolean(row.has_pending_closure) ||
      asBoolean((row.row_capabilities as Record<string, unknown> | undefined)?.has_pending_closure),
    closureRequestStatus:
      asString(row.closure_request_status) ||
      asString((row.row_capabilities as Record<string, unknown> | undefined)?.closure_request_status),
    vacantDate: asString(row.vacant_date),
    agingDays,
    agingBucket,
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
    headcount: hcTotal,
    hcFilled,
    hcTotal,
    hcDisplay,
    applicantId: asString(row.applicant_id ?? row.applicantId) ?? primaryApplicant?.applicantId ?? null,
    applicantLastName,
    applicantFirstName,
    applicantMiddleName,
    applicantName,
    storeLocation: [asString(row.area_city), asString(row.area_province ?? row.area_name ?? row.province)].filter(Boolean).join(" • ") || null,
    areaCity: asString(row.area_city),
    areaProvince: asString(row.area_province ?? row.area_name ?? row.province),
    storeBranch: asString(row.store_branch),
    omName: asString(row.om_name ?? row.om),
    tlName: asString(row.tl_name ?? row.tl),
    atlName: asString(row.atl_name ?? row.atl),

    // Detail-specific fields
    requestedById: asString(row.requested_by_id),
    requestedByName: asString(row.requested_by_name),
    triggeredByName,
    approvedById: asString(row.approved_by_id),
    approvedByName: asString(row.approved_by_name),
    approvedAt: asString(row.approved_at),
    headcountRequestId: asString(row.headcount_request_id),
    vacancyReason: asString(row.vacancy_reason),
    jobDescription: asString(row.job_description),
    closureRequestedAt: asString(row.closure_requested_at),
    closureRequestedBy: asString(row.closure_requested_by),
    closureReason: asString(row.closure_reason),
    profileEditCount: primaryApplicant?.profileEditCount ?? asNumber(row.profile_edit_count ?? row.applicant_profile_edit_count) ?? 0,
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

  // Failed / Backout tab count: all dropout applicants on non-deleted vacancies
  const failedPromise = (async () => {
    try {
      const { data: dropouts, error } = await supabase
        .from("applicants")
        .select("id, vacancy_vcode, status, is_archived")
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

  if (currentTab === "pipeline" || currentTab === "with_applicant") {
    // 1. Pipeline Tab: Candidate-level expansion so each active candidate is a distinct row matching the badge count
    try {
      const TERMINAL_STATUSES = [
        "failed",
        "backout",
        "rejected",
        "did_not_report",
        "did not report",
        "rejected_by_ops",
        "rejected by ops",
        "withdrew",
        "confirmed_onboard",
        "confirmed onboard",
        "hired",
      ];

      const { data: pipelineApplicants, error: appsError } = await supabase
        .from("applicants")
        .select(`
          id,
          vacancy_vcode,
          first_name,
          last_name,
          middle_name,
          full_name,
          contact_number,
          status,
          created_at,
          updated_at,
          profile_edit_count,
          is_archived
        `)
        .eq("is_archived", false)
        .order("created_at", { ascending: false });

      if (!appsError && Array.isArray(pipelineApplicants)) {
        const activeCandidates = pipelineApplicants.filter((a) => {
          const normStatus = (asString(a.status) || "").toLowerCase().trim().replace(/[\s-]+/g, "_");
          return !TERMINAL_STATUSES.some((t) => t.replace(/[\s-]+/g, "_") === normStatus);
        });

        const vcodes = Array.from(
          new Set(activeCandidates.map((c) => asString(c.vacancy_vcode)).filter(Boolean)),
        ) as string[];

        let vacQuery = supabase
          .from("vacancies")
          .select(`
            id,
            vcode,
            store_name,
            store_branch,
            store_id,
            position,
            account,
            account_id,
            group_id,
            area_city,
            province,
            hrco_name,
            vacant_date,
            created_at,
            target_fill_date,
            urgency_level,
            status,
            is_archived,
            deleted_at,
            required_headcount,
            has_pending_closure,
            closure_request_status,
            employment_type,
            source,
            is_pool_vacancy
          `)
          .in("vcode", vcodes)
          .eq("is_archived", false)
          .is("deleted_at", null);

        if (params.accountId) {
          vacQuery = vacQuery.eq("account_id", params.accountId);
        }
        if (params.groupId) {
          vacQuery = vacQuery.eq("group_id", params.groupId);
        }
        if (params.urgency) {
          vacQuery = vacQuery.ilike("urgency_level", params.urgency);
        }
        if (params.vacantFrom) {
          vacQuery = vacQuery.gte("vacant_date", params.vacantFrom);
        }
        if (params.vacantTo) {
          vacQuery = vacQuery.lte("vacant_date", params.vacantTo);
        }

        const [vacRes, groupMap] = await Promise.all([
          vacQuery,
          fetchGroupMap(supabase),
        ]);

        const vacMap = new Map(
          (vacRes.data ?? [])
            .filter((v) => {
              const st = (v.status || "").toLowerCase().trim();
              return st !== "filled" && st !== "closed" && st !== "archived";
            })
            .map((v) => [v.vcode, v]),
        );
        const validCandidates = activeCandidates.filter((c) => vacMap.has(asString(c.vacancy_vcode)));

        const pipelineRows: VacancyListItem[] = validCandidates.map((c: Record<string, unknown>, idx: number) => {
          const vcode = asString(c.vacancy_vcode) ?? "Uncoded";
          const vac = vacMap.get(vcode) as Record<string, unknown> | undefined;
          const lName = asString(c.last_name);
          const fName = asString(c.first_name);
          const mName = asString(c.middle_name);
          const fFull = asString(c.full_name);
          const candidateName = formatPersonName(fName, lName, mName, fFull || "Candidate");
          const position = asString(vac?.position) ?? "—";
          const loc = [asString(vac?.area_city), asString(vac?.province)].filter(Boolean).join(" • ") || null;
          let storeName = asString(vac?.store_name ?? vac?.store_branch);
          const account = asString(vac?.account);
          if (
            !storeName &&
            (vcode.includes("GHQ") ||
              account?.toLowerCase() === "moses hq" ||
              vac?.source === "pool" ||
              asBoolean(vac?.is_pool_vacancy))
          ) {
            storeName = "Moses HQ";
          }

          const stageBadge = asString(c.status) || "In Pipeline";
          const vDateStr = asString(vac?.vacant_date ?? vac?.created_at ?? c.created_at);
          let agingDays: number | null = null;
          if (vDateStr) {
            const vDate = new Date(vDateStr);
            if (!isNaN(vDate.getTime())) {
              const diffMs = Date.now() - vDate.getTime();
              agingDays = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
            }
          }

          let agingBucket: string | null = null;
          if (agingDays !== null) {
            if (agingDays <= 7) agingBucket = "0_7";
            else if (agingDays <= 14) agingBucket = "8_14";
            else if (agingDays <= 30) agingBucket = "15_30";
            else agingBucket = "31_plus";
          }

          const hcTotal = asNumber(vac?.required_headcount) ?? 1;
          const hcFilled = 0;
          const hcDisplay = `${hcFilled}/${hcTotal}`;
          const rawGroupName = vac?.group_id ? groupMap.get(asString(vac.group_id)!) : null;

          return {
            id: asString(vac?.id) ?? asString(c.id) ?? `pipeline-${idx}`,
            vcode,
            accountId: asString(vac?.account_id),
            accountName: account,
            groupId: asString(vac?.group_id),
            groupName: formatGroupName(rawGroupName, account) || null,
            storeId: asString(vac?.store_id),
            storeName,
            storeLocation: loc,
            position_title: position,
            department: null,
            employmentType: asString(vac?.employment_type),
            vacancyStatus: asString(vac?.status) ?? "Open",
            pipelineStatus: stageBadge,
            derivedStatus: "Pipeline",
            activeApplicantCount: 1,
            confirmedOnboardCount: 0,
            hasRecentHire: false,
            hasPendingClosure: asBoolean(vac?.has_pending_closure),
            closureRequestStatus: asString(vac?.closure_request_status),
            vacantDate: asString(vac?.vacant_date),
            agingDays,
            agingBucket,
            targetFillDate: asString(vac?.target_fill_date),
            urgencyLevel: asString(vac?.urgency_level),
            hrcoName: asString(vac?.hrco_name) ?? "—",
            applicantId: asString(c.id),
            applicantName: candidateName,
            applicantFirstName: fName,
            applicantLastName: lName,
            applicantMiddleName: mName,
            contactNumber: asString(c.contact_number),
            hiredDate: null,
            stageBadge,
            profileEditCount: asNumber(c.profile_edit_count) ?? 0,
            hasPenalty: false,
            penaltyExposure: 0,
            penaltyAmount: null,
            headcount: hcTotal,
            hcFilled,
            hcTotal,
            hcDisplay,
            lastActivityAt: asString(c.updated_at ?? c.created_at),
            rowCapabilities: {
              canViewDetail: true,
              canApprove: false,
              canUpdateApplicantStatus: true,
              canRequestClosure: true,
              raw: {},
            },
            totalCount: validCandidates.length,
          };
        });

        let filteredPipeline = pipelineRows;
        if (params.search) {
          const q = params.search.toLowerCase();
          filteredPipeline = filteredPipeline.filter(
            (r) =>
              r.vcode.toLowerCase().includes(q) ||
              (r.applicantName && r.applicantName.toLowerCase().includes(q)) ||
              (r.position_title && r.position_title.toLowerCase().includes(q)) ||
              (r.storeName && r.storeName.toLowerCase().includes(q)) ||
              (r.accountName && r.accountName.toLowerCase().includes(q)) ||
              (r.stageBadge && r.stageBadge.toLowerCase().includes(q)),
          );
        }

        if (params.agingBucket) {
          filteredPipeline = filteredPipeline.filter((r) => r.agingBucket === params.agingBucket);
        }

        const paginatedPipeline = filteredPipeline.slice(offset, offset + pageSize);
        for (const r of paginatedPipeline) {
          r.totalCount = filteredPipeline.length;
        }

        return {
          data: paginatedPipeline,
          totalCount: filteredPipeline.length,
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

  if (currentTab === "hired") {
    // 2. Hired Tab: Populate rows using the hired applicants source (fn_get_hired_applicants)
    try {
      const { data: hiredData, error: hiredError } = await supabase.rpc("fn_get_hired_applicants");
      if (!hiredError && Array.isArray(hiredData)) {
        const hiredRows: VacancyListItem[] = hiredData.map((h: Record<string, unknown>, idx: number) => {
          const lName = asString(h.last_name);
          const fName = asString(h.first_name);
          const mName = asString(h.middle_name);
          const rawFull = asString(h.full_name);
          const workerName = formatPersonName(fName, lName, mName, rawFull || "Hired Worker");

          const hiredDate = asString(h.hired_date ?? h.hired_at);
          const position = asString(h.position_name ?? h.position);
          const vcode = asString(h.vacancy_vcode) ?? "Uncoded";
          const account = asString(h.account);
          const groupName = formatGroupName(asString(h.group_name), account);

          const hcTotal = asNumber(h.required_headcount ?? h.headcount) ?? 1;
          const hcFilled = 1;
          const hcDisplay = `${hcFilled}/${hcTotal}`;

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
            confirmedOnboardCount: hcFilled,
            hasRecentHire: true,
            hasPendingClosure: false,
            closureRequestStatus: null,
            vacantDate: null,
            daysToFill: null,
            agingDays: null,
            agingBucket: null,
            targetFillDate: null,
            urgencyLevel: null,
            hrcoName: asString(h.hired_by) ?? "HR Team",
            applicantId: asString(h.id),
            applicantName: workerName,
            applicantFirstName: fName,
            applicantLastName: lName,
            applicantMiddleName: mName,
            contactNumber: asString(h.contact_number),
            hiredDate,
            hasPenalty: false,
            penaltyExposure: 0,
            penaltyAmount: null,
            headcount: hcTotal,
            hcFilled,
            hcTotal,
            hcDisplay,
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

        // Enrich store info and vacantDate for hired rows if vcodes exist
        const hiredVcodes = Array.from(new Set(hiredRows.map((r) => r.vcode).filter(Boolean)));
        if (hiredVcodes.length > 0) {
          try {
            const { data: vacsData } = await supabase
              .from("vacancies")
              .select("vcode, store_name, store_branch, area_city, province, store_id, account_id, group_id, account, vacant_date, created_at, employment_type, hrco_name")
              .in("vcode", hiredVcodes)
              .is("deleted_at", null);

            if (vacsData && vacsData.length > 0) {
              const vacMap = new Map(vacsData.map((v) => [v.vcode, v]));
              for (const row of hiredRows) {
                if (vacMap.has(row.vcode)) {
                  const v = vacMap.get(row.vcode)!;
                  const isPool =
                    v.vcode?.includes("GHQ") ||
                    String(v.account || "").toLowerCase() === "moses hq";
                  row.storeName = v.store_name || v.store_branch || (isPool ? "Moses HQ" : null);
                  row.vacantDate = v.vacant_date || v.created_at?.substring(0, 10) || null;
                  row.daysToFill = calculateDaysToFill(row.vacantDate, row.hiredDate);
                  row.accountId = v.account_id || row.accountId;
                  row.groupId = v.group_id || row.groupId;
                  row.storeId = v.store_id || row.storeId;
                  row.accountName = row.accountName || v.account || null;
                  if (v.employment_type) row.employmentType = v.employment_type;
                  if (v.hrco_name) row.hrcoName = v.hrco_name;
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

      const [vacRes, groupMap] = await Promise.all([
        vacQuery,
        fetchGroupMap(supabase),
      ]);
      const activeVacs = vacRes.data;
      const vacError = vacRes.error;

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
          const account = asString(vac.account);
          let storeName = asString(vac.store_name ?? vac.store_branch);
          if (
            !storeName &&
            (vcode.includes("GHQ") ||
              account?.toLowerCase() === "moses hq" ||
              vac.source === "pool" ||
              asBoolean(vac.is_pool_vacancy))
          ) {
            storeName = "Moses HQ";
          }
          const position = asString(vac.position) ?? "—";
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
          const hcTotal = asNumber(vac.required_headcount ?? vac.headcount) ?? 1;
          const hcFilled = 0;
          const hcDisplay = `${hcFilled}/${hcTotal}`;
          const rawGroupName = vac.group_id ? groupMap.get(asString(vac.group_id)!) : null;

          return {
            id: asString(vac.id) ?? asString(cr?.id) ?? `closure-${idx}`,
            vcode,
            accountId: asString(vac.account_id),
            accountName: account,
            groupId: asString(vac.group_id),
            groupName: formatGroupName(rawGroupName, account) || null,
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
            headcount: hcTotal,
            hcFilled,
            hcTotal,
            hcDisplay,
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
    // 4. Failed / Backout Tab: Display dropout / failed / backout records from active vacancies
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
          .select("id, vcode, store_name, store_branch, store_id, position, account, account_id, group_id, area_city, province, hrco_name, vacant_date, created_at, target_fill_date, urgency_level, is_archived, deleted_at, required_headcount")
          .in("vcode", dropoutVcodes)
          .is("deleted_at", null);

        if (params.accountId) {
          vacQuery = vacQuery.eq("account_id", params.accountId);
        }
        if (params.groupId) {
          vacQuery = vacQuery.eq("group_id", params.groupId);
        }

        const [vacsRes, groupMap] = await Promise.all([
          vacQuery,
          fetchGroupMap(supabase),
        ]);
        const vacsData = vacsRes.data;
        const vacMap = new Map((vacsData ?? []).map((v) => [v.vcode, v]));

        // Filter dropouts to only those linked to valid, non-deleted vacancies
        const validDropouts = dropoutsData.filter((d) => vacMap.has(d.vacancy_vcode));

        const failedRows: VacancyListItem[] = validDropouts.map((d: Record<string, unknown>, idx: number) => {
          const vcode = asString(d.vacancy_vcode) ?? "Uncoded";
          const vac = vacMap.get(vcode) as Record<string, unknown> | undefined;
          const lName = asString(d.last_name);
          const fName = asString(d.first_name);
          const fFull = asString(d.full_name);
          const candidateName = formatPersonName(fName, lName, null, fFull || "Candidate");
          const position = asString(vac?.position) ?? "—";
          const loc = [asString(vac?.area_city), asString(vac?.province)].filter(Boolean).join(" • ") || null;
          let storeName = asString(vac?.store_name ?? vac?.store_branch);
          const account = asString(vac?.account);
          if (
            !storeName &&
            (vcode.includes("GHQ") ||
              account?.toLowerCase() === "moses hq" ||
              vac?.source === "pool" ||
              asBoolean(vac?.is_pool_vacancy))
          ) {
            storeName = "Moses HQ";
          }
          const status = asString(d.status) || "Failed / Backout";
          const dropoutReason = asString(d.backout_reason) || status;
          const rawDropoutDate = asString(d.backout_date ?? d.updated_at ?? d.created_at);
          const dropoutDate = rawDropoutDate
            ? rawDropoutDate.includes("T")
              ? rawDropoutDate.split("T")[0]
              : rawDropoutDate
            : null;

          const vDateStr = asString(vac?.vacant_date ?? vac?.created_at ?? d.created_at);
          let agingDays: number | null = null;
          if (vDateStr) {
            const vDate = new Date(vDateStr);
            if (!isNaN(vDate.getTime())) {
              const diffMs = Date.now() - vDate.getTime();
              agingDays = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
            }
          }

          let agingBucket: string | null = null;
          if (agingDays !== null) {
            if (agingDays <= 7) agingBucket = "0_7";
            else if (agingDays <= 14) agingBucket = "8_14";
            else if (agingDays <= 30) agingBucket = "15_30";
            else agingBucket = "31_plus";
          }

          const hcTotal = asNumber(vac?.required_headcount ?? vac?.headcount ?? d.required_headcount) ?? 1;
          const hcFilled = 0;
          const hcDisplay = `${hcFilled}/${hcTotal}`;
          const rawGroupName = vac?.group_id ? groupMap.get(asString(vac.group_id)!) : null;

          return {
            id: asString(vac?.id) ?? asString(d.id) ?? `failed-${idx}`,
            vcode,
            accountId: asString(vac?.account_id),
            accountName: account,
            groupId: asString(vac?.group_id),
            groupName: formatGroupName(rawGroupName, account) || null,
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
            agingDays,
            agingBucket,
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
            headcount: hcTotal,
            hcFilled,
            hcTotal,
            hcDisplay,
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

  // Enrich missing group names via accounts & groups tables lookup
  const rowsMissingGroup = rows.filter((r) => !r.groupName);
  if (rowsMissingGroup.length > 0) {
    try {
      const acctIds = Array.from(new Set(rowsMissingGroup.map((r) => r.accountId).filter(Boolean) as string[]));
      const acctNames = Array.from(new Set(rowsMissingGroup.map((r) => r.accountName).filter(Boolean) as string[]));

      let acctQuery = supabase
        .from("accounts")
        .select("id, account_name, group_id, groups(group_name)");

      if (acctIds.length > 0) {
        acctQuery = acctQuery.in("id", acctIds);
      } else if (acctNames.length > 0) {
        acctQuery = acctQuery.in("account_name", acctNames);
      }

      const { data: acctsWithGroup } = await acctQuery;
      if (acctsWithGroup && acctsWithGroup.length > 0) {
        const idGroupMap = new Map<string, { groupId: string; groupName: string }>();
        const nameGroupMap = new Map<string, { groupId: string; groupName: string }>();

        for (const item of acctsWithGroup as Array<Record<string, unknown>>) {
          const gId = asString(item.group_id);
          const grp = item.groups as Record<string, unknown> | Array<Record<string, unknown>> | null;
          const rawGName = Array.isArray(grp) ? asString(grp[0]?.group_name) : asString(grp?.group_name);
          const acctName = asString(item.account_name);
          const resolvedName = formatGroupName(rawGName, acctName);

          if (gId || resolvedName) {
            const entry = { groupId: gId || "", groupName: resolvedName };
            if (item.id) idGroupMap.set(String(item.id), entry);
            if (acctName) nameGroupMap.set(acctName.toLowerCase().trim(), entry);
          }
        }

        for (const row of rows) {
          if (!row.groupName) {
            const match = (row.accountId ? idGroupMap.get(row.accountId) : null) ||
                          (row.accountName ? nameGroupMap.get(row.accountName.toLowerCase().trim()) : null);
            if (match) {
              row.groupName = match.groupName || row.groupName;
              if (!row.groupId && match.groupId) row.groupId = match.groupId;
            }
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Enrich applicant details based on active applicants:
  const allVcodes = Array.from(new Set(rows.map((r) => r.vcode).filter(Boolean)));
  const activeByVcode = new Map<string, Array<Record<string, unknown>>>();

  if (allVcodes.length > 0) {
    try {
      const { data: applicantsData } = await supabase
        .from("applicants")
        .select("id, vacancy_vcode, first_name, last_name, middle_name, full_name, contact_number, status, hired_date, backout_reason, backout_date, created_at, updated_at")
        .in("vacancy_vcode", allVcodes)
        .eq("is_archived", false)
        .order("created_at", { ascending: false });

      if (applicantsData && applicantsData.length > 0) {
        // Group active applicants by vcode
        for (const app of applicantsData) {
          const vcode = app.vacancy_vcode;
          const status = (app.status || "").toLowerCase().trim();
          const isNonPipeline =
            status === "backout" ||
            status === "rejected" ||
            status === "failed" ||
            status === "did not report" ||
            status === "rejected by ops" ||
            status === "withdrew" ||
            status === "confirmed onboard";

          if (!isNonPipeline) {
            if (!activeByVcode.has(vcode)) activeByVcode.set(vcode, []);
            activeByVcode.get(vcode)!.push(app);
          }
        }

        for (const row of rows) {
          if (currentTab === "open") {
            // Open tab: Store requisition level, applicant fields cleared.
            row.applicantId = null;
            row.applicantName = null;
            row.contactNumber = null;
            row.stageBadge = null;
          } else {
            // Default for other tabs: attach first active candidate if present
            const actives = activeByVcode.get(row.vcode);
            const active = actives && actives[0];
            if (active) {
              row.applicantId = asString(active.id);
              row.contactNumber = row.contactNumber || asString(active.contact_number);
              row.hiredDate = row.hiredDate || asString(active.hired_date);
              let lName = asString(active.last_name);
              let fName = asString(active.first_name);
              let mName = asString(active.middle_name);
              const fFull = asString(active.full_name);
              if ((!lName || !fName) && fFull) {
                const parsed = parseCandidateFullName(fFull, {
                  firstName: fName,
                  lastName: lName,
                  middleName: mName,
                });
                lName = lName || parsed.lastName || null;
                fName = fName || parsed.firstName || null;
                mName = mName || parsed.middleName || null;
              }
              row.applicantLastName = lName;
              row.applicantFirstName = fName;
              row.applicantMiddleName = mName;
              row.applicantName = formatPersonName(fName, lName, mName, fFull || row.applicantName);
              row.stageBadge = asString(active.status) || "In Pipeline";
            }
          }
        }
      }
    } catch {
      // Graceful fallback if applicants lookup fails
    }
  }

  // Enrich coverage group CGCode and assigned stores for multi-store / coverage group vacancies
  if (allVcodes.length > 0) {
    try {
      const { data: cgShadowData } = await supabase
        .from("vw_slot_derived_vacancy_cg_covered_shadow")
        .select("legacy_vcode, cg_code, coverage_group_id")
        .in("legacy_vcode", allVcodes);

      if (cgShadowData && cgShadowData.length > 0) {
        const cgIdMap = new Map<string, { cgCode: string; coverageGroupId: string }>();
        const cgIds: string[] = [];
        for (const item of cgShadowData as Array<{ legacy_vcode: string; cg_code: string; coverage_group_id: string }>) {
          if (item.legacy_vcode) {
            cgIdMap.set(item.legacy_vcode, {
              cgCode: item.cg_code,
              coverageGroupId: item.coverage_group_id,
            });
            if (item.coverage_group_id) {
              cgIds.push(item.coverage_group_id);
            }
          }
        }

        const cgStoresMap = new Map<string, string[]>();
        if (cgIds.length > 0) {
          const { data: cgsData } = await supabase
            .from("coverage_group_stores")
            .select("coverage_group_id, stores(store_name)")
            .in("coverage_group_id", Array.from(new Set(cgIds)))
            .is("archived_at", null);

          if (cgsData) {
            for (const item of cgsData as Array<Record<string, unknown>>) {
              const cgId = asString(item.coverage_group_id);
              const storeObj = item.stores as Record<string, unknown> | null;
              const storeName = asString(storeObj?.store_name);
              if (cgId && storeName) {
                if (!cgStoresMap.has(cgId)) cgStoresMap.set(cgId, []);
                cgStoresMap.get(cgId)!.push(storeName);
              }
            }
          }
        }

        for (const row of rows) {
          const cgInfo = cgIdMap.get(row.vcode);
          if (cgInfo) {
            row.cgCode = cgInfo.cgCode;
            const stores = cgStoresMap.get(cgInfo.coverageGroupId);
            if (stores && stores.length > 0) {
              row.assignedStores = stores;
            }
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Final Tab Scoping Enforcement:
  // For Open Tab: Stays visible until quota is completely fulfilled (hcFilled < hcTotal) and not closed/archived.
  // Active pipeline candidates do not remove the requisition from Open tab.
  let finalRows = rows;
  if (currentTab === "open") {
    finalRows = rows.filter((r) => {
      const hcFilled = r.hcFilled ?? 0;
      const hcTotal = r.hcTotal ?? r.headcount ?? 1;
      const isUnfulfilled = hcFilled < hcTotal;
      const isPendingClosure =
        r.hasPendingClosure === true ||
        (r.closureRequestStatus && r.closureRequestStatus.toLowerCase() === "pending") ||
        r.derivedStatus?.toLowerCase() === "for closure" ||
        r.derivedStatus?.toLowerCase() === "closure" ||
        r.vacancyStatus?.toLowerCase() === "for_closure" ||
        r.vacancyStatus?.toLowerCase() === "closure" ||
        r.vacancyStatus?.toLowerCase() === "closed" ||
        r.vacancyStatus?.toLowerCase() === "archived";
      return isUnfulfilled && !isPendingClosure;
    });
    for (const r of finalRows) {
      r.applicantId = null;
      r.applicantName = null;
      r.contactNumber = null;
      r.stageBadge = null;
      r.dropoutReason = null;
      r.dropoutDate = null;
    }
  }

  return {
    data: finalRows,
    totalCount: getTotalCount(finalRows) || getTotalCount(rows),
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
            const mName = asString(match.middle_name);
            const rawFull = asString(match.full_name);
            const workerName = formatPersonName(fName, lName, mName, rawFull || "Hired Worker");
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
            const vacDate = asString(vacRow?.vacant_date ?? vacRow?.created_at) || hiredDate;

            return {
              vacancyId,
              vcode,
              accountId: asString(vacRow?.account_id),
              accountName: asString(match.account ?? vacRow?.account),
              groupId: asString(vacRow?.group_id),
              groupName: asString(match.group_name ?? vacRow?.group_name),
              storeId: asString(vacRow?.store_id),
              storeName: asString(vacRow?.store_name ?? vacRow?.store_branch ?? vacRow?.store),
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
              vacantDate: vacDate,
              daysToFill: calculateDaysToFill(vacDate, hiredDate),
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
              headcount: 1,
              applicantLastName: lName,
              applicantFirstName: fName,
              applicantMiddleName: mName,
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
                  middleName: mName,
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

        // 2. Direct fallback for Filled / Closed / Archived vacancies (including dropouts)
        let vacRow: Record<string, unknown> | null = null;
        let targetVcode: string | null = null;

        // Check if vacancyId is an applicant id
        const { data: directApp } = await supabase
          .from("applicants")
          .select("*")
          .eq("id", vacancyId)
          .maybeSingle();

        if (directApp?.vacancy_vcode) {
          targetVcode = directApp.vacancy_vcode as string;
        }

        // Fetch vacancy by ID or vcode
        if (targetVcode) {
          const { data: vData } = await supabase
            .from("vacancies")
            .select("*")
            .eq("vcode", targetVcode)
            .is("deleted_at", null)
            .maybeSingle();
          vacRow = vData;
        } else {
          const { data: vData } = await supabase
            .from("vacancies")
            .select("*")
            .eq("id", vacancyId)
            .is("deleted_at", null)
            .maybeSingle();
          vacRow = vData;
          if (vacRow?.vcode) {
            targetVcode = vacRow.vcode as string;
          }
        }

        if (vacRow) {
          const vcode = asString(vacRow.vcode) ?? targetVcode ?? "Uncoded";
          const { data: allApps } = await supabase
            .from("applicants")
            .select("*")
            .eq("vacancy_vcode", vcode)
            .order("created_at", { ascending: false });

          const appsList = (allApps ?? []) as Array<Record<string, unknown>>;
          const primaryApp = directApp || appsList[0] || null;

          const areaCity = asString(vacRow.area_city);
          const areaProvince = asString(vacRow.area_province ?? vacRow.province);
          const storeLocation = [areaCity, areaProvince].filter(Boolean).join(" • ") || null;
          const vacDate = asString(vacRow.vacant_date ?? vacRow.created_at);

          const lName = asString(primaryApp?.last_name);
          const fName = asString(primaryApp?.first_name);
          const mName = asString(primaryApp?.middle_name);
          const rawFull = asString(primaryApp?.full_name);
          const candidateName = formatPersonName(fName, lName, mName, rawFull || "Candidate");

          const isMosesPool =
            vcode.includes("GHQ") ||
            String(vacRow.account || "").toLowerCase() === "moses hq" ||
            vacRow.source === "pool" ||
            asBoolean(vacRow.is_pool_vacancy);

          const storeName =
            asString(vacRow.store_name ?? vacRow.store_branch) || (isMosesPool ? "Moses HQ" : null);

          const confirmedCount = appsList.filter(
            (a) => (asString(a.status) || "").toLowerCase().trim() === "confirmed onboard",
          ).length;
          const activeCount = appsList.filter((a) => !asBoolean(a.is_archived)).length;
          const reqHc = asNumber(vacRow.required_headcount ?? vacRow.headcount) ?? 1;
          const occupiedCount = confirmedCount + activeCount;

          return {
            vacancyId: asString(vacRow.id) ?? vacancyId,
            vcode,
            accountId: asString(vacRow.account_id),
            accountName: asString(vacRow.account),
            groupId: asString(vacRow.group_id),
            groupName: asString(vacRow.group_name),
            storeId: asString(vacRow.store_id),
            storeName,
            position_title: asString(vacRow.position),
            department: asString(vacRow.department ?? vacRow.business_unit),
            employmentType: asString(vacRow.employment_type),
            vacancyStatus: asString(vacRow.status),
            pipelineStatus: asString(vacRow.status),
            derivedStatus: asString(vacRow.status),
            activeApplicantCount: activeCount,
            confirmedOnboardCount: confirmedCount,
            hasRecentHire: confirmedCount > 0,
            hasPendingClosure: asBoolean(vacRow.has_pending_closure),
            closureRequestStatus: asString(vacRow.closure_request_status),
            vacantDate: vacDate,
            daysToFill: null,
            agingDays: null,
            agingBucket: null,
            targetFillDate: asString(vacRow.target_fill_date),
            urgencyLevel: asString(vacRow.urgency_level),
            hrcoName: asString(vacRow.hrco_name) ?? "—",
            lastActivityAt: asString(vacRow.updated_at ?? vacRow.created_at),
            rowCapabilities: {
              canViewDetail: true,
              canApprove: false,
              canUpdateApplicantStatus: false,
              canRequestClosure: false,
              raw: {},
            },
            contactNumber: asString(primaryApp?.contact_number),
            onboardDate: asString(primaryApp?.hired_at ?? primaryApp?.hired_date),
            relieverOnDuty: null,
            hasReliever: false,
            hrcoRemarks: null,
            recruiterName: null,
            deployedByName: null,
            hasPenalty: false,
            penaltyExposure: 0,
            penaltyAmount: null,
            headcount: reqHc,
            hcFilled: occupiedCount,
            hcTotal: reqHc,
            hcDisplay: `${occupiedCount}/${reqHc}`,
            applicantLastName: lName,
            applicantFirstName: fName,
            applicantMiddleName: mName,
            applicantName: candidateName,
            applicantId: asString(primaryApp?.id),
            storeLocation,
            areaCity,
            areaProvince,
            storeBranch: asString(vacRow.store_branch),
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
            activeApplicantsList: appsList.map((a: Record<string, unknown>) => ({
              applicantId: asString(a.id) ?? "",
              displayName: formatPersonName(
                asString(a.first_name),
                asString(a.last_name),
                asString(a.middle_name),
                asString(a.full_name) || "Applicant",
              ),
              lastName: asString(a.last_name),
              firstName: asString(a.first_name),
              middleName: asString(a.middle_name),
              contactNumber: asString(a.contact_number),
              statusLabel: asString(a.status) || "Active",
              onboardDate: asString(a.hired_at ?? a.hired_date),
              updatedAt: asString(a.updated_at),
              recruiterName: null,
              deployedByName: null,
            })),
            activityHistory: [],
          };
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

  // Enrich leadership team (OM, TL, ATL, HRCO) and group from accounts and users_profile
  if (normalized.accountId || normalized.accountName) {
    try {
      const { data: rawAccount } = await supabase
        .from("accounts")
        .select("id, account_name, group_id, hrco_user_id, om_user_id, atl_user_id, om_name, atl_name, groups(group_name)")
        .eq(normalized.accountId ? "id" : "account_name", normalized.accountId || normalized.accountName)
        .maybeSingle();

      if (rawAccount) {
        if (!normalized.groupName) {
          const grp = rawAccount.groups as Record<string, unknown> | Array<Record<string, unknown>> | null;
          const rawGName = Array.isArray(grp) ? asString(grp[0]?.group_name) : asString(grp?.group_name);
          normalized.groupName = formatGroupName(rawGName, rawAccount.account_name) || normalized.groupName;
          if (!normalized.groupId && rawAccount.group_id) normalized.groupId = asString(rawAccount.group_id);
        }
        if (!normalized.omName && rawAccount.om_name) normalized.omName = rawAccount.om_name;
        if (!normalized.atlName && rawAccount.atl_name) normalized.atlName = rawAccount.atl_name;

        const userIdsToFetch = [
          !normalized.hrcoName && rawAccount.hrco_user_id ? rawAccount.hrco_user_id : null,
          !normalized.omName && rawAccount.om_user_id ? rawAccount.om_user_id : null,
          !normalized.atlName && rawAccount.atl_user_id ? rawAccount.atl_user_id : null,
        ].filter(Boolean) as string[];

        if (userIdsToFetch.length > 0) {
          const { data: profs } = await supabase
            .from("users_profile")
            .select("id, full_name")
            .in("id", userIdsToFetch);

          if (profs) {
            for (const p of profs) {
              if (p.id === rawAccount.hrco_user_id && !normalized.hrcoName) {
                normalized.hrcoName = p.full_name;
              }
              if (p.id === rawAccount.om_user_id && !normalized.omName) {
                normalized.omName = p.full_name;
              }
              if (p.id === rawAccount.atl_user_id && !normalized.atlName) {
                normalized.atlName = p.full_name;
              }
            }
          }
        }

        if (!normalized.hrcoName) {
          const accId = normalized.accountId || rawAccount?.id;
          const grpId = normalized.groupId || rawAccount?.group_id;
          if (accId || grpId) {
            try {
              let scopeQuery = supabase
                .from("user_scopes")
                .select("user_id, account_id, group_id, users_profile!inner(id, full_name, is_active, archived_at, roles!inner(role_name))")
                .eq("users_profile.is_active", true)
                .is("users_profile.archived_at", null)
                .eq("users_profile.roles.role_name", "HRCO")
                .order("created_at", { ascending: true })
                .limit(1);

              if (accId) {
                scopeQuery = scopeQuery.eq("account_id", accId);
              } else if (grpId) {
                scopeQuery = scopeQuery.eq("group_id", grpId).is("account_id", null);
              }

              const { data: scopedUser } = await scopeQuery.maybeSingle();
              if (scopedUser?.users_profile) {
                const up = Array.isArray(scopedUser.users_profile)
                  ? scopedUser.users_profile[0]
                  : (scopedUser.users_profile as unknown as { full_name?: string });
                if (up?.full_name) {
                  normalized.hrcoName = up.full_name;
                }
              }
            } catch {
              // fallback
            }
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Also query team directory for TL (and OM/ATL if missing)
  if (normalized.accountId && (!normalized.tlName || !normalized.omName || !normalized.atlName)) {
    try {
      const { data: teamData } = await supabase.rpc("get_team_directory", {
        p_account_id: normalized.accountId,
      });
      if (Array.isArray(teamData)) {
        const omList: string[] = [];
        const tlList: string[] = [];
        const atlList: string[] = [];
        for (const item of teamData) {
          const role = String(item.role_name || "").toLowerCase().replace(/[^a-z0-9]/g, "");
          const name = String(item.full_name || item.display_name || "").trim();
          if (!name) continue;
          if (role === "om" || role === "operationsmanager") omList.push(name);
          else if (role === "tl" || role === "teamleader") tlList.push(name);
          else if (role === "atl" || role === "assistantteamleader") atlList.push(name);
        }
        if (!normalized.omName && omList.length > 0) normalized.omName = Array.from(new Set(omList)).join(", ");
        if (!normalized.tlName && tlList.length > 0) normalized.tlName = Array.from(new Set(tlList)).join(", ");
        if (!normalized.atlName && atlList.length > 0) normalized.atlName = Array.from(new Set(atlList)).join(", ");
      }
    } catch {
      // Graceful fallback
    }
  }

  // Ensure pending closure and extra metadata details are enriched if applicable
  if (normalized.vcode) {
    try {
      const { data: vacCheck } = await supabase
        .from("vacancies")
        .select("has_pending_closure, closure_request_status, source, vacancy_type, created_at, target_fill_date, vacant_date, required_headcount")
        .eq("vcode", normalized.vcode)
        .maybeSingle();
      if (vacCheck) {
        if (!normalized.hasPendingClosure && vacCheck.has_pending_closure) normalized.hasPendingClosure = true;
        if (!normalized.closureRequestStatus && vacCheck.closure_request_status) normalized.closureRequestStatus = vacCheck.closure_request_status;
        if (!normalized.source && vacCheck.source) normalized.source = vacCheck.source;
        if (!normalized.vacancyType && vacCheck.vacancy_type) normalized.vacancyType = vacCheck.vacancy_type;
        if (!normalized.createdAt && vacCheck.created_at) normalized.createdAt = vacCheck.created_at;
        if (!normalized.targetFillDate && vacCheck.target_fill_date) normalized.targetFillDate = vacCheck.target_fill_date;
        if (!normalized.vacantDate && vacCheck.vacant_date) normalized.vacantDate = vacCheck.vacant_date;
        if ((!normalized.headcount || normalized.headcount <= 1) && vacCheck.required_headcount) {
          normalized.headcount = Number(vacCheck.required_headcount);
          normalized.hcTotal = normalized.headcount;
          normalized.hcDisplay = `${normalized.hcFilled ?? normalized.confirmedOnboardCount ?? 0}/${normalized.hcTotal}`;
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Enrich assigned stores for coverage groups if not already present
  if (!normalized.assignedStores || normalized.assignedStores.length === 0) {
    try {
      const { data: cgShadowData } = await supabase
        .from("vw_slot_derived_vacancy_cg_covered_shadow")
        .select("legacy_vcode, cg_code, coverage_group_id")
        .eq("legacy_vcode", normalized.vcode)
        .maybeSingle();

      if (cgShadowData?.coverage_group_id) {
        if (cgShadowData.cg_code) normalized.cgCode = cgShadowData.cg_code;
        const { data: cgsData } = await supabase
          .from("coverage_group_stores")
          .select("coverage_group_id, stores(store_name)")
          .eq("coverage_group_id", cgShadowData.coverage_group_id)
          .is("archived_at", null);

        if (cgsData && cgsData.length > 0) {
          const stores: string[] = [];
          for (const item of cgsData as Array<Record<string, unknown>>) {
            const storeObj = item.stores as Record<string, unknown> | null;
            const sName = asString(storeObj?.store_name);
            if (sName && !stores.includes(sName)) {
              stores.push(sName);
            }
          }
          if (stores.length > 0) {
            normalized.assignedStores = stores;
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Enrich itemized requirements if available
  try {
    const { data: reqData } = await supabase
      .from("vacancy_requirements")
      .select("id, vacancy_id, position_id, employment_type, hc_needed, hc_filled")
      .eq("vacancy_id", normalized.vacancyId)
      .order("hc_needed", { ascending: false });

    if (reqData && reqData.length > 0) {
      const posIds = (reqData as Array<Record<string, unknown>>)
        .map((r) => asString(r.position_id))
        .filter(Boolean);
      const posMap = new Map<string, string>();
      if (posIds.length > 0) {
        try {
          const { data: posData } = await supabase
            .from("positions")
            .select("id, position_name")
            .in("id", posIds);
          if (posData) {
            for (const p of posData as Array<Record<string, unknown>>) {
              const pid = asString(p.id);
              const pname = asString(p.position_name);
              if (pid && pname) posMap.set(pid, pname);
            }
          }
        } catch {
          // Graceful fallback
        }
      }

      normalized.requirements = (reqData as Array<Record<string, unknown>>).map((r) => {
        const pid = asString(r.position_id);
        return {
          id: asString(r.id) || "",
          positionName: (pid ? posMap.get(pid) : null) || normalized.position_title || "Position",
          employmentType: asString(r.employment_type) || normalized.employmentType,
          hcNeeded: asNumber(r.hc_needed) || 1,
          hcFilled: asNumber(r.hc_filled) || 0,
          pipelineCount: normalized.activeApplicantCount || 0,
        };
      });
    }
  } catch {
    // Graceful fallback
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

  if (normalized.activeApplicantsList && normalized.activeApplicantsList.length > 0) {
    try {
      const appIds = normalized.activeApplicantsList.map((a) => a.applicantId).filter(Boolean);
      if (appIds.length > 0) {
        const { data: appsData } = await supabase
          .from("applicants")
          .select("id, contact_number, first_name, last_name, middle_name, profile_edit_count, created_at, updated_at")
          .in("id", appIds);
        if (Array.isArray(appsData)) {
          const appMap = new Map(appsData.map((a: Record<string, unknown>) => [asString(a.id), a]));
          for (const cand of normalized.activeApplicantsList) {
            const rawApp = appMap.get(cand.applicantId);
            if (rawApp) {
              if (!cand.contactNumber && rawApp.contact_number) cand.contactNumber = asString(rawApp.contact_number);
              if (!cand.firstName && rawApp.first_name) cand.firstName = asString(rawApp.first_name);
              if (!cand.lastName && rawApp.last_name) cand.lastName = asString(rawApp.last_name);
              if (!cand.middleName && rawApp.middle_name) cand.middleName = asString(rawApp.middle_name);
              if (rawApp.profile_edit_count !== undefined && rawApp.profile_edit_count !== null) {
                cand.profileEditCount = Number(rawApp.profile_edit_count);
              }
              if (!cand.createdAt && rawApp.created_at) cand.createdAt = asString(rawApp.created_at);
              if (!cand.updatedAt && rawApp.updated_at) cand.updatedAt = asString(rawApp.updated_at);
            }

            if (cand.agingDays === undefined || cand.agingDays === null) {
              const ts = cand.createdAt || cand.updatedAt;
              if (ts) {
                const diffMs = Date.now() - new Date(ts).getTime();
                if (!isNaN(diffMs)) {
                  cand.agingDays = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
                }
              }
            }
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  return normalized;
}

// ── Candidate Duplicate Verification ──────────────────────────
export type CandidateDuplicateCheckResult = {
  isBlocked: boolean;
  conflictType?: "Pipeline" | "HR Emploc" | "Plantilla" | null;
  status?: string | null;
  vcode?: string | null;
  storeName?: string | null;
  account?: string | null;
  message?: string | null;
};

export async function checkCandidateDuplicate(params: {
  firstName: string;
  lastName: string;
  contactNumber?: string | null;
  currentApplicantId?: string | null;
}): Promise<CandidateDuplicateCheckResult> {
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("check_candidate_duplicate", {
      p_first_name: params.firstName.trim(),
      p_last_name: params.lastName.trim(),
      p_contact: params.contactNumber?.trim() || null,
      p_current_applicant_id: params.currentApplicantId || null,
    });
    if (error) {
      console.warn("check_candidate_duplicate RPC warning:", error.message);
      return { isBlocked: false };
    }
    if (data && typeof data === "object") {
      const res = data as Record<string, unknown>;
      return {
        isBlocked: res.is_blocked === true,
        conflictType: (res.conflict_type as CandidateDuplicateCheckResult["conflictType"]) ?? null,
        status: (res.status as string) ?? null,
        vcode: (res.vcode as string) ?? null,
        storeName: (res.store_name as string) ?? null,
        account: (res.account as string) ?? null,
        message: (res.message as string) ?? null,
      };
    }
    return { isBlocked: false };
  } catch (err) {
    console.warn("checkCandidateDuplicate exception (non-blocking):", err);
    return { isBlocked: false };
  }
}

// ── Edit Applicant Details (fn_update_applicant_profile_once) ──
export type UpdateApplicantProfileParams = {
  applicantId: string;
  firstName: string;
  lastName: string;
  middleName?: string | null;
  contactNumber: string;
  reason: string;
  vcode?: string;
};

export type UpdateApplicantProfileResult = {
  success: boolean;
  applicantId: string;
  linkedPropagatedCount: number;
};

export async function updateApplicantProfileOnce(
  params: UpdateApplicantProfileParams,
): Promise<UpdateApplicantProfileResult> {
  const supabase = createClient();
  const applicantId = params.applicantId.trim();
  const firstName = params.firstName.trim().toUpperCase();
  const lastName = params.lastName.trim().toUpperCase();
  const rawMiddle = params.middleName?.trim();
  const middleName =
    rawMiddle && !["", "NA", "N/A", "NONE", "N.A."].includes(rawMiddle.toUpperCase())
      ? rawMiddle.toUpperCase()
      : null;
  const reason = params.reason.trim();

  // Normalize contact number: 11 digits starting with 09
  const cleanContact = params.contactNumber.replace(/[^0-9]/g, "");
  const normalizedContact =
    cleanContact.length === 10 && cleanContact.startsWith("9")
      ? `0${cleanContact}`
      : cleanContact;

  if (!applicantId) {
    throw new VacancyDataError("validation", "Applicant ID is required.");
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
  if (!reason) {
    throw new VacancyDataError("validation", "Reason / comments for editing profile are required.");
  }

  const { error } = await supabase.rpc("fn_update_applicant_profile_once", {
    p_applicant_id: applicantId,
    p_first_name: firstName,
    p_last_name: lastName,
    p_contact_number: normalizedContact,
    p_middle_name: middleName,
    p_reason: reason,
  });

  if (error) {
    if (error.code === "42501") {
      throw new VacancyDataError("access_denied", error.message || "Permission denied to edit applicant details.");
    }
    throw new VacancyDataError("generic", error.message);
  }

  // Propagate identity fields to other active pipeline rows with the same contact number
  let linkedPropagatedCount = 0;
  try {
    linkedPropagatedCount = await propagateApplicantIdentityToLinked({
      applicantId,
      firstName,
      lastName,
      middleName,
      contactNumber: normalizedContact,
    });
  } catch (propError) {
    console.warn("propagateApplicantIdentityToLinked error (non-fatal):", propError);
  }

  return {
    success: true,
    applicantId,
    linkedPropagatedCount,
  };
}

export async function propagateApplicantIdentityToLinked(params: {
  applicantId: string;
  firstName: string;
  lastName: string;
  middleName?: string | null;
  contactNumber: string;
}): Promise<number> {
  const supabase = createClient();
  const normalizedContact = params.contactNumber.trim();
  if (!normalizedContact) return 0;

  const lockedStatuses = [
    "confirmed_onboard",
    "transferred",
    "hired",
    "Confirmed Onboard",
    "Transferred",
    "Hired",
  ];

  const { data: rows, error: selectError } = await supabase
    .from("applicants")
    .select("id, status")
    .eq("contact_number", normalizedContact)
    .neq("id", params.applicantId)
    .or("is_archived.is.null,is_archived.eq.false");

  if (selectError || !Array.isArray(rows)) return 0;

  const eligibleIds = rows
    .filter((r) => !lockedStatuses.includes(String(r.status)))
    .map((r) => r.id as string)
    .filter(Boolean);

  if (eligibleIds.length === 0) return 0;

  const fullName = formatPersonName(params.firstName, params.lastName, params.middleName);

  const { error: updateError } = await supabase
    .from("applicants")
    .update({
      first_name: params.firstName,
      last_name: params.lastName,
      middle_name: params.middleName || null,
      contact_number: normalizedContact,
      full_name: fullName,
      updated_at: new Date().toISOString(),
    })
    .in("id", eligibleIds);

  if (updateError) {
    console.warn("propagateApplicantIdentityToLinked update failed:", updateError.message);
    return 0;
  }

  return eligibleIds.length;
}

export function useUpdateApplicantProfile() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: UpdateApplicantProfileParams) => updateApplicantProfileOnce(params),
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

export type EndorseApplicantParams = {
  vcode: string;
  firstName: string;
  middleName: string;
  lastName: string;
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
  const firstName = params.firstName.trim().toUpperCase();
  const lastName = params.lastName.trim().toUpperCase();
  const middleName = params.middleName?.trim().toUpperCase() || "";
  const fullName = formatPersonName(firstName, lastName, middleName);
  
  // Normalize contact number: must be 11 digits starting with 09
  const cleanContact = params.contactNumber.replace(/[^0-9]/g, "");
  const normalizedContact =
    cleanContact.length === 10 && cleanContact.startsWith("9")
      ? `0${cleanContact}`
      : cleanContact;

  if (!vcode) {
    throw new VacancyDataError("validation", "Target VCode is required.");
  }
  if (!firstName || !middleName || !lastName) {
    throw new VacancyDataError("validation", "First Name, Middle Name, and Last Name are required.");
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

  // Pre-insert candidate duplicate check (Pipeline, HR Emploc, Plantilla)
  const dupCheck = await checkCandidateDuplicate({
    firstName,
    lastName,
    contactNumber: normalizedContact,
  });
  if (dupCheck.isBlocked) {
    throw new VacancyDataError(
      "validation",
      dupCheck.message ||
        "Candidate is already active in another requisition, HR Emploc processing, or Plantilla slot. Duplicate creation is blocked.",
    );
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

  // 3. Status transition: Requisitions remain 'Open' until all required headcount is confirmed onboard.
  // We do not overwrite vacancies.status to 'Pipeline' so multi-headcount vacancies stay actionable in Open tab.

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
    const isTerminal =
      params.newStatus?.toLowerCase() === "backout" ||
      params.newStatus?.toLowerCase() === "rejected" ||
      params.newStatus?.toLowerCase() === "failed";

    if (isTerminal) {
      updates.is_archived = true;
      updates.slot_id = null;
    }
    if (params.newStatus === "backout" || params.newStatus === "Backout") {
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

  // 1. Resolve target applicant ID defensively (if caller accidentally passed a vacancy ID)
  let targetApplicantId = params.applicantId;
  const { data: existingApp } = await supabase
    .from("applicants")
    .select("id, status, slot_id, vacancy_vcode")
    .eq("id", targetApplicantId)
    .maybeSingle();

  if (!existingApp && params.vcode) {
    const { data: activeApp } = await supabase
      .from("applicants")
      .select("id, status, slot_id, vacancy_vcode")
      .eq("vacancy_vcode", params.vcode)
      .eq("is_archived", false)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (activeApp) {
      targetApplicantId = activeApp.id;
    }
  }

  const prevStatus = existingApp?.status || null;
  const boundSlotId = existingApp?.slot_id || null;

  // 2. Mark applicant record strictly as terminal, archived, and unlink slot
  const { error } = await supabase
    .from("applicants")
    .update({
      status: params.status,
      backout_reason: params.reason,
      backout_date: new Date().toISOString().substring(0, 10),
      is_archived: true,
      archived_at: new Date().toISOString(),
      slot_id: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", targetApplicantId);

  if (error) {
    throw new VacancyDataError("generic", error.message);
  }

  // 3. Record status history in applicant_status_history
  try {
    const { data: userRes } = await supabase.auth.getUser();
    let profileId: string | null = null;
    let profileName: string | null = null;

    if (userRes?.user?.id) {
      const { data: profile } = await supabase
        .from("users_profile")
        .select("id, full_name")
        .eq("auth_user_id", userRes.user.id)
        .maybeSingle();
      if (profile) {
        profileId = profile.id;
        profileName = profile.full_name;
      }
    }

    await supabase.from("applicant_status_history").insert({
      applicant_id: targetApplicantId,
      from_status: prevStatus,
      to_status: params.status,
      reason_id: params.reasonId || null,
      reason_type: statusCode,
      remarks: params.reason,
      changed_by: profileId,
      changed_by_name: profileName,
      source_module: "vacancy",
      update_type: "status_change",
      changed_field: "status",
      old_value: prevStatus,
      new_value: params.status,
    });
  } catch {
    // Non-fatal if history logging fails
  }

  // 4. Release bound slot and reconcile vacancy slots
  if (boundSlotId) {
    try {
      await supabase.rpc("fn_release_applicant_slot", {
        p_slot_id: boundSlotId,
        p_performed_by: null,
      });
    } catch {
      // Non-fatal
    }
  }

  try {
    await supabase.rpc("fn_sync_vacancy_slot_open_pipeline", {
      p_vcode: params.vcode,
      p_performed_by: null,
      p_source_fn: "failBackoutApplicant",
    });
  } catch {
    // Non-fatal
  }

  // 5. Quota-aware vacancy status transition:
  // If this vacancy now has 0 remaining active pipeline candidates, check if required quota is still unfilled before returning to 'Open'
  try {
    const { data: vac } = await supabase
      .from("vacancies")
      .select("id, required_headcount, status")
      .eq("vcode", params.vcode)
      .maybeSingle();

    if (vac) {
      const { data: activeApps } = await supabase
        .from("applicants")
        .select("id, status")
        .eq("vacancy_vcode", params.vcode)
        .eq("is_archived", false)
        .neq("id", targetApplicantId);

      const activeList = activeApps ?? [];
      const confirmedCount = activeList.filter(
        (a) => (a.status || "").toLowerCase().trim() === "confirmed onboard",
      ).length;

      const requiredHc = Number(vac.required_headcount ?? 1) || 1;

      // Multi-headcount rule: as long as confirmed onboard count < required headcount,
      // the requisition has remaining open slots and must stay/reappear in Open tab.
      if (confirmedCount < requiredHc) {
        await supabase
          .from("vacancies")
          .update({
            status: "Open",
            is_archived: false,
            archived_at: null,
            archived_by: null,
            updated_at: new Date().toISOString(),
          })
          .eq("vcode", params.vcode);
      } else {
        await supabase
          .from("vacancies")
          .update({
            status: "Filled",
            updated_at: new Date().toISOString(),
          })
          .eq("vcode", params.vcode);
      }
    }
  } catch {
    // Non-fatal if status check fails
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

export type WithdrawVacancyClosureParams = {
  vcode: string;
  userId?: string | null;
};

export async function withdrawVacancyClosureRequest(params: WithdrawVacancyClosureParams) {
  const supabase = createClient();
  const vcode = params.vcode.trim();
  if (!vcode) {
    throw new VacancyDataError("validation", "Target VCode is required.");
  }

  try {
    const { data, error } = await supabase.rpc("withdraw_vacancy_closure_request", {
      p_vcode: vcode,
    });
    if (error) throw error;
    return data;
  } catch {
    // Fallback: direct table update matching mobile service
    const { error: updateError } = await supabase
      .from("vacancy_closure_requests")
      .update({
        status: "Withdrawn",
        withdrawn_by_user_id: params.userId || null,
        withdrawn_at: new Date().toISOString(),
      })
      .eq("vacancy_vcode", vcode)
      .eq("status", "Pending");

    if (updateError) {
      throw new VacancyDataError("generic", updateError.message);
    }

    // Clear pending closure flag on vacancy
    await supabase
      .from("vacancies")
      .update({
        has_pending_closure: false,
        closure_request_status: null,
        updated_at: new Date().toISOString(),
      })
      .eq("vcode", vcode);

    return { success: true };
  }
}

export function useWithdrawVacancyClosureRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: WithdrawVacancyClosureParams) => withdrawVacancyClosureRequest(params),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-counts"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-list"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["pending-vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-closure-counts"] });
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

// ── 8. Full Unpaginated Vacancy Dataset Export ──────────────────

export type VacancyExportFilters = {
  search?: string;
  accountId?: string;
  groupId?: string;
  aging?: string;
  agingBucket?: string;
  urgency?: string;
  dateFrom?: string;
  vacantFrom?: string;
  dateTo?: string;
  vacantTo?: string;
};

export type VacancyExportResult = {
  csv: string;
  rowCount: number;
  filename: string;
  scopeTitle: string;
};

export interface VacancyExportRowData {
  vcode: string;
  positionTitle: string;
  lifecycleStatus: string;
  accountName: string;
  groupName: string;
  storeName: string;
  storeLocation: string;
  hrcoName: string;
  agingDays: string;
  urgencyLevel: string;
  createdDate: string;
}

const VACANCY_EXPORT_HEADERS = [
  "VCode",
  "Position Title",
  "Lifecycle Status",
  "Account Name",
  "Operational Group",
  "Outlet / Store Name",
  "City / Location",
  "Assigned HRCO",
  "Aging (Days)",
  "Urgency Level",
  "Created Date",
] as const;

function escapeCsvValue(val: unknown): string {
  if (val === null || val === undefined) return "";
  const str = String(val).trim();
  if (/[",\r\n]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function buildVacancyExportCsv(rows: VacancyExportRowData[]): string {
  const headerLine = VACANCY_EXPORT_HEADERS.map(escapeCsvValue).join(",");
  const dataLines = rows.map((r) =>
    [
      escapeCsvValue(r.vcode),
      escapeCsvValue(r.positionTitle),
      escapeCsvValue(r.lifecycleStatus),
      escapeCsvValue(r.accountName),
      escapeCsvValue(r.groupName),
      escapeCsvValue(r.storeName),
      escapeCsvValue(r.storeLocation),
      escapeCsvValue(r.hrcoName),
      escapeCsvValue(r.agingDays),
      escapeCsvValue(r.urgencyLevel),
      escapeCsvValue(r.createdDate),
    ].join(",")
  );

  return "\uFEFF" + [headerLine, ...dataLines].join("\r\n");
}

export function getVacancyExportTimestamp(date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  const yyyy = date.getFullYear();
  const mm = pad(date.getMonth() + 1);
  const dd = pad(date.getDate());
  const hh = pad(date.getHours());
  const min = pad(date.getMinutes());
  return `${yyyy}${mm}${dd}_${hh}${min}`;
}

export function getVacancyExportScopeTitle(
  scope: "current_tab" | "all_statuses",
  currentTab: string,
): string {
  if (scope === "all_statuses") {
    return "ALL_STATUSES";
  }
  const normalized = currentTab.toLowerCase().trim();
  switch (normalized) {
    case "open":
      return "Open";
    case "pipeline":
    case "with_applicant":
      return "Pipeline";
    case "hired":
      return "Hired";
    case "closure":
      return "Closure";
    case "failed_backout":
    case "failed / backout":
    case "failed-backout":
      return "Failed_Backout";
    default:
      return currentTab.replace(/[^a-zA-Z0-9]+/g, "_").replace(/^_+|_+$/g, "") || "Current_Tab";
  }
}

async function fetchAllRpcVacancies(
  rpcStatus: string | null,
  filters: VacancyExportFilters,
  lifecycleStatus: string,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  const PAGE_BATCH = 200;
  let offset = 0;
  const allRows: VacancyListItem[] = [];

  while (true) {
    const rpcParams = {
      p_status: rpcStatus,
      p_account_id: asUuidFilter(filters.accountId),
      p_group_id: asUuidFilter(filters.groupId),
      p_aging_bucket: normalizeAgingBucket(filters.aging || filters.agingBucket) ?? null,
      p_urgency: normalizeUrgency(filters.urgency) ?? null,
      p_search: asTrimmedString(filters.search) ?? null,
      p_vacant_from: asDateFilter(filters.dateFrom || filters.vacantFrom) ?? null,
      p_vacant_to: asDateFilter(filters.dateTo || filters.vacantTo) ?? null,
      p_limit: PAGE_BATCH,
      p_offset: offset,
      p_sort_by: normalizeSortField("aging_days"),
      p_sort_dir: normalizeSortDirection("desc"),
    };

    const { data, error } = await supabase.rpc("list_web_vacancies", rpcParams);
    if (error) {
      throwVacancyError(error);
    }

    const rows = (Array.isArray(data) ? data : [])
      .map((row) => normalizeListRow(asObject(row)))
      .filter((row): row is VacancyListItem => row !== null);

    if (rows.length === 0) {
      break;
    }

    allRows.push(...rows);

    const totalCount = rows[0]?.totalCount ?? 0;
    if (allRows.length >= totalCount || rows.length < PAGE_BATCH) {
      break;
    }

    offset += PAGE_BATCH;
  }

  // Enrich missing store locations via stores table
  const missingStoreIds = Array.from(
    new Set(allRows.filter((r) => !r.storeLocation && r.storeId).map((r) => r.storeId as string))
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
          const loc = [s.area_city, s.area_province || s.province].filter(Boolean).join(" • ");
          if (loc) storeLocationMap.set(s.id, loc);
        }
        for (const row of allRows) {
          if (row.storeId && storeLocationMap.has(row.storeId)) {
            row.storeLocation = storeLocationMap.get(row.storeId) ?? null;
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  return allRows.map((item) => {
    const agingDaysStr =
      item.agingDays !== null && item.agingDays !== undefined && !Number.isNaN(item.agingDays)
        ? String(item.agingDays)
        : "";
    const createdDateStr = item.vacantDate
      ? item.vacantDate.includes("T")
        ? item.vacantDate.split("T")[0]
        : item.vacantDate
      : "";

    return {
      vcode: item.vcode || "",
      positionTitle: item.position_title || "",
      lifecycleStatus,
      accountName: item.accountName || "",
      groupName: item.groupName || "",
      storeName: item.storeName || "",
      storeLocation: item.storeLocation || "",
      hrcoName: item.hrcoName || "",
      agingDays: agingDaysStr,
      urgencyLevel: item.urgencyLevel || "",
      createdDate: createdDateStr,
    };
  });
}

async function fetchAllPipelineVacancies(
  filters: VacancyExportFilters,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  try {
    const TERMINAL_STATUSES = [
      "failed",
      "backout",
      "rejected",
      "did_not_report",
      "did not report",
      "rejected_by_ops",
      "rejected by ops",
      "withdrew",
      "confirmed_onboard",
      "confirmed onboard",
      "hired",
    ];

    const { data: pipelineApplicants, error: appsError } = await supabase
      .from("applicants")
      .select(`
        id,
        vacancy_vcode,
        first_name,
        last_name,
        middle_name,
        full_name,
        contact_number,
        status,
        created_at,
        updated_at,
        profile_edit_count,
        is_archived
      `)
      .eq("is_archived", false)
      .order("created_at", { ascending: false });

    if (appsError || !Array.isArray(pipelineApplicants)) {
      return [];
    }

    const activeCandidates = pipelineApplicants.filter((a) => {
      const normStatus = (asString(a.status) || "").toLowerCase().trim().replace(/[\s-]+/g, "_");
      return !TERMINAL_STATUSES.some((t) => t.replace(/[\s-]+/g, "_") === normStatus);
    });

    const vcodes = Array.from(
      new Set(activeCandidates.map((c) => asString(c.vacancy_vcode)).filter(Boolean)),
    ) as string[];

    let vacQuery = supabase
      .from("vacancies")
      .select(`
        id,
        vcode,
        store_name,
        store_branch,
        store_id,
        position,
        account,
        account_id,
        group_id,
        area_city,
        province,
        hrco_name,
        vacant_date,
        created_at,
        target_fill_date,
        urgency_level,
        status,
        is_archived,
        deleted_at,
        required_headcount,
        has_pending_closure,
        closure_request_status,
        employment_type,
        source,
        is_pool_vacancy
      `)
      .in("vcode", vcodes)
      .eq("is_archived", false)
      .is("deleted_at", null);

    if (filters.accountId) {
      vacQuery = vacQuery.eq("account_id", filters.accountId);
    }
    if (filters.groupId) {
      vacQuery = vacQuery.eq("group_id", filters.groupId);
    }
    if (filters.urgency) {
      vacQuery = vacQuery.ilike("urgency_level", filters.urgency);
    }
    if (filters.dateFrom || filters.vacantFrom) {
      vacQuery = vacQuery.gte("vacant_date", (filters.dateFrom || filters.vacantFrom)!);
    }
    if (filters.dateTo || filters.vacantTo) {
      vacQuery = vacQuery.lte("vacant_date", (filters.dateTo || filters.vacantTo)!);
    }

    const [vacRes, groupMap] = await Promise.all([
      vacQuery,
      fetchGroupMap(supabase),
    ]);

    const vacMap = new Map(
      (vacRes.data ?? [])
        .filter((v) => {
          const st = (v.status || "").toLowerCase().trim();
          return st !== "filled" && st !== "closed" && st !== "archived";
        })
        .map((v) => [v.vcode, v]),
    );
    const validCandidates = activeCandidates.filter((c) => vacMap.has(asString(c.vacancy_vcode)));

    const rows = validCandidates.map((c: Record<string, unknown>) => {
      const vcode = asString(c.vacancy_vcode) ?? "Uncoded";
      const vac = vacMap.get(vcode) as Record<string, unknown> | undefined;
      const lName = asString(c.last_name);
      const fName = asString(c.first_name);
      const mName = asString(c.middle_name);
      const fFull = asString(c.full_name);
      const candidateName = formatPersonName(fName, lName, mName, fFull || "Candidate");
      const position = asString(vac?.position) ?? "—";
      const loc = [asString(vac?.area_city), asString(vac?.province)].filter(Boolean).join(" • ") || "";
      let storeName = asString(vac?.store_name ?? vac?.store_branch);
      const account = asString(vac?.account);
      if (
        !storeName &&
        (vcode.includes("GHQ") ||
          account?.toLowerCase() === "moses hq" ||
          vac?.source === "pool" ||
          asBoolean(vac?.is_pool_vacancy))
      ) {
        storeName = "Moses HQ";
      }

      const stageBadge = asString(c.status) || "In Pipeline";
      const vDateStr = asString(vac?.vacant_date ?? vac?.created_at ?? c.created_at);
      let agingDays: number | null = null;
      if (vDateStr) {
        const vDate = new Date(vDateStr);
        if (!isNaN(vDate.getTime())) {
          const diffMs = Date.now() - vDate.getTime();
          agingDays = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
        }
      }

      const rawGroupName = vac?.group_id ? groupMap.get(asString(vac.group_id)!) : null;
      const groupName = formatGroupName(rawGroupName, account) || "";

      return {
        vcode,
        positionTitle: position,
        lifecycleStatus: "Pipeline",
        accountName: account || "",
        groupName,
        storeName: storeName || "",
        storeLocation: loc,
        hrcoName: asString(vac?.hrco_name) || "",
        agingDays: agingDays !== null ? String(agingDays) : "",
        urgencyLevel: asString(vac?.urgency_level) || "",
        createdDate: vDateStr ? (vDateStr.includes("T") ? vDateStr.split("T")[0] : vDateStr) : "",
        applicantName: candidateName,
        applicantContact: asString(c.contact_number) || "",
        pipelineStage: stageBadge,
      };
    });

    if (filters.search) {
      const q = filters.search.toLowerCase();
      return rows.filter(
        (r) =>
          r.vcode.toLowerCase().includes(q) ||
          r.positionTitle.toLowerCase().includes(q) ||
          r.accountName.toLowerCase().includes(q) ||
          r.storeName.toLowerCase().includes(q) ||
          (r.applicantName && r.applicantName.toLowerCase().includes(q)),
      );
    }

    return rows;
  } catch {
    return [];
  }
}

async function fetchAllHiredVacancies(
  filters: VacancyExportFilters,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  try {
    const { data: hiredData, error: hiredError } = await supabase.rpc("fn_get_hired_applicants");
    if (hiredError || !Array.isArray(hiredData)) {
      return [];
    }

    const hiredRows = hiredData.map((h: Record<string, unknown>, idx: number) => {
      const lName = asString(h.last_name);
      const fName = asString(h.first_name);
      const mName = asString(h.middle_name);
      const rawFull = asString(h.full_name);
      const workerName = formatPersonName(fName, lName, mName, rawFull || "Hired Worker");

      const hiredDate = asString(h.hired_date ?? h.hired_at);
      const position = asString(h.position_name ?? h.position);
      const vcode = asString(h.vacancy_vcode) ?? "Uncoded";
      const account = asString(h.account);
      const groupName = formatGroupName(asString(h.group_name), account);

      return {
        id: asString(h.id) ?? `hired-${idx}`,
        vcode,
        accountId: null as string | null,
        accountName: account,
        groupId: null as string | null,
        groupName,
        storeId: null as string | null,
        storeName: null as string | null,
        storeLocation: null as string | null,
        position_title: position,
        vacantDate: null as string | null,
        hiredDate,
        daysToFill: null as number | null,
        agingDays: null as number | null,
        urgencyLevel: null as string | null,
        hrcoName: asString(h.hired_by) ?? "HR Team",
        applicantName: workerName,
      };
    });

    // Enrich store info for hired rows if vcodes exist
    const hiredVcodes = Array.from(new Set(hiredRows.map((r) => r.vcode).filter(Boolean)));
    if (hiredVcodes.length > 0) {
      try {
        const { data: vacsData } = await supabase
          .from("vacancies")
          .select("vcode, store_name, store_branch, area_city, province, store_id, account_id, group_id, account, vacant_date, created_at")
          .in("vcode", hiredVcodes)
          .is("deleted_at", null);

        if (vacsData && vacsData.length > 0) {
          const vacMap = new Map(vacsData.map((v) => [v.vcode, v]));
          for (const row of hiredRows) {
            if (vacMap.has(row.vcode)) {
              const v = vacMap.get(row.vcode)!;
              row.storeName = v.store_name || v.store_branch || null;
              row.vacantDate = v.vacant_date || v.created_at?.substring(0, 10) || null;
              row.daysToFill = calculateDaysToFill(row.vacantDate, row.hiredDate);
              row.accountId = v.account_id || row.accountId;
              row.groupId = v.group_id || row.groupId;
              row.storeId = v.store_id || row.storeId;
              row.accountName = row.accountName || v.account || null;
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
    if (filters.accountId) {
      filteredHired = filteredHired.filter((r) => r.accountId === filters.accountId);
    }
    if (filters.groupId) {
      filteredHired = filteredHired.filter((r) => r.groupId === filters.groupId);
    }
    if (filters.search) {
      const q = filters.search.toLowerCase();
      filteredHired = filteredHired.filter(
        (r) =>
          r.vcode.toLowerCase().includes(q) ||
          (r.applicantName && r.applicantName.toLowerCase().includes(q)) ||
          (r.position_title && r.position_title.toLowerCase().includes(q)) ||
          (r.storeName && r.storeName.toLowerCase().includes(q)) ||
          (r.accountName && r.accountName.toLowerCase().includes(q)),
      );
    }

    const dFrom = filters.dateFrom || filters.vacantFrom;
    if (dFrom) {
      filteredHired = filteredHired.filter((r) => !r.vacantDate || r.vacantDate >= dFrom);
    }
    const dTo = filters.dateTo || filters.vacantTo;
    if (dTo) {
      filteredHired = filteredHired.filter((r) => !r.vacantDate || r.vacantDate <= dTo);
    }

    return filteredHired.map((item) => {
      const createdDateStr = item.vacantDate
        ? item.vacantDate.includes("T")
          ? item.vacantDate.split("T")[0]
          : item.vacantDate
        : "";

      return {
        vcode: item.vcode || "",
        positionTitle: item.position_title || "",
        lifecycleStatus: "Hired",
        accountName: item.accountName || "",
        groupName: item.groupName || "",
        storeName: item.storeName || "",
        storeLocation: item.storeLocation || "",
        hrcoName: item.hrcoName || "",
        agingDays:
          item.daysToFill !== null && item.daysToFill !== undefined
            ? `${item.daysToFill} days`
            : "",
        urgencyLevel: item.urgencyLevel || "",
        createdDate: createdDateStr,
      };
    });
  } catch {
    return [];
  }
}

async function fetchAllClosureVacancies(
  filters: VacancyExportFilters,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  try {
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
        updated_at,
        hrco_name,
        urgency_level
      `)
      .eq("is_archived", false)
      .is("deleted_at", null);

    if (filters.accountId) {
      vacQuery = vacQuery.eq("account_id", filters.accountId);
    }
    if (filters.groupId) {
      vacQuery = vacQuery.eq("group_id", filters.groupId);
    }

    const [vacRes, groupMap] = await Promise.all([
      vacQuery,
      fetchGroupMap(supabase),
    ]);
    const activeVacs = vacRes.data;
    const vacError = vacRes.error;

    if (vacError || !Array.isArray(activeVacs)) {
      return [];
    }

    const closureVacs = activeVacs.filter((vac: Record<string, unknown>) => {
      const vcode = asString(vac.vcode);
      const statusLower = (asString(vac.status) || "").toLowerCase().trim();
      const closureReqStatusLower = (asString(vac.closure_request_status) || "").toLowerCase().trim();
      const isClosureStatus = statusLower === "closure" || statusLower === "for_closure";
      const hasPendingFlag = asBoolean(vac.has_pending_closure) || closureReqStatusLower === "pending";
      const hasPendingRequest = vcode ? requestMap.has(vcode) : false;

      return isClosureStatus || hasPendingFlag || hasPendingRequest;
    });

    const closureRows = closureVacs.map((vac: Record<string, unknown>, idx: number) => {
      const vcode = asString(vac.vcode) ?? "Uncoded";
      const cr = requestMap.get(vcode);
      const storeName = asString(vac.store_name ?? vac.store_branch);
      const position = asString(vac.position) ?? "—";
      const account = asString(vac.account);
      const rawGroupName = vac.group_id ? groupMap.get(asString(vac.group_id)!) : null;
      const groupName = formatGroupName(rawGroupName, account) || null;
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
        asString(vac.updated_at) ??
        asString(vac.created_at);

      return {
        id: asString(vac.id) ?? asString(cr?.id) ?? `closure-${idx}`,
        vcode,
        accountId: asString(vac.account_id),
        accountName: account,
        groupId: asString(vac.group_id),
        groupName,
        storeName,
        storeLocation: loc,
        position_title: position,
        vacantDate: closureRequestedAt,
        urgencyLevel: asString(vac.urgency_level),
        hrcoName: asString(vac.hrco_name) ?? "—",
        closureReason,
        closureRequestedBy,
      };
    });

    let filteredClosure = closureRows;
    if (filters.search) {
      const q = filters.search.toLowerCase();
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

    const dFrom = filters.dateFrom || filters.vacantFrom;
    if (dFrom) {
      filteredClosure = filteredClosure.filter((r) => !r.vacantDate || r.vacantDate >= dFrom);
    }
    const dTo = filters.dateTo || filters.vacantTo;
    if (dTo) {
      filteredClosure = filteredClosure.filter((r) => !r.vacantDate || r.vacantDate <= dTo);
    }

    return filteredClosure.map((item) => {
      const createdDateStr = item.vacantDate
        ? item.vacantDate.includes("T")
          ? item.vacantDate.split("T")[0]
          : item.vacantDate
        : "";

      return {
        vcode: item.vcode || "",
        positionTitle: item.position_title || "",
        lifecycleStatus: "Closure",
        accountName: item.accountName || "",
        groupName: item.groupName || "",
        storeName: item.storeName || "",
        storeLocation: item.storeLocation || "",
        hrcoName: item.hrcoName || "",
        agingDays: "",
        urgencyLevel: item.urgencyLevel || "",
        createdDate: createdDateStr,
      };
    });
  } catch {
    return [];
  }
}

async function fetchAllFailedVacancies(
  filters: VacancyExportFilters,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
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
      .in("status", [
        "Backout", "backout",
        "Rejected", "rejected",
        "Failed", "failed",
        "Did Not Report", "did not report",
        "Rejected by Ops", "rejected by ops",
      ])
      .order("created_at", { ascending: false });

    if (dropoutsError || !Array.isArray(dropoutsData) || dropoutsData.length === 0) {
      return [];
    }

    const dropoutVcodes = Array.from(new Set(dropoutsData.map((d) => d.vacancy_vcode).filter(Boolean)));
    let vacQuery = supabase
      .from("vacancies")
      .select("id, vcode, store_name, store_branch, store_id, position, account, account_id, group_id, area_city, province, hrco_name, vacant_date, target_fill_date, urgency_level, is_archived, deleted_at")
      .in("vcode", dropoutVcodes)
      .is("deleted_at", null);

    if (filters.accountId) {
      vacQuery = vacQuery.eq("account_id", filters.accountId);
    }
    if (filters.groupId) {
      vacQuery = vacQuery.eq("group_id", filters.groupId);
    }

    const [vacsRes, groupMap] = await Promise.all([
      vacQuery,
      fetchGroupMap(supabase),
    ]);
    const vacsData = vacsRes.data;
    const vacMap = new Map((vacsData ?? []).map((v) => [v.vcode, v]));

    const validDropouts = dropoutsData.filter((d) => vacMap.has(d.vacancy_vcode));

    const failedRows = validDropouts.map((d: Record<string, unknown>, idx: number) => {
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
      const rawGroupName = vac?.group_id ? groupMap.get(asString(vac.group_id)!) : null;

      return {
        id: asString(vac?.id) ?? asString(d.id) ?? `failed-${idx}`,
        vcode,
        accountId: asString(vac?.account_id),
        accountName: asString(vac?.account),
        groupId: asString(vac?.group_id),
        groupName: formatGroupName(rawGroupName, asString(vac?.account)) || null,
        storeName,
        storeLocation: loc,
        position_title: position,
        vacantDate: asString(vac?.vacant_date) || dropoutDate,
        urgencyLevel: asString(vac?.urgency_level),
        hrcoName: asString(vac?.hrco_name) ?? "—",
        applicantName: candidateName,
        dropoutReason,
      };
    });

    let filteredFailed = failedRows;
    if (filters.search) {
      const q = filters.search.toLowerCase();
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

    const dFrom = filters.dateFrom || filters.vacantFrom;
    if (dFrom) {
      filteredFailed = filteredFailed.filter((r) => !r.vacantDate || r.vacantDate >= dFrom);
    }
    const dTo = filters.dateTo || filters.vacantTo;
    if (dTo) {
      filteredFailed = filteredFailed.filter((r) => !r.vacantDate || r.vacantDate <= dTo);
    }

    return filteredFailed.map((item) => {
      const createdDateStr = item.vacantDate
        ? item.vacantDate.includes("T")
          ? item.vacantDate.split("T")[0]
          : item.vacantDate
        : "";

      return {
        vcode: item.vcode || "",
        positionTitle: item.position_title || "",
        lifecycleStatus: "Failed / Backout",
        accountName: item.accountName || "",
        groupName: item.groupName || "",
        storeName: item.storeName || "",
        storeLocation: item.storeLocation || "",
        hrcoName: item.hrcoName || "",
        agingDays: "",
        urgencyLevel: item.urgencyLevel || "",
        createdDate: createdDateStr,
      };
    });
  } catch {
    return [];
  }
}

/**
 * Unpaginated full-dataset Vacancy Export query.
 * Pulls matched records without UI pagination truncation.
 */
export async function fetchVacanciesForExport(
  scope: "current_tab" | "all_statuses",
  currentTab: string,
  filters: VacancyExportFilters = {},
): Promise<VacancyExportResult> {
  const scopeTitle = getVacancyExportScopeTitle(scope, currentTab);
  const timestamp = getVacancyExportTimestamp();
  const filename = `OHMployee_Vacancies_${scopeTitle}_${timestamp}.csv`;

  let exportRows: VacancyExportRowData[] = [];

  if (scope === "all_statuses") {
    const [openRows, pipelineRows, hiredRows, closureRows, failedRows] = await Promise.all([
      fetchAllRpcVacancies("Open", filters, "Open"),
      fetchAllPipelineVacancies(filters),
      fetchAllHiredVacancies(filters),
      fetchAllClosureVacancies(filters),
      fetchAllFailedVacancies(filters),
    ]);

    exportRows = [
      ...openRows,
      ...pipelineRows,
      ...hiredRows,
      ...closureRows,
      ...failedRows,
    ];
  } else {
    const normalizedTab = currentTab.toLowerCase().trim();
    switch (normalizedTab) {
      case "open":
        exportRows = await fetchAllRpcVacancies("Open", filters, "Open");
        break;
      case "pipeline":
      case "with_applicant":
        exportRows = await fetchAllPipelineVacancies(filters);
        break;
      case "hired":
        exportRows = await fetchAllHiredVacancies(filters);
        break;
      case "closure":
        exportRows = await fetchAllClosureVacancies(filters);
        break;
      case "failed_backout":
      case "failed / backout":
      case "failed-backout":
        exportRows = await fetchAllFailedVacancies(filters);
        break;
      default:
        exportRows = await fetchAllRpcVacancies(tabToRpcStatus(normalizedTab as VacancyStatus), filters, "Open");
        break;
    }
  }

  const csv = buildVacancyExportCsv(exportRows);

  return {
    csv,
    rowCount: exportRows.length,
    filename,
    scopeTitle,
  };
}

/**
 * Triggers a direct browser download of generated CSV content with proper UTF-8 BOM.
 */
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


