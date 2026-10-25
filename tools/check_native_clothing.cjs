// Optional local integration audit. Native game sources stay in memory and
// are never copied into this project or its installable mod.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {spawnSync} = require('child_process');
const parser = require('luaparse');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
function option(name, fallback) {
  const index = args.indexOf(name);
  if (index === -1) return fallback;
  if (!args[index + 1]) throw new Error('Missing value for ' + name);
  return args[index + 1];
}
const gameZip = option('--game-zip', "D:/SteamLibrary/steamapps/common/Don't Starve Together/data/databundles/scripts.zip");
const runtimeFile = path.resolve(root, option('--runtime', 'mod/scripts/krypton_darkform_visual.lua'));
const nativeNames = ['scripts/clothing.lua', 'scripts/components/skinner.lua', 'scripts/constants.lua', 'scripts/prefabskin.lua', 'scripts/skinsutils.lua'];
const extraction = spawnSync('python', ['-c',
  'import sys,json,zipfile; z=zipfile.ZipFile(sys.argv[1]); print(json.dumps({n:z.read(n).decode("utf-8") for n in json.loads(sys.argv[2])}))',
  gameZip, JSON.stringify(nativeNames)], {encoding: 'utf8', maxBuffer: 12 * 1024 * 1024});
if (extraction.status !== 0) throw new Error(extraction.stderr || 'Could not read the installed game archive');
const sources = JSON.parse(extraction.stdout);
function extract(file, predicate, description) {
  const source = sources[file];
  const node = parser.parse(source, {luaVersion: '5.1', ranges: true}).body.find(predicate);
  if (!node) throw new Error('Missing native ' + description + ' in ' + file);
  return source.slice(node.range[0], node.range[1]);
}
function assigned(node, name) {
  return node.type === 'AssignmentStatement' && node.variables.some(v => v.type === 'Identifier' && v.name === name);
}
const nativeChunks = {
  native_clothing: sources['scripts/clothing.lua'],
  native_skin_helper: extract('scripts/components/skinner.lua',
    n => n.type === 'LocalStatement' && n.variables.some(v => v.name === 'clothing_order'), 'clothing iteration order') + '\n' + extract('scripts/components/skinner.lua',
    n => n.type === 'FunctionDeclaration' && n.identifier?.name === 'SetSkinsOnAnim', 'SetSkinsOnAnim'),
  native_constants: extract('scripts/constants.lua', n => assigned(n, 'SKIN_TYPES_THAT_RECEIVE_CLOTHING'), 'clothing modes'),
  native_base_tables: ['BASE_TORSO_TUCK', 'BASE_ALTERNATE_FOR_BODY', 'BASE_ALTERNATE_FOR_SKIRT',
    'ONE_PIECE_SKIRT', 'BASE_LEGS_SIZE', 'BASE_FEET_SIZE'].map(name =>
      extract('scripts/prefabskin.lua', n => assigned(n, name), name)).join('\n'),
  native_build_selector: extract('scripts/skinsutils.lua',
    n => n.type === 'FunctionDeclaration' && n.identifier?.name === 'GetBuildForItem', 'GetBuildForItem'),
};
const projectFiles = {
  'mod/scripts/krypton_darkform_visual.lua': fs.readFileSync(runtimeFile, 'utf8'),
  'mod/scripts/krypton_darkform.lua': fs.readFileSync(path.join(root, 'mod/scripts/krypton_darkform.lua'), 'utf8'),
};
const report = {
  kind: 'installed-native-clothing-helper-contracts',
  runtime: path.relative(root, runtimeFile).replaceAll('\\', '/'),
  runtime_sha256: crypto.createHash('sha256').update(projectFiles['mod/scripts/krypton_darkform_visual.lua']).digest('hex'),
  fixture_sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(root, 'tests/native_clothing.lua'))).digest('hex'),
  native_sources: Object.fromEntries(nativeNames.map(name => [name, crypto.createHash('sha256').update(sources[name]).digest('hex')])),
  boundary: 'Executes actual installed Lua clothing code against a command-recording AnimState. Does not emulate C++ rendering, Steam ownership, networking or GPU output.',
  checks: [],
};
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
for (const [name, source] of Object.entries(nativeChunks)) {
  lua.lua_pushstring(L, to_luastring(source)); lua.lua_setglobal(L, to_luastring(name));
}
lua.lua_pushjsfunction(L, state => {
  const file = to_jsstring(lua.lua_tostring(state, 1));
  if (!(file in projectFiles)) throw new Error('Unexpected project source: ' + file);
  lua.lua_pushstring(state, to_luastring(projectFiles[file])); return 1;
});
lua.lua_setglobal(L, to_luastring('read_project_file'));
lua.lua_pushjsfunction(L, state => {
  report.checks.push(to_jsstring(lua.lua_tostring(state, 1))); return 0;
});
lua.lua_setglobal(L, to_luastring('native_audit_pass'));
const status = lauxlib.luaL_dostring(L, to_luastring(fs.readFileSync(path.join(root, 'tests/native_clothing.lua'), 'utf8')));
report.passed = status === lua.LUA_OK;
if (!report.passed) report.failure = to_jsstring(lua.lua_tostring(L, -1));
lua.lua_close(L);
const output = path.resolve(root, option('--report', 'build/native-clothing-audit/report.json'));
if (!output.startsWith(path.join(root, 'build') + path.sep)) throw new Error('Audit output must remain under ignored build/');
fs.mkdirSync(path.dirname(output), {recursive: true});
fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
if (!report.passed) throw new Error(report.failure);
console.log('Installed native clothing audit passed: ' + report.checks.length + ' checks. GPU appearance still requires a game playtest.');
