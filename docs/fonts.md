# Scrawl fonts

In addition to Excalidraw's built-in fonts, Scrawl includes these typefaces for text on boards:

| Typeface | Intended use | Source |
|---|---|---|
| Inter | Clear, neutral interface and diagram text | [Inter](https://github.com/rsms/inter) |
| Plus Jakarta Sans | Rounded geometric headings and labels | [Plus Jakarta Sans](https://github.com/tokotype/PlusJakartaSans) |
| DM Sans | Friendly, compact labels and body text | [DM Sans](https://github.com/googlefonts/dm-fonts) |
| IBM Plex Mono | Code, technical notes and structured diagrams | [IBM Plex](https://github.com/IBM/plex) |
| Caveat | Informal, handwritten annotations | [Caveat](https://github.com/googlefonts/caveat) |

Choose the text tool, open **Font family → Show font picker**, and search for a typeface. The fonts are bundled for offline use, including their available language subsets. They are distributed under the SIL Open Font License 1.1; each font's license is included in `public/fonts/scrawl/` and the desktop app's resources.

The five fonts use Scrawl-specific numeric font identifiers in `.excalidraw` board files. Scrawl preserves them on save and reopen. Other Excalidraw-based apps may not recognize those identifiers and may use a fallback font. Export a PNG or SVG when visual consistency across other apps is important; keep the original board as an editable backup.

The editor is pinned to Excalidraw 0.18.1. Its font registry currently has no public extension API, so `scrawl-fonts-plugin.ts` extends the registry in both the editor and the conversion worker at build time. It deliberately fails the build if the registry changes; test font selection, reopen, and export before upgrading the editor. IDs in `public/fonts/scrawl/manifest.json` are persistent file-format values and must not be reassigned.
