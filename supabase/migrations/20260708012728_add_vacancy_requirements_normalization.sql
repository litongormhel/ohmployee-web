-- Migration: 20260708012728_add_vacancy_requirements_normalization
-- Created: 2026-07-08
-- Purpose: Introduce vacancy_requirements as line items under a vacancy (VCode) to support
--          multi-position demand per VCode, without removing or altering legacy vacancies columns.
--
-- Smoke Tests:
-- S1: select v.id, count(vr.id) from vacancies v left join vacancy_requirements vr
--     on vr.vacancy_id = v.id group by v.id having count(vr.id) < 1;  -- expect 0 rows
-- S2: insert into vacancy_requirements (vacancy_id, position_id, hc_needed, hc_filled)
--     values ('<existing vacancy id>', '<some uuid>', 1, 2);  -- expect trigger exception (HC exceeded)
-- S3: select * from vacancy_requirements where vacancy_id = '<existing vacancy id>';
--     as a scoped (non-full-access) user whose account cannot see that vacancy -- expect 0 rows
--     (confirms vr_same_access_as_vacancy composes with vacancies_read_scoped)

BEGIN;

-- 1. New table: one line item (position + HC target) per vacancy (VCode)
create table if not exists public.vacancy_requirements (
  id uuid primary key default gen_random_uuid(),
  vacancy_id uuid not null references public.vacancies(id) on delete cascade,

  position_id uuid not null,
  employment_type text,

  hc_needed int not null check (hc_needed > 0),
  hc_filled int not null default 0 check (hc_filled >= 0),

  created_at timestamptz not null default now()
);

comment on table public.vacancy_requirements is
  'Line items under a vacancy (VCode) — ADR-001 vacancy_requirements normalization (ohm#7f3a9c2d). '
  'Legacy vacancies.position_id / vacancies.hc_needed-equivalent (required_headcount) are preserved '
  'for backward compatibility and are not read from by any existing code path.';

-- 2. Indexes
create index if not exists idx_vr_vacancy_id on public.vacancy_requirements(vacancy_id);
create index if not exists idx_vr_position_id on public.vacancy_requirements(position_id);

-- 3. Backfill (CRITICAL) — 1 requirement row per existing vacancy.
--    vacancies has no hc_needed/hc_filled columns; required_headcount is the existing HC target,
--    and there is no existing "filled" counter on vacancies, so hc_filled backfills to 0.
insert into public.vacancy_requirements (
  vacancy_id,
  position_id,
  employment_type,
  hc_needed,
  hc_filled
)
select
  v.id,
  v.position_id,
  v.employment_type,
  greatest(coalesce(v.required_headcount, 1), 1),
  0
from public.vacancies v
where v.position_id is not null
  and not exists (
    select 1 from public.vacancy_requirements vr where vr.vacancy_id = v.id
  );

-- 4. Constraint (prevent overfill) — guards both insert and update paths
create or replace function public.check_vr_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.hc_filled > new.hc_needed then
    raise exception 'HC exceeded for requirement %: hc_filled (%) > hc_needed (%)',
      new.id, new.hc_filled, new.hc_needed;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_vr_capacity on public.vacancy_requirements;
create trigger trg_check_vr_capacity
before insert or update on public.vacancy_requirements
for each row execute function public.check_vr_capacity();

-- 5. RLS — read-only for now, scoped by composing with the parent vacancy's own RLS.
--    No INSERT/UPDATE/DELETE policy is granted to authenticated/anon: per AI.md
--    ("RPC-first for protected mutations"), writes to this new line-item table are deferred
--    to a follow-up migration that introduces the assignment RPC. Until then only
--    service_role (SECURITY DEFINER functions) can write.
alter table public.vacancy_requirements enable row level security;

create policy "vr_same_access_as_vacancy"
on public.vacancy_requirements
for select
to authenticated
using (
  exists (
    select 1 from public.vacancies v
    where v.id = vacancy_requirements.vacancy_id
  )
);

grant select on public.vacancy_requirements to authenticated;
grant all on public.vacancy_requirements to service_role;

COMMIT;
