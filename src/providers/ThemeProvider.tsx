"use client";

import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useSyncExternalStore,
} from "react";
import { useUserSettings } from "@/lib/queries/settings";

export type ThemeMode = "light" | "dark" | "system";

export const THEME_STORAGE_KEY = "ohmployee_theme_mode";

interface ThemeContextType {
  theme: ThemeMode;
  resolvedTheme: "light" | "dark";
  setTheme: (theme: ThemeMode) => void;
}

const ThemeContext = createContext<ThemeContextType>({
  theme: "light",
  resolvedTheme: "light",
  setTheme: () => {},
});

function getStoredTheme(): ThemeMode {
  if (typeof window === "undefined") return "light";
  try {
    const stored = localStorage.getItem(THEME_STORAGE_KEY) as ThemeMode | null;
    if (stored === "light" || stored === "dark" || stored === "system") {
      return stored;
    }
  } catch {}
  return "light";
}

function subscribeTheme(callback: () => void): () => void {
  window.addEventListener("storage", callback);
  window.addEventListener("ohmployee-theme-change", callback);
  return () => {
    window.removeEventListener("storage", callback);
    window.removeEventListener("ohmployee-theme-change", callback);
  };
}

function getSystemPref(): "light" | "dark" {
  if (typeof window === "undefined") return "light";
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function subscribeSystemPref(callback: () => void): () => void {
  const mq = window.matchMedia("(prefers-color-scheme: dark)");
  mq.addEventListener("change", callback);
  return () => mq.removeEventListener("change", callback);
}

function applyThemeToDocument(theme: ThemeMode, resolved: "light" | "dark") {
  if (typeof window === "undefined") return;
  const root = document.documentElement;
  const isDark = resolved === "dark";

  root.setAttribute("data-theme", theme);
  root.setAttribute("data-resolved-theme", resolved);
  root.style.colorScheme = isDark ? "dark" : "light";

  if (isDark) {
    root.classList.add("dark");
    root.classList.remove("light");
  } else {
    root.classList.add("light");
    root.classList.remove("dark");
  }
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const theme = useSyncExternalStore<ThemeMode>(
    subscribeTheme,
    getStoredTheme,
    () => "light"
  );

  const systemPref = useSyncExternalStore<"light" | "dark">(
    subscribeSystemPref,
    getSystemPref,
    () => "light"
  );

  const resolvedTheme: "light" | "dark" =
    theme === "dark" ? "dark" : theme === "system" ? systemPref : "light";


  const { data: settings } = useUserSettings();

  // If remote settings has a theme and differs from localStorage, sync to storage
  useEffect(() => {
    if (settings?.themeMode && typeof window !== "undefined") {
      const currentStored = localStorage.getItem(THEME_STORAGE_KEY);
      if (currentStored !== settings.themeMode) {
        localStorage.setItem(THEME_STORAGE_KEY, settings.themeMode);
        window.dispatchEvent(new Event("ohmployee-theme-change"));
      }
    }
  }, [settings?.themeMode]);

  // Synchronize DOM attributes and classList with theme & resolvedTheme
  useEffect(() => {
    applyThemeToDocument(theme, resolvedTheme);
  }, [theme, resolvedTheme]);

  const setTheme = useCallback((newTheme: ThemeMode) => {
    try {
      localStorage.setItem(THEME_STORAGE_KEY, newTheme);
      window.dispatchEvent(new Event("ohmployee-theme-change"));
    } catch {}
  }, []);

  return (
    <ThemeContext.Provider value={{ theme, resolvedTheme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error("useTheme must be used within a ThemeProvider");
  }
  return context;
}
