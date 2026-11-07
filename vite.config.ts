// Web app build. Excalidraw loads its fonts from window.EXCALIDRAW_ASSET_PATH (a CDN
// by default); this serves them from the app itself, so the app needs no outside network.
import { cp } from "node:fs/promises";
import path from "node:path";
import react from "@vitejs/plugin-react";
import { type Plugin, defineConfig } from "vite";
import { scrawlFonts } from "./scrawl-fonts-plugin.ts";

const PACKAGE_DIST = "node_modules/@excalidraw/excalidraw/dist/prod";

function excalidrawAssets(): Plugin {
  let outDir = "";
  return {
    name: "excalidraw-assets",
    configResolved: (config) => void (outDir = config.build.outDir),
    // Dev serves node_modules as-is; the build copies the fonts to /fonts.
    transformIndexHtml: (_html, ctx) => [
      {
        tag: "script",
        children: `window.EXCALIDRAW_ASSET_PATH = ${JSON.stringify(ctx.server ? `/${PACKAGE_DIST}/` : "/")};`,
        injectTo: "head-prepend",
      },
    ],
    closeBundle: async () => {
      if (outDir) await cp(path.join(PACKAGE_DIST, "fonts"), path.join(outDir, "fonts"), { recursive: true });
    },
  };
}

// Excalidraw paints a few canvas accents in its own violet, outside the CSS theme
// (the dot over an arrow or line point under the cursor). Swap them for Scrawl's coral.
const EXCALIDRAW_VIOLETS: [string, string][] = [
  ["rgba(105, 101, 219, 0.4)", "rgba(229, 72, 77, 0.4)"],
  ['"#6965db"', '"#e5484d"'],
];

function excalidrawCoral(): Plugin {
  return {
    name: "excalidraw-coral",
    transform(code, id) {
      if (!id.includes("@excalidraw/excalidraw") || !EXCALIDRAW_VIOLETS.some(([from]) => code.includes(from))) return null;
      return EXCALIDRAW_VIOLETS.reduce((out, [from, to]) => out.replaceAll(from, to), code);
    },
  };
}

export default defineConfig({
  plugins: [scrawlFonts(), react(), excalidrawAssets(), excalidrawCoral()],
  define: { "process.env.IS_PREACT": JSON.stringify("false") },
  build: {
    outDir: "dist/client",
    emptyOutDir: true,
    chunkSizeWarningLimit: 5000,
    rolldownOptions: {
      onLog(level, log, handler) {
        if (log.code === "MODULE_LEVEL_DIRECTIVE") return; // "use client" in React libraries
        handler(level, log);
      },
    },
  },
  server: {
    proxy: { "/api": "http://localhost:3779", "/mcp": "http://localhost:3779" },
  },
});
