import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";

export interface DetailedAccountPosition {
  positionId: string;
  positionName: string;
  positionCode: string | null;
  isActive: boolean;
  mappedAt: string | null;
  activeEmployeeCount: number;
  openVacancyCount: number;
}

export interface MasterPositionItem {
  id: string;
  positionName: string;
  positionCode: string | null;
  isActive: boolean;
}

export interface ManageAccountPositionPayload {
  action: "link" | "create_and_link" | "unlink";
  accountId: string;
  positionId?: string | null;
  positionName?: string | null;
}

export interface ManageAccountPositionResult {
  success: boolean;
  action: string;
  account_id: string;
  account_name: string;
  position_id: string;
  position_name: string;
  message: string;
}

/**
 * Fetch detailed positions for a given account with active employee and vacancy usage counts.
 */
export async function fetchAccountPositionsDetailed(
  accountId?: string | null
): Promise<DetailedAccountPosition[]> {
  if (!accountId) return [];
  const supabase = createClient();

  const { data, error } = await supabase.rpc("get_account_positions_detailed", {
    p_account_id: accountId,
  });

  if (error) {
    console.error("[PostgREST Schema Error] fetchAccountPositionsDetailed:", {
      message: error.message,
      code: error.code,
      details: error.details,
      hint: error.hint,
    });
    throw new Error(error.message || "Failed to load account positions.");
  }

  if (!data || !Array.isArray(data)) return [];

  return (data as Record<string, unknown>[]).map((row) => ({
    positionId: String(row.position_id ?? ""),
    positionName: String(row.position_name ?? ""),
    positionCode: row.position_code ? String(row.position_code) : null,
    isActive: Boolean(row.is_active ?? true),
    mappedAt: row.mapped_at ? String(row.mapped_at) : null,
    activeEmployeeCount: Number(row.active_employee_count ?? 0),
    openVacancyCount: Number(row.open_vacancy_count ?? 0),
  }));
}

/**
 * Fetch all active positions in the master catalog.
 */
export async function fetchMasterPositions(): Promise<MasterPositionItem[]> {
  const supabase = createClient();

  const { data, error } = await supabase
    .from("positions")
    .select("id, position_name, position_code, is_active")
    .eq("is_active", true)
    .order("position_name", { ascending: true });

  if (error) {
    console.error("[PostgREST Schema Error] fetchMasterPositions:", error);
    throw new Error(error.message || "Failed to load master positions.");
  }

  if (!data) return [];

  return data.map((p) => ({
    id: String(p.id),
    positionName: String(p.position_name || ""),
    positionCode: p.position_code ? String(p.position_code) : null,
    isActive: Boolean(p.is_active),
  }));
}

/**
 * Perform atomic link, create_and_link, or unlink mutation.
 */
export async function mutateManageAccountPosition(
  payload: ManageAccountPositionPayload
): Promise<ManageAccountPositionResult> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("manage_account_position", {
    p_action: payload.action,
    p_account_id: payload.accountId,
    p_position_id: payload.positionId ?? null,
    p_position_name: payload.positionName ?? null,
  });

  if (error) {
    console.error("[PostgREST Schema Error] manage_account_position:", error);
    throw new Error(error.message || "Failed to update account position.");
  }

  return data as ManageAccountPositionResult;
}

// ── Query Hooks ─────────────────────────────────────────────────────────────

export function useAccountPositionsDetailedQuery(accountId?: string | null) {
  return useQuery({
    queryKey: ["account-positions-detailed", accountId],
    queryFn: () => fetchAccountPositionsDetailed(accountId),
    enabled: Boolean(accountId),
  });
}

export function useMasterPositionsQuery() {
  return useQuery({
    queryKey: ["master-positions-catalog"],
    queryFn: () => fetchMasterPositions(),
    staleTime: 60_000,
  });
}

export function useManageAccountPositionMutation(accountId?: string | null) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: mutateManageAccountPosition,
    onSuccess: () => {
      if (accountId) {
        queryClient.invalidateQueries({
          queryKey: ["account-positions-detailed", accountId],
        });
        queryClient.invalidateQueries({
          queryKey: ["account-position-options", accountId],
        });
      }
      queryClient.invalidateQueries({
        queryKey: ["account-position-options"],
      });
      queryClient.invalidateQueries({
        queryKey: ["headcountFormOptions"],
      });
      queryClient.invalidateQueries({
        queryKey: ["master-positions-catalog"],
      });
    },
  });
}
