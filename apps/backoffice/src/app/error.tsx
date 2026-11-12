"use client";

import { ErrorState } from "@/components/error-state";

/** Erreur avant même d'afficher le menu (ex. API injoignable au chargement du back-office). */
export default function Error({ error, retry }: { error: unknown; retry: () => void }) {
  return (
    <main className="main">
      <ErrorState error={error} retry={retry} />
    </main>
  );
}
