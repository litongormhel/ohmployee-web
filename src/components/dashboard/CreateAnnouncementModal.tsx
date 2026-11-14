"use client";

import { useState } from "react";
import {
  Megaphone,
  AlertTriangle,
  AlertOctagon,
  Pin,
  Calendar,
  Users,
  Loader2,
  CheckCircle2,
} from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import {
  createAnnouncement,
  type AnnouncementPriority,
  type CreateAnnouncementInput,
} from "@/lib/queries/announcements";

interface CreateAnnouncementModalProps {
  isOpen: boolean;
  onClose: () => void;
  profileId: string;
  onSuccess?: () => void;
}

const AVAILABLE_ROLES = [
  "Operations Manager",
  "HRCO",
  "ATL",
  "TL",
  "Encoder",
  "HR Personnel",
  "Recruitment Team",
  "Back Office",
  "Viewer",
];

export function CreateAnnouncementModal({
  isOpen,
  onClose,
  profileId,
  onSuccess,
}: CreateAnnouncementModalProps) {
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [priority, setPriority] = useState<AnnouncementPriority>("info");
  const [isPinned, setIsPinned] = useState(false);
  const [isBroadcastAll, setIsBroadcastAll] = useState(true);
  const [selectedRoles, setSelectedRoles] = useState<string[]>([]);
  const [expiresAt, setExpiresAt] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const toggleRole = (role: string) => {
    setSelectedRoles((prev) =>
      prev.includes(role) ? prev.filter((r) => r !== role) : [...prev, role]
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !content.trim()) {
      setErrorMsg("Please enter both a title and message content.");
      return;
    }

    try {
      setIsSubmitting(true);
      setErrorMsg(null);

      const payload: CreateAnnouncementInput = {
        title: title.trim(),
        content: content.trim(),
        priority,
        is_pinned: isPinned,
        target_roles: isBroadcastAll || selectedRoles.length === 0 ? null : selectedRoles,
        expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
      };

      await createAnnouncement(payload, profileId);

      // Reset and close
      setTitle("");
      setContent("");
      setPriority("info");
      setIsPinned(false);
      setIsBroadcastAll(true);
      setSelectedRoles([]);
      setExpiresAt("");
      onSuccess?.();
      onClose();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Failed to publish announcement.";
      setErrorMsg(msg);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Create Announcement"
      subtitle="Publish an operational notice to all users or specific roles across Web and Mobile."
      icon={Megaphone}
      maxWidthClass="max-w-xl"
      isSubmitting={isSubmitting}
    >
      <form onSubmit={handleSubmit} className="space-y-5 text-sm">
        {errorMsg && (
          <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-xs text-red-500">
            {errorMsg}
          </div>
        )}

        {/* Priority Selection */}
        <div>
          <label className="block text-xs font-semibold text-[var(--foreground)] mb-2">
            Priority Level
          </label>
          <div className="grid grid-cols-3 gap-2">
            <button
              type="button"
              onClick={() => setPriority("info")}
              className={`flex items-center justify-center gap-2 rounded-lg border py-2.5 px-3 text-xs font-medium transition-all ${
                priority === "info"
                  ? "border-blue-500 bg-blue-500/10 text-blue-500 ring-1 ring-blue-500"
                  : "border-[var(--line)] bg-[var(--surface-base)] text-[var(--text-muted)] hover:border-[var(--line-subtle)]"
              }`}
            >
              <Megaphone className="h-4 w-4" />
              General Info
            </button>

            <button
              type="button"
              onClick={() => setPriority("important")}
              className={`flex items-center justify-center gap-2 rounded-lg border py-2.5 px-3 text-xs font-medium transition-all ${
                priority === "important"
                  ? "border-amber-500 bg-amber-500/10 text-amber-500 ring-1 ring-amber-500"
                  : "border-[var(--line)] bg-[var(--surface-base)] text-[var(--text-muted)] hover:border-[var(--line-subtle)]"
              }`}
            >
              <AlertTriangle className="h-4 w-4" />
              Important
            </button>

            <button
              type="button"
              onClick={() => setPriority("urgent")}
              className={`flex items-center justify-center gap-2 rounded-lg border py-2.5 px-3 text-xs font-medium transition-all ${
                priority === "urgent"
                  ? "border-red-500 bg-red-500/10 text-red-500 ring-1 ring-red-500"
                  : "border-[var(--line)] bg-[var(--surface-base)] text-[var(--text-muted)] hover:border-[var(--line-subtle)]"
              }`}
            >
              <AlertOctagon className="h-4 w-4" />
              Urgent (Popup)
            </button>
          </div>
          {priority === "urgent" && (
            <p className="mt-1.5 text-xs text-red-500/90 italic">
              * Urgent notices require active users to click &ldquo;Acknowledge&rdquo; before dismissing.
            </p>
          )}
        </div>

        {/* Title */}
        <div>
          <label className="block text-xs font-semibold text-[var(--foreground)] mb-1.5">
            Announcement Title <span className="text-red-500">*</span>
          </label>
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g., Scheduled System Maintenance & Import Freeze"
            className="w-full rounded-lg border border-[var(--line)] bg-[var(--surface-base)] px-3 py-2 text-sm text-[var(--foreground)] placeholder:text-[var(--text-muted)] focus:border-blue-500 focus:outline-none"
            required
          />
        </div>

        {/* Content */}
        <div>
          <label className="block text-xs font-semibold text-[var(--foreground)] mb-1.5">
            Message Body <span className="text-red-500">*</span>
          </label>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder="Provide clear details and instructions for workforce teams..."
            rows={4}
            className="w-full rounded-lg border border-[var(--line)] bg-[var(--surface-base)] px-3 py-2 text-sm text-[var(--foreground)] placeholder:text-[var(--text-muted)] focus:border-blue-500 focus:outline-none resize-y"
            required
          />
        </div>

        {/* Pinned & Expiration Controls */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-1">
          <div className="flex items-center gap-2.5 rounded-lg border border-[var(--line)] bg-[var(--surface-base)] p-3">
            <input
              type="checkbox"
              id="isPinnedCheck"
              checked={isPinned}
              onChange={(e) => setIsPinned(e.target.checked)}
              className="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
            />
            <label htmlFor="isPinnedCheck" className="text-xs font-medium text-[var(--foreground)] cursor-pointer flex items-center gap-1.5">
              <Pin className="h-3.5 w-3.5 text-blue-500" />
              Pin to Top of Dashboard
            </label>
          </div>

          <div>
            <label className="block text-xs font-semibold text-[var(--foreground)] mb-1.5 flex items-center gap-1">
              <Calendar className="h-3.5 w-3.5 text-[var(--text-muted)]" />
              Auto-Expire Date (Optional)
            </label>
            <input
              type="datetime-local"
              value={expiresAt}
              onChange={(e) => setExpiresAt(e.target.value)}
              className="w-full rounded-lg border border-[var(--line)] bg-[var(--surface-base)] px-2.5 py-2 text-xs text-[var(--foreground)] focus:border-blue-500 focus:outline-none"
            />
          </div>
        </div>

        {/* Target Audience */}
        <div className="rounded-lg border border-[var(--line)] bg-[var(--surface-base)] p-3 space-y-3">
          <div className="flex items-center justify-between">
            <label className="text-xs font-semibold text-[var(--foreground)] flex items-center gap-1.5">
              <Users className="h-3.5 w-3.5 text-[var(--text-muted)]" />
              Target Audience
            </label>
            <button
              type="button"
              onClick={() => {
                setIsBroadcastAll(!isBroadcastAll);
                if (!isBroadcastAll) setSelectedRoles([]);
              }}
              className="text-xs text-blue-500 hover:underline font-medium"
            >
              {isBroadcastAll ? "Restrict to Specific Roles" : "Broadcast to Everyone"}
            </button>
          </div>

          {isBroadcastAll ? (
            <p className="text-xs text-[var(--text-muted)]">
              This announcement will be visible to all active employees and staff across all roles.
            </p>
          ) : (
            <div className="space-y-2">
              <p className="text-xs text-[var(--text-muted)]">
                Select the roles that should receive this notice:
              </p>
              <div className="grid grid-cols-2 gap-2 max-h-36 overflow-y-auto pr-1">
                {AVAILABLE_ROLES.map((role) => (
                  <label
                    key={role}
                    className="flex items-center gap-2 text-xs text-[var(--foreground)] p-1 rounded hover:bg-[var(--surface-muted)] cursor-pointer"
                  >
                    <input
                      type="checkbox"
                      checked={selectedRoles.includes(role)}
                      onChange={() => toggleRole(role)}
                      className="h-3.5 w-3.5 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span>{role}</span>
                  </label>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Footer Actions */}
        <div className="flex justify-end gap-2 pt-2 border-t border-[var(--line)]">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="rounded-lg border border-[var(--line)] px-4 py-2 text-xs font-medium text-[var(--text-muted)] hover:bg-[var(--surface-muted)] transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={isSubmitting}
            className="flex items-center gap-1.5 rounded-lg bg-blue-600 px-4 py-2 text-xs font-medium text-white hover:bg-blue-700 transition-colors disabled:opacity-50"
          >
            {isSubmitting ? (
              <>
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                Publishing...
              </>
            ) : (
              <>
                <CheckCircle2 className="h-3.5 w-3.5" />
                Publish Announcement
              </>
            )}
          </button>
        </div>
      </form>
    </Modal>
  );
}
