-- OHM2026_0067 — HC Request Archive Super Admin UPDATE Policy
-- Root cause: headcount_requests had no UPDATE RLS policy; direct
-- .update() calls from authenticated clients were silently blocked,
-- returning 0 rows and surfacing as PGRST116 on the client.
--
-- Fix: add a permissive UPDATE policy restricted to Super Admin only.
-- All other UPDATE paths (approve, reject, create_vcode) continue
-- through SECURITY DEFINER RPCs and are unaffected.
--
-- Safe: additive-only. No existing policy, column, or RPC is modified.

CREATE POLICY "hcreq_update_super_admin_archive"
  ON public.headcount_requests
  AS PERMISSIVE
  FOR UPDATE
  TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

COMMENT ON POLICY "hcreq_update_super_admin_archive" ON public.headcount_requests
  IS 'Allows Super Admin to update headcount_requests rows directly (e.g. archive). '
     'Approve/reject/vcode paths remain RPC-only and are unaffected.';
