import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ---------------------------------------------------------------------------
// TypeScript Interfaces
// ---------------------------------------------------------------------------

export interface WorkforcePoolType {
  id: string;
  name: string;
  description?: string | null;
  code?: string | null;
  sortOrder: number;
}

export interface WorkforcePoolEmployee {
  id: string;
  employeeName: string;
  lastName?: string | null;
  firstName?: string | null;
  middleName?: string | null;
  employeeNo: string;
  emplocNo?: string | null;
  vcode?: string | null;
  poolTypeId: string;
  poolTypeName: string;
  poolTypeCode?: string | null;
  availabilityStatus: string;
  activeStoreCount: number;
  hasPendingRequest: boolean;
  needsReview: boolean;
  primaryDeploymentStore?: string | null;
  deploymentLoadLevel?: string | null; // low | medium | high | critical
  requestingAccount?: string | null;
  dateHired?: string | null;
  position?: string | null;
  homeAccount?: string | null;
  homeDeploymentType?: string | null;
  isGlobalVisible: boolean;
  taggedGroupName?: string | null;
  pendingRequestId?: string | null;
  pendingRequestedStore?: string | null;
}

export interface WorkforcePoolSummary {
  poolType: WorkforcePoolType;
  requiredHc: number;
  totalCount: number;
  availableCount: number;
  deployedCount: number;
  reviewCount: number;
  inactiveCount: number;
  vacantHc: number;
}

export interface WorkforceDeploymentItem {
  id: string;
  employeeId?: string | null;
  employeeName?: string | null;
  employeeNumber?: string | null;
  poolTypeName?: string | null;
  poolTypeCode?: string | null;
  accountName?: string | null;
  storeId?: string | null;
  storeName?: string | null;
  storeBranch?: string | null;
  groupName?: string | null;
  deploymentType?: string | null;
  status: string;
  priority: string;
  startDate?: string | null;
  endDate?: string | null;
  isPrimary: boolean;
  notes?: string | null;
  reviewLabel?: string | null;
  daysRemaining?: number | null;
  coveredPlantillaId?: string | null;
  endReason?: string | null;
  coveredVacancyVcode?: string | null;
  positionCovered?: string | null;
}

export interface WorkforcePendingRequest {
  id: string;
  employeeId?: string | null;
  employeeName?: string | null;
  employeeNumber?: string | null;
  poolType?: string | null;
  accountName?: string | null;
  storeName?: string | null;
  groupName?: string | null;
  requestedBy?: string | null;
  status: string;
  priority: string;
  requestDate?: string | null;
  startDate?: string | null;
  endDate?: string | null;
  reason?: string | null;
  ageDays?: number | null;
  escalationLevel?: string | null;
  notifyTargetRole?: string | null;
}

export interface WorkforceConversionRequest {
  id: string;
  employeeId: string;
  employeeName?: string | null;
  employeeNumber?: string | null;
  poolTypeName?: string | null;
  poolTypeCode?: string | null;
  vcode?: string | null;
  targetAccount?: string | null;
  targetStore?: string | null;
  targetPosition: string;
  effectiveDate: string;
  reason: string;
  notes?: string | null;
  status: string;
  requestedBy?: string | null;
  requestedByRole?: string | null;
  approvedBy?: string | null;
  approvedAt?: string | null;
  rejectedBy?: string | null;
  rejectedAt?: string | null;
  rejectionReason?: string | null;
  previousAccount?: string | null;
  previousStore?: string | null;
  previousPosition?: string | null;
  previousVcode?: string | null;
  activeAssignmentsClosed?: number | null;
  pendingRequestsCancelled?: number | null;
  createdAt?: string | null;
  ageDays?: number | null;
}

export interface WorkforceSlotReview {
  id: string;
  vcode: string;
  poolTypeId?: string | null;
  poolTypeName?: string | null;
  poolTypeCode?: string | null;
  triggerEvent: string;
  status: string;
  action?: string | null;
  reviewNotes?: string | null;
  previousEmployeeId?: string | null;
  previousEmployeeName?: string | null;
  previousEmployeeNumber?: string | null;
  previousPosition?: string | null;
  decidedAt?: string | null;
  createdAt?: string | null;
  reviewAgeDays?: number | null;
  slotId?: string | null;
  slotStatus?: string | null;
}

