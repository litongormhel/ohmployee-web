import { createClient } from "@/lib/supabase/client";
import { useQuery } from "@tanstack/react-query";

export interface SignupRoleOption {
  id: string;
  role_name: string;
}

export interface SignupGroupOption {
  id: string;
  group_name: string;
}

export interface SignupAccountOption {
  id: string;
  account_name: string;
  group_id: string;
}

export interface SignupOptionsResponse {
  roles: SignupRoleOption[];
  groups: SignupGroupOption[];
  accounts: SignupAccountOption[];
  is_registration_enabled?: boolean;
}

export interface SignupPayload {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  middleName: string;
  mobileNumber: string;
  requestedRoleId: string;
  groupIds: string[];
  accountIds: string[];
  notes?: string;
}

/**
 * Checks whether account sign-up is currently enabled in Admin Tools governance controls.
 */
export async function fetchAccountSignupStatus(): Promise<boolean> {
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("fn_check_governance_control", {
      p_control_key: "account_registration",
    });

    if (error) {
      console.warn("[signup] Error checking signup status:", error);
      // Fallback check: options RPC
      const { data: optData } = await supabase.rpc("get_request_account_signup_options");
      if (optData && typeof (optData as Record<string, unknown>).is_registration_enabled === "boolean") {
        return Boolean((optData as Record<string, unknown>).is_registration_enabled);
      }
      return true; // fail-open default
    }

    return Boolean(data);
  } catch (err) {
    console.warn("[signup] Exception checking signup status:", err);
    return true;
  }
}

export function useAccountSignupStatus() {
  return useQuery({
    queryKey: ["auth", "account-signup-status"],
    queryFn: fetchAccountSignupStatus,
    staleTime: 30 * 1000,
  });
}

/**
 * Loads dynamic role, group, and account options for account registration.
 * Sourced via SECURITY DEFINER RPC get_request_account_signup_options().
 */
export async function fetchSignupOptions(): Promise<SignupOptionsResponse> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_request_account_signup_options");

  if (error) {
    console.error("[signup] Failed to fetch signup options:", error);
    throw new Error(error.message || "Failed to load signup options");
  }

  const raw = data as Record<string, unknown>;

  return {
    roles: (raw?.roles as SignupRoleOption[]) ?? [],
    groups: (raw?.groups as SignupGroupOption[]) ?? [],
    accounts: (raw?.accounts as SignupAccountOption[]) ?? [],
    is_registration_enabled:
      typeof raw?.is_registration_enabled === "boolean"
        ? raw.is_registration_enabled
        : true,
  };
}

export function useSignupOptions() {
  return useQuery({
    queryKey: ["auth", "signup-options"],
    queryFn: fetchSignupOptions,
    staleTime: 5 * 60 * 1000,
  });
}

/**
 * Submits an account request via Supabase Auth sign-up.
 * Trigger on_auth_user_created automatically populates public.account_requests.
 */
export async function submitAccountRequest(payload: SignupPayload): Promise<void> {
  const supabase = createClient();

  const normalizedFirst = payload.firstName.trim();
  const normalizedLast = payload.lastName.trim();
  const normalizedMiddle = payload.middleName.trim();
  const normalizedMobile = payload.mobileNumber.trim();
  const fullName = [normalizedFirst, normalizedMiddle, normalizedLast]
    .filter(Boolean)
    .join(" ");

  const { data, error } = await supabase.auth.signUp({
    email: payload.email.trim(),
    password: payload.password,
    options: {
      data: {
        first_name: normalizedFirst,
        last_name: normalizedLast,
        middle_name: normalizedMiddle,
        full_name: fullName,
        requested_role_id: payload.requestedRoleId,
        group_ids: payload.groupIds,
        account_ids: payload.accountIds,
        mobile_number: normalizedMobile,
        notes: payload.notes?.trim() || null,
      },
    },
  });

  if (error) {
    throw new Error(error.message);
  }

  // If a session was automatically issued (e.g. email confirmation off),
  // enrich the account request and sign out immediately so the unapproved user does not stay logged in.
  if (data?.session) {
    try {
      await supabase.rpc("fn_enrich_account_request", {
        p_last_name: normalizedLast,
        p_first_name: normalizedFirst,
        p_middle_name: normalizedMiddle,
        p_mobile_number: normalizedMobile,
        p_requested_role_id: payload.requestedRoleId,
        p_group_ids: payload.groupIds,
        p_account_ids: payload.accountIds,
        p_notes: payload.notes?.trim() || null,
      });
    } catch (enrichErr) {
      console.warn("[signup] Non-fatal enrich notice:", enrichErr);
    }

    try {
      await supabase.auth.signOut();
    } catch {
      // ignore
    }
  }
}

/**
 * Sends a password reset email via Supabase Auth resetPasswordForEmail.
 */
export async function sendPasswordResetEmail(email: string): Promise<void> {
  const supabase = createClient();
  const origin = typeof window !== "undefined" ? window.location.origin : "http://localhost:3000";
  const redirectTo = `${origin}/reset-password`;

  const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
    redirectTo,
  });

  if (error) {
    throw new Error(error.message);
  }
}

/**
 * Updates the user's password using Supabase Auth updateUser.
 */
export async function updateUserPassword(newPassword: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.auth.updateUser({
    password: newPassword,
  });

  if (error) {
    throw new Error(error.message);
  }
}
