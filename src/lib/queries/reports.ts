import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ============================================================================
// 1. Core Filter & Common Models
// ============================================================================

export interface ReportQueryFilters {
  startDate?: string | null;
  endDate?: string | null;
  groupId?: string | null;
  accountId?: string | null;
}

export interface GroupReportSummary {
  groupId: string;
  groupName: string;
  accountId: string;
  accountName: string;
  totalCount: number;
  affectedStoreCount: number;
  periodStart: string;
  periodEnd: string;
  attritionRate?: number | null;
  avgDaysToFill?: number | null;
  lateCount?: number | null;
  backoutCount?: number | null;
  terminatedCount?: number | null;
  openCount?: number | null;
  closedCount?: number | null;
}

export interface AttritionDetailStore {
  storeName: string;
  location: string;
  separatedCount: number;
}

export interface AttritionDetailEmployee {
  id: string;
  employeeName: string;
  employeeNo?: string;
  storeName: string;
  position: string;
  separationDate: string | null;
  reason: string;
  separationStatus: string | null;
}

export interface AttritionDetailResult {
  stores: AttritionDetailStore[];
  employees: AttritionDetailEmployee[];
}

export interface ReportFilterOption {
  id: string;
  name: string;
  groupId?: string;
}

// ============================================================================
// 2. Floating Staff Models
// ============================================================================

export interface FloatingEmployeeRow {
  plantillaId: string;
  employeeNo: string;
  employeeName: string;
  position: string;
  accountId: string;
  accountName: string;
  groupId: string;
  groupName: string;
  storeName: string;
  floatingSince: string | null;
  daysFloating: number;
  employmentType: string;
  status: string;
}

// ============================================================================
// 3. Team Performance Models
// ============================================================================

export interface TeamPerformanceKpis {
  bestGroupName?: string | null;
  bestGroupScore?: number | null;
  lowestGroupName?: string | null;
  lowestGroupScore?: number | null;
  averageScore: number;
  criticalCount: number;
}

export interface TeamPerformanceEntry {
  accountId: string;
  accountName: string;
  groupId: string;
  groupName: string;
  hrcoName?: string | null;
  score: number;
  severity: "Excellent" | "Good" | "Watch" | "Critical";
  mfr: number;
  agedVacancies: number;
  lateHrUpdates: number;
  actualHc: number;
  vacantHc: number;
  requiredHc: number;
}

export interface TeamPerformanceSummary {
  kpis: TeamPerformanceKpis;
  leaderboard: TeamPerformanceEntry[];
}

export interface TeamPerformanceIssueRow {
  accountId: string;
  accountName: string;
  groupId: string;
  groupName: string;
  hrcoName?: string | null;
  issueCategory: string;
  issueLabel: string;
  issueDetail: string;
  daysImpacted?: number | null;
  storeName?: string | null;
  employeeName?: string | null;
  vcode?: string | null;
}

// ============================================================================
// 4. Data Integrity Models
// ============================================================================

export interface DataIntegritySectionSummary {
  affectedStores: number;
  totalFindings: number;
  affectedEmployees?: number | null;
  worstDelay?: number | null;
  criticalFindings?: number | null;
  activeFindings?: number | null;
}

export interface DataIntegritySummary {
  criticalIssues: number;
  highRiskIssues: number;
  totalFindings: number;
  affectedStores: number;
  lateHrUpdates: DataIntegritySectionSummary;
  vacancyCreationDelay: DataIntegritySectionSummary;
  ghostOccupancy: DataIntegritySectionSummary;
  pipelineNoVacancy: DataIntegritySectionSummary;
}

export interface DataIntegrityDetailRow {
  storeName: string;
  accountName: string;
  groupName: string;
  issueType: string;
  detectedDate?: string | null;
  employeeName?: string | null;
  applicantName?: string | null;
  position?: string | null;
  vcode?: string | null;
  currentStatus?: string | null;
  effectiveDate?: string | null;
  recordedDate?: string | null;
  vacancyCreatedDate?: string | null;
  daysImpacted?: number | null;
}

// ============================================================================
// 5. Query Implementation Functions
// ============================================================================

/**
 * Fetch Groups and Accounts for filtering
 */
