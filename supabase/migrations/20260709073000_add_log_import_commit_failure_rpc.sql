-- ============================================================================
-- New RPC: log_import_commit_failure(p_batch_id uuid, p_error_detail text)
-- Client-side re-log of a caught approve_plantilla_import_batch() commit
-- failure. approve_plantilla_import_batch() RAISEs on failure (its own
-- transaction rolls back, so any status/commit_error_detail write it
-- attempts is undone too) — this RPC is called by the Flutter client AFTER
-- it catches that exception, in its own separate transaction, so the
-- failure detail actually persists.
-- Migration: 20260709073000_add_log_import_commit_failure_rpc.sql
-- Task: ohm#8kfp3rmz (Option C — client-side re-log, no dblink/credentials)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.log_import_commit_failure(
  p_batch_id uuid,
  p_error_detail text
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  UPDATE public.plantilla_import_batches
     SET status = 'commit_failed',
         commit_error_detail = p_error_detail,
         updated_at = now()
   WHERE id = p_batch_id;
$function$;

GRANT EXECUTE ON FUNCTION public.log_import_commit_failure(uuid, text) TO authenticated;
