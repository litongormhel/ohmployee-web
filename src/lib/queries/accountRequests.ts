import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

// ============================================================================
// Types: Account Request
// ============================================================================

export type AccountRequestStatus = "pending" | "approved" | "rejected";

export interface AccountRequestItem {
  id: string;
  authUserId: string | null;
  email: string;
  fullName: string;
  lastName: string | null;
  firstName: string | null;
  middleName: string | null;
  mobileNumber: string | null;
  status: AccountRequestStatus;
  notes: string | null;
  requestedRoleId: string | null;
  requestedRoleName: string | null;
  requestedRoleLevel: number | null;
  assignedRoleId: string | null;
  assignedRoleName: string | null;
  assignedRoleLevel: number | null;
  assignedScopeType: string | null;
  assignedGroupsSnapshot: string[] | null;
  assignedAccountsSnapshot: string[] | null;
  reviewedBy: string | null;
  reviewedAt: string | null;
  rejectionReason: string | null;
  rejectedAt: string | null;
  createdAt: string;
  updatedAt: string | null;
  reviewerDisplayName: string | null;
  requestedGroupIds: string[];
  requestedGroupNames: string[];
  requestedAccountIds: string[];
  requestedAccountNames: string[];
  requestedScopeType: "global" | "scoped";
  daysPending: number | null;
}

export interface ApproveAccountRequestPayload {
  requestId: string;
  roleId: string;
  scopeType: "global" | "scoped";
  groupIds: string[];
  accountIds: string[];
}

export interface RejectAccountRequestPayload {
  requestId: string;
  reason: string;
  remarks?: string;
}

// ============================================================================
// Queries
// ============================================================================

export async function fetchApprovalQueue(status: AccountRequestStatus = "pending"): Promise<AccountRequestItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_approval_queue", {
    p_status: status,
  });

  if (error) {
    throw new Error(error.message || "Failed to fetch account approval queue");
  }

  const rows = (data as unknown as Record<string, unknown>[]) || [];

  return rows.map((r) => ({
    id: String(r.id),
    authUserId: r.auth_user_id ? String(r.auth_user_id) : null,
    email: String(r.email || ""),
    fullName: String(r.full_name || ""),
    lastName: r.last_name ? String(r.last_name) : null,
    firstName: r.first_name ? String(r.first_name) : null,
    middleName: r.middle_name ? String(r.middle_name) : null,
    mobileNumber: r.mobile_number ? String(r.mobile_number) : null,
    status: (r.status as AccountRequestStatus) || "pending",
    notes: r.notes ? String(r.notes) : null,
    requestedRoleId: r.requested_role_id ? String(r.requested_role_id) : null,
    requestedRoleName: r.requested_role_name ? String(r.requested_role_name) : null,
    requestedRoleLevel: typeof r.requested_role_level === "number" ? r.requested_role_level : null,
    assignedRoleId: r.assigned_role_id ? String(r.assigned_role_id) : null,
    assignedRoleName: r.assigned_role_name ? String(r.assigned_role_name) : null,
    assignedRoleLevel: typeof r.assigned_role_level === "number" ? r.assigned_role_level : null,
    assignedScopeType: r.assigned_scope_type ? String(r.assigned_scope_type) : null,
    assignedGroupsSnapshot: Array.isArray(r.assigned_groups_snapshot)
      ? (r.assigned_groups_snapshot as string[])
      : null,
    assignedAccountsSnapshot: Array.isArray(r.assigned_accounts_snapshot)
      ? (r.assigned_accounts_snapshot as string[])
      : null,
    reviewedBy: r.reviewed_by ? String(r.reviewed_by) : null,
    reviewedAt: r.reviewed_at ? String(r.reviewed_at) : null,
    rejectionReason: r.rejection_reason ? String(r.rejection_reason) : null,
    rejectedAt: r.rejected_at ? String(r.rejected_at) : null,
    createdAt: String(r.created_at || ""),
    updatedAt: r.updated_at ? String(r.updated_at) : null,
    reviewerDisplayName: r.reviewer_display_name ? String(r.reviewer_display_name) : null,
    requestedGroupIds: Array.isArray(r.requested_group_ids) ? (r.requested_group_ids as string[]) : [],
    requestedGroupNames: Array.isArray(r.requested_group_names) ? (r.requested_group_names as string[]) : [],
    requestedAccountIds: Array.isArray(r.requested_account_ids) ? (r.requested_account_ids as string[]) : [],
    requestedAccountNames: Array.isArray(r.requested_account_names) ? (r.requested_account_names as string[]) : [],
    requestedScopeType: r.requested_scope_type === "scoped" ? "scoped" : "global",
    daysPending: typeof r.days_pending === "number" ? r.days_pending : null,
  }));
}