export async function fetchReportFilterOptions(): Promise<{
  groups: ReportFilterOption[];
  accounts: ReportFilterOption[];
}> {
  const supabase = createClient();

  const [groupsRes, accountsRes] = await Promise.all([
    supabase
      .from("v_cencom_group_allocation_kpi")
      .select("group_id, group_name")
      .order("group_name", { ascending: true }),
    supabase
      .from("v_cencom_account_allocation_kpi")
      .select("account_id, account_name, group_id")
      .order("account_name", { ascending: true }),
  ]);

  const groups: ReportFilterOption[] = (groupsRes.data ?? [])
    .filter((g) => g.group_id && g.group_name)
    .map((g) => ({
      id: String(g.group_id),
      name: String(g.group_name),
    }));

  const accounts: ReportFilterOption[] = (accountsRes.data ?? [])
    .filter((a) => a.account_id && a.account_name)
    .map((a) => ({
      id: String(a.account_id),
      name: String(a.account_name),
      groupId: a.group_id ? String(a.group_id) : undefined,
    }));

  return { groups, accounts };
}

/**
 * Dispatcher for Quick Reports (Group-Scoped Operational Reports RPCs)
 */
export async function fetchUniversalGroupReport(
  reportId: string,
  filters: ReportQueryFilters
): Promise<GroupReportSummary[]> {
  const supabase = createClient();

  let rpcName: string;
  switch (reportId) {
    case "attrition_report":
      rpcName = "report_attrition_by_group";
      break;
    case "resigned_report":
      rpcName = "report_resigned_by_group";
      break;
    case "awol_report":
      rpcName = "report_awol_by_group";
      break;
    case "terminated_report":
      rpcName = "report_terminated_by_group";
      break;
    case "backout_report":
      rpcName = "report_backout_by_group";
      break;
    case "backout_terminated_report":
      rpcName = "report_backout_terminated_by_group";
      break;
    case "time_to_fill":
      rpcName = "report_time_to_fill_by_group";
      break;
    case "emploc_late_update":
      rpcName = "report_hr_emploc_late_update_by_group";
      break;
    default:
      throw new Error(`Unknown reportId: ${reportId}`);
  }

  const params: Record<string, unknown> = {
    p_start_date: filters.startDate || null,
    p_end_date: filters.endDate || null,
    p_group_id: filters.groupId || null,
    p_account_id: filters.accountId || null,
  };

  const { data, error } = await supabase.rpc(rpcName, params);

  if (error) {
    console.error(`[UniversalReport] Error calling ${rpcName}:`, error);
    throw error;
  }

  const rows = (data ?? []) as Array<Record<string, unknown>>;
  return rows.map((r) => ({
    groupId: String(r.group_id ?? ""),
    groupName: String(r.group_name ?? ""),
    accountId: String(r.account_id ?? ""),
    accountName: String(r.account_name ?? ""),
    totalCount: Number(r.total_count ?? 0),
    affectedStoreCount: Number(r.affected_store_count ?? 0),
    periodStart: String(r.period_start ?? ""),
    periodEnd: String(r.period_end ?? ""),
    attritionRate: r.attrition_rate != null ? Number(r.attrition_rate) : null,
    avgDaysToFill: r.avg_days_to_fill != null ? Number(r.avg_days_to_fill) : null,
    lateCount: r.late_count != null ? Number(r.late_count) : null,
    backoutCount: r.backout_count != null ? Number(r.backout_count) : null,
    terminatedCount: r.terminated_count != null ? Number(r.terminated_count) : null,
    openCount: r.open_count != null ? Number(r.open_count) : null,
    closedCount: r.closed_count != null ? Number(r.closed_count) : null,
  }));
}

/**
 * Detailed separated staff and stores breakdown for Attrition
 */
