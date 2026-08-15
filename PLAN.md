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

Untested since the last change: toolbar hover/pressed states, the ladybug's
two-texture swap, debug persistence across save/load, and toolbar placement
beside the bulldozer.

---

## Findings that cost real time — do not relearn these

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

## Open work

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

- **Remove `probeStockMapping`.** It forces `settings.debug = true` for its own
  duration and prints regardless of the player's setting.
- **Re-gate the `PLACE:` toolbar logs.** They use `emit` so they always print;
  demote to `log` now that placement works.
- **Retest settings persistence.** `load()` merges param-backed settings against
  a snapshot written at save time, so a param the player changed wins while an
  untouched one defers to the in-game panel. Saves predating the snapshot keep
  their stored values.
- Internal identifiers still read `rlv_cityoverlay` — config module, component
  names, texture path, log prefix. Cosmetic; not player-visible.
- `.luarc.json` ships to the Workshop; consider excluding.
- Retake the industry screenshot, and add one of the toolbar button.
- `!ui-couch` controller layout check for the new toolbar button.

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
