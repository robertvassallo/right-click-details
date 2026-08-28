--
-- probe_terminal_pax.lua -- PARKED DIAGNOSTIC, not shipped.
--
-- Lifted out of res/config/game_script/rlv_cityoverlay.lua in v1.7. It ran once
-- per session behind the debug setting and answered, conclusively, whether
-- per-stop attribution is reachable for passengers or waiting freight. It is
-- not: see "Per-station attribution" in API-NOTES.md for every finding.
--
-- Kept because the answer is a fact about a specific build of the game. If a
-- patch ever adds simCargoAtTerminalSystem's missing input, or puts a
-- TRANSPORT_NETWORK component on stations, this is the instrument that will say
-- so. Paste it back beside cargoLineMap and call it from showEntityPanel.
--
-- BEFORE REUSING: the two cargo walks in section 6 are UNCAPPED -- one
-- game.interface.getEntity per item, twice over, on lines the probe itself
-- measured at 436 items. Every other cargo path in the mod caps at
-- MAX_CARGO_SAMPLES. Cap these too before running it on a busy save.
--
-- Depends on: log, toTable, describeShape, settings, state (from the mod).
--

--- Count a KEY-VALUE map. Never use `#` for this.
--
-- `#` on a keyed map reads 0 regardless of contents. Measuring
-- getSimPersonsAtTerminalForTransportNetwork that way is precisely what
-- produced this mod's original (wrong) conclusion that the call "returns
-- nothing" -- see probeTerminalPax.
local function countKeys(t)
	if type(t) ~= "table" then return -1 end
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