export async function fetchAttritionDetails(
  accountId: string,
  startDate?: string | null,
  endDate?: string | null
): Promise<AttritionDetailResult> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_get_attrition_details", {
    p_account_id: accountId,
    p_start_date: startDate || null,
    p_end_date: endDate || null,
  });

  if (error) {
    console.error("[AttritionDetails] RPC error:", error);
    throw error;
  }

  const list = (data ?? []) as Array<Record<string, unknown>>;
  const employees: AttritionDetailEmployee[] = [];
  const storeCounts: Record<string, number> = {};
  const storeLocations: Record<string, string> = {};

  for (const r of list) {
    const empId = String(r.id ?? "");
    const empNameRaw = String(r.employee_name ?? "").trim();
    const empNo = String(r.employee_no ?? "").trim();
    const empName =
      !empNameRaw || empNameRaw === "(VACANT SLOT)"
        ? empNo && empNo !== "(PENDING)"
          ? `Employee #${empNo}`
          : "Unknown Employee"
        : empNameRaw;
    const storeName = String(r.store_name ?? "Unknown Store");
    const pos = String(r.position ?? "Staff");
    const reason = String(r.deactivation_reason ?? "Not specified");
    const separationStatus = r.separation_status ? String(r.separation_status) : null;

    const sepDateStr = r.date_of_separation ? String(r.date_of_separation) : null;
    const deacAtStr = r.deactivated_at ? String(r.deactivated_at) : null;
    const effectiveSepDate = sepDateStr || deacAtStr;

    employees.push({
      id: empId,
      employeeName: empName,
      employeeNo: empNo || undefined,
      storeName,
      position: pos,
      separationDate: effectiveSepDate,
      reason,
      separationStatus,
    });

    storeCounts[storeName] = (storeCounts[storeName] ?? 0) + 1;

    const city = String(r.area_city ?? "").trim();
    const province = String(r.area_province ?? "").trim();
    let location = "Unknown Location";
    if (city && province) location = `${city}, ${province}`;
    else if (city) location = city;
    else if (province) location = province;

    storeLocations[storeName] = location;
  }

  const stores: AttritionDetailStore[] = Object.entries(storeCounts).map(
    ([name, count]) => ({
      storeName: name,
      location: storeLocations[name] ?? "Unknown Location",
      separatedCount: count,
    })
  );

  return { stores, employees };
}

/**
 * Floating Staff Report
 */
export async function fetchFloatingReport(
  groupId?: string | null,
  accountId?: string | null
): Promise<FloatingEmployeeRow[]> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_report_floating_employees", {
    p_group_id: groupId || null,
    p_account_id: accountId || null,
  });

  if (error) {
    console.error("[FloatingReport] RPC error:", error);
    throw error;
  }

  const list = (data ?? []) as Array<Record<string, unknown>>;
  return list.map((j) => ({
    plantillaId: String(j.plantilla_id ?? ""),
    employeeNo: String(j.employee_no ?? ""),
    employeeName: String(j.employee_name ?? ""),
    position: String(j.position_title ?? j.position ?? ""),
    accountId: String(j.account_id ?? ""),
    accountName: String(j.account_name ?? ""),
    groupId: String(j.group_id ?? ""),
    groupName: String(j.group_name ?? ""),
    storeName: String(j.store_name ?? ""),
    floatingSince: j.floating_since ? String(j.floating_since) : null,
    daysFloating: Number(j.days_floating ?? 0),
    employmentType: String(j.employment_type ?? "Stationary"),
    status: String(j.status ?? "Floating"),
  }));
}

/**
 * Team Performance Summary
 */
export async function fetchTeamPerformanceSummary(
  groupId?: string | null,
  accountId?: string | null
): Promise<TeamPerformanceSummary> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_team_performance_summary", {
    p_group_id: groupId || null,
    p_account_id: accountId || null,
  });

  if (error) {
    console.error("[TeamPerformanceSummary] RPC error:", error);
    throw error;
  }

  const res = (data ?? {}) as Record<string, unknown>;
  const kpisRaw = (res.kpis ?? {}) as Record<string, unknown>;
  const leaderboardRaw = (res.leaderboard ?? []) as Array<Record<string, unknown>>;

  const kpis: TeamPerformanceKpis = {
    bestGroupName: kpisRaw.best_group ? String(kpisRaw.best_group) : null,
    bestGroupScore:
      kpisRaw.best_group_score != null ? Number(kpisRaw.best_group_score) : null,
    lowestGroupName: kpisRaw.lowest_group ? String(kpisRaw.lowest_group) : null,
    lowestGroupScore:
      kpisRaw.lowest_group_score != null ? Number(kpisRaw.lowest_group_score) : null,
    averageScore: Number(kpisRaw.average_score ?? 0),
    criticalCount: Number(kpisRaw.critical_count ?? 0),
  };

  const leaderboard: TeamPerformanceEntry[] = leaderboardRaw.map((j) => {
    const score = Number(j.score ?? 0);
    let severity: "Excellent" | "Good" | "Watch" | "Critical" = "Watch";
    if (score >= 90) severity = "Excellent";
    else if (score >= 80) severity = "Good";
    else if (score >= 70) severity = "Watch";
    else severity = "Critical";

    return {
      accountId: String(j.account_id ?? ""),
      accountName: String(j.account_name ?? ""),
      groupId: String(j.group_id ?? ""),
      groupName: String(j.group_name ?? ""),
      hrcoName: j.hrco_name ? String(j.hrco_name) : null,
      score,
      severity,
      mfr: Number(j.mfr ?? 0),
      agedVacancies: Number(j.aged_vacancies ?? 0),
      lateHrUpdates: Number(j.late_hr_updates ?? 0),
      actualHc: Number(j.actual_hc ?? 0),
      vacantHc: Number(j.vacant_hc ?? 0),
      requiredHc: Number(j.required_hc ?? 0),
    };
  });

  return { kpis, leaderboard };
}

