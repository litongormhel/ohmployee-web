import type { PostgrestError } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

export type FreezeModeStatus = {
  isReadOnlyEmergencyActive: boolean;
  activatedAt: string | null;
  activatedByName: string | null;
  reason: string | null;
};

export type FreezeModeErrorKind = "retryable";

export class FreezeModeError extends Error {
  kind: FreezeModeErrorKind;

  constructor(kind: FreezeModeErrorKind, message: string) {
    super(message);
    this.name = "FreezeModeError";
    this.kind = kind;
  }
}

function asObject(value: unknown): Record<string, unknown> {
  return value && !Array.isArray(value) && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown) {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function throwFreezeModeError(error: PostgrestError): never {
  if (process.env.NODE_ENV !== "production") {
    console.error("[freeze rpc error]", error.code, error.message);
  }
  throw new FreezeModeError("retryable", error.message);
}

export async function getWebFreezeModeStatus(): Promise<FreezeModeStatus> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_web_freeze_mode_status");

  if (error) {
    throwFreezeModeError(error);
  }

  const row = asObject(Array.isArray(data) ? data[0] : data);

  return {
    isReadOnlyEmergencyActive: row.is_read_only_emergency_active === true,
    activatedAt: asString(row.activated_at),
    activatedByName: asString(row.activated_by_name),
    reason: asString(row.reason),
  };
}
