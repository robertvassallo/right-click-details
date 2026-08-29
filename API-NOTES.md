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

On a SIM_CARGO, `sourceEntity` is where the item STARTED, not where it is now,
and `vehicleUsed` says whether it is currently aboard. Neither locates a waiting
item at a stop -- see "Per-station attribution" below.

Persons have **no** `sourceEntity`. `targetOrAtEntity` is the current leg's
target, matching one entry in `destinations` -- it is not the stop they are
waiting at.

A VEHICLE_DEPOT carries **nothing but two strings**. Confirmed against a live
save, not inferred:

    SHAPE getEntity(VEHICLE_DEPOT) type=table
      name = Hendon Train depot  [string]
      type = VEHICLE_DEPOT       [string]

No id, no position, no numbers, no accumulators. So a depot panel built on
`getEntity` can only ever show the name -- which is exactly what it does, and
why it looks broken. Anything useful about a depot (what is stabled in it) has
to come from the VEHICLE side, not from the depot entity.

### Industry stock slots

Slot ordinal = index into the construction's `stocks` array in DECLARATION order
(`industryutil.lua:18-24`; e.g. `steel_mill.con` declares
`{ "IRON_ORE", "COAL" }`). Never registry order.

No runtime route to that array has been found: `ConstructionDesc.stocks`,
`.placementParams`, `.updateFn` are all nil, and `STOCK_LIST` is opaque. Do not
parse the shipped `.con` files -- cargo mods override them.

### Per-station attribution: NEITHER cargo NOR passengers

Nothing the API exposes says which stop a waiting item or person is queued at.
Both halves of this were once believed solved; both were measurement errors, and
both shipped.

**Cargo.** `getSimCargosForLine(lineId)` returns cargo **in transit only** --
items already loaded onto vehicles. Probed on two lines against a live save: 436
of 436 and 395 of 395 items had `vehicleUsed = true`, and not one was waiting. It
answers "what is this line carrying", never "what is waiting HERE".

`sourceEntity` on those items is the **ORIGIN**, not the current location: every
sampled item shared one `sourceEntity` (the producing industry) while
`targetEntity` varied. An earlier version of this file called it "the entity the
item is waiting at", and v1.6 shipped a per-line freight breakdown built on that
reading. The filter matched nothing, the loop body never ran, and the feature
silently rendered no rows for a whole release. Do not rebuild it on this call.

Note also that `getSimCargosForLine` returns **entity ids, not item tables**. A
`type(it) == "table"` guard on them is false for every item, which turns a broken
walk into a confident zero rather than an error. Resolve each id through
`game.interface.getEntity` first.

The only route left is `simCargoAtTerminalSystem`, which wants a transport
network entity -- and nothing yields one, see below.

**Passengers.** `SIM_PERSON` has no `sourceEntity` at all. Probed and ruled out,
all against a live save:

    station entity              cargoWaiting totals only; no per-line split, no
                                person ids to intersect
    SIM_PERSON.sourceEntity     does not exist
    SIM_PERSON.targetOrAtEntity the CURRENT LEG's target, not the stop: it equals
                                .destinations[n] for the leg the person is on, so
                                its index measures journey progress. 21 distinct
                                values, every one a CONSTRUCTION -- a destination
                                BUILDING, never the station group
    SIM_PERSON.destinations[1]  26 distinct, all CONSTRUCTION, none the station
    simPersonAtTerminalSystem   only getEdgeInfoMap/getNumFreePlaces/getPos01
    TRANSPORT_NETWORK component ABSENT on stations. Probed on four: getComponent
                                returns ok=true, type=nil -- on the station group
                                AND on every member station. This is why no
                                terminal call can be reached
    getSimPersonsAtTerminalForTransportNetwork(tnEntity)
                                documented as "persons waiting at the given
                                transport network" -- but nothing yields a
                                tnEntity: not the station group, its members,
                                their constructions, nor
                                getEntities{type="TRANSPORT_NETWORK"}
    STATION component           CORRECTED -- nil on the station GROUP, but it
                                READS on the member station. getComponent(member,
                                ComponentType.STATION).terminals returns a list
                                of StationTerminal userdata (8 at one station, 4
                                at another). The claim that it was unreachable
                                blocked per-stop attribution from v1.6 onward
    subtraction (onLine - riders)
                                CORRECTED -- see "Vehicles" below. getLineVehicles
                                was looked for on lineSystem, which does not have
                                it; it lives on transportVehicleSystem and works