/**
 * Team Performance Issues Detail
 */
export async function fetchTeamPerformanceDetail(
  groupId?: string | null,
  accountId?: string | null
): Promise<TeamPerformanceIssueRow[]> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_team_performance_detail", {
    p_group_id: groupId || null,
    p_account_id: accountId || null,
  });

  if (error) {
    console.error("[TeamPerformanceDetail] RPC error:", error);
    throw error;
  }

  const list = (data ?? []) as Array<Record<string, unknown>>;
  return list.map((j) => ({
    accountId: String(j.account_id ?? ""),
    accountName: String(j.account_name ?? ""),
    groupId: String(j.group_id ?? ""),
    groupName: String(j.group_name ?? ""),
    hrcoName: j.hrco_name ? String(j.hrco_name) : null,
    issueCategory: String(j.issue_category ?? ""),
    issueLabel: String(j.issue_label ?? ""),
    issueDetail: String(j.issue_detail ?? ""),
    daysImpacted: j.days_impacted != null ? Number(j.days_impacted) : null,
    storeName: j.store_name ? String(j.store_name) : null,
    employeeName: j.employee_name ? String(j.employee_name) : null,
    vcode: j.vcode ? String(j.vcode) : null,
  }));
}

/**
 * Data Integrity Summary
 */
export async function fetchDataIntegritySummary(
  groupId?: string | null,
  accountId?: string | null
): Promise<DataIntegritySummary> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_data_integrity_summary", {
    p_group_id: groupId || null,
    p_account_id: accountId || null,
  });

  if (error) {
    console.error("[DataIntegritySummary] RPC error:", error);
    throw error;
  }

  const res = (data ?? {}) as Record<string, unknown>;
  const kpis = (res.kpis ?? {}) as Record<string, unknown>;
  const late = (res.late_hr_updates ?? {}) as Record<string, unknown>;
  const vac = (res.vacancy_creation_delay ?? {}) as Record<string, unknown>;
  const ghost = (res.ghost_occupancy ?? {}) as Record<string, unknown>;
  const pipe = (res.pipeline_no_vacancy ?? {}) as Record<string, unknown>;

  const parseSection = (j: Record<string, unknown>): DataIntegritySectionSummary => ({
    affectedStores: Number(j.affected_stores ?? 0),
    totalFindings: Number(j.total_findings ?? 0),
    affectedEmployees: j.affected_employees != null ? Number(j.affected_employees) : null,
    worstDelay: j.worst_delay != null ? Number(j.worst_delay) : null,
    criticalFindings: j.critical_findings != null ? Number(j.critical_findings) : null,
    activeFindings: j.active_findings != null ? Number(j.active_findings) : null,
  });

  return {
    criticalIssues: Number(kpis.critical_issues ?? 0),
    highRiskIssues: Number(kpis.high_risk_issues ?? 0),
    totalFindings: Number(kpis.total_findings ?? 0),
    affectedStores: Number(kpis.affected_stores ?? 0),
    lateHrUpdates: parseSection(late),
    vacancyCreationDelay: parseSection(vac),
    ghostOccupancy: parseSection(ghost),
    pipelineNoVacancy: parseSection(pipe),
  };
}

/**
 * Data Integrity Late HR Updates Detail
 */
