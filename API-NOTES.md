# Transport Fever 2 modding — reference and hard-won facts

Working notes for this mod. Two halves: where the official documentation lives,
and things established by probing at runtime that the documentation does not say
(or that are easy to get wrong).

---

## Official resources

| What | URL |
|---|---|
| API reference index | <https://wiki.transportfever2.com/api/> |
| `api.engine` — systems, components, entity access | <https://wiki.transportfever2.com/api/modules/api.engine.html> |
| `api.type` — **ComponentType values and component field layouts** | <https://wiki.transportfever2.com/api/modules/api.type.html> |
| `api.util` | <https://wiki.transportfever2.com/api/modules/api.util.html> |
| Lua states / script contexts | <https://transportfever2.com/wiki/api/topics/states.md.html> |
| Modding wiki (guides, file formats) | <https://wiki.transportfever2.com/doku.php?id=modding> |
| Community lexicon (German, practical recipes) | <https://www.transportfever.net/lexicon/lexicon/230-transport-fever-2/> |
| — Game Script entry | <https://www.transportfever.net/lexicon/entry/271-game-script/> |
| — Finding line entities | <https://www.transportfever.net/lexicon/entry/325-linien-entity-herausfinden/> |

**Read `api.type` first.** It documents the component layouts, and most of the
time lost on this mod came from guessing at structures that page states plainly.

Local sources worth grepping: `res/scripts/*.lua` (especially `guidesystem.lua`,
`industryutil.lua`), `res/config/style_sheet/*.lua`, and `strings -n 6` on the
`TransportFever2` binary for symbol names.

---

## Component layouts (from api.type)

    TRANSPORT_NETWORK = 52   nodes, edges. Attaches to STREET AND RAIL
                             INFRASTRUCTURE -- NOT to stations. Reading it off a
                             station returns nil; that is not a dead end, it is
                             the wrong entity.
    STATION           = 59   terminals, cargo, tag, pool
                             Terminal: vehicleNodeId, personNodes, personEdges, tag
    STATION_GROUP     = 60   stations
    COLOR             = 64   an RGB vector

`LINE` exposes only three fields to Lua: `stops`, `waitingTime`, `vehicleInfo`.
Line colour is NOT on it -- it is the separate COLOR component.

---

## Runtime facts established by probing

### Textures and tinting

Engine UI art is **8-bit greyscale** (PIL mode `L`, TGA bpp 8) used as a coverage
mask. `color` on an ImageView only tints **RGBA** art -- a mode `L` file renders
raw and comes out grey. Tinting works via `backgroundImage1/2` +
`backgroundColor1/2` on a **Button**, but a Button's background composites OVER
its child components.

`setColor` exists as a bound method but rejected every argument form tried
(floats, 0-1 table, 0-255 table), and `api.gui.util` has no `Color` type. The
only reliable runtime colouring is `setStyleClassList`, so any colour must
already exist as a style class.

Consequence: the toolbar button is a baked RGBA texture; the ladybug ships as two
baked variants; line dots use a pre-generated grid of 216 colour classes.

When inspecting the game's own art in Python, check `Image.open(p).mode` FIRST.
`.convert("RGBA")` fabricates an opaque alpha channel and hides that the file is
mode `L`.

### Userdata access

Several engine userdata have `__index` as a FUNCTION: direct field access works
while iteration does not. `toTable()` returning nil does **not** mean opaque --
try the field name.

    ConstructionDesc   toTable -> nil, but desc.type / desc.order resolve
    COLOR              toTable -> nil, but .color resolves; the vector then
                       answers BOTH .x/.y/.z AND [1]/[2]/[3] (1-based, not 0)

Genuinely opaque: `STOCK_LIST` -- `__index` is nil and sol refuses `__pairs`
("not recognized as a container").

### Returns that are MAPS, not arrays

`getSimPersonsAtTerminalForTransportNetwork(tnEntity)` returns
`{[Entity]={Entity,...},...}`. Measuring it with `#t` gives 0 regardless of
content. Iterate with `pairs`. This cost a full round of false "dead end".

### Accumulators

`itemsProduced` / `itemsShipped` / `itemsConsumed` look like:

    { _sum = 817946, CRUDE = 817946,
      _lastMonth = { _sum = 0, ... }, _lastYear = { _sum = 0, ... } }

`_sum` is a LIFETIME cumulative total. `_lastMonth` and `_lastYear` are present
but **never populated** -- always zero. Since `0` is truthy in Lua, an
`or`-chain preferring them silently returns 0 for everything.

A real rate therefore needs sampling `_sum` against
`game.interface.getGameTime().time` and differencing.

### Entity shapes

    SIM_CARGO   sourceEntity, targetEntity, cargoType, startTime, vehicleUsed, ...
    SIM_PERSON  cargoType, targetOrAtEntity, destinations, moveModes,
                travelTimes, landUse2ReachableLines, ...

Persons have **no** `sourceEntity`. `targetOrAtEntity` is that individual's
destination, unique per person -- it is not the stop they are waiting at.

### Industry stock slots

Slot ordinal = index into the construction's `stocks` array in DECLARATION order
(`industryutil.lua:18-24`; e.g. `steel_mill.con` declares
`{ "IRON_ORE", "COAL" }`). Never registry order.

No runtime route to that array has been found: `ConstructionDesc.stocks`,
`.placementParams`, `.updateFn` are all nil, and `STOCK_LIST` is opaque. Do not
parse the shipped `.con` files -- cargo mods override them.

### Time

    game.interface.getGameTime().time   elapsed GAME-TIME SECONDS, monotonic
    game.interface.getGameTime().date   { year, month, day }
    game.interface.getMillisPerDay()    can return 0 -- guard before dividing

Game-seconds to years: `seconds * (1000 / millisPerDay) / 365.25`
(from `res/scripts/mission/calendar.lua`).

### Script contexts

**A mod runs in more than one Lua context, each with its own copy of module
state.** The settings panel writes to one; `save()` reads another. Proven from
the log: a toggle printed "ENABLED" and the very next `save()`, microseconds
later, still reported the old value.

Propagate changes with `game.interface.sendScriptEvent(id, name, param)` and a
`handleEvent(src, id, name, param)` hook -- the pattern `guidesystem.lua` uses.
Broadcast from the **point of change**, not from `guiUpdate`: `guiUpdate` does
not necessarily run in the context the GUI writes to.

`load()` runs BEFORE `guiInit`, so a param-seeding step in `guiInit` will
overwrite whatever the savegame just restored unless guarded.

`save()` is called hundreds of times a minute -- never log unconditionally there.

### Toolbar / GUI tree

`getNumItems` / `getItem` live on the component **or** on its layout, depending
on the container -- probe both. `insertItem` lives on the layout for the bar
clusters. `menu`'s layout (which holds `menu.contexthelper`) reports `getIndex`,
`insertItem` and `addItem` all false: readable, but it accepts no children.

`dumpKeys` on userdata whose `__index` is a function only ever lists
metamethods. It is not a component inventory.

### Stylesheets

Evaluate in an ISOLATED Lua state: `game` is nil, so `runFn` values and
`game.config` are unreachable. Only `stylesheetutil` and other base-game modules
can be required. All values must be literals.

Stylesheets and textures are read **once per process** -- a save reload does not
pick them up, only a full restart does. Game-script changes DO come back on a
save reload.

### Logging

`print()` output goes to:

    ~/.steam/steam/userdata/<id>/1066780/local/crash_dump/stdout.txt

That file contains null bytes, so plain `grep` reports nothing and exits 1. Use
`grep -a`.