export interface PoolOpenSlot {
  id: string;
  vcode: string;
  poolTypeId?: string | null;
  poolTypeName?: string | null;
  poolTypeCode?: string | null;
  position?: string | null;
  account?: string | null;
  slotStatus: string;
  vacancyStatus?: string | null;
  createdAt?: string | null;
  daysOpen?: number | null;
}

export interface PoolRequestHistoryItem {
  id: string;
  poolTypeName?: string | null;
  poolTypeCode?: string | null;
  headcountNeeded: number;
  requestingAccount?: string | null;
  createdBy?: string | null;
  status: string;
  createdAt?: string | null;
  vcodes: string[];
  positionName?: string | null;
  isOpsRequest?: boolean;
  requestType?: string | null;
  operationalAccountName?: string | null;
}

export interface WorkforceEmployeeDetail {
  employee: WorkforcePoolEmployee;
  activeDeployments: WorkforceDeploymentItem[];
  assignmentHistory: WorkforceDeploymentItem[];
  reviewItems: WorkforceDeploymentItem[];
  pendingRequests: WorkforcePendingRequest[];
  conversionRequests: WorkforceConversionRequest[];
}

export interface RelieverCoverageRequestInput {
  employeeId: string;
  poolTypeId: string;
  requestedAccountId: string;
  requestedGroupId?: string | null;
  requestedStoreId: string;
  startDate: string;
  endDate: string;
  priority: string;
  reason: string;
  requestedPosition?: string | null;
}

export interface PoolConversionRequestInput {
  employeeId: string;
  targetAccountId: string;
  targetStoreId: string;
  position: string;
  effectiveDate: string;
  reason: string;
  notes?: string | null;
}

export interface PoolVacancyInput {
  poolTypeCode: string;
  positionId: string;
  requestingAccountId: string;
  requestingStoreId?: string | null;
  headcountNeeded: number;
  priority: string;
  reason?: string | null;
  requestType?: string;
  requestedProvince?: string | null;
  requestedCity?: string | null;
}

// ---------------------------------------------------------------------------
// Query Functions
// ---------------------------------------------------------------------------

export async function fetchPoolTypes(): Promise<WorkforcePoolType[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("workforce_pool_types")
    .select("*")
    .eq("is_active", true)
    .order("sort_order", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    console.error("[WorkforcePool] fetchPoolTypes error:", error);
    return [];
  }

  return (data ?? []).map((row) => ({
    id: String(row.id),
    name: String(row.name ?? row.pool_name ?? ""),
    description: row.description ? String(row.description) : null,
    code: row.code ?? row.pool_code ? String(row.code ?? row.pool_code) : null,
    sortOrder: Number(row.sort_order ?? 0),
  }));
}

export async function fetchPoolSummaries(): Promise<WorkforcePoolSummary[]> {
  const supabase = createClient();
  const types = await fetchPoolTypes();
  if (!types.length) return [];

  const [employeesRes, slotsRes] = await Promise.all([
    supabase.from("v_workforce_pool_employees").select("pool_type_id, availability_status, needs_review"),
    supabase.from("workforce_pool_slots").select("pool_type_id").eq("is_active", true).is("deleted_at", null),
  ]);

  if (employeesRes.error) {
    console.error("[WorkforcePool] fetchPoolSummaries employeesRes error:", employeesRes.error);
  }

  // Count slots per pool type (Required HC)
  const slotCounts: Record<string, number> = {};
  for (const s of slotsRes.data ?? []) {
    const tid = String(s.pool_type_id ?? "");
    if (tid) slotCounts[tid] = (slotCounts[tid] ?? 0) + 1;
  }

  // Count employees per pool type
  const empBuckets: Record<string, { total: number; available: number; deployed: number; review: number; inactive: number }> = {};
  for (const e of employeesRes.data ?? []) {
    const tid = String(e.pool_type_id ?? "");
    if (!tid) continue;
    if (!empBuckets[tid]) {
      empBuckets[tid] = { total: 0, available: 0, deployed: 0, review: 0, inactive: 0 };
    }
    const b = empBuckets[tid];
    b.total += 1;
    const status = String(e.availability_status ?? "").toLowerCase();
    const needsReview = Boolean(e.needs_review);

    if (status === "available") {
      b.available += 1;
    } else if (status === "deployed") {
      b.deployed += 1;
    } else if (status === "review" || needsReview) {
      b.review += 1;
    } else {
      b.inactive += 1;
    }
  }

  return types.map((t) => {
    const b = empBuckets[t.id] ?? { total: 0, available: 0, deployed: 0, review: 0, inactive: 0 };
    const req = slotCounts[t.id] ?? 0;
    const vacant = Math.max(0, req - b.total);
    return {
      poolType: t,
      requiredHc: req,
      totalCount: b.total,
      availableCount: b.available,
      deployedCount: b.deployed,
      reviewCount: b.review,
      inactiveCount: b.inactive,
      vacantHc: vacant,
    };
  });
}

