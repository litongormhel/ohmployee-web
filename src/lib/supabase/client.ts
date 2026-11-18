"use client";

import { createClient as createSupabaseClient, type SupabaseClient } from "@supabase/supabase-js";

let cachedClient: SupabaseClient | null = null;

function isValidHttpUrl(candidate?: string | null): boolean {
  if (!candidate || typeof candidate !== "string") {
    return false;
  }
  try {
    const parsed = new URL(candidate);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

/**
 * Checks whether Supabase environment variables are present and validly formatted.
 */
export function isSupabaseConfigured(): boolean {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();
  return Boolean(url && key && isValidHttpUrl(url));
}

/**
 * Returns a cached browser SupabaseClient instance.
 * Reads credentials strictly from environment variables (NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY).
 * Hardcoded API keys are strictly forbidden.
 */
export function createClient(): SupabaseClient {
  if (cachedClient) {
    return cachedClient;
  }

  const finalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const finalKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();

  if (!finalUrl || !finalKey || !isValidHttpUrl(finalUrl)) {
    const errorMsg =
      "[supabase] Missing or invalid NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY. Please verify your environment (.env) configuration.";
    console.error(errorMsg);
    throw new Error(errorMsg);
  }

  try {
    cachedClient = createSupabaseClient(finalUrl, finalKey);
    return cachedClient;
  } catch (err) {
    console.error("[supabase] Critical exception creating Supabase client instance:", err);
    throw err;
  }
}
