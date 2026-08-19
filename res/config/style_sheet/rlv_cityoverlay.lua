--[[
	rlv_cityoverlay - city overlay restyling

	Purely stylistic. Adds rules to the existing cascade; does not patch or
	replace res/config/style_sheet/hud.lua.

	IMPORTANT -- do not `require` this mod's own scripts here.
	Stylesheets load in a context where only the BASE GAME's res/scripts is on
	the Lua path. Requiring res/scripts/rlv_cityoverlay_config.lua from this
	file made the whole stylesheet fail with:
	    Failed to load .../res/config/style_sheet/rlv_cityoverlay.lua
	Only "stylesheetutil" and other base-game modules are safe here.

	Settings arrive instead via the `game` table, which mod.lua's runFn
	populates before stylesheets are read (verified from stdout ordering).
	Same mechanism the build-with-collision mod uses for `game.bwC`.

	What is reachable:
	  TownItem                 the city label plate
	  TownItem!hover           its hover state
	  TownItem BoxLayout       gap between name row and commodity row
	  TownItem::CargoItem      the commodity icons  <- the interesting one
	  TownBuildingItem         per-building demand icons

	What is NOT: new subcontrols. TownItem is built in C++ (HudIconManager),
	so its child tree is fixed.
--]]

local ssu = require "stylesheetutil"

-- TUNE HERE.
--
-- Verified at runtime: values published by mod.lua's runFn onto the `game`
-- table are NOT visible from a stylesheet -- the log showed
-- "runFn values unavailable" on every load. Stylesheets evidently evaluate in
-- an isolated Lua state. So these numbers are the real source of truth, and
-- the mod's visual sliders were removed rather than left as decoration.
--
-- Edit and restart the game to see changes.
local CONFIG = {
	-- CITY LABEL: vanilla by default.
	--
	-- These now match the base game exactly, so installing this mod does not
	-- silently resize anyone's city labels. Scaling is opt-in: raise the values
	-- below and restart. It cannot be exposed as an in-game option -- see the
	-- diagnostic further down.
	townLabelScale    = 3 / 2,           -- vanilla 3/2
	cargoIconScale    = 2 / 3,           -- vanilla 2/3  <- commodity icons
	townBuildingScale = 3 / 4,           -- vanilla 3/4
	labelInnerSpacing = 5,               -- vanilla 5
	labelPadding      = { 2, 5, 2, 5 },  -- vanilla { 2, 5, 2, 5 }

	-- Right-click panel.
	-- panelMinWidth is a FIXED value, not a measurement: the city label is
	-- engine-rendered and its width cannot be queried from Lua. Raise or lower
	-- it until it sits comfortably under a typical label on your screen.
	panelMinWidth = 132,
	-- Panel surface tint { r, g, b, a }. Applied over town_background.tga, so
	-- the plate shape is kept but darkened. Lower the RGB for darker still.
	panelTint     = { 34, 41, 49, 245 },
	-- Label column width for the industry readout, so values align.
	-- Wide enough for the longest label, 'Outbound/yr'.
	statLabelWidth = 92,
	-- Stylesheets cannot read mod options; flip by hand to debug styling.
	debugStylesheet = false,
	-- 1px rule between the headline stats and the stocks list.
	dividerTint    = { 120, 135, 150, 160 },

	-- Options window. Sized like a settings dialog rather than a tooltip.
	optionsWidth       = 340,
	optionsLabelWidth  = 150,
	optionsButtonWidth = 130,
	optionsTint        = { 26, 32, 40, 250 },

	-- Icon sizing is done with `scaling` ONLY -- never explicit width/height.
	-- The source textures have different aspect ratios (commodities are
	-- 24x19, passengers is 16x32), so any fixed box distorts them.
	cargoIconScaleInPanel = 2 / 3,   -- matches the base game's CargoItem::Icon
	popIconScale          = 0.5,     -- passengers is double height; scale down
}

