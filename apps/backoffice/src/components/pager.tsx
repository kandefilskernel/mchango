import Link from "next/link";

/** Taille des pages renvoyées par l'API (`/admin/users`, `/admin/groups`). */
export const PAGE_SIZE = 50;

/** Numéro de page lu dans l'URL (1 par défaut). */
export function pageFrom(value: unknown): number {
  const n = Number(value);
  return Number.isInteger(n) && n >= 1 && n <= 1000 ? n : 1;
}

/**
 * Sous une liste : « Résultats 51 à 100 » et Précédent / Suivant.
 * L'API ne renvoie pas de total : une page pleine laisse supposer qu'il y a une suite.
 */
export function Pager({
  path,
  params,
  page,
  count,
}: {
  path: string;
  /** Filtres en cours, gardés d'une page à l'autre. */
  params: Record<string, string>;
  page: number;
  count: number;
}) {
  const href = (p: number) => {
    const sp = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== ""));
    if (p > 1) sp.set("page", String(p));
    const qs = sp.toString();
    return qs ? `${path}?${qs}` : path;
  };
  const first = (page - 1) * PAGE_SIZE + 1;
  const hasNext = count === PAGE_SIZE;
  if (page === 1 && !hasNext) {
    return (
      <div className="list-foot muted">
        <span>{count === 0 ? "Aucun résultat" : `${count} résultat${count > 1 ? "s" : ""}`}</span>
      </div>
    );
  }
  return (
    <nav className="list-foot muted" aria-label="Pages">
      <span>{count === 0 ? "Aucun résultat sur cette page" : `Résultats ${first} à ${first + count - 1}`}</span>
      <span className="pager">
        <Link
          className="btn btn-secondary"
          href={href(page - 1)}
          aria-disabled={page === 1}
          tabIndex={page === 1 ? -1 : undefined}
        >
          ← Précédent
        </Link>
        <Link className="btn btn-secondary" href={href(page + 1)} aria-disabled={!hasNext} tabIndex={hasNext ? undefined : -1}>
          Suivant →
        </Link>
      </span>
    </nav>
  );
}
