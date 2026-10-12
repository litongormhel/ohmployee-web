import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export type RequestCategoryKey =
  | "new_stores"
  | "headcount"
  | "coverage"
  | "vacancy_closures"
  | "hr_emploc_deletions"
  | "deactivations"
  | "applicant_movements"
  | "account_group_transfers";

export interface RequestCategoryConfig {
  key: RequestCategoryKey;
  label: string;
  description: string;
  tableName: string;
}

export const REQUEST_CATEGORIES: RequestCategoryConfig[] = [
  {
    key: "new_stores",
    label: "New Stores",
    description: "Store registry additions and branch onboarding requests",
    tableName: "new_store_requests",
  },
  {
    key: "headcount",
    label: "Headcount",
    description: "Quota amendments, replacements, relievers, and capacity expansions",
    tableName: "headcount_requests",
  },
  {
    key: "coverage",
    label: "Coverage",
    description: "Roving store allocation groups and roving schedule requests",
    tableName: "coverage_requests",
  },
  {
    key: "vacancy_closures",
    label: "Vacancy Closures",
    description: "Position requisition retirement and closed-slot clearance requests",
    tableName: "vacancy_closure_requests",
  },
  {
    key: "hr_emploc_deletions",
    label: "HR Emploc Deletions",
    description: "Employee location link and assignment expungement requests",
    tableName: "hr_emploc_deletion_requests",
  },
  {
    key: "deactivations",
    label: "Deactivations",
    description: "Employee separation clearance, backouts, and deactivation requests",
    tableName: "v_deactivation_requests",
  },
  {
    key: "applicant_movements",
    label: "Applicant Movements",
    description: "Cross-store applicant transfers, swap approvals, and slot reassignment",
    tableName: "applicant_movement_requests",
  },
  {
    key: "account_group_transfers",
    label: "Account Group Transfers",
    description: "Account reassignments across operational management groups",
    tableName: "account_group_transfer_requests",
  },
];

export type RequestCategoryCounts = Record<RequestCategoryKey, number>;

export type HeadcountRequestItem = {
  id: string;
  requestType: string;
  isQuotaAmendment: boolean;
  targetVcode: string | null;
  previousTarget: number | null;
  proposedTarget: number | null;
  delta: number | null;
  isExpansion: boolean;
  isReduction: boolean;
  headcountNeeded: number;
  reason: string | null;
  urgency: string | null;
  status: string;
  accountId: string | null;
  storeId: string | null;
  positionId: string | null;
  storeName: string | null;
  accountName: string | null;
  positionName: string | null;
  groupName: string | null;
  requestedByName: string | null;
  requestedByRole: string | null;
  requestedAt: string | null;
  createdAt: string;
  workforceType: string | null;
  employmentType: string | null;
};

export type RequestErrorKind = "unauthorized" | "validation" | "not_found" | "generic";

export class RequestDataError extends Error {
  kind: RequestErrorKind;

  constructor(kind: RequestErrorKind, message: string) {
    super(message);
    this.name = "RequestDataError";
    this.kind = kind;
  }
}

/**
 * Fetches live pending request counts across all 8 module categories.
 * Fails safely per category so blocked tables return 0 rather than crashing.
 */
export async function fetchRequestCategoryCounts(): Promise<RequestCategoryCounts> {
  const supabase = createClient();

  const results: RequestCategoryCounts = {
    new_stores: 0,
    headcount: 0,
    coverage: 0,
    vacancy_closures: 0,
    hr_emploc_deletions: 0,
    deactivations: 0,
    applicant_movements: 0,
    account_group_transfers: 0,
  };

  const countItem = async (
    key: RequestCategoryKey,
    queryPromise: PromiseLike<{ count: number | null }>
  ): Promise<{ key: RequestCategoryKey; count: number }> => {
    try {
      const res = await queryPromise;
      return { key, count: res.count ?? 0 };
    } catch {
      return { key, count: 0 };
    }
  };

  const countPromises = [
    // 1. New Stores
    countItem(
      "new_stores",
      supabase
        .from("new_store_requests")
        .select("id", { count: "exact", head: true })
        .ilike("status", "pending")
    ),

    // 2. Headcount
    countItem(
      "headcount",
      supabase
        .from("headcount_requests")
        .select("id", { count: "exact", head: true })
        .or("status.ilike.pending,status.ilike.under_review")
    ),

    // 3. Coverage & Reliever Endorsements
    (async () => {
      try {
        const [covRes, relieverRes] = await Promise.all([
          supabase
            .from("coverage_requests")
            .select("id", { count: "exact", head: true })
            .or("status.ilike.pending,status.ilike.draft"),
          supabase
            .from("v_workforce_assignment_request_queue")
            .select("request_id", { count: "exact", head: true })
            .in("status", ["Pending", "pending", "For Review", "for review"]),
        ]);
        const total = (covRes.count ?? 0) + (relieverRes.count ?? 0);
        return { key: "coverage" as RequestCategoryKey, count: total };
      } catch {
        return { key: "coverage" as RequestCategoryKey, count: 0 };
      }
    })(),

    // 4. Vacancy Closures
    countItem(
      "vacancy_closures",
      supabase
        .from("vacancy_closure_requests")
        .select("id", { count: "exact", head: true })
        .ilike("status", "pending")
    ),

    // 5. HR Emploc Deletions
    countItem(
      "hr_emploc_deletions",
      supabase
        .from("hr_emploc_deletion_requests")
        .select("id", { count: "exact", head: true })
        .ilike("status", "pending")
    ),

    // 6. Deactivations
    countItem(
      "deactivations",
      supabase
        .from("v_deactivation_requests")
        .select("id", { count: "exact", head: true })
        .ilike("status", "pending")
    ),

    // 7. Applicant Movements
    countItem(
      "applicant_movements",
      supabase
        .from("applicant_movement_requests")
        .select("id", { count: "exact", head: true })
        .ilike("status", "pending")
    ),

    // 8. Account Group Transfers
    countItem(
      "account_group_transfers",
      supabase
        .from("account_group_transfer_requests")
        .select("id", { count: "exact", head: true })
        .ilike("status", "pending")
    ),
  ];

  const settled = await Promise.all(countPromises);
  for (const item of settled) {
    results[item.key] = item.count;
  }

  return results;
}

/**
 * Fetches pending headcount requests including quota amendment requests.
 */
