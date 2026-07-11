-- OHM2026_0043
-- Fix Store Master import approval commits against the current stores schema.
--
-- Root cause: store_import_rows still stages the CSV employment type in its
-- legacy column named "type", but public.stores now stores that value in
-- "employment_type". Approval RPCs were still inserting/updating the old store
-- type column,
-- which no longer exists on the current schema.

CREATE OR REPLACE FUNCTION public.approve_store_import_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_batch  public.store_import_batches%ROWTYPE;
  v_inserted int := 0;
  v_updated  int := 0;
  v_row    record;
  v_existing uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: super admin only';
  END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)', v_batch.status;
  END IF;
  IF v_batch.invalid_rows > 0 THEN
    RAISE EXCEPTION 'INVALID_STATE: batch contains invalid rows';
  END IF;

  FOR v_row IN
    SELECT * FROM public.store_import_rows
     WHERE batch_id = p_batch_id AND validation_status = 'valid'
     ORDER BY row_number
  LOOP
    SELECT id INTO v_existing FROM public.stores
      WHERE lower(vcode) = lower(v_row.vcode) AND status='active' LIMIT 1;

    IF v_existing IS NULL THEN
      INSERT INTO public.stores (
        vcode, store_name, area_province, area_city, employment_type, with_penalty,
        group_id, account_id, status, created_by, updated_by,
        approved_by, approved_at, source_import_id
      ) VALUES (
        v_row.vcode, v_row.store_name, v_row.area_province, v_row.area_city,
        v_row.type, v_row.with_penalty,
        v_batch.selected_group_id, v_batch.selected_account_id, 'active',
        v_uid, v_uid, v_uid, now(), p_batch_id
      ) RETURNING id INTO v_existing;
      v_inserted := v_inserted + 1;

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'stores', 'INSERT', v_existing,
              jsonb_build_object('vcode', v_row.vcode, 'source_import_id', p_batch_id));
    ELSE
      UPDATE public.stores
         SET store_name       = v_row.store_name,
             area_province    = v_row.area_province,
             area_city        = v_row.area_city,
             employment_type  = v_row.type,
             with_penalty     = v_row.with_penalty,
             group_id         = v_batch.selected_group_id,
             account_id       = v_batch.selected_account_id,
             status           = 'active',
             updated_by       = v_uid,
             approved_by      = v_uid,
             approved_at      = now(),
             source_import_id = p_batch_id
       WHERE id = v_existing;
      v_updated := v_updated + 1;

      INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
      VALUES (v_uid, 'stores', 'UPDATE', v_existing,
              jsonb_build_object('vcode', v_row.vcode, 'source_import_id', p_batch_id));
    END IF;
  END LOOP;

  UPDATE public.store_import_batches
     SET status='approved', approved_by=v_uid, approved_at=now(), updated_at=now()
   WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'store_import_batches', 'APPROVAL', p_batch_id,
          jsonb_build_object('inserted', v_inserted, 'updated', v_updated));

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'status', 'approved',
    'inserted', v_inserted,
    'updated', v_updated
  );
END$function$;