export async function fetchDataIntegrityLateHrDetail(options?: {
  groupId?: string | null;
  accountId?: string | null;
  slaDays?: number;
  page?: number;
  pageSize?: number;
}): Promise<DataIntegrityDetailRow[]> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_data_integrity_late_hr_detail", {
    p_group_id: options?.groupId || null,
    p_account_id: options?.accountId || null,
    p_sla_days: options?.slaDays ?? 7,
    p_page: options?.page ?? 0,
    p_page_size: options?.pageSize ?? 50,
  });

  if (error) {
    console.error("[LateHrDetail] RPC error:", error);
    throw error;
  }

  const list = (data ?? []) as Array<Record<string, unknown>>;
  return list.map((j) => ({
    storeName: String(j.store_name ?? "—"),
    accountName: String(j.account_name ?? "—"),
    groupName: String(j.group_name ?? "—"),
    issueType: String(j.issue_type ?? "Late Update"),
    detectedDate: j.detected_date ? String(j.detected_date) : null,
    employeeName: j.employee_name ? String(j.employee_name) : null,
    position: j.position ? String(j.position) : null,
    effectiveDate: j.effective_date ? String(j.effective_date) : null,
    recordedDate: j.recorded_date ? String(j.recorded_date) : null,
    daysImpacted: j.delay_days != null ? Number(j.delay_days) : null,
  }));
}

/**
 * Data Integrity Vacancy Creation Delay Detail
 */
export async function fetchDataIntegrityVacancyDelayDetail(options?: {
  groupId?: string | null;
  accountId?: string | null;
  slaDays?: number;
  page?: number;
  pageSize?: number;
}): Promise<DataIntegrityDetailRow[]> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_data_integrity_vacancy_delay_detail", {
    p_group_id: options?.groupId || null,
    p_account_id: options?.accountId || null,
    p_sla_days: options?.slaDays ?? 7,
    p_page: options?.page ?? 0,
    p_page_size: options?.pageSize ?? 50,
  });

  if (error) {
    console.error("[VacancyDelayDetail] RPC error:", error);
    throw error;
  }

  const list = (data ?? []) as Array<Record<string, unknown>>;
  return list.map((j) => ({
    storeName: String(j.store_name ?? "—"),
    accountName: String(j.account_name ?? "—"),
    groupName: String(j.group_name ?? "—"),
    issueType: "Vacancy Created Late",
    detectedDate: j.detected_date ? String(j.detected_date) : null,
    employeeName: j.employee_name ? String(j.employee_name) : null,
    position: j.position ? String(j.position) : null,
    vcode: j.vcode ? String(j.vcode) : null,
    effectiveDate: j.effective_departure_date ? String(j.effective_departure_date) : null,
    vacancyCreatedDate: j.vacancy_created_date ? String(j.vacancy_created_date) : null,
    daysImpacted: j.delay_days != null ? Number(j.delay_days) : null,
  }));
}

/**
 * Data Integrity Ghost Occupancy Detail
 */
export async function fetchDataIntegrityGhostOccupancyDetail(options?: {
  groupId?: string | null;
  accountId?: string | null;
  page?: number;
  pageSize?: number;
}): Promise<DataIntegrityDetailRow[]> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_data_integrity_ghost_occupancy_detail", {
    p_group_id: options?.groupId || null,
    p_account_id: options?.accountId || null,
    p_page: options?.page ?? 0,
    p_page_size: options?.pageSize ?? 50,
  });

  if (error) {
    console.error("[GhostOccupancyDetail] RPC error:", error);
    throw error;
  }

  const list = (data ?? []) as Array<Record<string, unknown>>;
  return list.map((j) => ({
    storeName: String(j.store_name ?? "—"),
    accountName: String(j.account_name ?? "—"),
    groupName: String(j.group_name ?? "—"),
    issueType: String(j.issue_type ?? "Ghost Occupancy"),
    detectedDate: j.detected_date ? String(j.detected_date) : null,
    employeeName: j.employee_name ? String(j.employee_name) : null,
    position: j.position ? String(j.position) : null,
  }));
}

/**
 * Data Integrity Pipeline Without Vacancy Detail
 */
