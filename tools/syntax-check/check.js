const fs = require('fs');
const path = require('path');
const Parser = require('web-tree-sitter');

async function main() {
  await Parser.init();
  const wasm = path.join(__dirname, 'node_modules/tree-sitter-wasms/out/tree-sitter-swift.wasm');
  // 用法：npm i && node check.js ../../MusicHall
  const lang = await Parser.Language.load(wasm);
  const parser = new Parser();
  parser.setLanguage(lang);

  const root = process.argv[2];
  const files = [];
  (function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.swift')) files.push(full);
    }
  })(root);

  let problems = 0;
  for (const file of files.sort()) {
    const source = fs.readFileSync(file, 'utf8');
    const tree = parser.parse(source);
    const errs = [];
    const missing = (node) => (typeof node.isMissing === 'function' ? node.isMissing() : !!node.isMissing);
    if ((typeof tree.rootNode.hasError === 'function' ? tree.rootNode.hasError() : tree.rootNode.hasError)) {
      (function visit(node) {
        if (node.type === 'ERROR' || missing(node)) {
          errs.push(node);
          return;
        }
        for (const child of node.children) visit(child);
      })(tree.rootNode);
    }
    if (errs.length) {
      problems += errs.length;
      console.log('\n### ' + path.relative(root, file));
      for (const err of errs.slice(0, 6)) {
        const text = source.slice(err.startIndex, Math.min(err.endIndex, err.startIndex + 120)).replace(/\n/g, ' ⏎ ');
        console.log(`  line ${err.startPosition.row + 1}:${err.startPosition.column + 1} [${err.type}${err.isMissing ? '/missing' : ''}] ${text}`);
      }
    }
  }
  console.log(`\nfiles=${files.length} problems=${problems}`);
}

main().catch((error) => { console.error(error); process.exit(1); });
