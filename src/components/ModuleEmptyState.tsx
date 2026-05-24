import { getModuleByHref } from "@/lib/modules";

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
    <section className="mx-auto flex min-h-[420px] max-w-4xl flex-col justify-between rounded-lg border border-slate-200 bg-white p-8 shadow-sm">
      <div>
        <div className="mb-6 flex h-12 w-12 items-center justify-center rounded-lg border border-slate-200 bg-slate-50 text-slate-700">
          <Icon size={22} aria-hidden="true" />
        </div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
          Module shell
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-slate-950">
          {currentModule.title}
        </h1>
        <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-600">
          {currentModule.purpose}
        </p>
      </div>

      <div className="mt-10 rounded-lg border border-dashed border-slate-300 bg-slate-50 px-6 py-5">
        <h2 className="text-sm font-semibold text-slate-900">
          Ready for module definition
        </h2>
        <p className="mt-2 text-sm leading-6 text-slate-600">
          This page is intentionally blank until the Supabase contracts, RLS,
          and workflow requirements are approved. No records, charts, or actions
          are mocked here.
        </p>
      </div>
    </section>
  );
}
