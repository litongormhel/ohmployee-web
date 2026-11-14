"use client";

import { useState } from "react";
import {
  Megaphone,
  AlertTriangle,
  AlertOctagon,
  Pin,
  Plus,
  Archive,
  ChevronDown,
  ChevronUp,
  Clock,
  Loader2,
} from "lucide-react";
import {
  useAnnouncements,
  archiveAnnouncement,
} from "@/lib/queries/announcements";
import { CreateAnnouncementModal } from "@/components/dashboard/CreateAnnouncementModal";
import { hasFullAccess } from "@/lib/rbac";
import type { WebCurrentUserContext } from "@/lib/auth";

interface AnnouncementBannerStripProps {
  currentUser: WebCurrentUserContext | null;
}

export function AnnouncementBannerStrip({ currentUser }: AnnouncementBannerStripProps) {
  const { data: announcements = [], isLoading, refetch } = useAnnouncements();
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [archivingId, setArchivingId] = useState<string | null>(null);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  const isAdmin = hasFullAccess(currentUser);
  const profileId = currentUser?.profileId;

  const toggleExpand = (id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleArchive = async (id: string) => {
    if (!confirm("Are you sure you want to archive this announcement?")) return;
    try {
      setArchivingId(id);
      await archiveAnnouncement(id);
      await refetch();
    } catch (err) {
      console.error("[announcements] Failed to archive:", err);
    } finally {
      setArchivingId(null);
    }
  };

  // If no announcements and not admin, collapse cleanly
  if (!isLoading && announcements.length === 0 && !isAdmin) {
    return null;
  }

  return (
    <div className="w-full space-y-3">
      {/* Header Strip with Title and Admin Action */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-blue-500/10 text-blue-500">
            <Megaphone className="h-4 w-4" />
          </div>
          <div>
            <h2 className="text-sm font-bold tracking-tight text-[var(--foreground)] flex items-center gap-2">
              Announcements
              {announcements.length > 0 && (
                <span className="inline-flex items-center justify-center rounded-full bg-blue-500/10 px-2 py-0.5 text-[11px] font-semibold text-blue-500">
                  {announcements.length}
                </span>
              )}
            </h2>
          </div>
        </div>

        {isAdmin && profileId && (
          <button
            type="button"
            onClick={() => setIsCreateOpen(true)}
            className="flex items-center gap-1.5 rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white shadow-xs hover:bg-blue-700 transition-colors"
          >
            <Plus className="h-3.5 w-3.5" />
            New Announcement
          </button>
        )}
      </div>

      {/* Announcements List */}
      {isLoading ? (
        <div className="rounded-xl border border-[var(--line)] bg-[var(--surface-base)] p-4 text-center text-xs text-[var(--text-muted)] animate-pulse">
          Loading operational announcements...
        </div>
      ) : announcements.length === 0 ? (
        isAdmin && (
          <div className="rounded-xl border border-dashed border-[var(--line)] bg-[var(--surface-base)] p-6 text-center space-y-2">
            <Megaphone className="h-6 w-6 text-[var(--text-muted)] mx-auto opacity-50" />
            <p className="text-xs text-[var(--text-muted)]">
              No active announcements. Click <strong>New Announcement</strong> above to broadcast updates to staff and workforce teams.
            </p>
          </div>
        )
      ) : (
        <div className="grid grid-cols-1 gap-2.5">
          {announcements.map((item) => {
            const isExpanded = expandedIds.has(item.id);
            const isLong = item.content.length > 160;

            const priorityConfig = {
              urgent: {
                border: "border-red-500/40 bg-red-500/5",
                badge: "bg-red-500/15 text-red-500 border-red-500/30",
                icon: AlertOctagon,
                label: "URGENT",
              },
              important: {
                border: "border-amber-500/40 bg-amber-500/5",
                badge: "bg-amber-500/15 text-amber-500 border-amber-500/30",
                icon: AlertTriangle,
                label: "IMPORTANT",
              },
              info: {
                border: "border-blue-500/30 bg-blue-500/5",
                badge: "bg-blue-500/15 text-blue-500 border-blue-500/30",
                icon: Megaphone,
                label: "GENERAL",
              },
            }[item.priority];

            const PriorityIcon = priorityConfig.icon;

            return (
              <div
                key={item.id}
                className={`relative rounded-xl border p-4 transition-all ${priorityConfig.border} shadow-2xs`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-start gap-3 flex-1 min-w-0">
                    <div className="mt-0.5 shrink-0">
                      <PriorityIcon className={`h-4 w-4 ${item.priority === "urgent" ? "text-red-500 animate-pulse" : item.priority === "important" ? "text-amber-500" : "text-blue-500"}`} />
                    </div>

                    <div className="space-y-1 flex-1 min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className={`inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 text-[10px] font-bold tracking-wider ${priorityConfig.badge}`}>
                          {priorityConfig.label}
                        </span>

                        {item.is_pinned && (
                          <span className="inline-flex items-center gap-1 rounded-md border border-blue-500/30 bg-blue-500/10 px-1.5 py-0.5 text-[10px] font-semibold text-blue-500">
                            <Pin className="h-2.5 w-2.5" />
                            PINNED
                          </span>
                        )}

                        <h3 className="text-sm font-semibold text-[var(--foreground)] truncate">
                          {item.title}
                        </h3>
                      </div>

                      <div className="text-xs text-[var(--foreground)]/90 leading-relaxed whitespace-pre-wrap">
                        {isLong && !isExpanded ? (
                          <>
                            {item.content.substring(0, 160)}...{" "}
                            <button
                              type="button"
                              onClick={() => toggleExpand(item.id)}
                              className="text-blue-500 font-medium hover:underline inline-flex items-center gap-0.5"
                            >
                              Show more <ChevronDown className="h-3 w-3" />
                            </button>
                          </>
                        ) : (
                          <>
                            {item.content}
                            {isLong && (
                              <button
                                type="button"
                                onClick={() => toggleExpand(item.id)}
                                className="text-blue-500 font-medium hover:underline inline-flex items-center gap-0.5 ml-2"
                              >
                                Show less <ChevronUp className="h-3 w-3" />
                              </button>
                            )}
                          </>
                        )}
                      </div>

                      <div className="flex flex-wrap items-center gap-3 text-[11px] text-[var(--text-muted)] pt-1">
                        <span>
                          By <strong className="text-[var(--foreground)]">{item.author_name || "Headquarters"}</strong>
                        </span>
                        <span>•</span>
                        <span className="flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          {new Date(item.created_at).toLocaleDateString(undefined, {
                            month: "short",
                            day: "numeric",
                            year: "numeric",
                          })}
                        </span>
                        {item.target_roles && item.target_roles.length > 0 && (
                          <>
                            <span>•</span>
                            <span className="text-[var(--text-muted)]">
                              Target: {item.target_roles.join(", ")}
                            </span>
                          </>
                        )}
                      </div>
                    </div>
                  </div>

                  {isAdmin && (
                    <div className="shrink-0">
                      <button
                        type="button"
                        onClick={() => handleArchive(item.id)}
                        disabled={archivingId === item.id}
                        title="Archive announcement"
                        className="rounded-lg p-1.5 text-[var(--text-muted)] hover:bg-[var(--surface-muted)] hover:text-red-500 transition-colors"
                      >
                        {archivingId === item.id ? (
                          <Loader2 className="h-4 w-4 animate-spin text-red-500" />
                        ) : (
                          <Archive className="h-4 w-4" />
                        )}
                      </button>
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Admin Creation Modal */}
      {isAdmin && profileId && (
        <CreateAnnouncementModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          profileId={profileId}
          onSuccess={() => refetch()}
        />
      )}
    </div>
  );
}
