"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon, type IconName } from "./icons";

export interface NavItem {
  href: string;
  label: string;
  icon: IconName;
  badge?: number;
}

export interface NavSection {
  title: string;
  items: NavItem[];
}

/** Menu latéral par sections : la page courante est mise en évidence, les cas à traiter sont comptés. */
export function Nav({ sections }: { sections: NavSection[] }) {
  const pathname = usePathname();
  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
  return (
    <nav className="nav">
      {sections.map((s) => (
        <div key={s.title} style={{ display: "contents" }}>
          <div className="nav-section">{s.title}</div>
          {s.items.map((item) => (
            <Link key={item.href} href={item.href} className={isActive(item.href) ? "active" : undefined}>
              <Icon name={item.icon} size={19} />
              <span>{item.label}</span>
              {item.badge ? <span className="nav-badge">{item.badge > 99 ? "99+" : item.badge}</span> : null}
            </Link>
          ))}
        </div>
      ))}
    </nav>
  );
}