export async function fetchPendingHeadcountRequests(): Promise<HeadcountRequestItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("headcount_requests")
    .select(`
      id,
      request_type,
      status,
      target_vcode,
      previous_target,
      proposed_target,
      headcount_needed,
      reason,
      urgency,
      account_id,
      store_id,
      position_id,
      account_name_snapshot,
      store_name_snapshot,
      position_name_snapshot,
      group_name_snapshot,
      requested_by_name,
      requested_by_role,
      requested_at,
      created_at,
      workforce_type,
      employment_type
    `)
    .or("status.ilike.pending,status.ilike.under_review")
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError("unauthorized", "Unauthorized: Scoped access restricted.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return (data ?? []).map((row) => {
    const rawType = (row.request_type ?? "").trim();
    const isQuotaAmendment =
      rawType.toLowerCase().includes("quota") ||
      rawType.toLowerCase().includes("amendment") ||
      !!row.target_vcode;

    const previousTarget =
      row.previous_target !== null && row.previous_target !== undefined
        ? Number(row.previous_target)
        : null;

    const proposedTarget =
      row.proposed_target !== null && row.proposed_target !== undefined
        ? Number(row.proposed_target)
        : null;

    let delta: number | null = null;
    let isExpansion = false;
    let isReduction = false;

    if (previousTarget !== null && proposedTarget !== null) {
      delta = proposedTarget - previousTarget;
      isExpansion = delta > 0;
      isReduction = delta < 0;
    }

    return {
      id: row.id,
      requestType: rawType || (isQuotaAmendment ? "Quota Amendment" : "Additional Headcount"),
      isQuotaAmendment,
      targetVcode: row.target_vcode ?? null,
      previousTarget,
      proposedTarget,
      delta,
      isExpansion,
      isReduction,
      headcountNeeded: Number(row.headcount_needed ?? 1),
      reason: row.reason ?? null,
      urgency: row.urgency ?? null,
      status: row.status ?? "pending",
      accountId: row.account_id ?? null,
      storeId: row.store_id ?? null,
      positionId: row.position_id ?? null,
      storeName: row.store_name_snapshot ?? null,
      accountName: row.account_name_snapshot ?? null,
      positionName: row.position_name_snapshot ?? null,
      groupName: row.group_name_snapshot ?? null,
      requestedByName: row.requested_by_name ?? null,
      requestedByRole: row.requested_by_role ?? null,
      requestedAt: row.requested_at ?? row.created_at,
      createdAt: row.created_at,
      workforceType: row.workforce_type ?? null,
      employmentType: row.employment_type ?? null,
    };
  });
}

export type ApproveHeadcountParams = {
  requestId: string;
  remarks?: string;
  isQuotaAmendment?: boolean;
};

export type RejectHeadcountParams = {
  requestId: string;
  remarks?: string;
};

/**
 * Approves a headcount request in-place.
 * For Quota Amendments, executes approve_headcount_amendment_request which triggers authoritative quota revision.
 * For standard requests, executes approve_headcount_request.
 */
export async function approveHeadcountRequest({
  requestId,
  remarks,
  isQuotaAmendment,
}: ApproveHeadcountParams) {
  const supabase = createClient();
  const trimmedRemarks = remarks?.trim() || "";

  if (isQuotaAmendment) {
    const { data, error } = await supabase.rpc("approve_headcount_amendment_request", {
      p_request_id: requestId,
      p_remarks: trimmedRemarks,
    });

    if (error) {
      if (error.code === "42501") {
        throw new RequestDataError(
          "unauthorized",
          error.message || "Unauthorized: Only Data Team and Admin roles may approve quota amendments.",
        );
      }
      if (error.code === "22023") {
        throw new RequestDataError("validation", error.message);
      }
      if (error.code === "P0002") {
        throw new RequestDataError("not_found", error.message || "Headcount request not found.");
      }
      throw new RequestDataError("generic", error.message);
    }

    return data;
  }

  // Standard Headcount request approval
  const { data, error } = await supabase.rpc("approve_headcount_request", {
    p_request_id: requestId,
    p_remarks: trimmedRemarks,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        error.message || "Unauthorized: Only Administrators may approve headcount requests.",
      );
    }
    throw new RequestDataError("generic", error.message);
  }

  return data;
}

/**
 * Rejects a headcount request in-place.
 * Executes reject_headcount_request RPC.
 */
export async function rejectHeadcountRequest({
  requestId,
  remarks,
}: RejectHeadcountParams) {
  const supabase = createClient();
  const trimmedRemarks = remarks?.trim() || "";

  const { data, error } = await supabase.rpc("reject_headcount_request", {
    p_request_id: requestId,
    p_remarks: trimmedRemarks,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        error.message || "Unauthorized: Only Administrators may reject requests.",
      );
    }
    throw new RequestDataError("generic", error.message);
  }

  return data;
}

// ─── React Query Hooks ───────────────────────────────────────────────────────

export function useRequestCategoryCounts() {
  return useQuery({
    queryKey: ["request-category-counts"],
    queryFn: () => fetchRequestCategoryCounts(),
    refetchInterval: 30000, // 30s polling
  });
}

export function usePendingHeadcountRequests() {
  return useQuery({
    queryKey: ["pending-headcount-requests"],
    queryFn: () => fetchPendingHeadcountRequests(),
  });
}

export function useApproveHeadcountRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ApproveHeadcountParams) => approveHeadcountRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["pending-headcount-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-detail"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["quota-details"] });
      queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
    },
  });
}

export function useRejectHeadcountRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RejectHeadcountParams) => rejectHeadcountRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["pending-headcount-requests"] });
      queryClient.invalidateQueries({ queryKey: ["quota-details"] });
    },
  });
}

// ─── New Store Requests ──────────────────────────────────────────────────────

export type NewStoreRequestItem = {
  id: string;
  storeName: string;
  province: string;
  city: string;
  accountId: string;
  accountName: string;
  groupId: string | null;
  groupName: string | null;
  position: string | null;
  requestedHc: number | null;
  reason: string;
  status: string;
  requestedBy: string;
  requestedByName: string;
  requestedAt: string;
  reviewedBy: string | null;
  reviewedByName: string | null;
  reviewedAt: string | null;
  reviewReason: string | null;
  createdAt: string;
};

export type ApproveNewStoreParams = {
  requestId: string;
};

export type RejectNewStoreParams = {
  requestId: string;
  reason: string;
};

interface NewStoreDbRow {
  id: string;
  store_name: string;
  province: string;
  city: string;
  account_id: string;
  account_name: string;
  group_id: string | null;
  position: string | null;
  requested_hc: number | null;
  reason: string;
  status: string;
  requested_by: string;
  requested_by_name: string;
  requested_at: string;
  reviewed_by: string | null;
  reviewed_by_name: string | null;
  reviewed_at: string | null;
  review_reason: string | null;
  created_at: string;
  groups?: {
    group_name: string | null;
  } | null;
}

