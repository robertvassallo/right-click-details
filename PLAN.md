# Plan

Rewritten 2026-08-14. The previous version had grown to ~600 lines, most of it
resolved or overtaken. Everything still true is kept; the rest is gone.

---

## Where things stand

Working and verified in-game:

- Right-click readouts for town, industry, station and depot
- Ranked selection with right-click-to-cycle
- Station cargo rows tagged with the line each item waits for
- Industry level, transport rating, produced / shipped / used, stored inputs
- Bevelled panel corners; panel persists until left-click; Escape closes
- Cargo registry read live, so modded commodities work
- Toolbar button on the HUD bar with the game's own disc styling
- In-game settings panel with a ladybug debug toggle
- Large figures abbreviated (62500 → 62.5K), threshold 10000

Shipped since: v1.5 fixed settings persistence (the mod runs in more than one
script context and the panel wrote to a different copy than save() read).
v1.6 added the per-line station breakdown with line-colour discs.

Open bug: a line can show its colour at one station and grey at another.
Diagnosed as the line ID differing by station -- `stationLines` infers it from a
"line stop" that is not always a line entity -- so it now verifies
`type == "LINE"` and logs rejects with the lookup variant that produced them.
Awaiting a log to confirm.

---

## Findings that cost real time — do not relearn these

**See [API-NOTES.md](API-NOTES.md)** for the full reference: official
documentation links plus everything established by probing — component layouts,
texture/tinting rules, userdata access, script contexts, entity shapes. The
summary below is the short version.


**Textures and tinting.** The engine's UI art is 8-bit GREYSCALE (PIL mode `L`,
TGA bpp 8) used as a coverage mask. `color` on an ImageView only tints **RGBA**
art — a mode `L` file in an ImageView renders raw and comes out grey, ignoring
the stylesheet. Tinting *does* work via `backgroundImage1/2` + `backgroundColor1/2`
on a **Button**, but a Button's background composites **over** its child
components, dimming anything inside it.

Consequence: the toolbar button is baked to a finished RGBA texture
(`tools/make_toolbar_button.py`), and the ladybug ships as two baked variants
swapped with `setImage`. Neither can be a stylesheet colour swap.

The same trap is waiting in **Filter Class**, whose toolbar button has not been
built yet.

**Diagnosing this cost a day**, largely because `.convert("RGBA")` on the game's
own files fabricates an opaque alpha channel and hides that they are mode `L`.
Check `Image.open(path).mode` before concluding anything about engine art.

**Accumulators.** `itemsProduced` / `itemsShipped` / `itemsConsumed` look like:

```lua
{ _sum = 817946, CRUDE = 817946,
  _lastMonth = { _sum = 0, CRUDE = 0 },
  _lastYear  = { _sum = 0, CRUDE = 0 } }
```

`_sum` is a lifetime cumulative total. `_lastMonth` and `_lastYear` are **always
zero** — present in the shape, never populated. Measured on a well that had
produced 817946 and shipped 279067.

Since `0` is truthy in Lua, the old `bucketTotal(acc._lastYear) or ...` chain
stopped on a zero and every figure read 0. Both `rateOf` and `perCargo` now treat
an all-zero bucket as absent.

**Stock slots.** The slot ordinal is the index into the construction's `stocks`
array, in DECLARATION order — `steel_mill.con` declares `{ "IRON_ORE", "COAL" }`
and the slots read iron ore then coal. It is never registry order.

But there is **no runtime route to that array**. All exhausted:

| route | result |
|---|---|
| CONSTRUCTION entity `.stocks` | key does not exist |
| `ConstructionDesc.stocks` / `.placementParams` / `.updateFn` | all nil |
| `toTable(desc)` | nil |
| ECS `STOCK_LIST` | opaque — `__index` nil, and sol refuses `__pairs`: *"not recognized as a container"* |
| ECS `CONSTRUCTION` / `SIM_BUILDING` | no stock fields |

**Toolbar containers.** `getNumItems` / `getItem` live on the component **or** on
its layout, depending on the container; `insertItem` lives on the layout. Probe
both. `menu`'s layout — the one holding the "?" — can be read but reports
`getIndex`, `insertItem` and `addItem` all false: it accepts no children, so
placing a button beside `menu.contexthelper` is impossible.

