"use client";

import { useState } from "react";
import { AlertCircle, Building2, MapPin, RefreshCw, Sliders, UsersRound } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DetailDrawer } from "@/components/shared/DetailDrawer";
import {
  type PlantillaStoreStaffingRow,
  deriveStaffingRisk,
} from "@/lib/queries/plantilla";
import {
  type StoreVacancyItem,
  useStoreVacancies,
} from "@/lib/queries/quota";
import { ReviseHeadcountQuotaModal } from "@/components/modals/ReviseHeadcountQuotaModal";
import { RequestHeadcountAdjustmentModal } from "@/components/modals/RequestHeadcountAdjustmentModal";

export interface StoreStaffingDrawerProps {
  storeRow: PlantillaStoreStaffingRow | null;
  onClose: () => void;
  canReviseQuota: boolean;
  canRequestAdjustment: boolean;
}

function formatFillRate(fillRate: number | null): string {
  if (fillRate === null) return "—";
  return `${(fillRate * 100).toFixed(1)}%`;
}

export function StoreStaffingDrawer({
  storeRow,
  onClose,
  canReviseQuota,
  canRequestAdjustment,
}: StoreStaffingDrawerProps) {
  const [selectedVacancyForRevise, setSelectedVacancyForRevise] = useState<StoreVacancyItem | null>(null);
  const [selectedVacancyForRequest, setSelectedVacancyForRequest] = useState<StoreVacancyItem | null>(null);

  const {
    data: vacancies,
    isLoading: isVacanciesLoading,
    isError: isVacanciesError,
    error: vacanciesError,
    refetch: refetchVacancies,
  } = useStoreVacancies(storeRow ? storeRow.storeId : null);

  if (!storeRow) return null;

  const risk = deriveStaffingRisk(storeRow);

  return (
    <>
      <DetailDrawer
        isOpen={!!storeRow}
        onClose={onClose}
        widthClass="w-[var(--drawer-width-lg)] max-w-full"
        badge={
          <Badge className="font-mono text-xs font-semibold bg-gray-900 text-white border-none py-1 px-2.5">
            {storeRow.storeCode ?? "STORE"}
          </Badge>
        }
        title={storeRow.storeName ?? "Store Staffing Overview"}
        subtitle={
          <>
            <MapPin className="h-3 w-3 shrink-0 text-gray-400" />
            <span className="truncate">
              {[storeRow.accountName, storeRow.region].filter(Boolean).join(" / ") || "Store Location"}
            </span>
          </>
        }
      >
        <div className="space-y-6">
          {/* Store Overview Cards */}
          <div className="rounded-lg border border-border-default bg-surface-muted p-4 space-y-3">
            <div className="flex items-center justify-between text-xs font-semibold text-text-secondary uppercase tracking-wider">
              <span className="flex items-center gap-1.5">
                <Building2 className="h-4 w-4 text-text-muted" />
                Store Staffing Metrics
              </span>
              <span className="font-mono text-[11px] text-text-muted">
                MFR: {formatFillRate(storeRow.fillRate)}
              </span>
            </div>

            <div className="grid grid-cols-4 gap-2 text-center">
              <div className="rounded border border-border-subtle bg-surface-base p-2.5">
                <div className="text-[10px] font-semibold uppercase text-text-muted">Actual</div>
                <div className="text-lg font-bold font-mono text-text-primary">{storeRow.onboardCount}</div>
              </div>
              <div className="rounded border border-border-subtle bg-surface-base p-2.5">
                <div className="text-[10px] font-semibold uppercase text-text-muted">Pipeline</div>
                <div className="text-lg font-bold font-mono text-amber-700">{storeRow.hrPipelineCount}</div>
              </div>
              <div className="rounded border border-border-subtle bg-surface-base p-2.5">
                <div className="text-[10px] font-semibold uppercase text-text-muted">Open Vacancy</div>
                <div className="text-lg font-bold font-mono text-blue-700">{storeRow.openHeadcount}</div>
              </div>
              <div className="rounded border border-border-subtle bg-surface-base p-2.5">
                <div className="text-[10px] font-semibold uppercase text-text-muted">Required</div>
                <div className="text-lg font-bold font-mono text-text-primary">{storeRow.requiredHeadcount}</div>
              </div>
            </div>

            {/* Risk & SLA badges */}
            <div className="flex items-center gap-2 pt-1 border-t border-border-subtle">
              <span className="text-xs text-text-muted">Status:</span>
              {risk.staffingRisk && (
                <StatusBadge
                  variant={risk.staffingRisk === "Optimal" ? "success" : "warning"}
                  text={risk.staffingRisk}
                />
              )}
              {risk.slaBadge && (
                <StatusBadge
                  variant={risk.slaBadge === "Within SLA" ? "neutral" : "danger"}
                  text={risk.slaBadge}
                />
              )}
            </div>
          </div>

          {/* Vacancy Headcount Quotas Section */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-text-secondary">
                <Sliders className="h-4 w-4 text-text-muted" />
                <span>Position Quotas & VCodes</span>
              </div>
              <button
                type="button"
                onClick={() => refetchVacancies()}
                className="text-[11px] text-text-muted hover:text-text-primary inline-flex items-center gap-1 transition-colors"
                title="Refresh position quotas"
              >
                <RefreshCw className="h-3 w-3" />
                Refresh
              </button>
            </div>

            {isVacanciesLoading ? (
              <div className="space-y-3 animate-pulse">
                <div className="h-20 rounded-md bg-surface-muted" />
                <div className="h-20 rounded-md bg-surface-muted" />
              </div>
            ) : isVacanciesError ? (
              <div className="flex items-center gap-2 rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
                <AlertCircle className="h-4 w-4 shrink-0 text-red-600" />
                <span>Error loading position quotas: {vacanciesError?.message}</span>
              </div>
            ) : (vacancies ?? []).length === 0 ? (
              <div className="rounded-md border border-border-default bg-surface-muted p-6 text-center">
                <UsersRound className="mx-auto h-8 w-8 text-text-muted" />
                <h4 className="mt-2 text-xs font-semibold text-text-primary">No Direct Vacancies</h4>
                <p className="mt-1 text-[11px] text-text-muted">
                  No active vacancy positions are registered under this store code.
                </p>
              </div>
            ) : (
              <div className="space-y-3">
                {(vacancies ?? []).map((vac) => (
                  <div
                    key={vac.id}
                    className="rounded-lg border border-border-default bg-surface-base p-4 space-y-3 hover:border-border-subtle transition-colors shadow-xs"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-xs font-semibold text-text-primary bg-mono-pill-surface border border-mono-pill-ring rounded px-1.5 py-0.5">
                            {vac.vcode}
                          </span>
                          <span className="text-xs font-semibold text-text-primary">
                            {vac.position ?? "General Staff"}
                          </span>
                        </div>
                        <div className="mt-1 flex items-center gap-2 text-xs text-text-muted">
                          <span>Status: {vac.status ?? "Active"}</span>
                        </div>
                      </div>

                      <div className="text-right">
                        <div className="text-[10px] uppercase font-semibold text-text-muted">Quota</div>
                        <div className="font-mono text-base font-bold text-text-primary">
                          {vac.requiredHeadcount} slot{vac.requiredHeadcount !== 1 ? "s" : ""}
                        </div>
                      </div>
                    </div>

                    {/* Action Bar for this VCode */}
                    <div className="flex items-center justify-end gap-2 border-t border-border-subtle pt-3">
                      {canReviseQuota && (
                        <button
                          type="button"
                          onClick={() => setSelectedVacancyForRevise(vac)}
                          className="inline-flex items-center gap-1 rounded border border-border-default bg-surface-base px-2.5 py-1 text-xs font-medium text-text-primary hover:bg-surface-hover transition-colors shadow-xs"
                        >
                          Adjust Quota
                        </button>
                      )}

                      {canRequestAdjustment && (
                        <button
                          type="button"
                          onClick={() => setSelectedVacancyForRequest(vac)}
                          className="inline-flex items-center gap-1 rounded bg-brand-600 px-2.5 py-1 text-xs font-semibold text-white hover:bg-brand-700 transition-colors shadow-xs"
                        >
                          Request HC Adjustment
                        </button>
                      )}

                      {!canReviseQuota && !canRequestAdjustment && (
                        <span className="text-[11px] text-text-muted italic">
                          Read-only quota view
                        </span>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </DetailDrawer>

      {/* Revise Headcount Quota Modal */}
      {selectedVacancyForRevise && (
        <ReviseHeadcountQuotaModal
          isOpen={!!selectedVacancyForRevise}
          onClose={() => setSelectedVacancyForRevise(null)}
          vcode={selectedVacancyForRevise.vcode}
          storeName={storeRow.storeName}
          positionTitle={selectedVacancyForRevise.position}
          initialQuota={selectedVacancyForRevise.requiredHeadcount}
          onSuccess={() => {
            refetchVacancies();
          }}
        />
      )}

      {/* Request Headcount Adjustment Modal */}
      {selectedVacancyForRequest && (
        <RequestHeadcountAdjustmentModal
          isOpen={!!selectedVacancyForRequest}
          onClose={() => setSelectedVacancyForRequest(null)}
          vcode={selectedVacancyForRequest.vcode}
          storeName={storeRow.storeName}
          positionTitle={selectedVacancyForRequest.position}
          initialQuota={selectedVacancyForRequest.requiredHeadcount}
          accountId={selectedVacancyForRequest.accountId}
          storeId={selectedVacancyForRequest.storeId ?? storeRow.storeId}
          positionId={selectedVacancyForRequest.positionId}
          onSuccess={() => {
            refetchVacancies();
          }}
        />
      )}
    </>
  );
}
