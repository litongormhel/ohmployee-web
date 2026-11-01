import { createClient as createSupabaseClient, type SupabaseClient, type User } from "@supabase/supabase-js";

const STAGING_URL = "https://qqiiznmqxfoamqytjica.supabase.co";
const STAGING_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFxaWl6bm1xeGZvYW1xeXRqaWNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxODQ2NjksImV4cCI6MjA5Nzc2MDY2OX0.e4v0-wkAwchas5NMF7QIDvUDW32Y7V7Rl8WF4_BC0OA";

export type ScopedServerClientResult = {
  supabase: SupabaseClient | null;
  user: User | null;
};

/**
 * Creates a scoped Supabase client tied strictly to the requesting user's Bearer JWT session.
 * Enforces PostgreSQL Row-Level Security (RLS) and user RBAC permissions.
 * NEVER uses SUPABASE_SERVICE_ROLE_KEY.
 */
export async function createScopedServerClient(
  authHeader: string | null
): Promise<ScopedServerClientResult> {
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return { supabase: null, user: null };
  }

  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return { supabase: null, user: null };
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() || STAGING_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim() || STAGING_ANON_KEY;

  const client = createSupabaseClient(url, anonKey, {
    global: {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const {
    data: { user },
    error,
  } = await client.auth.getUser(token);

  if (error || !user) {
    return { supabase: null, user: null };
  }

  return { supabase: client, user };
}
