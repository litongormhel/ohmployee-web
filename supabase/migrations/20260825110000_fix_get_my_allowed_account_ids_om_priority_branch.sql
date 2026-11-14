-- Migration: fix_get_my_allowed_account_ids_om_priority_branch
-- Prompt ID: ohm#5t8k2wnq
-- Date: 2026-08-25
--
-- get_my_allowed_account_ids() hard-coded OM (role_level=70) to always
-- resolve group-scoped, ignoring any explicit account_id user_scopes rows.
-- get_my_allowed_accounts() has no such special case: every non-admin role,
-- OM included, uses the same generic priority logic (account-scoped if any
-- account_id rows exist, else group-scoped fallback).
--
-- This removes the OM-only early-return IF block so OM falls through to the
-- same generic block HRCO/ATL/TL/Encoder/Recruitment already use. SA/HA
-- branch and the generic block itself are otherwise byte-identical.
--
-- Confirmed via read-only data check (staging + production, ohm#5t8k2wnq):
-- production user atlg2three@gmail.com (OM, account_id row = account THREE,
-- group has 21 accounts) currently gets 21 accounts from this function but
-- only 1 (THREE) from get_my_allowed_accounts() -- a live divergence that
-- plausibly explains the parked BUG-02 (ohm#6m2wqt9x) headcount split on
-- v_account_allocation_kpi for account THREE. This fix aligns the two
-- functions for that user.

CREATE OR REPLACE FUNCTION public.get_my_allowed_account_ids()
 RETURNS uuid[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role_level INT;
  v_profile_id UUID;
  v_acc_count  INT;
BEGIN
  v_role_level := get_my_role_level();
  v_profile_id := get_my_profile_id();

  -- SA / HA: full access
  IF v_role_level >= 90 THEN
    RETURN ARRAY(SELECT id FROM public.accounts WHERE is_active = true);
  END IF;

  -- OM (70), HRCO (60), ATL (50), TL (40), Encoder (30), Recruitment (20):
  -- account-scoped if any account_id rows; else group-scoped fallback
  SELECT COUNT(*) INTO v_acc_count
  FROM public.user_scopes
  WHERE user_id = v_profile_id AND account_id IS NOT NULL;

  IF v_acc_count > 0 THEN
    RETURN ARRAY(
      SELECT a.id FROM public.accounts a
      JOIN public.user_scopes us ON us.account_id = a.id
      WHERE us.user_id = v_profile_id AND a.is_active = true
    );
  ELSE
    RETURN ARRAY(
      SELECT a.id FROM public.accounts a
      JOIN public.user_scopes us ON us.group_id = a.group_id
      WHERE us.user_id = v_profile_id AND a.is_active = true
    );
  END IF;
END;
$function$;
