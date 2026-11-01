"use client";

import React, { useState, useMemo, useRef, useEffect, useCallback } from "react";
import { usePathname } from "next/navigation";
import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { createClient } from "@/lib/supabase/client";
import {
  RotateCcw,
  X,
  Send,
  Sparkles,
  Database,
  CheckCircle2,
  Loader2,
  Bot,
  User as UserIcon,
} from "lucide-react";

type OhmniDrawerProps = {
  isOpen: boolean;
  onClose: () => void;
};

// ── Lightweight Markdown Formatter ──────────────────────────────────────────

function renderInlineFormatted(text: string): React.ReactNode {
  // Regex to match `code` and **bold**
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
            className="px-1 py-0.5 mx-0.5 bg-slate-200 text-slate-900 rounded font-mono text-[11px]"
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
        <div key={`table-wrapper-${idx}`} className="my-2 overflow-x-auto rounded border border-slate-200">
          <table className="min-w-full divide-y divide-slate-200 text-left text-[11px]">
            <thead className="bg-slate-100 font-semibold text-slate-700">
              <tr>
                {header.map((col, cIdx) => (
                  <th key={`th-${cIdx}`} className="px-2 py-1.5 whitespace-nowrap">
                    {col}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 bg-white">
              {dataRows.map((r, rIdx) => (
                <tr key={`tr-${rIdx}`} className="hover:bg-slate-50">
                  {r.map((col, cIdx) => (
                    <td key={`td-${cIdx}`} className="px-2 py-1 whitespace-nowrap">
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
      // Check if it's a separator line e.g. |---|---|
      if (cols.every((c) => /^:?-+:?$/.test(c))) {
        // Separator row, ignore
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
        <div key={`li-${idx}`} className="flex items-start gap-1.5 pl-1 my-0.5">
          <span className="text-slate-400 mt-1 text-[8px]">•</span>
          <span className="flex-1 leading-snug">{renderInlineFormatted(trimmed.slice(2))}</span>
        </div>
      );
      return;
    }

    renderedElements.push(
      <p key={`p-${idx}`} className="leading-snug my-1">
        {renderInlineFormatted(trimmed)}
      </p>
    );
  });

  if (inTable) {
    flushTable(lines.length);
  }

  return <div className="space-y-0.5 text-xs text-slate-800">{renderedElements}</div>;
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
  // Default / CENCOM
  return [
    "Give me an executive snapshot of Plantilla fill rate and open slots",
    "How many pending items are in the HR Emploc queue?",
    "Show pending Headcount Requests across branches",
  ];
}

// ── Main OHMni Drawer Component ─────────────────────────────────────────────

export function OhmniDrawer({ isOpen, onClose }: OhmniDrawerProps) {
  const pathname = usePathname();
  const [input, setInput] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Guardrail 1: Forward current access_token via Authorization Bearer header
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
    <aside
      aria-label="OHMni Co-Pilot"
      className="fixed inset-y-0 right-0 z-50 flex w-[380px] sm:w-[400px] flex-col border-l border-[var(--line)] bg-white text-slate-800 shadow-2xl transition-transform duration-200"
    >
      {/* ── ZONE A: Compact Sub-Header (44px / h-11) ────────────────────── */}
      <header className="flex h-11 shrink-0 items-center justify-between border-b border-slate-200 bg-slate-50 px-3">
        <div className="flex items-center gap-2">
          <span
            className={`h-2.5 w-2.5 rounded-full transition-colors ${
              isLoading
                ? "bg-amber-500 animate-pulse"
                : "bg-emerald-500 shadow-2xs shadow-emerald-500/50"
            }`}
            title={isLoading ? "Querying live data..." : "OHMni Active"}
          />
          <div className="flex items-center gap-1.5">
            <span className="font-bold text-xs tracking-tight text-slate-900">
              OHMni
            </span>
            <span className="rounded bg-brand-500/10 px-1 py-0.2 text-[9px] font-semibold text-brand-700">
              AI Co-Pilot
            </span>
          </div>
        </div>

        {/* Dynamic Route Context Pill */}
        <div
          className="max-w-[140px] truncate rounded-full border border-slate-200 bg-white px-2 py-0.5 font-mono text-[10px] text-slate-600"
          title={`Active route: ${pathname}`}
        >
          📍 {pathname}
        </div>

        {/* Header Actions */}
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={handleReset}
            title="Reset Chat Session"
            className="rounded p-1 text-slate-400 hover:bg-slate-200 hover:text-slate-700 transition-colors cursor-pointer"
          >
            <RotateCcw size={14} />
          </button>
          <button
            type="button"
            onClick={onClose}
            title="Close OHMni Drawer"
            className="rounded p-1 text-slate-400 hover:bg-slate-200 hover:text-slate-700 transition-colors cursor-pointer"
          >
            <X size={15} />
          </button>
        </div>
      </header>

      {/* ── ZONE B: Dynamic Body ────────────────────────────────────────── */}
      <div className="flex-1 overflow-y-auto p-3 space-y-3 bg-slate-50/50">
        {messages.length === 0 ? (
          /* Route-Aware Zero-State */
          <div className="flex flex-col justify-center h-full px-2 py-4">
            <div className="flex items-center gap-2 mb-2 text-slate-700">
              <Sparkles size={16} className="text-amber-500" />
              <h2 className="text-xs font-bold uppercase tracking-wider text-slate-600">
                Operations & Data Self-Service
              </h2>
            </div>
            <p className="text-[11.5px] text-slate-500 leading-relaxed mb-4">
              Ask real-time data queries or procedure guides. Scoped directly to your
              authenticated permissions.
            </p>

            <div className="space-y-2">
              <span className="text-[10px] font-bold uppercase text-slate-400 tracking-wider">
                Suggested for {pathname}
              </span>
              {starters.map((promptText, i) => (
                <button
                  key={i}
                  type="button"
                  onClick={() => handleSend(promptText)}
                  className="w-full text-left rounded-lg border border-slate-200 bg-white p-2.5 text-xs text-slate-700 shadow-2xs hover:border-brand-500 hover:bg-brand-50/30 transition-all cursor-pointer flex items-start gap-2"
                >
                  <span className="text-brand-500 font-mono text-[11px] mt-0.5 font-bold">
                    {i + 1}.
                  </span>
                  <span className="leading-snug">{promptText}</span>
                </button>
              ))}
            </div>
          </div>
        ) : (
          /* Active Message & Micro-UI Stream */
          <div className="space-y-3">
            {messages.map((m: UIMessage) => {
              const isUser = m.role === "user";

              // Extract text parts and tool invocation parts
              const textParts = m.parts.filter(
                (p): p is { type: "text"; text: string } => p.type === "text"
              );
              const toolParts = m.parts.filter((p) =>
                p.type.startsWith("tool-") || p.type === "dynamic-tool"
              );

              return (
                <div
                  key={m.id}
                  className={`flex flex-col ${isUser ? "items-end" : "items-start"}`}
                >
                  {isUser ? (
                    /* User Bubble */
                    <div className="flex items-end gap-1.5 max-w-[85%]">
                      <div className="rounded-lg bg-slate-900 px-3 py-2 text-xs text-white shadow-2xs break-words whitespace-pre-wrap leading-snug">
                        {textParts.map((t) => t.text).join("")}
                      </div>
                      <div className="h-5 w-5 rounded-full bg-slate-200 flex items-center justify-center shrink-0">
                        <UserIcon size={12} className="text-slate-600" />
                      </div>
                    </div>
                  ) : (
                    /* Assistant Card */
                    <div className="w-full space-y-1.5">
                      {/* Tool Execution Trust Indicators */}
                      {toolParts.map((tp, idx) => {
                        const rawToolName = tp.type.replace(/^tool-/, "");
                        const isDone =
                          "state" in tp && tp.state === "output-available";
                        const isCalling =
                          "state" in tp &&
                          (tp.state === "input-streaming" ||
                            tp.state === "input-available");

                        return (
                          <div
                            key={`tool-${idx}`}
                            className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[10px] font-medium border ${
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

                      {/* Assistant Reply Card */}
                      <div className="w-full rounded-lg border border-slate-200 bg-white p-3 shadow-2xs">
                        <div className="flex items-center gap-1.5 mb-1.5 pb-1 border-b border-slate-100">
                          <Bot size={13} className="text-brand-600" />
                          <span className="text-[10px] font-bold uppercase text-slate-400 tracking-wider">
                            OHMni Response
                          </span>
                        </div>
                        {textParts.length > 0 ? (
                          textParts.map((t, idx) => (
                            <FormattedContent key={idx} content={t.text} />
                          ))
                        ) : isLoading ? (
                          <div className="flex items-center gap-2 text-slate-400 py-1">
                            <Loader2 size={13} className="animate-spin text-amber-500" />
                            <span className="text-xs italic">Analyzing operations data...</span>
                          </div>
                        ) : null}
                      </div>
                    </div>
                  )}
                </div>
              );
            })}

            {error && (
              <div className="rounded-lg border border-rose-200 bg-rose-50 p-2.5 text-xs text-rose-700">
                <strong>Error:</strong> {error.message || "Failed to process query."}
              </div>
            )}

            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* ── ZONE C: Contextual Quick-Follow-Up Strip ─────────────────────── */}
      <div className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-100 border-t border-slate-200 overflow-x-auto no-scrollbar text-[11px]">
        <button
          type="button"
          onClick={() => handleSend("Filter for vacant slots only")}
          disabled={isLoading}
          className="whitespace-nowrap px-2 py-0.5 rounded-full border border-slate-300 bg-white text-slate-700 hover:bg-slate-50 transition-colors disabled:opacity-50 cursor-pointer"
        >
          🔍 Vacant Only
        </button>
        <button
          type="button"
          onClick={() => handleSend("Check HR Emploc queue for pending items")}
          disabled={isLoading}
          className="whitespace-nowrap px-2 py-0.5 rounded-full border border-slate-300 bg-white text-slate-700 hover:bg-slate-50 transition-colors disabled:opacity-50 cursor-pointer"
        >
          📋 Check Emploc Queue
        </button>
        <button
          type="button"
          onClick={handleReset}
          disabled={isLoading || messages.length === 0}
          className="whitespace-nowrap px-2 py-0.5 rounded-full border border-slate-300 bg-white text-slate-700 hover:bg-slate-50 transition-colors disabled:opacity-50 cursor-pointer ml-auto"
        >
          ↺ Clear
        </button>
      </div>

      {/* ── ZONE D: Bottom Composer ──────────────────────────────────────── */}
      <footer className="border-t border-slate-200 p-3 bg-white space-y-2">
        <div className="relative flex items-center">
          <textarea
            ref={textareaRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask OHMni (e.g., open vacancies, slot authority)..."
            rows={2}
            disabled={isLoading}
            className="w-full resize-none rounded-lg border border-slate-200 px-3 py-2 pr-10 text-xs text-slate-800 placeholder-slate-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 disabled:bg-slate-50 disabled:opacity-60"
          />
          <button
            type="button"
            onClick={() => handleSend()}
            disabled={isLoading || !input.trim()}
            title="Send Message"
            className="absolute right-2 bottom-2.5 rounded-md bg-slate-900 p-1.5 text-white hover:bg-slate-800 disabled:bg-slate-200 disabled:text-slate-400 transition-colors cursor-pointer"
          >
            {isLoading ? <Loader2 size={13} className="animate-spin" /> : <Send size={13} />}
          </button>
        </div>

        {/* Footer Micro-Caption */}
        <div className="flex items-center justify-between text-[10px] text-slate-400">
          <span className="flex items-center gap-1">
            <Database size={10} className="text-slate-400" />
            Scoped to your RBAC permissions
          </span>
          <span>Resets on refresh</span>
        </div>
      </footer>
    </aside>
  );
}
