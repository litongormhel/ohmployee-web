import { getModuleByHref } from "@/lib/modules";
import { AdminPageHeader } from "@/components/shared/AdminPageHeader";
import { MetricCard } from "@/components/shared/MetricCard";

type ModuleEmptyStateProps = {
  href: string;
};

export function ModuleEmptyState({ href }: ModuleEmptyStateProps) {
  const currentModule = getModuleByHref(href);

  if (!currentModule) {
    return null;
  }

  const Icon = currentModule.icon;

  return (
    <div className="flex h-full min-h-[calc(100vh-7rem)] flex-col gap-4 text-gray-900">
      <AdminPageHeader
        title={currentModule.title}
        subtitle={currentModule.purpose}
        icon={Icon}
        readOnly
      />

      <section
        aria-label={`${currentModule.title} readiness metrics`}
        className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
      >
        <MetricCard label="Records" value={0} helperText="Awaiting approved Supabase contract" badgeLabel="Scoped" />
        <MetricCard label="Actions" value={0} helperText="No mutations exposed for this module" badgeLabel="Locked" />
        <MetricCard label="Filters" value={0} helperText="Filter model pending workflow definition" badgeLabel="Pending" />
        <MetricCard label="Routes" value={1} helperText="Module route is available" badgeLabel="Shell" />
      </section>

      <section className="flex min-h-0 flex-1 flex-col rounded-md border border-table-rule-section bg-table-row">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-table-rule-section px-4 py-3">
          <div>
            <h2 className="text-base font-semibold text-table-text">
              Module Workspace
            </h2>
            <p className="mt-1 text-sm text-table-text-muted">
              This module keeps the admin layout ready without mocking records or workflow actions.
            </p>
          </div>
          <div className="text-sm font-medium text-table-text-muted">
            Backend-authoritative behavior required
          </div>
        </div>

        <div className="flex flex-1 items-center justify-center px-4 py-16 text-center">
          <div className="max-w-2xl">
            <div className="mx-auto mb-5 flex h-12 w-12 items-center justify-center rounded-md border border-border-default bg-surface-muted text-text-secondary">
              <Icon size={22} aria-hidden="true" />
            </div>
            <h2 className="text-xl font-semibold text-text-primary">
              Ready for module definition
            </h2>
            <p className="mt-3 text-base leading-7 text-text-secondary">
              This page is intentionally blank until the Supabase contracts,
              RLS, and workflow requirements are approved. No records, charts,
              or actions are mocked here.
            </p>
          </div>
        </div>
      </section>
    </div>
  );
}
