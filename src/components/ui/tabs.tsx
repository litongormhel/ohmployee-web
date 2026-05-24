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
      className={`inline-flex rounded-lg border border-gray-200 bg-white p-1 ${className}`}
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
      className={`rounded-md px-3 py-1.5 text-sm transition-colors ${
        isActive
          ? "bg-blue-600 text-white"
          : "text-gray-600 hover:bg-gray-100 hover:text-gray-900"
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
