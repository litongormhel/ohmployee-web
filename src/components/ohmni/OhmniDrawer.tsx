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
  return false;
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

  return (
    <p className="text-sm text-text-muted">
      Query completed successfully.
    </p>
  );
}

// ── Route Starter Prompts ───────────────────────────────────────────────────

function getStarterPrompts(pathname: string): string[] {
  if (pathname.includes("/plantilla")) {
    return [
      "Summarize Plantilla fill-rate and vacant slots by branch",
      "How do I file a new Headcount Request?",
      "How do I bulk-import or Sync MIKA in Plantilla?",
    ];
  }
  if (pathname.includes("/vacancy")) {
    return [
      "Count all open vacancies grouped by position or branch",
      "List pending Headcount Requests older than 7 days",
      "Show open vacancies across retail branches",
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
                      <div className="text-sm text-text-secondary leading-relaxed bg-[var(--surface-base)] p-3.5 rounded-2xl border border-[var(--border-subtle)] shadow-2xs w-full">
                        {hasNonEmptyText ? (
                          textParts.map((t, idx) => (
                            <FormattedContent key={idx} content={t.text} />
                          ))
                        ) : isLoading ? (
                          /* Loading State while stream is in flight */
                          <div className="flex items-center gap-2 text-text-muted py-1">
                            <Loader2 size={14} className="animate-spin text-emerald-500" />
                            <span className="text-xs italic text-text-muted">
                              Thinking.....
                            </span>
                          </div>
                        ) : toolParts.length > 0 ? (
                          /* Fallback: stream finished with completed tools but 0 text parts */
                          <ToolOutputFallbackView toolParts={toolParts} />
                        ) : null}
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
              disabled={isLoading}
              className="text-sm placeholder:text-text-muted border-0 focus:ring-0 focus:outline-none w-full resize-none text-text-primary disabled:bg-transparent disabled:opacity-60 bg-transparent"
            />
            <div className="flex items-center justify-end pt-2 border-t border-[var(--border-subtle)]">
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
