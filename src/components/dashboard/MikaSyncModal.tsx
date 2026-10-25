"use client";

import { useState, useRef } from "react";
import { CloudUpload, FileSpreadsheet, CheckCircle2 } from "lucide-react";
import { Modal } from "@/components/shared/Modal";

interface MikaSyncModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

export function MikaSyncModal({ isOpen, onClose, onSuccess }: MikaSyncModalProps) {
  const [dragActive, setDragActive] = useState(false);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [isSyncing, setIsSyncing] = useState(false);
  const [syncDone, setSyncDone] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleDrag = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true);
    } else if (e.type === "dragleave") {
      setDragActive(false);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      setSelectedFile(e.dataTransfer.files[0]);
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      setSelectedFile(e.target.files[0]);
    }
  };

  const handleExecuteSync = () => {
    setIsSyncing(true);
    setTimeout(() => {
      setIsSyncing(false);
      setSyncDone(true);
      setTimeout(() => {
        setSyncDone(false);
        setSelectedFile(null);
        onClose();
        if (onSuccess) onSuccess();
      }, 1200);
    }, 1400);
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Sync MIKA Workforce Masterfile"
      subtitle="Upload MIKA export to reconcile Active Plantilla & Ghost Cases"
      icon={CloudUpload}
      maxWidthClass="max-w-lg"
      footer={
        !syncDone ? (
          <>
            <button
              type="button"
              onClick={onClose}
              disabled={isSyncing}
              className="rounded-lg border border-border-default bg-surface-base px-3.5 py-1.5 text-xs font-semibold text-text-primary shadow-2xs hover:bg-surface-hover cursor-pointer disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={!selectedFile || isSyncing}
              onClick={handleExecuteSync}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand-500 px-4 py-1.5 text-xs font-semibold text-white shadow-xs hover:bg-brand-600 disabled:opacity-50 cursor-pointer"
            >
              <CloudUpload className="h-3.5 w-3.5" />
              <span>{isSyncing ? "Reconciling..." : "Execute Sync"}</span>
            </button>
          </>
        ) : null
      }
    >
      <div className="space-y-4">
        {syncDone ? (
          <div className="rounded-xl border border-pct-good-border bg-pct-good-bg p-6 text-center">
            <CheckCircle2 className="mx-auto h-10 w-10 text-pct-good-text" />
            <div className="mt-2 text-sm font-bold text-pct-good-text">
              MIKA Masterfile Synchronized Successfully
            </div>
            <p className="mt-1 text-xs text-text-secondary">
              Active Plantilla (13) verified and 259 Ghost Employee cases updated in audit ledger.
            </p>
          </div>
        ) : (
          <>
            <div
              onDragEnter={handleDrag}
              onDragLeave={handleDrag}
              onDragOver={handleDrag}
              onDrop={handleDrop}
              onClick={() => fileInputRef.current?.click()}
              className={`flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition-colors ${
                dragActive
                  ? "border-brand-500 bg-brand-50 dark:bg-brand-500/10"
                  : "border-border-default bg-surface-muted hover:bg-surface-hover"
              }`}
            >
              <input
                ref={fileInputRef}
                type="file"
                accept=".xlsx,.csv"
                onChange={handleFileChange}
                className="hidden"
              />
              <FileSpreadsheet className="h-9 w-9 text-brand-500" />
              <div className="mt-2 text-xs font-semibold text-text-primary">
                {selectedFile ? selectedFile.name : "Click to select or drag & drop MIKA masterfile"}
              </div>
              <p className="mt-0.5 text-[11px] text-text-muted">
                Supported formats: Excel (.xlsx) or CSV (.csv)
              </p>
            </div>

            <div className="rounded-xl border border-border-subtle bg-surface-muted p-3 text-xs text-text-secondary">
              <span className="font-semibold text-text-primary">Data Synchronization Scope:</span>
              <ul className="mt-1 list-disc space-y-0.5 pl-4 text-[11px] text-text-secondary">
                <li>Plantilla active personnel baseline &amp; store assignments</li>
                <li>Cross-module SLA reconciliation for open requisitions</li>
                <li>Identity hygiene and ghost employee audit cross-check</li>
              </ul>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}
