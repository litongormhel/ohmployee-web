"use client";

import { Activity } from "lucide-react";
import { Modal } from "@/components/shared/Modal";
import { DiagnosticsTab } from "@/components/settings/DiagnosticsTab";

export interface SystemDiagnosticsModalProps {
  isOpen: boolean;
  onClose: () => void;
  isSuperAdmin: boolean;
}

export function SystemDiagnosticsModal({
  isOpen,
  onClose,
  isSuperAdmin,
}: SystemDiagnosticsModalProps) {
  if (!isSuperAdmin) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="System Diagnostics & Governance Probes"
      subtitle="Real-time infrastructure health, PostgREST schema cache sync, and operational freeze flags."
      icon={Activity}
      maxWidthClass="max-w-4xl"
    >
      <div className="py-2">
        <DiagnosticsTab />
      </div>
    </Modal>
  );
}
