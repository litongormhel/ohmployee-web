import { createClient } from "@/lib/supabase/client";
import { formatPersonName } from "@/lib/utils/formatName";
import {
  type VacancyStatus,
  type VacancyListItem,
  type VacancyExportFilters,
  type VacancyExportResult,
  type VacancyExportRowData,
} from "./types";
import {
  asObject,
  asString,
  asTrimmedString,
  asBoolean,
  asDateFilter,
  asUuidFilter,
  normalizeAgingBucket,
  normalizeUrgency,
  normalizeSortField,
  normalizeSortDirection,
  throwVacancyError,
  calculateDaysToFill,
  formatGroupName,
  fetchGroupMap,
  tabToRpcStatus,
} from "./vacancyHelpers";
import { normalizeListRow } from "./vacancyListing";


const VACANCY_EXPORT_HEADERS = [
  "VCode",
  "Position Title",
  "Lifecycle Status",
  "Account Name",
  "Operational Group",
  "Outlet / Store Name",
  "City / Location",
  "Assigned HRCO",
  "Aging (Days)",
  "Urgency Level",
  "Created Date",
] as const;

function escapeCsvValue(val: unknown): string {
  if (val === null || val === undefined) return "";
  const str = String(val).trim();
  if (/[",\r\n]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function buildVacancyExportCsv(rows: VacancyExportRowData[]): string {
  const headerLine = VACANCY_EXPORT_HEADERS.map(escapeCsvValue).join(",");
  const dataLines = rows.map((r) =>
    [
      escapeCsvValue(r.vcode),
      escapeCsvValue(r.positionTitle),
      escapeCsvValue(r.lifecycleStatus),
      escapeCsvValue(r.accountName),
      escapeCsvValue(r.groupName),
      escapeCsvValue(r.storeName),
      escapeCsvValue(r.storeLocation),
      escapeCsvValue(r.hrcoName),
      escapeCsvValue(r.agingDays),
      escapeCsvValue(r.urgencyLevel),
      escapeCsvValue(r.createdDate),
    ].join(",")
  );

  return "\uFEFF" + [headerLine, ...dataLines].join("\r\n");
}

export function getVacancyExportTimestamp(date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  const yyyy = date.getFullYear();
  const mm = pad(date.getMonth() + 1);
  const dd = pad(date.getDate());
  const hh = pad(date.getHours());
  const min = pad(date.getMinutes());
  return `${yyyy}${mm}${dd}_${hh}${min}`;
}

export function getVacancyExportScopeTitle(
  scope: "current_tab" | "all_statuses",
  currentTab: string,
): string {
  if (scope === "all_statuses") {
    return "ALL_STATUSES";
  }
  const normalized = currentTab.toLowerCase().trim();
  switch (normalized) {
    case "open":
      return "Open";
    case "pipeline":
    case "with_applicant":
      return "Pipeline";
    case "hired":
      return "Hired";
    case "closure":
      return "Closure";
    case "failed_backout":
    case "failed / backout":
    case "failed-backout":
      return "Failed_Backout";
    default:
      return currentTab.replace(/[^a-zA-Z0-9]+/g, "_").replace(/^_+|_+$/g, "") || "Current_Tab";
  }
}

async function fetchAllRpcVacancies(
  rpcStatus: string | null,
  filters: VacancyExportFilters,
  lifecycleStatus: string,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  const PAGE_BATCH = 200;
  let offset = 0;
  const allRows: VacancyListItem[] = [];

  while (true) {
    const rpcParams = {
      p_status: rpcStatus,
      p_account_id: asUuidFilter(filters.accountId),
      p_group_id: asUuidFilter(filters.groupId),
      p_aging_bucket: normalizeAgingBucket(filters.aging || filters.agingBucket) ?? null,
      p_urgency: normalizeUrgency(filters.urgency) ?? null,
      p_search: asTrimmedString(filters.search) ?? null,
      p_vacant_from: asDateFilter(filters.dateFrom || filters.vacantFrom) ?? null,
      p_vacant_to: asDateFilter(filters.dateTo || filters.vacantTo) ?? null,
      p_limit: PAGE_BATCH,
      p_offset: offset,
      p_sort_by: normalizeSortField("aging_days"),
      p_sort_dir: normalizeSortDirection("desc"),
    };

    const { data, error } = await supabase.rpc("list_web_vacancies", rpcParams);
    if (error) {
      throwVacancyError(error);
    }

    const rows = (Array.isArray(data) ? data : [])
      .map((row) => normalizeListRow(asObject(row)))
      .filter((row): row is VacancyListItem => row !== null);

    if (rows.length === 0) {
      break;
    }

    allRows.push(...rows);

    const totalCount = rows[0]?.totalCount ?? 0;
    if (allRows.length >= totalCount || rows.length < PAGE_BATCH) {
      break;
    }

    offset += PAGE_BATCH;
  }

  // Enrich missing store locations via stores table
  const missingStoreIds = Array.from(
    new Set(allRows.filter((r) => !r.storeLocation && r.storeId).map((r) => r.storeId as string))
  );

  if (missingStoreIds.length > 0) {
    try {
      const { data: storesData } = await supabase
        .from("stores")
        .select("id, store_name, area_city, area_province, province")
        .in("id", missingStoreIds);

      if (storesData && storesData.length > 0) {
        const storeLocationMap = new Map<string, string>();
        for (const s of storesData) {
          const loc = [s.area_city, s.area_province || s.province].filter(Boolean).join(" • ");
          if (loc) storeLocationMap.set(s.id, loc);
        }
        for (const row of allRows) {
          if (row.storeId && storeLocationMap.has(row.storeId)) {
            row.storeLocation = storeLocationMap.get(row.storeId) ?? null;
          }
        }
      }
    } catch {
      // Graceful fallback
    }
  }

  return allRows.map((item) => {
    const agingDaysStr =
      item.agingDays !== null && item.agingDays !== undefined && !Number.isNaN(item.agingDays)
        ? String(item.agingDays)
        : "";
    const createdDateStr = item.vacantDate
      ? item.vacantDate.includes("T")
        ? item.vacantDate.split("T")[0]
        : item.vacantDate
      : "";

    return {
      vcode: item.vcode || "",
      positionTitle: item.position_title || "",
      lifecycleStatus,
      accountName: item.accountName || "",
      groupName: item.groupName || "",
      storeName: item.storeName || "",
      storeLocation: item.storeLocation || "",
      hrcoName: item.hrcoName || "",
      agingDays: agingDaysStr,
      urgencyLevel: item.urgencyLevel || "",
      createdDate: createdDateStr,
    };
  });
}

async function fetchAllPipelineVacancies(
  filters: VacancyExportFilters,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  try {
    const TERMINAL_STATUSES = [
      "failed",
      "backout",
      "rejected",
      "did_not_report",
      "did not report",
      "rejected_by_ops",
      "rejected by ops",
      "withdrew",
      "confirmed_onboard",
      "confirmed onboard",
      "hired",
    ];

    const { data: pipelineApplicants, error: appsError } = await supabase
      .from("applicants")
      .select(`
        id,
        vacancy_vcode,
        first_name,
        last_name,
        middle_name,
        full_name,
        contact_number,
        status,
        created_at,
        updated_at,
        profile_edit_count,
        is_archived
      `)
      .eq("is_archived", false)
      .order("created_at", { ascending: false });

    if (appsError || !Array.isArray(pipelineApplicants)) {
      return [];
    }

    const activeCandidates = pipelineApplicants.filter((a) => {
      const normStatus = (asString(a.status) || "").toLowerCase().trim().replace(/[\s-]+/g, "_");
      return !TERMINAL_STATUSES.some((t) => t.replace(/[\s-]+/g, "_") === normStatus);
    });

    const vcodes = Array.from(
      new Set(activeCandidates.map((c) => asString(c.vacancy_vcode)).filter(Boolean)),
    ) as string[];

    let vacQuery = supabase
      .from("vw_vacancy_list")
      .select(`
        id,
        vcode,
        store_name,
        store_branch,
        store_id,
        position,
        account,
        account_id,
        group_id,
        area_city,
        province,
        hrco_name,
        vacant_date,
        created_at,
        target_fill_date,
        urgency_level,
        status,
        is_archived,
        hc_total,
        has_pending_closure,
        closure_request_status,
        employment_type,
        source,
        is_pool_vacancy
      `)
      .in("vcode", vcodes)
      .eq("is_archived", false);

    if (filters.accountId) {
      vacQuery = vacQuery.eq("account_id", filters.accountId);
    }
    if (filters.groupId) {
      vacQuery = vacQuery.eq("group_id", filters.groupId);
    }
    if (filters.urgency) {
      vacQuery = vacQuery.ilike("urgency_level", filters.urgency);
    }
    if (filters.dateFrom || filters.vacantFrom) {
      vacQuery = vacQuery.gte("vacant_date", (filters.dateFrom || filters.vacantFrom)!);
    }
    if (filters.dateTo || filters.vacantTo) {
      vacQuery = vacQuery.lte("vacant_date", (filters.dateTo || filters.vacantTo)!);
    }

    const [vacRes, groupMap] = await Promise.all([
      vacQuery,
      fetchGroupMap(supabase),
    ]);

    const vacMap = new Map(
      (vacRes.data ?? [])
        .filter((v) => {
          const st = (v.status || "").toLowerCase().trim();
          return st !== "filled" && st !== "closed" && st !== "archived";
        })
        .map((v) => [v.vcode, v]),
    );
    const validCandidates = activeCandidates.filter((c) => vacMap.has(asString(c.vacancy_vcode)));

    const rows = validCandidates.map((c: Record<string, unknown>) => {
      const vcode = asString(c.vacancy_vcode) ?? "Uncoded";
      const vac = vacMap.get(vcode) as Record<string, unknown> | undefined;
      const lName = asString(c.last_name);
      const fName = asString(c.first_name);
      const mName = asString(c.middle_name);
      const fFull = asString(c.full_name);
      const candidateName = formatPersonName(fName, lName, mName, fFull || "Candidate");
      const position = asString(vac?.position) ?? "—";
      const loc = [asString(vac?.area_city), asString(vac?.province)].filter(Boolean).join(" • ") || "";
      let storeName = asString(vac?.store_name ?? vac?.store_branch);
      const account = asString(vac?.account);
      if (
        !storeName &&
        (vcode.includes("GHQ") ||
          account?.toLowerCase() === "moses hq" ||
          vac?.source === "pool" ||
          asBoolean(vac?.is_pool_vacancy))
      ) {
        storeName = "Moses HQ";
      }

      const stageBadge = asString(c.status) || "In Pipeline";
      const vDateStr = asString(vac?.vacant_date ?? vac?.created_at ?? c.created_at);
      let agingDays: number | null = null;
      if (vDateStr) {
        const vDate = new Date(vDateStr);
        if (!isNaN(vDate.getTime())) {
          const diffMs = Date.now() - vDate.getTime();
          agingDays = Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
        }
      }

      const rawGroupName = vac?.group_id ? groupMap.get(asString(vac.group_id)!) : null;
      const groupName = formatGroupName(rawGroupName, account) || "";

      return {
        vcode,
        positionTitle: position,
        lifecycleStatus: "Pipeline",
        accountName: account || "",
        groupName,
        storeName: storeName || "",
        storeLocation: loc,
        hrcoName: asString(vac?.hrco_name) || "",
        agingDays: agingDays !== null ? String(agingDays) : "",
        urgencyLevel: asString(vac?.urgency_level) || "",
        createdDate: vDateStr ? (vDateStr.includes("T") ? vDateStr.split("T")[0] : vDateStr) : "",
        applicantName: candidateName,
        applicantContact: asString(c.contact_number) || "",
        pipelineStage: stageBadge,
      };
    });

    if (filters.search) {
      const q = filters.search.toLowerCase();
      return rows.filter(
        (r) =>
          r.vcode.toLowerCase().includes(q) ||
          r.positionTitle.toLowerCase().includes(q) ||
          r.accountName.toLowerCase().includes(q) ||
          r.storeName.toLowerCase().includes(q) ||
          (r.applicantName && r.applicantName.toLowerCase().includes(q)),
      );
    }

    return rows;
  } catch {
    return [];
  }
}

async function fetchAllHiredVacancies(
  filters: VacancyExportFilters,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  try {
    const { data: hiredData, error: hiredError } = await supabase.rpc("fn_get_hired_applicants");
    if (hiredError || !Array.isArray(hiredData)) {
      return [];
    }

    const hiredRows = hiredData.map((h: Record<string, unknown>, idx: number) => {
      const lName = asString(h.last_name);
      const fName = asString(h.first_name);
      const mName = asString(h.middle_name);
      const rawFull = asString(h.full_name);
      const workerName = formatPersonName(fName, lName, mName, rawFull || "Hired Worker");

      const hiredDate = asString(h.hired_date ?? h.hired_at);
      const position = asString(h.position_name ?? h.position);
      const vcode = asString(h.vacancy_vcode) ?? "Uncoded";
      const account = asString(h.account);
      const groupName = formatGroupName(asString(h.group_name), account);

      return {
        id: asString(h.id) ?? `hired-${idx}`,
        vcode,
        accountId: null as string | null,
        accountName: account,
        groupId: null as string | null,
        groupName,
        storeId: null as string | null,
        storeName: null as string | null,
        storeLocation: null as string | null,
        position_title: position,
        vacantDate: null as string | null,
        hiredDate,
        daysToFill: null as number | null,
        agingDays: null as number | null,
        urgencyLevel: null as string | null,
        hrcoName: asString(h.hired_by) ?? "HR Team",
        applicantName: workerName,
      };
    });

    // Enrich store info for hired rows if vcodes exist
    const hiredVcodes = Array.from(new Set(hiredRows.map((r) => r.vcode).filter(Boolean)));
    if (hiredVcodes.length > 0) {
      try {
        const { data: vacsData } = await supabase
          .from("vw_vacancy_list")
          .select("vcode, store_name, store_branch, area_city, province, store_id, account_id, group_id, account, vacant_date, created_at, hrco_name")
          .in("vcode", hiredVcodes);

        if (vacsData && vacsData.length > 0) {
          const vacMap = new Map(vacsData.map((v) => [v.vcode, v]));
          for (const row of hiredRows) {
            if (vacMap.has(row.vcode)) {
              const v = vacMap.get(row.vcode)!;
              row.storeName = v.store_name || v.store_branch || null;
              row.vacantDate = v.vacant_date || v.created_at?.substring(0, 10) || null;
              row.daysToFill = calculateDaysToFill(row.vacantDate, row.hiredDate);
              row.accountId = v.account_id || row.accountId;
              row.groupId = v.group_id || row.groupId;
              row.storeId = v.store_id || row.storeId;
              row.accountName = row.accountName || v.account || null;
              if (v.hrco_name) row.hrcoName = asString(v.hrco_name) || "Unassigned";
              const loc = [v.area_city, v.province].filter(Boolean).join(" • ");
              if (loc) row.storeLocation = loc;
            }
          }
        }
      } catch {
        // Graceful fallback
      }
    }

    // Apply filters & search on hiredRows
    let filteredHired = hiredRows;
    if (filters.accountId) {
      filteredHired = filteredHired.filter((r) => r.accountId === filters.accountId);
    }
    if (filters.groupId) {
      filteredHired = filteredHired.filter((r) => r.groupId === filters.groupId);
    }
    if (filters.search) {
      const q = filters.search.toLowerCase();
      filteredHired = filteredHired.filter(
        (r) =>
          r.vcode.toLowerCase().includes(q) ||
          (r.applicantName && r.applicantName.toLowerCase().includes(q)) ||
          (r.position_title && r.position_title.toLowerCase().includes(q)) ||
          (r.storeName && r.storeName.toLowerCase().includes(q)) ||
          (r.accountName && r.accountName.toLowerCase().includes(q)),
      );
    }

    const dFrom = filters.dateFrom || filters.vacantFrom;
    if (dFrom) {
      filteredHired = filteredHired.filter((r) => !r.vacantDate || r.vacantDate >= dFrom);
    }
    const dTo = filters.dateTo || filters.vacantTo;
    if (dTo) {
      filteredHired = filteredHired.filter((r) => !r.vacantDate || r.vacantDate <= dTo);
    }

    return filteredHired.map((item) => {
      const createdDateStr = item.vacantDate
        ? item.vacantDate.includes("T")
          ? item.vacantDate.split("T")[0]
          : item.vacantDate
        : "";

      return {
        vcode: item.vcode || "",
        positionTitle: item.position_title || "",
        lifecycleStatus: "Hired",
        accountName: item.accountName || "",
        groupName: item.groupName || "",
        storeName: item.storeName || "",
        storeLocation: item.storeLocation || "",
        hrcoName: item.hrcoName || "",
        agingDays:
          item.daysToFill !== null && item.daysToFill !== undefined
            ? `${item.daysToFill} days`
            : "",
        urgencyLevel: item.urgencyLevel || "",
        createdDate: createdDateStr,
      };
    });
  } catch {
    return [];
  }
}

async function fetchAllClosureVacancies(
  filters: VacancyExportFilters,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  try {
    const { data: closureRequests } = await supabase
      .from("vacancy_closure_requests")
      .select("id, vacancy_vcode, reason, details, status, requested_by, created_at")
      .ilike("status", "pending")
      .order("created_at", { ascending: false });

    const requestMap = new Map<string, Record<string, unknown>>();
    if (Array.isArray(closureRequests)) {
      for (const cr of closureRequests) {
        const vcode = asString(cr.vacancy_vcode);
        if (vcode && !requestMap.has(vcode)) {
          requestMap.set(vcode, cr as Record<string, unknown>);
        }
      }
    }

    let vacQuery = supabase
      .from("vacancies")
      .select(`
        id,
        vcode,
        store_name,
        store_branch,
        position,
        account,
        account_id,
        group_id,
        area_city,
        province,
        is_archived,
        deleted_at,
        has_pending_closure,
        closure_request_status,
        status,
        created_at,
        updated_at,
        hrco_name,
        urgency_level
      `)
      .eq("is_archived", false)
      .is("deleted_at", null);

    if (filters.accountId) {
      vacQuery = vacQuery.eq("account_id", filters.accountId);
    }
    if (filters.groupId) {
      vacQuery = vacQuery.eq("group_id", filters.groupId);
    }

    const [vacRes, groupMap] = await Promise.all([
      vacQuery,
      fetchGroupMap(supabase),
    ]);
    const activeVacs = vacRes.data;
    const vacError = vacRes.error;

    if (vacError || !Array.isArray(activeVacs)) {
      return [];
    }

    const closureVacs = activeVacs.filter((vac: Record<string, unknown>) => {
      const vcode = asString(vac.vcode);
      const statusLower = (asString(vac.status) || "").toLowerCase().trim();
      const closureReqStatusLower = (asString(vac.closure_request_status) || "").toLowerCase().trim();
      const isClosureStatus = statusLower === "closure" || statusLower === "for_closure";
      const hasPendingFlag = asBoolean(vac.has_pending_closure) || closureReqStatusLower === "pending";
      const hasPendingRequest = vcode ? requestMap.has(vcode) : false;

      return isClosureStatus || hasPendingFlag || hasPendingRequest;
    });

    const closureRows = closureVacs.map((vac: Record<string, unknown>, idx: number) => {
      const vcode = asString(vac.vcode) ?? "Uncoded";
      const cr = requestMap.get(vcode);
      const storeName = asString(vac.store_name ?? vac.store_branch);
      const position = asString(vac.position) ?? "—";
      const account = asString(vac.account);
      const rawGroupName = vac.group_id ? groupMap.get(asString(vac.group_id)!) : null;
      const groupName = formatGroupName(rawGroupName, account) || null;
      const loc = [asString(vac.area_city), asString(vac.province)]
        .filter(Boolean)
        .join(" • ") || null;

      const closureReason =
        asString(cr?.reason) ??
        asString(cr?.details) ??
        asString(vac.closure_reason) ??
        "Store Closed / Outlet Ceased Operations";
      const closureRequestedBy =
        asString(cr?.requested_by) ??
        asString(vac.closure_requested_by) ??
        "Operations";
      const closureRequestedAt =
        asString(cr?.created_at) ??
        asString(vac.closure_requested_at) ??
        asString(vac.updated_at) ??
        asString(vac.created_at);

      return {
        id: asString(vac.id) ?? asString(cr?.id) ?? `closure-${idx}`,
        vcode,
        accountId: asString(vac.account_id),
        accountName: account,
        groupId: asString(vac.group_id),
        groupName,
        storeName,
        storeLocation: loc,
        position_title: position,
        vacantDate: closureRequestedAt,
        urgencyLevel: asString(vac.urgency_level),
        hrcoName: asString(vac.hrco_name) ?? "—",
        closureReason,
        closureRequestedBy,
      };
    });

    let filteredClosure = closureRows;
    if (filters.search) {
      const q = filters.search.toLowerCase();
      filteredClosure = filteredClosure.filter(
        (r) =>
          r.vcode.toLowerCase().includes(q) ||
          (r.position_title && r.position_title.toLowerCase().includes(q)) ||
          (r.storeName && r.storeName.toLowerCase().includes(q)) ||
          (r.accountName && r.accountName.toLowerCase().includes(q)) ||
          (r.closureReason && r.closureReason.toLowerCase().includes(q)) ||
          (r.closureRequestedBy && r.closureRequestedBy.toLowerCase().includes(q)),
      );
    }

    const dFrom = filters.dateFrom || filters.vacantFrom;
    if (dFrom) {
      filteredClosure = filteredClosure.filter((r) => !r.vacantDate || r.vacantDate >= dFrom);
    }
    const dTo = filters.dateTo || filters.vacantTo;
    if (dTo) {
      filteredClosure = filteredClosure.filter((r) => !r.vacantDate || r.vacantDate <= dTo);
    }

    return filteredClosure.map((item) => {
      const createdDateStr = item.vacantDate
        ? item.vacantDate.includes("T")
          ? item.vacantDate.split("T")[0]
          : item.vacantDate
        : "";

      return {
        vcode: item.vcode || "",
        positionTitle: item.position_title || "",
        lifecycleStatus: "Closure",
        accountName: item.accountName || "",
        groupName: item.groupName || "",
        storeName: item.storeName || "",
        storeLocation: item.storeLocation || "",
        hrcoName: item.hrcoName || "",
        agingDays: "",
        urgencyLevel: item.urgencyLevel || "",
        createdDate: createdDateStr,
      };
    });
  } catch {
    return [];
  }
}

async function fetchAllFailedVacancies(
  filters: VacancyExportFilters,
): Promise<VacancyExportRowData[]> {
  const supabase = createClient();
  try {
    const { data: dropoutsData, error: dropoutsError } = await supabase
      .from("applicants")
      .select(`
        id,
        vacancy_vcode,
        first_name,
        last_name,
        full_name,
        contact_number,
        status,
        backout_reason,
        backout_date,
        created_at,
        updated_at
      `)
      .in("status", [
        "Backout", "backout",
        "Rejected", "rejected",
        "Failed", "failed",
        "Did Not Report", "did not report",
        "Rejected by Ops", "rejected by ops",
      ])
      .order("created_at", { ascending: false });

    if (dropoutsError || !Array.isArray(dropoutsData) || dropoutsData.length === 0) {
      return [];
    }

    const dropoutVcodes = Array.from(new Set(dropoutsData.map((d) => d.vacancy_vcode).filter(Boolean)));
    let vacQuery = supabase
      .from("vw_vacancy_list")
      .select("id, vcode, store_name, store_branch, store_id, position, account, account_id, group_id, area_city, province, hrco_name, vacant_date, target_fill_date, urgency_level, is_archived")
      .in("vcode", dropoutVcodes);

    if (filters.accountId) {
      vacQuery = vacQuery.eq("account_id", filters.accountId);
    }
    if (filters.groupId) {
      vacQuery = vacQuery.eq("group_id", filters.groupId);
    }

    const [vacsRes, groupMap] = await Promise.all([
      vacQuery,
      fetchGroupMap(supabase),
    ]);
    const vacsData = vacsRes.data;
    const vacMap = new Map((vacsData ?? []).map((v) => [v.vcode, v]));

    const validDropouts = dropoutsData.filter((d) => vacMap.has(d.vacancy_vcode));

    const failedRows = validDropouts.map((d: Record<string, unknown>, idx: number) => {
      const vcode = asString(d.vacancy_vcode) ?? "Uncoded";
      const vac = vacMap.get(vcode);
      const lName = asString(d.last_name);
      const fName = asString(d.first_name);
      const fFull = asString(d.full_name);
      const candidateName = fFull || (lName && fName ? `${lName}, ${fName}` : lName || fName || "Candidate");
      const storeName = asString(vac?.store_name ?? vac?.store_branch);
      const position = asString(vac?.position) ?? "—";
      const loc = [asString(vac?.area_city), asString(vac?.province)].filter(Boolean).join(" • ") || null;
      const status = asString(d.status) || "Failed / Backout";
      const dropoutReason = asString(d.backout_reason) || status;
      const dropoutDate = asString(d.backout_date ?? d.updated_at ?? d.created_at);
      const rawGroupName = vac?.group_id ? groupMap.get(asString(vac.group_id)!) : null;

      return {
        id: asString(vac?.id) ?? asString(d.id) ?? `failed-${idx}`,
        vcode,
        accountId: asString(vac?.account_id),
        accountName: asString(vac?.account),
        groupId: asString(vac?.group_id),
        groupName: formatGroupName(rawGroupName, asString(vac?.account)) || null,
        storeName,
        storeLocation: loc,
        position_title: position,
        vacantDate: asString(vac?.vacant_date) || dropoutDate,
        urgencyLevel: asString(vac?.urgency_level),
        hrcoName: asString(vac?.hrco_name) || "Unassigned",
        applicantName: candidateName,
        dropoutReason,
      };
    });

    let filteredFailed = failedRows;
    if (filters.search) {
      const q = filters.search.toLowerCase();
      filteredFailed = filteredFailed.filter(
        (r) =>
          r.vcode.toLowerCase().includes(q) ||
          (r.applicantName && r.applicantName.toLowerCase().includes(q)) ||
          (r.position_title && r.position_title.toLowerCase().includes(q)) ||
          (r.storeName && r.storeName.toLowerCase().includes(q)) ||
          (r.accountName && r.accountName.toLowerCase().includes(q)) ||
          (r.dropoutReason && r.dropoutReason.toLowerCase().includes(q)),
      );
    }

    const dFrom = filters.dateFrom || filters.vacantFrom;
    if (dFrom) {
      filteredFailed = filteredFailed.filter((r) => !r.vacantDate || r.vacantDate >= dFrom);
    }
    const dTo = filters.dateTo || filters.vacantTo;
    if (dTo) {
      filteredFailed = filteredFailed.filter((r) => !r.vacantDate || r.vacantDate <= dTo);
    }

    return filteredFailed.map((item) => {
      const createdDateStr = item.vacantDate
        ? item.vacantDate.includes("T")
          ? item.vacantDate.split("T")[0]
          : item.vacantDate
        : "";

      return {
        vcode: item.vcode || "",
        positionTitle: item.position_title || "",
        lifecycleStatus: "Failed / Backout",
        accountName: item.accountName || "",
        groupName: item.groupName || "",
        storeName: item.storeName || "",
        storeLocation: item.storeLocation || "",
        hrcoName: item.hrcoName || "",
        agingDays: "",
        urgencyLevel: item.urgencyLevel || "",
        createdDate: createdDateStr,
      };
    });
  } catch {
    return [];
  }
}

/**
 * Unpaginated full-dataset Vacancy Export query.
 * Pulls matched records without UI pagination truncation.
 */
export async function fetchVacanciesForExport(
  scope: "current_tab" | "all_statuses",
  currentTab: string,
  filters: VacancyExportFilters = {},
): Promise<VacancyExportResult> {
  const scopeTitle = getVacancyExportScopeTitle(scope, currentTab);
  const timestamp = getVacancyExportTimestamp();
  const filename = `OHMployee_Vacancies_${scopeTitle}_${timestamp}.csv`;

  let exportRows: VacancyExportRowData[] = [];

  if (scope === "all_statuses") {
    const [openRows, pipelineRows, hiredRows, closureRows, failedRows] = await Promise.all([
      fetchAllRpcVacancies("Open", filters, "Open"),
      fetchAllPipelineVacancies(filters),
      fetchAllHiredVacancies(filters),
      fetchAllClosureVacancies(filters),
      fetchAllFailedVacancies(filters),
    ]);

    exportRows = [
      ...openRows,
      ...pipelineRows,
      ...hiredRows,
      ...closureRows,
      ...failedRows,
    ];
  } else {
    const normalizedTab = currentTab.toLowerCase().trim();
    switch (normalizedTab) {
      case "open":
        exportRows = await fetchAllRpcVacancies("Open", filters, "Open");
        break;
      case "pipeline":
      case "with_applicant":
        exportRows = await fetchAllPipelineVacancies(filters);
        break;
      case "hired":
        exportRows = await fetchAllHiredVacancies(filters);
        break;
      case "closure":
        exportRows = await fetchAllClosureVacancies(filters);
        break;
      case "failed_backout":
      case "failed / backout":
      case "failed-backout":
        exportRows = await fetchAllFailedVacancies(filters);
        break;
      default:
        exportRows = await fetchAllRpcVacancies(tabToRpcStatus(normalizedTab as VacancyStatus), filters, "Open");
        break;
    }
  }

  const csv = buildVacancyExportCsv(exportRows);

  return {
    csv,
    rowCount: exportRows.length,
    filename,
    scopeTitle,
  };
}

/**
 * Triggers a direct browser download of generated CSV content with proper UTF-8 BOM.
 */
export function downloadCsv(csv: string, filename: string): void {
  if (typeof window === "undefined") return;
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.setAttribute("download", filename);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