export async function fetchPendingNewStoreRequests(): Promise<NewStoreRequestItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("new_store_requests")
    .select(`
      id,
      store_name,
      province,
      city,
      account_id,
      account_name,
      group_id,
      position,
      requested_hc,
      reason,
      status,
      requested_by,
      requested_by_name,
      requested_at,
      reviewed_by,
      reviewed_by_name,
      reviewed_at,
      review_reason,
      created_at,
      groups:group_id (
        group_name
      )
    `)
    .ilike("status", "pending")
    .eq("is_archived", false)
    .order("requested_at", { ascending: false });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError("unauthorized", "Unauthorized: Scoped access restricted.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return ((data as unknown as NewStoreDbRow[]) ?? []).map((row: NewStoreDbRow) => ({
    id: row.id,
    storeName: row.store_name,
    province: row.province,
    city: row.city,
    accountId: row.account_id,
    accountName: row.account_name,
    groupId: row.group_id ?? null,
    groupName: row.groups?.group_name ?? null,
    position: row.position ?? null,
    requestedHc: row.requested_hc ?? null,
    reason: row.reason,
    status: row.status,
    requestedBy: row.requested_by,
    requestedByName: row.requested_by_name,
    requestedAt: row.requested_at,
    reviewedBy: row.reviewed_by ?? null,
    reviewedByName: row.reviewed_by_name ?? null,
    reviewedAt: row.reviewed_at ?? null,
    reviewReason: row.review_reason ?? null,
    createdAt: row.created_at,
  }));
}

export async function approveNewStoreRequest({ requestId }: ApproveNewStoreParams) {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("approve_new_store_request", {
    p_request_id: requestId,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        error.message || "Unauthorized: Only Head Admin or Super Admin may approve new store requests."
      );
    }
    if (error.code === "P0001" || error.code === "22023") {
      throw new RequestDataError("validation", error.message);
    }
    if (error.code === "P0002") {
      throw new RequestDataError("not_found", error.message || "New store request not found.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return data;
}

export async function rejectNewStoreRequest({ requestId, reason }: RejectNewStoreParams) {
  const supabase = createClient();
  const trimmedReason = reason.trim();
  if (!trimmedReason) {
    throw new RequestDataError("validation", "A rejection reason is required.");
  }

  const { data, error } = await supabase.rpc("reject_new_store_request", {
    p_request_id: requestId,
    p_reason: trimmedReason,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        error.message || "Unauthorized: Only Head Admin or Super Admin may reject new store requests."
      );
    }
    if (error.code === "P0001" || error.code === "22023") {
      throw new RequestDataError("validation", error.message);
    }
    if (error.code === "P0002") {
      throw new RequestDataError("not_found", error.message || "New store request not found.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return data;
}

export function usePendingNewStoreRequests() {
  return useQuery({
    queryKey: ["pending-new-store-requests"],
    queryFn: () => fetchPendingNewStoreRequests(),
  });
}

export function useApproveNewStoreRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ApproveNewStoreParams) => approveNewStoreRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["pending-new-store-requests"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
    },
  });
}

export function useRejectNewStoreRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RejectNewStoreParams) => rejectNewStoreRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["pending-new-store-requests"] });
    },
  });
}

// ─── Vacancy Closures ────────────────────────────────────────────────────────

export type VacancyClosureRequestItem = {
  id: string;
  vacancyVcode: string;
  reason: string;
  details: string | null;
  requestedBy: string;
  requestedByUserId: string | null;
  status: string;
  reviewedBy: string | null;
  reviewedAt: string | null;
  reviewerRemarks: string | null;
  createdAt: string;
  storeName: string | null;
  storeBranch: string | null;
  position: string | null;
  account: string | null;
};

export type ReviewVacancyClosureParams = {
  requestId: string;
  status: "Approved" | "Rejected";
  reviewedBy: string;
  remarks?: string;
};

interface VacancyClosureDbRow {
  id: string;
  vacancy_vcode: string;
  reason: string;
  details: string | null;
  requested_by: string;
  requested_by_user_id: string | null;
  status: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
  reviewer_remarks: string | null;
  created_at: string;
  vacancies?: {
    store_name: string | null;
    store_branch: string | null;
    position: string | null;
    account: string | null;
  } | null;
}

export async function fetchPendingVacancyClosureRequests(): Promise<VacancyClosureRequestItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("vacancy_closure_requests")
    .select(`
      id,
      vacancy_vcode,
      reason,
      details,
      requested_by,
      requested_by_user_id,
      status,
      reviewed_by,
      reviewed_at,
      reviewer_remarks,
      created_at,
      vacancies:vacancy_vcode (
        store_name,
        store_branch,
        position,
        account
      )
    `)
    .ilike("status", "pending")
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError("unauthorized", "Unauthorized: Scoped access restricted.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return ((data as unknown as VacancyClosureDbRow[]) ?? []).map((row: VacancyClosureDbRow) => {
    const vac = row.vacancies;
    return {
      id: row.id,
      vacancyVcode: row.vacancy_vcode,
      reason: row.reason,
      details: row.details ?? null,
      requestedBy: row.requested_by,
      requestedByUserId: row.requested_by_user_id ?? null,
      status: row.status,
      reviewedBy: row.reviewed_by ?? null,
      reviewedAt: row.reviewed_at ?? null,
      reviewerRemarks: row.reviewer_remarks ?? null,
      createdAt: row.created_at,
      storeName: vac?.store_name ?? null,
      storeBranch: vac?.store_branch ?? null,
      position: vac?.position ?? null,
      account: vac?.account ?? null,
    };
  });
}

export async function reviewVacancyClosureRequest({
  requestId,
  status,
  reviewedBy,
  remarks,
}: ReviewVacancyClosureParams) {
  const supabase = createClient();
  const trimmedRemarks = remarks?.trim() || null;

  const { data, error } = await supabase.rpc("review_vacancy_closure_request", {
    p_request_id: requestId,
    p_status: status,
    p_reviewed_by: reviewedBy,
    p_remarks: trimmedRemarks,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        error.message || "Unauthorized: Insufficient permissions to review closure request."
      );
    }
    if (error.code === "P0001" || error.code === "22023" || error.code === "23514") {
      throw new RequestDataError("validation", error.message);
    }
    if (error.code === "P0002") {
      throw new RequestDataError("not_found", error.message || "Vacancy closure request not found.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return data;
}

export async function approveAllVacancyClosureRequests() {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("approve_all_vacancy_closure_requests");

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        error.message || "Unauthorized: Only Super Admin, Head Admin, or Encoder can bulk approve closure requests."
      );
    }
    throw new RequestDataError("generic", error.message);
  }

  return data as { approved_count: number; skipped_count: number };
}

export function usePendingVacancyClosureRequests() {
  return useQuery({
    queryKey: ["pending-vacancy-closure-requests"],
    queryFn: () => fetchPendingVacancyClosureRequests(),
  });
}

