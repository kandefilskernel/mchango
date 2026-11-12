"use client";

import { ErrorState } from "@/components/error-state";

/** Erreur dans une page : le menu reste visible, seule la page est remplacée. */
export default function Error({ error, retry }: { error: unknown; retry: () => void }) {
  return <ErrorState error={error} retry={retry} />;
}
