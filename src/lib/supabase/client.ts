"use client";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";

export function createClient() {
  let supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  let supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Local development fail-safe fallback to staging when env variables are missing or unset
  if (!supabaseUrl || !supabaseAnonKey) {
    if (process.env.NODE_ENV === "development") {
      console.warn("[supabase] Client variables missing. Failing safe to STAGING (qqiiznmqxfoamqytjica.supabase.co).");
      supabaseUrl = "https://qqiiznmqxfoamqytjica.supabase.co";
      supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxaWl6bm1xeGZvYW1xeXRqaWNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxODQ2NjksImV4cCI6MjA5Nzc2MDY2OX0.e4v0-wkAwchas5NMF7QIDvUDW32Y7V7Rl8WF4_BC0OA";
    } else {
      throw new Error(
        "Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY.",
      );
    }
  }

  return createSupabaseClient(supabaseUrl, supabaseAnonKey);
}
