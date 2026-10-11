// Optional native audit runner. The Python extractor provides installed-game
// methods on stdin, so no game source enters tracked files or release packages.
const fs = require('fs');
const path = require('path');
const parser = require('luaparse');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('fengari');
const root = path.resolve(__dirname, '..');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
parser.parse(input.fixture, {luaVersion: '5.1'});
const allowedFiles = new Set([
  'mod/scripts/components/krypton_starcore.lua',
  'mod/scripts/krypton_starcore_starter.lua',
  'mod/scripts/prefabs/krypton_starcore_amulet.lua',
]);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushjsfunction(L, state => {
  const file = to_jsstring(lua.lua_tostring(state, 1));
  if (!allowedFiles.has(file)) throw new Error('Unexpected project source: '+file);
  lua.lua_pushstring(state, to_luastring(fs.readFileSync(path.join(root, file), 'utf8')));
  return 1;
});
lua.lua_setglobal(L, to_luastring('read_project_file'));
lua.lua_pushjsfunction(L, state => {
  lua.lua_pushstring(state, to_luastring(input.fixture));
  return 1;
});
lua.lua_setglobal(L, to_luastring('read_native_starcore_methods'));
const status = lauxlib.luaL_dostring(L, to_luastring(fs.readFileSync(path.join(root, 'tests/starcore.lua'), 'utf8')));
if (status !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
lua.lua_close(L);
console.log('Installed native temperature, health, equippable and player classified methods passed the Starcore regressions.');
for (const [file, hash] of Object.entries(input.sources)) {
  console.log(`${file}: SHA-256 ${hash}`);
}
