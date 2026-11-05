/** Langues de Mchango (users.language). Le français est la langue par défaut. */
export const LANGUAGES = ['fr', 'sw', 'ln', 'en'] as const;
export type Language = (typeof LANGUAGES)[number];

export const asLanguage = (value: string | null | undefined): Language =>
  (LANGUAGES as readonly string[]).includes(value ?? '') ? (value as Language) : 'fr';