export function useReviewVacancyClosureRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ReviewVacancyClosureParams) => reviewVacancyClosureRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["pending-vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["quota-details"] });
    },
  });
}

export function useApproveAllVacancyClosures() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: () => approveAllVacancyClosureRequests(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["pending-vacancy-closure-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-summary"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["quota-details"] });
    },
  });
}

// ─── Applicant Movement Requests (AMR) ───────────────────────────────────────

export type ApplicantMovementType = "TRANSFER" | "SWAP";
export type ApplicantMovementStatus = "pending" | "approved" | "rejected" | "withdrawn";

export interface ApplicantMovementRequestItem {
  id: string;
  requestNumber: string;
  movementType: ApplicantMovementType;
  status: ApplicantMovementStatus;
  approvalStage: string | null;
  // Source info
  sourceApplicantId: string;
  sourceApplicantName: string;
  sourceApplicantStatus: string | null;
  sourceVacancyVcode: string;
  sourceStoreName: string | null;
  sourcePosition: string | null;
  sourceAccountName: string | null;
  // Target info
  targetVacancyVcode: string;
  targetStoreName: string | null;
  targetPosition: string | null;
  targetAccountName: string | null;
  // SWAP target applicant
  targetApplicantId: string | null;
  targetApplicantName: string | null;
  targetApplicantStatus: string | null;
  // Metadata & Justification
  reason: string;
  remarks: string | null;
  requestedBy: string;
  requestedByName: string;
  requestedByRole: string;
  requestedAt: string;
  createdAt: string;
  effectiveDate: string | null;
  hasActiveReservation: boolean;
  executionError: string | null;
}

export type ApproveApplicantMovementParams = {
  requestId: string;
  note?: string;
};

export type RejectApplicantMovementParams = {
  requestId: string;
  reason: string;
};

interface AmrDbRow {
  id: string;
  request_number: string;
  movement_type: string;
  status: string;
  approval_stage: string | null;
  source_applicant_id: string;
  source_applicant_name: string;
  source_applicant_status: string | null;
  source_vacancy_vcode: string;
  source_account_name: string | null;
  target_applicant_id: string | null;
  target_applicant_name: string | null;
  target_applicant_status: string | null;
  target_vacancy_vcode: string;
  target_account_name: string | null;
  reason: string;
  remarks: string | null;
  requested_by: string;
  requested_by_name: string;
  requested_by_role: string;
  requested_at: string;
  created_at: string;
  reservation_reserved_at: string | null;
  has_active_reservation: boolean | null;
  execution_error: string | null;
}

export async function fetchPendingApplicantMovementRequests(): Promise<ApplicantMovementRequestItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("vw_amr_list")
    .select(`
      id,
      request_number,
      movement_type,
      status,
      approval_stage,
      source_applicant_id,
      source_applicant_name,
      source_applicant_status,
      source_vacancy_vcode,
      source_account_name,
      target_applicant_id,
      target_applicant_name,
      target_applicant_status,
      target_vacancy_vcode,
      target_account_name,
      reason,
      remarks,
      requested_by,
      requested_by_name,
      requested_by_role,
      requested_at,
      created_at,
      reservation_reserved_at,
      has_active_reservation,
      execution_error
    `)
    .ilike("status", "pending")
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError("unauthorized", "Unauthorized: Scoped access restricted.");
    }
    throw new RequestDataError("generic", error.message);
  }

  const rows = (data as unknown as AmrDbRow[]) ?? [];
  if (rows.length === 0) return [];

  // Extract unique vcodes to resolve store and position metadata
  const vcodes = Array.from(
    new Set(
      rows
        .flatMap((r) => [r.source_vacancy_vcode, r.target_vacancy_vcode])
        .filter((v): v is string => Boolean(v && v.trim()))
    )
  );

  let vacancyMap: Record<string, { storeName: string | null; position: string | null; account: string | null }> = {};
  if (vcodes.length > 0) {
    try {
      const { data: vData } = await supabase
        .from("vacancies")
        .select("vcode, store_name, position, account")
        .in("vcode", vcodes);

      if (vData) {
        vacancyMap = vData.reduce(
          (acc, v) => {
            acc[v.vcode] = {
              storeName: v.store_name ?? null,
              position: v.position ?? null,
              account: v.account ?? null,
            };
            return acc;
          },
          {} as Record<string, { storeName: string | null; position: string | null; account: string | null }>
        );
      }
    } catch {
      // Non-blocking metadata enrichment
    }
  }

  return rows.map((r) => {
    const srcVac = vacancyMap[r.source_vacancy_vcode];
    const tgtVac = vacancyMap[r.target_vacancy_vcode];

    return {
      id: r.id,
      requestNumber: r.request_number,
      movementType: (r.movement_type === "SWAP" ? "SWAP" : "TRANSFER") as ApplicantMovementType,
      status: (r.status.toLowerCase() as ApplicantMovementStatus) || "pending",
      approvalStage: r.approval_stage ?? null,
      sourceApplicantId: r.source_applicant_id,
      sourceApplicantName: r.source_applicant_name || "—",
      sourceApplicantStatus: r.source_applicant_status ?? null,
      sourceVacancyVcode: r.source_vacancy_vcode,
      sourceStoreName: srcVac?.storeName ?? null,
      sourcePosition: srcVac?.position ?? null,
      sourceAccountName: srcVac?.account ?? r.source_account_name ?? null,
      targetVacancyVcode: r.target_vacancy_vcode,
      targetStoreName: tgtVac?.storeName ?? null,
      targetPosition: tgtVac?.position ?? null,
      targetAccountName: tgtVac?.account ?? r.target_account_name ?? null,
      targetApplicantId: r.target_applicant_id ?? null,
      targetApplicantName: r.target_applicant_name ?? null,
      targetApplicantStatus: r.target_applicant_status ?? null,
      reason: r.reason || "Operational Requirement",
      remarks: r.remarks ?? null,
      requestedBy: r.requested_by,
      requestedByName: r.requested_by_name || "—",
      requestedByRole: r.requested_by_role || "Requester",
      requestedAt: r.requested_at || r.created_at,
      createdAt: r.created_at,
      effectiveDate: r.reservation_reserved_at || r.requested_at || r.created_at,
      hasActiveReservation: Boolean(r.has_active_reservation),
      executionError: r.execution_error ?? null,
    };
  });
}

