--[[
	rlv_cityoverlay - right-click town commodity readout

	Right-click a town: a compact panel appears at the cursor listing the
	commodities that town wants, with supply / limit and a fill percentage.
	A shorthand for the Supply rows of the full town window.

	DESIGN NOTES

	* The mouse listener NEVER returns true. Right-drag is camera rotation in
	  TF2; swallowing the event would fight it. We observe, we do not consume.
	* TownItem (the label itself) is engine-rendered and cannot be reached via
	  getById, so there is no way to hit-test the label directly. We instead
	  take the terrain point under the cursor and find the nearest town.
	* Components must not have "." or "_" in their NAME (engine restriction
	  noted by the build-with-collision author). Ids may contain them.

	TWO CALLS ARE UNVERIFIED and are wrapped in pcall with logging:
	  1. getGameUI():getTerrainPos()          -- namespace inferred from the
	     binary's GameUI binding table, never seen in shipped Lua.
	  2. game.interface.getTownCargoSupplyAndLimit(id) -- confirmed to exist,
	     return SHAPE unknown. describeShape() logs it on first call.
	If either is wrong, stdout says exactly what happened and nothing breaks.
--]]

local PANEL_ID   = "rlvCityOverlayPanel"
local PANEL_NAME = "rlvCityOverlayPanel"   -- no "." or "_"
local ROW_NAME    = "rlvCityOverlayRow"
local HEADER_NAME  = "rlvCityOverlayHeader"
local DIVIDER_NAME = "rlvCityOverlayDivider"
local SPACER_NAME  = "rlvCityOverlaySpacer"
-- Set false to abandon our own overlay root and go back to parenting into the
-- engine's toolTipContainer. That reintroduces the mouse-move vanish, but is a
-- known-good state if the root ever misbehaves.
-- Applied to cargo-type keys coming out of api.engine maps before handing them
-- to cargoTypeRep.get(). The maps are 1-based, get() is 0-based. If commodity
-- icons ever shift by one again, this is the dial.
local CARGO_KEY_OFFSET = -1

local USE_OVERLAY_ROOT = true
local OVERLAY_ROOT_ID = "rlvDetailsRoot"
-- Which mainView layer hosts our overlay root. 2 is the topmost of the three,
-- so panels are not hidden behind HUD elements.
local OVERLAY_LAYER   = 2
local SEARCH_RADIUS   = 400   -- metres around the terrain point, for towns
-- Industries. Deliberately tight so you have to click the industry rather than
-- merely somewhere near it -- at 180 a click on open ground well outside the
-- site still resolved to it.
local INDUSTRY_RADIUS = 70
local LOCAL_RADIUS    = 45    -- stations/depots: tight, so they only win when
                              -- the click really is on them. At 90 a station
                              -- was stealing clicks meant for the town label.
local MAX_CANDIDATES  = 400   -- hard cap per query, so a dense area cannot stall
-- Most lines listed for one station. A DELIBERATE display limit, not a
-- performance guard: past about ten rows the panel stops being a glance and
-- becomes a window, which is the thing this mod exists to avoid. Lines beyond
-- the cap are dropped silently -- see stationLines, which logs when it trims.
local MAX_STATION_LINES = 10

local MAX_CARGO_SAMPLES = 120 -- sim-cargo items sampled when resolving
                              -- destinations; a busy station holds many
-- A click this close to a town CENTRE ranks the town first.
--
-- Ideally this would be "is the cursor over the town label", but the label
-- cannot be located: TownItem is absent from the api.gui tree, no world->screen
-- projection is exposed, and game.gui.getContentRect("townhudicon") returns
-- nil. All three routes confirmed dead by probe.
--
-- So this is deliberately generous -- wide enough to cover a town's built-up
-- area, where labels routinely sit over stations and depots. The cost is that
-- clicking a station well inside a town shows the town first; one more
-- right-click cycles to the station.
local TOWN_LABEL_RADIUS = 260
local LOW_STOCK_YEARS   = 0.25 -- stored/consumed below this reads as a
                               -- bottleneck and is highlighted
-- Mouse button numbers. RIGHT = 2 is confirmed: the build-with-collision mod
-- uses it and our own right-click handler fires correctly on it. That implies a
-- zero-based enum, so LEFT = 0 and MIDDLE = 1. Middle is deliberately not
-- handled at all -- it pans the camera.
local MOUSE_LEFT        = 0
local MOUSE_MIDDLE      = 1
local MOUSE_RIGHT       = 2

-- How far the cursor may travel before "Mouse moves" mode closes the panel.
local MOVE_DISMISS_PX   = 48
-- Output commodity icons shown beside an industry's name.
local MAX_OUTPUT_ICONS  = 3
-- Where the options panel sits, in screen pixels from the top-left.
local TOOLBAR_BTN_ID    = "rlvDetailsOptionsButton"
-- Which group of mainButtonsLayout hosts the button. 2 is the right-hand
-- group, which build-with-collision also uses.
local TOOLBAR_GROUP     = 2

-- Which existing button we sit beside, and on which side of it.
--
-- Anchoring by ID rather than by group index, because the anchor is not always
-- in the same group: menu.bulldozer lives in the right-hand cluster while
-- menu.contexthelper ("?") is over on the far left. The placement code finds
-- whichever container actually holds the anchor, so changing this constant is
-- enough to move the button.
-- Tried in order; the first one we can actually insert beside wins.
--
-- menu.contexthelper ("?") is preferred but may not be reachable: it lives in
-- `menu`'s layout, which reports getIndex, insertItem AND addItem all false --
-- readable, but it accepts no children. Appending into the next container up
-- (mainMenuTopBarBG) is worse than useless, since that places the button after
-- the whole `menu` block rather than beside the "?".
--
-- menu.bulldozer is the proven fallback: its cluster exposes
-- getNumItems/getItem/insertItem, and the button already rendered correctly
-- there.
-- The whole button -- disc, ring and glyph -- baked into one RGBA texture by
-- tools/make_toolbar_button.py.
--
-- The isolation test settled why this is necessary: dropping the game's OWN
-- bulldozer icon in here still produced a light grey disc, so our artwork was
-- never the problem. The engine's UI art is 8-bit GREYSCALE used as a coverage
-- mask, and `color` on an ImageView only tints RGBA -- mode "L" art renders
-- raw. Putting the disc on the Button as a backgroundImage tints correctly but
-- composites over the child glyph and dims it to slate.
--
-- Baking sidesteps both: the tinting happens in Python and the engine gets a
-- finished RGBA image. The disc SHAPE is still the game's own disk_big_*, so
-- the silhouette matches its neighbours.
local TOOLBAR_ICON = "ui/rlvcityoverlay/toolbar_button.tga"

local TOOLBAR_ANCHORS = { "menu.contexthelper", "menu.bulldozer" }
local TOOLBAR_ANCHOR_AFTER = true   -- false puts us before the anchor

local OPTIONS_X         = 60
local OPTIONS_Y         = 120

local CYCLE_TOLERANCE   = 24  -- screen px; right-clicks within this of the
                              -- previous one advance the cycle instead of
                              -- starting a new selection

local state = {
	shownFor    = nil,   -- town entity id currently displayed
	anchor      = nil,   -- { x, y } screen pos where the panel was placed
	loggedShape = false,
	loggedIndustryShape = false,
	loggedKinds = {},
	loggedCounts = false,
	loggedDest = false,
	loggedDestShape = false,
	warnedDest = false,
	loggedStock = false,
	loggedStockCall = false,
	loggedEntryKey = false,
	loggedEntryFail = false,
	loggedButtons = false,
	loggedFilter = false,
	loggedCargoResolve = false,
	loggedStoredRows = false,
	loggedTheme = false,
	loggedMoveEvt = false,
	loggedMoveDist = false,
	loggedStockIds = false,
	loggedPersonLine = false,
	loggedLines = false,
	loggedCargoLine = false,
	cycle = nil,
	dumpedApi   = false,
	debug       = false,
	dismissMode = "click",
}

-- ---------------------------------------------------------------------------
-- SETTINGS
--
-- Mod params are LOAD-TIME ONLY -- the engine offers no way to change them
-- mid-session, and the in-game settings menu has no Mods tab. So anything the
-- player should be able to change while playing lives here instead, seeded
-- from the mod params and then owned by the in-game options panel.
--
-- Persisted through the game script's save()/load(). That writes a small table
-- into the save, which is additive and orphaned harmlessly if the mod is
-- removed -- severityRemove stays NONE.
-- ---------------------------------------------------------------------------

local DISMISS_MODES = { "click", "move", "sticky" }
local DISMISS_TEXT  = { click = "Click off", move = "Mouse moves", sticky = "Sticky" }

-- Whether a town panel repeats the town's name.
--   auto   -- only when town labels are switched off in the HUD filter, so it
--             is never a duplicate of the label directly above
--   always -- show it regardless of the filter
--   never  -- never show it
local TOWN_NAME_MODES = { "auto", "always", "never" }
local TOWN_NAME_TEXT  = {
	auto   = "When label hidden",
	always = "Always",
	never  = "Never",
}

local THEMES        = { "dark", "darker", "light" }
local THEME_TEXT    = { dark = "Dark", darker = "Darker", light = "Light" }

local settings = {
	panelEnabled = true,
	dismissMode  = "click",
	townName     = "auto",
	theme        = "dark",
	debug        = false,
}

