"use client";

import { useState, useEffect } from "react";
import {
  X,
  ChevronLeft,
  ChevronRight,
  ZoomIn,
  ZoomOut,
  RotateCw,
  Download,
  Loader2,
  FileText,
  AlertCircle,
} from "lucide-react";
import { getHrEmplocDocSignedUrl, type HrEmplocAttachment } from "@/lib/queries/hr_emploc";

interface DocumentPreviewModalProps {
  isOpen: boolean;
  onClose: () => void;
  attachments: HrEmplocAttachment[];
  initialIndex?: number;
}

export function DocumentPreviewModal({
  isOpen,
  onClose,
  attachments,
  initialIndex = 0,
}: DocumentPreviewModalProps) {
  const [currentIndex, setCurrentIndex] = useState(() =>
    Math.max(0, Math.min(initialIndex, Math.max(0, attachments.length - 1)))
  );
  const [signedUrl, setSignedUrl] = useState<string | null>(null);
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(Boolean(isOpen && attachments[currentIndex]));
  const [error, setError] = useState<string | null>(null);

  // Image manipulation state
  const [scale, setScale] = useState(1);
  const [rotation, setRotation] = useState(0);

  const currentDoc = attachments[currentIndex];

  const isPdf = Boolean(
    (currentDoc?.file_type && currentDoc.file_type.toLowerCase().includes("pdf")) ||
    currentDoc?.file_name.toLowerCase().endsWith(".pdf")
  );

  // Keyboard navigation & Esc handler
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        onClose();
      } else if (e.key === "ArrowLeft") {
        setCurrentIndex((i) => Math.max(0, i - 1));
      } else if (e.key === "ArrowRight") {
        setCurrentIndex((i) => Math.min(attachments.length - 1, i + 1));
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, attachments.length, onClose]);

  useEffect(() => {
    if (!isOpen || !currentDoc) {
      return;
    }

    let isCancelled = false;
    let createdBlobUrl: string | null = null;
    const path = currentDoc.object_path || currentDoc.storage_path;

    getHrEmplocDocSignedUrl(path, { expiresIn: 600 })
      .then(async (url) => {
        if (isCancelled) return;
        setSignedUrl(url);

        if (isPdf) {
          try {
            const resp = await fetch(url);
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            const blob = await resp.blob();
            if (isCancelled) return;
            createdBlobUrl = URL.createObjectURL(blob);
            setBlobUrl(createdBlobUrl);
          } catch {
            // Fallback to direct signedUrl if blob fetch fails
            if (!isCancelled) setBlobUrl(null);
          }
        } else {
          setBlobUrl(null);
        }

        if (!isCancelled) {
          setIsLoading(false);
        }
      })
      .catch((err) => {
        if (!isCancelled) {
          setError(err instanceof Error ? err.message : "Failed to load document preview");
          setIsLoading(false);
        }
      });

    return () => {
      isCancelled = true;
      if (createdBlobUrl) {
        URL.revokeObjectURL(createdBlobUrl);
      }
    };
  }, [isOpen, currentDoc, isPdf]);

  if (!isOpen || !currentDoc) return null;

  const selectDoc = (idx: number) => {
    setCurrentIndex(idx);
    setSignedUrl(null);
    setBlobUrl(null);
    setIsLoading(true);
    setError(null);
    setScale(1);
    setRotation(0);
  };

  const handlePrev = () => {
    if (currentIndex > 0) {
      selectDoc(currentIndex - 1);
    }
  };

  const handleNext = () => {
    if (currentIndex < attachments.length - 1) {
      selectDoc(currentIndex + 1);
    }
  };

  const handleDownload = async () => {
    try {
      const path = currentDoc.object_path || currentDoc.storage_path;
      const downloadUrl = await getHrEmplocDocSignedUrl(path, { download: true, expiresIn: 300 });
      const link = document.createElement("a");
      link.href = downloadUrl;
      link.setAttribute("download", currentDoc.file_name);
      link.setAttribute("target", "_blank");
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    } catch (err) {
      alert("Failed to download file: " + (err instanceof Error ? err.message : String(err)));
    }
  };

  const zoomIn = () => setScale((s) => Math.min(3, Number((s + 0.25).toFixed(2))));
  const zoomOut = () => setScale((s) => Math.max(0.5, Number((s - 0.25).toFixed(2))));
  const rotateClockwise = () => setRotation((r) => (r + 90) % 360);
  const resetTransform = () => {
    setScale(1);
    setRotation(0);
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4 backdrop-blur-xs"
      onClick={onClose}
    >
      <div
        className="relative flex h-[92vh] w-full max-w-5xl flex-col rounded-xl bg-surface-base shadow-2xl overflow-hidden border border-border-default"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header bar */}
        <div className="flex h-14 shrink-0 items-center justify-between border-b border-border-default px-4 bg-surface-subtle">
          <div className="flex items-center gap-3 overflow-hidden">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-surface-hover text-text-secondary">
              <FileText className="h-4 w-4" />
            </div>
            <div className="overflow-hidden text-left">
              <h3 className="truncate text-sm font-semibold text-text-primary" title={currentDoc.file_name}>
                {currentDoc.file_name}
              </h3>
              <p className="text-2xs text-text-muted">
                Document {currentIndex + 1} of {attachments.length}
                {currentDoc.stage ? ` • ${currentDoc.stage === "correction" ? "Correction" : "Requirement"}` : ""}
              </p>
            </div>
          </div>

          {/* Controls */}
          <div className="flex items-center gap-2">
            {!isPdf && (
              <div className="flex items-center gap-1 rounded-lg border border-border-default bg-surface-base p-1 text-xs">
                <button
                  type="button"
                  onClick={zoomOut}
                  title="Zoom Out"
                  className="rounded p-1 hover:bg-surface-hover text-text-secondary"
                >
                  <ZoomOut className="h-3.5 w-3.5" />
                </button>
                <span className="min-w-10 text-center font-mono text-2xs text-text-muted">
                  {Math.round(scale * 100)}%
                </span>
                <button
                  type="button"
                  onClick={zoomIn}
                  title="Zoom In"
                  className="rounded p-1 hover:bg-surface-hover text-text-secondary"
                >
                  <ZoomIn className="h-3.5 w-3.5" />
                </button>
                <button
                  type="button"
                  onClick={rotateClockwise}
                  title="Rotate 90°"
                  className="rounded p-1 hover:bg-surface-hover text-text-secondary"
                >
                  <RotateCw className="h-3.5 w-3.5" />
                </button>
                {(scale !== 1 || rotation !== 0) && (
                  <button
                    type="button"
                    onClick={resetTransform}
                    className="rounded px-1.5 py-0.5 text-3xs text-accent-primary hover:bg-surface-hover font-medium"
                  >
                    Reset
                  </button>
                )}
              </div>
            )}

            <button
              type="button"
              onClick={handleDownload}
              title="Download Document"
              className="inline-flex items-center gap-1.5 rounded-lg border border-border-default bg-surface-base px-2.5 py-1.5 text-xs font-medium text-text-secondary hover:bg-surface-hover"
            >
              <Download className="h-3.5 w-3.5" />
              <span>Download</span>
            </button>

            <button
              type="button"
              onClick={onClose}
              title="Close Preview"
              className="rounded-lg p-1.5 text-text-muted hover:bg-surface-hover hover:text-text-primary"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        {/* Thumbnail switcher if multiple documents */}
        {attachments.length > 1 && (
          <div className="flex h-11 shrink-0 items-center gap-2 overflow-x-auto border-b border-border-subtle bg-surface-subtle/50 px-4">
            {attachments.map((doc, idx) => (
              <button
                key={doc.id || idx}
                type="button"
                onClick={() => selectDoc(idx)}
                className={`flex max-w-48 items-center gap-1.5 rounded-md px-2 py-1 text-2xs transition whitespace-nowrap ${
                  idx === currentIndex
                    ? "bg-accent-primary/10 font-semibold text-accent-primary border border-accent-primary/30"
                    : "text-text-muted hover:bg-surface-hover hover:text-text-primary border border-transparent"
                }`}
              >
                <span className="font-mono text-3xs">#{idx + 1}</span>
                <span className="truncate">{doc.file_name}</span>
              </button>
            ))}
          </div>
        )}

        {/* Body Viewer */}
        <div className="relative flex flex-1 items-center justify-center overflow-hidden bg-surface-canvas p-4">
          {/* Navigation overlay arrows */}
          {attachments.length > 1 && (
            <>
              <button
                type="button"
                onClick={handlePrev}
                disabled={currentIndex === 0}
                className="absolute left-4 top-1/2 -translate-y-1/2 z-10 rounded-full bg-surface-base/80 p-2 text-text-primary shadow-md backdrop-blur-xs disabled:opacity-30 hover:bg-surface-hover cursor-pointer border border-border-default"
                title="Previous Document"
              >
                <ChevronLeft className="h-5 w-5" />
              </button>
              <button
                type="button"
                onClick={handleNext}
                disabled={currentIndex === attachments.length - 1}
                className="absolute right-4 top-1/2 -translate-y-1/2 z-10 rounded-full bg-surface-base/80 p-2 text-text-primary shadow-md backdrop-blur-xs disabled:opacity-30 hover:bg-surface-hover cursor-pointer border border-border-default"
                title="Next Document"
              >
                <ChevronRight className="h-5 w-5" />
              </button>
            </>
          )}

          {isLoading ? (
            <div className="flex flex-col items-center gap-2 text-text-muted">
              <Loader2 className="h-8 w-8 animate-spin text-accent-primary" />
              <p className="text-xs">Loading document preview...</p>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center gap-3 p-6 text-center max-w-md">
              <AlertCircle className="h-8 w-8 text-status-danger" />
              <p className="text-sm font-medium text-text-primary">Unable to display preview</p>
              <p className="text-xs text-text-muted">{error}</p>
              <button
                type="button"
                onClick={handleDownload}
                className="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-brand-button px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand-button-hover shadow-xs cursor-pointer"
              >
                <Download className="h-3.5 w-3.5" />
                Download Original File
              </button>
            </div>
          ) : isPdf && (blobUrl || signedUrl) ? (
            <iframe
              src={blobUrl || signedUrl || ""}
              className="h-full w-full rounded-lg border border-border-subtle bg-white shadow-xs"
              title={currentDoc.file_name}
            />
          ) : signedUrl ? (
            <div className="flex h-full w-full items-center justify-center overflow-auto p-2">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={signedUrl}
                alt={currentDoc.file_name}
                style={{
                  transform: `scale(${scale}) rotate(${rotation}deg)`,
                  transition: "transform 0.15s ease-out",
                  maxWidth: "100%",
                  maxHeight: "100%",
                  objectFit: "contain",
                }}
                className="rounded shadow-xs select-none"
              />
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
