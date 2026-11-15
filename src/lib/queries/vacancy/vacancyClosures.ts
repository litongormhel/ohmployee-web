import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import {
  type RequestVacancyClosureParams,
  type ReviewClosureRequestParams,
  type WithdrawVacancyClosureParams,
  VacancyDataError,
} from "./types";
import { invalidateVacancyEcosystem } from "./vacancyHelpers";


// ── 5. Vacancy Closure Management ────────────────────────────
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
      invalidateVacancyEcosystem(queryClient, variables.vcode);
    },
  });
}

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
      invalidateVacancyEcosystem(queryClient, variables.vcode);
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
      invalidateVacancyEcosystem(queryClient);
    },
  });
}

