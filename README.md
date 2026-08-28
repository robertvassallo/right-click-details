# Right Click Details

Right-click a town, industry, station or depot in Transport Fever 2 for a
compact readout, without opening the full window.

**Version 1.7** — see `changelog.txt`.

## What it shows

- **Towns** — population, and the commodities they want with supply and fill
  percentage.
- **Industries** — level, transport rating, produced and shipped, stored versus
  used per input commodity.
- **Stations and stops** — broken down BY LINE, each with its own colour disc.
  Passengers show the exact number waiting at the stop, then per-line totals.
  Freight shows what is waiting here against capacity, then a row per line and
  commodity. Throughput sits underneath, greyed.
- Right-click the same spot again to cycle through anything else nearby.
- Figures over 10000 are abbreviated (62500 → 62.5K).

Settings live behind the mouse button in the HUD bar, beside the bulldozer:
panel on/off, how the panel closes, town-name mode, theme, and a ladybug debug
toggle in the footer.

Settings are stored **with the savegame** via the game script's `save()`/
`load()` — change one and save, or wait for an autosave, or it reverts.

They are also broadcast between script contexts with
`game.interface.sendScriptEvent` / `handleEvent`. That is not optional: the mod
runs in more than one Lua context, each with its own copy of the settings table,
and the panel writes to a different one than `save()` reads. Without the
broadcast, every choice is silently lost on reload — see v1.5 in the changelog.

`severityAdd` and `severityRemove` are both `NONE`, so the mod can be added to
and removed from an existing save freely; the settings table is additive and is
simply orphaned if the mod is removed.

## Media

![Main shot](media/MainShot.png)

Gateshead: population and every commodity the town wants, with supply and fill
percentage. This shot supplies both preview images.

![Station details](media/StationDetails.png)

Station: waiting cargo with the line each item is queued for, plus outbound and
inbound throughput.

![Town details](media/TownDetails.png)

Town: population, and the commodities it wants with supply and fill percentage.

![Industry details](media/IndustryDetails.png)

Industry: output commodity beside the name, level, produced and shipped per
year, transport rating, and stored versus consumed inputs below a rule. Stock
running short relative to consumption is highlighted.

![Settings panel](media/SettingsPanel.png)

Settings, opened from the mouse button on the right of the HUD bar.

### Where images actually go

Three separate slots, easy to confuse:

| File | Used for | Format |
|---|---|---|
| `image_00.tga` | in-game mod list thumbnail | 320×180, 24bpp uncompressed TGA |
| `workshop_preview.jpg` | Steam Workshop preview | JPEG |
| `modio_preview.jpg` | mod.io preview (not used here) | JPEG |

The publish dialog reports `[not found] workshop_preview.jpg` if that file is
missing — `image_00.tga` does **not** cover it. All three names are literals in
the binary, alongside separate "JPEG couldn't be read" / "TGA could not be read"
errors.

The engine loads exactly one in-game image: there is no `image_01` and no
numbered pattern anywhere. `media/` is documentation only — for this README and
for pasting into a Workshop description by hand, where Steam does allow several.

## Selection

The panel cannot hit-test the label you clicked. `TownItem` and the station and
depot icons are engine-rendered, absent from the `api.gui` tree; there is no
world→screen projection exposed, and `game.gui.getContentRect("townhudicon")`
returns nil. All three routes confirmed dead by probe.

So selection ranks everything near the terrain point under the cursor and lets
you **right-click again to cycle** through it. A town is promoted to the front
when the click lands within `TOWN_LABEL_RADIUS` of its centre, since that is
exactly where its label is drawn.

## Layout

```text
mod.lua                                     metadata, params, runFn
strings.lua                                 en localisation
res/config/game_script/rlv_cityoverlay.lua  the panels
res/config/style_sheet/rlv_cityoverlay.lua  styling (CONFIG at top)
res/scripts/rlv_cityoverlay_config.lua      values shared with mod.lua
res/textures/ui/rlvcityoverlay/             generated bevel 9-slice
tools/make_bevel.py                         regenerates that bevel
tools/make_mouse_icon.py                    regenerates the toolbar icon
tools/probe_terminal_pax.lua                parked API probe, never shipped
changelog.txt                               release notes
image_00.tga                                in-game thumbnail, 320x180 TGA
workshop_preview.jpg                        Steam Workshop preview, 640x360
media/                                      README / description screenshots
.luarc.json                                 VS Code Lua extension config
```

Internal identifiers still carry the old `rlv_cityoverlay` prefix from before
the mod was renamed. They are folder-independent and not player-visible.

## Engine notes worth keeping

Findings that cost real time to establish. **[API-NOTES.md](API-NOTES.md)** has
the full set plus links to the official reference — read `api.type` there first,
since it documents the component layouts that were otherwise guessed at.

- **`api.engine.system.*` returns userdata, not tables.** `game.interface.*`
  returns Lua tables. Guarding with `type(x) == "table"` silently discards every
  successful `api.engine` result — this caused line names and stock counts to
  read `--` for several iterations while the calls were working fine. Use
  `toTable()`.
- **Stylesheets evaluate in an isolated Lua state.** They cannot `require` this
  mod's own scripts (only the base game's `res/scripts` is on the path), and
  they cannot see values `runFn` publishes on `game`. Tune visuals in the
  `CONFIG` table at the top of the stylesheet.
- **`_()` behaves differently per context.** In a game script `_currentModIdTr`
  is nil, so symbolic ids never resolve — use the English text as the key.
  Symbolic ids only work in `mod.lua`.
