-- OHM2026_0093: Add vacancy_code_snapshot to v_hr_emploc_sla_flags
-- Coverage HR Emploc list tiles were showing "—" for vcode because the view
-- omitted this column; vacancy_code_snapshot holds the vcode for Coverage records.
CREATE OR REPLACE VIEW public.v_hr_emploc_sla_flags
WITH (security_invoker = true)
AS
SELECT
    id,
    applicant_id,
    applicant_name,
    vcode,
    account,
    account_id,
    store_id,
    store_name,
    "position",
    status,
    hr_status,
    employee_no,
    date_requested,
    created_at,
    assignment_type,
    roving_assignment_id,
    GREATEST(0, EXTRACT(day FROM now() - COALESCE(date_requested, created_at))::integer) AS aging_days,
    deleted_at IS NULL
        AND employee_no IS NULL
        AND (status = ANY (ARRAY[
            'Pending Emploc'::text,
            'Pending Requirements'::text,
            'For Compliance'::text,
            'In Review'::text
        ]))
        AND COALESCE(date_requested, created_at) < (now() - '3 days'::interval) AS sla_breached,
    COALESCE((
        SELECT count(*)
        FROM hr_emploc_store_links sl
        WHERE sl.hr_emploc_id = h.id AND sl.deleted_at IS NULL
    ), 0::bigint)::integer AS roving_store_count,
    COALESCE((
        SELECT count(*)
        FROM hr_emploc_store_links sl
        WHERE sl.hr_emploc_id = h.id AND sl.deleted_at IS NULL AND sl.status = 'Confirmed'::text
    ), 0::bigint)::integer AS roving_confirmed_count,
    (
        SELECT jsonb_agg(
            jsonb_build_object(
                'vcode', sl.vcode,
                'store_name', sl.store_name,
                'status', sl.status,
                'confirmed_at', sl.confirmed_at
            ) ORDER BY sl.vcode
        )
        FROM hr_emploc_store_links sl
        WHERE sl.hr_emploc_id = h.id AND sl.deleted_at IS NULL
    ) AS roving_stores,
    h.vacancy_code_snapshot
FROM hr_emploc h
WHERE deleted_at IS NULL;
