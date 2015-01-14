
local SectClient = pd.Class:new():register("sect-midi-client-lua")

function SectClient:initialize(sel, atoms)

	-- 1. Incoming MIDI-over-UDP commands from Sect
	-- 2. Incoming MIDI from user devices {cmd name, byte1, ... byte n}
	-- 3. Metronome ticks
	self.inlets = 3

	-- 1. Outgoing MIDI-over-UDP commands for Sect
	-- 2. Outgoing MIDI to user devices
	-- 3. Metronome timing value
	self.outlets = 3

	self.order = { -- Order in which the bytes of command-types FROM user devices should be sent TO Sect
		note = {3, 1, 2},
		key_after_touch = {1, 2},
		control_change = {3, 2, 1},
		patch_change = {2, 1},
		channel_after_touch = {3, 1, 2},
		pitch_wheel_change = {2, 1},
	}

	self.sus = {} -- Holds all sustain data for commands FROM Sect TO user devices

	-- Populate the sustain-data table
	for i = 0, 15 do
		self.sus[i] = {}
	end

	return true

end

-- On program-quit, send NOTE-OFFs for all active sustains
function SectClient:finalize()

	for i = 0, 15 do
		for k, _ in pairs(self.sus[i]) do
			self:outlet(2, "list", {"note", k, 0, i})
		end
	end

end

-- Get incoming MIDI-over-UDP commands from Sect, and send them to user devices
function SectClient:in_1_list(list)

	-- Convert incoming ASCII values into the table of commands they represent
	local conv = ""
	local t = {}
	for _, v in ipairs(list) do
		conv = conv .. string.char(v)
	end
	for unit in string.gmatch(conv, "%S+") do
		t[#t + 1] = ((#t == 2) and unit) or tonumber(unit)
	end

	pd.post("FROM SECT: " .. table.concat(t, " ") .. " (raw: " .. table.concat(list, " ") .. ")") -- debugging

	-- Get BPM and TPQ values, leaving note values in table form
	local bpm = table.remove(t, 1)
	local tpq = table.remove(t, 1)

	-- Seperate command-name from command-bytes
	local cmd = table.remove(t, 1)

	-- Get command's tick-position and channel
	local tick = table.remove(t, 1)

	-- If note, get duration, or default to 0
	local dur = 0
	if cmd == "note" then
		dur = table.remove(t, 1)
	end

	-- Update timing of external [metro] command, to trigger once every tick, at current BPM/TPQ values
	local ms = 60000 / (bpm * tpq * 4)
	self:outlet(3, "float", {ms})

	-- Format outgoing MIDI command for Pd's weird MIDI-send style
	local out = {}
	for k, v in ipairs(self.order[cmd]) do
		out[v] = t[k]
	end

	-- Send MIDI command to external MIDI device
	self:outlet(2, cmd, out)

	-- Record the note, and its duration, in the sustain-tracking table
	if cmd == "note" then
		self.sus[t[1]][t[2]] = self.sus[t[1]][t[2]] or {sust = 0, count = 0}
		self.sus[t[1]][t[2]].sust = dur
		self.sus[t[1]][t[2]].count = self.sus[t[1]][t[2]].count + 1
	end

end

-- Get incoming MIDI commands from user devices, and send them to Sect
function SectClient:in_2(sel, t)

	-- Serialize the MIDI-command information into a string, with the values reordered in Sect format
	local otab = {}
	local str = sel .. (((sel == 'note') and (" 0 0")) or " 0")
	for k, v in ipairs(self.order[sel]) do
		str = str .. " " .. t[v]
	end

	-- Convert the serialized comment into ASCII bytes, for UDP transfer
	local conv = {}
	for i = 1, str:len() do
		conv[i] = str:byte(i)
	end

	pd.post("TO SECT: " .. str .. " (raw: " .. table.concat(conv, " ") .. ")")

	-- Send the note to the [udpsend] apparatus
	self:outlet(1, "send", conv)

end


-- React to incoming metronome ticks
function SectClient:in_3_bang()

	-- Send automatic noteoffs for Sect-to-user-device notes whose durations have expired
	for chan, notes in pairs(self.sus) do
		for note, tab in pairs(notes) do

			local dur = tab.sust
		
			-- Decrease the sustain's duration value
			self.sus[chan][note].sust = dur - 1
		
			-- If the duration has expired, send a note-off for the note, and unset its table value
			if self.sus[chan][note].sust <= 1 then
				for i = 1, self.sus[chan][note].count do
					self:outlet(2, "note", {note, 0, chan})
				end
				self.sus[chan][note] = nil
			end
			
		end
	end

end
