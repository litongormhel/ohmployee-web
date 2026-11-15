"use client";

import React, { useState, useMemo, useRef, useEffect, useCallback } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { createClient } from "@/lib/supabase/client";
import { useQueryClient } from "@tanstack/react-query";
import type { WebCurrentUserContext } from "@/lib/auth";
import { submitHeadcountRequest } from "@/lib/queries/requests";
import { requestVacancyClosure } from "@/lib/queries/vacancy/vacancyClosures";
import {
  RotateCcw,
  ChevronLeft,
  ArrowUp,
  Loader2,
  Bot,
  CheckCircle2,
  AlertCircle,
  ArrowRight,
  Check,
} from "lucide-react";

type OhmniDrawerProps = {
  isOpen: boolean;
  onClose: () => void;
  currentUser?: WebCurrentUserContext | null;
};

// ── Lightweight Markdown & Inline Formatter ─────────────────────────────────

function renderInlineFormatted(text: string): React.ReactNode {
  const parts: React.ReactNode[] = [];
  let remaining = text;
  let keyIdx = 0;

  while (remaining.length > 0) {
    const codeMatch = remaining.match(/`([^`]+)`/);
    const boldMatch = remaining.match(/\*\*([^*]+)\*\*/);

    let firstMatch: { index: number; length: number; node: React.ReactNode } | null = null;

    if (codeMatch && codeMatch.index !== undefined) {
      firstMatch = {
        index: codeMatch.index,
        length: codeMatch[0].length,
        node: (
          <code
            key={`c-${keyIdx++}`}
            className="tech-token text-[11px] mx-0.5"
          >
            {codeMatch[1]}
          </code>
        ),
      };
    }

    if (boldMatch && boldMatch.index !== undefined) {
      if (!firstMatch || boldMatch.index < firstMatch.index) {
        firstMatch = {
          index: boldMatch.index,
          length: boldMatch[0].length,
          node: (
            <strong key={`b-${keyIdx++}`} className="font-semibold text-text-primary">
              {boldMatch[1]}
            </strong>
          ),
        };
      }
    }

    if (!firstMatch) {
      parts.push(remaining);
      break;
    }

    if (firstMatch.index > 0) {
      parts.push(remaining.slice(0, firstMatch.index));
    }
    parts.push(firstMatch.node);
    remaining = remaining.slice(firstMatch.index + firstMatch.length);
  }

  return parts;
}

function FormattedContent({ content }: { content: string }) {
  const lines = content.split("\n");
  const renderedElements: React.ReactNode[] = [];
  let tableRows: string[][] = [];
  let inTable = false;

  const flushTable = (idx: number) => {
    if (tableRows.length > 0) {
      const header = tableRows[0];
      const dataRows = tableRows.slice(1);
      renderedElements.push(
        <div
          key={`table-wrapper-${idx}`}
          className="my-3 overflow-x-auto rounded-xl border border-[var(--border-subtle)] shadow-2xs"
        >
          <table className="min-w-full divide-y divide-[var(--border-subtle)] text-left text-xs">
            <thead className="bg-surface-muted font-semibold text-text-primary">
              <tr>
                {header.map((col, cIdx) => (
                  <th key={`th-${cIdx}`} className="px-3 py-2 whitespace-nowrap">
                    {col}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-subtle)] bg-surface-base">
              {dataRows.map((r, rIdx) => (
                <tr key={`tr-${rIdx}`} className="hover:bg-surface-hover transition-colors">
                  {r.map((col, cIdx) => (
                    <td key={`td-${cIdx}`} className="px-3 py-2 whitespace-nowrap text-text-secondary">
                      {renderInlineFormatted(col)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
      tableRows = [];
      inTable = false;
    }
  };

  lines.forEach((line, idx) => {
    const trimmed = line.trim();

    if (trimmed.startsWith("|") && trimmed.endsWith("|")) {
      const cols = trimmed
        .slice(1, -1)
        .split("|")
        .map((c) => c.trim());
      if (cols.every((c) => /^:?-+:?$/.test(c))) {
        return;
      }
      inTable = true;
      tableRows.push(cols);
      return;
    }

    if (inTable) {
      flushTable(idx);
    }

    if (!trimmed) {
      return;
    }

    if (trimmed.startsWith("- ") || trimmed.startsWith("* ")) {
      renderedElements.push(
        <div key={`li-${idx}`} className="flex items-start gap-2 pl-1 my-1">
          <span className="text-emerald-500 mt-1.5 text-[7px]">●</span>
          <span className="flex-1 leading-relaxed text-sm text-text-secondary">
            {renderInlineFormatted(trimmed.slice(2))}
          </span>
        </div>
      );
      return;
    }

    renderedElements.push(
      <p key={`p-${idx}`} className="leading-relaxed my-1.5 text-sm text-text-secondary">
        {renderInlineFormatted(trimmed)}
      </p>
    );
  });

  if (inTable) {
    flushTable(lines.length);
  }

  return <div className="space-y-1">{renderedElements}</div>;
}

// ── Fallback Direct Tool Output Formatter ───────────────────────────────────

type GenericToolOutput = Record<string, unknown>;

function getToolOutputPayload(tp: unknown): GenericToolOutput | undefined {
  if (!tp || typeof tp !== "object") return undefined;
  const cast = tp as GenericToolOutput;
  return (
    (cast.output as GenericToolOutput) ||
    (cast.result as GenericToolOutput) ||
    undefined
  );
}

function hasToolResults(out?: GenericToolOutput): boolean {
  if (!out || typeof out !== "object") return false;
  if (Array.isArray(out.slots)) return out.slots.length > 0;
  if (typeof out.totalFound === "number") return out.totalFound > 0;
  if (Array.isArray(out.items)) return out.items.length > 0;
  if (Array.isArray(out.requests)) return out.requests.length > 0;
  if (Array.isArray(out.roster)) return out.roster.length > 0;
  if (Array.isArray(out.events)) return out.events.length > 0;
  if (Boolean(out.slotCode)) return true;
  return false;
}

function isActionDraftTool(tp: unknown): boolean {
  const out = getToolOutputPayload(tp);
  return Boolean(
    out &&
    (out.action === "SUBMIT_HEADCOUNT_REQUEST" ||
     out.action === "SUBMIT_VACANCY_CLOSURE")
  );
}

function ToolOutputFallbackView({
  toolParts,
}: {
  toolParts: unknown[];
}) {
  if (!toolParts || toolParts.length === 0) return null;

  // Prioritize the last tool part that produced actual results; otherwise take the last tool part
  const partsWithPayload = toolParts.map((tp) => {
    const rawToolName = ((tp as { type?: string })?.type || "").replace(/^tool-/, "");
    const output = getToolOutputPayload(tp);
    return { tp, rawToolName, output, hasData: hasToolResults(output) };
  });

  const selected =
    [...partsWithPayload].reverse().find((p) => p.hasData) ||
    partsWithPayload[partsWithPayload.length - 1];

  if (!selected || !selected.output) {
    return (
      <p className="text-sm text-text-muted">
        No records found matching your query.
      </p>
    );
  }

  const { output } = selected;

  if (output.error) {
    return (
      <p className="text-sm text-danger">
        Query encountered an error: {String(output.error)}
      </p>
    );
  }

  // Handle getOpenVacancies
  if (Array.isArray(output.slots)) {
    const slots = output.slots as Array<{
      slotCode?: string;
      position?: string;
      status?: string;
      employmentType?: string;
    }>;

    if (slots.length === 0) {
      return (
        <p className="text-sm text-text-muted">
          No open vacancies found matching your query.
        </p>
      );
    }

    return (
      <div className="space-y-2">
        <p className="text-sm text-text-secondary">
          Found <strong className="text-text-primary">{slots.length}</strong> open {slots.length === 1 ? "vacancy" : "vacancies"}:
        </p>
        <ul className="space-y-1.5 pl-1">
          {slots.map((s, idx) => (
            <li key={idx} className="flex items-start gap-2 text-sm text-text-secondary">
              <span className="text-emerald-500 mt-1.5 text-[7px]">●</span>
              <span className="leading-relaxed">
                <strong className="font-semibold text-text-primary tech-token">
                  {s.slotCode || "—"}
                </strong>{" "}
                — {s.position || "Unspecified"} ({s.status?.toLowerCase() || "open"}, {s.employmentType?.toLowerCase() || "regular"})
              </span>
            </li>
          ))}
        </ul>
      </div>
    );
  }

  // Handle getPlantillaSummary
  if (output.totalFound !== undefined || output.fillRatePercent !== undefined) {
    const total = Number(output.totalFound ?? 0);
    const vacant = Number(output.vacantCount ?? 0);
    const filled = Number(output.filledCount ?? 0);
    const rate = String(output.fillRatePercent ?? "0%");
    const sampleRows = Array.isArray(output.sampleRows)
      ? (output.sampleRows as Array<{
          slotCode?: string;
          position?: string;
          status?: string;
        }>)
      : [];

    if (total === 0) {
      return (
        <p className="text-sm text-text-muted">
          No plantilla slots found matching your query.
        </p>
      );
    }

    return (
      <div className="space-y-2">
        <p className="text-sm text-text-secondary">
          Found <strong className="text-text-primary">{total}</strong> total {total === 1 ? "slot" : "slots"} (
          <strong className="text-amber-500 font-semibold">{vacant} vacant</strong>,{" "}
          <strong className="text-emerald-500 font-semibold">{filled} filled</strong>, {rate} fill rate):
        </p>
        {sampleRows.length > 0 && (
          <ul className="space-y-1.5 pl-1">
            {sampleRows.slice(0, 10).map((r, idx) => (
              <li key={idx} className="flex items-start gap-2 text-sm text-text-secondary">
                <span className="text-emerald-500 mt-1.5 text-[7px]">●</span>
                <span className="leading-relaxed">
                  <strong className="font-semibold text-text-primary tech-token">
                    {r.slotCode || "—"}
                  </strong>{" "}
                  — {r.position || "Unspecified"} ({r.status?.toLowerCase() || "open"})
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>
    );
  }

  // Handle getEmplocQueueStatus
  if (Array.isArray(output.items)) {
    const items = output.items as Array<{
      employee?: string;
      employeeNo?: string;
      targetSlot?: string;
      status?: string;
      hrStatus?: string;
    }>;

    if (items.length === 0) {
      return (
        <p className="text-sm text-text-muted">
          No HR Emploc queue items found matching your query.
        </p>
      );
    }

    return (
      <div className="space-y-2">
        <p className="text-sm text-text-secondary">
          Found <strong className="text-text-primary">{items.length}</strong> {items.length === 1 ? "item" : "items"} in HR Emploc queue:
        </p>
        <ul className="space-y-1.5 pl-1">
          {items.slice(0, 10).map((it, idx) => (
            <li key={idx} className="flex items-start gap-2 text-sm text-text-secondary">
              <span className="text-emerald-500 mt-1.5 text-[7px]">●</span>
              <span className="leading-relaxed">
                <strong className="font-semibold text-text-primary">{it.employee}</strong> ({it.employeeNo || "—"}) — Target:{" "}
                <strong className="tech-token">
                  {it.targetSlot || "—"}
                </strong>{" "}
                [{it.status || "Pending"}]
              </span>
            </li>
          ))}
        </ul>
      </div>
    );
  }

  // Handle getHeadcountRequests
  if (Array.isArray(output.requests)) {
    const requests = output.requests as Array<{
      position?: string;
      store?: string;
      headcountNeeded?: number;
      status?: string;
    }>;

    if (requests.length === 0) {
      return (
        <p className="text-sm text-text-muted">
          No headcount requests found matching your query.
        </p>
      );
    }

    return (
      <div className="space-y-2">
        <p className="text-sm text-text-secondary">
          Found <strong className="text-text-primary">{requests.length}</strong> headcount {requests.length === 1 ? "request" : "requests"}:
        </p>
        <ul className="space-y-1.5 pl-1">
          {requests.slice(0, 10).map((r, idx) => (
            <li key={idx} className="flex items-start gap-2 text-sm text-text-secondary">
              <span className="text-emerald-500 mt-1.5 text-[7px]">●</span>
              <span className="leading-relaxed">
                <strong className="font-semibold text-text-primary">{r.position || "Unspecified"}</strong> ({r.store || "—"}) — Needed: {r.headcountNeeded ?? 1} [{r.status || "Pending"}]
              </span>
            </li>
          ))}
        </ul>
      </div>
    );
  }

  // Handle draftHeadcountRequest
  if (output.action === "SUBMIT_HEADCOUNT_REQUEST" && output.draft) {
    const draft = output.draft as {
      storeName?: string;
      position?: string;
      headcountNeeded?: number;
      reason?: string;
    };

    return (
      <div className="my-2 p-3.5 rounded-xl border border-emerald-500/30 bg-emerald-500/5 space-y-2.5">
        <div className="flex items-center gap-2 text-xs font-semibold text-emerald-600 dark:text-emerald-400">
          <Bot className="h-4 w-4" />
          <span>Action Ready: Headcount Request Draft</span>
        </div>
        <div className="text-xs space-y-1 text-text-secondary">
          <p>• <strong>Branch:</strong> {draft.storeName || "Unassigned"}</p>
          <p>• <strong>Position:</strong> {draft.position || "Staff"}</p>
          <p>• <strong>Count Needed:</strong> {draft.headcountNeeded ?? 1}</p>
          <p>• <strong>Justification:</strong> {draft.reason || "Operational demand"}</p>
        </div>
        <div className="pt-1">
          <a
            href={`/plantilla?request=headcount&store=${encodeURIComponent(draft.storeName || "")}&pos=${encodeURIComponent(draft.position || "")}`}
            className="inline-flex items-center justify-center px-3 py-1.5 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg shadow-xs transition-colors"
          >
            Review & Submit in Plantilla →
          </a>
        </div>
      </div>
    );
  }

  // Handle draftVacancyClosure
  if (output.action === "SUBMIT_VACANCY_CLOSURE" && output.draft) {
    const draft = output.draft as {
      vcode?: string;
      position?: string;
      storeName?: string;
      reason?: string;
    };

    return (
      <div className="my-2 p-3.5 rounded-xl border border-amber-500/30 bg-amber-500/5 space-y-2.5">
        <div className="flex items-center gap-2 text-xs font-semibold text-amber-600 dark:text-amber-400">
          <Bot className="h-4 w-4" />
          <span>Action Ready: Vacancy Closure Draft</span>
        </div>
        <div className="text-xs space-y-1 text-text-secondary">
          <p>• <strong>Slot Code:</strong> <code className="tech-token">{draft.vcode}</code></p>
          <p>• <strong>Position:</strong> {draft.position || "—"}</p>
          <p>• <strong>Branch:</strong> {draft.storeName || "—"}</p>
          <p>• <strong>Reason:</strong> {draft.reason || "Closure requested"}</p>
        </div>
        <div className="pt-1">
          <a
            href={`/vacancy?q=${encodeURIComponent(draft.vcode || "")}`}
            className="inline-flex items-center justify-center px-3 py-1.5 text-xs font-semibold text-white bg-amber-600 hover:bg-amber-700 rounded-lg shadow-xs transition-colors"
          >
            Review & Close in Vacancy Hub →
          </a>
        </div>
      </div>
    );
  }

  // Handle getOperationalBriefing
  if (output.totalActionItems !== undefined) {
    const briefing = output as {
      pendingHeadcount?: number;
      openVacancies?: number;
      agingVacancies?: number;
      pendingEmploc?: number;
      pendingClosures?: number;
      totalActionItems?: number;
      priorityAccounts?: Array<{
        name?: string;
        vacancies?: number;
        fillRate?: string;
      }>;
    };

    return (
      <div className="space-y-2 p-3 rounded-xl border border-[var(--border-subtle)] bg-surface-muted/50">
        <p className="text-xs font-semibold text-text-primary">
          📋 Today&apos;s Operational Snapshot ({briefing.totalActionItems ?? 0} Action Items):
        </p>
        <ul className="space-y-1 pl-1 text-xs text-text-secondary">
          <li>• <strong>Pending Headcount Requests:</strong> {briefing.pendingHeadcount ?? 0}</li>
          <li>• <strong>Open Vacancies:</strong> {briefing.openVacancies ?? 0} active</li>
          {Number(briefing.agingVacancies ?? 0) > 0 && (
            <li className="text-amber-600 dark:text-amber-400 font-medium">
              • <strong>Aging Vacancies (&gt;30d SLA Alert):</strong> {briefing.agingVacancies}
            </li>
          )}
          <li>• <strong>HR Emploc Queue:</strong> {briefing.pendingEmploc ?? 0} pending</li>
          <li>• <strong>Closure Requests:</strong> {briefing.pendingClosures ?? 0}</li>
        </ul>
      </div>
    );
  }

  // Handle inspectSlot (Phase 2 Layer 3)
  if (output.slotCode && (output.occupant !== undefined || output.candidate !== undefined || output.slotId)) {
    const slot = output as {
      slotCode?: string;
      status?: string;
      position?: string;
      employmentType?: string;
      isRoving?: boolean;
      storeName?: string;
      accountName?: string;
      occupant?: {
        name: string;
        employeeNo: string;
        position: string;
        status: string;
        dateHired?: string;
      } | null;
      candidate?: {
        name: string;
        stage: string;
        contactNo?: string;
      } | null;
      recentHistory?: Array<{
        action: string;
        oldValue: string;
        newValue: string;
        remarks: string;
      }>;
    };

    return (
      <div className="space-y-2 p-3 rounded-xl border border-[var(--border-subtle)] bg-surface-muted/50">
        <div className="flex items-center justify-between">
          <p className="text-xs font-semibold text-text-primary">
            🔍 Slot Details: <code className="tech-token">{slot.slotCode}</code>
          </p>
          <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-surface-elevated text-text-secondary font-semibold">
            {slot.status || "—"}
          </span>
        </div>
        <div className="text-xs space-y-1 text-text-secondary">
          <p>• <strong>Position:</strong> {slot.position || "—"} ({slot.employmentType || "Regular"}, {slot.isRoving ? "Roving" : "Stationary"})</p>
          <p>• <strong>Branch:</strong> {slot.storeName || "—"} ({slot.accountName || "—"})</p>
          {slot.occupant ? (
            <p className="text-emerald-600 dark:text-emerald-400 font-medium">
              • <strong>Occupant:</strong> {slot.occupant.name} (<code className="tech-token">{slot.occupant.employeeNo}</code>, {slot.occupant.status})
            </p>
          ) : (
            <p className="text-amber-600 dark:text-amber-400 font-medium">• <strong>Occupant:</strong> None (Vacant)</p>
          )}
          {slot.candidate && (
            <p className="text-sky-600 dark:text-sky-400 font-medium">
              • <strong>Candidate Reserved:</strong> {slot.candidate.name} [{slot.candidate.stage}]
            </p>
          )}
        </div>
        {slot.recentHistory && slot.recentHistory.length > 0 && (
          <div className="pt-1.5 border-t border-[var(--border-subtle)] text-[11px] text-text-secondary space-y-1">
            <span className="font-semibold text-text-primary">Recent Transition:</span>
            <p className="pl-1 text-text-muted">
              {slot.recentHistory[0].action}: {slot.recentHistory[0].oldValue || "—"} ➔ {slot.recentHistory[0].newValue || "—"} ({slot.recentHistory[0].remarks || "No remarks"})
            </p>
          </div>
        )}
      </div>
    );
  }

  // Handle inspectStoreRoster (Phase 2 Layer 3)
  if (Array.isArray(output.roster)) {
    const data = output as {
      storeName?: string;
      accountName?: string;
      totalStaff?: number;
      activeCount?: number;
      onLeaveCount?: number;
      floatingCount?: number;
      openVacanciesCount?: number;
      roster: Array<{
        name: string;
        employeeNo: string;
        position: string;
        status: string;
        deploymentType?: string;
        slotCode?: string;
      }>;
    };

    return (
      <div className="space-y-2 p-3 rounded-xl border border-[var(--border-subtle)] bg-surface-muted/50">
        <p className="text-xs font-semibold text-text-primary">
          👥 Staff Roster: {data.storeName || "Store"} ({data.totalStaff ?? 0} Staff, {data.openVacanciesCount ?? 0} Vacancies):
        </p>
        <ul className="space-y-1.5 pl-1 max-h-48 overflow-y-auto">
          {data.roster.slice(0, 15).map((m, idx) => (
            <li key={idx} className="flex items-start gap-2 text-xs text-text-secondary">
              <span className="text-emerald-500 mt-1.5 text-[7px]">●</span>
              <span className="leading-relaxed">
                <strong className="font-semibold text-text-primary">{m.name}</strong> (<code className="tech-token">{m.employeeNo}</code>) — {m.position} [{m.status}]
              </span>
            </li>
          ))}
        </ul>
      </div>
    );
  }

  // Handle getSlotAuditHistory (Phase 2 Layer 3)
  if (Array.isArray(output.events) && output.slotCode) {
    const hist = output as {
      slotCode: string;
      totalEvents?: number;
      events: Array<{
        action: string;
        oldValue: string;
        newValue: string;
        remarks: string;
        performedBy: string;
        createdAt?: string;
      }>;
    };

    return (
      <div className="space-y-2 p-3 rounded-xl border border-[var(--border-subtle)] bg-surface-muted/50">
        <p className="text-xs font-semibold text-text-primary">
          📜 Audit Timeline: <code className="tech-token">{hist.slotCode}</code> ({hist.totalEvents ?? hist.events.length} Events):
        </p>
        <ul className="space-y-1.5 pl-1">
          {hist.events.slice(0, 5).map((e, idx) => (
            <li key={idx} className="text-xs text-text-secondary leading-relaxed">
              <span className="font-semibold text-text-primary">• {e.action}</span>: {e.oldValue || "—"} ➔ {e.newValue || "—"} by {e.performedBy}
              {e.remarks ? <span className="italic text-text-muted"> ({e.remarks})</span> : null}
            </li>
          ))}
        </ul>
      </div>
    );
  }

  return (
    <p className="text-sm text-text-muted">
      Query completed successfully.
    </p>
  );
}

// ── Interactive Action Draft Card Component (Phase 2 Layer 2) ───────────────

interface ActionDraftCardProps {
  messageId: string;
  toolPart: unknown;
  submittingDrafts: Record<string, boolean>;
  submittedDrafts: Record<
    string,
    {
      status: "success" | "error";
      requestId?: string;
      vcode?: string;
      error?: string;
    }
  >;
  onConfirmHeadcount: (
    key: string,
    draft: {
      storeId?: string | null;
      storeName?: string;
      accountId?: string | null;
      accountName?: string;
      positionId?: string | null;
      position?: string;
      headcountNeeded?: number;
      reason?: string;
    }
  ) => Promise<void>;
  onConfirmVacancyClosure: (
    key: string,
    draft: {
      vacancyId?: string;
      vcode: string;
      position?: string;
      storeName?: string;
      reason?: string;
    }
  ) => Promise<void>;
}

function ActionDraftCard({
  messageId,
  toolPart,
  submittingDrafts,
  submittedDrafts,
  onConfirmHeadcount,
  onConfirmVacancyClosure,
}: ActionDraftCardProps) {
  const output = getToolOutputPayload(toolPart);
  if (!output || typeof output !== "object") return null;

  // 1. Headcount Request Draft
  if (output.action === "SUBMIT_HEADCOUNT_REQUEST" && output.draft) {
    const draft = output.draft as {
      storeId?: string | null;
      storeName?: string;
      accountId?: string | null;
      accountName?: string;
      positionId?: string | null;
      position?: string;
      headcountNeeded?: number;
      reason?: string;
    };
    const draftKey = `hc_${messageId}_${draft.storeName || ""}_${draft.position || ""}`;
    const isSubmitting = Boolean(submittingDrafts[draftKey]);
    const submission = submittedDrafts[draftKey];

    if (submission?.status === "success") {
      return (
        <div className="my-2.5 p-3.5 rounded-xl border border-emerald-500/40 bg-emerald-500/10 space-y-2.5 transition-all">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs font-semibold text-emerald-600 dark:text-emerald-400">
              <CheckCircle2 className="h-4 w-4 text-emerald-500" />
              <span>Headcount Request Submitted!</span>
            </div>
            <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-600 dark:text-emerald-300 font-bold">
              Pending Review
            </span>
          </div>
          <div className="text-xs space-y-1 text-text-secondary">
            <p>
              • <strong>Request ID:</strong>{" "}
              <code className="tech-token">{submission.requestId || "Submitted"}</code>
            </p>
            <p>
              • <strong>Branch:</strong> {draft.storeName || "—"}
            </p>
            <p>
              • <strong>Position:</strong> {draft.position || "Staff"} (
              {draft.headcountNeeded ?? 1} slot
              {(draft.headcountNeeded ?? 1) > 1 ? "s" : ""})
            </p>
          </div>
          <div className="pt-1 flex flex-wrap items-center gap-2">
            <a
              href="/my-requests"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg shadow-xs transition-colors"
            >
              <span>Track in My Requests</span>
              <ArrowRight size={13} />
            </a>
            <a
              href="/approvals?tab=headcount"
              className="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-text-secondary hover:text-text-primary bg-surface-muted hover:bg-surface-elevated border border-[var(--border-subtle)] rounded-lg transition-colors"
            >
              <span>View in Approvals</span>
            </a>
          </div>
        </div>
      );
    }

    return (
      <div className="my-2.5 p-3.5 rounded-xl border border-emerald-500/30 bg-emerald-500/5 space-y-2.5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs font-semibold text-emerald-600 dark:text-emerald-400">
            <Bot className="h-4 w-4" />
            <span>Action Ready: Headcount Request Draft</span>
          </div>
          <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 font-medium">
            Draft Ready
          </span>
        </div>
        <div className="text-xs space-y-1 text-text-secondary">
          <p>
            • <strong>Branch:</strong> {draft.storeName || "Unassigned"}
          </p>
          <p>
            • <strong>Position:</strong> {draft.position || "Staff"}
          </p>
          <p>
            • <strong>Count Needed:</strong> {draft.headcountNeeded ?? 1}
          </p>
          <p>
            • <strong>Justification:</strong> {draft.reason || "Operational demand"}
          </p>
        </div>
        {submission?.status === "error" && (
          <div className="p-2 rounded-lg bg-danger/10 border border-danger/20 text-xs text-danger flex items-start gap-1.5">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{submission.error}</span>
          </div>
        )}
        <div className="pt-1 flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => onConfirmHeadcount(draftKey, draft)}
            disabled={isSubmitting}
            className="inline-flex items-center justify-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 rounded-lg shadow-xs transition-colors cursor-pointer"
          >
            {isSubmitting ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                <span>Submitting...</span>
              </>
            ) : (
              <>
                <Check className="h-3.5 w-3.5" />
                <span>Confirm &amp; Submit</span>
              </>
            )}
          </button>
          <a
            href={`/plantilla?request=headcount&store=${encodeURIComponent(draft.storeName || "")}&pos=${encodeURIComponent(draft.position || "")}`}
            className="inline-flex items-center justify-center px-3 py-1.5 text-xs font-medium text-text-secondary hover:text-text-primary bg-surface-muted hover:bg-surface-elevated border border-[var(--border-subtle)] rounded-lg transition-colors"
          >
            Review in Plantilla →
          </a>
        </div>
      </div>
    );
  }

  // 2. Vacancy Closure Draft
  if (output.action === "SUBMIT_VACANCY_CLOSURE" && output.draft) {
    const draft = output.draft as {
      vacancyId?: string;
      vcode: string;
      position?: string;
      storeName?: string;
      reason?: string;
    };
    const draftKey = `closure_${messageId}_${draft.vcode}`;
    const isSubmitting = Boolean(submittingDrafts[draftKey]);
    const submission = submittedDrafts[draftKey];

    if (submission?.status === "success") {
      return (
        <div className="my-2.5 p-3.5 rounded-xl border border-amber-500/40 bg-amber-500/10 space-y-2.5 transition-all">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs font-semibold text-amber-600 dark:text-amber-400">
              <CheckCircle2 className="h-4 w-4 text-amber-500" />
              <span>Vacancy Closure Request Submitted!</span>
            </div>
            <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-amber-500/20 text-amber-600 dark:text-amber-300 font-bold">
              Pending Review
            </span>
          </div>
          <div className="text-xs space-y-1 text-text-secondary">
            <p>
              • <strong>Slot Code:</strong>{" "}
              <code className="tech-token">{draft.vcode}</code>
            </p>
            <p>
              • <strong>Position:</strong> {draft.position || "—"}
            </p>
            <p>
              • <strong>Branch:</strong> {draft.storeName || "—"}
            </p>
          </div>
          <div className="pt-1 flex flex-wrap items-center gap-2">
            <a
              href="/my-requests"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-white bg-amber-600 hover:bg-amber-700 rounded-lg shadow-xs transition-colors"
            >
              <span>Track in My Requests</span>
              <ArrowRight size={13} />
            </a>
            <a
              href={`/vacancy?q=${encodeURIComponent(draft.vcode || "")}`}
              className="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-text-secondary hover:text-text-primary bg-surface-muted hover:bg-surface-elevated border border-[var(--border-subtle)] rounded-lg transition-colors"
            >
              <span>Review in Vacancy Hub</span>
            </a>
          </div>
        </div>
      );
    }

    return (
      <div className="my-2.5 p-3.5 rounded-xl border border-amber-500/30 bg-amber-500/5 space-y-2.5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs font-semibold text-amber-600 dark:text-amber-400">
            <Bot className="h-4 w-4" />
            <span>Action Ready: Vacancy Closure Draft</span>
          </div>
          <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-600 dark:text-amber-400 font-medium">
            Draft Ready
          </span>
        </div>
        <div className="text-xs space-y-1 text-text-secondary">
          <p>
            • <strong>Slot Code:</strong>{" "}
            <code className="tech-token">{draft.vcode}</code>
          </p>
          <p>
            • <strong>Position:</strong> {draft.position || "—"}
          </p>
          <p>
            • <strong>Branch:</strong> {draft.storeName || "—"}
          </p>
          <p>
            • <strong>Reason:</strong> {draft.reason || "Closure requested"}
          </p>
        </div>
        {submission?.status === "error" && (
          <div className="p-2 rounded-lg bg-danger/10 border border-danger/20 text-xs text-danger flex items-start gap-1.5">
            <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <span>{submission.error}</span>
          </div>
        )}
        <div className="pt-1 flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => onConfirmVacancyClosure(draftKey, draft)}
            disabled={isSubmitting}
            className="inline-flex items-center justify-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-white bg-amber-600 hover:bg-amber-700 disabled:opacity-50 rounded-lg shadow-xs transition-colors cursor-pointer"
          >
            {isSubmitting ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                <span>Submitting...</span>
              </>
            ) : (
              <>
                <Check className="h-3.5 w-3.5" />
                <span>Confirm &amp; Submit</span>
              </>
            )}
          </button>
          <a
            href={`/vacancy?q=${encodeURIComponent(draft.vcode || "")}`}
            className="inline-flex items-center justify-center px-3 py-1.5 text-xs font-medium text-text-secondary hover:text-text-primary bg-surface-muted hover:bg-surface-elevated border border-[var(--border-subtle)] rounded-lg transition-colors"
          >
            Review in Vacancy Hub →
          </a>
        </div>
      </div>
    );
  }

  return null;
}

// ── Route & Context Starter Prompts ──────────────────────────────────────────

interface ContextParams {
  storeName?: string;
  accountName?: string;
  vcode?: string;
}

function getStarterPrompts(pathname: string, context?: ContextParams): string[] {
  const common = ["📋 Today's Operational Briefing"];
  const dynamicStarters: string[] = [];

  if (context?.storeName) {
    dynamicStarters.push(`Kumusta ang staffing sa ${context.storeName}?`);
    dynamicStarters.push(`Sino-sino ang nakaduty sa ${context.storeName}?`);
  }
  if (context?.vcode) {
    dynamicStarters.push(`I-check ang details at occupant ng ${context.vcode}`);
    dynamicStarters.push(`Ano ang audit history ng ${context.vcode}?`);
  }
  if (context?.accountName && !context?.storeName) {
    dynamicStarters.push(`Summarize headcount and vacancies for ${context.accountName}`);
  }

  if (pathname.includes("/plantilla")) {
    return [
      ...common,
      ...dynamicStarters,
      "Summarize Plantilla fill-rate and vacant slots by branch",
      "Sino-sino ang nakaduty sa branch na ito?",
      "Draft a headcount request for Cashier",
      "How do I bulk-import or Sync MIKA in Plantilla?",
    ];
  }
  if (pathname.includes("/vacancy")) {
    return [
      ...common,
      ...dynamicStarters,
      "Show vacancies open for more than 30 days (SLA breach)",
      "I-check ang history ng slot na ito",
      "Count open vacancies grouped by branch",
      "Draft closure request for a vacancy",
    ];
  }
  if (pathname.includes("/hr-emploc")) {
    return [
      ...common,
      ...dynamicStarters,
      "Show pending movements stuck in hr_emploc_queue",
      "Check queue status for a specific employee",
    ];
  }
  return [
    ...common,
    ...dynamicStarters,
    "Show accounts ranked by lowest fill rate (MFR)",
    "Show vacancies open for more than 30 days (SLA breach)",
    "Draft a headcount request",
  ];
}

// ── Main OHMni Centered Floating Card ───────────────────────────────────────

export function OhmniDrawer({ isOpen, onClose, currentUser }: OhmniDrawerProps) {
  const queryClient = useQueryClient();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [input, setInput] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // In-flight and completed interactive action draft states (Phase 2 Layer 2)
  const [submittingDrafts, setSubmittingDrafts] = useState<Record<string, boolean>>({});
  const [submittedDrafts, setSubmittedDrafts] = useState<
    Record<
      string,
      {
        status: "success" | "error";
        requestId?: string;
        vcode?: string;
        error?: string;
      }
    >
  >({});

  const handleConfirmHeadcount = useCallback(
    async (
      draftKey: string,
      draft: {
        storeId?: string | null;
        storeName?: string;
        accountId?: string | null;
        accountName?: string;
        positionId?: string | null;
        position?: string;
        headcountNeeded?: number;
        reason?: string;
      }
    ) => {
      setSubmittingDrafts((prev) => ({ ...prev, [draftKey]: true }));
      try {
        const supabase = createClient();
        let storeId = draft.storeId || null;
        let accountId = draft.accountId || null;
        let positionId = draft.positionId || null;
        const storeName = draft.storeName || "Unassigned Store";
        const positionName = draft.position || "Staff";

        // Resolve store and account if missing
        if (!storeId || !accountId) {
          const { data: storeRows } = await supabase
            .from("stores")
            .select("id, store_name, account_id, accounts(id, account_name)")
            .ilike("store_name", `%${storeName.replace(/[%_]/g, "")}%`)
            .limit(1);

          if (storeRows && storeRows.length > 0) {
            storeId = storeRows[0].id;
            accountId = storeRows[0].account_id;
          }
        }

        if (!accountId) {
          const { data: accRows } = await supabase
            .from("accounts")
            .select("id")
            .limit(1);
          if (accRows && accRows.length > 0) {
            accountId = accRows[0].id;
          }
        }

        // Resolve position if missing
        if (!positionId) {
          const { data: posRows } = await supabase
            .from("positions")
            .select("id, position_name")
            .ilike("position_name", `%${positionName.replace(/[%_]/g, "")}%`)
            .limit(1);

          if (posRows && posRows.length > 0) {
            positionId = posRows[0].id;
          } else {
            const { data: defPos } = await supabase
              .from("positions")
              .select("id, position_name")
              .eq("is_active", true)
              .limit(1);
            if (defPos && defPos.length > 0) {
              positionId = defPos[0].id;
            }
          }
        }

        if (!accountId || !positionId) {
          throw new Error(
            "Could not resolve account or position. Please review and submit via Plantilla."
          );
        }

        const res = await submitHeadcountRequest({
          account_id: accountId,
          account_name: draft.accountName,
          store_id: storeId,
          store_name: storeName,
          position_id: positionId,
          position_name: positionName,
          workforce_type: "stationary",
          employment_type: "Stationary",
          request_type: "Additional Headcount",
          headcount_needed: draft.headcountNeeded ?? 1,
          reason: draft.reason ?? "Operational demand",
          urgency: "Medium",
        });

        queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
        queryClient.invalidateQueries({ queryKey: ["my-requests"] });
        queryClient.invalidateQueries({ queryKey: ["headcount-requests"] });
        queryClient.invalidateQueries({ queryKey: ["pending-headcount-requests"] });
        queryClient.invalidateQueries({ queryKey: ["plantilla"] });
        queryClient.invalidateQueries({ queryKey: ["vacancies"] });

        setSubmittedDrafts((prev) => ({
          ...prev,
          [draftKey]: {
            status: "success",
            requestId: res.request_id,
          },
        }));
      } catch (err) {
        setSubmittedDrafts((prev) => ({
          ...prev,
          [draftKey]: {
            status: "error",
            error:
              err instanceof Error
                ? err.message
                : "Failed to submit headcount request",
          },
        }));
      } finally {
        setSubmittingDrafts((prev) => ({ ...prev, [draftKey]: false }));
      }
    },
    [queryClient]
  );

  const handleConfirmVacancyClosure = useCallback(
    async (
      draftKey: string,
      draft: {
        vacancyId?: string;
        vcode: string;
        position?: string;
        storeName?: string;
        reason?: string;
      }
    ) => {
      setSubmittingDrafts((prev) => ({ ...prev, [draftKey]: true }));
      try {
        const supabase = createClient();
        let userName = currentUser?.displayName;
        let userRole = currentUser?.roleName || "Ops";
        let userId = currentUser?.profileId;

        if (!userId || !userName) {
          const { data: authData } = await supabase.auth.getUser();
          if (authData?.user) {
            const { data: prof } = await supabase
              .from("users_profile")
              .select("id, full_name, role_name")
              .eq("auth_user_id", authData.user.id)
              .maybeSingle();
            if (prof) {
              userId = prof.id;
              userName = prof.full_name || userName;
              userRole = prof.role_name || userRole;
            }
          }
        }

        await requestVacancyClosure({
          vcode: draft.vcode,
          reason: draft.reason ?? "Position no longer required",
          details: "Submitted via OHMni AI Co-Pilot action card",
          requestedBy: userName || "Authorized User",
          requestedByRole: userRole || "Ops",
          requestedByUserId: userId || null,
        });

        queryClient.invalidateQueries({ queryKey: ["request-category-counts"] });
        queryClient.invalidateQueries({ queryKey: ["my-requests"] });
        queryClient.invalidateQueries({ queryKey: ["vacancy-closure-requests"] });
        queryClient.invalidateQueries({ queryKey: ["pending-vacancy-closure-requests"] });
        queryClient.invalidateQueries({ queryKey: ["vacancies"] });
        queryClient.invalidateQueries({ queryKey: ["plantilla"] });

        setSubmittedDrafts((prev) => ({
          ...prev,
          [draftKey]: {
            status: "success",
            vcode: draft.vcode,
          },
        }));
      } catch (err) {
        setSubmittedDrafts((prev) => ({
          ...prev,
          [draftKey]: {
            status: "error",
            error:
              err instanceof Error
                ? err.message
                : "Failed to submit vacancy closure request",
          },
        }));
      } finally {
        setSubmittingDrafts((prev) => ({ ...prev, [draftKey]: false }));
      }
    },
    [currentUser, queryClient]
  );

  const storeName = useMemo(
    () =>
      searchParams?.get("store") ||
      searchParams?.get("store_name") ||
      searchParams?.get("branch") ||
      "",
    [searchParams]
  );
  const accountName = useMemo(
    () =>
      searchParams?.get("account") ||
      searchParams?.get("account_name") ||
      "",
    [searchParams]
  );
  const vcode = useMemo(
    () =>
      searchParams?.get("vcode") ||
      searchParams?.get("q") ||
      "",
    [searchParams]
  );

  const activeContext = useMemo(
    () => ({
      route: pathname,
      storeName: storeName || undefined,
      accountName: accountName || undefined,
      vcode: vcode || undefined,
    }),
    [pathname, storeName, accountName, vcode]
  );

  // Authorization token forwarding & route context
  const transport = useMemo(
    () =>
      new DefaultChatTransport({
        api: "/api/ohmni",
        body: {
          activeContext,
        },
        headers: async (): Promise<Record<string, string>> => {
          const supabase = createClient();
          const { data } = await supabase.auth.getSession();
          const token = data?.session?.access_token;
          const reqHeaders: Record<string, string> = {};
          if (token) {
            reqHeaders["Authorization"] = `Bearer ${token}`;
          }
          return reqHeaders;
        },
      }),
    [activeContext]
  );

  const {
    messages,
    sendMessage,
    status,
    setMessages,
    stop,
    error,
  } = useChat({
    transport,
  });

  const isLoading = status === "submitted" || status === "streaming";

  // Auto-scroll on new messages
  useEffect(() => {
    if (isOpen) {
      messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, isOpen]);

  // Focus input when opened
  useEffect(() => {
    if (isOpen) {
      textareaRef.current?.focus();
    }
  }, [isOpen]);

  // Close on Escape key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isOpen) {
        onClose();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onClose]);

  const handleSend = useCallback(
    async (textToSend?: string) => {
      const trimmed = (textToSend ?? input).trim();
      if (!trimmed || isLoading) return;
      if (!textToSend) setInput("");

      try {
        await sendMessage({ text: trimmed });
      } catch (err) {
        console.error("[ohmni] Failed to send message:", err);
      }
    },
    [input, isLoading, sendMessage]
  );

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleReset = () => {
    if (isLoading) {
      stop();
    }
    setMessages([]);
    setSubmittingDrafts({});
    setSubmittedDrafts({});
  };

  const starters = useMemo(
    () => getStarterPrompts(pathname, activeContext),
    [pathname, activeContext]
  );

  if (!isOpen) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="OHMni Chat Overlay"
      onClick={(e) => {
        // Close if clicking directly on outer backdrop
        if (e.target === e.currentTarget) {
          onClose();
        }
      }}
      className="fixed inset-0 lg:left-[var(--sidebar-width)] z-50 bg-[var(--surface-overlay)] backdrop-blur-[2px] flex items-center justify-center p-3 sm:p-5 transition-opacity duration-200"
    >
      {/* ── Antigravity Centered Floating Card ───────────────────────────────────── */}
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-[680px] h-[calc(100vh-48px)] max-h-[780px] bg-[var(--surface-card)] rounded-3xl shadow-2xl border border-[var(--border-subtle)] flex flex-col overflow-hidden mx-auto my-auto animate-in fade-in zoom-in-95 duration-200"
      >
        {/* ── 1. Top Header ──────────────────────────────────────────────── */}
        <header className="flex items-center justify-between px-5 py-3.5 border-b border-[var(--border-subtle)] bg-[var(--surface-card)] shrink-0">
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={onClose}
              title="Close chat"
              aria-label="Close"
              className="w-8 h-8 rounded-full bg-surface-muted hover:bg-surface-hover flex items-center justify-center text-text-secondary transition-colors cursor-pointer"
            >
              <ChevronLeft size={18} />
            </button>
            <div>
              <div className="flex items-center gap-2">
                <span className="text-lg font-bold text-text-primary">Chat</span>
                <span
                  className={`text-[10px] font-semibold px-2 py-0.5 rounded-full flex items-center gap-1 transition-colors ${
                    isLoading
                      ? "bg-amber-500/10 text-amber-400 border border-amber-500/20 animate-pulse"
                      : "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
                  }`}
                >
                  {isLoading ? "⏳ SYNCING" : "⚡ LIVE"}
                </span>
              </div>
              <p className="text-xs text-text-muted leading-tight">
                Ask questions about slots, vacancies, or HR queues in plain language.
              </p>
            </div>
          </div>

          <div className="flex items-center gap-1.5">
            <button
              type="button"
              onClick={handleReset}
              title="Reset conversation"
              aria-label="Reset chat"
              className="w-8 h-8 rounded-full bg-surface-muted hover:bg-surface-hover flex items-center justify-center text-text-secondary transition-colors cursor-pointer"
            >
              <RotateCcw size={14} />
            </button>
          </div>
        </header>

        {/* ── 2. Active Message Stream & Welcome View ──────────────────────── */}
        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-5">
          {/* Welcome / Greeting Message */}
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center justify-center shrink-0 shadow-2xs">
              <Bot size={18} />
            </div>
            <div className="flex-1 space-y-1.5">
              <div className="font-semibold text-text-primary text-sm">OHMni</div>
              <div className="text-sm text-text-secondary space-y-1.5 leading-relaxed bg-surface-muted p-3.5 rounded-2xl border border-[var(--border-subtle)]">
                <p className="font-bold text-text-primary">Hi OHM!</p>
                <p>
                  Ask me about your Plantilla slots, open vacancies, headcount requests, or HR
                  Emploc queues.
                </p>
                {(activeContext.storeName || activeContext.accountName || activeContext.vcode) && (
                  <div className="flex items-center gap-1.5 py-1 px-2.5 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-600 dark:text-emerald-400 text-xs font-medium">
                    <span className="text-[11px]">📍</span>
                    <span className="truncate">
                      Context: {activeContext.storeName ? `Store: ${activeContext.storeName}` : ""}{activeContext.storeName && activeContext.accountName ? " • " : ""}{activeContext.accountName ? `Account: ${activeContext.accountName}` : ""}{activeContext.vcode ? `Slot: ${activeContext.vcode}` : ""}
                    </span>
                  </div>
                )}
                <p className="text-text-muted text-xs">
                  You can also ask step-by-step how-to questions anytime.
                </p>
              </div>

              {/* Starter pills (when session has no user messages) */}
              {messages.length === 0 && (
                <div className="pt-2 space-y-1.5">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-text-muted block px-1">
                    Suggested prompts
                  </span>
                  <div className="flex flex-col gap-1.5">
                    {starters.map((promptText, i) => (
                      <button
                        key={i}
                        type="button"
                        onClick={() => handleSend(promptText)}
                        className="text-left rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-base)] px-3.5 py-2 text-xs text-text-secondary shadow-2xs hover:border-emerald-500/50 hover:bg-surface-hover transition-all cursor-pointer flex items-center gap-2 group"
                      >
                        <span className="text-emerald-500 font-mono text-[11px] font-bold group-hover:translate-x-0.5 transition-transform">
                          →
                        </span>
                        <span className="leading-snug">{promptText}</span>
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Active Conversation Messages */}
          {messages.map((m: UIMessage) => {
            const isUser = m.role === "user";

            // Extract parts
            const textParts = m.parts.filter(
              (p): p is { type: "text"; text: string } =>
                p.type === "text" && typeof p.text === "string"
            );
            const toolParts = m.parts.filter((p) =>
              p.type.startsWith("tool-") || p.type === "dynamic-tool"
            );
            const actionParts = toolParts.filter(isActionDraftTool);
            const nonActionToolParts = toolParts.filter(
              (tp) => !isActionDraftTool(tp)
            );

            const hasNonEmptyText = textParts.some((t) => t.text.trim().length > 0);

            return (
              <div
                key={m.id}
                className={`flex flex-col ${isUser ? "items-end" : "items-start"}`}
              >
                {isUser ? (
                  /* User Bubble */
                  <div className="bg-brand-button text-white dark:bg-[#18181B] dark:text-[#F4F4F5] dark:border dark:border-[#27272A] text-sm px-4 py-2.5 rounded-2xl max-w-[80%] shadow-2xs break-words whitespace-pre-wrap leading-relaxed">
                    {textParts.map((t) => t.text).join("")}
                  </div>
                ) : (
                  /* OHMni Assistant Message */
                  <div className="flex items-start gap-3 max-w-[94%] w-full">
                    <div className="w-8 h-8 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center justify-center shrink-0 shadow-2xs mt-1">
                      <Bot size={18} />
                    </div>
                    <div className="flex-1 space-y-2">
                      <div className="font-semibold text-text-primary text-sm">OHMni</div>

                      {/* Assistant Reply Content */}
                      <div className="text-sm text-text-secondary leading-relaxed bg-[var(--surface-base)] p-3.5 rounded-2xl border border-[var(--border-subtle)] shadow-2xs w-full space-y-2">
                        {hasNonEmptyText &&
                          textParts.map((t, idx) => (
                            <FormattedContent key={idx} content={t.text} />
                          ))}

                        {/* Interactive Action Draft Cards (Phase 2 Layer 2) */}
                        {actionParts.map((tp, idx) => (
                          <ActionDraftCard
                            key={idx}
                            messageId={m.id}
                            toolPart={tp}
                            submittingDrafts={submittingDrafts}
                            submittedDrafts={submittedDrafts}
                            onConfirmHeadcount={handleConfirmHeadcount}
                            onConfirmVacancyClosure={handleConfirmVacancyClosure}
                          />
                        ))}

                        {/* Fallback: stream finished with completed query tools but 0 text parts */}
                        {!hasNonEmptyText &&
                          !isLoading &&
                          nonActionToolParts.length > 0 && (
                            <ToolOutputFallbackView
                              toolParts={nonActionToolParts}
                            />
                          )}

                        {/* Loading State while stream is in flight */}
                        {!hasNonEmptyText && isLoading && (
                          <div className="flex items-center gap-2 text-text-muted py-1">
                            <Loader2
                              size={14}
                              className="animate-spin text-emerald-500"
                            />
                            <span className="text-xs italic text-text-muted">
                              Thinking.....
                            </span>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })}

          {/* Pending Thinking bubble while waiting for initial stream response */}
          {isLoading && messages[messages.length - 1]?.role === "user" && (
            <div className="flex items-start gap-3 max-w-[94%] w-full animate-in fade-in duration-150">
              <div className="w-8 h-8 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center justify-center shrink-0 shadow-2xs mt-1">
                <Bot size={18} />
              </div>
              <div className="flex-1 space-y-2">
                <div className="font-semibold text-text-primary text-sm">OHMni</div>
                <div className="text-sm text-text-secondary leading-relaxed bg-[var(--surface-base)] p-3.5 rounded-2xl border border-[var(--border-subtle)] shadow-2xs w-full">
                  <div className="flex items-center gap-2 text-text-muted py-1">
                    <Loader2 size={14} className="animate-spin text-emerald-500" />
                    <span className="text-xs italic text-text-muted">
                      Thinking.....
                    </span>
                  </div>
                </div>
              </div>
            </div>
          )}

          {error && (
            <div className="rounded-2xl border border-rose-500/20 bg-rose-500/10 p-3 text-xs text-rose-400">
              <strong>Error:</strong> {error.message || "Failed to process query."}
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* ── 3. Bottom Composer Box (Antigravity Style) ─────────────────────────── */}
        <div className="px-6 pb-2">
          <div className="p-3 rounded-2xl border border-[var(--border-default)] bg-[var(--surface-base)] shadow-sm focus-within:border-border-strong transition-all">
            <textarea
              ref={textareaRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder='Ask a question or type "Show open vacancies in SM North"...'
              rows={2}
              maxLength={1000}
              disabled={isLoading}
              className="text-sm placeholder:text-text-muted border-0 focus:ring-0 focus:outline-none w-full resize-none text-text-primary disabled:bg-transparent disabled:opacity-60 bg-transparent"
            />
            <div className="flex items-center justify-between pt-2 border-t border-[var(--border-subtle)]">
              <div className="text-[10px] text-text-muted">
                {input.length > 800 && (
                  <span className={input.length >= 1000 ? "text-danger font-semibold" : ""}>
                    {input.length}/1000
                  </span>
                )}
              </div>
              <button
                type="button"
                onClick={() => handleSend()}
                disabled={isLoading || !input.trim()}
                title="Send query"
                aria-label="Send message"
                className="w-8 h-8 rounded-full bg-surface-muted hover:bg-surface-hover text-text-primary flex items-center justify-center transition-colors disabled:opacity-40 cursor-pointer"
              >
                {isLoading ? (
                  <Loader2 size={14} className="animate-spin text-emerald-500" />
                ) : (
                  <ArrowUp size={16} />
                )}
              </button>
            </div>
          </div>
        </div>

        {/* ── 4. Footer Micro-Caption ─────────────────────────────────────── */}
        <div className="text-[11px] text-text-muted pb-3 text-center">
          OHMni can make mistakes. Review important details.
        </div>
      </div>
    </div>
  );
}
