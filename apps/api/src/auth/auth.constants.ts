/** Durée de validité d'un code SMS. */
export const OTP_TTL_SECONDS = 5 * 60;
/** Essais par code ; au-delà le code est détruit. */
export const OTP_MAX_ATTEMPTS = 5;
/** Codes envoyés à un même numéro par fenêtre (protège la facture SMS et le titulaire). */
export const OTP_MAX_PER_PHONE = 3;
export const OTP_PHONE_WINDOW_SECONDS = 15 * 60;

/** Validité du jeton obtenu après le code SMS ; il ne sert qu'une fois. */
export const OTP_TOKEN_TTL_SECONDS = 10 * 60;

/** Échecs de PIN avant verrouillage, et durée du verrouillage. */
export const PIN_MAX_ATTEMPTS = 5;
export const PIN_LOCK_MINUTES = 30;

/** Validité d'un défi de connexion. */
export const CHALLENGE_TTL_SECONDS = 2 * 60;

/** Validité d'un jeton d'accès (pas de jeton de rafraîchissement : l'appareil re-signe un défi). */
export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
