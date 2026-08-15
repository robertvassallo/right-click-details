--[[
	rlv_cityoverlay - shared config

	Single source of truth for the numbers used by both mod.lua (runFn) and
	res/config/style_sheet/rlv_cityoverlay.lua.

	All lengths here are plain numbers = pixels (UI::LengthLegacy). The engine
	also accepts "NNvw" / "NNvh" strings, but this mod deliberately sticks to
	pixel units.
--]]

local config = {}

-- ---------------------------------------------------------------------------
-- Shipped values, for reference when tuning.
-- From res/config/style_sheet/hud.lua in the base game:
--   TownItem              scaling      = 3/2
--   TownItem::CargoItem   scaling      = 2/3   <- the commodity icons
--   TownBuildingItem      scaling      = 3/4
--   TownItem BoxLayout    innerSpacing = { 5, 5 }
--   TownItem              padding      = { 2, 5, 2, 5 }
-- From res/config/base_config.lua:
--   iconRenderDistances.towns              = 1.0
--   iconRenderDistances.townBuildingsCargo = 1.0
-- ---------------------------------------------------------------------------

config.defaults = {
	townLabelScale       = 3 / 2,           -- shipped 3/2
	cargoIconScale       = 1.0,             -- shipped 2/3 - bumped so commodities read
	townBuildingScale    = 1.0,             -- shipped 3/4
	labelInnerSpacing    = 7,               -- shipped 5
	labelPadding         = { 4, 8, 4, 8 },  -- shipped { 2, 5, 2, 5 }
	townRenderDistance   = 1.0,             -- shipped 1.0
	cargoRenderDistance  = 2.0,             -- shipped 1.0 - see commodities further out
}

-- ---------------------------------------------------------------------------
-- Parameter value tables. Mod params are index-based (0-based), so each
-- setting needs a label list plus the matching numeric list.
-- ---------------------------------------------------------------------------

config.scaleLabels  = { "50%", "67%", "75%", "100%", "125%", "150%", "200%" }
config.scaleValues  = { 0.5, 2 / 3, 0.75, 1.0, 1.25, 1.5, 2.0 }

config.distLabels   = { "1x", "1.5x", "2x", "3x", "4x" }
config.distValues   = { 1.0, 1.5, 2.0, 3.0, 4.0 }

config.spacingLabels = { "0", "3", "5", "7", "10", "14" }
config.spacingValues = { 0, 3, 5, 7, 10, 14 }

-- Checkbox params use this fixed value list (the convention other TF2 mods
-- follow); index 0 = off, 1 = on.
config.boolLabels = { "false", "true", "dummy" }

-- How the panel goes away. Index order must match dismissMode below.
config.dismissLabels = { "Click off", "Mouse moves", "Sticky" }
config.dismissValues = { "click", "move", "sticky" }

-- Default selections, expressed as 0-based indices into the lists above.
config.defaultIndex = {
	townLabelScale      = 3,  -- 100% (of the shipped 3/2)
	cargoIconScale      = 3,  -- 100%
	townBuildingScale   = 3,  -- 100%
	labelInnerSpacing   = 3,  -- 7px
	townRenderDistance  = 0,  -- 1x
	cargoRenderDistance = 2,  -- 2x
	panelEnabled        = 1,  -- on
	debugLogging        = 0,  -- off: this mod is published
	dismissMode         = 0,  -- click off
}

-- Populated by mod.lua's runFn. May still be nil when the stylesheet runs --
-- see config.get().
config.resolved = nil

-- Index helper: mod params are 0-based, Lua tables are 1-based.
local function pick(list, idx, fallback)
	if type(idx) ~= "number" then return fallback end
	return list[idx + 1] or fallback
end

--- Resolve raw mod params into concrete numbers and cache them.
function config.applyParams(params)
	params = params or {}
	local d = config.defaults

	config.resolved = {
		-- Scale params multiply the shipped base scaling rather than replacing
		-- it, so "100%" always means "looks like vanilla".
		townLabelScale      = (3 / 2) * pick(config.scaleValues,   params.townLabelScale,      1.0),
		cargoIconScale      = (2 / 3) * pick(config.scaleValues,   params.cargoIconScale,      1.5),
		townBuildingScale   = (3 / 4) * pick(config.scaleValues,   params.townBuildingScale,   1.0),
		labelInnerSpacing   =           pick(config.spacingValues, params.labelInnerSpacing,   d.labelInnerSpacing),
		townRenderDistance  =           pick(config.distValues,    params.townRenderDistance,  d.townRenderDistance),
		cargoRenderDistance =           pick(config.distValues,    params.cargoRenderDistance, d.cargoRenderDistance),
		labelPadding        = d.labelPadding,

		-- Read by res/config/game_script/rlv_cityoverlay.lua via the shared
		-- `game` table. Checkbox params arrive as 0 / 1.
		panelEnabled = (params.panelEnabled == nil) or (params.panelEnabled == 1),
		-- Off by default. Players only turn this on to produce a log for a
		-- bug report; it is very chatty.
		debugLogging = (params.debugLogging == 1),
		dismissMode  = pick(config.dismissValues, params.dismissMode, "click"),
	}

	return config.resolved
end

--- Return the values to style with.
--
-- NOTE (unverified): mod.lua's runFn and res/config/style_sheet/*.lua are
-- loaded at different points in startup, and may not even share a Lua state.
-- If they do share one, the stylesheet picks up the player's slider settings.
-- If they don't, it falls back to config.defaults and the sliders only affect
-- the runFn-driven settings (render distances).
--
-- The print below resolves that question on the first run: check
--   ~/.steam/steam/userdata/24778163/1066780/local/crash_dump/stdout.txt
-- for which branch was taken.
function config.get()
	if config.resolved then
		print("[rlv_cityoverlay] stylesheet: using resolved mod settings")
		return config.resolved
	end

	print("[rlv_cityoverlay] stylesheet: runFn values unavailable, using defaults")

	local d = config.defaults
	return {
		townLabelScale      = d.townLabelScale,
		cargoIconScale      = d.cargoIconScale,
		townBuildingScale   = d.townBuildingScale,
		labelInnerSpacing   = d.labelInnerSpacing,
		labelPadding        = d.labelPadding,
		townRenderDistance  = d.townRenderDistance,
		cargoRenderDistance = d.cargoRenderDistance,
	}
end

return config
