import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export type QuotaErrorKind = "unauthorized" | "validation" | "not_found" | "generic";

export class QuotaDataError extends Error {
  kind: QuotaErrorKind;

  constructor(kind: QuotaErrorKind, message: string) {
    super(message);
    this.name = "QuotaDataError";
    this.kind = kind;
  }
}

export type VcodeCommitments = {
  vcode: string;
  currentQuota: number;
  occupied: number;
  hrProcessing: number;
  pipeline: number;
  commitments: number;
  safetyFloor: number;
  storeName: string | null;
  positionTitle: string | null;
  accountId: string | null;
  storeId: string | null;
  positionId: string | null;
};

export type ReviseQuotaParams = {
  vcode: string;
  newQuota: number;
  reason: string;
  sourceRequestId?: string | null;
};

export type ReviseQuotaResult = {
  ok: boolean;
  success: boolean;
  vcode: string;
  previous_quota: number;
  new_quota: number;
  delta: number;
};

export type SubmitAmendmentParams = {
  targetVcode: string;
  proposedQuota: number;
  justification: string;
  currentQuota?: number;
  accountId?: string | null;
  storeId?: string | null;
  positionId?: string | null;
};

export type SubmitAmendmentResult = {
  ok: boolean;
  success: boolean;
  request_id: string;
  target_vcode: string;
  previous_target: number;
  proposed_target: number;
  delta: number;
};

export type StoreVacancyItem = {
  id: string;
  vcode: string;
  position: string | null;
  requiredHeadcount: number;
  status: string | null;
  accountId: string | null;
  storeId: string | null;
  positionId: string | null;
};

/**
 * Calculates live commitments and safety floor for a given vacancy vcode:
 * Safety Floor = max(1, Occupied + HR Processing + Pipeline)
 */
export async function getVcodeQuotaDetails(vcode: string): Promise<VcodeCommitments> {
  const supabase = createClient();

  // 1. Fetch vacancy record
  const { data: vac, error: vacError } = await supabase
    .from("vacancies")
    .select("required_headcount, account_id, store_id, position_id, position, store_name")
    .eq("vcode", vcode)
    .maybeSingle();

  if (vacError) {
    throw new QuotaDataError("generic", vacError.message);
  }

  // 2. Fetch plantilla slots associated with this vcode
  const { data: slots, error: slotsError } = await supabase
    .from("plantilla_slots")
    .select("slot_status")
    .eq("legacy_vcode", vcode);

  if (slotsError) {
    throw new QuotaDataError("generic", slotsError.message);
  }

  let occupied = 0;
  let hrProcessing = 0;
  let pipeline = 0;

  for (const slot of slots ?? []) {
    const status = (slot.slot_status ?? "").toLowerCase();
    if (status === "occupied" || status === "filled") {
      occupied++;
    } else if (status === "hr_processing") {
      hrProcessing++;
    } else if (status === "pipeline") {
      pipeline++;
    }
  }

  const currentQuota = Math.round(Number(vac?.required_headcount ?? 1)) || 1;
  const commitments = occupied + hrProcessing + pipeline;
  const safetyFloor = Math.max(1, commitments);

  return {
    vcode,
    currentQuota,
    occupied,
    hrProcessing,
    pipeline,
    commitments,
    safetyFloor,
    storeName: vac?.store_name ?? null,
    positionTitle: vac?.position ?? null,
    accountId: vac?.account_id ?? null,
    storeId: vac?.store_id ?? null,
    positionId: vac?.position_id ?? null,
  };
}

/**
 * Direct quota revision by Data Team and Admins.
 * Executes public.revise_vcode_headcount_quota RPC.
 */
export async function reviseVcodeHeadcountQuota(
  vcode: string,
  newQuota: number,
  reason: string,
  sourceRequestId?: string | null,
): Promise<ReviseQuotaResult> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("revise_vcode_headcount_quota", {
    p_vcode: vcode,
    p_new_target: newQuota,
    p_justification: reason.trim(),
    p_source_request_id: sourceRequestId ?? null,
  });

  if (error) {
    if (error.code === "42501") {
      throw new QuotaDataError(
        "unauthorized",
        error.message || "Unauthorized: Only Data Team and Admin roles may revise headcount quota.",
      );
    }
    if (error.code === "22023") {
      throw new QuotaDataError("validation", error.message);
    }
    if (error.code === "P0002") {
      throw new QuotaDataError("not_found", error.message || "Vacancy record not found.");
    }
    throw new QuotaDataError("generic", error.message);
  }

  return data as ReviseQuotaResult;
}

