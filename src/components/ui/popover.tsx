"use client";

import React, {
  createContext,
  useContext,
  useState,
  useRef,
  useEffect,
  type ReactNode,
  type RefObject,
} from "react";

interface PopoverContextType {
  open: boolean;
  setOpen: (open: boolean) => void;
  triggerRef: RefObject<HTMLElement | null>;
}

const PopoverContext = createContext<PopoverContextType | undefined>(undefined);

export function usePopover() {
  const context = useContext(PopoverContext);
  if (!context) {
    throw new Error("usePopover must be used within a Popover");
  }
  return context;
}

export interface PopoverProps {
  children: ReactNode;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

export function Popover({ children, open: controlledOpen, onOpenChange }: PopoverProps) {
  const [uncontrolledOpen, setUncontrolledOpen] = useState(false);
  const triggerRef = useRef<HTMLElement | null>(null);

  const isControlled = controlledOpen !== undefined;
  const open = isControlled ? controlledOpen : uncontrolledOpen;

  const setOpen = (nextOpen: boolean) => {
    if (!isControlled) {
      setUncontrolledOpen(nextOpen);
    }
    onOpenChange?.(nextOpen);
  };

  return (
    <PopoverContext.Provider value={{ open, setOpen, triggerRef }}>
      <div className="relative inline-block">{children}</div>
    </PopoverContext.Provider>
  );
}

export interface PopoverTriggerProps {
  children: ReactNode;
  asChild?: boolean;
  className?: string;
  [key: string]: unknown;
}

export function PopoverTrigger({
  children,
  asChild,
  className,
  ...props
}: PopoverTriggerProps) {
  const { open, setOpen, triggerRef } = usePopover();

  const handleClick = (e: React.MouseEvent) => {
    if (typeof props.onClick === "function") {
      (props.onClick as (e: React.MouseEvent) => void)(e);
    }
    if (!e.defaultPrevented) {
      setOpen(!open);
    }
  };

  if (asChild && React.isValidElement(children)) {
    const childElement = children as React.ReactElement<{
      ref?: React.Ref<HTMLElement>;
      onClick?: (e: React.MouseEvent) => void;
      [key: string]: unknown;
    }>;

    return React.cloneElement(childElement, {
      ref: triggerRef as React.Ref<HTMLElement>,
      onClick: (e: React.MouseEvent) => {
        childElement.props.onClick?.(e);
        handleClick(e);
      },
      "aria-haspopup": "dialog",
      "aria-expanded": open,
      ...props,
    });
  }

  return (
    <button
      ref={triggerRef as React.Ref<HTMLButtonElement>}
      type="button"
      aria-haspopup="dialog"
      aria-expanded={open}
      onClick={handleClick}
      className={className}
      {...props}
    >
      {children}
    </button>
  );
}

export interface PopoverContentProps {
  children: ReactNode;
  className?: string;
  align?: "start" | "center" | "end";
  sideOffset?: number;
}

export function PopoverContent({
  children,
  className = "",
  align = "start",
  sideOffset = 4,
}: PopoverContentProps) {
  const { open, setOpen, triggerRef } = usePopover();
  const contentRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;

    function handleClickOutside(event: MouseEvent) {
      if (
        contentRef.current &&
        !contentRef.current.contains(event.target as Node) &&
        triggerRef.current &&
        !triggerRef.current.contains(event.target as Node)
      ) {
        setOpen(false);
      }
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setOpen(false);
      }
    }

    document.addEventListener("mousedown", handleClickOutside);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [open, setOpen, triggerRef]);

  if (!open) return null;

  const alignClasses =
    align === "end"
      ? "right-0"
      : align === "center"
      ? "left-1/2 -translate-x-1/2"
      : "left-0";

  return (
    <div
      ref={contentRef}
      role="dialog"
      style={{ marginTop: `${sideOffset}px` }}
      className={`absolute z-50 mt-1 w-80 rounded-lg border border-border-default bg-surface-base p-4 shadow-xl animate-in fade-in zoom-in-95 duration-150 ${alignClasses} ${className}`}
    >
      {children}
    </div>
  );
}
