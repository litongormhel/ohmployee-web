"use client";

import { createClient as createSupabaseClient, type SupabaseClient } from "@supabase/supabase-js";

const STAGING_URL = "https://qqiiznmqxfoamqytjica.supabase.co";
const STAGING_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxaWl6bm1xeGZvYW1xeXRqaWNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxODQ2NjksImV4cCI6MjA5Nzc2MDY2OX0.e4v0-wkAwchas5NMF7QIDvUDW32Y7V7Rl8WF4_BC0OA";

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

function isVercelProduction(): boolean {
  if (process.env.NEXT_PUBLIC_VERCEL_ENV === "production") {
    return true;
  }
  if (typeof window !== "undefined" && window.location.hostname === "ohmployee-web.vercel.app") {
    return true;
  }
  return false;
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
 * When on Vercel production, missing credentials or staging references throw immediately
 * to guarantee production never operates against staging/test data.
 */
export function createClient(): SupabaseClient {
  if (cachedClient) {
    return cachedClient;
  }

  let finalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  let finalKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();

  if (isVercelProduction()) {
    if (!finalUrl || !finalKey || !isValidHttpUrl(finalUrl)) {
      const errMsg =
        "[supabase] FATAL: NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY must be configured on Vercel production. Staging fallback is disabled in production.";
      console.error(errMsg);
      throw new Error(errMsg);
    }
    if (finalUrl.includes("qqiiznmqxfoamqytjica")) {
      const errMsg =
        "[supabase] FATAL: Staging Supabase URL detected on Vercel production. Production must point to production Supabase (rwxelulyapjgaarlwkus).";
      console.error(errMsg);
      throw new Error(errMsg);
    }
  }

  if (!finalUrl || !finalKey || !isValidHttpUrl(finalUrl)) {
    console.error(
      `[supabase] ACTION REQUIRED: Supabase client credentials are missing or malformed!\n` +
        `  NEXT_PUBLIC_SUPABASE_URL: ${finalUrl || "<undefined>"}\n` +
        `  NEXT_PUBLIC_SUPABASE_ANON_KEY: ${
          finalKey ? `<set (length: ${finalKey.length})>` : "<undefined>"
        }\n` +
        (finalUrl && !isValidHttpUrl(finalUrl) ? "  Reason: URL must start with http:// or https://\n" : "") +
        `  Resolution: Configure NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in your hosting environment (e.g. Vercel Project Settings > Environment Variables).`
    );

    console.warn(
      `[supabase] Applying graceful fallback to STAGING (${STAGING_URL}) for non-production workspace bootstrap.`
    );

    finalUrl = STAGING_URL;
    finalKey = STAGING_ANON_KEY;
  }

  try {
    cachedClient = createSupabaseClient(finalUrl, finalKey);
    return cachedClient;
  } catch (err) {
    console.error("[supabase] Critical exception creating Supabase client instance:", err);
    throw err;
  }
}
