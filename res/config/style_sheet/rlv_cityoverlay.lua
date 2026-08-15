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
