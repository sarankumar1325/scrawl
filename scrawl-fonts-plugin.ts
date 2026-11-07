// Excalidraw 0.18.1 does not expose its font registry as a public API.
// Extend its pinned, bundled registry at build time; fail closed on package changes.
// IDs are persistent file-format values: never reuse or change them.
import { readFileSync } from 'node:fs';
import type { Plugin } from 'vite';

type Font = { name: string; id: number; metrics: { unitsPerEm: number; ascender: number; descender: number; lineHeight: number }; subsets: { file: string; range: string }[] };
const fonts = JSON.parse(readFileSync(new URL('./public/fonts/scrawl/manifest.json', import.meta.url), 'utf8')) as Font[];
const families = fonts.map(font => `${JSON.stringify(font.name)}:${font.id}`).join(',');
const descriptors = (font: Font) => font.subsets.map(({ file, range }) =>
  `{uri:new URL(${JSON.stringify(`/fonts/scrawl/${file}`)},window.location.origin).href,descriptors:{unicodeRange:${JSON.stringify(range)}}}`
).join(',');

export function scrawlFonts(): Plugin {
  let patched = false;
  let building = false;
  return {
    name: 'scrawl-fonts-registry',
    enforce: 'pre',
    configResolved(config) { building = config.command === 'build'; },
    transform(source, id) {
      if (!id.includes('/@excalidraw/excalidraw/dist/')) return null;
      const devAnchor = 'var FONT_FAMILY = {';
      const prodAnchor = 'Ie={Virgil:1,Helvetica:2,Cascadia:3,Excalifont:5,Nunito:6,"Lilita One":7,"Comic Shanns":8,"Liberation Sans":9}';
      let code = source;
      if (source.includes(devAnchor)) {
        const init = '    init("Cascadia", ...CascadiaFontFaces);';
        if (!source.includes(init)) throw new Error('Unsupported Excalidraw development font registry');
        const inserts = fonts.map(font => `    FONT_METADATA[${font.id}]={metrics:${JSON.stringify(font.metrics)}};\n    init(${JSON.stringify(font.name)},${descriptors(font)});`).join('\n');
        code = source.replace(devAnchor, `${devAnchor}\n${families},`).replace(init, `${inserts}\n${init}`);
      } else if (source.includes(prodAnchor)) {
        const init = 'n("Cascadia",...Gd)';
        if (!source.includes(init)) throw new Error('Unsupported Excalidraw production font registry');
        const inserts = fonts.map(font => `(Fr[${font.id}]={metrics:${JSON.stringify(font.metrics)}}),n(${JSON.stringify(font.name)},${descriptors(font)})`).join(',');
        code = source.replace(prodAnchor, prodAnchor.slice(0, -1) + `,${families}}`).replace(init, `${inserts},${init}`);
      } else {
        return null;
      }
      patched = true;
      return { code, map: null };
    },
    buildEnd(error) {
      if (building && !error && !patched) throw new Error('Scrawl fonts could not be registered; check the pinned Excalidraw version.');
    },
  };
}
