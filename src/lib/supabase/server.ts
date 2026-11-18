import { createClient as createSupabaseClient, type SupabaseClient, type User } from "@supabase/supabase-js";

export type ScopedServerClientResult = {
  supabase: SupabaseClient | null;
  user: User | null;
};

/**
 * Creates a scoped Supabase client tied strictly to the requesting user's Bearer JWT session.
 * Enforces PostgreSQL Row-Level Security (RLS) and user RBAC permissions.
 * Reads environment variables strictly; NEVER hardcodes credentials and NEVER uses SUPABASE_SERVICE_ROLE_KEY.
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

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.trim();

  if (!url || !anonKey) {
    console.error(
      "[supabase] createScopedServerClient: missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY"
    );
    return { supabase: null, user: null };
  }

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
