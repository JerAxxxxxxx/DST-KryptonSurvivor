const fs = require('fs');
const path = require('path');
const parser = require('luaparse');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
const root = path.resolve(__dirname, '..');
if (fs.readFileSync(path.join(root,'LICENSE'),'utf8') !== fs.readFileSync(path.join(root,'mod/LICENSE'),'utf8')) {
  throw new Error('The installable mod must include the current project code license.');
}
function files(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => e.isDirectory() ? files(path.join(dir,e.name)) : [path.join(dir,e.name)]);
}
const scripts = files(path.join(root, 'mod')).filter(p => p.endsWith('.lua'));
const fixtureFiles = files(path.join(root, 'tests/fixtures')).filter(p => p.endsWith('.lua'));
for (const file of [...scripts, ...fixtureFiles]) parser.parse(fs.readFileSync(file, 'utf8'), {luaVersion: '5.1'});
console.log(`Lua 5.1 syntax: ${scripts.length} mod files and ${fixtureFiles.length} world configuration passed.`);
const main = fs.readFileSync(path.join(root,'mod/modmain.lua'), 'utf8');
const assets = [...main.matchAll(/Asset\("(ATLAS|IMAGE)",\s*"([^"]+)"\)/g)];
for (const [, , relative] of assets) {
  if (!fs.existsSync(path.join(root, 'mod', relative))) throw new Error('Missing asset: '+relative);
}
for (const [,type,relative] of assets) if (type === 'ATLAS') {
  const xml = fs.readFileSync(path.join(root,'mod',relative), 'utf8');
  const texture = xml.match(/<Texture filename="([^"]+)"/)[1];
  if (!fs.existsSync(path.join(root,'mod',path.dirname(relative),texture))) throw new Error('Missing atlas texture: '+relative);
}
console.log(`UI asset references: ${assets.length} files passed.`);
// Embed project files because Fengari does not expose desktop filesystem IO in Lua.
const projectFiles = {};
const testFiles = ['tests/smoke.lua', 'tests/heatvision.lua', 'tests/mobility.lua', 'tests/eating.lua', 'tests/tool_actions.lua', 'tests/starcore.lua', 'tests/frostbreath.lua', 'tests/status_hud.lua', 'tests/combat_targets.lua', 'tests/darkform.lua', 'tests/ability_input.lua', 'tests/configuration.lua', 'tests/darkform_visual.lua'];
for (const file of [...scripts,...fixtureFiles,...testFiles.map(file => path.join(root, file))]) {
  projectFiles[path.relative(root,file).replaceAll('\\','/')] = fs.readFileSync(file,'utf8');
}
for (const testFile of testFiles) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_pushjsfunction(L, state => {
    const name = to_jsstring(lua.lua_tostring(state,1));
    if (!(name in projectFiles)) throw new Error('Unexpected source: '+name);
    lua.lua_pushstring(state,to_luastring(projectFiles[name]));
    return 1;
  });
  lua.lua_setglobal(L,to_luastring('read_project_file'));
  const status = lauxlib.luaL_dostring(L,to_luastring(projectFiles[testFile]));
  if (status !== lua.LUA_OK) throw new Error(testFile + ': ' + to_jsstring(lua.lua_tostring(L,-1)));
  lua.lua_close(L);
}
console.log('All checks passed. Actual game integration still requires a playtest.');