**Load order.** `load()` runs BEFORE `guiInit`. `seedSettingsFromParams` must not
overwrite what the save restored, or every setting silently reverts.

**Functions defined above `emit`/`log` cannot call them** — the locals are not in
scope yet and it resolves to a nil global, crashing `guiInit`.

---

## Roadmap — next up

These are the planned direction, ahead of the older blocked items below.

### A. Town details window — formatting pass — SHIPPED in v1.7

Brought in line with the station panel: right-aligned figures in a fixed column
via `rlvLineCount`, recessive percentages via `rlvStatMuted`, and a rule under
the population line. Left here as a pointer; the detail is in the changelog.

### B. Town radius — lines and cargo within it

Investigate what a town's catchment actually exposes, and whether the panel can
answer "which lines serve this town" and "what cargo moves through it" rather
than only what the town itself wants.

Starting points, none verified:

- `game.interface.getEntities({pos, radius}, {type=...})` already backs the
  right-click search, so the same query shape can find stations near a town.
- `stationSystem.getTown(stationEntity)` is documented — a station knows its
  town, which may be cheaper and more accurate than a radius sweep.
- `catchmentAreaSystem` exists in the system list and is unexplored; a real
  catchment beats a guessed radius.
- Per-station lines already work via `stationLines`, so town → stations → lines
  is reachable once the first hop is settled.

Watch the cost: this is a per-right-click query, and the industry panel already
had a 120-entity walk removed for being too expensive.

### C. Town name plate colour — toggle, if possible

Investigate whether the city label plate's colour can be changed, and expose it
as a toggle if so.

Known constraints, from this mod's own history:

- `TownItem` IS reachable from the stylesheet — the mod already restyles its
  background image and tint.
- BUT stylesheets evaluate in an isolated Lua state with no access to `game`,
  so a runtime toggle cannot be read there. This is exactly why the mod's visual
  sliders were removed in an earlier version.
- So a toggle needs either a set of pre-declared style classes swapped from the
  game script, or the same baked-asset approach the toolbar button uses.
- `TownItem` is engine-rendered (HudIconManager), so no new subcontrols — only
  properties on what already exists.

Feasibility is genuinely unknown; establish that before designing the UI.

### D. Right-click a VEHICLE — opt-in

Not supported today, and not merely unimplemented: a vehicle is never even a
candidate. `classify` returns nil for anything that is not a town, station,
depot or sim building, and the three search tiers only ever ASK the engine for
those types. So a right-click on a moving train falls through to whatever
station or industry happens to be underneath it.

Wanted, at minimum:

- its line
- its next stop
- what it is currently carrying

No buttons. An earlier draft of this item had a button group opening the real
line- and vehicle-management windows; dropped. It would have rested on
`util.ViewManager:openWindow`, which this mod has never called, and it needed
its own dismiss-mode gating to stop the buttons being unreachable under "Mouse
moves". Neither cost is worth paying for a shortcut to windows the player can
already reach by left-clicking.

**Ships OFF, behind a settings toggle.** This is the part to get right, and it
is not just caution — vehicles compete for clicks. `LOCAL_RADIUS` is
deliberately tight (45) so stations do not steal clicks meant for town labels,
and a vehicle sitting in a platform sits on top of the station serving it,
where the station is usually the answer the player wants. A toggle means anyone
who dislikes that trade simply never sees it, which is a better answer than
trying to find a ranking rule that suits everyone.

The wiring is an established pattern, not new ground — copy `panelEnabled` /
`debugLogging`:

- `config.defaultIndex` in `res/scripts/rlv_cityoverlay_config.lua`, index 0
  for off
- resolve it in `config.applyParams` as `(params.X == 1)`, alongside
  `debugLogging`
- `param_X` / `param_X_tt` strings in `strings.lua`
- it must survive the settings sync across script contexts — see the v1.5
  entry in the changelog for why that is not automatic

Then the ranking decision, once it is opt-in: when the toggle is on and a
vehicle and its station are both under the cursor, which wins, and does the
existing right-click-again cycling get the player to the other one? Cycling
already exists, so this is probably "station first, vehicle on the next click"
rather than a new radius tier.

