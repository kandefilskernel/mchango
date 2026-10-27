import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    globals: true,
    root: './',
    include: ['**/*.e2e-spec.ts'],
    setupFiles: ['./test/setup-env.ts'],
    // Base de test recréée à neuf avant chaque lancement (jamais la base de développement)
    globalSetup: ['./test/global-setup.ts'],
  },
});
