"use client";

import { useEffect } from "react";
import Link from "next/link";
import { Icon } from "./icons";

/**
 * Page d'erreur partagée : message clair, « Réessayer », et la référence à donner à l'équipe technique.
 * En production, le message d'origine n'est jamais montré (il peut contenir des données sensibles).
 */
export function ErrorState({ error, retry }: { error: unknown; retry: () => void }) {
  const digest = error instanceof Error && "digest" in error ? String((error as { digest?: unknown }).digest ?? "") : "";
  useEffect(() => {
    console.error(error);
  }, [error]);
  return (
    <section className="card error-state" role="alert">
      <div className="error-icon">
        <Icon name="disputes" size={26} />
      </div>
      <h1>Cette page n&apos;a pas pu se charger</h1>
      <p className="muted">
        Le serveur Mchango ne répond pas ou a renvoyé une erreur. Réessayez dans un instant ; si cela continue,
        prévenez l&apos;équipe technique{digest ? " en donnant la référence ci-dessous" : ""}.
      </p>
      {digest && <p className="mono muted">Référence : {digest}</p>}
      <div className="actions">
        <button className="btn btn-primary" onClick={() => retry()}>
          Réessayer
        </button>
        <Link className="btn btn-secondary" href="/">
          Retour au tableau de bord
        </Link>
      </div>
    </section>
  );
}