export async function fetchDataIntegrityPipelineNoVacancyDetail(options?: {
  groupId?: string | null;
  accountId?: string | null;
  page?: number;
  pageSize?: number;
}): Promise<DataIntegrityDetailRow[]> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fn_data_integrity_pipeline_no_vacancy_detail", {
    p_group_id: options?.groupId || null,
    p_account_id: options?.accountId || null,
    p_page: options?.page ?? 0,
    p_page_size: options?.pageSize ?? 50,
  });

  if (error) {
    console.error("[PipelineNoVacancyDetail] RPC error:", error);
    throw error;
  }

  const list = (data ?? []) as Array<Record<string, unknown>>;
  return list.map((j) => ({
    storeName: String(j.store_name ?? "—"),
    accountName: String(j.account_name ?? "—"),
    groupName: String(j.group_name ?? "—"),
    issueType: String(j.issue_type ?? "Pipeline Without Vacancy"),
    detectedDate: j.detected_date ? String(j.detected_date) : null,
    applicantName: j.applicant_name ? String(j.applicant_name) : null,
    vcode: j.vcode ? String(j.vcode) : null,
    currentStatus: j.current_status ? String(j.current_status) : null,
  }));
}

/**
 * Custom Report Preview
 */
export async function fetchCustomReportPreview(options: {
  reportType: string;
  startDate?: string;
  endDate?: string;
  groupId?: string | null;
  accountId?: string | null;
  accountName?: string | null;
  status?: string | null;
}): Promise<Record<string, unknown>[]> {
  const supabase = createClient();
  const today = new Date().toISOString().split("T")[0];
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    .toISOString()
    .split("T")[0];

  switch (options.reportType) {
    case "vacancy":
    case "plantilla": {
      const { data, error } = await supabase
        .from("v_cencom_account_allocation_kpi")
        .select(
          "account_id, account_name, group_id, actual_hc, slot_vacant_hc, open_hc, required_hc, pipeline_count, mfr"
        )
        .order("account_name", { ascending: true });

      if (error) throw error;
      const rows = (data ?? []) as Array<Record<string, unknown>>;
      return rows.filter((r) => {
        if (options.accountId && String(r.account_id) !== options.accountId) return false;
        if (options.groupId && String(r.group_id) !== options.groupId) return false;
        return true;
      });
    }

    case "hr_emploc": {
      const start = options.startDate || thirtyDaysAgo;
      const end = options.endDate || today;

      let q = supabase
        .from("hr_emploc")
        .select("applicant_name, position, store_name, hr_status, status, account, date_requested")
        .gte("date_requested", start)
        .lte("date_requested", end)
        .is("deleted_at", null);

      if (options.accountName) {
        q = q.eq("account", options.accountName);
      }
      if (options.status) {
        q = q.eq("status", options.status);
      }

      const { data, error } = await q.order("date_requested", { ascending: false }).limit(250);
      if (error) throw error;
      return (data ?? []) as Array<Record<string, unknown>>;
    }

    case "deployment": {
      const { data, error } = await supabase.rpc("fn_cencom_deployment_summary");
      if (error) throw error;
      const s = (data ?? {}) as Record<string, unknown>;
      return [
        { metric: "Total Departures", value: Number(s.total_departures ?? 0) },
        { metric: "Additional Headcount", value: Number(s.additional_hc ?? 0) },
        { metric: "Deleted VCodes", value: Number(s.deleted_vcode ?? 0) },
        { metric: "Net Deployment", value: Number(s.deployment ?? 0) },
      ];
    }

    case "data_integrity": {
      const s = await fetchDataIntegritySummary(options.groupId, options.accountId);
      return [
        {
          section: "Late HR Updates",
          total_findings: s.lateHrUpdates.totalFindings,
          affected_stores: s.lateHrUpdates.affectedStores,
          worst_delay: s.lateHrUpdates.worstDelay ?? "—",
        },
        {
          section: "Vacancy Creation Delay",
          total_findings: s.vacancyCreationDelay.totalFindings,
          affected_stores: s.vacancyCreationDelay.affectedStores,
          worst_delay: s.vacancyCreationDelay.worstDelay ?? "—",
        },
        {
          section: "Ghost Occupancy",
          total_findings: s.ghostOccupancy.totalFindings,
          affected_stores: s.ghostOccupancy.affectedStores,
          active_findings: s.ghostOccupancy.activeFindings ?? "—",
        },
        {
          section: "Pipeline Without Vacancy",
          total_findings: s.pipelineNoVacancy.totalFindings,
          affected_stores: s.pipelineNoVacancy.affectedStores,
          critical_findings: s.pipelineNoVacancy.criticalFindings ?? "—",
        },
      ];
    }

    case "team_performance": {
      const s = await fetchTeamPerformanceSummary(options.groupId, options.accountId);
      return s.leaderboard.map((e) => ({
        account_name: e.accountName,
        group_name: e.groupName,
        score: e.score.toFixed(1),
        severity: e.severity,
        mfr: `${(e.mfr * 100).toFixed(1)}%`,
        aged_vacancies: e.agedVacancies,
        late_hr_updates: e.lateHrUpdates,
        hrco_name: e.hrcoName ?? "—",
        actual_hc: e.actualHc,
        vacant_hc: e.vacantHc,
        required_hc: e.requiredHc,
      }));
    }

    default:
      return [];
  }
}