export async function approveApplicantMovementRequest({
  requestId,
  note,
}: ApproveApplicantMovementParams) {
  const supabase = createClient();
  const trimmedNote = note?.trim() || null;

  const { data, error } = await supabase.rpc("approve_applicant_movement_request", {
    p_request_id: requestId,
    p_note: trimmedNote,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        error.message || "Unauthorized: Only authorized approvers can approve applicant movements."
      );
    }
    if (error.code === "P0001" || error.code === "22023") {
      throw new RequestDataError("validation", error.message);
    }
    if (error.code === "P0002") {
      throw new RequestDataError("not_found", error.message || "Applicant movement request not found.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return data;
}

export async function rejectApplicantMovementRequest({
  requestId,
  reason,
}: RejectApplicantMovementParams) {
  const supabase = createClient();
  const trimmedReason = reason.trim();
  if (!trimmedReason) {
    throw new RequestDataError("validation", "A rejection reason is required.");
  }

  const { data, error } = await supabase.rpc("reject_applicant_movement_request", {
    p_request_id: requestId,
    p_reason: trimmedReason,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        error.message || "Unauthorized: Only authorized approvers can reject applicant movements."
      );
    }
    if (error.code === "P0001" || error.code === "22023") {
      throw new RequestDataError("validation", error.message);
    }
    if (error.code === "P0002") {
      throw new RequestDataError("not_found", error.message || "Applicant movement request not found.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return data;
}

export function usePendingApplicantMovements() {
  return useQuery({
    queryKey: ["applicant-movement-requests"],
    queryFn: () => fetchPendingApplicantMovementRequests(),
  });
}

export function useApproveApplicantMovement() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ApproveApplicantMovementParams) =>
      approveApplicantMovementRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["applicant-movement-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-detail"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
    },
  });
}

export function useRejectApplicantMovement() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RejectApplicantMovementParams) =>
      rejectApplicantMovementRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["applicant-movement-requests"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
    },
  });
}

// ─── Account Deactivations ───────────────────────────────────────────────────

export interface DeactivationRequestItem {
  id: string;
  plantillaId: string;
  employeeName: string;
  employeeNo: string | null;
  accountName: string;
  accountId: string;
  groupName: string | null;
  groupId: string | null;
  status: string;
  batchId: string | null;
  resubmitCount: number;
  createdAt: string;
  requestedAt: string;
  requestedByName: string;
  requestedByProfileId: string;
  // Enriched from plantilla
  storeName: string | null;
  positionTitle: string | null;
  separationStatus: string;
  remarks: string | null;
}

export type CompleteDeactivationParams = {
  requestId: string;
  plantillaId: string;
  remarks?: string;
};

export type RejectDeactivationParams = {
  requestId: string;
  plantillaId: string;
  reason: string;
  remarks?: string;
};

interface DeactivationDbRow {
  id: string;
  plantilla_id: string;
  employee_name: string;
  employee_no: string | null;
  account_name: string;
  account_id: string;
  group_name: string | null;
  group_id: string | null;
  status: string;
  batch_id: string | null;
  resubmit_count: number;
  created_at: string;
  requestor_display_name: string | null;
  requestor_profile_id: string;
}

export async function fetchPendingDeactivationRequests(): Promise<DeactivationRequestItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("v_deactivation_requests")
    .select(`
      id,
      plantilla_id,
      employee_name,
      employee_no,
      account_name,
      account_id,
      group_name,
      group_id,
      status,
      batch_id,
      resubmit_count,
      created_at,
      requestor_display_name,
      requestor_profile_id
    `)
    .ilike("status", "pending")
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError("unauthorized", "Unauthorized: Scoped access restricted.");
    }
    throw new RequestDataError("generic", error.message);
  }

  const rows = (data as unknown as DeactivationDbRow[]) ?? [];
  if (rows.length === 0) return [];

  // Batch-fetch plantilla metadata for store, position, separation status, remarks
  const plantillaIds = Array.from(
    new Set(rows.map((r) => r.plantilla_id).filter((id): id is string => Boolean(id)))
  );

  let plantillaMap: Record<
    string,
    { storeName: string | null; position: string | null; separationStatus: string; remarks: string | null }
  > = {};

  if (plantillaIds.length > 0) {
    try {
      const { data: pData } = await supabase
        .from("plantilla")
        .select("id, store_name, position, separation_status, remarks")
        .in("id", plantillaIds);

      if (pData) {
        plantillaMap = pData.reduce(
          (acc, p) => {
            acc[p.id] = {
              storeName: p.store_name ?? null,
              position: p.position ?? null,
              separationStatus: p.separation_status ?? "Resigned",
              remarks: p.remarks ?? null,
            };
            return acc;
          },
          {} as Record<
            string,
            { storeName: string | null; position: string | null; separationStatus: string; remarks: string | null }
          >
        );
      }
    } catch {
      // Non-blocking enrichment
    }
  }

  return rows.map((r) => {
    const meta = plantillaMap[r.plantilla_id];
    return {
      id: r.id,
      plantillaId: r.plantilla_id,
      employeeName: r.employee_name || "—",
      employeeNo: r.employee_no ?? null,
      accountName: r.account_name || "—",
      accountId: r.account_id,
      groupName: r.group_name ?? null,
      groupId: r.group_id ?? null,
      status: r.status,
      batchId: r.batch_id ?? null,
      resubmitCount: r.resubmit_count ?? 0,
      createdAt: r.created_at,
      requestedAt: r.created_at,
      requestedByName: r.requestor_display_name || "Requester",
      requestedByProfileId: r.requestor_profile_id,
      storeName: meta?.storeName ?? null,
      positionTitle: meta?.position ?? null,
      separationStatus: meta?.separationStatus ?? "Resigned",
      remarks: meta?.remarks ?? null,
    };
  });
}

export async function completeEmployeeDeactivation({
  requestId,
  plantillaId,
  remarks,
}: CompleteDeactivationParams) {
  const supabase = createClient();
  const trimmedRemarks = remarks?.trim() || null;

  // 1. Execute primary authoritative v2 batch RPC
  const { data: batchData, error: batchError } = await supabase.rpc(
    "approve_deactivation_requests_batch",
    {
      p_request_ids: [requestId],
    }
  );

  if (batchError) {
    // 2. Fallback to complete_employee_deactivation RPC
    const { data: singleData, error: singleError } = await supabase.rpc(
      "complete_employee_deactivation",
      {
        p_plantilla_id: plantillaId,
        p_remarks: trimmedRemarks,
      }
    );

    if (singleError) {
      if (singleError.code === "42501" || batchError.code === "42501") {
        throw new RequestDataError(
          "unauthorized",
          "Unauthorized: Only Backoffice and Super Admin roles may approve deactivations."
        );
      }
      throw new RequestDataError("generic", singleError.message || batchError.message);
    }
    return singleData;
  }

  // Best-effort remarks recording on plantilla
  if (trimmedRemarks) {
    try {
      await supabase.rpc("complete_employee_deactivation", {
        p_plantilla_id: plantillaId,
        p_remarks: trimmedRemarks,
      });
    } catch {
      // Ignored non-fatal error
    }
  }

  return batchData;
}

