"use client";

import { createClient as createSupabaseClient, type SupabaseClient } from "@supabase/supabase-js";

export const STAGING_URL = "https://qqiiznmqxfoamqytjica.supabase.co";
export const STAGING_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxaWl6bm1xeGZvYW1xeXRqaWNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxODQ2NjksImV4cCI6MjA5Nzc2MDY2OX0.e4v0-wkAwchas5NMF7QIDvUDW32Y7V7Rl8WF4_BC0OA";

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
 * Checks whether Supabase environment variables are present and validly formatted,
 * or whether the default staging fallback is active.
 */
export function isSupabaseConfigured(): boolean {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() || STAGING_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim() || STAGING_ANON_KEY;
  return Boolean(url && key && isValidHttpUrl(url));
}

/**
 * Returns a cached browser SupabaseClient instance.
 * Reads credentials from environment variables (NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY),
 * falling back gracefully to the Staging project if hosting environment variables are omitted.
 */
export function createClient(): SupabaseClient {
  if (cachedClient) {
    return cachedClient;
  }

  let finalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  let finalKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();

  if (!finalUrl || !finalKey || !isValidHttpUrl(finalUrl)) {
    console.warn(
      `[supabase] No explicit environment credentials found; applying default STAGING connection (${STAGING_URL}).`
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
