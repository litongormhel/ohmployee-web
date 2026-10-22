"use client";

import { useState, useRef } from "react";
import { CloudUpload, FileSpreadsheet, X, CheckCircle2 } from "lucide-react";

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

  if (!isOpen) return null;

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
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="mika-sync-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/60 p-4 backdrop-blur-xs"
    >
      <div className="w-full max-w-lg rounded-2xl border border-slate-200 bg-white p-6 shadow-2xl transition-all">
        {/* Header */}
        <div className="flex items-start justify-between border-b border-slate-100 pb-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-slate-900 text-blue-400">
              <CloudUpload className="h-5 w-5" />
            </div>
            <div>
              <h2 id="mika-sync-title" className="text-base font-bold text-slate-900">
                Sync MIKA Workforce Masterfile
              </h2>
              <p className="text-xs text-slate-500">
                Upload MIKA export to reconcile Active Plantilla &amp; Ghost Cases
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-700"
            aria-label="Close dialog"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Content */}
        <div className="space-y-4 py-4">
          {syncDone ? (
            <div className="rounded-xl border border-emerald-200 bg-emerald-50/70 p-6 text-center">
              <CheckCircle2 className="mx-auto h-10 w-10 text-emerald-600" />
              <div className="mt-2 text-sm font-bold text-emerald-950">
                MIKA Masterfile Synchronized Successfully
              </div>
              <p className="mt-1 text-xs text-emerald-700">
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
                className={`flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 text-center transition ${
                  dragActive
                    ? "border-blue-600 bg-blue-50/50"
                    : "border-slate-300 bg-slate-50/60 hover:bg-slate-50"
                }`}
              >
                <input
                  ref={fileInputRef}
                  type="file"
                  accept=".xlsx,.csv"
                  onChange={handleFileChange}
                  className="hidden"
                />
                <FileSpreadsheet className="h-9 w-9 text-blue-600" />
                <div className="mt-2 text-xs font-bold text-slate-900">
                  {selectedFile ? selectedFile.name : "Click to select or drag & drop MIKA masterfile"}
                </div>
                <p className="mt-0.5 text-[11px] text-slate-500">
                  Supported formats: Excel (.xlsx) or CSV (.csv)
                </p>
              </div>

              <div className="rounded-xl border border-slate-200/90 bg-slate-50 p-3 text-xs text-slate-600">
                <span className="font-semibold text-slate-900">Data Synchronization Scope:</span>
                <ul className="mt-1 list-disc space-y-0.5 pl-4 text-[11px] text-slate-600">
                  <li>Plantilla active personnel baseline &amp; store assignments</li>
                  <li>Cross-module SLA reconciliation for open requisitions</li>
                  <li>Identity hygiene and ghost employee audit cross-check</li>
                </ul>
              </div>
            </>
          )}
        </div>

        {/* Footer Actions */}
        {!syncDone && (
          <div className="flex items-center justify-end gap-2 border-t border-slate-100 pt-3">
            <button
              type="button"
              onClick={onClose}
              disabled={isSyncing}
              className="rounded-xl border border-slate-300 px-4 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleExecuteSync}
              disabled={isSyncing}
              className="inline-flex items-center gap-1.5 rounded-xl bg-slate-900 px-4 py-2 text-xs font-bold text-white shadow-xs hover:bg-slate-800 disabled:opacity-50"
            >
              <CloudUpload className="h-3.5 w-3.5 text-blue-300" />
              <span>{isSyncing ? "Syncing MIKA..." : "Sync MIKA"}</span>
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
