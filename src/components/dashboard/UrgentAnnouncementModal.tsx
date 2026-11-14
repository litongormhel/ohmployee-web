"use client";

import { useState } from "react";
import { AlertOctagon, CheckCircle, Loader2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  acknowledgeUrgentAnnouncement,
  type Announcement,
} from "@/lib/queries/announcements";

interface UrgentAnnouncementModalProps {
  announcement: Announcement | null;
  profileId?: string | null;
  onAcknowledged?: () => void;
}

export function UrgentAnnouncementModal({
  announcement,
  profileId,
  onAcknowledged,
}: UrgentAnnouncementModalProps) {
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (!announcement || !profileId) {
    return null;
  }

  const handleAcknowledge = async () => {
    try {
      setIsSubmitting(true);
      await acknowledgeUrgentAnnouncement(announcement.id, profileId);
      onAcknowledged?.();
    } catch (err) {
      console.error("[UrgentAnnouncement] Failed to acknowledge:", err);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={true}
      onClose={() => {}} // Mandatory acknowledge: cannot dismiss without clicking Acknowledge
      title={
        <div className="flex items-center gap-2 text-red-500 font-semibold">
          <AlertOctagon className="h-5 w-5 animate-pulse" />
          <span>Urgent Operational Announcement</span>
        </div>
      }
      subtitle="Action or acknowledgment required from all active personnel."
      maxWidthClass="max-w-lg"
      disableBackdropClick={true}
      isSubmitting={isSubmitting}
    >
      <div className="space-y-4 pt-1">
        <div className="rounded-xl border border-red-500/30 bg-red-500/5 p-4 space-y-2.5">
          <h3 className="text-base font-bold text-[var(--foreground)] tracking-tight">
            {announcement.title}
          </h3>
          <p className="text-sm text-[var(--foreground)] leading-relaxed whitespace-pre-wrap">
            {announcement.content}
          </p>
        </div>

        <div className="flex items-center justify-between text-xs text-[var(--text-muted)] px-1">
          <span>
            Posted by: <strong className="text-[var(--foreground)]">{announcement.author_name || "Headquarters"}</strong>
          </span>
          <span>
            {new Date(announcement.created_at).toLocaleDateString(undefined, {
              month: "short",
              day: "numeric",
              year: "numeric",
            })}
          </span>
        </div>

        <div className="pt-3 border-t border-[var(--line)]">
          <button
            type="button"
            onClick={handleAcknowledge}
            disabled={isSubmitting}
            className="w-full flex items-center justify-center gap-2 rounded-lg bg-red-600 px-4 py-3 text-sm font-semibold text-white shadow-xs hover:bg-red-700 transition-colors disabled:opacity-50"
          >
            {isSubmitting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Recording Acknowledgment...
              </>
            ) : (
              <>
                <CheckCircle className="h-4 w-4" />
                I Acknowledge and Understand
              </>
            )}
          </button>
        </div>
      </div>
    </Modal>
  );
}
