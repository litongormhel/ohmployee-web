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

    // 3. Coverage
    countItem(
      "coverage",
      supabase
        .from("coverage_requests")
        .select("id", { count: "exact", head: true })
        .or("status.ilike.pending,status.ilike.draft")
    ),

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
