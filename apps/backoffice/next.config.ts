import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Back-office : chaque page dépend de la personne connectée (cookie de session). Rien à
  // pré-générer : rendu à chaque requête, sans le mode « Cache Components ».
  cacheComponents: false,
  poweredByHeader: false,
};

export default nextConfig;