/**
 * Operations amendment request pipeline.
 * Executes public.submit_headcount_amendment_request RPC.
 */
export async function submitHeadcountAmendmentRequest(
  targetVcode: string,
  proposedQuota: number,
  justification: string,
  options?: {
    currentQuota?: number;
    accountId?: string | null;
    storeId?: string | null;
    positionId?: string | null;
  },
): Promise<SubmitAmendmentResult> {
  const supabase = createClient();

  let currentQuota = options?.currentQuota;
  let accountId = options?.accountId ?? null;
  let storeId = options?.storeId ?? null;
  let positionId = options?.positionId ?? null;

  if (currentQuota === undefined || !accountId) {
    const { data: vac } = await supabase
      .from("vacancies")
      .select("required_headcount, account_id, store_id, position_id")
      .eq("vcode", targetVcode)
      .maybeSingle();

    if (vac) {
      if (currentQuota === undefined) {
        currentQuota = Math.round(Number(vac.required_headcount ?? 1)) || 1;
      }
      if (!accountId) {
        accountId = vac.account_id ?? null;
      }
      if (!storeId) {
        storeId = vac.store_id ?? null;
      }
      if (!positionId) {
        positionId = vac.position_id ?? null;
      }
    } else {
      if (currentQuota === undefined) currentQuota = 1;
    }
  }

  const { data, error } = await supabase.rpc("submit_headcount_amendment_request", {
    p_target_vcode: targetVcode,
    p_current_target: currentQuota,
    p_proposed_target: proposedQuota,
    p_reason: justification.trim(),
    p_account_id: accountId,
    p_store_id: storeId,
    p_position_id: positionId,
  });

  if (error) {
    if (error.code === "42501") {
      throw new QuotaDataError(
        "unauthorized",
        error.message || "Unauthorized: Only Ops roles and Administrators may submit quota amendment requests.",
      );
    }
    if (error.code === "22023") {
      throw new QuotaDataError("validation", error.message);
    }
    if (error.code === "P0002") {
      throw new QuotaDataError("not_found", error.message || "Vacancy record not found.");
    }
    throw new QuotaDataError("generic", error.message);
  }

  return data as SubmitAmendmentResult;
}

/**
 * Fetches all active vacancies for a store.
 */
export async function getStoreVacancies(storeId: string): Promise<StoreVacancyItem[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("vacancies")
    .select("id, vcode, position, required_headcount, status, account_id, store_id, position_id")
    .eq("store_id", storeId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  if (error) {
    throw new QuotaDataError("generic", error.message);
  }

  return (data ?? []).map((row) => ({
    id: row.id,
    vcode: row.vcode,
    position: row.position,
    requiredHeadcount: Math.round(Number(row.required_headcount ?? 1)) || 1,
    status: row.status,
    accountId: row.account_id,
    storeId: row.store_id,
    positionId: row.position_id,
  }));
}

// ─── React Query Hooks ───────────────────────────────────────────────────────

export function useVcodeQuotaDetails(vcode: string | null) {
  return useQuery({
    queryKey: ["quota-details", vcode],
    queryFn: () => getVcodeQuotaDetails(vcode!),
    enabled: !!vcode,
  });
}

export function useStoreVacancies(storeId: string | null) {
  return useQuery({
    queryKey: ["store-vacancies", storeId],
    queryFn: () => getStoreVacancies(storeId!),
    enabled: !!storeId,
  });
}

export function useReviseHeadcountQuota() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: ReviseQuotaParams) =>
      reviseVcodeHeadcountQuota(
        params.vcode,
        params.newQuota,
        params.reason,
        params.sourceRequestId,
      ),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-detail"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["quota-details"] });
      queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
    },
  });
}

export function useSubmitHeadcountAmendment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (params: SubmitAmendmentParams) =>
      submitHeadcountAmendmentRequest(
        params.targetVcode,
        params.proposedQuota,
        params.justification,
        {
          currentQuota: params.currentQuota,
          accountId: params.accountId,
          storeId: params.storeId,
          positionId: params.positionId,
        },
      ),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["vacancies"] });
      queryClient.invalidateQueries({ queryKey: ["vacancy-detail"] });
      queryClient.invalidateQueries({ queryKey: ["plantilla"] });
      queryClient.invalidateQueries({ queryKey: ["quota-details"] });
      queryClient.invalidateQueries({ queryKey: ["store-vacancies"] });
    },
  });
}
