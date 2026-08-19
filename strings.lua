function data()
return {
	en = {
		mod_name = "Right Click Details",
		mod_desc = "Right-click a town, industry, station or depot for a compact readout, "
			.. "without opening the full window. Built for spotting a logistics problem and "
			.. "moving on.\n\n"
			.. "TOWNS show population and the commodities they want, with supply and fill "
			.. "percentage.\n\n"
			.. "INDUSTRIES show level, transport rating, what has been produced and shipped, "
			.. "and stored versus used per input commodity.\n\n"
			.. "STATIONS AND STOPS break down by line, each with its own colour so you "
			.. "can match a row to the line at a glance. Passengers show the exact number "
			.. "waiting at the stop, then how many people are travelling on each line "
			.. "serving it. Freight shows what is waiting here against the station's "
			.. "capacity, then a row per line and commodity. Inbound and outbound "
			.. "throughput sit underneath.\n\n"
			.. "Right-click the same spot again to cycle through anything else nearby, or "
			.. "to fold the panel away.\n\n"
			.. "SETTINGS live behind the mouse button in the HUD bar, beside the bulldozer - "
			.. "turn the panel on or off, choose how it closes (click off, on mouse move, or "
			.. "sticky), decide when a town's name is shown, and pick a panel theme. Escape "
			.. "closes whichever panel is open. Settings are saved with your game.\n\n"
			.. "Large figures are abbreviated, so a commodity sitting on 62500 units reads as "
			.. "62.5K rather than stretching the panel.\n\n"
			.. "Reads the live cargo registry, so modded commodities work - tested "
			.. "alongside Freestyle Industries and Real Industrial Chains.\n\n"
			.. "NEED TO KNOW\n\n"
			.. "Passenger counts per line cover everyone travelling that line, not only "
			.. "those at this stop - the game does not expose which stop a person is "
			.. "waiting at. The \"waiting here\" total and the freight rows ARE exact for "
			.. "the stop, so the two will not add up to each other.\n\n"
			.. "Produced, Shipped and Used are lifetime totals since the industry was "
			.. "built, not per-year rates - the game's per-period counters exist but are "
			.. "never filled in, so a rate cannot be read from them.\n\n"
			.. "On industries with more than one input, Stored shows a combined total "
			.. "instead of a figure per commodity, because the game does not expose which "
			.. "storage slot holds which cargo.\n\n"
			.. "Nothing is written to the save beyond your settings - safe to add or remove "
			.. "at any time.",

		-- In-game strings from the game script use their English text as the
		-- key (_currentModIdTr is nil there, so symbolic ids never resolve).
		-- English needs no entry; other locales would add e.g.
		--   de = { ["Population"] = "Bevölkerung" }
		-- Symbolic ids below are fine: mod.lua loads with translation context.

		param_dismissMode    = "Panel stays open until",
		param_dismissMode_tt = "How the detail panel goes away. "
			.. "Click off: closes on a left-click anywhere. "
			.. "Mouse moves: closes as soon as the cursor leaves where it opened, "
			.. "like a tooltip. "
			.. "Sticky: stays until you right-click it again or open another. "
			.. "Middle-click never closes it, since that pans the camera.",

		param_debugLogging    = "Debug logging",
		param_debugLogging_tt = "Writes detailed diagnostics to the game log. Off by default and "
			.. "very chatty - only turn it on if you are reporting a problem. The log is at "
			.. "userdata/1066780/local/crash_dump/stdout.txt.",

		param_panelEnabled    = "Right-click detail panel",
		param_panelEnabled_tt = "Right-click a town, industry, station or depot for a compact readout. "
			.. "Right-click again to cycle through anything else nearby, or to close it. "
			.. "Left-click still opens the full window as usual.",

		param_cargoRenderDistance    = "Commodity icon draw distance",
		param_cargoRenderDistance_tt = "How far out building demand icons stay visible. Higher values let you "
			.. "read what towns want without zooming in.",

		param_townRenderDistance     = "City label draw distance",
		param_townRenderDistance_tt  = "How far out city name labels stay visible.",

		-- Debug toggle. A ladybug glyph in the settings panel footer rather
		-- than a labelled row: it is a support switch, not a player preference.
		debug_tooltip = "Debug logging - writes diagnostics to stdout.txt. "
			.. "Turn this on only to produce a log for a bug report.",
	},
}
end