export async function fetchPoolEmployees(params?: {
  poolTypeId?: string | null;
  availability?: string | null;
  search?: string | null;
}): Promise<WorkforcePoolEmployee[]> {
  const supabase = createClient();
  let query = supabase.from("v_workforce_pool_employees").select("*");

  if (params?.poolTypeId && params.poolTypeId !== "all") {
    query = query.eq("pool_type_id", params.poolTypeId);
  }

  if (params?.availability && params.availability !== "all") {
    const a = params.availability.toLowerCase();
    if (a === "available") {
      query = query.eq("availability_status", "Available");
    } else if (a === "deployed") {
      query = query.eq("availability_status", "Deployed");
    } else if (a === "review") {
      query = query.or("availability_status.eq.Review,needs_review.eq.true");
    } else if (a === "inactive") {
      query = query.in("availability_status", ["Inactive", "Resigned", "Terminated", "AWOL", "Suspended", "On Leave"]);
    }
  }

  if (params?.search && params.search.trim()) {
    const s = params.search.trim();
    query = query.or(`full_name.ilike.%${s}%,employee_name.ilike.%${s}%,employee_no.ilike.%${s}%,vcode.ilike.%${s}%,position.ilike.%${s}%,primary_deployment_store.ilike.%${s}%`);
  }

  const { data, error } = await query.order("full_name", { ascending: true });
  if (error) {
    console.error("[WorkforcePool] fetchPoolEmployees error:", error);
    throw error;
  }

  return (data ?? []).map((row) => ({
    id: String(row.employee_id ?? row.id ?? ""),
    employeeName: String(row.employee_name ?? row.full_name ?? ""),
    lastName: row.last_name ? String(row.last_name) : null,
    firstName: row.first_name ? String(row.first_name) : null,
    middleName: row.middle_name ? String(row.middle_name) : null,
    employeeNo: String(row.employee_no ?? row.employee_number ?? ""),
    emplocNo: row.emploc_no ? String(row.emploc_no) : null,
    vcode: row.vcode ? String(row.vcode) : null,
    poolTypeId: String(row.pool_type_id ?? ""),
    poolTypeName: String(row.pool_type_name ?? ""),
    poolTypeCode: row.pool_type_code ? String(row.pool_type_code) : null,
    availabilityStatus: String(row.availability_status ?? "Available"),
    activeStoreCount: Number(row.active_store_count ?? 0),
    hasPendingRequest: Boolean(row.has_pending_request),
    needsReview: Boolean(row.needs_review),
    primaryDeploymentStore: row.primary_deployment_store ? String(row.primary_deployment_store) : null,
    deploymentLoadLevel: row.deployment_load_level ? String(row.deployment_load_level) : null,
    requestingAccount: row.requesting_account ? String(row.requesting_account) : null,
    dateHired: row.date_hired ? String(row.date_hired) : null,
    position: row.position ? String(row.position) : null,
    homeAccount: row.home_account ? String(row.home_account) : null,
    homeDeploymentType: row.home_deployment_type ? String(row.home_deployment_type) : null,
    isGlobalVisible: Boolean(row.is_global_visible),
    taggedGroupName: row.tagged_group_name ? String(row.tagged_group_name) : null,
    pendingRequestId: row.pending_request_id ? String(row.pending_request_id) : null,
    pendingRequestedStore: row.pending_requested_store ? String(row.pending_requested_store) : null,
  }));
}

