import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Back-office : chaque page dépend de la personne connectée (cookie de session). Rien à
  // pré-générer : rendu à chaque requête, sans le mode « Cache Components ».
  cacheComponents: false,
  poweredByHeader: false,
  // Une compilation de contrôle (npm run build:check) écrit ailleurs que `next dev` :
  // partager `.next` avec le serveur de développement en marche casse ses pages.
  distDir: process.env.NEXT_DIST_DIR || ".next",
};

export default nextConfig;