So passenger figures can only ever be route-wide, and waiting freight can only be
reported per commodity for the station as a whole. That is what the mod ships as
of v1.7.

Two measurement mistakes wasted a lot of time here and are worth avoiding:
passing a station id where a network entity was wanted, and calling `#t` on a
return documented as a key-value map.

### Vehicles -- richer than anything else in this API

`transportVehicleSystem` owns them. Confirmed function list on a live save:

    getDepotVehicles          getGoingToDepotVehicles   getInfo
    getLine2VehicleMap        getLineStopVehicles       getLineVehicles
    getNoPathVehicles         getVehicleNames           getVehicles
    getVehiclesWithState

**`getLineVehicles` works.** An earlier note here called it useless -- it had
been looked for on `lineSystem`, which has no such function. Third measurement
error of the same kind in this file, after `#` on a key-value map and passing a
station id where a network entity was wanted. Check WHICH SYSTEM before
concluding a call is dead.

`getEntity(vehicleId)` returns 14 keys, and they are the good ones:

    id           39547
    name         "Medium Rare"
    type         "VEHICLE"
    carrier      "RAIL"
    state        "EN_ROUTE"        -- already a readable string
    line         35910             -- the line entity id
    stopIndex    2                 -- index into getLineStops(line)
    depot        -1                -- -1 when not assigned/in one
    position     { x, y, z }
    speed        22.45
    cargoLoad    { PLANKS = 129 }              -- what it is carrying NOW
    capacities   { LOGS = 143, PLANKS = 130 }  -- what it is CONFIGURED for
    allCapacities{ LOGS = 273, PLANKS = 273, STEEL = 273,
                   CONSTRUCTION_MATERIALS = 273 }  -- what it COULD be set to
    vehicles     per-unit consist: fileName, condition, purchaseTime,
                 loadConfig, color, reversed, logo

**`capacities` is the fix for per-line cargo attribution.** It is what the
vehicle is configured to carry and does not change when the train runs empty,
unlike `getSimCargosForLine`, which reports only what is aboard at that instant
and returns n=0 for most lines most of the time. Line -> getLineVehicles ->
each vehicle's `capacities` keys gives a STABLE set of commodities a line
carries. That is what the panel should have been using.

The TRANSPORT_VEHICLE component adds little over `getEntity`: `.line`, `.state`
(an integer rather than the friendly string), `.config` (opaque userdata),
`.userStopped`, `.depot`, `.doorsTime`. Vehicles have **no COLOR component**
(`ok=true, type=nil`), so vehicle colour lives in `vehicles[n].color`.

`getDepotVehicles` is the only route to a useful depot panel -- the depot
entity itself is two strings, see Entity shapes.

### Screen geometry -- keeping a panel on screen

    game.gui.getContentRect("mainView")   -> { x, y, w, h } plain table
                                             measured { 0, 0, 2560, 1080 }
    component:calcMinimumSize()           -> Size USERDATA, read .w and .h
    component:getContentRect()            -> Rect USERDATA

`getContentRect` was recorded in this project as dead because it returns nil for
`"townhudicon"`. The CALL is fine -- `"mainView"` answers immediately. One
failing argument is not a dead function, and this is the fourth entry in these
notes that had to be corrected for exactly that reasoning.

The Size/Rect userdata cannot be walked by `toTable`; field access works, and
the spelling is `.w` / `.h` (confirmed, logged as "via w/h" at first placement).

Component surface, from a key dump of a live component:

    addLifeTimeChecker addStyleClass calcMinimumSize getContentRect getCore
    getLayout getName getParent hasFocus ...

The panel host is a `CFloatingLayout`: `addItem`, `deleteAll`, `getIndex`,
`new`, `setItemPosition`, `setPosition`. `setItemPosition` allows repositioning
after insertion, so measure-then-move is possible if placing correctly up front
ever stops being enough.

Only BoxLayout and AbsoluteLayout are used by this mod; `api.gui.layout` has
never been dumped, so whether a grid or scroll component exists is unknown.
Nested BoxLayouts give columns regardless.

### Opening an entity's window

    comp.GameUI:getViewManager()
    util.ViewManager:openWindow(entity, above, tabIndex) -> [Window] or nil

That is the route to making something clickable-to-open (e.g. a line row opening
the line overview). `game.gui.openWindow` also exists in the legacy table.

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