export async function rejectEmployeeDeactivation({
  requestId,
  plantillaId,
  reason,
  remarks,
}: RejectDeactivationParams) {
  const supabase = createClient();
  const trimmedReason = reason.trim();
  if (!trimmedReason) {
    throw new RequestDataError("validation", "A rejection reason is required.");
  }
  const combinedRemarks = [trimmedReason, remarks?.trim()].filter(Boolean).join(" - ");

  // 1. Execute primary authoritative v2 batch RPC
  const { data: batchData, error: batchError } = await supabase.rpc(
    "reject_deactivation_requests_batch",
    {
      p_request_ids: [requestId],
    }
  );

  if (batchError) {
    // 2. Fallback: plantilla_update_separation
    const today = new Date().toISOString().split("T")[0];
    const { data: sepData, error: sepError } = await supabase.rpc(
      "plantilla_update_separation",
      {
        p_plantilla_id: plantillaId,
        p_separation_status: "Resigned",
        p_effective_date: today,
        p_remarks: combinedRemarks,
        p_open_vacancy: true,
      }
    );

    if (sepError) {
      if (sepError.code === "42501" || batchError.code === "42501") {
        throw new RequestDataError(
          "unauthorized",
          "Unauthorized: Only Backoffice and Super Admin roles may reject deactivations."
        );
      }
      throw new RequestDataError("generic", sepError.message || batchError.message);
    }
    return sepData;
  }

  // Also update separation status and remarks on plantilla
  try {
    const today = new Date().toISOString().split("T")[0];
    await supabase.rpc("plantilla_update_separation", {
      p_plantilla_id: plantillaId,
      p_separation_status: "Resigned",
      p_effective_date: today,
      p_remarks: combinedRemarks,
      p_open_vacancy: true,
    });
  } catch {
    // Ignored non-fatal error
  }

  return batchData;
}

export function usePendingDeactivationRequests() {
  return useQuery({
    queryKey: ["deactivation-requests"],
    queryFn: () => fetchPendingDeactivationRequests(),
  });
}

export function useCompleteDeactivation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: CompleteDeactivationParams) =>
      completeEmployeeDeactivation(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["deactivation-requests"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
    },
  });
}

export function useRejectDeactivation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: RejectDeactivationParams) =>
      rejectEmployeeDeactivation(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["deactivation-requests"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
    },
  });
}

// ─── 8. Account Group Transfers ───────────────────────────────────────────────

export interface AccountGroupTransferSimulationSnapshot {
  affected_stores?: number;
  affected_plantilla_count?: number;
  affected_vacancies_count?: number;
  affected_hr_emploc_count?: number;
  users_gaining_visibility?: number;
  users_losing_visibility?: number;
  has_coverage_conflict?: boolean;
  warnings?: string[];
  warning_count?: number;
  coverage_group_conflicts?: Array<{
    employee_name: string;
    store_name: string;
    home_group_name: string;
    conflict_type?: string;
  }>;
  current_group_id?: string;
  current_group_name?: string;
  current_group_code?: string;
  destination_group_id?: string;
  destination_group_name?: string;
  destination_group_code?: string;
  [key: string]: unknown;
}

export interface AccountGroupTransferItem {
  id: string;
  requestNumber: string;
  accountId: string;
  accountName: string;
  fromGroupId: string;
  fromGroupName: string;
  fromGroupCode: string;
  toGroupId: string;
  toGroupName: string;
  toGroupCode: string;
  reason: string;
  status: "pending" | "approved" | "rejected";
  simulationSnapshot: AccountGroupTransferSimulationSnapshot;
  requestedBy: string;
  requestedByName: string;
  requestedAt: string;
  reviewedBy?: string | null;
  reviewedByName?: string | null;
  reviewedAt?: string | null;
  rejectionReason?: string | null;
  createdAt: string;
  updatedAt: string;
}

export async function fetchPendingAccountGroupTransfers(): Promise<AccountGroupTransferItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("account_group_transfer_requests")
    .select(`
      *,
      accounts:account_id(account_name),
      from_groups:from_group_id(group_name, group_code),
      to_groups:to_group_id(group_name, group_code)
    `)
    .ilike("status", "pending")
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        "Unauthorized: Head Admin or Super Admin role required to view account group transfers."
      );
    }
    throw new RequestDataError("generic", error.message);
  }

  const rows = (data || []) as Array<{
    id: string;
    request_number: string;
    account_id: string;
    from_group_id: string;
    to_group_id: string;
    reason: string;
    status: string;
    simulation_snapshot: unknown;
    requested_by: string;
    requested_by_name: string;
    requested_at: string;
    reviewed_by?: string | null;
    reviewed_by_name?: string | null;
    reviewed_at?: string | null;
    rejection_reason?: string | null;
    created_at: string;
    updated_at: string;
    accounts?: { account_name?: string | null } | null;
    from_groups?: { group_name?: string | null; group_code?: string | null } | null;
    to_groups?: { group_name?: string | null; group_code?: string | null } | null;
  }>;

  return rows.map((r) => {
    const rawSnapshot = r.simulation_snapshot;
    const simulationSnapshot: AccountGroupTransferSimulationSnapshot =
      rawSnapshot && typeof rawSnapshot === "object"
        ? (rawSnapshot as AccountGroupTransferSimulationSnapshot)
        : {};

    return {
      id: r.id,
      requestNumber: r.request_number,
      accountId: r.account_id,
      accountName: r.accounts?.account_name || "—",
      fromGroupId: r.from_group_id,
      fromGroupName: r.from_groups?.group_name || "—",
      fromGroupCode: r.from_groups?.group_code || "—",
      toGroupId: r.to_group_id,
      toGroupName: r.to_groups?.group_name || "—",
      toGroupCode: r.to_groups?.group_code || "—",
      reason: r.reason || "—",
      status: (r.status?.toLowerCase() as "pending" | "approved" | "rejected") || "pending",
      simulationSnapshot,
      requestedBy: r.requested_by,
      requestedByName: r.requested_by_name || "Requester",
      requestedAt: r.requested_at || r.created_at,
      reviewedBy: r.reviewed_by ?? null,
      reviewedByName: r.reviewed_by_name ?? null,
      reviewedAt: r.reviewed_at ?? null,
      rejectionReason: r.rejection_reason ?? null,
      createdAt: r.created_at,
      updatedAt: r.updated_at,
    };
  });
}

export async function approveAccountGroupTransfer(requestId: string): Promise<void> {
  const supabase = createClient();

  const { error } = await supabase.rpc("approve_account_group_transfer_request", {
    p_request_id: requestId,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        "Unauthorized: Only Super Admins can approve account group transfer requests."
      );
    }
    throw new RequestDataError("generic", error.message);
  }
}