export async function fetchPoolEmployeeDetail(employeeId: string): Promise<WorkforceEmployeeDetail | null> {
  if (!employeeId) return null;
  const supabase = createClient();

  // Fetch employee record first
  const { data: empRow, error: empErr } = await supabase
    .from("v_workforce_pool_employees")
    .select("*")
    .eq("employee_id", employeeId)
    .maybeSingle();

  if (empErr || !empRow) {
    console.error("[WorkforcePool] fetchPoolEmployeeDetail empErr:", empErr);
    return null;
  }

  const employee: WorkforcePoolEmployee = {
    id: String(empRow.employee_id ?? empRow.id ?? ""),
    employeeName: String(empRow.employee_name ?? empRow.full_name ?? ""),
    lastName: empRow.last_name ? String(empRow.last_name) : null,
    firstName: empRow.first_name ? String(empRow.first_name) : null,
    middleName: empRow.middle_name ? String(empRow.middle_name) : null,
    employeeNo: String(empRow.employee_no ?? empRow.employee_number ?? ""),
    emplocNo: empRow.emploc_no ? String(empRow.emploc_no) : null,
    vcode: empRow.vcode ? String(empRow.vcode) : null,
    poolTypeId: String(empRow.pool_type_id ?? ""),
    poolTypeName: String(empRow.pool_type_name ?? ""),
    poolTypeCode: empRow.pool_type_code ? String(empRow.pool_type_code) : null,
    availabilityStatus: String(empRow.availability_status ?? "Available"),
    activeStoreCount: Number(empRow.active_store_count ?? 0),
    hasPendingRequest: Boolean(empRow.has_pending_request),
    needsReview: Boolean(empRow.needs_review),
    primaryDeploymentStore: empRow.primary_deployment_store ? String(empRow.primary_deployment_store) : null,
    deploymentLoadLevel: empRow.deployment_load_level ? String(empRow.deployment_load_level) : null,
    requestingAccount: empRow.requesting_account ? String(empRow.requesting_account) : null,
    dateHired: empRow.date_hired ? String(empRow.date_hired) : null,
    position: empRow.position ? String(empRow.position) : null,
    homeAccount: empRow.home_account ? String(empRow.home_account) : null,
    homeDeploymentType: empRow.home_deployment_type ? String(empRow.home_deployment_type) : null,
    isGlobalVisible: Boolean(empRow.is_global_visible),
    taggedGroupName: empRow.tagged_group_name ? String(empRow.tagged_group_name) : null,
    pendingRequestId: empRow.pending_request_id ? String(empRow.pending_request_id) : null,
    pendingRequestedStore: empRow.pending_requested_store ? String(empRow.pending_requested_store) : null,
  };

  // Parallel query for sub-tables
  const [activeDeploymentsRes, historyRes, reviewRes, pendingRes, conversionRes] = await Promise.all([
    supabase
      .from("v_workforce_store_temporary_coverage")
      .select("*")
      .eq("employee_id", employeeId)
      .order("is_primary", { ascending: false })
      .order("start_date", { ascending: false }),
    supabase
      .from("workforce_assignments")
      .select(`
        id, deployment_type, status, priority, start_date, end_date,
        is_primary, notes, covered_plantilla_id, end_reason,
        accounts:assigned_account_id(account_name),
        stores:assigned_store_id(store_name, store_branch),
        groups:assigned_group_id(group_name),
        covered_vacancy:covered_vacancy_id(vcode, position),
        covered_plantilla:covered_plantilla_id(position)
      `)
      .eq("employee_id", employeeId)
      .order("start_date", { ascending: false })
      .limit(15),
    supabase
      .from("v_workforce_assignment_review_queue")
      .select("*")
      .eq("employee_id", employeeId)
      .order("end_date", { ascending: true }),
    supabase
      .from("v_workforce_assignment_request_queue")
      .select("*")
      .eq("employee_id", employeeId)
      .in("status", ["Pending", "pending", "For Review", "for review"])
      .order("created_at", { ascending: false })
      .limit(5),
    supabase
      .from("v_workforce_pool_conversion_requests")
      .select("*")
      .eq("employee_id", employeeId)
      .order("created_at", { ascending: false })
      .limit(5),
  ]);

  const activeDeployments: WorkforceDeploymentItem[] = (activeDeploymentsRes.data ?? []).map((row) => ({
    id: String(row.assignment_id ?? row.id ?? ""),
    employeeId: row.employee_id ? String(row.employee_id) : null,
    employeeName: row.employee_name ? String(row.employee_name) : null,
    employeeNumber: row.employee_number ? String(row.employee_number) : null,
    poolTypeName: row.pool_type_name ? String(row.pool_type_name) : null,
    poolTypeCode: row.pool_type_code ? String(row.pool_type_code) : null,
    accountName: row.account_name ? String(row.account_name) : null,
    storeId: row.store_id ? String(row.store_id) : null,
    storeName: row.store_name ? String(row.store_name) : null,
    storeBranch: row.store_branch ? String(row.store_branch) : null,
    groupName: row.group_name ? String(row.group_name) : null,
    deploymentType: row.deployment_type ? String(row.deployment_type) : null,
    status: String(row.status ?? "Active"),
    priority: String(row.priority ?? "Normal"),
    startDate: row.start_date ? String(row.start_date) : null,
    endDate: row.end_date ? String(row.end_date) : null,
    isPrimary: Boolean(row.is_primary),
    coveredPlantillaId: row.covered_plantilla_id ? String(row.covered_plantilla_id) : null,
    endReason: row.end_reason ? String(row.end_reason) : null,
    coveredVacancyVcode: row.covered_vacancy_vcode ? String(row.covered_vacancy_vcode) : null,
    positionCovered: row.position_covered ? String(row.position_covered) : null,
  }));

  const assignmentHistory: WorkforceDeploymentItem[] = (historyRes.data ?? []).map((row) => {
    const acc = row.accounts as { account_name?: string } | null;
    const st = row.stores as { store_name?: string; store_branch?: string } | null;
    const grp = row.groups as { group_name?: string } | null;
    const vac = row.covered_vacancy as { vcode?: string; position?: string } | null;
    const plan = row.covered_plantilla as { position?: string } | null;
    return {
      id: String(row.id),
      accountName: acc?.account_name ? String(acc.account_name) : null,
      storeName: st?.store_name ? String(st.store_name) : null,
      storeBranch: st?.store_branch ? String(st.store_branch) : null,
      groupName: grp?.group_name ? String(grp.group_name) : null,
      deploymentType: row.deployment_type ? String(row.deployment_type) : null,
      status: String(row.status ?? "—"),
      priority: String(row.priority ?? "Normal"),
      startDate: row.start_date ? String(row.start_date) : null,
      endDate: row.end_date ? String(row.end_date) : null,
      isPrimary: Boolean(row.is_primary),
      notes: row.notes ? String(row.notes) : null,
      coveredPlantillaId: row.covered_plantilla_id ? String(row.covered_plantilla_id) : null,
      endReason: row.end_reason ? String(row.end_reason) : null,
      coveredVacancyVcode: vac?.vcode ? String(vac.vcode) : null,
      positionCovered: vac?.position ?? plan?.position ?? null,
    };
  });

  const reviewItems: WorkforceDeploymentItem[] = (reviewRes.data ?? []).map((row) => ({
    id: String(row.assignment_id ?? row.id ?? ""),
    employeeId: row.employee_id ? String(row.employee_id) : null,
    employeeName: row.employee_name ? String(row.employee_name) : null,
    employeeNumber: row.employee_number ? String(row.employee_number) : null,
    poolTypeName: row.pool_type_name ? String(row.pool_type_name) : null,
    poolTypeCode: row.pool_type_code ? String(row.pool_type_code) : null,
    accountName: row.account_name ? String(row.account_name) : null,
    storeName: row.store_name ? String(row.store_name) : null,
    status: String(row.status ?? "Review"),
    priority: String(row.priority ?? "Normal"),
    startDate: row.start_date ? String(row.start_date) : null,
    endDate: row.end_date ? String(row.end_date) : null,
    notes: row.notes ? String(row.notes) : null,
    reviewLabel: row.review_label ? String(row.review_label) : null,
    daysRemaining: row.days_remaining != null ? Number(row.days_remaining) : null,
    isPrimary: false,
  }));

  const pendingRequests: WorkforcePendingRequest[] = (pendingRes.data ?? []).map((row) => ({
    id: String(row.request_id ?? row.id ?? ""),
    employeeId: row.employee_id ? String(row.employee_id) : null,
    employeeName: row.employee_name ? String(row.employee_name) : null,
    employeeNumber: row.employee_number ? String(row.employee_number) : null,
    poolType: row.pool_type ? String(row.pool_type) : null,
    accountName: row.requested_account ? String(row.requested_account) : null,
    storeName: row.requested_store ? String(row.requested_store) : null,
    groupName: row.requested_group ? String(row.requested_group) : null,
    requestedBy: row.requested_by ? String(row.requested_by) : null,
    status: String(row.status ?? "Pending"),
    priority: String(row.priority ?? "Normal"),
    requestDate: row.created_at ? String(row.created_at) : null,
    startDate: row.start_date ? String(row.start_date) : null,
    endDate: row.end_date ? String(row.end_date) : null,
    reason: row.reason ? String(row.reason) : null,
    ageDays: row.request_age_days != null ? Number(row.request_age_days) : null,
    escalationLevel: row.escalation_level ? String(row.escalation_level) : null,
    notifyTargetRole: row.notify_target_role ? String(row.notify_target_role) : null,
  }));

  const conversionRequests: WorkforceConversionRequest[] = (conversionRes.data ?? []).map((row) => ({
    id: String(row.request_id ?? row.id ?? ""),
    employeeId: String(row.employee_id ?? ""),
    employeeName: row.employee_name ? String(row.employee_name) : null,
    employeeNumber: row.employee_number ? String(row.employee_number) : null,
    poolTypeName: row.pool_type_name ? String(row.pool_type_name) : null,
    poolTypeCode: row.pool_type_code ? String(row.pool_type_code) : null,
    vcode: row.vcode ? String(row.vcode) : null,
    targetAccount: row.target_account ? String(row.target_account) : null,
    targetStore: row.target_store ? String(row.target_store) : null,
    targetPosition: String(row.target_position ?? ""),
    effectiveDate: String(row.effective_date ?? ""),
    reason: String(row.reason ?? ""),
    notes: row.notes ? String(row.notes) : null,
    status: String(row.status ?? "Pending"),
    requestedBy: row.requested_by_name ? String(row.requested_by_name) : null,
    requestedByRole: row.requested_by_role ? String(row.requested_by_role) : null,
    approvedBy: row.approved_by_name ? String(row.approved_by_name) : null,
    approvedAt: row.approved_at ? String(row.approved_at) : null,
    rejectedBy: row.rejected_by_name ? String(row.rejected_by_name) : null,
    rejectedAt: row.rejected_at ? String(row.rejected_at) : null,
    rejectionReason: row.rejection_reason ? String(row.rejection_reason) : null,
    previousAccount: row.previous_account ? String(row.previous_account) : null,
    previousStore: row.previous_store ? String(row.previous_store) : null,
    previousPosition: row.previous_position ? String(row.previous_position) : null,
    previousVcode: row.previous_vcode ? String(row.previous_vcode) : null,
    activeAssignmentsClosed: row.active_assignments_closed != null ? Number(row.active_assignments_closed) : null,
    pendingRequestsCancelled: row.pending_requests_cancelled != null ? Number(row.pending_requests_cancelled) : null,
    createdAt: row.created_at ? String(row.created_at) : null,
    ageDays: row.request_age_days != null ? Number(row.request_age_days) : null,
  }));

  return {
    employee,
    activeDeployments,
    assignmentHistory,
    reviewItems,
    pendingRequests,
    conversionRequests,
  };
}

