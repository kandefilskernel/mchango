// Compilation de contrôle dans .next-check, sans toucher au .next du serveur de développement.
//   npm run build:check            (compile)
//   npm run build:check -- start   (sert la compilation sur le port 3002)
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const next = fileURLToPath(new URL("../node_modules/next/dist/bin/next", import.meta.url));
const args = process.argv[2] === "start" ? ["start", "-p", "3002"] : ["build"];
const { status } = spawnSync(process.execPath, [next, ...args], {
  stdio: "inherit",
  env: { ...process.env, NEXT_DIST_DIR: ".next-check" },
});
process.exit(status ?? 1);
