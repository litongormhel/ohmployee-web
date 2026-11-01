"use client";

import React, { useState, useMemo, useRef, useEffect, useCallback } from "react";
import { usePathname } from "next/navigation";
import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { createClient } from "@/lib/supabase/client";
import {
  RotateCcw,
  ChevronLeft,
  ArrowUp,
  CheckCircle2,
  Loader2,
  Bot,
} from "lucide-react";

type OhmniDrawerProps = {
  isOpen: boolean;
  onClose: () => void;
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
            className="px-1.5 py-0.5 mx-0.5 bg-slate-100 text-slate-800 rounded font-mono text-[11px] border border-slate-200"
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
            <strong key={`b-${keyIdx++}`} className="font-semibold text-slate-900">
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
          className="my-3 overflow-x-auto rounded-xl border border-slate-200/90 shadow-2xs"
        >
          <table className="min-w-full divide-y divide-slate-200 text-left text-xs">
            <thead className="bg-slate-50 font-semibold text-slate-700">
              <tr>
                {header.map((col, cIdx) => (
                  <th key={`th-${cIdx}`} className="px-3 py-2 whitespace-nowrap">
                    {col}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 bg-white">
              {dataRows.map((r, rIdx) => (
                <tr key={`tr-${rIdx}`} className="hover:bg-slate-50/80 transition-colors">
                  {r.map((col, cIdx) => (
                    <td key={`td-${cIdx}`} className="px-3 py-2 whitespace-nowrap text-slate-700">
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
          <span className="flex-1 leading-relaxed text-sm text-slate-800">
            {renderInlineFormatted(trimmed.slice(2))}
          </span>
        </div>
      );
      return;
    }

    renderedElements.push(
      <p key={`p-${idx}`} className="leading-relaxed my-1.5 text-sm text-slate-800">
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

function ToolOutputFallbackView({
  toolName,
  output,
}: {
  toolName: string;
  output: GenericToolOutput;
}) {
  if (!output || typeof output !== "object") return null;

  if (output.error) {
    return (
      <div className="rounded-xl border border-rose-200 bg-rose-50 p-3 text-xs text-rose-700">
        <p className="font-semibold">Query encountered an error:</p>
        <p className="mt-0.5">{String(output.error)}</p>
      </div>
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
    return (
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold text-slate-700">
            Open Vacancies Found ({slots.length})
          </span>
          <span className="text-[11px] font-medium text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
            Verified Supabase Live
          </span>
        </div>
        {slots.length === 0 ? (
          <p className="text-xs text-slate-500 italic">No open vacancies matching query.</p>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-slate-200/90 shadow-2xs">
            <table className="min-w-full divide-y divide-slate-200 text-left text-xs">
              <thead className="bg-slate-50 font-semibold text-slate-700">
                <tr>
                  <th className="px-3 py-2">Slot Code</th>
                  <th className="px-3 py-2">Position</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Type</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 bg-white">
                {slots.map((s, idx) => (
                  <tr key={idx} className="hover:bg-slate-50/80 transition-colors">
                    <td className="px-3 py-2 font-mono text-[11px] font-medium text-slate-900">
                      {s.slotCode || "—"}
                    </td>
                    <td className="px-3 py-2 text-slate-800">{s.position || "—"}</td>
                    <td className="px-3 py-2">
                      <span className="px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700 text-[10px] font-semibold">
                        {s.status || "Vacant"}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-slate-500">{s.employmentType || "Regular"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    );
  }

  // Handle getPlantillaSummary
  if (output.totalFound !== undefined || output.fillRatePercent !== undefined) {
    const sampleRows = Array.isArray(output.sampleRows)
      ? (output.sampleRows as Array<{
          slotCode?: string;
          position?: string;
          status?: string;
          employmentType?: string;
        }>)
      : [];

    return (
      <div className="space-y-3">
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <div className="p-2.5 rounded-xl bg-slate-50 border border-slate-200/80">
            <div className="text-[10px] uppercase font-bold text-slate-400">Total Slots</div>
            <div className="text-base font-bold text-slate-900">{String(output.totalFound ?? 0)}</div>
          </div>
          <div className="p-2.5 rounded-xl bg-slate-50 border border-slate-200/80">
            <div className="text-[10px] uppercase font-bold text-slate-400">Filled</div>
            <div className="text-base font-bold text-emerald-600">{String(output.filledCount ?? 0)}</div>
          </div>
          <div className="p-2.5 rounded-xl bg-slate-50 border border-slate-200/80">
            <div className="text-[10px] uppercase font-bold text-slate-400">Vacant</div>
            <div className="text-base font-bold text-amber-600">{String(output.vacantCount ?? 0)}</div>
          </div>
          <div className="p-2.5 rounded-xl bg-slate-50 border border-slate-200/80">
            <div className="text-[10px] uppercase font-bold text-slate-400">Fill Rate</div>
            <div className="text-base font-bold text-brand-600">{String(output.fillRatePercent ?? "0%")}</div>
          </div>
        </div>

        {sampleRows.length > 0 && (
          <div className="overflow-x-auto rounded-xl border border-slate-200/90 shadow-2xs">
            <table className="min-w-full divide-y divide-slate-200 text-left text-xs">
              <thead className="bg-slate-50 font-semibold text-slate-700">
                <tr>
                  <th className="px-3 py-2">Slot Code</th>
                  <th className="px-3 py-2">Position</th>
                  <th className="px-3 py-2">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 bg-white">
                {sampleRows.slice(0, 10).map((r, idx) => (
                  <tr key={idx} className="hover:bg-slate-50/80">
                    <td className="px-3 py-2 font-mono text-[11px] font-medium text-slate-900">
                      {r.slotCode || "—"}
                    </td>
                    <td className="px-3 py-2 text-slate-800">{r.position || "—"}</td>
                    <td className="px-3 py-2">
                      <span
                        className={`px-1.5 py-0.5 rounded text-[10px] font-semibold ${
                          (r.status || "").toLowerCase() === "filled"
                            ? "bg-slate-100 text-slate-700"
                            : "bg-emerald-50 text-emerald-700"
                        }`}
                      >
                        {r.status || "Unknown"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
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
    return (
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold text-slate-700">
            HR Emploc Queue ({items.length} items)
          </span>
          <span className="text-[11px] font-medium text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
            Live Queue Snapshot
          </span>
        </div>
        {items.length === 0 ? (
          <p className="text-xs text-slate-500 italic">No queue items matching filter.</p>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-slate-200/90 shadow-2xs">
            <table className="min-w-full divide-y divide-slate-200 text-left text-xs">
              <thead className="bg-slate-50 font-semibold text-slate-700">
                <tr>
                  <th className="px-3 py-2">Applicant / Employee</th>
                  <th className="px-3 py-2">Target Slot</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">HR Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 bg-white">
                {items.slice(0, 10).map((it, idx) => (
                  <tr key={idx} className="hover:bg-slate-50/80">
                    <td className="px-3 py-2 font-medium text-slate-900">
                      {it.employee} <span className="text-slate-400 font-normal">({it.employeeNo || "—"})</span>
                    </td>
                    <td className="px-3 py-2 font-mono text-[11px] text-slate-700">{it.targetSlot || "—"}</td>
                    <td className="px-3 py-2 text-slate-700">{it.status || "—"}</td>
                    <td className="px-3 py-2">
                      <span className="px-1.5 py-0.5 rounded bg-blue-50 text-blue-700 text-[10px] font-semibold">
                        {it.hrStatus || "Pending"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
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
      urgency?: string;
    }>;
    return (
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold text-slate-700">
            Headcount Requests ({requests.length})
          </span>
          <span className="text-[11px] font-medium text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
            Live Requests
          </span>
        </div>
        {requests.length === 0 ? (
          <p className="text-xs text-slate-500 italic">No headcount requests found.</p>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-slate-200/90 shadow-2xs">
            <table className="min-w-full divide-y divide-slate-200 text-left text-xs">
              <thead className="bg-slate-50 font-semibold text-slate-700">
                <tr>
                  <th className="px-3 py-2">Position</th>
                  <th className="px-3 py-2">Store</th>
                  <th className="px-3 py-2">Needed</th>
                  <th className="px-3 py-2">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 bg-white">
                {requests.slice(0, 10).map((r, idx) => (
                  <tr key={idx} className="hover:bg-slate-50/80">
                    <td className="px-3 py-2 font-medium text-slate-900">{r.position || "—"}</td>
                    <td className="px-3 py-2 text-slate-700">{r.store || "—"}</td>
                    <td className="px-3 py-2 text-slate-900 font-semibold">{r.headcountNeeded ?? 1}</td>
                    <td className="px-3 py-2">
                      <span className="px-1.5 py-0.5 rounded bg-amber-50 text-amber-700 text-[10px] font-semibold">
                        {r.status || "Pending"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    );
  }

  // Generic JSON view fallback
  return (
    <div className="rounded-xl border border-slate-200 bg-slate-50 p-3 text-xs">
      <div className="font-semibold text-slate-700 mb-1.5">
        Tool Results ({toolName}):
      </div>
      <pre className="text-[11px] font-mono text-slate-600 overflow-x-auto whitespace-pre-wrap">
        {JSON.stringify(output, null, 2)}
      </pre>
    </div>
  );
}

// ── Route Starter Prompts ───────────────────────────────────────────────────

function getStarterPrompts(pathname: string): string[] {
  if (pathname.includes("/plantilla")) {
    return [
      "Summarize Plantilla fill-rate and vacant slots by branch",
      "Check details for a specific slot in plantilla_slots",
      "How do I bulk-import or Sync MIKA in Plantilla?",
    ];
  }
  if (pathname.includes("/vacancy")) {
    return [
      "Count all open vacancies grouped by position or branch",
      "List pending Headcount Requests older than 7 days",
      "How do I file a new Headcount Request?",
    ];
  }
  if (pathname.includes("/hr-emploc")) {
    return [
      "Show pending movements stuck in hr_emploc_queue",
      "Check queue status for a specific employee or branch",
      "How do I resolve web vs. mobile HR Emploc discrepancies?",
    ];
  }
  return [
    "Give me an executive snapshot of Plantilla fill rate and open slots",
    "How many pending items are in the HR Emploc queue?",
    "Show pending Headcount Requests across branches",
  ];
}

// ── Main OHMni Centered Floating Card ───────────────────────────────────────

export function OhmniDrawer({ isOpen, onClose }: OhmniDrawerProps) {
  const pathname = usePathname();
  const [input, setInput] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Authorization token forwarding
  const transport = useMemo(
    () =>
      new DefaultChatTransport({
        api: "/api/ohmni",
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
    []
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
  };

  const starters = useMemo(() => getStarterPrompts(pathname), [pathname]);

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
      className="fixed inset-0 lg:left-[var(--sidebar-width)] z-50 bg-slate-900/10 backdrop-blur-[2px] flex items-center justify-center p-3 sm:p-5 transition-opacity duration-200"
    >
      {/* ── Tarsi Centered Floating Card ───────────────────────────────────── */}
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-[680px] h-[calc(100vh-48px)] max-h-[780px] bg-white rounded-3xl shadow-2xl border border-slate-200/80 flex flex-col overflow-hidden mx-auto my-auto animate-in fade-in zoom-in-95 duration-200"
      >
        {/* ── 1. Top Header ──────────────────────────────────────────────── */}
        <header className="flex items-center justify-between px-5 py-3.5 border-b border-slate-100 bg-white shrink-0">
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={onClose}
              title="Close chat"
              aria-label="Close"
              className="w-8 h-8 rounded-full bg-slate-100 hover:bg-slate-200 flex items-center justify-center text-slate-700 transition-colors cursor-pointer"
            >
              <ChevronLeft size={18} />
            </button>
            <div>
              <div className="flex items-center gap-2">
                <span className="text-lg font-bold text-slate-900">Chat</span>
                <span
                  className={`text-[10px] font-semibold px-2 py-0.5 rounded-full flex items-center gap-1 transition-colors ${
                    isLoading
                      ? "bg-amber-50 text-amber-700 animate-pulse border border-amber-200"
                      : "bg-emerald-50 text-emerald-700 border border-emerald-200"
                  }`}
                >
                  {isLoading ? "⏳ SYNCING" : "⚡ LIVE"}
                </span>
              </div>
              <p className="text-xs text-slate-500 leading-tight">
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
              className="w-8 h-8 rounded-full bg-slate-100 hover:bg-slate-200 flex items-center justify-center text-slate-600 transition-colors cursor-pointer"
            >
              <RotateCcw size={14} />
            </button>
          </div>
        </header>

        {/* ── 2. Active Message Stream & Welcome View ──────────────────────── */}
        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-5">
          {/* Welcome / Greeting Message */}
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 rounded-full bg-emerald-100 text-emerald-700 flex items-center justify-center shrink-0 shadow-2xs">
              <Bot size={18} />
            </div>
            <div className="flex-1 space-y-1.5">
              <div className="font-semibold text-slate-900 text-sm">OHMni</div>
              <div className="text-sm text-slate-800 space-y-1.5 leading-relaxed bg-slate-50/70 p-3.5 rounded-2xl border border-slate-200/60">
                <p className="font-bold text-slate-900">Hi OHM!</p>
                <p>
                  Ask me about your Plantilla slots, open vacancies, headcount requests, or HR
                  Emploc queues.
                </p>
                <p className="text-slate-600 text-xs">
                  You can also ask step-by-step how-to questions anytime.
                </p>
              </div>

              {/* Starter pills (when session has no user messages) */}
              {messages.length === 0 && (
                <div className="pt-2 space-y-1.5">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400 block px-1">
                    Suggested prompts
                  </span>
                  <div className="flex flex-col gap-1.5">
                    {starters.map((promptText, i) => (
                      <button
                        key={i}
                        type="button"
                        onClick={() => handleSend(promptText)}
                        className="text-left rounded-xl border border-slate-200/90 bg-white px-3.5 py-2 text-xs text-slate-700 shadow-2xs hover:border-emerald-500 hover:bg-emerald-50/30 transition-all cursor-pointer flex items-center gap-2 group"
                      >
                        <span className="text-emerald-600 font-mono text-[11px] font-bold group-hover:translate-x-0.5 transition-transform">
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

            const hasNonEmptyText = textParts.some((t) => t.text.trim().length > 0);

            return (
              <div
                key={m.id}
                className={`flex flex-col ${isUser ? "items-end" : "items-start"}`}
              >
                {isUser ? (
                  /* User Bubble */
                  <div className="bg-slate-900 text-white text-sm px-4 py-2.5 rounded-2xl max-w-[80%] shadow-2xs break-words whitespace-pre-wrap leading-relaxed">
                    {textParts.map((t) => t.text).join("")}
                  </div>
                ) : (
                  /* OHMni Assistant Message */
                  <div className="flex items-start gap-3 max-w-[94%] w-full">
                    <div className="w-8 h-8 rounded-full bg-emerald-100 text-emerald-700 flex items-center justify-center shrink-0 shadow-2xs mt-1">
                      <Bot size={18} />
                    </div>
                    <div className="flex-1 space-y-2">
                      <div className="font-semibold text-slate-900 text-sm">OHMni</div>

                      {/* Tool Execution Trust Indicators */}
                      {toolParts.length > 0 && (
                        <div className="flex flex-wrap gap-1.5">
                          {toolParts.map((tp, idx) => {
                            const rawToolName = tp.type.replace(/^tool-/, "");
                            const isDone =
                              "state" in tp &&
                              (tp.state === "output-available" ||
                                (tp as GenericToolOutput).output !== undefined ||
                                (tp as GenericToolOutput).result !== undefined);
                            const isCalling =
                              "state" in tp &&
                              (tp.state === "input-streaming" || tp.state === "input-available");

                            return (
                              <div
                                key={`tool-badge-${idx}`}
                                className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-medium border ${
                                  isDone
                                    ? "bg-emerald-50 text-emerald-800 border-emerald-200"
                                    : isCalling
                                    ? "bg-amber-50 text-amber-800 border-amber-200 animate-pulse"
                                    : "bg-slate-100 text-slate-700 border-slate-200"
                                }`}
                              >
                                {isDone ? (
                                  <>
                                    <CheckCircle2 size={11} className="text-emerald-600" />
                                    <span>⚡ Verified Live Data • {rawToolName}</span>
                                  </>
                                ) : (
                                  <>
                                    <Loader2 size={11} className="animate-spin text-amber-600" />
                                    <span>⏳ Querying live Supabase data ({rawToolName})...</span>
                                  </>
                                )}
                              </div>
                            );
                          })}
                        </div>
                      )}

                      {/* Assistant Reply Content */}
                      <div className="text-sm text-slate-800 leading-relaxed bg-white p-3.5 rounded-2xl border border-slate-200/80 shadow-2xs w-full">
                        {hasNonEmptyText ? (
                          textParts.map((t, idx) => (
                            <FormattedContent key={idx} content={t.text} />
                          ))
                        ) : isLoading ? (
                          /* Loading State while stream is in flight */
                          <div className="flex items-center gap-2 text-slate-400 py-1">
                            <Loader2 size={14} className="animate-spin text-emerald-600" />
                            <span className="text-xs italic text-slate-500">
                              Analyzing operations data...
                            </span>
                          </div>
                        ) : toolParts.length > 0 ? (
                          /* Critical Tool Output Fallback: stream finished with completed tools but 0 text parts */
                          <div className="space-y-3">
                            {toolParts.map((tp, idx) => {
                              const rawToolName = tp.type.replace(/^tool-/, "");
                              const out =
                                ((tp as GenericToolOutput).output as GenericToolOutput) ||
                                ((tp as GenericToolOutput).result as GenericToolOutput);
                              return (
                                <ToolOutputFallbackView
                                  key={`fb-${idx}`}
                                  toolName={rawToolName}
                                  output={out}
                                />
                              );
                            })}
                          </div>
                        ) : null}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })}

          {error && (
            <div className="rounded-2xl border border-rose-200 bg-rose-50 p-3 text-xs text-rose-700">
              <strong>Error:</strong> {error.message || "Failed to process query."}
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* ── 3. Bottom Composer Box (Tarsi Style) ─────────────────────────── */}
        <div className="px-6 pb-2">
          <div className="p-3 rounded-2xl border border-slate-200 bg-white shadow-sm focus-within:border-slate-300 focus-within:shadow-md transition-all">
            <textarea
              ref={textareaRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder='Ask a question or type "Show open vacancies in SM North"...'
              rows={2}
              disabled={isLoading}
              className="text-sm placeholder:text-slate-400 border-0 focus:ring-0 focus:outline-none w-full resize-none text-slate-800 disabled:bg-transparent disabled:opacity-60"
            />
            <div className="flex items-center justify-between pt-2 border-t border-slate-100">
              <div
                className="bg-emerald-50 text-emerald-700 text-xs font-medium px-2.5 py-1 rounded-full flex items-center gap-1.5 border border-emerald-200/60"
                title={`Active module: ${pathname}`}
              >
                <span>⚡ Cloud • {pathname}</span>
              </div>
              <button
                type="button"
                onClick={() => handleSend()}
                disabled={isLoading || !input.trim()}
                title="Send query"
                aria-label="Send message"
                className="w-8 h-8 rounded-full bg-slate-100 hover:bg-slate-900 hover:text-white text-slate-600 flex items-center justify-center transition-colors disabled:opacity-40 cursor-pointer"
              >
                {isLoading ? (
                  <Loader2 size={14} className="animate-spin text-emerald-600" />
                ) : (
                  <ArrowUp size={16} />
                )}
              </button>
            </div>
          </div>
        </div>

        {/* ── 4. Footer Micro-Caption ─────────────────────────────────────── */}
        <div className="text-[11px] text-slate-400 pb-3 text-center">
          OHMni can make mistakes. Review important details.
        </div>
      </div>
    </div>
  );
}