export async function fetchOpenPoolSlots(poolTypeId?: string | null): Promise<PoolOpenSlot[]> {
  const supabase = createClient();
  let query = supabase
    .from("workforce_pool_slots")
    .select(`
      id, vcode, pool_type_id, status, created_at, account,
      vacancies:vacancy_id(status, position),
      workforce_pool_types:pool_type_id(name, code)
    `)
    .eq("status", "open")
    .is("deleted_at", null)
    .eq("is_active", true);

  if (poolTypeId && poolTypeId !== "all") {
    query = query.eq("pool_type_id", poolTypeId);
  }

  const { data, error } = await query.order("created_at", { ascending: false });
  if (error) {
    console.error("[WorkforcePool] fetchOpenPoolSlots error:", error);
    return [];
  }

  return (data ?? []).map((row) => {
    const vac = row.vacancies as { status?: string; position?: string } | null;
    const pt = row.workforce_pool_types as { name?: string; code?: string } | null;
    return {
      id: String(row.id),
      vcode: String(row.vcode ?? ""),
      poolTypeId: row.pool_type_id ? String(row.pool_type_id) : null,
      poolTypeName: pt?.name ? String(pt.name) : null,
      poolTypeCode: pt?.code ? String(pt.code) : null,
      position: vac?.position ? String(vac.position) : null,
      account: row.account ? String(row.account) : null,
      slotStatus: String(row.status ?? "open"),
      vacancyStatus: vac?.status ? String(vac.status) : null,
      createdAt: row.created_at ? String(row.created_at) : null,
      daysOpen: row.created_at
        ? Math.floor((Date.now() - new Date(row.created_at).getTime()) / (1000 * 60 * 60 * 24))
        : null,
    };
  });
}

