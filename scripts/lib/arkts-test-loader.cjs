const fs = require('node:fs');
const path = require('node:path');
const ts = require(process.env.ARKTS_TEST_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/ohpm/node_modules/typescript');

function loader(mocks = {}) {
  const modules = new Map();
  function load(filename) {
    if (Object.hasOwn(mocks, filename)) return mocks[filename];
    if (modules.has(filename)) return modules.get(filename).exports;
    const module = { exports: {} };
    modules.set(filename, module);
    const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: {
        target: ts.ScriptTarget.ES2020,
        module: ts.ModuleKind.CommonJS,
        experimentalDecorators: true
      }
    }).outputText;
    const localRequire = (id) => {
      if (Object.hasOwn(mocks, id)) return mocks[id];
      if (!id.startsWith('.')) throw new Error('Unmocked native import: ' + id);
      return load(path.resolve(path.dirname(filename), id + '.ets'));
    };
    new Function('require', 'exports', 'module', 'ObservedV2', 'Trace', 'Computed', 'Scroller', 'canIUse', output)(
      localRequire, module.exports, module, (value) => value, () => {}, () => {}, class {}, mocks.canIUse || (() => true));
    return module.exports;
  }
  return load;
}

module.exports = { loader };
