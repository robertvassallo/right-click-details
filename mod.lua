-- Kept at the top level of res/scripts/ rather than in a subdirectory: the
-- shipped build-with-collision mod proves `require "<toplevel>"` resolves from
-- mod.lua, whereas dotted subdirectory requires are only proven from game
-- scripts (which load much later).
local config = require "rlv_cityoverlay_config"

function data()
return {
	info = {
		-- No majorVersion here: it comes from the folder suffix
		-- (RightClickDetailsMod_1). No shipped mod declares it, and an
		-- explicit value that disagrees with the folder is asking for
		-- trouble.
		minorVersion = 6,
		name = _("mod_name"),
		description = _("mod_desc"),
		tags = { "Script Mod", "Misc" },

		-- Pure UI styling: nothing is written into the save game, so this mod
		-- is safe to add to and remove from an existing save.
		severityAdd = "NONE",
		severityRemove = "NONE",

		authors = {
			{
				name = "Smugglemurph",
				role = "CREATOR",
			},
		},

		params = {
			{
				key = "debugLogging",
				name = _("param_debugLogging"),
				tooltip = _("param_debugLogging_tt"),
				uiType = "CHECKBOX",
				values = config.boolLabels,
				defaultIndex = config.defaultIndex.debugLogging,
			},
			{
				key = "dismissMode",
				name = _("param_dismissMode"),
				tooltip = _("param_dismissMode_tt"),
				uiType = "COMBOBOX",
				values = config.dismissLabels,
				defaultIndex = config.defaultIndex.dismissMode,
			},
			{
				key = "panelEnabled",
				name = _("param_panelEnabled"),
				tooltip = _("param_panelEnabled_tt"),
				uiType = "CHECKBOX",
				values = config.boolLabels,
				defaultIndex = config.defaultIndex.panelEnabled,
			},
			-- NOTE: sliders for the visual settings (icon scale, label scale,
			-- spacing) were REMOVED. Stylesheets evaluate in an isolated Lua
			-- state and cannot see values published here, so those sliders
			-- would have done nothing. Tune the visuals in the CONFIG table at
			-- the top of res/config/style_sheet/rlv_cityoverlay.lua instead.
			-- The params below all take effect via runFn or the game script.
			{
				key = "cargoRenderDistance",
				name = _("param_cargoRenderDistance"),
				tooltip = _("param_cargoRenderDistance_tt"),
				uiType = "SLIDER",
				values = config.distLabels,
				defaultIndex = config.defaultIndex.cargoRenderDistance,
			},
			{
				key = "townRenderDistance",
				name = _("param_townRenderDistance"),
				tooltip = _("param_townRenderDistance_tt"),
				uiType = "SLIDER",
				values = config.distLabels,
				defaultIndex = config.defaultIndex.townRenderDistance,
			},
		},
	},

	runFn = function (settings, modparams)
		local params = modparams and modparams[getCurrentModId()] or {}
		local c = config.applyParams(params)

		-- Publish the resolved style values on the shared `game` table.
		-- The stylesheet cannot require this mod's scripts (only the base
		-- game's res/scripts is on the Lua path when stylesheets load), but
		-- runFn demonstrably runs BEFORE stylesheets are read, and `game` is
		-- shared across both. Same mechanism build-with-collision uses for
		-- game.bwC.
		game.rlvCityOverlay = {
			townLabelScale    = c.townLabelScale,
			cargoIconScale    = c.cargoIconScale,
			townBuildingScale = c.townBuildingScale,
			labelInnerSpacing = c.labelInnerSpacing,
			labelPadding      = c.labelPadding,
			panelEnabled      = c.panelEnabled,
			debugLogging      = c.debugLogging,
			dismissMode       = c.dismissMode,
		}

		-- Render distances are plain multipliers on game.config, set the same
		-- way the shipped urbangames_no_costs_1 mod sets game.config.noCosts.
		-- Guarded because the table only exists once base_config.lua has run.
		if game and game.config and game.config.gui and game.config.gui.iconRenderDistances then
			local d = game.config.gui.iconRenderDistances
			d.townBuildingsCargo = c.cargoRenderDistance
			d.towns = c.townRenderDistance
			if c.debugLogging then
				print("[RightClickDetails] runFn: iconRenderDistances towns="
					.. tostring(d.towns)
					.. " townBuildingsCargo=" .. tostring(d.townBuildingsCargo))
			end
		else
			print("[RightClickDetails] WARN: game.config.gui.iconRenderDistances not available")
		end
	end,
}
end
