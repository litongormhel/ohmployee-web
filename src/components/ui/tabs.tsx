"use client";

import {
  createContext,
  useContext,
  useMemo,
  useState,
  type ButtonHTMLAttributes,
  type HTMLAttributes,
} from "react";

type TabsContextValue = {
  value: string;
  setValue: (value: string) => void;
};

const TabsContext = createContext<TabsContextValue | null>(null);

function useTabs() {
  const context = useContext(TabsContext);

  if (!context) {
    throw new Error("Tabs components must be rendered inside Tabs.");
  }

  return context;
}

type TabsProps = HTMLAttributes<HTMLDivElement> & {
  defaultValue: string;
};

export function Tabs({ defaultValue, children, ...props }: TabsProps) {
  const [value, setValue] = useState(defaultValue);
  const contextValue = useMemo(() => ({ value, setValue }), [value]);

  return (
    <TabsContext.Provider value={contextValue}>
      <div {...props}>{children}</div>
    </TabsContext.Provider>
  );
}

export function TabsList({ className = "", ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={`flex items-center gap-1.5 overflow-x-auto no-scrollbar scrollbar-none border-b border-border-subtle pb-3 ${className}`}
      role="tablist"
      {...props}
    />
  );
}

type TabsTriggerProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  value: string;
};

export function TabsTrigger({
  className = "",
  value,
  type = "button",
  ...props
}: TabsTriggerProps) {
  const tabs = useTabs();
  const isActive = tabs.value === value;

  return (
    <button
      aria-selected={isActive}
      className={`group inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border px-3.5 py-2 text-xs font-semibold whitespace-nowrap transition cursor-pointer ${
        isActive
          ? "border-brand-200 bg-brand-50 text-brand-900 shadow-2xs"
          : "border-transparent bg-transparent text-text-secondary hover:border-[var(--border-bold)] hover:bg-surface-hover hover:text-text-primary"
      } ${className}`}
      onClick={() => tabs.setValue(value)}
      role="tab"
      type={type}
      {...props}
    />
  );
}

type TabsContentProps = HTMLAttributes<HTMLDivElement> & {
  value: string;
};

export function TabsContent({ value, ...props }: TabsContentProps) {
  const tabs = useTabs();

  if (tabs.value !== value) {
    return null;
  }

  return <div role="tabpanel" {...props} />;
}
