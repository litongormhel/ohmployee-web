-- =============================================================================
-- Migration: 20262606000189_fix_hr_emploc_correction_attachments_rls.sql
-- Prompt ID: smoke-test-phase1-bug1
-- Title: Fix Upload Requirements RLS Policy Violation on hr_emploc_correction_attachments
-- Module: HR Emploc / Security
--
-- Description:
-- Resolves "new row violates row-level security policy for table hr_emploc_correction_attachments"
-- when submitting requirements via "Submit & Move to For Emploc".
-- 1. Unifies and broadens INSERT policy to allow authorized Ops roles (Operations Manager,
--    Area Team Leader, Team Leader, HRCO, HR Personnel, Head Admin, Super Admin, Encoder).
-- 2. Aligns SELECT policy on hr_emploc_correction_attachments so inserting users can read
--    the newly created attachment row during .insert().select().
-- 3. Synchronizes storage.objects policies on 'hr-corrections' bucket for SELECT, INSERT, DELETE.
-- =============================================================================

-- 1. Drop narrow/redundant legacy INSERT policies on public.hr_emploc_correction_attachments
DROP POLICY IF EXISTS "correction_attach_insert" ON public.hr_emploc_correction_attachments;
DROP POLICY IF EXISTS "correction_attach_insert_auth_uid" ON public.hr_emploc_correction_attachments;
DROP POLICY IF EXISTS "correction_attach_insert_uploaded_by_profile" ON public.hr_emploc_correction_attachments;

-- 2. Create authoritative INSERT policy on public.hr_emploc_correction_attachments
CREATE POLICY "correction_attach_insert"
  ON public.hr_emploc_correction_attachments
  AS PERMISSIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (SELECT public.i_have_full_access() OR public.i_am_ops() OR public.i_am_hr_dept() OR public.i_am_data_team())
    OR (
      EXISTS (
        SELECT 1
        FROM public.users_profile up
        WHERE up.is_active = true
          AND (up.auth_user_id = (SELECT auth.uid()) OR up.id = (SELECT auth.uid()))
          AND replace(lower(COALESCE(up.role, '')), '_', ' ') = ANY (
            ARRAY[
              'super admin',
              'head admin',
              'hrco',
              'operations manager',
              'area team leader',
              'team leader',
              'hr personnel',
              'encoder'
            ]
          )
      )
    )
  );

-- 3. Update SELECT policy on public.hr_emploc_correction_attachments
DROP POLICY IF EXISTS "correction_attach_read" ON public.hr_emploc_correction_attachments;
CREATE POLICY "correction_attach_read"
  ON public.hr_emploc_correction_attachments
  AS PERMISSIVE
  FOR SELECT
  TO authenticated
  USING (
    is_deleted = false
    AND (
      (SELECT public.i_have_full_access() OR public.i_am_ops() OR public.i_am_hr_dept() OR public.i_am_data_team())
      OR (
        EXISTS (
          SELECT 1
          FROM public.hr_emploc he
          WHERE he.id = hr_emploc_correction_attachments.hr_emploc_id
            AND (
              he.account = ANY (public.get_my_allowed_accounts())
              OR he.hrco_user_id_snapshot = (SELECT public.get_my_profile_id())
            )
        )
      )
    )
  );

-- 4. Synchronize storage.objects policies for the 'hr-corrections' bucket
DROP POLICY IF EXISTS "hr_corrections_select_policy" ON storage.objects;
CREATE POLICY "hr_corrections_select_policy"
  ON storage.objects
  AS PERMISSIVE
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'hr-corrections'
    AND (
      EXISTS (
        SELECT 1
        FROM public.users_profile up
        WHERE up.is_active = true
          AND (up.auth_user_id = (SELECT auth.uid()) OR up.id = (SELECT auth.uid()))
          AND replace(lower(COALESCE(up.role, '')), '_', ' ') = ANY (
            ARRAY[
              'super admin',
              'head admin',
              'hrco',
              'operations manager',
              'area team leader',
              'team leader',
              'hr personnel',
              'encoder'
            ]
          )
      )
    )
  );

DROP POLICY IF EXISTS "hr_corrections_upload_policy" ON storage.objects;
CREATE POLICY "hr_corrections_upload_policy"
  ON storage.objects
  AS PERMISSIVE
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'hr-corrections'
    AND (
      EXISTS (
        SELECT 1
        FROM public.users_profile up
        WHERE up.is_active = true
          AND (up.auth_user_id = (SELECT auth.uid()) OR up.id = (SELECT auth.uid()))
          AND replace(lower(COALESCE(up.role, '')), '_', ' ') = ANY (
            ARRAY[
              'super admin',
              'head admin',
              'hrco',
              'operations manager',
              'area team leader',
              'team leader',
              'hr personnel',
              'encoder'
            ]
          )
      )
    )
  );

DROP POLICY IF EXISTS "hr_corrections_delete_policy" ON storage.objects;
CREATE POLICY "hr_corrections_delete_policy"
  ON storage.objects
  AS PERMISSIVE
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'hr-corrections'
    AND (
      EXISTS (
        SELECT 1
        FROM public.users_profile up
        WHERE up.is_active = true
          AND (up.auth_user_id = (SELECT auth.uid()) OR up.id = (SELECT auth.uid()))
          AND replace(lower(COALESCE(up.role, '')), '_', ' ') = ANY (
            ARRAY[
              'super admin',
              'head admin',
              'hrco',
              'operations manager',
              'area team leader',
              'team leader',
              'hr personnel',
              'encoder'
            ]
          )
      )
    )
  );