export async function rejectAccountGroupTransfer({
  requestId,
  reason,
}: {
  requestId: string;
  reason: string;
}): Promise<void> {
  const supabase = createClient();
  const trimmed = reason.trim();
  if (!trimmed) {
    throw new RequestDataError("validation", "A rejection reason is required.");
  }

  const { error } = await supabase.rpc("reject_account_group_transfer_request", {
    p_request_id: requestId,
    p_reason: trimmed,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        "Unauthorized: Only Super Admins can reject account group transfer requests."
      );
    }
    throw new RequestDataError("generic", error.message);
  }
}

export function usePendingAccountGroupTransfers() {
  return useQuery({
    queryKey: ["account-group-transfers"],
    queryFn: () => fetchPendingAccountGroupTransfers(),
  });
}

export function useApproveAccountGroupTransfer() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (requestId: string) => approveAccountGroupTransfer(requestId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["account-group-transfers"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
      queryClient.invalidateQueries({ queryKey: ["accounts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
    },
  });
}

export function useRejectAccountGroupTransfer() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: { requestId: string; reason: string }) =>
      rejectAccountGroupTransfer(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["account-group-transfers"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
      queryClient.invalidateQueries({ queryKey: ["accounts"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
    },
  });
}

// ============================================================================
// 9. Reliever Endorsements & Coverage Requests
// ============================================================================

export type RelieverEndorsementItem = {
  requestId: string;
  employeeId: string;
  employeeNumber: string | null;
  employeeName: string | null;
  poolType: string | null;
  requestedAccount: string | null;
  requestedStore: string | null;
  requestedGroup: string | null;
  priority: string;
  startDate: string | null;
  endDate: string | null;
  reason: string | null;
  status: string;
  requestedBy: string | null;
  rejectionReason: string | null;
  reviewedBy: string | null;
  reviewedAt: string | null;
  convertedAssignmentId: string | null;
  createdAt: string;
  requestAgeDays: number | null;
  escalationLevel: string | null;
  notifyTargetRole: string | null;
};

export type CoverageGroupRequestItem = {
  id: string;
  requestType: string;
  status: string;
  accountId: string | null;
  accountName: string | null;
  positionId: string | null;
  employmentType: string | null;
  targetCoverageGroupId: string | null;
  targetCoverageGroupName: string | null;
  targetCoverageGroupCode: string | null;
  sourceCoverageGroupId: string | null;
  destinationCoverageGroupId: string | null;
  payload: Record<string, unknown>;
  reason: string | null;
  requestedBy: string;
  requestedByName: string;
  requestedByRole: string | null;
  requestedAt: string;
  approvedBy: string | null;
  approvedByName: string | null;
  approvedAt: string | null;
  rejectedBy: string | null;
  rejectedByName: string | null;
  rejectedAt: string | null;
  rejectionReason: string | null;
  reviewerRemarks: string | null;
  executionSummary: Record<string, unknown> | null;
  createdAt: string;
};

/**
 * Fetches pending Reliever Endorsement requests from v_workforce_assignment_request_queue.
 */
export async function fetchPendingRelieverEndorsements(): Promise<RelieverEndorsementItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("v_workforce_assignment_request_queue")
    .select(`
      request_id,
      employee_id,
      employee_number,
      employee_name,
      pool_type,
      requested_account,
      requested_store,
      requested_group,
      priority,
      start_date,
      end_date,
      reason,
      status,
      requested_by,
      rejection_reason,
      reviewed_by,
      reviewed_at,
      converted_assignment_id,
      created_at,
      request_age_days,
      escalation_level,
      notify_target_role
    `)
    .in("status", ["Pending", "pending", "For Review", "for review"])
    .order("request_age_days", { ascending: false })
    .order("created_at", { ascending: true });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError("unauthorized", "Unauthorized: Scoped access restricted.");
    }
    throw new RequestDataError("generic", error.message);
  }

  return (data ?? []).map((row) => ({
    requestId: row.request_id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number ?? null,
    employeeName: row.employee_name ?? null,
    poolType: row.pool_type ?? null,
    requestedAccount: row.requested_account ?? null,
    requestedStore: row.requested_store ?? null,
    requestedGroup: row.requested_group ?? null,
    priority: row.priority ?? "Normal",
    startDate: row.start_date ?? null,
    endDate: row.end_date ?? null,
    reason: row.reason ?? null,
    status: row.status ?? "Pending",
    requestedBy: row.requested_by ?? null,
    rejectionReason: row.rejection_reason ?? null,
    reviewedBy: row.reviewed_by ?? null,
    reviewedAt: row.reviewed_at ?? null,
    convertedAssignmentId: row.converted_assignment_id ?? null,
    createdAt: row.created_at,
    requestAgeDays: row.request_age_days !== null ? Number(row.request_age_days) : null,
    escalationLevel: row.escalation_level ?? null,
    notifyTargetRole: row.notify_target_role ?? null,
  }));
}

/**
 * Fetches pending Coverage Requests (roving coverage structures) joined with accounts and coverage groups.
 */
