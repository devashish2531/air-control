"use client";

import {
  useEffect,
  useRef,
  type CSSProperties,
  type ElementType,
  type HTMLAttributes,
  type JSX,
  type ReactNode,
} from "react";

/**
 * Any HTML tag name Reveal is allowed to render as. Kept literal (rather than
 * a bare `string`) so a typo like `as="sectoin"` is a type error.
 */
type RevealTag = keyof JSX.IntrinsicElements;

type RevealProps = {
  /** Tag to render. Defaults to "div". */
  as?: RevealTag;
  /** Stagger delay in ms, written to the `--reveal-delay` CSS custom property. */
  delay?: number;
  className?: string;
  id?: string;
  children?: ReactNode;
} & Omit<
  HTMLAttributes<HTMLElement>,
  "as" | "className" | "id" | "children" | "style"
>;

/**
 * One IntersectionObserver shared by every <Reveal>, created lazily on first
 * use. Splitting observers per-instance would mean dozens of scroll listeners
 * for a page with this many reveal blocks.
 */
let sharedObserver: IntersectionObserver | null = null;

function getSharedObserver(): IntersectionObserver | null {
  if (typeof IntersectionObserver === "undefined") {
    return null;
  }
  if (!sharedObserver) {
    sharedObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-inview");
            sharedObserver?.unobserve(entry.target);
          }
        }
      },
      { threshold: 0.15, rootMargin: "0px 0px -8% 0px" },
    );
  }
  return sharedObserver;
}

/**
 * Fades/slides its children in the first time they scroll into view. Renders
 * server-side with `data-reveal` already set, so content is present in the
 * initial HTML for SEO and no-JS clients; see the `[data-reveal]` base rule
 * and the `<noscript>` fallback in `layout.tsx`.
 */
export function Reveal({
  as,
  delay,
  className,
  id,
  children,
  ...rest
}: RevealProps) {
  const Tag = (as ?? "div") as ElementType;
  const ref = useRef<HTMLElement | null>(null);

  useEffect(() => {
    const node = ref.current;
    if (!node) {
      return;
    }

    const observer = getSharedObserver();
    if (!observer) {
      // No IntersectionObserver support: show content immediately.
      node.classList.add("is-inview");
      return;
    }

    observer.observe(node);
    return () => {
      observer.unobserve(node);
    };
  }, []);

  const style: CSSProperties | undefined =
    delay === undefined
      ? undefined
      : ({ "--reveal-delay": `${delay}ms` } as CSSProperties);

  return (
    <Tag ref={ref} id={id} className={className} data-reveal="" style={style} {...rest}>
      {children}
    </Tag>
  );
}
