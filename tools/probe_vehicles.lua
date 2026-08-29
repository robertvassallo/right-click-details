--
-- probe_vehicles.lua -- PARKED DIAGNOSTIC, not shipped.
--
-- Lifted out of res/config/game_script/rlv_cityoverlay.lua before v1.8. It ran
-- once per session behind the debug setting and answered what a VEHICLE
-- exposes, which unblocked three roadmap items at once. Every finding is
-- written up under "Vehicles" in API-NOTES.md.
--
-- Headline results, so this need not be re-run to recall them:
--   * transportVehicleSystem owns vehicles; getLineVehicles WORKS (it had been
--     looked for on lineSystem, which has no such function)
--   * getEntity(vehicleId) returns 14 keys including line, stopIndex, state,
--     cargoLoad, capacities and allCapacities
--   * capacities is what a vehicle is CONFIGURED to carry and is what the
--     carrier attribution now uses
--   * getDepotVehicles is the only route to a useful depot panel
--
-- Paste it back beside cargoLineMap and call it from showEntityPanel.
-- Depends on: log, toTable, describeShape, settings, state (from the mod).
--

--- TEMPORARY DIAGNOSTIC -- must not ship. See "Before release" in PLAN.md.
--
-- Answers the one question three roadmap items are all blocked on: what can we
-- learn about a VEHICLE?
--
--   D  right-click a vehicle -- needs its line, next stop and current cargo
--   E  the carrier set -- needs what a line's vehicles are CONFIGURED to carry,
--      which does not change when a train happens to be running empty
--   E0 the depot panel -- a depot entity is two strings, so the only useful
--      content is which vehicles are stabled in it
--
-- BUILT TO THE RULES THIS MOD LEARNED THE HARD WAY:
--   * every walk is capped -- the last probe did ~1600 getEntity calls a click
--   * counts go through countKeys, never `#`, on anything that may be a map
--   * ids are resolved BEFORE type-checking; getSimCargosForLine returns ids,
--     and a `type(x) == "table"` guard on those reported a confident zero
--   * pcall errors are LOGGED, never discarded -- a swallowed error is what
--     hid the broken settings broadcast for three releases
local PROBE_ITEMS = 6

local function countKeys(t)
	if type(t) ~= "table" then return -1 end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

--- Try a call, log what came back OR why it failed. Returns the value or nil.
local function probeCall(label, fn)
	local ok, res = pcall(fn)
	if not ok then
		log("  ", label, "FAILED:", tostring(res))
		return nil
	end
	local t = toTable(res)
	log("  ", label, "ok raw=", type(res),
		"arrayN=", t and tostring(#t) or "nil",
		"keys=", tostring(countKeys(t)))
	return t, res
end

local function probeVehicles(stationId, entity, lines)
	if not settings.debug or state.probedVehicles then return end

	local sys = api and api.engine and api.engine.system
	if not sys then log("VEHICLE PROBE: no api.engine.system"); return end

	log("=========== VEHICLE PROBE ===========")

	-- 1. WHICH SYSTEM OWNS VEHICLES? lineSystem does NOT expose getLineVehicles
	--    on this build -- its key dump is getLineStops/getLineStopsForStation/
	--    getLineStopsForTerminal/getLines/getLinesForPlayer/getLinesForWaypoint/
	--    getProblemLines/getStationGroup2LineStopsMap/getTerminal2lineStops.
	--    That is why "getLineVehicles yields nothing usable" -- it was never
	--    there to begin with. So find the system that does have it.
	for name, tbl in pairs(sys) do
		if type(tbl) == "table" and tostring(name):lower():find("vehicle") then
			local fns = {}
			pcall(function()
				for k in pairs(tbl) do fns[#fns + 1] = tostring(k) end
			end)
			table.sort(fns)
			log("system", tostring(name), "=", table.concat(fns, " "))
		end
	end

	-- 2. GET A VEHICLE ID, by whatever route works. Each is named so a failure
	--    is attributable rather than "vehicles are unavailable".
	local vid
	local tvs = sys.transportVehicleSystem

	if tvs and lines and lines[1] then
		for i = 1, math.min(#lines, PROBE_ITEMS) do
			if tvs.getLineVehicles then
				local t = probeCall("transportVehicleSystem.getLineVehicles(" ..
					tostring(lines[i].name) .. ")",
					function() return tvs.getLineVehicles(lines[i].id) end)
				if t and t[1] then vid = t[1]; break end
			end
		end
	end

	if not vid and entity and entity.position then
		-- The route item D actually needs: can a click FIND a vehicle at all?
		local t = probeCall("getEntities{type=VEHICLE} r=200 at station",
			function()
				return game.interface.getEntities(
					{ pos = { entity.position[1], entity.position[2] }, radius = 200 },
					{ type = "VEHICLE" })
			end)
		if t and t[1] then vid = t[1] end
	end

	if not vid then
		log("  no vehicle id from any route -- nothing further to probe")
		log("=========== VEHICLE PROBE END ===========")
		state.probedVehicles = true
		return
	end

	-- 3. WHAT DOES THE VEHICLE CARRY? getEntity first, the friendly view.
	log("  probing vehicle id", tostring(vid))
	local okE, ve = pcall(game.interface.getEntity, vid)
	if okE and type(ve) == "table" then
		describeShape("getEntity(vehicle)", ve, 3)
	else
		log("  getEntity(vehicle) FAILED:", tostring(ve))
	end

	-- 4. THE COMPONENT SIDE. api.type lists TransportVehicle,
	--    TransportVehicleConfig, VehicleCargoInfo, TransportVehicleInfo and
	--    VehicleInfo -- the config ones are what item E needs, because a
	--    CONFIGURED capacity is stable while an actual load is not.
	local ct = api and api.type and api.type.ComponentType
	if ct then
		for _, cname in ipairs({ "TRANSPORT_VEHICLE", "VEHICLE", "COLOR" }) do
			if ct[cname] then
				local okC, comp = pcall(api.engine.getComponent, vid, ct[cname])
				log("  component", cname, "ok=", tostring(okC), "type=", type(comp))
				if okC and comp then
					-- Engine components come back as USERDATA whose __index is a
					-- function, so toTable cannot walk them. Ask for names.
					for _, f in ipairs({ "line", "lineStop0", "lineStop1", "state",
							"cargoTypes", "capacities", "config", "userStopped",
							"depot", "name", "doorsTime", "adjustedCapacities" }) do
						local okF, v = pcall(function() return comp[f] end)
						if okF and v ~= nil then
							log("    ." .. f, "=", tostring(v), "[" .. type(v) .. "]")
						end
					end
				end
			end
		end
	end

	log("=========== VEHICLE PROBE END ===========")
	state.probedVehicles = true
end