function data()
	local result = {}
	local a = ssu.makeAdder(result)
	local c = CONFIG

	-- The stylesheet runs in an ISOLATED Lua state -- confirmed by probe, `game`
	-- is nil here -- so it cannot read the mod's debug option. This is a literal
	-- switch; flip it when investigating styling.
	if CONFIG.debugStylesheet then
		print("[RightClickDetails] stylesheet loaded; cargoIconScale="
			.. tostring(c.cargoIconScale))
	end

	-- -----------------------------------------------------------------------
	-- The city label plate
	-- -----------------------------------------------------------------------

	a("TownItem", {
		scaling = c.townLabelScale,
		padding = c.labelPadding,
		-- Shipped background, restated so it is obvious where to swap art.
		backgroundImage1 = {
			fileName   = "ui/hud/town_background.tga",
			horizontal = { 0, 3, 47, 50 },
			vertical   = { 0, 4, 46, 50 },
		},
		backgroundColor1 = ssu.makeColor(255, 255, 255),
	})

	a("TownItem!hover", {
		backgroundColor1 = ssu.makeColor(200, 200, 200),
	})

	a("TownItem BoxLayout", {
		innerSpacing = { c.labelInnerSpacing, c.labelInnerSpacing },
	})

	-- -----------------------------------------------------------------------
	-- Commodity icons -- the desired-goods icons beside the city name.
	-- Confirmed in game: these match the "Supply" rows of the town window.
	-- Shipped at 2/3, which is why they are hard to read.
	-- -----------------------------------------------------------------------

	a("TownItem::CargoItem", {
		scaling = c.cargoIconScale,
	})

	-- Scope any CargoItem override to TownItem so vehicle/station/cockpit UI
	-- is left alone.
	a("TownItem CargoItem::Layout", {
		innerSpacing = { 5, 0 },
	})

	-- -----------------------------------------------------------------------
	-- Per-building demand icons
	-- -----------------------------------------------------------------------

	a("TownBuildingItem", {
		scaling = c.townBuildingScale,
	})

	a("TownBuildingItem BoxLayout", {
		innerSpacing = { 0, 0 },
	})

	-- -----------------------------------------------------------------------
	-- Right-click commodity panel (built by res/config/game_script/).
	-- Component names must not contain "." or "_" -- engine restriction.
	-- -----------------------------------------------------------------------

	-- Styled to match TownItem's plate (same 9-slice background, same tint) so
	-- the panel reads as the city label unfolding rather than a tooltip
	-- floating nearby. It cannot actually be a child of the label -- TownItem
	-- is engine-rendered -- so visual continuity is doing the work.
	-- BEVELLED CORNERS.
	--
	-- The engine has no borderRadius / corner property -- the full style
	-- property list is backgroundColor/1/2, backgroundImage1/2, borderImage,
	-- borderColor, borderWidth, font*, text*, minSize, maxSize, anchorPoint,
	-- outerSpacing, padding, margin, shadowNinePatch, shadowColor, shadowWidth,
	-- blurRadius, transition*, animation*, soundEffect1/2, actionPromptList.
	-- Corners therefore have to come from ARTWORK.
	--
	-- The game's own rounded panel (ui/design/window/tooltip.tga) carries a
	-- speech-bubble tail at bottom-left, which looks wrong here, so this uses a
	-- generated 32x32 octagon with a 9px 45-degree chamfer, white so
	-- backgroundColor1 tints it. Regenerate at a different bevel by editing
	-- BEVEL in the generator noted in the README.
	-- Our overlay root: a full-screen, invisible, absolutely-positioned host for
	-- the panels. It replaces parenting into the engine's toolTipContainer,
	-- which the engine clears on cursor movement.
	--
	-- Viewport units are deliberate here even though the panels themselves use
	-- pixels: this must cover the screen at any resolution, and vw/vh is the
	-- only way to say that. Same approach as build-with-collision's
	-- full-screen listener component.
	a("rlvDetailsRoot", {
		size    = { "100vw", "100vh" },
		minSize = { "100vw", "100vh" },
		gravity = { 0, 0 },
	})

	a("rlvCityOverlayPanel", {
		backgroundImage1 = {
			fileName   = "ui/rlvcityoverlay/panel_bevel.tga",
			horizontal = { 0, 10, 22, 32 },
			vertical   = { 0, 10, 22, 32 },
		},
		-- Dark tint over the label's 9-slice: keeps the plate shape but reads
		-- as a distinct, recessed surface under the label.
		backgroundColor1 = ssu.makeColor(
			CONFIG.panelTint[1], CONFIG.panelTint[2],
			CONFIG.panelTint[3], CONFIG.panelTint[4]),
		padding = { 6, 9, 6, 9 },
		gravity = { 0.0, 0.0 },

		-- The city label's width CANNOT be measured: TownItem is engine-
		-- rendered and absent from the api.gui tree, so there is nothing to
		-- query. This is a fixed minimum chosen to sit close to a typical
		-- label; the panel still grows if content needs more room. Tune it.
		minSize = { CONFIG.panelMinWidth, -1 },
	})

	a("rlvCityOverlayPanel BoxLayout", {
		innerSpacing = { 3, 3 },
	})

	a("rlvCityOverlayPanel TextView", {
		fontSize = 13,
		padding = { 1, 2, 1, 2 },
	})

	-- THEME VARIANTS.
	--
	-- The stylesheet cannot read settings (isolated state, loads once), so
	-- instead it declares every variant and the game script picks one at build
	-- time with setStyleClassList. That is the only runtime styling lever
	-- available, and it is why themes apply to the NEXT panel opened rather
	-- than restyling one already on screen.
	a("rlvCityOverlayPanel!rlvThemedark", {
		backgroundColor1 = ssu.makeColor(46, 56, 68, 240),
	})

	a("rlvCityOverlayPanel!rlvThemedarker", {
		backgroundColor1 = ssu.makeColor(4, 6, 9, 254),
	})

	a("rlvCityOverlayPanel!rlvThemelight", {
		backgroundColor1 = ssu.makeColor(226, 231, 236, 245),
	})

	-- Light theme needs dark text to stay legible.
	a([[rlvCityOverlayPanel!rlvThemelight TextView,
		rlvCityOverlayPanel!rlvThemelight TextView!rlvTitle,
		rlvCityOverlayPanel!rlvThemelight TextView!rlvStatValue,
		rlvCityOverlayPanel!rlvThemelight TextView!rlvResidents]], {
		color = ssu.makeColor(24, 30, 38),
	})

	a([[rlvCityOverlayPanel!rlvThemelight TextView!rlvStatLabel,
		rlvCityOverlayPanel!rlvThemelight TextView!rlvPopCaption,
		rlvCityOverlayPanel!rlvThemelight TextView!rlvDest]], {
		color = ssu.makeColor(78, 90, 104),
	})

	-- OPTIONS PANEL -- sized like a proper settings window, not a tooltip.
	-- The detail panels are deliberately compact; this one is read and
	-- interacted with, so it gets room to breathe.
	a("rlvDetailsOptions", {
		backgroundImage1 = {
			fileName   = "ui/rlvcityoverlay/panel_bevel.tga",
			horizontal = { 0, 10, 22, 32 },
			vertical   = { 0, 10, 22, 32 },
		},
		backgroundColor1 = ssu.makeColor(
			CONFIG.optionsTint[1], CONFIG.optionsTint[2],
			CONFIG.optionsTint[3], CONFIG.optionsTint[4]),
		minSize = { CONFIG.optionsWidth, -1 },
		padding = { 16, 20, 16, 20 },
		-- Placed by gravity/margin, not a Rect: it lives in a mainView layer's
		-- box layout so it can receive clicks, and box layouts do not do
		-- absolute positioning.
		gravity = { 0.0, 0.0 },
		margin = { 120, 60, 0, 0 },
	})

	a("rlvDetailsOptions BoxLayout", {
		innerSpacing = { 8, 8 },
	})

	a("rlvDetailsOptions TextView", {
		fontSize = 15,
	})

	-- Fixed label column so the value buttons line up down the panel.
	a("rlvDetailsOptions TextView!rlvOptLabel", {
		fontSize = 15,
		minSize = { CONFIG.optionsLabelWidth, -1 },
		gravity = { 0.0, 0.5 },
		color = ssu.makeColor(210, 216, 222),
	})

	a("rlvDetailsOptionRow BoxLayout", {
		innerSpacing = { 12, 0 },
	})

	-- Dropdown control. ComboBox renders its own button and popup list, so the
	-- styling targets both -- the popup is a separate component tree and does
	-- not inherit the panel's rules.
	a("rlvDetailsOptions ComboBox!rlvOptCombo", {
		minSize = { CONFIG.optionsButtonWidth, 28 },
		gravity = { 0.0, 0.5 },
	})

	-- Appearance comes from the game's own "style-popup" rules in default.lua
	-- (background, hover, active), which the control opts into. Only sizing and
	-- text treatment are set here, so the dropdowns match the settings menu.
	a("rlvDetailsOptions ComboBox!rlvOptCombo TextView", {
		fontSize = 14,
		textTransform = "NONE",
	})

	a("rlvDetailsOptions Button!rlvOptButton", {
		minSize = { CONFIG.optionsButtonWidth, 28 },
		backgroundColor = ssu.makeColor(255, 255, 255, 26),
		borderColor = ssu.makeColor(150, 165, 180, 120),
		borderWidth = { 1, 1, 1, 1 },
	})

	a("rlvDetailsOptions Button!rlvOptButton:hover", {
		backgroundColor = ssu.makeColor(255, 255, 255, 62),
	})

	-- DEBUG TOGGLE -- the ladybug in the settings footer.
	--
	-- NO `color` here. The two states are two baked RGBA textures swapped in
	-- Lua (see the toggle's applyDebugStyle): dim slate when logging is off,
	-- ladybird red when on. Tinting one greyscale mask was the original design
	-- and cannot work -- `color` on an ImageView only affects RGBA art, so a
	-- mode "L" file renders raw and ignores the stylesheet.
	--
	-- No background or border in either state: it should read as a status glyph
	-- in the corner, not a second button competing with Close.
	a("rlvDetailsOptions Button!rlvDebugBtn", {
		backgroundColor = ssu.makeColor(255, 255, 255, 0),
		borderWidth = { 0, 0, 0, 0 },
		minSize = { 26, 26 },
	})
	a("ImageView!rlvDebugIcon", {
		size = { 18, 18 },
		gravity = { 0.5, 0.5 },
	})

a("rlvDetailsOptions Button::Text", {
		fontSize = 14,
		textTransform = "NONE",
	})

	-- TOOLBAR BUTTON.
	--
	-- The disc, ring and glyph are BAKED into one RGBA texture
	-- (tools/make_toolbar_button.py). The engine's UI art is 8-bit greyscale
	-- coverage and `color` on an ImageView only tints RGBA, so a mode "L" mask
	-- renders raw and comes out grey -- confirmed by swapping in the game's own
	-- bulldozer icon, which was equally grey. Baking does the tinting in Python
	-- and hands the engine a finished image.
	--
	-- HOVER AND PRESSED reuse the very behaviour that made the glyph grey
	-- earlier: a Button's backgroundImage composites OVER its child. As a base
	-- state that was a bug; as a hover state it is exactly right -- a lighter
	-- disc washed over the baked one. So the Button is transparent at rest and
	-- only paints on hover/active.
	--
	-- Values are game-menu.lua:154 verbatim, the rule shared by
	-- ConstructionMenuIndicator, LineManagerButton, VehicleManagerButton and
	-- BulldozerButton:
	--     hover    fill 183,188,193 @128   ring solid white
	--     pressed  fill 110,122,132
	--
	-- `backgroundColor` (no digit) stays cleared in every state -- default.lua:112
	-- sets it white@50 on hover and white@100 on active, which would draw a
	-- SQUARE behind the disc. Different property from backgroundColor1/2.
	a("rlvDetailsToolbarButton Button", {
		backgroundColor = ssu.makeColor(255, 255, 255, 0),
		borderWidth = { 0, 0, 0, 0 },
	})

	a("rlvDetailsToolbarButton Button:hover", {
		backgroundColor = ssu.makeColor(255, 255, 255, 0),
		backgroundImage1 = { fileName = "ui/design/buttons/disk_big_surface.tga" },
		backgroundColor1 = ssu.makeColor(183, 188, 193, 128),
		borderImage = { fileName = "ui/design/buttons/disk_big_contour.tga" },
		borderColor = ssu.makeColor(255, 255, 255),
	})

	a("rlvDetailsToolbarButton Button:active", {
		backgroundColor = ssu.makeColor(255, 255, 255, 0),
		backgroundImage1 = { fileName = "ui/design/buttons/disk_big_surface.tga" },
		backgroundColor1 = ssu.makeColor(110, 122, 132),
		borderImage = { fileName = "ui/design/buttons/disk_big_contour.tga" },
		borderColor = ssu.makeColor(255, 255, 255),
	})

	a("ImageView!rlvToolbarIcon", {
		size = { 60, 60 },
		gravity = { 0.5, 0.5 },
	})

	-- HORIZONTAL margin only. It was { 0, 4, 0, 4 } -- 4px top and bottom --
	-- which pushed the 60px disc past the bar's height and clipped it.
	a("rlvDetailsToolbarButton", {
		margin = { 4, 0, 4, 0 },
	})

	-- Output commodity icons leading an industry's title. scaling only -- the
	-- source textures are not square, so any fixed box distorts them.
	a("rlvCityOverlayHeader ImageView!rlvOutIcon", {
		scaling = 2 / 3,
		gravity = { 0.0, 0.5 },
	})

	-- Entity name, styled as a title: uppercase and bold.
	--
	-- textTransform and fontWeight are both real style properties; valid
	-- weights are Regular, Bold, MonoRegular, MonoBold. The base game styles
	-- Window::Title the same way (fontSize 16, UPPERCASE), so this reads as
	-- native rather than invented.
	a("rlvCityOverlayPanel TextView!rlvTitle", {
		fontSize = 14,
		fontWeight = "Bold",
		textTransform = "UPPERCASE",
		gravity = { 0.0, 0.5 },
		padding = { 1, 2, 3, 2 },
	})

	-- Header: passenger icon + population. No town name -- the label above
	-- already shows it.
	a("rlvCityOverlayHeader BoxLayout", {
		innerSpacing = { 7, 0 },
	})

	a("rlvCityOverlayPanel TextView!rlvResidents", {
		fontSize = 14,
		gravity = { 0.0, 0.5 },
	})

	-- "Population" caption: subordinate to the number beside it.
	a("rlvCityOverlayPanel TextView!rlvPopCaption", {
		fontSize = 12,
		color = ssu.makeColor(200, 205, 210),
		gravity = { 0.0, 0.5 },
	})

	a("rlvCityOverlayRow BoxLayout", {
		innerSpacing = { 7, 0 },
	})

	-- Industry readout: "Label   value" pairs. Fixed label column so the
	-- values line up down the panel instead of ragged.
	a("rlvCityOverlayPanel TextView!rlvStatLabel", {
		fontSize = 13,
		color = ssu.makeColor(200, 205, 210),
		minSize = { CONFIG.statLabelWidth, -1 },
		gravity = { 0.0, 0.5 },
	})

	a("rlvCityOverlayPanel TextView!rlvStatValue", {
		fontSize = 13,
		gravity = { 0.0, 0.5 },
	})

	-- 1px horizontal rule separating the headline stats from the stocks list.
	-- size = {-1, 1} is "fill width, one pixel tall" -- -1 is the engine's fill
	-- sentinel, the same convention as the shipped ProgressBar rule.
	a("rlvCityOverlayDivider", {
		size    = { -1, 1 },
		minSize = { -1, 1 },
		maxSize = { -1, 1 },
		backgroundColor = ssu.makeColor(
			CONFIG.dividerTint[1], CONFIG.dividerTint[2],
			CONFIG.dividerTint[3], CONFIG.dividerTint[4]),
		margin = { 3, 0, 3, 0 },
	})

	-- Stored figure when the material is running short relative to how fast it
	-- is consumed. This is the one thing on the panel meant to catch the eye.
	a("rlvCityOverlayPanel TextView!rlvLowStock", {
		fontSize = 13,
		color = ssu.makeColor(255, 150, 150),
		gravity = { 0.0, 0.5 },
	})

	-- "→ Destination" on station cargo rows: subordinate to the amount.
	a("rlvCityOverlayPanel TextView!rlvDest", {
		fontSize = 12,
		color = ssu.makeColor(170, 200, 225),
		gravity = { 0.0, 0.5 },
	})

	-- LINE DOT -- the bullet leading a per-line passenger row.
	--
	-- Colour is NOT set here: each line has its own arbitrary RGB, read from its
	-- COLOR component at runtime and applied per instance. This rule only fixes
	-- the size and spacing, and provides the fallback colour for when the
	-- runtime tint does not take -- a neutral grey, so the row still reads as a
	-- bullet rather than disappearing.
	--
	-- It sits where a cargo icon would on a freight row, so the two row types
	-- line up in the same column.
	-- LINE DOT COLOURS -- a quantised RGB grid, 6 levels per channel.
	--
	-- Line colour is arbitrary per line, read from its COLOR component at
	-- runtime, and it CANNOT be applied directly: setColor exists as a bound
	-- method but rejected every argument form tried (floats, 0-1 table, 0-255
	-- table), and api.gui.util has no Color type. Only setStyleClassList works,
	-- so the colour has to already exist as a class.
	--
	-- Matching the game's own palette was the obvious idea and does not work:
	-- game.config.gui.lineColors holds 100 entries at runtime whose first is
	-- (246,206,206), while base_config.lua declares 50 starting (94,47,0) --
	-- something extends it after load. A stylesheet cannot read `game` either,
	-- so the palette is simply not knowable here.
	--
	-- A fixed grid sidesteps all of it: 6 levels per channel = 216 classes,
	-- index r*36 + g*6 + b. lineDotClass() snaps a line's RGB to the nearest
	-- level. Worst-case error is ~25 per channel, invisible on a bullet, and it
	-- works for modded line colours too.
	a("rlvCityOverlayPanel TextView!rlvDot0", { color = ssu.makeColor(0, 0, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot1", { color = ssu.makeColor(0, 0, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot2", { color = ssu.makeColor(0, 0, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot3", { color = ssu.makeColor(0, 0, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot4", { color = ssu.makeColor(0, 0, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot5", { color = ssu.makeColor(0, 0, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot6", { color = ssu.makeColor(0, 51, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot7", { color = ssu.makeColor(0, 51, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot8", { color = ssu.makeColor(0, 51, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot9", { color = ssu.makeColor(0, 51, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot10", { color = ssu.makeColor(0, 51, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot11", { color = ssu.makeColor(0, 51, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot12", { color = ssu.makeColor(0, 102, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot13", { color = ssu.makeColor(0, 102, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot14", { color = ssu.makeColor(0, 102, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot15", { color = ssu.makeColor(0, 102, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot16", { color = ssu.makeColor(0, 102, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot17", { color = ssu.makeColor(0, 102, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot18", { color = ssu.makeColor(0, 153, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot19", { color = ssu.makeColor(0, 153, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot20", { color = ssu.makeColor(0, 153, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot21", { color = ssu.makeColor(0, 153, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot22", { color = ssu.makeColor(0, 153, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot23", { color = ssu.makeColor(0, 153, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot24", { color = ssu.makeColor(0, 204, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot25", { color = ssu.makeColor(0, 204, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot26", { color = ssu.makeColor(0, 204, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot27", { color = ssu.makeColor(0, 204, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot28", { color = ssu.makeColor(0, 204, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot29", { color = ssu.makeColor(0, 204, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot30", { color = ssu.makeColor(0, 255, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot31", { color = ssu.makeColor(0, 255, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot32", { color = ssu.makeColor(0, 255, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot33", { color = ssu.makeColor(0, 255, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot34", { color = ssu.makeColor(0, 255, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot35", { color = ssu.makeColor(0, 255, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot36", { color = ssu.makeColor(51, 0, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot37", { color = ssu.makeColor(51, 0, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot38", { color = ssu.makeColor(51, 0, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot39", { color = ssu.makeColor(51, 0, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot40", { color = ssu.makeColor(51, 0, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot41", { color = ssu.makeColor(51, 0, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot42", { color = ssu.makeColor(51, 51, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot43", { color = ssu.makeColor(51, 51, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot44", { color = ssu.makeColor(51, 51, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot45", { color = ssu.makeColor(51, 51, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot46", { color = ssu.makeColor(51, 51, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot47", { color = ssu.makeColor(51, 51, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot48", { color = ssu.makeColor(51, 102, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot49", { color = ssu.makeColor(51, 102, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot50", { color = ssu.makeColor(51, 102, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot51", { color = ssu.makeColor(51, 102, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot52", { color = ssu.makeColor(51, 102, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot53", { color = ssu.makeColor(51, 102, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot54", { color = ssu.makeColor(51, 153, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot55", { color = ssu.makeColor(51, 153, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot56", { color = ssu.makeColor(51, 153, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot57", { color = ssu.makeColor(51, 153, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot58", { color = ssu.makeColor(51, 153, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot59", { color = ssu.makeColor(51, 153, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot60", { color = ssu.makeColor(51, 204, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot61", { color = ssu.makeColor(51, 204, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot62", { color = ssu.makeColor(51, 204, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot63", { color = ssu.makeColor(51, 204, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot64", { color = ssu.makeColor(51, 204, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot65", { color = ssu.makeColor(51, 204, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot66", { color = ssu.makeColor(51, 255, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot67", { color = ssu.makeColor(51, 255, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot68", { color = ssu.makeColor(51, 255, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot69", { color = ssu.makeColor(51, 255, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot70", { color = ssu.makeColor(51, 255, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot71", { color = ssu.makeColor(51, 255, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot72", { color = ssu.makeColor(102, 0, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot73", { color = ssu.makeColor(102, 0, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot74", { color = ssu.makeColor(102, 0, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot75", { color = ssu.makeColor(102, 0, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot76", { color = ssu.makeColor(102, 0, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot77", { color = ssu.makeColor(102, 0, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot78", { color = ssu.makeColor(102, 51, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot79", { color = ssu.makeColor(102, 51, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot80", { color = ssu.makeColor(102, 51, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot81", { color = ssu.makeColor(102, 51, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot82", { color = ssu.makeColor(102, 51, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot83", { color = ssu.makeColor(102, 51, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot84", { color = ssu.makeColor(102, 102, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot85", { color = ssu.makeColor(102, 102, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot86", { color = ssu.makeColor(102, 102, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot87", { color = ssu.makeColor(102, 102, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot88", { color = ssu.makeColor(102, 102, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot89", { color = ssu.makeColor(102, 102, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot90", { color = ssu.makeColor(102, 153, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot91", { color = ssu.makeColor(102, 153, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot92", { color = ssu.makeColor(102, 153, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot93", { color = ssu.makeColor(102, 153, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot94", { color = ssu.makeColor(102, 153, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot95", { color = ssu.makeColor(102, 153, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot96", { color = ssu.makeColor(102, 204, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot97", { color = ssu.makeColor(102, 204, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot98", { color = ssu.makeColor(102, 204, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot99", { color = ssu.makeColor(102, 204, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot100", { color = ssu.makeColor(102, 204, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot101", { color = ssu.makeColor(102, 204, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot102", { color = ssu.makeColor(102, 255, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot103", { color = ssu.makeColor(102, 255, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot104", { color = ssu.makeColor(102, 255, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot105", { color = ssu.makeColor(102, 255, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot106", { color = ssu.makeColor(102, 255, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot107", { color = ssu.makeColor(102, 255, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot108", { color = ssu.makeColor(153, 0, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot109", { color = ssu.makeColor(153, 0, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot110", { color = ssu.makeColor(153, 0, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot111", { color = ssu.makeColor(153, 0, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot112", { color = ssu.makeColor(153, 0, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot113", { color = ssu.makeColor(153, 0, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot114", { color = ssu.makeColor(153, 51, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot115", { color = ssu.makeColor(153, 51, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot116", { color = ssu.makeColor(153, 51, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot117", { color = ssu.makeColor(153, 51, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot118", { color = ssu.makeColor(153, 51, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot119", { color = ssu.makeColor(153, 51, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot120", { color = ssu.makeColor(153, 102, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot121", { color = ssu.makeColor(153, 102, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot122", { color = ssu.makeColor(153, 102, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot123", { color = ssu.makeColor(153, 102, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot124", { color = ssu.makeColor(153, 102, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot125", { color = ssu.makeColor(153, 102, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot126", { color = ssu.makeColor(153, 153, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot127", { color = ssu.makeColor(153, 153, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot128", { color = ssu.makeColor(153, 153, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot129", { color = ssu.makeColor(153, 153, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot130", { color = ssu.makeColor(153, 153, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot131", { color = ssu.makeColor(153, 153, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot132", { color = ssu.makeColor(153, 204, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot133", { color = ssu.makeColor(153, 204, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot134", { color = ssu.makeColor(153, 204, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot135", { color = ssu.makeColor(153, 204, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot136", { color = ssu.makeColor(153, 204, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot137", { color = ssu.makeColor(153, 204, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot138", { color = ssu.makeColor(153, 255, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot139", { color = ssu.makeColor(153, 255, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot140", { color = ssu.makeColor(153, 255, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot141", { color = ssu.makeColor(153, 255, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot142", { color = ssu.makeColor(153, 255, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot143", { color = ssu.makeColor(153, 255, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot144", { color = ssu.makeColor(204, 0, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot145", { color = ssu.makeColor(204, 0, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot146", { color = ssu.makeColor(204, 0, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot147", { color = ssu.makeColor(204, 0, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot148", { color = ssu.makeColor(204, 0, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot149", { color = ssu.makeColor(204, 0, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot150", { color = ssu.makeColor(204, 51, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot151", { color = ssu.makeColor(204, 51, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot152", { color = ssu.makeColor(204, 51, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot153", { color = ssu.makeColor(204, 51, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot154", { color = ssu.makeColor(204, 51, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot155", { color = ssu.makeColor(204, 51, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot156", { color = ssu.makeColor(204, 102, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot157", { color = ssu.makeColor(204, 102, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot158", { color = ssu.makeColor(204, 102, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot159", { color = ssu.makeColor(204, 102, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot160", { color = ssu.makeColor(204, 102, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot161", { color = ssu.makeColor(204, 102, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot162", { color = ssu.makeColor(204, 153, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot163", { color = ssu.makeColor(204, 153, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot164", { color = ssu.makeColor(204, 153, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot165", { color = ssu.makeColor(204, 153, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot166", { color = ssu.makeColor(204, 153, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot167", { color = ssu.makeColor(204, 153, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot168", { color = ssu.makeColor(204, 204, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot169", { color = ssu.makeColor(204, 204, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot170", { color = ssu.makeColor(204, 204, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot171", { color = ssu.makeColor(204, 204, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot172", { color = ssu.makeColor(204, 204, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot173", { color = ssu.makeColor(204, 204, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot174", { color = ssu.makeColor(204, 255, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot175", { color = ssu.makeColor(204, 255, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot176", { color = ssu.makeColor(204, 255, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot177", { color = ssu.makeColor(204, 255, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot178", { color = ssu.makeColor(204, 255, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot179", { color = ssu.makeColor(204, 255, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot180", { color = ssu.makeColor(255, 0, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot181", { color = ssu.makeColor(255, 0, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot182", { color = ssu.makeColor(255, 0, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot183", { color = ssu.makeColor(255, 0, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot184", { color = ssu.makeColor(255, 0, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot185", { color = ssu.makeColor(255, 0, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot186", { color = ssu.makeColor(255, 51, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot187", { color = ssu.makeColor(255, 51, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot188", { color = ssu.makeColor(255, 51, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot189", { color = ssu.makeColor(255, 51, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot190", { color = ssu.makeColor(255, 51, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot191", { color = ssu.makeColor(255, 51, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot192", { color = ssu.makeColor(255, 102, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot193", { color = ssu.makeColor(255, 102, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot194", { color = ssu.makeColor(255, 102, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot195", { color = ssu.makeColor(255, 102, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot196", { color = ssu.makeColor(255, 102, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot197", { color = ssu.makeColor(255, 102, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot198", { color = ssu.makeColor(255, 153, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot199", { color = ssu.makeColor(255, 153, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot200", { color = ssu.makeColor(255, 153, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot201", { color = ssu.makeColor(255, 153, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot202", { color = ssu.makeColor(255, 153, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot203", { color = ssu.makeColor(255, 153, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot204", { color = ssu.makeColor(255, 204, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot205", { color = ssu.makeColor(255, 204, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot206", { color = ssu.makeColor(255, 204, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot207", { color = ssu.makeColor(255, 204, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot208", { color = ssu.makeColor(255, 204, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot209", { color = ssu.makeColor(255, 204, 255) })
	a("rlvCityOverlayPanel TextView!rlvDot210", { color = ssu.makeColor(255, 255, 0) })
	a("rlvCityOverlayPanel TextView!rlvDot211", { color = ssu.makeColor(255, 255, 51) })
	a("rlvCityOverlayPanel TextView!rlvDot212", { color = ssu.makeColor(255, 255, 102) })
	a("rlvCityOverlayPanel TextView!rlvDot213", { color = ssu.makeColor(255, 255, 153) })
	a("rlvCityOverlayPanel TextView!rlvDot214", { color = ssu.makeColor(255, 255, 204) })
	a("rlvCityOverlayPanel TextView!rlvDot215", { color = ssu.makeColor(255, 255, 255) })

	-- The one exact per-stop figure on the panel. Yellow because every number
	-- under it is a whole-line total, and in a narrow column the colour
	-- separates the two faster than any label can.
	--
	-- Matches BulldozerButton::Icon's yellow (game-menu.lua:151) so it reads as
	-- the game's own highlight rather than an arbitrary colour.
	-- Throughput figures: background context, deliberately recessive so the
	-- line rows and the panel heading stay dominant. Same grey as the muted
	-- destination text already used on cargo rows.
	a([[rlvCityOverlayPanel TextView!rlvStatMuted]], {
		fontSize = 12,
		color = ssu.makeColor(130, 145, 160),
		gravity = { 1.0, 0.5 },
	})

	-- Leading icon on an icon-led stat row. scaling ONLY -- the passengers
	-- texture is 16x32, so any fixed box distorts it (see the icon aspect-ratio
	-- note further down).
	a("rlvCityOverlayPanel ImageView!rlvRowIcon", {
		scaling = 0.5,
		gravity = { 0.0, 0.5 },
		margin = { 0, 0, 4, 0 },
	})

	a("rlvCityOverlayPanel TextView!rlvHighlight", {
		fontSize = 12,
		color = ssu.makeColor(255, 255, 0),
		gravity = { 1.0, 0.5 },
	})

	-- THEME-AWARE HIGHLIGHT AND MUTED TEXT.
	--
	-- Theme overrides win by SPECIFICITY, not position -- the extra
	-- !rlvThemelight class outranks the base rule wherever either sits.
	--
	-- The highlight is yellow on the dark themes, which is unreadable on light.
	-- A dark amber keeps the same "this is the exact figure" signal while
	-- staying legible on a pale plate.
	a("rlvCityOverlayPanel!rlvThemelight TextView!rlvHighlight", {
		color = ssu.makeColor(150, 95, 0),
	})

	-- Muted throughput text: recessive against a light plate rather than a dark
	-- one, so it lightens instead of darkening.
	a("rlvCityOverlayPanel!rlvThemelight TextView!rlvStatMuted", {
		color = ssu.makeColor(120, 132, 145),
	})


	-- Blank vertical gap. size {-1, N}: -1 is the FILL sentinel for width, N the
	-- height in pixels -- same idiom as the divider directly below.
	a("rlvCityOverlaySpacer", {
		size = { -1, 6 },
	})

	-- Geometry only -- NO colour here.
	--
	-- This rule is declared AFTER the 216 rlvDot* classes, so any `color` it set
	-- would win the cascade and repaint every line dot the same grey. That is
	-- exactly what happened: the runtime was picking the right class all along
	-- (log: "rgb 247 129 129 -> class rlvDot201") and this rule silently
	-- overrode it.
	--
	-- The fallback for a line with no colour is rlvDotNone below, applied from
	-- Lua instead, so it cannot clobber a real colour.
	-- fontSize sets the DISC SIZE: the dot is a U+25CF glyph, not an image, so
	-- its diameter is font metrics. 18 against the row's 12pt text gives a disc
	-- that reads as a line marker rather than a bullet point.
	-- The count on a per-line row. Left-aligned and fixed-width so the numbers
	-- form a column between the dots and the names; rlvStatValue right-aligns
	-- for label/value rows and would push it away from its dot.
	a("rlvCityOverlayPanel TextView!rlvLineCount", {
		fontSize = 12,
		color = ssu.makeColor(210, 220, 230),
		-- RIGHT-aligned inside a fixed column. Left alignment gave a ragged gap:
		-- a 2-digit count sat at the column's left edge with ~20px of air before
		-- the line name, so nothing lined up and the pair read as disconnected.
		-- Right alignment puts every number's last digit on the same x, and puts
		-- all of them hard against the name.
		gravity = { 1.0, 0.5 },
		minSize = { 30, -1 },
		margin = { 0, 0, 4, 0 },
	})
	-- The per-line count is near-white for the dark themes and would disappear
	-- on a pale plate.
	--
	-- Placement does not matter for THEME overrides: the extra !rlvThemelight
	-- class makes them more specific than the base rule, and specificity beats
	-- declaration order here. The six pre-existing light overrides sit ~200
	-- lines BEFORE their bases and have always worked.
	--
	-- Order only decides between rules of EQUAL specificity on the same element
	-- -- which is what made every line dot grey when rlvLineDot carried a colour
	-- alongside rlvDot<n>.
	a("rlvCityOverlayPanel!rlvThemelight TextView!rlvLineCount", {
		color = ssu.makeColor(24, 30, 38),
	})

	a("rlvCityOverlayPanel TextView!rlvLineDot", {
		fontSize = 18,
		gravity = { 0.0, 0.5 },
		-- Fixed width so the dot occupies the same column on every row; without
		-- it the glyph's own advance width varies with the theme font and the
		-- counts beside it drift row to row.
		minSize = { 16, -1 },
		margin = { 0, 0, 3, 0 },
	})

	a("rlvCityOverlayPanel TextView!rlvDotNone", {
		color = ssu.makeColor(150, 165, 180),
	})

	-- ICON ASPECT RATIO -- two separate traps here, both hit in earlier builds:
	--
	-- 1. gravity -1 is the FILL sentinel in this engine (same meaning as
	--    size = {-1, 4}). On an ImageView it stretches the icon to the column
	--    width. Use 0.0 to align without resizing.
	--
	-- 2. The source textures are NOT square, and they differ from each other:
	--       cargo_goods / tools / construction_materials   24 x 19
	--       cargo_passengers                               16 x 32
	--    So pinning size/minSize/maxSize to a square box distorts every one of
	--    them. Only `scaling` preserves aspect -- which is why the base game
	--    styles CargoItem::Icon and TownItem::CargoItem with scaling alone.
	--
	-- Never reintroduce explicit sizes here.
	a("rlvCityOverlayRow ImageView", {
		scaling = CONFIG.cargoIconScaleInPanel,
		gravity = { 0.0, 0.5 },
	})

	-- Passenger is 16x32 -- twice as tall as wide -- so it needs its own,
	-- smaller scaling or it towers over the commodity rows.
	a("rlvCityOverlayHeader ImageView", {
		scaling = CONFIG.popIconScale,
		gravity = { 0.0, 0.5 },
	})

	return result
end