--- Next value in a list, wrapping.
local function cycleValue(list, current)
	for i = 1, #list do
		if list[i] == current then return list[(i % #list) + 1] end
	end
	return list[1]
end

--- The three settings that mod params can drive, read from the shared `game`
--- table that mod.lua's runFn populates. nil when runFn has not run.
--
-- townName and theme are deliberately absent: they exist only in the in-game
-- panel and have no param, so nothing can conflict over them.
local function paramValues()
	local g = game and game.rlvCityOverlay
	if type(g) ~= "table" then return nil end
	return {
		panelEnabled = g.panelEnabled and true or false,
		dismissMode  = g.dismissMode and tostring(g.dismissMode) or nil,
		debug        = g.debugLogging and true or false,
	}
end

--- Seed from mod params.
--
-- The comment here used to claim this runs "before any save data is applied, so
-- a saved choice always wins". That is backwards: load() runs FIRST, and this
-- then overwrote everything it had just restored with the menu defaults. Saving
-- with debug on and reloading came back with debug off, every time.
--
-- settingsLoaded records that load() has already spoken. Params are only a
-- seed for a save that has never stored these settings.
local settingsSeeded = false
local settingsLoaded = false

local function seedSettingsFromParams(cfg)
	-- ONLY ONCE.
	--
	-- Params are the initial defaults; after that the settings table is owned
	-- by the in-game panel and the savegame. guiInit can run more than once in
	-- a session, and re-seeding there silently reverted every choice the
	-- moment anything re-initialised the UI -- which looked exactly like
	-- "settings are not saved".
	if settingsSeeded then return end
	settingsSeeded = true

	-- load() already applied the savegame's choices; do not clobber them with
	-- the menu defaults. This is the fix for "saved with debug on, loaded with
	-- debug off".
	--
	-- NO LOGGING HERE: this function is defined ABOVE emit/log, so `log` inside
	-- it resolves to a nil global rather than the local declared further down,
	-- and calling it crashed guiInit outright. Anything logged about seeding has
	-- to happen at the call site instead.
	if settingsLoaded then
		return
	end

	if type(cfg) ~= "table" then return end
	if cfg.panelEnabled ~= nil then settings.panelEnabled = cfg.panelEnabled and true or false end
	if cfg.dismissMode  ~= nil then settings.dismissMode  = tostring(cfg.dismissMode) end
	if cfg.debugLogging ~= nil then settings.debug        = cfg.debugLogging and true or false end
end

-- ---------------------------------------------------------------------------
-- logging helpers
-- ---------------------------------------------------------------------------

-- LOGGING POLICY
--
-- This mod is published. Verbose output belongs behind a switch, not in every
-- player's stdout -- the API probes alone dump whole metatables and the entire
-- api.type registry.
--
--   log()  diagnostics. Silent unless the user enables debug logging in the
--          mod options, so bug reports are still possible.
--   warn() genuine failures. Always printed -- if something is broken, it
--          should say so without the player first knowing to opt in.
--
-- settings.debug is seeded from the mod params and then owned by the in-game
-- options panel.

local function emit(...)
	local parts = { "[RightClickDetails]" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	print(table.concat(parts, " "))
end

local function log(...)
	if not settings.debug then return end
	emit(...)
end

local function warn(...)
	emit("WARN:", ...)
end


--- Mouse-move dismissal.
--
-- insertMouseListener delivers BUTTON events only -- a listener branch for
-- motion never fired once, confirmed by instrumenting it. So this mode has to
-- poll, which means guiUpdate.
--
-- guiUpdate runs every frame, so the cost is kept to essentially nothing: an
-- early return unless a panel is open AND this mode is selected. No entity
-- reads, no allocation -- just comparing the cursor against the point the
-- panel opened at. That is a very different proposition from the live-refresh
-- experiment removed earlier, which re-read simulation data continuously.
-- Broadcast settings to the OTHER script instance.
--
-- The mod runs in more than one Lua context, each with its own `settings`
-- table. The in-game panel and the ladybug run in the GUI context; save() runs
-- in another. Proven from the log: the toggle prints "debug logging ENABLED"
-- and the very next save(), microseconds later, still reports debug=false.
-- Nothing was wrong with the load-side merge -- the value never reached the
-- save at all.
--
-- res/scripts/guidesystem.lua has the same problem and solves it exactly this
-- way: it sends its state as a script event from guiUpdate and reapplies it in
-- handleEvent. Same pattern here, but only when something actually changed --
-- guiUpdate runs every frame and this does not need to.
local SETTINGS_EVENT = "rlvSettingsSync"

local function settingsSignature()
	return tostring(settings.panelEnabled) .. "|" .. tostring(settings.dismissMode)
		.. "|" .. tostring(settings.townName) .. "|" .. tostring(settings.theme)
		.. "|" .. tostring(settings.debug)
end

local function broadcastSettings()
	local sig = settingsSignature()
	if sig == state.lastBroadcastSig then return end
	state.lastBroadcastSig = sig

	local ok = pcall(function()
		game.interface.sendScriptEvent(SETTINGS_EVENT, "", {
			panelEnabled = settings.panelEnabled,
			dismissMode  = settings.dismissMode,
			townName     = settings.townName,
			theme        = settings.theme,
			debug        = settings.debug,
		})
	end)
	if not ok then warn("settings broadcast failed") end
end


--- Log the structure AND values of an unknown return value, recursing a few
-- levels. Scalars print their value -- an earlier version logged only the type
-- for non-tables, which hid the actual number of getIndustryTransportRating.
local function describeShape(label, v, depth, indent)
	depth  = depth or 3
	indent = indent or "  "

	if type(v) ~= "table" then
		log("SHAPE", label, "type=" .. type(v), "value=" .. tostring(v))
		return
	end

	log("SHAPE", label, "type=table")

	local function walk(t, d, pad)
		local n = 0
		for k, val in pairs(t) do
			n = n + 1
			if n > 14 then
				log(pad .. "... (truncated)")
				break
			end
			if type(val) == "table" then
				if d > 1 then
					log(pad .. tostring(k) .. " = {")
					walk(val, d - 1, pad .. "    ")
					log(pad .. "}")
				else
					log(pad .. tostring(k) .. " = (table, deeper)")
				end
			else
				log(pad .. tostring(k) .. " = " .. tostring(val) .. "  [" .. type(val) .. "]")
			end
		end
		return n
	end

	local total = walk(v, depth, indent)
	log("  total keys:", total)
end

--- Dump the callable keys of a table or userdata, so we can discover the real
-- API surface instead of guessing at it.
local function dumpKeys(label, obj)
	if obj == nil then log("KEYS", label, "= nil"); return end

	local function join(t)
		table.sort(t)
		return table.concat(t, " ")
	end

	if type(obj) == "table" then
		local names = {}
		for k, v in pairs(obj) do names[#names + 1] = tostring(k) .. ":" .. type(v) end
		log("KEYS", label, "(table) =", join(names))
		return
	end

	if type(obj) == "userdata" then
		local mt = getmetatable(obj)
		if not mt then log("KEYS", label, "(userdata, no metatable)"); return end

		local idx = rawget(mt, "__index")
		if type(idx) == "table" then
			local names = {}
			for k in pairs(idx) do names[#names + 1] = tostring(k) end
			log("KEYS", label, "(userdata __index) =", join(names))
		else
			local names = {}
			for k in pairs(mt) do names[#names + 1] = tostring(k) end
			log("KEYS", label, "(userdata metatable, __index is " .. type(idx) .. ") =", join(names))
		end
		return
	end

	log("KEYS", label, "= unsupported type", type(obj))
end

--- Convert an api.engine return value into a plain Lua table.
--
-- THIS IS THE FIX FOR A WHOLE CLASS OF SILENT FAILURES.
--
-- game.interface.* returns Lua tables, but api.engine.system.* returns
-- USERDATA containers (C++ vectors/maps exposed through metatables). Probes
-- showed calls SUCCEEDING -- "getLineStopsForStation(group) ok= true
-- type= userdata" -- while every one of our `type(x) == "table"` guards threw
-- the result away. That is why line names and stock counts always read "--"
-- even though the underlying calls worked.
--
-- These userdata types carry __pairs (visible in the mainView metatable dump),
-- so pairs() iterates them. Numeric indexing is the fallback, tried from 1 and
-- then 0, since C++ bindings are commonly zero-based.
local function toTable(v)
	if type(v) == "table" then return v end
	if type(v) ~= "userdata" then return nil end

	-- 1. __pairs -- works for most engine maps.
	local out = {}
	local okPairs = pcall(function()
		for k, item in pairs(v) do out[k] = item end
	end)
	if okPairs and next(out) ~= nil then return out end

	-- 2. __ipairs. Lua 5.2 honours it and the engine's containers define it --
	-- the metatable dump showed __ipairs, __len, and methods add/at/size/get/
	-- find/insert/next/pairs. Missing this is why "sourceAndCount" looked
	-- unreadable when it is really just another container.
	out = {}
	local okIp = pcall(function()
		for _, item in ipairs(v) do out[#out + 1] = item end
	end)
	if okIp and #out > 0 then return out end

	-- 3. The container's own size()/at() methods, 0- then 1-based.
	local okSize, n = pcall(function() return v:size() end)
	if okSize and type(n) == "number" and n > 0 then
		for _, base in ipairs({ 0, 1 }) do
			out = {}
			for i = base, base + n - 1 do
				local okAt, item = pcall(function() return v:at(i) end)
				if okAt and item ~= nil then out[#out + 1] = item end
			end
			if #out > 0 then return out end
		end
	end

	-- 4. Plain length + index.
	local okLen, len = pcall(function() return #v end)
	if okLen and type(len) == "number" and len > 0 then
		for _, base in ipairs({ 1, 0 }) do
			out = {}
			for i = base, base + len - 1 do
				local okI, item = pcall(function() return v[i] end)
				if okI and item ~= nil then out[#out + 1] = item end
			end
			if #out > 0 then return out end
		end
	end

	-- Empty container is a legitimate answer, not a failure.
	if okPairs or okIp then return {} end
	return nil
end

-- ---------------------------------------------------------------------------
-- NOTE ON LIVE UPDATES
--
-- A guiUpdate-driven refresh was built and then removed on purpose. guiUpdate
-- runs EVERY FRAME, and keeping several fields in step meant re-reading entity
-- data continuously for a panel that is on screen for a few seconds. Not worth
-- the frames.
--
-- Every panel already re-reads its data from scratch in show*Panel, so closing
-- and reopening -- or cycling with another right-click -- shows current values.
-- That is the refresh path.
--
-- If live updates are ever wanted again: keep references to the value
-- TextViews, call setText on them from guiUpdate on a frame throttle, and
-- never rebuild components there (destroying mid-event is undefined
-- behaviour). res/config/game_script/gameinfo.lua is the shipped example.
-- ---------------------------------------------------------------------------

--- Our own absolute-positioned overlay root.
--
-- WHY THIS EXISTS. Panels used to be parented into `toolTipContainer`, the
-- engine's own tooltip layer. The engine clears that container as the cursor
-- moves and its tooltip logic runs, which is what made the panel vanish on
-- mouse move -- with no destroyPanel call of ours involved.
--
-- The container survey showed why a straight reparent is not enough:
--   mainView layer 0/1/2 layout -> addItem, deleteAll, insertItem, setAlignment
--   toolTipContainer layout     -> addItem, deleteAll, getIndex,
--                                  setItemPosition, setPosition
-- The mainView layers are aligned layouts with no absolute positioning, so
-- attaching there directly would lose cursor placement.
--
-- So we build our own: a full-screen Component with an AbsoluteLayout, added
-- once to a mainView layer. It is ours, the engine does not manage it, and
-- panels inside it keep exact Rect positioning. Same pattern as
-- build-with-collision's full-screen bwcMouseListenerComp.
local function ensureOverlayRoot()
	if not USE_OVERLAY_ROOT then return nil end

	local existing = api.gui.util.getById(OVERLAY_ROOT_ID)
	if existing then return existing end

	local mainView = api.gui.util.getById("mainView")
	if not mainView then return nil end

	local okML, mainLayout = pcall(function() return mainView:getLayout() end)
	if not okML or not mainLayout then return nil end

	local okL, layer = pcall(function() return mainLayout:getItem(OVERLAY_LAYER) end)
	if not okL or not layer then
		warn("mainView layer", OVERLAY_LAYER, "unavailable; panels stay in toolTipContainer")
		return nil
	end

	local okLL, layerLayout = pcall(function() return layer:getLayout() end)
	if not okLL or not layerLayout then return nil end

	local okNew, root = pcall(function()
		local abs = api.gui.layout.AbsoluteLayout.new()
		local comp = api.gui.comp.Component.new("rlvDetailsRoot")
		comp:setId(OVERLAY_ROOT_ID)
		comp:setLayout(abs)

		-- CRITICAL: the root covers the whole screen, so without this it eats
		-- every mouse event before the game sees it -- no camera rotation, no
		-- scroll zoom, no clicking the nav bar. setTransparent makes it pass
		-- input straight through while still hosting positioned children.
		local okT = pcall(function() comp:setTransparent(true) end)
		if not okT then
			warn("setTransparent failed on overlay root -- input may be blocked;"
				.. " set USE_OVERLAY_ROOT = false to fall back")
		end

		layerLayout:addItem(comp)
		return comp
	end)

	if not okNew or not root then
		warn("could not create overlay root:", tostring(root))
		return nil
	end

	log("overlay root created in mainView layer", OVERLAY_LAYER)
	return root
end

--- Where panels attach. Our own root if we could make one, else the old
--- tooltip container so the mod still works rather than showing nothing.
local function panelHost()
	local root = ensureOverlayRoot()
	if root then
		local okL, lay = pcall(function() return root:getLayout() end)
		if okL and lay then return lay, "overlay-root" end
	end

	local ttc = api.gui.util.getById("toolTipContainer")
	if ttc then
		local okL, lay = pcall(function() return ttc:getLayout() end)
		if okL and lay then return lay, "tooltip-container" end
	end
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- panel teardown
-- ---------------------------------------------------------------------------

--- Tear down the open panel.
--
-- `keepCycle` separates the two reasons this gets called, which used to be
-- conflated:
--
--   DISMISSAL  -- click-off, Escape, mouse moved, nothing under cursor. The
--                cycle should be forgotten, so reopening at the same spot
--                starts from the top rather than resuming mid-cycle.
--   REPLACEMENT -- a show* function swapping in the next candidate's panel.
--                Must NOT forget the cycle, because the cycle is the state
--                driving that very swap.
--
-- Without the distinction, cycling could never advance. handleRightClick set
-- state.cycle, then called a show* function whose first statement nulled it, so
-- the next right-click found no cycle, rebuilt the list and picked index 1
-- again. Right-clicking a station inside a town returned the town forever, and
-- no amount of clicking reached the station.
local function destroyPanel(fromCallback, reason, keepCycle)
	if not api or not api.gui then return end

	if state.shownFor and reason then
		log("panel closed:", reason)
	end

	local elem = api.gui.util.getById(PANEL_ID)
	if elem then
		local host = panelHost()
		if host then pcall(function() host:removeItem(elem) end) end
		-- Destroying a component from inside its own event callback is
		-- undefined behaviour; the engine warns about it explicitly.
		if fromCallback then
			pcall(function() api.gui.util.destroyLater(elem) end)
		else
			pcall(function() elem:destroy() end)
		end
	end

	state.shownFor = nil
	state.anchor   = nil
	if not keepCycle then
		state.cycle = nil
	end
end

-- ---------------------------------------------------------------------------
-- data
-- ---------------------------------------------------------------------------

--- Normalise whatever getTerrainPos returns into { x, y, z }.
local function toXYZ(p)
	if type(p) == "table" then
		if p.x then return { x = p.x, y = p.y, z = p.z or 0 } end
		if p[1] then return { x = p[1], y = p[2], z = p[3] or 0 } end
	end
	-- userdata with fields
	local ok, x = pcall(function() return p.x end)
	if ok and x then
		return { x = p.x, y = p.y, z = (pcall(function() return p.z end) and p.z) or 0 }
	end
	return nil
end

--- Classify an entity as something we can show a readout for.
--
-- Mirrors the game's own dispatch in res/scripts/contexthelper.lua:690:
--     if e.type == "TOWN" then townWindow
--     elseif e.type == "SIM_BUILDING"
--         or (e.type == "CONSTRUCTION" and e.simBuildings[1] ~= nil) then industryWindow
-- Using the engine's own rule rather than inventing one.
local function classify(e)
	if type(e) ~= "table" then return nil end
	if e.type == "TOWN" then return "TOWN" end

	-- Stations and depots MUST be classified, not just for their own sake:
	-- while they were unrecognised, right-clicking a depot beside a factory
	-- fell through to the factory, so the depot appeared to "inherit" the
	-- industry's stats. Being candidates at all is what fixes that.
	if e.type == "STATION_GROUP" then return "STATION" end
	if e.type == "STATION"       then return "STATION" end
	if e.type == "VEHICLE_DEPOT" then return "DEPOT"   end

	if e.type == "SIM_BUILDING" then return "INDUSTRY" end
	if e.type == "CONSTRUCTION" and e.simBuildings and e.simBuildings[1] ~= nil then
		return "INDUSTRY"
	end
	return nil
end

--- For a CONSTRUCTION wrapping an industry, the production queries want the
-- underlying sim building.
local function industryQueryId(entityId, e)
	if e and e.type == "CONSTRUCTION" and e.simBuildings and e.simBuildings[1] then
		return e.simBuildings[1]
	end
	return entityId
end

--- Every town / industry / station / depot near a world position, ordered by
--- how likely the user meant it. Returns a list of
--- { id, kind, entity, tier, d2 }.
--
-- WHY THIS IS HARD, and why it is a ranked list rather than a single answer:
-- the user aims at a floating HUD LABEL, but all we can hit-test is the
-- terrain point under the cursor. TownItem and the station/depot icons are
-- engine-rendered, absent from the api.gui tree, and there is no world->screen
-- projection exposed (confirmed by a full API survey). So we cannot know which
-- label was clicked -- only what is near the ground beneath it.
--
-- Consequently any single-answer rule has failure cases. Nearest-wins picked
-- stations over towns; strict tiers did the same, because in a built-up area
-- there is always a bus stop within metres of the town centre. Instead we rank
-- every candidate and let the user cycle by right-clicking again.
local function collectCandidates(pos)
	local found, seen = {}, {}

	local function consider(entityId, tier)
		if seen[entityId] then return end
		local okE, e = pcall(game.interface.getEntity, entityId)
		if not okE then return end
		local kind = classify(e)
		if not kind then return end

		-- COLLAPSE CONSTRUCTION -> SIM_BUILDING.
		--
		-- An industry exists as BOTH a construction and a sim building, at
		-- slightly different positions. Clicking one spot found the sim
		-- building (full data) and a spot a few metres away found the
		-- construction, whose entity has no itemsProduced/itemsConsumed -- so
		-- the same oil well showed "Produced/yr 400" or "Produced/yr --"
		-- depending on exactly where you clicked.
		--
		-- Resolve to the sim building so both routes land on the same entity,
		-- and mark BOTH ids seen so the pair cannot enter the cycle twice.
		if e.type == "CONSTRUCTION" and e.simBuildings and e.simBuildings[1] then
			local simId = e.simBuildings[1]
			seen[entityId] = true
			if seen[simId] then return end
			local okS, se = pcall(game.interface.getEntity, simId)
			if okS and se then
				entityId, e = simId, se
			end
		end

		seen[entityId] = true

		-- A STATION_GROUP aggregates its member stations and carries the
		-- combined cargoWaiting / itemsLoaded figures, so it is the one worth
		-- showing. Mark its members seen so a stop and its parent group do not
		-- both appear as separate steps in the cycle. Groups are queried before
		-- individual stations, so this ordering holds.
		if e.type == "STATION_GROUP" and e.stations then
			local members = toTable(e.stations)
			if members then
				for _, mid in pairs(members) do
					if type(mid) == "number" then seen[mid] = true end
				end
			end
		end

		local d2 = 0
		if e.position then
			local dx = (e.position[1] or e.position.x or 0) - pos.x
			local dy = (e.position[2] or e.position.y or 0) - pos.y
			d2 = dx * dx + dy * dy
		end

		-- Town promotion is NOT decided here -- see the post-pass below. It
		-- depends on what else was found, which is unknowable at this point.
		found[#found + 1] =
			{ id = entityId, kind = kind, entity = e, tier = tier, d2 = d2 }
	end

	local queries = {
		-- STATION as well as STATION_GROUP: bus and tram stops are individual
		-- stations, and querying only groups meant right-clicking a stop found
		-- nothing and fell through to whatever was nearby.
		{ tier = 1, radius = LOCAL_RADIUS,
		  types = { "VEHICLE_DEPOT", "STATION_GROUP", "STATION" } },
		{ tier = 2, radius = INDUSTRY_RADIUS,
		  types = { "SIM_BUILDING", "CONSTRUCTION" } },
		{ tier = 3, radius = SEARCH_RADIUS,
		  types = { "TOWN" } },
	}

	for q = 1, #queries do
		local qy = queries[q]
		for ti = 1, #qy.types do
			local tname = qy.types[ti]
			local ok, entities = pcall(function()
				return game.interface.getEntities(
					{ pos = { pos.x, pos.y }, radius = qy.radius },
					{ type = tname })
			end)
			if ok and type(entities) == "table" then
				if not state.loggedCounts then
					log("query", tname, "r=" .. qy.radius, "->", #entities, "entities")
				end
				local n = math.min(#entities, MAX_CANDIDATES)
				for i = 1, n do consider(entities[i], qy.tier) end
			elseif not state.loggedCounts then
				warn("query", tname, "FAILED:", tostring(entities))
			end
		end
	end
	state.loggedCounts = true

	-- TOWN PROMOTION -- a post-pass, because it is a RELATIVE judgement.
	--
	-- A town's label is drawn at its centre, so a click near that centre
	-- usually means the user aimed at the town label rather than at whatever
	-- happens to stand nearby. TOWN_LABEL_RADIUS is deliberately generous (260m)
	-- to cover a town's built-up area.
	--
	-- But applied unconditionally that radius swallows every station in every
	-- town of any size: the sort is tier-then-distance, so a promoted town beat
	-- a station regardless of how much closer the station was -- a stop 3m from
	-- the cursor lost to a town centre 200m away.
	--
	-- It could not be decided during collection, because at that point nothing
	-- is known about the other candidates. Done here, it can be conditional:
	-- promote the town ONLY if nothing more specific is genuinely under the
	-- cursor. LOCAL_RADIUS already means "the click really is on this thing", so
	-- if a station or depot is that close, the user did not mean the town.
	--
	-- When nothing specific is under the cursor this is a no-op, so the case
	-- the generous radius was introduced to fix behaves exactly as before.
	local specificUnderCursor = false
	for i = 1, #found do
		local c = found[i]
		if (c.kind == "STATION" or c.kind == "DEPOT")
			and c.d2 <= LOCAL_RADIUS * LOCAL_RADIUS then
			specificUnderCursor = true
			break
		end
	end

	if not specificUnderCursor then
		for i = 1, #found do
			local c = found[i]
			if c.kind == "TOWN" and c.d2 <= TOWN_LABEL_RADIUS * TOWN_LABEL_RADIUS then
				c.tier = 0
			end
		end
	end

	table.sort(found, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		return a.d2 < b.d2
	end)

	return found
end

-- Canonical cargo ordering, taken from the `order` field of
-- res/config/cargo_types/*.cargo.lua. The town window appears to list
-- commodities in the town's own needs order, which pairs() cannot recover --
-- so we use this stable ordering instead. Flip the comparison in sortRows to
-- reverse it.
-- CARGO ORDERING -- built from the live registry, not hardcoded.
--
-- A fixed list breaks every cargo mod. Real Industrial Chains alone adds six
-- types (PACKAGING_MATERIALS, LUBRICANTS, SLAG, LIVESTOCK, BIOPLASTIC,
-- INDUSTRIAL_TOOLS), and Freestyle Industries lets the player build chains from
-- whatever is installed. The previous hardcoded table was also used as a
-- FILTER, so modded cargo was silently dropped from industry stock rows.
--
-- api.res.cargoTypeRep is the authoritative source and is what Freestyle's own
-- postRunFn uses: getAll() returns ids and is 0-indexed.
local FALLBACK_CARGO_ORDER = {
	PASSENGERS = 0, LOGS = 1, COAL = 3, IRON_ORE = 4, STONE = 5,
	GRAIN = 6, CRUDE = 7, STEEL = 8, PLANKS = 9, PLASTIC = 10,
	OIL = 12, CONSTRUCTION_MATERIALS = 13, MACHINES = 14, FUEL = 15,
	TOOLS = 16, FOOD = 17, GOODS = 18,
}

local cargoOrderCache = nil
local cargoIdByIndex  = nil

local function buildCargoTables()
	if cargoOrderCache then return end
	cargoOrderCache = {}
	cargoIdByIndex  = {}

	local ok, list = pcall(function() return api.res.cargoTypeRep.getAll() end)
	local t = ok and toTable(list) or nil

	if t then
		for k, id in pairs(t) do
			if type(id) == "string" and type(k) == "number" then
				cargoOrderCache[id] = k
				cargoIdByIndex[k]   = id
			end
		end
	end

	if next(cargoOrderCache) == nil then
		warn("cargoTypeRep unavailable; falling back to base-game cargo list."
			.. " Modded cargo will not be shown in industry stocks.")
		cargoOrderCache = FALLBACK_CARGO_ORDER
	else
		log("cargo registry:", (function()
			local n = 0
			for _ in pairs(cargoOrderCache) do n = n + 1 end
			return n
		end)(), "types")
	end
end

--- Sort position for a cargo id. Unknown ids sort last but are never dropped.
local function cargoOrder(id)
	buildCargoTables()
	return cargoOrderCache[id] or 999
end

--- Is this a real cargo type? Replaces the old "is in my hardcoded list" test.
local function isCargoType(id)
	buildCargoTables()
	return cargoOrderCache[id] ~= nil
end


--- Return a list of { id=<cargo id>, supply=<n>, limit=<n> }.
--
-- CONFIRMED SHAPE (from runtime): a table keyed by cargo id, each value a
-- two-element array { supply, limit }:
--     { GOODS = { 0, 84 }, FUEL = { 0, 79 } }
-- The keyed/named variants below are kept as cheap defensive fallbacks.
local function cargoRows(townId)
	local ok, raw = pcall(game.interface.getTownCargoSupplyAndLimit, townId)
	if not ok or raw == nil then
		warn("getTownCargoSupplyAndLimit failed:", tostring(raw))
		return {}
	end

	local rows = {}
	if type(raw) ~= "table" then return rows end

	for k, v in pairs(raw) do
		if type(v) == "table" then
			local supply = v[1] or v.supply
			local limit  = v[2] or v.limit
			if supply and limit and type(k) == "string" then
				rows[#rows + 1] = { id = k, supply = supply, limit = limit }
			end
		elseif type(k) == "string" and type(v) == "number" then
			rows[#rows + 1] = { id = k, supply = v, limit = nil }
		end
	end

	table.sort(rows, function(a, b)
		local oa = cargoOrder(a.id)
		local ob = cargoOrder(b.id)
		if oa ~= ob then return oa < ob end
		return a.id < b.id
	end)
	return rows
end

--- Headline figures for the town.
--
-- CONFIRMED SHAPES (from runtime):
--   getTownCapacities(id) -> { residents, shoppingFacilities, workplaces }
--                            e.g. { 143, 145, 143 } -- matches the three
--                            figures across the top of the town window.
--   getEntity(id)         -> { name, id, type="TOWN", position={x,y,z},
--                              counts, townDestCounts, useLinesCounts,
--                              useLinesPercentage, lu2cargoInfo }
local function townSummary(townId)
	local okC, caps = pcall(game.interface.getTownCapacities, townId)

	local residents
	if okC and type(caps) == "table" then
		residents = caps[1]
	end

	return residents
end

--- Industry headline figures: level, production, shipment, transport rating.
--
-- All four calls sit in the same game.interface block as the town functions we
-- have already proven, so they exist -- but their return SHAPES are unverified.
-- describeShape logs each one on first use, exactly as we did for
-- getTownCargoSupplyAndLimit before pinning it down.
--- Pull a rate out of one of the engine's accumulator tables.
--
-- These look like:
--   { _sum = 7836, GRAIN = 7836, _lastMonth = {...}, _lastYear = {...} }
-- _sum is LIFETIME total, which is not what the overview window shows -- it
-- displays a rate. _lastYear / _lastMonth are the per-period buckets, so we
-- prefer those and fall back to the lifetime total only if they are absent.
-- MEASURED, on a level-2 oil well (probe output, 2026-08-12):
--
--   itemsProduced = {
--       _sum       = 817946,   CRUDE = 817946,
--       _lastMonth = { _sum = 0, CRUDE = 0 },
--       _lastYear  = { _sum = 0, CRUDE = 0 },
--   }
--
-- Two things that were previously assumed are now settled:
--
--   * `_sum` IS a lifetime cumulative total. 817946 crude from one well.
--   * `_lastMonth` and `_lastYear` are **always zero**, on a well that had
--     demonstrably produced 817946 and shipped 279067. They are present in the
--     shape but never populated.
--
-- So the old preference order returned `bucketTotal(acc._lastYear)` = 0, and
-- since 0 is TRUTHY in Lua the `or` chain stopped there. Every rate read 0.
-- That is the whole of the Produced/Shipped/Used bug.
--
-- It also retires the README's claim that our figures are "trailing
-- twelve-month totals from the entity's _lastYear accumulators" -- that never
-- happened, because those buckets hold nothing.
--
-- CONSEQUENCE: there is no per-period figure to be had from this data. The only
-- real number is the lifetime total, so that is what we return, and the caller
-- labels it as such. A true rate would mean sampling `_sum` over game time and
-- differencing it -- see PLAN.md §8.
local function rateOf(acc)
	if type(acc) ~= "table" then return nil end

	local function bucketTotal(b)
		if type(b) ~= "table" then return nil end
		if type(b._sum) == "number" then return b._sum end
		local total, any = 0, false
		for k, v in pairs(b) do
			if type(v) == "number" and tostring(k):sub(1, 1) ~= "_" then
				total = total + v
				any = true
			end
		end
		return any and total or nil
	end

	-- Prefer a period bucket if one ever carries data -- costs nothing, and
	-- means a future patch that starts populating them is picked up for free.
	-- A zero bucket is treated as absent rather than as an answer, which is
	-- exactly the short-circuit that caused the bug.
	local y = bucketTotal(acc._lastYear)
	if y and y ~= 0 then return y end

	local m = bucketTotal(acc._lastMonth)
	if m and m ~= 0 then return m end

	return type(acc._sum) == "number" and acc._sum or nil
end

--- Industry headline figures: level, production, shipment, transport rating.
--
-- CONFIRMED FROM RUNTIME: getEntity() on a SIM_BUILDING already carries the
-- production and shipment data:
--     { name, level, stockList, upgradeProgress, type="SIM_BUILDING",
--       position, itemsProduced, itemsShipped, itemsConsumed,
--       itemsConsumedVehicleUsed }
-- getIndustryProduction / ProductionLimit / Shipping all FAILED their pcall,
-- so we read the entity instead of calling them. Only
-- getIndustryTransportRating works (returns a plain number).
--- Per-cargo breakdown from one of the engine's accumulator tables.
-- Returns { CARGO = amount }, preferring _lastYear like rateOf does.
-- Carries the SAME defect rateOf had, and for the same reason: _lastYear and
-- _lastMonth are never populated (see rateOf for the measured shape), but they
-- do contain the cargo KEYS with zero values -- e.g.
-- _lastYear = { _sum = 0, IRON_ORE = 0, COAL = 0 }. So `any` was true, the
-- bucket came back non-nil, and the `or` chain stopped on a table of zeros.
--
-- That is why the stocks table's Used column read 0 for every commodity while
-- Produced and Shipped were already fixed -- those go through rateOf, this does
-- not. An all-zero bucket is treated as absent here too.
local function perCargo(acc)
	if type(acc) ~= "table" then return {} end

	local function bucket(b)
		if type(b) ~= "table" then return nil end
		local out, any = {}, false
		for k, v in pairs(b) do
			if type(v) == "number" and tostring(k):sub(1, 1) ~= "_" then
				out[k] = v
				any = true
			end
		end
		return any and out or nil
	end

	-- Keep the cargo keys even from an all-zero bucket if that is all there is:
	-- the stocks rows are DRIVEN off these keys, so returning {} would drop the
	-- rows entirely rather than showing them with a zero.
	local function ifAnyNonZero(t)
		if not t then return nil end
		for _, v in pairs(t) do
			if v ~= 0 then return t end
		end
		return nil
	end

	return ifAnyNonZero(bucket(acc._lastYear))
		or ifAnyNonZero(bucket(acc._lastMonth))
		or bucket(acc)
		or bucket(acc._lastYear)
		or {}
end

--- Cargo type names in engine id order, so numeric cargo keys can be named.
-- api.engine maps often key by cargo type INDEX rather than by name.
local cargoTypeNames = nil
--- Resolve a cargo-type KEY from an api.engine map into its id string.
--
-- Do NOT do index arithmetic here. The base game's cargo `order` values are
-- sparse (0,1,3,4,...,18 -- 2 and 11 are unused) while the registry array is
-- dense 0..16, so "index + 1" style guesses drift after the first gap. That
-- drift is exactly why stored rows drew the wrong commodity icons while
-- consumed rows -- which arrive keyed by NAME -- were right.
--
-- api.res.cargoTypeRep.get(key) hands back the actual cargo type for that key,
-- which is what Freestyle Industries uses. Ask it, do not compute it.
local function cargoNameForIndex(idx)
	if type(idx) == "string" then return idx end
	if type(idx) ~= "number" then return nil end

	-- OFF BY ONE, CONFIRMED FROM RUNTIME.
	--
	-- The keys of getCargoType2stockList2sourceAndCount are 1-BASED, while
	-- cargoTypeRep.get() is 0-based. Proof: a construction materials plant that
	-- consumes STONE logged
	--     stored resolved:   GRAIN = 100
	--     consumed resolved: STONE = 100
	-- Stone sits at 1-based position 5; get(5) returns grain, the next entry.
	-- Consumed is keyed by NAME so it was unaffected, which is exactly why only
	-- the stored column ever showed the wrong commodity.
	local ok, ct = pcall(function()
		return api.res.cargoTypeRep.get(idx + CARGO_KEY_OFFSET)
	end)
	if ok and ct then
		local okId, id = pcall(function() return ct.id end)
		if okId and type(id) == "string" and id ~= "" then
			if not state.loggedCargoResolve then
				state.loggedCargoResolve = true
				log("cargo key resolution via cargoTypeRep.get(); key", idx, "->", id)
			end
			return id
		end
		local okN, nm = pcall(function() return ct.name end)
		if okN and type(nm) == "string" and nm ~= "" then return nm end
	end

	-- Fall back to the dense registry array only if get() is unavailable.
	buildCargoTables()
	if cargoIdByIndex then
		local viaArray = cargoIdByIndex[idx + CARGO_KEY_OFFSET]
		if viaArray then
			if not state.loggedCargoResolve then
				state.loggedCargoResolve = true
				warn("cargoTypeRep.get() unavailable; falling back to array index."
					.. " Stored commodity icons may be wrong.")
			end
			return viaArray
		end
	end
	return nil
end

--- Pull a count out of a "sourceAndCount" entry.
--
-- CONFIRMED: the innermost value of getCargoType2stockList2sourceAndCount is
-- USERDATA that toTable cannot convert -- it has no __pairs and no length, so
-- it is a struct rather than a container. Field access is the only route, and
-- the field name is unknown, so try the plausible ones directly.
local function entryCount(entry)
	if entry == nil then return nil end
	if type(entry) == "number" then return entry end

	-- CONFIRMED from the metatable dump: this is a CONTAINER, not a struct --
	-- add/at/clear/empty/erase/find/get/insert/next/pairs/set/size. The name
	-- "sourceAndCount" means it maps a supplying source to a stored count, so
	-- the stored total is the sum of its values, not a single field.
	local t = toTable(entry)
	if not t then
		if not state.loggedEntryFail then
			state.loggedEntryFail = true
			log("stock entry still unreadable; metatable follows")
			dumpKeys("stock entry", entry)
		end
		return nil
	end

	local total, any = 0, false
	for _, v in pairs(t) do
		if type(v) == "number" then
			total = total + v
			any = true
		else
			-- Nested pair (source, count): take its numeric part.
			local t2 = toTable(v)
			if t2 then
				for _, v2 in pairs(t2) do
					if type(v2) == "number" then
						total = total + v2
						any = true
					end
				end
			end
		end
	end

	if any then
		if not state.loggedEntryKey then
			state.loggedEntryKey = true
			log("stock entry read as container; summed", total)
		end
		return total
	end
	return nil
end

--- Read stock levels for an industry.
--
-- CONFIRMED SIGNATURE: simEntityAtStockSystem.getStockCount(stockEntity, stockId)
-- returns a number. Single-argument forms all error, and getStockEntities /
-- getStockSimEntity error too, so this is the way in.
--
-- What "stockId" means is the remaining question. The binary names the pair
-- (stockEntity, stockId), and the cargo maps elsewhere are keyed 1-based
-- against a 0-based registry -- so both the cargo index and that index off by
-- one are plausible. Try each, keep whichever returns a number, and log the
-- pair once so the mapping stops being guesswork.
--
-- NOT getCargoType2stockList2sourceAndCount: that returned 800/800 on a steel
-- mill where the game showed 1673/418, and 800/800 was exactly that
-- industry's Consumption. It describes supply arrangements, not holdings.
local function readStockLevels(entity, cargoIds)
	local out = {}
	local sys = api and api.engine and api.engine.system
	local ses = sys and sys.simEntityAtStockSystem
	local sl = entity and entity.stockList
	if not ses or not ses.getStockCount or not sl then return out end

	-- Read the slots. Stock lives at slot 0, 1, ... in the order the
	-- industry's rule declares its inputs.
	local slots = {}
	for i = 0, 7 do
		local ok, n = pcall(function() return ses.getStockCount(sl, i) end)
		if ok and type(n) == "number" then slots[#slots + 1] = n else break end
	end

	if #cargoIds == 1 then
		-- Unambiguous: one input, one slot.
		out[cargoIds[1]] = slots[1] or 0
		return out
	end

	-- MULTI-INPUT: the slot-to-cargo mapping is not recoverable. SETTLED.
	--
	-- The ordering itself is known: the slot ordinal is the index into the
	-- construction's `stocks` array, in DECLARATION order.
	-- res/scripts/industryutil.lua:18-24 builds
	--     result.stocks[i] = { cargoType = stocks[i], ... }
	-- and industry/steel_mill.con declares { "IRON_ORE", "COAL" } -- exactly the
	-- 0=iron ore, 1=coal the slots read. It is never registry order, which is
	-- why no arithmetic on cargo ids ever fit.
	--
	-- What does not exist is any RUNTIME route to that array. All probed and
	-- confirmed dead:
	--     CONSTRUCTION entity .stocks            key absent
	--     ConstructionDesc .stocks               nil
	--     ConstructionDesc .placementParams      nil
	--     ConstructionDesc .updateFn             nil
	--     toTable(ConstructionDesc)              nil
	--     ECS STOCK_LIST                         opaque -- __index nil, and sol
	--                                            refuses __pairs: "not
	--                                            recognized as a container"
	--     ECS CONSTRUCTION / SIM_BUILDING        no stock fields
	--
	-- A stockSlotOrder() helper trying the first three was written and removed:
	-- it could never return anything. Parsing the shipped .con files is not an
	-- option either -- Real Industrial Chains overrides industry configs, so it
	-- would mislabel exactly the setups being played.
	--
	-- Rather than confidently mislabel 1759 units of iron ore as coal, report
	-- the combined buffer. It is correct, and still answers the question that
	-- matters: is this industry starving? Revisit only if a future patch exposes
	-- StockList to Lua.
	local total = 0
	for i = 1, #slots do total = total + slots[i] end
	out.__total = total
	return out
end

--- Stored / consumed materials for an industry.
--
-- The industry window shows a "Stocks" table with Stored and Consumption
-- columns -- your steel mill had iron ore at 1 stored / 356 consumed and coal
-- at 4901 / 356. Consumption we already have: itemsConsumed on the entity.
-- Stored lives behind entity.stockList, which is an ENTITY ID (4028 on the
-- farm we dumped), so getEntity should resolve it -- but its shape is
-- unconfirmed, hence the probe and dump.
--
-- Returns a list of { id, stored, consumed }. Empty for a raw producer like a
-- forest, which consumes nothing -- the panel then omits the section entirely.
local function industryStocks(entity)
	local consumed = perCargo(entity and entity.itemsConsumed)
	local stored = {}

	-- Stock levels come from simEntityAtStockSystem, keyed by the cargo types
	-- this industry actually consumes.
	local inputIds = {}
	for id in pairs(consumed) do inputIds[#inputIds + 1] = id end
	local okStock, levels = pcall(readStockLevels, entity, inputIds)
	local storedTotal = nil
	if okStock and levels then
		for id, n in pairs(levels) do
			if id == "__total" then storedTotal = n else stored[id] = n end
		end
	end

	-- CONFIRMED DEAD END: entity.stockList is NOT a stock list. getEntity on it
	-- returns the CONSTRUCTION wrapping the industry -- particleSystems,
	-- townBuildings, depots, params.productionLevel, transf. No stock levels
	-- anywhere in it. The real data lives in the ECS systems below.
	local sys = api and api.engine and api.engine.system

	if not state.loggedStock then
		state.loggedStock = true
		log("=== CONSOLIDATED PROBE ===")
		log("-- outstanding: stored stock levels, line/route lookup,")
		log("-- and rates that match the window (ours read ~6% high) --")

		if sys then
			dumpKeys("simEntityAtStockSystem", sys.simEntityAtStockSystem)
			dumpKeys("stockListSystem",        sys.stockListSystem)
			dumpKeys("lineSystem",             sys.lineSystem)
			dumpKeys("stationGroupSystem",     sys.stationGroupSystem)
			dumpKeys("stationSystem",          sys.stationSystem)
		end
		dumpKeys("api.engine.transport", api and api.engine and api.engine.transport)
		dumpKeys("api.engine.util",      api and api.engine and api.engine.util)
		dumpKeys("api.type",             api and api.type)
		if api and api.type and api.type.ComponentType then
			dumpKeys("api.type.ComponentType", api.type.ComponentType)
		end

		-- getComponent returns USERDATA, not a table -- describeShape only
		-- printed its type last round. dumpKeys walks the metatable instead.
		--
		-- Last round also passed the wrong entity: STOCK_LIST was queried
		-- against the sim-building id and came back nil. entity.stockList is
		-- the entity that carries the stock-list component (7313 shares an id
		-- with the construction, which is why getEntity showed a construction
		-- view -- one entity, several components).
		if api and api.engine and api.engine.getComponent
			and api.type and api.type.ComponentType then
			local targets = {
				{ name = "SIM_BUILDING", id = entity.id },
				{ name = "STOCK_LIST",   id = entity.stockList or entity.id },
			}
			for _, t in ipairs(targets) do
				local ct = api.type.ComponentType[t.name]
				if ct and t.id then
					local okC, comp = pcall(api.engine.getComponent, t.id, ct)
					log("getComponent", t.name, "entity=", tostring(t.id),
						"ok=", tostring(okC), "type=", type(comp))
					if okC and comp ~= nil then
						dumpKeys("component " .. t.name, comp)
						-- __index is nil on STOCK_LIST but __pairs exists, so
						-- iteration is the only way in.
						local conv = toTable(comp)
						if conv then describeShape("component " .. t.name .. " (iterated)", conv, 3) end
					end
				end
			end
		end

		-- stockListSystem returns counts directly, which may be simpler than
		-- reaching through the component.
		if sys and sys.stockListSystem then
			local okM, m = pcall(sys.stockListSystem.getCargoType2stockList2sourceAndCount)
			log("getCargoType2stockList2sourceAndCount ok=", tostring(okM),
				"type=", type(m))
			if okM and type(m) == "table" then describeShape("cargo2stock2count", m, 3) end
		end
		log("=== END CONSOLIDATED PROBE ===")
	end

	-- CONFIRMED: simEntityAtStockSystem.getStockCount(id) errors -- ok=false
	-- with a string payload, so its signature is wrong.
	--
	-- stockListSystem.getCargoType2stockList2sourceAndCount() DOES work. Its
	-- name describes the shape: cargoType -> stockList -> (source, count). We
	-- index it by this industry's stockList entity to get per-cargo stored
	-- amounts. Everything comes back as userdata, so every level needs
	-- toTable.
	if sys and sys.stockListSystem and entity and entity.stockList then
		local okM, mRaw = pcall(sys.stockListSystem.getCargoType2stockList2sourceAndCount)
		local m = okM and toTable(mRaw) or nil

		if not state.loggedStockCall then
			state.loggedStockCall = true
			log("cargo2stock2count ok=", tostring(okM), "raw=", type(mRaw),
				"converted=", m and "table" or "nil",
				"| our stockList =", tostring(entity.stockList))
			if m then
				local shown = 0
				for cargoKey, byStock in pairs(m) do
					shown = shown + 1
					if shown > 3 then break end
					local bs = toTable(byStock)
					log("  cargoKey=", tostring(cargoKey),
						"(", tostring(cargoNameForIndex(cargoKey) or cargoKey), ")",
						"byStock=", type(byStock), "->", bs and "table" or "nil")
					if bs then
						local n = 0
						for stockId, entry in pairs(bs) do
							n = n + 1
							if n > 3 then break end
							log("      stock", tostring(stockId), "=", type(entry),
								type(entry) ~= "table" and type(entry) ~= "userdata"
									and tostring(entry) or "")
							log("          count ->", tostring(entryCount(entry)))
						end
					end
				end
			end
		end

		-- NOTE: the extraction that used to live here has been REMOVED.
		--
		-- It read getCargoType2stockList2sourceAndCount and presented the
		-- result as "Stored". Measured against a steel mill it produced
		-- 800/800 where the game showed 1673/418 -- and 800/800 was exactly
		-- that industry's Consumption. The map describes supply arrangements
		-- per source, not what is currently held.
		--
		-- Stored now comes from simEntityAtStockSystem.getStockCount instead,
		-- which is the only call that returns a real number here.
	end

	if not state.loggedStoredRows then
		state.loggedStoredRows = true
		for k, v in pairs(stored) do
			log("stored resolved:", tostring(k), "=", tostring(v))
		end
		for k, v in pairs(consumed) do
			log("consumed resolved:", tostring(k), "=", tostring(v))
		end
	end

	-- INPUTS ONLY, matching the game's own Stocks table.
	--
	-- entity.stockList holds output stock as well as input, so a union of
	-- stored+consumed produced spurious half-filled rows: the output appeared
	-- with a stored amount and no consumption, and inputs with no stock
	-- appeared with no stored value. The game lists only what the industry
	-- CONSUMES, which is also the actionable set -- an input running dry is the
	-- bottleneck; output stock is already implied by Production vs Shipment.
	--
	-- Driving rows off `consumed` has a second benefit: those keys arrive as
	-- cargo NAMES from the accumulator, so they are never subject to key
	-- resolution problems.
	local seen, rows = {}, {}
	local function add(id)
		if seen[id] then return end
		seen[id] = true
		rows[#rows + 1] = { id = id, stored = stored[id], consumed = consumed[id] }
	end
	for k in pairs(consumed) do add(k) end

	table.sort(rows, function(a, b)
		local oa = cargoOrder(a.id)
		local ob = cargoOrder(b.id)
		if oa ~= ob then return oa < ob end
		return a.id < b.id
	end)

	return rows
end

local function industrySummary(entityId, entity)
	local qid = industryQueryId(entityId, entity)
	local okRate, rating = pcall(game.interface.getIndustryTransportRating, qid)

	if not state.loggedIndustryShape then
		state.loggedIndustryShape = true
		log("--- industry data ---")
		describeShape("getEntity(industry)", entity, 3)
		log("getIndustryTransportRating ok=", tostring(okRate),
			"raw=", tostring(rating))
		log("--- end industry data ---")
	end

	return {
		name       = entity and entity.name,
		level      = entity and entity.level,
		production = entity and rateOf(entity.itemsProduced),
		shipping   = entity and rateOf(entity.itemsShipped),
		consumed   = entity and rateOf(entity.itemsConsumed),
		rating     = okRate and rating or nil,
	}
end

-- ---------------------------------------------------------------------------
-- panel construction
-- ---------------------------------------------------------------------------

local function cargoIcon(cargoId)
	return "ui/hud/cargo_" .. tostring(cargoId):lower() .. ".tga"
end

--- A 1px horizontal rule. Height comes from the stylesheet, where
-- size = {-1, 1} means "full width, one pixel tall" (-1 is the fill sentinel).
--- Abbreviate a figure so a wide number cannot stretch the panel: 62500 -> "62.5K".
--
-- Threshold is 10000 rather than 1000 on purpose. Below that, abbreviating costs
-- precision that matters for a stock readout -- "1.7K" is a worse answer than
-- "1673" when the question is whether an input is about to run dry -- and saves
-- at most one character. Set ABBREVIATE_FROM to 1000 if uniformity is worth more
-- than precision.
--
-- Returns nil for a non-number so callers can fall back to "--" as before, and
-- keeps rounding out of the caller: pass the raw value.
local ABBREVIATE_FROM = 10000

local function fmtCompact(n)
	if type(n) ~= "number" then return nil end

	local neg = n < 0
	local v = math.abs(n)

	if v < ABBREVIATE_FROM then
		local s = tostring(math.floor(v + 0.5))
		return neg and ("-" .. s) or s
	end

	local units = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for i = 1, #units do
		local div, suffix = units[i][1], units[i][2]
		if v >= div then
			local scaled = v / div
			-- Rounding can push a value up into the next unit -- 999999 would
			-- otherwise render as "1000K". Promote it instead.
			if scaled >= 999.95 and i > 1 then
				div, suffix = units[i - 1][1], units[i - 1][2]
				scaled = v / div
			end
			-- One decimal, with a trailing ".0" dropped so 5000 reads "5K".
			local s = string.format("%.1f", scaled):gsub("%.0$", "")
			s = s .. suffix
			return neg and ("-" .. s) or s
		end
	end
end

local function buildDivider()
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
	local comp = api.gui.comp.Component.new(DIVIDER_NAME)
	comp:setLayout(layout)
	return comp
end

--- One stocks line: icon, stored amount, consumption rate.
local function buildStockRow(row)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	local okIcon = pcall(function()
		layout:addItem(api.gui.comp.ImageView.new(cargoIcon(row.id)))
	end)
	if not okIcon then
		layout:addItem(api.gui.comp.TextView.new(tostring(row.id)))
	end

	-- LOW-STOCK HIGHLIGHT IS DISABLED, and deliberately so.
	--
	-- The rule needs `consumed` to be a RATE -- stored divided by per-year
	-- consumption gives years of cover, and colouring the short one is the
	-- whole reason to open this panel rather than the full window.
	--
	-- It no longer is a rate. The probe showed _lastYear/_lastMonth are never
	-- populated, so consumption is now a lifetime cumulative total (see
	-- rateOf). Dividing by that yields a vanishing ratio for every row, which
	-- would paint the entire table as a bottleneck -- strictly worse than no
	-- highlight at all.
	--
	-- Restore this the moment a real rate exists: sample itemsProduced._sum
	-- against game.interface.getGameTime().time and difference it. The
	-- threshold constant LOW_STOCK_YEARS is left in place for that, and the
	-- class it applies is unchanged.
	local coverClass = "rlvStatValue"

	local storedText = api.gui.comp.TextView.new(fmtCompact(row.stored) or "--")
	storedText:setStyleClassList({ coverClass })
	layout:addItem(storedText)

	local consumedText = api.gui.comp.TextView.new(fmtCompact(row.consumed) or "--")
	consumedText:setStyleClassList({ "rlvDest" })
	layout:addItem(consumedText)

	local comp = api.gui.comp.Component.new(ROW_NAME)
	comp:setLayout(layout)
	return comp
end

local function buildRow(row, townId)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	local okIcon = pcall(function()
		layout:addItem(api.gui.comp.ImageView.new(cargoIcon(row.id)))
	end)
	if not okIcon then
		layout:addItem(api.gui.comp.TextView.new(tostring(row.id)))
	end

	local function fmt(supply, limit)
		if limit and limit > 0 then
			-- Both sides abbreviated, so a large limit cannot widen the panel
			-- on its own. The percentage beside it carries the precision.
			return fmtCompact(supply or 0) .. " / " .. fmtCompact(limit),
			       string.format("%d%%", math.floor(((supply or 0) / limit) * 100 + 0.5))
		end
		return fmtCompact(supply or 0), "--"
	end

	local figure, pct = fmt(row.supply, row.limit)

	-- COLUMN DISCIPLINE, matching the station panel's per-line rows.
	--
	-- Both views previously carried NO class at all, so every town row sized
	-- itself to its own text and the figures came out ragged down the panel --
	-- which is what made this panel the odd one out after v1.6.
	--
	-- rlvLineCount right-aligns inside a fixed-width column, putting every
	-- figure's last digit on the same x. rlvStatMuted makes the percentage
	-- recessive, the same way throughput sits behind the line detail.
	--
	-- Deliberately NOT rlvRowIcon on the icon above: `rlvCityOverlayRow
	-- ImageView` already scales it, and `... ImageView!rlvRowIcon` is MORE
	-- specific (scaling 0.5), so adding the class would silently resize every
	-- town commodity icon. Specificity, not order, decides here.
	local figureView = api.gui.comp.TextView.new(figure)
	figureView:setStyleClassList({ "rlvLineCount" })
	layout:addItem(figureView)

	local pctView = api.gui.comp.TextView.new(pct)
	pctView:setStyleClassList({ "rlvStatMuted" })
	layout:addItem(pctView)

	local comp = api.gui.comp.Component.new(ROW_NAME)
	comp:setLayout(layout)
	return comp
end

--- Header line: population, shown as a passenger icon plus the count.
-- The town name is deliberately omitted -- the label directly above already
-- shows it, so repeating it just made the panel look like a separate window.
local function buildHeader(residents, townId)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	local okIcon = pcall(function()
		layout:addItem(api.gui.comp.ImageView.new("ui/hud/cargo_passengers.tga"))
	end)
	if not okIcon then
		layout:addItem(api.gui.comp.TextView.new(_("Pop.")))
	end

	local pop = api.gui.comp.TextView.new(tostring(residents or "--"))
	pop:setStyleClassList({ "rlvResidents" })
	layout:addItem(pop)

	-- Number then label, matching the town window's own "251 Residents".
	--
	-- NOTE: use the ENGLISH TEXT as the translation key here, not a symbolic
	-- id. Inside a game script _currentModIdTr is nil, so the mod's strings.lua
	-- lookup does not run and _() returns its argument verbatim -- which is why
	-- an earlier build rendered the literal "label_population" on screen.
	-- Symbolic ids only resolve in mod.lua, which loads with that context set.
	-- Other locales still work: map ["Population"] = "Bevölkerung" in strings.lua.
	local caption = api.gui.comp.TextView.new(_("Population"))
	caption:setStyleClassList({ "rlvPopCaption" })
	layout:addItem(caption)

	local comp = api.gui.comp.Component.new(HEADER_NAME)
	comp:setLayout(layout)
	return comp
end

--- A "Label   value" line for the industry readout.
--- Are town labels currently drawn? Drives whether the town panel repeats the
--- town's name.
--
-- menu.layers.hudFilter.towns lives in the PERSISTENT ui tree (unlike TownItem
-- itself), so getById should reach it. isSelected is the expected accessor;
-- both are unverified, so a failure is treated as "labels visible", which is
-- the state where omitting the name is correct anyway.
local function townLabelsVisible()
	local f = api.gui.util.getById("menu.layers.hudFilter.towns")
	if not f then
		if not state.loggedFilter then
			state.loggedFilter = true
			log("hudFilter.towns not reachable; assuming labels visible")
		end
		return true
	end

	local ok, sel = pcall(function() return f:isSelected() end)
	if not state.loggedFilter then
		state.loggedFilter = true
		log("hudFilter.towns isSelected ok=", tostring(ok), "value=", tostring(sel))
		if not ok then dumpKeys("hudFilter.towns", f) end
	end
	if ok and type(sel) == "boolean" then return sel end
	return true
end

--- Tag a panel with the current theme so the stylesheet can restyle it.
--
-- Style CLASSES are the only way to vary appearance at runtime: the stylesheet
-- itself is immutable and loads once per process, but setStyleClassList can be
-- called on components we build. Each theme name maps to a class with its own
-- surface colour.
--
-- Applies to panels as they are BUILT, so a theme change shows on the next
-- panel opened rather than retroactively restyling one already on screen.
local function applyTheme(panel)
	local cls = "rlvTheme" .. (settings.theme or "dark")
	local ok = pcall(function() panel:setStyleClassList({ cls }) end)
	if not state.loggedTheme then
		state.loggedTheme = true
		log("theme class applied:", cls, "ok=", tostring(ok))
	end
end

--- Title row: the entity's name, uppercase and bold, optionally preceded by
--- the commodity icons it produces.
--
-- Raw producers -- quarries, farms, forests -- consume nothing, so the stocks
-- section is empty and the panel otherwise gives no clue what the place makes.
-- Leading the title with the output icon fixes that, and reads well for
-- processors too.
local function buildTitleRow(name, outputIds)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	if outputIds then
		for i = 1, math.min(#outputIds, MAX_OUTPUT_ICONS) do
			pcall(function()
				local iv = api.gui.comp.ImageView.new(cargoIcon(outputIds[i]))
				iv:setStyleClassList({ "rlvOutIcon" })
				layout:addItem(iv)
			end)
		end
	end

	local t = api.gui.comp.TextView.new(tostring(name))
	t:setStyleClassList({ "rlvTitle" })
	layout:addItem(t)

	local comp = api.gui.comp.Component.new(HEADER_NAME)
	comp:setLayout(layout)
	return comp
end

--- What an industry produces, as a sorted list of cargo ids.
-- perCargo falls back through _lastYear -> _lastMonth -> the accumulator's own
-- top-level keys, so a brand-new industry with empty period buckets still
-- reports its output.
local function industryOutputs(entity)
	local produced = perCargo(entity and entity.itemsProduced)
	local ids = {}
	for id in pairs(produced) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b) return cargoOrder(a) < cargoOrder(b) end)
	return ids
end

-- valueClass is optional: it replaces rlvStatValue on the figure only, so a
-- single row can be highlighted without a second row builder.
local function buildStatRow(label, value, valueClass, labelClass)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	local cap = api.gui.comp.TextView.new(label)
	cap:setStyleClassList({ labelClass or "rlvStatLabel" })
	layout:addItem(cap)

	local val = api.gui.comp.TextView.new(value)
	val:setStyleClassList({ valueClass or "rlvStatValue" })
	layout:addItem(val)

	local comp = api.gui.comp.Component.new(ROW_NAME)
	comp:setLayout(layout)
	return comp
end

--- A stat row led by a cargo icon: icon, label, value.
--
-- Used for "Waiting here", so the exact per-stop figure carries the passengers
-- icon and reads as a commodity total rather than another line row. Falls back
-- to a plain row if the texture will not load.
local function buildIconStatRow(iconPath, label, value, valueClass)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	local okIcon = pcall(function()
		local iv = api.gui.comp.ImageView.new(iconPath)
		iv:setStyleClassList({ "rlvRowIcon" })
		layout:addItem(iv)
	end)
	if not okIcon then
		return buildStatRow(label, value, valueClass)
	end

	local cap = api.gui.comp.TextView.new(label)
	cap:setStyleClassList({ "rlvStatLabel" })
	layout:addItem(cap)

	local val = api.gui.comp.TextView.new(value)
	val:setStyleClassList({ valueClass or "rlvStatValue" })
	layout:addItem(val)

	local comp = api.gui.comp.Component.new(ROW_NAME)
	comp:setLayout(layout)
	return comp
end

--- Format a value that may be a plain number or a per-cargo table.
local function fmtValue(v)
	if v == nil then return "--" end
	if type(v) == "number" then
		return fmtCompact(v)
	end
	if type(v) == "table" then
		-- Per-cargo tables: sum them for the short form.
		local total, any = 0, false
		for _, n in pairs(v) do
			if type(n) == "number" then total = total + n; any = true end
		end
		if any then return fmtCompact(total) end
	end
	return tostring(v)
end

--- Industry readout: level, production, shipment, transport rating.
local function showIndustryPanel(entityId, entity, mouseX, mouseY)
	-- keepCycle: this is a replacement, not a dismissal. See destroyPanel.
	destroyPanel(false, nil, true)

	local s = industrySummary(entityId, entity)

	local layout = api.gui.layout.BoxLayout.new("VERTICAL")

	-- Industries have no world label carrying their name, so always show it --
	-- led by what they produce, which for a raw producer is the only indication
	-- of what the place actually does.
	if s.name then layout:addItem(buildTitleRow(s.name, industryOutputs(entity))) end

	if s.level then
		-- Engine level is 0-based; the window shows it 1-based.
		layout:addItem(buildStatRow(_("Level"), tostring(s.level + 1)))
	end

	-- LIFETIME TOTALS, not a rate -- and the label has to say so.
	--
	-- This previously read "Produced/yr", on the belief that the figures were
	-- trailing-twelve-month totals from the entity's _lastYear accumulators.
	-- The probe disproved that: _lastYear and _lastMonth are present in the
	-- shape but never populated -- both were zero on a well that had produced
	-- 817946 and shipped 279067. Only `_sum` carries data, and it is cumulative
	-- since the industry was built. See rateOf.
	--
	-- The game's own window shows a live rate over capacity ("30/100"),
	-- computed in C++ from the production rule -- getIndustryProduction and
	-- friends all fail their pcall. So the two still cannot be reconciled, but
	-- naming the period honestly is what keeps ours from looking broken.
	layout:addItem(buildStatRow(_("Produced"), fmtValue(s.production)))
	layout:addItem(buildStatRow(_("Shipped"),  fmtValue(s.shipping)))

	-- Transport rating scale is not yet pinned down: an earlier build rendered
	-- 1% for an industry the window showed at 100%, which is consistent with a
	-- 0..1 fraction. Handle both conventions rather than guess wrong -- values
	-- at or below 1 are treated as a fraction, above 1 as an actual percent.
	local rating = s.rating
	if type(rating) == "number" then
		local pct = (rating <= 1.0) and (rating * 100) or rating
		layout:addItem(buildStatRow(_("Transport"),
			string.format("%d%%", math.floor(pct + 0.5))))
	else
		layout:addItem(buildStatRow(_("Transport"), fmtValue(rating)))
	end

	-- Stored / consumed inputs, below a 1px rule. Omitted entirely for raw
	-- producers (a forest consumes nothing), so the panel stays short for the
	-- industries that have nothing to say here.
	local stocks, storedTotal = industryStocks(entity)
	if #stocks > 0 then
		layout:addItem(buildDivider())
		-- Stored is a CURRENT level; Used is a trailing-year total. Different
		-- kinds of number, so the header says so.
		-- "Used" not "Used/yr": the consumption column is the same lifetime
		-- total as Produced / Shipped above. See rateOf.
		layout:addItem(buildStatRow(_("Stored"), _("Used")))
		for i = 1, #stocks do
			layout:addItem(buildStockRow(stocks[i]))
		end

		-- Multi-input industries get a combined figure instead of per-cargo
		-- ones, because the slot-to-cargo mapping is not recoverable. Better a
		-- correct total than a confidently mislabelled breakdown.
		if storedTotal then
			layout:addItem(buildStatRow(_("Stored total"), fmtValue(storedTotal)))
		end
	end

	local panel = api.gui.comp.Component.new(PANEL_NAME)
	panel:setId(PANEL_ID)
	panel:setLayout(layout)
	applyTheme(panel)

	local host = panelHost()
	if not host then
		warn("no container available -- cannot show panel")
		return
	end

	local ok, err = pcall(function()
		host:addItem(panel, api.gui.util.Rect.new(mouseX - 12, mouseY + 14, 0, 0))
	end)
	if not ok then
		warn("failed to attach industry panel:", tostring(err))
		return
	end

	state.shownFor = entityId
	state.anchor   = { x = mouseX, y = mouseY }
end

--- Where is the cargo waiting at this station headed?
--
-- Destination is NOT on the station entity -- the dump showed only
-- cargoWaiting / itemsLoaded / itemsUnloaded / stations. The routing lives in
-- api.engine.system.simCargoSystem, whose binding block lists:
--     getSimCargosForTarget(targetEntity)
--     getSimCargosForSource(sourceEntity)
--     getSimCargosForLine(...)
-- Path and return shape are both unconfirmed, so this probes candidates and
-- dumps whatever it finds. Returns a map of cargoId -> destination name, or an
-- empty table. Never throws; the cargo list renders with or without it.
local function stationDestinations(stationId)
	local result = {}

	local sys = api and api.engine and api.engine.system
	local scs = sys and sys.simCargoSystem

	if not state.loggedDest then
		state.loggedDest = true
		log("--- destination probe ---")
		dumpKeys("api.engine", api and api.engine)
		if sys then dumpKeys("api.engine.system", sys) end
		if scs then dumpKeys("simCargoSystem", scs) end
	end

	if not scs then
		if not state.warnedDest then
			state.warnedDest = true
			log("simCargoSystem unavailable -- destinations cannot be resolved")
		end
		return result
	end

	-- CONFIRMED FAILURE: getSimCargosForSource(stationId) errors -- it returned
	-- a userdata error object, so the signature is wrong. It likely wants a
	-- transport-network or source entity, not a station group.
	--
	-- Pivoting: the game's own station window does not show per-cargo
	-- destinations at all -- it lists the LINES serving the station, each with
	-- its cargo counts ("Leatherhead Bread Transfer -- bread 19"). That is what
	-- "where it is going" means in this game's model, and it is a far more
	-- tractable lookup. Probe the line route first; keep the sim-cargo attempt
	-- only as a fallback.
	local ok, cargos = pcall(function()
		return scs.getSimCargosForSource(stationId)
	end)
	if not ok or type(cargos) ~= "table" then
		if not state.warnedDest then
			state.warnedDest = true
			log("getSimCargosForSource failed (signature wrong):", tostring(cargos))
			log("  -> destinations need the LINE route instead; see consolidated probe")
		end
		return result
	end

	if not state.loggedDestShape then
		state.loggedDestShape = true
		log("getSimCargosForSource returned", #cargos, "entries")
		if cargos[1] then
			local okC, c = pcall(game.interface.getEntity, cargos[1])
			if okC then describeShape("simCargo entity", c, 2) end
		end
	end

	-- Aggregate: most common destination per cargo type. Capped -- a busy
	-- station can hold a lot of sim cargo and this runs on right-click.
	local counts = {}
	for i = 1, math.min(#cargos, MAX_CARGO_SAMPLES) do
		local okC, c = pcall(game.interface.getEntity, cargos[i])
		if okC and type(c) == "table" then
			local ctype = c.cargoType or c.type
			local dest  = c.targetEntity or c.destinationEntity
			if ctype and dest then
				local okD, d = pcall(game.interface.getEntity, dest)
				local dname = okD and d and d.name or nil
				if dname then
					counts[ctype] = counts[ctype] or {}
					counts[ctype][dname] = (counts[ctype][dname] or 0) + 1
				end
			end
		end
	end

	for ctype, byName in pairs(counts) do
		local bestName, bestN
		for nm, n in pairs(byName) do
			if not bestN or n > bestN then bestName, bestN = nm, n end
		end
		result[ctype] = bestName
	end

	return result
end

--- Names of the lines serving a station.
--
-- This is what the game's own station window shows -- "Breirly Tool Transfer",
-- "Leatherhead Bread Transfer" and so on, each with its cargo counts. It is a
-- far better answer to "where is this going" than chasing individual sim-cargo
-- destinations, which failed outright (getSimCargosForSource errors).
--
-- lineSystem exposes, confirmed by probe:
--   getLineStopsForStation, getLineStops, getLineStopsForTerminal,
--   getLines, getLinesForPlayer, getStationGroup2LineStopsMap
-- Signatures are unverified, so each candidate is tried in turn and the shapes
-- are logged once.
local function stationLines(stationId, entity)
	local out = {}
	local sys = api and api.engine and api.engine.system
	local ls = sys and sys.lineSystem
	if not ls then return out end

	local lineIds

	-- Member station ids, since the group id may not be what these want.
	local memberId = entity and entity.stations and entity.stations[1] or nil

	-- Which variant produced the ids, so a bad id can be traced back to its
	-- source rather than just reported as "not a LINE".
	local usedVariant = nil

	local attempts = {
		{ "getLineStopsForStation(group)",  function() return ls.getLineStopsForStation(stationId) end },
		{ "getLineStopsForStation(member)", function() return memberId and ls.getLineStopsForStation(memberId) end },
	}

	for i = 1, #attempts do
		local name, fn = attempts[i][1], attempts[i][2]
		local ok, res = pcall(fn)
		local conv = ok and toTable(res) or nil
		if not state.loggedLines then
			log("lines:", name, "ok=", tostring(ok), "raw=", type(res),
				"converted=", conv and ("n=" .. #conv) or "nil")
			if conv and conv[1] then describeShape("lineStop[1]", conv[1], 2) end
		end
		if conv and #conv > 0 then
			lineIds = conv
			usedVariant = name
			break
		end
	end

	if not state.loggedLines then
		state.loggedLines = true
		local okMap, mRaw = pcall(ls.getStationGroup2LineStopsMap)
		local m = okMap and toTable(mRaw) or nil
		log("getStationGroup2LineStopsMap ok=", tostring(okMap),
			"raw=", type(mRaw), "converted=", type(m))
		if m then
			local n = 0
			for k, v in pairs(m) do
				n = n + 1
				if n <= 2 then
					log("  group", tostring(k), "->", type(v),
						type(v) == "table" and ("n=" .. #v) or tostring(v))
				end
			end
			log("  groups in map:", n)
		end
	end

	if type(lineIds) ~= "table" then return out end

	-- A line stop may be the line id itself, or a table carrying one.
	local seen = {}
	-- Trim NOTED, not silent: a station busier than the cap will be missing
	-- rows, and that must be traceable rather than looking like a lookup bug.
	if #lineIds > MAX_STATION_LINES then
		log("stationLines: station has", tostring(#lineIds),
			"line stops, showing first", tostring(MAX_STATION_LINES))
	end

	for i = 1, math.min(#lineIds, MAX_STATION_LINES) do
		local stop = lineIds[i]
		local lineId = (type(stop) == "table" and (stop.line or stop.lineEntity)) or stop
		if type(lineId) == "number" and not seen[lineId] then
			seen[lineId] = true
			local okL, le = pcall(game.interface.getEntity, lineId)

			-- VERIFY IT IS ACTUALLY A LINE.
			--
			-- The id above is inferred: a "line stop" may be the line id itself
			-- or a table carrying one, and which of those comes back varies by
			-- lookup variant and by station. When it is not a line, the colour
			-- lookup fails and the row falls back to a grey disc -- which is why
			-- the SAME line appeared coloured at one station and grey at
			-- another. A per-line colour cache cannot cause that; a differing id
			-- can.
			--
			-- getEntity reports .type, so reject anything that is not a LINE
			-- rather than carrying a wrong id into the colour and name lookups.
			local isLine = okL and le and le.type == "LINE"
			if okL and le and le.name and not isLine then
				log("stationLines: id", tostring(lineId), "is", tostring(le.type),
					"not LINE (via", tostring(usedVariant or "?"), ") -- skipped")
			end

			if isLine and le.name then
				out[#out + 1] = { id = lineId, name = le.name }
			end
		end
	end

	return out
end

--- Map cargo type -> name of the line it is waiting for.
--
-- Built by asking each line serving this station what cargo it is carrying
-- (simCargoSystem.getSimCargosForLine) and recording which types appear. That
-- is how the game's own station overview pairs a line with cargo icons.
--
-- Signature unverified -- logged once, and the panel falls back to "--" per
-- row if it does not resolve, so the amounts stay correct regardless.
--
-- THE CARRIER SET IS SAMPLED, so it is a lower bound. See the loop below.
local function cargoLineMap(lines)
	local map = {}
	-- cargoType -> { [lineId] = lineName } for every line seen carrying it.
	local carriers = {}
	local sys = api and api.engine and api.engine.system
	local scs = sys and sys.simCargoSystem
	local sps = sys and sys.simPersonSystem

	-- PASSENGERS ARE NOT CARGO.
	--
	-- A passenger station showed "PASSENGERS -> --" because
	-- getSimCargosForLine only covers freight; people are sim PERSONS, tracked
	-- by simPersonSystem, which exposes the mirror call getSimPersonsForLine.
	--
	-- Ask both per line: whichever returns entries tells us that line carries
	-- that traffic. Passengers get attributed directly, since a person on a
	-- line is a passenger by definition and needs no per-entity type lookup.
	if sps and sps.getSimPersonsForLine then
		for i = 1, #lines do
			local line = lines[i]
			local ok, people = pcall(function()
				return sps.getSimPersonsForLine(line.id)
			end)
			local conv = ok and toTable(people) or nil
			if not state.loggedPersonLine then
				state.loggedPersonLine = true
				log("getSimPersonsForLine(", tostring(line.id), ") ok=", tostring(ok),
					"raw=", type(people), "converted=", conv and ("n=" .. #conv) or "nil")
			end
			if conv and #conv > 0 and not map.PASSENGERS then
				map.PASSENGERS = { name = line.name, id = line.id }
			end
		end
	end

	if not scs or not scs.getSimCargosForLine then return map end

	for i = 1, #lines do
		local line = lines[i]
		local ok, cargos = pcall(function()
			return scs.getSimCargosForLine(line.id)
		end)

		local conv = ok and toTable(cargos) or nil
		if not state.loggedCargoLine then
			log("getSimCargosForLine(", tostring(line.id), ") ok=", tostring(ok),
				"raw=", type(cargos), "converted=", conv and ("n=" .. #conv) or "nil")
			if conv and conv[1] then
				local okC, c = pcall(game.interface.getEntity, conv[1])
				if okC then describeShape("lineCargo[1]", c, 2) end
			end
		end

		if conv then
			-- SAMPLED, therefore a LOWER BOUND on who carries what.
			--
			-- Only the first MAX_CARGO_SAMPLES items of a line are decoded, so
			-- a commodity this line rarely moves can fall outside the sample
			-- and the line is never recorded as one of its carriers.
			--
			-- That matters because of what the caller does with the result: a
			-- commodity with one known carrier gets that line's NAME and
			-- COLOUR, while two or more get the neutral "N lines". Undercount
			-- the carriers of an ambiguous commodity down to one and the panel
			-- goes back to confidently naming a line -- the exact bug the
			-- carriers table was added to kill, just rarer.
			--
			-- Left sampled deliberately. The cap is one getEntity per item and
			-- this runs on every right-click; the industry panel already lost a
			-- 120-entity walk for being too slow. Raising it trades a hitch on
			-- busy saves against a rare mislabel, and the mislabel is the
			-- cheaper failure. Documented in the v1.7 changelog so a player who
			-- sees it knows why.
			for j = 1, math.min(#conv, MAX_CARGO_SAMPLES) do
				local okC, c = pcall(game.interface.getEntity, conv[j])
				if okC and type(c) == "table" then
					local ctype = c.cargoType or c.type
					if ctype then
						-- RECORD EVERY LINE, then decide afterwards.
						--
						-- This used to be "first line wins", on the assumption
						-- that one line serves a commodity at a given station.
						-- That assumption is false at any interchange, and it
						-- is the whole bug: two lines carrying the same goods
						-- collapsed into one row labelled with whichever was
						-- found first, so the panel confidently named the
						-- wrong line.
						carriers[ctype] = carriers[ctype] or {}
						carriers[ctype][line.id] = line.name
					end
				end
			end
		end
	end

	-- A line is named ONLY when it is the sole carrier of that commodity here.
	-- With two or more the honest answer is that we cannot tell which, and the
	-- row says so instead of guessing.
	for ctype, byLine in pairs(carriers) do
		local all = {}
		for lid, lname in pairs(byLine) do
			all[#all + 1] = { id = lid, name = lname }
		end
		table.sort(all, function(a, b)
			return tostring(a.name) < tostring(b.name)
		end)

		-- KEEP THE WHOLE LIST.
		--
		-- Which line a given waiting item is queued for is not recorded, so a
		-- single confident label is a guess. But WHICH LINES HANDLE THIS
		-- COMMODITY HERE is a set question, and the set is right here -- every
		-- line serving this stop that carries this cargo. Naming them all is
		-- both honest and more useful than naming one and hiding the rest.
		map[ctype] = {
			name  = all[1] and all[1].name or nil,   -- sole carrier, when n == 1
			id    = all[1] and all[1].id or nil,
			lines = all,
			count = #all,
		}
	end

	state.loggedCargoLine = true
	return map
end

--- A line's colour as { r, g, b } in 0-255, or nil.
--
-- The LINE component does NOT carry colour -- its Lua usertype exposes only
-- stops, waitingTime and vehicleInfo. Colour is the separate COLOR component
-- (api.type: COLOR = 64, "an RGB vector"), and its `color` field hands back the
-- values as 0-1 floats. Confirmed at runtime on two lines: (1/0/1) and
-- (0.968/0.505/0.505).
--
-- The vector does NOT iterate -- toTable returns nil -- but both .x/.y/.z and
-- [1]/[2]/[3] resolve, because __index is a function. Note it is 1-BASED: an
-- earlier attempt read [0] first, got nil, and fell through.
--
-- Cached per line: the answer never changes and this runs on every right-click.
local lineColorCache = {}

local function lineColor(lineId)
	if lineColorCache[lineId] ~= nil then
		local c = lineColorCache[lineId]
		return c ~= false and c or nil
	end

	local out, why = nil, nil
	local ct = api and api.type and api.type.ComponentType
	if not (ct and ct.COLOR) then
		why = "no ComponentType.COLOR"
	else
		local okAll = pcall(function()
			local comp = api.engine.getComponent(lineId, ct.COLOR)
			if not comp then why = "no COLOR component" return end
			local c = comp.color
			if not c then why = "component has no .color" return end

			-- 1-BASED. An early version read c[0] first, got nil, and only
			-- worked because of the .x fallback below.
			local r, g, b = c[1], c[2], c[3]
			if r == nil then r, g, b = c.x, c.y, c.z end
			if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
				why = "vector unreadable (" .. type(r) .. ")"
				return
			end
			out = { math.floor(r * 255 + 0.5),
			        math.floor(g * 255 + 0.5),
			        math.floor(b * 255 + 0.5) }
		end)
		if not okAll and not why then why = "lookup errored" end
	end

	-- Say WHY a line fell back to the neutral chip. Silent nils were being read
	-- as "that line has no colour" when the cause could equally be a failed
	-- lookup -- and the result is cached, so one transient failure would stick
	-- for the rest of the session.
	if not out then
		state.loggedNoColor = state.loggedNoColor or {}
		if not state.loggedNoColor[lineId] then
			state.loggedNoColor[lineId] = true
			log("line", tostring(lineId), "has no colour:", tostring(why))
		end
	end

	lineColorCache[lineId] = out or false
	return out
end

--- A line-colour disc.
--
-- Kept as one helper because three row builders need it -- passenger rows,
-- per-line cargo rows and the fallback cargo rows -- and the colour-to-class
-- arithmetic should live in exactly one place.
--
-- NO BORDER OR RING. Both were tried and reverted: borderWidth on a TextView
-- draws a rectangle around the glyph's text box (it outlined the cell, not the
-- circle), and stacking a larger disc behind it added weight without earning
-- it. The plain disc is what the panel wants.
--
-- Colour cannot be applied at runtime -- setColor rejects every argument form
-- and api.gui.util has no Color type -- so the stylesheet carries a 216-entry
-- quantised grid (6 levels per channel, index r*36 + g*6 + b) and this snaps to
-- the nearest.
local function buildLineDot(color)
	local dot = api.gui.comp.TextView.new("\226\151\143")  -- U+25CF BLACK CIRCLE

	if color then
		local function level(v)
			return math.floor((math.max(0, math.min(255, v)) / 255) * 5 + 0.5)
		end
		local idx = level(color[1]) * 36 + level(color[2]) * 6 + level(color[3])
		dot:setStyleClassList({ "rlvLineDot", "rlvDot" .. idx })
	else
		-- Neutral grey via its own class rather than a default on rlvLineDot:
		-- the two have equal specificity, so a colour there would win on
		-- declaration order and repaint every dot.
		dot:setStyleClassList({ "rlvLineDot", "rlvDotNone" })
	end

	return dot
end

--- Passengers per line at this station.
--
-- Returns { name, count, color } sorted busiest first, where `count` is the
-- line's total passengers -- everyone travelling with it, route-wide.
--
-- PER-STOP ATTRIBUTION IS NOT AVAILABLE, and this is settled rather than
-- unfinished. Everything below was probed against a live save:
--
--   station entity            cargoWaiting totals only; no per-line split and
--                             no person ids to intersect
--   SIM_PERSON.sourceEntity   does not exist (that is a cargo field)
--   SIM_PERSON.targetOrAtEntity  21 distinct values, every one a CONSTRUCTION
--                             -- the person's destination BUILDING
--   SIM_PERSON.destinations[1]   26 distinct, all CONSTRUCTION, none matching
--                             the station
--   simPersonAtTerminalSystem  only getEdgeInfoMap/getNumFreePlaces/getPos01
--   getSimPersonsAtTerminalForTransportNetwork  needs a tnEntity; stations,
--                             their members, their constructions and
--                             getEntities{TRANSPORT_NETWORK} all fail to yield
--                             one
--   STATION component         returns nil on the group and its members, so its
--                             documented `terminals`/`personNodes` are
--                             unreachable
--   subtraction (onLine minus riders)  getLineVehicles yields nothing usable
--                             from either lineSystem or game.interface
--
-- The panel therefore shows an EXACT per-stop total in its own highlighted row
-- (straight from cargoWaiting) above these route-wide line figures. Two honest
-- numbers rather than one invented one.
--
-- An earlier version walked every person on the line calling getEntity to
-- filter by station -- up to 120 lookups per right-click, always returning
-- zero. Removed: it cost real time per click and produced nothing.
local function linePassengers(stationId, entity, lines)
	local out = {}
	local sys = api and api.engine and api.engine.system
	local sps = sys and sys.simPersonSystem
	if not (sps and sps.getSimPersonsForLine) then return out end

	for i = 1, #lines do
		local line = lines[i]
		local ok, people = pcall(function() return sps.getSimPersonsForLine(line.id) end)
		local ids = ok and toTable(people) or nil
		local total = ids and #ids or 0

		-- Only lines someone is actually travelling with. A freight station is
		-- served by freight lines, every one reporting zero -- listing them all
		-- made a cargo yard look like a passenger interchange.
		if total > 0 then
			out[#out + 1] = {
				name  = line.name,
				count = total,
				color = lineColor(line.id),
			}
		end
	end

	table.sort(out, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return tostring(a.name) < tostring(b.name)
	end)
	return out
end

--- One per-line passenger row: coloured dot, count, arrow, line name.
local function buildLinePassengerRow(row)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	-- Line chip: coloured disc with a contrasting ring. See buildLineDot.
	layout:addItem(buildLineDot(row.color))

	-- ORDER: dot, count, line name.
	--
	-- The dot and its number read as one unit -- "this line, this many" -- with
	-- the name trailing as the label. rlvLineCount rather than rlvStatValue
	-- because that class right-aligns for the label/value rows, which would
	-- shove the number away from its dot.
	--
	-- If per-stop attribution ever becomes available, this is the one place to
	-- change: build atStop .. " / " .. count instead. See linePassengers for the
	-- routes ruled out.
	local amt = api.gui.comp.TextView.new(fmtCompact(row.count) or tostring(row.count))
	amt:setStyleClassList({ "rlvLineCount" })
	layout:addItem(amt)

	local name = api.gui.comp.TextView.new(tostring(row.name or "?"))
	name:setStyleClassList({ "rlvDest" })
	layout:addItem(name)

	local comp = api.gui.comp.Component.new(ROW_NAME)
	comp:setLayout(layout)
	return comp
end

--- A blank vertical gap. Height comes from the stylesheet.
--
-- Used to separate the exact per-stop figure from the whole-line rows beneath
-- it, so the two groups do not read as one list of comparable numbers.
local function buildSpacer()
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")
	local comp = api.gui.comp.Component.new(SPACER_NAME)
	comp:setLayout(layout)
	return comp
end

-- REMOVED: lineCargo() and buildLineCargoRow().
--
-- They tried to break waiting freight down per line by filtering
-- getSimCargosForLine on `sourceEntity`. Two things were wrong, both now
-- measured rather than assumed:
--
--   1. getSimCargosForLine returns cargo IN TRANSIT ONLY. Probed twice on
--      different lines: 436 of 436 and 395 of 395 items had vehicleUsed=true,
--      and zero were waiting. It answers "what is this line carrying", never
--      "what is waiting HERE".
--   2. `sourceEntity` is the ORIGIN, not the current location -- every sampled
--      item shared one src (the producing industry) while targetEntity varied.
--
-- The filter therefore matched nothing, the loop body never ran, and the
-- function silently returned an empty list on every call. The panel fell
-- through to the flat per-commodity list below, which is what players have
-- actually been seeing all along.
--
-- DO NOT REBUILD THIS against getSimCargosForLine. Per-stop waiting freight
-- needs simCargoAtTerminalSystem, which wants a transport-network entity --
-- and stations do not carry a TRANSPORT_NETWORK component (probed on four
-- stations: ok=true, type=nil every time).
--
-- The probe that established all of the above lived here and has been lifted
-- out; its findings are written up under "Per-station attribution" in
-- API-NOTES.md, and the instrument itself is parked in
-- tools/probe_terminal_pax.lua should a future patch make this worth retesting.

--- One waiting-cargo line: icon, amount, and where it is headed.
-- `dest` is { name, id } from cargoLineMap, or nil when no line could be
-- attributed. The id is what makes the coloured disc possible.
--- Sub-rows naming every line that carries a commodity at this stop.
--
-- Returns a list of components, empty when a single line carries it (that case
-- is already named inline on the commodity row itself).
--
-- No count on these rows, deliberately: the amount belongs to the commodity as
-- a whole and splitting it per line is exactly the attribution the game does
-- not expose. These rows answer "which lines handle this here", nothing more.
local function buildCargoLineList(dest)
	local out = {}
	if not (dest and dest.lines and #dest.lines > 1) then return out end

	for i = 1, #dest.lines do
		local ln = dest.lines[i]
		local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

		-- Indent under the commodity row it belongs to.
		local pad = api.gui.comp.TextView.new("   ")
		layout:addItem(pad)

		layout:addItem(buildLineDot(lineColor(ln.id)))

		local name = api.gui.comp.TextView.new(tostring(ln.name or "?"))
		name:setStyleClassList({ "rlvDest" })
		layout:addItem(name)

		local comp = api.gui.comp.Component.new(ROW_NAME)
		comp:setLayout(layout)
		out[#out + 1] = comp
	end
	return out
end

local function buildStationCargoRow(cargoId, amount, dest)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	local okIcon = pcall(function()
		layout:addItem(api.gui.comp.ImageView.new(cargoIcon(cargoId)))
	end)
	if not okIcon then
		layout:addItem(api.gui.comp.TextView.new(tostring(cargoId)))
	end

	local amt = api.gui.comp.TextView.new(fmtCompact(amount) or tostring(amount))
	amt:setStyleClassList({ "rlvStatValue" })
	layout:addItem(amt)

	-- A LINE-COLOURED DISC, not an arrow.
	--
	-- The arrow said "headed for", which the disc says just as well while also
	-- identifying WHICH line at a glance -- and it matches the passenger rows,
	-- so both halves of the panel use one visual language for "this line".
	-- No colour when the carrier is ambiguous: a coloured disc would point at
	-- one specific line, which is exactly the claim we cannot make.
	layout:addItem(buildLineDot(
		(dest and dest.id and (dest.count or 1) == 1) and lineColor(dest.id) or nil))

	local label, cls
	if dest and dest.count and dest.count > 1 then
		-- The commodity row itself stays neutral; the lines are listed beneath
		-- it by buildCargoLineList, one per row, so a stop served by four
		-- liquid lines reads as four lines rather than "4 lines".
		label = tostring(dest.count) .. " " .. _("lines")
		cls   = "rlvStatMuted"
	elseif dest and dest.name then
		label = tostring(dest.name)
		cls   = "rlvDest"
	else
		label = "--"
		cls   = "rlvDest"
	end

	local nameText = api.gui.comp.TextView.new(label)
	nameText:setStyleClassList({ cls })
	layout:addItem(nameText)

	local comp = api.gui.comp.Component.new(ROW_NAME)
	comp:setLayout(layout)
	return comp
end

--- Station / depot readout.
--
-- Their entity field names are not yet confirmed, so this renders the name
-- plus any top-level scalar fields, and dumps the full structure once per kind
-- so the next pass can show curated stats (waiting cargo, vehicle counts)
-- instead of whatever happens to be there.
local function showEntityPanel(entityId, kind, entity, mouseX, mouseY)
	-- keepCycle: this is a replacement, not a dismissal. See destroyPanel.
	destroyPanel(false, nil, true)

	local concrete = (entity and entity.type) or kind
	if not state.loggedKinds[concrete] then
		state.loggedKinds[concrete] = true
		log("--- " .. kind .. " (" .. tostring(concrete) .. ") entity data ---")
		describeShape("getEntity(" .. tostring(concrete) .. ")", entity, 3)
		log("--- end " .. kind .. " entity data ---")
	end

	local layout = api.gui.layout.BoxLayout.new("VERTICAL")

	-- Name as a title rather than a label/value pair -- no world label carries
	-- a station or depot name, so it always shows.
	if entity and entity.name then
		layout:addItem(buildTitleRow(entity.name))
	end

	local shown = 0

	if kind == "STATION" then
		-- CONFIRMED SHAPE (from runtime), type is STATION_GROUP:
		--   name, id, position, stations = { memberIds }
		--   cargoWaiting  = { LOGS = 30 }
		--   itemsLoaded   = { _sum, LOGS, _lastYear = { LOGS, _sum }, _lastMonth }
		--   itemsUnloaded = { same }
		--
		-- Rendered as an icon list mirroring the town panel, one row per cargo
		-- type waiting, with its most common destination.
		local rows = {}
		if type(entity.cargoWaiting) == "table" then
			for k, v in pairs(entity.cargoWaiting) do
				if type(v) == "number" and tostring(k):sub(1, 1) ~= "_" then
					rows[#rows + 1] = { id = k, amount = v }
				end
			end
		end

		table.sort(rows, function(a, b)
			local oa = cargoOrder(a.id)
			local ob = cargoOrder(b.id)
			if oa ~= ob then return oa < ob end
			return a.id < b.id
		end)

		-- Which line is each waiting cargo queued for. Replaces the earlier
		-- per-cargo destination lookup, which could not be made to work
		-- (getSimCargosForSource errors on a station group).
		local lines = stationLines(entityId, entity)
		local byCargo = cargoLineMap(lines)

		-- PASSENGERS GET THEIR OWN PER-LINE ROWS.
		--
		-- cargoWaiting gives one combined passenger total for the station, which
		-- answers "how many are here" but not "waiting for what" -- and at a
		-- stop served by several lines that is the question worth asking. So the
		-- passenger row is replaced by one row per line: coloured dot, count,
		-- arrow, line name. Freight keeps its existing single row per commodity.
		local paxRows = linePassengers(entityId, entity, lines)
		local haveLinePax = #paxRows > 0

		-- THE TWO NUMBERS MEAN DIFFERENT THINGS, so both are shown.
		--
		-- The station's own passenger total is exact -- it comes straight from
		-- cargoWaiting, the same figure the game shows. What is NOT available is
		-- splitting it per line: a SIM_PERSON carries no field naming the stop it
		-- waits at (targetOrAtEntity is its destination), the station holds no
		-- person ids to intersect, and every per-terminal call needs a transport
		-- network id that stations do not carry. Six routes, all dead.
		--
		-- So the header states what is true of THIS STOP, and each line row
		-- states the total for THAT LINE across its whole route. Together they
		-- answer "how busy is this stop" and "which of its lines is loaded",
		-- without either number pretending to be the other.
		local hereTotal = nil
		if haveLinePax and type(entity.cargoWaiting) == "table" then
			local v = entity.cargoWaiting.PASSENGERS
			if type(v) == "number" then hereTotal = v end
		end

		-- FREIGHT SUMMARY: everything waiting here, combined, over capacity.
		--
		-- The total is exact -- cargoWaiting summed across commodities.
		-- Capacity is attempted via simCargoAtTerminalSystem.getMaxCount, whose
		-- signature is undocumented, so several argument shapes are tried and
		-- the figure is simply omitted if none work. A total with no
		-- denominator is still useful; a wrong denominator is not.
		local freightTotal, freightKinds = 0, 0
		for i = 1, #rows do
			if rows[i].id ~= "PASSENGERS" then
				freightTotal = freightTotal + (rows[i].amount or 0)
				freightKinds = freightKinds + 1
			end
		end

		local capacity = nil
		do
			local scat = api.engine.system.simCargoAtTerminalSystem
			if scat and scat.getMaxCount and freightKinds > 0 then
				local ids = { entityId }
				local mem = toTable(entity.stations)
				if mem then for _, m in pairs(mem) do ids[#ids + 1] = m end end
				local sum = 0
				for _, sid in ipairs(ids) do
					for term = 0, 3 do
						local okC, v = pcall(function() return scat.getMaxCount(sid, term) end)
						if okC and type(v) == "number" and v > 0 then sum = sum + v end
					end
				end
				if sum > 0 then capacity = sum end
			end
		end

		if #rows == 0 and not haveLinePax then
			layout:addItem(api.gui.comp.TextView.new(_("Nothing waiting")))
			shown = 1
		else
			if hereTotal then
				-- Yellow, because this is the one exact per-stop figure on the
				-- panel -- everything below it is a whole-line total. The colour
				-- is doing the work the labels cannot do in a narrow column.
				layout:addItem(buildIconStatRow("ui/hud/cargo_passengers.tga",
					_("Waiting here"), fmtCompact(hereTotal), "rlvHighlight"))
				layout:addItem(buildSpacer())
				shown = shown + 1
			end
			for i = 1, #paxRows do
				layout:addItem(buildLinePassengerRow(paxRows[i]))
				shown = shown + 1
			end
			-- Rule under the per-line block, separating it from the freight rows
			-- and throughput figures that follow.
			if #paxRows > 0 then
				layout:addItem(buildDivider())
			end
			-- FREIGHT: exact station total, then one row per commodity.
			--
			-- There is deliberately no per-line breakdown here. Waiting freight
			-- cannot be attributed to a line -- see the removal note above.
			if freightTotal > 0 then
				local txt = fmtCompact(freightTotal) or tostring(freightTotal)
				if capacity then
					txt = txt .. " / " .. (fmtCompact(capacity) or tostring(capacity))
				end
				layout:addItem(buildIconStatRow("ui/hud/cargo_goods.tga",
					_("Freight here"), txt, "rlvHighlight"))
				layout:addItem(buildSpacer())
				shown = shown + 1
			end

			-- One row per commodity. The amount is exact (cargoWaiting); the
			-- line beside it is shown only where it is unambiguous.
			for i = 1, #rows do
				if not (haveLinePax and rows[i].id == "PASSENGERS") then
					local dest = byCargo[rows[i].id]
					layout:addItem(buildStationCargoRow(
						rows[i].id, rows[i].amount, dest))
					shown = shown + 1

					-- Name every line handling this commodity here.
					local subRows = buildCargoLineList(dest)
					for j = 1, #subRows do
						layout:addItem(subRows[j])
						shown = shown + 1
					end
				end
			end

			if freightTotal > 0 then
				layout:addItem(buildDivider())
			end
		end

		-- Throughput summary under the list.
		-- "Loaded"/"Unloaded" is the engine's own vocabulary, but in a compact
		-- panel it reads ambiguously -- loaded onto what, by whom. These are
		-- really the station's two throughput DIRECTIONS: items put onto
		-- vehicles here versus taken off here. Outbound/Inbound says that
		-- directly, and works for passengers as well as freight.
		-- Muted: throughput is background context, not the thing you opened the
		-- panel for. Greying it keeps the line rows and the heading dominant.
		layout:addItem(buildStatRow(_("Outbound/yr"),
			fmtValue(rateOf(entity.itemsLoaded)), "rlvStatMuted", "rlvStatMuted"))
		layout:addItem(buildStatRow(_("Inbound/yr"),
			fmtValue(rateOf(entity.itemsUnloaded)), "rlvStatMuted", "rlvStatMuted"))

		-- Line names now sit on the cargo rows themselves, so no separate list.
	else
		-- DEPOT: shape still unconfirmed -- no depot has been selected yet, so
		-- nothing has been dumped. Surface scalars and accumulator totals until
		-- the log shows what a depot actually carries.
		local skip = { id = true, type = true, position = true, name = true }
		if type(entity) == "table" then
			for k, v in pairs(entity) do
				if shown >= 5 then break end
				if not skip[k] then
					if type(v) == "number" then
						layout:addItem(buildStatRow(tostring(k), fmtValue(v)))
						shown = shown + 1
					elseif type(v) == "table" then
						local r = rateOf(v)
						if r then
							layout:addItem(buildStatRow(tostring(k), fmtValue(r)))
							shown = shown + 1
						end
					end
				end
			end
		end
	end

	if shown == 0 and not (entity and entity.name) then
		layout:addItem(api.gui.comp.TextView.new(_("No data")))
	end

	local panel = api.gui.comp.Component.new(PANEL_NAME)
	panel:setId(PANEL_ID)
	panel:setLayout(layout)
	applyTheme(panel)

	local host = panelHost()
	if not host then
		warn("no container available -- cannot show panel")
		return
	end

	local ok, err = pcall(function()
		host:addItem(panel, api.gui.util.Rect.new(mouseX - 12, mouseY + 14, 0, 0))
	end)
	if not ok then
		warn("failed to attach " .. kind .. " panel:", tostring(err))
		return
	end

	state.shownFor = entityId
	state.anchor   = { x = mouseX, y = mouseY }
end

--- Show the readout anchored to the label the user clicked.
--
-- NOTE: this cannot be a true child of the town label. TownItem is rendered in
-- C++ by HudIconManager and is not present in the api.gui tree, so getById
-- cannot reach it and nothing can be reparented into it. We instead anchor at
-- the click point -- which IS the label, since that is what was clicked -- and
-- style the panel to match the label's plate so the two read as one unit.
local function showPanel(townId, mouseX, mouseY)
	-- keepCycle: this is a replacement, not a dismissal. See destroyPanel.
	destroyPanel(false, nil, true)

	local rows = cargoRows(townId)
	local residents = townSummary(townId)

	local layout = api.gui.layout.BoxLayout.new("VERTICAL")

	-- Town name visibility, per the "Town name" setting.
	--   auto   -- only when the label is switched off, so it is never a
	--             duplicate of the label sitting directly above
	--   always -- show regardless of the HUD filter
	--   never  -- omit entirely
	local nameMode = settings.townName or "auto"
	local showName = (nameMode == "always")
		or (nameMode == "auto" and not townLabelsVisible())

	if showName then
		local okN, e = pcall(game.interface.getEntity, townId)
		if okN and e and e.name then layout:addItem(buildTitleRow(e.name)) end
	end

	layout:addItem(buildHeader(residents, townId))

	if #rows == 0 then
		layout:addItem(api.gui.comp.TextView.new(_("No commodity demand")))
	else
		-- Rule under the population line, so the headline figure sits apart
		-- from the commodity list -- the same separation the station panel
		-- puts between its exact total and the per-line rows beneath it.
		layout:addItem(buildDivider())
		for i = 1, #rows do
			layout:addItem(buildRow(rows[i], townId))
		end
	end

	local panel = api.gui.comp.Component.new(PANEL_NAME)
	panel:setId(PANEL_ID)
	panel:setLayout(layout)
	applyTheme(panel)

	local host = panelHost()
	if not host then
		warn("no container available -- cannot show panel")
		return
	end

	-- Hang directly beneath the click point so it reads as the label
	-- unfolding, rather than a tooltip floating off to one side.
	local ok, err = pcall(function()
		host:addItem(panel, api.gui.util.Rect.new(mouseX - 12, mouseY + 14, 0, 0))
	end)
	if not ok then
		warn("failed to attach panel:", tostring(err))
		return
	end

	state.shownFor = townId
	state.anchor   = { x = mouseX, y = mouseY }
end

-- ---------------------------------------------------------------------------
-- OPTIONS PANEL
--
-- A real in-game settings surface, because mod params cannot be changed
-- mid-session. Built from the same api.gui primitives as the detail panels and
-- hosted in our own overlay root, so it is not at the mercy of the engine's
-- tooltip layer.
--
-- Each row is a label plus a button showing the current value; clicking cycles
-- to the next. Dropdowns were tried and abandoned -- see buildOptionRow.
-- ---------------------------------------------------------------------------

--- Host for INTERACTIVE UI.
--
-- The overlay root used by the detail panels is setTransparent(true) so it
-- passes mouse input straight through -- without that, a full-screen component
-- swallows camera rotation, scroll zoom and the nav bar. But transparency
-- applies to its children too, so anything inside it can never be clicked.
-- That is why the options buttons did nothing: the clicks went through the
-- panel to the world behind it.
--
-- Interactive UI therefore attaches DIRECTLY to a mainView layer instead. That
-- layer's layout is a box layout with no absolute positioning, so the options
-- panel is placed with gravity/margin from the stylesheet rather than a Rect --
-- and because it is sized to its content, it only intercepts clicks where it
-- actually is.
local function interactiveHost()
	local mainView = api.gui.util.getById("mainView")
	if not mainView then return nil end

	local okML, mainLayout = pcall(function() return mainView:getLayout() end)
	if not okML or not mainLayout then return nil end

	local okL, layer = pcall(function() return mainLayout:getItem(OVERLAY_LAYER) end)
	if not okL or not layer then return nil end

	local okLL, layerLayout = pcall(function() return layer:getLayout() end)
	if not okLL or not layerLayout then return nil end

	return layerLayout
end

local OPTIONS_ID   = "rlvDetailsOptions"
local OPTIONS_NAME = "rlvDetailsOptions"
local OPTION_ROW_NAME = "rlvDetailsOptionRow"

local function optionsOpen()
	return api.gui.util.getById(OPTIONS_ID) ~= nil
end

local function closeOptions(fromCallback)
	local elem = api.gui.util.getById(OPTIONS_ID)
	if not elem then return end

	local host = interactiveHost()
	if host then pcall(function() host:removeItem(elem) end) end
	if fromCallback then
		pcall(function() api.gui.util.destroyLater(elem) end)
	else
		pcall(function() elem:destroy() end)
	end
end

--- Label + control row. Clicking the value cycles to the next option.
--
-- REVERTED FROM ComboBox, deliberately.
--
-- Dropdowns looked right but could not be made to work reliably: binding
-- onIndexChanged succeeded yet never fired, and after also binding
-- onCurrentIndexChanged only some rows responded. Their construction and
-- signal semantics are unverified -- no shipped Lua builds one, the base game
-- only styles ComboBoxes created in C++.
--
-- Cycling buttons use Button + onClick, which is proven in this codebase and
-- in build-with-collision. A settings panel that works beats one that looks
-- more native and does nothing.
--
-- The row MUTATES its own text rather than rebuilding the panel. Rebuilding
-- failed with a duplicate-id error, because closeOptions defers destruction via
-- destroyLater, and it also meant destroying a component tree from inside a
-- callback belonging to a button within it.
--
-- Changes are logged, but behind the debug switch. They were unconditional
-- while the panel was being debugged; a shipped mod should not narrate every
-- click into the player's log.
local function buildOptionRow(label, items, values, getCurrent, onSelect)
	local layout = api.gui.layout.BoxLayout.new("HORIZONTAL")

	local cap = api.gui.comp.TextView.new(label)
	cap:setStyleClassList({ "rlvOptLabel" })
	layout:addItem(cap)

	local function textFor(v)
		for i = 1, #values do
			if values[i] == v then return items[i] end
		end
		return tostring(v)
	end

	local valueView = api.gui.comp.TextView.new(textFor(getCurrent()))
	local btn = api.gui.comp.Button.new(valueView, true)
	btn:setStyleClassList({ "rlvOptButton" })
	btn:onClick(function()
		local nextVal = cycleValue(values, getCurrent())
		onSelect(nextVal)
		pcall(function() valueView:setText(textFor(nextVal)) end)
		log("setting:", label, "->", tostring(nextVal))
	end)
	layout:addItem(btn)

	local comp = api.gui.comp.Component.new(OPTION_ROW_NAME)
	comp:setLayout(layout)
	return comp
end

local function buildOptionsPanel()
	local layout = api.gui.layout.BoxLayout.new("VERTICAL")

	local title = api.gui.comp.TextView.new(_("Right Click Details Settings"))
	title:setStyleClassList({ "rlvTitle" })
	local titleWrap = api.gui.comp.Component.new(HEADER_NAME)
	local tl = api.gui.layout.BoxLayout.new("HORIZONTAL")
	tl:addItem(title)
	titleWrap:setLayout(tl)
	layout:addItem(titleWrap)

	layout:addItem(buildDivider())

	layout:addItem(buildOptionRow(_("Detail panel"),
		{ _("On"), _("Off") }, { true, false },
		function() return settings.panelEnabled end,
		function(v) settings.panelEnabled = v; broadcastSettings() end))

	layout:addItem(buildOptionRow(_("Closes on"),
		{ DISMISS_TEXT.click, DISMISS_TEXT.move, DISMISS_TEXT.sticky },
		DISMISS_MODES,
		function() return settings.dismissMode end,
		function(v) settings.dismissMode = v; broadcastSettings() end))

	layout:addItem(buildOptionRow(_("Town name"),
		{ TOWN_NAME_TEXT.auto, TOWN_NAME_TEXT.always, TOWN_NAME_TEXT.never },
		TOWN_NAME_MODES,
		function() return settings.townName end,
		function(v) settings.townName = v; broadcastSettings() end))

	layout:addItem(buildOptionRow(_("Theme"),
		{ THEME_TEXT.dark, THEME_TEXT.darker, THEME_TEXT.light },
		THEMES,
		function() return settings.theme end,
		function(v) settings.theme = v; broadcastSettings() end))

	layout:addItem(buildDivider())

	-- Footer: Close at one end, the debug toggle at the other.
	--
	-- Debug is a support switch rather than a player preference, so it gets a
	-- ladybug glyph in the corner instead of a labelled row. It has to live
	-- here: the main-menu mod param cannot be relied on to reach a save already
	-- in progress, and even when it does, a param change needs a save/reload to
	-- take effect -- useless when the thing you want logged is happening now.
	local closeText = api.gui.comp.TextView.new(_("Close"))
	local closeBtn = api.gui.comp.Button.new(closeText, true)
	closeBtn:setStyleClassList({ "rlvOptButton" })
	closeBtn:onClick(function() closeOptions(true) end)

	local cl = api.gui.layout.BoxLayout.new("HORIZONTAL")
	cl:addItem(closeBtn)

	-- SWAP THE IMAGE, do not restyle it.
	--
	-- The two states cannot be a `color` swap on one greyscale mask: the
	-- engine's UI art is 8-bit coverage and `color` on an ImageView only tints
	-- RGBA, so a mode "L" file renders raw and ignores the stylesheet. Same
	-- defect that made the toolbar disc grey. So they are two finished RGBA
	-- textures, both baked by tools/make_ladybug_icon.py.
	local debugBtn, debugIcon
	local function applyDebugStyle()
		if not debugIcon then return end
		pcall(function()
			debugIcon:setImage(settings.debug
				and "ui/rlvcityoverlay/ladybug_on.tga"
				or  "ui/rlvcityoverlay/ladybug_off.tga", false)
		end)
	end

	local okBug = pcall(function()
		debugIcon = api.gui.comp.ImageView.new("ui/rlvcityoverlay/ladybug_off.tga")
		debugIcon:setStyleClassList({ "rlvDebugIcon" })
		debugBtn = api.gui.comp.Button.new(debugIcon, true)
		debugBtn:setStyleClassList({ "rlvDebugBtn" })
		debugBtn:setTooltip(_("debug_tooltip"))
		debugBtn:onClick(function()
			settings.debug = not settings.debug
			applyDebugStyle()
			-- Push it to the context that owns save().
			--
			-- Broadcast from the mutation itself, not from guiUpdate: the log
			-- showed guiUpdate runs somewhere this click never reaches, so it
			-- sent a stale debug=false and its signature guard then suppressed
			-- every send afterwards. Sending from the point of change guarantees
			-- the sender is the context that actually changed.
			broadcastSettings()
			-- Always print, whatever the new state: this is the one line that
			-- confirms the switch reached the script, and when turning logging
			-- OFF it is the last thing that will appear.
			emit("debug logging", settings.debug and "ENABLED" or "DISABLED")
		end)
		applyDebugStyle()
		-- Filler so the bug is pushed to the far end, opposite Close.
		local spacer = api.gui.comp.Component.new("rlvOptSpacer")
		spacer:setLayout(api.gui.layout.BoxLayout.new("HORIZONTAL"))
		cl:addItem(spacer, true, false)
		cl:addItem(debugBtn)
	end)
	if not okBug then
		warn("could not build debug toggle -- ladybug_off.tga missing?")
	end

	local closeWrap = api.gui.comp.Component.new(OPTION_ROW_NAME)
	closeWrap:setLayout(cl)
	layout:addItem(closeWrap)

	local panel = api.gui.comp.Component.new(OPTIONS_NAME)
	panel:setId(OPTIONS_ID)
	panel:setLayout(layout)
	return panel
end

local function openOptions()
	if optionsOpen() then return end

	local host = interactiveHost()
	if not host then
		warn("no interactive container -- cannot show options")
		return
	end

	-- No Rect: this layout positions by gravity/margin, set in the stylesheet.
	log("options opened: panel=", tostring(settings.panelEnabled),
		"closes=", tostring(settings.dismissMode),
		"townName=", tostring(settings.townName),
		"theme=", tostring(settings.theme))

	local ok, err = pcall(function()
		host:addItem(buildOptionsPanel())
	end)
	if not ok then warn("failed to show options:", tostring(err)) end
end

local function toggleOptions()
	if optionsOpen() then closeOptions(true) else openOptions() end
end

-- ---------------------------------------------------------------------------
-- input
-- ---------------------------------------------------------------------------

--- The world position under the cursor.
--
-- CONFIRMED FROM RUNTIME: gameUI:getTerrainPos() does NOT exist -- the first
-- build failed with "attempt to call method 'getTerrainPos' (a nil value)".
-- The name appears in the binary's string pool but is evidently bound
-- elsewhere, so we probe a list of candidates and remember the first that
-- works. If none do, we dump the real key sets and give up quietly.
local terrainPosFn = nil

local function findTerrainPos()
	if terrainPosFn then return terrainPosFn end

	local okUI, gameUI = pcall(api.gui.util.getGameUI)
	if not okUI then gameUI = nil end

	local candidates = {
		{ "gameUI:getTerrainPos",       function() return gameUI:getTerrainPos() end },
		{ "gameUI:getTerrainPosition",  function() return gameUI:getTerrainPosition() end },
		{ "gameUI:getMouseTerrainPos",  function() return gameUI:getMouseTerrainPos() end },
		{ "game.gui.getTerrainPos",     function() return game.gui.getTerrainPos() end },
		{ "game.gui.getMouseTerrainPos",function() return game.gui.getMouseTerrainPos() end },
		{ "api.gui.util.getTerrainPos", function() return api.gui.util.getTerrainPos() end },
	}

	for i = 1, #candidates do
		local name, fn = candidates[i][1], candidates[i][2]
		local ok, res = pcall(fn)
		if ok and res ~= nil then
			log("terrain position resolved via", name)
			terrainPosFn = fn
			return fn
		end
	end

	-- Nothing worked. Dump the real API surface once so the next build can
	-- use a fact instead of a guess.
	if settings.debug and not state.dumpedApi then
		state.dumpedApi = true
		log("no terrain-position call found; dumping API surface")
		dumpKeys("game.gui", game and game.gui)
		dumpKeys("api.gui.util", api and api.gui and api.gui.util)
		dumpKeys("gameUI", gameUI)
		dumpKeys("game.interface", game and game.interface)
	end
	return nil
end

local function handleRightClick()
	local fn = findTerrainPos()
	if not fn then return end

	local okPos, rawPos = pcall(fn)
	if not okPos or rawPos == nil then
		warn("terrain position call failed:", tostring(rawPos))
		return
	end

	local pos = toXYZ(rawPos)
	if not pos then
		describeShape("terrainPos", rawPos)
		return
	end

	local mouse = api.gui.util.getMouseScreenPos()
	local mx = mouse.x or mouse[1] or 0
	local my = mouse.y or mouse[2] or 0

	-- CYCLING.
	-- Because we cannot tell which label was clicked (see collectCandidates),
	-- right-clicking the same spot again steps to the next candidate rather
	-- than guessing harder. Town -> station -> industry, in ranked order, so
	-- the thing you actually meant is at most a click or two away.
	-- "Same spot" is a RADIUS around the previous click, not a grid cell.
	--
	-- This used to bucket the cursor with floor(mx / CYCLE_TOLERANCE), which
	-- reads like a tolerance but is not one: two clicks a single pixel apart
	-- land in different buckets whenever they straddle a cell boundary, so the
	-- cycle reset at random depending on where on the screen you happened to be
	-- clicking. Comparing distance to the anchor makes the tolerance mean what
	-- the constant says it means.
	local sameSpot = false
	if state.cycle and state.cycle.mx then
		local dx, dy = mx - state.cycle.mx, my - state.cycle.my
		sameSpot = (dx * dx + dy * dy) <= (CYCLE_TOLERANCE * CYCLE_TOLERANCE)
	end

	if sameSpot and #state.cycle.list > 0 then
		if #state.cycle.list == 1 then
			-- Only one thing here: behave as a plain open/close toggle.
			destroyPanel(true, "toggle")
			state.cycle = nil
			return
		end
		state.cycle.index = (state.cycle.index % #state.cycle.list) + 1
	else
		-- Anchor on the click that started the cycle, so the tolerance is
		-- measured from there rather than drifting one step per click.
		state.cycle = { mx = mx, my = my, list = collectCandidates(pos), index = 1 }
	end

	local pick = state.cycle.list[state.cycle.index]
	if not pick then
		destroyPanel(true, "nothing under cursor")
		state.cycle = nil
		return
	end

	local entityId, kind, entity = pick.id, pick.kind, pick.entity

	if kind == "INDUSTRY" then
		showIndustryPanel(entityId, entity, mx, my)
	elseif kind == "STATION" or kind == "DEPOT" then
		showEntityPanel(entityId, kind, entity, mx, my)
	else
		showPanel(entityId, mx, my)
	end
end

--- Make Escape close our panels.
--
-- Pattern copied from the shipped guide system (res/scripts/guidesystem.lua
-- around line 146), which does exactly this for its tip window:
--     w:setInputActionHandler("IA_ABORT", function() ... end, function() ... end)
-- The third argument is an enabled predicate -- returning false lets the action
-- fall through to whatever would normally handle it.
--
-- IA_CLOSE_TOPMOST_WINDOW is bound to Escape (and gamepad B) in the default
-- keybindings, and is semantically the right action: close the top thing.
--
-- The predicate only claims Escape when one of our panels is actually open, so
-- Escape still opens the in-game menu the rest of the time.
local function installEscapeHandler(comp, label)
	if not comp then return end
	local ok = pcall(function()
		comp:setInputActionHandler("IA_CLOSE_TOPMOST_WINDOW",
			function()
				if optionsOpen() then
					closeOptions(true)
				elseif state.shownFor then
					destroyPanel(true, "escape")
				end
			end,
			function()
				return optionsOpen() or (state.shownFor ~= nil)
			end)
	end)
	if not ok then
		warn("could not bind Escape on", tostring(label))
	else
		log("Escape handler bound on", tostring(label))
	end
end

--- Toolbar button that opens the options panel.
--
-- mainButtonsLayout is the game's own top bar; build-with-collision adds to
-- getItem(2), the right-hand group, so that is a proven attachment point.
-- Failure here is not fatal -- the panels still work, you just cannot reach
-- the options -- so it warns rather than erroring.
local function installToolbarButton()
	if api.gui.util.getById(TOOLBAR_BTN_ID) then return end

	local bar = api.gui.util.getById("mainButtonsLayout")
	if not bar then
		warn("mainButtonsLayout not found -- no options button")
		return
	end

	local ok, err = pcall(function()
		local group = bar:getItem(TOOLBAR_GROUP)
		if not group then error("toolbar group " .. TOOLBAR_GROUP .. " missing") end

		-- The whole button -- disc, ring and mouse glyph -- is baked into one
		-- RGBA texture by tools/make_toolbar_button.py. See TOOLBAR_ICON for
		-- why it cannot be assembled from the game's own art at runtime.
		-- Falls back to text if the texture cannot be loaded, rather than
		-- producing a blank button.
		local content
		local okIcon = pcall(function()
			local iv = api.gui.comp.ImageView.new(TOOLBAR_ICON)
			iv:setStyleClassList({ "rlvToolbarIcon" })
			content = iv
		end)
		if not okIcon or not content then
			content = api.gui.comp.TextView.new(_("RCD"))
		end

		local button = api.gui.comp.Button.new(content, true)
		button:setId(TOOLBAR_BTN_ID)
		button:setTooltip(_("Right Click Details options"))
		button:onClick(function() toggleOptions() end)

		local wrap = api.gui.comp.Component.new("rlvDetailsToolbarButton")
		local wl = api.gui.layout.BoxLayout.new("HORIZONTAL")
		wl:addItem(button)
		wrap:setLayout(wl)

		-- PLACE US BESIDE AN EXISTING BUTTON, found by id.
		--
		-- Not by group index: the anchor is not always in the same cluster.
		-- menu.bulldozer sits in the right-hand group while menu.contexthelper
		-- ("?") is over on the far left, so the container is discovered from the
		-- anchor rather than assumed.
		--
		-- Three API facts, each learned from a failed attempt:
		--   * getNumItems / getItem live on the component OR on its layout,
		--     depending on the container -- probe both, and enumerate through
		--     whichever answered (`enum`), never through `parent` directly.
		--   * insertItem lives on the layout for these containers, not behind
		--     getLayout on the component.
		--   * menu's layout -- the one holding the "?" -- reports getIndex,
		--     insertItem AND addItem all false. It can be read but accepts no
		--     children, so the "?" can never be an insertion point. It is left
		--     first in TOOLBAR_ANCHORS in case a patch ever changes that.
		local placed = false
		for _, anchorId in ipairs(TOOLBAR_ANCHORS) do
		if placed then break end
		local anchor = api.gui.util.getById(anchorId)
		log("PLACE: anchor", anchorId, "->", anchor and "found" or "NIL")

		if anchor then
			local okPlace, perr = pcall(function()
				local node = anchor
				for level = 1, 12 do
					local parent = node.getParent and node:getParent() or nil
					if not parent then break end

					local lay = parent.getLayout and parent:getLayout() or nil

					local enum = nil
					if parent.getNumItems and parent.getItem then
						enum = parent
					elseif lay and lay.getNumItems and lay.getItem then
						enum = lay
					end

					local inserter = parent.insertItem and parent or nil
					if not inserter and lay and lay.insertItem then
						inserter = lay
					end

					if enum and inserter then
						local n = enum:getNumItems()
						for i = 0, n - 1 do
							if enum:getItem(i) == node then
								local at = TOOLBAR_ANCHOR_AFTER and (i + 1) or i
								inserter:insertItem(wrap, at)
								placed = true
								log("PLACE: inserted at", at, "of", n,
									"at level", level)
								return
							end
						end
					end

					node = parent
				end
			end)
			if not okPlace then
				log("PLACE: errored:", tostring(perr))
			end
		end
		end  -- for over TOOLBAR_ANCHORS

		if not placed then
			-- Still usable, just at the end of the right-hand cluster.
			log("PLACE: no anchor worked; appending to group", TOOLBAR_GROUP)
			group:addItem(wrap)
		end
	end)

	if not ok then
		warn("could not add options button:", tostring(err))
	else
		log("options button installed")
	end
end

local function guiInit()
	-- Settings arrive through the shared `game` table, published by mod.lua's
	-- runFn. Game scripts cannot read mod params directly; this is the same
	-- mechanism the build-with-collision mod uses for game.bwC.
	local cfg = game and game.rlvCityOverlay

	-- Debug logging is opt-in from the mod options. Set before anything else
	-- so the messages below obey it.
	state.initCount = (state.initCount or 0) + 1
	seedSettingsFromParams(cfg)
	log("init #" .. state.initCount .. ": params", cfg and "visible" or "NOT VISIBLE",
		"| debug=", tostring(settings.debug),
		"| dismiss=", tostring(settings.dismissMode))

	if cfg then
		log("settings visible; panelEnabled=", tostring(cfg.panelEnabled),
			"debugLogging=", tostring(settings.debug))
	else
		log("settings unavailable in game script")
	end
	if not settings.panelEnabled then
		log("right-click panel disabled in settings")
	end

	local mainView = api.gui.util.getById("mainView")
	if not mainView then
		warn("mainView not found -- right-click panel unavailable")
		return
	end

	-- ONE-SHOT API SURVEY.
	-- The panel currently opens wherever the cursor was, because there is no
	-- confirmed way to convert the town's world position into a screen
	-- position -- and TownItem itself is engine-rendered, so its rect cannot
	-- be queried. Locking the panel under the label needs a world->screen
	-- projection. Dump the real API surface so we can find one (or rule it
	-- out) instead of guessing. Remove this block once resolved.
	if not state.dumpedApi then
		state.dumpedApi = true
		log("--- API survey: looking for a world->screen projection ---")
		dumpKeys("game.gui", game and game.gui)
		dumpKeys("api.gui.util", api and api.gui and api.gui.util)
		dumpKeys("mainView", mainView)
		local okUI, gameUI = pcall(api.gui.util.getGameUI)
		if okUI then dumpKeys("gameUI", gameUI) end
		local okCam, cam = pcall(function() return mainView:getCameraController() end)
		if okCam then dumpKeys("cameraController", cam) end

		-- LAST LEAD for locking the panel to the label.
		-- The survey found no world->screen projection anywhere, so the town's
		-- world position cannot be converted to a screen point. The one
		-- remaining possibility: the guide system calls
		-- game.gui.setHighlighted("townhudicon", true), so the engine DOES
		-- accept that name for town labels. If getContentRect accepts it too,
		-- it may hand back a screen rect we can anchor to.
		-- CONTAINER SURVEY -- for reparenting off toolTipContainer.
		--
		-- The panel currently lives in the engine's tooltip layer, which the
		-- engine clears as the cursor moves; that is the mouse-move vanish. We
		-- need another container whose layout takes addItem(comp, Rect), i.e.
		-- absolute positioning, and which the engine does not manage.
		--
		-- Walk mainView's layers and report what each one is. Nothing is
		-- attached here -- this only describes the tree.
		local okML, mainLayout = pcall(function() return mainView:getLayout() end)
		if okML and mainLayout then
			local okN, n = pcall(function() return mainLayout:getNumItems() end)
			log("mainView layers:", tostring(okN and n or "?"))
			for i = 0, (okN and n or 0) - 1 do
				local okI, item = pcall(function() return mainLayout:getItem(i) end)
				if okI and item then
					local nm  = select(2, pcall(function() return item:getName() end))
					local id  = select(2, pcall(function() return item:getId() end))
					local okL, lay = pcall(function() return item:getLayout() end)
					log("  layer", i, "name=", tostring(nm), "id=", tostring(id),
						"hasLayout=", tostring(okL and lay ~= nil))
					if okL and lay then
						dumpKeys("    layer" .. i .. ".layout", lay)
					end
				end
			end
		end

		-- For comparison: what IS toolTipContainer's layout, so we know what
		-- shape we are looking for elsewhere.
		local ttc = api.gui.util.getById("toolTipContainer")
		if ttc then
			local okT, ttl = pcall(function() return ttc:getLayout() end)
			if okT and ttl then dumpKeys("toolTipContainer.layout", ttl) end
		end

		local okRect, rect = pcall(game.gui.getContentRect, "townhudicon")
		log("getContentRect('townhudicon') ok=", tostring(okRect))
		if okRect then describeShape("townhudicon rect", rect) end

		log("--- end API survey ---")
	end

	mainView:insertMouseListener(function(evt)
		-- evt.type == 2, evt.button == 2 is the right-button press combination
		-- used by the build-with-collision mod. Deliberately never return true:
		-- consuming the event would break camera rotation.
		if evt.type == 2 and evt.button == MOUSE_RIGHT and settings.panelEnabled then
			local ok, err = pcall(handleRightClick)
			if not ok then warn("right-click handler error:", tostring(err)) end
		elseif evt.type == 2 and evt.button == MOUSE_LEFT then
			-- Click-off: LEFT button only.
			--
			-- Middle-click must NOT close the panel -- it is camera panning in
			-- TF2, so closing on it would fight normal navigation. Anything
			-- that is not an explicit left click is ignored.
			-- Sticky mode ignores click-off entirely: only another right-click
			-- on the same thing, or opening a different panel, closes it.
			if state.shownFor and settings.dismissMode ~= "sticky" then
				destroyPanel(true, "click-off")
			end
		elseif evt.type == 2 then
			-- Some other button. Log its number once so the mapping below can
			-- be confirmed rather than assumed.
			if not state.loggedButtons then
				state.loggedButtons = true
				log("non-left, non-right mouse button seen:", tostring(evt.button),
					"(ignored; left =", tostring(MOUSE_LEFT),
					"right =", tostring(MOUSE_RIGHT) .. ")")
			end
		end
		return false
	end)

	installToolbarButton()

	-- Escape closes whichever of our panels is open. Bound on mainView so it
	-- applies regardless of which container the panel lives in.
	installEscapeHandler(mainView, "mainView")

	log("right-click panel armed")
end

local function guiHandleEvent(id, name, param)
	if not state.shownFor then return end

	-- DELIBERATELY EMPTY.
	--
	-- This used to close the panel on mainView/select, on a construction-menu
	-- tab change, and on the bulldozer toggle. That made it vanish while the
	-- player was still reading it -- selecting anything in the world, or so
	-- much as opening a build menu, wiped it.
	--
	-- The panel now closes only on an explicit action: a left/middle click
	-- (handled in the mouse listener) or right-clicking the same thing again.
	-- If it still disappears on its own, destroyPanel logs the reason.
end
local function guiUpdate()
	-- DELIBERATELY NOT broadcasting settings here.
	--
	-- It was, and that made things worse. guiUpdate does not run in the context
	-- the options panel writes to: the log showed it sending debug=false while
	-- the toggle had just set true elsewhere, and the signature guard then
	-- suppressed every subsequent send. A frame hook in the wrong context also
	-- risks overwriting a good value with a stale one.
	--
	-- Broadcasts now happen at each point of change instead -- the ladybug and
	-- the four option setters -- so the sender is always the context that
	-- actually changed something.

	if not state.shownFor then return end
	if settings.dismissMode ~= "move" then return end

	local a = state.anchor
	if not a then return end

	local okM, mp = pcall(api.gui.util.getMouseScreenPos)
	if not okM or not mp then return end

	local mx = mp.x or mp[1]
	local my = mp.y or mp[2]
	if type(mx) ~= "number" or type(my) ~= "number" then return end

	local dx, dy = mx - a.x, my - a.y
	if (dx * dx + dy * dy) > (MOVE_DISMISS_PX * MOVE_DISMISS_PX) then
		destroyPanel(false, "mouse moved")
	end
end

function data()
	return {
		guiInit = guiInit,
		guiUpdate = guiUpdate,
		guiHandleEvent = guiHandleEvent,

		-- RECEIVE settings from the GUI context.
		--
		-- guiHandleEvent above is for GUI widget events; this is the separate
		-- script-event channel, and it is the only way one script instance can
		-- tell another that something changed. Without it the instance that runs
		-- save() never sees a setting the player toggled, and every choice is
		-- silently lost on reload -- which is the bug this fixes.
		--
		-- Guarded on the event id so we ignore everything else on the channel,
		-- and the values are re-normalised rather than trusted verbatim.
		handleEvent = function(src, id, name, param)
			if id ~= SETTINGS_EVENT or type(param) ~= "table" then return end

			if param.panelEnabled ~= nil then
				settings.panelEnabled = param.panelEnabled and true or false
			end
			if param.dismissMode ~= nil then settings.dismissMode = tostring(param.dismissMode) end
			if param.townName    ~= nil then settings.townName    = tostring(param.townName) end
			if param.theme       ~= nil then settings.theme       = tostring(param.theme) end
			if param.debug       ~= nil then settings.debug       = param.debug and true or false end

			-- A setting arriving from elsewhere counts as the player having
			-- spoken, so the param seed must not overwrite it later.
			settingsLoaded = true

			log("settings sync received: debug=", tostring(settings.debug),
				"panel=", tostring(settings.panelEnabled),
				"theme=", tostring(settings.theme))
		end,
		-- Persist the in-game settings. Additive only; if the mod is removed the
		-- table is simply orphaned, so severityRemove stays NONE.
		save = function()
			-- NOTE: save() is called very frequently -- hundreds of times a
			-- minute -- so nothing here may log unconditionally. A trace added
			-- during debugging produced 900+ lines in a single session.
			return {
				panelEnabled = settings.panelEnabled,
				dismissMode  = settings.dismissMode,
				townName     = settings.townName,
				theme        = settings.theme,
				debug        = settings.debug,
				-- The mod params AS THEY WERE when this save was written. load()
				-- diffs against them to tell "the player changed a param" from
				-- "the player changed the in-game panel". Without it the two are
				-- indistinguishable and params silently do nothing -- see load.
				params = paramValues(),
			}
		end,

		-- load() APPLIES ONCE.
		--
		-- TF2 calls a game script's load() to restore state, and it is not a
		-- one-off at savegame load -- it is also used to sync state, so it
		-- fires repeatedly during play. Applying it every time meant each call
		-- overwrote the settings table with the last SAVED values, silently
		-- reverting anything changed in the options panel.
		--
		-- That is exactly the observed symptom: "setting: Town name -> always"
		-- fired four times, and each click started from "auto" again, because
		-- something restored the old value in between. guiInit ran only once,
		-- so re-seeding was not the culprit.
		--
		-- Saved values are the starting point; after that the panel owns them.
		load = function(data)
			state.loadCount = (state.loadCount or 0) + 1
			if state.loadCount <= 3 then
				log("load #" .. state.loadCount .. ": applied=",
					tostring(not state.loadApplied),
					"townName=", tostring(data and data.townName))
			end

			if state.loadApplied then return end
			state.loadApplied = true

			if type(data) ~= "table" then return end

			-- Tell seedSettingsFromParams to stand down: whatever is in this
			-- save wins over the menu defaults. load() runs BEFORE guiInit, so
			-- without this the seed silently undoes everything below.
			settingsLoaded = true

			-- Panel-only settings: no param can conflict, so the save always wins.
			if data.townName ~= nil then settings.townName = data.townName end
			if data.theme    ~= nil then settings.theme    = data.theme end

			-- PARAM-BACKED SETTINGS need a three-way merge.
			--
			-- These used to be applied straight from the save, which made the
			-- mod-settings screen do NOTHING on any save that had ever been
			-- written -- silently, for every param, not just debug. The saved
			-- value always overwrote whatever seedSettingsFromParams had put
			-- there, and there was no way to tell the two apart.
			--
			-- Diffing against the params recorded at save time separates them:
			-- a param that has changed since then is a deliberate act by the
			-- player and wins; a param that has not defers to the in-game panel.
			--
			-- No migration when `params` is absent. An earlier version let the
			-- param win on saves predating the snapshot, which discarded the
			-- player's in-panel choices on first load and turned debug logging
			-- off on a save where it had been switched on.
			local cur, snap = paramValues(), data.params

			local function resolve(key)
				if cur and snap and cur[key] ~= snap[key] then
					log("param", key, "changed:", tostring(snap[key]),
						"->", tostring(cur[key]), "-- param wins")
					return cur[key]
				end
				return data[key]
			end

			local pe = resolve("panelEnabled")
			local dm = resolve("dismissMode")
			local db = resolve("debug")
			if pe ~= nil then settings.panelEnabled = pe and true or false end
			if dm ~= nil then settings.dismissMode  = tostring(dm) end
			if db ~= nil then settings.debug        = db and true or false end

			log("settings restored: debug=", tostring(settings.debug),
				"panel=", tostring(settings.panelEnabled),
				"theme=", tostring(settings.theme),
				"| snapshot=", tostring(snap ~= nil),
				"params=", tostring(cur ~= nil))
		end,
	}
end
