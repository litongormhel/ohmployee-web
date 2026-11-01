import { streamText, tool, stepCountIs, convertToModelMessages } from "ai";
import { google } from "@ai-sdk/google";
import { z } from "zod";
import { createScopedServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

const OHMPLOYEE_SOP_MANUAL = `
## Built-In SOP Manual:
- How to file a Headcount Request: Navigate to Vacancy module -> click "+ Request Headcount" -> select Branch & Position/Slot -> submit for approval.
- How to hydrate/sync Plantilla: Navigate to Plantilla -> use bulk import / "Sync MIKA" action to hydrate slot assignments.
- How to check HR Emploc discrepancies: Navigate to HR Emploc -> filter queue by pending/sync status to compare web vs. mobile movement records.
- CENCOM overview: Central Command sits right above OHMni for high-level executive operational oversight and directory tracking.
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
3. Group & Branch Lookups: When searching for groups (e.g., 'Group 1', 'G1'), use groupFilter or branchFilter with 'G1' or 'group 1' to match legacy slot codes and group assignments.
4. Formatting Rules: Keep outputs compact and readable. Use short bullet lists and monospace badges for Slot Codes/IDs (\`SLOT-001\`). Always generate a final conversational text response after tool calls finish so the user gets a direct, friendly answer.
5. Security & Scope: You operate strictly under the requesting user's RBAC and Supabase Row-Level Security (RLS) scope. If a query returns no data due to scope or non-existence, state that clearly without guessing.

${OHMPLOYEE_SOP_MANUAL}
`;

async function applyPlantillaFilters(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  query: any,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  options: {
    branchFilter?: string;
    groupFilter?: string;
  }
) {
  let updatedQuery = query;
  const { branchFilter, groupFilter } = options;

  // Check if groupFilter is provided or if branchFilter looks like a group (e.g. "group 1", "g1")
  const looksLikeGroup =
    branchFilter && (/group\s*\d+/i.test(branchFilter) || /\bg\d+\b/i.test(branchFilter));
  const effectiveGroup = groupFilter || (looksLikeGroup ? branchFilter : undefined);

  if (effectiveGroup) {
    const trimmed = effectiveGroup.trim();
    const groupMatch =
      trimmed.match(/group\s*0*(\d+)/i) || trimmed.match(/\bg0*(\d+)\b/i);
    const groupPattern = groupMatch ? `G${groupMatch[1]}` : undefined;

    let groupIds: string[] = [];
    try {
      const orConds = [`group_name.ilike.%${trimmed}%`];
      if (groupPattern) {
        orConds.push(`group_name.ilike.%${groupPattern}%`);
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

    const groupOrParts: string[] = [];
    if (groupPattern) {
      groupOrParts.push(`legacy_vcode.ilike.%${groupPattern}%`);
    }
    groupOrParts.push(`legacy_vcode.ilike.%${trimmed}%`);
    if (groupIds.length > 0) {
      for (const gid of groupIds) {
        groupOrParts.push(`group_id.eq.${gid}`);
      }
    }

    updatedQuery = updatedQuery.or(groupOrParts.join(","));
  }

  // If branchFilter was provided and was not a group alias
  if (branchFilter && !looksLikeGroup) {
    updatedQuery = updatedQuery.or(
      `legacy_vcode.ilike.%${branchFilter}%,position.ilike.%${branchFilter}%`
    );
  }

  return updatedQuery;
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

    const result = streamText({
      model: google("gemini-3.5-flash"),
      system: SYSTEM_PROMPT,
      messages: modelMessages,
      stopWhen: stepCountIs(3),
      tools: {
        getPlantillaSummary: tool({
          description:
            "Queries plantilla_slots to get summary counts (total, filled, vacant, fill rate %) and up to 15 matching slots.",
          inputSchema: z.object({
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
          execute: async ({ branchFilter, groupFilter, slotCode, statusFilter }) => {
            try {
              return await executeWithTimeout(async () => {
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

                query = await applyPlantillaFilters(query, supabase, {
                  branchFilter,
                  groupFilter,
                });

                const { data, error } = await query.limit(50);
                if (error) {
                  return { error: error.message };
                }

                const rows = data || [];
                const total = rows.length;
                const filled = rows.filter(
                  (r) => (r.slot_status || "").toLowerCase() === "filled"
                ).length;
                const vacant = rows.filter(
                  (r) =>
                    (r.slot_status || "").toLowerCase() === "vacant" ||
                    (r.slot_status || "").toLowerCase() === "open"
                ).length;
                const fillRate = total > 0 ? Math.round((filled / total) * 100) : 0;

                return {
                  totalFound: total,
                  filledCount: filled,
                  vacantCount: vacant,
                  fillRatePercent: `${fillRate}%`,
                  sampleRows: rows.slice(0, 15).map((r) => ({
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
                  err instanceof Error
                    ? err.message
                    : "Failed to query plantilla slots",
              };
            }
          },
        }),

        getOpenVacancies: tool({
          description:
            "Returns open or vacant slots from plantilla_slots grouped or listed with slot code, position, and status.",
          inputSchema: z.object({
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
          execute: async ({ branchFilter, groupFilter, positionTitle, limit = 20 }) => {
            try {
              return await executeWithTimeout(async () => {
                let query = supabase
                  .from("plantilla_slots")
                  .select(
                    "id, legacy_vcode, position, slot_status, employment_type, store_id, account_id, group_id"
                  )
                  .or("slot_status.ilike.vacant,slot_status.ilike.open");

                if (positionTitle) {
                  query = query.ilike("position", `%${positionTitle}%`);
                }

                query = await applyPlantillaFilters(query, supabase, {
                  branchFilter,
                  groupFilter,
                });

                const { data, error } = await query.limit(limit);
                if (error) {
                  return { error: error.message };
                }

                return {
                  openSlotsCount: data?.length || 0,
                  slots: (data || []).map((s) => ({
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
                  err instanceof Error
                    ? err.message
                    : "Failed to fetch open vacancies",
              };
            }
          },
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
          execute: async ({ employeeFilter, statusFilter }) => {
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
                  items: (data || []).map((row) => ({
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
                  err instanceof Error
                    ? err.message
                    : "Failed to query hr_emploc queue",
              };
            }
          },
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
          execute: async ({ requestId, branchFilter, statusFilter }) => {
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
                  requests: (data || []).map((r) => ({
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
          },
        }),
      },
    });

    return result.toUIMessageStreamResponse({
      onError: (err) => {
        console.error("[OHMni API Stream Error]:", err);
        return err instanceof Error ? err.message : String(err);
      },
    });
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