- **The engine runs Lua 5.2.** No `\u{XXXX}` escapes; use byte escapes.
- **No corner-radius style property exists.** Bevelled corners come from a
  9-slice image; see `tools/make_bevel.py`.
- **`-1` is the fill sentinel**, in both `gravity` and `size`. On an `ImageView`
  it stretches the icon. Icons are sized with `scaling` only — the source
  textures are not square (commodities 24x19, passengers 16x32), so any fixed
  box distorts them.
- **Lengths** are plain pixels here. The engine also accepts `"NNvw"` / `"NNvh"`
  strings; the parser rejects anything else — no `%`, `px` or `em`.
- **The mod folder's `_N` suffix is the major version.** Do not declare
  `majorVersion` in `mod.lua`; no shipped mod does.
- **UI art is 8-bit greyscale coverage, and `color` on an ImageView only tints
  RGBA.** A mode `L` file in an ImageView renders raw and comes out grey —
  including the game's own icons. Tinting works via `backgroundImage` +
  `backgroundColor1/2` on a **Button**, but a Button's background composites
  *over* its children. Hence the baked toolbar texture and the two baked ladybug
  variants. When inspecting engine art in Python, check `Image.open(p).mode`
  first: `.convert("RGBA")` fabricates an opaque alpha and hides this.
- **`setColor` is unusable.** It exists as a bound method but rejects every
  argument form, and `api.gui.util` has no `Color` type. Runtime colouring must
  go through `setStyleClassList`, so the colour has to already exist as a class
  — which is why the stylesheet carries a 216-entry quantised colour grid.
- **Userdata `__index` is often a FUNCTION.** `toTable()` returning nil does not
  mean opaque — try the field name. `ConstructionDesc` and the `COLOR` vector
  both behave this way. The colour vector is **1-based**.
- **Style rules resolve by SPECIFICITY, not declaration order.** A
  `!rlvThemelight` override outranks its base wherever it sits. Order only
  decides between rules of *equal* specificity on the same element — which is
  what made every line dot grey when `rlvLineDot` carried a colour alongside
  `rlvDot<n>`.
- **The mod runs in more than one Lua context**, each with its own module state.
  `load()` also runs *before* `guiInit`. Both bite settings persistence; see
  v1.5 in the changelog.
- **Engine containers nest.** Stored stock lives behind
  `stockListSystem.getCargoType2stockList2sourceAndCount()`, and its innermost
  `sourceAndCount` value is *another* container (its metatable exposes
  `add/at/size/find/get/insert/next/pairs`), not a struct with a `count` field.
  Read it with `ipairs` — Lua 5.2 honours `__ipairs`, which these types define —
  or with the container's own `size()`/`at()`, then sum the values.

## Iterating

Lives in `staging_area/`, so it loads without packaging. Stylesheets are read
**once per process**, so visual changes need a full restart — reloading a save
is not enough. Game-script changes come back on a save reload.

`print()` output lands in:

```text
~/.steam/steam/userdata/24778163/1066780/local/crash_dump/stdout.txt
```

That file contains null bytes, so plain `grep` reports nothing and exits 1 —
use `grep -a`.

The repo lives outside the staging area; `./deploy.sh` copies only the shipping
subset in, keeping `.git/`, `tools/`, `PLAN.md`, `API-NOTES.md`, `README.md` and
`LICENSE` out of anything published. `--dry` previews.

## Known gaps

- The panel's percentage is `supply / limit`, not the growth-contribution `%`
  from the town window — that is computed in C++ and not exposed.
- **Produced / Shipped / Used are LIFETIME totals, not rates.** An earlier
  version of this file claimed they were trailing-twelve-month figures from the
  entity's `_lastYear` accumulators. That was wrong for three releases: those
  buckets exist in the shape but are **never populated** — both read zero on a
  well that had produced 817946 and shipped 279067. Only `_sum` carries data,
  and it is cumulative since the industry was built. Labels no longer say
  `/yr`. A real rate needs sampling `_sum` against
  `game.interface.getGameTime().time` and differencing — see PLAN.md §2.
- **The low-stock highlight is currently disabled.** It divided stored by
  consumption expecting a rate; against a lifetime total the ratio vanishes and
  every row would flag as a bottleneck. Returns when a rate exists.
- **Per-stop attribution is unavailable for passengers AND for freight.** A
  `SIM_PERSON` carries no field naming the stop it waits at —
  `targetOrAtEntity` is the current leg's target and `destinations[1]` a
  destination *building* — so per-line passenger counts are route-wide.
  Freight fails for a different reason: `getSimCargosForLine` returns only cargo
  already aboard a vehicle (probed twice: 436/436 and 395/395 items with
  `vehicleUsed`), and its `sourceEntity` is the ORIGIN rather than the current
  location. v1.6 shipped a per-line freight breakdown built on that misreading;
  the filter matched nothing and it rendered no rows. Waiting freight is
  therefore reported per commodity for the station as a whole. The "waiting
  here" total IS exact for the stop, so it will not reconcile with the
  route-wide per-line figures. Full list of ruled-out routes in `API-NOTES.md`.
- **Stored is combined on multi-input industries.** The slot ordinal is the
  index into the construction's `stocks` array in declaration order, but no
  runtime route to that array exists — `STOCK_LIST` is opaque to Lua.
- Industry capacity (the `/400` the window shows) cannot be read: it is
  `baseCapacity * (level+1)` per `industryutil.lua:146`, and `baseCapacity`
  lives in each industry's own config rather than on the entity.
