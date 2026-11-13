import { execSync } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";

const STAGING_PROJECT_REF = "qqiiznmqxfoamqytjica";

function executeRoleBlock(roleName, sql) {
  const tmpFile = path.join(os.tmpdir(), `cg_qa_${Date.now()}_${Math.random().toString(36).slice(2, 7)}.sql`);
  fs.writeFileSync(tmpFile, sql, "utf8");

  try {
    const stdout = execSync(
      `npx supabase db query --remote -f "${tmpFile}" --yes`,
      {
        cwd: process.cwd(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      }
    );

    const jsonStart = stdout.indexOf("{");
    if (jsonStart !== -1) {
      const parsed = JSON.parse(stdout.slice(jsonStart));
      return parsed.rows || [];
    }
    return [];
  } catch (err) {
    const combined = (err.stdout || "") + "\n" + (err.stderr || "") + "\n" + (err.message || "");
    const marker = "SANITY_CHECK_ROLLBACK_SUCCESS:";
    const idx = combined.indexOf(marker);
    if (idx !== -1) {
      const sub = combined.slice(idx + marker.length).trim();
      const bracketStart = sub.indexOf("[");
      const bracketEnd = sub.lastIndexOf("]");
      if (bracketStart !== -1 && bracketEnd !== -1) {
        let jsonStr = sub.slice(bracketStart, bracketEnd + 1);
        try {
          return JSON.parse(jsonStr);
        } catch {
          try {
            const cleaned = jsonStr.replace(/\\+"/g, '"');
            return JSON.parse(cleaned);
          } catch (e2) {
            console.error("RAW JSON STRING FAILED TO PARSE:\n", jsonStr);
            throw e2;
          }
        }
      }
    }
    console.error(`DEBUG SQL ERROR FOR ${roleName}:\n`, combined);
    throw err;
  } finally {
    try {
      if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
    } catch {}
  }
}

async function runCoverageGroupSanity() {
  console.log("===============================================================================");
  console.log("     COVERAGE GROUP MODULE: SANITY CHECK AGAINST LIVE STAGING DATABASE         ");
  console.log(`     Target Database : Staging (${STAGING_PROJECT_REF})`);
  console.log("===============================================================================\n");

  const results = [];

  // =========================================================================
  // 1. SUPER ADMIN / HEAD ADMIN BLOCK
  // =========================================================================
  const haSql = `
    DO $$
    DECLARE
      v_ha_uid uuid := '59917295-9844-47d4-bcd9-03742b1c9c8d'; -- Sy Bolinas (Head Admin)
      v_enc_uid uuid := '3ca941ac-8d46-4096-b950-d734e85a4974'; -- GROUP TWO (Encoder)
      v_account_id uuid;
      v_pos_id uuid;
      v_pos_name text;

      v_s1 uuid := gen_random_uuid();
      v_s2 uuid := gen_random_uuid();
      v_s3 uuid := gen_random_uuid();
      v_s4 uuid := gen_random_uuid();
      v_s5 uuid := gen_random_uuid();

      v_cg1_id uuid;
      v_cg1_code text;
      v_cg2_id uuid;
      v_req_id uuid;
      v_res json;
      v_out jsonb := '[]'::jsonb;
    BEGIN
      SELECT id INTO v_account_id FROM public.accounts WHERE is_active = true AND lower(coalesce(status, 'active')) <> 'archived' LIMIT 1;
      SELECT id, position_name INTO v_pos_id, v_pos_name FROM public.positions WHERE is_active = true LIMIT 1;

      INSERT INTO public.user_scopes (id, user_id, account_id, is_active)
      VALUES (gen_random_uuid(), '35676691-0d53-4e99-b5f2-1044f30e17f4', v_account_id, true);

      INSERT INTO public.stores (id, store_name, vcode, account_id, island_group, is_active, status, with_penalty)
      VALUES 
        (v_s1, 'QA HA S1', 'QA-HA-1-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s2, 'QA HA S2', 'QA-HA-2-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s3, 'QA HA S3', 'QA-HA-3-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s4, 'QA HA S4', 'QA-HA-4-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s5, 'QA HA S5', 'QA-HA-5-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false);

      INSERT INTO public.plantilla_slots (id, store_id, account_id, position, employment_type, is_roving, slot_status, slot_ordinal)
      VALUES 
        (gen_random_uuid(), v_s1, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s2, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s3, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s4, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s5, v_account_id, v_pos_name, 'Regular', false, 'open', 1);

      -- HA: Create Coverage Group (Direct Execution)
      PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);

      BEGIN
        v_res := public.create_coverage_group(v_account_id, v_pos_id, 'Regular', 'QA HA Clust', ARRAY[v_s1, v_s2], v_s1);
        v_cg1_id := (v_res->>'coverage_group_id')::uuid;
        v_cg1_code := v_res->>'coverage_code';
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Create Coverage Group', 'status', 'passed', 'details', 'Direct execution created ' || coalesce(v_cg1_code, ''));
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Create Coverage Group', 'status', 'failed', 'details', SQLERRM);
      END;

      -- HA: Add Store
      BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);
        SELECT (public.create_coverage_request('add_store'::public.request_type, jsonb_build_object('store_ids', jsonb_build_array(v_s3)), v_account_id, NULL, NULL, v_cg1_id, NULL, NULL, 'Add S3')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);

        PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);
        PERFORM public.approve_coverage_request(v_req_id, 'HA Approve Add Store'::text, NULL::jsonb);
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Add Store', 'status', 'passed', 'details', 'HA reviewed, approved, and executed Add Store');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Add Store', 'status', 'failed', 'details', SQLERRM);
      END;

      -- HA: Remove Store
      BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);
        SELECT (public.create_coverage_request('remove_store'::public.request_type, jsonb_build_object('store_ids', jsonb_build_array(v_s3)), v_account_id, NULL, NULL, v_cg1_id, NULL, NULL, 'Rem S3')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);

        PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);
        PERFORM public.approve_coverage_request(v_req_id, 'HA Approve Rem Store'::text, NULL::jsonb);
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Remove Store', 'status', 'passed', 'details', 'HA reviewed, approved, and executed Remove Store');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Remove Store', 'status', 'failed', 'details', SQLERRM);
      END;

      -- Create Aux CG2 for Merge
      v_res := public.create_coverage_group(v_account_id, v_pos_id, 'Regular', 'QA HA Aux', ARRAY[v_s4, v_s5], v_s4);
      v_cg2_id := (v_res->>'coverage_group_id')::uuid;

      -- HA: Merge Coverage Groups
      BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);
        SELECT (public.create_coverage_request('merge_coverage_groups'::public.request_type, '{}'::jsonb, v_account_id, NULL, NULL, NULL, v_cg2_id, v_cg1_id, 'Merge Aux into CG1')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);

        PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);
        PERFORM public.approve_coverage_request(v_req_id, 'HA Approve Merge'::text, NULL::jsonb);
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Merge Coverage Groups', 'status', 'passed', 'details', 'HA reviewed, approved, and executed Merge');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Merge Coverage Groups', 'status', 'failed', 'details', SQLERRM);
      END;

      -- HA: Dissolve Coverage Group
      BEGIN
        PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);
        SELECT (public.create_coverage_request('dissolve_coverage_group'::public.request_type, '{}'::jsonb, v_account_id, NULL, NULL, v_cg1_id, NULL, NULL, 'Dissolve CG1')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);

        PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);
        PERFORM public.approve_coverage_request(v_req_id, 'HA Approve Dissolve'::text, NULL::jsonb);
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Dissolve Coverage Group', 'status', 'passed', 'details', 'HA reviewed, approved, and executed Dissolve');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Super Admin / Head Admin', 'operation', 'Dissolve Coverage Group', 'status', 'failed', 'details', SQLERRM);
      END;

      RAISE EXCEPTION 'SANITY_CHECK_ROLLBACK_SUCCESS: %', v_out;
    END $$;
  `;

  // =========================================================================
  // 2. ENCODER BLOCK
  // =========================================================================
  const encSql = `
    DO $$
    DECLARE
      v_ha_uid uuid := '59917295-9844-47d4-bcd9-03742b1c9c8d'; -- Sy Bolinas (Head Admin)
      v_enc_uid uuid := '3ca941ac-8d46-4096-b950-d734e85a4974'; -- GROUP TWO (Encoder)
      v_account_id uuid;
      v_pos_id uuid;
      v_pos_name text;

      v_s1 uuid := gen_random_uuid();
      v_s2 uuid := gen_random_uuid();
      v_s3 uuid := gen_random_uuid();

      v_cg_id uuid;
      v_req_id uuid;
      v_res json;
      v_out jsonb := '[]'::jsonb;
    BEGIN
      SELECT id INTO v_account_id FROM public.accounts WHERE is_active = true AND lower(coalesce(status, 'active')) <> 'archived' LIMIT 1;
      SELECT id, position_name INTO v_pos_id, v_pos_name FROM public.positions WHERE is_active = true LIMIT 1;

      INSERT INTO public.user_scopes (id, user_id, account_id, is_active)
      VALUES (gen_random_uuid(), '35676691-0d53-4e99-b5f2-1044f30e17f4', v_account_id, true);

      INSERT INTO public.stores (id, store_name, vcode, account_id, island_group, is_active, status, with_penalty)
      VALUES 
        (v_s1, 'QA ENC S1', 'QA-ENC-1-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s2, 'QA ENC S2', 'QA-ENC-2-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s3, 'QA ENC S3', 'QA-ENC-3-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false);

      INSERT INTO public.plantilla_slots (id, store_id, account_id, position, employment_type, is_roving, slot_status, slot_ordinal)
      VALUES 
        (gen_random_uuid(), v_s1, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s2, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s3, v_account_id, v_pos_name, 'Regular', false, 'open', 1);

      -- Switch to Encoder
      PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);

      -- Encoder: Create Coverage Group (Request)
      BEGIN
        SELECT (public.create_coverage_request('create_coverage_group'::public.request_type, jsonb_build_object('store_ids', jsonb_build_array(v_s1, v_s2), 'anchor_store_id', v_s1), v_account_id, v_pos_id, 'Regular', NULL, NULL, NULL, 'Enc Create')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Create Coverage Group', 'status', 'passed', 'details', 'Request created and submitted to pending');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Create Coverage Group', 'status', 'failed', 'details', SQLERRM);
      END;

      -- HA approves so group is active for next tests
      PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);
      PERFORM public.approve_coverage_request(v_req_id, 'HA Approve'::text, NULL::jsonb);
      SELECT target_coverage_group_id INTO v_cg_id FROM public.coverage_requests WHERE id = v_req_id;

      -- Switch to Encoder
      PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);

      -- Encoder: Add Store (Request)
      BEGIN
        SELECT (public.create_coverage_request('add_store'::public.request_type, jsonb_build_object('store_ids', jsonb_build_array(v_s3)), v_account_id, NULL, NULL, v_cg_id, NULL, NULL, 'Enc Add Store')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Add Store', 'status', 'passed', 'details', 'Request created and submitted to pending');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Add Store', 'status', 'failed', 'details', SQLERRM);
      END;

      -- HA approves Add Store
      PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);
      PERFORM public.approve_coverage_request(v_req_id, 'HA Approve'::text, NULL::jsonb);

      -- Switch to Encoder
      PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);

      -- Encoder: Remove Store (Request)
      BEGIN
        SELECT (public.create_coverage_request('remove_store'::public.request_type, jsonb_build_object('store_ids', jsonb_build_array(v_s3)), v_account_id, NULL, NULL, v_cg_id, NULL, NULL, 'Enc Rem Store')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Remove Store', 'status', 'passed', 'details', 'Request created and submitted to pending');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Remove Store', 'status', 'failed', 'details', SQLERRM);
      END;

      -- HA approves Remove Store
      PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);
      PERFORM public.approve_coverage_request(v_req_id, 'HA Approve'::text, NULL::jsonb);

      -- Switch to Encoder
      PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);

      -- Encoder: Dissolve Coverage Group (Request)
      BEGIN
        SELECT (public.create_coverage_request('dissolve_coverage_group'::public.request_type, '{}'::jsonb, v_account_id, NULL, NULL, v_cg_id, NULL, NULL, 'Enc Dissolve')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Dissolve Coverage Group', 'status', 'passed', 'details', 'Request created and submitted to pending');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Dissolve Coverage Group', 'status', 'failed', 'details', SQLERRM);
      END;

      -- Encoder: Self-Approval Barrier Check
      BEGIN
        PERFORM public.approve_coverage_request(v_req_id, 'Illegal Self Approval'::text, NULL::jsonb);
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Self-Approval Barrier Check', 'status', 'failed', 'details', 'Encoder was able to approve own request');
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM ILIKE '%self-approval is not permitted%' OR SQLSTATE = '42501' THEN
          v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Self-Approval Barrier Check', 'status', 'passed', 'details', 'Barrier held firm: ' || SQLERRM);
        ELSE
          v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Self-Approval Barrier Check', 'status', 'failed', 'details', SQLERRM);
        END IF;
      END;

      RAISE EXCEPTION 'SANITY_CHECK_ROLLBACK_SUCCESS: %', v_out;
    END $$;
  `;

  // =========================================================================
  // 3. OPERATIONS BLOCK A (Create CG, Barrier Check, Tiered Review)
  // =========================================================================
  const opsSqlA = `
    DO $$
    DECLARE
      v_ha_uid uuid := '59917295-9844-47d4-bcd9-03742b1c9c8d'; -- Sy Bolinas (Head Admin)
      v_enc_uid uuid := '3ca941ac-8d46-4096-b950-d734e85a4974'; -- GROUP TWO (Encoder)
      v_om_uid uuid := '54935b05-65a1-48aa-b953-15e6c756e80e'; -- Amutan, Cherry Lou (OM)

      v_account_id uuid;
      v_pos_id uuid;
      v_pos_name text;

      v_s1 uuid := gen_random_uuid();
      v_s2 uuid := gen_random_uuid();

      v_cg_id uuid;
      v_req_id uuid;
      v_out jsonb := '[]'::jsonb;
    BEGIN
      SELECT id INTO v_account_id FROM public.accounts WHERE is_active = true AND lower(coalesce(status, 'active')) <> 'archived' LIMIT 1;
      SELECT id, position_name INTO v_pos_id, v_pos_name FROM public.positions WHERE is_active = true LIMIT 1;

      INSERT INTO public.user_scopes (id, user_id, account_id, is_active)
      VALUES 
        (gen_random_uuid(), '35676691-0d53-4e99-b5f2-1044f30e17f4', v_account_id, true),
        (gen_random_uuid(), '33c93767-45cd-4340-8319-d6d55be3ff89', v_account_id, true);

      INSERT INTO public.stores (id, store_name, vcode, account_id, island_group, is_active, status, with_penalty)
      VALUES 
        (v_s1, 'QA OPS S1', 'QA-OPS-1-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s2, 'QA OPS S2', 'QA-OPS-2-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false);

      INSERT INTO public.plantilla_slots (id, store_id, account_id, position, employment_type, is_roving, slot_status, slot_ordinal)
      VALUES 
        (gen_random_uuid(), v_s1, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s2, v_account_id, v_pos_name, 'Regular', false, 'open', 1);

      -- Switch to Operations Manager
      PERFORM set_config('request.jwt.claim.sub', v_om_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_om_uid, 'role', 'authenticated')::text, true);

      -- Operations: Create Coverage Group (Request)
      BEGIN
        SELECT (public.create_coverage_request('create_coverage_group'::public.request_type, jsonb_build_object('store_ids', jsonb_build_array(v_s1, v_s2), 'anchor_store_id', v_s1), v_account_id, v_pos_id, 'Regular', NULL, NULL, NULL, 'Ops Create')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Create Coverage Group', 'status', 'passed', 'details', 'Request created and submitted to pending');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Create Coverage Group', 'status', 'failed', 'details', SQLERRM);
      END;

      -- Operations: Approval Authority Barrier Check (Ops cannot approve)
      BEGIN
        PERFORM public.approve_coverage_request(v_req_id, 'Illegal Ops Approval'::text, NULL::jsonb);
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Approval Authority Barrier Check', 'status', 'failed', 'details', 'Ops was able to approve request');
      EXCEPTION WHEN OTHERS THEN
        IF SQLERRM ILIKE '%authorized to review%' OR SQLERRM ILIKE '%only Head Admin%' OR SQLERRM ILIKE '%self-approval is not permitted%' OR SQLSTATE = '42501' THEN
          v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Approval Authority Barrier Check', 'status', 'passed', 'details', 'Barrier held firm: ' || SQLERRM);
        ELSE
          v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Approval Authority Barrier Check', 'status', 'failed', 'details', SQLERRM);
        END IF;
      END;

      -- Tiered Review: Encoder reviews & approves Ops request!
      PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);

      BEGIN
        PERFORM public.approve_coverage_request(v_req_id, 'Encoder reviews Ops request'::text, NULL::jsonb);
        SELECT target_coverage_group_id INTO v_cg_id FROM public.coverage_requests WHERE id = v_req_id;
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Tiered Review (Approve Ops Request)', 'status', 'passed', 'details', 'Encoder successfully reviewed and approved Ops request into execution');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Encoder', 'operation', 'Tiered Review (Approve Ops Request)', 'status', 'failed', 'details', SQLERRM);
      END;

      RAISE EXCEPTION 'SANITY_CHECK_ROLLBACK_SUCCESS: %', v_out;
    END $$;
  `;

  // =========================================================================
  // 4. OPERATIONS BLOCK B (Add Store, Remove Store, Dissolve)
  // =========================================================================
  const opsSqlB = `
    DO $$
    DECLARE
      v_ha_uid uuid := '59917295-9844-47d4-bcd9-03742b1c9c8d'; -- Sy Bolinas (Head Admin)
      v_enc_uid uuid := '3ca941ac-8d46-4096-b950-d734e85a4974'; -- GROUP TWO (Encoder)
      v_om_uid uuid := '54935b05-65a1-48aa-b953-15e6c756e80e'; -- Amutan, Cherry Lou (OM)

      v_account_id uuid;
      v_pos_id uuid;
      v_pos_name text;

      v_s1 uuid := gen_random_uuid();
      v_s2 uuid := gen_random_uuid();
      v_s3 uuid := gen_random_uuid();

      v_cg_id uuid;
      v_req_id uuid;
      v_res json;
      v_out jsonb := '[]'::jsonb;
    BEGIN
      SELECT id INTO v_account_id FROM public.accounts WHERE is_active = true AND lower(coalesce(status, 'active')) <> 'archived' LIMIT 1;
      SELECT id, position_name INTO v_pos_id, v_pos_name FROM public.positions WHERE is_active = true LIMIT 1;

      INSERT INTO public.user_scopes (id, user_id, account_id, is_active)
      VALUES 
        (gen_random_uuid(), '35676691-0d53-4e99-b5f2-1044f30e17f4', v_account_id, true),
        (gen_random_uuid(), '33c93767-45cd-4340-8319-d6d55be3ff89', v_account_id, true);

      INSERT INTO public.stores (id, store_name, vcode, account_id, island_group, is_active, status, with_penalty)
      VALUES 
        (v_s1, 'QA OPS S1', 'QA-OPS-1-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s2, 'QA OPS S2', 'QA-OPS-2-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false),
        (v_s3, 'QA OPS S3', 'QA-OPS-3-' || substr(gen_random_uuid()::text, 1, 6), v_account_id, 'Luzon', true, 'active', false);

      INSERT INTO public.plantilla_slots (id, store_id, account_id, position, employment_type, is_roving, slot_status, slot_ordinal)
      VALUES 
        (gen_random_uuid(), v_s1, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s2, v_account_id, v_pos_name, 'Regular', false, 'open', 1),
        (gen_random_uuid(), v_s3, v_account_id, v_pos_name, 'Regular', false, 'open', 1);

      -- Prepare active group via HA
      PERFORM set_config('request.jwt.claim.sub', v_ha_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_ha_uid, 'role', 'authenticated')::text, true);
      v_res := public.create_coverage_group(v_account_id, v_pos_id, 'Regular', 'QA OPS Clust', ARRAY[v_s1, v_s2], v_s1);
      v_cg_id := (v_res->>'coverage_group_id')::uuid;

      -- Switch to Operations
      PERFORM set_config('request.jwt.claim.sub', v_om_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_om_uid, 'role', 'authenticated')::text, true);

      -- Operations: Add Store (Request)
      BEGIN
        SELECT (public.create_coverage_request('add_store'::public.request_type, jsonb_build_object('store_ids', jsonb_build_array(v_s3)), v_account_id, NULL, NULL, v_cg_id, NULL, NULL, 'Ops Add Store')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Add Store', 'status', 'passed', 'details', 'Request created and submitted to pending');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Add Store', 'status', 'failed', 'details', SQLERRM);
      END;

      -- Encoder approves Ops Add Store
      PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);
      PERFORM public.approve_coverage_request(v_req_id, 'Encoder approves Ops Add Store'::text, NULL::jsonb);

      -- Switch to Operations
      PERFORM set_config('request.jwt.claim.sub', v_om_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_om_uid, 'role', 'authenticated')::text, true);

      -- Operations: Remove Store (Request)
      BEGIN
        SELECT (public.create_coverage_request('remove_store'::public.request_type, jsonb_build_object('store_ids', jsonb_build_array(v_s3)), v_account_id, NULL, NULL, v_cg_id, NULL, NULL, 'Ops Rem Store')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Remove Store', 'status', 'passed', 'details', 'Request created and submitted to pending');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Remove Store', 'status', 'failed', 'details', SQLERRM);
      END;

      -- Encoder approves Ops Remove Store
      PERFORM set_config('request.jwt.claim.sub', v_enc_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_enc_uid, 'role', 'authenticated')::text, true);
      PERFORM public.approve_coverage_request(v_req_id, 'Encoder approves Ops Remove Store'::text, NULL::jsonb);

      -- Switch to Operations
      PERFORM set_config('request.jwt.claim.sub', v_om_uid::text, true);
      PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_om_uid, 'role', 'authenticated')::text, true);

      -- Operations: Dissolve Coverage Group (Request)
      BEGIN
        SELECT (public.create_coverage_request('dissolve_coverage_group'::public.request_type, '{}'::jsonb, v_account_id, NULL, NULL, v_cg_id, NULL, NULL, 'Ops Dissolve')->>'coverage_request_id')::uuid INTO v_req_id;
        PERFORM public.submit_coverage_request(v_req_id);
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Dissolve Coverage Group', 'status', 'passed', 'details', 'Request created and submitted to pending');
      EXCEPTION WHEN OTHERS THEN
        v_out := v_out || jsonb_build_object('role', 'Operations (OM/HRCO)', 'operation', 'Dissolve Coverage Group', 'status', 'failed', 'details', SQLERRM);
      END;

      RAISE EXCEPTION 'SANITY_CHECK_ROLLBACK_SUCCESS: %', v_out;
    END $$;
  `;

  try {
    const haResults = executeRoleBlock("Super Admin / Head Admin", haSql);
    const encResults = executeRoleBlock("Encoder", encSql);
    const opsResultsA = executeRoleBlock("Operations (Part A)", opsSqlA);
    const opsResultsB = executeRoleBlock("Operations (Part B)", opsSqlB);

    const allResults = [...haResults, ...encResults, ...opsResultsA, ...opsResultsB];

    console.log("-------------------------------------------------------------------------------");
    console.log("                 SANITY CHECK SUMMARY PER ROLE & OPERATION                     ");
    console.log("-------------------------------------------------------------------------------");

    let allPassed = true;
    const grouped = {};

    for (const item of allResults) {
      if (!grouped[item.role]) grouped[item.role] = [];
      grouped[item.role].push(item);
      if (item.status !== "passed") allPassed = false;
    }

    for (const [role, items] of Object.entries(grouped)) {
      console.log(`\n### ROLE: ${role.toUpperCase()}`);
      for (const item of items) {
        const mark = item.status === "passed" ? "✔ [PASSED]" : "✖ [FAILED]";
        console.log(`  ${mark} ${item.operation}`);
        console.log(`       -> ${item.details}`);
      }
    }

    console.log("\n===============================================================================");
    console.log(`  OVERALL OUTCOME: ${allPassed ? "ALL OPERATIONS & BARRIERS PASSED" : "FAILURES DETECTED"}`);
    console.log("  SANDBOX ISOLATION: 100% ROLLED BACK (ZERO OPERATIONAL POLLUTION)");
    console.log("===============================================================================\n");
  } catch (err) {
    console.error("Test execution aborted:", err.message);
  }
}

runCoverageGroupSanity();
