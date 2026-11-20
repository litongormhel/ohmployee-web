import { createClient } from "@/lib/supabase/client";
import type { WebCurrentUserContext } from "@/lib/auth";
import { useQuery } from "@tanstack/react-query";

export type MyRequestCategoryType =
  | "all"
  | "headcount"
  | "new_stores"
  | "vacancy_closures"
  | "deactivations"
  | "applicant_movements"
  | "coverage";

export type MyRequestStatus = "pending" | "approved" | "rejected" | "cancelled";

export interface MyRequestItem {
  id: string;
  category: Exclude<MyRequestCategoryType, "all">;
  categoryLabel: string;
  status: MyRequestStatus;
  statusLabel: string;
  title: string;
  subtitle: string;
  details: {
    storeName?: string | null;
    accountName?: string | null;
    positionName?: string | null;
    groupName?: string | null;
    vcode?: string | null;
    employeeName?: string | null;
    employeeNo?: string | null;
    reason?: string | null;
    headcountNeeded?: number | null;
    proposedTarget?: number | null;
    previousTarget?: number | null;
    urgency?: string | null;
    movementType?: string | null;
    requestNumber?: string | null;
    location?: string | null;
  };
  createdAt: string;
  reviewedAt?: string | null;
  reviewedByName?: string | null;
  reviewerRemarks?: string | null;
}

export interface MyRequestsCounts {
  total: number;
  pending: number;
  approved: number;
  rejected: number;
}

function normalizeStatus(raw: string | null | undefined): MyRequestStatus {
  const s = (raw ?? "").toLowerCase().trim();
  if (
    s === "pending" ||
    s === "under_review" ||
    s === "for_approval" ||
    s === "review_pending" ||
    s === "submitted"
  ) {
    return "pending";
  }
  if (
    s === "approved" ||
    s === "completed" ||
    s === "approved_pending_vcode" ||
    s === "processed"
  ) {
    return "approved";
  }
  if (s === "rejected" || s === "declined" || s === "disapproved") {
    return "rejected";
  }
  if (s === "cancelled" || s === "withdrawn") {
    return "cancelled";
  }
  return "pending";
}

function getStatusLabel(status: MyRequestStatus): string {
  switch (status) {
    case "pending":
      return "Pending Review";
    case "approved":
      return "Approved";
    case "rejected":
      return "Rejected";
    case "cancelled":
      return "Cancelled";
  }
}

/**
 * Fetches all requests submitted by the current user across all operational domains.
 * Mirrors Mobile OHMployee `my_requests_screen.dart` behavior.
 */
