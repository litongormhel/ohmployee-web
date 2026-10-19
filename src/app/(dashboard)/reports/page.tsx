"use client";

import { Suspense, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ModuleEmptyState } from "@/components/ModuleEmptyState";

function ReportsPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const tab = searchParams.get("tab");

  useEffect(() => {
    if (tab === "qa_center" || tab === "qa") {
      router.replace("/more?open=qa_center");
    } else if (tab === "permission_drift" || tab === "drift") {
      router.replace("/more?open=permission_drift");
    }
  }, [tab, router]);

  return <ModuleEmptyState href="/reports" />;
}

export default function ReportsPage() {
  return (
    <Suspense fallback={<div className="h-64 animate-pulse bg-surface-base rounded-xl" />}>
      <ReportsPageContent />
    </Suspense>
  );
}
