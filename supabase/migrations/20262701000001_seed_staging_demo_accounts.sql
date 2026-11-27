-- Seed 3 Staging Demo Accounts (@ohmployee.com) for App Store / Play Store review & UAT
-- Staging-only safe seed: idempotent (skips if email already exists in auth.users)

DO $$
DECLARE
  v_sa_role_id uuid;
  v_om_role_id uuid;
  v_hrco_role_id uuid;
  v_group_id uuid;
  v_account_id uuid;

  v_sa_uid uuid := 'd0000000-0000-4000-8000-000000000101';
  v_om_uid uuid := 'd0000000-0000-4000-8000-000000000102';
  v_hrco_uid uuid := 'd0000000-0000-4000-8000-000000000103';
  v_pw_hash text := extensions.crypt('Demo@2026!', extensions.gen_salt('bf'));
BEGIN
  SET LOCAL session_replication_role = replica;

  SELECT id INTO v_sa_role_id FROM public.roles WHERE role_level = 100 LIMIT 1;
  SELECT id INTO v_om_role_id FROM public.roles WHERE role_level = 70 LIMIT 1;
  SELECT id INTO v_hrco_role_id FROM public.roles WHERE role_level = 45 LIMIT 1;

  SELECT id INTO v_group_id FROM public.groups ORDER BY id LIMIT 1;
  SELECT id INTO v_account_id FROM public.accounts ORDER BY id LIMIT 1;

  -- 1. Super Admin (global)
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'demo.sa@ohmployee.com') AND v_sa_role_id IS NOT NULL THEN
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, email_change_token_current,
      phone_change, phone_change_token,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_sa_uid, 'authenticated', 'authenticated',
      'demo.sa@ohmployee.com', v_pw_hash,
      NOW(), '', '', '', '', '', '', '',
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"Demo Super Admin"}'::jsonb,
      NOW(), NOW()
    );

    INSERT INTO public.users_profile (id, email, full_name, role_id, is_active, scope_type)
    VALUES (v_sa_uid, 'demo.sa@ohmployee.com', 'Demo Super Admin', v_sa_role_id, true, 'global')
    ON CONFLICT (id) DO NOTHING;
  END IF;

  -- 2. Operations Manager (group scope)
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'demo.om@ohmployee.com') AND v_om_role_id IS NOT NULL THEN
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, email_change_token_current,
      phone_change, phone_change_token,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_om_uid, 'authenticated', 'authenticated',
      'demo.om@ohmployee.com', v_pw_hash,
      NOW(), '', '', '', '', '', '', '',
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"Demo Operations Manager"}'::jsonb,
      NOW(), NOW()
    );

    INSERT INTO public.users_profile (id, email, full_name, role_id, is_active, scope_type)
    VALUES (v_om_uid, 'demo.om@ohmployee.com', 'Demo Operations Manager', v_om_role_id, true, 'scoped')
    ON CONFLICT (id) DO NOTHING;

    IF v_group_id IS NOT NULL THEN
      INSERT INTO public.user_scopes (user_id, group_id, account_id)
      VALUES (v_om_uid, v_group_id, NULL)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- 3. HRCO (account scope)
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'demo.hrco@ohmployee.com') AND v_hrco_role_id IS NOT NULL THEN
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, email_change_token_current,
      phone_change, phone_change_token,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_hrco_uid, 'authenticated', 'authenticated',
      'demo.hrco@ohmployee.com', v_pw_hash,
      NOW(), '', '', '', '', '', '', '',
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"Demo HRCO"}'::jsonb,
      NOW(), NOW()
    );

    INSERT INTO public.users_profile (id, email, full_name, role_id, is_active, scope_type)
    VALUES (v_hrco_uid, 'demo.hrco@ohmployee.com', 'Demo HRCO', v_hrco_role_id, true, 'scoped')
    ON CONFLICT (id) DO NOTHING;

    IF v_account_id IS NOT NULL THEN
      INSERT INTO public.user_scopes (user_id, group_id, account_id)
      VALUES (v_hrco_uid, NULL, v_account_id)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;
END $$;
