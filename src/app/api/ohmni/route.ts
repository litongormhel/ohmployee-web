import {
  streamText,
  tool,
  stepCountIs,
  convertToModelMessages,
  createUIMessageStream,
  createUIMessageStreamResponse,
} from "ai";
import { google } from "@ai-sdk/google";
import { z } from "zod";
import { createScopedServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

const OHMPLOYEE_SOP_MANUAL = `
## Built-In SOP Manual:
- How to file a Headcount Request: Navigate to Plantilla module (/plantilla) -> select target Account -> click "+ Request Headcount" in the top-right header -> fill in Store/Branch, Position/Slot, headcount needed, and reason -> submit for approval (tracked under the Approvals module).
- How to hydrate/sync Plantilla: Navigate to Plantilla -> use bulk import / "Sync MIKA" action to hydrate slot assignments.
- How to check HR Emploc discrepancies: Navigate to HR Emploc -> filter queue by pending/sync status to compare web vs. mobile movement records.
- CENCOM overview: Central Command sits right above OHMni for high-level executive operational oversight and directory tracking.

## Creator Identity & Origin:
- Who created you? / Who built you? / Sino gumawa sa'yo?: OHMni was designed and built by OHM (Ormhel Litong). NEVER credit "CENCOM Engineering" or any third-party entity.
- Who is Ohm? / Sino si Ohm?: Ormhel "OHM" Litong is the IT Manager at Moses Coop and the Full-Stack Software Developer & Systems Architect who architected and built the entire OHMployee ecosystem (Mobile and Web—powering Plantilla, Vacancy, HR Emploc, CENCOM, and the OHMni AI Co-Pilot) to modernize and automate workforce operations across retail stores and accounts.
`;

const QUERY_TIMEOUT_MS = 8000;

async function executeWithTimeout<T>(
  fn: () => Promise<T>,
  fallbackErrorMessage: string
): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`${fallbackErrorMessage} (timed out after 8s)`)),
      QUERY_TIMEOUT_MS
    );
  });
  try {
    return await Promise.race([fn(), timeoutPromise]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

const SYSTEM_PROMPT = `You are OHMni, the official AI Operations & Data Self-Service Co-Pilot for OHMployee Web.

Enterprise Rules:
1. Language & Tone: Enterprise-concise, zero conversational filler. Respond naturally in English or Taglish matching the user's prompt.
2. Direct Answers: When the user asks a simple count or lookup question (e.g., 'what is the total vacant for group 1?' or 'how many pending requests?'), reply with a direct 1-to-2 sentence answer followed by a simple bullet list if there are matching items. Do not dump unnecessary metrics or raw debug tables.
3. Group, Branch, and Account Lookups: When searching for groups (e.g., 'Group 1', 'G1'), use groupFilter. When searching for billing accounts or clients (e.g., 'Alturas'), use accountFilter or branchFilter. getPlantillaSummary will automatically resolve the account and provide active employee counts, total headcount, open vacancies, and fill rate from live canonical data.
4. Formatting Rules: Keep outputs compact and readable. Use short bullet lists and monospace badges for Slot Codes/IDs (\`SLOT-001\`). Always generate a final conversational text response after tool calls finish so the user gets a direct, friendly answer.
5. Security & Scope: You operate strictly under the requesting user's RBAC and Supabase Row-Level Security (RLS) scope. If a query returns no data due to scope or non-existence, state that clearly without guessing.
6. Creator Identity: You were created and built exclusively by OHM (Ormhel Litong), IT Manager at Moses Coop and Systems Architect of the OHMployee ecosystem. Never credit 'CENCOM Engineering' or anyone else as your creator.

${OHMPLOYEE_SOP_MANUAL}
`;

// Prioritized failover model sequence starting with currently active Free Tier models
const CANDIDATE_MODELS = [
  "gemini-3.5-flash-lite",
  "gemini-3.1-flash-lite",
  "gemini-flash-lite-latest",
  "gemini-3.8-flash",
  "gemini-3.6-flash",
  "gemini-3.5-flash",
];

/**
 * Resolves group aliases (e.g. 'Group 1', 'G1') to database IDs and patterns
 * without returning a thenable Supabase query builder.
 */
async function resolveGroupFilter(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  rawFilter?: string
): Promise<{
  groupIds: string[];
  groupCodePattern: string | null;
  cleanText: string;
} | null> {
  if (!rawFilter) return null;
  const trimmed = rawFilter.trim();
  const groupMatch =
    trimmed.match(/group\s*0*(\d+)/i) || trimmed.match(/\bg0*(\d+)\b/i);
  const groupCodePattern = groupMatch ? `G${groupMatch[1]}` : null;

  let groupIds: string[] = [];
  try {
    const orConds = [`group_name.ilike.%${trimmed}%`];
    if (groupCodePattern) {
      orConds.push(`group_name.ilike.%${groupCodePattern}%`);
      if (groupMatch) {
        orConds.push(`group_name.ilike.%Group ${groupMatch[1]}%`);
      }
    }
    const { data: grpData } = await supabase
      .from("groups")
      .select("id")
      .or(orConds.join(","));

    if (grpData && grpData.length > 0) {
      groupIds = grpData
        .map((g: { id: string }) => g.id)
        .filter(Boolean);
    }
  } catch {
    // non-blocking fallback
  }

  return {
    groupIds,
    groupCodePattern,
    cleanText: trimmed,
  };
}

/**
 * Resolves account filter against public.accounts to fetch account ID and canonical name.
 */
async function resolveAccountFilter(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  rawFilter: string
): Promise<{
  id: string;
  accountName: string;
  groupId: string | null;
} | null> {
  const trimmed = rawFilter.trim();
  if (!trimmed) return null;

  try {
    const { data: accounts } = await supabase
      .from("accounts")
      .select("id, account_name, group_id")
      .ilike("account_name", `%${trimmed}%`)
      .limit(1);

    if (accounts && accounts.length > 0) {
      return {
        id: accounts[0].id,
        accountName: accounts[0].account_name,
        groupId: accounts[0].group_id,
      };
    }
  } catch {
    // non-blocking fallback
  }

  return null;
}

/**
 * 1. Plantilla Summary Executor
 */
async function executePlantillaSummary(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  {
    accountFilter,
    branchFilter,
    groupFilter,
    slotCode,
    statusFilter,
  }: {
    accountFilter?: string;
    branchFilter?: string;
    groupFilter?: string;
    slotCode?: string;
    statusFilter?: string;
  }
) {
  try {
    return await executeWithTimeout(async () => {
      const looksLikeGroup =
        branchFilter &&
        (/group\s*\d+/i.test(branchFilter) || /\bg\d+\b/i.test(branchFilter));
      const effectiveGroup =
        groupFilter || (looksLikeGroup ? branchFilter : undefined);

      // Check if query targets an account (e.g. "Alturas")
      const candidateAccount =
        accountFilter || (!looksLikeGroup && branchFilter ? branchFilter : undefined);
      const resolvedAccount = candidateAccount
        ? await resolveAccountFilter(supabase, candidateAccount)
        : null;

      // If an account is resolved, query canonical account allocation KPI + safe roster count
      if (resolvedAccount) {
        let actualHc = 0;
        let vacantHc = 0;
        let pipelineCount = 0;
        let requiredHc = 0;
        let fillRatePercent = "100%";

        const { data: kpiData } = await supabase
          .from("v_account_allocation_kpi")
          .select("actual_hc, slot_vacant_hc, pipeline_count, required_hc, mfr")
          .eq("account_id", resolvedAccount.id)
          .maybeSingle();

        if (kpiData) {
          actualHc = Number(kpiData.actual_hc ?? 0);
          vacantHc = Math.round(Number(kpiData.slot_vacant_hc ?? 0));
          pipelineCount = Number(kpiData.pipeline_count ?? 0);
          requiredHc = Number(kpiData.required_hc ?? (actualHc + vacantHc));
          const rawMfr = requiredHc > 0 ? (actualHc / requiredHc) * 100 : 0;
          fillRatePercent =
            rawMfr >= 100
              ? "100%"
              : actualHc < requiredHc && rawMfr >= 99.95
              ? "99.9%"
              : `${rawMfr.toFixed(2)}%`;
        } else {
          // Fallback to counting v_plantilla_safe rows directly
          const { count: vpsCount } = await supabase
            .from("v_plantilla_safe")
            .select("*", { count: "exact", head: true })
            .eq("account_id", resolvedAccount.id);
          actualHc = vpsCount ?? 0;
          requiredHc = actualHc;
        }

        // Fetch sample active employees for conversational detail
        const { data: sampleEmps } = await supabase
          .from("v_plantilla_safe")
          .select("id, employee_name, employee_no, position, store_name, status")
          .eq("account_id", resolvedAccount.id)
          .order("employee_name", { ascending: true })
          .limit(10);

        // Fetch matching plantilla_slots (if any exist)
        const { data: slotRows } = await supabase
          .from("plantilla_slots")
          .select("id, legacy_vcode, position, slot_status, employment_type")
          .eq("account_id", resolvedAccount.id)
          .limit(10);

        return {
          accountName: resolvedAccount.accountName,
          totalHeadcount: requiredHc,
          activeEmployees: actualHc,
          openVacancies: vacantHc,
          pipelineCount,
          fillRatePercent,
          sampleEmployees: (sampleEmps || []).map((e: Record<string, unknown>) => ({
            name: String(e.employee_name ?? ""),
            employeeNo: String(e.employee_no ?? ""),
            position: String(e.position || "Unspecified"),
            store: String(e.store_name ?? ""),
          })),
          slots: (slotRows || []).map((s: Record<string, unknown>) => ({
            slotCode: String(s.legacy_vcode || s.id || ""),
            position: String(s.position || "Unspecified"),
            status: String(s.slot_status || "Unknown"),
          })),
        };
      }

      const resolvedGroup = effectiveGroup
        ? await resolveGroupFilter(supabase, effectiveGroup)
        : null;

      let query = supabase
        .from("plantilla_slots")
        .select(
          "id, legacy_vcode, position, slot_status, employment_type, store_id, account_id, group_id, created_at"
        );

      if (slotCode) {
        query = query.ilike("legacy_vcode", `%${slotCode}%`);
      }
      if (statusFilter) {
        query = query.ilike("slot_status", `%${statusFilter}%`);
      }

      if (resolvedGroup) {
        const groupOrParts: string[] = [];
        if (resolvedGroup.groupCodePattern) {
          groupOrParts.push(`legacy_vcode.ilike.%${resolvedGroup.groupCodePattern}%`);
        }
        groupOrParts.push(`legacy_vcode.ilike.%${resolvedGroup.cleanText}%`);
        for (const gid of resolvedGroup.groupIds) {
          groupOrParts.push(`group_id.eq.${gid}`);
        }
        query = query.or(groupOrParts.join(","));
      }

      if (branchFilter && !looksLikeGroup) {
        query = query.or(
          `legacy_vcode.ilike.%${branchFilter}%,position.ilike.%${branchFilter}%`
        );
      }

      // Synchronously applied chaining: query is never unwrapped via an async return
      const { data, error } = await query.limit(50);
      if (error) {
        return { error: error.message };
      }

      const rows = data || [];
      const total = rows.length;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const filled = rows.filter((r: any) => (r.slot_status || "").toLowerCase() === "filled").length;
      const vacant = rows.filter(
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (r: any) =>
          (r.slot_status || "").toLowerCase() === "vacant" ||
          (r.slot_status || "").toLowerCase() === "open"
      ).length;
      const fillRate = total > 0 ? Math.round((filled / total) * 100) : 0;

      return {
        totalFound: total,
        filledCount: filled,
        vacantCount: vacant,
        fillRatePercent: `${fillRate}%`,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        sampleRows: rows.slice(0, 15).map((r: any) => ({
          slotCode: r.legacy_vcode || r.id,
          position: r.position || "Unspecified",
          status: r.slot_status || "Unknown",
          employmentType: r.employment_type || "Regular",
        })),
      };
    }, "Failed to query plantilla slots");
  } catch (err) {
    return {
      error:
        err instanceof Error ? err.message : "Failed to query plantilla slots",
    };
  }
}

/**
 * 2. Open Vacancies Executor
 */
async function executeOpenVacancies(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  {
    accountFilter,
    branchFilter,
    groupFilter,
    positionTitle,
    limit = 20,
  }: {
    accountFilter?: string;
    branchFilter?: string;
    groupFilter?: string;
    positionTitle?: string;
    limit?: number;
  }
) {
  try {
    return await executeWithTimeout(async () => {
      const looksLikeGroup =
        branchFilter &&
        (/group\s*\d+/i.test(branchFilter) || /\bg\d+\b/i.test(branchFilter));
      const effectiveGroup =
        groupFilter || (looksLikeGroup ? branchFilter : undefined);

      const candidateAccount =
        accountFilter || (!looksLikeGroup && branchFilter ? branchFilter : undefined);
      const resolvedAccount = candidateAccount
        ? await resolveAccountFilter(supabase, candidateAccount)
        : null;

      const resolvedGroup = effectiveGroup
        ? await resolveGroupFilter(supabase, effectiveGroup)
        : null;

      let query = supabase
        .from("plantilla_slots")
        .select(
          "id, legacy_vcode, position, slot_status, employment_type, store_id, account_id, group_id"
        )
        .or("slot_status.ilike.vacant,slot_status.ilike.open");

      if (positionTitle) {
        query = query.ilike("position", `%${positionTitle}%`);
      }

      if (resolvedAccount) {
        query = query.eq("account_id", resolvedAccount.id);
      } else if (resolvedGroup) {
        const groupOrParts: string[] = [];
        if (resolvedGroup.groupCodePattern) {
          groupOrParts.push(`legacy_vcode.ilike.%${resolvedGroup.groupCodePattern}%`);
        }
        groupOrParts.push(`legacy_vcode.ilike.%${resolvedGroup.cleanText}%`);
        for (const gid of resolvedGroup.groupIds) {
          groupOrParts.push(`group_id.eq.${gid}`);
        }
        query = query.or(groupOrParts.join(","));
      } else if (branchFilter && !looksLikeGroup) {
        query = query.or(
          `legacy_vcode.ilike.%${branchFilter}%,position.ilike.%${branchFilter}%`
        );
      }

      // Synchronously applied chaining
      const { data, error } = await query.limit(limit);
      if (error) {
        return { error: error.message };
      }

      return {
        openSlotsCount: data?.length || 0,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        slots: (data || []).map((s: any) => ({
          slotCode: s.legacy_vcode || s.id,
          position: s.position || "Unspecified",
          status: s.slot_status || "Vacant",
          employmentType: s.employment_type || "Regular",
        })),
      };
    }, "Failed to fetch open vacancies");
  } catch (err) {
    return {
      error:
        err instanceof Error ? err.message : "Failed to fetch open vacancies",
    };
  }
}

/**
 * 3. HR Emploc Queue Executor
 */
async function executeEmplocQueueStatus(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  {
    employeeFilter,
    statusFilter,
  }: {
    employeeFilter?: string;
    branchFilter?: string;
    statusFilter?: string;
  }
) {
  try {
    return await executeWithTimeout(async () => {
      let query = supabase
        .from("hr_emploc")
        .select(
          "id, applicant_name, vcode, employee_no, status, hr_status, assignment_type, store_id, created_at"
        )
        .is("deleted_at", null);

      if (employeeFilter) {
        query = query.or(
          `applicant_name.ilike.%${employeeFilter}%,employee_no.ilike.%${employeeFilter}%`
        );
      }
      if (statusFilter) {
        query = query.ilike("status", `%${statusFilter}%`);
      }

      const { data, error } = await query
        .order("created_at", { ascending: false })
        .limit(25);

      if (error) {
        return { error: error.message };
      }

      return {
        totalQueueCount: data?.length || 0,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        items: (data || []).map((row: any) => ({
          id: row.id,
          employee: row.applicant_name || "Unknown Applicant",
          employeeNo: row.employee_no || "Unassigned",
          targetSlot: row.vcode || "Unassigned",
          status: row.status || "Pending",
          hrStatus: row.hr_status || "Pending",
          assignmentType: row.assignment_type || "Standard",
          createdAt: row.created_at,
        })),
      };
    }, "Failed to query hr_emploc queue");
  } catch (err) {
    return {
      error:
        err instanceof Error ? err.message : "Failed to query hr_emploc queue",
    };
  }
}

/**
 * 4. Headcount Requests Executor
 */
async function executeHeadcountRequests(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  {
    requestId,
    branchFilter,
    statusFilter,
  }: {
    requestId?: string;
    branchFilter?: string;
    statusFilter?: string;
  }
) {
  try {
    return await executeWithTimeout(async () => {
      let query = supabase
        .from("headcount_requests")
        .select(
          "id, request_type, status, target_vcode, headcount_needed, reason, urgency, account_name_snapshot, store_name_snapshot, position_name_snapshot, requested_by_name, requested_at, created_at"
        )
        .eq("is_archived", false);

      if (requestId) {
        query = query.eq("id", requestId);
      }
      if (statusFilter) {
        query = query.ilike("status", `%${statusFilter}%`);
      }
      if (branchFilter) {
        query = query.or(
          `store_name_snapshot.ilike.%${branchFilter}%,account_name_snapshot.ilike.%${branchFilter}%`
        );
      }

      const { data, error } = await query
        .order("created_at", { ascending: false })
        .limit(20);

      if (error) {
        return { error: error.message };
      }

      return {
        totalRequestsFound: data?.length || 0,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        requests: (data || []).map((r: any) => ({
          id: r.id,
          type: r.request_type || "Standard",
          status: r.status || "Pending",
          targetSlot: r.target_vcode || "Unassigned",
          headcountNeeded: r.headcount_needed || 1,
          store: r.store_name_snapshot || "N/A",
          position: r.position_name_snapshot || "N/A",
          requestedBy: r.requested_by_name || "Unknown",
          requestedAt: r.requested_at || r.created_at,
          urgency: r.urgency || "Normal",
        })),
      };
    }, "Failed to query headcount requests");
  } catch (err) {
    return {
      error:
        err instanceof Error
          ? err.message
          : "Failed to query headcount requests",
    };
  }
}

/**
 * Deterministic local fallback router when Gemini Free Tier quota is exhausted
 */
async function handleDeterministicFallback(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  rawPrompt: string
): Promise<string> {
  const p = rawPrompt.toLowerCase().trim();

  // 0. Check for Creator / Builder Identity inquiries ("Who created you?", "Who is Ohm?")
  const isCreatorQuery =
    p.includes("who created") ||
    p.includes("who built") ||
    p.includes("who made") ||
    p.includes("who designed") ||
    p.includes("sino gumawa") ||
    p.includes("sinong gumawa") ||
    p.includes("creator") ||
    p.includes("who is ohm") ||
    p.includes("sino si ohm") ||
    p.includes("kilala mo si ohm") ||
    p.includes("ormhel") ||
    (p.includes("ohm") &&
      (p.includes("who") || p.includes("sino") || p.includes("developer") || p.includes("author")));

  if (isCreatorQuery) {
    if (
      p.includes("who is ohm") ||
      p.includes("sino si ohm") ||
      p.includes("kilala mo si ohm") ||
      p.includes("ormhel")
    ) {
      return (
        "Si **Ormhel \"OHM\" Litong** ay ang **IT Manager sa Moses Coop** at ang **Full-Stack Software Developer & Systems Architect** na nagdisenyo at nagtayo ng buong **OHMployee** ecosystem (parehong Mobile at Web—na nagpapatakbo sa Plantilla, Vacancy, HR Emploc, CENCOM, at OHMni AI Co-Pilot) upang gawing moderno at automated ang pamamahala ng workforce sa mga retail stores at accounts."
      );
    }
    return (
      "Ako ay si **OHMni**, ang official AI Operations & Data Co-Pilot ng OHMployee! Ako ay nilikha at binuo ni **OHM (Ormhel Litong)**, ang IT Manager sa Moses Coop at Systems Architect ng buong OHMployee ecosystem."
    );
  }

  // 1. Check for SOP / How-to queries
  const isHowTo =
    p.includes("paano") ||
    p.includes("how to") ||
    p.includes("how do i") ||
    p.includes("sop") ||
    p.includes("steps") ||
    p.includes("guide");

  if (isHowTo || p.includes("paano mag-request") || p.includes("how to request")) {
    if (p.includes("headcount") || p.includes("request")) {
      return (
        "Para mag-file ng **Headcount Request**:\n\n" +
        "1. Pumunta sa **Plantilla** module (`/plantilla`) mula sa kaliwang navigation sidebar at piliin ang target **Account**.\n" +
        "2. I-click ang **`+ Request Headcount`** button sa kanang itaas ng header (action bar).\n" +
        "3. Piliin ang target **Store / Branch**, **Position / Slot**, bilang ng kailangang headcount, at dahilan (justification).\n" +
        "4. I-click ang **Submit** para mapunta sa **Approvals** module para sa review at approval."
      );
    }
    if (p.includes("mika") || p.includes("hydrate") || p.includes("sync")) {
      return (
        "Para mag-sync o mag-hydrate ng **Plantilla**:\n\n" +
        "1. Pumunta sa **Plantilla** module sa navigation sidebar.\n" +
        "2. Gamitin ang bulk import o i-click ang action button na **`Sync MIKA`** para ma-hydrate ang active slot assignments."
      );
    }
    if (p.includes("emploc") || p.includes("discrepanc") || p.includes("movement")) {
      return (
        "Para i-check ang **HR Emploc** discrepancies:\n\n" +
        "1. Buksan ang **HR Emploc** module mula sa sidebar.\n" +
        "2. I-filter ang queue gamit ang **Pending** o **Sync Status** filter upang mai-kumpara ang web vs. mobile movement records."
      );
    }
    if (p.includes("cencom") || p.includes("central command")) {
      return (
        "Ang **CENCOM** (Central Command) ay matatagpuan sa itaas ng OHMni sa sidebar para sa high-level executive operational oversight at real-time directory tracking."
      );
    }
    return (
      "Narito ang mga gabay mula sa **OHMployee Built-In SOP Manual**:\n\n" +
      "- **Headcount Request:** Navigate sa *Plantilla* module -> piliin ang target Account -> click `+ Request Headcount` sa itaas -> punan ang Store, Position, at headcount -> submit for approval sa *Approvals*.\n" +
      "- **Plantilla Sync:** Navigate sa *Plantilla* -> gamitin ang bulk import / `Sync MIKA` para ma-hydrate ang slots.\n" +
      "- **HR Emploc Queue:** Navigate sa *HR Emploc* -> i-filter ang queue ayon sa pending/sync status para ma-resolve ang discrepancies.\n" +
      "- **CENCOM:** Central Command sa sidebar para sa high-level operational oversight."
    );
  }

  // 1.5. Live Data: Account-level Active Employee / Headcount Inquiry (e.g. "ilan ang active employee ng alturas?", "active employee alturas")
  if (
    p.includes("active") ||
    p.includes("employee") ||
    p.includes("headcount") ||
    p.includes("ilan") ||
    p.includes("alturas")
  ) {
    const cleanWords = p
      .replace(/[^a-zA-Z0-9\s]/g, " ")
      .split(/\s+/)
      .filter(
        (w) =>
          w.length >= 4 &&
          ![
            "ilan",
            "mga",
            "active",
            "employee",
            "employees",
            "headcount",
            "meron",
            "tayo",
            "para",
            "what",
            "many",
            "total",
            "kailan",
            "saan",
            "sino",
          ].includes(w)
      );

    for (const word of cleanWords) {
      const resolved = await resolveAccountFilter(supabase, word);
      if (resolved) {
        const res = await executePlantillaSummary(supabase, {
          accountFilter: resolved.accountName,
        });

        if ("accountName" in res && res.accountName) {
          const act = res.activeEmployees ?? 0;
          const req = res.totalHeadcount ?? act;
          const vac = res.openVacancies ?? 0;
          const rate = res.fillRatePercent ?? "100%";
          return `Sa kasalukuyan, ang **${res.accountName}** ay may **${act} active employees** mula sa kabuuang **${req} required headcount**, na may **${vac} open vacancy** (${rate} fulfillment rate).`;
        }
      }
    }
  }

  // 2. Live Data: Open Vacancies / Vacant
  if (p.includes("vacan") || (p.includes("open") && p.includes("slot"))) {
    const groupMatch = p.match(/group\s*0*(\d+)/i) || p.match(/\bg0*(\d+)\b/i);
    const groupFilter = groupMatch ? `Group ${groupMatch[1]}` : undefined;

    const res = await executeOpenVacancies(supabase, {
      groupFilter,
      limit: 20,
    });

    if ("error" in res && res.error) {
      return `Hindi ma-access ang vacancies sa database: ${res.error}`;
    }

    const count = res.openSlotsCount || 0;
    const groupLabel = groupFilter ? ` para sa ${groupFilter}` : "";

    if (count === 0) {
      return `Walang open vacancies na natagpuan${groupLabel} sa kasalukuyan.`;
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const items = (res.slots || []).slice(0, 10).map((s: any) =>
      `- \`${s.slotCode}\` — **${s.position}** (${s.status.toLowerCase()}, ${s.employmentType.toLowerCase()})`
    );

    return (
      `Mayroong **${count}** open ${count === 1 ? "vacancy" : "vacancies"}${groupLabel}:\n\n` +
      items.join("\n")
    );
  }

  // 3. Live Data: Headcount Requests
  if (p.includes("headcount") || (p.includes("pending") && p.includes("request"))) {
    const res = await executeHeadcountRequests(supabase, {
      statusFilter: "pending",
    });

    if ("error" in res && res.error) {
      return `Hindi ma-access ang headcount requests: ${res.error}`;
    }

    const count = res.totalRequestsFound || 0;
    if (count === 0) {
      return "Walang pending headcount requests sa kasalukuyan.";
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const items = (res.requests || []).slice(0, 10).map((r: any) =>
      `- **${r.position}** (${r.store}) — Needed: **${r.headcountNeeded}** [${r.status}, Urgency: ${r.urgency}, Requested by: ${r.requestedBy}]`
    );

    return (
      `Mayroong **${count}** pending headcount ${count === 1 ? "request" : "requests"} sa kasalukuyan:\n\n` +
      items.join("\n")
    );
  }

  // 4. Live Data: HR Emploc Queue
  if (p.includes("emploc") || (p.includes("queue") && !p.includes("headcount"))) {
    const res = await executeEmplocQueueStatus(supabase, {});

    if ("error" in res && res.error) {
      return `Hindi ma-access ang HR Emploc queue: ${res.error}`;
    }

    const count = res.totalQueueCount || 0;
    if (count === 0) {
      return "Walang pending items sa HR Emploc queue sa kasalukuyan.";
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const items = (res.items || []).slice(0, 10).map((it: any) =>
      `- **${it.employee}** (Slot: \`${it.targetSlot}\`) — Status: **${it.status}** [HR Status: ${it.hrStatus}, Type: ${it.assignmentType}]`
    );

    return (
      `Mayroong **${count}** items sa HR Emploc queue:\n\n` +
      items.join("\n")
    );
  }

  // 5. Live Data: Plantilla Summary
  if (p.includes("plantilla") || p.includes("slot") || p.includes("fill rate") || p.includes("total")) {
    const groupMatch = p.match(/group\s*0*(\d+)/i) || p.match(/\bg0*(\d+)\b/i);
    const groupFilter = groupMatch ? `Group ${groupMatch[1]}` : undefined;

    const res = await executePlantillaSummary(supabase, {
      groupFilter,
    });

    if ("error" in res && res.error) {
      return `Hindi ma-access ang plantilla slots: ${res.error}`;
    }

    const total = res.totalFound || 0;
    const vacant = res.vacantCount || 0;
    const filled = res.filledCount || 0;
    const rate = res.fillRatePercent || "0%";
    const groupLabel = groupFilter ? ` para sa ${groupFilter}` : "";

    return (
      `Plantilla Summary${groupLabel}: Mayroong **${total}** kabuuang slots — **${vacant} vacant**, **${filled} filled** (${rate} fill rate).`
    );
  }

  return (
    "Nandito ako para tumulong sa Plantilla slots, open vacancies, headcount requests, o HR Emploc queues. " +
    "Maaari kang magtanong tulad ng: *'What is the total vacant for group 1?'*, *'Ilang pending headcount requests meron tayo?'*, o *'Paano mag-request ng headcount?'*."
  );
}

export async function POST(req: Request) {
  if (!process.env.GOOGLE_GENERATIVE_AI_API_KEY) {
    return new Response(
      JSON.stringify({
        error:
          "Missing GOOGLE_GENERATIVE_AI_API_KEY in .env.local — please add your Gemini API key and restart npm run dev.",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }

  const authHeader = req.headers.get("authorization");
  const { supabase, user } = await createScopedServerClient(authHeader);

  if (!supabase || !user) {
    return new Response(
      JSON.stringify({
        error: "Unauthorized. Valid session token required to query OHMni.",
      }),
      {
        status: 401,
        headers: { "Content-Type": "application/json" },
      }
    );
  }

  try {
    const { messages } = await req.json();
    if (!Array.isArray(messages)) {
      return new Response(
        JSON.stringify({ error: "Invalid messages payload: expected an array." }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    const modelMessages = await convertToModelMessages(messages);

    // Extract the raw prompt text from the last user message for deterministic fallback
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const lastUserMessage = [...messages].reverse().find((m: any) => m.role === "user");
    const promptText =
      typeof lastUserMessage?.content === "string"
        ? lastUserMessage.content
        : Array.isArray(lastUserMessage?.parts)
        ? lastUserMessage.parts
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            .filter((p: any) => p.type === "text")
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            .map((p: any) => p.text)
            .join(" ")
        : "";

    const tools = {
      getPlantillaSummary: tool({
        description:
          "Queries accounts and plantilla_slots to get summary counts (active employees, total headcount, filled, vacant, fill rate %) and matching slots/employees.",
        inputSchema: z.object({
          accountFilter: z
            .string()
            .optional()
            .describe("Filter by billing account or client name (e.g. 'Alturas')"),
          branchFilter: z
            .string()
            .optional()
            .describe("Filter slots by branch or store name/id"),
          groupFilter: z
            .string()
            .optional()
            .describe("Filter slots by group name, code, or alias (e.g. 'Group 1', 'G1')"),
          slotCode: z
            .string()
            .optional()
            .describe("Filter by slot code / legacy VCode"),
          statusFilter: z
            .string()
            .optional()
            .describe("Filter by slot status (e.g. vacant, filled)"),
        }),
        execute: async (params) => executePlantillaSummary(supabase, params),
      }),

      getOpenVacancies: tool({
        description:
          "Returns open or vacant slots from plantilla_slots grouped or listed with slot code, position, and status.",
        inputSchema: z.object({
          accountFilter: z
            .string()
            .optional()
            .describe("Filter by billing account or client name (e.g. 'Alturas')"),
          branchFilter: z.string().optional().describe("Filter by branch/store"),
          groupFilter: z
            .string()
            .optional()
            .describe("Filter by group name, code, or alias (e.g. 'Group 1', 'G1')"),
          positionTitle: z
            .string()
            .optional()
            .describe("Filter by position title"),
          limit: z
            .number()
            .optional()
            .default(20)
            .describe("Max slots to return"),
        }),
        execute: async (params) => executeOpenVacancies(supabase, params),
      }),

      getEmplocQueueStatus: tool({
        description:
          "Queries hr_emploc for pending or active employee placement/movement items in the queue.",
        inputSchema: z.object({
          employeeFilter: z
            .string()
            .optional()
            .describe(
              "Filter by candidate/employee name or employee number"
            ),
          branchFilter: z
            .string()
            .optional()
            .describe("Filter by target store or branch"),
          statusFilter: z
            .string()
            .optional()
            .describe(
              "Filter by status (e.g. Pending, Correction, Ready, Deployed)"
            ),
        }),
        execute: async (params) => executeEmplocQueueStatus(supabase, params),
      }),

      getHeadcountRequests: tool({
        description:
          "Queries headcount_requests table to return pending or specific headcount requests including branch, role, approval status, and creation date.",
        inputSchema: z.object({
          requestId: z
            .string()
            .optional()
            .describe("Filter by specific headcount request ID"),
          branchFilter: z
            .string()
            .optional()
            .describe("Filter by branch/store name"),
          statusFilter: z
            .string()
            .optional()
            .describe("Filter by status (e.g. pending, approved, rejected)"),
        }),
        execute: async (params) => executeHeadcountRequests(supabase, params),
      }),
    };

    const stream = createUIMessageStream({
      execute: async ({ writer }) => {
        let streamSuccess = false;

        for (const modelName of CANDIDATE_MODELS) {
          try {
            const result = streamText({
              model: google(modelName),
              system: SYSTEM_PROMPT,
              messages: modelMessages,
              stopWhen: stepCountIs(3),
              maxRetries: 0,
              tools,
            });

            const uiStream = result.toUIMessageStream();
            const reader = uiStream.getReader();
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const bufferedChunks: any[] = [];
            let isError = false;

            while (true) {
              const { done, value } = await reader.read();
              if (done) break;

              if (value?.type === "error") {
                isError = true;
                break;
              }

              bufferedChunks.push(value);
              // As soon as generation starts emitting real steps, deltas, or tool calls, the model is confirmed working
              if (
                value?.type === "start-step" ||
                value?.type === "text-start" ||
                value?.type === "text-delta" ||
                (typeof value?.type === "string" && value.type.startsWith("tool-"))
              ) {
                break;
              }
            }

            if (isError) {
              console.warn(
                `[OHMni] Model ${modelName} returned error/quota-exceeded. Failing over to next candidate...`
              );
              reader.releaseLock();
              continue;
            }

            // Flush buffered chunks
            for (const chunk of bufferedChunks) {
              writer.write(chunk);
            }

            // Stream remainder of the response
            while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              if (value?.type === "error") {
                console.warn(`[OHMni] Model ${modelName} encountered error mid-stream:`, value);
                break;
              }
              writer.write(value);
            }

            reader.releaseLock();
            streamSuccess = true;
            break;
          } catch (err) {
            console.warn(`[OHMni] Error launching model ${modelName}:`, err);
          }
        }

        // Deterministic Zero-Quota Fallback when all Free Tier models hit 429
        if (!streamSuccess) {
          console.warn(
            "[OHMni] All Gemini models exhausted. Activating deterministic local fallback."
          );
          const fallbackText = await handleDeterministicFallback(supabase, promptText);
          writer.write({ type: "start" });
          writer.write({ type: "text-start", id: "fb-answer" });
          writer.write({ type: "text-delta", id: "fb-answer", delta: fallbackText });
          writer.write({ type: "text-end", id: "fb-answer" });
          writer.write({ type: "finish", finishReason: "stop" });
        }
      },
    });

    return createUIMessageStreamResponse({ stream });
  } catch (err) {
    console.error("[OHMni API Error]:", err);
    return new Response(
      JSON.stringify({
        error:
          err instanceof Error
            ? err.message
            : "An unexpected error occurred while processing the request.",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
}
