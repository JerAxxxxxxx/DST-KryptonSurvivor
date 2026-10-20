# Krypton Survivor

[简体中文](README.md) · **English**

Bring DC's Superman to **Don't Starve Together** on Steam. Enjoy powerful stats, full night vision, heat vision, frost breath, flight, map teleportation, the exclusive axe **Rao's Edge** and the **Starcore Amulet**. Built for relaxed exploration and overpowered combat with friends.

**Current code version: 0.9.0.** Skill feedback has passed in-game testing; multiplayer protection scenarios remain to be tested. **Steam Workshop remains at 0.8.2, with no update planned yet.** Supports Chinese and English; the features below describe the repository code. See the [changelog](docs/changelog.md) for Workshop version differences.

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3811663817) · [Changelog](docs/changelog.md) · [Development guide](docs/build.md) · [Report an issue](https://github.com/JerAxxxxxxx/DST-KryptonSurvivor/issues)

![Superman holding Rao's Edge, shown from the front, side and back](assets/source/superman-standing.jpg)

## Installation and controls

1. Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3811663817).
2. Enable the mod under **Server Mods** in your world's settings.
3. Select **Superman** on the character selection screen.

All players need the same mod version. After an update, let Steam finish downloading it and restart the game. Enable one copy of the mod if you also have a local installation.

For a local installation, copy the complete `mod/` directory to your game's `mods/KryptonSurvivor/` directory, then enable it under Server Mods.

| Action | Control |
| --- | --- |
| Heat vision | Aim with the mouse and press **R**. No equipment required. |
| Frost breath | Aim with the mouse and press **X** to breathe cold air. |
| Toggle flight | Press **V**. Flight starts enabled. |
| Map teleport | Open the map with **Tab**, hold **Ctrl**, then **right-click** the destination. |
| Harvest with Rao's Edge | Use **Space** or **left-click** to pick berries, grass and twigs. |
| Dig with Rao's Edge | **Right-click** to uproot plants. Tree stumps can also be dug with **Space**. |

Heat vision, frost breath and flight keys can be changed in the mod settings. These abilities and map teleport require no equipment. Map teleport uses a keyboard and mouse; normal controller map controls remain available.

## Character abilities

- Maximum health, hunger and sanity are **10,000 each**.
- No natural hunger loss or ongoing sanity drain. Instant effects, such as food penalties, can still change sanity.
- Full night vision at night and in caves, without the Moggles color filter.
- Regenerates **100 health and 100 sanity per second** during daytime on the surface, up to the current maximum. Regeneration stops at dusk, at night, in caves, and while dead or a ghost.
- Movement speed can be set to **1.5×, 2× or 3×** a normal character's speed; the default is **1.5×**.
- Eating uses open-mouth, chewing and satisfied expressions alongside the game's body, food and sound animations. The normal expression returns when eating ends or is interrupted.

## Heat vision

Heat vision is an innate ability. Aim with the mouse and press **R**, whether empty-handed or holding the axe.

- **Range: 20** world units. Beams pierce multiple enemies in a straight line.
- Damage is configurable separately from axe damage: **2,000, 10,000 or 50,000**, with **2,000** as the default.
- No hunger, sanity or durability cost; the minimum firing interval is **0.35 seconds**.
- Beams start at the eyes and follow head movement, with a bright core, glow and eye lights.
- Direct hits skip players, followers, companions, domesticated creatures, walls and structures.
- Surviving targets that can burn and are not fire-immune may catch fire. The game's normal fire spread still applies.
- Servers can disable **Heat vision ignition** while retaining beam damage and visuals. Ignition stays enabled by default.

The shortcut is inactive while chatting, interacting with interfaces or placing buildings. Heat vision cannot fire while busy, working, dead, a ghost, or while the server is paused.

## Frost breath

Aim with the mouse and press **X** to release blue-white cold mist and ice crystals from the mouth. This innate ability needs no equipment and consumes no hunger, sanity, materials or durability.

- A forward cone with a **range of 8** and a **28° half-angle**. Each cast lasts about **1 second**; the minimum cast interval is **1.2 seconds**.
- Applies the game's native freezing mechanics to enemies, adding **2 coldness once per target per cast**. It causes no direct health damage.
- Whether a target freezes, and for how long, follows native resistance, freeze immunity and boss diminishing returns. It does not force every target to freeze or promise a fixed duration.
- Freezing skips players, followers, companions, domesticated creatures, walls and structures. The breath can still extinguish burning or smoldering friends, structures and trees.
- Campfires, cooking facilities and fueled devices are preserved so intentional fire sources keep working.
- The server can disable the ability. Each player can select **X, C, N**, or disable the shortcut. Chat, interfaces, building placement, busy, mounted, dead, ghost and paused states prevent casting.

Casting temporarily uses the supplied open-mouth front or profile head, with mist following the mouth. The back view retains the existing head. The normal expression returns when the cast ends or is interrupted, while body and equipment animations continue to use the installed game.

## Rao's Edge

Superman's exclusive axe is provided and automatically equipped on spawn. Other characters cannot use it and will drop it if they pick it up.

- Configurable damage: **2,000, 10,000 or 50,000**, default **2,000**.
- Extended melee reach and area damage around the target. Area damage shares heat vision and freezing's protection rules, skipping players, followers, companions, domesticated and player-aligned creatures, walls and structures. Deliberate primary melee attacks keep native behavior.
- Works as an axe, pickaxe, hammer and shovel, at **10×** normal tool efficiency.
- **Space and left-click prioritize harvesting** berries, grass and twigs. Continuing to hold Space after picking will not uproot those plants; use right-click when you want to transplant them. Tree stumps can still be dug with Space.
- Unlimited durability. Attacks, tool work and lighting consume no fuel or resources.
- Provides light for the wearer and nearby friends at night and in caves while equipped.

Digging turf remains a **pitchfork** action and is not included.

## Starcore Amulet

The Starcore Amulet is exclusive to Superman and uses the native **body equipment slot**, shared with backpacks and armor. It has unlimited durability and no resource cost.

- New characters receive and equip it on spawn. Existing saves receive one amulet on their first upgrade; an occupied body slot is left alone and the amulet goes into inventory, or drops nearby if inventory is full. Losing it or rejoining does not grant another copy.
- While equipped, moisture is cleared and the wearer stays dry. Body temperature remains in a safe range—**10–50 °C by default**—to avoid cold and overheat warnings and health damage. Normal temperature changes resume after unequipping.
- When equipped and ready, it automatically revives the wearer at the death position, restoring health to the **current maximum**. Existing maximum-health penalties still apply. The amulet is retained; other items follow normal death-drop rules.
- Successful revival starts a **one-game-day cooldown**, normally **480 simulation seconds**. Environmental protection stays active during cooldown, but another death will not trigger revival until it is ready.
- Cooldown is saved with the character and follows them between shards. Swapping or crafting amulets does not reset it.
- Automatic revival uses the game's ghost or revivable-corpse mechanics. Wilderness modes without either mechanic retain normal death and character-reroll behavior.
- Craft without a station in Superman's character crafting category: **3 Gold Nuggets + 2 Nightmare Fuel + 1 Red Gem**.

Inspecting an amulet on cooldown reports that it is recovering; when cooldown ends while it is worn, Superman announces that it is ready.

The protection covers moisture, cold damage and overheating damage. **Fire, combat damage, food effects on health/hunger/sanity, and freezing effects that immobilize the character still follow the game's rules.**

## Flight and map teleport

Both abilities are innate and use no hunger, sanity, materials or durability.

**Flight** starts enabled. Press **V** to toggle it; players may choose **B** or disable the shortcut, and the server may disable the ability entirely. Fly over oceans and gaps within caves while retaining collisions with ordinary obstacles such as walls and trees.

Return to safe land or a boat before turning flight off. Landing over open water or a cave void is refused. Flight is suspended while mounted; dismount before toggling flight or using map teleport.

**Map teleport** uses **Ctrl + right-click** on the open map. The map closes, and teleportation takes place after gameplay resumes. There is no distance or material cost, but travel stays within the **current world shard**. Use normal entrances to travel between the surface and caves.

Destinations outside the map, in cave voids, occupied by buildings or entrances, or blocked by native special barriers are rejected. Ocean destinations are allowed while flying; with flight off, select safe land or a boat. Success and failure messages explain the result. Busy, mounted, dead, ghost and server-paused states prevent teleportation. Normal map dragging, zooming, right-clicking and closing remain available.

Hovering and flight movement use the supplied front, side and back artwork. Flight loops show an empty-handed pose without held items or hats; attacks, harvesting, heat vision and frost breath restore the normal character animations and equipment display. Equipped items continue to provide their effects. Airborne movement uses gentle wind instead of walking footsteps, hovering is quiet, and normal ground and mount sounds resume when appropriate.

## Ability status HUD

A compact panel appears in the **upper-right corner, below the health, hunger, sanity and moisture displays**, only for Superman. Its upper three rows show:

- **Flight**: blue when enabled; gray when disabled, suspended by riding or unavailable.
- **Amulet**: green while dry and safe-temperature protection is active; gray when not equipped or inactive.
- **Revive**: green when ready, or a cooldown such as `04:35`. An unequipped amulet is never presented as ready.

Dryness and temperature protection remain active during revival cooldown, and cooldown continues even after removing the amulet. The server synchronizes status and remaining time every simulation second; the timer stops while the simulation is paused. Hover over a row for details.

Each row has its own cape, star shield or revival-arrow icon, dimmed when inactive; status text and cooldown remain visible. Each player can hide the panel, choose **80%, 100% or 120%** size, and switch between **default, shifted left or shifted down** positions in mod configuration.

Two additional text rows show **heat vision and frost breath**, including each player's actual configured key and readiness, cooldown, casting or unavailability. Short cooldowns dim the rows without rapidly changing decimal timers. Disabled keys and server-disabled frost breath are also explained. Skill state comes from the server and cooldown completion follows simulation time, stopping when paused. The panel remains read-only, with hover help.

## Configuration

| Setting | Options | Default |
| --- | --- | --- |
| Language | Automatic, Chinese, English | Automatic |
| Movement speed | 1.5×, 2×, 3× | 1.5× |
| Axe damage | 2,000, 10,000, 50,000 | 2,000 |
| Heat vision damage | 2,000, 10,000, 50,000 | 2,000 |
| Heat vision ignition (server) | Enabled, Disabled | Enabled |
| Heat vision key | R, G, Z, Disabled | R |
| Frost breath ability (server) | Enabled, Disabled | Enabled |
| Frost breath key | X, C, N, Disable key | X |
| Flight ability (server) | Enabled, Disabled | Enabled |
| Flight toggle key | V, B, Disable key | V |
| Map teleport ability (server) | Enabled, Disabled | Enabled |
| Map teleport input | Ctrl + right-click, Disabled | Ctrl + right-click |
| Ability status HUD | Show, Hide | Show |
| Ability HUD size | 80%, 100%, 120% | 100% |
| Ability HUD position | Default, Shift left, Shift down | Default |

There are **15 settings**. Each player configures their own heat vision, frost breath and flight keys, map teleport input, and HUD visibility, size and position. The Starcore Amulet revival cooldown is fixed at one game day.

## Development

Lua checks require **Node.js 24**. From the repository root, run:

```shell
npm ci
npm run check
```

For pre-release asset validation, install Python 3.13 and the minimal dependencies in `requirements-check.txt`, then run `npm run check:assets`. This checks owned animation archives, atlases, textures and head-frame coverage, including rejection of damaged assets. It requires neither an installed game nor an artwork rebuild. GitHub Actions is configured to run the same validation when the code is pushed.

`mod/` contains installable scripts and compiled assets. `assets/` contains the source artwork, slice definitions and source notes. `tools/` provides asset construction, preview and packaging utilities.

Rebuilding artwork also requires **Python 3.13**, the dependencies in `requirements.txt`, and a local installation of Don't Starve Together. See the [development guide](docs/build.md) for setup and commands. Slice polygons and placements belong in `assets/slices.json`; generated parts and previews go in the ignored `build/` directory. Existing artwork is extracted and transformed without redrawing it.

To report a problem, open an [issue](https://github.com/JerAxxxxxxx/DST-KryptonSurvivor/issues) with the version, reproduction steps, and relevant screenshots or logs.

## License and artwork

Code and documentation use the [MIT License](LICENSE). Character and weapon images and their derived textures retain the source and licensing notes in [the artwork guide](assets/README.md); including them in the repository does not automatically apply the code license to them.

Base-game animations and effects are loaded from the installed game at runtime and are not redistributed in this repository or the mod package.
