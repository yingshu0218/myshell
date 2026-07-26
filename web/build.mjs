import { cp, mkdir, rm } from "node:fs/promises";
import { join } from "node:path";

const root = new URL(".", import.meta.url).pathname;
const dist = join(root, "dist");
const vendor = join(dist, "vendor");

await rm(dist, { recursive: true, force: true });
await mkdir(vendor, { recursive: true });
await cp(join(root, "src"), dist, { recursive: true });

const files = [
  ["node_modules/@xterm/xterm/lib/xterm.js", "xterm.js"],
  ["node_modules/@xterm/xterm/css/xterm.css", "xterm.css"],
  ["node_modules/@xterm/addon-fit/lib/addon-fit.js", "xterm-addon-fit.js"],
  ["node_modules/prismjs/prism.js", "prism.js"],
  ["node_modules/prismjs/components/prism-bash.min.js", "prism-bash.js"],
  ["node_modules/prismjs/components/prism-json.min.js", "prism-json.js"],
  ["node_modules/prismjs/components/prism-yaml.min.js", "prism-yaml.js"],
  ["node_modules/prismjs/components/prism-toml.min.js", "prism-toml.js"],
  ["node_modules/prismjs/components/prism-go.min.js", "prism-go.js"],
  ["node_modules/prismjs/components/prism-swift.min.js", "prism-swift.js"],
  ["node_modules/prismjs/components/prism-csharp.min.js", "prism-csharp.js"],
  ["node_modules/prismjs/components/prism-javascript.min.js", "prism-javascript.js"],
  ["node_modules/prismjs/components/prism-typescript.min.js", "prism-typescript.js"],
  ["node_modules/prismjs/components/prism-markup.min.js", "prism-markup.js"],
  ["node_modules/prismjs/components/prism-css.min.js", "prism-css.js"],
  ["node_modules/prismjs/components/prism-docker.min.js", "prism-docker.js"],
  ["node_modules/prismjs/components/prism-sql.min.js", "prism-sql.js"],
  ["node_modules/prismjs/components/prism-markdown.min.js", "prism-markdown.js"]
];

for (const [source, target] of files) {
  await cp(join(root, source), join(vendor, target));
}