export async function fetchPendingCoverageRequests(): Promise<CoverageGroupRequestItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("coverage_requests")
    .select(`
      id,
      request_type,
      status,
      account_id,
      position_id,
      employment_type,
      target_coverage_group_id,
      source_coverage_group_id,
      destination_coverage_group_id,
      payload,
      reason,
      requested_by,
      requested_by_name,
      requested_by_role,
      requested_at,
      approved_by,
      approved_by_name,
      approved_at,
      rejected_by,
      rejected_by_name,
      rejected_at,
      rejection_reason,
      reviewer_remarks,
      execution_summary,
      created_at,
      accounts:account_id (
        account_name
      ),
      target_coverage_group:target_coverage_group_id (
        name,
        code
      )
    `)
    .or("status.ilike.pending,status.ilike.draft")
    .is("archived_at", null)
    .order("created_at", { ascending: false });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError("unauthorized", "Unauthorized: Scoped access restricted.");
    }
    throw new RequestDataError("generic", error.message);
  }

  type RawCoverageRow = {
    id: string;
    request_type: string;
    status: string;
    account_id: string | null;
    position_id: string | null;
    employment_type: string | null;
    target_coverage_group_id: string | null;
    source_coverage_group_id: string | null;
    destination_coverage_group_id: string | null;
    payload: Record<string, unknown> | null;
    reason: string | null;
    requested_by: string;
    requested_by_name: string;
    requested_by_role: string | null;
    requested_at: string;
    approved_by: string | null;
    approved_by_name: string | null;
    approved_at: string | null;
    rejected_by: string | null;
    rejected_by_name: string | null;
    rejected_at: string | null;
    rejection_reason: string | null;
    reviewer_remarks: string | null;
    execution_summary: Record<string, unknown> | null;
    created_at: string;
    accounts?: { account_name?: string } | null;
    target_coverage_group?: { name?: string; code?: string } | null;
  };

  return ((data as unknown as RawCoverageRow[]) ?? []).map((row) => ({
    id: row.id,
    requestType: row.request_type,
    status: row.status,
    accountId: row.account_id ?? null,
    accountName: row.accounts?.account_name ?? null,
    positionId: row.position_id ?? null,
    employmentType: row.employment_type ?? null,
    targetCoverageGroupId: row.target_coverage_group_id ?? null,
    targetCoverageGroupName: row.target_coverage_group?.name ?? null,
    targetCoverageGroupCode: row.target_coverage_group?.code ?? null,
    sourceCoverageGroupId: row.source_coverage_group_id ?? null,
    destinationCoverageGroupId: row.destination_coverage_group_id ?? null,
    payload: row.payload ?? {},
    reason: row.reason ?? null,
    requestedBy: row.requested_by,
    requestedByName: row.requested_by_name,
    requestedByRole: row.requested_by_role ?? null,
    requestedAt: row.requested_at,
    approvedBy: row.approved_by ?? null,
    approvedByName: row.approved_by_name ?? null,
    approvedAt: row.approved_at ?? null,
    rejectedBy: row.rejected_by ?? null,
    rejectedByName: row.rejected_by_name ?? null,
    rejectedAt: row.rejected_at ?? null,
    rejectionReason: row.rejection_reason ?? null,
    reviewerRemarks: row.reviewer_remarks ?? null,
    executionSummary: row.execution_summary ?? null,
    createdAt: row.created_at,
  }));
}

/**
 * Approves a Reliever Coverage request.
 * Invokes approve_reliever_coverage_request(p_request_id, p_assigned_employee_id, p_notes).
 */
export async function approveRelieverCoverageRequest({
  requestId,
  assignedEmployeeId,
  notes,
}: {
  requestId: string;
  assignedEmployeeId?: string;
  notes?: string;
}): Promise<void> {
  const supabase = createClient();

  const { error } = await supabase.rpc("approve_reliever_coverage_request", {
    p_request_id: requestId,
    p_assigned_employee_id: assignedEmployeeId || null,
    p_notes: notes?.trim() || null,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        "Unauthorized: Only Data Team, Head Admin, or Super Admin can approve reliever coverage requests."
      );
    }
    throw new RequestDataError("generic", error.message);
  }
}

/**
 * Rejects a Reliever Coverage request.
 * Invokes reject_reliever_coverage_request(p_request_id, p_rejection_reason).
 */
export async function rejectRelieverCoverageRequest({
  requestId,
  reason,
}: {
  requestId: string;
  reason: string;
}): Promise<void> {
  const supabase = createClient();
  const trimmed = reason.trim();
  if (!trimmed) {
    throw new RequestDataError("validation", "A rejection reason is required.");
  }

  const { error } = await supabase.rpc("reject_reliever_coverage_request", {
    p_request_id: requestId,
    p_rejection_reason: trimmed,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        "Unauthorized: Only Data Team, Head Admin, or Super Admin can reject reliever coverage requests."
      );
    }
    throw new RequestDataError("generic", error.message);
  }
}

/**
 * Approves a Coverage Request (roving coverage structure).
 * Invokes approve_coverage_request(p_coverage_request_id, p_reviewer_remarks).
 */
export async function approveCoverageRequest({
  coverageRequestId,
  reviewerRemarks,
}: {
  coverageRequestId: string;
  reviewerRemarks?: string;
}): Promise<void> {
  const supabase = createClient();

  const { error } = await supabase.rpc("approve_coverage_request", {
    p_coverage_request_id: coverageRequestId,
    p_reviewer_remarks: reviewerRemarks?.trim() || null,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        "Unauthorized: Only Head Admin or Super Admin can approve coverage structure requests."
      );
    }
    throw new RequestDataError("generic", error.message);
  }
}

/**
 * Rejects a Coverage Request (roving coverage structure).
 * Invokes reject_coverage_request(p_coverage_request_id, p_rejection_reason, p_reviewer_remarks).
 */
export async function rejectCoverageRequest({
  coverageRequestId,
  rejectionReason,
  reviewerRemarks,
}: {
  coverageRequestId: string;
  rejectionReason: string;
  reviewerRemarks?: string;
}): Promise<void> {
  const supabase = createClient();
  const trimmed = rejectionReason.trim();
  if (!trimmed) {
    throw new RequestDataError("validation", "A rejection reason is required.");
  }

  const { error } = await supabase.rpc("reject_coverage_request", {
    p_coverage_request_id: coverageRequestId,
    p_rejection_reason: trimmed,
    p_reviewer_remarks: reviewerRemarks?.trim() || null,
  });

  if (error) {
    if (error.code === "42501") {
      throw new RequestDataError(
        "unauthorized",
        "Unauthorized: Only Head Admin or Super Admin can reject coverage structure requests."
      );
    }
    throw new RequestDataError("generic", error.message);
  }
}

export function usePendingRelieverEndorsements() {
  return useQuery({
    queryKey: ["reliever-endorsements"],
    queryFn: () => fetchPendingRelieverEndorsements(),
  });
}

export function usePendingCoverageRequests() {
  return useQuery({
    queryKey: ["coverage-group-requests"],
    queryFn: () => fetchPendingCoverageRequests(),
  });
}

export function useApproveRelieverCoverage() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: {
      requestId: string;
      assignedEmployeeId?: string;
      notes?: string;
    }) => approveRelieverCoverageRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["reliever-endorsements"] });
      queryClient.invalidateQueries({ queryKey: ["workforce-assignments"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
    },
  });
}

export function useRejectRelieverCoverage() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: { requestId: string; reason: string }) =>
      rejectRelieverCoverageRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["reliever-endorsements"] });
      queryClient.invalidateQueries({ queryKey: ["workforce-assignments"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
    },
  });
}

export function useApproveCoverageRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: {
      coverageRequestId: string;
      reviewerRemarks?: string;
    }) => approveCoverageRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["coverage-group-requests"] });
      queryClient.invalidateQueries({ queryKey: ["coverage-groups"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["cencom"] });
    },
  });
}

export function useRejectCoverageRequest() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: {
      coverageRequestId: string;
      rejectionReason: string;
      reviewerRemarks?: string;
    }) => rejectCoverageRequest(params),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["coverage-group-requests"] });
      queryClient.invalidateQueries({ queryKey: ["coverage-groups"] });
      queryClient.invalidateQueries({ queryKey: ["stores"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["cencom"] });
    },
  });
}