export async function fetchSlotReviewQueue(): Promise<WorkforceSlotReview[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("v_workforce_slot_reviews")
    .select("*")
    .in("status", ["Pending", "Resolved"])
    .order("created_at", { ascending: true });

  if (error) {
    console.error("[WorkforcePool] fetchSlotReviewQueue error:", error);
    return [];
  }

  return (data ?? []).map((row) => ({
    id: String(row.review_id ?? row.id ?? ""),
    vcode: String(row.vcode ?? ""),
    poolTypeId: row.pool_type_id ? String(row.pool_type_id) : null,
    poolTypeName: row.pool_type_name ? String(row.pool_type_name) : null,
    poolTypeCode: row.pool_type_code ? String(row.pool_type_code) : null,
    triggerEvent: String(row.trigger_event ?? ""),
    status: String(row.status ?? "Pending"),
    action: row.action ? String(row.action) : null,
    reviewNotes: row.review_notes ? String(row.review_notes) : null,
    previousEmployeeId: row.previous_employee_id ? String(row.previous_employee_id) : null,
    previousEmployeeName: row.previous_employee_name ? String(row.previous_employee_name) : null,
    previousEmployeeNumber: row.previous_employee_number ? String(row.previous_employee_number) : null,
    previousPosition: row.previous_position ? String(row.previous_position) : null,
    decidedAt: row.decided_at ? String(row.decided_at) : null,
    createdAt: row.created_at ? String(row.created_at) : null,
    reviewAgeDays: row.review_age_days != null ? Number(row.review_age_days) : null,
    slotId: row.slot_id ? String(row.slot_id) : null,
    slotStatus: row.slot_status ? String(row.slot_status) : null,
  }));
}