// ============================================================================
// 6. TanStack Query Hooks
// ============================================================================

export function useReportFilterOptions() {
  return useQuery({
    queryKey: ["reports", "filter-options"],
    queryFn: fetchReportFilterOptions,
    staleTime: 60 * 1000,
  });
}

export function useUniversalGroupReport(reportId: string, filters: ReportQueryFilters) {
  return useQuery({
    queryKey: ["reports", "group-report", reportId, filters],
    queryFn: () => fetchUniversalGroupReport(reportId, filters),
    staleTime: 30 * 1000,
  });
}

export function useAttritionDetails(
  accountId: string | null,
  startDate?: string | null,
  endDate?: string | null,
  enabled = true
) {
  return useQuery({
    queryKey: ["reports", "attrition-details", accountId, startDate, endDate],
    queryFn: () => fetchAttritionDetails(accountId!, startDate, endDate),
    enabled: Boolean(accountId && enabled),
    staleTime: 30 * 1000,
  });
}

export function useFloatingReport(groupId?: string | null, accountId?: string | null) {
  return useQuery({
    queryKey: ["reports", "floating", groupId, accountId],
    queryFn: () => fetchFloatingReport(groupId, accountId),
    staleTime: 30 * 1000,
  });
}

export function useTeamPerformanceSummary(groupId?: string | null, accountId?: string | null) {
  return useQuery({
    queryKey: ["reports", "team-performance-summary", groupId, accountId],
    queryFn: () => fetchTeamPerformanceSummary(groupId, accountId),
    staleTime: 30 * 1000,
  });
}

export function useTeamPerformanceDetail(
  groupId?: string | null,
  accountId?: string | null,
  enabled = true
) {
  return useQuery({
    queryKey: ["reports", "team-performance-detail", groupId, accountId],
    queryFn: () => fetchTeamPerformanceDetail(groupId, accountId),
    enabled,
    staleTime: 30 * 1000,
  });
}

export function fetchDataIntegrityDetailBySection(
  section: string,
  options?: {
    groupId?: string | null;
    accountId?: string | null;
    slaDays?: number;
    page?: number;
    pageSize?: number;
  }
): Promise<DataIntegrityDetailRow[]> {
  switch (section) {
    case "late_hr":
      return fetchDataIntegrityLateHrDetail(options);
    case "vacancy_delay":
      return fetchDataIntegrityVacancyDelayDetail(options);
    case "ghost_occupancy":
      return fetchDataIntegrityGhostOccupancyDetail(options);
    case "pipeline_no_vacancy":
      return fetchDataIntegrityPipelineNoVacancyDetail(options);
    default:
      return Promise.resolve([]);
  }
}

export function useDataIntegritySummary(groupId?: string | null, accountId?: string | null) {
  return useQuery({
    queryKey: ["reports", "data-integrity-summary", groupId, accountId],
    queryFn: () => fetchDataIntegritySummary(groupId, accountId),
    staleTime: 30 * 1000,
  });
}

export function useDataIntegrityDetail(
  section: string | null,
  options?: {
    groupId?: string | null;
    accountId?: string | null;
    slaDays?: number;
  },
  enabled = true
) {
  return useQuery({
    queryKey: ["reports", "data-integrity-detail", section, options],
    queryFn: () => fetchDataIntegrityDetailBySection(section!, options),
    enabled: Boolean(section && enabled),
    staleTime: 30 * 1000,
  });
}