--- ONE-SHOT PROBE: is per-stop passenger attribution actually reachable?
--
-- Runs once per session, debug only, from a real station right-click so the
-- station context is genuine rather than synthesised.
--
-- WHY THIS EXISTS. The panel currently tells players that per-stop passenger
-- counts are impossible, and the comment at the call site calls six routes
-- dead. At least two of those were MEASUREMENT ERRORS, not missing APIs:
--
--   1. getSimPersonsAtTerminalForTransportNetwork was measured with `#conv`.
--      That is meaningless on a key-value map and always reads 0. The result
--      was reported as "the call returns nothing".
--   2. A station id was passed where a TRANSPORT NETWORK entity was wanted,
--      and the resulting failure was read as the API being unavailable.
--
-- So: every count here goes through countKeys, never `#`, and every candidate
-- id is tried and NAMED in the log rather than assumed. If the call works for
-- any id, the shipped "not exposed" claim has to be retracted.
local function probeTerminalPax(stationId, entity, lines)
	if not settings.debug then return end

	-- TWO INDEPENDENT FLAGS, not one.
	--
	-- The first run landed on a freight station: getSimPersonsForLine returned
	-- nothing, so the SIM_PERSON dump never fired -- yet a single shared flag
	-- had already marked the probe done, costing a whole game session. Each
	-- half now retires only when it actually produced its data.
	local wantPax   = not state.probedPax
	local wantCargo = not state.probedCargo
	if not (wantPax or wantCargo) then return end

	local sys = api and api.engine and api.engine.system
	if not sys then log("PROBE: no api.engine.system"); return end
	local ct = api and api.type and api.type.ComponentType

	log("=========== TERMINAL PAX PROBE ===========")
	log("station group id:", tostring(stationId))

	-- Candidate ids: the group and each member station. The group/member
	-- distinction already mattered in stationLines, so try both here too.
	local ids = { stationId }
	local mem = entity and toTable(entity.stations)
	if mem then
		for _, m in pairs(mem) do
			if type(m) == "number" then ids[#ids + 1] = m end
		end
	end
	local idStr = ""
	for i = 1, #ids do idStr = idStr .. (i > 1 and ", " or "") .. tostring(ids[i]) end
	log("candidate station ids:", idStr)

	-- 1. Does any candidate carry a TRANSPORT_NETWORK component? This is the
	--    entity the terminal calls actually want.
	if ct and ct.TRANSPORT_NETWORK then
		for _, id in ipairs(ids) do
			local okC, comp = pcall(api.engine.getComponent, id, ct.TRANSPORT_NETWORK)
			log("  TRANSPORT_NETWORK on", tostring(id),
				"ok=", tostring(okC), "type=", type(comp))
			if okC and comp then
				describeShape("tn@" .. tostring(id), toTable(comp) or comp, 2)
			end
		end
	else
		log("  ComponentType.TRANSPORT_NETWORK not present")
	end

	-- 2. What does simPersonAtTerminalSystem actually offer? An earlier pass
	--    reported "only 3 unrelated fns" -- worth re-reading rather than
	--    trusting.
	local spat = sys.simPersonAtTerminalSystem
	log("simPersonAtTerminalSystem present:", tostring(spat ~= nil))
	if spat then
		local names = {}
		pcall(function() for k in pairs(spat) do names[#names + 1] = tostring(k) end end)
		table.sort(names)
		local fnStr = ""
		for i = 1, #names do fnStr = fnStr .. (i > 1 and ", " or "") .. names[i] end
		log("  functions:", fnStr)

		if spat.getEdgeInfoMap then
			local okE, raw = pcall(spat.getEdgeInfoMap)
			local m = okE and toTable(raw) or nil
			log("  getEdgeInfoMap ok=", tostring(okE), "keys=", tostring(countKeys(m)))
			if m then
				local shown = 0
				for k, v in pairs(m) do
					shown = shown + 1
					if shown > 2 then break end
					log("    edge", tostring(k), "->", type(v))
					describeShape("edgeInfo", toTable(v) or v, 2)
				end
			end
		end
	end

	-- 3. THE CALL ITSELF, against every id we can name. Counted with pairs.
	local sps = sys.simPersonSystem
	if sps and sps.getSimPersonsAtTerminalForTransportNetwork then
		for _, id in ipairs(ids) do
			local okP, raw = pcall(function()
				return sps.getSimPersonsAtTerminalForTransportNetwork(id)
			end)
			local t = okP and toTable(raw) or nil
			log("  getSimPersonsAtTerminalForTN(", tostring(id), ") ok=", tostring(okP),
				"raw=", type(raw), "keys=", tostring(countKeys(t)))
		end
	else
		log("  getSimPersonsAtTerminalForTransportNetwork MISSING")
	end

	-- 4. stationSystem maps that bridge person edges back to terminals.
	local ss = sys.stationSystem
	if ss and ss.getPersonNodeId2StationTerminalsMap then
		local okM, raw = pcall(ss.getPersonNodeId2StationTerminalsMap)
		local m = okM and toTable(raw) or nil
		log("  getPersonNodeId2StationTerminalsMap ok=", tostring(okM),
			"keys=", tostring(countKeys(m)))
		if m then
			local shown = 0
			for k, v in pairs(m) do
				shown = shown + 1
				if shown > 2 then break end
				log("    node", tostring(k), "->", type(v))
				describeShape("terminals", toTable(v) or v, 2)
			end
		end
	end

	-- 5. What fields does a SIM_PERSON carry? This decides whether filtering by
	--    NEXT LEG is possible, which is what the transfer-bias caveat needs.
	if wantPax and lines and sps and sps.getSimPersonsForLine and ct and ct.SIM_PERSON then
		-- Walk every line, not just the first: line 1 of a mixed station may
		-- carry freight while line 3 carries the people.
		for i = 1, #lines do
			local okL, people = pcall(function()
				return sps.getSimPersonsForLine(lines[i].id)
			end)
			local pids = okL and toTable(people) or nil
			if pids and pids[1] then
				log("  line", tostring(lines[i].name), "has", tostring(#pids), "persons")
				-- A person id may itself need resolving, same as cargo.
				local okE, pent = pcall(game.interface.getEntity, pids[1])
				if okE and type(pent) == "table" then
					describeShape("getEntity(person)", pent, 3)
				end

				local okC, comp = pcall(api.engine.getComponent, pids[1], ct.SIM_PERSON)
				log("  SIM_PERSON", tostring(pids[1]), "ok=", tostring(okC), "type=", type(comp))
				if okC and comp then
					-- SIM_PERSON came back as USERDATA that toTable could not
					-- iterate. Field access still works on these (the engine's
					-- __index is a function), so ask for names directly rather
					-- than concluding "no fields".
					local names = {
						"sourceEntity", "targetEntity", "targetOrAtEntity",
						"atTerminal", "terminal", "stationGroup", "station",
						"line", "currentLine", "nextLine", "nextLeg",
						"destinations", "journey", "route", "itinerary",
						"state", "position", "arrivalTime", "departureTime",
					}
					local found = 0
					for _, nm in ipairs(names) do
						local okF, v = pcall(function() return comp[nm] end)
						if okF and v ~= nil then
							found = found + 1
							log("    ." .. nm, "=", tostring(v), "[" .. type(v) .. "]")
						end
					end
					log("    fields found:", tostring(found), "of", tostring(#names))
					if found > 0 then state.probedPax = true end
				end
				-- WHERE ARE THESE PEOPLE, really?
				--
				-- getEntity(person) decodes to a full itinerary:
				--   destinations = { 32289, 76145, 28612 }   -- legs
				--   moveModes    = { 0, 2, 2 }               -- mode per leg
				--   targetOrAtEntity = 76145                 -- == destinations[2]
				--
				-- So targetOrAtEntity is the CURRENT LEG's target, and its index
				-- in destinations says how far along the journey the person is.
				-- An earlier pass dismissed this field because its values were
				-- all CONSTRUCTIONs -- but a station EXISTS as a construction
				-- alongside its station group, so "all CONSTRUCTION" may mean
				-- "all stations" rather than "not stations".
				--
				-- Tally the values. If people waiting at this stop share one,
				-- it will show up as a cluster rather than a spread.
				local tally, legs = {}, {}
				local walked = 0
				for k = 1, math.min(#pids, 200) do
					local okP, pe = pcall(game.interface.getEntity, pids[k])
					if okP and type(pe) == "table" then
						walked = walked + 1
						local t = pe.targetOrAtEntity
						if t ~= nil then tally[t] = (tally[t] or 0) + 1 end
						-- Which leg are they on?
						local ds = toTable(pe.destinations)
						if ds and t ~= nil then
							for di = 1, #ds do
								if ds[di] == t then
									legs[di] = (legs[di] or 0) + 1
									break
								end
							end
						end
					end
				end

				log("    walked", tostring(walked), "persons on this line")
				local order = {}
				for k, v in pairs(tally) do order[#order + 1] = { id = k, n = v } end
				table.sort(order, function(a, b) return a.n > b.n end)
				for k = 1, math.min(#order, 8) do
					local isHere = false
					for _, sid in ipairs(ids) do
						if order[k].id == sid then isHere = true end
					end
					log("      targetOrAtEntity", tostring(order[k].id),
						"count=", tostring(order[k].n),
						"isThisStation=", tostring(isHere))
				end
				log("    distinct targets:", tostring(#order))
				local legStr = ""
				for di = 1, 6 do
					if legs[di] then legStr = legStr .. "leg" .. di .. "=" .. legs[di] .. " " end
				end
				log("    leg distribution:", legStr)

				break
			end
		end
	end

	-- 6. WHAT DOES sourceEntity ACTUALLY MEAN?
	--
	-- lineCargo filters waiting freight with here[it.sourceEntity], commented
	-- as "where the item is waiting". The first sample contradicts that: it had
	-- vehicleUsed = true (so it is ON a vehicle) and a sourceEntity that is
	-- neither this station nor its member. If sourceEntity is the ORIGIN rather
	-- than the current location, the per-line freight rows are counting the
	-- wrong set -- which fits the reported line attribution being close but
	-- wrong.
	--
	-- Dump a spread of items with the station ids alongside, so the answer is
	-- readable rather than inferred from one sample.
	local scs = sys.simCargoSystem
	if wantCargo and lines and scs and scs.getSimCargosForLine then
		for i = 1, #lines do
			local okC, cargos = pcall(function()
				return scs.getSimCargosForLine(lines[i].id)
			end)
			local items = okC and toTable(cargos) or nil
			if items and items[1] then
				log("  CARGO SEMANTICS on line", tostring(lines[i].name),
					"-- station ids are", idStr)
				local shown, onVeh, srcHere, resolved = 0, 0, 0, 0
				for k = 1, #items do
					-- getSimCargosForLine returns ENTITY IDS, not item tables.
					-- The previous guard (`type(it) == "table"`) was therefore
					-- false for every item, so this loop counted nothing and
					-- reported a confident 0/0. Resolve the id first.
					local it = items[k]
					if type(it) == "number" then
						local okE, ent = pcall(game.interface.getEntity, it)
						it = okE and ent or nil
					end
					if type(it) == "table" then
						resolved = resolved + 1
						local isHere = false
						for _, sid in ipairs(ids) do
							if it.sourceEntity == sid then isHere = true end
						end
						if it.vehicleUsed then onVeh = onVeh + 1 end
						if isHere then srcHere = srcHere + 1 end
						if shown < 8 then
							shown = shown + 1
							log("    item", tostring(k),
								"src=", tostring(it.sourceEntity),
								"tgt=", tostring(it.targetEntity),
								"onVehicle=", tostring(it.vehicleUsed),
								"srcIsThisStation=", tostring(isHere),
								"cargo=", tostring(it.cargoType))
						end
					end
				end
				log("    TOTALS: items=", tostring(#items),
					"resolved=", tostring(resolved),
					"onVehicle=", tostring(onVeh),
					"srcIsThisStation=", tostring(srcHere))

				-- The first decode showed 436 of 436 items onVehicle=true, so
				-- getSimCargosForLine may only ever return cargo IN TRANSIT --
				-- in which case it can never answer "what is waiting HERE".
				-- Dump the not-on-vehicle items specifically to find out.
				local waitShown = 0
				for k = 1, #items do
					local id = items[k]
					local okE, it = pcall(game.interface.getEntity, id)
					if okE and type(it) == "table" and not it.vehicleUsed then
						waitShown = waitShown + 1
						if waitShown <= 8 then
							log("      WAITING item src=", tostring(it.sourceEntity),
								"tgt=", tostring(it.targetEntity),
								"cargo=", tostring(it.cargoType))
						end
					end
				end
				log("    not-on-vehicle (waiting) items:", tostring(waitShown))
				if resolved == 0 then
					log("    !! resolved 0 of", tostring(#items),
						"-- ids did not decode; treat totals as MEANINGLESS")
				end
				state.probedCargo = true
				break
			end
		end
	end

	log("=========== PROBE END ===========")
end