One unknown, and it blocks design: **what does a VEHICLE entity carry?**
Nothing in this repo has ever dumped one, so line, next stop and current load
are all assumptions. `getLineVehicles` is recorded in API-NOTES as yielding
nothing usable, but that was the line-to-vehicles direction while hunting
passenger attribution; vehicle-to-line is the reverse and may differ. Settle it
with one debug pass, then design.

Do NOT build the panel against assumed field meanings. v1.6's per-line freight
rows and the "cargo YES" note in API-NOTES were both exactly that mistake, and
both shipped broken.

### E. The station line cap — pick the right ten

`MAX_STATION_LINES` is 10, and a station busier than that is handled worse than
the constant suggests. Analysed during v1.7 but deliberately NOT fixed there;
no save on hand has such a station, so it would have shipped untested.

Three faults, in order of severity:

1. **The cap can resurrect the wrong-line bug v1.7 just fixed.** `cargoLineMap`
   only ever sees the capped list, so it can only learn about carriers among
   the surviving lines. Where an included line and an excluded line both carry
   a commodity, the map holds exactly one known carrier and the panel names it
   -- with its colour -- as the sole carrier. Confidently wrong, at precisely
   the kind of interchange where >10 lines and shared commodities co-occur.

2. **You can get fewer than ten rows.** The cap slices `lineIds`, which holds
   line STOPS, while dedup (`seen`) and the is-it-a-LINE check both happen
   INSIDE that window. A line stopping twice burns two slots for one row; a
   stop resolving to a non-LINE burns a slot for none. The log still says
   "showing first 10".

3. **Which ten is arbitrary** -- whatever order the engine returns stops in.

The fix, and the reason it is not just "raise the cap":

- Dedupe and validate BEFORE capping, so ten means ten distinct lines. Costs a
  `getEntity` per extra stop; trivial next to the cargo walks.
- Rank the full list and keep the busiest ten. This IS possible and the mod
  already does it for passengers: `#getSimPersonsForLine(id)` and
  `#getSimCargosForLine(id)` are plain array counts, one call per line, no
  per-item resolution. `linePassengers` already sorts on the first of those.
  Do not confuse this with per-stop attribution -- asking a line for its total
  never requires knowing which line a waiting item belongs to.
- Be honest that the ranking is ROUTE-WIDE. A trunk line barely calling here
  outranks a local line that is this station's main service. Better than
  arbitrary; not the same as "busiest here", and must not be labelled as such.
- When the list was trimmed, suppress sole-carrier naming. If we know we did
  not see every line, one known carrier is not a proven sole carrier -- the
  same rule the rest of v1.7 follows.

And the bigger one, found while verifying v1.7 and the reason its wording had
to be walked back before release:

- **`cargoLineMap` asks the wrong question.** It builds the carrier set from
  what each line is HOLDING at that instant, so a line that serves the stop and
  carries the commodity contributes nothing whenever its vehicles are empty --
  and empty is the normal state. Measured on a live save: six of eight lines
  returned `n=0` from `getSimCargosForLine`. The set therefore churns, and one
  station reads "2 lines" one minute and a single confident name the next.
  Observed directly at Lutterworth East during v1.7 testing.

  Raising `MAX_CARGO_SAMPLES` does not touch this -- the cap is the smaller of
  the two effects. The right source is what each line's VEHICLES ARE
  CONFIGURED TO CARRY, which is stable regardless of load. Unexplored; likely
  via the line's vehicle list and each vehicle's capacities. Nothing in this
  repo has probed it, so treat the route as unknown.

  Until that exists, v1.7 ships saying a named line is the only one SEEN
  carrying it, not the only one that does.

---

## Open work — older items

### 1. Per-cargo Stored on multi-input industries — BLOCKED

`readStockLevels` reports a combined `__total` when it cannot map slots to cargo,
so those rows render `--`. `stockSlotOrder` tries three routes and validates any
mapping against the industry's known inputs before trusting it; all three
currently fail (see above), so the fallback always wins.

Not fixable without a new API surface. The combined figure is still surfaced as
the *Stored total* row. Revisit if a future patch exposes `StockList`.

### 2. A real production rate — the path to several other things

`_sum` only ever grows, so sampling it against game time gives a genuine realised
rate: `(sum_now − sum_then) / (time_now − time_then)`, stashed per industry in
`save`/`load`.

That unblocks:

- **The low-stock highlight**, currently disabled. It divided stored by
  consumption expecting a rate; against a lifetime total the ratio vanishes and
  every row would flag as a bottleneck. `LOW_STOCK_YEARS` is left in place for
  when a rate exists. This was the mod's signature feature.
- **Honest per-year labels** instead of lifetime totals.

Costs: nothing useful on first view of an industry, and it needs save data.
Degrades gracefully to today's lifetime totals.

### 3. Percentage bars for stored commodities — BLOCKED on a denominator

`ProgressBar` exists (`setProgress` / `setRange` / `setValue`), and `hud.lua:135`
shows the game styling a 4px bar for `StationItem`. The game's own version is
`UI::AddStockListOverviewBars`, C++ with no Lua binding, so the look can be
reproduced but not the arithmetic.

The denominator is unresolved. `rule.capacity` is 200 on a steel mill, but coal
was observed at 4901 stored — so it is not the cap in displayed units. Note also
that the installed *Industry Production Levels* mod rewrites capacities at load
time, so any capacity must be read live, never from shipped config.

Depends on §1 anyway: without per-cargo Stored there is nothing to draw a bar
against on multi-input industries.

### 4. Name header — UPPERCASE and bold

Unstarted. `textTransform = "UPPERCASE"` and `fontWeight = "Bold"` are both
confirmed to exist. Industry always shows its name; the town shows its name only
when town labels are hidden by the HUD filter.

---

## Before release

Cleared for v1.4:

- ~~Remove `probeStockMapping`~~ — gone. It forced `settings.debug = true` and
  printed regardless of the player's setting.
- ~~Re-gate the `PLACE:` toolbar logs~~ — now behind `log`, silent unless the
  ladybug is on.
- ~~`.luarc.json` ships to the Workshop~~ — the repo lives outside the staging
  area now and `deploy.sh` excludes it, along with `tools/`, `PLAN.md`,
  `README.md`, `LICENSE` and `.git/`.

Cleared for v1.7:

- ~~Probe code in the shipped script~~ — `probeTerminalPax` and `countKeys`
  lifted out to `tools/probe_terminal_pax.lua`; findings written up in
  API-NOTES. Same class of fault as `probeStockMapping` in v1.4.
- ~~v1.6 and v1.7 changelog entries contradicting each other~~ — v1.6 restored
  byte-for-byte to what shipped; v1.7 does the correcting.
- ~~API-NOTES claiming per-stop cargo attribution works~~ — retracted and
  replaced with the measured findings.
- ~~Station throughput labelled `/yr` against a lifetime total~~ — labels are
  now plain Outbound/Inbound, matching the industry panel.
- ~~Version consistency~~ — `mod.lua` minorVersion 7, README, changelog and the
  Workshop description all agree.
- ~~Syntax~~ — `luac -p` clean on all five shipped Lua files.

Outstanding for v1.7, in-game only:

- Town panel: rule under the population line, figures stacking in a column,
  and commodity icons UNCHANGED in size (the `rlvLineCount` class went on
  those rows; `rlvCityOverlayRow ImageView` should still win on the icon).
- An industry, a depot, and right-click cycling — plain regressions, the
  shipped script lost 337 lines.
- Debug log carries no `TERMINAL PAX PROBE` block.
- A station with more than ten lines — NOT TESTABLE on the current save. See
  roadmap item E; the cap is known to misbehave and is deferred, not fixed.

Still outstanding:

- **Retest settings persistence** across a save/reload. `load()` merges
  param-backed settings against a snapshot written at save time, so a param the
  player changed wins while an untouched one defers to the in-game panel. Saves
  predating the snapshot keep their stored values. Never verified end to end.
- Internal identifiers still read `rlv_cityoverlay` — config module, component
  names, texture path, log prefix. Cosmetic; not player-visible.
- Retake the industry screenshot, and add one of the toolbar button.
- `!ui-couch` controller layout check for the new toolbar button.
- Publish: staging already holds the exact shipping set, so it is `./deploy.sh`
  then upload.

---

## Iterating

Stylesheets and textures are read **once per process** — visual changes need a
full restart, a save reload is not enough. Game-script changes come back on a
save reload.

`print()` output lands in:

```text
~/.steam/steam/userdata/24778163/1066780/local/crash_dump/stdout.txt
```

That file contains null bytes, so plain `grep` reports nothing and exits 1. Use
`grep -a`.
