"use client";

import { useState, useCallback } from "react";
import type { HrEmplocQueue } from "@/lib/queries/hr_emploc";

export interface HrEmplocFilterState {
  queue: HrEmplocQueue;
  search: string;
  accountId: string;
  groupId: string;
}

export interface HrEmplocSavedView {
  id: string;
  name: string;
  filters: HrEmplocFilterState;
  createdAt: string;
  updatedAt: string;
}

const STORAGE_KEY = "ohm_hr_emploc_saved_views_v1";

function loadSavedViewsFromStorage(): HrEmplocSavedView[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        return parsed;
      }
    }
  } catch (e) {
    console.error("Failed to load saved views from localStorage:", e);
  }
  return [];
}

export function useHrEmplocSavedViews() {
  const [savedViews, setSavedViews] = useState<HrEmplocSavedView[]>(loadSavedViewsFromStorage);

  const persistViews = useCallback((views: HrEmplocSavedView[]) => {
    setSavedViews(views);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(views));
    } catch (e) {
      console.error("Failed to persist saved views to localStorage:", e);
    }
  }, []);

  const saveView = useCallback(
    (name: string, filters: HrEmplocFilterState): HrEmplocSavedView => {
      const now = new Date().toISOString();
      const newView: HrEmplocSavedView = {
        id:
          typeof crypto !== "undefined" && crypto.randomUUID
            ? crypto.randomUUID()
            : `view-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
        name: name.trim(),
        filters: { ...filters },
        createdAt: now,
        updatedAt: now,
      };

      const updated = [newView, ...savedViews];
      persistViews(updated);
      return newView;
    },
    [savedViews, persistViews]
  );

  const updateView = useCallback(
    (id: string, name: string, filters: HrEmplocFilterState) => {
      const now = new Date().toISOString();
      const updated = savedViews.map((v) =>
        v.id === id
          ? {
              ...v,
              name: name.trim() || v.name,
              filters: { ...filters },
              updatedAt: now,
            }
          : v
      );
      persistViews(updated);
    },
    [savedViews, persistViews]
  );

  const deleteView = useCallback(
    (id: string) => {
      const updated = savedViews.filter((v) => v.id !== id);
      persistViews(updated);
    },
    [savedViews, persistViews]
  );

  return {
    savedViews,
    saveView,
    updateView,
    deleteView,
  };
}