export async function approveAccountRequest(payload: ApproveAccountRequestPayload): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("approve_account_request_v2", {
    p_request_id: payload.requestId,
    p_role_id: payload.roleId,
    p_scope_type: payload.scopeType,
    p_group_ids: payload.groupIds,
    p_account_ids: payload.accountIds,
  });

  if (error) {
    const errStr = error.message || "";
    if (errStr.includes("23503")) {
      throw new Error(
        "Auth sync error: The user's authentication account could not be found. Please ask user to sign up again."
      );
    }
    if (
      errStr.includes("chk_mobile_number") ||
      errStr.includes("invalid mobile number") ||
      errStr.includes("invalid_ph_mobile")
    ) {
      throw new Error("Invalid mobile number format. Please use 09XXXXXXXXX or +639XXXXXXXXX.");
    }
    throw new Error(error.message || "Failed to approve account request");
  }
}

export async function rejectAccountRequest(payload: RejectAccountRequestPayload): Promise<void> {
  const supabase = createClient();
  const notes = payload.remarks ? `${payload.reason}\n\n${payload.remarks}` : payload.reason;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase
    .from("account_requests")
    .update({
      status: "rejected",
      notes: notes,
      rejection_reason: payload.reason,
      reviewed_by: user?.id ?? null,
      reviewed_at: new Date().toISOString(),
      rejected_at: new Date().toISOString(),
    })
    .eq("id", payload.requestId);

  if (error) {
    throw new Error(error.message || "Failed to reject account request");
  }
}

export async function fetchAccountRequestCounts(): Promise<{ pending: number; approved: number; rejected: number }> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("account_requests")
    .select("status");

  if (error) {
    throw new Error(error.message || "Failed to fetch account request counts");
  }

  if (!data) return { pending: 0, approved: 0, rejected: 0 };

  let pending = 0;
  let approved = 0;
  let rejected = 0;

  for (const row of data) {
    const s = (row.status || "").toLowerCase();
    if (s === "pending") pending++;
    else if (s === "approved") approved++;
    else if (s === "rejected") rejected++;
  }

  return { pending, approved, rejected };
}

// ============================================================================
// React Query Hooks
// ============================================================================

export function useAccountApprovalQueue(status: AccountRequestStatus = "pending") {
  return useQuery({
    queryKey: ["account-approval-queue", status],
    queryFn: () => fetchApprovalQueue(status),
    refetchInterval: 30000,
  });
}

export function useAccountRequestCounts() {
  return useQuery({
    queryKey: ["account-request-counts"],
    queryFn: () => fetchAccountRequestCounts(),
    retry: 1,
  });
}

export function useApproveAccountRequest() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: approveAccountRequest,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["account-approval-queue"] });
      queryClient.invalidateQueries({ queryKey: ["account-request-counts"] });
      queryClient.invalidateQueries({ queryKey: ["users"] });
      queryClient.invalidateQueries({ queryKey: ["users-list"] });
    },
  });
}

export function useRejectAccountRequest() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: rejectAccountRequest,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
      queryClient.invalidateQueries({ queryKey: ["account-approval-queue"] });
      queryClient.invalidateQueries({ queryKey: ["account-request-counts"] });
    },
  });
}