export async function fetchPoolRequestHistory(): Promise<PoolRequestHistoryItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("workforce_pool_requests")
    .select(`
      id, headcount_needed, requesting_account, created_by_name, approved_by,
      created_by, status, created_at, position_name, is_ops_request,
      request_type, operational_account_name,
      workforce_pool_types:pool_type_id(name, code),
      workforce_pool_request_items:request_id(vcode)
    `)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(100);

  if (error) {
    console.error("[WorkforcePool] fetchPoolRequestHistory error:", error);
    return [];
  }

  return (data ?? []).map((row) => {
    const pt = row.workforce_pool_types as { name?: string; code?: string } | null;
    const items = (row.workforce_pool_request_items as { vcode?: string }[] | null) ?? [];
    return {
      id: String(row.id),
      poolTypeName: pt?.name ? String(pt.name) : null,
      poolTypeCode: pt?.code ? String(pt.code) : null,
      headcountNeeded: Number(row.headcount_needed ?? 1),
      requestingAccount: row.requesting_account ? String(row.requesting_account) : null,
      createdBy: String(row.created_by_name ?? row.approved_by ?? row.created_by ?? "—"),
      status: String(row.status ?? "approved"),
      createdAt: row.created_at ? String(row.created_at) : null,
      vcodes: items.map((i) => String(i.vcode ?? "")).filter(Boolean),
      positionName: row.position_name ? String(row.position_name) : null,
      isOpsRequest: Boolean(row.is_ops_request),
      requestType: row.request_type ? String(row.request_type) : null,
      operationalAccountName: row.operational_account_name ? String(row.operational_account_name) : null,
    };
  });
}

export async function fetchPoolPositions(): Promise<{ id: string; name: string }[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("positions")
    .select("id, position_name, pool_sort_order")
    .eq("is_pool_position", true)
    .eq("is_active", true)
    .order("pool_sort_order", { ascending: true, nullsFirst: false })
    .order("position_name", { ascending: true });

  if (error) {
    console.error("[WorkforcePool] fetchPoolPositions error:", error);
    return [];
  }

  return (data ?? []).map((r) => ({
    id: String(r.id),
    name: String(r.position_name ?? ""),
  }));
}

// ---------------------------------------------------------------------------
// TanStack Query Hooks
// ---------------------------------------------------------------------------

export function useWorkforcePoolTypes() {
  return useQuery({
    queryKey: ["workforce", "pool-types"],
    queryFn: fetchPoolTypes,
    staleTime: 60000,
  });
}

export function useWorkforcePoolSummaries() {
  return useQuery({
    queryKey: ["workforce", "pool-summaries"],
    queryFn: fetchPoolSummaries,
    staleTime: 30000,
  });
}