export async function fetchMyRequests(
  user: WebCurrentUserContext | null
): Promise<MyRequestItem[]> {
  if (!user) return [];

  const supabase = createClient();
  const authUserId = user.authUserId;
  const profileId = user.profileId;
  if (!authUserId && !profileId) return [];

  const items: MyRequestItem[] = [];

  // Helper filter string for OR matching
  const buildUserOrFilter = (columnName: string) => {
    if (profileId && authUserId && profileId !== authUserId) {
      return `${columnName}.eq.${authUserId},${columnName}.eq.${profileId}`;
    }
    return `${columnName}.eq.${authUserId || profileId}`;
  };

  // 1. Headcount Requests
  try {
    let q = supabase
      .from("headcount_requests")
      .select(
        "id, status, created_at, updated_at, store_name_snapshot, position_name_snapshot, account_name_snapshot, group_name_snapshot, headcount_needed, proposed_target, previous_target, reason, urgency, requested_by_user_id, requested_by_name, reviewed_by_name, reviewed_at, reviewer_remarks, request_type, hc_request_stores ( id, is_new_store, store_name, store_name_snapshot, area_province, area_city )"
      )
      .eq("is_archived", false)
      .order("created_at", { ascending: false });

    q = q.or(buildUserOrFilter("requested_by_user_id"));

    const { data, error } = await q;
    if (error) {
      console.error(
        "[PostgREST Schema Error] fetchMyRequests(headcount_requests):",
        error.message || error,
        error.details,
        error
      );
    } else if (data) {
      for (const row of data) {
        const normStatus = normalizeStatus(row.status);
        const pos = row.position_name_snapshot || "Position";
        const account = row.account_name_snapshot || "";
        const isQuota = Boolean(row.proposed_target !== null && row.previous_target !== null);
        const reqType = row.request_type || (isQuota ? "Quota Amendment" : "Additional Headcount");

        const stores = (row.hc_request_stores || []) as Array<{
          id: string;
          is_new_store?: boolean;
          store_name?: string | null;
          store_name_snapshot?: string | null;
          area_province?: string | null;
          area_city?: string | null;
        }>;
        const newStores = stores.filter((s) => s.is_new_store);
        const existingStores = stores
          .filter((s) => !s.is_new_store)
          .map((s) => s.store_name || s.store_name_snapshot)
          .filter(Boolean)
          .join(", ");

        if (newStores.length > 0) {
          // Option 1: Route to New Stores category when requisition introduces new/unlisted doors
          const storeNames = newStores
            .map((s) => s.store_name || s.store_name_snapshot)
            .filter(Boolean)
            .join(", ");
          const location = [newStores[0]?.area_city, newStores[0]?.area_province]
            .filter(Boolean)
            .join(", ");

          items.push({
            id: row.id,
            category: "new_stores",
            categoryLabel: "New Store",
            status: normStatus,
            statusLabel: getStatusLabel(normStatus),
            title: `New Store (${pos}): ${storeNames}`,
            subtitle: account
              ? `${account} · ${newStores.length} New Door(s) Proposed`
              : `${newStores.length} New Door(s) Proposed`,
            details: {
              storeName: storeNames,
              accountName: account,
              positionName: pos,
              headcountNeeded: row.headcount_needed,
              reason: row.reason,
              location: location || null,
            },
            createdAt: row.created_at,
            reviewedAt: row.reviewed_at,
            reviewedByName: row.reviewed_by_name,
            reviewerRemarks: row.reviewer_remarks,
          });
        } else {
          const store = row.store_name_snapshot || existingStores || "—";
          items.push({
            id: row.id,
            category: "headcount",
            categoryLabel: reqType,
            status: normStatus,
            statusLabel: getStatusLabel(normStatus),
            title: `${pos} at ${store}`,
            subtitle: account ? `${account} · ${reqType}` : reqType,
            details: {
              storeName: store,
              accountName: row.account_name_snapshot,
              positionName: row.position_name_snapshot,
              groupName: row.group_name_snapshot,
              headcountNeeded: row.headcount_needed,
              proposedTarget: row.proposed_target,
              previousTarget: row.previous_target,
              reason: row.reason,
              urgency: row.urgency,
            },
            createdAt: row.created_at,
            reviewedAt: row.reviewed_at,
            reviewedByName: row.reviewed_by_name,
            reviewerRemarks: row.reviewer_remarks,
          });
        }
      }
    }
  } catch (err) {
    console.error("[MyRequests] Unexpected exception querying headcount_requests:", err);
  }

  // 2. New Store Requests
  try {
    let q = supabase
      .from("new_store_requests")
      .select(
        "id, store_name, account_name, province, city, status, requested_at, created_at, reviewed_by_name, reviewed_at, review_reason, requested_by, position, requested_hc, reason"
      )
      .eq("is_archived", false)
      .order("created_at", { ascending: false });

    q = q.or(buildUserOrFilter("requested_by"));

    const { data, error } = await q;
    if (error) {
      console.error(
        "[PostgREST Schema Error] fetchMyRequests(new_store_requests):",
        error.message || error,
        error.details,
        error
      );
    } else if (data) {
      for (const row of data) {
        const normStatus = normalizeStatus(row.status);
        const location = [row.province, row.city].filter(Boolean).join(", ") || null;

        items.push({
          id: row.id,
          category: "new_stores",
          categoryLabel: "New Store",
          status: normStatus,
          statusLabel: getStatusLabel(normStatus),
          title: `New Store: ${row.store_name}`,
          subtitle: row.account_name ? `${row.account_name}${location ? ` · ${location}` : ""}` : (location || "New Store Opening"),
          details: {
            storeName: row.store_name,
            accountName: row.account_name,
            positionName: row.position,
            headcountNeeded: row.requested_hc,
            reason: row.reason,
            location,
          },
          createdAt: row.requested_at || row.created_at,
          reviewedAt: row.reviewed_at,
          reviewedByName: row.reviewed_by_name,
          reviewerRemarks: row.review_reason,
        });
      }
    }
  } catch (err) {
    console.error("[MyRequests] Unexpected exception querying new_store_requests:", err);
  }

  // 3. Vacancy Closure Requests
  try {
    let q = supabase
      .from("vacancy_closure_requests")
      .select(
        "id, status, created_at, vacancy_vcode, reason, details, requested_by, requested_by_user_id, reviewed_by, reviewed_at, reviewer_remarks, vacancies(store_name, position, account)"
      )
      .order("created_at", { ascending: false });

    q = q.or(buildUserOrFilter("requested_by_user_id"));

    const { data, error } = await q;
    if (error) {
      console.error(
        "[PostgREST Schema Error] fetchMyRequests(vacancy_closure_requests):",
        error.message || error,
        error.details,
        error
      );
    } else if (data) {
      for (const row of data) {
        const normStatus = normalizeStatus(row.status);
        const vac = row.vacancies as { store_name?: string | null; position?: string | null; account?: string | null } | null;
        const vcode = row.vacancy_vcode || "—";
        const store = vac?.store_name || "—";
        const pos = vac?.position || "";

        items.push({
          id: row.id,
          category: "vacancy_closures",
          categoryLabel: "Vacancy Closure",
          status: normStatus,
          statusLabel: getStatusLabel(normStatus),
          title: `Close Vacancy: ${vcode}`,
          subtitle: `${store}${pos ? ` · ${pos}` : ""}`,
          details: {
            vcode,
            storeName: vac?.store_name,
            accountName: vac?.account,
            positionName: vac?.position,
            reason: row.reason || row.details,
          },
          createdAt: row.created_at,
          reviewedAt: row.reviewed_at,
          reviewedByName: row.reviewed_by,
          reviewerRemarks: row.reviewer_remarks,
        });
      }
    }
  } catch (err) {
    console.error("[MyRequests] Unexpected exception querying vacancy_closure_requests:", err);
  }

  // 4. Employee Deactivation Requests (via v_deactivation_requests)
  try {
    let q = supabase
      .from("v_deactivation_requests")
      .select(
        "id, plantilla_id, employee_name, employee_no, account_name, group_name, status, created_at, processed_at, processor_display_name, requestor_profile_id, requestor_display_name"
      )
      .order("created_at", { ascending: false });

    q = q.or(buildUserOrFilter("requestor_profile_id"));

    const { data, error } = await q;
    if (error) {
      console.error(
        "[PostgREST Schema Error] fetchMyRequests(v_deactivation_requests):",
        error.message || error,
        error.details,
        error
      );
    } else if (data) {
      for (const row of data) {
        const normStatus = normalizeStatus(row.status);
        const empName = row.employee_name || "Employee";
        const empNo = row.employee_no ? ` (${row.employee_no})` : "";

        items.push({
          id: row.id,
          category: "deactivations",
          categoryLabel: "Deactivation",
          status: normStatus,
          statusLabel: getStatusLabel(normStatus),
          title: `Deactivation: ${empName}${empNo}`,
          subtitle: [row.account_name, row.group_name].filter(Boolean).join(" · ") || "Employee Separation",
          details: {
            employeeName: row.employee_name,
            employeeNo: row.employee_no,
            accountName: row.account_name,
            groupName: row.group_name,
          },
          createdAt: row.created_at,
          reviewedAt: row.processed_at,
          reviewedByName: row.processor_display_name,
          reviewerRemarks: null,
        });
      }
    }
  } catch (err) {
    console.error("[MyRequests] Unexpected exception querying v_deactivation_requests:", err);
  }

  // 5. Applicant Movement Requests (AMR via vw_amr_list)
  try {
    let q = supabase
      .from("vw_amr_list")
      .select(
        "id, request_number, movement_type, status, source_applicant_name, target_vacancy_vcode, reason, remarks, requested_by, requested_by_name, approval_stage, rejection_reason, requested_at, created_at, updated_at"
      )
      .order("created_at", { ascending: false });

    q = q.or(buildUserOrFilter("requested_by"));

    const { data, error } = await q;
    if (error) {
      console.error(
        "[PostgREST Schema Error] fetchMyRequests(applicant_movement_requests):",
        error.message || error,
        error.details,
        error
      );
    } else if (data) {
      for (const row of data) {
        const normStatus = normalizeStatus(row.status);
        const movType = row.movement_type === "SWAP" ? "Applicant Swap" : "Applicant Transfer";
        const applicant = row.source_applicant_name || "Applicant";

        items.push({
          id: row.id,
          category: "applicant_movements",
          categoryLabel: movType,
          status: normStatus,
          statusLabel: getStatusLabel(normStatus),
          title: `${movType}: ${applicant}`,
          subtitle: `Target VCODE: ${row.target_vacancy_vcode || "—"}${row.request_number ? ` · #${row.request_number}` : ""}`,
          details: {
            employeeName: row.source_applicant_name,
            vcode: row.target_vacancy_vcode,
            movementType: row.movement_type,
            requestNumber: row.request_number,
            reason: row.reason || row.remarks,
          },
          createdAt: row.requested_at || row.created_at,
          reviewedAt: row.updated_at,
          reviewedByName: row.approval_stage ? `Stage: ${row.approval_stage}` : null,
          reviewerRemarks: row.rejection_reason || row.remarks,
        });
      }
    }
  } catch (err) {
    console.error("[MyRequests] Unexpected exception querying applicant_movement_requests:", err);
  }

  // 6. Roving Coverage Requests
  try {
    let q = supabase
      .from("coverage_requests")
      .select(`
        id,
        request_type,
        status,
        reason,
        created_at,
        approved_at,
        rejected_at,
        cancelled_at,
        reviewer_remarks,
        rejection_reason,
        requested_by,
        accounts:accounts!account_id (
          account_name
        ),
        target_coverage_group:coverage_groups!target_coverage_group_id (
          coverage_code,
          area_name
        )
      `)
      .is("archived_at", null)
      .order("created_at", { ascending: false });

    q = q.or(buildUserOrFilter("requested_by"));

    const { data, error } = await q;
    if (error) {
      console.error(
        "[PostgREST Schema Error] fetchMyRequests(coverage_requests):",
        error.message || error,
        error.details,
        error
      );
    } else if (data) {
      for (const row of data) {
        const normStatus = normalizeStatus(row.status);
        const cg = row.target_coverage_group as { coverage_code?: string | null; area_name?: string | null } | null;
        const acc = row.accounts as { account_name?: string | null } | null;
        const cgCode = cg?.coverage_code || "";
        const cgArea = cg?.area_name ? ` · ${cg.area_name}` : "";
        const cgTitle = cgCode ? `${cgCode}${cgArea}` : "Coverage Group";

        items.push({
          id: row.id,
          category: "coverage",
          categoryLabel: "Coverage Group",
          status: normStatus,
          statusLabel: getStatusLabel(normStatus),
          title: `Coverage Request (${row.request_type || "Roving"}): ${cgTitle}`,
          subtitle: acc?.account_name || cgCode || "Roving Store Coverage",
          details: {
            groupName: cgTitle,
            accountName: acc?.account_name,
            reason: row.reason,
          },
          createdAt: row.created_at,
          reviewedAt: row.approved_at || row.rejected_at || row.cancelled_at || null,
          reviewedByName: null,
          reviewerRemarks: row.rejection_reason || row.reviewer_remarks,
        });
      }
    }
  } catch (err) {
    console.error("[MyRequests] Unexpected exception querying coverage_requests:", err);
  }

  // Sort unified requests by createdAt descending
  items.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
  return items;
}

/**
 * React Query hook for retrieving current user's submitted requests.
 */
export function useMyRequests(user: WebCurrentUserContext | null) {
  return useQuery({
    queryKey: ["my-requests", user?.authUserId, user?.profileId],
    queryFn: () => fetchMyRequests(user),
    enabled: Boolean(user?.authUserId || user?.profileId),
    staleTime: 30 * 1000,
  });
}

/**
 * Calculates status counts from user's request list.
 */
export function calculateMyRequestsCounts(items: MyRequestItem[]): MyRequestsCounts {
  let pending = 0;
  let approved = 0;
  let rejected = 0;

  for (const item of items) {
    if (item.status === "pending") pending++;
    else if (item.status === "approved") approved++;
    else if (item.status === "rejected" || item.status === "cancelled") rejected++;
  }

  return {
    total: items.length,
    pending,
    approved,
    rejected,
  };
}
