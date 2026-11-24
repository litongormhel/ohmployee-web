import { createClient } from "@/lib/supabase/client";
import { formatPersonName, parseCandidateFullName } from "@/lib/utils/formatName";
import { useQuery } from "@tanstack/react-query";
import {
  type AssignedStoreDetail,
  type VacancyListItem,
  type ActiveApplicantItem,
  type ActivityHistoryItem,
  type VacancyDetailItem,
  type VacancyListParams,
  type VacancySummary,
  type VacancyRpcRow,
  type OccupiedStoreIdentifiers,
  type VacancyRequirementItem,
  VacancyDataError,
} from "./types";
import {
  MAX_PAGE_SIZE,
  asObject,
  asString,
  asTrimmedString,
  asDateFilter,
  asUuidFilter,
  asNumber,
  asBoolean,
  asCount,
  normalizeCapabilities,
  normalizeAgingBucket,
  normalizeUrgency,
  normalizeSortField,
  normalizeSortDirection,
  getTotalCount,
  throwVacancyError,
  calculateDaysToFill,
  formatGroupName,
  tabToRpcStatus,
  fetchGroupMap,
} from "./vacancyHelpers";

export function normalizeListRow(row: VacancyRpcRow): VacancyListItem | null {
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
  const hrProcessingCount =
    asNumber(row.hr_processing_count ?? rowCaps.hr_processing_count) ?? 0;

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
    activeApplicantCount: asCount(row.active_applicant_count ?? rowCaps.active_applicant_count),
    confirmedOnboardCount: asCount(row.confirmed_onboard_count ?? rowCaps.confirmed_onboard_count) || hcFilled,
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
    remarks: asString(row.remarks ?? row.hrco_remarks ?? row.notes),
    opsRemarks: asString(row.ops_remarks ?? row.opsRemarks),
    recruitmentRemarks: asString(row.recruitment_remarks ?? row.recruitmentRemarks),
    hrRemarks: asString(row.hr_remarks ?? row.hrRemarks),
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
    hrProcessingCount,
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
    activeApplicantCount:
      asCount(row.active_applicant_count ?? rowCaps.active_applicant_count) ||
      activeApplicantsList.filter((a) => (a.statusLabel || "").toLowerCase() !== "confirmed onboard").length,
    confirmedOnboardCount:
      asCount(row.confirmed_onboard_count ?? rowCaps.confirmed_onboard_count) ||
      activeApplicantsList.filter((a) => (a.statusLabel || "").toLowerCase() === "confirmed onboard").length ||
      hcFilled,
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

  // Authoritative Database Summary RPC (KISS - Database Computes, UI Renders)
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
        .select("vacancy_vcode")
        .ilike("status", "pending");

      const pendingVcodes = new Set(
        (rawRequests ?? []).map((r) => r.vacancy_vcode).filter(Boolean),
      );

      // 2. Query active vacancies using PostgREST exact head count
      let vacQuery = supabase
        .from("vacancies")
        .select("id", { count: "exact", head: true })
        .eq("is_archived", false)
        .is("deleted_at", null);

      if (params.accountId) {
        vacQuery = vacQuery.eq("account_id", params.accountId);
      }
      if (params.groupId) {
        vacQuery = vacQuery.eq("group_id", params.groupId);
      }

      const orConditions = [
        "status.in.(closure,for_closure,Closure,For Closure)",
        "has_pending_closure.eq.true",
        "closure_request_status.ilike.pending",
      ];
      if (pendingVcodes.size > 0) {
        orConditions.push(`vcode.in.(${Array.from(pendingVcodes).join(",")})`);
      }
      vacQuery = vacQuery.or(orConditions.join(","));

      const { count, error } = await vacQuery;
      if (error) {
        return pendingVcodes.size;
      }
      return count ?? 0;
    } catch {
      return 0;
    }
  })();

  const [summaryRes, hiredCountResult, closureCountResult] = await Promise.allSettled([
    summaryPromise,
    hiredPromise,
    closurePromise,
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

  const openCount = baseSummary.open;
  const pipelineCount = baseSummary.pipeline;
  const failedCount = baseSummary.failedBackout;

  return {
    ...baseSummary,
    open: openCount,
    pipeline: pipelineCount,
    with_applicant: pipelineCount,
    hired: hiredCount,
    closure: closureCount,
    failedBackout: failedCount,
    total: openCount + pipelineCount + hiredCount + closureCount + failedCount,
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
          recruitment_remarks,
          ops_remarks,
          remarks,
          created_at,
          updated_at,
          profile_edit_count,
          is_archived,
          recruited_by_name,
          recruited_by_user_id,
          vacancy_requirement_id
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
          .from("vw_vacancy_list")
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
            hc_total,
            has_pending_closure,
            closure_request_status,
            employment_type,
            source,
            is_pool_vacancy
          `)
          .in("vcode", vcodes)
          .eq("is_archived", false);

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

        const candidateReqIds = Array.from(
          new Set(validCandidates.map((c) => asString(c.vacancy_requirement_id)).filter(Boolean)),
        ) as string[];

        const candidatePositionMap = new Map<string, string>();
        if (candidateReqIds.length > 0) {
          try {
            const { data: vrRows, error: vrError } = await supabase
              .from("vacancy_requirements")
              .select("id, position_id")
              .in("id", candidateReqIds);
            if (!vrError && Array.isArray(vrRows)) {
              const posIds = Array.from(new Set(vrRows.map((r) => asString(r.position_id)).filter(Boolean))) as string[];
              if (posIds.length > 0) {
                const { data: posRows } = await supabase
                  .from("positions")
                  .select("id, position_name")
                  .in("id", posIds);
                const posNameMap = new Map<string, string>();
                (posRows || []).forEach((p) => {
                  if (p.id && p.position_name) posNameMap.set(String(p.id), String(p.position_name));
                });
                vrRows.forEach((r) => {
                  const pName = posNameMap.get(asString(r.position_id) || "");
                  if (r.id && pName) candidatePositionMap.set(String(r.id), pName);
                });
              }
            }
          } catch (e) {
            console.error("[PostgREST Schema Error] pipeline candidates position resolution:", e);
          }
        }

        const pipelineRows: VacancyListItem[] = validCandidates.map((c: Record<string, unknown>, idx: number) => {
          const vcode = asString(c.vacancy_vcode) ?? "Uncoded";
          const vac = vacMap.get(vcode) as Record<string, unknown> | undefined;
          const lName = asString(c.last_name);
          const fName = asString(c.first_name);
          const mName = asString(c.middle_name);
          const fFull = asString(c.full_name);
          const candidateName = formatPersonName(fName, lName, mName, fFull || "Candidate");
          const candReqId = asString(c.vacancy_requirement_id);
          const resolvedPosition = candReqId ? candidatePositionMap.get(candReqId) : null;
          const position = resolvedPosition ?? asString(vac?.position) ?? "—";
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
            hrcoName: asString(vac?.hrco_name) || null,
            applicantId: asString(c.id),
            applicantName: candidateName,
            applicantFirstName: fName,
            applicantLastName: lName,
            applicantMiddleName: mName,
            contactNumber: asString(c.contact_number),
            recruiterName: asString(c.recruited_by_name) || null,
            recruiterId: asString(c.recruited_by_user_id) || null,
            endorsedByName: asString(c.recruited_by_name) || null,
            hiredDate: null,
            stageBadge,
            vacancyRequirementId: candReqId || null,
            remarks: asString(c.ops_remarks ?? c.recruitment_remarks ?? c.remarks) || null,
            opsRemarks: asString(c.ops_remarks) || null,
            recruitmentRemarks: asString(c.recruitment_remarks) || null,
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
            hrcoName: null,
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
              .from("vw_vacancy_list")
              .select("vcode, store_name, store_branch, area_city, province, store_id, account_id, group_id, account, vacant_date, created_at, employment_type, hrco_name")
              .in("vcode", hiredVcodes);

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
                  row.hrcoName = asString(v.hrco_name) || null;
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
        .from("vw_vacancy_list")
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
          has_pending_closure,
          closure_request_status,
          status,
          created_at,
          updated_at,
          hrco_name,
          source,
          is_pool_vacancy
        `)
        .eq("is_archived", false);

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
            hrcoName: asString(vac.hrco_name) || null,
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
          .from("vw_vacancy_list")
          .select("id, vcode, store_name, store_branch, store_id, position, account, account_id, group_id, area_city, province, hrco_name, vacant_date, created_at, target_fill_date, urgency_level, is_archived, hc_total, source, is_pool_vacancy")
          .in("vcode", dropoutVcodes);

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
            hrcoName: asString(vac?.hrco_name) || null,
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

  // Enrich applicant details based on active applicants, HR Emploc onboarding state, and Plantilla occupancy:
  const allVcodes = Array.from(new Set(rows.map((r) => r.vcode).filter(Boolean)));
  const activeByVcode = new Map<string, Array<Record<string, unknown>>>();
  const emplocsByVcode = new Map<string, Array<Record<string, unknown>>>();
  const occupiedVcodeCountMap = new Map<string, number>();

  if (allVcodes.length > 0) {
    try {
      const [applicantsRes, emplocRes, plantillaRes, slotsRes] = await Promise.all([
        supabase
          .from("applicants")
          .select("id, vacancy_vcode, first_name, last_name, middle_name, full_name, contact_number, status, hired_date, backout_reason, backout_date, recruitment_remarks, ops_remarks, remarks, created_at, updated_at")
          .in("vacancy_vcode", allVcodes)
          .eq("is_archived", false)
          .order("created_at", { ascending: false }),
        supabase
          .from("hr_emploc")
          .select("id, vcode, applicant_id, applicant_name, status, hr_status, hired_date, employee_no, ops_remarks, hr_remarks, employee_lookup_remarks, correction_reason, created_at, updated_at, slot_id, position")
          .in("vcode", allVcodes)
          .is("deleted_at", null)
          .order("created_at", { ascending: false }),
        supabase
          .from("plantilla")
          .select("id, vcode, store_id, status, is_deleted, date_of_separation, deactivated_at")
          .in("vcode", allVcodes)
          .eq("status", "Active")
          .is("date_of_separation", null)
          .is("deactivated_at", null)
          .or("is_deleted.is.null,is_deleted.eq.false"),
        supabase
          .from("plantilla_slots")
          .select("id, legacy_vcode, store_id, position, slot_ordinal, slot_status, current_occupant_plantilla_id")
          .in("legacy_vcode", allVcodes)
          .in("slot_status", ["open", "pipeline", "hr_processing", "occupied"])
          .order("slot_ordinal", { ascending: true }),
      ]);

      const applicantsData = applicantsRes.data;
      const emplocData = emplocRes.data;
      const plantillaData = plantillaRes.data;
      const slotsData = slotsRes.data;

      // 0. Index physical slots by VCode
      const slotsByVcode = new Map<string, Array<{ slotId: string; slotOrdinal: number; position: string; slotStatus: string }>>();
      if (slotsData && Array.isArray(slotsData)) {
        for (const slot of slotsData) {
          const vk = (asString(slot.legacy_vcode) || "").trim().toUpperCase();
          if (vk) {
            if (!slotsByVcode.has(vk)) slotsByVcode.set(vk, []);
            slotsByVcode.get(vk)!.push({
              slotId: asString(slot.id) || "",
              slotOrdinal: asNumber(slot.slot_ordinal) ?? 1,
              position: asString(slot.position) || "",
              slotStatus: asString(slot.slot_status) || "open",
            });
          }
        }
      }

      // 1. Tally active Plantilla occupants per VCode
      if (plantillaData && Array.isArray(plantillaData)) {
        for (const pl of plantillaData) {
          const vk = (asString(pl.vcode) || "").trim().toUpperCase();
          if (vk) {
            occupiedVcodeCountMap.set(vk, (occupiedVcodeCountMap.get(vk) ?? 0) + 1);
          }
        }
      }

      // 2. Index active HR Emploc onboarding records by VCode and track deployed candidate IDs
      const deployedCandidateIds = new Set<string>();
      const deployedCandidateNames = new Set<string>();
      if (emplocData && Array.isArray(emplocData)) {
        for (const emp of emplocData) {
          const empStatus = asString(emp.status);
          const candId = asString(emp.applicant_id);
          const rawName = asString(emp.applicant_name);
          if (empStatus === "Moved to Plantilla") {
            if (candId) deployedCandidateIds.add(candId);
            if (rawName) deployedCandidateNames.add(rawName.toLowerCase().trim());
            continue;
          }

          const vk = (asString(emp.vcode) || "").trim().toUpperCase();
          if (vk) {
            if (!emplocsByVcode.has(vk)) emplocsByVcode.set(vk, []);
            emplocsByVcode.get(vk)!.push(emp as Record<string, unknown>);
          }
        }
      }

      // 3. Index active applicants by VCode (excluding deployed / moved-to-plantilla candidates)
      if (applicantsData && Array.isArray(applicantsData)) {
        for (const app of applicantsData) {
          const vcode = (asString(app.vacancy_vcode) || "").trim().toUpperCase();
          if (!vcode) continue;
          const actId = asString(app.id) || "";
          const actFullName = asString(app.full_name) || "";
          if (actId && deployedCandidateIds.has(actId)) continue;
          if (actFullName && deployedCandidateNames.has(actFullName.toLowerCase().trim())) continue;

          const status = (app.status || "").toLowerCase().trim();
          const isNonPipeline =
            status === "backout" ||
            status === "rejected" ||
            status === "failed" ||
            status === "did not report" ||
            status === "rejected by ops" ||
            status === "withdrew";

          if (!isNonPipeline) {
            if (!activeByVcode.has(vcode)) activeByVcode.set(vcode, []);
            activeByVcode.get(vcode)!.push(app);
          }
        }
      }

      for (const row of rows) {
        const isClosure =
          row.hasPendingClosure === true ||
          (row.closureRequestStatus || "").toLowerCase() === "pending" ||
          (row.pipelineStatus || "").toLowerCase().includes("closure");

        const vcodeKey = (row.vcode || "").trim().toUpperCase();
        const emplocs = emplocsByVcode.get(vcodeKey) ?? [];
        const actives = activeByVcode.get(vcodeKey) ?? [];
        const slotsForVcode = slotsByVcode.get(vcodeKey) ?? [];

        // Build composite candidate list for this VCode preserving both HR Emploc and recruitment candidates
        const allCandidatesForVcode: ActiveApplicantItem[] = [];
        const seenCandidateIds = new Set<string>();
        const seenCandidateNames = new Set<string>();

        // 1. Emploc onboarding candidates
        for (const emp of emplocs) {
          const candId = asString(emp.applicant_id) || asString(emp.id) || "";
          const rawName = asString(emp.applicant_name) || "Onboarding Candidate";
          const parsed = parseCandidateFullName(rawName);
          const fName = parsed.firstName || null;
          const lName = parsed.lastName || null;
          const mName = parsed.middleName || null;
          const formattedName = formatPersonName(fName, lName, mName, rawName);

          const hrSt = (asString(emp.hr_status) || "").toLowerCase().trim();
          const st = (asString(emp.status) || "").toLowerCase().trim();
          let stageBadge = "HR Emploc - Pending";
          if (hrSt.includes("correction") || st.includes("correction")) {
            stageBadge = "HR Emploc - Correction";
          } else if (hrSt.includes("review") || st.includes("review")) {
            stageBadge = "HR Emploc - Review";
          } else if (hrSt.includes("for emploc") || st.includes("for emploc") || st === "for emploc" || hrSt === "for emploc") {
            stageBadge = "HR Emploc - For Emploc";
          } else if (hrSt.includes("complete") || hrSt.includes("ready") || st.includes("ready")) {
            stageBadge = "HR Emploc - Ready";
          }

          const hrRem = asString(emp.hr_remarks)?.trim() || null;
          const opsRem = asString(emp.ops_remarks)?.trim() || null;
          let issueRem: string | null = null;
          if (emp.correction_reason) {
            const cr = emp.correction_reason;
            if (Array.isArray(cr) && cr.length > 0) {
              const first = asObject(cr[0]);
              issueRem = asString(first.comment ?? first.label ?? first.code)?.trim() || null;
            } else if (typeof cr === "object" && cr !== null) {
              const crObj = asObject(cr);
              issueRem = asString(crObj.comment ?? crObj.reason ?? crObj.label)?.trim() || null;
            }
          }
          const lookupRem = asString(emp.employee_lookup_remarks)?.trim() || null;
          const latestEmplocRemarks = hrRem || issueRem || opsRem || lookupRem || null;

          if (candId) seenCandidateIds.add(candId);
          seenCandidateNames.add(formattedName.toLowerCase());

          const slotId = asString(emp.slot_id);
          const matchedSlot = slotId ? slotsForVcode.find((s) => s.slotId === slotId) : null;
          const pos = asString(emp.position) || matchedSlot?.position || null;

          allCandidatesForVcode.push({
            applicantId: candId,
            displayName: formattedName,
            firstName: fName,
            lastName: lName,
            middleName: mName,
            contactNumber: null,
            statusLabel: stageBadge,
            onboardDate: asString(emp.hired_date),
            updatedAt: asString(emp.updated_at ?? emp.created_at),
            recruiterName: null,
            deployedByName: null,
            remarks: latestEmplocRemarks,
            slotId,
            slotOrdinal: matchedSlot?.slotOrdinal ?? null,
            position: pos,
          });
        }

        // 2. Active recruitment pipeline candidates (not yet in emploc)
        for (const act of actives) {
          const actId = asString(act.id) || "";
          let lName = asString(act.last_name);
          let fName = asString(act.first_name);
          let mName = asString(act.middle_name);
          const fFull = asString(act.full_name);
          if ((!lName || !fName) && fFull) {
            const parsed = parseCandidateFullName(fFull, { firstName: fName, lastName: lName, middleName: mName });
            lName = lName || parsed.lastName || null;
            fName = fName || parsed.firstName || null;
            mName = mName || parsed.middleName || null;
          }
          const formattedName = formatPersonName(fName, lName, mName, fFull || "Candidate");

          if (actId && seenCandidateIds.has(actId)) continue;
          if (seenCandidateNames.has(formattedName.toLowerCase())) continue;

          if (actId) seenCandidateIds.add(actId);
          seenCandidateNames.add(formattedName.toLowerCase());

          const appSt = (asString(act.status) || "").toLowerCase().trim();
          const stageBadge = (appSt.includes("onboard") || appSt.includes("emploc"))
            ? "HR Emploc - Pending"
            : "Vacancy - Pipeline";

          const appOpsRem = asString(act.ops_remarks)?.trim() || null;
          const appRecRem = asString(act.recruitment_remarks)?.trim() || null;
          const appRem = asString(act.remarks)?.trim() || null;
          const latestAppRemarks = appOpsRem || appRecRem || appRem || null;

          allCandidatesForVcode.push({
            applicantId: actId,
            displayName: formattedName,
            firstName: fName,
            lastName: lName,
            middleName: mName,
            contactNumber: asString(act.contact_number),
            statusLabel: stageBadge,
            onboardDate: asString(act.hired_date),
            updatedAt: asString(act.updated_at ?? act.created_at),
            recruiterName: null,
            deployedByName: null,
            remarks: latestAppRemarks,
          });
        }

        // Attach candidate lists and counts
        row.slotsList = slotsForVcode;
        row.activeApplicantsList = allCandidatesForVcode;
        row.activeApplicantCount = allCandidatesForVcode.length;
        row.hrProcessingCount = emplocs.length;

        if (currentTab === "open") {
          // Open tab: Store requisition level, applicant fields cleared.
          row.applicantId = null;
          row.applicantName = null;
          row.contactNumber = null;
          row.stageBadge = isClosure ? "Vacancy - Closure" : "Vacancy - Open";
          row.pipelineStatus = isClosure ? "Vacancy - Closure" : "Vacancy - Open";
        } else {
          if (isClosure) {
            row.stageBadge = "Vacancy - Closure";
            row.pipelineStatus = "Vacancy - Closure";
            continue;
          }

          if (allCandidatesForVcode.length > 0) {
            const primary = allCandidatesForVcode[0];
            row.applicantId = primary.applicantId;
            row.applicantName = primary.displayName;
            row.applicantFirstName = primary.firstName;
            row.applicantLastName = primary.lastName;
            row.applicantMiddleName = primary.middleName;
            row.contactNumber = row.contactNumber || primary.contactNumber;
            row.hiredDate = row.hiredDate || primary.onboardDate;
            row.stageBadge = primary.statusLabel;
            row.pipelineStatus = primary.statusLabel;
            row.remarks = primary.remarks || row.remarks;
          } else {
            row.applicantId = null;
            row.applicantName = null;
            row.stageBadge = "Vacancy - Open";
            row.pipelineStatus = "Vacancy - Open";
          }
        }
      }
    } catch {
      // Graceful fallback if enrichment queries encounter issues
    }
  }

  // Enrich coverage group CGCode and assigned stores for multi-store / coverage group vacancies
  if (allVcodes.length > 0 || rows.some((r) => r.storeId)) {
    try {
      const explicitStoreIds = rows.map((r) => r.storeId).filter(Boolean) as string[];
      let matchedStoreIds: string[] = [];
      if (allVcodes.length > 0) {
        const { data: storeRows } = await supabase
          .from("stores")
          .select("id, vcode")
          .in("vcode", allVcodes);
        if (storeRows) {
          matchedStoreIds = storeRows.map((s) => s.id as string).filter(Boolean);
        }
      }
      const allTargetStoreIds = Array.from(new Set([...explicitStoreIds, ...matchedStoreIds]));

      if (allTargetStoreIds.length > 0) {
        const { data: cgsMatch } = await supabase
          .from("coverage_group_stores")
          .select("coverage_group_id, store_id")
          .in("store_id", allTargetStoreIds)
          .is("archived_at", null);

        if (cgsMatch && cgsMatch.length > 0) {
          const cgIds = Array.from(new Set(cgsMatch.map((c) => asString(c.coverage_group_id)).filter(Boolean) as string[]));

          const { data: allGroupStoresData } = await supabase
            .from("coverage_group_stores")
            .select(`
              coverage_group_id,
              store_id,
              is_anchor,
              hc_share,
              stores (id, store_name, vcode, area_city, area_province),
              coverage_groups (id, coverage_code, status, required_headcount)
            `)
            .in("coverage_group_id", cgIds)
            .is("archived_at", null);

          const { data: activeSlots } = await supabase
            .from("coverage_slots")
            .select("coverage_group_id, slot_status, current_occupant_plantilla_id")
            .in("coverage_group_id", cgIds)
            .eq("slot_status", "active")
            .not("current_occupant_plantilla_id", "is", null);

          const filledCgIds = new Set<string>();
          if (activeSlots) {
            for (const slot of activeSlots) {
              if (slot.coverage_group_id) filledCgIds.add(slot.coverage_group_id);
            }
          }

          type GroupStoreInfo = {
            cgId: string;
            cgCode: string;
            isFilled: boolean;
            requiredHc: number;
            anchorStoreName: string;
            anchorVcode: string;
            memberStoreIds: Set<string>;
            memberVcodes: Set<string>;
            storeNames: string[];
            storeDetails: AssignedStoreDetail[];
          };

          const cgMap = new Map<string, GroupStoreInfo>();
          const storeIdToCgId = new Map<string, string>();
          const vcodeToCgId = new Map<string, string>();

          if (allGroupStoresData) {
            const grouped = new Map<string, Array<Record<string, unknown>>>();
            for (const item of allGroupStoresData as Array<Record<string, unknown>>) {
              const cgId = asString(item.coverage_group_id);
              if (!cgId) continue;
              if (!grouped.has(cgId)) grouped.set(cgId, []);
              grouped.get(cgId)!.push(item);
            }

            for (const [cgId, items] of grouped.entries()) {
              const cgRaw = items[0]?.coverage_groups as unknown;
              const firstCg = Array.isArray(cgRaw) ? (cgRaw[0] as Record<string, unknown> | undefined) : (cgRaw as Record<string, unknown> | null);
              const cgCode = asString(firstCg?.coverage_code) || "";
              const cgStatus = (asString(firstCg?.status) || "").toLowerCase();
              const isFilled = cgStatus === "filled" || filledCgIds.has(cgId);
              const rawReq = asNumber(firstCg?.required_headcount);
              const requiredHc = rawReq != null && !isNaN(rawReq) && rawReq > 0 ? rawReq : 1;
              const count = items.length || 1;
              const defaultFraction = `1/${count}`;

              let anchorName = "";
              let anchorVk = "";
              const memberStoreIds = new Set<string>();
              const memberVcodes = new Set<string>();
              const storeNames: string[] = [];
              const storeDetails: AssignedStoreDetail[] = [];

              for (const item of items) {
                const sObj = (item.stores as unknown) as Record<string, unknown> | null;
                const sid = asString(item.store_id) || asString(sObj?.id) || "";
                const sname = asString(sObj?.store_name) || "";
                const svcode = asString(sObj?.vcode) || "";
                const isAnchor = asBoolean(item.is_anchor);
                const hcShare = asNumber(item.hc_share);
                const slotFraction = hcShare
                  ? hcShare === 0.5
                    ? "1/2"
                    : hcShare >= 0.33 && hcShare <= 0.34
                    ? "1/3"
                    : hcShare === 0.25
                    ? "1/4"
                    : defaultFraction
                  : defaultFraction;

                if (sid) memberStoreIds.add(sid);
                if (svcode) memberVcodes.add(svcode.toUpperCase());
                if (sname && !storeNames.includes(sname)) storeNames.push(sname);

                if (isAnchor || !anchorName) {
                  anchorName = sname;
                  anchorVk = svcode;
                }

                storeDetails.push({
                  storeId: sid || undefined,
                  storeName: sname,
                  vcode: svcode || null,
                  isAnchor,
                  slotFraction,
                });

                if (sid) storeIdToCgId.set(sid, cgId);
                if (svcode) vcodeToCgId.set(svcode.toUpperCase(), cgId);
              }

              cgMap.set(cgId, {
                cgId,
                cgCode,
                isFilled,
                requiredHc,
                anchorStoreName: anchorName,
                anchorVcode: anchorVk,
                memberStoreIds,
                memberVcodes,
                storeNames,
                storeDetails,
              });
            }
          }

          const shouldConsolidate = params.consolidateCoverageGroups !== false;
          const seenCgInVacancies = new Set<string>();
          const consolidatedRows: VacancyListItem[] = [];

          for (const row of rows) {
            const rowVk = (row.vcode || "").trim().toUpperCase();
            const rowCg = (row.cgCode || "").trim().toUpperCase();
            const isExplicitlyStationary =
              (row.employmentType || "").toLowerCase() === "stationary" ||
              (!row.cgCode && !rowVk.startsWith("CG-") && (row.employmentType || "").toLowerCase() !== "roving");

            let cgId: string | null = null;
            if (rowCg) {
              for (const [id, info] of cgMap.entries()) {
                if (info.cgCode.toUpperCase() === rowCg) {
                  cgId = id;
                  break;
                }
              }
            }
            if (!cgId && rowVk) {
              if (rowVk.startsWith("CG-")) {
                for (const [id, info] of cgMap.entries()) {
                  if (info.cgCode.toUpperCase() === rowVk) {
                    cgId = id;
                    break;
                  }
                }
              }
              if (!cgId && vcodeToCgId.has(rowVk)) {
                cgId = vcodeToCgId.get(rowVk) || null;
              }
            }

            // Only fallback to storeId matching if the vacancy is not explicitly stationary/backfill,
            // and is either designated as roving or belongs to an active coverage group with requiredHc > 0
            if (!cgId && !isExplicitlyStationary && row.storeId && storeIdToCgId.has(row.storeId)) {
              const candidateCgId = storeIdToCgId.get(row.storeId)!;
              const candidateInfo = cgMap.get(candidateCgId);
              const isRoving = (row.employmentType || "").toLowerCase().includes("roving");
              if (
                candidateInfo &&
                (isRoving || (candidateInfo.requiredHc > 0 && candidateInfo.anchorVcode?.toUpperCase() === rowVk))
              ) {
                cgId = candidateCgId;
              }
            }

            if (cgId && cgMap.has(cgId)) {
              const cgInfo = cgMap.get(cgId)!;
              if (cgInfo.isFilled) {
                // Member store covered by active employee -> fulfilled/suppressed
                continue;
              }

              const numStores = cgInfo.storeDetails.length || 1;
              const calcShare = Math.round((1.0 / numStores) * 100) / 100;

              if (shouldConsolidate) {
                // Vacancy Module (/vacancy): Merge multiple member stores into 1 row under CGCode
                if (seenCgInVacancies.has(cgId)) {
                  continue;
                }
                seenCgInVacancies.add(cgId);
                row.cgCode = cgInfo.cgCode;
                row.vcode = cgInfo.anchorVcode || row.vcode;
                row.storeName = cgInfo.anchorStoreName;
                row.employmentType = "Roving";
                row.assignedStores = cgInfo.storeNames;
                row.assignedStoreDetails = cgInfo.storeDetails;
                row.slotShare = calcShare;
                row.headcount = cgInfo.requiredHc;
                row.hcTotal = cgInfo.requiredHc;
                row.hcDisplay = `${row.confirmedOnboardCount ?? row.hcFilled ?? 0}/${cgInfo.requiredHc}`;
                consolidatedRows.push(row);
              } else {
                // Plantilla Vacancy tab (/plantilla): Keep 1:1 row per store, annotate roving slot = 0.5
                row.cgCode = cgInfo.cgCode;
                row.employmentType = "Roving";
                row.assignedStores = cgInfo.storeNames;
                row.assignedStoreDetails = cgInfo.storeDetails;
                row.slotShare = calcShare;
                consolidatedRows.push(row);
              }
            } else {
              consolidatedRows.push(row);
            }
          }

          rows.length = 0;
          rows.push(...consolidatedRows);
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Final Tab Scoping Enforcement:
  // For Open Tab: Trust the server tab result (ADR-001 Rule 4) and only guard against pending closure/closed/archived.
  let finalRows = rows;
  if (currentTab === "open") {
    finalRows = rows.filter((r) => {
      const isPendingClosure =
        r.hasPendingClosure === true ||
        (r.closureRequestStatus && r.closureRequestStatus.toLowerCase() === "pending") ||
        r.derivedStatus?.toLowerCase() === "for closure" ||
        r.derivedStatus?.toLowerCase() === "closure" ||
        r.vacancyStatus?.toLowerCase() === "for_closure" ||
        r.vacancyStatus?.toLowerCase() === "closure" ||
        r.vacancyStatus?.toLowerCase() === "closed" ||
        r.vacancyStatus?.toLowerCase() === "archived";
      return !isPendingClosure;
    });
    for (const r of finalRows) {
      r.applicantId = null;
      r.applicantName = null;
      r.contactNumber = null;
      r.stageBadge = "Vacancy - Open";
      r.pipelineStatus = "Vacancy - Open";
      r.dropoutReason = null;
      r.dropoutDate = null;
    }
  } else {
    // Exclude fully fulfilled / occupied vacancies from active vacancy list
    finalRows = rows.filter((r) => {
      const vcodeKey = (r.vcode || "").trim().toUpperCase();
      const occupiedCount = occupiedVcodeCountMap.get(vcodeKey) ?? 0;
      const hcTotal = r.hcTotal ?? r.headcount ?? 1;
      const isFullyOccupied = occupiedCount >= hcTotal && hcTotal > 0;
      const isFilled =
        r.vacancyStatus?.toLowerCase() === "filled" ||
        r.pipelineStatus?.toLowerCase() === "hired" ||
        r.derivedStatus?.toLowerCase() === "hired";
      return !isFullyOccupied && !isFilled;
    });
  }

  const effectiveTotal = Math.max(finalRows.length, getTotalCount(finalRows), getTotalCount(rows));
  for (const r of finalRows) {
    r.totalCount = effectiveTotal;
  }

  return {
    data: finalRows,
    totalCount: effectiveTotal,
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
    // Attempt fallback lookup for hired applicants or direct vacancy record
    // before throwing, so RPC schema or edge-case errors degrade gracefully.
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
              activityHistory: await (async () => {
                if (vacRow?.id) {
                  try {
                    const { data: tlData } = await supabase.rpc("get_vacancy_activity_timeline", {
                      p_vacancy_id: String(vacRow.id),
                    });
                    if (Array.isArray(tlData)) {
                      return tlData.map(normalizeActivityHistory);
                    }
                  } catch {
                    // fallback
                  }
                }
                return [
                  {
                    eventId: `hired-${asString(match.id) ?? vacancyId}`,
                    eventLabel: "Candidate Confirmed Onboard",
                    eventDescription: `${workerName} confirmed onboard for ${pos || asString(vacRow?.position) || "Position"} (${vcode}).`,
                    createdAt: hiredDate,
                    profileName: asString(match.hired_by) ?? "HR Team",
                  },
                ];
              })(),
            };
          }
        }

        // 2. Direct fallback for Filled / Closed / Archived vacancies (including dropouts and vacated plantilla slots)
        let vacRow: Record<string, unknown> | null = null;
        let targetVcode: string | null = null;
        let directPlantilla: Record<string, unknown> | null = null;

        // Check if vacancyId is an applicant id
        const { data: directApp } = await supabase
          .from("applicants")
          .select("*")
          .eq("id", vacancyId)
          .maybeSingle();

        if (directApp?.vacancy_vcode) {
          targetVcode = directApp.vacancy_vcode as string;
        }

        // Check if vacancyId is a plantilla id
        if (!targetVcode) {
          const { data: plData } = await supabase
            .from("plantilla")
            .select("*")
            .eq("id", vacancyId)
            .maybeSingle();
          if (plData) {
            directPlantilla = plData as Record<string, unknown>;
            if (plData.vcode) {
              targetVcode = plData.vcode as string;
            }
          }
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

        // Also check if vacancyId itself is a VCode in vacancies
        if (!vacRow && !targetVcode) {
          const { data: vDataByVcode } = await supabase
            .from("vacancies")
            .select("*")
            .eq("vcode", vacancyId)
            .is("deleted_at", null)
            .maybeSingle();
          if (vDataByVcode) {
            vacRow = vDataByVcode;
            targetVcode = vDataByVcode.vcode as string;
          }
        }

        // Or if vacancyId is a VCode in plantilla
        if (!vacRow && !targetVcode && !directPlantilla) {
          const { data: plByVcode } = await supabase
            .from("plantilla")
            .select("*")
            .eq("vcode", vacancyId)
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();
          if (plByVcode) {
            directPlantilla = plByVcode as Record<string, unknown>;
            targetVcode = (plByVcode.vcode as string) || vacancyId;
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
            activityHistory: await (async () => {
              if (vacRow?.id) {
                try {
                  const { data: tlData } = await supabase.rpc("get_vacancy_activity_timeline", {
                    p_vacancy_id: String(vacRow.id),
                  });
                  if (Array.isArray(tlData)) {
                    return tlData.map(normalizeActivityHistory);
                  }
                } catch {
                  // fallback
                }
              }
              return [
                {
                  eventId: `vac-init-${asString(vacRow.id) ?? vacancyId}`,
                  eventLabel: "Vacancy Requisition Created",
                  eventDescription: `Opened ${asString(vacRow.position) || "Position"} requisition for ${storeName || vcode} (${vcode} • ${reqHc} HC).`,
                  createdAt: asString(vacRow.created_at ?? vacRow.vacant_date),
                  profileName: asString(vacRow.hrco_name) ?? "System",
                },
              ];
            })(),
          };
        }

        // 3. Fallback for vacated Plantilla slots that do not have an explicit vacancies row
        if (!vacRow && (directPlantilla || targetVcode)) {
          const vcode = targetVcode ?? asString(directPlantilla?.vcode) ?? "Uncoded";
          const { data: allApps } = await supabase
            .from("applicants")
            .select("*")
            .eq("vacancy_vcode", vcode)
            .order("created_at", { ascending: false });

          const appsList = (allApps ?? []) as Array<Record<string, unknown>>;
          const primaryApp = directApp || appsList[0] || null;

          const areaCity = asString(directPlantilla?.area_city);
          const areaProvince = asString(directPlantilla?.area_province ?? directPlantilla?.province);
          const storeLocation = [areaCity, areaProvince].filter(Boolean).join(" • ") || null;
          const vacDate =
            asString(directPlantilla?.date_of_separation ?? directPlantilla?.deactivated_at ?? directPlantilla?.created_at) ||
            new Date().toISOString().substring(0, 10);

          const lName = asString(primaryApp?.last_name);
          const fName = asString(primaryApp?.first_name);
          const mName = asString(primaryApp?.middle_name);
          const rawFull = asString(primaryApp?.full_name);
          const candidateName = formatPersonName(fName, lName, mName, rawFull || "Candidate");

          const storeName = asString(directPlantilla?.store_name ?? directPlantilla?.store_branch);
          const confirmedCount = appsList.filter(
            (a) => (asString(a.status) || "").toLowerCase().trim() === "confirmed onboard",
          ).length;
          const activeCount = appsList.filter((a) => !asBoolean(a.is_archived)).length;
          const reqHc = 1;
          const occupiedCount = confirmedCount + activeCount;

          let agingDays: number | null = null;
          if (vacDate) {
            const vDate = new Date(vacDate);
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

          return {
            vacancyId: asString(directPlantilla?.id) ?? vacancyId,
            vcode,
            accountId: asString(directPlantilla?.account_id),
            accountName: asString(directPlantilla?.account_name ?? directPlantilla?.account) || "ALTURAS",
            groupId: asString(directPlantilla?.group_id),
            groupName: asString(directPlantilla?.group_name),
            storeId: asString(directPlantilla?.store_id),
            storeName,
            position_title: asString(directPlantilla?.position_title) ?? "Motorized Collector",
            department: asString(directPlantilla?.department),
            employmentType: asString(directPlantilla?.deployment_type) ?? "Stationary",
            vacancyStatus: "Open",
            pipelineStatus: "Vacancy - Open",
            derivedStatus: "Open",
            activeApplicantCount: activeCount,
            confirmedOnboardCount: confirmedCount,
            hasRecentHire: confirmedCount > 0,
            hasPendingClosure: false,
            closureRequestStatus: null,
            vacantDate: vacDate,
            daysToFill: null,
            agingDays,
            agingBucket,
            targetFillDate: null,
            urgencyLevel: "Standard",
            hrcoName: asString(directPlantilla?.hrco_name) ?? "—",
            lastActivityAt: asString(directPlantilla?.updated_at ?? directPlantilla?.created_at),
            rowCapabilities: {
              canViewDetail: true,
              canApprove: false,
              canUpdateApplicantStatus: true,
              canRequestClosure: true,
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
            storeBranch: asString(directPlantilla?.store_branch),
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
            activityHistory: [
              {
                eventId: `pl-vac-${asString(directPlantilla?.id) ?? vacancyId}`,
                eventLabel: "Vacancy Requisition Opened (Separation Backfill)",
                eventDescription: `Requisition ${vcode} opened for ${storeName || vcode} following Plantilla personnel separation.`,
                createdAt: vacDate,
                profileName: asString(directPlantilla?.hrco_name) ?? "System",
              },
            ],
          };
        }
    } catch {
      // Fall through to original error throw
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

  // Fallback: If accountName is missing or "Unknown Account", resolve via accountId or linked store
  if ((!normalized.accountName || normalized.accountName === "Unknown Account" || !normalized.groupName) && normalized.accountId) {
    try {
      const { data: acct } = await supabase
        .from("accounts")
        .select("account_name, group_id, groups(group_name)")
        .eq("id", normalized.accountId)
        .maybeSingle();

      if (acct) {
        if (!normalized.accountName || normalized.accountName === "Unknown Account") {
          normalized.accountName = acct.account_name;
        }
        if (!normalized.groupId && acct.group_id) {
          normalized.groupId = acct.group_id;
        }
        const grp = Array.isArray(acct.groups) ? acct.groups[0] : acct.groups;
        if (!normalized.groupName && grp && typeof grp === "object" && "group_name" in grp) {
          normalized.groupName = formatGroupName(String(grp.group_name), normalized.accountName);
        }
      }
    } catch {
      // Graceful fallback
    }
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

  // Enrich assigned stores and slot fraction details for coverage groups if not already present
  if (!normalized.assignedStores || normalized.assignedStores.length === 0 || !normalized.assignedStoreDetails) {
    try {
      let targetCgId: string | null = null;
      let targetCgCode: string | null = normalized.cgCode || null;

      if (normalized.cgCode) {
        const { data: cgRow } = await supabase
          .from("coverage_groups")
          .select("id, coverage_code")
          .eq("coverage_code", normalized.cgCode)
          .maybeSingle();
        if (cgRow?.id) targetCgId = cgRow.id;
      }

      if (!targetCgId && (normalized.storeId || normalized.vcode)) {
        let sid = normalized.storeId;
        if (!sid && normalized.vcode) {
          const { data: sRow } = await supabase
            .from("stores")
            .select("id")
            .eq("vcode", normalized.vcode)
            .maybeSingle();
          if (sRow?.id) sid = sRow.id;
        }

        if (sid) {
          const { data: cgsMatch } = await supabase
            .from("coverage_group_stores")
            .select("coverage_group_id, coverage_groups(coverage_code)")
            .eq("store_id", sid)
            .is("archived_at", null)
            .maybeSingle();
          if (cgsMatch?.coverage_group_id) {
            targetCgId = cgsMatch.coverage_group_id;
            const cgRaw = cgsMatch.coverage_groups as unknown;
            const cgObj = Array.isArray(cgRaw) ? (cgRaw[0] as Record<string, unknown> | undefined) : (cgRaw as Record<string, unknown> | null);
            if (cgObj?.coverage_code) targetCgCode = asString(cgObj.coverage_code);
          }
        }
      }

      if (targetCgId) {
        if (targetCgCode) normalized.cgCode = targetCgCode;

        const { data: allCgs } = await supabase
          .from("coverage_group_stores")
          .select(`
            coverage_group_id,
            store_id,
            is_anchor,
            hc_share,
            stores(id, store_name, vcode)
          `)
          .eq("coverage_group_id", targetCgId)
          .is("archived_at", null);

        if (allCgs && allCgs.length > 0) {
          const count = allCgs.length;
          const defaultFraction = `1/${count}`;
          const storesList: string[] = [];
          const detailsList: AssignedStoreDetail[] = [];

          for (const item of allCgs as Array<Record<string, unknown>>) {
            const sObj = (item.stores as unknown) as Record<string, unknown> | null;
            const sname = asString(sObj?.store_name) || "";
            const svcode = asString(sObj?.vcode) || "";
            const sid = asString(item.store_id) || asString(sObj?.id) || "";
            const isAnchor = asBoolean(item.is_anchor);
            const hcShare = asNumber(item.hc_share);
            const slotFraction = hcShare
              ? hcShare === 0.5
                ? "1/2"
                : hcShare >= 0.33 && hcShare <= 0.34
                ? "1/3"
                : hcShare === 0.25
                ? "1/4"
                : defaultFraction
              : defaultFraction;

            if (sname && !storesList.includes(sname)) {
              storesList.push(sname);
            }
            detailsList.push({
              storeId: sid || undefined,
              storeName: sname,
              vcode: svcode || null,
              isAnchor,
              slotFraction,
            });
          }

          if (storesList.length > 0) normalized.assignedStores = storesList;
          if (detailsList.length > 0) normalized.assignedStoreDetails = detailsList;
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  // Enrich itemized requirements if available
  try {
    const itemizedReqs = await fetchVacancyRequirements(normalized.vacancyId);
    if (itemizedReqs && itemizedReqs.length > 0) {
      normalized.requirements = itemizedReqs;
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
          .select("id, contact_number, first_name, last_name, middle_name, profile_edit_count, created_at, updated_at, vacancy_requirement_id")
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
              if (rawApp.vacancy_requirement_id) {
                cand.vacancyRequirementId = asString(rawApp.vacancy_requirement_id);
                if (normalized.requirements && normalized.requirements.length > 0) {
                  const matchedReq = normalized.requirements.find((r) => r.id === cand.vacancyRequirementId);
                  if (matchedReq?.positionName) {
                    cand.position = matchedReq.positionName;
                  }
                }
              }
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


// ── 4b. Direct Import / Quick-Create Vacancy ─────────────────
export async function fetchOccupiedStoreIdentifiers(
  accountId: string
): Promise<OccupiedStoreIdentifiers> {
  const supabase = createClient();
  const occupiedStoreIds = new Set<string>();
  const occupiedVcodes = new Set<string>();
  const occupiedStoreNames = new Set<string>();

  if (!accountId) {
    return { occupiedStoreIds, occupiedVcodes, occupiedStoreNames };
  }

  const [slotsRes, plantillaRes, allocsRes] = await Promise.all([
    supabase
      .from("plantilla_slots")
      .select("store_id, legacy_vcode, slot_status, current_occupant_plantilla_id")
      .eq("account_id", accountId)
      .or("slot_status.in.(occupied,filled),current_occupant_plantilla_id.not.is.null"),
    supabase
      .from("plantilla")
      .select("store_id, vcode, store_name, status, deactivated_at, date_of_separation")
      .eq("account_id", accountId)
      .is("deactivated_at", null)
      .is("date_of_separation", null),
    supabase
      .from("employee_store_allocations")
      .select("store_id, vcode, store_name")
      .eq("account_id", accountId)
      .eq("is_active", true),
  ]);

  if (slotsRes.data && Array.isArray(slotsRes.data)) {
    for (const slot of slotsRes.data) {
      if (slot.store_id) occupiedStoreIds.add(String(slot.store_id));
      if (slot.legacy_vcode) occupiedVcodes.add(String(slot.legacy_vcode).trim().toUpperCase());
    }
  }

  if (plantillaRes.data && Array.isArray(plantillaRes.data)) {
    const INACTIVE_STATUSES = new Set([
      "inactive",
      "deactivated",
      "resigned",
      "separated",
      "endo",
      "terminated",
    ]);
    for (const emp of plantillaRes.data) {
      const st = (emp.status || "active").toLowerCase().trim();
      if (!INACTIVE_STATUSES.has(st)) {
        if (emp.store_id) occupiedStoreIds.add(String(emp.store_id));
        if (emp.vcode) occupiedVcodes.add(String(emp.vcode).trim().toUpperCase());
        if (emp.store_name) occupiedStoreNames.add(String(emp.store_name).trim().toUpperCase());
      }
    }
  }

  if (allocsRes.data && Array.isArray(allocsRes.data)) {
    for (const alloc of allocsRes.data) {
      if (alloc.store_id) occupiedStoreIds.add(String(alloc.store_id));
      if (alloc.vcode) occupiedVcodes.add(String(alloc.vcode).trim().toUpperCase());
      if (alloc.store_name) occupiedStoreNames.add(String(alloc.store_name).trim().toUpperCase());
    }
  }

  return { occupiedStoreIds, occupiedVcodes, occupiedStoreNames };
}

/**
 * Fetch itemized position requirements (vacancy_requirements) for a vacancy.
 * Resolves by either vacancyId (UUID) or vcode.
 * Joins positions table for human-readable position_name and computes pipeline counts.
 */
export async function fetchVacancyRequirements(
  vacancyIdOrVcode: string,
): Promise<VacancyRequirementItem[]> {
  if (!vacancyIdOrVcode || !vacancyIdOrVcode.trim()) return [];
  const supabase = createClient();
  const input = vacancyIdOrVcode.trim();
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input);

  let targetVacancyId: string | null = isUuid ? input : null;

  if (!targetVacancyId) {
    const { data: vac, error: vacError } = await supabase
      .from("vacancies")
      .select("id")
      .eq("vcode", input)
      .maybeSingle();

    if (vacError) {
      console.error("[PostgREST Schema Error] fetchVacancyRequirements resolve vacancy_id:", vacError);
      return [];
    }
    if (!vac?.id) return [];
    targetVacancyId = String(vac.id);
  }

  // 1. Fetch requirements with derived hc_filled from vw_vacancy_requirements (with fallback to table)
  let reqData: Array<Record<string, unknown>> | null = null;
  const { data: viewData, error: viewError } = await supabase
    .from("vw_vacancy_requirements")
    .select("id, vacancy_id, position_id, employment_type, hc_needed, hc_filled")
    .eq("vacancy_id", targetVacancyId)
    .order("hc_needed", { ascending: false });

  if (!viewError && Array.isArray(viewData)) {
    reqData = viewData;
  } else {
    const { data: tblData, error: tblError } = await supabase
      .from("vacancy_requirements")
      .select("id, vacancy_id, position_id, employment_type, hc_needed, hc_filled")
      .eq("vacancy_id", targetVacancyId)
      .order("hc_needed", { ascending: false });
    if (tblError) {
      console.error("[PostgREST Schema Error] fetchVacancyRequirements fallback table:", tblError);
      return [];
    }
    reqData = tblData;
  }

  if (!reqData || reqData.length === 0) return [];

  // 2. Resolve position names
  const posIds = Array.from(new Set(reqData.map((r) => asString(r.position_id)).filter(Boolean))) as string[];
  const posMap = new Map<string, string>();
  if (posIds.length > 0) {
    try {
      const { data: posData, error: posError } = await supabase
        .from("positions")
        .select("id, position_name")
        .in("id", posIds);
      if (!posError && Array.isArray(posData)) {
        for (const p of posData) {
          const pid = asString(p.id);
          const pname = asString(p.position_name);
          if (pid && pname) posMap.set(pid, pname);
        }
      }
    } catch (e) {
      console.error("[PostgREST Schema Error] fetchVacancyRequirements positions join:", e);
    }
  }

  // 3. Count active pipeline applicants per requirement
  const reqIds = reqData.map((r) => asString(r.id)).filter(Boolean) as string[];
  const pipelineCounts = new Map<string, number>();
  if (reqIds.length > 0) {
    try {
      const { data: appsData, error: appsError } = await supabase
        .from("applicants")
        .select("vacancy_requirement_id")
        .in("vacancy_requirement_id", reqIds)
        .not("status", "in", '("Backout","backout","Failed","failed","Rejected","rejected","Did Not Report","did not report","confirmed_onboard","Confirmed Onboard","hired","Hired")')
        .eq("is_archived", false);

      if (!appsError && Array.isArray(appsData)) {
        for (const a of appsData) {
          const rid = asString(a.vacancy_requirement_id);
          if (rid) {
            pipelineCounts.set(rid, (pipelineCounts.get(rid) || 0) + 1);
          }
        }
      }
    } catch (e) {
      console.error("[PostgREST Schema Error] fetchVacancyRequirements pipeline counts:", e);
    }
  }

  return reqData.map((r) => {
    const rid = asString(r.id) || "";
    const pid = asString(r.position_id);
    const hcNeeded = asNumber(r.hc_needed) || 1;
    const hcFilled = asNumber(r.hc_filled) || 0;
    const pipeCount = pipelineCounts.get(rid) || 0;
    const availableSlots = Math.max(0, hcNeeded - hcFilled - pipeCount);
    const isFull = availableSlots <= 0;
    return {
      id: rid,
      positionName: (pid ? posMap.get(pid) : null) || "Position",
      employmentType: asString(r.employment_type) || "Stationary",
      hcNeeded,
      hcFilled,
      pipelineCount: pipeCount,
      availableSlots,
      isFull,
    };
  });
}

/**
 * React hook to fetch position requirements for a vacancy with TanStack Query.
 */
export function useVacancyRequirements(
  vacancyIdOrVcode: string | null | undefined,
  enabled = true,
) {
  return useQuery({
    queryKey: ["vacancy", "requirements", vacancyIdOrVcode],
    queryFn: () => (vacancyIdOrVcode ? fetchVacancyRequirements(vacancyIdOrVcode) : Promise.resolve([])),
    enabled: Boolean(vacancyIdOrVcode && enabled),
    staleTime: 30_000,
  });
}