export function useWorkforcePoolEmployees(params?: {
  poolTypeId?: string | null;
  availability?: string | null;
  search?: string | null;
}) {
  return useQuery({
    queryKey: ["workforce", "employees", params],
    queryFn: () => fetchPoolEmployees(params),
    staleTime: 15000,
  });
}

export function useWorkforcePoolEmployeeDetail(employeeId: string | null) {
  return useQuery({
    queryKey: ["workforce", "employee-detail", employeeId],
    queryFn: () => (employeeId ? fetchPoolEmployeeDetail(employeeId) : null),
    enabled: Boolean(employeeId),
    staleTime: 15000,
  });
}

export function useOpenPoolSlots(poolTypeId?: string | null) {
  return useQuery({
    queryKey: ["workforce", "open-slots", poolTypeId],
    queryFn: () => fetchOpenPoolSlots(poolTypeId),
    staleTime: 30000,
  });
}

export function useSlotReviewQueue() {
  return useQuery({
    queryKey: ["workforce", "slot-reviews"],
    queryFn: fetchSlotReviewQueue,
    staleTime: 30000,
  });
}

export function usePoolRequestHistory() {
  return useQuery({
    queryKey: ["workforce", "request-history"],
    queryFn: fetchPoolRequestHistory,
    staleTime: 30000,
  });
}

export function usePoolPositions() {
  return useQuery({
    queryKey: ["workforce", "pool-positions"],
    queryFn: fetchPoolPositions,
    staleTime: 60000,
  });
}

// ---------------------------------------------------------------------------
// Mutation Hooks
// ---------------------------------------------------------------------------

export function useRequestRelieverCoverage() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: RelieverCoverageRequestInput) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("request_reliever_coverage", {
        p_employee_id: input.employeeId,
        p_pool_type_id: input.poolTypeId,
        p_requested_account_id: input.requestedAccountId,
        p_requested_group_id: input.requestedGroupId || null,
        p_requested_store_id: input.requestedStoreId,
        p_start_date: input.startDate,
        p_end_date: input.endDate,
        p_priority: input.priority,
        p_reason: input.reason,
        p_requested_position: input.requestedPosition || null,
      });

      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useRequestPoolConversion() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: PoolConversionRequestInput) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("request_pool_conversion", {
        p_employee_id: input.employeeId,
        p_target_account_id: input.targetAccountId,
        p_target_store_id: input.targetStoreId,
        p_position: input.position,
        p_effective_date: input.effectiveDate,
        p_reason: input.reason,
        p_notes: input.notes || null,
      });

      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useApprovePoolConversion() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ requestId, notes }: { requestId: string; notes?: string }) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("approve_pool_conversion", {
        p_request_id: requestId,
        p_notes: notes || null,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useRejectPoolConversion() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ requestId, reason }: { requestId: string; reason: string }) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("reject_pool_conversion", {
        p_request_id: requestId,
        p_reason: reason,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useWithdrawRelieverCoverage() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ requestId, reason }: { requestId: string; reason?: string }) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("withdraw_reliever_coverage_request", {
        p_request_id: requestId,
        p_reason: reason || "Withdrawn by user",
      });
      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
    },
  });
}

export function useCloseWorkforceAssignment() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ assignmentId, notes }: { assignmentId: string; notes?: string }) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("close_workforce_assignment", {
        p_assignment_id: assignmentId,
        p_notes: notes || null,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useCreatePoolVacancy() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: PoolVacancyInput) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("create_pool_vacancy", {
        p_pool_type_code: input.poolTypeCode,
        p_position_id: input.positionId,
        p_requesting_account_id: input.requestingAccountId,
        p_requesting_store_id: input.requestingStoreId || null,
        p_headcount_needed: input.headcountNeeded,
        p_priority: input.priority,
        p_reason: input.reason || null,
        p_request_type: input.requestType || "Additional",
        p_province: input.requestedProvince || null,
        p_city: input.requestedCity || null,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

export function useReopenPoolSlotReview() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ reviewId, notes }: { reviewId: string; notes?: string }) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("reopen_pool_slot_review", {
        p_review_id: reviewId,
        p_notes: notes || null,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
    },
  });
}

export function useClosePoolSlotReview() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ reviewId, notes }: { reviewId: string; notes?: string }) => {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("close_pool_slot_review", {
        p_review_id: reviewId,
        p_notes: notes || null,
      });
      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["workforce"] });
    },
  });
}
