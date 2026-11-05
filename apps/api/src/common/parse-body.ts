import { BadRequestException } from '@nestjs/common';
import type { z } from 'zod';

/** Valide un corps de requête ; renvoie 400 avec la liste des champs fautifs. */
export function parseBody<S extends z.ZodType>(schema: S, body: unknown): z.infer<S> {
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    throw new BadRequestException({
      message: 'Requête invalide.',
      errors: parsed.error.issues.map((i) => ({ field: i.path.join('.'), message: i.message })),
    });
  }
  return parsed.data;
}
