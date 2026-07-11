-- OHM2026_1140 (corrective #2) — fix team performance RPCs: r.level → i_have_full_access()
--
-- WHY: migrations 20261207 and 20261208 both used `r.level` in the scope guard.
--   The `roles` table column is `role_level`, not `level`.
--   PostgreSQL error: column r.level does not exist (42703).
--   Fix: replace the inline JOIN check with i_have_full_access() which internally
--   calls get_my_role_level() >= 90 against roles.role_level (proven, table-backed).

DROP FUNCTION IF EXISTS public.fn_team_performance_summary(uuid, uuid);
DROP FUNCTION IF EXISTS public.fn_team_performance_detail(uuid, uuid);

-- ── fn_team_performance_summary ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_team_performance_summary(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authenticated access required';
  END IF;

  WITH
  base_accounts AS (
    SELECT
      a.id           AS account_id,
      a.account_name,
      g.id           AS group_id,
      g.group_name,
      (
        SELECT up.full_name
        FROM users_profile up
        WHERE up.id = a.hrco_user_id
        LIMIT 1
      ) AS hrco_name
    FROM accounts a
    JOIN groups g ON g.id = a.group_id
    WHERE
      (p_group_id   IS NULL OR g.id = p_group_id)
      AND (p_account_id IS NULL OR a.id = p_account_id)
      AND (
        i_have_full_access()
        OR a.account_name = ANY(get_my_allowed_accounts())
      )
  ),

  actual_hc AS (
    SELECT account_id, COUNT(*) AS hc
    FROM plantilla
    WHERE status IN ('Active', 'On Leave')
      AND is_deleted = false
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  vacant_hc AS (
    SELECT account_id, COUNT(*) AS hc
    FROM vacancies
    WHERE status = 'Open'
      AND deleted_at IS NULL
      AND archived_at IS NULL
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  aged_vac AS (
    SELECT account_id, COUNT(*) AS cnt
    FROM vacancies
    WHERE status = 'Open'
      AND deleted_at IS NULL
      AND archived_at IS NULL
      AND COALESCE(vacant_date, created_at)::date < CURRENT_DATE - INTERVAL '30 days'
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  late_hr AS (
    SELECT account_id, COUNT(*) AS cnt
    FROM plantilla
    WHERE date_of_separation IS NOT NULL
      AND is_deleted = false
      AND (updated_at::date - date_of_separation) > 7
      AND account_id IN (SELECT account_id FROM base_accounts)
    GROUP BY account_id
  ),

  metrics AS (
    SELECT
      ba.account_id,
      ba.account_name,
      ba.group_id,
      ba.group_name,
      ba.hrco_name,
      COALESCE(ah.hc,  0) AS actual_hc,
      COALESCE(vh.hc,  0) AS vacant_hc,
      COALESCE(ah.hc,  0) + COALESCE(vh.hc, 0) AS required_hc,
      COALESCE(av.cnt, 0) AS aged_vacancies,
      COALESCE(lh.cnt, 0) AS late_hr_updates
    FROM base_accounts ba
    LEFT JOIN actual_hc ah ON ah.account_id = ba.account_id
    LEFT JOIN vacant_hc vh ON vh.account_id = ba.account_id
    LEFT JOIN aged_vac  av ON av.account_id = ba.account_id
    LEFT JOIN late_hr   lh ON lh.account_id = ba.account_id
  ),

  scored AS (
    SELECT
      *,
      CASE
        WHEN required_hc = 0 THEN 0.0
        ELSE LEAST(1.0, actual_hc::float / required_hc::float)
      END AS mfr,
      GREATEST(0, LEAST(100,
        100
        - CASE
            WHEN required_hc = 0 THEN 0
            WHEN actual_hc::float / required_hc::float < 0.70 THEN 30
            WHEN actual_hc::float / required_hc::float < 0.80 THEN 20
            WHEN actual_hc::float / required_hc::float < 0.90 THEN 10
            WHEN actual_hc::float / required_hc::float < 0.95 THEN 5
            ELSE 0
          END
        - LEAST(aged_vacancies * 3, 20)
        - LEAST(late_hr_updates * 5, 15)
      )) AS score
    FROM metrics
  ),

  final AS (
    SELECT
      *,
      CASE
        WHEN score >= 90 THEN 'Excellent'
        WHEN score >= 80 THEN 'Good'
        WHEN score >= 70 THEN 'Watch'
        ELSE 'Critical'
      END AS severity
    FROM scored
  )

  SELECT jsonb_build_object(
    'kpis', jsonb_build_object(
      'best_group',         (SELECT account_name FROM final ORDER BY score DESC, account_name LIMIT 1),
      'best_group_score',   (SELECT score          FROM final ORDER BY score DESC, account_name LIMIT 1),
      'lowest_group',       (SELECT account_name FROM final ORDER BY score ASC,  account_name LIMIT 1),
      'lowest_group_score', (SELECT score          FROM final ORDER BY score ASC,  account_name LIMIT 1),
      'average_score',      ROUND(COALESCE((SELECT AVG(score) FROM final), 0)::numeric, 1),
      'critical_count',     (SELECT COUNT(*) FROM final WHERE score < 70)
    ),
    'leaderboard', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'account_id',      account_id,
            'account_name',    account_name,
            'group_id',        group_id,
            'group_name',      group_name,
            'hrco_name',       hrco_name,
            'score',           score,
            'severity',        severity,
            'mfr',             mfr,
            'aged_vacancies',  aged_vacancies,
            'late_hr_updates', late_hr_updates,
            'actual_hc',       actual_hc,
            'vacant_hc',       vacant_hc,
            'required_hc',     required_hc
          )
          ORDER BY score DESC, account_name
        )
        FROM final
      ),
      '[]'::jsonb
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_team_performance_summary(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_team_performance_summary(uuid, uuid) TO authenticated;

-- ── fn_team_performance_detail ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_team_performance_detail(
  p_group_id   uuid DEFAULT NULL,
  p_account_id uuid DEFAULT NULL
)
RETURNS TABLE (
  account_id     uuid,
  account_name   text,
  group_id       uuid,
  group_name     text,
  hrco_name      text,
  issue_category text,
  issue_label    text,
  issue_detail   text,
  days_impacted  int,
  store_name     text,
  employee_name  text,
  vcode          text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authenticated access required';
  END IF;

  RETURN QUERY
  WITH
  base_accounts AS (
    SELECT
      a.id           AS acct_id,
      a.account_name AS acct_name,
      g.id           AS grp_id,
      g.group_name   AS grp_name,
      (
        SELECT up.full_name FROM users_profile up
        WHERE up.id = a.hrco_user_id LIMIT 1
      ) AS hrco
    FROM accounts a
    JOIN groups g ON g.id = a.group_id
    WHERE
      (p_group_id   IS NULL OR g.id = p_group_id)
      AND (p_account_id IS NULL OR a.id = p_account_id)
      AND (
        i_have_full_access()
        OR a.account_name = ANY(get_my_allowed_accounts())
      )
  ),

  aged_issues AS (
    SELECT
      ba.acct_id,
      ba.acct_name,
      ba.grp_id,
      ba.grp_name,
      ba.hrco,
      'aged_vacancy'::text                    AS cat,
      'Aged Vacancy'::text                    AS lbl,
      'Open vacancy older than 30 days'::text AS dtl,
      (CURRENT_DATE - COALESCE(v.vacant_date, v.created_at)::date) AS days,
      COALESCE(v.store_name, v.account)::text AS store,
      NULL::text                              AS emp,
      v.vcode::text                           AS vc
    FROM vacancies v
    JOIN base_accounts ba ON ba.acct_id = v.account_id
    WHERE v.status = 'Open'
      AND v.deleted_at IS NULL
      AND v.archived_at IS NULL
      AND COALESCE(v.vacant_date, v.created_at)::date < CURRENT_DATE - INTERVAL '30 days'
  ),

  late_hr_issues AS (
    SELECT
      ba.acct_id,
      ba.acct_name,
      ba.grp_id,
      ba.grp_name,
      ba.hrco,
      'late_hr'::text                                                   AS cat,
      'Late HR Update'::text                                            AS lbl,
      'Separation recorded more than 7 days after effective date'::text AS dtl,
      (p.updated_at::date - p.date_of_separation)::int                 AS days,
      COALESCE(p.store_name, '')::text                                  AS store,
      COALESCE(p.employee_name, '')::text                               AS emp,
      NULL::text                                                        AS vc
    FROM plantilla p
    JOIN base_accounts ba ON ba.acct_id = p.account_id
    WHERE p.date_of_separation IS NOT NULL
      AND p.is_deleted = false
      AND (p.updated_at::date - p.date_of_separation) > 7
  )

  SELECT acct_id, acct_name, grp_id, grp_name, hrco, cat, lbl, dtl, days, store, emp, vc
  FROM aged_issues
  UNION ALL
  SELECT acct_id, acct_name, grp_id, grp_name, hrco, cat, lbl, dtl, days, store, emp, vc
  FROM late_hr_issues
  ORDER BY acct_name, cat, days DESC NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_team_performance_detail(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_team_performance_detail(uuid, uuid) TO authenticated;
