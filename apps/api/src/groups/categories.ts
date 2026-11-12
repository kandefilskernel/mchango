/**
 * Catégories de tontine (spec/categories.md). Un profil par catégorie, relu et versionné avec le code.
 *
 * Étape 1 (socle) : la catégorie est une étiquette de départ. Tous les profils ont les mêmes règles
 * qu'une tontine communautaire et `features` est vide ; les fonctions propres à chaque catégorie
 * arrivent aux étapes suivantes, sans changer ce contrat.
 */

export const GROUP_CATEGORIES = ['community', 'organization', 'workers', 'religion'] as const;
export type GroupCategory = (typeof GROUP_CATEGORIES)[number];
export const DEFAULT_CATEGORY: GroupCategory = 'community';

export interface CategoryProfile {
  code: GroupCategory;
  /** 1 = le plus simple, 4 = le plus évolué. */
  level: number;
  /** Textes en français : l'app les traduit elle-même, ceci sert de repli pour un code qu'elle ignore. */
  name: string;
  description: string;
  /** Règles par défaut et limites. Identiques pour toutes les catégories à l'étape 1. */
  rules: {
    maxMembersLimit: number;
    defaultMaxMembers: number;
    frequencies: ('daily' | 'weekly' | 'monthly')[];
    payoutModes: 'direct_to_beneficiary'[];
  };
  /** Fonctions propres à la catégorie, actives. Vide à l'étape 1. */
  features: string[];
}

const BASE_RULES: CategoryProfile['rules'] = {
  maxMembersLimit: 100,
  defaultMaxMembers: 30,
  frequencies: ['daily', 'weekly', 'monthly'],
  payoutModes: ['direct_to_beneficiary'],
};

export const CATEGORY_PROFILES: readonly CategoryProfile[] = [
  {
    code: 'community',
    level: 1,
    name: 'Communautaire',
    description: 'Voisins, amis, marchands, taxi-motos, associations de quartier.',
    rules: BASE_RULES,
    features: [],
  },
  {
    code: 'organization',
    level: 2,
    name: 'Organisation',
    description: 'Associations, coopératives, syndicats, ONG, mutuelles.',
    rules: BASE_RULES,
    features: [],
  },
  {
    code: 'workers',
    level: 3,
    name: 'Travailleurs',
    description: "Collègues d'un même employeur ou d'un même métier, fonctionnaires.",
    rules: BASE_RULES,
    features: [],
  },
  {
    code: 'religion',
    level: 4,
    name: 'Religion',
    description: 'Églises, paroisses, mosquées, communautés et leurs groupes.',
    rules: BASE_RULES,
    features: [],
  },
];

export const isGroupCategory = (v: string): v is GroupCategory =>
  (GROUP_CATEGORIES as readonly string[]).includes(v);