CREATE OR REPLACE FUNCTION public.approve_store_import_batch_rbac(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_batch public.store_import_batches%ROWTYPE;
  v_row record; v_existing uuid; v_inserted int := 0; v_updated int := 0;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_batch.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'INVALID_STATE: only pending_approval can be approved (current=%)', v_batch.status USING ERRCODE='22023'; END IF;
  IF v_batch.invalid_rows > 0 THEN
    RAISE EXCEPTION 'INVALID_STATE: batch contains invalid rows' USING ERRCODE='22023'; END IF;

  FOR v_row IN SELECT * FROM public.store_import_rows
    WHERE batch_id=p_batch_id AND validation_status='valid' ORDER BY row_number
  LOOP
    SELECT id INTO v_existing FROM public.stores
     WHERE lower(vcode)=lower(v_row.vcode) AND status='active' LIMIT 1;
    IF v_existing IS NULL THEN
      INSERT INTO public.stores (vcode,store_name,area_province,area_city,employment_type,with_penalty,
        group_id,account_id,status,created_by,updated_by,approved_by,approved_at,source_import_id)
      VALUES (v_row.vcode,v_row.store_name,v_row.area_province,v_row.area_city,v_row.type,v_row.with_penalty,
        v_batch.selected_group_id,v_batch.selected_account_id,'active',v_uid,v_uid,v_uid,now(),p_batch_id)
      RETURNING id INTO v_existing;
      v_inserted := v_inserted+1;
    ELSE
      UPDATE public.stores SET store_name=v_row.store_name,area_province=v_row.area_province,
        area_city=v_row.area_city,employment_type=v_row.type,with_penalty=v_row.with_penalty,
        group_id=v_batch.selected_group_id,account_id=v_batch.selected_account_id,status='active',
        updated_by=v_uid,approved_by=v_uid,approved_at=now(),source_import_id=p_batch_id
      WHERE id=v_existing;
      v_updated := v_updated+1;
    END IF;
  END LOOP;

  UPDATE public.store_import_batches
     SET status='approved',approved_by=v_uid,approved_at=now(),updated_at=now()
   WHERE id=p_batch_id;

  INSERT INTO public.audit_logs(actor_id,module,action,record_id,new_data)
  VALUES (v_uid,'store_import_batches','APPROVAL',p_batch_id,
          jsonb_build_object('inserted',v_inserted,'updated',v_updated,'rbac','ha_sa'));

  RETURN jsonb_build_object('batch_id',p_batch_id,'status','approved','inserted',v_inserted,'updated',v_updated);
END$function$;

CREATE OR REPLACE FUNCTION public.reject_store_import_batch(p_batch_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_batch public.store_import_batches%ROWTYPE;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED: super admin only';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required';
  END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed','draft_uploaded') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status;
  END IF;

  UPDATE public.store_import_batches
     SET status='rejected', rejected_by=v_uid, rejected_at=now(),
         rejection_reason=p_reason, updated_at=now()
   WHERE id=p_batch_id;

  INSERT INTO public.audit_logs(actor_id, module, action, record_id, new_data)
  VALUES (v_uid, 'store_import_batches', 'APPROVAL', p_batch_id,
          jsonb_build_object('decision','rejected','reason',p_reason));

  RETURN jsonb_build_object('batch_id',p_batch_id,'status','rejected');
END$function$;

CREATE OR REPLACE FUNCTION public.reject_store_import_batch_rbac(p_batch_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_batch public.store_import_batches%ROWTYPE;
BEGIN
  IF NOT public.fn_can_approve_plantilla_import() THEN
    RAISE EXCEPTION 'forbidden: Head Admin or Super Admin required' USING ERRCODE='42501'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason))=0 THEN
    RAISE EXCEPTION 'INVALID_INPUT: rejection reason required' USING ERRCODE='22023'; END IF;

  SELECT * INTO v_batch FROM public.store_import_batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BATCH_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_batch.status NOT IN ('pending_approval','validation_failed','draft_uploaded') THEN
    RAISE EXCEPTION 'INVALID_STATE: cannot reject batch in % state', v_batch.status USING ERRCODE='22023'; END IF;

  UPDATE public.store_import_batches
     SET status='rejected',rejected_by=v_uid,rejected_at=now(),rejection_reason=p_reason,updated_at=now()
   WHERE id=p_batch_id;

  INSERT INTO public.audit_logs(actor_id,module,action,record_id,new_data)
  VALUES (v_uid,'store_import_batches','APPROVAL',p_batch_id,
          jsonb_build_object('decision','rejected','reason',p_reason,'rbac','ha_sa'));

  RETURN jsonb_build_object('batch_id',p_batch_id,'status','rejected');
END$function$;

REVOKE ALL ON FUNCTION public.approve_store_import_batch(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_store_import_batch_rbac(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_store_import_batch(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_store_import_batch_rbac(uuid,text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.approve_store_import_batch(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_store_import_batch_rbac(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_store_import_batch(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_store_import_batch_rbac(uuid,text) TO authenticated;
